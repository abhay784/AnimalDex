#!/usr/bin/env python3
"""Export a validated MobileNetV3 checkpoint as an iOS 17 Core ML classifier."""
from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

# coremltools 8 currently imports ``distutils.version``. Python 3.12+ removed
# that standard-library module, while setuptools retains a compatible private
# copy. Alias it before importing coremltools so exporting remains usable in a
# modern virtual environment.
try:
    import distutils  # type: ignore[import-not-found]  # noqa: F401
except ModuleNotFoundError:
    from setuptools import _distutils

    sys.modules["distutils"] = _distutils
    sys.modules["distutils.version"] = _distutils.version

import coremltools as ct
import torch
from torch import nn

try:
    from .labels import ROOT, model_labels
    from .model import IMAGENET_MEAN, IMAGENET_STD, IMAGE_SIZE, make_model
except ImportError:  # `python ml/export_coreml.py`
    from labels import ROOT, model_labels
    from model import IMAGENET_MEAN, IMAGENET_STD, IMAGE_SIZE, make_model

OUTPUT = ROOT / "AnimalDex" / "Resources" / "Models" / "AnimalDexSpeciesClassifier.mlmodel"


class ImageNetClassifier(nn.Module):
    """Keep ImageNet normalization in the graph; Core ML only scales RGB bytes."""
    def __init__(self, classifier: nn.Module):
        super().__init__()
        self.classifier = classifier
        self.register_buffer("mean", torch.tensor(IMAGENET_MEAN).view(1, 3, 1, 1))
        self.register_buffer("std", torch.tensor(IMAGENET_STD).view(1, 3, 1, 1))

    def forward(self, image: torch.Tensor) -> torch.Tensor:
        return self.classifier((image - self.mean) / self.std)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()

    checkpoint = torch.load(args.checkpoint, map_location="cpu", weights_only=False)
    labels: list[str] = checkpoint["labels"]
    committed_labels = model_labels()
    if not labels or labels[-1] != "__not_wildlife__" or any(label not in committed_labels for label in labels):
        raise ValueError("checkpoint labels do not match the committed AnimalDex model contract")
    expected_order = [label for label in committed_labels if label in set(labels)]
    if labels != expected_order:
        raise ValueError("checkpoint labels are not in stable AnimalDex catalog order")
    classifier = make_model(len(labels), pretrained=False)
    classifier.load_state_dict(checkpoint["model_state"])
    wrapper = ImageNetClassifier(classifier).eval()
    example = torch.rand(1, 3, IMAGE_SIZE, IMAGE_SIZE)
    traced = torch.jit.trace(wrapper, example)

    model = ct.convert(
        traced,
        # A standard neural-network model is portable across supported Python
        # runtimes and compiles to the same iOS Core ML runtime. `mlprogram`
        # packaging depends on optional native Python binaries unavailable on
        # some current macOS/Python combinations.
        convert_to="neuralnetwork",
        minimum_deployment_target=ct.target.iOS14,
        inputs=[ct.ImageType(
            name="image",
            shape=example.shape,
            scale=1 / 255.0,
            color_layout=ct.colorlayout.RGB,
        )],
        classifier_config=ct.ClassifierConfig(class_labels=labels),
    )
    model.author = "AnimalDex"
    model.short_description = "MobileNetV3-Small animal species classifier for AnimalDex"
    model.version = "1"
    model.user_defined_metadata["animaldex.architecture"] = "MobileNetV3-Small"
    model.user_defined_metadata["animaldex.class_count"] = str(len(labels))
    model.user_defined_metadata["animaldex.labels.sha256"] = hashlib.sha256("\n".join(labels).encode()).hexdigest()
    model.user_defined_metadata["animaldex.manifest.sha256"] = checkpoint["dataset_metadata"]["manifest_sha256"]
    model.user_defined_metadata["animaldex.validation.macro_f1"] = str(checkpoint["validation"]["validation_macro_f1"])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    model.save(args.output)
    try:
        displayed_path = args.output.relative_to(ROOT)
    except ValueError:
        displayed_path = args.output
    print(f"wrote {displayed_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
