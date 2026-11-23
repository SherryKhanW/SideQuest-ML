#!/usr/bin/env bash
# Reproduce the v1 model end to end from data/places_v1.parquet (about 20 minutes, mostly evaluate.py).
set -euo pipefail
cd "$(dirname "$0")"
PY="${PYTHON:-../../.venv/bin/python}"
"$PY" prepare.py                          # split + feature spec
"$PY" sweep_k.py                          # KMeans for k=2..40 x category weight 1.0/1.5/2.0 x 5 seeds
"$PY" evaluate.py                         # recommendation-usefulness metrics, plots, shortlist
"$PY" profile.py --w 1.5 --k 25 --final   # chosen model -> output/model_v1.json + cluster profiles
"$PY" demo_queries.py                     # dummy user inputs through the decision logic
"$PY" category_config.py                    # per-category types, filters, card fields -> output/category_filters.json
"$PY" group.py                              # example rooms -> one shared deck each
"$PY" compare_group.py                      # group decks vs naive approaches, 500 rooms (~7 min)
"$PY" compare_baselines.py                  # v1 vs popularity list vs k=1
"$PY" simulate_group_swipes.py              # v2 preview, synthetic groups
"$PY" export_for_app.py                     # package for the app -> output/app/
