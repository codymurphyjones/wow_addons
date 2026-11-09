"""Zone to zone walks for long trips (Data/ZoneWays.lua): every place the ground crosses from one zone
to another, every dock, flight master and town, and the walk between every two of them on the same zone,
once for each road mode. So a trip by boat, zeppelin or flight has its walks ready too, and a trip to a
town needs no search of the world.

The way from one zone to another on foot doesn't change, so it's worked out once, here, and ships with
the addon. In the game a long trip is a chain of these (ZoneWays.lua), there at once, however far it is.

Entrances: the links of the graph (nav_stitch.py) between two zones (Data/Nav<map>.lua's zones, map
chunks rolled up to their top zone), in groups of a pair of zones and a CELL-yard square: a long open
border is several entrances, a mountain pass one. A group's middle link stands for it.

    python -I tools/Waypoint/nav_zones.py [map ...]     (default: both continents)

Intersections: the walks between those stops, laid over each other, are each zone's ways (valleys,
passes, ramps, roads). Where three or more of them branch apart (in JUNCTION_CELL squares, each branch
going on for JUNCTION_BRANCH squares or to a stop) is an intersection, and a stop too (zone, zone,
node), within JUNCTION_REACH yards of the stops it's walked to. So a long trip's last stop is near
where it's going, and the straight stretch from it to the target short.

Out, per map: exits = { { zoneA, zoneB, north, west }, ... }, and for each road mode { costs, ways }:
costs, zlib then base64: "to,seconds,to,seconds,...;" a line for each exit in order, all a route needs
to choose its way. ways[from], the same: "to,n,w,n,w,...;" the walks themselves, unpacked in the game
only for the exits a route goes through. Seconds are at RUN yards a second, points simplified to within
TOLERANCE yards. Exits count from 1.
"""
import base64
import collections
import json
import os
import re
import site
import sys
import time
import zlib

sys.path.append(site.getusersitepackages())  # (scipy: build_all.py runs the scripts with -I)

import numpy as np  # noqa: E402
from scipy.sparse import csr_matrix  # noqa: E402
from scipy.sparse.csgraph import dijkstra  # noqa: E402
from scipy.spatial import cKDTree  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import nav_pack  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
ADDON = os.path.join(ROOT, "addons", "Waypoint")
NAV = os.path.join(HERE, ".nav")
CELL = 400            # yards: one entrance a square, per pair of zones
MIN_LINKS = 4         # links a group needs: fewer is a crack in a wall, not a way through
ROAD_YARDS = 16       # a node this near a road is on it
TOLERANCE = 6         # yards the simplified walk may be off
PLACE_YARDS = 60      # yards from a dock or flight master its floor may be
LIMIT = 900           # seconds on foot: no walk inside one zone is longer (a road mode weighs ground more)
MODES = {"safe": 2.5, "balanced": 1.4, "speed": 1.08}  # Route.lua's ROAD_MODES
JUNCTION_CELL = 60    # yards: the squares the walks are laid over each other in
JUNCTION_BRANCH = 3   # squares each of an intersection's ways has to go on for (or end at a stop)
JUNCTION_MERGE = 150  # yards: intersections this close are one
JUNCTION_CLEAR = 120  # yards from another stop an intersection has to be
JUNCTION_REACH = 1200 # yards: an intersection's walks go to the stops this near (the others' to their whole zone)


def zone_of_nodes(mapid, N):
    """Each node's zone: its place in Nav<map>.lua's zones, 0 none."""
    src = open(os.path.join(ADDON, "Data", "Nav%d.lua" % mapid), encoding="utf-8").read()
    part = src[src.index("zoneOf = {"):src.index("}, areas = {")]
    tiles = {int(t): zlib.decompress(base64.b64decode(b)) for t, b in re.findall(r'\[(\d+)\] = "([^"]+)"', part)}
    tile = N[:, 0] * 64 + N[:, 1]
    chunk = (N[:, 2] // 4) * 16 + (N[:, 3] // 4)  # 64 cells a tile, 16 chunks
    order = np.argsort(tile, kind="stable")
    ids, first = np.unique(tile[order], return_index=True)
    out = np.zeros(len(N), dtype=np.int32)
    for k, t in enumerate(ids):
        raw = tiles.get(int(t))
        if raw:
            rows = order[first[k]:first[k + 1] if k + 1 < len(first) else len(order)]
            out[rows] = np.frombuffer(raw, np.uint8)[chunk[rows]]
    return out


def roads(mapid):
    """The road points of a map, a point every few yards."""
    src = open(os.path.join(ADDON, "Data", "Roads.lua"), encoding="utf-8").read()
    m = re.search(r"\[%d\] = \{\s*roads = \{(.*?)\n\s*\},\s*blockers" % mapid, src, re.S)
    if not m:
        return np.zeros((0, 2))
    pts = []
    for line in re.findall(r"\{ ([-\d., ]+) \}", m.group(1)):
        v = [float(x) for x in line.split(",")]
        p = np.array(v).reshape(-1, 2)
        for a, b in zip(p, p[1:]):
            k = max(1, int(np.hypot(*(b - a)) / 8))
            pts += [a + (b - a) * i / k for i in range(k)]
    return np.array(pts)


def entrances(N, L, usable, zone, pn, pw):
    """[(zone a, zone b, node)]."""
    a, b = L[usable, 0], L[usable, 1]
    za, zb = zone[a], zone[b]
    cross = (za != zb) & (za > 0) & (zb > 0) & (N[a, 4] == 0) & (N[b, 4] == 0)
    groups = collections.defaultdict(list)
    for u, v, x, y in zip(a[cross], b[cross], za[cross], zb[cross]):
        key = (min(x, y), max(x, y), int(pn[u] // CELL), int(pw[u] // CELL))
        groups[key].append(int(u))
    out = []
    for (x, y, _, _), nodes in groups.items():
        if len(nodes) >= MIN_LINKS:
            mn, mw = np.mean(pn[nodes]), np.mean(pw[nodes])
            best = min(nodes, key=lambda i: (pn[i] - mn) ** 2 + (pw[i] - mw) ** 2)
            out.append((int(x), int(y), best))
    return out


def transit(mapid, N, zone, pn, pw):
    """The docks, flight masters and towns (Data/Nav<map>.lua's places): [(zone, zone, node)]."""
    src = open(os.path.join(ADDON, "Data", "Nav%d.lua" % mapid), encoding="utf-8").read()
    found = re.findall(r'\{ "(?:fp|dock|town)", "(?:[^"\\]|\\.)*", (-?[\d.]+), (-?[\d.]+) \}', src)
    land = np.nonzero((N[:, 4] == 0) & (zone > 0))[0]
    tree = cKDTree(np.column_stack([pn[land], pw[land]]))
    out = []
    for n, w in found:
        d, i = tree.query((float(n), float(w)))
        if d <= PLACE_YARDS:
            node = int(land[i])
            out.append((int(zone[node]), int(zone[node]), node))
    return out


def junctions(exits, G, pn, pw, N, zone):
    """The intersections of the walks between the stops: [(zone, zone, node)]."""
    by_zone = collections.defaultdict(set)
    for i, (x, y, _) in enumerate(exits):
        by_zone[x].add(i)
        by_zone[y].add(i)
    adj = collections.defaultdict(set)   # square -> neighbouring squares the walks go to
    node_of = {}                         # square -> a node of a walk in it
    stop_cells = set()
    def cell(u):
        return (int(pn[u] // JUNCTION_CELL), int(pw[u] // JUNCTION_CELL))
    for i, (x, y, node) in enumerate(exits):
        stop_cells.add(cell(node))
        want = (by_zone[x] | by_zone[y]) - {i}
        dist, pred = dijkstra(G, indices=node, return_predecessors=True, limit=LIMIT * MODES["balanced"])
        for j in want:
            to = exits[j][2]
            if not np.isfinite(dist[to]):
                continue
            u, last = to, None
            while u >= 0:
                c = cell(u)
                if c != last:
                    node_of.setdefault(c, u)
                    if last is not None:
                        adj[c].add(last)
                        adj[last].add(c)
                    last = c
                u = int(pred[u])
    def branch_ok(start, first):
        prev, at = start, first
        for _ in range(JUNCTION_BRANCH):
            if at in stop_cells:
                return True
            nxt = [c for c in adj[at] if c != prev]
            if not nxt:
                return False
            prev, at = at, nxt[0]
        return True
    found = []
    for c, ns_ in adj.items():
        if len(ns_) >= 3 and c not in stop_cells:
            if sum(1 for d in ns_ if branch_ok(c, d)) >= 3:
                found.append(node_of[c])
    # One for each place; none on top of a stop already there, nor in water.
    stops = np.array([[pn[n], pw[n]] for _, _, n in exits]) if exits else np.zeros((0, 2))
    tree = cKDTree(stops) if len(stops) else None
    kept = []
    for u in sorted(found, key=lambda u: (pn[u], pw[u])):
        if N[u, 4] != 0 or zone[u] <= 0:
            continue
        if tree is not None and tree.query((pn[u], pw[u]))[0] < JUNCTION_CLEAR:
            continue
        if any((pn[u] - pn[k]) ** 2 + (pw[u] - pw[k]) ** 2 < JUNCTION_MERGE ** 2 for k in kept):
            continue
        kept.append(u)
    return [(int(zone[u]), int(zone[u]), int(u)) for u in kept]


def simplify(pts):
    """Douglas-Peucker, without recursion."""
    keep = [False] * len(pts)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        i, j = stack.pop()
        if j <= i + 1:
            continue
        a, b = pts[i], pts[j]
        dn, dw = b[0] - a[0], b[1] - a[1]
        length = max(1e-6, (dn * dn + dw * dw) ** 0.5)
        far, at = 0, None
        for k in range(i + 1, j):
            d = abs((pts[k][0] - a[0]) * dw - (pts[k][1] - a[1]) * dn) / length
            if d > far:
                far, at = d, k
        if far > TOLERANCE:
            keep[at] = True
            stack += [(i, at), (at, j)]
    return [p for p, k in zip(pts, keep) if k]


def lua_b64(text):
    return base64.b64encode(zlib.compress(text.encode("ascii"), 9)).decode("ascii")


def build(mapid):
    t0 = time.time()
    z = np.load(os.path.join(NAV, "%d.graph.npz" % mapid))
    N, L = z["nodes"].astype(np.int64), z["links"].astype(np.int64)
    LD = np.concatenate([L, nav_pack.diagonals(N, L)])
    walk, swim, usable = nav_pack.edge_costs(N, LD)
    # Lifts, portals and the tram: part of the walk, with their own time (as nav_pack.py's walk_table).
    jumps = LD[:, 2] == 3
    usable = usable | jumps
    fixed = np.where(jumps, LD[:, 3] / 10.0, 0.0)
    _, _, pn, pw, _ = nav_pack.positions(N)
    zone = zone_of_nodes(mapid, N)
    exits = entrances(N, LD, usable, zone, pn, pw)
    gates = len(exits)
    exits += transit(mapid, N, zone, pn, pw)
    print("map %d: %d nodes, %d entrances, %d docks and flight masters (%.0fs)" % (
        mapid, len(N), gates, len(exits) - gates, time.time() - t0), flush=True)
    A, B = LD[usable, 0], LD[usable, 1]
    wv, sv, fv = walk[usable].astype(np.float64), swim[usable].astype(np.float64), fixed[usable]
    # The intersections of the walks between those stops (balanced mode's walks).
    A0, B0 = LD[usable, 0], LD[usable, 1]
    rp = roads(mapid)
    on_road0 = np.zeros(len(N), dtype=bool)
    if len(rp):
        d0, _ = cKDTree(rp).query(np.column_stack([pn, pw]), k=1, distance_upper_bound=ROAD_YARDS)
        on_road0 = np.isfinite(d0)
    w0 = walk[usable].astype(np.float64) * np.where(on_road0[A0] & on_road0[B0], 1, MODES["balanced"])         + swim[usable].astype(np.float64) + fixed[usable] + 0.001
    G0 = csr_matrix((w0, (A0, B0)), shape=(len(N), len(N)))
    first = len(exits)
    exits += junctions(exits, G0, pn, pw, N, zone)
    print("map %d: %d intersections (%.0fs)" % (mapid, len(exits) - first, time.time() - t0), flush=True)
    junction = set(range(first, len(exits)))
    on_road = np.zeros(len(N), dtype=bool)
    if len(rp):
        d, _ = cKDTree(rp).query(np.column_stack([pn, pw]), k=1, distance_upper_bound=ROAD_YARDS)
        on_road = np.isfinite(d)
    road_edge = on_road[A] & on_road[B]
    by_zone = collections.defaultdict(set)
    for i, (x, y, _) in enumerate(exits):
        by_zone[x].add(i)
        by_zone[y].add(i)
    out = {}
    for mode, off in MODES.items():
        weight = wv * np.where(road_edge, 1, off) + sv + fv + 0.001
        G = csr_matrix((weight, (A, B)), shape=(len(N), len(N)))
        costs, ways = [], []
        for i, (x, y, node) in enumerate(exits):
            want = (by_zone[x] | by_zone[y]) - {i}
            # (An intersection's walks: to the stops near it, not its whole zone.)
            want = {j for j in want if not (i in junction or j in junction)
                    or (pn[node] - pn[exits[j][2]]) ** 2 + (pw[node] - pw[exits[j][2]]) ** 2 <= JUNCTION_REACH ** 2}
            dist, pred = dijkstra(G, indices=node, return_predecessors=True, limit=LIMIT * off)
            cost, walk_rows = [], []
            for j in sorted(want):
                to = exits[j][2]
                if not np.isfinite(dist[to]):
                    continue
                pts, u = [], to
                while u >= 0:
                    pts.append((float(pn[u]), float(pw[u])))
                    u = int(pred[u])
                pts.reverse()
                flat = ",".join("%d,%d" % (round(p[0]), round(p[1])) for p in simplify(pts))
                cost.append("%d,%d" % (j + 1, round(dist[to])))
                walk_rows.append("%d,%s" % (j + 1, flat))
            costs.append(",".join(cost))
            ways.append(lua_b64(";".join(walk_rows)))
            if i % 25 == 0:
                print("  %s %d/%d (%.0fs)" % (mode, i, len(exits), time.time() - t0), flush=True)
        out[mode] = (lua_b64(";".join(costs)), ways)
        print("  %s: %.1f KB of costs, %.1f KB of walks (%.0fs)" % (
            mode, len(out[mode][0]) / 1024, sum(len(w) for w in ways) / 1024, time.time() - t0), flush=True)
    rows = ["{ %d, %d, %d, %d }" % (x, y, round(pn[n]), round(pw[n])) for x, y, n in exits]
    return rows, out


def main(argv):
    maps = [int(a) for a in argv] or [1, 0]
    path = os.path.join(ADDON, "Data", "ZoneWays.lua")
    lines = ["-- GENERATED by tools/Waypoint/nav_zones.py from Waypoint's navigation graph. Do not edit.",
             "-- Every zone entrance, and the walk between those on one zone, by road mode (see that script).",
             "local _, ns = ...", "ns.ZoneWayData = {"]
    for mapid in maps:
        rows, modes = build(mapid)
        lines.append("    [%d] = { exits = { %s }," % (mapid, ", ".join(rows)))
        for mode, (costs, ways) in modes.items():
            lines.append('        %s = { costs = "%s", ways = {' % (mode, costs))
            lines.extend('            "%s",' % w for w in ways)
            lines.append("        } },")
        lines.append("    },")
    lines.append("}")
    # The lifts: where each goes from and to, for places only a lift reaches (ZoneWays.lua).
    # { north, west, bottom height, top height, seconds }
    lifts = collections.defaultdict(list)
    for link in json.load(open(os.path.join(NAV, "links.json"), encoding="utf-8")):
        # (Only the mesas': the top of Undercity's is the ground, and it's the bottom that's the place.)
        if link["kind"] == "lift" and link["map"] in maps and "Mesa" in link["name"]:
            a, b = link["a"], link["b"]
            lifts[link["map"]].append("{ %d, %d, %d, %d, %d }" % (
                round(a[0]), round(a[1]), round(min(a[2], b[2])), round(max(a[2], b[2])), round(link["secs"])))
    lines.append("ns.ZoneLifts = {")
    for mapid, rows in lifts.items():
        lines.append("    [%d] = { %s }," % (mapid, ", ".join(rows)))
    lines.append("}")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print(path, "%.1f MB" % (os.path.getsize(path) / 1048576))


if __name__ == "__main__":
    main(sys.argv[1:])
