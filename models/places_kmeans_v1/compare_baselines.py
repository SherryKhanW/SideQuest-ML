#!/usr/bin/env python3
"""Compare the v1 model (k = 25) with two dumb baselines on the same realistic user queries.

  popularity  hard filters, then the most-reviewed places first (what a plain "top places" list does)
  k = 1       hard filters, then the same ranking as v1 over every place (no clustering; exhaustive)
  v1 (k=25)   hard filters, nearest cluster(s), the same ranking

Queries: the 575 feasible queries from evaluate.py (every borough/any x price 0-4 x category, plus
"any" x price 1-4 x category x each vibe toggle). Writes output/baseline_comparison.csv/.md.
"""
from __future__ import annotations

import itertools
import json
import time

import numpy as np
import pandas as pd

from features import BOROUGHS, CATEGORIES, OUTPUT, raw_vibes
from recommend import MODEL_PATH, VIBE_TOGGLES, Recommender, hard_filter

TOP = 10
REPEATS = 3


def popularity_deck(rec: Recommender, borough, max_price, cats, n=TOP):
    ok = np.flatnonzero(hard_filter(rec.places, borough, max_price, cats))
    cnt = rec.places["rating_count"].fillna(0).to_numpy()[ok]
    order = ok[np.lexsort((rec.places["master_id"].to_numpy()[ok], -cnt))]
    deck, names = [], set()
    for i in order:
        nm = rec.places.at[i, "name"].strip().lower()
        if nm not in names:
            names.add(nm)
            deck.append(int(i))
        if len(deck) == n:
            break
    return deck


def k1_recommender(v1: Recommender) -> Recommender:
    """Same data, ranking and filters as v1, but a single cluster (= exhaustive search)."""
    center = v1.X.mean(axis=0, keepdims=True)
    return Recommender(center, v1.w_cat, ["all places"], v1.spec, v1.places, v1.X,
                       np.zeros(len(v1.places), dtype=int), v1.qual)


def deck_ids(rec: Recommender, out: dict) -> list[int]:
    key = rec.places["name"]
    return [int(rec.places.index[(key == c["name"]) & (rec.places["maps_uri"] == c["maps_uri"])][0])
            for c in out["deck"]]


def main() -> None:
    v1 = Recommender.load(MODEL_PATH)
    k1 = k1_recommender(v1)
    places = v1.places
    vib = raw_vibes(places)
    bayes = v1.qual * 1.5 + 3.5
    k = len(v1.centers)

    plain = [(b, p, c, None) for b, p, c in itertools.product(BOROUGHS + ["any"], range(5), CATEGORIES)]
    toggled = [("any", p, c, t) for p, c, t in itertools.product(range(1, 5), CATEGORIES, VIBE_TOGGLES)]
    queries = [g for g in plain + toggled if hard_filter(places, g[0], g[1], [g[2]]).sum() >= TOP]

    rows = []
    for g in queries:
        b, p, c, t = g
        toggles = [t] if t else []
        res = {}
        for name, fn in [("popularity", lambda: popularity_deck(v1, b, p, [c])),
                         ("k=1 (no clustering)", lambda: deck_ids(k1, k1.recommend(b, p, [c], toggles))),
                         (f"v1 (k={k})", lambda: deck_ids(v1, v1.recommend(b, p, [c], toggles)))]:
            times = []
            for _ in range(REPEATS):
                t0 = time.perf_counter()
                d = fn()
                times.append(time.perf_counter() - t0)
            res[name] = (d, float(np.median(times)))
        pool = int(hard_filter(places, b, p, [c]).sum())
        ref = set(res["k=1 (no clustering)"][0])
        for name, (d, sec) in res.items():
            flags = VIBE_TOGGLES[t] if t else {}
            vm = float((vib.iloc[d][list(flags)] == 1).all(axis=1).mean()) if t else np.nan
            v1_pool = sum(int(((v1.labels == cl) & hard_filter(places, b, p, [c])).sum())
                          for cl in [x["id"] for x in v1.recommend(b, p, [c], toggles)["clusters_used"]]) \
                if name.startswith("v1") else pool
            rows.append({
                "model": name, "borough": b, "max_price": p, "category": c, "toggle": t or "",
                "ms": sec * 1000, "places_scored": v1_pool if name.startswith("v1") else pool,
                "overlap_with_exhaustive": len(set(d) & ref) / TOP,
                "avg_smoothed_rating": float(bayes[d].mean()),
                "median_review_count": float(np.median(places["rating_count"].fillna(0).to_numpy()[d])),
                "hidden_gems": float(((places["rating"].to_numpy()[d] >= 4.6) &
                                      (places["rating_count"].fillna(0).to_numpy()[d] < 500)).mean()),
                "distinct_types": len(set(places["subcategory"].to_numpy()[d])),
                "vibe_match": vm,
                "price_at_budget": float((places["price_final"].to_numpy()[d] == p).mean()),
                "explanation": name.startswith("v1"),
                "deck": json.dumps([places.at[i, "master_id"] for i in d]),
            })

    df = pd.DataFrame(rows)
    df.drop(columns="deck").to_csv(OUTPUT / "baseline_comparison_queries.csv", index=False, float_format="%.5g")
    coverage = df.groupby("model")["deck"].apply(lambda s: len({x for d in s for x in json.loads(d)}))
    summary = df.groupby("model", sort=False).agg(
        ms_median=("ms", "median"), places_scored=("places_scored", "mean"),
        overlap_with_exhaustive=("overlap_with_exhaustive", "mean"),
        avg_smoothed_rating=("avg_smoothed_rating", "mean"), median_review_count=("median_review_count", "median"),
        hidden_gems=("hidden_gems", "mean"), distinct_types=("distinct_types", "mean"),
        vibe_match=("vibe_match", "mean"), price_at_budget=("price_at_budget", "mean"))
    summary["distinct_places_shown"] = coverage
    summary.to_csv(OUTPUT / "baseline_comparison.csv", float_format="%.4g")
    print(f"{len(queries)} queries ({sum(q[3] is None for q in queries)} plain, "
          f"{sum(q[3] is not None for q in queries)} with a vibe toggle)\n")
    print(summary.to_string(float_format=lambda x: f"{x:.3f}"))


if __name__ == "__main__":
    main()
