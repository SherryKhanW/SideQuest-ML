#!/usr/bin/env python3
"""Step 3: score every (category weight, k) model on how useful it is for recommending.

Adds to the fit / separation / stability metrics from sweep_k.py:

  proxy_recall10     Held-out places as proxy queries (1,000 test places). Overlap of the top 10 found
                     inside the query's nearest cluster with the exhaustive top 10 over all training
                     places, divided by 10. Same idea as the earlier parks experiment.
  pool_share         Average share of the catalog searched when only the nearest cluster is used
                     (lower = less work than exhaustive search).
  filtered_recall10  Realistic user queries, run through the same decision logic as recommend.py:
                       - plain: every borough (+ "any") x max price 0-4 x category              (360)
                       - with a vibe toggle: "any" borough x max price 1-4 x category x toggle   (288)
                     Hard filters applied. Overlap of the top 10 found in the query's nearest cluster(s)
                     (recommend.cluster_pool) with the top 10 of the SAME ranking over ALL places that
                     pass the filters. Measures what clustering costs in recommendation quality.
  fill_rate          Share of feasible queries (>= 10 matching places exist) that the nearest cluster
                     (plus clusters tied with it) fills with >= 10 places, without further fallback.
  clusters_needed    Average clusters searched per query.
  vibe_match         Toggled queries only: share of returned places whose known flag matches the toggle
                     (e.g. outdoor seating = yes). Unknown flags count as not matching.
Writes output/evaluation_metrics.csv, output/shortlist.csv, output/plots/k_selection.png.
`python evaluate.py --report` redraws plots and the shortlist from the saved CSV without recomputing.
"""
from __future__ import annotations

import itertools

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from joblib import load

from features import (BOROUGHS, CATEGORIES, OUTPUT, SPLIT_PATH, VIBES, load_places, load_spec, query_vector,
                      raw_vibes, transform)
from recommend import (CLUSTER_TIE_BAND, VIBE_TOGGLES, assign, centroid_distances, cluster_pool, expressed_mask,
                       hard_filter, nearest_order, quality, rank)

PROXY_QUERIES = 1000
TOP = 10
MODELS_DIR = OUTPUT / "sweep_models"
PLOTS = OUTPUT / "plots"


def topk(X: np.ndarray, q: np.ndarray, idx: np.ndarray, k: int = TOP) -> set:
    if len(idx) == 0:
        return set()
    d = ((X[idx] - q) ** 2).sum(axis=1)
    return set(idx[np.argsort(d, kind="stable")[:k]].tolist())


def main() -> None:
    import sys
    if "--report" not in sys.argv:
        compute()
    report()


def compute() -> None:
    PLOTS.mkdir(parents=True, exist_ok=True)
    spec = load_spec()
    df = load_places(fit_only=True)
    split = pd.read_csv(SPLIT_PATH).set_index("master_id")["split"]
    is_train = df["master_id"].map(split).eq("train").to_numpy()
    train_idx, test_idx = np.flatnonzero(is_train), np.flatnonzero(~is_train)
    rng = np.random.default_rng(0)
    proxy = rng.choice(test_idx, size=PROXY_QUERIES, replace=False)

    plain = [(b, p, c, None) for b, p, c in itertools.product(BOROUGHS + ["any"], range(5), CATEGORIES)]
    toggled = [("any", p, c, t) for p, c, t in itertools.product(range(1, 5), CATEGORIES, VIBE_TOGGLES)]
    grid = plain + toggled
    masks = {g: hard_filter(df, g[0], g[1], [g[2]]) for g in grid}
    feasible = [g for g in grid if masks[g].sum() >= TOP]
    ids = df["master_id"].to_numpy()
    qual = quality(df, float(df["rating"].mean()))
    vib = raw_vibes(df)
    toggle_flags = {t: list(v) for t, v in VIBE_TOGGLES.items()}

    sweep = pd.read_csv(OUTPUT / "sweep_metrics.csv")
    rows = []
    for w in sorted(sweep["w_cat"].unique()):
        X = transform(df, spec, w)
        qs = {}
        for g in feasible:
            vibes = dict(VIBE_TOGGLES[g[3]]) if g[3] else {}
            q, m = query_vector([g[2]], g[1], spec, w, vibes), expressed_mask(vibes)
            qs[g] = (q, m, rank(X, q, m, qual, np.flatnonzero(masks[g]), ids)[:TOP])   # exhaustive top 10
        for k in sorted(sweep.loc[(sweep["w_cat"] == w) & (sweep["k"] > 1), "k"]):
            centers = load(MODELS_DIR / f"w{w}_k{k}.joblib").cluster_centers_
            labels = assign(X, centers)
            train_labels = labels[train_idx]

            # proxy queries (unfiltered, full vectors), catalog = training places
            rec, pool = [], []
            for i in proxy:
                q = X[i]
                c = nearest_order(q, centers)[0]
                in_c = train_idx[train_labels == c]
                rec.append(len(topk(X, q, in_c) & topk(X, q, train_idx)) / TOP)
                pool.append(len(in_c) / len(train_idx))

            # realistic filtered user queries through the recommend.py logic, catalog = all places
            frec, filled, needed, vmatch = [], [], [], []
            for g in feasible:
                q, m, exhaustive = qs[g]
                dists = centroid_distances(q, centers, m)
                pool_mask, used = cluster_pool(labels, masks[g], dists, TOP)
                tied = dists <= dists.min() + CLUSTER_TIE_BAND
                filled.append((masks[g] & np.isin(labels, np.flatnonzero(tied))).sum() >= TOP)
                needed.append(len(used))
                got = rank(X, q, m, qual, np.flatnonzero(pool_mask), ids)[:TOP]
                frec.append(len(set(got) & set(exhaustive)) / TOP)
                if g[3]:
                    flags = vib.iloc[got][toggle_flags[g[3]]]
                    vmatch.append(float((flags == 1).all(axis=1).mean()))

            rows.append({"w_cat": w, "k": k, "proxy_recall10": np.mean(rec), "pool_share": np.mean(pool),
                         "filtered_recall10": np.mean(frec), "fill_rate": np.mean(filled),
                         "clusters_needed": np.mean(needed), "vibe_match": np.mean(vmatch)})
            r = rows[-1]
            print(f"w={w} k={k:2d}  proxy@10={r['proxy_recall10']:.3f}  filtered@10={r['filtered_recall10']:.3f}  "
                  f"fill={r['fill_rate']:.3f}  clusters={r['clusters_needed']:.2f}  vibe={r['vibe_match']:.3f}",
                  flush=True)

    ev = sweep.merge(pd.DataFrame(rows), on=["w_cat", "k"], how="left")
    ev.to_csv(OUTPUT / "evaluation_metrics.csv", index=False, float_format="%.6g")
    print(f"\nfeasible user queries: {len(feasible)} of {len(grid)} "
          f"({sum(g[3] is None for g in feasible)} plain, {sum(g[3] is not None for g in feasible)} with a toggle)")


# Selection rule (documented in README):
#   k >= MIN_K          below 12 clusters, k-means merges whole categories, so a cluster adds nothing to the
#                       category the user already picked
#   ari_mean >= 0.85    the same clusters come back across random seeds
#   smallest >= 0.2%    no near-empty cluster
#   then the highest filtered_recall10 (least recommendation quality lost to clustering)
MIN_K, MIN_ARI, MIN_SHARE = 12, 0.85, 0.002


def report() -> None:
    PLOTS.mkdir(parents=True, exist_ok=True)
    ev = pd.read_csv(OUTPUT / "evaluation_metrics.csv")
    panels = [("sse_test_vs_k1", "Held-out SSE / SSE(k=1)  (elbow)"), ("silhouette", "Silhouette (higher better)"),
              ("ari_mean", "Stability: mean ARI across seeds"), ("filtered_recall10", "User-query recall@10 vs exhaustive"),
              ("vibe_match", "Toggled queries: deck matches the vibe"), ("fill_rate", "Nearest cluster(s) fill a deck")]
    fig, axes = plt.subplots(2, 3, figsize=(16, 9))
    for ax, (col, title) in zip(axes.flat, panels):
        for w, g in ev[ev["k"] > 1].groupby("w_cat"):
            ax.plot(g["k"], g[col], marker=".", label=f"category weight {w}")
        ax.axvline(MIN_K, color="grey", ls=":", lw=1)
        ax.set_title(title)
        ax.set_xlabel("k")
        ax.grid(alpha=0.3)
    axes.flat[0].legend()
    fig.tight_layout()
    fig.savefig(PLOTS / "k_selection.png", dpi=120)

    cand = ev[(ev["k"] >= MIN_K) & (ev["ari_mean"] >= MIN_ARI) & (ev["smallest_cluster_share"] >= MIN_SHARE)]
    cand = cand.sort_values(["filtered_recall10", "silhouette"], ascending=False)
    cols = ["w_cat", "k", "filtered_recall10", "vibe_match", "fill_rate", "clusters_needed", "proxy_recall10",
            "pool_share", "silhouette", "ari_mean", "sse_test_vs_k1", "smallest_cluster_share", "largest_cluster_share"]
    cand[cols].to_csv(OUTPUT / "shortlist.csv", index=False, float_format="%.4g")
    print(f"shortlist (k >= {MIN_K}, ARI >= {MIN_ARI}, smallest cluster >= {MIN_SHARE:.1%}), best user-query recall first:")
    print(cand[cols].head(10).to_string(index=False, float_format=lambda x: f"{x:.3f}"))
    best = cand.iloc[0]
    print(f"\nselected: category weight {best['w_cat']}, k = {int(best['k'])}")


if __name__ == "__main__":
    main()
