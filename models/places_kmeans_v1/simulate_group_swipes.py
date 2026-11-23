#!/usr/bin/env python3
"""SIMULATION, not evidence: would clusters help a group of 5 find a match faster once we learn from swipes (v2)?

Synthetic groups. Each group has a hidden shared taste over the 8 vibe flags and price; each member is that
taste plus personal noise. A member likes a place with probability
    sigmoid(bias + taste . (vibe - 0.5) * 2  - price_dislike * price  + 0.8 * quality_z)
using the same place features the model sees (unknown flags = category mean). A "match" is a card that at
least 4 of 5 members swipe right on. Every round shows one card to the whole group.

Strategies (all start from the same hard-filtered pool for the query):
  popularity       most-reviewed first, no learning
  static ranking   v1 / k=1 ranking (distance + quality), no learning           <- what v1 does today
  cluster bandit   Thompson sampling over the v1 clusters on the group's yes-rate; show the best-ranked
                   unseen card from the sampled cluster                          <- v2 with clusters
  feature learner  Bayesian linear regression on 9 features (8 vibes + price) of the yes-rate, Thompson
                   sampling over individual places                               <- v2 without clusters

Writes output/group_swipe_simulation.csv/.md.
"""
from __future__ import annotations

import numpy as np
import pandas as pd

from features import OUTPUT, VIBES
from recommend import MODEL_PATH, Recommender, expressed_mask, hard_filter, rank
from features import query_vector

GROUPS = 400
ROUNDS = 20
MEMBERS = 5
MATCH_AT = 4
QUERIES = [("any", 2, "Restaurants"), ("any", 3, "Bars & Nightlife"), ("any", 2, "Cafes & Desserts"),
           ("Manhattan", 3, "Restaurants"), ("Brooklyn", 2, "Restaurants")]
rng = np.random.default_rng(7)


def sigmoid(x):
    return 1 / (1 + np.exp(-x))


def main() -> None:
    rec = Recommender.load(MODEL_PATH)
    P = rec.places
    nv = len(VIBES)
    vibe = rec.X[:, -nv:]                                   # 0..1, unknown = category mean
    price = P["price_final"].to_numpy() / 4
    qz = (rec.qual - rec.qual.mean()) / rec.qual.std()
    feats = np.hstack([vibe, price[:, None]])               # what the feature learner sees
    ids = P["master_id"].to_numpy()

    rows = []
    for (b, p, c) in QUERIES:
        ok = np.flatnonzero(hard_filter(P, b, p, [c]))
        q = query_vector([c], p, rec.spec, rec.w_cat, {})
        mask = expressed_mask({})
        static_order = rank(rec.X, q, mask, rec.qual, ok, ids)
        pop_order = ok[np.argsort(-P["rating_count"].fillna(0).to_numpy()[ok], kind="stable")]
        labels = rec.labels[ok]
        clusters = [cl for cl in np.unique(labels) if (labels == cl).sum() >= 5]
        by_cluster = {cl: [i for i in static_order if rec.labels[i] == cl] for cl in clusters}

        for g in range(GROUPS):
            taste = rng.normal(0, 1.2, nv)
            price_dislike = rng.normal(1.0, 0.8)
            members = taste + rng.normal(0, 0.5, (MEMBERS, nv))
            logits = (-0.3 + ((vibe[ok] - 0.5) * 2) @ members.T - price_dislike * price[ok][:, None]
                      + 0.8 * qz[ok][:, None])                 # (pool, members)
            like_p = dict(zip(ok, sigmoid(logits)))

            def swipe(i):
                votes = rng.random(MEMBERS) < like_p[i]
                return votes.sum()

            results = {}
            # no-learning orders
            for name, order in [("popularity", pop_order), ("static ranking (v1 today)", static_order)]:
                yes = [swipe(i) for i in order[:ROUNDS]]
                results[name] = yes
            # cluster bandit
            a, bb = {cl: 1.0 for cl in clusters}, {cl: 1.0 for cl in clusters}
            ptr = {cl: 0 for cl in clusters}
            yes = []
            for _ in range(ROUNDS):
                live = [cl for cl in clusters if ptr[cl] < len(by_cluster[cl])]
                cl = max(live, key=lambda x: rng.beta(a[x], bb[x]))
                i = by_cluster[cl][ptr[cl]]
                ptr[cl] += 1
                y = swipe(i)
                a[cl] += y
                bb[cl] += MEMBERS - y
                yes.append(y)
            results["cluster bandit (v2 + clusters)"] = yes
            # feature learner: Bayesian linear regression on yes-rate, Thompson sampling
            Fx = np.hstack([feats[ok], np.ones((len(ok), 1))])
            prior_mean = np.zeros(Fx.shape[1])
            # start from the static ranking's preference: tiny prior that favours quality via ordering
            A, bvec = np.eye(Fx.shape[1]) * 1.0, np.zeros(Fx.shape[1])
            shown = np.zeros(len(ok), dtype=bool)
            rank_bonus = np.zeros(len(ok))
            pos = {i: r for r, i in enumerate(static_order)}
            rank_bonus = np.array([1 - pos[i] / len(ok) for i in ok]) * 0.3
            yes = []
            for _ in range(ROUNDS):
                cov = np.linalg.inv(A)
                w = rng.multivariate_normal(cov @ bvec + prior_mean, cov * 0.25)
                score = Fx @ w + rank_bonus
                score[shown] = -np.inf
                j = int(np.argmax(score))
                shown[j] = True
                y = swipe(ok[j])
                A += np.outer(Fx[j], Fx[j])
                bvec += Fx[j] * (y / MEMBERS - 0.5)
                yes.append(y)
            results["feature learner (v2, no clusters)"] = yes

            for name, ys in results.items():
                ys = np.array(ys)
                hit = np.flatnonzero(ys >= MATCH_AT)
                rows.append({"query": f"{c} · {b} · max {p}", "strategy": name,
                             "first_match_round": int(hit[0]) + 1 if len(hit) else np.nan,
                             "matched_within_10": bool(len(hit) and hit[0] < 10),
                             "matches_in_10": int((ys[:10] >= MATCH_AT).sum()),
                             "yes_rate_10": float(ys[:10].mean() / MEMBERS)})

    df = pd.DataFrame(rows)
    df.to_csv(OUTPUT / "group_swipe_simulation.csv", index=False)
    order = ["popularity", "static ranking (v1 today)", "cluster bandit (v2 + clusters)",
             "feature learner (v2, no clusters)"]
    s = df.groupby("strategy").agg(match_within_10=("matched_within_10", "mean"),
                                   matches_in_10=("matches_in_10", "mean"),
                                   yes_rate_10=("yes_rate_10", "mean"),
                                   median_rounds_to_match=("first_match_round", "median")).loc[order]
    print(f"{GROUPS} synthetic groups x {len(QUERIES)} queries, {ROUNDS} cards max, match = {MATCH_AT}/{MEMBERS} yes\n")
    print(s.to_string(float_format=lambda x: f"{x:.3f}"))
    s.to_csv(OUTPUT / "group_swipe_simulation_summary.csv", float_format="%.4g")


if __name__ == "__main__":
    main()
