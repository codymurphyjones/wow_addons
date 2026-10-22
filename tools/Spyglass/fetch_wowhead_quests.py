"""Builds the quest plugin's own quest data from Wowhead's WoW Forever database, so it
needs neither Questie nor QuestieDB: SpyglassPluginQuests/Data/QuestDB.lua.

Walks the quest list one required level at a time (each page gives every quest's
level, side, class, zone and item rewards), then reads every quest's page: who starts
and ends it and where they stand, the chain in order, the creatures it involves, its
objective, and every area it takes you to (so a quest filed under a zone that sends
you into a dungeon is still listed in that dungeon's journal Quests tab).

The data is kept as small as the plugin allows: only quests that reward items, that
are in or take you to a dungeon or raid, and the chain steps before them; each NPC
keeps one spot per area.

Every answer is cached in tools/Spyglass/.wowhead_cache (paced, retried), so a rerun costs
nothing and an interrupted run carries on where it stopped.

    python tools/Spyglass/fetch_wowhead_quests.py                 # everything (slow the first time)
    python tools/Spyglass/fetch_wowhead_quests.py --only 6571,2841,1249
"""
import argparse
import datetime
import html
import json
import os
import re
import sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "_shared"))
import fetcher as fetching  # noqa: E402  (paced, cached; pages from a real browser: Wowhead refuses curl)
from luawrite import lua_val  # noqa: E402  (strings: newlines escaped, CRs dropped; floats to 1 place)
from wowhead import balanced, js_literal  # noqa: E402

ADDON = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "addons", "Spyglass")  # tools/Spyglass/ builds addons/Spyglass/
QUEST_DATA = os.path.join(ADDON, "..", "SpyglassPluginQuests", "Data")
OUT = os.path.join(QUEST_DATA, "QuestDB.lua")
REPORT = os.path.join(QUEST_DATA, "questdb_report.txt")
CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".wowhead_cache")
BASE = "https://www.wowhead.com/forever/"
PACE = 3.0  # seconds between requests: faster runs get refused (HTTP 403) after a hundred or so
MAX_LEVEL = 60
SPLIT_AT = 950

# Wowhead's quest category2: 2 dungeons, 3 raids.
INSTANCE_CATEGORIES = {2, 3}

# Race masks as the plugin tests them (Quests.lua): bit raceID - 1, and Forever's
# Skyborne at 2^32 (Alliance) and 2^33 (Horde).
RACE_IDS = {"Human": 1, "Orc": 2, "Dwarf": 3, "Night Elf": 4, "Undead": 5, "Tauren": 6, "Gnome": 7, "Troll": 8}
ALLIANCE = sum(2 ** (r - 1) for r in (1, 3, 4, 7)) + 2 ** 32
HORDE = sum(2 ** (r - 1) for r in (2, 5, 6, 8)) + 2 ** 33
SIDE_MASK = {1: ALLIANCE, 2: HORDE}


def Fetcher(refresh=False):
    """The paced, cached fetcher (fetcher.py) on this tool's cache; fetch_zone_art.py uses it too."""
    return fetching.Fetcher(CACHE, refresh=refresh, pace=PACE)


# ---------------------------------------------------------------------------
# Reading Wowhead's pages
# ---------------------------------------------------------------------------

def quest_list(text):
    i = text.find("new Listview({template: 'quest'")
    if i < 0:
        return []
    j = text.index("data:", i) + len("data:")
    while text[j] == " ":
        j += 1
    return js_literal(balanced(text, j))


def person(markup, label):
    """Start/End from the infobox markup: (kind, id, name) or None."""
    m = re.search(label + r": \[url=\\?/forever\\?/(npc|object|item)=(\d+)[^\]]*\]([^\[]*)\[", markup)
    if not m:
        return None
    return m.group(1), int(m.group(2)), html.unescape(m.group(3))


def quest_page(text):
    if not text or "new Mapper(" not in text and "WH.markup.printHtml" not in text:
        return None
    out = {}
    m = re.search(r'WH\.markup\.printHtml\("(\[ul\].*?)"', text)
    markup = m.group(1) if m else ""
    out["start"] = person(markup, "Start")
    out["end"] = person(markup, "End")
    races = re.search(r"Races?: (.*?)\[\\?/li\]", markup)
    if races:
        plain = re.sub(r"\[[^\]]*\]", "", races.group(1))
        out["races"] = [n.strip() for n in re.split(r",| and ", plain) if n.strip() in RACE_IDS]

    # The chain, in order: each row one step (several quests when it branches);
    # the page's own quest is the row without a link.
    series = []
    j = text.find('<table class="series">')
    if j >= 0:
        table = text[j:text.find("</table>", j)]
        for row in re.findall(r"<tr>(.*?)</tr>", table, re.S):
            ids = [int(x) for x in re.findall(r"/forever/quest=(\d+)", row)]
            series.append(ids or ["self"])
    out["series"] = series

    # Mapper: where its starter and ender stand, and the creatures it involves.
    out["points"], out["npcs"], out["areas"] = {}, [], set()
    k = text.find("new Mapper(")
    if k >= 0:
        try:
            mapper = js_literal(balanced(text, k + len("new Mapper(")))
        except (ValueError, json.JSONDecodeError):
            mapper = {}
        for area, zone in (mapper.get("objectives") or {}).items():
            for level in zone.get("levels") or []:
                for p in level:
                    kind = p.get("point")
                    # Every area the quest takes you to: where it starts and
                    # ends, and where what it asks for is found.
                    out["areas"].add(int(area))
                    if kind in ("start", "end"):
                        point = out["points"].setdefault(kind, {"id": p.get("id"), "spawns": {}})
                        coords = p.get("coords") or ([p["coord"]] if p.get("coord") else [])
                        point["spawns"].setdefault(int(area), []).extend(c for c in coords if c)
                        ra, rh = p.get("reactalliance"), p.get("reacthorde")
                        point["react"] = "A" if ra == 1 and rh != 1 else "H" if rh == 1 and ra != 1 else None
                    elif kind in ("requirement", "sourcerequirement") and p.get("type") == 1 and p.get("id"):
                        if p["id"] not in out["npcs"]:
                            out["npcs"].append(p["id"])

    h = text.find('<h1 class="heading-size-1">')
    if h >= 0:
        body = text[text.find("</h1>", h) + 5:]
        body = re.split(r"<table|<h2|<div", body, 1)[0]
        out["objective"] = " ".join(html.unescape(re.sub(r"<[^>]+>", "", body)).split()) or None
    return out


# ---------------------------------------------------------------------------
# The run
# ---------------------------------------------------------------------------

def gear_items():
    """Item IDs that are weapons or armor, from the item data SpyGlass has."""
    gear = set()
    for name in ("harvest.json", "wowhead.json"):
        try:
            with open(os.path.join(ADDON, "Data", name), encoding="utf-8") as f:
                for item_id, row in json.load(f).get("items", {}).items():
                    if row.get("classID") in (2, 4):
                        gear.add(int(item_id))
        except (OSError, ValueError):
            pass
    return gear


def walk_lists(fetcher):
    quests = {}

    def page(path):
        rows = quest_list(fetcher.get(BASE + path) or "")
        for r in rows:
            quests.setdefault(r["id"], r)
        return len(rows)

    for level in list(range(0, MAX_LEVEL + 1)) + [None]:
        band = ("min-req-level:%d" % (MAX_LEVEL + 1)) if level is None else \
            ("min-req-level:%d/max-req-level:%d" % (level, level))
        if page("quests/" + band) >= SPLIT_AT:
            for side in ("alliance", "horde"):
                page("quests/%s/side:%s" % (band, side))
    print("quest lists: %d quests (%d requests)" % (len(quests), fetcher.requests))
    return quests


def reward_ids(row):
    return [r[0] for r in (row.get("itemrewards") or []) + (row.get("itemchoices") or []) if r]


def Needed(row):
    """A quest SpyGlass uses: it rewards an item, or belongs to a dungeon or raid."""
    return bool(reward_ids(row)) or row.get("category2") in INSTANCE_CATEGORIES


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--only", help="comma-separated quest IDs (their pages only, for testing)")
    ap.add_argument("--refresh", action="store_true", help="ignore the cache")
    args = ap.parse_args(argv)
    fetcher = Fetcher(refresh=args.refresh)

    lists = walk_lists(fetcher)
    gear = gear_items()
    if args.only:
        wanted = [int(x) for x in args.only.split(",") if x.strip()]
    else:
        # Every quest's page: a quest filed under a zone can still take you into a
        # dungeon (its objectives, giver or ender inside), which only the page says.
        # What isn't needed is dropped below, so the shipped data stays small.
        wanted = sorted(lists)

    pages, failed = {}, []
    queue, seen = list(wanted), set()
    while queue:
        qid = queue.pop(0)
        if qid in seen:
            continue
        seen.add(qid)
        page = quest_page(fetcher.get("%squest=%d" % (BASE, qid)))
        if not page:
            failed.append(qid)
            continue
        pages[qid] = page
        # Every step of the chain gets its own page (who gives it, where).
        if not args.only:
            for step in page["series"]:
                queue.extend(sid for sid in step if sid != "self" and sid not in seen)
        if len(pages) % 200 == 0:
            print("  %d quest pages, %d requests" % (len(pages), fetcher.requests))

    # Kept: quests that reward items, dungeon and raid quests, and every step
    # before them in their chains. Every other quest is left out (SpyGlass never
    # shows it), and each giver or ender keeps one spot per area.
    def prev_of(qid):
        series = pages[qid]["series"] if qid in pages else []
        for i, step in enumerate(series):
            if "self" in step and i > 0:
                return [s for s in series[i - 1] if s != "self"]
        return []

    # Dungeon and raid areas: what Wowhead files instance quests under. A quest
    # belongs to one when it's filed there or takes you there.
    instance_areas = {r["category"] for r in lists.values()
                      if r.get("category2") in INSTANCE_CATEGORIES and (r.get("category") or 0) > 0}

    def instances_of(qid):
        row = lists.get(qid, {})
        areas = set(pages[qid]["areas"]) if qid in pages else set()
        if (row.get("category") or 0) > 0:
            areas.add(row["category"])
        return sorted(areas & instance_areas)

    keep, todo = set(), [q for q in set(lists) | set(pages)
                         if Needed(lists.get(q, {})) or instances_of(q)]
    if args.only:
        todo = [q for q in todo if q in pages]
    while todo:
        qid = todo.pop()
        if qid not in keep:
            keep.add(qid)
            todo.extend(prev_of(qid))

    # Assemble in the shape Quests.lua, Location.lua and Dungeons.lua read.
    quests, npcs, objects, dungeons, dungeon_npcs = {}, {}, {}, {}, {}
    for qid in sorted(keep):
        row, page = lists.get(qid, {}), pages.get(qid)
        q = {"name": row.get("name"), "level": row.get("level"), "req": row.get("reqlevel") or None,
             "classes": row.get("reqclass") or None,
             "zone": row.get("category") if (row.get("category") or 0) > 0 else None,
             "rewards": reward_ids(row) or None,
             "prev": [p for p in prev_of(qid) if p in keep] or None}
        races = SIDE_MASK.get(row.get("side"))
        if page:
            if page.get("races"):
                races = sum(2 ** (RACE_IDS[n] - 1) for n in page["races"])
            q["text"] = page.get("objective")
            for key, field in (("start", "giver"), ("end", "ender")):
                who = page.get(key)
                if who and who[0] in ("npc", "object"):
                    q[field] = [who[0], who[1]]
                    point = page["points"].get(key) or {}
                    table = npcs if who[0] == "npc" else objects
                    entry = table.setdefault(who[1], {"name": who[2]})
                    # One spot per area: enough to find them.
                    for area, coords in (point.get("spawns") or {}).items():
                        if coords and area not in entry.setdefault("spawns", {}):
                            entry["spawns"][area] = [list(coords[0])]
                    if who[0] == "npc" and point.get("react"):
                        entry["react"] = point["react"]
        q["races"] = races
        # Listed under every dungeon or raid it's in or takes you to, with the
        # creatures it involves (the journal's per-boss filter).
        for area in instances_of(qid):
            dungeons.setdefault(area, []).append(qid)
            if page and page["npcs"]:
                dungeon_npcs[qid] = page["npcs"]
        quests[qid] = {k: v for k, v in q.items() if v not in (None, "", [])}

    os.makedirs(QUEST_DATA, exist_ok=True)
    lines = [
        "-- GENERATED by tools/Spyglass/fetch_wowhead_quests.py from Wowhead's WoW Forever",
        "-- database. Do not edit; run the tool again. %d quests, %d NPCs, %d objects."
        % (len(quests), len(npcs), len(objects)),
        "--   Only quests that reward items, dungeon and raid quests, and the chain steps before them.",
        "--   quests[id] = { name, level, req, races (mask), classes (mask), zone (area ID),",
        "--     prev = { quest IDs before it }, text = objective, giver / ender = { \"npc\" or",
        "--     \"object\", id }, rewards = { item IDs } }",
        "--   npcs / objects[id] = { name, spawns = { [areaID] = { { x, y } } } (0-100), react }",
        "--   dungeons[areaID] = { quest IDs }; dungeonNpcs[questID] = { creature IDs it involves }",
        "local _, ns = ...",
        "ns.QuestDB = {",
        "quests = {",
    ]
    lines += ["[%d] = %s," % (k, lua_val(quests[k])) for k in sorted(quests)]
    lines += ["},", "npcs = {"]
    lines += ["[%d] = %s," % (k, lua_val(npcs[k])) for k in sorted(npcs)]
    lines += ["},", "objects = {"]
    lines += ["[%d] = %s," % (k, lua_val(objects[k])) for k in sorted(objects)]
    lines += ["},", "areaMap = {},", "dungeons = {"]
    lines += ["[%d] = %s," % (k, lua_val(dungeons[k])) for k in sorted(dungeons)]
    lines += ["},", "dungeonNpcs = {"]
    lines += ["[%d] = %s," % (k, lua_val(dungeon_npcs[k])) for k in sorted(dungeon_npcs)]
    lines += ["},", "}", ""]
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))

    gear_quests = sum(1 for q in quests.values() if any(i in gear for i in q.get("rewards", [])))
    with open(REPORT, "w", encoding="utf-8", newline="\n") as f:
        f.write("Wowhead quest data (%s), %s\n" % (BASE, datetime.date.today().isoformat()))
        f.write("quests listed: %d\nquests written: %d\nquest pages read: %d\n" % (len(lists), len(quests), len(pages)))
        f.write("kept (reward items, dungeon or raid, or a step before one): %d\n" % len(keep))
        f.write("quests rewarding gear: %d\nwith a giver: %d\n"
                % (gear_quests,sum(1 for q in quests.values() if q.get("giver"))))
        f.write("NPCs: %d, objects: %d, instances with quests: %d\n" % (len(npcs), len(objects), len(dungeons)))
        f.write("pages that failed: %s\n" % (", ".join(map(str, failed)) or "none"))
    print("wrote %s: %d quests (%d pages), %d web requests"
          % (os.path.relpath(OUT, ADDON), len(quests), len(pages), fetcher.requests))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
