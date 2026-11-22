# Staged open data (enrichment layers for nyc_activities)

Free public datasets, one parquet per source, cleaned and clipped to the five boroughs.
Downloaded 2026-11-21. (`google_places.parquet` in this folder comes from a separate process and is not covered here.)

## Rebuild

```bash
./fetch_open_data.sh                 # all sources -> data/raw/<source>/  (about 10 min, mostly polite pauses)
./fetch_open_data.sh osm wikidata    # or just some sources
duckdb < stage_open_data.sql         # -> data/staging/*.parquet  (about 3 s, in-memory)
```

OSM tag groups and Wikidata sub-boxes already on disk are skipped on a re-run; set `OSM_FORCE=1` / `WIKIDATA_FORCE=1` to refetch them.

## Common columns

Every file has `source`, `source_id` (unique within the file), `name`, `lat`, `lng` (WGS84, never null), then the
source-specific columns, then `nta_code`, `neighborhood`, `borough`. These come from a point-in-polygon join against
`data/raw/nta2020.geojson` (2020 NTAs), the same way `nyc_activities` gets them. Points outside every NTA are dropped,
which clips each source to the five boroughs.

## Files

| File | Source / dataset ID | Rows | Key columns |
|---|---|---|---|
| `restaurant_inspections.parquet` | NYC DOHMH Restaurant Inspection Results, [data.cityofnewyork.us `43nn-pn8j`](https://data.cityofnewyork.us/d/43nn-pn8j) | 30,762 | camis, dba, cuisine_description, latest_grade (A/B/C), latest_grade_date, n_inspections, last_inspection_date, last_score, last_action, closed_at_last_inspection, critical_violations_2y, violations_2y, phone, address, zipcode, boro |
| `subway_stations.parquet` | MTA Subway Stations, [data.ny.gov `39hk-dx4f`](https://data.ny.gov/d/39hk-dx4f) | 496 | station_id, complex_id, gtfs_stop_id, stop_name, line, division, daytime_routes, routes (list), structure, in_cbd, ada_code (0/1/2), ada_accessibility (none/full/partial), ada_northbound/southbound, ada_notes |
| `osm_places.parquet` | OpenStreetMap via the Overpass API (`overpass-api.de`) | 24,685 | osm_type, osm_id, amenity, tourism, leisure, historic, primary_tag, cuisine, opening_hours, fee, charge, wheelchair, outdoor_seating, takeaway, delivery, diet_*, website, phone, wikidata, addr_*, brand, operator, capacity, smoking, internet_access, reservation |
| `wikidata_places.parquet` | Wikidata Query Service (SPARQL, `wikibase:box`) | 8,127 | qid, label_en, description, instance_of (pipe-joined labels), instance_qids, sitelinks, enwiki_title, enwiki_url, likely_not_venue |
| `libraries.parquet` | NYC Open Data "LIBRARY", `feuq-due4` | 216 | system (NYPL 92 / BPL 59 / QPL 65), address, city, zip, url, bin, bbl |
| `museums.parquet` | NYC Open Data "MUSEUM", `fn6f-htvy` | 128 | address, city, zip, phone, url |
| `greenthumb_gardens.parquet` | GreenThumb Garden Info, `p78i-pat6` | 634 | parks_id, address, cross_streets, zipcode, status, is_active, jurisdiction, hours_mon … hours_sun, has_posted_hours, coords_from_polygon |
| `farmers_markets.parquet` | NYC Farmers Markets, `8vwk-6iz2` | 102 | season_year, address, days_of_operation, hours_of_operation, season_begin, accepts_ebt, open_year_round, health_dept_cooking_demos |
| `parks_events.parquet` | NYC Parks Public Events – Upcoming 14 Days, `w3wp-dpdi` | 550 | title, event_date, start_time, end_time, start_ts, end_ts, location, park_names, park_ids, categories (list), instructor, url, registration_url, requires_registration, mentions_free, mentions_price, description, has_multiple_locations |

Source-specific notes:

- **Restaurant inspections**: the raw file has one row per violation (295,671 rows for 31,582 restaurants). It is aggregated to one row per CAMIS.
  `latest_grade` is the most recent A/B/C grade; pending grades (Z, P, N) are ignored. `n_inspections` counts distinct
  inspection dates. Violation counts cover the 2 years before the staging run (they use `current_date`).
- **OSM**: four Overpass queries, one per tag group (amenity / tourism / leisure / historic), restricted to the bbox
  40.477,-74.259,40.918,-73.700. Nodes, ways and relations are included; ways and relations use their `center` point.
  Unnamed features are dropped. Features matching several groups appear once. `primary_tag` is the first of
  amenity, tourism, leisure, historic. `website` and `phone` fall back to `contact:*`.
- **Wikidata**: items with a coordinate (P625) in the bbox **and** an English Wikipedia article. They are queried in a
  2x2 grid of sub-boxes, plus one query for the labels of the instance-of classes. Items with several coordinates keep one.
  `sitelinks` (the number of Wikipedia/Wikimedia language editions) is the popularity/notability signal.
- **Farmers markets**: the dataset has one row per market per year, from 2009 to 2026. Only the latest year (2026) is kept.
- **Parks events**: the feed is a rolling window. Each pull is archived as `data/raw/parks_events/parks_events_<date>.json`,
  and the staged file is built from `parks_events_latest.json`. **Covered dates: 2026-11-13 to 2026-11-27.**

## Licences and terms

- NYC Open Data (DOHMH, Libraries, Museums, GreenThumb, Farmers Markets, Parks Events): free to use under the
  NYC Open Data Terms of Use, provided as-is with no warranty.
- data.ny.gov (MTA): NY Open Data terms of use, free to use.
- OpenStreetMap: © OpenStreetMap contributors, **ODbL 1.0**. You must give attribution, and a database derived from it
  must be shared alike if you distribute it.
- Wikidata: CC0. The Wikipedia article text is CC BY-SA, but only titles and URLs are kept here.

## Known caveats

- **Restaurants**: 820 of the 31,582 CAMIS have no coordinates (lat/lng 0 or missing), so they are dropped. 3,869 have not
  been inspected yet (placeholder date 1900-01-01), so `n_inspections` = 0 and `latest_grade` is null. Overall
  6,469 restaurants have no A/B/C grade. A few grades are years old: 133 date from before 2022.
- **Museums (`fn6f-htvy`)** was last updated in **2014**. It is stale (some museums have closed or moved), has no
  hours or prices, and its zip codes came as floats ("10004.0", fixed here). **Libraries (`feuq-due4`)** was last
  updated in 2016. Branch locations are stable, but there are no hours.
- **GreenThumb**: 56 gardens had no lat/lon, so they get a point on the garden polygon (`coords_from_polygon` = true).
  81 are not active (closed, under construction, not GreenThumb, or inactive). Use `is_active`. 198 post no hours at all.
- **Farmers markets 2026**: `season_begin` is empty for every row, and there is no season-end column. Use
  `open_year_round`, `days_of_operation` and `hours_of_operation`, which are free text.
- **Parks events**: there is no structured cost or free field. `mentions_free` and `mentions_price` are regex heuristics on
  the description, and most Parks events are free. The source feed was last refreshed on 2026-11-13, so about half of
  the window is already in the past. 3 events list several coordinates; only the first is kept.
- **Wikidata** includes things that are not venues but have coordinates: neighbourhoods, organisations headquartered in NYC,
  recurring events, and even a constructed language. `likely_not_venue` is a regex heuristic on the instance-of labels that flags 809 of them.
  It is imperfect in both directions. The median item has only 2 sitelinks.
- **OSM**: tag coverage is patchy (opening_hours on 42% of rows, wheelchair on 12%; cuisine on 80% of food places).
  The Overpass public servers were overloaded during this pull (502/504 responses). The script retries and falls back to
  mirrors, so a re-run may be needed.
- **Subway**: the file has one row per station (496). Several stations share a `complex_id` (445 complexes), because a
  transfer complex is split by line.
