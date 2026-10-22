"""Wealth Planner's crafting data from Wowhead's WoW Forever database: every recipe of
the classic professions (what it makes, how many, the skill and skill-up colours, its
reagents, where it's learned and what the trainer charges, the recipe item), and what
vendors charge for the reagents and trade goods they sell. Collected by
tools/shared/build_recipes.py, which writes the one recipe dataset both Wealth Planner and SpyGlass
load (addons/shared/Recipes.lua).

Uses fetch_farms.py's paced, cached fetcher (same cache) and Wowhead's page readers
(tools/_shared/wowhead.py). The approach follows tools/Spyglass/fetch_wowhead_professions.py.

    python tools/WealthPlanner/fetch_crafts.py   (runs tools/shared/build_recipes.py)
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fetch_farms as ff  # noqa: E402  (puts tools/_shared on sys.path)
from wowhead import listview, not_in_game, page_listview  # noqa: E402

BASE = ff.BASE
MAX_SKILL = 300

# (key written to the data, spell list path, recipe items list path or None)
PROFESSIONS = [
    ("alchemy", "spells/professions/alchemy", "items/recipes/alchemy"),
    ("blacksmithing", "spells/professions/blacksmithing", "items/recipes/blacksmithing"),
    ("enchanting", "spells/professions/enchanting", "items/recipes/enchanting"),
    ("engineering", "spells/professions/engineering", "items/recipes/engineering"),
    ("leatherworking", "spells/professions/leatherworking", "items/recipes/leatherworking"),
    ("tailoring", "spells/professions/tailoring", "items/recipes/tailoring"),
    ("cooking", "spells/secondary-skills/cooking", "items/recipes/cooking"),
    ("firstaid", "spells/secondary-skills/first-aid", "items/recipes/first-aid"),
    ("mining", "spells/professions/mining", None),  # smelting
]
RECIPE_PREFIXES = ("Pattern: ", "Plans: ", "Recipe: ", "Schematic: ", "Formula: ", "Design: ", "Manual: ",
                   "Blueprint: ")
# Wowhead's source codes, first match wins.
LEARN = [(6, "trainer"), (5, "vendor"), (4, "quest"), (2, "drop"), (16, "drop"), (21, "drop")]


def learn_of(source):
    for code, word in LEARN:
        if code in (source or []):
            return word
    return None


def money(cost):
    """Copper from Wowhead's cost [ money, [[currency, n]], [[item, n]] ]; None when it
    costs anything but money."""
    if not cost:
        return None
    c = cost[0] if isinstance(cost[0], list) else cost
    if (len(c) > 1 and c[1]) or (len(c) > 2 and c[2]):
        return None
    return c[0] if c and isinstance(c[0], int) and c[0] > 0 else None


def vendor_price(fetcher, item_id):
    """The lowest price a vendor sells the item for (copper), from its page, or None."""
    text = fetcher.get("%sitem=%d" % (BASE, item_id)) or ""
    prices = [p for p in (money(r.get("cost")) for r in page_listview(text, "sold-by")) if p]
    return min(prices) if prices else None


def collect(fetcher):
    """recipes { spellID: record }, vendor { itemID: copper }: what Wealth Planner's crafting reads."""
    recipes = {}
    for prof, spell_path, recipe_path in PROFESSIONS:
        spells = listview(fetcher.get(BASE + spell_path) or "", "listviewspells")
        by_name = {}
        if recipe_path:
            for r in listview(fetcher.get(BASE + recipe_path) or "", "listviewitems"):
                if not_in_game(r["id"]):
                    continue
                for p in RECIPE_PREFIXES:
                    if r.get("name", "").startswith(p):
                        by_name.setdefault(r["name"][len(p):], r)
        n = 0
        for s in spells:
            name = s.get("name") or ""
            creates = s.get("creates") or []
            item = creates[0] if creates else None
            skill = s.get("learnedat") or 0
            reagents = [[a, b] for a, b in (s.get("reagents") or [])]
            if not name or skill > MAX_SKILL or not reagents or re.search(r"\b(OLD|DND|Test|QA)\b", name):
                continue
            if item and not_in_game(item):
                continue
            if any(not_in_game(a) for a, _ in reagents):
                continue
            # Enchants make no item; everything else must.
            if not item and not name.startswith("Enchant "):
                continue
            recipe = by_name.get(name)
            if recipe and not_in_game(recipe["id"]):
                recipe = None
            learn = None
            if s.get("trainingcost") is not None or 6 in (s.get("source") or []):
                learn = "trainer"
            elif recipe:
                learn = learn_of(recipe.get("source")) or "drop"
            else:
                learn = learn_of(s.get("source")) or ("trainer" if skill <= 1 else None)
            made = 1.0
            if len(creates) >= 3 and creates[1]:
                made = (creates[1] + (creates[2] or creates[1])) / 2.0
            colors = s.get("colors")
            recipes[s["id"]] = {
                "prof": prof, "item": item, "made": made, "skill": skill,
                "colors": [int(c) for c in colors] if colors and len(colors) == 4 else None,
                "reagents": reagents, "learn": learn,
                "cost": s.get("trainingcost") or None,
                "recipeItem": recipe["id"] if recipe else None,
                "name": name,
            }
            n += 1
        print("%-15s %d recipes" % (prof, n), flush=True)

    # Vendor prices: every reagent, and every trade good (their pages are cached by fetch_farms).
    wanted = {a for r in recipes.values() for a, _ in r["reagents"]}
    wanted |= {r["id"] for r in ff.item_list(fetcher)}
    vendor = {}
    for n, iid in enumerate(sorted(wanted), 1):
        p = vendor_price(fetcher, iid)
        if p:
            vendor[iid] = p
        if n % 100 == 0:
            print("  %d/%d item pages, %d web requests" % (n, len(wanted), fetcher.requests), flush=True)

    return recipes, vendor


def main():
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "shared"))
    import build_recipes
    return build_recipes.main()


if __name__ == "__main__":
    sys.exit(main())
