# SideQuest ML

Model code for SideQuest. The Flask app and frontend live in the SideQuest app repository; nothing here is
imported by the app yet.

| Folder | What it is |
|---|---|
| `data_pipeline/` | How the NYC places dataset was built: Overture Maps, Google Places, NYC Open Data, OSM, Wikidata. See `data_pipeline/DATA.md` |
| `data/places_v1.parquet` | Modeling extract (`data_pipeline/build_places_v1.sql`): 45,440 Google-verified NYC places with category, price, rating, vibe flags and location, plus 755 official NYC Parks / GreenThumb parks, fields and gardens (free, no rating) |
| `models/places_kmeans_v1/` | **v1 model**: K-means (k = 25) over category, price and vibe, plus the decision logic that turns a user's borough, price and categories into a 10-card deck. See its README |

Quick start:

```bash
python3 -m venv .venv
.venv/bin/pip install -r models/places_kmeans_v1/requirements.txt
cd models/places_kmeans_v1
../../.venv/bin/python recommend.py --borough Manhattan --max-price 2 --categories "Museums & Galleries"
```

The data contains Google Places content stored under the team's permission. Keep this repository private.
