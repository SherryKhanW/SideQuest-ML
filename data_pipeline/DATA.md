# NYC places dataset (recommendation engine foundation)

**Goal of the project:** a user enters a **price**, a **location** and an **activity category**. The engine clusters
places and activities, then recommends the ones closest to the search. This dataset is the foundation: one row per
real place in the five boroughs, with as many signals as we could collect for clustering and ranking.

## Main outputs

| File | What it is |
|---|---|
| `nyc_places_enriched.parquet` | **The dataset.** 109,986 places, 108 columns, one row per place |
| `../data/places_v1.parquet` | Modeling extract for SideQuest-ML (`build_places_v1.sql`): the 45,440 Google-verified places plus 755 official NYC Parks / GreenThumb places |
| `nyc_events.parquet` | 550 NYC Parks events (time-bound: 2026-11-13 to 2026-11-27); kept separate from places |
| `data/staging/*.parquet` | Each source cleaned on its own (Google, inspections, subway, OSM, Wikidata, ...) |
| `data/raw/` | Untouched downloads, including every Google response (`data/raw/google/places.jsonl`) |

Rebuild everything with `./run_all.sh`. It skips the paid Google step unless you pass `--google`.

## Sources

| Source | Gives us | Linked rows |
|---|---|---|
| **Google Places API (New)**, Text Search by area, 47 place types, 4,768 calls (~$191 list price) | price level and range, rating and count, hours, 5 reviews, AI summaries, ~25 attributes (outdoor seating, kids, dogs, groups, reservable, vegetarian, ...) | 45,440 places |
| **Overture Maps** places (release 2026-11-18.0) | wide coverage of businesses, category taxonomy, brand, contacts | 89k Overture rows, 25.5k linked to Google |
| **NYC Parks Properties** (`enfh-gkve`) | official parks, playgrounds, gardens; acreage | 1,792 parks |
| **NYC 2020 NTAs** (`9nt8-h7nd`) | borough + one of 252 neighborhoods for every place | all |
| **MTA Subway Stations** (`39hk-dx4f`) | nearest station, lines, stations within 800 m, step-free access | all |
| **DOHMH Restaurant Inspections** (`43nn-pn8j`) | health grade A/B/C, score, critical violations (2 yrs), closed flag | 22,310 |
| **OpenStreetMap** (Overpass) | fee/charge, wheelchair, diet tags, OSM hours, capacity | 14,462 |
| **Wikidata** | notability (Wikipedia sitelinks), description, Wikipedia link | 1,836 |
| **NYC libraries / museums directories** (`feuq-due4`, `fn6f-htvy`) | official flags, library system | 124 / 91 |
| **GreenThumb community gardens** (`p78i-pat6`) | gardens + posted hours; 150 gardens added as new rows | 582 |

## Coverage

| | places | Google-verified | real price | rating | AI summary | health grade | Wikidata |
|---|---:|---:|---:|---:|---:|---:|---:|
| Restaurants | 41,565 | 20,509 | 17,663 | 20,028 | 15,235 | 13,565 | 304 |
| Shopping | 18,000 | 2,153 | 1 | 1,938 | 1,047 | 0 | 43 |
| Cafes & Desserts | 11,343 | 5,785 | 3,814 | 5,545 | 3,802 | 4,019 | 31 |
| Sports & Fitness | 7,405 | 1,769 | 1 | 1,614 | 755 | 0 | 37 |
| Parks & Outdoors | 5,982 | 3,494 | 0 (free) | 2,842 | 1,160 | 0 | 316 |
| Bars & Nightlife | 5,904 | 2,795 | 2,154 | 2,679 | 1,897 | 1,773 | 73 |
| Spas & Wellness | 5,646 | 3,296 | 260 | 2,983 | 1,104 | 0 | 7 |
| Attractions & Tours | 5,282 | 2,037 | 0 | 1,594 | 234 | 0 | 502 |
| Museums & Galleries | 3,692 | 1,529 | 0 | 1,387 | 230 | 0 | 216 |
| Shows & Live Events | 3,236 | 1,000 | 7 | 872 | 451 | 0 | 241 |
| Libraries & Bookstores | 1,459 | 827 | 0 | 712 | 304 | 0 | 64 |
| Games & Indoor Fun | 472 | 246 | 0 | 238 | 147 | 0 | 2 |

`google_verified = true` (45,440 rows) is the high-confidence core: Google lists the place as operational, with rich data.
The other 64,546 rows come only from Overture, NYC Parks or GreenThumb. They are useful for coverage, but some will be
closed or duplicated under another name. Weight them down, or filter on `google_verified`.

## Key columns, grouped by how the recommender will use them

**User inputs**
- Category: `activity_category` (12 buckets), `subcategory` (Google primary type or Overture category), `subcategory_label`, `cuisine`, `google_types`
- Location: `lat`, `lng`, `borough`, `neighborhood`, `nta_code`, `address`, `postcode`
- Price: `price_final` (0 = free to 4 = $$$$, always filled) and `price_final_source` (`google` 23,900 / `public_free` 6,711 / `category_estimate` 79,375). Also `price_level` (Google, 0–4), `price_min_usd` / `price_max_usd` (Google per-person range; max NULL = open-ended), `price_tier_estimate`

**Quality and popularity (ranking)**
`rating`, `rating_count`, `reviews_avg_rating`, `latest_review_at`, `wikidata_sitelinks`, `inspection_grade`,
`inspection_score`, `critical_violations_2y`, `closed_at_last_inspection`, `is_chain`, `brand`

**Accessibility and transit (location fit)**
`nearest_subway`, `nearest_subway_m`, `nearest_subway_lines`, `subway_stations_800m`, `subway_lines_800m`,
`ada_subway_800m`, `wheelchair_entrance`, `wheelchair_seating`, `osm_wheelchair`

**When it's open**
`hours_per_week`, `days_open`, `open_weekends`, `open_late` (closes 11 pm or later), `open_24_7`, `opening_hours` (text), `osm_opening_hours`

**Vibe and attributes (clustering features)**
- Booleans (NULL = unknown): `outdoor_seating`, `live_music`, `good_for_children`, `good_for_groups`, `good_for_watching_sports`, `allows_dogs`, `reservable`, `menu_for_children`, `restroom`, `serves_*` (vegetarian, cocktails, beer, wine, brunch, breakfast, lunch, dinner, dessert, coffee), `takeout`, `delivery`, `dine_in`, `accepts_credit_cards`, `cash_only`
- OSM: `osm_fee`, `osm_charge`, `osm_diet_*`, `osm_outdoor_seating`, `osm_capacity`, `osm_internet_access`
- Parks: `acres`

**Text (for embeddings / semantic clustering)**
`generative_summary` (Google AI overview, 26k), `editorial_summary`, `review_summary`, `reviews_text` (up to 5 reviews joined by ` ||| `, 42k), `wikidata_description`

**IDs and provenance**
`master_id`, `google_place_id`, `maps_uri`, `overture_id`, `nycparks_id`, `dohmh_camis`, `osm_key`, `wikidata_qid`,
`official_library_id`, `official_museum_id`, `greenthumb_id`, `link_name_similarity`, `link_distance_m`, `google_fetched_at`

## How records are linked

- Google ↔ Overture: within 120 m, and normalized names with Jaro-Winkler ≥ 0.88 or one name contained in the other. Mutual best match only.
- Google ↔ NYC Parks: the Google point is in or near the park polygon, with a similar name.
- Inspections: name ≥ 0.88 within 120 m, or the same phone number within 300 m with name ≥ 0.75.
- OSM and Wikidata: name ≥ 0.9 / 0.92 with similar name length, within 150 / 250 m. Wikidata is also linked through OSM's `wikidata` tag.
- Every link is one-to-one, so no source record is attached to two places.

## Reproducibility and the frozen v1 snapshot

- **The pipeline is deterministic.** Lists of search types are sorted, and every record-matching step has explicit tie-breakers. Two consecutive full rebuilds give identical output. Before this fix, 24 Google places could flip category between runs, because a place found by several searches took its fallback category from an unsorted list.
- **`../data/places_v1.parquet` is frozen:** the exact rows and values the v1 model was fitted on. New columns are added without touching them using `add_columns_to_places_v1.sql`. Build a fresh extract to a temp path, then join only the new columns by `master_id`. This is how `open_intervals` (weekly opening hours as [start, end) minutes of the week, Sunday 00:00 = 0, from Google's `regularOpeningHours.periods`) and the extra filter fields were added.

## Known gaps and next steps

1. **Price outside food and drink is mostly estimated.** Google returns price for about 85% of restaurants, bars and cafes, but almost never for museums, shows, attractions, gyms or spas. Options: (a) train a price model on the 23,900 real prices (the rule-based estimate agrees with Google only ~53% of the time); (b) collect admission prices for the top museums, attractions and venues from their websites.
2. **Overture-only rows** (64k) aren't verified. Some are closed or duplicates under different names.
3. **Events** cover only a 2-week NYC Parks window, with free/paid guessed from text. For "activities" beyond places, a richer events feed (NYC events calendars, Eventbrite, venue calendars) would add a lot.
4. **Reviews are capped at 5 per place** by Google. Review text has no author names; they were stripped for privacy.
5. **Terms:** Google data is stored under the user's stated permission. OSM data is ODbL (attribution, share-alike if redistributed). NYC Open Data and Wikidata are open.
