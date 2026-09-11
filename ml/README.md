# AnimalDex custom species classifier

This pipeline trains a **MobileNetV3-Small convolutional neural network** for
the AnimalDex catalog, then exports it as a Core ML image classifier for the
iOS app. It is intentionally separate from the shipping Apple Vision baseline:
the app continues to work without this model, and automatically adopts it only
when the exported file is bundled.

## What the model identifies

- The 138 `labelKey` values in `AnimalDex/Resources/species_catalog.json`,
  including **human** (`Homo sapiens`) as a real AnimalDex species.
- `__not_wildlife__`, a required negative class. This prevents a closed-set
  classifier from confidently naming an animal for every input, including
  meals, people, landscapes, or a blank frame.

Each model label is the app's catalog key, not a display name. That makes the
classifier-to-Dex mapping a direct contract with no mutable lookup table.

## Setup

Use CPython 3.10 or 3.11 and a virtual environment rather than the system
Python. The Core ML converter does not yet support every newer Python release:

```bash
python3.11 -m venv ml/.venv
ml/.venv/bin/python -m pip install --upgrade pip
ml/.venv/bin/python -m pip install -r ml/requirements.txt
```

## Build the training corpus

The downloader requests research-grade iNaturalist observations for every
catalog species, then uses licensed casual observations only for species that
cannot reach the requested count. It records each asset's URL, observation ID,
and license in a manifest, and stores images outside Git:

```bash
python ml/fetch_inaturalist.py --per-class 400 --negative-per-iconic-taxon 200 --workers 6
```

The command adds research-grade Plants and Fungi as licensed negatives. Add
the Open Images hard-negative subset, which mixes food, indoor objects,
vehicles/text, and built scenes while excluding annotated people and animals:

```bash
python ml/fetch_openimages_negatives.py --per-category 250 --workers 8
```

This source is stored in a separate manifest with its Open Images ID, source
URL, category, and CC-BY-2.0 license. The validation report then breaks the
negative false-accept rate down by category. Add consented iPhone failure cases
and camera-blur photos under `ml/data/raw/__not_wildlife__/` before a release.
Do not add photos without a documented license or consent. Then create deterministic,
observation-grouped train/validation/test splits:

```bash
python ml/make_splits.py
```

The split is grouped by iNaturalist observation, so two photos from one sighting
cannot land in both training and evaluation. A random image-level split would
overstate accuracy by leaking near-duplicate images.

For a production candidate, train only balanced classes. This keeps weak data
from teaching the softmax that a poorly represented animal is equally reliable:

```bash
python ml/make_splits.py --minimum-per-class 400 --exclude-underfilled
```

This removes underfilled labels from the **model output** while keeping their
AnimalDex entries and existing catches intact. The exported Core ML model can
therefore recognize only the species it has enough data to support.

## Train, evaluate, and export

```bash
python ml/train.py --epochs 20 --batch-size 32 --run-dir ml/runs/openimages_hard_negatives
python ml/evaluate.py --checkpoint ml/runs/openimages_hard_negatives/best.pt
python ml/export_coreml.py --checkpoint ml/runs/openimages_hard_negatives/best.pt
```

The exporter writes `AnimalDex/Resources/Models/AnimalDexSpeciesClassifier.mlmodel`.
Xcode compiles it into `mlmodelc` as part of the application build. Do not
replace the runtime model based on overall accuracy alone: inspect macro-F1,
the negative-class false-accept rate, and the confusion matrix for local species
before promoting a checkpoint.

To resume an interrupted run from its best checkpoint without repeating its
completed epochs, pass that checkpoint explicitly:

```bash
python ml/train.py --epochs 20 --run-dir ml/runs/openimages_hard_negatives \
  --resume-checkpoint ml/runs/openimages_hard_negatives/best.pt
```

## Dataset and release policy

- Keep `ml/data/` and `ml/runs/` out of Git. The manifest is reproducible
  provenance, but raw photos are large and each remains subject to its license.
- Train only from a frozen `manifest.jsonl` and record its SHA-256 with the
  checkpoint. That makes every model release traceable to its data.
- Never treat high offline accuracy as field validation. Hold out locations and
  contributors where possible, then test on real iPhone camera photos before
release.

## BioCLIP comparison

Run a separate zero-shot benchmark on the exact same held-out split:

```bash
python ml/benchmark_bioclip.py --split test --device cpu
```

It uses BioCLIP's scientific-name candidates for each retained AnimalDex
species and explicit non-wildlife candidates for the negative class. It does
not replace the MobileNet model or alter training data; compare its report with
the MobileNet test report before deciding whether to fine-tune or distill it.

To fine-tune BioCLIP without updating its complete ViT-B/16 image tower, train
the classifier head and the final two vision blocks. This remains a laptop-sized
experiment; keep the batch size at four and use early stopping:

```bash
python ml/train_bioclip.py --epochs 10 --batch-size 4 --unfreeze-blocks 2 --device mps
```

Resume an interrupted BioCLIP run from its saved best checkpoint:

```bash
python ml/train_bioclip.py --epochs 10 --batch-size 4 --unfreeze-blocks 2 --device mps \
  --resume-checkpoint ml/runs/bioclip_finetune/best.pt
```

Use a distinct `--run-dir` for a fresh experiment so it does not overwrite a
checkpoint you may want to compare.
