-- ============================================================
-- Modeling extract for SideQuest-ML: data/places_v1.parquet
--   * every Google-verified operational place (rich: price, rating, hours, vibes, summary)
--   * plus official city parks & community gardens Google didn't return (NYC Parks, GreenThumb):
--     trustworthy and free by definition, but no rating, hours or vibe data
-- Overture-only places are left out: unverified, no rating/hours/vibes, price only estimated.
-- Run from data_pipeline/ after run_all.sh:   duckdb < build_places_v1.sql
-- (set PLACES_ENRICHED to read the enriched parquet from elsewhere)
-- ============================================================
.bail on
SET VARIABLE src = coalesce(getenv('PLACES_ENRICHED'), 'nyc_places_enriched.parquet');

COPY (
  SELECT master_id,
         CASE WHEN google_verified THEN 'google'
              WHEN greenthumb_id IS NOT NULL THEN 'greenthumb'
              ELSE 'nyc_parks' END                                   AS verified_by,
         google_place_id, name, activity_category, subcategory,
         coalesce(subcategory_label,
                  CASE WHEN NOT google_verified
                       THEN upper(left(replace(subcategory, '_', ' '), 1)) || substr(replace(subcategory, '_', ' '), 2) END)
                                                                       AS subcategory_label,
         cuisine, borough, neighborhood, nta_code, lat, lng, address,
         price_final, price_final_source, price_level, price_min_usd, price_max_usd,
         rating, rating_count,
         good_for_children, good_for_groups, outdoor_seating, live_music, allows_dogs,
         serves_cocktails, serves_beer, serves_wine, reservable,
         open_late, open_weekends, hours_per_week,
         nearest_subway, nearest_subway_m, inspection_grade, wikidata_sitelinks, acres,
         generative_summary, maps_uri
  FROM read_parquet(getvariable('src'))
  WHERE google_verified
     OR nycparks_id IS NOT NULL OR greenthumb_id IS NOT NULL      -- official city parks, fields, gardens
  ORDER BY master_id
) TO '../data/places_v1.parquet' (FORMAT parquet, COMPRESSION zstd);

SELECT verified_by, count(*) AS places FROM '../data/places_v1.parquet' GROUP BY 1 ORDER BY 2 DESC;
