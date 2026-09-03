#!/usr/bin/env python3
"""Build AnimalDex/Resources/species_catalog.json from public APIs.

Sources
  iNaturalist  /v1/taxa    -> taxonomy, common name, observation count, photo credit
  Wikipedia    REST summary -> dex flavor text

Both are unauthenticated. iNat asks for <=100 req/min, so we pace ourselves and
cache aggressively — a re-run with a warm cache is instant.

    python3 tools/build_catalog.py            # incremental, uses cache
    python3 tools/build_catalog.py --refresh  # ignore cache
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys
import time
import urllib.parse
import urllib.request

from species_map import LABEL_MAP

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "AnimalDex" / "Resources" / "species_catalog.json"
CACHE = pathlib.Path(__file__).parent / ".cache"
CACHE.mkdir(exist_ok=True)

UA = "AnimalDex/0.1 (catalog builder; educational project)"
INAT = "https://api.inaturalist.org/v1/taxa"
WIKI = "https://en.wikipedia.org/api/rest_v1/page/summary/"

# iNat iconic taxa we model explicitly; anything else becomes "Animalia",
# which the app renders as the generic CREATURE type.
KNOWN_TYPES = {
    "Aves", "Insecta", "Mammalia", "Arachnida",
    "Reptilia", "Amphibia", "Actinopterygii", "Mollusca",
}


def fetch(url: str, cache_key: str, refresh: bool) -> dict | None:
    path = CACHE / f"{cache_key}.json"
    if path.exists() and not refresh:
        return json.loads(path.read_text())
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                data = json.load(r)
            path.write_text(json.dumps(data))
            time.sleep(0.7)  # stay well under the rate limit
            return data
        except Exception as e:  # noqa: BLE001 - one gap is not fatal, but do back off
            # Pacing on the failure path matters more than on the success path:
            # without it a rate-limit burst turns into a tighter request loop,
            # which is what produced 42 phantom "no match" results earlier.
            wait = 1.5 * (attempt + 1) ** 2
            print(f"  ! {type(e).__name__} on {url} (attempt {attempt+1}/3), "
                  f"backing off {wait:.1f}s", file=sys.stderr)
            time.sleep(wait)
    return None


def pick_taxon(results: list[dict], want: str, expect: str) -> dict | None:
    """Choose the right taxon out of a fuzzy search.

    iNat's `q=` search substring-matches across every kingdom and every rank, so
    a naive `results[0]` gives "common dandelion" for `lion`, "Mosses" for
    `moose`, and the *genus* "Typical Old World Deer" for `elk`. The last one is
    the dangerous kind: a genus aggregates the observation counts of everything
    beneath it, so rarity comes out wrong while looking perfectly fine.

    Two constraints fix it. `Animalia` is always accepted alongside the expected
    iconic taxon because iNat files cartilaginous fish, crustaceans, and worms
    there — and it still excludes every plant and fungus.
    """
    if not results:
        return None

    allowed = {expect, "Animalia"}
    def usable(r: dict) -> bool:
        return r.get("iconic_taxon_name") in allowed and r.get("rank") in {"species", "subspecies"}

    pool = [r for r in results if usable(r)]
    if not pool:
        return None
    # Species outrank subspecies unless nothing else matches - domestic animals
    # (Sus scrofa domesticus) only exist at subspecies rank.
    pool.sort(key=lambda r: 0 if r.get("rank") == "species" else 1)

    lowered = want.lower()
    # A scientific name is unique by construction, so an exact hit on it beats
    # any common-name heuristic. This is why the ambiguous entries in
    # species_map.py are written as binomials.
    by_science = [r for r in pool if (r.get("name") or "").lower() == lowered]
    if by_science:
        return by_science[0]

    exact = [r for r in pool if (r.get("preferred_common_name") or "").lower() == lowered]
    if exact:
        return exact[0]
    # Otherwise prefer a common name that at least contains the words we asked for.
    contains = [r for r in pool if lowered in (r.get("preferred_common_name") or "").lower()]
    return (contains or pool)[0]


def wiki_summary(wikipedia_url: str | None, key: str, refresh: bool) -> str:
    if not wikipedia_url:
        return ""
    title = wikipedia_url.rstrip("/").rsplit("/", 1)[-1]
    data = fetch(WIKI + urllib.parse.quote(title), f"wiki_{key}", refresh)
    if not data:
        return ""
    extract = (data.get("extract") or "").strip()
    # Dex entries are a couple of sentences, not an encyclopedia article.
    sentences = extract.split(". ")
    return ". ".join(sentences[:2]).rstrip(".") + "." if extract else ""


def photo_credit(taxon: dict) -> str | None:
    photo = taxon.get("default_photo") or {}
    attribution = photo.get("attribution")
    return attribution.strip() if attribution else None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--refresh", action="store_true", help="ignore cached responses")
    args = ap.parse_args()

    entries: list[dict] = []
    problems: list[str] = []

    for index, (label, query, expect) in enumerate(LABEL_MAP, start=1):
        url = f"{INAT}?q={urllib.parse.quote(query)}&per_page=12"
        data = fetch(url, f"inat_{label}", args.refresh)
        taxon = pick_taxon((data or {}).get("results", []), query, expect)

        if not taxon:
            problems.append(f"{label}: no {expect}/species match for {query!r}")
            continue

        common = taxon.get("preferred_common_name") or query
        if common.lower() != query.lower():
            problems.append(f"{label}: asked {query!r}, matched {common!r}")

        iconic = taxon.get("iconic_taxon_name") or "Animalia"
        wiki_url = taxon.get("wikipedia_url")

        entries.append({
            "labelKey": label,
            "dexNumber": index,
            "commonName": common,
            "scientificName": taxon.get("name", ""),
            "taxonType": iconic if iconic in KNOWN_TYPES else "Animalia",
            "observationsCount": int(taxon.get("observations_count") or 0),
            "dexDescription": wiki_summary(wiki_url, label, args.refresh),
            "wikipediaURL": wiki_url,
            "photoAttribution": photo_credit(taxon),
        })
        print(f"  {index:>3}. {label:<20} -> {common:<34} {entries[-1]['observationsCount']:>9,}")

    # Two labels resolving to one taxon means two dex slots for one animal.
    by_sci: dict[str, list[str]] = {}
    for e in entries:
        by_sci.setdefault(e["scientificName"], []).append(e["labelKey"])
    for sci, labels in by_sci.items():
        if len(labels) > 1:
            problems.append(f"DUPLICATE taxon {sci} claimed by {labels}")

    missing_desc = [e["labelKey"] for e in entries if not e["dexDescription"]]
    if missing_desc:
        problems.append(f"{len(missing_desc)} entries have no description: {missing_desc}")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(entries, indent=2, ensure_ascii=False))

    print(f"\nwrote {len(entries)} entries -> {OUT.relative_to(ROOT)}")
    if problems:
        print(f"\n{len(problems)} item(s) worth eyeballing:")
        for p in problems:
            print(f"  - {p}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
