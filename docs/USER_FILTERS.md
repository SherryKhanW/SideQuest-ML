# What users can customise: a data-backed list

Based on the 45,440 Google-verified NYC places in `data/places_v1.parquet`. The same file also has 755
official NYC Parks / GreenThumb places, which are always free but have no rating, hours or vibe data. For each possible setting this
lists how many places have the data ("coverage") and how much it narrows results ("selectivity": the
share of known places that say yes). A setting is only worth offering if the data is mostly there **and**
it actually narrows the deck.

## Tier 1: core settings (offer to everyone)

| Setting | What the user picks | Data behind it | Coverage | Notes |
|---|---|---|---:|---|
| **Activity** | 1+ of 12 categories | `activity_category` | 100% | Restaurants 20.5k, Cafes & Desserts 5.8k, Parks 3.5k, Spas 3.3k, Bars 2.8k, Shopping 2.2k, Attractions 2.0k, Fitness 1.8k, Museums 1.5k, Shows 1.0k, Libraries & Bookstores 0.8k, Games 0.2k |
| **Type / cuisine** (optional, refines activity) | e.g. sushi, comedy club, rooftop bar, playground | `subcategory` (340 types), `cuisine` (151) | 100% / 70% of restaurants | Top cuisines: Chinese 1.9k, pizza 1.7k, Mexican 1.5k, Italian 1.0k, American 0.8k, Japanese 0.6k |
| **Budget per person** | Free / up to $20 / $30 / $90 / no limit | `price_level`, `price_min_usd`, `price_max_usd` | 86% of restaurants, 77% of bars, 66% of cafes; ~0% elsewhere | Median per-person spend: $ = $10–20, $$ = $20–30, $$$ = $40–90, $$$$ = $100+. Outside food and drink the price is a category estimate (`price_final_source`); say so on the card |
| **Where you're starting from** | borough or neighborhood | `borough`, `neighborhood` (255), `lat`/`lng` | 100% | Replaces "pick boroughs". It lets the app choose fair places when people start in different boroughs |
| **How far you'll go** | e.g. 15 / 30 / 45 min, or "anywhere" | `lat`/`lng` (straight-line now; Routes API later) | 100% | Needed for the fair meeting point |
| **Near the subway** | "within a 5 / 10 min walk of a subway" | `nearest_subway_m`, `subway_lines_800m` | 100% | 64% of places are within 400 m (~5 min), 83% within 800 m |
| **Rating** | minimum stars | `rating` (smoothed by `rating_count`) | 93% | 4.7+: 12.9k, 4.5–4.69: 7.8k, 4.0–4.49: 14.6k, under 4.0: 7.1k |
| **Popular vs hidden gems** | slider | `rating_count` | 93% | 2,000+ reviews: 1.9k; 500–1,999: 7.6k; 50–499: 19.7k; under 50: 13.3k |
| **Open late** | "still open after 11 pm" | `open_late` (from hours) | 87% | 35% yes, so it's selective |

## Tier 2: vibe toggles (food and drink mostly)

Google provides these mainly for restaurants, bars and cafes. Treat them as **preferences**: a place is
excluded only when Google says "no", and places with unknown values rank lower but still appear.

| Toggle | Field | Known for | Says yes | Where it's available |
|---|---|---:|---:|---|
| **Live music** | `live_music` | 20.4k | 10% | restaurants 79%, bars 60% |
| **Sports on TV** | `good_for_watching_sports` | 16.4k | 15% | restaurants, bars |
| **Dog-friendly** | `allows_dogs` | 11.2k | 20% | restaurants 41%, bars 38%, parks 24% |
| **Kids' menu** | `menu_for_children` | 14.3k | 30% | restaurants |
| **Outdoor seating** | `outdoor_seating` | 17.0k | 36% | restaurants 65%, bars 65%, cafes 32% (parks are outdoor by definition) |
| **Cocktails / drinks** | `serves_cocktails`, `serves_beer`, `serves_wine` | 17.0k | 49% | bars 85%, restaurants 62% |
| **Takes reservations** | `reservable` | 17.0k | 56% | restaurants 64%, bars 69% |
| **Brunch / breakfast** | `serves_brunch`, `serves_breakfast` | 9.8k / 12.8k | 72% / 67% | restaurants, cafes |
| **Vegetarian options** | `serves_vegetarian` | 12.3k | 75% | restaurants 51% |
| **Kid-friendly** | `good_for_children` | 26.0k | 77% | most categories, 25–80% |

## Tier 3: accessibility (hard requirements when set)

| Setting | Field | Coverage | Notes |
|---|---|---:|---|
| **Wheelchair-accessible entrance** | `wheelchair_entrance` | 60% (95% of known say yes) | When someone sets it, show only places confirmed accessible |
| **Step-free subway nearby** | `ada_subway_800m` | 100% (63% yes) | A fully accessible station within 800 m |
| **Restroom on site** | `restroom` | 57% (88% yes) | Useful for families and long outings |

## Tier 4: quality and taste extras

| Setting | Field | Coverage | Notes |
|---|---|---:|---|
| **Health grade A only** | `inspection_grade` | 59% of food places | A 14.8k, B 1.4k, C 0.4k; ungraded = new or not yet inspected |
| **Skip chains** | `is_chain` | 100% | 10% are chains |
| **Famous landmarks** | `wikidata_sitelinks` | 4% overall; 11–17% of attractions and shows | Good for a "tourist day" mode |
| **Big parks** | `acres` | 34% of parks | 124 parks of 10+ acres; good for a "proper park day" toggle |
| **Opening hours on a chosen day and time** | raw Google `regularOpeningHours.periods` | 87% | Not computed yet. The raw harvest has the full weekly schedule, so "open Saturday 8 pm" is a small data step |

## Not worth offering

| Setting | Why |
|---|---|
| Good for groups | 98% of known places say yes, so it doesn't narrow anything |
| Takeout, delivery, dine-in | 82–96% yes, and not what a group outing needs |
| Open on weekends | 96% yes |
| Serves dessert | 90% yes |
| Halal, kosher, vegan (OSM) | Known for under 2% of places, too sparse to filter on |
| Cash only / card accepted | 2% are cash-only. Could be a card label, not a filter |
| Wi-fi, capacity | Almost never known |

## What v1 implements

The final per-category lists are in `models/places_kmeans_v1/category_config.py`, exported as `output/category_filters.json` for the app:
- **Room settings (organizer):** borough(s), group size, when.
- **Universal per-person settings:** max price, kid-friendly, outdoors, late night & drinks, wheelchair access (`v1: true`).
- **Per category:** curated type groups (e.g. Bars → Cocktail & wine bars / Pubs / Sports bars / Clubs & hookah / Karaoke / Breweries), restaurant cuisines (19 groups covering 84% of restaurants), and extra toggles (`v1: false`, the v2 UI).
- **Card fields per category:** e.g. restaurants show cuisine, $ range, rating, open-until and health grade; parks show type, Free, size and nearest subway.

Types outside the curated groups are data noise (e.g. Doctor under Spas, Supermarket under Shopping) and are never recommended. Neither are places rated below 3.5★ with 10+ ratings. That leaves 43,069 recommendable places.

## How settings combine in a group room

- **Hard limits combine strictly:** the room's boroughs and time (the organizer's), budget (lowest wins), and accessibility (if anyone needs it, every card has a confirmed accessible entrance).
- **Soft preferences combine fairly:** activity, type, vibes, rating and popularity. The deck is ranked by the average member plus the worst-off member, and every member gets cards that suit them (`models/places_kmeans_v1/group.py`).
- **Location is decided by the room:** the organizer picks the borough(s) when creating the room, so members never end up with no borough in common. A later "starting area + travel time" option could add fairness within those boroughs.

## Effect on the model

- **v1 clusters already use:** category, price, and 8 vibes (kids, groups, outdoor, live music, dogs, alcohol, reservable, open late). Every other setting above is a filter or ranking signal, so nothing needs refitting.
- **Candidates to add as features in v2:** brunch/breakfast, vegetarian, sports, kids' menu. Drop "groups" (98% yes, no signal), plus popularity and distance once swipe data shows what actually drives likes.
