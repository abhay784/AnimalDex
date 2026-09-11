"""The one source of truth for model class labels."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = ROOT / "AnimalDex" / "Resources" / "species_catalog.json"
NEGATIVE_LABEL = "__not_wildlife__"


def catalog_labels() -> list[str]:
    """Return stable Dex order, which is also the model's output order."""
    entries = json.loads(CATALOG_PATH.read_text())
    labels = [entry["labelKey"] for entry in sorted(entries, key=lambda entry: entry["dexNumber"])]
    if len(labels) != len(set(labels)):
        raise ValueError("species catalog has duplicate model labels")
    if NEGATIVE_LABEL in labels:
        raise ValueError(f"{NEGATIVE_LABEL} is reserved for the negative class")
    return labels


def model_labels() -> list[str]:
    return [*catalog_labels(), NEGATIVE_LABEL]
