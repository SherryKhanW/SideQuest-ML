-- ============================================================
-- Add new columns to the FROZEN v1 snapshot without changing the rows or values the model was fitted on.
-- Takes every existing column from the committed data/places_v1.parquet and joins the new columns
-- (opening hours, extra filter fields) by master_id from a fresh pipeline build.
-- Run from data_pipeline/:  NEW_PLACES=<fresh extract> duckdb < add_columns_to_places_v1.sql
-- ============================================================
.bail on
SET VARIABLE fresh = getenv('NEW_PLACES');

CREATE TEMP TABLE frozen AS SELECT * FROM '../data/places_v1.parquet';
CREATE TEMP TABLE fresh AS SELECT * FROM read_parquet(getvariable('fresh'));

COPY (
  SELECT f.*,
         n.open_intervals, n.opening_hours,
         n.serves_vegetarian, n.serves_brunch, n.serves_breakfast, n.menu_for_children,
         n.good_for_watching_sports, n.wheelchair_entrance, n.is_chain
  FROM frozen f LEFT JOIN fresh n USING (master_id)
  ORDER BY master_id
) TO '../data/places_v1.parquet' (FORMAT parquet, COMPRESSION zstd);

SELECT count(*) AS places, count(open_intervals) AS with_hours FROM '../data/places_v1.parquet';
