#!/usr/bin/env bash
# Download free public datasets that enrich nyc_activities.parquet.
# Raw files land in data/raw/<source>/ ; stage them with:  duckdb nyc.duckdb < stage_open_data.sql
#
# Usage: ./fetch_open_data.sh [source ...]
#   sources: restaurants subway osm wikidata libraries museums gardens farmers_markets parks_events
#   (no args = all). Existing files are re-downloaded (overwritten).
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data/staging

UA="nyc-activities-research/0.1"
RAW=data/raw
NYC_OD="https://data.cityofnewyork.us/resource"
NY_OD="https://data.ny.gov/resource"
# NYC bounding box (south, west, north, east)
S=40.477; W=-74.259; N=40.918; E=-73.700

get() {  # get <url> <outfile>
  local url="$1" out="$2"
  mkdir -p "$(dirname "$out")"
  echo "  -> $out"
  curl -sS -f -L --retry 3 --retry-delay 10 --max-time 900 -A "$UA" -o "$out.part" "$url"
  mv "$out.part" "$out"
}

restaurants() {
  # DOHMH Restaurant Inspection Results (one row per violation); aggregated to one row per CAMIS in SQL.
  echo "[restaurants] DOHMH inspections 43nn-pn8j"
  local cols="camis,dba,boro,building,street,zipcode,phone,cuisine_description,inspection_date,action,violation_code,critical_flag,score,grade,grade_date,inspection_type,latitude,longitude,nta"
  get "$NYC_OD/43nn-pn8j.csv?\$select=$cols&\$limit=2000000&\$order=camis,inspection_date" \
      "$RAW/restaurant_inspections/restaurant_inspections.csv"
}

subway() {
  echo "[subway] MTA Subway Stations 39hk-dx4f"
  get "$NY_OD/39hk-dx4f.csv?\$limit=5000" "$RAW/subway_stations/subway_stations.csv"
}

libraries() {
  echo "[libraries] feuq-due4"
  get "$NYC_OD/feuq-due4.json?\$limit=5000" "$RAW/libraries/libraries.json"
}

museums() {
  echo "[museums] fn6f-htvy"
  get "$NYC_OD/fn6f-htvy.json?\$limit=5000" "$RAW/museums/museums.json"
}

gardens() {
  echo "[gardens] GreenThumb p78i-pat6"
  get "$NYC_OD/p78i-pat6.csv?\$select=parksid,gardenname,address,borough,zipcode,status,juris,openhrsm,openhrstu,openhrsw,openhrsth,openhrsf,openhrssa,openhrssu,crossstreets,nta,lat,lon,multipolygon&\$limit=5000" \
      "$RAW/greenthumb_gardens/greenthumb_gardens.csv"
}

farmers_markets() {
  echo "[farmers_markets] 8vwk-6iz2"
  get "$NYC_OD/8vwk-6iz2.csv?\$limit=5000" "$RAW/farmers_markets/farmers_markets.csv"
}

parks_events() {
  # "NYC Parks Public Events - Upcoming 14 Days": a rolling window, so archive each pull by date.
  echo "[parks_events] w3wp-dpdi"
  local d; d=$(date +%Y-%m-%d)
  get "$NYC_OD/w3wp-dpdi.json?\$limit=50000" "$RAW/parks_events/parks_events_$d.json"
  cp "$RAW/parks_events/parks_events_$d.json" "$RAW/parks_events/parks_events_latest.json"
}

osm() {
  # One Overpass query per tag group, with pauses in between to be polite.
  # Groups already on disk are skipped (set OSM_FORCE=1 to refetch). On 504/429 the next mirror is tried.
  echo "[osm] Overpass API"
  local bbox="$S,$W,$N,$E"
  local -a mirrors=("https://overpass-api.de/api/interpreter" "https://overpass.kumi.systems/api/interpreter" "https://overpass.private.coffee/api/interpreter")
  local -a groups=(
    "amenity|^(restaurant|cafe|bar|pub|biergarten|fast_food|ice_cream|food_court|nightclub|theatre|cinema|arts_centre|library|community_centre)\$"
    "tourism|^(museum|gallery|attraction|viewpoint|zoo|aquarium|theme_park|artwork)\$"
    "leisure|^(park|garden|playground|sports_centre|fitness_centre|swimming_pool|bowling_alley|escape_game|amusement_arcade|ice_rink|nature_reserve|dog_park|miniature_golf|pitch|stadium)\$"
    "historic|."
  )
  local first=1
  for g in "${groups[@]}"; do
    local key="${g%%|*}" re="${g#*|}" out="$RAW/osm/osm_${g%%|*}.json"
    if [[ -s "$out" && -z "${OSM_FORCE:-}" ]]; then echo "  skip $key (exists)"; continue; fi
    [[ $first -eq 1 ]] || sleep 30
    first=0
    local q="[out:json][timeout:600][maxsize:1073741824][bbox:$bbox];
(
  node[\"$key\"~\"$re\"][\"name\"];
  way[\"$key\"~\"$re\"][\"name\"];
  relation[\"$key\"~\"$re\"][\"name\"];
);
out center tags;"
    mkdir -p "$RAW/osm"
    local ok=0 m
    for m in "${mirrors[@]}"; do
      echo "  query: $key @ $m"
      if curl -sS -f --retry 1 --retry-delay 60 --max-time 900 -A "$UA" \
           --data-urlencode "data=$q" -o "$out.part" "$m" && jq -e '.elements' "$out.part" >/dev/null; then
        mv "$out.part" "$out"; echo "  -> $out ($(jq '.elements|length' "$out") elements)"; ok=1; break
      fi
      sleep 30
    done
    [[ $ok -eq 1 ]] || { echo "  FAILED: osm $key" >&2; rm -f "$out.part"; }
  done
}

wikidata() {
  # Items with coordinates in the NYC bbox that have an English Wikipedia article.
  # Stage 1: a 2x2 grid of sub-boxes (item, label, description, coords, sitelinks, enwiki URL, P31 QIDs).
  # Stage 2: one query for English labels of all P31 classes seen. (Joining class labels inside stage 1
  # made queries time out.) WDQS may rate-limit hard (seen: 1 request/min), so queries are spaced 65 s apart.
  echo "[wikidata] SPARQL"
  mkdir -p "$RAW/wikidata"
  # Boxes already on disk are skipped (set WIKIDATA_FORCE=1 to refetch everything).
  [[ -z "${WIKIDATA_FORCE:-}" ]] || rm -f "$RAW/wikidata"/*.csv
  local nlat=2 nlng=2 i j first=1
  for ((i=0; i<nlat; i++)); do
    for ((j=0; j<nlng; j++)); do
      local s n w e
      s=$(awk -v a=$S -v b=$N -v k=$i -v m=$nlat 'BEGIN{printf "%.4f", a+(b-a)*k/m}')
      n=$(awk -v a=$S -v b=$N -v k=$((i+1)) -v m=$nlat 'BEGIN{printf "%.4f", a+(b-a)*k/m}')
      w=$(awk -v a=$W -v b=$E -v k=$j -v m=$nlng 'BEGIN{printf "%.4f", a+(b-a)*k/m}')
      e=$(awk -v a=$W -v b=$E -v k=$((j+1)) -v m=$nlng 'BEGIN{printf "%.4f", a+(b-a)*k/m}')
      local q="SELECT ?item ?itemLabel ?itemDescription ?lat ?lng ?sitelinks ?article ?instance_qids WHERE {
 { SELECT ?item ?lat ?lng ?sitelinks ?article
     (GROUP_CONCAT(DISTINCT STRAFTER(STR(?inst), \"entity/\"); separator=\"|\") AS ?instance_qids)
   WHERE {
     SERVICE wikibase:box { ?item wdt:P625 ?coord .
       bd:serviceParam wikibase:cornerSouthWest \"Point($w $s)\"^^geo:wktLiteral .
       bd:serviceParam wikibase:cornerNorthEast \"Point($e $n)\"^^geo:wktLiteral . }
     ?article schema:about ?item ; schema:isPartOf <https://en.wikipedia.org/> .
     ?item wikibase:sitelinks ?sitelinks .
     BIND(geof:latitude(?coord) AS ?lat) BIND(geof:longitude(?coord) AS ?lng)
     OPTIONAL { ?item wdt:P31 ?inst }
   } GROUP BY ?item ?lat ?lng ?sitelinks ?article }
 SERVICE wikibase:label { bd:serviceParam wikibase:language \"en\".
   ?item rdfs:label ?itemLabel . ?item schema:description ?itemDescription . }
}"
      if [[ -s "$RAW/wikidata/wikidata_${i}_${j}.csv" ]]; then echo "  skip box $i,$j (exists)"; continue; fi
      [[ $first -eq 1 ]] || sleep 65
      first=0
      echo "  box $i,$j ($s,$w)-($n,$e)"
      sparql "$q" "$RAW/wikidata/wikidata_${i}_${j}.csv"
    done
  done
  # Stage 2: labels for the instance-of classes
  local values
  # instance_qids is the last CSV column (never quoted); WDQS CSV uses CRLF line endings
  values=$(tail -q -n +2 "$RAW/wikidata"/wikidata_*.csv | tr -d '\r' | awk -F, '{print $NF}' | tr '|' '\n' \
           | { grep -E '^Q[0-9]+$' || true; } | sort -u | sed 's/^/wd:/' | tr '\n' ' ')
  sleep 65
  echo "  instance-of labels"
  sparql "SELECT ?inst ?instLabel WHERE { VALUES ?inst { $values }
  SERVICE wikibase:label { bd:serviceParam wikibase:language \"en\". } }" "$RAW/wikidata/instance_labels.csv"
}

sparql() {  # sparql <query> <outfile> ; retries 429/5xx after a pause
  local q="$1" out="$2" code try
  for try in 1 2 3 4; do
    code=$(curl -sS --max-time 300 -A "$UA" -H "Accept: text/csv" --data-urlencode "query=$q" \
             -o "$out.part" -w "%{http_code}" "https://query.wikidata.org/sparql" || echo 000)
    if [[ "$code" == 200 ]]; then mv "$out.part" "$out"; echo "  -> $out ($(($(wc -l < "$out") - 1)) rows)"; return 0; fi
    echo "  HTTP $code, retrying in 90 s (attempt $try)"; sleep 90
  done
  echo "  FAILED: $out" >&2; rm -f "$out.part"; return 1
}

ALL=(restaurants subway libraries museums gardens farmers_markets parks_events wikidata osm)
if [[ $# -gt 0 ]]; then TARGETS=("$@"); else TARGETS=("${ALL[@]}"); fi
for t in "${TARGETS[@]}"; do "$t"; done
date -u +%Y-%m-%dT%H:%M:%SZ > "$RAW/.open_data_fetched_at"
echo "done."
