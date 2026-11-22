-- ============================================================
-- Build the master places table: one row per real-world place, all sources linked.
--   Google harvest (rich: price, rating, hours, attributes, text)  data/staging/google_places.parquet
--   Overture + NYC Parks consolidated set                          nyc_activities (table in nyc.duckdb)
-- Run: duckdb nyc.duckdb < build_master.sql      (after stage_google.sql)
-- ============================================================
.bail on
LOAD spatial;
SET geometry_always_xy = true;   -- points are (lng, lat)

CREATE OR REPLACE MACRO haversine_m(lat1, lng1, lat2, lng2) AS
  2 * 6371000 * asin(sqrt(pow(sin(radians(lat2 - lat1) / 2), 2) +
      cos(radians(lat1)) * cos(radians(lat2)) * pow(sin(radians(lng2 - lng1) / 2), 2)));

CREATE OR REPLACE MACRO norm_name(s) AS
  trim(regexp_replace(regexp_replace(lower(replace(coalesce(s, ''), '&', ' and ')),
       '\b(the|nyc|new york|inc|llc|restaurant|cafe|bar)\b', ' ', 'g'), '[^a-z0-9]+', ' ', 'g'));

-- ---------- 1) Google places -> our 12 activity categories ----------
CREATE OR REPLACE TABLE g AS
SELECT *,
  CASE
    WHEN primary_type IN ('bar','pub','irish_pub','wine_bar','cocktail_bar','sports_bar','lounge_bar','beer_garden',
                          'brewpub','brewery','gastropub','hookah_bar','night_club','karaoke','winery','bar_and_grill')
         AND primary_type <> 'bar_and_grill' THEN 'Bars & Nightlife'
    WHEN primary_type IN ('cafe','coffee_shop','coffee_stand','coffee_roastery','tea_house','bakery','pastry_shop',
                          'cake_shop','ice_cream_shop','dessert_shop','dessert_restaurant','donut_shop','juice_shop',
                          'acai_shop','bagel_shop','chocolate_shop','confectionery','candy_store','cat_cafe','dog_cafe',
                          'bubble_tea_shop','tea_store')
      THEN 'Cafes & Desserts'
    WHEN primary_type LIKE '%restaurant' OR primary_type IN ('deli','diner','sandwich_shop','bistro','food_court',
         'bar_and_grill','meal_takeaway','meal_delivery','snack_bar','salad_shop','noodle_shop','hot_dog_stand',
         'cafeteria','buffet_restaurant','steak_house','fast_food_restaurant')
      THEN 'Restaurants'
    WHEN primary_type IN ('museum','art_museum','history_museum','art_gallery','planetarium','art_studio','cultural_center')
      THEN 'Museums & Galleries'
    WHEN primary_type IN ('performing_arts_theater','movie_theater','live_music_venue','comedy_club','concert_hall',
                          'opera_house','philharmonic_hall','amphitheatre','auditorium','stadium','arena','event_venue','dance_hall')
      THEN 'Shows & Live Events'
    WHEN primary_type IN ('park','city_park','state_park','national_park','garden','botanical_garden','beach','hiking_area',
                          'dog_park','playground','picnic_ground','plaza','nature_preserve','scenic_spot','marina',
                          'wildlife_refuge','cycling_park','skateboard_park','fishing_pier','woods','island')
      THEN 'Parks & Outdoors'
    WHEN primary_type IN ('tourist_attraction','historical_landmark','historical_place','cultural_landmark','monument',
                          'sculpture','fountain','castle','observation_deck','zoo','aquarium','amusement_park',
                          'wildlife_park','visitor_center','ferris_wheel','roller_coaster','water_park')
      THEN 'Attractions & Tours'
    WHEN primary_type IN ('bowling_alley','video_arcade','amusement_center','miniature_golf_course','indoor_playground',
                          'go_karting_venue','paintball_center','ice_skating_rink','adventure_sports_center','casino',
                          'indoor_golf_course','internet_cafe')
      THEN 'Games & Indoor Fun'
    WHEN primary_type IN ('spa','massage_spa','massage','sauna','wellness_center','skin_care_clinic','public_bath')
      THEN 'Spas & Wellness'
    WHEN primary_type IN ('library','book_store')
      THEN 'Libraries & Bookstores'
    WHEN primary_type IN ('gym','fitness_center','yoga_studio','sports_complex','swimming_pool','sports_club',
                          'athletic_field','tennis_court','sports_activity_location','golf_course','sports_coaching')
      THEN 'Sports & Fitness'
    WHEN primary_type IN ('market','farmers_market','flea_market','shopping_mall','department_store','thrift_store',
                          'gift_shop','toy_store','clothing_store','grocery_store','supermarket')
      THEN 'Shopping'
    -- fall back to the search that found it
    ELSE CASE split_part(query_types, ';', 1)
      WHEN 'restaurant' THEN 'Restaurants'
      WHEN 'cafe' THEN 'Cafes & Desserts' WHEN 'bakery' THEN 'Cafes & Desserts'
      WHEN 'ice_cream_shop' THEN 'Cafes & Desserts' WHEN 'dessert_shop' THEN 'Cafes & Desserts'
      WHEN 'bar' THEN 'Bars & Nightlife' WHEN 'night_club' THEN 'Bars & Nightlife' WHEN 'karaoke' THEN 'Bars & Nightlife'
      WHEN 'museum' THEN 'Museums & Galleries' WHEN 'art_gallery' THEN 'Museums & Galleries'
      WHEN 'performing_arts_theater' THEN 'Shows & Live Events' WHEN 'live_music_venue' THEN 'Shows & Live Events'
      WHEN 'comedy_club' THEN 'Shows & Live Events' WHEN 'movie_theater' THEN 'Shows & Live Events'
      WHEN 'concert_hall' THEN 'Shows & Live Events' WHEN 'stadium' THEN 'Shows & Live Events'
      WHEN 'park' THEN 'Parks & Outdoors' WHEN 'garden' THEN 'Parks & Outdoors' WHEN 'beach' THEN 'Parks & Outdoors'
      WHEN 'hiking_area' THEN 'Parks & Outdoors' WHEN 'playground' THEN 'Parks & Outdoors' WHEN 'dog_park' THEN 'Parks & Outdoors'
      WHEN 'tourist_attraction' THEN 'Attractions & Tours' WHEN 'historical_landmark' THEN 'Attractions & Tours'
      WHEN 'zoo' THEN 'Attractions & Tours' WHEN 'aquarium' THEN 'Attractions & Tours'
      WHEN 'amusement_park' THEN 'Attractions & Tours' WHEN 'observation_deck' THEN 'Attractions & Tours'
      WHEN 'bowling_alley' THEN 'Games & Indoor Fun' WHEN 'video_arcade' THEN 'Games & Indoor Fun'
      WHEN 'amusement_center' THEN 'Games & Indoor Fun' WHEN 'miniature_golf_course' THEN 'Games & Indoor Fun'
      WHEN 'indoor_playground' THEN 'Games & Indoor Fun' WHEN 'ice_skating_rink' THEN 'Games & Indoor Fun'
      WHEN 'spa' THEN 'Spas & Wellness'
      WHEN 'library' THEN 'Libraries & Bookstores' WHEN 'book_store' THEN 'Libraries & Bookstores'
      WHEN 'gym' THEN 'Sports & Fitness' WHEN 'yoga_studio' THEN 'Sports & Fitness'
      WHEN 'sports_complex' THEN 'Sports & Fitness' WHEN 'swimming_pool' THEN 'Sports & Fitness'
      ELSE 'Shopping' END
  END AS activity_category,
  norm_name(name) AS nkey
FROM read_parquet('data/staging/google_places.parquet')
WHERE business_status = 'OPERATIONAL';

-- ---------- 2) Link Overture / NYC Parks rows to Google places ----------
CREATE OR REPLACE TABLE o AS
SELECT *, norm_name(name) AS nkey FROM nyc_activities;

-- candidate pairs: within ~120 m, similar names
CREATE OR REPLACE TABLE pairs AS
SELECT o.place_id, g.google_place_id,
       jaro_winkler_similarity(o.nkey, g.nkey) AS sim,
       haversine_m(o.lat, o.lng, g.lat, g.lng) AS dist_m
FROM (SELECT *, floor(lat / 0.0011)::INT AS cy, floor(lng / 0.0014)::INT AS cx FROM o WHERE source = 'overture') o
JOIN (SELECT g.*, floor(lat / 0.0011)::INT + dy AS cy, floor(lng / 0.0014)::INT + dx AS cx
      FROM g, (SELECT unnest([-1,0,1]) AS dy), (SELECT unnest([-1,0,1]) AS dx)) g
  ON o.cy = g.cy AND o.cx = g.cx                         -- grid join: same or neighbouring ~120 m cell
WHERE TRUE
  AND o.nkey <> '' AND g.nkey <> ''
  AND (jaro_winkler_similarity(o.nkey, g.nkey) >= 0.88
       OR (length(o.nkey) >= 4 AND length(g.nkey) >= 4 AND (contains(o.nkey, g.nkey) OR contains(g.nkey, o.nkey))));

-- mutual best match: each Overture row and each Google place used at most once
CREATE OR REPLACE TABLE og_link AS
WITH ranked AS (
  SELECT *, sim - dist_m / 1000.0 AS score,
         row_number() OVER (PARTITION BY place_id ORDER BY sim - dist_m / 1000.0 DESC) AS r_o,
         row_number() OVER (PARTITION BY google_place_id ORDER BY sim - dist_m / 1000.0 DESC) AS r_g
  FROM pairs WHERE dist_m <= 120
)
SELECT place_id, google_place_id, sim, dist_m FROM ranked WHERE r_o = 1 AND r_g = 1;

-- Official NYC Parks properties: link when a Google park point lies inside/near the park polygon with a similar name
CREATE OR REPLACE TABLE parks_link AS
WITH pp AS (
  SELECT 'nycparks:' || gispropnum AS place_id, coalesce(signname, name311) AS pname, geom
  FROM ST_Read('data/raw/parks_properties.geojson') WHERE NOT retired
), c AS (
  SELECT pp.place_id, g.google_place_id,
         jaro_winkler_similarity(norm_name(pp.pname), g.nkey) AS sim,
         row_number() OVER (PARTITION BY pp.place_id ORDER BY jaro_winkler_similarity(norm_name(pp.pname), g.nkey) DESC) AS r_p,
         row_number() OVER (PARTITION BY g.google_place_id ORDER BY jaro_winkler_similarity(norm_name(pp.pname), g.nkey) DESC) AS r_g
  FROM pp JOIN g ON g.activity_category IN ('Parks & Outdoors','Sports & Fitness','Attractions & Tours')
   AND ST_DWithin(pp.geom, ST_Point(g.lng, g.lat), 0.0008)
  WHERE jaro_winkler_similarity(norm_name(pp.pname), g.nkey) >= 0.85
)
SELECT place_id, google_place_id, sim, 0.0 AS dist_m FROM c WHERE r_p = 1 AND r_g = 1;

CREATE OR REPLACE TABLE links AS
SELECT * FROM og_link
UNION ALL
SELECT * FROM parks_link WHERE google_place_id NOT IN (SELECT google_place_id FROM og_link);

SELECT (SELECT count(*) FROM g) AS google_places,
       (SELECT count(*) FROM og_link) AS overture_links,
       (SELECT count(*) FROM parks_link) AS park_links,
       (SELECT count(DISTINCT google_place_id) FROM links) AS google_linked;

-- ---------- 3) Master table: one row per place ----------
-- A) every operational Google place (linked Overture / NYC Parks info attached)
-- B) Overture / NYC Parks places Google didn't return (no observed price/rating; google_verified = false)
CREATE OR REPLACE TABLE places_master AS
WITH a AS (
  SELECT
    g.google_place_id                                   AS master_id,
    g.name,
    g.activity_category,
    g.primary_type                                      AS subcategory,
    g.primary_type_display                              AS subcategory_label,
    CASE WHEN g.activity_category = 'Restaurants' AND g.primary_type LIKE '%\_restaurant' ESCAPE '\'
              AND g.primary_type NOT IN ('fast_food_restaurant','restaurant')
         THEN replace(replace(g.primary_type, '_restaurant', ''), '_', ' ')
         ELSE o.cuisine END                             AS cuisine,
    g.types                                             AS google_types,
    g.lat, g.lng, g.borough, g.neighborhood, g.nta_code,
    g.address, g.postcode, coalesce(g.website, o.website) AS website, coalesce(g.phone, o.phone) AS phone,
    o.brand, coalesce(o.is_chain, false)                AS is_chain,
    o.acres,
    -- price
    g.price_level, g.price_min_usd, g.price_max_usd,
    coalesce(o.price_tier, est_price(g.activity_category, g.primary_type, coalesce(o.is_chain, false))) AS price_tier_estimate,
    -- quality / popularity
    g.rating, g.rating_count,
    -- hours
    g.hours_per_week, g.open_24_7, g.open_weekends, g.open_late, g.days_open, g.opening_hours,
    -- text
    g.editorial_summary, g.generative_summary, g.review_summary, g.reviews_text,
    g.reviews_avg_rating, g.latest_review_at,
    -- attributes
    g.outdoor_seating, g.live_music, g.good_for_children, g.good_for_groups, g.good_for_watching_sports,
    g.allows_dogs, g.reservable, g.menu_for_children, g.restroom, g.serves_vegetarian, g.serves_cocktails,
    g.serves_beer, g.serves_wine, g.serves_brunch, g.serves_breakfast, g.serves_lunch, g.serves_dinner,
    g.serves_dessert, g.serves_coffee, g.takeout, g.delivery, g.dine_in,
    g.wheelchair_entrance, g.wheelchair_seating, g.accepts_credit_cards, g.cash_only,
    -- provenance
    true AS google_verified, g.google_place_id, g.maps_uri,
    CASE WHEN l.place_id LIKE 'nycparks:%' THEN NULL ELSE l.place_id END AS overture_id,
    CASE WHEN l.place_id LIKE 'nycparks:%' THEN l.place_id END            AS nycparks_id,
    l.sim AS link_name_similarity, l.dist_m AS link_distance_m,
    g.fetched_at AS google_fetched_at
  FROM g
  LEFT JOIN links l USING (google_place_id)
  LEFT JOIN o ON o.place_id = l.place_id
), b AS (
  SELECT
    o.place_id AS master_id, o.name, o.activity_category, o.subcategory, NULL AS subcategory_label, o.cuisine,
    NULL AS google_types,
    o.lat, o.lng, o.borough, o.neighborhood, o.nta_code, o.address, o.postcode, o.website, o.phone,
    o.brand, o.is_chain, o.acres,
    NULL::INT AS price_level, NULL::DOUBLE AS price_min_usd, NULL::DOUBLE AS price_max_usd,
    o.price_tier AS price_tier_estimate,
    NULL::DOUBLE AS rating, NULL::BIGINT AS rating_count,
    NULL::DOUBLE AS hours_per_week, NULL::BOOLEAN AS open_24_7, NULL::BOOLEAN AS open_weekends,
    NULL::BOOLEAN AS open_late, NULL::BIGINT AS days_open, NULL AS opening_hours,
    NULL AS editorial_summary, NULL AS generative_summary, NULL AS review_summary, NULL AS reviews_text,
    NULL::DOUBLE AS reviews_avg_rating, NULL::TIMESTAMP AS latest_review_at,
    NULL::BOOLEAN AS outdoor_seating, NULL::BOOLEAN AS live_music, NULL::BOOLEAN AS good_for_children,
    NULL::BOOLEAN AS good_for_groups, NULL::BOOLEAN AS good_for_watching_sports, NULL::BOOLEAN AS allows_dogs,
    NULL::BOOLEAN AS reservable, NULL::BOOLEAN AS menu_for_children, NULL::BOOLEAN AS restroom,
    NULL::BOOLEAN AS serves_vegetarian, NULL::BOOLEAN AS serves_cocktails, NULL::BOOLEAN AS serves_beer,
    NULL::BOOLEAN AS serves_wine, NULL::BOOLEAN AS serves_brunch, NULL::BOOLEAN AS serves_breakfast,
    NULL::BOOLEAN AS serves_lunch, NULL::BOOLEAN AS serves_dinner, NULL::BOOLEAN AS serves_dessert,
    NULL::BOOLEAN AS serves_coffee, NULL::BOOLEAN AS takeout, NULL::BOOLEAN AS delivery, NULL::BOOLEAN AS dine_in,
    NULL::BOOLEAN AS wheelchair_entrance, NULL::BOOLEAN AS wheelchair_seating,
    NULL::BOOLEAN AS accepts_credit_cards, NULL::BOOLEAN AS cash_only,
    false AS google_verified, NULL AS google_place_id, NULL AS maps_uri,
    CASE WHEN o.source = 'overture' THEN o.place_id END AS overture_id,
    CASE WHEN o.source = 'nyc_parks' THEN o.place_id END AS nycparks_id,
    NULL::DOUBLE AS link_name_similarity, NULL::DOUBLE AS link_distance_m, NULL::TIMESTAMP AS google_fetched_at
  FROM o
  WHERE o.place_id NOT IN (SELECT place_id FROM links)
)
SELECT *,
  -- one price field for the recommender: observed Google level first, then known-free, then estimate
  coalesce(price_level,
           CASE WHEN activity_category IN ('Parks & Outdoors') OR subcategory IN ('library') THEN 0 END,
           price_tier_estimate)                           AS price_final,
  CASE WHEN price_level IS NOT NULL THEN 'google'
       WHEN activity_category IN ('Parks & Outdoors') OR subcategory IN ('library') THEN 'public_free'
       WHEN price_tier_estimate IS NOT NULL THEN 'category_estimate' END AS price_final_source
FROM (SELECT * FROM a UNION ALL BY NAME SELECT * FROM b);

SELECT google_verified, count(*) n, count(price_level) google_price, count(rating) rated FROM places_master GROUP BY 1;
