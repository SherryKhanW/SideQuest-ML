-- ============================================================
-- Flatten the raw Google harvest (data/raw/google/places.jsonl) into one row per Google place.
-- Output: data/staging/google_places.parquet
-- Run   : duckdb nyc.duckdb < stage_google.sql
-- ============================================================
.bail on
LOAD spatial;

CREATE OR REPLACE TEMP TABLE g_raw AS
SELECT query_type, fetched_at, place
FROM read_json('data/raw/google/places.jsonl', format = 'newline_delimited',
               sample_size = -1, maximum_object_size = 50000000, ignore_errors = true)
WHERE place.id IS NOT NULL;

-- One row per place: latest copy, plus every query type that returned it.
CREATE OR REPLACE TEMP TABLE g AS
SELECT x.gid, x.p, x.fetched_at, q.query_types, q.times_seen
FROM (
  SELECT place.id AS gid, place AS p, fetched_at,
         row_number() OVER (PARTITION BY place.id ORDER BY fetched_at DESC) AS rn
  FROM g_raw
) x
JOIN (SELECT place.id AS gid, string_agg(DISTINCT query_type, ';') AS query_types, count(*) AS times_seen
      FROM g_raw GROUP BY 1) q USING (gid)
WHERE x.rn = 1;

-- Weekly opening hours from periods (handles closing after midnight).
CREATE OR REPLACE TEMP TABLE g_hours AS
WITH per AS (
  SELECT gid, unnest(p.regularOpeningHours.periods) AS pr FROM g
), mins AS (
  SELECT gid,
         pr.open.day AS od,
         pr.open.day * 1440 + pr.open.hour * 60 + pr.open.minute AS o,
         CASE WHEN pr.close IS NULL THEN NULL
              ELSE pr.close.day * 1440 + pr.close.hour * 60 + pr.close.minute END AS c,
         pr.close.hour AS ch, pr.close.day AS cd
  FROM per
)
SELECT gid,
       round(sum(CASE WHEN c IS NULL THEN 10080              -- open 24/7
                      WHEN c >= o THEN c - o ELSE c + 10080 - o END) / 60.0, 1) AS hours_per_week,
       bool_or(c IS NULL) AS open_24_7,
       bool_or(od IN (0, 6)) AS open_weekends,
       bool_or(c IS NOT NULL AND (cd <> od OR ch >= 23)) AS open_late,      -- closes 11pm or later / after midnight
       count(DISTINCT od) AS days_open
FROM mins GROUP BY gid;

CREATE OR REPLACE TABLE google_places AS
SELECT
  gid                                             AS google_place_id,
  p.displayName.text                              AS name,
  p.primaryType                                   AS primary_type,
  p.primaryTypeDisplayName.text                   AS primary_type_display,
  array_to_string(p.types, ';')                   AS types,
  query_types, times_seen,
  p.businessStatus                                AS business_status,
  p.location.latitude                             AS lat,
  p.location.longitude                            AS lng,
  p.formattedAddress                              AS address,
  p.shortFormattedAddress                         AS short_address,
  list_extract(list_filter(p.addressComponents, lambda a: list_contains(a.types, 'postal_code')), 1).longText   AS postcode,
  list_extract(list_filter(p.addressComponents, lambda a: list_contains(a.types, 'neighborhood')), 1).longText  AS google_neighborhood,
  list_extract(list_filter(p.addressComponents, lambda a: list_contains(a.types, 'sublocality_level_1')), 1).longText AS google_borough,
  p.googleMapsUri                                 AS maps_uri,
  p.websiteUri                                    AS website,
  p.nationalPhoneNumber                           AS phone,
  -- price
  CASE p.priceLevel WHEN 'PRICE_LEVEL_FREE' THEN 0 WHEN 'PRICE_LEVEL_INEXPENSIVE' THEN 1
       WHEN 'PRICE_LEVEL_MODERATE' THEN 2 WHEN 'PRICE_LEVEL_EXPENSIVE' THEN 3
       WHEN 'PRICE_LEVEL_VERY_EXPENSIVE' THEN 4 END AS price_level,
  try_cast(p.priceRange.startPrice.units AS DOUBLE) AS price_min_usd,
  try_cast(p.priceRange.endPrice.units AS DOUBLE)   AS price_max_usd,      -- NULL = open-ended ("$100+")
  -- popularity / quality
  p.rating                                        AS rating,
  p.userRatingCount                               AS rating_count,
  -- hours
  h.hours_per_week, h.open_24_7, h.open_weekends, h.open_late, h.days_open,
  array_to_string(p.regularOpeningHours.weekdayDescriptions, ' | ') AS opening_hours,
  -- text (for embeddings / vibe clustering)
  p.editorialSummary.text                         AS editorial_summary,
  p.generativeSummary.overview.text               AS generative_summary,
  p.reviewSummary.text.text                       AS review_summary,
  array_to_string([coalesce(r.originalText.text, r.text.text) FOR r IN p.reviews
                   IF coalesce(r.originalText.text, r.text.text) IS NOT NULL], ' ||| ') AS reviews_text,
  len(p.reviews)                                  AS n_reviews_returned,
  list_avg([r.rating FOR r IN p.reviews])         AS reviews_avg_rating,
  list_max([try_cast(r.publishTime AS TIMESTAMP) FOR r IN p.reviews]) AS latest_review_at,
  -- atmosphere attributes (NULL = unknown)
  p.outdoorSeating AS outdoor_seating, p.liveMusic AS live_music, p.goodForChildren AS good_for_children,
  p.goodForGroups AS good_for_groups, p.goodForWatchingSports AS good_for_watching_sports,
  p.allowsDogs AS allows_dogs, p.reservable, p.menuForChildren AS menu_for_children, p.restroom,
  p.servesVegetarianFood AS serves_vegetarian, p.servesCocktails AS serves_cocktails, p.servesBeer AS serves_beer,
  p.servesWine AS serves_wine, p.servesBrunch AS serves_brunch, p.servesBreakfast AS serves_breakfast,
  p.servesLunch AS serves_lunch, p.servesDinner AS serves_dinner, p.servesDessert AS serves_dessert,
  p.servesCoffee AS serves_coffee, p.takeout, p.delivery, p.dineIn AS dine_in,
  p.accessibilityOptions.wheelchairAccessibleEntrance AS wheelchair_entrance,
  p.accessibilityOptions.wheelchairAccessibleSeating  AS wheelchair_seating,
  p.paymentOptions.acceptsCreditCards AS accepts_credit_cards,
  p.paymentOptions.acceptsCashOnly    AS cash_only,
  fetched_at
FROM g LEFT JOIN g_hours h USING (gid);

-- Keep the five boroughs only, and attach NTA neighborhood + borough.
CREATE OR REPLACE TABLE google_places AS
SELECT gp.*, n.nta2020 AS nta_code, n.ntaname AS neighborhood, n.boroname AS borough
FROM google_places gp
JOIN ST_Read('data/raw/nta2020.geojson') n ON ST_Contains(n.geom, ST_Point(gp.lng, gp.lat));

COPY google_places TO 'data/staging/google_places.parquet' (FORMAT parquet);

SELECT count(*) AS places, count(price_level) AS with_price_level, count(price_min_usd) AS with_price_range,
       count(rating) AS with_rating, count(generative_summary) AS with_summary,
       count(*) FILTER (WHERE business_status <> 'OPERATIONAL') AS not_operational
FROM google_places;
