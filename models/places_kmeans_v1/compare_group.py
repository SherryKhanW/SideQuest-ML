#!/usr/bin/env python3
"""Room decks vs the naive ways groups decide today, on 500 random rooms.

Rooms are synthetic but follow the real app flow: the organizer picks 1-2 boroughs, the group size and a time
(weekday/weekend, morning to late night); each of 2-5 members privately picks categories, a max price, sometimes
a vibe toggle, a type or cuisine, or needs wheelchair access. The places are real. Every approach builds a
10-card deck for the same room:

  organizer searches   one person searches with their own budget and taste in the room's first borough
  popularity list      everyone's budget and the room's boroughs respected, most-reviewed first
  averaged request     one request: mean budget, all categories combined (a search box or a chatbot prompt)
  SideQuest room k=1   group.py room logic with one cluster (no clustering)
  SideQuest room v1    group.py room logic with the k=25 model

Per deck, judged against each member's OWN stated preferences and the room's settings:
  breaks_limit          share of cards over some member's budget or outside the room's boroughs
  closed_at_time        share of cards known to be closed (or closing within 90 min) at the room's time
  no_wheelchair         share of cards without a confirmed accessible entrance when someone needs one
  members_with_2plus    share of members with at least 2 cards that suit them
  worst_member_cards    cards suiting the least-served member
  avg_rating            Bayesian-smoothed Google rating
Writes output/group_comparison.csv and output/group_comparison_rooms.csv.
"""
from __future__ import annotations

import time
from datetime import datetime, timedelta

import numpy as np
import pandas as pd

from category_config import TYPE_GROUPS
from features import BOROUGHS, CATEGORIES, OUTPUT
from group import GroupRecommender, Member, Room
from recommend import MODEL_PATH, VIBE_TOGGLES, Recommender, hard_filter

ROOMS = 500
rng = np.random.default_rng(11)
CAT_WEIGHTS = np.array([30, 14, 14, 10, 8, 7, 6, 4, 2, 2, 2, 1], dtype=float)
CAT_WEIGHTS /= CAT_WEIGHTS.sum()
PRICE_WEIGHTS = [0.05, 0.25, 0.4, 0.2, 0.1]
SLOTS = [(4, 19, 30), (4, 21, 0), (5, 13, 0), (5, 20, 0), (5, 23, 0), (6, 11, 0), (6, 15, 0), (1, 18, 30), (2, 12, 0)]
CUISINE_CHOICES = ["Pizza & Italian", "Mexican & Latin", "Chinese", "Japanese & sushi", "American & burgers",
                   "Middle Eastern & Mediterranean", "Southeast Asian", "Indian & South Asian", "Korean"]


def random_room() -> tuple[Room, list[Member]]:
    size = int(rng.integers(2, 6))
    home = rng.choice(BOROUGHS, p=[0.4, 0.3, 0.15, 0.1, 0.05])
    boroughs = [str(home)] + ([str(rng.choice([b for b in BOROUGHS if b != home]))] if rng.random() < 0.35 else [])
    wd, h, mi = SLOTS[int(rng.integers(len(SLOTS)))]
    when = datetime(2026, 11, 30, h, mi) + timedelta(days=wd)          # Nov 30 2026 is a Monday
    shared = rng.choice(CATEGORIES, p=CAT_WEIGHTS)
    members = []
    for j in range(size):
        cats = {str(shared)} if rng.random() < 0.6 else set()
        while len(cats) < int(rng.integers(1, 3)):
            cats.add(str(rng.choice(CATEGORIES, p=CAT_WEIGHTS)))
        cats = sorted(cats)
        toggles = [str(rng.choice(["kids", "outdoors", "nightlife"]))] if rng.random() < 0.3 else []
        types = {}
        if rng.random() < 0.25:
            c = cats[0]
            if c != "Restaurants":
                types = {c: [str(rng.choice(list(TYPE_GROUPS[c])))]}
        cuisines = [str(rng.choice(CUISINE_CHOICES))] if "Restaurants" in cats and rng.random() < 0.3 else []
        members.append(Member(f"m{j}", int(rng.choice(5, p=PRICE_WEIGHTS)), cats, toggles, types, cuisines,
                              needs_wheelchair=bool(rng.random() < 0.05)))
    return Room(boroughs, size, when), members


def main() -> None:
    rec = Recommender.load(MODEL_PATH)
    k1 = Recommender(rec.X.mean(axis=0, keepdims=True), rec.w_cat, ["all places"], rec.spec, rec.places, rec.X,
                     np.zeros(len(rec.places), dtype=int), rec.qual)
    g_v1, g_k1 = GroupRecommender(rec), GroupRecommender(k1)
    P = g_v1.P
    pos = dict(zip(P["master_id"], P.index))
    bayes = rec.qual * 1.5 + 3.5
    wheel = P["wheelchair_entrance"].eq(True).fillna(False).to_numpy(dtype=bool)

    def ids(deck):
        return [pos[c["master_id"] if "master_id" in c else c["id"]] for c in deck]

    rows, skipped, room_no = [], 0, 0
    while room_no < ROOMS:
        room, members = random_room()
        t0 = time.perf_counter(); out = g_v1.recommend_room(room, members); t_v1 = time.perf_counter() - t0
        if len(out["deck"]) < 10:                       # nothing fits at that time: skip for every approach
            skipped += 1
            continue
        org = members[0]
        cap = min(m.max_price for m in members)
        all_cats = sorted({c for m in members for c in m.categories})
        strict = hard_filter(P, "any", cap, all_cats) & np.isin(P["borough"], room.boroughs)
        pop = np.flatnonzero(strict)
        pop = pop[np.argsort(-P["rating_count"].fillna(0).to_numpy()[pop], kind="stable")]
        pop_deck, seen = [], set()
        for i in pop:
            if P.at[i, "name"] not in seen:
                seen.add(P.at[i, "name"]); pop_deck.append(int(i))
            if len(pop_deck) == 10:
                break
        t0 = time.perf_counter(); k1_out = g_k1.recommend_room(room, members); t_k1 = time.perf_counter() - t0
        decks = {
            "organizer searches": ids(rec.recommend(room.boroughs[0], org.max_price, org.categories, org.toggles)["deck"]),
            "popularity list": pop_deck,
            "averaged request": ids(rec.recommend(room.boroughs[0], int(round(np.mean([m.max_price for m in members]))),
                                                  all_cats)["deck"]),
            "SideQuest room k=1": ids(k1_out["deck"]),
            "SideQuest room v1": ids(out["deck"]),
        }
        open_ok = g_v1.open_at(room.when)
        need_wheel = any(m.needs_wheelchair for m in members)
        vibes = [g_v1._queries(m)[2] for m in members]
        for name, d in decks.items():
            d = np.array(d, dtype=int)
            over = (P["price_final"].to_numpy()[d] > cap) | ~np.isin(P["borough"].to_numpy()[d], room.boroughs)
            per_member = [int(g_v1.suits(m, d, v).sum()) for m, v in zip(members, vibes)]
            rows.append({"room": room_no, "size": len(members), "approach": name,
                         "breaks_limit": over.mean(), "closed_at_time": (~open_ok[d]).mean(),
                         "no_wheelchair": (~wheel[d]).mean() if need_wheel else np.nan,
                         "members_with_2plus": np.mean([c >= 2 for c in per_member]),
                         "worst_member_cards": min(per_member), "avg_rating": float(bayes[d].mean()),
                         "ms": {"SideQuest room k=1": t_k1, "SideQuest room v1": t_v1}.get(name, np.nan) * 1000})
        room_no += 1

    df = pd.DataFrame(rows)
    df.to_csv(OUTPUT / "group_comparison_rooms.csv", index=False, float_format="%.4g")
    order = ["organizer searches", "popularity list", "averaged request", "SideQuest room k=1", "SideQuest room v1"]
    s = df.groupby("approach").agg(breaks_limit=("breaks_limit", "mean"), closed_at_time=("closed_at_time", "mean"),
                                   no_wheelchair=("no_wheelchair", "mean"),
                                   members_with_2plus=("members_with_2plus", "mean"),
                                   worst_member_cards=("worst_member_cards", "mean"),
                                   avg_rating=("avg_rating", "mean"), ms_median=("ms", "median")).loc[order]
    s.to_csv(OUTPUT / "group_comparison.csv", float_format="%.4g")
    n_wheel = int(df.loc[df.approach == order[-1], "no_wheelchair"].notna().sum())
    print(f"{ROOMS} synthetic rooms with a full deck ({skipped} rooms skipped: nothing fit at that time); "
          f"{n_wheel} rooms had a member needing wheelchair access\n")
    print(s.to_string(float_format=lambda x: f"{x:.3f}"))


if __name__ == "__main__":
    main()
