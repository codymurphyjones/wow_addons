"""Checks where the guide says quest NPCs stand against two other sources (item 7 of the test plan).

    python -I tools/FieldGuide/check_npcs.py

For every quest giver and hand-in in Guides/Data.lua: the CMaNGOS world database's spawn for that NPC
(the same game positions, kept apart from QuestieDB), and the navigation graph (is that spot in water,
or far from any ground). Lists the disagreements, worst first, in tools/FieldGuide/npc_report.txt.
"""
import collections
import math
import os
import re
import site
import sys

sys.path.append(site.getusersitepackages())

import numpy as np  # noqa: E402
from scipy.spatial import cKDTree  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "Waypoint"))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "_shared"))
import zone_walks as Z  # noqa: E402
import nav_pack as NP  # noqa: E402
import sqldump  # noqa: E402
import fetcher as fetching  # noqa: E402

CHECK = 60   # yards of disagreement worth listing


def main():
    data = open(Z.DATA, encoding="utf-8").read()
    people = collections.defaultdict(set)  # name -> { (uiMapID, x, y) }
    for ui, x, y, who in re.findall(r'\b[at] = \{ (\d+), ([\d.]+), ([\d.]+), "((?:[^"\\]|\\.)*)" \}', data):
        people[who].add((int(ui), float(x), float(y)))
    assign = Z.assignments()
    dump = os.path.join(os.path.dirname(HERE), "Spyglass", ".wowhead_cache")
    text = sqldump.cmangos(fetching.Fetcher(dump, pace=0))
    names = {}
    for g in sqldump.rows_of(text, "creature_template"):
        names.setdefault(g.get("Name") or g.get("name"), []).append(int(g.get("Entry") or g.get("entry")))
    spawns = collections.defaultdict(list)
    for r in sqldump.sql_rows(text, "creature"):
        spawns[int(r[1])].append((int(r[2]), float(r[4]), float(r[5])))  # map, x (north), y (west)
    trees, kinds = {}, {}
    rows, compared, off = [], 0, 0
    shifts = collections.defaultdict(list)
    for who, spots in people.items():
        ids = names.get(who, [])
        theirs = [s for i in ids for s in spawns.get(i, [])]
        for ui, x, y in spots:
            w = Z.C.world(assign, ui, x / 100, y / 100)
            if not w:
                continue
            mine = [s for s in theirs if s[0] == w[0]]
            gap = min((math.hypot(s[1] - w[1], s[2] - w[2]) for s in mine), default=None)
            if mine:
                nearest = min(mine, key=lambda s: math.hypot(s[1] - w[1], s[2] - w[2]))
                shifts[ui].append((w[1] - nearest[1], w[2] - nearest[2]))
            wet = None
            if w[0] not in trees and os.path.exists(os.path.join(NP.NAV, "%d.graph.npz" % w[0])):
                z = np.load(os.path.join(NP.NAV, "%d.graph.npz" % w[0]))
                N = z["nodes"].astype(np.int64)
                _, _, n, wv, _ = NP.positions(N)
                trees[w[0]], kinds[w[0]] = cKDTree(np.stack([n, wv], axis=1)), N[:, 4]
            if w[0] in trees:
                d, i = trees[w[0]].query([w[1], w[2]])
                wet = bool(kinds[w[0]][i] == 1) and d < 15
            if gap is not None:
                compared += 1
                if gap > CHECK:
                    off += 1
            if (gap is not None and gap > CHECK) or wet:
                rows.append((gap if gap is not None else -1, wet, who, ui, x, y))
    rows.sort(key=lambda r: -r[0])
    lines = ["%6.0f yd off%s  %-34s %d %.1f, %.1f" % (r[0], "  IN WATER" if r[1] else "", r[2][:34], r[3], r[4], r[5]) for r in rows]
    with open(os.path.join(HERE, "npc_report.txt"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print("%d spots compared, %d over %d yd from the world database, %d listed, %d in water" % (
        compared, off, CHECK, len(rows), sum(1 for r in rows if r[1])))
    # Misaligned maps move a whole zone the same way; one bad NPC moves only itself.
    print("zone   spots  median north  median west  median gap   within 30 yd")
    for ui, ds in sorted(shifts.items(), key=lambda kv: -len(kv[1])):
        if len(ds) >= 8:
            dn = sorted(d[0] for d in ds)[len(ds) // 2]
            dw = sorted(d[1] for d in ds)[len(ds) // 2]
            gaps = sorted(math.hypot(d[0], d[1]) for d in ds)
            print("%5d %6d %12.1f %12.1f %10.1f %10d%%" % (
                ui, len(ds), dn, dw, gaps[len(ds) // 2], 100 * sum(g <= 30 for g in gaps) / len(ds)))
    for line in lines[:14]:
        print(line)
    for line in [x for x in lines if "Kauth" in x]:
        print("KAUTH", line)


if __name__ == "__main__":
    main()
