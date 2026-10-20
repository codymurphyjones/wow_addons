"""Builds SpyGlass's own dungeon and raid loot (addons/Spyglass/Data/Loot.lua), so SpyGlass no longer
needs AtlasLoot installed.

Two sources, merged:
  * AtlasLoot Continued (OkrahTV's AtlasLootClassic, the build with WoW Forever's data), downloaded
    once into tools/Spyglass/.cache/atlasloot/ (from the curseforge-mirror GitHub releases, or a zip
    or unpacked folder you give with --atlasloot). Its data files are only read, inside a locked-down
    Lua sandbox: the instances (name, area ID, level range, raid or dungeon), every boss (name, NPC
    IDs, model, level) and its loot for both factions, and AtlasLoot's class restrictions.
  * Data/harvest.json: what the AtlasLoot you had installed listed in game (the /sg harvest,
    tools/Spyglass/build_items.py). Its instance keys are kept (the journal's art and boss data use
    them), and its loot comes first; AtlasLoot Continued adds what it has on top, and fills in the
    area IDs, NPC IDs, models and levels the harvest never recorded.

Bosses AtlasLoot gives no NPC ID get one from the quest plugin's NPC data
(SpyglassPluginQuests/Data/QuestDB.lua) when exactly one NPC by that name stands in the instance.

    python tools/Spyglass/build_loot.py                      # newest AtlasLoot Continued release
    python tools/Spyglass/build_loot.py --atlasloot path      # a zip, or the unpacked AddOns folder(s)
    python tools/Spyglass/build_loot.py --offline             # only what's cached
"""
import argparse
import glob
import io
import json
import os
import re
import sys
import urllib.request
import zipfile

import lupa

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ADDON = os.path.join(ROOT, "addons", "Spyglass")
DATA = os.path.join(ADDON, "Data")
QUESTDB = os.path.join(ROOT, "addons", "SpyglassPluginQuests", "Data", "QuestDB.lua")
CACHE = os.path.join(HERE, ".cache", "atlasloot")
RELEASES = "https://api.github.com/repos/curseforge-mirror/atlaslootclassic-anniversary/releases?per_page=1"

# AtlasLoot's files that hold what SpyGlass needs (paths inside its AddOns folders).
LOOT_FILES = ["AtlasLootContinued_DungeonsAndRaids/data.lua", "AtlasLootContinued_DungeonsAndRaids/data-forever.lua"]
REQ_FILE = "AtlasLootContinued/Data/Requirements.lua"

PLACEHOLDER_BOSSES = {"coming soon", "loot will be updated asap! data mining is not yet fully possible!"}

# Area IDs AtlasLoot doesn't have yet (its Forever data says "MapID once known"), from WoW Forever's
# own Map table (Map-1.60.1.70450: AreaTableID). Forever's other new places have none there either;
# for those the quest plugin goes by the instance's name.
AREA_IDS = {"CityOfDalaran": 16544, "OnyxiasLairNew": 2159}
CLASSIC_CLASS_BITS = 1 | 2 | 4 | 8 | 16 | 64 | 128 | 256 | 1024  # every class there is on Forever


# ---------------------------------------------------------------------------------------------
# Getting AtlasLoot Continued
# ---------------------------------------------------------------------------------------------

def fetch(offline):
    """The folder holding AtlasLoot's AddOns folders: the cache, refreshed from the newest release."""
    os.makedirs(CACHE, exist_ok=True)
    have = sorted(glob.glob(os.path.join(CACHE, "*", "AtlasLootContinued_DungeonsAndRaids")))
    if offline or os.environ.get("WOW_TOOLS_OFFLINE"):
        if not have:
            raise SystemExit("No AtlasLoot in %s and --offline: run once online, or pass --atlasloot." % CACHE)
        return os.path.dirname(have[-1])
    with urllib.request.urlopen(urllib.request.Request(RELEASES, headers={"User-Agent": "wow-addons-tools"}), timeout=60) as r:
        release = json.load(r)[0]
    asset = next(a for a in release["assets"] if a["name"].endswith("-classic.zip"))
    folder = os.path.join(CACHE, os.path.splitext(asset["name"])[0])
    if not os.path.isdir(os.path.join(folder, "AtlasLootContinued_DungeonsAndRaids")):
        print("downloading", asset["name"])
        with urllib.request.urlopen(asset["browser_download_url"], timeout=300) as r:
            unpack(io.BytesIO(r.read()), folder)
    return folder


def unpack(source, folder):
    """Unpacks only AtlasLoot's .lua and .toc files (nothing outside the folder)."""
    with zipfile.ZipFile(source) as z:
        for name in z.namelist():
            if name.endswith("/") or not name.lower().endswith((".lua", ".toc")):
                continue
            dest = os.path.normpath(os.path.join(folder, name))
            if not dest.startswith(os.path.normpath(folder) + os.sep):
                continue
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with open(dest, "wb") as f:
                f.write(z.read(name))


def resolve(arg):
    if arg.lower().endswith(".zip"):
        folder = os.path.join(CACHE, os.path.splitext(os.path.basename(arg))[0])
        unpack(arg, folder)
        return folder
    return arg


# ---------------------------------------------------------------------------------------------
# Reading AtlasLoot's data files in a sandbox
# ---------------------------------------------------------------------------------------------

SANDBOX = r"""
python = nil; os = nil; io = nil; require = nil; dofile = nil; loadfile = nil; package = nil; debug = nil
load = nil; loadstring = nil; collectgarbage = nil
CAPTURE = {}
function getfenv() return _G end
FACTION_HORDE, FACTION_ALLIANCE = "Horde", "Alliance"
ATLASLOOT_IT_HORDE, ATLASLOOT_IT_ALLIANCE = 901, 902
setmetatable(_G, { __index = function(_, k)
    if type(k) == "string" and k:match("^ATLASLOOT_") then return { 0, 0, 0, 1 } end
end })
function UnitFactionGroup() return "Horde" end
C_Map = { GetAreaInfo = function(id) return "Area" .. tostring(id) end }
local CLASSIC, BC, WRATH, FOREVER = 1, 2, 3, 16
-- The game these files are read for: Classic content, WoW Forever's own version.
local function On(v) return v == CLASSIC or v == FOREVER end
AtlasLoot = { CLASSIC_VERSION_NUM = CLASSIC, BC_VERSION_NUM = BC, WRATH_VERSION_NUM = WRATH,
    FOREVER_VERSION_NUM = FOREVER, IS_SOD = false }
local passthrough = setmetatable({}, { __index = function(_, k) return k end })
AtlasLoot.Locales, AtlasLoot.IngameLocales = passthrough, passthrough
function AtlasLoot:GameVersion_GE(v, ...)
    if select("#", ...) == 0 then return On(v) end
    local a, b = ...
    if On(v) then return a else return b end
end
function AtlasLoot:GameVersion_LT(v, ...)
    if select("#", ...) == 0 then return not On(v) end
    local a, b = ...
    if On(v) then return b else return a end
end
function AtlasLoot.ReturnForGameVersion(classic) return classic end
local methods = {}
function methods:AddDifficulty(name) local d = rawget(self, "_diff"); d[#d + 1] = name; return #d end
function methods:AddItemTableType(name) local t = rawget(self, "_itt"); t[#t + 1] = name; return #t end
function methods:AddExtraItemTableType() return 1 end
function methods:AddContentType(name) local c = rawget(self, "_content"); c[#c + 1] = name; return #c end
AtlasLoot.ItemDB = { Add = function(_, name, _, version)
    local m = { _diff = {}, _itt = {}, _content = {}, _entries = {}, _order = {}, _version = version }
    setmetatable(m, { __index = methods, __newindex = function(t, k, v)
        rawget(t, "_entries")[k] = v
        local order = rawget(t, "_order"); order[#order + 1] = k
    end })
    CAPTURE[#CAPTURE + 1] = m
    return m
end }
"""


def lua_list(t):
    out, i = [], 1
    while t is not None and t[i] is not None:
        out.append(t[i])
        i += 1
    return out


def entry_items(e, faction):
    """The item an AtlasLoot loot entry ({ slot, itemID, ..., [901] = Horde, [902] = Alliance }) is
    for that faction, or None (headers, icons, placeholders)."""
    if not hasattr(e, "keys") and not hasattr(e, "items"):
        return None
    horde, alliance = e[901], e[902]
    value = e[2]
    if horde is True and faction != "Horde" or alliance is True and faction != "Alliance":
        return None
    if faction == "Horde" and isinstance(horde, (int, float)) and not isinstance(horde, bool):
        value = horde
    elif faction == "Alliance" and isinstance(alliance, (int, float)) and not isinstance(alliance, bool):
        value = alliance
    if isinstance(value, str):
        m = re.match(r"^i(\d+)", value)
        value = int(m.group(1)) if m else None
    if isinstance(value, (int, float)) and not isinstance(value, bool) and value > 0:
        return int(value)
    return None


def read_atlasloot(folder):
    """AtlasLoot's instances, in the order its files list them:
    [{ key, file, name, areaID, raid, minLevel, maxLevel, bosses: [{ name, npcIDs, displayID, level,
       placeholder, A: [ids], H: [ids] }] }]"""
    L = lupa.LuaRuntime(register_eval=False, register_builtins=False, unpack_returned_tuples=True)
    L.execute(SANDBOX)
    for rel in LOOT_FILES:
        path = os.path.join(folder, rel)
        code = open(path, encoding="utf-8").read()
        L.execute(code, os.path.basename(os.path.dirname(path)))
    out = []
    for module in lua_list(L.globals().CAPTURE):
        diffs = lua_list(module._diff)
        content = lua_list(module._content)
        itt = lua_list(module._itt)
        for key in lua_list(module._order):
            inst = module._entries[key]
            if inst is None or inst["items"] is None:
                continue
            ctype = inst["ContentType"]
            ctype_name = content[int(ctype) - 1] if isinstance(ctype, (int, float)) and 0 < ctype <= len(content) else ""
            rng = lua_list(inst["LevelRange"]) if inst["LevelRange"] is not None else []
            entry = {
                "key": key, "module": module._version, "name": strip(inst["name"] or key),
                "areaID": int(inst["MapID"]) if isinstance(inst["MapID"], (int, float)) else None,
                "raid": "raid" in str(ctype_name).lower(),
                "minLevel": int(rng[1]) if len(rng) > 2 else (int(rng[0]) if rng else None),
                "maxLevel": int(rng[2]) if len(rng) > 2 else (int(rng[1]) if len(rng) > 1 else None),
                "bosses": [],
            }
            for boss in lua_list(inst["items"]):
                if not hasattr(boss, "keys") or boss["ExtraList"] or boss["IgnoreAsSource"]:
                    continue
                tt = boss["TableType"]
                if isinstance(tt, (int, float)) and 0 < tt <= len(itt) and itt[int(tt) - 1] == "Set":
                    continue  # tier set browsers, not drops
                b = {"name": strip(boss["name"] or ""), "npcIDs": npc_ids(boss["npcID"]),
                     "displayID": display_id(boss["DisplayIDs"]), "level": level(boss["Level"]),
                     "A": [], "H": []}
                tables = {}
                for k in boss.keys():
                    if isinstance(k, (int, float)) and hasattr(boss[k], "keys"):
                        tables[int(k)] = boss[k]
                for d, t in tables.items():
                    dname = diffs[d - 1] if 0 < d <= len(diffs) else ""
                    lists = [t]
                    inherit = t["GetItemsFromDiff"]
                    if isinstance(inherit, (int, float)) and int(inherit) in tables:
                        lists.append(tables[int(inherit)])
                    factions = ["Horde"] if dname == "Horde" else (["Alliance"] if dname == "Alliance" else ["Alliance", "Horde"])
                    for lst in lists:
                        for e in lua_list(lst):
                            for faction in factions:
                                item = entry_items(e, faction)
                                if item and item not in b[faction[0]]:
                                    b[faction[0]].append(item)
                b["placeholder"] = not b["A"] and not b["H"] or b["name"].lower() in PLACEHOLDER_BOSSES
                entry["bosses"].append(b)
            out.append(entry)
    return out


def strip(s):
    s = str(s)
    s = re.sub(r"\|T.-\|t", "", s)
    s = re.sub(r"\|c[0-9a-fA-F]{8}", "", s).replace("|r", "")
    return s.strip()


def npc_ids(v):
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        return [int(v)]
    if v is not None and hasattr(v, "keys"):
        return [int(x) for x in lua_list(v) if isinstance(x, (int, float))]
    return []


def display_id(v):
    first = lua_list(v)[0] if v is not None and hasattr(v, "keys") and lua_list(v) else None
    if first is not None and hasattr(first, "keys"):
        first = lua_list(first)[0] if lua_list(first) else None
    return int(first) if isinstance(first, (int, float)) else None


def level(v):
    if v is not None and hasattr(v, "keys"):
        vals = lua_list(v)
        v = vals[1] if len(vals) > 1 else (vals[0] if vals else None)
    return int(v) if isinstance(v, (int, float)) and not isinstance(v, bool) else None


def read_class_masks(folder):
    """{ itemID: class mask } from AtlasLoot's Classic requirements (only items not every class can use)."""
    text = open(os.path.join(folder, REQ_FILE), encoding="utf-8").read()
    start = text.index("ReqData_RAW.CLASSIC = {")
    end = text.index("\n}", start)
    out = {}
    for item, mask in re.findall(r"\[(\d+)\]\s*=\s*\{\s*(\d+)", text[start:end]):
        mask = int(mask)
        if mask & CLASSIC_CLASS_BITS != CLASSIC_CLASS_BITS:
            out[int(item)] = mask
    return out


# ---------------------------------------------------------------------------------------------
# NPC names from the quest plugin
# ---------------------------------------------------------------------------------------------

def read_npcs():
    """{ lower-case name: [(npcID, { areaIDs })] } from SpyglassPluginQuests' QuestDB.lua."""
    if not os.path.exists(QUESTDB):
        return {}
    L = lupa.LuaRuntime(register_eval=False, register_builtins=False)
    L.execute("python = nil; os = nil; io = nil")
    ns = L.table()
    L.execute(open(QUESTDB, encoding="utf-8").read(), "SpyglassPluginQuests", ns)
    db = ns["QuestDB"]
    out = {}
    if db is None or db["npcs"] is None:
        return out
    for npc_id, npc in db["npcs"].items():
        name = npc["name"]
        if not name:
            continue
        areas = set(int(a) for a in (npc["spawns"].keys() if npc["spawns"] is not None else []))
        out.setdefault(str(name).lower(), []).append((int(npc_id), areas))
    return out


# ---------------------------------------------------------------------------------------------
# Merging
# ---------------------------------------------------------------------------------------------

def norm(s):
    s = strip(s).lower()
    s = re.sub(r"^the ", "", s)
    return re.sub(r"[^a-z0-9]", "", s)


def merge(harvest, atlas, npcs):
    """The shipped instance list: the harvest's instances (keys, names, loot), with AtlasLoot
    Continued's on top; AtlasLoot instances the harvest never saw are added."""
    sources = harvest.get("sources", {})
    # AtlasLoot's "...Forever" copies are what Forever has: they win over the Classic originals.
    by_key, by_name = {}, {}
    for inst in atlas:
        base = inst["key"][:-len("Forever")] if inst["key"].endswith("Forever") else inst["key"]
        forever = inst["key"] != base
        for k in (base, inst["key"]):
            if forever or k not in by_key:
                by_key[k] = inst
        n = norm(inst["name"])
        if forever or n not in by_name:
            by_name[n] = inst
    used, out = set(), []
    for key, h in sources.items():
        a = by_key.get(key) or by_name.get(norm(h.get("name", key)))
        if a:
            used.add(id(a))
        out.append(merge_instance(key, h, a, npcs))
    have = {o["key"] for o in out}
    for inst in atlas:
        base = inst["key"][:-len("Forever")] if inst["key"].endswith("Forever") else inst["key"]
        # Already merged, a Classic original whose Forever copy stands in for it, or a key taken.
        if id(inst) in used or by_key.get(base) is not inst or base in have:
            continue
        have.add(base)
        out.append(merge_instance(base, None, inst, npcs))
    return out


def merge_instance(key, h, a, npcs):
    inst = {
        "key": key,
        "name": (h or {}).get("name") or (a and a["name"]) or key,
        "isRaid": bool((h or {}).get("isRaid") or (a and a["raid"])),
        # One of Forever's own places (not a copy of a Classic one).
        "isCustom": bool(h.get("isCustom")) if h else bool(a and a["module"] == 16 and not a["key"].endswith("Forever")),
        "areaID": (a and a["areaID"]) or AREA_IDS.get(key),
        "minLevel": (h or {}).get("minLevel") or (a and a["minLevel"]) or 60,
        "maxLevel": (h or {}).get("maxLevel") or (a and a["maxLevel"]) or 60,
        "world": key.startswith("WorldBoss"),
        "bosses": [],
    }
    a_bosses = list(a["bosses"]) if a else []
    a_by_name = {norm(b["name"]): b for b in a_bosses}
    taken = set()
    hb = (h or {}).get("bosses", {})
    for index in sorted(hb, key=lambda k: int(k)):
        b = hb[index]
        match = a_by_name.get(norm(b.get("name", "")))
        if match:
            taken.add(id(match))
        inst["bosses"].append(merge_boss(b.get("name", "#" + index), b.get("Alliance", []), b.get("Horde", []), match))
    harvested_loot = any(b["A"] or b["H"] for b in inst["bosses"])
    for b in a_bosses:
        if id(b) in taken:
            continue
        # AtlasLoot's "Coming soon" page adds nothing to an instance whose loot the harvest has.
        if b["placeholder"] and (harvested_loot or inst["bosses"]):
            continue
        inst["bosses"].append(merge_boss(b["name"], [], [], b))
    # A harvested "Coming soon" page goes once AtlasLoot has the real bosses.
    if any(not x["placeholder"] for x in inst["bosses"]):
        inst["bosses"] = [x for x in inst["bosses"] if not x["placeholder"] or x["A"] or x["H"]]
    area = inst["areaID"]
    for b in inst["bosses"]:
        if not b["npcIDs"]:
            cands = npcs.get(strip(b["name"]).lower(), [])
            here = [c for c in cands if area and area in c[1]]
            pick = here if len(here) == 1 else (cands if len(cands) == 1 else [])
            if pick:
                b["npcIDs"] = [pick[0][0]]
    return inst


def merge_boss(name, alliance, horde, a):
    A, H = list(alliance), list(horde)
    if a:
        for item in a["A"]:
            if item not in A:
                A.append(item)
        for item in a["H"]:
            if item not in H:
                H.append(item)
    placeholder = strip(name).lower() in PLACEHOLDER_BOSSES or (not A and not H)
    return {"name": strip(name), "npcIDs": list(a["npcIDs"]) if a else [], "displayID": a and a["displayID"],
            "level": a and a["level"], "A": A, "H": H, "placeholder": placeholder}


# ---------------------------------------------------------------------------------------------
# Writing Data/Loot.lua
# ---------------------------------------------------------------------------------------------

def lua_str(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def lua_ids(ids):
    return "{ " + ", ".join(str(i) for i in ids) + " }"


def write(instances, masks, source, path):
    lines = [
        "-- Generated by tools/Spyglass/build_loot.py; do not edit by hand.",
        "-- Dungeon and raid loot from AtlasLoot Continued (%s) merged with SpyGlass's harvest." % source,
        "-- instances = { { key, name, isRaid, isCustom, world, areaID, minLevel, maxLevel,",
        "--     bosses = { { name, npcIDs, displayID, level, comingSoon, items = { both factions },",
        "--                  A = { Alliance only }, H = { Horde only } } } } }",
        "-- classMask = { [itemID] = classes that can use it (AtlasLoot's class bits) }",
        "local _, ns = ...",
        "ns.LootData = {",
        "instances = {",
    ]
    for inst in instances:
        head = ["key = %s" % lua_str(inst["key"]), "name = %s" % lua_str(inst["name"])]
        if inst["isRaid"]:
            head.append("isRaid = true")
        if inst["isCustom"]:
            head.append("isCustom = true")
        if inst["world"]:
            head.append("world = true")
        if inst["areaID"]:
            head.append("areaID = %d" % inst["areaID"])
        head += ["minLevel = %d" % inst["minLevel"], "maxLevel = %d" % inst["maxLevel"]]
        lines.append("{ " + ", ".join(head) + ", bosses = {")
        for b in inst["bosses"]:
            both = [i for i in b["A"] if i in b["H"]]
            only_a = [i for i in b["A"] if i not in b["H"]]
            only_h = [i for i in b["H"] if i not in b["A"]]
            parts = ["name = %s" % lua_str(b["name"])]
            if b["npcIDs"]:
                parts.append("npcIDs = %s" % lua_ids(b["npcIDs"]))
            if b["displayID"]:
                parts.append("displayID = %d" % b["displayID"])
            if b["level"]:
                parts.append("level = %d" % b["level"])
            if b["placeholder"] and not both and not only_a and not only_h:
                parts.append("comingSoon = true")
            parts.append("items = %s" % lua_ids(both))
            if only_a:
                parts.append("A = %s" % lua_ids(only_a))
            if only_h:
                parts.append("H = %s" % lua_ids(only_h))
            lines.append("    { " + ", ".join(parts) + " },")
        lines.append("} },")
    lines += ["},", "classMask = {"]
    for item in sorted(masks):
        lines.append("[%d] = %d," % (item, masks[item]))
    lines += ["},", "}", ""]
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--atlasloot", help="AtlasLoot Continued: a release zip, or the folder holding its AddOns folders")
    ap.add_argument("--offline", action="store_true", help="use the cached AtlasLoot only")
    args = ap.parse_args()
    folder = resolve(args.atlasloot) if args.atlasloot else fetch(args.offline)
    toc = glob.glob(os.path.join(folder, "AtlasLootContinued_DungeonsAndRaids", "*.toc"))
    version = "?"
    for t in toc:
        m = re.search(r"^## Version:\s*(\S+)", open(t, encoding="utf-8").read(), re.M)
        if m:
            version = m.group(1)
    atlas = read_atlasloot(folder)
    masks = read_class_masks(folder)
    harvest = json.load(open(os.path.join(DATA, "harvest.json"), encoding="utf-8"))
    npcs = read_npcs()
    instances = merge(harvest, atlas, npcs)
    instances.sort(key=lambda i: (i["minLevel"], i["maxLevel"], i["name"]))
    out = os.path.join(DATA, "Loot.lua")
    write(instances, masks, "version " + version, out)
    bosses = sum(len(i["bosses"]) for i in instances)
    items = len({x for i in instances for b in i["bosses"] for x in b["A"] + b["H"]})
    no_npc = sum(1 for i in instances for b in i["bosses"] if not b["npcIDs"] and not b["placeholder"])
    no_area = [i["key"] for i in instances if not i["areaID"]]
    print("AtlasLoot Continued %s: %d instances read, %d class restrictions" % (version, len(atlas), len(masks)))
    print("wrote %s: %d instances, %d bosses, %d items" % (out, len(instances), bosses, items))
    print("  bosses without an NPC ID: %d; instances without an area ID: %s" % (no_npc, ", ".join(no_area) or "none"))


if __name__ == "__main__":
    main()
