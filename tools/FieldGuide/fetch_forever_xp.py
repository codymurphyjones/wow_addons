"""What quests really pay on WoW Forever, from players' comments on Wowhead's Forever quest pages.

Wowhead's own "xp" field for a quest is often still the Classic value (Testing an Enemy's Strength
says 1,050; players report 3,200, then 2,150 after the dungeon XP nerf), so the comments are the
better source. This reads the quest pages of every dungeon quest and of a sample of the others,
and keeps each comment dated on or after SINCE that gives an amount of XP for the quest.

Writes tools/FieldGuide/data/forever_quest_xp.json:
{ questId: { name, level, listed, dungeon, comments: [ { xp, date, user, text } ] } }
It's resumable: quests already in the file aren't fetched again.

    python -I tools/FieldGuide/fetch_forever_xp.py
"""
import json
import os
import random
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "_shared"))
import webfetch  # noqa: E402

BASE = "https://www.wowhead.com/forever/"
OUT = os.path.join(HERE, "data", "forever_quest_xp.json")
DATA = os.path.join(os.path.dirname(os.path.dirname(HERE)), "addons", "FieldGuide", "Guides", "Data.lua")
SINCE = "2026-08-01"  # comments before this are about older versions of the game
SAMPLE = 120          # quests that aren't a dungeon's, to see whether they changed too
PACE = 1.2            # seconds between pages

ROW = re.compile(r'^\s*\[(\d+)\] = \{ n = "(.*?)", l = (-?\d+), r = \d+, xp = (\d+)(.*)$', re.M)
COMMENT = re.compile(r'"user":"([^"]*)","body":"((?:[^"\\]|\\.)*)","date":"(\d{4}-\d\d-\d\d)')
AMOUNT = re.compile(r"(\d{1,2},\d{3}|\d{3,6})\s*(?:xp|exp\b|experience)", re.I)


def quests():
    with open(DATA, encoding="utf-8") as f:
        text = f.read()
    dungeon, other = [], []
    for m in ROW.finditer(text):
        row = (int(m[1]), m[2], int(m[3]), int(m[4]))
        (dungeon if "dq = true" in m[5] else other).append(row)
    random.Random(7).shuffle(other)
    return dungeon, [q for q in other if 5 <= q[2] <= 60][:SAMPLE]


def main():
    out = {}
    if os.path.exists(OUT):
        with open(OUT, encoding="utf-8") as f:
            out = json.load(f)
    dungeon, sample = quests()
    todo = [(q, True) for q in dungeon] + [(q, False) for q in sample]
    print(len(dungeon), "dungeon quests,", len(sample), "others,", len(out), "already read", flush=True)
    for n, ((qid, name, level, listed), isdungeon) in enumerate(todo):
        if str(qid) in out:
            continue
        status, body = webfetch.fetch(BASE + "quest=%d" % qid)
        if status != 200:
            print("quest", qid, "status", status, flush=True)
            time.sleep(PACE)
            continue
        comments = []
        for user, text, date in COMMENT.findall(body or ""):
            if date >= SINCE:
                found = AMOUNT.findall(text)
                if found:
                    comments.append({"xp": [int(a.replace(",", "")) for a in found], "date": date, "user": user, "text": text[:200]})
        out[str(qid)] = {"name": name, "level": level, "listed": listed, "dungeon": isdungeon, "comments": comments}
        if n % 10 == 0:
            with open(OUT, "w", encoding="utf-8", newline="\n") as f:
                json.dump(out, f, indent=0, sort_keys=True)
            print(n, "of", len(todo), flush=True)
        time.sleep(PACE)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        json.dump(out, f, indent=0, sort_keys=True)
    print("done:", len(out), "quests,", sum(1 for q in out.values() if q["comments"]), "with Forever XP comments")


if __name__ == "__main__":
    main()
