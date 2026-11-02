"""Real walking times between zones with quests, over Waypoint's navigation graph.

Straight lines lie: Elwynn Forest and Dun Morogh look a few minutes apart, and there's a mountain
range between them. This walks the map (Waypoint/Data/Water.lua, built from the game's tiles: the
steps you can really take, cliffs you can drop but not climb, tunnels) from each zone's quest area
to the others, taking only the drops that do no damage (a walk that jumps off a mesa isn't a walk).
Zones it can't reach on foot aren't listed.

Writes tools/FieldGuide/data/zone_walks.json: { "from uiMapID": { "to uiMapID": minutes } }, and the
same into addons/FieldGuide/Guides/Data.lua (build_guides.py reads the file on its next run).

    python -I tools/FieldGuide/zone_walks.py
"""
import collections
import csv
import io
import json
import os
import re
import site
import statistics
import sys
import tarfile

sys.path.append(site.getusersitepackages())  # (scipy: build_all.py runs the scripts with -I)

import numpy as np  # noqa: E402
from scipy.sparse import csr_matrix  # noqa: E402
from scipy.sparse.csgraph import dijkstra  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
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


def write_data(out):
    """The table in Data.lua, as build_guides.py writes it."""
    path = os.path.join(ROOT, "addons", "FieldGuide", "Guides", "Data.lua")
    text = open(path, encoding="utf-8").read()
    head = text.index("ns.ZoneWalks = {")
    end = text.index("\n}", head)
    rows = ["    [%s] = { %s }," % (a, ", ".join("[%s] = %s" % (b, out[a][b]) for b in sorted(out[a], key=int)))
            for a in sorted(out, key=int)]
    text = text[:head] + "ns.ZoneWalks = {\n" + "\n".join(rows) + text[end:]
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def main():
    import quest_walks as W
    from scipy.spatial import cKDTree
    assign = assignments()
    areas = quest_areas(assign)
    old = json.load(open(OUT, encoding="utf-8")) if os.path.exists(OUT) else {}
    out = {}
    for cont, zones in areas.items():
        if not os.path.exists(os.path.join(W.NP.NAV, "%d.graph.npz" % cont)):
            print("continent", cont, "not on the graph:", sorted(zones))
            continue
        at, size, g, ground = W.graph(cont)
        ids = np.nonzero(ground)[0]
        tree = cKDTree(at[ground])
        nodes = {}
        for ui, (n, w) in zones.items():
            near = tree.query_ball_point([n, w], 40) or [int(tree.query([n, w])[1])]
            nodes[ui] = int(ids[max(near, key=lambda i: size[ids[i]])])
        uis = sorted(nodes)
        print("continent", cont, len(uis), "zones", flush=True)
        dist = dijkstra(g, directed=True, indices=[nodes[u] for u in uis])
        for i, a in enumerate(uis):
            row = {}
            for b in uis:
                d = dist[i, nodes[b]]
                if a != b and np.isfinite(d):
                    row[str(b)] = round(float(d) / YARDS_A_MINUTE, 1)
            out[str(a)] = row
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        json.dump(out, f, indent=0, sort_keys=True)
    write_data(out)
    changes = sorted(((round(out[a][b] - old[a][b], 1), a, b, old[a][b], out[a][b])
                      for a in out for b in out[a] if a in old and b in old[a]), reverse=True)
    print("wrote", len(out), "zones;", sum(abs(c[0]) >= 1 for c in changes), "of", len(changes),
          "walks changed by a minute or more; biggest:", changes[:4])
    lost = [(a, b) for a in old for b in old[a] if a not in out or b not in out.get(a, {})]
    print(len(lost), "walks no longer found on foot:", lost[:6])


if __name__ == "__main__":
    main()
