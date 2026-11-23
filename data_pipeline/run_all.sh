#!/usr/bin/env bash
# Rebuild the NYC places dataset end to end.
# Paid step (Google) is OFF unless you pass --google; it reuses data/raw/google/places.jsonl otherwise.
set -euo pipefail
cd "$(dirname "$0")"

if [[ "${1:-}" == "--google" ]]; then
  # Hard cap counts every call ever logged in data/raw/google/calls.jsonl. Raise it deliberately.
  python3 google_harvest.py --max-calls "${2:-7000}"
fi

duckdb nyc.duckdb < nyc_places_overture.sql      # Overture places for the NYC area        (~15 s)
duckdb nyc.duckdb < build_nyc_activities.sql     # buckets, borough clip, cleaning, parks   (~3 s)
./fetch_open_data.sh                             # free NYC datasets -> data/raw/<source>/   (~10 min; skips what's on disk)
duckdb < stage_open_data.sql                     # -> data/staging/*.parquet                 (~3 s)
duckdb nyc.duckdb < stage_google.sql             # Google raw JSON -> data/staging/google_places.parquet (~10 s)
duckdb nyc.duckdb < build_master.sql             # link Google <-> Overture <-> NYC Parks    (~4 s)
duckdb nyc.duckdb < enrich_master.sql            # transit, inspections, OSM, Wikidata, ...  (~6 s)
# data/places_v1.parquet in git is a FROZEN v1 snapshot (the rows the model was fitted on). To add new columns
# without changing it: build a fresh extract to a temp path, then add_columns_to_places_v1.sql (see DATA.md).
# duckdb < build_places_v1.sql                   # full rebuild of the extract (only for a new model version)
echo "Done: nyc_places_enriched.parquet, nyc_events.parquet"
