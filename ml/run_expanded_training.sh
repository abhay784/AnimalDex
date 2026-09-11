#!/bin/zsh
set -euo pipefail
cd /Users/abhaykorlapati/Documents/ChatGPT/AnimalDex
ml/.venv/bin/python -u ml/fetch_inaturalist.py --per-class 400 --negative-per-iconic-taxon 200 --workers 6
ml/.venv/bin/python ml/make_splits.py --minimum-per-class 400 --exclude-underfilled
ml/.venv/bin/python -u ml/train.py --epochs 20 --batch-size 32
