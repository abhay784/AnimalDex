#!/bin/zsh
# Keeps this new corpus experiment separate from the prior baseline checkpoint.
set -euo pipefail
cd /Users/abhaykorlapati/Documents/ChatGPT/AnimalDex
ml/.venv/bin/python -u ml/train.py \
  --epochs 20 \
  --batch-size 32 \
  --resume-checkpoint ml/runs/openimages_hard_negatives/best.pt \
  --run-dir ml/runs/openimages_hard_negatives
