# Does the v1 model add value? An honest comparison

SideQuest is a **group** decision engine. The organizer sets the room's borough(s), group size and time. Up
to 5 friends each enter their own budget and interests privately, get one shared swipe deck, and the app picks
what most of them like. So the real test is whether it produces a better *group* deck than the ways groups
decide today.

## 1. Room decks vs how groups decide today (real places, 500 synthetic rooms)

`compare_group.py` runs 500 random rooms through five approaches. Each room has the organizer's boroughs and a
time (weekday evening to Saturday 11 pm), 2–5 members with varied budgets, categories and sometimes a vibe, type
or cuisine, and occasionally someone who needs wheelchair access. Each member is judged against **their own**
stated preferences.

| | Breaks someone's budget or the room's borough | Closed at the chosen time | No accessible entrance when someone needs it | Members with ≥ 2 cards they'd like | Cards for the least-served person | Avg rating |
|---|---:|---:|---:|---:|---:|---:|
| Organizer searches alone (the group-chat way) | 42% | 35% | 28% | 52% | 0.9 | 4.75 |
| Popularity list within budget and borough | 0% | 16% | 5% | 59% | 1.3 | 4.52 |
| One averaged request (search box or chatbot) | 63% | 37% | 37% | 64% | 0.9 | 4.82 |
| SideQuest room logic, no clustering (k = 1) | 0% | 0% | 0% | 94% | 4.7 | 4.69 |
| **SideQuest room v1 (k = 25)** | **0%** | **0%** | **0%** | **94%** | **4.5** | 4.66 |

The wheelchair column covers the 82 rooms where someone needed access. 35 more random rooms were skipped
because nothing at all fit at that time, e.g. free museums at 11 pm.

**What this shows:**
- **Naive approaches give unusable cards.**
  - When one person searches, 42% of cards are over someone's budget or outside the room's borough, and 35% are closed at the planned time.
  - When the group's wishes are averaged into one request, those figures are 63% and 37%.
  - Even a popularity list that respects budget and borough shows 16% of places closed at the planned time.
  - SideQuest has 0% on all three by design.
- **Everyone gets something.** 94% of members get at least 2 cards that suit them, against 52–64%. The least-served person gets about 4.5 cards instead of about 1. That comes from ranking by the worst-off member and filling slots for whoever has the fewest cards so far.
- **Clustering no longer makes room decks meaningfully faster:** 41 ms vs 45 ms. The room's borough and time shrink the pool before clustering kicks in. An earlier, borough-free version measured 2.9× faster; that no longer holds, and k = 1 is marginally fairer here (4.7 vs 4.5 cards for the least-served person).
- **Ratings are about the same.** The averaged request scores slightly higher only because it ignores people's limits and opening hours.

`group.py` holds the logic; `output/group_demo.md` has example rooms. In one, a Friday 8 pm Manhattan room of five gets:
- cocktail bars for Ana,
- Thai and Japanese spots for Ben,
- comedy clubs for Dev,

with everything at or under $$ and open past 9:30 pm. A Saturday 11:30 pm Brooklyn room only gets places open until at least 1 am.

## 2. One person's deck (real data, 575 queries)

`compare_baselines.py` compares single-user decks:

| | Popularity list | k = 1 (no clusters) | v1 (k = 25) |
|---|---:|---:|---:|
| Time | 2.0 ms | 3.3 ms | 3.2 ms |
| Average rating | 4.52 | 4.72 | 4.71 |
| Matches the requested vibe | 19% | 37% | 37% |
| Hidden gems (≥ 4.6★, < 500 reviews) | 7% | 51% | 51% |
| Distinct places shown across queries | 998 | 1,723 | 1,752 |

For one person, the ranking beats a popularity list, and clustering changes nothing: same quality, same speed.

## 3. v2: learning from the group's swipes (simulation, not evidence)

`simulate_group_swipes.py` runs synthetic groups of 5 swiping 20 cards. Their taste is generated from the
same features the model uses, so this checks the mechanism; it isn't a result.

| | Group finds a match within 10 cards | Matches in the first 10 cards |
|---|---:|---:|
| Popularity list | 81% | 3.5 |
| v1 static deck (today) | 87% | 4.7 |
| v2: learn which clusters the group likes | 89% | 5.2 |
| v2: learn feature weights, no clusters | 98% | 4.8 |

Cluster-level learning gives about 10% more matches than v1's static deck: 25 segments can be learned from a
handful of swipes, 45k individual places can't. Only real swipes can confirm this.

## Verdict

**Is the direction sound?** Yes. The value is the **room decision**, and that is measurable:
- 0% of cards break anyone's budget, the room's borough, the opening hours or an accessibility need (vs 28–63% for the naive ways),
- 94% of members get cards they like (vs 52–64%),
- the least-served person gets about 5 times as many suitable cards.

**What clustering contributes, stated plainly:**
- named, explainable segments ("Luxury restaurants · drinks, reservations"),
- for v2, the structure that lets a group's swipes be learned quickly: 25 segments instead of 43k places.

Today it does **not** make decks better or meaningfully faster; the filters, ranking and fair fill do that.
Clustering's case rests on explainability and on v2.

**Against "just ask Claude":** a chatbot gets one person's description of the group. That's the "averaged
request" row: 63% of cards break someone's limit and 37% are closed at the planned time. SideQuest collects each person's limits privately, guarantees every card respects them, and lets the
group decide by swiping.

**What not to claim:** money saved, or the v2 simulation numbers as real results.

**Getting a real-world number:** the Dec 3 class exercise is a free pilot. Run rooms with the "organizer
searches" approach and with SideQuest, then measure time to a decision and how many people are happy with the
pick.
