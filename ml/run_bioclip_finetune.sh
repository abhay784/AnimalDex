#!/bin/zsh
set -euo pipefail
cd /Users/abhaykorlapati/Documents/ChatGPT/AnimalDex
ml/.venv/bin/python -u ml/train_bioclip.py \
  --epochs 10 \
  --batch-size 4 \
  --unfreeze-blocks 2 \
  --patience 3 \
  --device mps \
  --resume-checkpoint ml/runs/bioclip_finetune/best.pt \
  --run-dir ml/runs/bioclip_finetune
