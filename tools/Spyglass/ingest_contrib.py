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
  pulls     [ { i, m, x, y, npcs, n } ]       pulls recorded in dungeons (Journal/DungeonWatch.lua):
                                               instance map ID, floor uiMap, where the player stood
                                               (0-100, or null), the NPC IDs that came, and players
  sightings { uiMap: { npc: players } }       NPCs seen on each dungeon floor

Pulls and sightings also come from each account's own pool (SpyGlassDB.observed, kept whether
or not "Contribute data" is on), and need only --min-pulls players (default 1): a wrong one only
nudges a pack's floor or link, which tools/Spyglass/fetch_pulls.py folds in on the next build.

    python tools/Spyglass/ingest_contrib.py                      # finds WTF/Account/*/SavedVariables/Spyglass.lua
    python tools/Spyglass/ingest_contrib.py --min 1 path/to/Spyglass.lua
"""
import argparse
import json
import os
import sys

from lupa import lua51

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "_shared"))
import savedvars  # noqa: E402

ADDON = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "addons", "Spyglass")  # tools/Spyglass/ builds addons/Spyglass/
OUT = os.path.join(ADDON, "Data", "contributed.json")


def collected(path):
    """{ fact: reporters } from a saved-variables file."""
    db = savedvars.load(path, "SpyGlassDB", lua=lua51.LuaRuntime(), errors="replace")
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


def observed(path):
    """{ fact: 1 } of the pulls and sightings this account recorded itself (SpyGlassDB.observed)."""
    db = savedvars.load(path, "SpyGlassDB", lua=lua51.LuaRuntime(), errors="replace")
    obs = db and db.observed
    return {str(f): 1 for f in ((obs and obs.facts) or {}).keys()}


def pull_npcs(s):
    """"123x2.456" -> [123, 123, 456]."""
    out = []
    for part in s.split("."):
        npc, _, count = part.partition("x")
        out += [int(npc)] * (int(count) if count else 1)
    return out


def npc_key(s):
    return s if s.startswith("o") else int(s)


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("paths", nargs="*")
    ap.add_argument("--min", type=int, default=2, help="different players needed (default 2)")
    ap.add_argument("--min-pulls", type=int, default=1, help="players needed for pulls and sightings (default 1)")
    args = ap.parse_args(argv)
    paths = args.paths or savedvars.files("Spyglass")

    facts = {}
    for path in paths:
        for fact, n in collected(path).items():
            facts[fact] = max(facts.get(fact, 0), n)
        pooled = observed(path)
        for fact, n in pooled.items():
            facts[fact] = max(facts.get(fact, 0), n)
    kept = {f: n for f, n in facts.items() if n >= (args.min_pulls if f[:2] in ("P:", "W:") else args.min)}

    out = {"loot": {}, "vendors": {}, "npcs": {}, "quests": {}, "bosses": {}, "recipes": {},
           "pulls": [], "sightings": {}}
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
            elif kind == "P":
                out["pulls"].append({"i": int(p[1]), "m": int(p[2]),
                                     "x": None if p[3] == "-" else float(p[3]),
                                     "y": None if p[4] == "-" else float(p[4]),
                                     "npcs": sorted(set(pull_npcs(p[5]))), "size": len(pull_npcs(p[5])),
                                     "n": kept[fact]})
            elif kind == "W":
                if int(p[2]):
                    out["sightings"].setdefault(p[2], {})[p[3]] = kept[fact]
        except (IndexError, ValueError):
            continue

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        json.dump(out, f, indent=1, sort_keys=True)
    print("%d facts read, %d reported by at least %d players (pulls and sightings: %d) -> Data/contributed.json"
          % (len(facts), len(kept), args.min, args.min_pulls))
    for k, v in out.items():
        print("  %-8s %d" % (k, len(v)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
