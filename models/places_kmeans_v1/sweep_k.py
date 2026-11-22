#!/usr/bin/env python3
"""Step 2: fit K-means for every k and category weight, on TRAINING places only.

For each category weight w in WEIGHTS and k in K_RANGE, fit with SEEDS random seeds and record:
  - fit:        train SSE (inertia) and held-out test SSE, averaged over seeds
  - separation: silhouette (10k-row train sample), Davies-Bouldin, Calinski-Harabasz (seed 0)
  - stability:  mean adjusted Rand index between the seeds' train labelings
The seed-0 model of every (w, k) is saved to output/sweep_models/ for evaluate.py.

Writes output/sweep_metrics.csv.
"""
from __future__ import annotations

import itertools
import time

import numpy as np
import pandas as pd
from joblib import dump
from sklearn.cluster import KMeans
from sklearn.metrics import (adjusted_rand_score, calinski_harabasz_score, davies_bouldin_score,
                             silhouette_score)

from features import OUTPUT, SPLIT_PATH, load_places, load_spec, transform

WEIGHTS = [1.0, 1.5, 2.0]
K_RANGE = range(2, 41)
SEEDS = [0, 1, 2, 3, 4]
N_INIT = 3
SIL_SAMPLE = 10_000
MODELS_DIR = OUTPUT / "sweep_models"


def sse(X: np.ndarray, centers: np.ndarray) -> float:
    d2 = ((X[:, None, :] - centers[None, :, :]) ** 2).sum(axis=2)
    return float(d2.min(axis=1).sum())


def main() -> None:
    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    spec = load_spec()
    df = load_places()
    split = pd.read_csv(SPLIT_PATH).set_index("master_id")["split"]
    is_train = df["master_id"].map(split).eq("train").to_numpy()
    rng = np.random.default_rng(0)
    sil_idx = rng.choice(is_train.sum(), size=min(SIL_SAMPLE, is_train.sum()), replace=False)

    rows = []
    t0 = time.time()
    for w in WEIGHTS:
        X = transform(df, spec, w)
        Xtr, Xte = X[is_train], X[~is_train]
        k1 = Xtr.mean(axis=0, keepdims=True)
        sse1_tr, sse1_te = sse(Xtr, k1), sse(Xte, k1)
        for k in K_RANGE:
            fits = [KMeans(n_clusters=k, n_init=N_INIT, random_state=s).fit(Xtr) for s in SEEDS]
            tr = [f.inertia_ for f in fits]
            te = [sse(Xte, f.cluster_centers_) for f in fits]
            ari = [adjusted_rand_score(a.labels_, b.labels_) for a, b in itertools.combinations(fits, 2)]
            m0 = fits[0]
            sizes = np.bincount(m0.labels_, minlength=k) / len(m0.labels_)
            rows.append({
                "w_cat": w, "k": k,
                "sse_train": np.mean(tr), "sse_test": np.mean(te),
                "sse_train_per_place": np.mean(tr) / len(Xtr), "sse_test_per_place": np.mean(te) / len(Xte),
                "sse_test_vs_k1": np.mean(te) / sse1_te,
                "silhouette": silhouette_score(Xtr[sil_idx], m0.labels_[sil_idx]),
                "davies_bouldin": davies_bouldin_score(Xtr, m0.labels_),
                "calinski_harabasz": calinski_harabasz_score(Xtr, m0.labels_),
                "ari_mean": np.mean(ari), "ari_min": np.min(ari),
                "smallest_cluster_share": sizes.min(), "largest_cluster_share": sizes.max(),
            })
            dump(m0, MODELS_DIR / f"w{w}_k{k}.joblib")
            print(f"w={w} k={k:2d}  test SSE/k1={rows[-1]['sse_test_vs_k1']:.3f}  "
                  f"sil={rows[-1]['silhouette']:.3f}  ARI={rows[-1]['ari_mean']:.3f}  "
                  f"[{time.time() - t0:.0f}s]", flush=True)
        rows.append({"w_cat": w, "k": 1, "sse_train": sse1_tr, "sse_test": sse1_te,
                     "sse_train_per_place": sse1_tr / len(Xtr), "sse_test_per_place": sse1_te / len(Xte),
                     "sse_test_vs_k1": 1.0, "ari_mean": 1.0, "ari_min": 1.0,
                     "smallest_cluster_share": 1.0, "largest_cluster_share": 1.0})

    out = pd.DataFrame(rows).sort_values(["w_cat", "k"])
    out.to_csv(OUTPUT / "sweep_metrics.csv", index=False, float_format="%.6g")
    print(f"wrote sweep_metrics.csv ({len(out)} rows) in {time.time() - t0:.0f}s")


if __name__ == "__main__":
    main()
