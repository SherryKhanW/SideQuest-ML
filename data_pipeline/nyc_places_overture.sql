-- ============================================================
-- NYC places from Overture Maps (free, open data)
-- Run with the DuckDB CLI:   duckdb nyc.duckdb < nyc_places_overture.sql
-- Outputs: nyc_places.csv, nyc_places.parquet, nyc_category_counts.csv
-- ============================================================

INSTALL httpfs;  LOAD httpfs;
INSTALL spatial; LOAD spatial;
SET s3_region = 'us-west-2';

-- Latest release as of Nov 2026. Releases are removed after ~60 days,
-- so update this when it 404s (see docs.overturemaps.org/blog).
SET VARIABLE release = '2026-11-18.0';

-- 1) Pull everything inside the NYC bounding box.
--    Filtering on the bbox columns lets DuckDB skip most of the global
--    file, so this reads a few hundred MB, not the whole planet.
CREATE OR REPLACE TABLE nyc_places AS
SELECT
    id                                   AS overture_id,
    names.primary                        AS name,
    basic_category,
    taxonomy.primary                     AS category,
    taxonomy.hierarchy[1]                AS top_category,     -- e.g. food_and_drink, arts_and_entertainment
    array_to_string(taxonomy.hierarchy, ' > ') AS category_path,
    array_to_string(taxonomy.alternates, '; ') AS alt_categories,
    confidence,
    operating_status,
    brand.names.primary                  AS brand,
    addresses[1].freeform                AS address,
    addresses[1].locality                AS locality,
    addresses[1].postcode                AS postcode,
    addresses[1].region                  AS region,
    websites[1]                          AS website,
    phones[1]                            AS phone,
    socials[1]                           AS social,
    emails[1]                            AS email,
    ST_Y(geometry)                       AS lat,
    ST_X(geometry)                       AS lng,
    array_to_string(list_distinct([s.dataset FOR s IN sources]), ', ') AS source_datasets
FROM read_parquet(
        's3://overturemaps-us-west-2/release/' || getvariable('release') || '/theme=places/type=place/*',
        hive_partitioning = 1)
WHERE bbox.xmin BETWEEN -74.2591 AND -73.7004
  AND bbox.ymin BETWEEN  40.4774 AND  40.9176;

-- 2) Clean up: drop closed places, low-confidence records,
--    and the NJ / Long Island spillover from the bounding box.
DELETE FROM nyc_places
WHERE operating_status = 'permanently_closed'
   OR confidence < 0.5           -- tune: 0.5 is a common cut-off; go lower for more recall
   OR coalesce(region, 'NY') NOT IN ('NY', 'US-NY');   -- Overture mostly uses ISO codes (US-NY)

-- Optional: exact clip to the five boroughs instead of the bbox.
-- Download "Borough Boundaries" GeoJSON from NYC Open Data as boroughs.geojson, then:
-- DELETE FROM nyc_places p
-- WHERE NOT EXISTS (
--     SELECT 1 FROM ST_Read('boroughs.geojson') b
--     WHERE ST_Contains(b.geom, ST_Point(p.lng, p.lat)));

-- 3) Export.
COPY nyc_places TO 'nyc_places.csv'     (HEADER, DELIMITER ',');
COPY nyc_places TO 'nyc_places.parquet' (FORMAT parquet);

-- 4) Quick look at what you got.
COPY (
    SELECT top_category, category, count(*) AS n
    FROM nyc_places
    GROUP BY ALL
    ORDER BY n DESC
) TO 'nyc_category_counts.csv' (HEADER);

SELECT count(*) AS total_places FROM nyc_places;
SELECT top_category, count(*) AS n FROM nyc_places GROUP BY 1 ORDER BY 2 DESC;

-- ============================================================
-- Handy slices (run interactively):
--   Restaurants/bars/cafes:
--     SELECT * FROM nyc_places WHERE top_category = 'food_and_drink';
--   Activities:
--     SELECT * FROM nyc_places
--     WHERE top_category IN ('arts_and_entertainment', 'sports_and_recreation',
--                            'travel_and_transportation')  -- check names in nyc_category_counts.csv
--        OR category ILIKE '%museum%' OR category ILIKE '%park%';
-- ============================================================
