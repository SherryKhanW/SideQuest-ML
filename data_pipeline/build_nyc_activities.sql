-- ============================================================
-- Consolidate NYC places into one activity dataset for the recommender.
-- Input : nyc_places (built by nyc_places_overture.sql, in nyc.duckdb)
--         data/raw/nta2020.geojson          NYC Open Data 9nt8-h7nd (2020 Neighborhood Tabulation Areas)
--         data/raw/parks_properties.geojson NYC Open Data enfh-gkve (NYC Parks Properties)
-- Output: nyc_activities.parquet / nyc_activities.csv, activity_category_summary.csv
-- Run   : duckdb nyc.duckdb < build_nyc_activities.sql
-- ============================================================
.bail on
LOAD spatial;

-- ---------- 1) Map Overture categories to user-facing activity buckets ----------
CREATE OR REPLACE TABLE category_map AS
WITH c AS (SELECT DISTINCT top_category, category FROM nyc_places WHERE category IS NOT NULL)
SELECT top_category, category,
  CASE
    -- Bars & Nightlife
    WHEN category IN ('bar','cocktail_bar','lounge','sports_bar','wine_bar','pub','irish_pub','dive_bar',
                      'hookah_bar','brewery','beer_bar','gay_bar','winery','beer_garden','gastropub',
                      'dance_club','nightlife_venue','karaoke_venue','salsa_club','bar_crawl','club_crawl',
                      'cabaret','jazz_and_blues_venue')
         OR (top_category = 'food_and_drink' AND category LIKE '%\_bar' ESCAPE '\' AND category NOT IN ('salad_bar','smoothie_juice_bar'))
      THEN 'Bars & Nightlife'
    -- Cafes & Desserts
    WHEN category IN ('coffee_shop','cafe','bakery','tea_room','bubble_tea_shop','ice_cream_shop','dessert_shop',
                      'donut_shop','frozen_yogurt_shop','cupcake_shop','chocolatier','smoothie_juice_bar',
                      'candy_store','internet_cafe','gelato','creperie','patisserie','juice_bar','coffee_roastery')
      THEN 'Cafes & Desserts'
    -- Restaurants (everything else in food_and_drink that serves meals)
    WHEN top_category = 'food_and_drink'
         AND category NOT IN ('food_and_drink','airport_lounge','beverage_store','food_stand','caterer','catering')
      THEN 'Restaurants'
    WHEN category = 'food_and_drink' THEN 'Restaurants'
    -- Parks & Outdoors
    WHEN category IN ('park','dog_park','playground','hiking_trail','national_park','state_park','skate_park',
                      'mountain_bike_trail','boating_place','sailing_area','fishing_area','rafting_kayaking_area',
                      'memorial_park','sculpture_park','wildlife_sanctuary','public_plaza','public_fountain',
                      'atv_recreation_park','pumpkin_patch')
         OR (top_category = 'geographic_entities' AND category NOT IN ('building','geographic_entities','canal'))
      THEN 'Parks & Outdoors'
    -- Museums & Galleries
    WHEN category LIKE '%museum%' OR category IN ('art_gallery','planetarium','observatory','cultural_center')
      THEN 'Museums & Galleries'
    -- Shows & Live Events
    WHEN category IN ('music_venue','performing_arts_venue','theatre_venue','movie_theater','comedy_club',
                      'opera_and_ballet','band_orchestra_symphony','dinner_theater','drive_in_theater',
                      'event_venue','festival_venue','music_festival_venue','film_festival_venue','auditorium',
                      'circus_venue','stadium_arena','stadium','arena','baseball_stadium','basketball_stadium',
                      'football_stadium','soccer_stadium','tennis_stadium','track_stadium','hockey_arena',
                      'country_dance_hall','ticket_office_or_booth')
      THEN 'Shows & Live Events'
    -- Attractions & Tours
    WHEN category IN ('historic_site','monument','memorial_site','sculpture_statue','street_art','lighthouse','fort',
                      'castle','palace','historic_mission','zoo','petting_zoo','aquarium','amusement_park',
                      'carousel','carnival_venue','fairgrounds','water_park','visitor_center')
         OR category LIKE '%\_tour' ESCAPE '\' OR category = 'sightseeing_tour_agency'
      THEN 'Attractions & Tours'
    -- Games & Indoor Fun
    WHEN category IN ('arcade','escape_room','bowling_alley','pool_billiards','pool_hall','miniature_golf_course',
                      'laser_tag','paintball','go_kart_club','go_kart_track','axe_throwing','haunted_house',
                      'virtual_reality_center','paint_and_sip_venue','paint_your_own_pottery_venue',
                      'glass_blowing_venue','indoor_playcenter','batting_cage','indoor_golf_center',
                      'challenge_courses_center','roller_skating_rink','ice_skating_rink','skating_rink',
                      'bingo_hall','makerspace','board_game_cafe','trampoline_park','casino')
      THEN 'Games & Indoor Fun'
    -- Sports & Fitness
    WHEN top_category = 'sports_and_recreation'
         AND category NOT IN ('sport_league','amateur_sport_league','professional_sport_league','professional_sport_team',
                              'amateur_sport_team','school_sport_team','fitness_trainer','swimming_instructor',
                              'golf_instructor','scuba_diving_instruction')
      THEN 'Sports & Fitness'
    -- Libraries & Bookstores
    WHEN category IN ('library','bookstore','comic_books_store','newspaper_and_magazines_store')
      THEN 'Libraries & Bookstores'
    -- Spas & Wellness
    WHEN category IN ('spa','day_spa','health_spa','massage_therapy','public_bath_house','sauna','meditation_center',
                      'onsen','float_spa','halotherapy','health_and_wellness_club')
      THEN 'Spas & Wellness'
    -- Shopping (leisure shopping only, no errands like pharmacies, phone or auto stores)
    WHEN category IN ('shopping_mall','department_store','clothing_store','womens_clothing_store','mens_clothing_store',
                      'fashion_boutique','designer_clothing','fashion_accessories_store','shoe_store','jewelry_store',
                      'antique_store','second_hand_store','second_hand_clothing_store','vintage_store','thrift_store',
                      'farmers_market','flea_market','gift_shop','toy_store','music_and_dvd_store','vinyl_record_store',
                      'hobby_shop','arts_crafts_and_hobby_store','specialty_foods_store','cosmetics_and_fragrance_store',
                      'sporting_goods_store','sportswear_store','home_decor_store','flowers_and_gifts_store',
                      'video_game_store','musical_instrument_store','camera_and_photography_store',
                      'chocolate_shop','cheese_shop','wine_shop','beer_wine_spirits_store','pop_up_store',
                      'market_stall','public_market','food_hall')
      THEN 'Shopping'
    ELSE NULL   -- not an activity (services, health care, schools, government, auto, worship, lodging, etc.)
  END AS activity_category
FROM c;

-- ---------- 2) Estimated price tier: 0 = free, 1 = $, 2 = $$, 3 = $$$, 4 = $$$$ ----------
-- Overture has NO price data. These are category-level priors, flagged with price_source = 'category_estimate'.
-- Swap in real prices (Foursquare, Yelp or Google Places) later where available.
CREATE OR REPLACE MACRO est_price(act, cat, has_brand) AS
  CASE
    WHEN act IN ('Parks & Outdoors','Libraries & Bookstores') AND cat NOT IN ('bookstore','comic_books_store','newspaper_and_magazines_store') THEN 0
    WHEN cat IN ('historic_site','monument','memorial_site','sculpture_statue','street_art','lighthouse','fort',
                 'art_gallery','cultural_center','visitor_center','public_plaza','farmers_market') THEN 0
    WHEN cat IN ('steakhouse','french_restaurant','fine_dining_restaurant','omakase_restaurant','wine_bar',
                 'cocktail_bar','lounge','opera_and_ballet','theatre_venue','performing_arts_venue',
                 'band_orchestra_symphony','dinner_theater','spa','day_spa','health_spa','float_spa',
                 'designer_clothing','jewelry_store','department_store','casino','stadium_arena','arena',
                 'baseball_stadium','basketball_stadium','football_stadium','tennis_stadium','hockey_arena',
                 'golf_course','sailing_club','equestrian_facility','skydiving_center','private_jet_charter') THEN 3
    WHEN cat IN ('pizza_restaurant','fast_food_restaurant','delicatessen','food_truck_stand','bagel_shop',
                 'sandwich_shop','hot_dog_restaurant','falafel_restaurant','taco_restaurant','chicken_restaurant',
                 'chicken_wings_restaurant','halal_restaurant','food_court','coffee_shop','cafe','bakery',
                 'ice_cream_shop','donut_shop','bubble_tea_shop','frozen_yogurt_shop','dessert_shop','cupcake_shop',
                 'candy_store','smoothie_juice_bar','dive_bar','salad_bar','soup_restaurant','burger_restaurant',
                 'internet_cafe','second_hand_store','second_hand_clothing_store','thrift_store','gift_shop',
                 'comic_books_store','newspaper_and_magazines_store','playground','dog_park','skate_park',
                 'pool_billiards','pool_hall','bingo_hall') THEN 1
    WHEN act = 'Restaurants' AND has_brand THEN 1        -- chains skew cheap
    ELSE 2
  END;

-- ---------- 3) Reference layers from NYC Open Data ----------
CREATE OR REPLACE TABLE nta AS
SELECT nta2020 AS nta_code, ntaname AS neighborhood, boroname AS borough, geom
FROM ST_Read('data/raw/nta2020.geojson');

-- Official NYC Parks properties (dataset enfh-gkve). Non-visitable types are skipped.
CREATE OR REPLACE TABLE parks_official AS
SELECT gispropnum AS park_id, coalesce(signname, name311) AS name, typecategory,
       try_cast(acres AS DOUBLE) AS acres, address, zipcode, geom,
       ST_PointOnSurface(geom) AS pt
FROM ST_Read('data/raw/parks_properties.geojson')
WHERE NOT retired
  AND typecategory NOT IN ('Strip','Undeveloped','Parkway','Lot','Operations','Cemetery','Mall')
  AND coalesce(signname, name311) IS NOT NULL AND signname <> 'Park';

-- ---------- 4) Overture rows: bucket, neighborhood, quality filters ----------
CREATE OR REPLACE TABLE overture_tagged AS
SELECT
  p.overture_id AS place_id, p.name, m.activity_category, p.category AS subcategory,
  p.category_path, p.alt_categories, p.brand, p.lat, p.lng,
  n.borough, n.neighborhood, n.nta_code,
  p.address, p.postcode, p.website, p.phone, p.social, p.email,
  p.confidence, p.operating_status, p.source_datasets,
  -- ZIP prefix -> borough, to catch pins dropped in the wrong borough
  CASE WHEN p.postcode SIMILAR TO '10[0-2].*' THEN 'Manhattan'
       WHEN p.postcode LIKE '103%' THEN 'Staten Island'
       WHEN p.postcode LIKE '104%' THEN 'Bronx'
       WHEN p.postcode LIKE '112%' THEN 'Brooklyn'
       WHEN p.postcode SIMILAR TO '11[013-6].*' THEN 'Queens' END AS zip_borough,
  EXISTS (SELECT 1 FROM parks_official o WHERE ST_DWithin(o.geom, ST_Point(p.lng, p.lat), 0.0005)) AS in_official_park
FROM nyc_places p
JOIN category_map m USING (top_category, category)
JOIN nta n ON ST_Contains(n.geom, ST_Point(p.lng, p.lat))
WHERE m.activity_category IS NOT NULL
  AND p.name IS NOT NULL AND trim(p.name) <> '';

CREATE OR REPLACE TABLE overture_clean AS
SELECT * FROM overture_tagged
WHERE (address IS NOT NULL OR (activity_category = 'Parks & Outdoors' AND in_official_park))   -- addressless pins are mostly misplaced
  AND (zip_borough IS NULL OR zip_borough = borough);                                          -- ZIP must agree with location

-- Drop Overture park pins that are just a copy of an official park (same place, similar name).
CREATE OR REPLACE TABLE overture_park_dupes AS
SELECT DISTINCT t.place_id
FROM overture_clean t JOIN parks_official o
  ON ST_DWithin(o.geom, ST_Point(t.lng, t.lat), 0.0005)
WHERE t.subcategory IN ('park','playground','national_park','state_park','garden','community_garden','nature_reserve','memorial_park')
  AND jaro_winkler_similarity(lower(t.name), lower(o.name)) >= 0.88
UNION
-- Overture park pins carrying an official park's exact name are either copies (near the park)
-- or misplaced pins (e.g. "Central Park" in Tribeca). Either way the official row covers it.
SELECT t.place_id
FROM overture_clean t
WHERE t.activity_category = 'Parks & Outdoors'
  AND t.subcategory IN ('park','playground','national_park','state_park','garden','community_garden','nature_reserve','memorial_park')
  AND lower(regexp_replace(t.name, '[^A-Za-z0-9]', '', 'g')) IN
      (SELECT lower(regexp_replace(name, '[^A-Za-z0-9]', '', 'g')) FROM parks_official);

-- ---------- 5) Union Overture + official parks into one schema ----------
CREATE OR REPLACE TABLE activities_raw AS
SELECT
  place_id, name, activity_category, subcategory,
  CASE WHEN activity_category = 'Restaurants' AND subcategory LIKE '%\_restaurant' ESCAPE '\'
            AND subcategory NOT IN ('fast_food_restaurant','restaurant')
       THEN replace(replace(subcategory, '_restaurant', ''), '_', ' ') END AS cuisine,
  category_path, alt_categories,
  est_price(activity_category, subcategory, brand IS NOT NULL) AS price_tier,
  'category_estimate' AS price_source,
  brand, brand IS NOT NULL AS is_chain,
  lat, lng, borough, neighborhood, nta_code, address, postcode,
  website, phone, social, email,
  NULL::DOUBLE AS acres,
  confidence, operating_status,
  'overture' AS source, source_datasets AS source_detail
FROM overture_clean
WHERE place_id NOT IN (SELECT place_id FROM overture_park_dupes)
UNION ALL
SELECT
  'nycparks:' || o.park_id, o.name,
  CASE WHEN o.typecategory IN ('Recreational Field/Courts','Buildings/Institutions') THEN 'Sports & Fitness'
       WHEN o.typecategory = 'Historic House Park' THEN 'Attractions & Tours'
       ELSE 'Parks & Outdoors' END,
  lower(replace(replace(o.typecategory, '/', '_or_'), ' ', '_')),
  NULL, NULL, NULL,
  0, 'nyc_parks_public',
  NULL, false,
  ST_Y(o.pt), ST_X(o.pt), n.borough, n.neighborhood, n.nta_code, o.address, o.zipcode,
  NULL, NULL, NULL, NULL,
  o.acres,
  1.0, 'open',
  'nyc_parks', 'NYC Parks Properties (NYC Open Data enfh-gkve)'
FROM parks_official o
JOIN nta n ON ST_Contains(n.geom, o.pt);

-- ---------- 6) Deduplicate: same normalized name, same bucket, within ~50 m -> keep highest confidence ----------
CREATE OR REPLACE TABLE nyc_activities AS
WITH k AS (
  SELECT *, lower(regexp_replace(name, '[^A-Za-z0-9]', '', 'g')) AS name_key FROM activities_raw
), dupes AS (
  SELECT DISTINCT b.place_id
  FROM k a JOIN k b
    ON a.name_key = b.name_key AND a.activity_category = b.activity_category
   AND a.place_id <> b.place_id
   AND abs(a.lat - b.lat) < 0.00045 AND abs(a.lng - b.lng) < 0.0006          -- ~50 m box
   AND (a.confidence > b.confidence OR (a.confidence = b.confidence AND a.place_id < b.place_id))
)
SELECT * EXCLUDE (name_key) FROM k
WHERE place_id NOT IN (SELECT place_id FROM dupes)
ORDER BY borough, neighborhood, activity_category, name;

-- ---------- 7) Export ----------
COPY nyc_activities TO 'nyc_activities.parquet' (FORMAT parquet);
COPY nyc_activities TO 'nyc_activities.csv' (HEADER);
COPY (
  SELECT activity_category, count(*) AS places,
         round(avg(price_tier), 2) AS avg_price_tier,
         count(*) FILTER (WHERE price_tier = 0) AS free_places,
         count(DISTINCT subcategory) AS subcategories
  FROM nyc_activities GROUP BY 1 ORDER BY 2 DESC
) TO 'activity_category_summary.csv' (HEADER);

SELECT (SELECT count(*) FROM overture_tagged) AS overture_in_nyc,
       (SELECT count(*) FROM overture_tagged) - (SELECT count(*) FROM overture_clean) AS dropped_quality,
       (SELECT count(*) FROM overture_park_dupes) AS dropped_park_dupes,
       (SELECT count(*) FROM parks_official) AS official_parks,
       (SELECT count(*) FROM activities_raw) AS before_dedup, count(*) AS final_rows FROM nyc_activities;
SELECT activity_category, count(*) n FROM nyc_activities GROUP BY 1 ORDER BY 2 DESC;
SELECT borough, count(*) n FROM nyc_activities GROUP BY 1 ORDER BY 2 DESC;
SELECT price_tier, count(*) n FROM nyc_activities GROUP BY 1 ORDER BY 1;
