"""Checks Waypoint's land and water map (Data/Water.lua, from build_water.py) against places you can
and can't walk between, so the map can be made stricter without cutting off real paths.

    python -I tools/Waypoint/check_water.py [baseline Water.lua]

Steps are taken the way Grid.lua takes them: a walk link, or a drop link (down a cliff), never onto
lava or off the map; water squares are swum; a passage (a tunnel or a cave) joins its two mouths.
Two places are "together" when each can be reached from the other.

  * Towns (Data/Towns.lua): with a baseline map, every two towns that were together on the baseline
    must still be together. Without one, it lists which towns end up apart.
  * MUST_NOT: climbs you can't make in the game. The top may well be reachable the long way round
    (a ramp elsewhere), so this fails when the walk there is under DETOUR times as long as the
    straight line.

Map coordinates become world coordinates through UiMapAssignment (wago.tools, cached in
tools/Waypoint/.cache; `yarn data:unpack` first). Exits with 1 when anything fails.
"""
import os
import re
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
ADDON = os.path.join(os.path.dirname(TOOLS), "addons", "Waypoint")
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(TOOLS, "_shared"))
import build_water as B  # noqa: E402

BUILD = "1.60.1.70450"
DIRS = B.DIRS

DETOUR = 5
# Climbs the game won't let you make: (what, from (uiMapID, x, y), to (uiMapID, x, y) or world (continent, n, w)).
MUST_NOT = [
    ("Un'Goro north wall, up to the rim", (1449, 0.429, 0.088), (1, -6181, -385)),
    ("Tanaris behind Zul'Farrak, north over the rim", (1446, 0.34, 0.05), (1446, 0.32, 0.005)),
]


def load(path):
    """continent -> { r0, c0, kinds (2D chars), walk, drop (2D uint8) }"""
    text = open(path, encoding="utf-8").read()
    cell = float(re.search(r"cell = ([\d.]+)", text).group(1))
    mx = float(re.search(r"max = ([\d.]+)", text).group(1))
    out = {}
    # Passages (tunnels and caves) come after the maps: { north, west, north, west, yards, name }.
    passages = {}
    tail = text.find("}, passages = {")
    if tail >= 0:
        for m in re.finditer(r"\[(\d+)\] = \{(.*?)\n    \}", text[tail:], re.S):
            passages[int(m.group(1))] = [tuple(float(v) for v in p) for p in
                                         re.findall(r"\{ ([-\d.]+), ([-\d.]+), ([-\d.]+), ([-\d.]+), (\d+),", m.group(2))]
        text = text[:tail]
    for m in re.finditer(r"\n    \[(\d+)\] = \{", text):
        cont = int(m.group(1))
        end = text.index("\n    },\n", m.end())
        blk = text[m.end():end]
        r0, c0 = map(int, re.search(r"r0 = (\d+), c0 = (\d+)", blk).groups())
        rows = re.findall(r'"([^"]*)"', blk[:blk.index("heights")])
        end_links = blk.find("bends", blk.index("links"))  # bends (newer maps) come after the links
        links = re.findall(r'"([^"]*)"', blk[blk.index("links"):end_links if end_links >= 0 else None])
        kinds = np.array([list(re.sub(r"(\d+)(\D)", lambda x: x.group(2) * int(x.group(1)), r)) for r in rows])
        val = []
        for r in links:
            row = []
            for n, tok in re.findall(r"(\d*)(\D\D\D)", r):
                v = (B.LINK_CHARS.index(tok[0]) << 12) | (B.LINK_CHARS.index(tok[1]) << 6) | B.LINK_CHARS.index(tok[2])
                row += [v] * (int(n) if n else 1)
            val.append(row)
        val = np.array(val, dtype=np.int64)
        out[cont] = {"r0": r0, "c0": c0, "kinds": kinds, "walk": val & 255, "drop": val >> 8, "cell": cell, "max": mx,
                     "passages": passages.get(cont, [])}
    return out


def graph(m):
    """Directed steps between usable squares, and their strongly connected groups."""
    kinds, walk, drop = m["kinds"], m["walk"], m["drop"]
    nr, nc = kinds.shape
    ok = (kinds != "v") & (kinds != "h")
    src, dst = [], []
    idx = np.arange(nr * nc).reshape(nr, nc)
    for k, (dr, dc) in enumerate(DIRS):
        bit = 1 << k
        rs = slice(max(0, -dr), nr - max(0, dr))
        cs = slice(max(0, -dc), nc - max(0, dc))
        rt = slice(max(0, dr), nr - max(0, -dr) if max(0, -dr) else nr)
        ct = slice(max(0, dc), nc - max(0, -dc) if max(0, -dc) else nc)
        step = (((walk[rs, cs] | drop[rs, cs]) & bit) != 0) & ok[rs, cs] & ok[rt, ct]
        src.append(idx[rs, cs][step])
        dst.append(idx[rt, ct][step])
    src, dst = np.concatenate(src).tolist(), np.concatenate(dst).tolist()
    n = nr * nc
    fwd, back = [[] for _ in range(n)], [[] for _ in range(n)]
    for a, b in zip(src, dst):
        fwd[a].append(b)
        back[b].append(a)
    for an, aw, bn, bw, _ in m["passages"]:              # a tunnel or a cave: both ways
        a, b = square(m, an, aw), square(m, bn, bw)
        if a is not None and b is not None:
            fwd[a].append(b)
            back[b].append(a)
            fwd[b].append(a)
            back[a].append(b)
    return fwd, strong_groups(fwd, back, n)


def steps(adj, start, goal):
    """The fewest steps from start to goal, or None."""
    dist, todo = {start: 0}, [start]
    while todo:
        nxt = []
        for a in todo:
            if a == goal:
                return dist[a]
            for b in adj[a]:
                if b not in dist:
                    dist[b] = dist[a] + 1
                    nxt.append(b)
        todo = nxt
    return None


def strong_groups(fwd, back, n):
    """Kosaraju: each square's group, squares in one group reach each other."""
    order, seen = [], [False] * n
    for s in range(n):
        if seen[s] or not fwd[s] and not back[s]:
            continue
        seen[s] = True
        stack = [(s, 0)]
        while stack:
            v, i = stack[-1]
            if i < len(fwd[v]):
                stack[-1] = (v, i + 1)
                w = fwd[v][i]
                if not seen[w]:
                    seen[w] = True
                    stack.append((w, 0))
            else:
                stack.pop()
                order.append(v)
    label = [-1] * n
    for s in reversed(order):
        if label[s] != -1:
            continue
        label[s] = s
        todo = [s]
        while todo:
            for w in back[todo.pop()]:
                if label[w] == -1:
                    label[w] = s
                    todo.append(w)
    return label


def world(assign, ui, x, y):
    for r in assign:
        if r["UiMapID"] == str(ui) and r["OrderIndex"] == "0":
            x0, y0 = float(r["UiMin_0"]), float(r["UiMin_1"])
            x1, y1 = float(r["UiMax_0"]), float(r["UiMax_1"])
            fx, fy = (x - x0) / (x1 - x0), (y - y0) / (y1 - y0)
            minx, miny, maxx, maxy = (float(r["Region_%d" % i]) for i in (0, 1, 3, 4))
            return int(r["MapID"]), maxx - fy * (maxx - minx), maxy - fx * (maxy - miny)
    return None


def square(m, n, w):
    """The usable square at a world point, or the nearest one within two squares."""
    r = int((m["max"] - n) // m["cell"]) - m["r0"]
    c = int((m["max"] - w) // m["cell"]) - m["c0"]
    kinds = m["kinds"]
    nr, nc = kinds.shape
    for ring in range(3):
        for dr in range(-ring, ring + 1):
            for dc in range(-ring, ring + 1):
                rr, cc = r + dr, c + dc
                if 0 <= rr < nr and 0 <= cc < nc and kinds[rr, cc] == "l":
                    return rr * nc + cc
    return None


def towns():
    text = open(os.path.join(ADDON, "Data", "Towns.lua"), encoding="utf-8").read()
    return [(m.group(1), int(m.group(2)), float(m.group(3)), float(m.group(4)))
            for m in re.finditer(r'\{ "((?:[^"\\]|\\.)*)", (\d+), ([\d.]+), ([\d.]+),', text)]


def town_groups(maps, assign):
    """continent -> { town name: group label }"""
    out = {}
    for cont, m in maps.items():
        m["g"], m["labels"] = graph(m)
    for name, ui, x, y in towns():
        pos = world(assign, ui, x, y)
        if not pos or pos[0] not in maps:
            continue
        m = maps[pos[0]]
        sq = square(m, pos[1], pos[2])
        if sq is not None:
            out.setdefault(pos[0], {})["%s (%d)" % (name, ui)] = m["labels"][sq]
    return out


def main():
    assign = B.wago_table("UiMapAssignment", BUILD)
    maps = load(os.environ.get("WATER_IN") or os.path.join(ADDON, "Data", "Water.lua"))
    now = town_groups(maps, assign)
    failed = 0

    for what, a, b in MUST_NOT:
        ca, na, wa = world(assign, *a)
        cb, nb, wb = b if len(b) == 3 and isinstance(b[0], int) and b[0] < 10 else world(assign, *b)
        m = maps[ca]
        sa, sb = square(m, na, wa), square(m, nb, wb)
        nc = m["kinds"].shape[1]
        straight = max(abs(sa // nc - sb // nc), abs(sa % nc - sb % nc))
        took = steps(m["g"], sa, sb)
        if took is not None and took < DETOUR * straight:
            failed += 1
            print("FAIL  can still climb: %s (%d squares, straight line %d)" % (what, took, straight))
        else:
            print("ok    no short way: %s (%s squares, straight line %d)" % (what, took, straight))

    if len(sys.argv) > 1:
        base = town_groups(load(sys.argv[1]), assign)
        split = 0
        for cont, groups in base.items():
            byg = {}
            for t, g in groups.items():
                byg.setdefault(g, []).append(t)
            for members in byg.values():
                if len(members) < 2:
                    continue
                parts = {}
                for t in members:
                    parts.setdefault(now.get(cont, {}).get(t), []).append(t)
                if len(parts) > 1:
                    pieces = sorted(parts.values(), key=len, reverse=True)
                    for p in pieces[1:]:
                        split += len(p)
                        print("FAIL  cut off from %s: %s" % (pieces[0][0], ", ".join(p)))
        failed += split
        print("%d town(s) cut off compared with the baseline" % split)
    else:
        for cont, groups in now.items():
            sizes = {}
            for g in groups.values():
                sizes[g] = sizes.get(g, 0) + 1
            print("continent %d: %d towns in %d groups (largest %d)" % (cont, len(groups), len(sizes), max(sizes.values())))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
