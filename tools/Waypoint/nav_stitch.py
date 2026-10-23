"""Joins a map's reduced tiles (nav_reduce.py) into one graph and keeps only the ground players can
get to.

    python -I tools/Waypoint/nav_stitch.py <map> [...]

Links into another tile land on the node of that tile's cell whose floors span the link's height
(within MATCH yards), nearest to where it lands.
Reachable: from SEEDS, the places players are known to stand (RoadLog's roads, towns, and the NPCs,
mailboxes and objects in Data/Places.lua), every node you can walk, swim or drop to. A seed point has
no height: it seeds the biggest node of its cell (the open ground, not a cellar under it), and the
others only when they're as big (a map with no known places: its largest stretches of ground).
Everything else (the terrain under a city's streets, a sealed
cave, a peak you can't climb) goes.
Nodes under MIN_SIZE Recast cells go too (clutter you'd hop onto).
Frequented floors: the ones creatures and objects stand on (CMaNGOS spawns, with their heights) and
a cell or two round them; where floors are stacked, the game's first guess at yours.
Out: <map>.graph.npz in tools/Waypoint/.nav: nodes (tile row, tile col, cell row, cell col, kind,
height, low, high, size, offsets, frequented) and links (from, to, kind, fall), with node ids renumbered over the kept ones.
"""
import os
import re
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import nav_reduce as nr  # noqa: E402

NAV = nr.NAV
ADDON = os.path.join(os.path.dirname(os.path.dirname(HERE)), "addons", "Waypoint")
MATCH = 1.5   # yards a link's height may miss its node's floors by
MIN_SIZE = 8  # Recast cells (a quarter square yard each) a node needs to be kept: smaller are clutter
              # (a crate's top, a rock's tip), unless it's water


def load_tiles(mapid):
    tiles = {}
    for name in os.listdir(NAV):
        if name.endswith(".npz") and name.startswith("%d_" % mapid) and name.count("_") == 2:
            _, ty, tx = (int(v) for v in name[:-4].split("_"))
            z = np.load(os.path.join(NAV, name))
            tiles[(ty, tx)] = (z["nodes"], z["links"])
    return tiles


def stitch(tiles):
    keys = sorted(tiles)
    base, total = {}, 0
    for k in keys:
        base[k] = total
        total += len(tiles[k][0])
    N = np.zeros((total, 11), dtype=np.int64)   # ty, tx, r, c, kind, h, lo, hi, size, ofn, ofw
    for k in keys:
        nodes = tiles[k][0]
        b = base[k]
        N[b:b + len(nodes), 0], N[b:b + len(nodes), 1] = k
        N[b:b + len(nodes), 2:] = nodes
    # Per tile: its nodes sorted by cell, to find a cell's nodes.
    cellkey = (N[:, 0] * 64 + N[:, 2]) * 4096 + N[:, 1] * 64 + N[:, 3]
    order = np.argsort(cellkey, kind="stable")
    sorted_keys = cellkey[order]
    A, B, K, F = [], [], [], []
    unmatched = 0
    for k in keys:
        links = tiles[k][1]
        if len(links) == 0:
            continue
        b = base[k]
        frm = links[:, 0] + b
        to = np.where(links[:, 8] >= 0, links[:, 8] + b, -1)
        # Into another tile: the node of that cell whose floors hold the link's height, nearest.
        other = to < 0
        if other.any():
            l = links[other]
            ty, tx = k[0] + l[:, 1], k[1] + l[:, 2]
            ck = (ty * 64 + l[:, 3]) * 4096 + tx * 64 + l[:, 4]
            lo_i = np.searchsorted(sorted_keys, ck, "left")
            hi_i = np.searchsorted(sorted_keys, ck, "right")
            best = np.full(len(l), -1, dtype=np.int64)
            bestd = np.full(len(l), np.inf)
            # Where the link lands, in cell units from the cell's corner.
            ln = l[:, 9] / 10 / nr.FINE - (ty * 64 + l[:, 3])
            lw = l[:, 10] / 10 / nr.FINE - (tx * 64 + l[:, 4])
            for step in range(int((hi_i - lo_i).max()) if len(l) else 0):
                has = lo_i + step < hi_i
                cand = np.where(has, order[np.minimum(lo_i + step, len(order) - 1)], 0)
                h = l[:, 5]
                miss = np.maximum(0, np.maximum(N[cand, 6] - h, h - N[cand, 7])) / 10
                water = (N[cand, 4] == 1)
                miss = np.where(water, np.abs(N[cand, 5] - h) / 10, miss)
                d = np.hypot(N[cand, 9] / 255 - ln, N[cand, 10] / 255 - lw) * 0.01 + miss
                ok = has & (miss <= MATCH) & (d < bestd)
                best[ok], bestd[ok] = cand[ok], d[ok]
            to[other] = best
            unmatched += int((best < 0).sum())
        m = to >= 0
        A.append(frm[m]); B.append(to[m]); K.append(links[m, 6]); F.append(links[m, 7])
    A, B, K, F = (np.concatenate(x) for x in (A, B, K, F))
    keep = A != B
    return N, A[keep], B[keep], K[keep], F[keep], unmatched


def world_of_map(assign_rows):
    def conv(ui, x, y):
        for r in assign_rows.get(ui, []):
            x0, y0, x1, y1 = (float(r[k]) for k in ("UiMin_0", "UiMin_1", "UiMax_0", "UiMax_1"))
            if x0 <= x <= x1 and y0 <= y <= y1:
                fx, fy = (x - x0) / (x1 - x0), (y - y0) / (y1 - y0)
                minx, miny, maxx, maxy = (float(r["Region_%d" % i]) for i in (0, 1, 3, 4))
                return int(r["MapID"]), maxx - fy * (maxx - minx), maxy - fx * (maxy - miny)
        return None
    return conv


def seeds(mapid):
    """World points (north, west) on this map players are known to stand at."""
    import csv
    pts = []
    roads = open(os.path.join(ADDON, "Data", "Roads.lua"), encoding="utf-8").read()
    m = re.search(r"\[%d\] = \{\s*roads = \{(.*?)\n        \}," % mapid, roads, re.S)
    if m:
        for line in re.findall(r"\{ ([-\d., ]+) \}", m.group(1)):
            v = [float(x) for x in line.split(",")]
            pts += list(zip(v[0::2], v[1::2]))
    assign = {}
    path = [p for p in os.listdir(os.path.join(HERE, ".cache")) if p.startswith("UiMapAssignment")]
    with open(os.path.join(HERE, ".cache", sorted(path)[-1]), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if r["OrderIndex"] == "0":
                assign.setdefault(int(r["UiMapID"]), []).append(r)
    conv = world_of_map(assign)
    spots = []
    places = open(os.path.join(ADDON, "Data", "Places.lua"), encoding="utf-8").read()
    for s in re.findall(r'"((?:\d+,[\d.]+,[\d.]+;?)+)" \}', places):
        for one in s.split(";"):
            ui, x, y = one.split(",")
            spots.append((int(ui), float(x), float(y)))
    towns = open(os.path.join(ADDON, "Data", "Towns.lua"), encoding="utf-8").read()
    for ui, x, y in re.findall(r'\{ "(?:[^"\\]|\\.)*", (\d+), ([\d.]+), ([\d.]+),', towns):
        spots.append((int(ui), float(x), float(y)))
    for ui, x, y in spots:
        w = conv(ui, x, y)
        if w and w[0] == mapid:
            pts.append((w[1], w[2]))
    return pts


def prune(N, A, B, K, mapid):
    """Nodes reachable from the seeds."""
    n = len(N)
    cellkey = ((N[:, 0] * 64 + N[:, 2]) * 4096 + N[:, 1] * 64 + N[:, 3])
    pts = seeds(mapid)
    start = np.zeros(n, dtype=bool)
    if pts:
        P = np.array(pts)
        gr = np.floor((nr.MAX - P[:, 0]) / nr.FINE).astype(np.int64)
        gc = np.floor((nr.MAX - P[:, 1]) / nr.FINE).astype(np.int64)
        want = np.unique(gr * 4096 + gc)
        # Each wanted cell: its biggest land node, and any as big.
        ins = np.isin(cellkey, want) & (N[:, 4] != 2)
        idx = np.nonzero(ins)[0]
        order = np.lexsort((-N[idx, 8], cellkey[idx]))
        idx = idx[order]
        first = np.ones(len(idx), dtype=bool)
        first[1:] = cellkey[idx[1:]] != cellkey[idx[:-1]]
        biggest = np.zeros(n, dtype=np.int64)
        grp = np.cumsum(first) - 1
        big = N[idx[first], 8]
        start[idx[N[idx, 8] >= big[grp] * 0.8]] = True
    if not start.any():
        # No known places on this map (a small zone): its largest stretches of ground, joined either
        # way, the parts at least a tenth the size of the biggest.
        comp = nr.components(n, A, B)
        sizes = np.bincount(comp)
        big = np.nonzero(sizes >= sizes.max() * 0.1)[0]
        start = np.isin(comp, big)
    # Forward reach over the links (CSR).
    order = np.argsort(A, kind="stable")
    A2, B2 = A[order], B[order]
    ptr = np.searchsorted(A2, np.arange(n + 1))
    seen = start.copy()
    frontier = np.nonzero(start)[0]
    while len(frontier):
        lo, hi = ptr[frontier], ptr[frontier + 1]
        cnt = hi - lo
        if cnt.sum() == 0:
            break
        idx = np.repeat(lo, cnt) + (np.arange(cnt.sum()) - np.repeat(np.cumsum(cnt) - cnt, cnt))
        nxt = np.unique(B2[idx])
        nxt = nxt[~seen[nxt]]
        seen[nxt] = True
        frontier = nxt
    return seen, int(start.sum()), len(pts)


BUSY_HEIGHT = 3    # yards a spawn's height may miss its floor by
BUSY_HOPS = 2      # cells round a spawn whose floors (walked to) count as frequented too


def frequented(N, A, B, K, mapid):
    """Floors where people are: every creature's and object's spawn (CMaNGOS, with its height) marks
    the floor it stands on, and the floors BUSY_HOPS walking links round it. Where floors are
    stacked, the game doesn't tell an addon which you're on: this is its first guess."""
    import gzip
    sys.path.insert(0, os.path.join(os.path.dirname(HERE), "_shared"))
    import sqldump
    dump = os.path.join(os.path.dirname(HERE), "Spyglass", ".wowhead_cache", "cmangos-classic-db.sql.gz")
    if not os.path.exists(dump):
        print("  (no CMaNGOS dump: no frequented floors)")
        return np.zeros(len(N), dtype=bool)
    text = gzip.decompress(open(dump, "rb").read()).decode("utf-8", "replace")
    pts = []
    for table in ("creature", "gameobject"):
        cols = sqldump.columns(text, table)
        im, ix, iy, iz = (cols.index(c) for c in ("map", "position_x", "position_y", "position_z"))
        for r in sqldump.sql_rows(text, table):
            if int(r[im]) == mapid:
                pts.append((float(r[ix]), float(r[iy]), float(r[iz])))
    if not pts:
        return np.zeros(len(N), dtype=bool)
    P = np.array(pts)
    gr = np.floor((nr.MAX - P[:, 0]) / nr.FINE).astype(np.int64)
    gc = np.floor((nr.MAX - P[:, 1]) / nr.FINE).astype(np.int64)
    pkey = gr * 4096 + gc
    nkey = (N[:, 0] * 64 + N[:, 2]) * 4096 + N[:, 1] * 64 + N[:, 3]
    order = np.argsort(nkey, kind="stable")
    sk = nkey[order]
    lo_i, hi_i = np.searchsorted(sk, pkey, "left"), np.searchsorted(sk, pkey, "right")
    busy = np.zeros(len(N), dtype=bool)
    lo, hi = N[:, 6] / 10.0, N[:, 7] / 10.0
    for step in range(int((hi_i - lo_i).max()) if len(pts) else 0):
        has = lo_i + step < hi_i
        cand = order[np.minimum(lo_i + step, len(order) - 1)]
        ok = has & (P[:, 2] >= lo[cand] - BUSY_HEIGHT) & (P[:, 2] <= hi[cand] + BUSY_HEIGHT)
        busy[cand[ok]] = True
    walk = K == 0
    a, b = A[walk], B[walk]
    for _ in range(BUSY_HOPS):
        busy[b[busy[a]]] = True
    print("  %d spawns mark %d floors as frequented" % (len(pts), busy.sum()))
    return busy


JUMP_REACH = 15    # yards round a lift's, portal's or tram's end its floor may be
JUMP_HEIGHT = 6    # yards above or below the end's height


def add_jumps(N, A, B, K, F, mapid):
    """Lifts, portals and the tram (nav_links.py's links.json) as links of kind 3, their seconds
    in the fall column (tenths): each end the nearest floor within JUMP_REACH yards and JUMP_HEIGHT
    of its height. Returns the links with them, and the nodes at their ends."""
    path = os.path.join(NAV, "links.json")
    if not os.path.exists(path):
        return A, B, K, F, set()
    import json
    gr, gc = N[:, 0] * 64 + N[:, 2], N[:, 1] * 64 + N[:, 3]
    pn = nr.MAX - (gr + N[:, 9] / 255.0) * nr.FINE
    pw = nr.MAX - (gc + N[:, 10] / 255.0) * nr.FINE
    h = N[:, 5] / 10.0

    def snap(p):
        d = np.hypot(pn - p[0], pw - p[1])
        near = np.nonzero((d <= JUMP_REACH) & (np.abs(h - p[2]) <= JUMP_HEIGHT) & (N[:, 4] != 2))[0]
        if len(near) == 0:
            return None
        return int(near[np.argmin(d[near] + np.abs(h[near] - p[2]))])

    extra, ends = [], set()
    for l in json.load(open(path, encoding="utf-8")):
        if l["map"] != mapid:
            continue
        a, b = snap(l["a"]), snap(l["b"])
        if a is None or b is None or a == b:
            print("  %s %s: no floor at %s" % (l["kind"], l["name"], "its start" if a is None else "its end" if b is None else "both ends (the same)"))
            continue
        secs = int(round(l["secs"] * 10))
        extra.append((a, b, secs))
        if l["both"]:
            extra.append((b, a, secs))
        ends |= {a, b}
    if not extra:
        return A, B, K, F, ends
    E = np.array(extra, dtype=np.int64)
    print("  %d lift, portal and tram links" % len(E))
    return (np.concatenate([A, E[:, 0]]), np.concatenate([B, E[:, 1]]),
            np.concatenate([K, np.full(len(E), 3)]), np.concatenate([F, E[:, 2]]), ends)


def main(argv):
    for mapid in (int(a) for a in argv):
        t = time.time()
        tiles = load_tiles(mapid)
        N, A, B, K, F, unmatched = stitch(tiles)
        print("map %d: %d tiles, %d nodes, %d links (%d drops), %d cross-tile links unmatched (%.0fs)" % (
            mapid, len(tiles), len(N), len(A), int((K == 2).sum()), unmatched, time.time() - t))
        A, B, K, F, ends = add_jumps(N, A, B, K, F, mapid)
        keep, nseed, npts = prune(N, A, B, K, mapid)
        print("  %d seed points -> %d seed nodes; reachable %d nodes (%.0f%%)" % (npts, nseed, keep.sum(), 100 * keep.mean()))
        small = keep & (N[:, 8] < MIN_SIZE) & (N[:, 4] != 1)
        small[list(ends)] = False
        keep &= ~small
        print("  %d small nodes dropped: %d kept" % (small.sum(), keep.sum()))
        new = np.full(len(N), -1, dtype=np.int64)
        new[keep] = np.arange(keep.sum())
        m = keep[A] & keep[B]
        busy = frequented(N, A, B, K, mapid)
        N = np.concatenate([N, busy[:, None].astype(N.dtype)], 1)   # column 11: frequented
        np.savez_compressed(os.path.join(NAV, "%d.graph.npz" % mapid), nodes=N[keep],
                            links=np.stack([new[A[m]], new[B[m]], K[m], F[m]], 1))
        sizes = N[keep, 8]
        print("  kept nodes by size (Recast cells): <10: %d, 10-99: %d, 100+: %d; water %d, lava %d" % (
            (sizes < 10).sum(), ((sizes >= 10) & (sizes < 100)).sum(), (sizes >= 100).sum(),
            (N[keep, 4] == 1).sum(), (N[keep, 4] == 2).sum()))


if __name__ == "__main__":
    main(sys.argv[1:])
