"""Quest XP for WoW Forever quests, from data already on disk (no downloads).

Wowhead now answers scripted requests with a bot challenge (HTTP 202, empty page) or 403, so
this reads what's already here:
  1. QuestieDB's Classic quest XP table (support/Forever/QuestXP/xpDB-classic.lua):
     { [questId] = { level, xp } }.
  2. Every Wowhead page in Spyglass's cache (tools/Spyglass/.wowhead_cache) with a quest list
     (zone, item and quest list pages): their rows carry "xp".
Wowhead's value wins where both have one. Writes tools/FieldGuide/data/wowhead_quests.json:
{ questId: { xp, level, reqlevel, category, side, name, source } }.

    python tools/FieldGuide/fetch_xp.py
"""
import glob
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "Spyglass"))
import fetch_wowhead_quests as wh  # noqa: E402
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # sibling modules, also under python -I
from questiedb import DEFAULT_TOC  # noqa: E402

OUT = os.path.join(HERE, "data", "wowhead_quests.json")
XP_DB = os.path.join(os.path.dirname(os.environ.get("QUESTIEDB_TOC") or DEFAULT_TOC),
                     "support", "Forever", "QuestXP", "xpDB-classic.lua")


def questie_xp():
    out = {}
    try:
        with open(XP_DB, encoding="utf-8") as f:
            for m in re.finditer(r"\[(\d+)\]\s*=\s*\{\s*(\d+)\s*,\s*(\d+)\s*\}", f.read()):
                out[int(m.group(1))] = {"level": int(m.group(2)), "xp": int(m.group(3)), "source": "questie"}
    except OSError as e:
        print("No QuestieDB XP table:", e)
    return out


def cached_lists():
    out = {}
    for path in glob.glob(os.path.join(wh.CACHE, "*.html")):
        if os.path.getsize(path) == 0:
            continue
        with open(path, encoding="utf-8") as f:
            text = f.read()
        start = 0
        # A page can hold several quest lists (a zone page: started here, ended here...).
        while True:
            i = text.find("new Listview({template: 'quest'", start)
            if i < 0:
                break
            try:
                rows = wh.quest_list(text[i:])
            except Exception:  # a list we can't read: skip it
                rows = []
            for r in rows:
                if isinstance(r, dict) and r.get("id") and r.get("xp"):
                    row = {k: r.get(k) for k in ("name", "xp", "level", "reqlevel", "category", "category2", "side")}
                    row["source"] = "wowhead"
                    out[r["id"]] = row
            start = i + 10
    return out


def main():
    out = questie_xp()
    print("QuestieDB XP table: %d quests" % len(out))
    wowhead = cached_lists()
    print("Wowhead cache: %d quests with XP" % len(wowhead))
    out.update(wowhead)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        json.dump({str(k): v for k, v in sorted(out.items())}, f, indent=0)
    print("wrote %s: %d quests with XP" % (OUT, len(out)))


if __name__ == "__main__":
    main()
