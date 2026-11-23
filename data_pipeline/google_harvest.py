#!/usr/bin/env python3
"""
Harvest NYC places from Google Places API (New) Text Search, by area.

For each Google place type (restaurant, bar, museum, park, ...) we search rectangles
covering NYC with includedType + strictTypeFiltering. One request returns up to 20 places,
and a query returns at most 60 (3 pages). Tiles are planned from the Overture place density we
already have (nyc_activities.parquet): a tile is split, without spending a call, until it's
expected to hold <= ~45 places of that type. If a tile still comes back full (60), it is
split live and the children are queried.

Every response is saved raw to data/raw/google/places.jsonl; every request is logged to
data/raw/google/calls.jsonl. That log enforces the budget across runs and makes the harvest resumable.

Usage:
  python3 google_harvest.py --plan                          # cost estimate per type, no API calls
  python3 google_harvest.py --types restaurant --area park_slope --max-calls 40   # pilot
  python3 google_harvest.py --priority 1 --max-calls 3000
  python3 google_harvest.py --max-calls 7000                 # everything, by priority, until the cap

Billing: the field mask includes Atmosphere fields -> "Text Search Enterprise + Atmosphere"
($40 / 1000 requests, first 1,000 per month free). --max-calls is a hard cap over ALL runs.
"""
import argparse, csv, json, math, os, re, subprocess, sys, tempfile, threading, time, urllib.error, urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "data", "raw", "google")
PLACES_LOG = os.path.join(OUT_DIR, "places.jsonl")
CALLS_LOG = os.path.join(OUT_DIR, "calls.jsonl")
URL = "https://places.googleapis.com/v1/places:searchText"
COST_PER_CALL = 0.040

FIELDS = [
    # Pro
    "id", "displayName", "formattedAddress", "shortFormattedAddress", "addressComponents", "location",
    "types", "primaryType", "primaryTypeDisplayName", "businessStatus", "googleMapsUri", "accessibilityOptions",
    # Enterprise
    "priceLevel", "priceRange", "rating", "userRatingCount", "websiteUri", "nationalPhoneNumber",
    "regularOpeningHours",
    # Enterprise + Atmosphere
    "editorialSummary", "generativeSummary", "reviewSummary", "reviews",
    "outdoorSeating", "liveMusic", "goodForChildren", "goodForGroups", "goodForWatchingSports", "allowsDogs",
    "reservable", "servesVegetarianFood", "servesCocktails", "servesBeer", "servesWine", "servesBrunch",
    "servesBreakfast", "servesLunch", "servesDinner", "servesDessert", "servesCoffee", "menuForChildren",
    "restroom", "takeout", "delivery", "dineIn", "paymentOptions", "parkingOptions",
]
FIELD_MASK = ",".join("places." + f for f in FIELDS) + ",nextPageToken"

# (google includedType, priority, prior: Overture activity_category, optional subcategory regex)
# The prior only shapes the tiles; it doesn't limit what Google returns.
QUERIES = [
    ("restaurant",               1, "Restaurants", None),
    ("cafe",                     1, "Cafes & Desserts", r"coffee|cafe|tea"),
    ("bakery",                   1, "Cafes & Desserts", r"bakery|patisserie|bagel"),
    ("ice_cream_shop",           1, "Cafes & Desserts", r"ice_cream|frozen_yogurt|gelato"),
    ("dessert_shop",             1, "Cafes & Desserts", r"dessert|donut|cupcake|chocolat|candy"),
    ("bar",                      1, "Bars & Nightlife", None),
    ("night_club",               1, "Bars & Nightlife", r"dance_club|nightlife|salsa|lounge"),
    ("museum",                   2, "Museums & Galleries", r"museum|planetarium|observatory"),
    ("art_gallery",              2, "Museums & Galleries", r"art_gallery"),
    ("tourist_attraction",       2, "Attractions & Tours", None),
    ("historical_landmark",      2, "Attractions & Tours", r"historic|monument|memorial|fort|castle"),
    ("performing_arts_theater",  2, "Shows & Live Events", r"theat|performing|opera|dinner"),
    ("live_music_venue",         2, "Shows & Live Events", r"music|jazz|band"),
    ("comedy_club",              2, "Shows & Live Events", r"comedy"),
    ("movie_theater",            2, "Shows & Live Events", r"movie"),
    ("concert_hall",             2, "Shows & Live Events", r"music|auditorium|symphony"),
    ("park",                     2, "Parks & Outdoors", None),
    ("garden",                   2, "Parks & Outdoors", r"garden"),
    ("beach",                    2, "Parks & Outdoors", r"beach"),
    ("hiking_area",              2, "Parks & Outdoors", r"trail|nature"),
    ("zoo",                      2, "Attractions & Tours", r"zoo"),
    ("aquarium",                 2, "Attractions & Tours", r"aquarium"),
    ("amusement_park",           2, "Attractions & Tours", r"amusement|water_park|carousel"),
    ("observation_deck",         2, "Attractions & Tours", r"observ"),
    ("bowling_alley",            2, "Games & Indoor Fun", r"bowling"),
    ("video_arcade",             2, "Games & Indoor Fun", r"arcade"),
    ("amusement_center",         2, "Games & Indoor Fun", None),
    ("karaoke",                  2, "Bars & Nightlife", r"karaoke"),
    ("miniature_golf_course",    2, "Games & Indoor Fun", r"golf"),
    ("indoor_playground",        2, "Games & Indoor Fun", r"playcenter|indoor"),
    ("spa",                      2, "Spas & Wellness", None),
    ("library",                  2, "Libraries & Bookstores", r"library"),
    ("book_store",               2, "Libraries & Bookstores", r"book"),
    ("market",                   2, "Shopping", r"market|food_hall"),
    ("shopping_mall",            2, "Shopping", r"mall|department"),
    ("gym",                      3, "Sports & Fitness", r"gym|fitness|boot_camp|boxing|cycl"),
    ("yoga_studio",              3, "Sports & Fitness", r"yoga|pilates|barre|tai_chi"),
    ("sports_complex",           3, "Sports & Fitness", r"sport|complex|field|court"),
    ("swimming_pool",            3, "Sports & Fitness", r"swim|pool"),
    ("ice_skating_rink",         3, "Games & Indoor Fun", r"skat"),
    ("playground",               3, "Parks & Outdoors", r"playground"),
    ("dog_park",                 3, "Parks & Outdoors", r"dog_park"),
    ("stadium",                  3, "Shows & Live Events", r"stadium|arena"),
    ("thrift_store",             4, "Shopping", r"second_hand|thrift|vintage"),
    ("gift_shop",                4, "Shopping", r"gift"),
    ("toy_store",                4, "Shopping", r"toy|hobby|game"),
    ("department_store",         4, "Shopping", r"department"),
]

NYC = (40.4774, -74.2591, 40.9176, -73.7004)          # lat_lo, lng_lo, lat_hi, lng_hi
AREAS = {                                              # small test areas for pilots
    "park_slope": (40.660, -73.990, 40.682, -73.968),
    "midtown":    (40.748, -73.995, 40.765, -73.972),
    "astoria":    (40.755, -73.935, 40.780, -73.900),
}
TARGET = 50          # plan tiles to hold about this many Google places (<= 60 max per query)
PRIOR_SCALE = 0.6    # Google lists ~0.57 places per Overture place (Park Slope pilot, restaurants)
MIN_TILE_DEG = 0.0015  # ~150 m; never split below this


# ---------------------------------------------------------------- prior (Overture density)
def load_points():
    tmp = tempfile.NamedTemporaryFile(suffix=".csv", delete=False).name
    sql = (f"COPY (SELECT lat, lng, activity_category, subcategory FROM "
           f"read_parquet('{os.path.join(HERE, 'nyc_activities.parquet')}')) TO '{tmp}' (HEADER);")
    subprocess.run(["duckdb", "-c", sql], check=True, capture_output=True)
    with open(tmp, newline="") as f:
        pts = [(float(r["lat"]), float(r["lng"]), r["activity_category"], r["subcategory"] or "") for r in csv.DictReader(f)]
    os.unlink(tmp)
    return pts


def prior_points(points, cat, rx):
    pat = re.compile(rx) if rx else None
    return [(la, ln) for la, ln, c, s in points if c == cat and (pat is None or pat.search(s))]


def inside(p, t):
    return t[0] <= p[0] < t[2] and t[1] <= p[1] < t[3]


def split(t):
    mlat, mlng = (t[0] + t[2]) / 2, (t[1] + t[3]) / 2
    return [(t[0], t[1], mlat, mlng), (t[0], mlng, mlat, t[3]), (mlat, t[1], t[2], mlng), (mlat, mlng, t[2], t[3])]


def plan_tiles(tile, pts, land):
    """Split by prior until expected count <= TARGET. Returns [(tile, expected)]. No API calls."""
    est = len(pts) * PRIOR_SCALE
    if est <= TARGET or (tile[2] - tile[0]) < MIN_TILE_DEG * 2:
        if est == 0 and len(land) < 5:      # empty water / outside NYC: skip
            return []
        return [(tile, est)]
    out = []
    for c in split(tile):
        out += plan_tiles(c, [p for p in pts if inside(p, c)], [p for p in land if inside(p, c)])
    return out


def expected_calls(est):
    return max(1, min(3, math.ceil(est / 20)))


# ---------------------------------------------------------------- state / logs
def tile_key(qtype, t):
    return f"{qtype}|" + ",".join(f"{x:.5f}" for x in t)


def load_state():
    """Returns (billable calls so far, done tile keys, saturated tiles [(qtype, tile, est, depth)])."""
    calls, done, got, meta = 0, set(), {}, {}
    if os.path.exists(CALLS_LOG):
        for line in open(CALLS_LOG):
            r = json.loads(line)
            calls += 1 if r.get("billable", True) else 0
            got[r["key"]] = got.get(r["key"], 0) + r["n"]
            meta[r["key"]] = (r["query_type"], tuple(r["tile"]), r.get("est", 0), r.get("depth", 0))
            if r.get("tile_done"):
                done.add(r["key"])
    saturated = [meta[k] for k in done if got.get(k, 0) >= 60]
    return calls, done, saturated


def load_key():
    for line in open(os.path.join(HERE, ".env")):
        m = re.match(r"\s*GOOGLE_PLACES_API_KEY\s*=\s*(.*)$", line)
        if m:
            return m.group(1).strip().strip('"').strip("'")
    return os.environ.get("GOOGLE_PLACES_API_KEY", "")


def strip_personal(place):
    """Drop reviewer names/photos/profile links; keep review text, rating, time, language."""
    for rv in place.get("reviews", []) or []:
        rv.pop("authorAttribution", None)
    return place


class Fatal(Exception):
    pass


class Budget(Exception):
    pass


class Transient(Exception):
    pass


class Harvester:
    def __init__(self, key, max_calls, used):
        self.key, self.max_calls, self.used = key, max_calls, used
        self.lock = threading.Lock()
        self.fplaces = open(PLACES_LOG, "a")
        self.fcalls = open(CALLS_LOG, "a")
        self.new_places = 0
        self.skipped = 0
        self.stop = threading.Event()

    def _reserve(self):
        with self.lock:
            if self.used >= self.max_calls:
                raise Budget()
            self.used += 1

    def request(self, body):
        self._reserve()
        req = urllib.request.Request(URL, data=json.dumps(body).encode(), method="POST", headers={
            "Content-Type": "application/json", "X-Goog-Api-Key": self.key, "X-Goog-FieldMask": FIELD_MASK})
        for attempt in range(6):
            try:
                with urllib.request.urlopen(req, timeout=40) as r:
                    return json.load(r)
            except urllib.error.HTTPError as e:
                msg = e.read().decode(errors="replace")[:400]
                if e.code in (429, 500, 502, 503, 504):
                    time.sleep(2 ** attempt)
                    continue
                if e.code == 400 and "pageToken" in body and attempt < 2:
                    time.sleep(2)            # page token not ready yet
                    continue
                raise Fatal(f"HTTP {e.code}: {msg}")
            except (urllib.error.URLError, TimeoutError, ConnectionError, OSError):
                time.sleep(2 ** attempt)
        raise Transient("network failure after retries")

    def log_call(self, rec):
        with self.lock:
            self.fcalls.write(json.dumps(rec) + "\n")
            self.fcalls.flush()

    def query_tile(self, qtype, tile, est, depth=0):
        """Query one tile with paging. If it saturates at 60 and can be split, query the children."""
        if self.stop.is_set():
            return
        key = tile_key(qtype, tile)
        body = {
            "textQuery": qtype.replace("_", " "),
            "includedType": qtype, "strictTypeFiltering": True, "pageSize": 20,
            "locationRestriction": {"rectangle": {"low": {"latitude": tile[0], "longitude": tile[1]},
                                                  "high": {"latitude": tile[2], "longitude": tile[3]}}},
        }
        got, page, token = 0, 0, None
        while True:
            b = dict(body, pageToken=token) if token else body
            resp = self.request(b)
            page += 1
            places = resp.get("places", [])
            got += len(places)
            now = datetime.now(timezone.utc).isoformat(timespec="seconds")
            with self.lock:
                for p in places:
                    self.fplaces.write(json.dumps({"query_type": qtype, "tile": tile, "page": page,
                                                   "fetched_at": now, "place": strip_personal(p)}) + "\n")
                self.fplaces.flush()
                self.new_places += len(places)
            token = resp.get("nextPageToken")
            last = not token or page >= 3
            self.log_call({"key": key, "query_type": qtype, "tile": tile, "page": page, "n": len(places),
                           "est": round(est, 1), "depth": depth, "at": now,
                           "tile_done": last and not (got >= 60 and token is None and False)})
            if last:
                break
        saturated = got >= 60
        if saturated and (tile[2] - tile[0]) >= MIN_TILE_DEG * 2:
            for c in split(tile):
                self.query_tile(qtype, c, est / 4, depth + 1)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--plan", action="store_true", help="print the tile plan and cost estimate, no API calls")
    ap.add_argument("--types", help="comma-separated Google types (default: all, by priority)")
    ap.add_argument("--priority", type=int, help="only types with priority <= N")
    ap.add_argument("--area", choices=sorted(AREAS), help="restrict to a small test area")
    ap.add_argument("--max-calls", type=int, default=0, help="HARD cap on billable requests across all runs")
    ap.add_argument("--workers", type=int, default=6)
    a = ap.parse_args()

    os.makedirs(OUT_DIR, exist_ok=True)
    queries = QUERIES
    if a.types:
        want = {t.strip() for t in a.types.split(",")}
        queries = [q for q in QUERIES if q[0] in want]
        missing = want - {q[0] for q in queries}
        if missing:
            sys.exit(f"Unknown types: {missing}")
    if a.priority:
        queries = [q for q in queries if q[1] <= a.priority]
    root = AREAS[a.area] if a.area else NYC

    points = load_points()
    land = [(la, ln) for la, ln, _, _ in points if inside((la, ln), root)]
    used, done, saturated = load_state()

    jobs, total_calls = [], 0
    print(f"{'type':26s} {'prio':>4s} {'tiles':>6s} {'exp.places':>10s} {'exp.calls':>9s} {'est $':>8s}")
    for qtype, prio, cat, rx in queries:
        pts = [p for p in prior_points(points, cat, rx) if inside(p, root)]
        tiles = plan_tiles(root, pts, land)
        todo = [(t, e) for t, e in tiles if tile_key(qtype, t) not in done]
        calls = sum(expected_calls(e) for _, e in todo)
        total_calls += calls
        print(f"{qtype:26s} {prio:>4d} {len(todo):>6d} {round(sum(e for _, e in todo)):>10d} {calls:>9d} {calls*COST_PER_CALL:>8.2f}")
        jobs += [(qtype, t, e) for t, e in todo]
    # children of tiles that came back full (60) but whose split didn't finish
    want_types = {q[0] for q in queries}
    orphans = [(q, c, e / 4, d + 1) for q, t, e, d in saturated if q in want_types and (t[2] - t[0]) >= MIN_TILE_DEG * 2
               for c in split(t) if tile_key(q, c) not in done]
    if orphans:
        print(f"Re-queueing {len(orphans)} sub-tiles of full tiles that weren't finished.")
        jobs = orphans + jobs
    print(f"\nPlanned calls: {total_calls} (~${total_calls*COST_PER_CALL:,.2f} before the free tier; "
          f"live splitting of full tiles adds some). Already used: {used} calls.")
    if a.plan:
        return
    if not a.max_calls:
        sys.exit("Set --max-calls (hard budget across all runs).")
    if used >= a.max_calls:
        sys.exit(f"Budget reached: {used} >= {a.max_calls}")

    key = load_key()
    if not key:
        sys.exit("No key: put GOOGLE_PLACES_API_KEY=... in .env")
    h = Harvester(key, a.max_calls, used)
    start_used = used

    def run(job):
        if h.stop.is_set():
            return
        try:
            h.query_tile(*job)
        except Budget:
            h.stop.set()
        except Transient as e:
            with h.lock:
                h.skipped += 1          # tile not marked done -> retried on the next run
        except Fatal as e:
            h.stop.set()
            print("\nStopping:", e, file=sys.stderr)

    t0 = time.time()
    with ThreadPoolExecutor(a.workers) as ex:
        for i, _ in enumerate(ex.map(run, jobs), 1):
            if i % 25 == 0:
                print(f"  tiles {i}/{len(jobs)}  calls this run {h.used - start_used}  places {h.new_places}", flush=True)
    spent = h.used - start_used
    print(f"\nDone in {time.time()-t0:.0f}s. Calls this run: {spent} (~${spent*COST_PER_CALL:.2f} list price), "
          f"total calls so far: {h.used}. Place results this run: {h.new_places} -> {PLACES_LOG}. "
          f"Tiles skipped on network errors (retry by re-running): {h.skipped}")
    if h.stop.is_set() and h.used >= a.max_calls:
        print("Stopped at the --max-calls budget. Re-run with a higher cap to continue.")


if __name__ == "__main__":
    main()
