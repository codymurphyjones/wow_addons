"""Turns what players contributed (SpyGlass's "Contribute data", kept by a
collector character with /sg collect) into Data/contributed.json for the next
update.

Reads SpyGlassDB.collected from the collector's saved variables (WoW writes them
on logout or /reload), keeps facts at least --min different players reported,
and groups them:
  loot     { npc: { place: [items] } }        who drops what, where
  vendors  { npc: { item: cost } }            what vendors sell and for what
  npcs     { npc: [map, x, y] }               where vendors and quest givers stand
  quests   { quest: { giver, rewards } }       who gives quests, their rewards
  bosses   { npc: { class, level, place } }   rares and bosses
  recipes  { spell: { quests, learned } }      quests that teach a recipe, and how
                                               players learned it ({ "t<npc>" / "i<item>" /
                                               "q<quest>" / "u": players })

    python tools/Spyglass/ingest_contrib.py                      # finds WTF/Account/*/SavedVariables/Spyglass.lua
    python tools/Spyglass/ingest_contrib.py --min 1 path/to/Spyglass.lua
"""
import argparse
import glob
import json
import os
import sys

from lupa import lua51

ADDON = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "addons", "Spyglass")  # tools/Spyglass/ builds addons/Spyglass/
WTF = os.environ.get("WOW_WTF") or r"Z:\Games\World of Warcraft\_classic_beta_\WTF"  # the game's saved variables (read only)
OUT = os.path.join(ADDON, "Data", "contributed.json")


def collected(path):
    """{ fact: reporters } from a saved-variables file."""
    lua = lua51.LuaRuntime()
    with open(path, encoding="utf-8", errors="replace") as f:
        lua.execute(f.read())
    db = lua.globals().SpyGlassDB
    out = {}
    if db is None:
        return out
    for fact, entry in (db.collected or {}).items():
        out[str(fact)] = int(entry.n or 0)
    # The shared set the collector synced (Sync.lua): trusted peers' facts, each
    # counted as one report unless reported directly as well.
    sync = db.sync
    for fact in ((sync and sync.facts) or {}).keys():
        out.setdefault(str(fact), 1)
    return out


def npc_key(s):
    return s if s.startswith("o") else int(s)


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("paths", nargs="*")
    ap.add_argument("--min", type=int, default=2, help="different players needed (default 2)")
    args = ap.parse_args(argv)
    paths = args.paths or glob.glob(os.path.join(WTF, "Account", "*", "SavedVariables", "Spyglass.lua"))

    facts = {}
    for path in paths:
        for fact, n in collected(path).items():
            facts[fact] = max(facts.get(fact, 0), n)
    kept = {f: n for f, n in facts.items() if n >= args.min}

    out = {"loot": {}, "vendors": {}, "npcs": {}, "quests": {}, "bosses": {}, "recipes": {}}
    for fact in sorted(kept):
        p = fact.split(":")
        kind = p[0]
        try:
            if kind == "L":
                out["loot"].setdefault(str(npc_key(p[1])), {}).setdefault(p[2], []).append(int(p[3]))
            elif kind == "V":
                out["vendors"].setdefault(str(npc_key(p[1])), {})[p[2]] = p[3]
            elif kind == "N":
                out["npcs"][str(npc_key(p[1]))] = [int(p[2]), float(p[3]), float(p[4])]
            elif kind == "Q":
                out["quests"].setdefault(p[1], {})["giver"] = npc_key(p[2])
            elif kind == "R":
                out["quests"].setdefault(p[1], {}).setdefault("rewards", []).append(int(p[2]))
            elif kind == "B":
                out["bosses"][p[1]] = {"class": p[2], "level": int(p[3]), "place": p[4]}
            elif kind == "S":
                out["recipes"].setdefault(p[2], {}).setdefault("quests", []).append(int(p[1]))
            elif kind == "K":
                out["recipes"].setdefault(p[1], {}).setdefault("learned", {})[p[2]] = kept[fact]
        except (IndexError, ValueError):
            continue

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        json.dump(out, f, indent=1, sort_keys=True)
    print("%d facts read, %d reported by at least %d players -> Data/contributed.json"
          % (len(facts), len(kept), args.min))
    for k, v in out.items():
        print("  %-8s %d" % (k, len(v)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
