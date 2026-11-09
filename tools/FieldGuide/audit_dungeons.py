"""Audits every dungeon quest's road in: each quest of each dungeon (to pick up before the run, after it,
started inside, or led to by one started inside), and every quest it needs first, as far back as the
chain goes. Checks that the dungeon route (FieldGuide's Instance.lua) can really get you ready:

  missing    a quest needed first isn't in Guides\\Data.lua: the route can't send you to it, and the
             dungeon quest is never offered
  faction    a quest needed first is for the other faction (or races you can't be)
  dungeon    a quest needed first is another dungeon's quest: that dungeon comes first
  inside     a quest to pick up before the run needs one done inside the dungeon (it belongs after)
  giver      a quest on the road has no giver (nor an item that starts it), or no hand-in
  level      a quest needed first needs a higher level than the dungeon's last level
  series     Wowhead's quest series (the page's "Series" box) has a quest before this one that our
             prerequisites don't (with --wowhead; the strongest evidence there is)
  unchecked  one of Forever's own quests (90000+) with no prerequisite and no series read for it

Reads Guides\\Data.lua and Guides\\Instances.lua (the build's output) and tools/FieldGuide/instances.py
(levels). With --wowhead, reads each quest's Wowhead Forever page (cached in .wowhead_cache/, the same
forever_quest_<id>.html files fetch_forever_prereqs.py keeps; a real Chrome window, see webfetch.py)
and writes the series disagreements to data/dungeon_series.json for build_guides.py to use.

    python -I tools/FieldGuide/audit_dungeons.py [--wowhead]
Writes tools/FieldGuide/dungeon_audit_report.txt.
"""
import json
import os
import random
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "_shared"))
from instances import LEVELS  # noqa: E402

ADDON = os.path.join(os.path.dirname(os.path.dirname(HERE)), "addons", "FieldGuide")
REPORT = os.path.join(HERE, "dungeon_audit_report.txt")
SERIES_OUT = os.path.join(HERE, "data", "dungeon_series.json")
CACHE = os.path.join(HERE, ".wowhead_cache")
BASE = "https://www.wowhead.com/forever/quest=%d"
PACE = 6.0
FIRST_NEW = 90000
FACTION_BITS = {"Alliance": 1 + 4 + 8 + 64 + 2 ** 32, "Horde": 2 + 16 + 32 + 128 + 2 ** 33}  # build_guides.py FACTION_MASK

SERIES = re.compile(r'<table class="series">(.*?)</table>', re.S)
ROW = re.compile(r"<tr>(.*?)</tr>", re.S)
LINK = re.compile(r'href="/forever/quest=(\d+)')


def load_lua():
    import lupa
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    ns = lua.eval("{}")
    run = lua.eval("function(src, ns) return assert(load(src))('FieldGuide', ns) end")
    for name in ("Data.lua", "Instances.lua"):
        with open(os.path.join(ADDON, "Guides", name), encoding="utf-8") as f:
            run(f.read(), ns)
    return lua, ns


def to_py(v):
    """Lua tables to dicts/lists."""
    if v is None or isinstance(v, (int, float, str, bool)):
        return v
    keys = list(v.keys())
    if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
        return [to_py(v[k]) for k in sorted(keys)]
    return {k: to_py(v[k]) for k in keys}


def dungeon_names():
    out = {}
    with open(os.path.join(ADDON, "Guides", "Instances.lua"), encoding="utf-8") as f:
        for line in f:
            m = re.match(r"\s*\{ id = (\d+), -- (.*)", line)
            if m:
                out[int(m.group(1))] = m.group(2).strip()
    return out


def can_take(rm, faction):
    return not rm or (rm & FACTION_BITS[faction]) != 0


def series_of(qid, fetch):
    """The quests before qid in its Wowhead series, the row just before it ({ id, ... }: any one of them),
    or None (no series, or no page)."""
    path = os.path.join(CACHE, "forever_quest_%d.html" % qid)
    text = None
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            text = f.read()
    elif fetch:
        import webfetch
        for wait in (0, 30, 90):
            if wait:
                time.sleep(wait)
            status, body = webfetch.fetch(BASE % qid)
            if status == 200 and body:
                text = body
                os.makedirs(CACHE, exist_ok=True)
                with open(path, "w", encoding="utf-8") as f:
                    f.write(text)
                break
        time.sleep(PACE + random.random() * 2)
    if text is None:
        return None
    m = SERIES.search(text)
    if not m:
        return []
    rows = ROW.findall(m.group(1))
    for i, row in enumerate(rows):
        if "<b>" in row and not LINK.search(row.split("<b>")[1].split("</b>")[0]):
            if i == 0:
                return []
            return [int(x) for x in LINK.findall(rows[i - 1])]
    return []


def main():
    fetch = "--wowhead" in sys.argv
    lua, ns = load_lua()
    quests = to_py(ns.Quests)
    dungeons = to_py(ns.DungeonQuests)
    names = dungeon_names()
    # Checked by hand (data/prereqs_manual.json): what it says stands over Wowhead's series.
    with open(os.path.join(HERE, "data", "prereqs_manual.json"), encoding="utf-8") as f:
        checked = {k for k in json.load(f) if k.isdigit()}

    def Q(qid):
        return quests.get(qid)

    # Every quest in scope: the dungeons' quests and everything they need first.
    scope = {}  # qid -> { (dungeon, faction, role) }
    roles = []
    for d in dungeons:
        for faction in ("Alliance", "Horde"):
            for qid in d.get(faction) or []:
                roles.append((d, faction, "before", qid))
            for qid in (d.get("after") or {}).get(faction) or []:
                roles.append((d, faction, "after", qid))
            for qid in (d.get("inside") or {}).get(faction) or []:
                roles.append((d, faction, "inside", qid))
                for f in (d.get("follow") or {}).get(qid) or []:
                    # (One list for both factions: the route leaves out what isn't yours.)
                    if f in quests and can_take(quests[f].get("rm"), faction):
                        roles.append((d, faction, "follow", f))

    def chain(qid, faction, seen=None, depth=0):
        """Every quest qid needs first, earliest first: [(qid, depth, any)]. Of "any one of these", the
        ones the faction can take (all of them when it can take none: the faction check flags that)."""
        seen = seen if seen is not None else set()
        out = []
        q = Q(qid)
        if not q or depth > 15:
            return out
        pre = q.get("pre") or []
        if q.get("preAny"):
            mine = [p for p in pre if Q(p) and can_take(Q(p).get("rm"), faction)]
            pre = mine[:1] or pre[:1]
        for p in pre:
            if p in seen:
                continue
            seen.add(p)
            out += chain(p, faction, seen, depth + 1)
            out.append((p, depth + 1, bool(q.get("preAny"))))
        return out

    for d, faction, role, qid in roles:
        scope.setdefault(qid, set()).add((d["id"], faction, role))
        for p, _, _ in chain(qid, faction):
            scope.setdefault(p, set()).add((d["id"], faction, "needed"))

    series = {}
    if fetch:
        todo = [qid for qid in sorted(scope) if not os.path.exists(os.path.join(CACHE, "forever_quest_%d.html" % qid))]
        print("Wowhead: %d quests in scope, %d to fetch (about %d minutes)" % (len(scope), len(todo), len(todo) * (PACE + 2) // 60))
    for i, qid in enumerate(sorted(scope)):
        s = series_of(qid, fetch)
        if s is not None:
            series[qid] = s
        if fetch and i % 25 == 0:
            print("  %d/%d" % (i, len(scope)), flush=True)

    dungeon_of = {}
    for d in dungeons:
        for faction in ("Alliance", "Horde"):
            for qid in (d.get(faction) or []) + ((d.get("after") or {}).get(faction) or []) + ((d.get("inside") or {}).get(faction) or []):
                dungeon_of.setdefault(qid, d["id"])
            for fs in (d.get("follow") or {}).values():
                for f in fs:
                    dungeon_of.setdefault(f, d["id"])

    def done_inside(d, qid):
        q = Q(qid) or {}
        faction_inside = set()
        for faction in ("Alliance", "Horde"):
            faction_inside |= set((d.get("inside") or {}).get(faction) or [])
        return qid in faction_inside or q.get("ti") or (d.get("before") or {}).get(qid) == "part"

    lines, counts, fixes = [], {}, {}

    def flag(kind, text):
        counts[kind] = counts.get(kind, 0) + 1
        return "    [%s] %s" % (kind, text)

    def qname(qid):
        q = Q(qid)
        return '%d "%s"' % (qid, q["n"]) if q else "%d (not in Data.lua)" % qid

    for d in sorted(dungeons, key=lambda d: LEVELS.get(d["id"], (0, 0))):
        lo, hi = LEVELS.get(d["id"], (0, 60))
        lines.append("")
        lines.append("== %s (levels %d-%d)" % (names.get(d["id"], d["id"]), lo, hi))
        for faction in ("Alliance", "Horde"):
            mine = [r for r in roles if r[0] is d and r[1] == faction]
            if not mine:
                continue
            lines.append("  %s" % faction)
            for _, _, role, qid in mine:
                q = Q(qid)
                issues = []
                road = chain(qid, faction)
                if not q:
                    issues.append(flag("missing", "the quest itself isn't in Data.lua"))
                else:
                    if not (q.get("a") or q.get("ia")):
                        issues.append(flag("giver", "no giver and no item that starts it"))
                    if not q.get("t"):
                        issues.append(flag("giver", "no hand-in"))
                    if not can_take(q.get("rm"), faction):
                        issues.append(flag("faction", "the quest itself isn't for %s" % faction))
                for p, depth, any_ in road:
                    pq = Q(p)
                    if not pq:
                        issues.append(flag("missing", "needs %d, which isn't in Data.lua" % p))
                        continue
                    if not can_take(pq.get("rm"), faction):
                        issues.append(flag("faction", "needs %s, not for %s" % (qname(p), faction)))
                    od = dungeon_of.get(p)
                    if pq.get("dq") and od and od != d["id"]:
                        issues.append(flag("dungeon", "needs %s, a quest of %s" % (qname(p), names.get(od, od))))
                    if role == "before" and od == d["id"] and done_inside(d, p):
                        issues.append(flag("inside", "picked up before the run, but needs %s, done inside" % qname(p)))
                    if not (pq.get("a") or pq.get("ia")) or not pq.get("t"):
                        issues.append(flag("giver", "needs %s, which has no %s" % (qname(p), "giver" if not (pq.get("a") or pq.get("ia")) else "hand-in")))
                    if (pq.get("r") or 1) > hi:
                        issues.append(flag("level", "needs %s at level %d, past the dungeon's %d" % (qname(p), pq.get("r") or 1, hi)))
                # Wowhead's series: the quest just before this one (and before each on the road).
                for x in [qid] + [p for p, _, _ in road]:
                    xq = Q(x)
                    s = series.get(x)
                    if xq is None:
                        continue
                    pre = set(xq.get("pre") or [])
                    if s and str(x) not in checked:
                        if not (set(s) & pre):
                            issues.append(flag("series", "Wowhead's series has %s before %s; ours: %s" % (
                                " or ".join(qname(y) for y in s), qname(x), ", ".join(qname(y) for y in sorted(pre)) or "nothing")))
                            fixes[x] = {"name": xq["n"], "pre": s, "ours": sorted(pre)}
                    elif x >= FIRST_NEW and not pre and s is None:
                        issues.append(flag("unchecked", "%s: one of Forever's own, no prerequisite, series not read" % qname(x)))
                road_text = " -> ".join(qname(p) for p, _, _ in road)
                lines.append("    %-6s %s%s" % (role, qname(qid), ("   needs: " + road_text) if road else ""))
                lines.extend(issues)

    head = ["Dungeon quest audit (audit_dungeons.py): every dungeon quest and all it needs first.",
            "Roles: before = picked up before the run; after = offered once something inside is done;",
            "inside = started by an item found inside; follow = what one started inside leads to.",
            "Wowhead series read for %d of %d quests in scope." % (len(series), len(scope)),
            "Issues: " + (", ".join("%s %d" % kv for kv in sorted(counts.items())) or "none")]
    with open(REPORT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(head + lines) + "\n")
    if fetch or fixes:
        with open(SERIES_OUT, "w", encoding="utf-8", newline="\n") as f:
            json.dump({str(k): v for k, v in sorted(fixes.items())}, f, indent=1)
    print("\n".join(head))
    print("wrote", REPORT)


if __name__ == "__main__":
    main()
