"""Builds SpyglassPluginQuests's item source index from GearQuest Forever's
local data files.

GearQuest ships, for each class, a facts table about every item it knows (name,
quality, levels, where it comes from) and per-class ranked picks. Only the facts
are used: SpyGlass ranks items itself, by the StatLedger priorities of whoever is
playing, so nothing here is per class.

Reads (never changes) the GearQuestForever* folders next to SpyGlass:
  GearQuestForever_<CLASS>/Data.*.generated.lua   item facts; picks only for faction
  GearQuestForever/_generated/CraftSkills          profession, skill, reagents
  GearQuestForever/_generated/Data.Coordinates     map spots
  GearQuestForever/_generated/Data.QuestFaction    faction-only quest rewards
  GearQuestForever/_generated/Data.ForeverAudit    items missing on this server

Writes SpyglassPluginQuests/Data/Sources.lua (ns.Sources),
Data/SourcesHarvest.lua (items SpyGlass's item data doesn't have yet, for
/sg harvest) and Data/sources_report.txt.

    python -I Tools/build_sources.py
"""
import glob
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_items import Parser, as_list, lua_val  # noqa: E402

ADDON = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDONS = os.path.dirname(ADDON)
GQ = os.path.join(ADDONS, "GearQuestForever")
GQ_GEN = os.path.join(GQ, "_generated")
OUT = os.path.join(ADDONS, "SpyglassPluginQuests", "Data")
HARVEST = os.path.join(ADDON, "Data", "harvest.json")

# GearQuest sourceType -> (our kind, sub type). Boss drops are AtlasLoot's
# business (the Dungeons and Raids buttons); kept only for items it lacks.
KINDS = {
    "vendor": ("vendor", None),
    "profession": ("craft", None),
    "quest_reward": ("quest", None),
    "seasonal_quest": ("quest", "seasonal"),
    "world_drop": ("world", "world"),
    "rare_npc": ("world", "rare"),
    "raid_trash": ("world", "trash"),
    "object_drop": ("world", "object"),
    "container": ("world", "container"),
    "fishing": ("world", "fishing"),
    "mail": ("world", "mail"),
    "special": ("world", "special"),
    "boss_drop": ("world", "boss"),
}

# Facts fields -> Sources.lua fields.
FACT_FIELDS = [
    ("name", "name"), ("quality", "q"), ("ilvl", "ilvl"), ("reqLevel", "req"),
    ("instructions", "t"), ("zone", "zone"), ("npc", "npc"), ("questName", "quest"),
    ("profession", "prof"), ("zoneOpen", "open"),
]


def table_after(text, name):
    """The Lua table assigned to `name` (e.g. GQ.Data.coordinates), parsed."""
    m = re.search(re.escape(name) + r"\s*=\s*\{", text)
    if not m:
        return None
    start = m.end() - 1
    depth, i, n = 0, start, len(text)
    while i < n:
        c = text[i]
        if c == '"':
            i += 1
            while text[i] != '"':
                i += 2 if text[i] == "\\" else 1
        elif c == "-" and text.startswith("--", i):
            i = text.find("\n", i)
            if i < 0:
                break
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return Parser(text[start:i + 1]).value()
        i += 1
    raise ValueError("unterminated table " + name)


def read(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def class_files():
    for path in sorted(glob.glob(os.path.join(ADDONS, "GearQuestForever_*", "Data.*.generated.lua"))):
        text = read(path)
        names = re.findall(r"^GQ\.Data\.(\w+)\s*=\s*\{", text, re.M)
        facts = [n for n in names if n.endswith("Facts")]
        picks = [n for n in names if not n.endswith("Facts")]
        yield path, text, facts, picks


def richness(row):
    return sum(1 for v in row.values() if v not in (None, "", False))


def levels_from(text):
    m = re.search(r"around level (\d+)-(\d+)", text or "")
    return (int(m.group(1)), int(m.group(2))) if m else None


def num(v):
    return ("%g" % v) if isinstance(v, (int, float)) else str(v)


def compact(row):
    """The row as written to Sources.lua: lists packed into strings, so the
    game holds one string per item instead of dozens of small tables
    (Sources.lua unpacks them only for the item you hover or click)."""
    out = dict(row)
    if out.get("spots"):
        out["spots"] = ";".join("%s,%s,%s,%s" % (num(s["map"]), num(s["x"]), num(s["y"]), (s.get("fac") or "")[:1])
                                for s in out["spots"])
    if out.get("mats"):
        out["mats"] = ";".join("%s,%s,%s" % (num(m[0]), num(m[1] or 1), (m[2] or "").replace(";", ","))
                               for m in out["mats"])
    if out.get("rep"):
        out["rep"] = ";".join("%s:%s" % (r[0], r[1]) for r in out["rep"])
    if out.get("lv"):
        out["lv"] = "%d-%d" % tuple(out["lv"])
    return out


def harvest_sources():
    """Item IDs SpyGlass already lists from a dungeon or raid boss."""
    if not os.path.exists(HARVEST):
        return set(), set()
    with open(HARVEST, encoding="utf-8") as f:
        snap = json.load(f)
    covered = set()
    for src in (snap.get("sources") or {}).values():
        for boss in (src.get("bosses") or {}).values():
            covered.update(boss.get("Alliance") or [])
            covered.update(boss.get("Horde") or [])
    return covered, set(int(k) for k in (snap.get("items") or {}))


def main():
    if not os.path.isdir(GQ):
        print("GearQuestForever isn't installed next to SpyGlass.")
        return 1

    # Facts, unioned across every class file (the richest row wins).
    facts, factions, seen_in = {}, {}, {}
    for path, text, fact_names, pick_names in class_files():
        both_sides = ".Horde." not in os.path.basename(path)
        for name in fact_names:
            for item_id, row in (table_after(text, "GQ.Data." + name) or {}).items():
                if isinstance(row, dict) and (item_id not in facts or richness(row) > richness(facts[item_id])):
                    facts[item_id] = row
                seen_in.setdefault(item_id, set()).add(os.path.basename(path))
        if both_sides:
            for name in pick_names:
                for row in as_list(table_after(text, "GQ.Data." + name)):
                    if isinstance(row, dict) and isinstance(row.get(1), int) and isinstance(row.get(7), str):
                        factions.setdefault(row[1], set()).add(row[7])
        print("read %s" % os.path.relpath(path, ADDONS))

    gen = lambda f: read(os.path.join(GQ_GEN, f))  # noqa: E731
    coords = table_after(gen("Data.Coordinates.generated.lua"), "GQ.Data.coordinates") or {}
    quest_faction = table_after(gen("Data.QuestFaction.generated.lua"), "GQ.Data.questFaction") or {}
    audit = table_after(gen("Data.ForeverAudit.generated.lua"), "GQ.Data.foreverAudit") or {}
    crafts = {}
    for m in re.finditer(r"^GQ\.CraftSkills\[(\d+)\]\s*=\s*(\{.*\})\s*$", gen("CraftSkills.generated.lua"), re.M):
        crafts[int(m.group(1))] = Parser(m.group(2)).value()

    covered, harvested = harvest_sources()

    items, counts, skipped = {}, {}, {"missing on this server": 0, "unsourced": 0, "boss drop SpyGlass has": 0, "other": 0}
    for item_id in sorted(facts):
        f = facts[item_id]
        if (audit.get(item_id) or {}).get("status") == "missing":
            skipped["missing on this server"] += 1
            continue
        st = f.get("sourceType")
        if st == "unsourced":
            skipped["unsourced"] += 1
            continue
        if st not in KINDS:
            skipped["other"] += 1
            continue
        if st == "boss_drop" and item_id in covered:
            skipped["boss drop SpyGlass has"] += 1
            continue
        kind, sub = KINDS[st]
        out = {"k": kind}
        if sub:
            out["s"] = sub
        for src, dst in FACT_FIELDS:
            v = f.get(src)
            if v not in (None, "", False):
                out[dst] = v
        lv = levels_from(f.get("instructions"))
        if lv:
            out["lv"] = list(lv)
        rep = [[r.get(1), r.get(2)] for r in as_list(f.get("reqRep")) if isinstance(r, dict)]
        if rep:
            out["rep"] = rep
        craft = crafts.get(item_id)
        if kind == "craft" and craft:
            out["prof"] = craft.get("profession") or out.get("prof")
            if craft.get("skill") is not None:
                out["skill"] = craft["skill"]
            if craft.get("spellId"):
                out["spell"] = craft["spellId"]
            reagents = [[r.get(1), r.get(2), r.get(3)] for r in as_list(craft.get("reagents")) if isinstance(r, dict)]
            if reagents:
                out["mats"] = reagents
        elif kind == "craft":
            m = re.search(r"\((\d+)\)", f.get("instructions") or "")
            if m:
                out["skill"] = int(m.group(1))
        c = coords.get(item_id)
        if isinstance(c, dict):
            spots = []
            for s in as_list(c.get("spots")):
                if isinstance(s, dict) and s.get("mapId"):
                    spot = {"map": s.get("mapId"), "x": s.get("x"), "y": s.get("y")}
                    if s.get("faction") in ("Alliance", "Horde"):
                        spot["fac"] = s["faction"]
                    spots.append(spot)
            if spots:
                out["spots"] = spots
                if c.get("note"):
                    out["note"] = c["note"]
        # Faction: a faction-only quest reward, else every spot on one side
        # (vendors in faction towns), else only ever picked for one side.
        fac = quest_faction.get(item_id) if kind == "quest" else None
        if not fac and out.get("spots"):
            sides = set(s.get("fac") for s in out["spots"])
            if len(sides) == 1 and None not in sides:
                fac = sides.pop()
        if not fac and len(factions.get(item_id, ())) == 1:
            fac = next(iter(factions[item_id]))
        if fac in ("Alliance", "Horde"):
            out["fac"] = fac
        items[item_id] = out
        counts[kind] = counts.get(kind, 0) + 1

    os.makedirs(OUT, exist_ok=True)
    lines = [
        "-- GENERATED by Spyglass/Tools/build_sources.py from GearQuest Forever's item facts.",
        "-- Do not edit; run the tool again. %d items." % len(items),
        "--   k = vendor | craft | quest | world; s = world sub type (rare, boss, trash, object,",
        "--   container, fishing, mail, special, world) or quest \"seasonal\"; t = how to get it;",
        "--   npc, zone, quest (quest name), prof, skill, spell, mats = \"id,count,name;...\",",
        "--   rep = \"faction:standing;...\", lv = \"min-max\" world drop levels, open = no fixed spot,",
        "--   spots = \"uiMapID,x,y,A|H|(both);...\" (x, y 0-100), note = what the spot is,",
        "--   fac = Alliance or Horde only, name/q/ilvl/req = the item before the game answers.",
        "local _, ns = ...",
        "ns.Sources = { items = {",
    ]
    for item_id in sorted(items):
        lines.append("    [%d] = %s," % (item_id, lua_val(compact(items[item_id]))))
    lines.append("} }")
    with open(os.path.join(OUT, "Sources.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")

    missing = sorted(i for i in items if i not in harvested)
    with open(os.path.join(OUT, "SourcesHarvest.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write("-- GENERATED by Spyglass/Tools/build_sources.py: source items SpyGlass's item data\n"
                "-- (Spyglass/Data/Items.lua) doesn't have yet. Dev.lua hands them to /sg harvest.\n"
                "local _, ns = ...\nns.SourcesHarvest = {\n")
        for i in range(0, len(missing), 20):
            f.write("    " + ", ".join(str(x) for x in missing[i:i + 20]) + ",\n")
        f.write("}\n")

    report = ["SpyglassPluginQuests sources, built from GearQuest Forever", ""]
    report += ["%-8s %5d" % (k, counts[k]) for k in sorted(counts)]
    report += ["%-8s %5d" % ("total", len(items)), "", "Left out:"]
    report += ["  %-24s %5d" % (k, v) for k, v in skipped.items()]
    by_sub = {}
    for row in items.values():
        key = row["k"] + (":" + row["s"] if row.get("s") else "")
        by_sub[key] = by_sub.get(key, 0) + 1
    report += ["", "By sub type:"] + ["  %-18s %5d" % (k, by_sub[k]) for k in sorted(by_sub)]
    report += ["", "%d items aren't in SpyGlass's item data yet (Data/SourcesHarvest.lua);" % len(missing),
               "the game supplies their details when the list asks, and /sg harvest bakes them in."]
    with open(os.path.join(OUT, "sources_report.txt"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(report) + "\n")
    print("\n".join(report))
    return 0


if __name__ == "__main__":
    sys.exit(main())
