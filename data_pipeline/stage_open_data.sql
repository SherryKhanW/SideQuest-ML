-- ============================================================
-- Stage free public datasets (downloaded by fetch_open_data.sh) into clean parquet files.
-- Input : data/raw/<source>/...           (see fetch_open_data.sh)
--         data/raw/nta2020.geojson         (NYC Open Data 9nt8-h7nd, for borough/neighborhood + 5-borough clip)
-- Output: data/staging/<source>.parquet   one file per source
-- Run   : duckdb < stage_open_data.sql      (in-memory; only reads data/raw, writes data/staging)
--
-- Every output has: source, source_id, name, lat, lng (WGS84, non-null), nta_code, neighborhood,
-- borough, then source-specific columns. Rows outside the five boroughs (no NTA hit) are dropped.
-- ============================================================
.bail on
LOAD spatial;

CREATE OR REPLACE TEMP TABLE stg_nta AS
SELECT nta2020 AS nta_code, ntaname AS neighborhood, boroname AS borough, geom
FROM ST_Read('data/raw/nta2020.geojson');

-- Attach NTA attributes to any relation with lat/lng; inner join = clip to the five boroughs.
CREATE OR REPLACE TEMP MACRO with_nta(t) AS TABLE
SELECT t.*, n.nta_code, n.neighborhood, n.borough
FROM query_table(t) t
JOIN stg_nta n ON ST_Contains(n.geom, ST_Point(t.lng, t.lat))
WHERE t.lat IS NOT NULL AND t.lng IS NOT NULL;

-- ---------- 1) DOHMH restaurant inspections: one row per CAMIS ----------
CREATE OR REPLACE TEMP TABLE raw_insp AS
SELECT * REPLACE (CAST(inspection_date AS DATE) AS inspection_date, CAST(grade_date AS DATE) AS grade_date)
FROM read_csv('data/raw/restaurant_inspections/restaurant_inspections.csv', header = true,
     types = {'camis': 'VARCHAR', 'zipcode': 'VARCHAR', 'phone': 'VARCHAR', 'building': 'VARCHAR',
              'violation_code': 'VARCHAR', 'score': 'INTEGER', 'latitude': 'DOUBLE', 'longitude': 'DOUBLE'});

CREATE OR REPLACE TEMP TABLE r_restaurants AS
WITH agg AS (
  SELECT camis,
    arg_max(dba, inspection_date)                 AS dba,
    arg_max(cuisine_description, inspection_date) AS cuisine_description,
    arg_max(boro, inspection_date)                AS boro,
    arg_max(trim(coalesce(building, '') || ' ' || coalesce(street, '')), inspection_date) AS address,
    arg_max(zipcode, inspection_date)             AS zipcode,
    arg_max(phone, inspection_date)               AS phone,
    arg_max(latitude,  inspection_date) FILTER (WHERE latitude  <> 0) AS lat,
    arg_max(longitude, inspection_date) FILTER (WHERE longitude <> 0) AS lng,
    arg_max(grade, grade_date) FILTER (WHERE grade IN ('A', 'B', 'C')) AS latest_grade,
    max(grade_date)            FILTER (WHERE grade IN ('A', 'B', 'C')) AS latest_grade_date,
    count(DISTINCT inspection_date) FILTER (WHERE inspection_date > DATE '1901-01-01') AS n_inspections,
    max(inspection_date) FILTER (WHERE inspection_date > DATE '1901-01-01') AS last_inspection_date,
    arg_max(score, inspection_date) FILTER (WHERE score IS NOT NULL AND inspection_date > DATE '1901-01-01') AS last_score,
    arg_max(action, inspection_date) FILTER (WHERE inspection_date > DATE '1901-01-01') AS last_action,
    count(DISTINCT (inspection_date, violation_code))
      FILTER (WHERE critical_flag = 'Critical' AND inspection_date >= current_date - INTERVAL 2 YEAR) AS critical_violations_2y,
    count(DISTINCT (inspection_date, violation_code))
      FILTER (WHERE violation_code IS NOT NULL AND inspection_date >= current_date - INTERVAL 2 YEAR) AS violations_2y
  FROM raw_insp
  GROUP BY camis
)
SELECT 'dohmh_restaurant_inspections' AS source, camis AS source_id, dba AS name, lat, lng,
       camis, dba, cuisine_description, latest_grade, latest_grade_date, n_inspections,
       last_inspection_date, last_score, last_action,
       coalesce(last_action ILIKE '%closed by dohmh%', false) AS closed_at_last_inspection,
       critical_violations_2y, violations_2y, phone, address, zipcode, boro
FROM agg;

COPY (SELECT * FROM with_nta('r_restaurants') ORDER BY source_id)
TO 'data/staging/restaurant_inspections.parquet' (FORMAT parquet);

-- ---------- 2) MTA subway stations ----------
CREATE OR REPLACE TEMP TABLE r_subway AS
SELECT 'mta_subway_stations' AS source, CAST(station_id AS VARCHAR) AS source_id, stop_name AS name,
       CAST(gtfs_latitude AS DOUBLE) AS lat, CAST(gtfs_longitude AS DOUBLE) AS lng,
       CAST(station_id AS VARCHAR) AS station_id, CAST(complex_id AS VARCHAR) AS complex_id,
       gtfs_stop_id, stop_name, line, division, daytime_routes,
       string_split(daytime_routes, ' ') AS routes,
       structure, borough AS mta_borough_code, CAST(cbd AS BOOLEAN) AS in_cbd,
       CAST(ada AS INTEGER) AS ada_code,                      -- 0 = no, 1 = fully, 2 = partially accessible
       CASE CAST(ada AS INTEGER) WHEN 1 THEN 'full' WHEN 2 THEN 'partial' ELSE 'none' END AS ada_accessibility,
       CAST(ada_northbound AS BOOLEAN) AS ada_northbound, CAST(ada_southbound AS BOOLEAN) AS ada_southbound,
       nullif(ada_notes, 'NaN') AS ada_notes
FROM read_csv('data/raw/subway_stations/subway_stations.csv', header = true, all_varchar = true);

COPY (SELECT * FROM with_nta('r_subway') ORDER BY source_id)
TO 'data/staging/subway_stations.parquet' (FORMAT parquet);

-- ---------- 3) OpenStreetMap (Overpass) ----------
CREATE OR REPLACE TEMP TABLE raw_osm AS
SELECT e.type AS osm_type, e.id AS osm_id,
       coalesce(e.lat, e.center.lat) AS lat, coalesce(e.lon, e.center.lon) AS lng, e.tags AS tags
FROM (
  SELECT unnest(elements) AS e
  FROM read_json('data/raw/osm/osm_*.json', format = 'auto',
       columns = {'elements': 'STRUCT(type VARCHAR, id BIGINT, lat DOUBLE, lon DOUBLE,
                                      center STRUCT(lat DOUBLE, lon DOUBLE), tags MAP(VARCHAR, VARCHAR))[]'})
);

CREATE OR REPLACE TEMP TABLE r_osm AS
WITH d AS (  -- a feature can match several tag groups (e.g. a historic museum); keep one copy
  SELECT DISTINCT ON (osm_type, osm_id) * FROM raw_osm ORDER BY osm_type, osm_id
)
SELECT 'openstreetmap' AS source, osm_type || '/' || osm_id AS source_id, tags['name'] AS name, lat, lng,
       osm_type, osm_id,
       tags['amenity'] AS amenity, tags['tourism'] AS tourism, tags['leisure'] AS leisure, tags['historic'] AS historic,
       coalesce('amenity=' || tags['amenity'], 'tourism=' || tags['tourism'],
                'leisure=' || tags['leisure'], 'historic=' || tags['historic']) AS primary_tag,
       tags['cuisine'] AS cuisine, tags['opening_hours'] AS opening_hours, tags['fee'] AS fee, tags['charge'] AS charge,
       tags['wheelchair'] AS wheelchair, tags['outdoor_seating'] AS outdoor_seating, tags['takeaway'] AS takeaway,
       tags['delivery'] AS delivery, tags['diet:vegetarian'] AS diet_vegetarian, tags['diet:vegan'] AS diet_vegan,
       tags['diet:halal'] AS diet_halal, tags['diet:kosher'] AS diet_kosher,
       coalesce(tags['website'], tags['contact:website']) AS website,
       coalesce(tags['phone'], tags['contact:phone']) AS phone, tags['wikidata'] AS wikidata,
       tags['addr:housenumber'] AS addr_housenumber, tags['addr:street'] AS addr_street, tags['addr:postcode'] AS addr_postcode,
       tags['brand'] AS brand, tags['operator'] AS operator, tags['capacity'] AS capacity, tags['smoking'] AS smoking,
       tags['internet_access'] AS internet_access, tags['reservation'] AS reservation
FROM d
WHERE nullif(trim(tags['name']), '') IS NOT NULL;

COPY (SELECT * FROM with_nta('r_osm') ORDER BY source_id)
TO 'data/staging/osm_places.parquet' (FORMAT parquet);

-- ---------- 4) Wikidata items with an English Wikipedia article ----------
CREATE OR REPLACE TEMP TABLE wd_inst_labels AS
SELECT replace(inst, 'http://www.wikidata.org/entity/', '') AS qid, instLabel AS label
FROM read_csv('data/raw/wikidata/instance_labels.csv', header = true, all_varchar = true);

CREATE OR REPLACE TEMP TABLE r_wikidata AS
WITH raw AS (
  SELECT replace(item, 'http://www.wikidata.org/entity/', '') AS qid, itemLabel AS label,
         itemDescription AS description, CAST(lat AS DOUBLE) AS lat, CAST(lng AS DOUBLE) AS lng,
         CAST(sitelinks AS INTEGER) AS sitelinks, article, instance_qids
  FROM read_csv('data/raw/wikidata/wikidata_*.csv', header = true, all_varchar = true, union_by_name = true)
),
one AS (  -- sub-boxes overlap on edges and items can carry several coordinates: keep one row per QID
  SELECT DISTINCT ON (qid) * FROM raw ORDER BY qid, lat, lng
),
inst AS (
  SELECT o.qid, string_agg(DISTINCT l.label, '|' ORDER BY l.label) AS instance_of
  FROM one o, unnest(string_split(o.instance_qids, '|')) AS u(iq)
  LEFT JOIN wd_inst_labels l ON l.qid = u.iq
  GROUP BY o.qid
)
SELECT 'wikidata' AS source, o.qid AS source_id, coalesce(o.label, o.qid) AS name, o.lat, o.lng,
       o.qid, o.label AS label_en, o.description, i.instance_of, nullif(o.instance_qids, '') AS instance_qids,
       o.sitelinks, url_decode(replace(o.article, 'https://en.wikipedia.org/wiki/', '')) AS enwiki_title,
       o.article AS enwiki_url,
       -- Heuristic: areas, organisations, languages, events etc. that carry a coordinate but are not
       -- visitable venues. Anything that also has a venue-like class (museum, theatre, park, ...) is kept.
       coalesce(regexp_matches(i.instance_of,
         '(?i)\b(city|borough|neighborhood|neighbourhood|county|census tract|language|organization|organisation|company|business|enterprise|association|charity|foundation|newspaper|magazine|band|record label|sports team|event|election|battle|disaster|fire|shipwreck|human|family)\b')
         AND NOT regexp_matches(i.instance_of,
         '(?i)(museum|library|park|garden|theat|cinema|club|venue|restaurant|bar\b|pub\b|caf|gallery|zoo|aquarium|stadium|arena|church|cathedral|synagogue|mosque|temple|monument|memorial|statue|landmark|building|bridge|tower|market|hall|centre|center|beach|island|attraction)'),
         false) AS likely_not_venue
FROM one o LEFT JOIN inst i USING (qid);

COPY (SELECT * FROM with_nta('r_wikidata') ORDER BY sitelinks DESC, source_id)
TO 'data/staging/wikidata_places.parquet' (FORMAT parquet);

-- ---------- 5a) Public libraries (NYPL / BPL / QPL) ----------
CREATE OR REPLACE TEMP TABLE r_libraries AS
SELECT 'nyc_libraries' AS source,
       coalesce(nullif(bin, ''), md5(name || coalesce(housenum, '') || coalesce(streetname, ''))) AS source_id,
       name, the_geom.coordinates[2] AS lat, the_geom.coordinates[1] AS lng,
       system, trim(coalesce(housenum, '') || ' ' || coalesce(streetname, '')) AS address, city, zip, url, bin, bbl
FROM read_json('data/raw/libraries/libraries.json', format = 'array',
     columns = {'the_geom': 'STRUCT(type VARCHAR, coordinates DOUBLE[])', 'name': 'VARCHAR', 'streetname': 'VARCHAR',
                'housenum': 'VARCHAR', 'city': 'VARCHAR', 'zip': 'VARCHAR', 'url': 'VARCHAR', 'bin': 'VARCHAR',
                'bbl': 'VARCHAR', 'system': 'VARCHAR'});

COPY (SELECT * FROM with_nta('r_libraries') ORDER BY system, name)
TO 'data/staging/libraries.parquet' (FORMAT parquet);

-- ---------- 5b) Museums ----------
CREATE OR REPLACE TEMP TABLE r_museums AS
SELECT 'nyc_museums' AS source, md5(name || coalesce(adress1, '')) AS source_id,
       name, the_geom.coordinates[2] AS lat, the_geom.coordinates[1] AS lng,
       nullif(trim(concat_ws(', ', nullif(adress1, ''), nullif(address2, ''))), '') AS address, city,
       regexp_replace(zip, '\.0$', '') AS zip, tel AS phone, url
FROM read_json('data/raw/museums/museums.json', format = 'array',
     columns = {'the_geom': 'STRUCT(type VARCHAR, coordinates DOUBLE[])', 'name': 'VARCHAR', 'tel': 'VARCHAR',
                'url': 'VARCHAR', 'adress1': 'VARCHAR', 'address2': 'VARCHAR', 'city': 'VARCHAR', 'zip': 'VARCHAR'});

COPY (SELECT * FROM with_nta('r_museums') ORDER BY name)
TO 'data/staging/museums.parquet' (FORMAT parquet);

-- ---------- 5c) GreenThumb community gardens ----------
CREATE OR REPLACE TEMP TABLE r_gardens AS
SELECT 'greenthumb_gardens' AS source, parksid AS source_id, gardenname AS name,
       -- ~10% of gardens have no lat/lon; fall back to a point on the garden polygon
       coalesce(CAST(lat AS DOUBLE), ST_Y(ST_PointOnSurface(ST_GeomFromText(multipolygon)))) AS lat,
       coalesce(CAST(lon AS DOUBLE), ST_X(ST_PointOnSurface(ST_GeomFromText(multipolygon)))) AS lng,
       (lat IS NULL) AS coords_from_polygon,
       parksid AS parks_id, address, crossstreets AS cross_streets, zipcode, borough AS borough_code,
       status, juris AS jurisdiction, status LIKE 'Active%' AS is_active,
       openhrsm AS hours_mon, openhrstu AS hours_tue, openhrsw AS hours_wed, openhrsth AS hours_thu,
       openhrsf AS hours_fri, openhrssa AS hours_sat, openhrssu AS hours_sun,
       (coalesce(openhrsm, openhrstu, openhrsw, openhrsth, openhrsf, openhrssa, openhrssu) IS NOT NULL) AS has_posted_hours
FROM read_csv('data/raw/greenthumb_gardens/greenthumb_gardens.csv', header = true, all_varchar = true);

COPY (SELECT * FROM with_nta('r_gardens') ORDER BY source_id)
TO 'data/staging/greenthumb_gardens.parquet' (FORMAT parquet);

-- ---------- 5d) Farmers markets (latest season only) ----------
CREATE OR REPLACE TEMP TABLE r_markets AS
WITH m AS (
  SELECT * FROM read_csv('data/raw/farmers_markets/farmers_markets.csv', header = true, all_varchar = true)
)
SELECT 'nyc_farmers_markets' AS source, md5(marketname || coalesce(streetaddress, '')) AS source_id,
       marketname AS name, CAST(latitude AS DOUBLE) AS lat, CAST(longitude AS DOUBLE) AS lng,
       CAST(year AS INTEGER) AS season_year, streetaddress AS address, borough AS market_borough,
       daysoperation AS days_of_operation, hoursoperations AS hours_of_operation, season_begin,
       accepts_ebt = 'Yes' AS accepts_ebt, open_year_round = 'Yes' AS open_year_round,
       nyc_dept_of_health_cooking = 'Yes' AS health_dept_cooking_demos
FROM m
WHERE year = (SELECT max(year) FROM m);

COPY (SELECT * FROM with_nta('r_markets') ORDER BY name)
TO 'data/staging/farmers_markets.parquet' (FORMAT parquet);

-- ---------- 5e) NYC Parks public events (rolling 14-day window; time-bound) ----------
CREATE OR REPLACE TEMP TABLE r_events AS
WITH e AS (
  SELECT *,
    string_split(trim(string_split(coordinates, ';')[1]), ',') AS xy
  FROM read_json('data/raw/parks_events/parks_events_latest.json', format = 'array',
       columns = {'guid': 'VARCHAR', 'title': 'VARCHAR', 'description': 'VARCHAR', 'starttime': 'TIMESTAMP',
                  'endtime': 'TIMESTAMP', 'location': 'VARCHAR', 'parknames': 'VARCHAR', 'parkids': 'VARCHAR',
                  'categories': 'VARCHAR', 'coordinates': 'VARCHAR', 'instructor': 'VARCHAR',
                  'link': 'STRUCT(url VARCHAR)', 'registration_url': 'STRUCT(url VARCHAR)',
                  'registration_description': 'VARCHAR'})
)
SELECT 'nyc_parks_events' AS source, guid AS source_id, title AS name,
       try_cast(trim(xy[1]) AS DOUBLE) AS lat, try_cast(trim(xy[2]) AS DOUBLE) AS lng,
       title, CAST(starttime AS DATE) AS event_date, CAST(starttime AS TIME) AS start_time,
       CAST(endtime AS TIME) AS end_time, starttime AS start_ts, endtime AS end_ts,
       location, parknames AS park_names, parkids AS park_ids,
       list_transform(string_split(categories, '|'), lambda x: trim(x)) AS categories,
       instructor, link.url AS url, registration_url.url AS registration_url,
       registration_url.url IS NOT NULL AS requires_registration,
       -- No structured cost field exists; these are text heuristics on the description.
       regexp_matches(coalesce(description, ''), '\$\s?[0-9]') AS mentions_price,
       regexp_matches(coalesce(description, '') || ' ' || coalesce(categories, ''), '(?i)\bfree\b') AS mentions_free,
       regexp_replace(regexp_replace(description, '<[^>]+>', ' ', 'g'), '&nbsp;|\s+', ' ', 'g') AS description,
       len(string_split(coordinates, ';')) > 1 AS has_multiple_locations
FROM e;

COPY (SELECT * FROM with_nta('r_events') ORDER BY start_ts, source_id)
TO 'data/staging/parks_events.parquet' (FORMAT parquet);

-- ---------- Summary ----------
SELECT 'restaurant_inspections' AS file, count(*) AS rows FROM 'data/staging/restaurant_inspections.parquet'
UNION ALL SELECT 'subway_stations', count(*) FROM 'data/staging/subway_stations.parquet'
UNION ALL SELECT 'osm_places', count(*) FROM 'data/staging/osm_places.parquet'
UNION ALL SELECT 'wikidata_places', count(*) FROM 'data/staging/wikidata_places.parquet'
UNION ALL SELECT 'libraries', count(*) FROM 'data/staging/libraries.parquet'
UNION ALL SELECT 'museums', count(*) FROM 'data/staging/museums.parquet'
UNION ALL SELECT 'greenthumb_gardens', count(*) FROM 'data/staging/greenthumb_gardens.parquet'
UNION ALL SELECT 'farmers_markets', count(*) FROM 'data/staging/farmers_markets.parquet'
UNION ALL SELECT 'parks_events', count(*) FROM 'data/staging/parks_events.parquet';
