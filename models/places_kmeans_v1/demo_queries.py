#!/usr/bin/env python3
"""Step 5: run hand-written dummy user profiles through the v1 model and check the decks.

These are made-up test inputs, not observed users. For each profile we record the cluster chosen,
how many clusters were needed, the 10 cards, and whether every card passes the hard filters
(borough, max price, category). Writes output/demo_results.md and output/demo_results.json.
"""
from __future__ import annotations

import json

from features import OUTPUT
from recommend import Recommender

PROFILES = [
    {"label": "Dinner in Brooklyn, mid-range", "borough": "Brooklyn", "max_price": 2, "categories": ["Restaurants"]},
    {"label": "Free culture in Manhattan", "borough": "Manhattan", "max_price": 0, "categories": ["Museums & Galleries"]},
    {"label": "Cheap park day with kids, Queens", "borough": "Queens", "max_price": 1,
     "categories": ["Parks & Outdoors"], "toggles": ["kids"]},
    {"label": "Night out anywhere, upscale", "borough": "any", "max_price": 3,
     "categories": ["Bars & Nightlife"], "toggles": ["nightlife"]},
    {"label": "Luxury spa, Staten Island (edge case)", "borough": "Staten Island", "max_price": 4,
     "categories": ["Spas & Wellness"]},
    {"label": "Coffee + books, Manhattan", "borough": "Manhattan", "max_price": 1,
     "categories": ["Cafes & Desserts", "Libraries & Bookstores"]},
    {"label": "Live show, Manhattan, $$$", "borough": "Manhattan", "max_price": 3, "categories": ["Shows & Live Events"]},
    {"label": "Group games night, Brooklyn", "borough": "Brooklyn", "max_price": 2,
     "categories": ["Games & Indoor Fun"], "toggles": ["groups"]},
    {"label": "Budget eats, Bronx, late", "borough": "Bronx", "max_price": 1, "categories": ["Restaurants"],
     "toggles": ["nightlife"]},
    {"label": "Dog-friendly outdoors, any borough", "borough": "any", "max_price": 2,
     "categories": ["Parks & Outdoors", "Cafes & Desserts"], "toggles": ["dogs", "outdoors"]},
    {"label": "Tourist day, Manhattan, $$", "borough": "Manhattan", "max_price": 2,
     "categories": ["Attractions & Tours", "Museums & Galleries"]},
    {"label": "Fine dining, Manhattan", "borough": "Manhattan", "max_price": 4, "categories": ["Restaurants"],
     "toggles": ["groups"]},
]


def main() -> None:
    rec = Recommender.load()
    results, lines = [], ["# v1 model on dummy user inputs\n",
                          "Made-up test profiles, not real users. Every card is checked against the hard filters.\n"]
    all_ok = True
    for p in PROFILES:
        out = rec.recommend(p["borough"], p["max_price"], p["categories"], p.get("toggles"))
        ok = all(c["passes_filters"] for c in out["deck"])
        all_ok &= ok
        results.append({"profile": p, **out, "all_cards_pass_filters": ok})
        lines.append(f"## {p['label']}\n")
        lines.append(f"Input: borough={p['borough']}, max_price={p['max_price']}, categories={p['categories']}, "
                     f"toggles={p.get('toggles', [])}  ")
        lines.append(f"Nearest cluster: **{out['nearest_cluster']['id']} · {out['nearest_cluster']['name']}**  ")
        lines.append(f"Clusters used: {len(out['clusters_used'])} · matching places in catalog: "
                     f"{out['matching_places_in_catalog']:,} · deck size: {len(out['deck'])} · "
                     f"all cards pass filters: {'yes' if ok else 'NO'}\n")
        lines.append("| # | place | type | price | rating | neighborhood | cluster |")
        lines.append("|---|---|---|---|---|---|---|")
        for i, c in enumerate(out["deck"], 1):
            rating = f"{c['rating']} ({c['rating_count']:,})" if c["rating"] else "–"
            lines.append(f"| {i} | {c['name']} | {c['type']} | {c['price']} | {rating} | "
                         f"{c['neighborhood']}, {c['borough']} | {c['cluster']} |")
        lines.append("")
        print(f"{'OK ' if ok else 'BAD'} {p['label']:40s} cluster {out['nearest_cluster']['id']:>2} "
              f"({out['nearest_cluster']['name']})  used {len(out['clusters_used'])}  deck {len(out['deck'])}")

    (OUTPUT / "demo_results.md").write_text("\n".join(lines))
    (OUTPUT / "demo_results.json").write_text(json.dumps(results, indent=2, default=str) + "\n")
    print(f"\nall decks pass hard filters: {all_ok}. wrote demo_results.md / .json")
    if not all_ok:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
