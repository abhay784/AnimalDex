#!/bin/zsh
# Resume the known-good BioCLIP checkpoint and keep the Mac awake while it runs.
set -euo pipefail
cd /Users/abhaykorlapati/Documents/ChatGPT/AnimalDex

# Documents can be managed by a file provider. Stage the 571 MB checkpoint on
# the local temporary volume before PyTorch memory-maps it, then remove that
# temporary copy after training exits.
CHECKPOINT=$(mktemp /private/tmp/animaldex-bioclip-resume.XXXXXX)
trap 'rm -f "$CHECKPOINT"' EXIT HUP INT TERM
cp -c ml/runs/bioclip_finetune_fresh/best.pt "$CHECKPOINT" 2>/dev/null \
  || cp ml/runs/bioclip_finetune_fresh/best.pt "$CHECKPOINT"

caffeinate -dimsu ml/.venv/bin/python -u ml/train_bioclip.py \
  --epochs 10 \
  --batch-size 4 \
  --unfreeze-blocks 2 \
  --patience 3 \
  --device mps \
  --run-dir ml/runs/bioclip_finetune_fresh \
  --resume-checkpoint "$CHECKPOINT"
