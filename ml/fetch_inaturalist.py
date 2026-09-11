#!/usr/bin/env python3
"""Download a licensed, provenance-recorded iNaturalist corpus for AnimalDex.

The data output is deliberately ignored by Git. Each downloaded image has a
manifest row carrying the source observation, photo URL and license, which lets
us reproduce or remove training material later.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import time
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

import requests
from PIL import Image

try:
    from .labels import ROOT, catalog_labels
except ImportError:  # `python ml/fetch_inaturalist.py`
    from labels import ROOT, catalog_labels

API = "https://api.inaturalist.org/v1"
DATA = ROOT / "ml" / "data"
RAW = DATA / "raw"
MANIFEST = DATA / "inat_manifest.jsonl"
LICENSES = ("CC0", "CC-BY", "CC-BY-SA", "CC-BY-NC", "CC-BY-NC-SA")
SESSION = requests.Session()
SESSION.headers["User-Agent"] = "AnimalDex-ML/0.1 (educational, contact via repository)"
# iNaturalist serves some large observation pages through a proxy. Closing the
# connection after each request avoids a stale keep-alive socket stalling a
# long unattended corpus download.
SESSION.headers["Connection"] = "close"
REQUEST_DELAY = 0.8
LAST_REQUEST_AT = 0.0


def get_json(url: str, params: dict[str, Any]) -> dict[str, Any]:
    global LAST_REQUEST_AT
    wait = REQUEST_DELAY - (time.monotonic() - LAST_REQUEST_AT)
    if wait > 0:
        time.sleep(wait)
    for attempt in range(4):
        try:
            response = SESSION.get(url, params=params, timeout=(8, 30))
            LAST_REQUEST_AT = time.monotonic()
        except requests.RequestException:
            if attempt == 3:
                raise
            time.sleep(2 ** (attempt + 1))
            continue
        if response.status_code == 429:
            time.sleep(2 ** (attempt + 1))
            continue
        response.raise_for_status()
        return response.json()
    raise RuntimeError(f"rate limited by iNaturalist: {url}")


def taxon_for(label: str) -> int:
    # The catalog already gives us a scientific name, so match that exact taxon.
    catalog = json.loads((ROOT / "AnimalDex" / "Resources" / "species_catalog.json").read_text())
    entry = next(item for item in catalog if item["labelKey"] == label)
    results = get_json(f"{API}/taxa", {"q": entry["scientificName"], "per_page": 30})["results"]
    exact = [item for item in results if item.get("name") == entry["scientificName"]]
    if not exact:
        raise RuntimeError(f"no exact iNaturalist taxon for {label}: {entry['scientificName']}")
    return int(exact[0]["id"])


def existing_urls() -> set[str]:
    if not MANIFEST.exists():
        return set()
    return {json.loads(line)["source_url"] for line in MANIFEST.read_text().splitlines() if line.strip()}


def existing_counts() -> Counter[str]:
    if not MANIFEST.exists():
        return Counter()
    return Counter(
        json.loads(line)["label"]
        for line in MANIFEST.read_text().splitlines()
        if line.strip()
    )


def save_photo(label: str, observation: dict[str, Any], photo: dict[str, Any]) -> dict[str, Any] | None:
    license_code = str(photo.get("license_code") or "").upper()
    if license_code not in LICENSES:
        return None
    # A medium iNaturalist image has enough detail for the 224px training
    # crop, while keeping a first local training corpus within laptop storage.
    source_url = photo.get("url", "").replace("square", "medium")
    if not source_url:
        return None
    for attempt in range(3):
        try:
            # `requests.Session` shares mutable connection-pool state, so API
            # metadata remains serial while independent image files use a fresh
            # request in the bounded download worker pool.
            response = requests.get(source_url, headers=SESSION.headers, timeout=(8, 45))
            response.raise_for_status()
            content = response.content
            break
        except requests.RequestException:
            if attempt == 2:
                return None
            time.sleep(2 ** (attempt + 1))
    try:
        # Verify the encoded stream before retaining it. We reopen below rather
        # than calling `verify()` on a converted image, which no longer checks
        # the original decoder state.
        import io
        with Image.open(io.BytesIO(content)) as image:
            image.verify()
    except Exception:
        return None
    digest = hashlib.sha256(content).hexdigest()
    destination = RAW / label / f"{digest}.jpg"
    destination.parent.mkdir(parents=True, exist_ok=True)
    if not destination.exists():
        destination.write_bytes(content)
    return {
        "path": destination.relative_to(ROOT).as_posix(),
        "label": label,
        "source": "iNaturalist",
        "source_url": source_url,
        "observation_id": observation["id"],
        "photo_id": photo.get("id"),
        "observer": observation.get("user", {}).get("login"),
        "license": license_code,
        "sha256": digest,
    }


def collect(
    label: str,
    query: dict[str, Any],
    target: int,
    known_urls: set[str],
    manifest: Any,
    workers: int,
) -> int:
    """Download up to target new, licensed images from an observation query."""
    collected = 0
    page = 1
    while collected < target:
        response = get_json(f"{API}/observations", {
            "quality_grade": "research",
            "photos": "true",
            "per_page": 100,
            "page": page,
            "order": "desc",
            "order_by": "votes",
            "photo_license": ",".join(LICENSES),
            **query,
        })
        observations = response.get("results", [])
        if not observations:
            break
        candidates: list[tuple[dict[str, Any], dict[str, Any]]] = []
        queued_urls: set[str] = set()
        for observation in observations:
            for photo in observation.get("photos", []):
                source_url = photo.get("url", "").replace("square", "medium")
                if not source_url or source_url in known_urls or source_url in queued_urls:
                    continue
                candidates.append((observation, photo))
                queued_urls.add(source_url)

        # Downloading image files dominates collection time. Six workers keep
        # the laptop and the public host responsive while avoiding an unbounded
        # request burst. Metadata API calls above remain rate-limited.
        remaining = target - collected
        with ThreadPoolExecutor(max_workers=workers) as pool:
            rows = pool.map(lambda item: save_photo(label, item[0], item[1]), candidates[:remaining])
            for row in rows:
                if row is None:
                    continue
                manifest.write(json.dumps(row, sort_keys=True) + "\n")
                manifest.flush()
                known_urls.add(row["source_url"])
                collected += 1
                if collected >= target:
                    return collected
        page += 1
    return collected


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--per-class", type=int, default=400)
    parser.add_argument(
        "--negative-per-iconic-taxon",
        type=int,
        default=0,
        help="licensed Plant and Fungi images to add to __not_wildlife__ per iconic taxon",
    )
    parser.add_argument(
        "--research-only",
        action="store_true",
        help="do not use licensed casual iNaturalist observations to fill sparse species",
    )
    parser.add_argument("--delay", type=float, default=0.8, help="minimum seconds between iNaturalist API requests")
    parser.add_argument("--workers", type=int, default=6, help="parallel image downloads (1-12; API requests stay serial)")
    args = parser.parse_args()
    if args.per_class < 1:
        parser.error("--per-class must be positive")
    if args.negative_per_iconic_taxon < 0:
        parser.error("--negative-per-iconic-taxon cannot be negative")
    if not 1 <= args.workers <= 12:
        parser.error("--workers must be between 1 and 12")

    global REQUEST_DELAY
    REQUEST_DELAY = args.delay

    DATA.mkdir(parents=True, exist_ok=True)
    known_urls = existing_urls()
    counts = existing_counts()
    with MANIFEST.open("a") as manifest:
        for label in catalog_labels():
            taxon_id = taxon_for(label)
            present = counts[label]
            collected = collect(label, {"taxon_id": taxon_id}, max(0, args.per_class - present), known_urls, manifest, args.workers)
            counts[label] += collected
            # A few species have very few research-grade observations. Casual
            # observations remain licensed, are still tied to a specific taxon,
            # and avoid silently dropping a class from the first classifier.
            if counts[label] < args.per_class and not args.research_only:
                collected = collect(
                    label,
                    {"taxon_id": taxon_id, "quality_grade": "casual"},
                    args.per_class - counts[label],
                    known_urls,
                    manifest,
                    args.workers,
                )
                counts[label] += collected
            print(f"{label}: {counts[label]}/{args.per_class} licensed images ({collected} new)")
        for iconic_taxon in ("Plantae", "Fungi"):
            if not args.negative_per_iconic_taxon:
                continue
            collected = collect(
                "__not_wildlife__",
                {"iconic_taxa": iconic_taxon},
                args.negative_per_iconic_taxon,
                known_urls,
                manifest,
                args.workers,
            )
            print(f"__not_wildlife__ ({iconic_taxon}): {collected}/{args.negative_per_iconic_taxon} new licensed images")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
