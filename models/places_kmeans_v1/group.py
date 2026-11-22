#!/usr/bin/env python3
"""Group decision logic: up to 5 people's preferences -> one shared, fair 10-card deck.

Each member gives: boroughs they'll go to (a list, or "any"), their own max price, 1+ categories,
and optional vibe toggles. Members never see each other's limits; only the deck is shared.

  1. Hard limits combine strictly. Price cap = the LOWEST member max; allowed boroughs = the boroughs
     EVERY member accepts. Nobody is outvoted on money or location. If no borough is accepted by
     everyone, the result says so instead of breaking someone's limit.
  2. Each member becomes query vectors (one per chosen category, same space as places).
  3. Clusters are scored for the whole group: mean member distance + the worst-off member's distance
     (masked to what each member expressed). The best-fitting clusters form the candidate pool, adding
     clusters until every member has enough candidates they'd like.
  4. Places are ranked by the same group score (mean + worst-off member) minus a quality bonus.
  5. Fair fill: each slot goes to the best-ranked place that suits the member with the fewest suitable
     cards so far, so every person sees something they asked for. One card per name, max 3 per type.

    python group.py          # runs the example groups in EXAMPLES
"""
from __future__ import annotations

import json
from dataclasses import dataclass, field

import numpy as np
import pandas as pd

from features import BOROUGHS, CATEGORIES, OUTPUT, VIBES, query_vector, raw_vibes
from recommend import (DECK_SIZE, MAX_PER_SUBCATEGORY, MODEL_PATH, PRICE_LABEL, QUALITY_WEIGHT, VIBE_TOGGLES,
                       Recommender, expressed_mask, place_type)

MIN_CANDIDATES_PER_MEMBER = 5     # keep adding clusters until each member has this many candidates they'd like
WORST_OFF_WEIGHT = 1.0            # weight of the worst-off member in the group score (mean has weight 1)


@dataclass
class Member:
    name: str
    max_price: int
    categories: list[str]
    boroughs: list[str] | str = "any"
    toggles: list[str] = field(default_factory=list)

    def borough_set(self) -> set[str]:
        return set(BOROUGHS) if self.boroughs == "any" else set(self.boroughs)


def member_vibes(m: Member) -> dict[str, float]:
    v = {}
    for t in m.toggles:
        v.update(VIBE_TOGGLES[t])
    return v


class GroupRecommender:
    def __init__(self, rec: Recommender):
        self.rec = rec
        self.vib = raw_vibes(rec.places)                       # known flags (NaN = unknown)
        self.cat = rec.places["activity_category"].to_numpy()
        self.price = rec.places["price_final"].to_numpy()
        self.borough = rec.places["borough"].to_numpy()

    # -- per-member helpers ------------------------------------------------------------------
    def _member_queries(self, m: Member):
        vibes = member_vibes(m)
        mask = expressed_mask(vibes)
        return [query_vector([c], m.max_price, self.rec.spec, self.rec.w_cat, vibes) for c in m.categories], mask

    def _dist(self, Y: np.ndarray, queries, mask) -> np.ndarray:
        """Distance from each row of Y to the member's closest query (masked to what they expressed)."""
        return np.min([np.sqrt(((Y[:, mask] - q[mask]) ** 2).sum(axis=1)) for q in queries], axis=0)

    def suits(self, m: Member, idx: np.ndarray) -> np.ndarray:
        """Would this member want this card? Their category, their budget and borough, and no toggle the
        place is KNOWN to fail (unknown flags are given the benefit of the doubt)."""
        ok = np.isin(self.cat[idx], m.categories) & (self.price[idx] <= m.max_price) \
            & np.isin(self.borough[idx], list(m.borough_set()))
        for f in member_vibes(m):
            ok &= ~(self.vib[f].to_numpy()[idx] == 0)
        return ok

    # -- main ---------------------------------------------------------------------------------
    def recommend(self, members: list[Member], n: int = DECK_SIZE) -> dict:
        if not 1 <= len(members) <= 5:
            raise ValueError("a room has 1 to 5 members")
        for m in members:
            bad = [c for c in m.categories if c not in CATEGORIES] + [t for t in m.toggles if t not in VIBE_TOGGLES]
            if bad or not m.categories:
                raise ValueError(f"{m.name}: bad or missing categories/toggles {bad}")

        price_cap = min(m.max_price for m in members)
        boroughs = set.intersection(*(m.borough_set() for m in members))
        wanted = sorted({c for m in members for c in m.categories})
        base = {"group_limits": {"max_price": PRICE_LABEL[price_cap], "boroughs": sorted(boroughs),
                                 "categories": wanted}}
        if not boroughs:
            return {**base, "deck": [], "message": "No borough is acceptable to every member."}

        P = self.rec.places
        ok = np.isin(self.cat, wanted) & (self.price <= price_cap) & np.isin(self.borough, list(boroughs))
        mq = [self._member_queries(m) for m in members]

        # 1. cluster scores for the group: mean + worst-off member distance to the centroid
        cd = np.array([self._dist(self.rec.centers, qs, mask) for qs, mask in mq])   # (members, k)
        cluster_score = cd.mean(axis=0) + WORST_OFF_WEIGHT * cd.max(axis=0)
        order = np.argsort(cluster_score, kind="stable")

        # 2. candidate pool from the best clusters, until every member has enough suitable candidates
        pool, used = np.zeros(len(P), dtype=bool), []
        for c in order:
            used.append(int(c))
            pool |= ok & (self.rec.labels == c)
            idx = np.flatnonzero(pool)
            if len(idx) >= 3 * n and all(self.suits(m, idx).sum() >= MIN_CANDIDATES_PER_MEMBER for m in members):
                break
        idx = np.flatnonzero(pool)
        if len(idx) == 0:
            return {**base, "deck": [], "message": "Nothing in the catalog fits everyone's limits."}

        # 3. rank places by group score minus quality
        pd_ = np.array([self._dist(self.rec.X[idx], qs, mask) for qs, mask in mq])    # (members, pool)
        score = pd_.mean(axis=0) + WORST_OFF_WEIGHT * pd_.max(axis=0) - QUALITY_WEIGHT * self.rec.qual[idx]
        ranked = idx[np.lexsort((P["master_id"].to_numpy()[idx], score))]
        suits = {i: [self.suits(m, np.array([i]))[0] for m in members] for i in ranked}

        # 4. fair fill: the least-served member picks the next slot
        deck, names, per_sub = [], set(), {}
        served = np.zeros(len(members), dtype=int)

        def allowed(i):
            nm = P.at[i, "name"].strip().lower()
            return nm not in names and per_sub.get(P.at[i, "subcategory"], 0) < MAX_PER_SUBCATEGORY

        while len(deck) < n:
            pick = None
            for who in np.argsort(served, kind="stable"):           # least-served member first
                pick = next((i for i in ranked if i not in deck and allowed(i) and suits[i][who]), None)
                if pick is not None:
                    break
            if pick is None:                                         # nobody can be helped specifically
                pick = next((i for i in ranked if i not in deck and allowed(i)), None)
            if pick is None:
                break
            deck.append(pick)
            names.add(P.at[pick, "name"].strip().lower())
            per_sub[P.at[pick, "subcategory"]] = per_sub.get(P.at[pick, "subcategory"], 0) + 1
            served += np.array(suits[pick], dtype=int)

        cards = []
        for i in deck:
            p = P.loc[i]
            cards.append({
                "master_id": p["master_id"], "verified_by": p["verified_by"],
                "name": p["name"], "category": p["activity_category"], "type": place_type(p),
                "borough": p["borough"], "neighborhood": p["neighborhood"], "price": PRICE_LABEL[int(p["price_final"])],
                "rating": None if pd.isna(p["rating"]) else float(p["rating"]),
                "rating_count": None if pd.isna(p["rating_count"]) else int(p["rating_count"]),
                "cluster": int(self.rec.labels[i]), "cluster_name": self.rec.names[int(self.rec.labels[i])],
                "for": [m.name for m, s in zip(members, suits[i]) if s],
                "within_everyones_limits": bool(ok[i]),
                "maps_uri": p["maps_uri"],
            })
        unserved = {}
        for m, s in zip(members, served):
            if s == 0:                     # explain why, instead of silently leaving someone out
                any_fit = (np.isin(self.cat, m.categories) & (self.price <= price_cap)
                           & np.isin(self.borough, list(boroughs))).sum()
                unserved[m.name] = (f"nothing in {', '.join(m.categories)} within the group's limits "
                                    f"({PRICE_LABEL[price_cap]}, {', '.join(sorted(boroughs))})" if any_fit == 0
                                    else "their picks rank below what the rest of the group shares")
        return {**base, "clusters_used": [{"id": c, "name": self.rec.names[c]} for c in used],
                "cards_per_member": {m.name: int(s) for m, s in zip(members, served)},
                "unserved_members": unserved, "deck": cards}


EXAMPLES = {
    "Friday night, mixed budgets (Manhattan/Brooklyn)": [
        Member("Ana", 3, ["Bars & Nightlife"], ["Manhattan", "Brooklyn"], ["nightlife"]),
        Member("Ben", 2, ["Restaurants"], ["Manhattan", "Brooklyn"]),
        Member("Chi", 2, ["Bars & Nightlife", "Restaurants"], "any"),
        Member("Dev", 4, ["Shows & Live Events"], ["Manhattan"]),
        Member("Eli", 2, ["Restaurants"], ["Manhattan", "Brooklyn", "Queens"], ["outdoors"]),
    ],
    "Cheap Sunday with kids (Queens/Brooklyn)": [
        Member("Fay", 1, ["Parks & Outdoors"], ["Queens", "Brooklyn"], ["kids"]),
        Member("Gus", 2, ["Museums & Galleries", "Parks & Outdoors"], ["Queens"]),
        Member("Hal", 1, ["Cafes & Desserts"], "any", ["kids"]),
        Member("Ivy", 0, ["Parks & Outdoors", "Museums & Galleries"], ["Queens", "Brooklyn"]),
    ],
    "Nobody agrees on a borough": [
        Member("Jo", 2, ["Restaurants"], ["Bronx"]),
        Member("Kai", 2, ["Restaurants"], ["Staten Island"]),
    ],
}


def main() -> None:
    g = GroupRecommender(Recommender.load(MODEL_PATH))
    lines = ["# Group decks (example rooms)\n", "Made-up rooms for testing. Each card lists the members it suits.\n"]
    out_json = {}
    for title, members in EXAMPLES.items():
        out = g.recommend(members)
        out_json[title] = {"members": [m.__dict__ for m in members], **out}
        print(f"\n== {title}")
        print(f"   group limits: {out['group_limits']}")
        lines.append(f"## {title}\n")
        lines.append("| member | max price | boroughs | categories | toggles |\n|---|---|---|---|---|")
        for m in members:
            lines.append(f"| {m.name} | {PRICE_LABEL[m.max_price]} | {m.boroughs if m.boroughs == 'any' else ', '.join(m.boroughs)} "
                         f"| {', '.join(m.categories)} | {', '.join(m.toggles) or '–'} |")
        lines.append(f"\nGroup limits: max price {out['group_limits']['max_price']}, boroughs "
                     f"{', '.join(out['group_limits']['boroughs']) or 'none'}.  ")
        if not out["deck"]:
            print(f"   {out['message']}")
            lines.append(f"**{out['message']}**\n")
            continue
        print(f"   cards per member: {out['cards_per_member']}")
        lines.append(f"Cards that suit each member: {out['cards_per_member']}  ")
        for who, why in out["unserved_members"].items():
            print(f"   no card for {who}: {why}")
            lines.append(f"No card for {who}: {why}.  ")
        lines.append("")
        lines.append("| # | place | type | price | rating | where | suits | cluster |\n|---|---|---|---|---|---|---|---|")
        for i, c in enumerate(out["deck"], 1):
            r = f"{c['rating']} ({c['rating_count']:,})" if c["rating"] else "–"
            print(f"   {i:2d}. {c['name']} · {c['type']} · {c['price']} · {r} · {c['neighborhood']}, {c['borough']} "
                  f"· for {', '.join(c['for']) or 'group'}")
            lines.append(f"| {i} | {c['name']} | {c['type']} | {c['price']} | {r} | {c['neighborhood']}, {c['borough']} "
                         f"| {', '.join(c['for']) or '–'} | {c['cluster_name']} |")
            assert c["within_everyones_limits"]
        lines.append("")
    (OUTPUT / "group_demo.md").write_text("\n".join(lines) + "\n")
    (OUTPUT / "group_demo.json").write_text(json.dumps(out_json, indent=2, default=str) + "\n")
    print("\nwrote group_demo.md / .json")


if __name__ == "__main__":
    main()
