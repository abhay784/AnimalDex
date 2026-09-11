#!/usr/bin/env python3
"""Evaluate zero-shot BioCLIP against the frozen AnimalDex split.

This benchmark is deliberately separate from the MobileNet training run. It
uses each AnimalDex species' scientific name as a BioCLIP candidate and six
explicit non-wildlife candidates, then collapses any non-wildlife prediction
back to AnimalDex's single ``__not_wildlife__`` output for a fair comparison.
"""
from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path

import open_clip
import torch
from torch.utils.data import DataLoader

try:
    from .labels import NEGATIVE_LABEL, ROOT
    from .model import ManifestDataset
    from .train import macro_f1
except ImportError:  # `python ml/benchmark_bioclip.py`
    from labels import NEGATIVE_LABEL, ROOT
    from model import ManifestDataset
    from train import macro_f1


MODEL_ID = "hf-hub:imageomics/bioclip"
NEGATIVE_PROMPTS = (
    "a photograph of food, not an animal",
    "a photograph of an indoor object, not an animal",
    "a photograph of a vehicle, road sign, or text, not an animal",
    "a photograph of a building or urban scene, not an animal",
    "a photograph of a plant or fungus, not an animal",
    "a photograph with no animal or wildlife",
)


def prompts_for(labels: list[str]) -> tuple[list[str], list[str]]:
    catalog = json.loads((ROOT / "AnimalDex" / "Resources" / "species_catalog.json").read_text())
    entries = {str(entry["labelKey"]): entry for entry in catalog}
    positive_labels = [label for label in labels if label != NEGATIVE_LABEL]
    missing = set(positive_labels) - entries.keys()
    if missing:
        raise ValueError(f"catalog entries missing for model labels: {sorted(missing)}")
    # BioCLIP's training data uses taxonomic names. Prefixing all candidates in
    # the same way prevents the English display names from biasing candidates
    # with shorter or more familiar spellings.
    prompts = [f"a photograph of {entries[label]['scientificName']}" for label in positive_labels]
    return positive_labels, prompts + list(NEGATIVE_PROMPTS)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--split", choices=("validation", "test"), default="test")
    parser.add_argument("--batch-size", type=int, default=8)
    parser.add_argument("--device", choices=("cpu", "mps", "cuda"), default="cpu")
    parser.add_argument("--limit", type=int, default=0, help="optional first-N smoke-test limit")
    parser.add_argument("--output", type=Path, default=ROOT / "ml" / "runs" / "bioclip_zero_shot" / "test_report.json")
    args = parser.parse_args()
    if args.device == "mps" and not torch.backends.mps.is_available():
        raise RuntimeError("MPS is unavailable")
    if args.device == "cuda" and not torch.cuda.is_available():
        raise RuntimeError("CUDA is unavailable")

    metadata = json.loads((ROOT / "ml" / "data" / "splits" / "metadata.json").read_text())
    labels: list[str] = metadata["labels"]
    dataset = ManifestDataset(ROOT / "ml" / "data" / "splits" / f"{args.split}.jsonl", labels, transform=lambda image: image.convert("RGB"))
    if args.limit:
        dataset.rows = dataset.rows[:args.limit]
    loader = DataLoader(dataset, batch_size=args.batch_size, shuffle=False, collate_fn=lambda batch: batch)
    positive_labels, prompts = prompts_for(labels)
    device = torch.device(args.device)
    model, _, preprocess = open_clip.create_model_and_transforms(MODEL_ID, device=device)
    tokenizer = open_clip.get_tokenizer(MODEL_ID)
    model.eval()
    with torch.inference_mode():
        text_features = model.encode_text(tokenizer(prompts).to(device))
        text_features = text_features / text_features.norm(dim=-1, keepdim=True)

    predictions: list[int] = []
    targets: list[int] = []
    top5_hits = 0
    for batch in loader:
        images, expected = zip(*batch)
        tensors = torch.stack([preprocess(image) for image in images]).to(device)
        with torch.inference_mode():
            image_features = model.encode_image(tensors)
            image_features = image_features / image_features.norm(dim=-1, keepdim=True)
            similarity = 100 * image_features @ text_features.T
        candidate_predictions = similarity.argmax(dim=1).cpu().tolist()
        # A negative prototype maps to the one application reject class.
        negative_index = labels.index(NEGATIVE_LABEL)
        predictions.extend(index if index < len(positive_labels) else negative_index for index in candidate_predictions)
        targets.extend(expected)
        top_candidates = similarity.topk(min(5, similarity.shape[1]), dim=1).indices.cpu().tolist()
        for candidate_indices, target in zip(top_candidates, expected):
            top_labels = {index if index < len(positive_labels) else negative_index for index in candidate_indices}
            top5_hits += int(target in top_labels)

    accuracy = sum(predicted == target for predicted, target in zip(predictions, targets)) / len(targets)
    errors = Counter((labels[target], labels[predicted]) for predicted, target in zip(predictions, targets) if predicted != target)
    category_totals: Counter[str] = Counter()
    category_false_accepts: Counter[str] = Counter()
    for row, predicted, target in zip(dataset.rows, predictions, targets):
        if labels[target] != NEGATIVE_LABEL:
            continue
        category = str(row.get("negative_category", "unclassified"))
        category_totals[category] += 1
        if predicted != target:
            category_false_accepts[category] += 1
    report = {
        "model": "imageomics/bioclip",
        "mode": "zero_shot",
        "device": args.device,
        "split": args.split,
        "images": len(targets),
        "species_prompt_template": "a photograph of {scientificName}",
        "negative_prompts": list(NEGATIVE_PROMPTS),
        "accuracy": accuracy,
        "top5_accuracy": top5_hits / len(targets),
        "macro_f1": macro_f1(predictions, targets, len(labels)),
        "negative_false_accept_rate": (
            sum(predicted != target for predicted, target in zip(predictions, targets) if labels[target] == NEGATIVE_LABEL)
            / max(1, sum(labels[target] == NEGATIVE_LABEL for target in targets))
        ),
        "animal_false_rejection_rate": (
            sum(labels[predicted] == NEGATIVE_LABEL for predicted, target in zip(predictions, targets) if labels[target] != NEGATIVE_LABEL)
            / max(1, sum(labels[target] != NEGATIVE_LABEL for target in targets))
        ),
        "negative_false_accept_rate_by_category": {
            category: {"images": total, "false_accepts": category_false_accepts[category], "rate": category_false_accepts[category] / total}
            for category, total in sorted(category_totals.items())
        },
        "most_common_confusions": [
            {"actual": actual, "predicted": predicted, "count": count}
            for (actual, predicted), count in errors.most_common(25)
        ],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
