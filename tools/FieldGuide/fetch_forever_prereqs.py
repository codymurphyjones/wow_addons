"""Prerequisites of WoW Forever's own quests, from players' comments on Wowhead's Forever quest pages.

Questie's data has no prerequisites for most of Forever's new quests (The Wrath of Rath'mael, The New
Plague, Her Name Is Olgra...), so Field Guide sent you to givers who didn't offer them yet. Wowhead
shows no series for them either, but players write it in the comments: "Prerequisite is
[quest=99156]", "you need to do [quest=...] first", "requires [quest=...]". This reads the Forever
quest page of every Forever quest in the guides that has no prerequisite (id 90000 and up), and keeps
the quests a comment names as needed first, linked ([quest=N]) or by name in plain text (the longest
quest name in the sentence; of several quests with that name, the one in the same zone, else the one
at or under its level). A comment that names a quest as coming after ("leads to", "unlocks", "opens",
"next") is left out: that's the other way round. Every page read is kept in .wowhead_cache/
(forever_quest_<id>.html), so a better reading of the comments never needs Wowhead again.

Writes tools/FieldGuide/data/forever_prereqs.json:
  { questId: { name, pre: [questId, ...], evidence: [ { date, user, text } ] } }
  (quests read and found to have no prerequisite are kept with pre = [], so reruns skip them).
Resumable (pages cached, every cached page read again each run); build_guides.py adds what it
finds where Questie has nothing.

    python -I tools/FieldGuide/fetch_forever_prereqs.py
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

BASE = "https://www.wowhead.com/forever/quest=%d"
OUT = os.path.join(HERE, "data", "forever_prereqs.json")
DATA = os.path.join(os.path.dirname(os.path.dirname(HERE)), "addons", "FieldGuide", "Guides", "Data.lua")
FIRST_NEW = 90000   # Forever's own quests start here
PACE = 6.0          # seconds between pages (plus a little at random): faster and Wowhead starts refusing
CACHE = os.path.join(HERE, ".wowhead_cache")
MIN_NAME = 8        # a quest name this long or longer is recognised in plain text
BACKOFF = (30, 90, 240)  # seconds to wait before trying a refused page again
GIVE_UP = 3         # refused this many quests in a row: stop (rerun later; the file keeps what's done)

COMMENT = re.compile(r'"body":"((?:[^"\\]|\\.)*)"(.{0,400}?)"date":"([^"]+)"', re.S)
USER = re.compile(r'"user":"([^"]*)"')
QUEST = re.compile(r"\[quest=(\d+)\]")
# Said of a quest that comes first, or of one that comes after: only the first kind counts.
BEFORE = re.compile(r"pre-?req|prerequisite|require|need(?:s|ed)? (?:to )?(?:do|complete|finish|have)|"
                    r"\bafter (?:completing|doing|finishing|you)|unlocked by|comes? after|first do|do .{0,30} first|"
                    r"\bbefore (?:you can|this|it)|chain starts|starts? with|breadcrumb", re.I)
# Sentences that say the opposite, or something else: "no need to do X first", "did not need X",
# "this is a breadcrumb for X" (X comes after), "while doing X" (at the same time), and comments
# that only list a dungeon's quests ("Quest: ... Others: ..."). Checked by hand against the first
# run (2026-11-06): each of these had been read as a prerequisite and wasn't one.
NOT_BEFORE = re.compile(r"\bno need\b|\bnot need|n't need|\bnot required\b|n't required|doesn't require|"
                        r"\bnot (?:a )?pre-?req|breadcrumb|simultaneous|\bwhile\b|"
                        r"\bothers?:|\bgo to\b|\bdestroy\b|\bkill\b", re.I)
AFTER = re.compile(r"leads? to|unlocks|opens|followed by|\bnext\b|then you get|continues? (?:with|in)", re.I)


def unescape(s):
    try:
        return json.loads('"%s"' % s)
    except ValueError:
        return s


def guide_quests():
    """{ questId: name } of the guide's Forever quests with no prerequisite."""
    out = {}
    with open(DATA, encoding="utf-8") as f:
        for line in f:
            m = re.match(r'\s*\[(\d+)\] = \{ n = "((?:[^"\\]|\\.)*)"', line)
            if m and int(m.group(1)) >= FIRST_NEW and " pre = {" not in line:
                out[int(m.group(1))] = m.group(2)
    return out


_NAMES = None


def names():
    """QuestieDB's quests by lower-case name: { name: [ (id, zone, level), ... ] }, longest names first."""
    global _NAMES
    if _NAMES is None:
        from questiedb import QuestieDB
        db = QuestieDB.load()
        by = {}
        for qid in db.quest_ids():
            q = db.quest(qid) or {}
            n = (q.get("name") or "").strip().lower()
            if len(n) >= MIN_NAME:
                by.setdefault(n, []).append((qid, q.get("zoneOrSort"), q.get("questLevel") or 0))
        _NAMES = (by, sorted(by, key=len, reverse=True), db)
    return _NAMES


def by_name(qid, sentence):
    """The quest named in plain text in the sentence (the longest name found), or None."""
    by, ordered, db = names()
    text = sentence.lower()
    me = db.quest(qid) or {}
    own = (me.get("name") or "").strip().lower()
    for n in ordered:
        if n == own or n not in text:
            continue
        if not re.search(r"(?<![a-z])%s(?![a-z])" % re.escape(n), text):
            continue
        cands = [c for c in by[n] if c[0] != qid]
        if not cands:
            continue
        same = [c for c in cands if c[1] == me.get("zoneOrSort")]
        under = [c for c in cands if c[2] <= (me.get("questLevel") or 99)]
        pick = (same or under or cands)
        return max(pick, key=lambda c: c[2])[0]
    return None


def prerequisites(qid, page):
    pre, evidence = [], []
    for m in COMMENT.finditer(page):
        body, between, date = unescape(m.group(1)), m.group(2), m.group(3)
        # Each sentence on its own: "X is the prerequisite, it leads to Y" names X only.
        for sentence in re.split(r"(?<=[.!?\n])\s+", body):
            plain = re.sub(r"\[/?[a-z]+\]", "", sentence)  # (markup: "[i]not[/i]")
            if not BEFORE.search(sentence) or NOT_BEFORE.search(plain) or AFTER.search(sentence) and not BEFORE.search(sentence.split("[quest=")[0]):
                continue
            found = [int(x) for x in QUEST.findall(sentence) if int(x) != qid]
            if not found:
                named = by_name(qid, sentence)
                found = [named] if named else []
            if not found:
                continue
            for x in found:
                if x not in pre:
                    pre.append(x)
            user = USER.search(between)
            evidence.append({"date": date[:10], "user": user.group(1) if user else "", "text": sentence.strip()[:240]})
    return pre, evidence


def main():
    done = {}
    if os.path.exists(OUT):
        with open(OUT, encoding="utf-8") as f:
            done = {int(k): v for k, v in json.load(f).items()}
    os.makedirs(CACHE, exist_ok=True)
    quests = sorted(guide_quests().items())
    cached = lambda q: os.path.join(CACHE, "forever_quest_%d.html" % q)  # noqa: E731
    # Cached pages: read again (the reading may have improved); the rest: fetched.
    for qid, name in quests:
        if os.path.exists(cached(qid)):
            with open(cached(qid), encoding="utf-8") as f:
                pre, evidence = prerequisites(qid, f.read())
            done[qid] = {"name": name, "pre": pre, "evidence": evidence}
    todo = [(q, n) for q, n in quests if not os.path.exists(cached(q))]
    print("%d Forever quests without a prerequisite; %d cached, %d to fetch" % (len(quests), len(quests) - len(todo), len(todo)))
    refused = 0
    for i, (qid, name) in enumerate(todo, 1):
        status, page = webfetch.fetch(BASE % qid)
        for wait in BACKOFF:
            if status == 200 and page:
                break
            print("  %d %s: HTTP %s, trying again in %d s" % (qid, name, status, wait))
            time.sleep(wait)
            status, page = webfetch.fetch(BASE % qid)
        if status != 200 or not page:
            refused += 1
            print("  %d %s: HTTP %s, skipped" % (qid, name, status))
            if refused >= GIVE_UP:
                print("Wowhead keeps refusing: stopped. Rerun later; what's read is kept.")
                break
            continue
        refused = 0
        with open(cached(qid), "w", encoding="utf-8", newline="\n") as f:
            f.write(page)
        pre, evidence = prerequisites(qid, page)
        done[qid] = {"name": name, "pre": pre, "evidence": evidence}
        if pre:
            print("  %d %s <- %s" % (qid, name, ", ".join(map(str, pre))))
        if i % 10 == 0 or i == len(todo):
            with open(OUT, "w", encoding="utf-8", newline="\n") as f:
                json.dump({str(k): v for k, v in sorted(done.items())}, f, indent=1)
            print("  %d/%d read" % (i, len(todo)))
        time.sleep(PACE + random.random() * 0.6)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        json.dump({str(k): v for k, v in sorted(done.items())}, f, indent=1)
    found = sum(1 for v in done.values() if v["pre"])
    print("done: %d quests read, %d with a prerequisite named in comments" % (len(done), found))


if __name__ == "__main__":
    main()
