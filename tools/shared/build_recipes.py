"""The one recipe dataset SpyGlass and Wealth Planner both load: every recipe of the classic
professions from Wowhead's WoW Forever database, read once and written to
addons/shared/Recipes.lua (the builds copy it into each addon that lists it in its TOC).

SpyGlass's journal and Wealth Planner's crafting used to scrape the same Wowhead pages each on its
own. Their collectors now share one paced, cached fetcher (Wealth Planner's, which also reads
SpyGlass's page cache), so a page is fetched once:
  * tools/Spyglass/fetch_wowhead_professions.py  collect(): the journal's recipes, where to learn
    each (trainer, vendors, drops, quests), Wowhead's 1-300 leveling guide, cooking dish kinds
  * tools/WealthPlanner/fetch_crafts.py           collect(): how many each craft makes, trainer
    costs, how each is learned (one word), First Aid and smelting, and vendor prices

Each keeps its own rules for which recipes it wants; a recipe only one of them wants is marked
with only = "journal" or "craft", and each addon's loader keeps its own. Where the two read a
field differently, Wealth Planner's reading is kept beside it in craft = { ... }.

    python tools/shared/build_recipes.py
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
REPO = os.path.dirname(TOOLS)
OUT = os.path.join(REPO, "addons", "shared", "Recipes.lua")

sys.path.insert(0, os.path.join(TOOLS, "_shared"))
sys.path.insert(0, os.path.join(TOOLS, "Spyglass"))
sys.path.insert(0, os.path.join(TOOLS, "WealthPlanner"))
import fetch_wowhead_professions as journal  # noqa: E402
import fetch_crafts as crafts  # noqa: E402
import fetch_farms as ff  # noqa: E402
import luawrite  # noqa: E402

# Wealth Planner's profession keys -> the journal's names, in the order written.
PROFESSIONS = [
    ("alchemy", "Alchemy"), ("blacksmithing", "Blacksmithing"), ("enchanting", "Enchanting"),
    ("engineering", "Engineering"), ("leatherworking", "Leatherworking"), ("tailoring", "Tailoring"),
    ("cooking", "Cooking"), ("firstaid", "First Aid"), ("mining", "Mining"),
]
# Fields both read: the journal's name for each, Wealth Planner's.
SHARED_FIELDS = [("item", "item"), ("skill", "skill"), ("colors", "colors"), ("reagents", "reagents"),
                 ("name", "name"), ("recipe", "recipeItem")]


def lua_str(s):
    return luawrite.lua_str(s)  # newlines escaped, CRs dropped


def lua_val(v):
    return luawrite.lua_val(v, precision=2)  # made = 1.5: floats to 2 places


def empty(v):
    return v is None or v == [] or v == ""


def merge(rows_by_prof, recipes):
    """{ profession name: [ records ] }: the journal's rows in its order, each with Wealth
    Planner's fields added, then the recipes only Wealth Planner wants, by spell ID."""
    by_prof = {}
    for sid, r in recipes.items():
        by_prof.setdefault(r["prof"], {})[sid] = r
    out, differ = {}, 0
    for key, name in PROFESSIONS:
        craft = by_prof.get(key, {})
        records, seen = [], set()
        for row in rows_by_prof.get(name, []):
            rec = {k: v for k, v in row.items() if not empty(v)}
            c = craft.get(row["id"])
            if c:
                seen.add(row["id"])
                if c["made"] != 1:
                    rec["made"] = c["made"]
                if c["cost"]:
                    rec["cost"] = c["cost"]
                if c["learn"]:
                    rec["how"] = c["learn"]
                own = {}
                for jf, cf in SHARED_FIELDS:
                    a, b = row.get(jf), c.get(cf)
                    if (None if empty(a) else a) != (None if empty(b) else b):
                        own[jf] = b if not empty(b) else False
                if own:
                    rec["craft"] = own
                    differ += 1
            else:
                rec["only"] = "journal"
            records.append(rec)
        for sid in sorted(craft):
            if sid in seen:
                continue
            c = craft[sid]
            rec = {"id": sid, "name": c["name"], "skill": c["skill"], "reagents": c["reagents"], "only": "craft"}
            for jf, cf in (("item", "item"), ("colors", "colors"), ("recipe", "recipeItem")):
                if not empty(c.get(cf)):
                    rec[jf] = c[cf]
            if c["made"] != 1:
                rec["made"] = c["made"]
            if c["cost"]:
                rec["cost"] = c["cost"]
            if c["learn"]:
                rec["how"] = c["learn"]
            records.append(rec)
        out[name] = records
    return out, differ


def from_lua(v):
    """A lupa table as Python: a list when its keys are 1..n, else a dict."""
    if not hasattr(v, "items"):
        return v
    d = {k: from_lua(x) for k, x in v.items()}
    if d and all(isinstance(k, int) for k in d) and sorted(d) == list(range(1, len(d) + 1)):
        return [d[i] for i in range(1, len(d) + 1)]
    return d


def load_generated(path, var):
    import lupa
    lua = lupa.LuaRuntime()
    ns = lua.table()
    with open(path, encoding="utf-8") as f:
        lua.execute("local args = {...}; local f = assert(load(args[1], args[2])); f(nil, args[3])", f.read(), path, ns)
    return from_lua(ns[var])


def generated(addons):
    """The two addons' last generated files (Data/Professions.lua, Data/Crafts.lua), read back as
    collect() returns them: for turning them into the shared file without fetching anything."""
    rows = load_generated(os.path.join(addons, "Spyglass", "Data", "Professions.lua"), "ProfessionData")
    craft = load_generated(os.path.join(addons, "WealthPlanner", "Data", "Crafts.lua"), "CraftData")
    recipes = {}
    for sid, r in craft["recipes"].items():
        recipes[sid] = {"prof": r["prof"], "item": r.get("item"), "made": r.get("made", 1), "skill": r["skill"],
                        "colors": r.get("colors"), "reagents": r.get("reagents") or [], "learn": r.get("learn"),
                        "cost": r.get("cost"), "recipeItem": r.get("recipeItem"), "name": r["name"]}
    return rows, recipes, craft.get("vendor") or {}


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    fetcher = ff.Fetcher()
    if "--from-generated" in argv:
        # git's copies of the old files, so this works after they're gone from the workspace.
        rows, recipes, vendor = generated(argv[argv.index("--from-generated") + 1])
    else:
        print("== the journal's recipes (SpyGlass)", flush=True)
        rows = journal.collect(fetcher)
        print("== crafting (Wealth Planner)", flush=True)
        recipes, vendor = crafts.collect(fetcher)
    data, differ = merge(rows, recipes)

    lines = [
        "-- GENERATED by tools/shared/build_recipes.py from Wowhead's WoW Forever database.",
        "-- Do not edit; run the tool again. SpyGlass's journal and Wealth Planner's crafting both load it.",
        "--   recipes[profession] = { { id = spell ID, name, item = what it makes (nil: an enchant), skill,",
        "--     reagents = { { itemID, count } }, recipe = the pattern's item ID,",
        "--     colors = { orange, yellow, green, grey }: the skill where each starts,",
        "--     learn = { where } (the journal's text), how = \"trainer\"|\"vendor\"|\"drop\"|\"quest\",",
        "--     cost = trainer copper, made = average made per craft (1 when missing),",
        "--     guide = { { from, to } }: Wowhead's 1-300 leveling guide makes it at those skills,",
        "--     buff = (Cooking) the kind of dish, only = \"journal\"|\"craft\" when only one of them wants it,",
        "--     craft = { field = value }: Wealth Planner's own reading where it differs (false: none) } }",
        "--   vendor[itemID] = lowest vendor price (copper)",
        "local _, ns = ...",
        "ns.RecipeData = {",
        "professions = { %s }," % ", ".join(lua_str(n) for _, n in PROFESSIONS),
        "recipes = {",
    ]
    for _, name in PROFESSIONS:
        lines.append("[%s] = {" % lua_str(name))
        for rec in data.get(name, []):
            lines.append("    " + lua_val(rec) + ",")
        lines.append("},")
    lines += ["},", "vendor = {"]
    lines += ["[%d] = %d," % (iid, vendor[iid]) for iid in sorted(vendor)]
    lines += ["},", "}", ""]
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    total = sum(len(v) for v in data.values())
    print("wrote %s: %d recipes (%d read differently by the two), %d vendor prices; %.2f MB; %d web requests"
          % (os.path.relpath(OUT, REPO), total, differ, len(vendor), os.path.getsize(OUT) / 1048576.0,
             fetcher.requests))
    return 0


if __name__ == "__main__":
    sys.exit(main())
