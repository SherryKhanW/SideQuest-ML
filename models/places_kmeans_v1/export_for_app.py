#!/usr/bin/env python3
"""Package exactly what the SideQuest app needs, and nothing that fits or evaluates a model.

Writes output/app/:
  engine/      decision logic only: features.py (vectorise places and queries), recommend.py (ranking helpers),
               group.py (recommend_room, pick_winner), category_config.py (types, filters, card fields)
  model/       the fitted model: model_v1.json (25 centroids), feature_spec.json (feature order and the
               imputation means used for queries), category_filters.json (what the UI shows per category)
  data/        places_catalog.parquet: the 46,195-place catalog the decks are drawn from
  README.md    how the app calls it
  example_room.py   runs one room end to end from this folder alone

The app copies output/app/ in, installs requirements.txt, sets SIDEQUEST_PLACES and SIDEQUEST_MODEL_DIR
(example_room.py shows how) and calls engine.group.recommend_room / pick_winner. No fitting code is exported.
"""
from __future__ import annotations

import shutil
import subprocess
import sys

from features import DATA_PATH, OUTPUT, SPEC_PATH

HERE = OUTPUT.parent
APP = OUTPUT / "app"
ENGINE_FILES = ["features.py", "recommend.py", "group.py", "category_config.py"]

README = """# SideQuest engine (v1) for the app

Exported from SideQuest-ML `models/places_kmeans_v1/export_for_app.py`. **Don't edit here; change the ML repo and
re-export.** It holds the fitted model and the decision logic only; fitting and evaluation stay in SideQuest-ML.

| Folder | What |
|---|---|
| `model/model_v1.json` | fitted K-means, k = 25: centroids, cluster names |
| `model/feature_spec.json` | feature order + imputation means used to turn preferences into a vector |
| `model/category_filters.json` | room settings, per-category filters (`v1: true` = shown in v1) and card fields |
| `data/places_catalog.parquet` | 46,195 NYC places the decks come from (Google-verified + official parks/gardens) |
| `engine/` | decision logic: `group.recommend_room`, `group.pick_winner` |

## Use

```python
import os
os.environ["SIDEQUEST_PLACES"] = "<this folder>/data/places_catalog.parquet"
os.environ["SIDEQUEST_MODEL_DIR"] = "<this folder>/model"
import sys; sys.path.insert(0, "<this folder>/engine")
from datetime import datetime
from recommend import Recommender
from group import GroupRecommender, Room, Member, pick_winner

engine = GroupRecommender(Recommender.load())          # load once at app start (~1 s)

room = Room(boroughs=["Manhattan"], group_size=3, when=datetime(2026, 12, 4, 20, 0))   # organizer
members = [Member("Ana", 3, ["Bars & Nightlife"], ["nightlife"]),                      # each person, privately
           Member("Ben", 2, ["Restaurants"], cuisines=["Korean"]),
           Member("Chi", 2, ["Restaurants", "Bars & Nightlife"], needs_wheelchair=True)]
deck = engine.recommend_room(room, members)["deck"]     # 10 cards: id, name, category, fields, for, maps_uri...
votes = {"Ana": {deck[0]["id"]: True}, "Ben": {deck[0]["id"]: True}, "Chi": {}}
result = pick_winner(deck, votes)                       # {"match": card, ...} or {"match": None, "reason": ...}
# no match -> engine.recommend_room(room, members, exclude={c["id"] for c in deck}) for a fresh deck
```

## Inputs

- **Room (organizer):** `boroughs` (1+ of Manhattan, Brooklyn, Queens, Bronx, Staten Island), `group_size` (2–5), `when` (datetime, NYC local time).
- **Member (each person, private):**
  - `max_price`: 0 Free, 1 ≈ $20, 2 ≈ $30, 3 ≈ $90, 4 no limit;
  - `categories`: 1+ of the 12;
  - `toggles`: optional `kids`, `outdoors`, `nightlife`;
  - `types` and `cuisines`: optional; values are in `category_filters.json`;
  - `needs_wheelchair`.

## Guarantees

Every card is in the room's boroughs, at or under the lowest member budget, and not known to be closed for 90 minutes
from `when` (unknown hours are labelled). It has a confirmed accessible entrance if anyone needs one, is a real place
of its category, and is not clearly badly rated. `fields` holds the category-specific card fields to display.
`for` lists which members the card suits.

Data contains Google Places content stored under the team's permission: keep the app repo private.
"""

EXAMPLE = '''#!/usr/bin/env python3
"""Run one room end to end using only this folder (no SideQuest-ML repo needed)."""
import os
import sys
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
os.environ["SIDEQUEST_PLACES"] = str(HERE / "data" / "places_catalog.parquet")
os.environ["SIDEQUEST_MODEL_DIR"] = str(HERE / "model")
sys.path.insert(0, str(HERE / "engine"))

from recommend import Recommender                                  # noqa: E402
from group import GroupRecommender, Member, Room, pick_winner      # noqa: E402

engine = GroupRecommender(Recommender.load())
room = Room(["Manhattan"], 3, datetime(2026, 12, 4, 20, 0))
members = [Member("Ana", 3, ["Bars & Nightlife"], ["nightlife"]),
           Member("Ben", 2, ["Restaurants"], cuisines=["Korean"]),
           Member("Chi", 2, ["Restaurants", "Bars & Nightlife"], needs_wheelchair=True)]
out = engine.recommend_room(room, members)
for i, c in enumerate(out["deck"], 1):
    print(i, c["id"], c["name"], "|", c["category"], "|", " · ".join(str(v) for k, v in c["fields"].items()
                                                                  if k != "summary"), "| for", c["for"])
votes = {m.name: {c["id"]: m.name in c["for"] for c in out["deck"]} for m in members}
print("winner:", (pick_winner(out["deck"], votes)["match"] or {}).get("name"))
'''


def main() -> None:
    subprocess.run([sys.executable, str(HERE / "category_config.py")], check=True, capture_output=True)
    if APP.exists():
        shutil.rmtree(APP)
    for d in ("engine", "model", "data"):
        (APP / d).mkdir(parents=True)
    for f in ENGINE_FILES:
        shutil.copy2(HERE / f, APP / "engine" / f)
    for f in ("model_v1.json", "category_filters.json"):
        shutil.copy2(OUTPUT / f, APP / "model" / f)
    shutil.copy2(SPEC_PATH, APP / "model" / "feature_spec.json")
    shutil.copy2(DATA_PATH, APP / "data" / "places_catalog.parquet")
    shutil.copy2(HERE / "requirements.txt", APP / "requirements.txt")
    (APP / "README.md").write_text(README)
    (APP / "example_room.py").write_text(EXAMPLE)
    print(f"wrote {APP}:")
    for p in sorted(APP.rglob("*")):
        if p.is_file():
            print(f"  {p.relative_to(APP)}  ({p.stat().st_size / 1024:,.0f} KB)")


if __name__ == "__main__":
    main()
