#!/bin/zsh
# Faster laptop-friendly BioCLIP continuation: 4 parallel JPEG loaders and a
# 16-image MPS batch reduce epoch two from 9,534 to 2,384 optimizer steps.
set -euo pipefail
cd /Users/abhaykorlapati/Documents/ChatGPT/AnimalDex

# Keep the checkpoint on the local temporary volume.  This avoids occasional
# file-provider timeouts from Documents and lets torch memory-map it quickly.
CHECKPOINT=$(mktemp /private/tmp/animaldex-bioclip-resume.XXXXXX)
trap 'rm -f "$CHECKPOINT"' EXIT HUP INT TERM
cp -c ml/runs/bioclip_finetune_fresh/best.pt "$CHECKPOINT" 2>/dev/null \
  || cp ml/runs/bioclip_finetune_fresh/best.pt "$CHECKPOINT"

caffeinate -dimsu ml/.venv/bin/python -u ml/train_bioclip.py \
  --epochs 10 \
  --batch-size 16 \
  --workers 4 \
  --prefetch-factor 2 \
  --unfreeze-blocks 1 \
  --patience 3 \
  --log-interval 50 \
  --device mps \
  --run-dir ml/runs/bioclip_finetune_fresh \
  --resume-checkpoint "$CHECKPOINT"
