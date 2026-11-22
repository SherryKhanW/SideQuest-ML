#!/usr/bin/env python3
"""Step 4: describe and name the clusters of a (category weight, k) model; export the chosen one.

    python profile.py --w 1.5 --k 20            # write output/profiles/w1.5_k20.md for inspection
    python profile.py --w 1.5 --k 20 --final    # also export output/model_v1.json + cluster_profiles.*

The model is refit with the exact sweep settings (train rows only, n_init=3, random_state=0), so it is
the same model evaluate.py scored. Names are generated from each cluster's profile, so they are
reproducible: dominant category, price band, and the vibe flags that stand out from the average.
"""
from __future__ import annotations

import argparse
import json

import numpy as np
import pandas as pd
from sklearn.cluster import KMeans

from features import (CATEGORIES, OUTPUT, SPLIT_PATH, VIBES, feature_names, load_places, load_spec, raw_vibes,
                      transform)
from recommend import assign

PRICE_BAND = [(0.25, "Free"), (1.4, "Budget"), (2.15, "Mid-range"), (2.9, "Upscale"), (9, "Luxury")]
VIBE_TAG = {"kids": "family-friendly", "groups": "good for groups", "outdoor": "outdoor", "live_music": "live music",
            "dogs": "dog-friendly", "alcohol": "drinks", "reservable": "reservations", "open_late": "late-night"}
SHORT = {"Restaurants": "Restaurants", "Cafes & Desserts": "Cafes & desserts", "Bars & Nightlife": "Bars",
         "Parks & Outdoors": "Parks & outdoors", "Museums & Galleries": "Museums & galleries",
         "Shows & Live Events": "Shows & live events", "Attractions & Tours": "Attractions",
         "Games & Indoor Fun": "Games & indoor fun", "Sports & Fitness": "Sports & fitness",
         "Spas & Wellness": "Spas & wellness", "Libraries & Bookstores": "Libraries & bookstores",
         "Shopping": "Shopping"}


def fit(df: pd.DataFrame, spec: dict, w: float, k: int, is_train: np.ndarray) -> tuple[KMeans, np.ndarray]:
    X = transform(df, spec, w)
    km = KMeans(n_clusters=k, n_init=3, random_state=0).fit(X[is_train])
    return km, X


def profile(df: pd.DataFrame, labels: np.ndarray, k: int) -> pd.DataFrame:
    v = raw_vibes(df)
    vibe_global = v.mean()
    rows = []
    for c in range(k):
        m = labels == c
        sub = df[m]
        cat_share = sub["activity_category"].value_counts(normalize=True)
        price_mean = float(sub["price_final"].mean())
        vibe = v[m].mean()                                  # rate among places where the flag is known
        known = v[m].notna().mean()
        lift = (vibe - vibe_global).where(known >= 0.25)     # only trust flags known for >= 25% of the cluster
        tags = [VIBE_TAG[f] for f in lift.sort_values(ascending=False).index
                if pd.notna(lift[f]) and lift[f] >= 0.2 and vibe[f] >= 0.5][:2]
        top_cat = cat_share.index[0]
        if cat_share.iloc[0] >= 0.8 or len(cat_share) == 1:
            what = SHORT[top_cat]
        else:
            what = f"{SHORT[top_cat]} + {SHORT[cat_share.index[1]].lower()}"
        band = next(lbl for hi, lbl in PRICE_BAND if price_mean < hi)
        name = f"{band} {what[0].lower() + what[1:]}" if band != "Free" else f"Free {what[0].lower() + what[1:]}"
        name = name[0].upper() + name[1:]
        if tags:
            name += " · " + ", ".join(tags)
        top_rated = sub.assign(score=sub["rating"].fillna(0) * np.log1p(sub["rating_count"].fillna(0)))
        rows.append({
            "cluster": c, "name": name, "places": int(m.sum()), "share": float(m.mean()),
            "categories": "; ".join(f"{k_} {p:.0%}" for k_, p in cat_share.head(3).items()),
            "price_mean": round(price_mean, 2),
            "price_mix": "; ".join(f"{int(p)}:{s:.0%}" for p, s in
                                   sub["price_final"].value_counts(normalize=True).sort_index().items()),
            **{f"vibe_{f}": None if pd.isna(vibe[f]) else round(float(vibe[f]), 2) for f in VIBES},
            "top_types": "; ".join(sub["subcategory_label"].fillna(sub["subcategory"]).value_counts().head(4).index),
            "boroughs": "; ".join(f"{b} {p:.0%}" for b, p in sub["borough"].value_counts(normalize=True).head(3).items()),
            "examples": "; ".join(top_rated.sort_values("score", ascending=False)["name"].head(3)),
        })
    out = pd.DataFrame(rows)
    # make names unique by appending the top place type where two clusters share a name
    dup = out["name"].duplicated(keep=False)
    out.loc[dup, "name"] = out.loc[dup].apply(lambda r: f"{r['name']} ({r['top_types'].split('; ')[0]})", axis=1)
    return out


def to_markdown(prof: pd.DataFrame, w: float, k: int) -> str:
    lines = [f"# Cluster profiles: category weight {w}, k = {k}\n",
             "Vibe rates are among places where Google reports the flag. Price 0 = free … 4 = $$$$.\n",
             "| # | name | places | share | categories | avg price | top types | examples |",
             "|---|---|---:|---:|---|---:|---|---|"]
    for _, r in prof.sort_values("places", ascending=False).iterrows():
        lines.append(f"| {r['cluster']} | {r['name']} | {r['places']:,} | {r['share']:.1%} | {r['categories']} | "
                     f"{r['price_mean']} | {r['top_types']} | {r['examples']} |")
    return "\n".join(lines) + "\n"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--w", type=float, required=True)
    ap.add_argument("--k", type=int, required=True)
    ap.add_argument("--final", action="store_true", help="export this as the v1 model")
    a = ap.parse_args()

    spec = load_spec()
    df = load_places()
    split = pd.read_csv(SPLIT_PATH).set_index("master_id")["split"]
    is_train = df["master_id"].map(split).eq("train").to_numpy()
    km, X = fit(df, spec, a.w, a.k, is_train)
    labels = assign(X, km.cluster_centers_)
    prof = profile(df, labels, a.k)

    (OUTPUT / "profiles").mkdir(exist_ok=True)
    md = to_markdown(prof, a.w, a.k)
    (OUTPUT / "profiles" / f"w{a.w}_k{a.k}.md").write_text(md)
    print(md)

    if a.final:
        model = {
            "model": "places_kmeans_v1", "algorithm": "KMeans (scikit-learn), Lloyd, n_init=3, random_state=0",
            "fit_on": f"{int(is_train.sum())} training places (output/split.csv)",
            "w_cat": a.w, "k": a.k, "feature_names": feature_names(),
            # + 0.0 turns -0.0 into 0.0 so the file is byte-identical across runs
            "centroids": [[round(float(x), 6) + 0.0 for x in row] for row in km.cluster_centers_],
            "clusters": [{"id": int(r["cluster"]), "name": r["name"], "places": int(r["places"])}
                         for _, r in prof.sort_values("cluster").iterrows()],
            "feature_spec": "output/feature_spec.json (category list, vibe list, imputation means)",
        }
        (OUTPUT / "model_v1.json").write_text(json.dumps(model, indent=2) + "\n")
        prof.to_csv(OUTPUT / "cluster_profiles.csv", index=False)
        (OUTPUT / "cluster_profiles.md").write_text(md)
        pd.DataFrame({"master_id": df["master_id"], "cluster": labels}).to_csv(OUTPUT / "place_clusters.csv", index=False)
        print("exported model_v1.json, cluster_profiles.md/.csv, place_clusters.csv")


if __name__ == "__main__":
    main()
