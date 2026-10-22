"""Runs every addon's build scripts (tools/<Addon>/), in order, and says how each went.

    python tools/build_all.py                 # all the data builds
    python tools/build_all.py --list          # what would run, and what each needs
    python tools/build_all.py --only Waypoint,WealthPlanner/fetch_farms
    python tools/build_all.py --skip Spyglass
    python tools/build_all.py --offline       # no network: rebuild from what's cached
    python tools/build_all.py --headed        # show the browser window fetching Wowhead
    python tools/build_all.py --dev           # also the steps that read your saved variables
    python tools/build_all.py --art           # also redraw every addon's icons
    python tools/build_all.py --keep-data     # leave the datasets unpacked afterwards
    (yarn build ... does the same)

Each step runs on its own (python -I), so one failing doesn't stop the rest (unless
--stop-on-error). A step whose input isn't there (QuestieDB, saved variables, Pillow) is
skipped, with the reason. Scrapers keep their own caches: a second run only fetches what's new.
Wowhead pages come from a real browser session (_shared/webfetch.py: Playwright and Chrome).
The datasets (scraped pages, game tables) are kept packed (datasets.py): unpacked before the
first step, packed again after the last, even when a step fails.
"""
import argparse
import glob
import os
import subprocess
import sys
import time

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)  # python -I leaves the script's folder off sys.path
sys.path.insert(0, os.path.join(TOOLS, "_shared"))
import datasets  # noqa: E402  (tools/datasets.py: the scraped data, packed when not in use)
import paths  # noqa: E402
import savedvars  # noqa: E402

REPO = paths.REPO
ADDONS = paths.ADDONS
QUESTIEDB = paths.QUESTIEDB_TOC


def _questiedb():
    return None if os.path.exists(QUESTIEDB) else "needs QuestieDB (%s)" % QUESTIEDB


def _module(name):
    def check():
        try:
            __import__(name)
            return None
        except ImportError:
            return "needs the Python package %s" % name
    return check


def _saved(addon):
    def check():
        found = savedvars.files(addon)
        return None if found else "needs %s's saved variables (WTF/Account/*/SavedVariables/%s.lua)" % (addon, addon)
    return check


# The data builds, in order (a step's input built by an earlier one comes first). Each:
# (addon, script, args, what it does, [checks that return a reason to skip, or None]).
STEPS = [
    ("Waypoint", "build_places.py", [], "places, vendors and towns for Navigate To", [_questiedb]),
    ("Waypoint", "build_water.py", [], "land and water map for route planning (the game's map tiles, wago.tools)", [_module("numpy")]),
    ("WealthPlanner", "build_vendor_items.py", [], "which items vendors sell", [_questiedb]),
    ("WealthPlanner", "fetch_farms.py", [], "farming drops and spawns (Wowhead)", []),
    ("shared", "build_instances.py", [], "the dungeons and raids Field Guide, SpyGlass and Fireside share (QuestieDB)", [_questiedb]),
    ("shared", "build_recipes.py", [], "recipes for SpyGlass's journal and Wealth Planner's crafting, read once (Wowhead)", []),
    ("FieldGuide", "fetch_xp.py", [], "quest XP (QuestieDB + Wowhead cache)", [_questiedb]),
    ("FieldGuide", "build_guides.py", [], "the leveling guides", [_questiedb]),
    ("MrMiyagi", "fetch_mobs.py", [], "mob abilities (CMaNGOS, wago.tools)", []),
    ("Spyglass", "fetch_wowhead_quests.py", [], "SpyglassPluginQuests' quest database (Wowhead)", []),
    ("Spyglass", "build_loot.py", [], "dungeon and raid loot (AtlasLoot Continued + the harvest; needs the quest database)", [_module("lupa")]),
    ("Spyglass", "fetch_wowhead.py", [], "item equip effects (Wowhead)", []),
    ("Spyglass", "fetch_pulls.py", [], "dungeon pull maps (Wowhead, wago.tools)", []),
    ("Spyglass", "fetch_zone_art.py", [], "zone pictures (Wowhead)", [_module("PIL")]),
]

# With --dev: steps that read what the game saved (a /sg harvest, the sync history, contributions).
DEV_STEPS = [
    ("Spyglass", "build_items.py", [], "Data/Items.lua from /sg harvest runs", [_saved("Spyglass")]),
    ("Spyglass", "fetch_web_loot.py", [], "loot AtlasLoot lacks (wowtbc.gg)", []),
    ("Spyglass", "ingest_contrib.py", [], "players' contributed vendors and NPCs", [_saved("Spyglass")]),
    ("Spyglass", "export_anchors.py", [], "the sync history for a release", [_saved("Spyglass")]),
    ("RoadLog", "build_caves.py", [], "heights along the caves you logged (the caves' floors in the game files)",
     [_module("numpy"), _module("lupa"), _saved("RoadLog")]),
    ("Waypoint", "build_roads.py", [], "the roads, blockers and passes logged with RoadLog, packaged for every Waypoint user",
     [_module("numpy"), _module("lupa"), _saved("RoadLog")]),
]

# Never run here: SimplePanel/make_defaults.py takes your saved layout and an output path.


def art_steps():
    steps = []
    for path in sorted(glob.glob(os.path.join(TOOLS, "*", "make_*.py"))):
        addon = os.path.basename(os.path.dirname(path))
        steps.append((addon, os.path.basename(path), [], "redraws %s's art" % addon, [_module("PIL")]))
    return steps


def selected(step, only, skip):
    addon, script = step[0], step[1]
    keys = {addon.lower(), (addon + "/" + script).lower(), (addon + "/" + script[:-3]).lower(), script.lower(), script[:-3].lower()}
    if only and not keys & only:
        return False
    return not keys & skip


def run(step, env):
    addon, script, args = step[0], step[1], step[2]
    cmd = [sys.executable, "-I", os.path.join(TOOLS, addon, script)] + list(args)
    start = time.time()
    code = subprocess.call(cmd, cwd=REPO, env=env)
    return code, time.time() - start


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--list", action="store_true", help="show the steps and stop")
    ap.add_argument("--only", help="comma-separated addons or addon/script (e.g. Waypoint,WealthPlanner/fetch_farms)")
    ap.add_argument("--skip", help="comma-separated addons or addon/script to leave out")
    ap.add_argument("--offline", action="store_true", help="fetch nothing: rebuild from the caches")
    ap.add_argument("--headed", action="store_true", help="show the browser window while it fetches Wowhead")
    ap.add_argument("--dev", action="store_true", help="also the steps that read your saved variables")
    ap.add_argument("--art", action="store_true", help="also redraw every addon's icons")
    ap.add_argument("--stop-on-error", action="store_true", help="stop at the first step that fails")
    ap.add_argument("--keep-data", action="store_true", help="leave the datasets unpacked afterwards")
    a = ap.parse_args(argv)

    only = {s.strip().lower() for s in (a.only or "").split(",") if s.strip()}
    skip = {s.strip().lower() for s in (a.skip or "").split(",") if s.strip()}
    steps = STEPS + (DEV_STEPS if a.dev else []) + (art_steps() if a.art else [])
    steps = [s for s in steps if selected(s, only, skip)]
    if not steps:
        print("Nothing to run (check --only / --skip).")
        return 1

    if a.list:
        for i, s in enumerate(steps, 1):
            reasons = [r for r in (check() for check in s[4]) if r]
            print("%2d. %-14s %-30s %s%s" % (i, s[0], s[1], s[3], ("   [skip: %s]" % "; ".join(reasons)) if reasons else ""))
        return 0

    env = dict(os.environ)
    if a.offline:
        env["WOW_TOOLS_OFFLINE"] = "1"
    if a.headed:
        env["WOW_TOOLS_HEADED"] = "1"
    env["PYTHONUNBUFFERED"] = "1"

    # The datasets (scraped pages, game tables) stay packed: out for the build, back in after,
    # even when a step fails.
    print("Unpacking the datasets...", flush=True)
    datasets.unpack(quiet=True)
    results = []
    try:
        for i, s in enumerate(steps, 1):
            label = "%s / %s" % (s[0], s[1])
            reasons = [r for r in (check() for check in s[4]) if r]
            print("\n" + "=" * 78 + "\n[%d/%d] %s: %s\n" % (i, len(steps), label, s[3]) + "=" * 78, flush=True)
            if reasons:
                print("skipped: " + "; ".join(reasons), flush=True)
                results.append((label, "skipped", 0.0, "; ".join(reasons)))
                continue
            code, took = run(s, env)
            results.append((label, "ok" if code == 0 else "FAILED (exit %d)" % code, took, ""))
            if code != 0 and a.stop_on_error:
                break
    finally:
        print("\nPacking the datasets%s..." % (" (folders kept)" if a.keep_data else ""), flush=True)
        packed = datasets.pack(keep=a.keep_data)

    print("\n" + "=" * 78 + "\nSummary\n" + "=" * 78)
    for label, status, took, why in results:
        print("  %-46s %-16s %7.1fs  %s" % (label, status, took, why))
    failed = [r for r in results if r[1].startswith("FAILED")]
    print("\n%d ok, %d failed, %d skipped, in %.0fs." % (sum(r[1] == "ok" for r in results), len(failed),
                                                        sum(r[1] == "skipped" for r in results), sum(r[2] for r in results)))
    if not packed:
        print("Some datasets couldn't be packed: their folders were kept (python tools/datasets.py status).")
    return 1 if failed or not packed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
