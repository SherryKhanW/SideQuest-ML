#!/usr/bin/env python3
"""Run one room end to end using only this folder (no SideQuest-ML repo needed)."""
import os
import sys
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
os.environ["SIDEQUEST_PLACES"] = str(HERE / "data" / "places_catalog.parquet")
os.environ["SIDEQUEST_MODEL_DIR"] = str(HERE / "model")
sys.path.insert(0, str(HERE / "engine"))

from recommend import Recommender                                  # noqa: E402
from group import GroupRecommender, Member, Room, pick_winner      # noqa: E402

engine = GroupRecommender(Recommender.load())
room = Room(["Manhattan"], 3, datetime(2026, 12, 4, 20, 0))
members = [Member("Ana", 3, ["Bars & Nightlife"], ["nightlife"]),
           Member("Ben", 2, ["Restaurants"], cuisines=["Korean"]),
           Member("Chi", 2, ["Restaurants", "Bars & Nightlife"], needs_wheelchair=True)]
out = engine.recommend_room(room, members)
for i, c in enumerate(out["deck"], 1):
    print(i, c["id"], c["name"], "|", c["category"], "|", " · ".join(str(v) for k, v in c["fields"].items()
                                                                  if k != "summary"), "| for", c["for"])
votes = {m.name: {c["id"]: m.name in c["for"] for c in out["deck"]} for m in members}
print("winner:", (pick_winner(out["deck"], votes)["match"] or {}).get("name"))
