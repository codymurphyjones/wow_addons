"""Spots on the walkable ground that a point on the map alone doesn't pin down (Data/Spots.lua): the
flight masters, each with its floor's height, and for the ones up a tower, a ramp or stairs, where the
climb up to them starts.

    python -I tools/Waypoint/nav_spots.py [map ...]      (maps with a stitched graph in tools/Waypoint/.nav)

The game tells an addon where a target is on the map, not how high: with floors stacked under it (the
street under Orgrimmar's flight master tower, the terrain under a city), the addon would guess the
ground's and lead you to the foot of the tower as if you'd arrived. Each flight master (TaxiNodes
with a mount: the generic, quest and transport nodes aren't flight masters) keeps the height of its
floor in the stitched graph (nav_stitch.py).

Its entrance: from the flight master's floor, the floors you reach going only down (CLIMB_SLACK of
give, within REACH yards on the map), and the lowest of them is where the climb up starts. A flight
master gets one when that climb is at least RISE yards high and its walk up is at least DETOUR times
the straight line (a spiral round a tower, switchbacks, stairs up a cliff): a plain slope up to it
needs no waypoint of its own. Then the arrow leads to the entrance first, and up from there.
"""
import csv
import heapq
import os
import re
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "_shared"))
import nav_reduce as nr  # noqa: E402

NAV = nr.NAV
ADDON = os.path.join(os.path.dirname(os.path.dirname(HERE)), "addons", "Waypoint")
OUT = os.path.join(ADDON, "Data", "Spots.lua")
SNAP = 40          # yards from a flight master its floor may be
REACH = 40         # yards on the map round a flight master its climb may start
CLIMB_SLACK = 1.0  # yards a way down may rise again and still count as going down
RISE = 8.0         # yards of climb that make an entrance worth a waypoint...
DETOUR = 1.6       # ...when the walk up is this many times the straight line
RETIRED = re.compile(r"^zz|^quest path|^generic\b|\bdnt\b|do not use", re.I)  # "Generic, World target": not one


def flight_masters(mapid, build):
    """[(name, north, west, height)] of the flight masters on this map (TaxiNodes)."""
    import build_water as bw
    out = []
    for r in bw.wago_table("TaxiNodes", build):
        name = r["Name_lang"]
        mounted = int(r["MountCreatureID_0"] or 0) or int(r["MountCreatureID_1"] or 0)
        if int(r["ContinentID"]) == mapid and name and mounted and not RETIRED.search(name):
            out.append((name, float(r["Pos_0"]), float(r["Pos_1"]), float(r["Pos_2"])))
    return out


class Graph:
    """A map's stitched graph (nav_stitch.py): where each node is, and its walking links both ways."""

    def __init__(self, mapid):
        z = np.load(os.path.join(NAV, "%d.graph.npz" % mapid))
        N, L = z["nodes"], z["links"]
        gr, gc = N[:, 0] * 64 + N[:, 2], N[:, 1] * 64 + N[:, 3]
        self.N = N
        self.n = nr.MAX - (gr + N[:, 9] / 255.0) * nr.FINE
        self.w = nr.MAX - (gc + N[:, 10] / 255.0) * nr.FINE
        self.h = N[:, 5] / 10.0
        self.land = N[:, 4] == 0
        walk = L[:, 2] == 0
        a = np.concatenate([L[walk, 0], L[walk, 1]])
        b = np.concatenate([L[walk, 1], L[walk, 0]])
        order = np.argsort(a, kind="stable")
        self.to = b[order]
        self.start = np.searchsorted(a[order], np.arange(len(N) + 1))

    def near(self, i):
        return self.to[self.start[i]:self.start[i + 1]]


def spot(g, name, n, w, z):
    """(height, entrance or None, note on the climb or None) of a flight master at (n, w, z), or None when no floor is near it."""
    d = np.hypot(g.n - n, g.w - w)
    near = np.nonzero((d <= SNAP) & g.land)[0]
    if len(near) == 0:
        return None
    fp = int(near[np.argmin(d[near] + np.abs(g.h[near] - z) * 2)])
    # Down from its floor, only ever going down (a little give), staying near it.
    down = {fp}
    stack = [fp]
    while stack:
        u = stack.pop()
        for v in g.near(u):
            v = int(v)
            if v not in down and d[v] <= REACH and g.land[v] and g.h[v] <= g.h[u] + CLIMB_SLACK:
                down.add(v)
                stack.append(v)
    foot = min(down, key=lambda v: (g.h[v], d[v]))
    rise = g.h[fp] - g.h[foot]
    if rise < RISE:
        return g.h[fp], None, None
    # The walk up from the foot, over those floors.
    dist = {foot: 0.0}
    heap = [(0.0, foot)]
    while heap:
        k, u = heapq.heappop(heap)
        if u == fp:
            break
        if k > dist[u]:
            continue
        for v in g.near(u):
            v = int(v)
            if v in down:
                nk = k + float(np.hypot(g.n[u] - g.n[v], g.w[u] - g.w[v]))
                if nk < dist.get(v, 1e18):
                    dist[v] = nk
                    heapq.heappush(heap, (nk, v))
    straight = float(np.hypot(np.hypot(g.n[foot] - g.n[fp], g.w[foot] - g.w[fp]), rise))
    if fp not in dist or dist[fp] < straight * DETOUR:
        return g.h[fp], None, None
    note = "climb of %.0f yd, %.0f yd up (x%.1f the straight line)" % (rise, dist[fp], dist[fp] / straight)
    print("  %s: %s from (%.0f, %.0f)" % (name, note, g.n[foot], g.w[foot]))
    return g.h[fp], (g.n[foot], g.w[foot], g.h[foot]), note


def lua_string(s):
    return '"%s"' % s.replace("\\", "\\\\").replace('"', '\\"')


def main(argv):
    from casc import Casc
    build = Casc.open().version
    maps = [int(m) for m in argv] or sorted(int(f.split(".")[0]) for f in os.listdir(NAV) if f.endswith(".graph.npz"))
    per_map = {}
    for mapid in maps:
        print("spots on map %d" % mapid)
        g = Graph(mapid)
        rows = []
        for name, n, w, z in flight_masters(mapid, build):
            got = spot(g, name, n, w, z)
            if got:
                rows.append((name, n, w) + got)
            else:
                # Left out: in the game it's found on whatever floor the ground's height picks.
                print("  %s: no walkable floor within %d yd, left out" % (name, SNAP))
        per_map[mapid] = rows
        print("  %d flight masters, %d with an entrance" % (len(rows), sum(1 for r in rows if r[4])))
    lines = [
        "-- GENERATED by tools/Waypoint/nav_spots.py from the game's flight masters and the walkable ground"
        " (nav_*.py). Do not edit.",
        "-- NavSpots[map] = { { kind, name, north, west, height, entrance north, west, height }, ... }:",
        "-- a spot's floor, and where the climb up to it starts (nil: you walk straight up to it).",
        "local _, ns = ...",
        "ns.NavSpots = ns.NavSpots or {}",
    ]
    for mapid in sorted(per_map):
        lines.append("ns.NavSpots[%d] = {" % mapid)
        for name, n, w, h, e, note in per_map[mapid]:
            tail = ", %.1f, %.1f, %.1f" % e if e else ""
            comment = " -- " + note if note else ""
            lines.append('    { "fp", %s, %.1f, %.1f, %.1f%s },%s' % (lua_string(name), n, w, h, tail, comment))
        lines.append("}")
    with open(OUT, "w", encoding="utf-8", newline="") as f:
        f.write("\n".join(lines) + "\n")
    print("wrote", OUT)


if __name__ == "__main__":
    main(sys.argv[1:])
