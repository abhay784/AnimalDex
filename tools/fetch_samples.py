#!/usr/bin/env python3
"""Download a handful of real photos into Resources/dev_samples/.

The Simulator has no camera, so these stand in for a live viewfinder. They are
real photographs on purpose: synthetic shapes would exercise the UI but tell us
nothing about whether recognition works, and recognition is the risky part.

Photos come from iNaturalist and carry per-photo CC licenses, so attribution is
written alongside them and surfaced in the app's debug panel. Dev assets only.
"""
from __future__ import annotations

import json
import pathlib
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
CACHE = pathlib.Path(__file__).parent / ".cache"
OUT = ROOT / "AnimalDex" / "Resources" / "dev_samples"

# Chosen to cover distinct branches of the recognition path: several taxa, one
# food-veto probe, and one creature Vision only knows at hypernym level.
WANTED = [
    "squirrel", "butterfly", "spider", "frog",
    "owl", "snail", "dragonfly", "turtle",
]

UA = "AnimalDex/0.1 (dev sample fetcher; educational project)"


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    credits: dict[str, str] = {}

    for label in WANTED:
        cached = CACHE / f"inat_{label}.json"
        if not cached.exists():
            print(f"  ! no cached taxon for {label} — run build_catalog.py first")
            continue

        results = json.loads(cached.read_text()).get("results", [])
        if not results:
            continue
        taxon = results[0]
        photo = taxon.get("default_photo") or {}
        url = photo.get("medium_url") or photo.get("url")
        if not url:
            print(f"  ! {label}: taxon has no photo")
            continue

        dest = OUT / f"sample_{label}.jpg"
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=20) as r:
                dest.write_bytes(r.read())
        except Exception as e:  # noqa: BLE001
            print(f"  ! {label}: {type(e).__name__} {e}")
            continue

        credits[dest.name] = photo.get("attribution", "iNaturalist")
        print(f"  {dest.name:<26} {dest.stat().st_size/1024:>6.0f} KB  {taxon.get('preferred_common_name')}")
        time.sleep(0.5)

    (OUT / "CREDITS.json").write_text(json.dumps(credits, indent=2, ensure_ascii=False))
    print(f"\n{len(credits)} samples -> {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
