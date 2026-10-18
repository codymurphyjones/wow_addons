"""Turns a /sg harvest run into SpyGlass's shipped item data.

Reads SpyGlassDevDB from the SavedVariables file(s) WoW writes on /reload or
logout, merges it into Data/harvest.json (earlier runs are kept, newer
answers win), and writes Data/Items.lua from that.

Then the same for the quest plugin: SpyGlassPluginQuestsDevDB (from
SpyglassPluginQuests.lua next to each Spyglass.lua) goes into
SpyglassPluginQuests/Data/harvest.json and Data/Quests.lua, and a gap report
lists the quest gear the Wowhead quest data alone would have missed.

    python tools/Spyglass/build_items.py                # finds WTF/Account/*/SavedVariables/Spyglass.lua
    python tools/Spyglass/build_items.py path/to/Spyglass.lua [...]
    python tools/Spyglass/build_items.py --no-wowhead   # leave out Data/wowhead.json

Items the harvest never saw (or the client keeps encrypted) come from
Data/wowhead.json (tools/Spyglass/fetch_wowhead.py) and are marked src = "wh"; where
Wowhead says they come from goes to SpyglassPluginQuests/Data/SourcesWowhead.lua.
Quests come from Data/wowhead_quests.json (tools/Spyglass/fetch_wowhead_quests.py) and
go to SpyglassPluginQuests/Data/QuestDB.lua.
"""
import glob
import json
import os
import re
import sys

ADDON = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "addons", "Spyglass")  # tools/Spyglass/ builds addons/Spyglass/
DATA = os.path.join(ADDON, "Data")
QUEST_DATA = os.path.join(ADDON, "..", "SpyglassPluginQuests", "Data")
WTF = os.environ.get("WOW_WTF") or r"Z:\Games\World of Warcraft\_classic_beta_\WTF"  # the game's saved variables (read only)

TOKEN = re.compile(r"""
    \s+ | --[^\n]* |
    (?P<str>"(?:\\.|[^"\\])*") |
    (?P<num>-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?) |
    (?P<word>[A-Za-z_]\w*) |
    (?P<sym>[{}\[\]=,;])
""", re.VERBOSE | re.DOTALL)

ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "\n": "\n"}


def unquote(s):
    out, i = [], 1
    while i < len(s) - 1:
        c = s[i]
        if c == "\\":
            nxt = s[i + 1]
            if nxt.isdigit():
                m = re.match(r"\d{1,3}", s[i + 1:])
                out.append(chr(int(m.group())))
                i += 1 + len(m.group())
                continue
            out.append(ESCAPES.get(nxt, nxt))
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def tokens(text):
    pos = 0
    while pos < len(text):
        m = TOKEN.match(text, pos)
        if not m:
            raise ValueError("can't read Lua at offset %d: %r" % (pos, text[pos:pos + 40]))
        pos = m.end()
        kind = m.lastgroup
        if kind:
            yield kind, m.group(kind)


class Parser:
    def __init__(self, text):
        self.toks = list(tokens(text))
        self.i = 0

    def peek(self):
        return self.toks[self.i] if self.i < len(self.toks) else (None, None)

    def take(self, value=None):
        tok = self.peek()
        if value is not None and tok[1] != value:
            raise ValueError("expected %r, got %r" % (value, tok[1]))
        self.i += 1
        return tok

    def value(self):
        kind, v = self.take()
        if kind == "str":
            return unquote(v)
        if kind == "num":
            f = float(v)
            return int(f) if f.is_integer() else f
        if kind == "word":
            return {"true": True, "false": False, "nil": None}[v]
        if v == "{":
            return self.table()
        raise ValueError("unexpected %r" % v)

    def table(self):
        out, n = {}, 0
        while self.peek()[1] != "}":
            if self.peek()[1] == "[":
                self.take("[")
                key = self.value()
                self.take("]")
                self.take("=")
                out[key] = self.value()
            elif self.peek()[0] == "word" and self.toks[self.i + 1][1] == "=":
                key = self.take()[1]
                self.take("=")
                out[key] = self.value()
            else:
                n += 1
                out[n] = self.value()
            if self.peek()[1] in (",", ";"):
                self.take()
        self.take("}")
        return out

    def assignments(self):
        out = {}
        while self.i < len(self.toks):
            name = self.take()[1]
            self.take("=")
            out[name] = self.value()
        return out


def as_list(t):
    """A Lua array (dict with keys 1..n) as a list."""
    if isinstance(t, list):
        return t
    if not isinstance(t, dict):
        return []
    return [t[k] for k in sorted(k for k in t if isinstance(k, int))]


def read_harvest(path, name="SpyGlassDevDB"):
    with open(path, encoding="utf-8", errors="replace") as f:
        db = Parser(f.read()).assignments().get(name)
    return db if isinstance(db, dict) else None


def merge(old, db):
    """Adds one SpyGlassDevDB to the JSON snapshot."""
    items, sources = old.setdefault("items", {}), old.setdefault("sources", {})
    encrypted = set(old.get("encrypted", []))
    for item_id, row in (db.get("items") or {}).items():
        row = dict(row)
        row["effects"] = as_list(row.get("effects"))
        items[str(item_id)] = row
        encrypted.discard(int(item_id))
    for item_id in (db.get("encrypted") or {}):
        if str(item_id) not in items:
            encrypted.add(int(item_id))
    for key, src in (db.get("sources") or {}).items():
        bosses = {}
        for index, boss in (src.get("bosses") or {}).items():
            bosses[str(index)] = {
                "name": boss.get("name"),
                "Alliance": as_list(boss.get("Alliance")),
                "Horde": as_list(boss.get("Horde")),
            }
        entry = {k: v for k, v in src.items() if k != "bosses"}
        entry["bosses"] = bosses
        sources[key] = entry
    old["encrypted"] = sorted(encrypted)
    old["build"] = db.get("build", old.get("build"))
    return old


def lua_str(s):
    s = s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "")
    return '"' + s + '"'


def lua_val(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return lua_str(v)
    if isinstance(v, list):
        return "{ " + ", ".join(lua_val(x) for x in v) + " }"
    if isinstance(v, dict):
        parts = []
        for k in sorted(v):
            key = k if re.match(r"^[A-Za-z_]\w*$", k) else "[" + lua_str(k) + "]"
            parts.append("%s = %s" % (key, lua_val(v[k])))
        return "{ " + ", ".join(parts) + " }"
    raise TypeError(v)


ITEM_FIELDS = [  # harvest key -> Data\Items.lua key
    ("name", "name"), ("quality", "q"), ("itemLevel", "ilvl"), ("reqLevel", "req"),
    ("equipLoc", "loc"), ("classID", "cls"), ("subClassID", "sub"), ("subType", "subType"),
    ("icon", "icon"), ("stats", "stats"), ("classes", "classes"), ("effects", "effects"),
    ("src", "src"),  # "wh": known only from Wowhead (the client keeps it encrypted or never sent it)
]


def write_lua(snap, path, reported=None):
    items = snap.get("items", {})
    lines = [
        "-- Generated by tools/Spyglass/build_items.py from /sg harvest runs; do not edit by hand.",
        "-- Client build %s. %d items." % (snap.get("build", "?"), len(items)),
        "local _, ns = ...",
        "ns.ItemData = {",
        "items = {",
    ]
    for item_id in sorted(items, key=int):
        row = items[item_id]
        fields = []
        for src, dst in ITEM_FIELDS:
            v = row.get(src)
            if v is None or v == [] or v == {}:
                continue
            fields.append("%s = %s" % (dst, lua_val(v)))
        lines.append("[%s] = { %s }," % (item_id, ", ".join(fields)))
    lines += ["},", "sources = {"]
    for key in sorted(snap.get("sources", {})):
        bosses = snap["sources"][key]["bosses"]
        out = []
        for index in sorted(bosses, key=int):
            a = [i for i in bosses[index]["Alliance"] if str(i) in items]
            h = [i for i in bosses[index]["Horde"] if str(i) in items]
            both = [i for i in dict.fromkeys(a) if i in h]
            only_a = [i for i in dict.fromkeys(a) if i not in h]
            only_h = [i for i in dict.fromkeys(h) if i not in a]
            if not (both or only_a or only_h):
                continue
            parts = [str(i) for i in both]
            if only_a:
                parts.append("A = " + lua_val(only_a))
            if only_h:
                parts.append("H = " + lua_val(only_h))
            out.append("[%s] = { %s }" % (index, ", ".join(parts)))
        if out:
            lines.append("[%s] = { %s }," % (lua_str(key), ", ".join(out)))
    lines += ["},", "reported = {"]
    for key in sorted(reported or {}):
        bosses = ", ".join("{ name = %s, items = %s }" % (lua_str(b["name"]), lua_val(b["items"]))
                           for b in reported[key])
        lines.append("[%s] = { %s }," % (lua_str(key), bosses))
    lines += ["},", "}", ""]
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


def load_json(path):
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    return {}


def save_json(snap, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(snap, f, indent=1, sort_keys=True, ensure_ascii=False)


def union(a, b):
    return list(dict.fromkeys(list(a) + list(b)))


def merge_quests(old, db):
    """Adds one SpyGlassPluginQuestsDevDB to the quest JSON snapshot."""
    for key in ("rewards", "itemClass", "quests", "captured"):
        old.setdefault(key, {})
    for quest, items in (db.get("rewards") or {}).items():
        old["rewards"][str(quest)] = union(old["rewards"].get(str(quest), []), as_list(items))
    for item_id, cls in (db.get("itemClass") or {}).items():
        old["itemClass"][str(item_id)] = cls
    for quest, row in (db.get("quests") or {}).items():
        old["quests"][str(quest)] = row
    for quest, row in (db.get("captured") or {}).items():
        prev = old["captured"].get(str(quest), {})
        row = dict(row)
        row["rewards"] = union(prev.get("rewards", []), as_list(row.get("rewards")))
        row["choices"] = union(prev.get("choices", []), as_list(row.get("choices")))
        row["factions"] = sorted(set(prev.get("factions", [])) | set((row.get("factions") or {}).keys()))
        for k in ("name", "level", "giver", "ender"):
            if row.get(k) is None and prev.get(k) is not None:
                row[k] = prev[k]
        old["captured"][str(quest)] = row
    return old


def write_quests_lua(qsnap, items, path):
    """Data/Quests.lua: quests seen in game, and gear rewards the quest data misses."""
    captured, rewards = qsnap.get("captured", {}), qsnap.get("rewards", {})
    item_class = qsnap.get("itemClass", {})
    out_rewards = {}
    gap_class, gap_captured, not_harvested = [], [], set()

    def harvested(item_id):
        if str(item_id) in items:
            return True
        not_harvested.add(item_id)
        return False

    # The quest data lists these rewards, but the game gives an item class that isn't weapon/armor.
    for quest, ids in rewards.items():
        for item_id in ids:
            if harvested(item_id) and item_class.get(str(item_id)) not in (2, 4):
                out_rewards.setdefault(int(quest), []).append(item_id)
                gap_class.append((item_id, quest))
    # Seen in game: every reward, which the quest data may not list. Items not in
    # the item harvest (not gear, or not harvested yet) go in too; the plugin
    # checks they're gear itself.
    for quest, row in captured.items():
        known = set(rewards.get(quest, []))
        for item_id in union(row.get("rewards", []), row.get("choices", [])):
            lst = out_rewards.setdefault(int(quest), [])
            if item_id not in lst:
                lst.append(item_id)
            if harvested(item_id) and item_id not in known:
                gap_captured.append((item_id, quest))

    lines = [
        "-- Generated by tools/Spyglass/build_items.py from /sg harvest runs; do not edit by hand.",
        "-- %d quests seen in game, %d quests with extra rewards." % (len(captured), len(out_rewards)),
        "local _, ns = ...",
        "ns.ShippedQuests = {",
        "quests = {",
    ]
    for quest in sorted(captured, key=int):
        row = captured[quest]
        q = {"name": row.get("name"), "level": row.get("level")}
        g = row.get("giver") or row.get("ender")
        if isinstance(g, dict):
            q["giver"] = {k: g[k] for k in ("kind", "id", "name", "map", "x", "y") if g.get(k) is not None}
        q = {k: v for k, v in q.items() if v is not None}
        lines.append("[%s] = %s," % (quest, lua_val(q)))
    lines += ["},", "rewards = {"]
    for quest in sorted(out_rewards):
        if out_rewards[quest]:
            lines.append("[%d] = %s," % (quest, lua_val(out_rewards[quest])))
    lines += ["},", "}", ""]
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))

    def name(item_id):
        return items.get(str(item_id), {}).get("name", "item %s" % item_id)

    def quest_name(quest):
        row = captured.get(str(quest)) or qsnap.get("quests", {}).get(str(quest)) or {}
        return row.get("name") or "quest %s" % quest

    print("\nGap report")
    print("  %d quest gear rewards under a non-gear item class (now included)" % len(gap_class))
    for item_id, quest in gap_class[:15]:
        print("    %s [%s] - %s [%s]" % (name(item_id), item_id, quest_name(quest), quest))
    new = [q for q, r in captured.items() if r.get("new")]
    print("  %d quests seen in game that the quest data doesn't have" % len(new))
    for quest in sorted(new, key=int)[:15]:
        print("    %s [%s]" % (quest_name(quest), quest))
    print("  %d gear rewards seen in game that the quest data doesn't list for that quest" % len(gap_captured))
    for item_id, quest in gap_captured[:15]:
        print("    %s [%s] - %s [%s]" % (name(item_id), item_id, quest_name(quest), quest))
    print("  %d reward items not in the item harvest (not gear, or not harvested yet: /sg harvest start)"
          % len(not_harvested))


def resolve_web_loot(items):
    """Data/web_loot.json (tools/Spyglass/fetch_web_loot.py) with item names matched
    to harvested item IDs: { instKey: [ { name, items = [ids] } ] }."""
    path = os.path.join(DATA, "web_loot.json")
    if not os.path.exists(path):
        return {}
    web = load_json(path)
    by_name = {}
    for item_id, row in items.items():
        by_name.setdefault((row.get("name") or "").lower(), []).append(int(item_id))
    out = {}
    print("\nReported loot (%s, fetched %s)" % (web.get("source"), web.get("fetched")))
    for key, inst in sorted(web.get("instances", {}).items()):
        bosses, found, missing = [], 0, []
        for boss in inst.get("bosses", []):
            ids = []
            for item in boss["items"]:
                matches = sorted(by_name.get(item["name"].lower(), []))
                # Several items share the name: Forever's own (270000+) first.
                matches.sort(key=lambda i: i < 270000)
                if matches:
                    ids.append(matches[0])
                else:
                    missing.append(item["name"])
            found += len(ids)
            if ids:
                bosses.append({"name": boss["boss"], "items": ids})
        if bosses:
            out[key] = bosses
        if inst.get("bosses"):
            print("  %-18s %d bosses, %d items matched%s" % (key, len(bosses), found,
                  ("; not in the item harvest: " + ", ".join(missing)) if missing else ""))
    return out


def merge_wowhead(snap):
    """Data/wowhead.json (tools/Spyglass/fetch_wowhead.py): the items the harvest lacks,
    added to a copy of the harvest's items (the harvest's own answers always
    win; harvest.json itself stays the game's answers only). Returns the
    merged items, the encrypted IDs still unexplained, and Wowhead's rows."""
    items = snap.get("items", {})
    encrypted = list(snap.get("encrypted", []))
    path = os.path.join(DATA, "wowhead.json")
    if not os.path.exists(path):
        return items, encrypted, {}
    web = load_json(path).get("items", {})
    # Subclass names as the client spells them ("Leather", not "Leather Armor").
    names = {}
    for row in items.values():
        key = (row.get("classID"), row.get("subClassID"))
        if row.get("subType"):
            names.setdefault(key, {}).setdefault(row["subType"], 0)
            names[key][row["subType"]] += 1
    sub_type = {k: max(v, key=v.get) for k, v in names.items()}
    merged = dict(items)
    added = 0
    for item_id, row in web.items():
        if item_id in merged:
            continue
        row = {k: v for k, v in row.items() if k != "source"}
        row["subType"] = sub_type.get((row.get("classID"), row.get("subClassID")))
        row["src"] = "wh"
        merged[item_id] = row
        added += 1
    known = set(merged)
    encrypted = [i for i in encrypted if str(i) not in known]
    print("Wowhead (fetched %s): %d items, %d of them added to the harvest's %d"
          % (load_json(path).get("fetched"), len(web), added, len(items)))
    return merged, encrypted, web


SOURCE_TEXT = {"quest": "Quest reward.", "vendor": "Sold by a vendor.", "craft": "Crafted.", "world": "World drop."}


def write_wowhead_sources(snap, web, path):
    """SpyglassPluginQuests/Data/SourcesWowhead.lua: where Wowhead says gear
    comes from, for items nothing else explains (not in Data/Sources.lua and
    not an AtlasLoot boss drop). Fills ns.Sources only where it's empty."""
    sources_lua = os.path.join(os.path.dirname(path), "Sources.lua")
    have = set()
    if os.path.exists(sources_lua):
        with open(sources_lua, encoding="utf-8") as f:
            have = {m.group(1) for m in re.finditer(r"^\s*\[(\d+)\] = \{", f.read(), re.M)}
    for src in snap.get("sources", {}).values():
        for boss in src.get("bosses", {}).values():
            have.update(str(i) for i in boss.get("Alliance", []) + boss.get("Horde", []))
    rows = []
    for item_id in sorted(web, key=int):
        row = web[item_id]
        src = row.get("source")
        if item_id in have or not src or (row.get("quality") or 0) < 2:
            continue
        f = {"k": src["kind"], "name": row.get("name"), "q": row.get("quality"),
             "ilvl": row.get("itemLevel"), "req": row.get("reqLevel") or None, "area": src.get("area")}
        if src["kind"] == "world":
            f["s"] = "object" if src.get("object") else ("trash" if src.get("npc") else "world")
            if not src.get("npc") and not src.get("area"):
                f["open"] = True
        f["npc"] = src.get("npc")
        f["quest"] = src.get("quest")
        if src["kind"] == "quest" and src.get("quest"):
            f["t"] = "Reward from the quest '%s'." % src["quest"]
        elif src.get("npc"):
            f["t"] = ("Sold by %s." if src["kind"] == "vendor" else "Drops from %s.") % src["npc"]
        else:
            f["t"] = SOURCE_TEXT[src["kind"]]
        rows.append("    [%s] = %s," % (item_id, lua_val({k: v for k, v in f.items() if v is not None})))
    lines = [
        "-- GENERATED by tools/Spyglass/build_items.py from Wowhead's WoW Forever database",
        "-- (Spyglass/Data/wowhead.json). Do not edit; run the tool again. %d items." % len(rows),
        "-- The same fields as Data\\Sources.lua, plus area = AreaTable ID (named in game);",
        "-- an item Data\\Sources.lua already has keeps its entry.",
        "local _, ns = ...",
        "local items = ns.Sources and ns.Sources.items",
        "if not items then return end",
        "for id, f in pairs({",
    ] + rows + [
        "}) do",
        "    if not items[id] then items[id] = f end",
        "end",
        "",
    ]
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    print("wrote %s: %d items" % (os.path.relpath(path, ADDON), len(rows)))


MAX_DROPPERS = 25  # items dropped by more creatures than this are too common to place a quest
INSTANCE_CATEGORIES = {2, 3}  # Wowhead's quest categories: dungeons, raids


def lua_list(values):
    return "{ " + ", ".join(lua_val(v) for v in values) + " }"


def lua_spawns(spawns):
    """{ [areaID] = { { x, y }, ... } }"""
    return "{ " + ", ".join("[%s] = { %s }" % (area, ", ".join(lua_list(p) for p in points))
                            for area, points in sorted(spawns.items(), key=lambda kv: int(kv[0]))) + " }"


def write_quest_db(path):
    """SpyglassPluginQuests/Data/QuestDB.lua from Data/wowhead_quests.json
    (tools/Spyglass/fetch_wowhead_quests.py): every quest with its giver, ender, chain
    and rewards, where givers stand, and which quests belong to which dungeon
    or raid (worked out here rather than in game)."""
    src = os.path.join(DATA, "wowhead_quests.json")
    if not os.path.exists(src):
        return False
    web = load_json(src)
    quests, npcs, objects = web.get("quests", {}), web.get("npcs", {}), web.get("objects", {})
    items, areas = web.get("items", {}), web.get("areas", {})
    instances = {q["zone"] for q in quests.values() if q.get("category2") in INSTANCE_CATEGORIES and (q.get("zone") or 0) > 0}

    def areas_of(table, eid):
        return (table.get(str(eid)) or {}).get("areas") or []

    # The dungeon index, by the rules the plugin used to apply in game: a
    # quest belongs to an instance when its zone is the instance, or its giver
    # or something it asks for is found only there.
    dungeons, dungeon_npcs = {}, {}
    for qid, q in quests.items():
        found, involved = set(), set()

        def only(lst):
            if len(lst) == 1 and isinstance(lst[0], int) and lst[0] > 0:
                found.add(lst[0])

        def npc(nid):
            involved.add(nid)
            only(areas_of(npcs, nid))

        if (q.get("zone") or 0) > 0:
            found.add(q["zone"])
        giver = q.get("giver")
        if giver and giver[0] == "npc":
            only(areas_of(npcs, giver[1]))
        elif giver and giver[0] == "object":
            only(areas_of(objects, giver[1]))
        objectives = q.get("objectives") or {}
        for nid in objectives.get("npc", []):
            npc(nid)
        for oid in objectives.get("object", []):
            only(areas_of(objects, oid))
        for item_id in objectives.get("item", []):
            drops = items.get(str(item_id)) or {}
            if len(drops.get("npc", [])) <= MAX_DROPPERS:
                for nid in drops.get("npc", []):
                    npc(nid)
            if len(drops.get("object", [])) <= MAX_DROPPERS:
                for oid in drops.get("object", []):
                    only(areas_of(objects, oid))
        for area in found & instances:
            dungeons.setdefault(area, []).append(int(qid))
            if involved:
                dungeon_npcs[int(qid)] = sorted(involved)

    # Who's needed in game: givers and enders (with where they stand).
    people = {"npc": set(), "object": set()}
    for q in quests.values():
        for who in (q.get("giver"), q.get("ender")):
            if who and who[0] in people:
                people[who[0]].add(str(who[1]))

    def person(kind, eid, row):
        f = {"name": row.get("name"), "sub": row.get("sub"), "level": row.get("level"), "react": row.get("react")}
        spawns = {}
        for area, points in (row.get("spawns") or {}).items():
            # Inside a dungeon or raid there's no world map position.
            spawns[area] = [[-1, -1]] if int(area) in instances else points
        if not spawns and len(row.get("areas") or []) == 1 and row["areas"][0] in instances:
            spawns[str(row["areas"][0])] = [[-1, -1]]
        parts = ["%s = %s" % (k, lua_val(v)) for k, v in sorted(f.items()) if v is not None]
        if spawns:
            parts.append("spawns = " + lua_spawns(spawns))
        return "[%s] = { %s }," % (eid, ", ".join(parts))

    def step_before(qid, chain):
        qid = int(qid)
        if qid in chain:
            i = chain.index(qid)
            if i > 0:
                return [chain[i - 1]]
        return None

    lines = [
        "-- GENERATED by tools/Spyglass/build_items.py from Wowhead's WoW Forever database",
        "-- (Spyglass/Data/wowhead_quests.json, fetched %s). Do not edit; run the tool again." % web.get("fetched"),
        "-- %d quests, %d givers and enders, %d dungeons and raids." % (len(quests), sum(map(len, people.values())), len(dungeons)),
        "local _, ns = ...",
        "ns.QuestDB = {",
        "quests = {",
    ]
    for qid in sorted(quests, key=int):
        q = quests[qid]
        f = {"name": q.get("name"), "level": q.get("level"), "req": q.get("req"),
             "races": q.get("races") or None, "classes": q.get("classes") or None,
             "zone": q.get("zone"), "text": q.get("text"), "prev": step_before(qid, q.get("series") or []),
             "rewards": q.get("rewards") or None}
        for key in ("giver", "ender"):
            who = q.get(key)
            if who and who[0] in people:
                f[key] = who
        lines.append("[%s] = %s," % (qid, lua_val({k: v for k, v in f.items() if v is not None})))
    lines += ["},", "npcs = {"]
    lines += [person("npc", eid, npcs[eid]) for eid in sorted(people["npc"], key=int) if eid in npcs]
    lines += ["},", "objects = {"]
    lines += [person("object", eid, objects[eid]) for eid in sorted(people["object"], key=int) if eid in objects]
    lines += ["},", "areaMap = {"]
    lines += ["[%s] = %s," % (a, areas[a]["map"]) for a in sorted(areas, key=int) if areas[a].get("map")]
    lines += ["},", "dungeons = {"]
    lines += ["[%d] = %s," % (a, lua_list(sorted(ids))) for a, ids in sorted(dungeons.items())]
    lines += ["},", "dungeonNpcs = {"]
    lines += ["[%d] = %s," % (q, lua_list(ids)) for q, ids in sorted(dungeon_npcs.items())]
    lines += ["},", "}", ""]
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    print("wrote %s: %d quests, %d npcs, %d objects, %d dungeons and raids (%d KB)"
          % (os.path.relpath(path, ADDON), len(quests), len(people["npc"]), len(people["object"]),
             len(dungeons), os.path.getsize(path) // 1024))
    return True


def main(argv):
    use_wowhead = "--no-wowhead" not in argv
    argv = [a for a in argv if a != "--no-wowhead"]
    paths = argv or glob.glob(os.path.join(WTF, "Account", "*", "SavedVariables", "Spyglass.lua"))
    snap_path = os.path.join(DATA, "harvest.json")
    snap = load_json(snap_path)
    used = 0
    for path in paths:
        db = read_harvest(path)
        if not db:
            print("no harvest in", path)
            continue
        merge(snap, db)
        used += 1
        print("read %s: %d items, %d instances" % (path, len(db.get("items") or {}), len(db.get("sources") or {})))
    items, encrypted, web = merge_wowhead(snap) if use_wowhead else (snap.get("items", {}), snap.get("encrypted", []), {})
    reported = resolve_web_loot(items)
    if used or reported or web:
        if used:
            save_json(snap, snap_path)
        out = dict(snap, items=items, encrypted=encrypted)
        write_lua(out, os.path.join(DATA, "Items.lua"), reported)
        print("wrote Data/Items.lua: %d items, %d instances, %d encrypted left out"
              % (len(items), len(snap.get("sources", {})), len(encrypted)))
        if web and os.path.isdir(QUEST_DATA):
            write_wowhead_sources(snap, web, os.path.join(QUEST_DATA, "SourcesWowhead.lua"))
    quest_db = use_wowhead and os.path.isdir(QUEST_DATA) and write_quest_db(os.path.join(QUEST_DATA, "QuestDB.lua"))

    # The quest plugin's harvest, saved next to each Spyglass.lua.
    qsnap_path = os.path.join(QUEST_DATA, "harvest.json")
    qsnap = load_json(qsnap_path)
    qused = 0
    for path in paths:
        qpath = os.path.join(os.path.dirname(path), "SpyglassPluginQuests.lua")
        db = os.path.exists(qpath) and read_harvest(qpath, "SpyGlassPluginQuestsDevDB")
        if not db:
            continue
        merge_quests(qsnap, db)
        qused += 1
        print("read %s: %d swept reward quests, %d quests seen in game"
              % (qpath, len(db.get("rewards") or {}), len(db.get("captured") or {})))
    if qused and os.path.isdir(os.path.dirname(QUEST_DATA)):
        save_json(qsnap, qsnap_path)
        write_quests_lua(qsnap, snap.get("items", {}), os.path.join(QUEST_DATA, "Quests.lua"))
        print("wrote SpyglassPluginQuests/Data/harvest.json and Data/Quests.lua")

    if not used and not qused and not web and not quest_db:
        print("Nothing to do: run /sg harvest in game (D.DEV_MODE = true), then /reload.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
