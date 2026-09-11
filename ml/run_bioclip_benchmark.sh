#!/bin/zsh
set -euo pipefail
cd /Users/abhaykorlapati/Documents/ChatGPT/AnimalDex
ml/.venv/bin/python -u ml/benchmark_bioclip.py \
  --split test \
  --batch-size 8 \
  --device cpu \
  --output ml/runs/bioclip_zero_shot/test_report.json
