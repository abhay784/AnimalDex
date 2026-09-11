#!/usr/bin/env python3
"""Download licensed Open Images hard negatives for AnimalDex.

The Open Images bounding-box annotations provide a compact way to select
photographs with specific non-wildlife subjects. We reject an image whenever
its annotations contain a Person or any Animal descendant, so Human remains an
AnimalDex positive class and non-animal negatives do not silently contain pets
or wildlife. Each retained image records its Open Images ID, source URL,
selection category, and CC-BY-2.0 license in a separate manifest.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import random
import time
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Iterable

import requests
from PIL import Image

try:
    from .labels import NEGATIVE_LABEL, ROOT
except ImportError:  # `python ml/fetch_openimages_negatives.py`
    from labels import NEGATIVE_LABEL, ROOT


DATA = ROOT / "ml" / "data"
RAW = DATA / "raw" / NEGATIVE_LABEL / "openimages"
MANIFEST = DATA / "external_negative_manifest.jsonl"
CACHE = DATA / "openimages_metadata"
CLASS_DESCRIPTIONS_URL = "https://storage.googleapis.com/openimages/v7/oidv7-class-descriptions-boxable.csv"
VALIDATION_BOXES_URL = "https://storage.googleapis.com/openimages/v5/validation-annotations-bbox.csv"
HIERARCHY_URL = "https://storage.googleapis.com/openimages/2018_04/bbox_labels_600_hierarchy.json"
IMAGE_URL = "https://open-images-dataset.s3.amazonaws.com/validation/{image_id}.jpg"
LICENSE = "CC-BY-2.0"
SOURCE = "Open Images V7"

# These subjects are common phone-camera failure modes. The category survives
# in the manifest even though they all train as one reject class.
CATEGORY_LABELS = {
    "food": ("Food", "Dessert", "Fruit", "Vegetable", "Sandwich", "Pizza", "Cake"),
    "indoor_object": ("Chair", "Table", "Furniture", "Computer keyboard", "Mobile phone", "Bottle"),
    "vehicle_or_text": ("Car", "Truck", "Bus", "Motorcycle", "Traffic sign", "Traffic light"),
    # The boxable Open Images vocabulary does not include generic sky, sea,
    # road, or room classes. These built-scene labels provide the equivalent
    # non-animal camera backgrounds with verified annotations.
    "built_scene": ("Building", "Office building", "House", "Skyscraper", "Window", "Door"),
}
REJECT_LABELS = ("Animal", "Person")
REQUEST_HEADERS = {"User-Agent": "AnimalDex-ML/0.1 (educational; dataset provenance recorded)"}


def cached_download(url: str, destination: Path) -> Path:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        return destination
    response = requests.get(url, headers=REQUEST_HEADERS, timeout=(10, 120))
    response.raise_for_status()
    destination.write_bytes(response.content)
    return destination


def class_ids(description_path: Path) -> dict[str, str]:
    with description_path.open(newline="") as handle:
        return {name: mid for mid, name in csv.reader(handle) if mid and name}


def descendant_ids(tree: dict, inherited: bool = False) -> set[str]:
    """Return all labels below an Animal or Person subtree."""
    own = str(tree.get("LabelName", ""))
    active = inherited or own in _REJECT_IDS
    result = {own} if active and own else set()
    for child in tree.get("Subcategory", []):
        result |= descendant_ids(child, active)
    return result


_REJECT_IDS: set[str] = set()


def annotation_index(boxes_path: Path, category_ids: dict[str, set[str]], rejected_ids: set[str]) -> dict[str, set[str]]:
    """Index verified positive labels by image ID without retaining boxes."""
    labels_by_image: dict[str, set[str]] = defaultdict(set)
    useful = set().union(*category_ids.values()) | rejected_ids
    with boxes_path.open(newline="") as handle:
        for row in csv.DictReader(handle):
            if row["LabelName"] in useful and row["ImageID"]:
                labels_by_image[row["ImageID"]].add(row["LabelName"])
    return labels_by_image


def selected_ids(labels_by_image: dict[str, set[str]], category_ids: dict[str, set[str]], rejected_ids: set[str], per_category: int, seed: int) -> dict[str, list[str]]:
    choices: dict[str, list[str]] = {category: [] for category in category_ids}
    for image_id, labels in labels_by_image.items():
        if labels & rejected_ids:
            continue
        for category, ids in category_ids.items():
            if labels & ids:
                choices[category].append(image_id)
    selected: dict[str, list[str]] = {}
    already_selected: set[str] = set()
    for category, candidates in choices.items():
        random.Random(f"{seed}:{category}").shuffle(candidates)
        picked = [image_id for image_id in candidates if image_id not in already_selected][:per_category]
        if len(picked) < per_category:
            raise RuntimeError(f"Open Images has only {len(picked)} usable {category} validation images; need {per_category}")
        selected[category] = picked
        already_selected.update(picked)
    return selected


def existing_ids() -> set[str]:
    if not MANIFEST.exists():
        return set()
    return {
        str(json.loads(line).get("openimages_id"))
        for line in MANIFEST.read_text().splitlines()
        if line.strip()
    }


def download_one(category: str, image_id: str) -> dict | None:
    url = IMAGE_URL.format(image_id=image_id)
    for attempt in range(3):
        try:
            response = requests.get(url, headers=REQUEST_HEADERS, timeout=(10, 60))
            response.raise_for_status()
            content = response.content
            with Image.open(__import__("io").BytesIO(content)) as image:
                image.verify()
            break
        except (requests.RequestException, OSError):
            if attempt == 2:
                return None
            time.sleep(2 ** attempt)
    digest = hashlib.sha256(content).hexdigest()
    path = RAW / category / f"{image_id}-{digest[:12]}.jpg"
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        path.write_bytes(content)
    return {
        "path": path.relative_to(ROOT).as_posix(),
        "label": NEGATIVE_LABEL,
        "negative_category": category,
        "source": SOURCE,
        "source_url": url,
        "openimages_id": image_id,
        "observation_id": f"openimages:validation:{image_id}",
        "license": LICENSE,
        "sha256": digest,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--per-category", type=int, default=250)
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--seed", type=int, default=20260909)
    args = parser.parse_args()
    if args.per_category < 1:
        parser.error("--per-category must be positive")
    if not 1 <= args.workers <= 16:
        parser.error("--workers must be between 1 and 16")

    descriptions = cached_download(CLASS_DESCRIPTIONS_URL, CACHE / "class-descriptions.csv")
    boxes = cached_download(VALIDATION_BOXES_URL, CACHE / "validation-boxes.csv")
    hierarchy = json.loads(cached_download(HIERARCHY_URL, CACHE / "hierarchy.json").read_text())
    ids_by_name = class_ids(descriptions)
    missing_names = [name for names in CATEGORY_LABELS.values() for name in names if name not in ids_by_name]
    if missing_names:
        raise RuntimeError(f"Open Images class names unavailable: {missing_names}")
    global _REJECT_IDS
    _REJECT_IDS = {ids_by_name[name] for name in REJECT_LABELS}
    rejected_ids = descendant_ids(hierarchy)
    category_ids = {category: {ids_by_name[name] for name in names} for category, names in CATEGORY_LABELS.items()}
    selected = selected_ids(annotation_index(boxes, category_ids, rejected_ids), category_ids, rejected_ids, args.per_category, args.seed)

    known = existing_ids()
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    with MANIFEST.open("a") as manifest:
        for category, image_ids in selected.items():
            wanted = [image_id for image_id in image_ids if image_id not in known]
            with ThreadPoolExecutor(max_workers=args.workers) as pool:
                rows: Iterable[dict | None] = pool.map(lambda image_id: download_one(category, image_id), wanted)
                added = 0
                for row in rows:
                    if row is None:
                        continue
                    manifest.write(json.dumps(row, sort_keys=True) + "\n")
                    manifest.flush()
                    added += 1
            print(f"{category}: {len(image_ids) - len(wanted) + added}/{args.per_category} Open Images negatives")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
