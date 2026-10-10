#!/usr/bin/env python3
"""Seed the installed app's events inside the simulator container, then boot the simulator.
usage: scripts/seed_app.py <YYYY-MM-DD start> [cycle_length=28] [--tags] [--clear]
Needs the app installed (xcrun simctl install). `simctl spawn defaults write` does NOT reach the app
container, so this edits the container plist while the simulator is shut down.
"""
import json, plistlib, subprocess, sys, uuid
from datetime import date, datetime, timedelta, timezone

SIM = subprocess.check_output(["scripts/sim-id.sh"], text=True).strip()
BUNDLE = "beta.Rhythm"
KEY = "com.example.rhythm(x).events"

def sh(*a, check=True):
    return subprocess.run(a, check=check, capture_output=True, text=True).stdout.strip()

args = [a for a in sys.argv[1:] if not a.startswith("--")]
flags = {a for a in sys.argv[1:] if a.startswith("--")}
sh("xcrun", "simctl", "boot", SIM, check=False)
sh("xcrun", "simctl", "bootstatus", SIM, check=False)
container = sh("xcrun", "simctl", "get_app_container", SIM, BUNDLE, "data")  # needs a booted device
sh("xcrun", "simctl", "terminate", SIM, BUNDLE, check=False)
sh("xcrun", "simctl", "shutdown", SIM, check=False)
path = f"{container}/Library/Preferences/{BUNDLE}.plist"
try:
    with open(path, "rb") as f:
        prefs = plistlib.load(f)
except FileNotFoundError:
    prefs = {}

if "--clear" in flags:
    prefs.pop(KEY, None)
else:
    start = date.fromisoformat(args[0])
    length = int(args[1]) if len(args) > 1 else 28
    ref = datetime(2001, 1, 1, tzinfo=timezone.utc)
    phases = [("menstrual", range(0, 5)), ("follicular", range(5, 13)),
              ("ovulation", range(13, 16)), ("luteal", range(16, length))]
    tag_by_phase = {"menstrual": "Symptom:Cramps, Mood:Tired", "follicular": "Mood:Energetic, Exercise:Run",
                    "ovulation": "Cervical Mucus:Egg White, Symptom:Bloating", "luteal": "Symptom:Cramps, Mood:Irritable"}
    events = []
    for name, days in phases:
        for off in days:
            d = datetime.combine(start + timedelta(days=off), datetime.min.time(), tzinfo=timezone.utc)
            events.append({"id": str(uuid.uuid4()), "eventType": name,
                           "date": (d - ref).total_seconds(),
                           "note": f"{name.capitalize()} day {off + 1}",
                           "tags": tag_by_phase[name] if "--tags" in flags and off % 2 == 0 else ""})
    prefs[KEY] = json.dumps(events, separators=(",", ":")).encode()

with open(path, "wb") as f:
    plistlib.dump(prefs, f)
sh("xcrun", "simctl", "boot", SIM, check=False)
print("seeded", path)
