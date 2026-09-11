#!/usr/bin/env python3
"""Fine-tune a small BioCLIP vision slice plus an AnimalDex classifier head.

The model is intentionally conservative for a laptop: the BioCLIP image tower
is frozen except for its final transformer blocks and projection, while a new
linear 133-way AnimalDex head learns from the existing, grouped split. This is
real fine-tuning, but avoids updating the full ViT-B/16 on every batch.
"""
from __future__ import annotations

import argparse
import json
import os
import random
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import open_clip
import torch
from torch import nn
from torch.optim import AdamW
from torch.utils.data import DataLoader

try:
    from .labels import ROOT
    from .model import ManifestDataset
    from .train import macro_f1
except ImportError:  # `python ml/train_bioclip.py`
    from labels import ROOT
    from model import ManifestDataset
    from train import macro_f1


MODEL_ID = "hf-hub:imageomics/bioclip"


class BioCLIPSpeciesClassifier(nn.Module):
    def __init__(self, backbone: nn.Module, embedding_size: int, class_count: int):
        super().__init__()
        self.backbone = backbone
        self.classifier = nn.Linear(embedding_size, class_count)

    def forward(self, images: torch.Tensor) -> torch.Tensor:
        embeddings = self.backbone.encode_image(images, normalize=True)
        return self.classifier(embeddings)


def unfreeze_final_blocks(backbone: nn.Module, count: int) -> None:
    """Keep BioCLIP cheap enough for a laptop while retaining visual adaptation."""
    for parameter in backbone.parameters():
        parameter.requires_grad = False
    visual = backbone.visual
    blocks = list(visual.transformer.resblocks)
    if not 0 <= count <= len(blocks):
        raise ValueError(f"--unfreeze-blocks must be between 0 and {len(blocks)}")
    for block in blocks[-count:] if count else []:
        for parameter in block.parameters():
            parameter.requires_grad = True
    for name in ("ln_post", "proj"):
        module = getattr(visual, name, None)
        if isinstance(module, nn.Module):
            for parameter in module.parameters():
                parameter.requires_grad = True
        elif isinstance(module, nn.Parameter):
            module.requires_grad = True


@torch.inference_mode()
def evaluate(
    model: nn.Module,
    loader: DataLoader,
    device: torch.device,
    class_count: int,
    use_amp: bool,
) -> tuple[float, float]:
    model.eval()
    predictions: list[int] = []
    targets: list[int] = []
    for images, expected in loader:
        with torch.autocast(device_type=device.type, dtype=torch.float16, enabled=use_amp):
            logits = model(images.to(device))
        predictions.extend(logits.argmax(dim=1).cpu().tolist())
        targets.extend(expected.tolist())
    accuracy = sum(predicted == expected for predicted, expected in zip(predictions, targets)) / len(targets)
    return accuracy, macro_f1(predictions, targets, class_count)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--epochs", type=int, default=10)
    parser.add_argument("--batch-size", type=int, default=4)
    parser.add_argument("--unfreeze-blocks", type=int, default=2)
    parser.add_argument(
        "--amp",
        action="store_true",
        help="use CUDA float16 automatic mixed precision for faster GPU training",
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=None,
        help="parallel image-loader processes (default: up to four)",
    )
    parser.add_argument(
        "--prefetch-factor",
        type=int,
        default=2,
        help="batches each image-loader process prepares ahead of the GPU",
    )
    parser.add_argument("--head-learning-rate", type=float, default=1e-3)
    parser.add_argument("--backbone-learning-rate", type=float, default=1e-5)
    parser.add_argument("--patience", type=int, default=3)
    parser.add_argument(
        "--log-interval",
        type=int,
        default=100,
        help="print a progress update after this many training batches",
    )
    parser.add_argument("--seed", type=int, default=20260910)
    parser.add_argument("--device", choices=("mps", "cpu", "cuda"), default="mps")
    parser.add_argument("--run-dir", type=Path, default=ROOT / "ml" / "runs" / "bioclip_finetune")
    parser.add_argument(
        "--resume-checkpoint",
        type=Path,
        help="continue from a compatible saved BioCLIP checkpoint without repeating completed epochs",
    )
    args = parser.parse_args()
    if args.device == "mps" and not torch.backends.mps.is_available():
        raise RuntimeError("MPS is unavailable; use --device cpu")
    if args.device == "cuda" and not torch.cuda.is_available():
        raise RuntimeError("CUDA is unavailable; use --device cpu")
    if args.amp and args.device != "cuda":
        parser.error("--amp is supported only with --device cuda")
    if args.epochs < 1 or args.batch_size < 1 or args.patience < 1 or args.log_interval < 1:
        parser.error("epochs, batch size, patience, and log interval must be positive")
    if args.workers is not None and args.workers < 0:
        parser.error("workers cannot be negative")
    if args.prefetch_factor < 1:
        parser.error("prefetch factor must be positive")

    random.seed(args.seed)
    np.random.seed(args.seed)
    torch.manual_seed(args.seed)
    device = torch.device(args.device)
    scaler = torch.amp.GradScaler("cuda", enabled=args.amp)
    splits = ROOT / "ml" / "data" / "splits"
    metadata = json.loads((splits / "metadata.json").read_text())
    labels: list[str] = metadata["labels"]
    backbone, preprocessing_train, preprocessing_validation = open_clip.create_model_and_transforms(MODEL_ID)
    unfreeze_final_blocks(backbone, args.unfreeze_blocks)
    embedding_size = int(backbone.visual.output_dim)
    model = BioCLIPSpeciesClassifier(backbone, embedding_size, len(labels)).to(device)
    train_set = ManifestDataset(splits / "train.jsonl", labels, preprocessing_train)
    validation_set = ManifestDataset(splits / "validation.jsonl", labels, preprocessing_validation)
    # Loading and decoding JPEGs in the training process starves MPS on a
    # laptop.  Separate loader processes overlap that CPU/I/O work with GPU
    # execution.  Explicit --workers 0 remains available for troubleshooting.
    workers = args.workers if args.workers is not None else min(4, os.cpu_count() or 2)
    loader_options: dict[str, object] = {"num_workers": workers}
    if workers:
        loader_options.update({
            "persistent_workers": True,
            "prefetch_factor": args.prefetch_factor,
        })
    train_loader = DataLoader(train_set, batch_size=args.batch_size, shuffle=True, **loader_options)
    validation_loader = DataLoader(validation_set, batch_size=args.batch_size, **loader_options)
    print(json.dumps({
        "device": str(device),
        "train_samples": len(train_set),
        "train_batches_per_epoch": len(train_loader),
        "validation_samples": len(validation_set),
        "image_loader_workers": workers,
        "automatic_mixed_precision": args.amp,
    }, sort_keys=True), flush=True)
    backbone_parameters = [parameter for parameter in model.backbone.parameters() if parameter.requires_grad]
    trainable_parameters = [parameter for parameter in model.parameters() if parameter.requires_grad]
    optimizer = AdamW(
        [
            {"params": model.classifier.parameters(), "lr": args.head_learning_rate},
            {"params": backbone_parameters, "lr": args.backbone_learning_rate},
        ],
        weight_decay=1e-4,
    )
    criterion = nn.CrossEntropyLoss(label_smoothing=0.05)
    args.run_dir.mkdir(parents=True, exist_ok=True)
    history: list[dict] = []
    best_f1 = -1.0
    stalled_epochs = 0
    start_epoch = 1
    if args.resume_checkpoint:
        # Memory-map a large checkpoint instead of issuing a single blocking
        # read from a file-provider-backed Documents directory. This is both
        # faster on APFS and avoids intermittent ``Errno 60`` read timeouts.
        checkpoint = torch.load(
            args.resume_checkpoint,
            map_location="cpu",
            weights_only=True,
            mmap=True,
        )
        if checkpoint.get("labels") != labels:
            raise ValueError("resume checkpoint labels do not match the frozen split")
        if checkpoint.get("model_id") != MODEL_ID:
            raise ValueError("resume checkpoint was not created from the expected BioCLIP model")
        model.backbone.load_state_dict(checkpoint["backbone_state"])
        model.classifier.load_state_dict(checkpoint["classifier_state"])
        completed_epoch = int(checkpoint["epoch"])
        if completed_epoch >= args.epochs:
            raise ValueError(f"resume checkpoint is already at epoch {completed_epoch}; --epochs must be higher")
        best_f1 = float(checkpoint["validation"]["validation_macro_f1"])
        history_path = args.run_dir / "history.json"
        if history_path.exists():
            history = [metric for metric in json.loads(history_path.read_text()) if int(metric["epoch"]) <= completed_epoch]
        start_epoch = completed_epoch + 1
        print(json.dumps({"resumed_from": str(args.resume_checkpoint), "completed_epoch": completed_epoch, "best_validation_macro_f1": best_f1}), flush=True)
    for epoch in range(start_epoch, args.epochs + 1):
        model.train()
        losses: list[float] = []
        for batch_index, (images, expected) in enumerate(train_loader, start=1):
            optimizer.zero_grad(set_to_none=True)
            with torch.autocast(device_type=device.type, dtype=torch.float16, enabled=args.amp):
                logits = model(images.to(device))
                loss = criterion(logits, expected.to(device))
            scaler.scale(loss).backward()
            scaler.unscale_(optimizer)
            torch.nn.utils.clip_grad_norm_(trainable_parameters, max_norm=1.0)
            scaler.step(optimizer)
            scaler.update()
            losses.append(float(loss.detach().cpu()))
            if batch_index % args.log_interval == 0 or batch_index == len(train_loader):
                print(json.dumps({
                    "epoch": epoch,
                    "batch": batch_index,
                    "batches": len(train_loader),
                    "train_loss": losses[-1],
                }, sort_keys=True), flush=True)
        accuracy, f1 = evaluate(model, validation_loader, device, len(labels), args.amp)
        metrics = {"epoch": epoch, "train_loss": float(np.mean(losses)), "validation_accuracy": accuracy, "validation_macro_f1": f1}
        history.append(metrics)
        (args.run_dir / "history.json").write_text(json.dumps(history, indent=2) + "\n")
        print(json.dumps(metrics, sort_keys=True), flush=True)
        if f1 > best_f1:
            best_f1 = f1
            stalled_epochs = 0
            torch.save({
                "architecture": "bioclip_vit_b16_last_blocks",
                "model_id": MODEL_ID,
                "unfreeze_blocks": args.unfreeze_blocks,
                "labels": labels,
                "classifier_state": model.classifier.state_dict(),
                "backbone_state": model.backbone.state_dict(),
                "dataset_metadata": metadata,
                "epoch": epoch,
                "validation": metrics,
                "created_at": datetime.now(timezone.utc).isoformat(),
            }, args.run_dir / "best.pt")
        else:
            stalled_epochs += 1
            if stalled_epochs >= args.patience:
                print(json.dumps({"early_stopping": True, "best_validation_macro_f1": best_f1}), flush=True)
                break
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
