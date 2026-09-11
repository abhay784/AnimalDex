#!/usr/bin/env python3
"""Create deterministic, observation-grouped dataset splits and class metadata."""
from __future__ import annotations

import argparse
import hashlib
import json
import random
from collections import Counter, defaultdict
from pathlib import Path

from PIL import Image, UnidentifiedImageError

try:
    from .labels import NEGATIVE_LABEL, ROOT, model_labels
except ImportError:  # `python ml/make_splits.py`
    from labels import NEGATIVE_LABEL, ROOT, model_labels

DATA = ROOT / "ml" / "data"
MANIFEST = DATA / "inat_manifest.jsonl"
EXTERNAL_NEGATIVE_MANIFEST = DATA / "external_negative_manifest.jsonl"
SPLITS = DATA / "splits"


def read_manifest() -> list[dict]:
    rows: list[dict] = []
    if MANIFEST.exists():
        rows.extend(json.loads(line) for line in MANIFEST.read_text().splitlines() if line.strip())
    if EXTERNAL_NEGATIVE_MANIFEST.exists():
        rows.extend(
            json.loads(line)
            for line in EXTERNAL_NEGATIVE_MANIFEST.read_text().splitlines()
            if line.strip()
        )
    recorded_paths = {row["path"] for row in rows}

    # Curated negatives are intentionally local. They must be documented before
    # a production release, but this permits safe iteration without scraping
    # third-party images whose license cannot be recorded by the downloader.
    negative_dir = DATA / "raw" / NEGATIVE_LABEL
    negative_images = sorted(negative_dir.glob("**/*")) if negative_dir.exists() else []
    for image in negative_images:
        if image.suffix.lower() in {".jpg", ".jpeg", ".png", ".heic", ".webp"}:
            relative_path = image.relative_to(ROOT).as_posix()
            # iNaturalist negatives already carry full provenance in the
            # manifest. Only add genuinely local negatives here; otherwise the
            # exact same image appears twice under two group IDs and leaks
            # across train/validation/test.
            if relative_path in recorded_paths:
                continue
            rows.append({
                "path": relative_path,
                "label": NEGATIVE_LABEL,
                "source": "curated_local",
                "observation_id": f"negative:{image.stem}",
            })
    return rows


def assign_groups(rows: list[dict], seed: int) -> dict[str, list[dict]]:
    by_label: dict[str, dict[str, list[dict]]] = defaultdict(lambda: defaultdict(list))
    for row in rows:
        path = ROOT / row["path"]
        if not path.exists():
            continue
        by_label[row["label"]][str(row["observation_id"])].append(row)

    splits = {"train": [], "validation": [], "test": []}
    for label, groups in by_label.items():
        group_rows = list(groups.values())
        random.Random(f"{seed}:{label}").shuffle(group_rows)
        group_count = len(group_rows)
        if group_count < 3:
            raise ValueError(f"{label} has only {group_count} distinct observations; need at least 3")
        validation_count = max(1, round(group_count * 0.15))
        test_count = max(1, round(group_count * 0.15))
        # Preserve at least one observation for training for small classes.
        while validation_count + test_count >= group_count:
            if validation_count > test_count:
                validation_count -= 1
            else:
                test_count -= 1
        for index, group in enumerate(group_rows):
            target = "validation" if index < validation_count else "test" if index < validation_count + test_count else "train"
            splits[target].extend(group)
    return splits


def filter_readable_images(rows: list[dict]) -> tuple[list[dict], list[str]]:
    """Exclude missing or corrupt assets before they can crash a training epoch.

    Downloaded files can have a valid image extension and even a JPEG header
    while still ending mid-stream. ``Image.load`` forces Pillow to decode each
    asset so such files are removed during split creation, rather than hours
    into an MPS training run.
    """
    valid: list[dict] = []
    rejected: list[str] = []
    for row in rows:
        path = ROOT / row["path"]
        try:
            with Image.open(path) as image:
                image.load()
        except (FileNotFoundError, OSError, UnidentifiedImageError) as error:
            rejected.append(f"{row['path']}: {error}")
            continue
        valid.append(row)
    return valid, rejected


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=20260909)
    parser.add_argument("--minimum-per-class", type=int, default=30)
    parser.add_argument(
        "--exclude-underfilled",
        action="store_true",
        help="omit classes below --minimum-per-class from this model instead of failing",
    )
    parser.add_argument(
        "--verify-images",
        action="store_true",
        help="fully decode every asset before splitting; use as a slower corpus-integrity check",
    )
    args = parser.parse_args()

    rows = read_manifest()
    rejected_images: list[str] = []
    if args.verify_images:
        rows, rejected_images = filter_readable_images(rows)
    else:
        # The normal split path stays fast for large local corpora. Missing
        # images (including files moved to the quarantine directory) are
        # excluded deterministically; --verify-images is available for a full
        # decode of every remaining asset before a release.
        rows = [row for row in rows if (ROOT / row["path"]).exists()]
    for rejected in rejected_images:
        print(f"excluding unreadable image: {rejected}")
    catalog_model_labels = model_labels()
    counts = Counter(row["label"] for row in rows if (ROOT / row["path"]).exists())
    unknown = set(counts) - set(catalog_model_labels)
    if unknown:
        raise ValueError(f"manifest contains labels outside the model contract: {sorted(unknown)}")
    missing = [label for label in catalog_model_labels if counts[label] < args.minimum_per_class]
    if missing:
        details = ", ".join(f"{label}={counts[label]}" for label in missing[:12])
        if not args.exclude_underfilled:
            raise ValueError(
                f"need at least {args.minimum_per_class} images for each of {len(missing)} classes; {details}"
            )
        print(f"excluding {len(missing)} underfilled model classes: {details}")
    labels = [label for label in catalog_model_labels if label not in set(missing)]
    rows = [row for row in rows if row["label"] in set(labels)]

    splits = assign_groups(rows, args.seed)
    SPLITS.mkdir(parents=True, exist_ok=True)
    for name, records in splits.items():
        records.sort(key=lambda row: (row["label"], row["path"]))
        (SPLITS / f"{name}.jsonl").write_text("".join(json.dumps(row, sort_keys=True) + "\n" for row in records))

    digest = hashlib.sha256(
        b"".join(
            path.read_bytes()
            for path in (MANIFEST, EXTERNAL_NEGATIVE_MANIFEST)
            if path.exists()
        )
    ).hexdigest()
    metadata = {
        "labels": labels,
        "excluded_labels": missing,
        "minimum_per_class": args.minimum_per_class,
        "negative_label": NEGATIVE_LABEL,
        "seed": args.seed,
        "manifest_sha256": digest,
        "counts": dict(counts),
        "split_counts": {name: len(records) for name, records in splits.items()},
        "rejected_image_count": len(rejected_images),
    }
    (SPLITS / "metadata.json").write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")
    print(json.dumps(metadata["split_counts"], sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
