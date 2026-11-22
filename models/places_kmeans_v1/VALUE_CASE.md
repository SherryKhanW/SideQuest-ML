# Does the v1 model add value? An honest comparison

SideQuest is a **group** decision engine: up to 5 friends each enter their own budget, boroughs and
interests privately, get one shared swipe deck, and the app picks what most of them like. So the real
test is whether it produces a better *group* deck than the ways groups decide today.

## 1. Group decks vs how groups decide today (real places, 500 synthetic rooms)

`compare_group.py` runs 500 random rooms of 2–5 people, with realistic, varied preferences, through five
approaches. Each member is judged against **their own** stated preferences.

| | Cards that break someone's budget or borough | Members with ≥ 2 cards they'd like | Cards for the least-served person | Avg rating |
|---|---:|---:|---:|---:|
| Organizer searches alone (the group-chat way) | 52% | 55% | 1.1 | 4.76 |
| Popularity list within everyone's limits | 0% | 68% | 1.9 | 4.51 |
| One averaged request (typing it into a search box or chatbot) | 64% | 73% | 1.3 | 4.82 |
| SideQuest group logic, no clustering (k = 1) | 0% | 96% | 5.5 | 4.74 |
| **SideQuest group v1 (k = 25)** | **0%** | **96%** | **5.5** | 4.71 |

**What this shows:**
- **Naive approaches break people's limits.** When one person searches, or the group's wishes are averaged into one request, 52–64% of the cards are over somebody's budget or in a borough they won't go to. SideQuest has 0% by design: the price cap is the lowest budget and the boroughs are the ones everyone accepts.
- **Everyone gets something.** 96% of members get at least 2 cards that suit them, against 55–73%. The least-served person gets about 5.5 cards instead of 1–2. That comes from ranking by the worst-off member and filling slots for whoever has the fewest cards so far.
- **Clustering makes the group logic about 2.9× faster** (102 ms vs 292 ms median) with the same decks. The group step scores every candidate for every member, so searching only the best-fitting clusters matters more than for one person. Both times are fine for an app, so this is a modest benefit, not a money saving.
- **Ratings are about the same.** The averaged request scores slightly higher only because it ignores people's limits.

`group.py` holds the logic; `output/group_demo.md` has example rooms. In one, Friday-night friends with budgets from $$ to $$$$ get a $$ Manhattan deck mixing Thai restaurants, comedy clubs and bars, and every member gets 3–7 cards that suit them. A room whose members share no borough is told so instead of having someone's limit broken.

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

**Is the direction sound?** Yes. The value is the **group decision**, and that is measurable:
- 0% of cards break anyone's limits (vs 52–64% for the naive ways),
- 96% of members get cards they like (vs 55–73%),
- the least-served person gets about 5 times as many suitable cards.

**What clustering contributes, stated plainly:**
- named, explainable segments,
- about 2.9× faster group decks,
- for v2, the structure that lets a group's swipes be learned quickly.

It does not, by itself, make a single person's recommendations better.

**Against "just ask Claude":** a chatbot gets one person's description of the group. That's the "averaged
request" row, where 64% of cards break someone's limit, and it can't check that places are open or within
budget. SideQuest collects each person's limits privately, guarantees every card respects them, and lets the
group decide by swiping.

**What not to claim:** money saved, or the v2 simulation numbers as real results.

**Getting a real-world number:** the Dec 3 class exercise is a free pilot. Run rooms with the "organizer
searches" approach and with SideQuest, then measure time to a decision and how many people are happy with the
pick.
