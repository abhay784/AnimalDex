#!/bin/zsh
# A clean run from the pretrained BioCLIP weights. The prior epoch-2 experiment
# remains in ml/runs/bioclip_finetune for a fair comparison.
set -euo pipefail
cd /Users/abhaykorlapati/Documents/ChatGPT/AnimalDex
ml/.venv/bin/python -u ml/train_bioclip.py \
  --epochs 10 \
  --batch-size 4 \
  --unfreeze-blocks 2 \
  --patience 3 \
  --device mps \
  --run-dir ml/runs/bioclip_finetune_fresh
