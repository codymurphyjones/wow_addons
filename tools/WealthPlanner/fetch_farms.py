"""Wealth Planner's farming data from Wowhead's WoW Forever database: which mobs drop,
are skinned for, and which nodes give each farmable trade good (cloth, leather, ore,
herbs, elemental, enchanting dust, meat, fish...), with drop chances and where those
mobs and nodes spawn (uiMapID, 0-100 coords). Writes Data/Farms.lua.

Fetching (paced, cached, retried: tools/_shared/fetcher.py) and Wowhead's JS literals
(tools/_shared/wowhead.py) are the tools' shared modules. Spyglass's page cache is read as an
extra read-only cache when present.

    python tools/WealthPlanner/fetch_farms.py
    python tools/WealthPlanner/fetch_farms.py --only 2589,2318      # a few items (testing)
"""
import argparse
import os
import re
import sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "_shared"))
import fetcher as fetching  # noqa: E402  (paced, cached; pages from a real browser: Wowhead refuses curl)
import wowhead  # noqa: E402
from luawrite import lua_num, lua_str  # noqa: E402  (newlines escaped, CRs dropped)
from wowhead import balanced, js_literal, not_in_game, page_listview  # noqa: E402

ADDON = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "addons", "WealthPlanner")  # tools/WealthPlanner/ builds addons/WealthPlanner/
OUT = os.path.join(ADDON, "Data", "Farms.lua")
CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".wowhead_cache")
# Read-only extra cache (same key scheme): pages Spyglass's tools already fetched.
EXTRA_CACHES = [os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Spyglass", ".wowhead_cache")]
BASE = "https://www.wowhead.com/forever/"
PACE = 2.5  # seconds between requests (Wowhead refuses faster runs after a hundred or so)


def Fetcher(refresh=False):
    """The paced, cached fetcher (fetcher.py) on this tool's cache, Spyglass's read too;
    tools/shared/build_recipes.py uses it for the recipes."""
    return fetching.Fetcher(CACHE, extra_caches=EXTRA_CACHES, refresh=refresh, pace=PACE, skip_empty=True,
                            flush=True)


# ---------------------------------------------------------------------------
# Zones: area IDs, instances, uiMapIDs
# ---------------------------------------------------------------------------

# Classic's world maps (uiMapID) by zone name: the fallback when no Wowhead page
# gave an area's uiMapID (fishing zones, mostly). Forever's own Zephras Isle is 2521.
UIMAP_BY_NAME = {
    "Durotar": 1411, "Mulgore": 1412, "The Barrens": 1413, "Kalimdor": 1414, "Eastern Kingdoms": 1415,
    "Alterac Mountains": 1416, "Arathi Highlands": 1417, "Badlands": 1418, "Blasted Lands": 1419,
    "Tirisfal Glades": 1420, "Silverpine Forest": 1421, "Western Plaguelands": 1422,
    "Eastern Plaguelands": 1423, "Hillsbrad Foothills": 1424, "The Hinterlands": 1425, "Dun Morogh": 1426,
    "Searing Gorge": 1427, "Burning Steppes": 1428, "Elwynn Forest": 1429, "Deadwind Pass": 1430,
    "Duskwood": 1431, "Loch Modan": 1432, "Redridge Mountains": 1433, "Stranglethorn Vale": 1434,
    "Swamp of Sorrows": 1435, "Westfall": 1436, "Wetlands": 1437, "Teldrassil": 1438, "Darkshore": 1439,
    "Ashenvale": 1440, "Thousand Needles": 1441, "Stonetalon Mountains": 1442, "Desolace": 1443,
    "Feralas": 1444, "Dustwallow Marsh": 1445, "Tanaris": 1446, "Azshara": 1447, "Felwood": 1448,
    "Un'Goro Crater": 1449, "Moonglade": 1450, "Silithus": 1451, "Winterspring": 1452,
    "Stormwind City": 1453, "Orgrimmar": 1454, "Ironforge": 1455, "Thunder Bluff": 1456, "Darnassus": 1457,
    "Undercity": 1458, "Alterac Valley": 1459, "Warsong Gulch": 1460, "Arathi Basin": 1461,
    "Zephras Isle": 2521,
}
# Wowhead's zone categories: 2 dungeons, 3 raids, 6 battlegrounds.
INSTANCE_CATEGORIES = {2, 3, 6}


def zones(fetcher):
    """{ area ID: (name, is_instance) } for every zone Wowhead Forever lists."""
    rows = wowhead.zone_rows(fetcher)
    if rows is None:
        raise SystemExit("Wowhead's zone list didn't parse; stopped.")
    out = {}
    for r in rows:
        inst = bool(r.get("instance")) or r.get("category") in INSTANCE_CATEGORIES
        out[r["id"]] = (r.get("name") or "", inst)
    return out


# ---------------------------------------------------------------------------
# Items and their sources
# ---------------------------------------------------------------------------

MAX_ITEMS = 600
MAX_LEVEL = 60
TOP = 12            # sources kept per kind
TOP_CHESTS = 5
MIN_OUTOF = 20      # fewer looted than this: too few to trust the chance
MIN_CHANCE = 0.005
MIN_CHEST_CHANCE = 0.05
# Wowhead's classification: 0 normal, 1 elite, 2 rare elite, 3 boss, 4 rare.
SKIP_CLASSIFICATION = {2, 3, 4}
ELITE = {1, 2}
# Wowhead object types: -3 herb, -4 mining node, -5 locked chest, 3 container.
CHEST_TYPES = {3, -5}


def item_list(fetcher):
    """Trade goods (cloth, leather, metal & stone, herbs, elemental, enchanting, meat,
    which holds the raw fish, parts...): [ row ] sorted by item ID."""
    text = fetcher.get(BASE + "items/trade-goods") or ""
    i = text.find("var listviewitems")
    if i < 0:
        raise SystemExit("Wowhead's trade goods list didn't parse; stopped.")
    rows = js_literal(balanced(text, text.index("[", i)))
    rows = [r for r in rows if not not_in_game(r["id"]) and (r.get("reqlevel") or 0) <= MAX_LEVEL]
    rows.sort(key=lambda r: r["id"])
    return rows[:MAX_ITEMS]


def chance(r):
    count, outof = r.get("count") or 0, r.get("outof") or 0
    if count <= 0 or outof < MIN_OUTOF:
        return 0.0
    return min(1.0, count / outof)


def top(rows, n, min_chance=MIN_CHANCE):
    """The n rows looted most (count), with a usable chance; then by chance."""
    rows = [r for r in rows if chance(r) >= min_chance]
    rows.sort(key=lambda r: (-(r.get("count") or 0), r["id"]))
    rows = rows[:n]
    rows.sort(key=lambda r: (-chance(r), r["id"]))
    return rows


def item_sources(text, zone_info):
    """From an item page: ( [ (kind, id, chance) ], { npc id: row }, { object id: (row, kind) } )."""
    sources, npcs, objects = [], {}, {}

    def outdoors(r):
        locs = [z for z in (r.get("location") or []) if z and z > 0]
        return any(not zone_info.get(z, ("", False))[1] for z in locs)

    for lv_id, kind in (("dropped-by", "npc"), ("skinned-from", "skin")):
        rows = [r for r in page_listview(text, lv_id)
                if r.get("classification") not in SKIP_CLASSIFICATION and outdoors(r)]
        for r in top(rows, TOP):
            sources.append((kind, r["id"], chance(r)))
            npcs.setdefault(r["id"], r)
    for lv_id, okind in (("mined-from-object", "mine"), ("gathered-from-object", "herb")):
        for r in top(page_listview(text, lv_id), TOP):
            k = "mine" if r.get("type") == -4 else "herb" if r.get("type") == -3 else okind
            sources.append(("node", r["id"], chance(r)))
            objects.setdefault(r["id"], (r, k))
    chests = [r for r in page_listview(text, "contained-in-object")
              if r.get("type") in CHEST_TYPES and outdoors(r)]
    for r in top(chests, TOP_CHESTS, MIN_CHEST_CHANCE):
        sources.append(("node", r["id"], chance(r)))
        objects.setdefault(r["id"], (r, "chest"))
    fished = [r for r in page_listview(text, "fished-in") if not zone_info.get(r["id"], ("", False))[1]]
    for r in top(fished, TOP):
        sources.append(("fish", r["id"], chance(r)))  # an area ID for now: uiMapID later
    return sources, npcs, objects


# ---------------------------------------------------------------------------
# Spawns
# ---------------------------------------------------------------------------

MAX_POINTS = 40
GRID = 1.5  # map units (0-100) merged into one point; grows until <= MAX_POINTS remain


def mapper_data(text):
    """{ area ID: [ { count, coords, uiMapId, uiMapName } ] } from an npc or object page."""
    m = re.search(r"g_mapperData = (\{)", text)
    if not m:
        return {}
    try:
        data = js_literal(balanced(text, m.start(1)))
    except ValueError:
        return {}
    return {k: v for k, v in data.items() if k.lstrip("-").isdigit()} if isinstance(data, dict) else {}


def downsample(points):
    """Grid-merge close points (their mean) until no more than MAX_POINTS remain."""
    grid = GRID
    while True:
        cells = {}
        for x, y in points:
            c = cells.setdefault((int(x // grid), int(y // grid)), [0.0, 0.0, 0])
            c[0] += x
            c[1] += y
            c[2] += 1
        if len(cells) <= MAX_POINTS:
            break
        grid *= 1.4
    merged = [(c[0] / c[2], c[1] / c[2], c[2]) for c in cells.values()]
    merged.sort(key=lambda p: (-p[2], round(p[0], 1), round(p[1], 1)))
    return merged


def fmt(v):
    return lua_num(v, 1)


def spawns(text, zone_info, area_map):
    """{ uiMapID: (n, "x,y;x,y;...") } outside instances; learns area -> uiMapID."""
    by_map = {}
    for area, entries in mapper_data(text).items():
        area = int(area)
        name, inst = zone_info.get(area, ("", False))
        if inst:
            continue
        for e in entries or []:
            ui = e.get("uiMapId")
            if ui and area not in area_map:
                area_map[area] = ui
            ui = ui or area_map.get(area) or UIMAP_BY_NAME.get(name)
            if not ui:
                continue
            pts = [(float(c[0]), float(c[1])) for c in e.get("coords") or [] if c and len(c) >= 2]
            if not pts:
                continue
            slot = by_map.setdefault(ui, [0, []])
            slot[0] += max(e.get("count") or 0, len(pts))
            slot[1].extend(pts)
    out = {}
    for ui, (n, pts) in by_map.items():
        out[ui] = (n, ";".join("%s,%s" % (fmt(x), fmt(y)) for x, y, _ in downsample(pts)))
    return out


# The npc infobox's "Worth: ... Average money dropped ... [money=N]" (copper).
WORTH = re.compile(r"Worth:.{0,200}?\[money=(\d+)\]")
SKILL = re.compile(r"Requires (?:Herbalism|Mining|Lockpicking) \((\d+)\)")


# ---------------------------------------------------------------------------
# Lua
# ---------------------------------------------------------------------------

def fmt_chance(c):
    s = ("%.3f" % c).rstrip("0").rstrip(".")
    return s if s not in ("0", "") else "0.001"


def lua_spawns(sp):
    return "{ " + ", ".join("[%d] = { n = %d, %s }" % (ui, n, lua_str(pts))
                            for ui, (n, pts) in sorted(sp.items())) + " }"


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--only", help="comma-separated item IDs (testing)")
    ap.add_argument("--refresh", action="store_true", help="ignore the cache")
    args = ap.parse_args(argv)
    fetcher = Fetcher(refresh=args.refresh)

    zone_info = zones(fetcher)
    rows = item_list(fetcher)
    if args.only:
        want = {int(x) for x in args.only.split(",") if x.strip()}
        rows = [r for r in rows if r["id"] in want]
    print("%d trade goods to read" % len(rows), flush=True)

    items, npc_rows, obj_rows = {}, {}, {}
    no_source = []
    for n, r in enumerate(rows, 1):
        text = fetcher.get("%sitem=%d" % (BASE, r["id"])) or ""
        sources, npcs, objects = item_sources(text, zone_info)
        if sources:
            items[r["id"]] = (r["name"], sources)
            for k, v in npcs.items():
                npc_rows.setdefault(k, v)
            for k, v in objects.items():
                obj_rows.setdefault(k, v)
        else:
            no_source.append(r)
        if n % 50 == 0:
            print("  %d/%d item pages, %d web requests" % (n, len(rows), fetcher.requests), flush=True)
    print("items with sources: %d (none: %d); npcs: %d; objects: %d"
          % (len(items), len(no_source), len(npc_rows), len(obj_rows)), flush=True)

    area_map = {}
    npcs, objects, coin = {}, {}, {}
    for n, nid in enumerate(sorted(npc_rows), 1):
        text = fetcher.get("%snpc=%d" % (BASE, nid)) or ""
        sp = spawns(text, zone_info, area_map)
        if sp:
            npcs[nid] = sp
        m = WORTH.search(text)
        if m and int(m.group(1)) > 0:
            coin[nid] = int(m.group(1))
        if n % 100 == 0:
            print("  %d/%d npc pages, %d web requests" % (n, len(npc_rows), fetcher.requests), flush=True)
    obj_skill = {}
    for n, oid in enumerate(sorted(obj_rows), 1):
        text = fetcher.get("%sobject=%d" % (BASE, oid)) or ""
        sp = spawns(text, zone_info, area_map)
        if sp:
            objects[oid] = sp
        m = SKILL.search(text)
        skill = int(m.group(1)) if m else obj_rows[oid][0].get("skill")
        if skill:
            obj_skill[oid] = int(skill)
        if n % 100 == 0:
            print("  %d/%d object pages, %d web requests" % (n, len(obj_rows), fetcher.requests), flush=True)

    # Sources whose mob or node has no known spawn outside instances are dropped;
    # fishing zones become uiMapIDs.
    def fish_map(area):
        return area_map.get(area) or UIMAP_BY_NAME.get(zone_info.get(area, ("", False))[0])

    out_items, used_npcs, used_objs, missing_fish = {}, set(), set(), set()
    for iid, (name, sources) in sorted(items.items()):
        kept, seen = [], set()
        for kind, sid, c in sources:
            if kind in ("npc", "skin"):
                if sid not in npcs:
                    continue
                used_npcs.add(sid)
            elif kind == "node":
                if sid not in objects:
                    continue
                used_objs.add(sid)
            elif kind == "fish":
                ui = fish_map(sid)
                if not ui:
                    missing_fish.add(zone_info.get(sid, ("area %d" % sid, False))[0])
                    continue
                sid = ui
            if (kind, sid) in seen:
                continue
            seen.add((kind, sid))
            kept.append((kind, sid, c))
        if kept:
            out_items[iid] = (name, kept)

    order = {"npc": 0, "skin": 1, "node": 2, "fish": 3}
    lines = [
        "-- GENERATED by tools/WealthPlanner/fetch_farms.py from Wowhead's WoW Forever database.",
        "-- Do not edit; run the tool again.",
        "--   items[itemID] = { name, { { kind, id, chance } } }: kind \"npc\" (drops) or \"skin\"",
        "--     (skinned from; id = creature), \"node\" (mined / gathered / opened; id = object),",
        "--     \"fish\" (fished in; id = uiMapID); chance per kill / skin / node / catch (0-1)",
        "--   npcs[id] = { name, minLevel, maxLevel, elite (0/1), { [uiMapID] = { n = spawns, \"x,y;...\" } },",
        "--     coin = average money dropped (copper) }",
        "--   objects[id] = { name, \"mine\"|\"herb\"|\"chest\", { [uiMapID] = { n = spawns, \"x,y;...\" } },",
        "--     skill = required gathering skill }",
        "--   Coordinates 0-100; close spawns merged (at most %d points per map); instances left out." % MAX_POINTS,
        "local _, ns = ...",
        "ns.FarmData = {",
        "items = {",
    ]
    for iid, (name, kept) in sorted(out_items.items()):
        kept.sort(key=lambda s: (order[s[0]], -s[2], s[1]))
        src = ", ".join("{ %s, %d, %s }" % (lua_str(k), sid, fmt_chance(c)) for k, sid, c in kept)
        lines.append("[%d] = { %s, { %s } }," % (iid, lua_str(name), src))
    lines += ["},", "npcs = {"]
    for nid in sorted(used_npcs):
        r = npc_rows[nid]
        lo = r.get("minlevel") or 0
        hi = r.get("maxlevel") or lo
        lines.append("[%d] = { %s, %d, %d, %d, %s%s }," % (
            nid, lua_str(r.get("name")), lo, hi, 1 if r.get("classification") in ELITE else 0,
            lua_spawns(npcs[nid]), (", coin = %d" % coin[nid]) if nid in coin else ""))
    lines += ["},", "objects = {"]
    for oid in sorted(used_objs):
        r, kind = obj_rows[oid]
        skill = obj_skill.get(oid)
        lines.append("[%d] = { %s, %s, %s%s }," % (
            oid, lua_str(r.get("name")), lua_str(kind), lua_spawns(objects[oid]),
            (", skill = %d" % skill) if skill else ""))
    lines += ["},", "}", ""]
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))

    zones_used = set()
    for nid in used_npcs:
        zones_used |= set(npcs[nid])
    for oid in used_objs:
        zones_used |= set(objects[oid])
    for _, kept in out_items.values():
        zones_used |= {sid for k, sid, _ in kept if k == "fish"}
    size = os.path.getsize(OUT)
    print("wrote %s: %d items, %d npcs, %d objects, %d zones (uiMapIDs); %.2f MB; %d web requests"
          % (os.path.relpath(OUT, ADDON), len(out_items), len(used_npcs), len(used_objs), len(zones_used),
             size / 1048576.0, fetcher.requests))
    lost = [r for r in rows if r["id"] not in out_items]
    print("items without a farmable source: %d" % len(lost))
    if missing_fish:
        print("fishing zones without a uiMapID: " + ", ".join(sorted(missing_fish)))
    if size > 2 * 1048576:
        print("WARNING: over 2 MB; tighten TOP / MAX_POINTS")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
