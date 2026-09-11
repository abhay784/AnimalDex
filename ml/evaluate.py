#!/usr/bin/env python3
"""Evaluate a checkpoint on one observation-grouped dataset split."""
from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path

import torch
from torch.utils.data import DataLoader

try:
    from .labels import ROOT
    from .model import ManifestDataset, evaluation_transform, make_model
    from .train import macro_f1
except ImportError:  # `python ml/evaluate.py`
    from labels import ROOT
    from model import ManifestDataset, evaluation_transform, make_model
    from train import macro_f1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--split", choices=("train", "validation", "test"), default="test")
    args = parser.parse_args()

    checkpoint = torch.load(args.checkpoint, map_location="cpu", weights_only=True)
    labels: list[str] = checkpoint["labels"]
    model = make_model(len(labels), pretrained=False)
    model.load_state_dict(checkpoint["model_state"])
    device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
    model.to(device).eval()
    dataset = ManifestDataset(
        ROOT / "ml" / "data" / "splits" / f"{args.split}.jsonl",
        labels,
        evaluation_transform(),
    )
    loader = DataLoader(dataset, batch_size=args.batch_size)

    predictions: list[int] = []
    targets: list[int] = []
    with torch.inference_mode():
        for images, expected in loader:
            predictions.extend(model(images.to(device)).argmax(dim=1).cpu().tolist())
            targets.extend(expected.tolist())
    accuracy = sum(predicted == expected for predicted, expected in zip(predictions, targets)) / len(targets)
    errors = Counter((labels[expected], labels[predicted]) for predicted, expected in zip(predictions, targets) if predicted != expected)
    category_totals: Counter[str] = Counter()
    category_false_accepts: Counter[str] = Counter()
    for row, predicted, expected in zip(dataset.rows, predictions, targets):
        if labels[expected] != "__not_wildlife__":
            continue
        category = str(row.get("negative_category", "unclassified"))
        category_totals[category] += 1
        if predicted != expected:
            category_false_accepts[category] += 1
    report = {
        "split": args.split,
        "images": len(targets),
        "accuracy": accuracy,
        "macro_f1": macro_f1(predictions, targets, len(labels)),
        "negative_false_accept_rate": (
            sum(predicted != expected for predicted, expected in zip(predictions, targets) if labels[expected] == "__not_wildlife__")
            / max(1, sum(labels[expected] == "__not_wildlife__" for expected in targets))
        ),
        "animal_false_rejection_rate": (
            sum(labels[predicted] == "__not_wildlife__" for predicted, expected in zip(predictions, targets) if labels[expected] != "__not_wildlife__")
            / max(1, sum(labels[expected] != "__not_wildlife__" for expected in targets))
        ),
        "negative_false_accept_rate_by_category": {
            category: {
                "images": total,
                "false_accepts": category_false_accepts[category],
                "rate": category_false_accepts[category] / total,
            }
            for category, total in sorted(category_totals.items())
        },
        "most_common_confusions": [
            {"actual": actual, "predicted": predicted, "count": count}
            for (actual, predicted), count in errors.most_common(25)
        ],
    }
    output = args.checkpoint.parent / f"{args.split}_report.json"
    output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
