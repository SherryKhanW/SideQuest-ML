#!/usr/bin/env python3
"""Group decks vs the naive ways groups decide today, on 500 random rooms.

Rooms are synthetic (2-5 members with randomly drawn but realistic preferences); the places are real.
Every approach produces a 10-card deck for the same room:

  organizer searches   one person searches with their own budget, borough and taste (the usual group chat)
  popularity list      everyone's limits respected, then the most-reviewed places (no personal taste)
  averaged request     one request built by averaging: mean budget, the borough most members accept,
                       all categories combined (what you'd type into a single search box or chatbot)
  SideQuest group k=1  the group logic in group.py with one cluster (no clustering)
  SideQuest group v1   the group logic in group.py with the k=25 model

Metrics per deck (each member is judged by their OWN stated preferences):
  breaks_someones_limit   share of cards over some member's budget or outside a borough they accept
  members_with_2plus      share of members with at least 2 cards that suit them
  worst_member_cards      cards suiting the least-served member
  avg_rating              Bayesian-smoothed Google rating of the deck
Writes output/group_comparison.csv and output/group_comparison_rooms.csv.
"""
from __future__ import annotations

import time

import numpy as np
import pandas as pd

from features import BOROUGHS, CATEGORIES, OUTPUT
from group import GroupRecommender, Member
from recommend import MODEL_PATH, VIBE_TOGGLES, Recommender, hard_filter

ROOMS = 500
rng = np.random.default_rng(11)
CAT_WEIGHTS = np.array([30, 14, 14, 10, 8, 7, 6, 4, 2, 2, 2, 1], dtype=float)   # roughly how often people ask
CAT_WEIGHTS /= CAT_WEIGHTS.sum()
PRICE_WEIGHTS = [0.05, 0.25, 0.4, 0.2, 0.1]


def random_room() -> list[Member]:
    size = int(rng.integers(2, 6))
    home = rng.choice(BOROUGHS, p=[0.4, 0.3, 0.15, 0.1, 0.05])
    shared = rng.choice(CATEGORIES, p=CAT_WEIGHTS)                    # groups usually half-agree on something
    members = []
    for j in range(size):
        if rng.random() < 0.35:
            boroughs = "any"
        else:
            extra = [b for b in BOROUGHS if b != home and rng.random() < 0.3]
            boroughs = [home] + extra if rng.random() < 0.9 else list(rng.choice(BOROUGHS, 1))
        cats = {shared} if rng.random() < 0.6 else set()
        while len(cats) < int(rng.integers(1, 3)):
            cats.add(rng.choice(CATEGORIES, p=CAT_WEIGHTS))
        toggles = [rng.choice(list(VIBE_TOGGLES))] if rng.random() < 0.3 else []
        members.append(Member(f"m{j}", int(rng.choice(5, p=PRICE_WEIGHTS)), sorted(cats), boroughs, toggles))
    return members


def main() -> None:
    rec = Recommender.load(MODEL_PATH)
    k1 = Recommender(rec.X.mean(axis=0, keepdims=True), rec.w_cat, ["all places"], rec.spec, rec.places, rec.X,
                     np.zeros(len(rec.places), dtype=int), rec.qual)
    g_v1, g_k1 = GroupRecommender(rec), GroupRecommender(k1)
    P = rec.places
    key = dict(zip(zip(P["name"], P["maps_uri"]), P.index))
    bayes = rec.qual * 1.5 + 3.5

    def ids(deck):
        return [key[(c["name"], c["maps_uri"])] for c in deck]

    rows, skipped = [], 0
    while len(rows) < ROOMS * 5:
        members = random_room()
        out = g_v1.recommend(members)
        if len(out["deck"]) < 10:          # infeasible room (no shared borough / nothing fits): skip for all
            skipped += 1
            continue
        org = members[0]
        org_b = "any" if org.boroughs == "any" else org.boroughs[0]
        boroughs_count = {b: sum(b in m.borough_set() for m in members) for b in BOROUGHS}
        avg_b = max(boroughs_count, key=boroughs_count.get)
        avg_price = int(round(np.mean([m.max_price for m in members])))
        all_cats = sorted({c for m in members for c in m.categories})
        strict = hard_filter(P, "any", min(m.max_price for m in members), all_cats) & \
            np.isin(P["borough"], list(set.intersection(*(m.borough_set() for m in members))))
        pop = np.flatnonzero(strict)
        pop = pop[np.argsort(-P["rating_count"].fillna(0).to_numpy()[pop], kind="stable")]
        pop_deck, seen = [], set()
        for i in pop:
            if P.at[i, "name"] not in seen:
                seen.add(P.at[i, "name"])
                pop_deck.append(int(i))
            if len(pop_deck) == 10:
                break

        decks = {}
        t0 = time.perf_counter()
        decks["organizer searches"] = ids(rec.recommend(org_b, org.max_price, org.categories, org.toggles)["deck"])
        decks["popularity list"] = pop_deck
        decks["averaged request"] = ids(rec.recommend(avg_b, avg_price, all_cats)["deck"])
        t1 = time.perf_counter()
        decks["SideQuest group k=1"] = ids(g_k1.recommend(members)["deck"])
        t2 = time.perf_counter()
        decks["SideQuest group v1"] = ids(out["deck"])
        t3 = time.perf_counter(); g_v1.recommend(members); t4 = time.perf_counter()

        for name, d in decks.items():
            d = np.array(d, dtype=int)
            over = np.zeros(len(d), dtype=bool)
            for m in members:
                over |= (P["price_final"].to_numpy()[d] > m.max_price) | ~np.isin(P["borough"].to_numpy()[d],
                                                                               list(m.borough_set()))
            per_member = [int(g_v1.suits(m, d).sum()) for m in members]
            rows.append({"room": len(rows) // 5, "size": len(members), "approach": name,
                         "breaks_someones_limit": over.mean(),
                         "members_with_2plus": np.mean([c >= 2 for c in per_member]),
                         "worst_member_cards": min(per_member), "avg_rating": float(bayes[d].mean()),
                         "ms": {"SideQuest group k=1": (t2 - t1), "SideQuest group v1": (t4 - t3)}.get(name, np.nan) * 1000})

    df = pd.DataFrame(rows)
    df.to_csv(OUTPUT / "group_comparison_rooms.csv", index=False, float_format="%.4g")
    order = ["organizer searches", "popularity list", "averaged request", "SideQuest group k=1", "SideQuest group v1"]
    s = df.groupby("approach").agg(breaks_someones_limit=("breaks_someones_limit", "mean"),
                                   members_with_2plus=("members_with_2plus", "mean"),
                                   worst_member_cards=("worst_member_cards", "mean"),
                                   avg_rating=("avg_rating", "mean"), ms_median=("ms", "median")).loc[order]
    s.to_csv(OUTPUT / "group_comparison.csv", float_format="%.4g")
    print(f"{ROOMS} feasible synthetic rooms (2-5 members; {skipped} infeasible rooms skipped)\n")
    print(s.to_string(float_format=lambda x: f"{x:.3f}"))


if __name__ == "__main__":
    main()
