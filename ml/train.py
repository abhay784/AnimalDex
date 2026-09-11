#!/usr/bin/env python3
"""Fine-tune MobileNetV3-Small and save the best validation macro-F1 checkpoint."""
from __future__ import annotations

import argparse
import json
import os
import random
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import torch
from torch import nn
from torch.optim import AdamW
from torch.utils.data import DataLoader

try:
    from .labels import ROOT
    from .model import ManifestDataset, evaluation_transform, make_model, training_transform
except ImportError:  # `python ml/train.py`
    from labels import ROOT
    from model import ManifestDataset, evaluation_transform, make_model, training_transform


def macro_f1(predictions: list[int], targets: list[int], class_count: int) -> float:
    scores = []
    for label in range(class_count):
        tp = sum(p == label and t == label for p, t in zip(predictions, targets))
        fp = sum(p == label and t != label for p, t in zip(predictions, targets))
        fn = sum(p != label and t == label for p, t in zip(predictions, targets))
        denominator = 2 * tp + fp + fn
        scores.append(0.0 if denominator == 0 else (2 * tp) / denominator)
    return float(np.mean(scores))


@torch.inference_mode()
def evaluate(model: nn.Module, loader: DataLoader, device: torch.device) -> tuple[float, float]:
    model.eval()
    predictions: list[int] = []
    targets: list[int] = []
    for images, labels in loader:
        output = model(images.to(device))
        predictions.extend(output.argmax(dim=1).cpu().tolist())
        targets.extend(labels.tolist())
    accuracy = sum(p == t for p, t in zip(predictions, targets)) / len(targets)
    return accuracy, macro_f1(predictions, targets, len(loader.dataset.index_for))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--epochs", type=int, default=20)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--learning-rate", type=float, default=3e-4)
    parser.add_argument("--seed", type=int, default=20260909)
    parser.add_argument("--run-dir", type=Path, default=ROOT / "ml" / "runs" / "latest")
    parser.add_argument(
        "--resume-checkpoint",
        type=Path,
        help="resume model weights and completed epoch from a compatible best.pt checkpoint",
    )
    args = parser.parse_args()

    random.seed(args.seed)
    np.random.seed(args.seed)
    torch.manual_seed(args.seed)
    if torch.backends.mps.is_available():
        device = torch.device("mps")
    elif torch.cuda.is_available():
        device = torch.device("cuda")
    else:
        device = torch.device("cpu")

    splits = ROOT / "ml" / "data" / "splits"
    metadata = json.loads((splits / "metadata.json").read_text())
    labels = metadata["labels"]
    train_set = ManifestDataset(splits / "train.jsonl", labels, training_transform())
    validation_set = ManifestDataset(splits / "validation.jsonl", labels, evaluation_transform())
    workers = 0 if device.type == "mps" else min(8, (os.cpu_count() or 2))
    train_loader = DataLoader(train_set, batch_size=args.batch_size, shuffle=True, num_workers=workers)
    validation_loader = DataLoader(validation_set, batch_size=args.batch_size, num_workers=workers)

    # A resume checkpoint already contains the pretrained backbone, so do not
    # fetch ImageNet weights merely to overwrite them moments later.
    model = make_model(len(labels), pretrained=args.resume_checkpoint is None).to(device)
    criterion = nn.CrossEntropyLoss()
    optimizer = AdamW(model.parameters(), lr=args.learning_rate, weight_decay=1e-4)
    args.run_dir.mkdir(parents=True, exist_ok=True)
    best_f1 = -1.0
    history: list[dict] = []
    start_epoch = 1
    if args.resume_checkpoint:
        checkpoint = torch.load(args.resume_checkpoint, map_location="cpu", weights_only=True)
        if checkpoint.get("labels") != labels:
            raise ValueError("resume checkpoint labels do not match the frozen split")
        model.load_state_dict(checkpoint["model_state"])
        completed_epoch = int(checkpoint["epoch"])
        if completed_epoch >= args.epochs:
            raise ValueError(f"resume checkpoint is already at epoch {completed_epoch}; --epochs must be higher")
        best_f1 = float(checkpoint["validation"]["validation_macro_f1"])
        history_path = args.run_dir / "history.json"
        if history_path.exists():
            history = [metric for metric in json.loads(history_path.read_text()) if int(metric["epoch"]) <= completed_epoch]
        start_epoch = completed_epoch + 1
        print(json.dumps({"resumed_from": str(args.resume_checkpoint), "completed_epoch": completed_epoch, "best_validation_macro_f1": best_f1}))
    for epoch in range(start_epoch, args.epochs + 1):
        model.train()
        losses = []
        for images, targets in train_loader:
            optimizer.zero_grad(set_to_none=True)
            logits = model(images.to(device))
            loss = criterion(logits, targets.to(device))
            loss.backward()
            optimizer.step()
            losses.append(float(loss.detach().cpu()))
        accuracy, f1 = evaluate(model, validation_loader, device)
        metrics = {"epoch": epoch, "train_loss": float(np.mean(losses)), "validation_accuracy": accuracy, "validation_macro_f1": f1}
        history.append(metrics)
        # Persist after every epoch so a long local run can be monitored safely
        # without waiting for the final epoch or reading Terminal scrollback.
        (args.run_dir / "history.json").write_text(json.dumps(history, indent=2) + "\n")
        print(json.dumps(metrics, sort_keys=True))
        if f1 > best_f1:
            best_f1 = f1
            torch.save({
                "architecture": "mobilenet_v3_small",
                "labels": labels,
                "model_state": model.state_dict(),
                "dataset_metadata": metadata,
                "epoch": epoch,
                "validation": metrics,
                "created_at": datetime.now(timezone.utc).isoformat(),
            }, args.run_dir / "best.pt")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
