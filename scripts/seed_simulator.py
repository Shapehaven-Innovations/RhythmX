#!/usr/bin/env python3
"""Prints hex for the events UserDefaults value: a generated cycle starting on a date.
usage: seed_simulator.py 2026-09-26 28
then:  xcrun simctl spawn $SIM defaults write beta.Rhythm "com.example.rhythm(x).events" -data $(scripts/seed_simulator.py 2026-09-26 28)
"""
import json, sys, uuid
from datetime import date, datetime, timedelta, timezone

start = date.fromisoformat(sys.argv[1])
length = int(sys.argv[2]) if len(sys.argv) > 2 else 28
ref = datetime(2001, 1, 1, tzinfo=timezone.utc)
phases = [("menstrual", range(0, 5)), ("follicular", range(5, 13)),
          ("ovulation", range(13, 16)), ("luteal", range(16, length))]
events = []
for name, days in phases:
    for off in days:
        d = datetime.combine(start + timedelta(days=off), datetime.min.time(), tzinfo=timezone.utc)
        events.append({"id": str(uuid.uuid4()), "eventType": name,
                       "date": (d - ref).total_seconds(),
                       "note": f"{name.capitalize()} day {off + 1}", "tags": ""})
print(json.dumps(events, separators=(",", ":")).encode().hex())
