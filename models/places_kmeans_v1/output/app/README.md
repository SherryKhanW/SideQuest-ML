# SideQuest engine (v1) for the app

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
