"""Fetches every piece of gear in Wowhead's WoW Forever database into
Data/wowhead.json, so SpyGlass knows items the client keeps encrypted (and
any the /sg harvest never saw).

Walks the armor and weapon list pages one required level at a time (each
page carries the stats of every item on it), then asks for single item
pages only for items with no stats of their own (trinkets, relics, procs),
to read their "Equip:" lines. Every answer is cached in tools/Spyglass/.wowhead_cache,
so a rerun costs nothing and an interrupted run carries on where it stopped.

tools/Spyglass/build_items.py then merges the items the harvest doesn't have into
Data/Items.lua (the harvest's own answers always win).

    python tools/Spyglass/fetch_wowhead.py                  # everything (slow the first time: polite pacing)
    python tools/Spyglass/fetch_wowhead.py --only 263411,9624
    python tools/Spyglass/fetch_wowhead.py --refresh        # ignore the cache
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
from wowhead import balanced, js_literal  # noqa: E402

ADDON = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "addons", "Spyglass")  # tools/Spyglass/ builds addons/Spyglass/
OUT = os.path.join(ADDON, "Data", "wowhead.json")
HARVEST = os.path.join(ADDON, "Data", "harvest.json")
DATA_LUA = os.path.join(ADDON, "Data.lua")
CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".wowhead_cache")
BASE = "https://www.wowhead.com/forever/"
PACE = 1.5          # seconds between requests
MAX_LEVEL = 60
SPLIT_AT = 950      # a page this full may be cut short: split it by subclass

SUBCLASS_SLUGS = {
    "armor": ["miscellaneous", "cloth", "leather", "mail", "plate", "shields", "librams", "idols", "totems"],
    "weapons": ["one-handed-axes", "two-handed-axes", "bows", "guns", "one-handed-maces", "two-handed-maces",
                "polearms", "one-handed-swords", "two-handed-swords", "staves", "fist-weapons", "miscellaneous",
                "daggers", "thrown", "crossbows", "wands"],
}

# Wowhead's inventory slot number -> INVTYPE_*
SLOTS = {
    1: "INVTYPE_HEAD", 2: "INVTYPE_NECK", 3: "INVTYPE_SHOULDER", 4: "INVTYPE_BODY", 5: "INVTYPE_CHEST",
    6: "INVTYPE_WAIST", 7: "INVTYPE_LEGS", 8: "INVTYPE_FEET", 9: "INVTYPE_WRIST", 10: "INVTYPE_HAND",
    11: "INVTYPE_FINGER", 12: "INVTYPE_TRINKET", 13: "INVTYPE_WEAPON", 14: "INVTYPE_SHIELD",
    15: "INVTYPE_RANGED", 16: "INVTYPE_CLOAK", 17: "INVTYPE_2HWEAPON", 19: "INVTYPE_TABARD",
    20: "INVTYPE_ROBE", 21: "INVTYPE_WEAPONMAINHAND", 22: "INVTYPE_WEAPONOFFHAND", 23: "INVTYPE_HOLDABLE",
    25: "INVTYPE_THROWN", 26: "INVTYPE_RANGEDRIGHT", 28: "INVTYPE_RELIC",
}

# Wowhead's class bits (1 << classID - 1) -> the tooltip's class names.
CLASS_BITS = [(1, "Warrior"), (2, "Paladin"), (4, "Hunter"), (8, "Rogue"), (16, "Priest"),
              (64, "Shaman"), (128, "Mage"), (256, "Warlock"), (1024, "Druid")]
ALL_CLASSES = sum(b for b, _ in CLASS_BITS)

# Wowhead's jsonequip keys -> SpyGlass (StatLedger) stat keys.
STAT_KEYS = {
    "str": ["STR"], "agi": ["AGI"], "sta": ["STA"], "int": ["INT"], "spi": ["SPI"],
    "armor": ["ARMOR"], "armorbonus": ["ARMOR"], "atkpwr": ["AP"], "mleatkpwr": ["AP"], "rgdatkpwr": ["RAP"],
    "splpwr": ["SP", "HEAL"], "spldmg": ["SP"], "splheal": ["HEAL"],
    "firsplpwr": ["FIRE"], "frosplpwr": ["FROST"], "shasplpwr": ["SHADOW"], "arcsplpwr": ["ARCANE"],
    "natsplpwr": ["NATURE"],
    "critstrkrtng": ["CRIT"], "mlecritstrkrtng": ["CRIT"], "rgdcritstrkrtng": ["CRIT"],
    "splcritstrkrtng": ["SPELLCRIT"],
    "hitrtng": ["HIT"], "mlehitrtng": ["HIT"], "rgdhitrtng": ["HIT"], "splhitrtng": ["HIT"],
    "hastertng": ["HASTE"], "mlehastertng": ["HASTE"],
    "defrtng": ["DEF"], "dodgertng": ["DODGE"], "parryrtng": ["PARRY"], "blockrtng": ["BLOCK"],
    "block": ["BLOCKVALUE"], "manargn": ["MP5"],
    "dps": ["DPS"], "mledps": ["DPS"], "rgddps": ["DPS"],
}
# Keys that add up (spell power counts for both damage and healing, on top of
# either alone; bonus armor on top of base armor). Other keys repeat one value
# (dps / mledps), so the larger counts.
SUMMED = {"splpwr", "spldmg", "splheal", "armor", "armorbonus"}
# Stats that don't make an item "have stats" (every armor piece has armor).
PLAIN = {"ARMOR", "DPS"}

# Wowhead's source codes -> the quest plugin's source kinds.
SOURCE_KINDS = {1: "craft", 2: "world", 4: "quest", 5: "vendor"}

EFFECT_PREFIXES = ("Equip:", "Use:", "Chance on hit:")


# ---------------------------------------------------------------------------
# Reading Wowhead's pages (fetcher.py fetches, wowhead.py reads the JS literals)
# ---------------------------------------------------------------------------

def list_page(text):
    """(listview rows by id, gatherer entries by id) from an items list page."""
    rows, gatherer = {}, {}
    i = text.find("var listviewitems = ")
    if i >= 0:
        for row in js_literal(balanced(text, i + len("var listviewitems = "))):
            rows.setdefault(row["id"], row)
    for m in re.finditer(r"WH\.Gatherer\.addData\(3,\s*\d+,\s*", text):
        for item_id, entry in js_literal(balanced(text, m.end())).items():
            gatherer.setdefault(int(item_id), entry)
    return rows, gatherer


def tooltip_lines(tooltip):
    text = re.sub(r"<br\s*/?>|</tr>|</div>|</table>", "\n", tooltip)
    text = html.unescape(re.sub(r"<[^>]+>", "", text))
    return [" ".join(line.split()) for line in text.split("\n") if line.strip()]


def item_xml(text):
    """name/json/jsonEquip/tooltip lines from an item=<id>&xml answer."""
    def cdata(tag):
        m = re.search(r"<%s><!\[CDATA\[(.*?)\]\]></%s>" % (tag, tag), text, re.S)
        return m.group(1) if m else None
    if not text or "<error>" in text:
        return None
    out = {}
    for tag in ("json", "jsonEquip"):
        raw = cdata(tag)
        out[tag] = js_literal("{" + raw + "}") if raw else {}
    out["lines"] = tooltip_lines(cdata("htmlTooltip") or "")
    icon = re.search(r"<icon[^>]*>([^<]+)</icon>", text)
    out["icon"] = icon.group(1) if icon else None
    return out


# ---------------------------------------------------------------------------
# Stats: Wowhead's keys plus SpyGlass's own "Equip:" patterns (Data.lua)
# ---------------------------------------------------------------------------

def lua_pattern_to_regex(p):
    out, i = [], 0
    while i < len(p):
        c = p[i]
        if c == "%" and i + 1 < len(p):
            n = p[i + 1]
            out.append({"d": r"\d", "a": "[A-Za-z]", "s": r"\s", "w": r"\w"}.get(n, re.escape(n)))
            i += 2
            continue
        out.append(c if c in "()+*?" else re.escape(c))
        i += 1
    return re.compile("".join(out))


def equip_patterns():
    with open(DATA_LUA, encoding="utf-8") as f:
        text = f.read()
    block = text[text.index("D.EQUIP_PATTERNS"):]
    block = block[:block.index("\n}\n")]
    patterns = []
    for m in re.finditer(r'\{\s*"([^"]+)",\s*(\{[^}]*\}|"SCHOOL")\s*\}', block):
        stats = "SCHOOL" if m.group(2) == '"SCHOOL"' else re.findall(r'"(\w+)"', m.group(2))
        patterns.append((lua_pattern_to_regex(m.group(1)), stats))
    schools = dict(re.findall(r'(\w+) = "(\w+)"', text[text.index("D.SCHOOLS"):].split("\n", 1)[0]))
    return patterns, schools


def stats_from(equip, effects, patterns, schools):
    stats, summed = {}, {}
    for key, value in (equip or {}).items():
        if isinstance(value, (int, float)) and value > 0:
            for stat in STAT_KEYS.get(key, ()):
                if key in SUMMED:
                    summed[stat] = summed.get(stat, 0) + value
                else:
                    stats[stat] = max(stats.get(stat, 0), value)
    for stat, value in summed.items():
        stats[stat] = max(stats.get(stat, 0), value)
    # Same rule as Scoring:ItemStats: the larger of the API's and the text's number.
    for line in effects:
        if not line.startswith("Equip:"):
            continue
        low = line.lower()
        for regex, out in patterns:
            m = regex.search(low)
            if not m:
                continue
            if out == "SCHOOL":
                school = schools.get(m.group(1))
                if school:
                    stats[school] = max(stats.get(school, 0), int(m.group(2)))
            else:
                for stat in out:
                    stats[stat] = max(stats.get(stat, 0), int(m.group(1)))
            break
    return stats


def class_names(mask):
    if not mask or mask & ALL_CLASSES == ALL_CLASSES:
        return None
    names = [name for bit, name in CLASS_BITS if mask & bit]
    return ", ".join(names) or None


def source_of(row):
    codes = row.get("source") or []
    more = (row.get("sourcemore") or [{}])[0] or {}
    kind = next((SOURCE_KINDS[c] for c in codes if c in SOURCE_KINDS), None)
    if not kind:
        return None
    src = {"kind": kind}
    if more.get("z"):
        src["area"] = more["z"]
    if more.get("n"):
        if more.get("t") == 5:
            src["quest"] = more["n"]
        else:
            src["npc"] = more["n"]
    if more.get("t") == 5 and more.get("ti"):
        src["questID"] = more["ti"]
    if more.get("t") == 2 and kind == "world":
        src["object"] = True
    return src


# ---------------------------------------------------------------------------
# The run
# ---------------------------------------------------------------------------

def walk_lists(fetcher, rows, gatherer):
    def page(path):
        text = fetcher.get(BASE + path)
        if text is None:
            print("  gave up on", path)
            return 0
        r, g = list_page(text)
        rows.update({k: v for k, v in r.items() if k not in rows})
        gatherer.update({k: v for k, v in g.items() if k not in gatherer})
        return len(r)

    for top, slugs in SUBCLASS_SLUGS.items():
        for level in list(range(0, MAX_LEVEL + 1)) + [None]:
            band = ("min-req-level:%d" % (MAX_LEVEL + 1)) if level is None else \
                ("min-req-level:%d/max-req-level:%d" % (level, level))
            n = page("items/%s/%s" % (top, band))
            if n >= SPLIT_AT:
                for slug in slugs:
                    page("items/%s/%s/%s" % (top, slug, band))
        print("%-7s %d items so far (%d requests)" % (top, len(rows), fetcher.requests))


def build_row(item_id, lv, gat, xml, patterns, schools):
    json_ = (xml or {}).get("json") or {}
    equip = dict((gat or {}).get("jsonequip") or {})
    equip.update((xml or {}).get("jsonEquip") or {})
    base = dict(lv or {})
    for k, v in json_.items():
        base.setdefault(k, v)
    lines = (xml or {}).get("lines") or []
    has_tooltip = bool(lines)
    effects = [l for l in lines if l.startswith(EFFECT_PREFIXES) or re.match(r"^\(\d+\) Set:", l)]
    classes = class_names(base.get("reqclass") or equip.get("classes"))
    for l in lines:
        if l.startswith("Classes: "):
            classes = l[len("Classes: "):]
    icon = (gat or {}).get("icon") or (xml or {}).get("icon")
    row = {
        "name": base.get("name") or (gat or {}).get("name_enus"),
        "quality": base.get("quality", (gat or {}).get("quality")),
        "itemLevel": base.get("level"),
        "reqLevel": base.get("reqlevel") or equip.get("reqlevel") or 0,
        "equipLoc": SLOTS.get(base.get("slot") or equip.get("slotbak")),
        "classID": base.get("classs"),
        "subClassID": base.get("subclass"),
        "icon": ("Interface\\Icons\\" + icon) if icon else None,
        "stats": stats_from(equip, effects, patterns, schools),
        "classes": classes,
        "effects": effects,
        "source": source_of(base),
        "tooltip": has_tooltip or None,
    }
    return {k: v for k, v in row.items() if v is not None}


def needs_xml(row):
    """Not read off its tooltip yet: list pages leave out "Equip:" lines (attack
    power, procs, an idol's whole worth) and the "Classes:" line."""
    return not row.get("tooltip")


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--only", help="comma-separated item IDs (item pages only, for testing)")
    ap.add_argument("--refresh", action="store_true", help="ignore the cache")
    ap.add_argument("--min-quality", type=int, default=2, help="lowest quality kept (2 = green)")
    ap.add_argument("--limit", type=int, help="at most this many item pages")
    args = ap.parse_args(argv)

    patterns, schools = equip_patterns()
    fetcher = fetching.Fetcher(CACHE, refresh=args.refresh, pace=PACE)
    try:
        with open(HARVEST, encoding="utf-8") as f:
            harvested = json.load(f).get("items", {})
    except (OSError, ValueError):
        harvested = {}

    rows, gatherer = {}, {}
    if args.only:
        ids = [int(x) for x in args.only.split(",") if x.strip()]
        rows = {i: {} for i in ids}
    else:
        walk_lists(fetcher, rows, gatherer)

    out = {}
    pages = 0
    for item_id in sorted(rows):
        lv, gat = rows[item_id], gatherer.get(item_id)
        if lv and (lv.get("quality") or 0) < args.min_quality:
            continue
        if lv and lv.get("classs") not in (2, 4):
            continue
        row = build_row(item_id, lv, gat, None, patterns, schools)
        # Single item pages for the items the harvest doesn't have (the
        # harvest read the game's own tooltip for the rest).
        if not lv or (needs_xml(row) and str(item_id) not in harvested):
            if args.limit is not None and pages >= args.limit:
                pass
            else:
                pages += 1
                xml = item_xml(fetcher.get("%sitem=%d&xml" % (BASE, item_id)))
                if xml:
                    row = build_row(item_id, lv, gat, xml, patterns, schools)
        if row.get("name") and row.get("equipLoc") and (row.get("quality") or 0) >= args.min_quality:
            out[str(item_id)] = row
        if pages and pages % 200 == 0:
            print("  %d item pages, %d requests" % (pages, fetcher.requests))

    if not out:
        print("Nothing fetched; Data/wowhead.json left as it was.")
        return 1
    if args.only and os.path.exists(OUT):
        # A test run adds to what's there rather than replacing it.
        with open(OUT, encoding="utf-8") as f:
            old = json.load(f).get("items", {})
        old.update(out)
        out = old
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        json.dump({"source": BASE, "fetched": datetime.date.today().isoformat(), "items": out},
                  f, indent=0, ensure_ascii=False, sort_keys=True)
    print("wrote Data/wowhead.json: %d items (%d not in the harvest), %d web requests"
          % (len(out), sum(1 for k in out if k not in harvested), fetcher.requests))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
