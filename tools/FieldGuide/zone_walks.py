"""Real walking times between zones with quests, over Waypoint's land and water map.

Straight lines lie: Elwynn Forest and Dun Morogh look a few minutes apart, and there's a mountain
range between them. This walks the map (Waypoint/Data/Water.lua, built from the game's tiles: the
steps you can really take, cliffs you can drop but not climb, tunnels) from each zone's quest area
to the others. Zones it can't reach on foot aren't listed.

Writes tools/FieldGuide/data/zone_walks.json: { "from uiMapID": { "to uiMapID": minutes } }.

    python -I tools/FieldGuide/zone_walks.py
"""
import collections
import csv
import io
import json
import os
import re
import statistics
import sys
import tarfile

import numpy as np
from scipy.sparse import csr_matrix
from scipy.sparse.csgraph import dijkstra

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "tools", "_shared"))
sys.path.insert(0, os.path.join(ROOT, "tools", "Waypoint"))
import check_water as C  # noqa: E402

OUT = os.path.join(HERE, "data", "zone_walks.json")
DATA = os.path.join(ROOT, "addons", "FieldGuide", "Guides", "Data.lua")
WATER = os.path.join(ROOT, "addons", "Waypoint", "Data", "Water.lua")
YARDS_A_MINUTE = 420
SWIM = 1.5  # a square of water takes this much longer than land


def assignments():
    """uiMapID -> its UiMapAssignment row (from Waypoint's cached table, read out of the archive)."""
    with tarfile.open(os.path.join(ROOT, "tools", "Waypoint", ".cache.tar.xz"), "r:xz") as t:
        name = sorted(m.name for m in t.getmembers() if "UiMapAssignment" in m.name)[-1]
        text = t.extractfile(name).read().decode("utf-8")
    return [r for r in csv.DictReader(io.StringIO(text))]


def quest_areas(assign):
    """continent -> { uiMapID: (north, west) }: the middle of each map's quest givers."""
    points = collections.defaultdict(list)
    text = open(DATA, encoding="utf-8").read()
    for m in re.finditer(r"\ba = \{ (\d+), ([\d.]+), ([\d.]+),", text):
        points[int(m[1])].append((float(m[2]) / 100, float(m[3]) / 100))
    out = collections.defaultdict(dict)
    for ui, pts in points.items():
        w = C.world(assign, ui, statistics.median(p[0] for p in pts), statistics.median(p[1] for p in pts))
        if w:
            out[w[0]][ui] = (w[1], w[2])
    return out


def build_graph(m):
    kinds, walk, drop = m["kinds"], m["walk"], m["drop"]
    nr, nc = kinds.shape
    ok = (kinds != "v") & (kinds != "h")
    water = kinds == "w"
    idx = np.arange(nr * nc).reshape(nr, nc)
    src, dst, cost = [], [], []
    for k, (dr, dc) in enumerate(C.DIRS):
        bit = 1 << k
        rs = slice(max(0, -dr), nr - max(0, dr))
        cs = slice(max(0, -dc), nc - max(0, dc))
        rt = slice(max(0, dr), nr - max(0, -dr) if max(0, -dr) else nr)
        ct = slice(max(0, dc), nc - max(0, -dc) if max(0, -dc) else nc)
        step = (((walk[rs, cs] | drop[rs, cs]) & bit) != 0) & ok[rs, cs] & ok[rt, ct]
        src.append(idx[rs, cs][step])
        dst.append(idx[rt, ct][step])
        length = m["cell"] * (2 ** 0.5 if dr and dc else 1)
        cost.append(np.where(water[rt, ct][step], length * SWIM, length))
    for an, aw, bn, bw, yards in m["passages"]:  # a tunnel or a cave: both ways
        a, b = C.square(m, an, aw), C.square(m, bn, bw)
        if a is not None and b is not None:
            src.append(np.array([a, b]))
            dst.append(np.array([b, a]))
            cost.append(np.array([float(yards), float(yards)]))
    return csr_matrix((np.concatenate(cost), (np.concatenate(src), np.concatenate(dst))), shape=(nr * nc, nr * nc))


def main():
    assign = assignments()
    maps = C.load(WATER)
    areas = quest_areas(assign)
    out = {}
    for cont, zones in areas.items():
        if cont not in maps:
            print("continent", cont, "not on the map:", sorted(zones))
            continue
        m = maps[cont]
        m["max"] = m.get("max")
        g = build_graph(m)
        squares = {}
        for ui, (n, w) in zones.items():
            sq = C.square(m, n, w)
            if sq is None:
                print("no square for", ui)
            else:
                squares[ui] = sq
        uis = sorted(squares)
        print("continent", cont, len(uis), "zones", flush=True)
        dist = dijkstra(g, directed=True, indices=[squares[u] for u in uis])
        for i, a in enumerate(uis):
            row = {}
            for b in uis:
                d = dist[i, squares[b]]
                if a != b and np.isfinite(d):
                    row[str(b)] = round(float(d) / YARDS_A_MINUTE, 1)
            out[str(a)] = row
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        json.dump(out, f, indent=0, sort_keys=True)
    print("wrote", len(out), "zones")


if __name__ == "__main__":
    main()
