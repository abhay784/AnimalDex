"""Shared MobileNetV3 model construction and manifest dataset."""
from __future__ import annotations

import json
import warnings
from collections import defaultdict
from pathlib import Path
from typing import Callable

import torch
from PIL import Image
from torch import nn
from torch.utils.data import Dataset
from torchvision.models import MobileNet_V3_Small_Weights, mobilenet_v3_small

try:
    from .labels import ROOT
except ImportError:  # `python ml/train.py`
    from labels import ROOT

IMAGE_SIZE = 224
IMAGENET_MEAN = (0.485, 0.456, 0.406)
IMAGENET_STD = (0.229, 0.224, 0.225)


def make_model(class_count: int, pretrained: bool) -> nn.Module:
    weights = MobileNet_V3_Small_Weights.IMAGENET1K_V1 if pretrained else None
    model = mobilenet_v3_small(weights=weights)
    # `classifier[3]` is the ImageNet 1000-class head. The feature extractor
    # stays pretrained while this project-specific head learns Dex labels.
    model.classifier[3] = nn.Linear(model.classifier[3].in_features, class_count)
    return model


def training_transform() -> Callable:
    from torchvision import transforms
    return transforms.Compose([
        transforms.RandomResizedCrop(IMAGE_SIZE, scale=(0.55, 1.0)),
        transforms.RandomHorizontalFlip(),
        transforms.ColorJitter(brightness=0.2, contrast=0.2, saturation=0.15),
        transforms.ToTensor(),
        transforms.Normalize(IMAGENET_MEAN, IMAGENET_STD),
    ])


def evaluation_transform() -> Callable:
    from torchvision import transforms
    return transforms.Compose([
        transforms.Resize(256),
        transforms.CenterCrop(IMAGE_SIZE),
        transforms.ToTensor(),
        transforms.Normalize(IMAGENET_MEAN, IMAGENET_STD),
    ])


class ManifestDataset(Dataset):
    def __init__(self, manifest: Path, labels: list[str], transform: Callable):
        self.rows = [json.loads(line) for line in manifest.read_text().splitlines() if line.strip()]
        self.index_for = {label: index for index, label in enumerate(labels)}
        self.transform = transform
        if not self.rows:
            raise ValueError(f"empty split: {manifest}")
        missing = {row["label"] for row in self.rows} - self.index_for.keys()
        if missing:
            raise ValueError(f"unknown labels in {manifest}: {sorted(missing)}")
        self.indices_for_label: dict[str, list[int]] = defaultdict(list)
        for index, row in enumerate(self.rows):
            self.indices_for_label[row["label"]].append(index)
        self.unreadable_indices: set[int] = set()

    def __len__(self) -> int:
        return len(self.rows)

    def __getitem__(self, index: int) -> tuple[torch.Tensor, int]:
        """Load one sample, replacing a malformed download within its class.

        The remote corpus occasionally contains files with a JPEG extension
        that Pillow cannot decode. A single bad file must not throw away a
        multi-hour epoch; choosing another sample from the same class preserves
        the requested target while keeping the failure visible as a warning.
        """
        original = self.rows[index]
        same_label = self.indices_for_label[original["label"]]
        start = same_label.index(index)
        candidates = same_label[start:] + same_label[:start]

        for candidate in candidates:
            if candidate in self.unreadable_indices:
                continue
            row = self.rows[candidate]
            try:
                with Image.open(ROOT / row["path"]) as image:
                    tensor = self.transform(image.convert("RGB"))
            except OSError as error:
                self.unreadable_indices.add(candidate)
                warnings.warn(
                    f"Skipping unreadable training image {row['path']}: {error}",
                    RuntimeWarning,
                    stacklevel=2,
                )
                continue
            return tensor, self.index_for[row["label"]]

        raise RuntimeError(f"no readable images remain for label {original['label']}")
