-- ============================================================
-- Enrich places_master with free NYC sources (data/staging/*.parquet, from stage_open_data.sql)
--   transit access (MTA subway), DOHMH inspection grades, OpenStreetMap tags, Wikidata notability,
--   official library / museum / GreenThumb garden records.
-- Output: places_enriched (table) -> nyc_places_enriched.parquet, plus nyc_events.parquet
-- Run   : duckdb nyc.duckdb < enrich_master.sql      (after build_master.sql)
-- ============================================================
.bail on
LOAD spatial;

CREATE OR REPLACE MACRO haversine_m(lat1, lng1, lat2, lng2) AS
  2 * 6371000 * asin(sqrt(pow(sin(radians(lat2 - lat1) / 2), 2) +
      cos(radians(lat1)) * cos(radians(lat2)) * pow(sin(radians(lng2 - lng1) / 2), 2)));
CREATE OR REPLACE MACRO len_ratio(a, b) AS least(length(a), length(b)) / greatest(length(a), length(b), 1);
CREATE OR REPLACE MACRO digits10(s) AS right(regexp_replace(coalesce(s, ''), '[^0-9]', '', 'g'), 10);

-- grid cells: ~220 m; candidate pairs = same or neighbouring cell
CREATE OR REPLACE TEMP TABLE m AS
SELECT master_id, name, activity_category, subcategory, lat, lng, phone,
       norm_name(name) AS nkey, digits10(phone) AS ph,
       floor(lat / 0.002)::INT AS cy, floor(lng / 0.0026)::INT AS cx
FROM places_master;

CREATE OR REPLACE MACRO cells(t) AS TABLE
  SELECT t.*, floor(t.lat / 0.002)::INT + dy AS cy, floor(t.lng / 0.0026)::INT + dx AS cx
  FROM query_table(t) t, (SELECT unnest([-1,0,1]) AS dy), (SELECT unnest([-1,0,1]) AS dx);

-- ---------- 1) Transit: nearest subway station, lines there, stations within walking distance ----------
CREATE OR REPLACE TEMP TABLE s AS
SELECT complex_id, stop_name, routes, ada_accessibility, lat, lng FROM 'data/staging/subway_stations.parquet';

CREATE OR REPLACE TEMP TABLE transit AS
WITH d AS (
  SELECT m.master_id, s.stop_name, s.routes, s.ada_accessibility, s.complex_id,
         haversine_m(m.lat, m.lng, s.lat, s.lng) AS dist
  FROM m JOIN s ON abs(m.lat - s.lat) < 0.09 AND abs(m.lng - s.lng) < 0.12      -- ~10 km box
)
SELECT master_id,
  arg_min(stop_name, dist)                                   AS nearest_subway,
  round(min(dist))                                           AS nearest_subway_m,
  len(arg_min(routes, dist))                                 AS nearest_subway_lines,
  count(DISTINCT complex_id) FILTER (WHERE dist <= 800)      AS subway_stations_800m,
  len(list_distinct(flatten(list(routes) FILTER (WHERE dist <= 800)))) AS subway_lines_800m,
  bool_or(ada_accessibility = 'full' AND dist <= 800)        AS ada_subway_800m
FROM d GROUP BY master_id;

-- ---------- 2) DOHMH restaurant inspections (food & drink only) ----------
CREATE OR REPLACE TEMP TABLE ri AS
SELECT camis, dba, cuisine_description, latest_grade, latest_grade_date, last_inspection_date, last_score,
       closed_at_last_inspection, critical_violations_2y, violations_2y, n_inspections,
       lat, lng, norm_name(dba) AS nkey, digits10(phone) AS ph
FROM 'data/staging/restaurant_inspections.parquet';

CREATE OR REPLACE TEMP TABLE ri_link AS
WITH c AS (
  SELECT m.master_id, r.camis,
         jaro_winkler_similarity(m.nkey, r.nkey) AS sim,
         haversine_m(m.lat, m.lng, r.lat, r.lng) AS dist,
         (m.ph <> '' AND m.ph = r.ph) AS same_phone
  FROM (SELECT * FROM m WHERE activity_category IN ('Restaurants','Cafes & Desserts','Bars & Nightlife')) m
  JOIN cells('ri') r ON m.cy = r.cy AND m.cx = r.cx
), ok AS (
  SELECT *, (CASE WHEN same_phone THEN 1 ELSE 0 END) + sim - dist / 500 AS score FROM c
  WHERE (sim >= 0.88 AND dist <= 120) OR (same_phone AND dist <= 300 AND sim >= 0.75)
), r AS (
  SELECT *, row_number() OVER (PARTITION BY master_id ORDER BY score DESC) a,
            row_number() OVER (PARTITION BY camis ORDER BY score DESC) b FROM ok
)
SELECT master_id, camis FROM r WHERE a = 1 AND b = 1;

-- ---------- 3) OpenStreetMap tags ----------
CREATE OR REPLACE TEMP TABLE osm AS
SELECT source_id AS osm_key, name, lat, lng, norm_name(name) AS nkey, primary_tag, cuisine, opening_hours, fee, charge,
       wheelchair, outdoor_seating, diet_vegetarian, diet_vegan, diet_halal, diet_kosher, wikidata, capacity, internet_access
FROM 'data/staging/osm_places.parquet';

CREATE OR REPLACE TEMP TABLE osm_link AS
WITH c AS (
  SELECT m.master_id, o.osm_key, m.nkey AS m_nkey, o.nkey AS o_nkey, jaro_winkler_similarity(m.nkey, o.nkey) AS sim,
         haversine_m(m.lat, m.lng, o.lat, o.lng) AS dist
  FROM m JOIN cells('osm') o ON m.cy = o.cy AND m.cx = o.cx
  WHERE m.nkey <> '' AND o.nkey <> ''
), r AS (
  SELECT *, row_number() OVER (PARTITION BY master_id ORDER BY sim - dist / 1000 DESC) a,
            row_number() OVER (PARTITION BY osm_key ORDER BY sim - dist / 1000 DESC) b
  FROM c WHERE sim >= 0.9 AND dist <= 150 AND len_ratio(m_nkey, o_nkey) >= 0.75
)
SELECT master_id, osm_key FROM r WHERE a = 1 AND b = 1;

-- ---------- 4) Wikidata notability (via OSM's wikidata tag, else name + distance) ----------
CREATE OR REPLACE TEMP TABLE wd AS
SELECT qid, label_en, description, instance_of, sitelinks, enwiki_url, likely_not_venue, lat, lng,
       norm_name(label_en) AS nkey
FROM 'data/staging/wikidata_places.parquet';

CREATE OR REPLACE TEMP TABLE wd_link AS
WITH via_osm AS (
  SELECT l.master_id, o.wikidata AS qid, 2.0 AS score
  FROM osm_link l JOIN osm o USING (osm_key) WHERE o.wikidata IN (SELECT qid FROM wd)
), via_name AS (
  SELECT m.master_id, w.qid, jaro_winkler_similarity(m.nkey, w.nkey) - haversine_m(m.lat, m.lng, w.lat, w.lng) / 1000 AS score
  FROM m JOIN cells('wd') w ON m.cy = w.cy AND m.cx = w.cx
  WHERE NOT coalesce(w.likely_not_venue, false) AND m.nkey <> '' AND w.nkey <> ''
    AND jaro_winkler_similarity(m.nkey, w.nkey) >= 0.92 AND haversine_m(m.lat, m.lng, w.lat, w.lng) <= 250
    AND len_ratio(m.nkey, w.nkey) >= 0.75
), r AS (
  SELECT *, row_number() OVER (PARTITION BY master_id ORDER BY score DESC) a,
            row_number() OVER (PARTITION BY qid ORDER BY score DESC) b
  FROM (SELECT * FROM via_osm UNION ALL SELECT * FROM via_name)
)
SELECT master_id, qid FROM r WHERE a = 1 AND b = 1;

-- ---------- 5) Official directories: libraries, museums (flags) ----------
CREATE OR REPLACE MACRO official_link(tbl, cats) AS TABLE
  WITH c AS (
    SELECT m.master_id, t.source_id,
           jaro_winkler_similarity(m.nkey, norm_name(t.name)) - haversine_m(m.lat, m.lng, t.lat, t.lng) / 1000 AS score
    FROM (SELECT * FROM m WHERE list_contains(cats, activity_category)) m
    JOIN cells(tbl) t ON m.cy = t.cy AND m.cx = t.cx
    WHERE haversine_m(m.lat, m.lng, t.lat, t.lng) <= 200
      AND jaro_winkler_similarity(m.nkey, norm_name(t.name)) >= 0.8
  ), r AS (
    SELECT *, row_number() OVER (PARTITION BY master_id ORDER BY score DESC) a,
              row_number() OVER (PARTITION BY source_id ORDER BY score DESC) b FROM c
  )
  SELECT master_id, source_id FROM r WHERE a = 1 AND b = 1;

CREATE OR REPLACE TEMP TABLE lib AS SELECT * FROM 'data/staging/libraries.parquet';
CREATE OR REPLACE TEMP TABLE mus AS SELECT * FROM 'data/staging/museums.parquet';
CREATE OR REPLACE TEMP TABLE lib_link AS SELECT * FROM official_link('lib', ['Libraries & Bookstores']);
CREATE OR REPLACE TEMP TABLE mus_link AS SELECT * FROM official_link('mus', ['Museums & Galleries','Attractions & Tours']);

-- ---------- 6) GreenThumb community gardens: link, and add the ones we don't have ----------
CREATE OR REPLACE TEMP TABLE gt AS SELECT * FROM 'data/staging/greenthumb_gardens.parquet';
CREATE OR REPLACE TEMP TABLE gt_link AS SELECT * FROM official_link('gt', ['Parks & Outdoors']);

-- ---------- 7) Assemble ----------
CREATE OR REPLACE TABLE places_enriched AS
SELECT pm.*,
  -- transit
  t.nearest_subway, t.nearest_subway_m, t.nearest_subway_lines, t.subway_stations_800m, t.subway_lines_800m,
  coalesce(t.ada_subway_800m, false) AS ada_subway_800m,
  -- health inspections
  r.camis AS dohmh_camis, r.cuisine_description AS dohmh_cuisine, r.latest_grade AS inspection_grade,
  r.latest_grade_date AS inspection_grade_date, r.last_score AS inspection_score,
  r.critical_violations_2y, r.closed_at_last_inspection,
  -- OSM
  ol.osm_key, o.fee AS osm_fee, o.charge AS osm_charge, o.wheelchair AS osm_wheelchair,
  o.outdoor_seating AS osm_outdoor_seating, o.diet_vegetarian AS osm_diet_vegetarian, o.diet_vegan AS osm_diet_vegan,
  o.diet_halal AS osm_diet_halal, o.diet_kosher AS osm_diet_kosher, o.opening_hours AS osm_opening_hours,
  o.cuisine AS osm_cuisine, o.capacity AS osm_capacity, o.internet_access AS osm_internet_access,
  -- Wikidata
  w.qid AS wikidata_qid, w.sitelinks AS wikidata_sitelinks, w.enwiki_url, w.description AS wikidata_description,
  w.instance_of AS wikidata_instance_of,
  -- official directories
  ll.source_id AS official_library_id, lb.system AS library_system,
  ml.source_id AS official_museum_id,
  gl.source_id AS greenthumb_id
FROM places_master pm
LEFT JOIN transit t   USING (master_id)
LEFT JOIN ri_link rl  USING (master_id) LEFT JOIN ri r ON r.camis = rl.camis
LEFT JOIN osm_link ol USING (master_id) LEFT JOIN osm o ON o.osm_key = ol.osm_key
LEFT JOIN wd_link wl  USING (master_id) LEFT JOIN wd w ON w.qid = wl.qid
LEFT JOIN lib_link ll USING (master_id) LEFT JOIN lib lb ON lb.source_id = ll.source_id
LEFT JOIN mus_link ml USING (master_id)
LEFT JOIN gt_link gl  USING (master_id);

-- GreenThumb gardens not already present -> new rows (free, outdoor)
INSERT INTO places_enriched BY NAME
SELECT 'greenthumb:' || g.source_id AS master_id, g.name, 'Parks & Outdoors' AS activity_category,
       'community_garden' AS subcategory, g.lat, g.lng, g.borough, g.neighborhood, g.nta_code, g.address,
       g.zipcode AS postcode, 0 AS price_final, 'public_free' AS price_final_source, 0 AS price_tier_estimate,
       false AS google_verified, g.source_id AS greenthumb_id, false AS is_chain, false AS ada_subway_800m,
       concat_ws(' | ', 'Mon: ' || g.hours_mon, 'Tue: ' || g.hours_tue, 'Wed: ' || g.hours_wed, 'Thu: ' || g.hours_thu,
                 'Fri: ' || g.hours_fri, 'Sat: ' || g.hours_sat, 'Sun: ' || g.hours_sun) AS opening_hours
FROM gt g
WHERE coalesce(g.is_active, true) AND g.source_id NOT IN (SELECT source_id FROM gt_link);

-- transit for the new garden rows
UPDATE places_enriched pe SET
  nearest_subway = x.nearest_subway, nearest_subway_m = x.nearest_subway_m, nearest_subway_lines = x.nearest_subway_lines,
  subway_stations_800m = x.subway_stations_800m, subway_lines_800m = x.subway_lines_800m, ada_subway_800m = x.ada_subway_800m
FROM (
  WITH d AS (
    SELECT p.master_id, s.stop_name, s.routes, s.ada_accessibility, s.complex_id, haversine_m(p.lat, p.lng, s.lat, s.lng) AS dist
    FROM places_enriched p JOIN s ON abs(p.lat - s.lat) < 0.09 AND abs(p.lng - s.lng) < 0.12
    WHERE p.master_id LIKE 'greenthumb:%'
  )
  SELECT master_id, arg_min(stop_name, dist) nearest_subway, round(min(dist)) nearest_subway_m,
         len(arg_min(routes, dist)) nearest_subway_lines,
         count(DISTINCT complex_id) FILTER (WHERE dist <= 800) subway_stations_800m,
         len(list_distinct(flatten(list(routes) FILTER (WHERE dist <= 800)))) subway_lines_800m,
         coalesce(bool_or(ada_accessibility = 'full' AND dist <= 800), false) ada_subway_800m
  FROM d GROUP BY master_id
) x WHERE pe.master_id = x.master_id;

-- Places closed at their last health inspection are flagged, not dropped (may have reopened).
COPY places_enriched TO 'nyc_places_enriched.parquet' (FORMAT parquet);
COPY (SELECT * FROM 'data/staging/parks_events.parquet') TO 'nyc_events.parquet' (FORMAT parquet);

SELECT count(*) AS places,
       count(nearest_subway_m) AS with_transit,
       count(dohmh_camis) AS with_inspection,
       count(osm_key) AS with_osm,
       count(wikidata_qid) AS with_wikidata,
       count(official_library_id) AS official_libraries,
       count(official_museum_id) AS official_museums,
       count(greenthumb_id) AS greenthumb_gardens
FROM places_enriched;
