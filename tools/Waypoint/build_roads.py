"""Packages the roads players logged with RoadLog for Waypoint (Data/Roads.lua), so every Waypoint
user has them, with or without RoadLog.

    python -I tools/Waypoint/build_roads.py        (yarn build --dev runs it)

Reads RoadLog's saved variables (WTF/Account/*/SavedVariables/RoadLog.lua; WOW_WTF overrides the
folder) and cleans the roads the way RoadLog draws them, with RoadLog's own Smooth.lua (lupa):
  * each stretch is cleaned (Smooth.Clean: weaving, out-and-back steps and wobble taken out);
  * the stretches become one network (Smooth.Network): a road walked twice is one line, and the
    loops and side trips it marks faint are left out (they aren't a way anywhere).
Then it's checked against the land map (Data/Water.lua): a road crossing a step the map can't walk
opens that step in Waypoint, so each one is listed for review (a real narrow pass the map's
squares missed, or a recording left on over a cliff); stretches over open water are listed too.
Blockers (walls, fences, cliff edges) and narrow passes are packaged as they were logged.

Output: ns.Roads[continent] = { roads = { { n, w, n, w, ... } }, blockers = { { n, w, ... } },
passes = { { n, w } } }, world yards to a tenth.
"""
import glob
import math
import os
import sys

from lupa import LuaRuntime

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
REPO = os.path.dirname(TOOLS)
ADDON = os.path.join(REPO, "addons", "Waypoint")
SMOOTH = os.path.join(REPO, "addons", "RoadLog", "Smooth.lua")
OUT = os.path.join(ADDON, "Data", "Roads.lua")
WTF = os.environ.get("WOW_WTF") or r"Z:\Games\World of Warcraft\_classic_beta_\WTF"
sys.path.insert(0, HERE)
import check_water as CW  # noqa: E402  (reads Data/Water.lua's squares and links)

CHECK_EVERY = 10  # yards between the points a road is checked at against the land map


def lua_list(t):
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


def lua_dict(t):
    return {k: t[k] for k in t} if t is not None else {}


def read_logs(lua):
    """Every account's RoadLog: { continent: { "roads": [(at, flat)], "blockers": [...], "passes": [(n, w)] } }."""
    out = {}
    files = glob.glob(os.path.join(WTF, "Account", "*", "SavedVariables", "RoadLog.lua"))
    for path in files:
        lua.execute("RoadLogDB = nil")
        lua.execute(open(path, encoding="utf-8").read())
        db = lua.globals().RoadLogDB
        if db is None:
            continue
        for key in ("roads", "blockers"):
            for c, items in lua_dict(db[key]).items():
                for it in lua_list(items):
                    pts = [float(v) for v in lua_list(it["pts"])]
                    if len(pts) >= 4:
                        out.setdefault(int(c), {}).setdefault(key, []).append((it["at"] or 0, pts))
        for c, pins in lua_dict(db["passes"]).items():
            for pin in lua_list(pins):
                if pin["n"] and pin["w"]:
                    out.setdefault(int(c), {}).setdefault("passes", []).append((float(pin["n"]), float(pin["w"])))
    return out, files


def network(lua, stretches):
    """RoadLog's own cleaning: Clean each stretch (oldest first), then Network. Returns
    (kept flat lists, how many faint pieces were left out)."""
    ns = lua.table()
    lua.execute("return function(src, ns) assert(load(src))(nil, ns) end")(open(SMOOTH, encoding="utf-8").read(), ns)
    smooth = ns.Smooth
    cleaned = lua.table()
    for i, (_, pts) in enumerate(sorted(stretches, key=lambda s: s[0]), 1):
        cleaned[i] = smooth.Clean(lua.table(*pts))
    kept, faint = [], 0
    for piece in lua_list(smooth.Network(cleaned)):
        flat = [float(v) for v in lua_list(piece["pts"])]
        if piece["faint"]:
            faint += 1
        elif len(flat) >= 4:
            kept.append(flat)
    return kept, faint


def length(flat):
    return sum(math.hypot(flat[i] - flat[i - 2], flat[i + 1] - flat[i - 1]) for i in range(2, len(flat) - 1, 2))


def review(m, flat):
    """Steps of a road the land map can't walk, and stretches over open water: [(what, n, w)]."""
    found = []
    pts = [(flat[i], flat[i + 1]) for i in range(0, len(flat), 2)]
    dense = [pts[0]]
    for a, b in zip(pts, pts[1:]):
        steps = max(1, int(math.hypot(b[0] - a[0], b[1] - a[1]) // CHECK_EVERY))
        for k in range(1, steps + 1):
            dense.append((a[0] + (b[0] - a[0]) * k / steps, a[1] + (b[1] - a[1]) * k / steps))
    kinds, walk = m["kinds"], m["walk"]
    nr, nc = kinds.shape

    def sq(n, w):
        r = int((m["max"] - n) // m["cell"]) - m["r0"]
        c = int((m["max"] - w) // m["cell"]) - m["c0"]
        return (r, c) if 0 <= r < nr and 0 <= c < nc else None

    prev = sq(*dense[0])
    for n, w in dense[1:]:
        cur = sq(n, w)
        if cur and prev and cur != prev:
            d = (cur[0] - prev[0], cur[1] - prev[1])
            if d in CW.DIRS and not (walk[prev] >> CW.DIRS.index(d)) & 1:
                found.append(("map can't walk this step", n, w))
            if kinds[cur] == "w":
                found.append(("over water", n, w))
        prev = cur or prev
    # neighbouring finds are one place
    out = []
    for f in found:
        if not out or out[-1][0] != f[0] or math.hypot(out[-1][1] - f[1], out[-1][2] - f[2]) > 40:
            out.append(f)
    return out


def fmt(v):
    return ("%.1f" % v).rstrip("0").rstrip(".")


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    logs, files = read_logs(lua)
    print("read %d RoadLog saved variable file(s)" % len(files))
    maps = CW.load(os.path.join(ADDON, "Data", "Water.lua"))
    lines = [
        "-- GENERATED by tools/Waypoint/build_roads.py from the roads players logged with RoadLog. Do not edit.",
        "-- Roads[continent] = { roads = { { north, west, ... } } (cleaned and merged as RoadLog draws them),",
        "-- blockers = { { north, west, ... } } (walls, fences, cliff edges), passes = { { north, west } } }.",
        "local _, ns = ...",
        "ns.Roads = {",
    ]
    for c in sorted(logs):
        got = logs[c]
        roads, faint = network(lua, got.get("roads", []))
        raw = sum(length(p) for _, p in got.get("roads", []))
        print("continent %d: %d stretches (%.0f yd) -> %d roads (%.0f yd), %d loops and side trips left out" % (
            c, len(got.get("roads", [])), raw, len(roads), sum(length(r) for r in roads), faint))
        if c in maps:
            for i, r in enumerate(roads, 1):
                for what, n, w in review(maps[c], r):
                    print("  road %d: %s at %.0f, %.0f" % (i, what, n, w))
        lines.append("    [%d] = {" % c)
        for key, items in (("roads", roads), ("blockers", [p for _, p in got.get("blockers", [])])):
            lines.append("        %s = {" % key)
            for flat in items:
                lines.append("            { %s }," % ", ".join(fmt(v) for v in flat))
            lines.append("        },")
        lines.append("        passes = {")
        for n, w in got.get("passes", []):
            lines.append("            { %s, %s }," % (fmt(n), fmt(w)))
        lines.append("        },")
        lines.append("    },")
        print("  %d blockers, %d narrow passes" % (len(got.get("blockers", [])), len(got.get("passes", []))))
    lines.append("}")
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print("wrote", OUT, "%.0f KB" % (os.path.getsize(OUT) / 1024))


if __name__ == "__main__":
    main()
