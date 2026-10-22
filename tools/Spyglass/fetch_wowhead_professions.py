"""The journal's Professions tab data, from Wowhead's WoW Forever database:
every recipe of the crafting professions, Enchanting and Cooking (trainer, vendor, drop
and quest ones, the server's own included), what each makes and needs, and
where to learn it. Collected by tools/shared/build_recipes.py, which writes the one recipe
dataset both SpyGlass and Wealth Planner load (addons/shared/Recipes.lua).

Reads each profession's spell list (what it makes, skill, reagents, its
skill-up colours, how it's learned), Wowhead's Classic 1-300 leveling guide
(which recipes to make at which skill; recipes it uses are added if missing)
and its recipe items (patterns, plans, formulae...: who sells or drops
them, and where); a recipe with several sources gets its own page read. build_recipes.py gives
it the paced, cached fetcher; Wowhead's pages are read with tools/_shared/wowhead.py.

    python tools/Spyglass/fetch_wowhead_professions.py   (runs tools/shared/build_recipes.py)
"""
import html
import json
import os
import re
import sys
import urllib.parse

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "_shared"))
import wowhead  # noqa: E402
from wowhead import BASE, balanced, js_literal, listview, not_in_game, page_listview  # noqa: E402

MAX_SKILL = 300

# Profession -> Wowhead's slug (spells/professions/<slug>, items/recipes/<slug>).
PROFESSIONS = [
    ("Alchemy", "alchemy"), ("Blacksmithing", "blacksmithing"), ("Enchanting", "enchanting"),
    ("Engineering", "engineering"), ("Leatherworking", "leatherworking"), ("Tailoring", "tailoring"),
    ("Cooking", "cooking"),
]
# Secondary skills' spells are listed elsewhere.
SPELL_PATH = {"cooking": "spells/secondary-skills/"}
RECIPE_PREFIXES = ("Pattern: ", "Plans: ", "Recipe: ", "Schematic: ", "Formula: ", "Design: ", "Manual: ",
                   "Blueprint: ")

# Wowhead's source codes, as words.
LEARN = {6: "Trainer", 5: "Vendor", 2: "Drop", 4: "Quest", 16: "Fishing", 21: "Pickpocket", 1: "Crafted"}


def zones(fetcher):
    """{ area ID: name } for every zone and instance."""
    return {r["id"]: r["name"] for r in wowhead.zone_rows(fetcher) or []}


def where_lines(source, more, zone_names, commondrop=False):
    """'Trainer', 'Sold by X (Zone)', 'Drops from X (Zone)', 'World drop', 'Quest: Y'."""
    lines = []
    more = more or []
    by_type = {}
    for m in more:
        by_type.setdefault(m.get("t"), []).append(m)

    def place(m):
        z = zone_names.get(m.get("z"))
        return m.get("n", "?") + (" (" + z + ")" if z else "")

    for code in source or []:
        if code == 6:
            lines.append("Trainer")
        elif code == 5:
            vendors = [place(m) for m in more if m.get("t") == 1] or []
            lines.append("Sold by " + (", ".join(vendors[:3]) if vendors else "a vendor")
                         + (" and others" if len(vendors) > 3 else ""))
        elif code == 2:
            if commondrop and not more:
                lines.append("World drop")
            else:
                mobs = [place(m) for m in more if m.get("t") in (1, 2)]
                lines.append(("Drops from " + ", ".join(mobs[:3]) + (" and others" if len(mobs) > 3 else ""))
                             if mobs else "World drop")
        elif code == 4:
            quests = [m.get("n") for m in more if m.get("t") == 5 and m.get("n")]
            lines.append("Quest: " + ", ".join(quests[:2]) if quests else "Quest reward")
        elif code in LEARN:
            lines.append(LEARN[code])
    # Keep the order, drop repeats.
    return list(dict.fromkeys(lines))


def collect(fetcher):
    """{ profession: [ rows ] }, rows in the spell list's order (the journal's recipes)."""
    zone_names = zones(fetcher)
    out = {}
    for prof, slug in PROFESSIONS:
        spells = listview(fetcher.get(BASE + SPELL_PATH.get(slug, "spells/professions/") + slug) or "", "listviewspells")
        recipes = listview(fetcher.get(BASE + "items/recipes/" + slug) or "", "listviewitems")
        by_name = {}
        for r in recipes:
            for p in RECIPE_PREFIXES:
                if r.get("name", "").startswith(p):
                    by_name.setdefault(r["name"][len(p):], r)
        guide = guide_steps(fetcher, slug)
        in_guide = {sid for _, _, ids in guide for sid in ids}
        rows = []
        for s in spells:
            name = s.get("name") or ""
            creates = (s.get("creates") or [None])[0]
            skill = s.get("learnedat") or 0
            if not name or skill > MAX_SKILL or not_in_game(creates) or re.search(r"\b(OLD|DND|Test)\b", name):
                continue
            # Neither an item nor an enchant (smelting...): left out, unless the
            # leveling guide uses it to level.
            if not creates and not name.startswith("Enchant ") and s["id"] not in in_guide:
                continue
            recipe = by_name.get(name)
            if not recipe and not s.get("trainingcost") and 6 not in (s.get("source") or []):
                # Not in the recipe list (or under a name it doesn't match): the
                # item that teaches it, by Wowhead's search.
                recipe = search_recipe(fetcher, name)
            if recipe and not_in_game(recipe["id"]):
                continue  # a Season of Discovery pattern
            if recipe:
                more = recipe.get("sourcemore")
                if not more and not recipe.get("commondrop") and recipe.get("source"):
                    # Several sources: the pattern's page lists who sells it (and
                    # for what: gold, or a currency like Merchant's Favor) and
                    # who drops it.
                    learn = page_lines(fetcher, recipe["id"], zone_names) or \
                        where_lines(recipe.get("source"), None, zone_names)
                else:
                    learn = where_lines(recipe.get("source"), more, zone_names, recipe.get("commondrop"))
            else:
                learn = where_lines(s.get("source"), s.get("sourcemore"), zone_names)
            # Wowhead's sources are spread out: the spell's own, then a
            # trainer's price (and the specialization it needs), then the
            # recipe item's page.
            if not learn:
                learn = where_lines(s.get("source"), s.get("sourcemore"), zone_names)
            if not learn and s.get("trainingcost") is not None:
                learn = ["Trainer"]
            learn = [trainer_line(s) if line == "Trainer" else line for line in learn]
            if recipe and (not learn or "World drop" in learn):
                # Who drops it (or sells it), from the item's page: a "world drop"
                # is often a few mobs in one place.
                found = page_lines(fetcher, recipe["id"], zone_names)
                if found:
                    learn = list(dict.fromkeys([l for l in learn if l != "World drop"] + found))
            if not learn:
                learn = ["Known from the start"] if skill <= 1 else ["Wowhead lists no source for this recipe"]
            colors = s.get("colors")
            rows.append({
                "id": s["id"], "name": name, "item": creates, "skill": skill,
                "reagents": [[a, b] for a, b in (s.get("reagents") or [])],
                "recipe": recipe and recipe["id"], "learn": learn,
                # Skill-up colours: the skill where orange, yellow, green and grey start.
                "colors": [int(c) for c in colors] if colors and len(colors) == 4 else None,
            })
        # The leveling guide's steps: { from, to } on each recipe it uses.
        by_id = {r["id"]: r for r in rows}
        names = guide_names(fetcher, slug)
        used, missing = set(), set()
        for lo, hi, ids in guide:
            for sid in ids:
                # Not in this game under that ID: the server's own version of it
                # ("Minor Healing Potion" -> "Minor Discolored Healing Potion").
                r = by_id.get(sid) or replacement(rows, names.get(sid))
                if r:
                    r.setdefault("guide", []).append([lo, hi])
                    used.add(sid)
                else:
                    missing.add(sid)
        if prof == "Cooking":
            # Cooking's journal page sorts its dishes by what eating them gives.
            for r in rows:
                r["buff"] = cooking_kind(item_use(fetcher, r["item"])) if r["item"] else "C_SPECIAL"
        out[prof] = rows
        print("%-15s %d recipes (%d with a pattern); guide: %d steps, %d recipes used%s"
              % (prof, len(rows), sum(1 for r in rows if r["recipe"]), len(guide), len(used),
                 (", not in this game: " + ", ".join(map(str, sorted(missing)))) if missing else ""))

    return out


GUIDE = "https://www.wowhead.com/classic/guide/%s-leveling-1-300-wow-classic"


def guide_steps(fetcher, slug):
    """Wowhead's Classic 1-300 leveling guide: [ (from, to, [spell IDs]) ], in order.
    Its tables have rows like '[tr][td]30 - 45[/td][td]~18 [spell=2152][/td]...'."""
    text = (fetcher.get(GUIDE % slug) or "").replace("\\/", "/").replace("\\r", "").replace("\\n", "\n")
    steps = []
    for m in re.finditer(r"\[tr\]\s*\[td\]\s*(\d+)\s*[-–]\s*(\d+)\s*\[/td\](.*?)\[/tr\]", text, re.S):
        lo, hi, rest = int(m.group(1)), int(m.group(2)), m.group(3)
        # The recipe cell only (the next one lists the materials).
        cell = re.match(r"\s*\[td\](.*?)\[/td\]", rest, re.S)
        ids = [int(x) for x in re.findall(r"\[spell=(\d+)", cell.group(1) if cell else rest)]
        if ids and lo < hi <= 300:
            steps.append((lo, hi, ids))
    return steps


def guide_names(fetcher, slug):
    """{ spell ID: name } of the spells the guide names (its page data)."""
    text = fetcher.get(GUIDE % slug) or ""
    out = {}
    for m in re.finditer(r"WH\.Gatherer\.addData\(6,\s*\d+,\s*", text):
        try:
            data = js_literal(balanced(text, m.end()))
        except ValueError:
            continue
        for sid, entry in data.items():
            out[int(sid)] = entry.get("name_enus")
    return out


def replacement(rows, name):
    """A recipe whose name is the guide's with one word added, or None."""
    if not name:
        return None
    want = name.lower().split()
    for r in rows:
        words = r["name"].lower().split()
        if len(words) == len(want) + 1 and all(w in words for w in want):
            rest = [w for w in words if w not in want]
            if len(rest) == 1 and words[-1] == want[-1]:
                return r
    return None


# Specializations a recipe can need (their spell IDs).
SPECIALIZATIONS = {
    9788: "Armorsmiths", 9787: "Weaponsmiths", 17039: "Master Swordsmiths", 17040: "Master Hammersmiths",
    17041: "Master Axesmiths", 20219: "Gnomish Engineers", 20222: "Goblin Engineers",
    10656: "Dragonscale Leatherworkers", 10658: "Elemental Leatherworkers", 10660: "Tribal Leatherworkers",
}


def money_text(copper):
    g, s_, c = copper // 10000, (copper // 100) % 100, copper % 100
    return " ".join(p for p in ("%dg" % g if g else "", "%ds" % s_ if s_ else "", "%dc" % c if c else "") if p) or "free"


def trainer_line(spell):
    """'Trainer (Armorsmiths only), 90s' from the spell's training cost and specialization."""
    line = "Trainer"
    spec = SPECIALIZATIONS.get(spell.get("specialization"))
    if spec:
        line += " (" + spec + " only)"
    cost = spell.get("trainingcost")
    if cost:
        line += ", " + money_text(cost)
    return line


def item_use(fetcher, item_id):
    """The item tooltip's 'Use:' text, or ''."""
    text = fetcher.get("%sitem=%d&xml" % (BASE, item_id)) or ""
    m = re.search(r"<htmlTooltip><!\[CDATA\[(.*?)\]\]></htmlTooltip>", text, re.S)
    if not m:
        return ""
    tip = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", m.group(1))))
    use = re.search(r"Use: (.*?)(?: Requires| Sell Price|$)", tip)
    return use.group(1) if use else ""


# A dish's kind from what it gives, first match wins (keys as in Journal/Professions.lua).
COOKING_KINDS = [
    ("C_STAMSPI", r"Stamina and Spirit"),
    ("C_HEALING", r"Healing Power"),
    ("C_SPELL", r"Spell Damage"),
    ("C_ATTACK", r"Attack Power|Critical Strike"),
    ("C_GATHER", r"Fishing Skill|Herbalism|Mining|Skinning"),
    ("C_STAMINA", r"gain \d+ Stamina"),
    ("C_STRENGTH", r"gain \d+ Strength"),
    ("C_AGILITY", r"gain \d+ Agility"),
    ("C_INTELLECT", r"gain \d+ Intellect"),
    ("C_SPIRIT", r"gain \d+ Spirit"),
    ("C_SPECIAL", r"well fed|Eat me|energy|belch|Builds|Places|Lay out"),
    ("C_BASIC", r"Restores \d+ (health|mana)|Heals \d+"),
]


def cooking_kind(use):
    for key, pattern in COOKING_KINDS:
        if re.search(pattern, use, re.I):
            return key
    return "C_SPECIAL"


_currencies, _items = {}, {}


def currency_name(fetcher, cid):
    if cid not in _currencies:
        text = fetcher.get("%scurrency=%d" % (BASE, cid)) or ""
        m = re.search(r'<meta property="og:title" content="([^"]+)"', text)
        _currencies[cid] = html.unescape(m.group(1)) if m else "currency %d" % cid
    return _currencies[cid]


def item_name(fetcher, item_id):
    if item_id not in _items:
        text = fetcher.get("%sitem=%d&xml" % (BASE, item_id)) or ""
        m = re.search(r"<name><!\[CDATA\[(.*?)\]\]></name>", text)
        _items[item_id] = m.group(1) if m else "item %d" % item_id
    return _items[item_id]


def cost_text(fetcher, cost):
    """Wowhead's cost [ money, [[currency, n]], [[item, n]] ] as words ('30 Merchant's Favor', '2g 50s')."""
    if not cost:
        return None
    c = cost[0] if isinstance(cost[0], list) else cost
    parts = []
    money = c[0] if len(c) > 0 else 0
    if money:
        g, s_ = money // 10000, (money // 100) % 100
        parts.append(("%dg" % g if g else "") + (" %ds" % s_ if s_ else "").strip() or "%dc" % money)
    for cid, n in (c[1] if len(c) > 1 else []) or []:
        parts.append("%d %s" % (n, currency_name(fetcher, cid)))
    for iid, n in (c[2] if len(c) > 2 else []) or []:
        parts.append("%d %s" % (n, item_name(fetcher, iid)))
    return ", ".join(p for p in parts if p) or None


# More mobs than this drop it: a world drop, not worth naming them.
MAX_DROPPERS = 8


def search_recipe(fetcher, name):
    """{ id } of the item that teaches a recipe ('Blueprint: <name>', 'Recipe: <name>'...), by Wowhead's search."""
    text = fetcher.get(BASE + "search/suggestions-template?q=" + urllib.parse.quote_plus(name)) or ""
    try:
        results = json.loads(text).get("results") or []
    except (ValueError, AttributeError):
        return None
    for r in results:
        rname = r.get("name") or ""
        if r.get("type") == 3 and any(rname == p + name for p in RECIPE_PREFIXES):
            return {"id": r["id"]}
    return None


def page_lines(fetcher, item_id, zone_names):
    """'Sold by X (Zone), Y (Zone) for 30 Merchant's Favor', 'Drops from Z (Zone)' from the item's page."""
    text = fetcher.get("%sitem=%d" % (BASE, item_id)) or ""
    lines = []

    def place(r):
        loc = (r.get("location") or [None])[0]
        z = zone_names.get(loc)
        return r.get("name", "?") + (" (" + z + ")" if z else "")

    vendors = page_listview(text, "sold-by")
    if vendors:
        names = [place(r) for r in vendors[:3]]
        cost = cost_text(fetcher, vendors[0].get("cost"))
        lines.append("Sold by " + ", ".join(names) + (" and others" if len(vendors) > 3 else "")
                     + (" for " + cost if cost else ""))
    droppers = page_listview(text, "dropped-by")
    if len(droppers) > MAX_DROPPERS:
        # Too many to name: a world drop, from mobs of these levels.
        lows = sorted(r.get("minlevel") or 0 for r in droppers if r.get("minlevel"))
        highs = sorted(r.get("maxlevel") or 0 for r in droppers if r.get("maxlevel"))
        lines.append("World drop" + (" (mobs level %d-%d)" % (lows[0], highs[-1]) if lows and highs else ""))
    elif droppers:
        def chance(r):
            return (r.get("count") or 0) / r["outof"] if r.get("outof") else 0
        droppers = sorted(droppers, key=chance, reverse=True)
        parts = []
        for r in droppers[:3]:
            c = chance(r)
            parts.append(place(r) + (" %s%%" % ("%.1f" % (c * 100)).rstrip("0").rstrip(".") if c else ""))
        lines.append("Drops from " + ", ".join(parts) + (" and others" if len(droppers) > 3 else ""))
    for lv_id, label in (("contained-in-object", "Found in "), ("contained-in-item", "Found in ")):
        found = page_listview(text, lv_id)
        if found:
            lines.append(label + ", ".join(r.get("name", "?") for r in found[:3]))
    return lines


def fq_item_xml(fetcher, item_id):
    """The item page's json (source, sourcemore), or None."""
    text = fetcher.get("%sitem=%d&xml" % (BASE, item_id)) or ""
    m = re.search(r"<json><!\[CDATA\[(.*?)\]\]></json>", text, re.S)
    if not m:
        return None
    try:
        return js_literal("{" + m.group(1) + "}")
    except ValueError:
        return None


def main():
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "shared"))
    import build_recipes
    return build_recipes.main()


if __name__ == "__main__":
    sys.exit(main())
