#!/usr/bin/env python3
"""Step 1: fixed train/test split and the feature spec (imputation means from training rows only).

Writes output/split.csv and output/feature_spec.json, and prints a short data summary.
"""
from __future__ import annotations

import json

import pandas as pd
from sklearn.model_selection import train_test_split

from features import (CATEGORIES, OUTPUT, SPEC_PATH, SPLIT_PATH, VIBES, feature_names, fit_imputation,
                      load_places, raw_vibes)

TEST_SIZE = 0.2
SEED = 42


def main() -> None:
    OUTPUT.mkdir(exist_ok=True)
    df = load_places(fit_only=True)
    ids = sorted(df["master_id"])
    train_ids, test_ids = train_test_split(ids, test_size=TEST_SIZE, shuffle=True, random_state=SEED)
    split = pd.DataFrame({"master_id": ids})
    split["split"] = split["master_id"].isin(set(test_ids)).map({True: "test", False: "train"})
    split.to_csv(SPLIT_PATH, index=False)

    train = df[df["master_id"].isin(set(train_ids))]
    spec = {
        "data": "data/places_v1.parquet (Google-verified operational NYC places)",
        "rows": int(len(df)), "train_rows": int(len(train_ids)), "test_rows": int(len(test_ids)),
        "split": {"method": "train_test_split on sorted master_id", "test_size": TEST_SIZE, "random_state": SEED},
        "categories": CATEGORIES, "vibes": VIBES, "feature_names": feature_names(),
        "price": "price_final / 4 (0 = free ... 4 = $$$$)",
        "imputation": fit_imputation(train),
    }
    SPEC_PATH.write_text(json.dumps(spec, indent=2) + "\n")

    v = raw_vibes(df)
    print(f"places: {len(df):,}  train: {len(train_ids):,}  test: {len(test_ids):,}")
    print("\nplaces per category:")
    print(df["activity_category"].value_counts().to_string())
    print("\nprice_final distribution (0=free .. 4=$$$$):")
    print(df["price_final"].value_counts().sort_index().to_string())
    print("\nvibe flags known (non-missing) share:")
    print((v.notna().mean().round(3)).to_string())
    print(f"\nwrote {SPEC_PATH.name}, {SPLIT_PATH.name}")


if __name__ == "__main__":
    main()
