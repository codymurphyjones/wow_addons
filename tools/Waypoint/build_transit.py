"""Builds Waypoint's travel data from the game's tables (Data/Transit.lua): flights, boat and
zeppelin timetables, and teleports.

    python -I tools/Waypoint/build_transit.py

Flights (TaxiNodes, TaxiPath, TaxiPathNode; wago.tools for the installed build): every flight
point (where it is), and every hop between two of them with its route through the air (thinned to
THIN yards) and its time. A hop's time is fitted to the flights you've timed (Waypoint's saved
db.taxi.times, any account): seconds = a * yards + b * hops + c over the shortest way through the
network; without enough timed flights, yards / FLIGHT_SPEED + HOP_SECS. Route.lua plans a flight hop
by hop through flight points you know, and draws it along these routes.

Boats and zeppelins (CMaNGOS: transports and their gameobject's taxi path; TaxiPathNode): each
route's loop, period (milliseconds, exact) and stops (path nodes flagged 2, with their wait). The
boat's place in the loop over time is laid out by distance: the moving time (period less the waits)
spread over each stretch's length; crossing between continents takes none. Each stop gets the
dock (Data/Transports.lua) within DOCK_REACH yards of it. Waypoint learns where in its loop a boat
is from the rides you take; with that, the wait at a dock is exact.

Teleports (spell_target_position): where each mage teleport and Teleport: Moonglade lands, for the
spells this client has (SpellName); Astral Recall, the shaman's second hearthstone.

Every point is also given as zone coordinates (the smallest map that holds it, UiMapAssignment).
"""
import csv
import gzip
import math
import os
import re
import sys
from collections import defaultdict

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(TOOLS, "_shared"))
import build_water as bw  # noqa: E402
import sqldump  # noqa: E402
import fetcher as fetching  # noqa: E402
import paths  # noqa: E402

ADDON = os.path.join(os.path.dirname(TOOLS), "addons", "Waypoint")
OUT = os.path.join(ADDON, "Data", "Transit.lua")
CACHE = os.path.join(HERE, ".cache")
DUMP_CACHE = os.path.join(TOOLS, "Spyglass", ".wowhead_cache")
THIN = 15            # yards a flight's drawn route may stray from its path
FLIGHT_SPEED = 32    # yards a second in the air, without timed flights to go by
HOP_SECS = 8         # seconds a hop adds (slowing down over a flight point), likewise
DOCK_REACH = 200     # yards from a boat's stop its dock may be
ASTRAL_RECALL = 556
MOONGLADE = 18960
TELEPORT_CITIES = {3561: "Stormwind City", 3562: "Ironforge", 3565: "Darnassus", 3567: "Orgrimmar",
                   3563: "Undercity", 3566: "Thunder Bluff", MOONGLADE: "Moonglade"}
RETIRED = re.compile(r"^zz|\bdnt\b|do not use", re.I)


def zone_of():
    """world (continent, north, west) -> (uiMapID, x, y): the smallest map holding it."""
    path = sorted(p for p in os.listdir(CACHE) if p.startswith("UiMapAssignment"))[-1]
    rows = []
    with open(os.path.join(CACHE, path), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if r["OrderIndex"] == "0":
                rows.append(r)

    def conv(c, n, w):
        best = None
        for r in rows:
            if int(r["MapID"]) != c:
                continue
            minx, miny, maxx, maxy = (float(r["Region_%d" % i]) for i in (0, 1, 3, 4))
            if not (minx <= n <= maxx and miny <= w <= maxy) or maxx <= minx or maxy <= miny:
                continue
            area = (maxx - minx) * (maxy - miny)
            if best and area >= best[0]:
                continue
            fy, fx = (maxx - n) / (maxx - minx), (maxy - w) / (maxy - miny)
            x0, y0, x1, y1 = (float(r[k]) for k in ("UiMin_0", "UiMin_1", "UiMax_0", "UiMax_1"))
            best = (area, int(r["UiMapID"]), x0 + fx * (x1 - x0), y0 + fy * (y1 - y0))
        return best[1:] if best else None
    return conv


def thin(points, tol):
    """Douglas-Peucker on [(n, w)]."""
    if len(points) <= 2:
        return points
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        i, j = stack.pop()
        (an, aw), (bn, bw_) = points[i], points[j]
        dn, dw = bn - an, bw_ - aw
        ln = math.hypot(dn, dw) or 1e-9
        best, bi = tol, None
        for k in range(i + 1, j):
            pn, pw = points[k]
            d = abs((pn - an) * dw - (pw - aw) * dn) / ln
            if d > best:
                best, bi = d, k
        if bi is not None:
            keep[bi] = True
            stack += [(i, bi), (bi, j)]
    return [p for p, k in zip(points, keep) if k]


def timed_flights():
    """{ "A>B": seconds } from every account's saved Waypoint data."""
    import savedvars
    from lupa import lua51
    out = {}
    for path in savedvars.files("Waypoint"):
        db = savedvars.load(path, "WaypointDB", lua=lua51.LuaRuntime(), errors="replace")
        taxi = db and db.taxi
        for k, v in ((taxi and taxi.times) or {}).items():
            out[str(k)] = float(v)
    return out


def main():
    from casc import Casc
    build = Casc.open().version
    conv = zone_of()
    names = {int(r["ID"]): r["Name_lang"] for r in bw.wago_table("SpellName", build)}
    nodes = {}
    for r in bw.wago_table("TaxiNodes", build):
        name = r["Name_lang"]
        pos = (float(r["Pos_0"]), float(r["Pos_1"]))
        # (the boats' and zeppelins' own taxi nodes are "Transport, ..." at 0, 0: not flight points)
        if name and not RETIRED.search(name) and int(r["ContinentID"]) in bw.MAPS and pos != (0.0, 0.0)                 and not name.startswith("Transport"):
            nodes[int(r["ID"])] = (name, int(r["ContinentID"]), float(r["Pos_0"]), float(r["Pos_1"]))
    pts = defaultdict(list)
    for r in bw.wago_table("TaxiPathNode", build):
        pts[int(r["PathID"])].append((int(r["NodeIndex"]), int(r["ContinentID"]), float(r["Loc_0"]), float(r["Loc_1"]),
                                      int(r["Flags"]), int(r["Delay"])))
    for v in pts.values():
        v.sort()
    hops = []
    for r in bw.wago_table("TaxiPath", build):
        a, b, pid = int(r["FromTaxiNode"]), int(r["ToTaxiNode"]), int(r["ID"])
        if a in nodes and b in nodes and pid in pts and nodes[a][1] == nodes[b][1]:
            line = [(p[2], p[3]) for p in pts[pid] if p[1] == nodes[a][1]]
            length = sum(math.hypot(line[i][0] - line[i - 1][0], line[i][1] - line[i - 1][1]) for i in range(1, len(line)))
            hops.append((a, b, length, thin(line, THIN)))
    # Fit the time to the flights you've timed.
    by_name = {v[0]: k for k, v in nodes.items()}
    graph = defaultdict(list)
    for a, b, length, _ in hops:
        graph[a].append((b, length))
    import heapq

    def shortest(a, b):
        dist, pq = {a: (0.0, 0)}, [(0.0, 0, a)]
        while pq:
            d, h, u = heapq.heappop(pq)
            if u == b:
                return d, h
            if d > dist[u][0]:
                continue
            for v, ln in graph[u]:
                if d + ln < dist.get(v, (math.inf,))[0]:
                    dist[v] = (d + ln, h + 1)
                    heapq.heappush(pq, (d + ln, h + 1, v))
        return None
    X, Y = [], []
    for key, secs in timed_flights().items():
        a, _, b = key.partition(">")
        if a in by_name and b in by_name:
            s = shortest(by_name[a], by_name[b])
            if s:
                X.append([s[0], s[1], 1.0])
                Y.append(secs)
    if len(X) >= 6:
        coef = np.linalg.lstsq(np.array(X), np.array(Y), rcond=None)[0]
        per_yard, per_hop, base = float(coef[0]), max(0.0, float(coef[1])), float(coef[2])
        if per_yard <= 0:
            per_yard, per_hop, base = 1 / FLIGHT_SPEED, HOP_SECS, 0.0
        err = np.abs(np.array(X) @ np.array([per_yard, per_hop, base]) - np.array(Y))
        print("flight times fitted to %d timed flights: %.1f yd/s, %.1f s a hop, %.1f s; mean error %.1f s" % (
            len(X), 1 / per_yard, per_hop, base, err.mean()))
    else:
        per_yard, per_hop, base = 1 / FLIGHT_SPEED, HOP_SECS, 0.0
        print("only %d timed flights: %d yd/s, %d s a hop" % (len(X), FLIGHT_SPEED, HOP_SECS))

    # Boats and zeppelins.
    text = sqldump.cmangos(fetching.Fetcher(DUMP_CACHE, pace=0))
    period = {int(r[0]): (r[1], int(r[2])) for r in sqldump.sql_rows(text, "transports")}
    templates = {int(g["entry"]): g for g in sqldump.rows_of(text, "gameobject_template")}
    docks = []
    src = open(os.path.join(ADDON, "Data", "Transports.lua"), encoding="utf-8").read()
    import nav_places
    wconv = nav_places.assignments()
    for key, ui, x, y in re.findall(r'key = "([^"]+)",[^\n]*?mapID = (\d+),\s*x = ([\d.]+),\s*y = ([\d.]+)', src):
        w = wconv(int(ui), float(x) / 100, float(y) / 100)
        if w:
            docks.append((key, w[0], w[1], w[2]))
    boats = []
    for entry, (name, ms) in period.items():
        g = templates.get(entry)
        pid = g and int(g["data0"] or 0)
        path = pts.get(pid)
        if not path or str(g["type"]) != "15":
            continue
        # Each node's time from the loop's start: moving time spread by distance (none between continents).
        waits = sum(p[5] for p in path if p[4] & 2)
        dists = [0.0]
        for i in range(1, len(path)):
            same = path[i][1] == path[i - 1][1]
            dists.append(math.hypot(path[i][2] - path[i - 1][2], path[i][3] - path[i - 1][3]) if same else 0.0)
        total = sum(dists) or 1
        moving = ms / 1000 - waits
        t, stops = 0.0, []
        for i, p in enumerate(path):
            t += dists[i] / total * moving
            if p[4] & 2:
                near = [d for d in docks if d[1] == p[1] and math.hypot(d[2] - p[2], d[3] - p[3]) <= DOCK_REACH]
                stops.append({"c": p[1], "n": p[2], "w": p[3], "arrive": round(t, 1), "depart": round(t + p[5], 1),
                              "docks": [d[0] for d in near]})
                t += p[5]
        # A dock is "place:dest": it's this boat's only if another stop is at its dest's dock (the
        # zeppelin towers' two platforms stand side by side, each for its own route).
        for s in stops:
            others = {k.split(":")[1] for o in stops if o is not s for k in o["docks"]}
            s["docks"] = [k for k in s["docks"] if k.split(":")[2] in others]
        boats.append({"entry": entry, "name": name, "period": ms / 1000, "stops": stops})
        print("boat %-45s %5.0f s loop, stops: %s" % (name, ms / 1000, "; ".join(
            "%s at %.0f-%.0f" % (",".join(s["docks"]) or "no dock", s["arrive"], s["depart"]) for s in stops)))

    # Teleports.
    tele = {int(r[0]): r for r in sqldump.sql_rows(text, "spell_target_position")}
    ports = []
    for sid, city in sorted(TELEPORT_CITIES.items()):
        r = tele.get(sid)
        if sid in names and r and int(r[1]) in bw.MAPS:
            ports.append((sid, city, int(r[1]), float(r[2]), float(r[3])))

    def zone(c, n, w):
        z = conv(c, n, w)
        return z if z else (0, 0, 0)
    lines = ["-- GENERATED by tools/Waypoint/build_transit.py from the game's tables (%s) and CMaNGOS. Do not edit." % build,
             "-- See build_transit.py. Points: continent, north, west (world yards), then uiMapID, x, y (0-1).",
             "local _, ns = ...",
             "ns.Transit = {",
             "    flight = { perYard = %.6f, perHop = %.2f, base = %.2f }," % (per_yard, per_hop, base),
             "    -- flight points: name -> point",
             "    nodes = {"]
    for k, (name, c, n, w) in sorted(nodes.items(), key=lambda kv: kv[1][0]):
        m, x, y = zone(c, n, w)
        lines.append('        ["%s"] = { %d, %.1f, %.1f, %d, %.4f, %.4f },' % (name.replace('"', '\\"'), c, n, w, m, x, y))
    lines.append("    },")
    lines.append("    -- hops: { from, to, yards, route { north, west, ... } }")
    lines.append("    hops = {")
    for a, b, length, line in hops:
        flat = ", ".join("%.0f, %.0f" % p for p in line)
        lines.append('        { "%s", "%s", %.0f, { %s } },' % (nodes[a][0].replace('"', '\\"'), nodes[b][0].replace('"', '\\"'), length, flat))
    lines.append("    },")
    lines.append("    -- boats: { name, period (seconds), stops = { { continent, north, west, arrive, depart, docks = { key, ... } } } }")
    lines.append("    boats = {")
    for bt in boats:
        lines.append('        { name = "%s", period = %.3f, stops = {' % (bt["name"].replace('"', '\\"'), bt["period"]))
        for s in bt["stops"]:
            lines.append('            { %d, %.1f, %.1f, %.1f, %.1f, docks = { %s } },' % (
                s["c"], s["n"], s["w"], s["arrive"], s["depart"], ", ".join('"%s"' % d for d in s["docks"])))
        lines.append("        } },")
    lines.append("    },")
    lines.append("    -- teleports: spell -> { city, point }")
    lines.append("    teleports = {")
    for sid, city, c, n, w in ports:
        m, x, y = zone(c, n, w)
        lines.append('        [%d] = { "%s", %d, %.1f, %.1f, %d, %.4f, %.4f }, -- %s' % (sid, city, c, n, w, m, x, y, names[sid]))
    lines.append("    },")
    lines.append("    astralRecall = %s," % (ASTRAL_RECALL if ASTRAL_RECALL in names else "nil"))
    lines.append("}")
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print("%d flight points, %d hops, %d boats, %d teleports -> %s" % (len(nodes), len(hops), len(boats), len(ports), OUT))


if __name__ == "__main__":
    main()
