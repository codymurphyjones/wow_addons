"""Packs a map's stitched graph (nav_stitch.py) into Waypoint's navigation data, Data/Nav<map>.lua:
every tile's nodes and links (compressed, unpacked in the game only when a route needs that tile),
and the doors between tiles with the times to cross each tile from door to door, so a route is
first found door to door and only then walked out node by node.

    python -I tools/Waypoint/nav_pack.py <map> [...]

Costs (the doors' times, seconds at RUN yards a second and SWIM swimming): a walk is its length
plus each yard up counted CLIMB times; a swim its length at SWIM; a drop no higher than HARMLESS
slides down (SLIDE times slower); a higher one isn't counted here (fall damage depends on you: the
game decides those near you). Lava isn't crossed. Times are kept as walking and swimming apart, so
the game can scale each by your own speeds.

Doors: the links between two tiles, in runs (links whose nodes join on both sides, the same way:
both ways, or only one), at most DOOR cells long (a long open border becomes several doors). The
link in the middle of a run stands for it.

Each string below is zlib then base64 (C_EncodingUtil in the game).
tiles[ty * 64 + tx], the tile's nodes in cell order (rows north to south, columns west to east),
then by height; a node's number is its place in that order (from 0):
  4096 bytes      nodes per cell
  n bytes         kind (0 land, 1 water, 2 lava) | default links << 2: a bit for each side (north,
                  south, west, east) linked to the node of that cell whose height is nearest (a
                  swim when either is water, else a walk) | 64 when its middle isn't the cell's
                  | 128 when it's frequented (nav_stitch.py: creatures and objects stand there)
  n int16         height, half yards, each less the one before (the first less 0)
  bytes           for each node with flag 64, where its middle is in the cell: north offset << 4 |
                  west offset (sixteenths); the others fill most of their cell: its middle
  n bytes         extra links
  3 bytes each    the extra links, node by node: direction (0-7 as Grid.lua's STEPS, 8 the same
                  cell) | kind << 4 (0 walk, 1 swim, 2 drop); the target's place among its cell's
                  nodes; fall (half yards)
doors[ty * 64 + tx]: byte count; uint16 node of each door; then for each door, to each door:
  uint16 walk, uint16 swim (tenths of a second; 65535: no way across inside the tile)
cross: for each way a door's link goes: uint16 from tile, byte its door, uint16 to tile, byte its
  door, byte kind (3: a lift, portal or the tram), uint16 walk, uint16 swim (tenths of a second),
  uint16 fall (tenths of a yard), uint16 fixed (tenths of a second: a lift's, portal's or tram's)
places = { { kind, name, north, west }, ... } (nav_places.py) and walks: for each place, to each
  place, uint16 walk, swim, fixed (tenths of a second; 65535 no way)
zones = { { zone, level, capital }, ... } and zoneOf[ty * 64 + tx]: 256 bytes, the zone (its place
  in zones, 0 none) of each of the tile's 16 x 16 chunks
"""
import base64
import os
import struct
import subprocess
import sys
import time
import zlib

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import nav_reduce as nr  # noqa: E402
import nav_places  # noqa: E402

NAV = nr.NAV
ROOT = os.path.dirname(os.path.dirname(HERE))
ADDON = os.path.join(ROOT, "addons", "Waypoint")
RUN = 7.0          # yards a second running
SWIM = 4.72        # swimming (Route.lua's SWIM)
CLIMB = 1.0        # each yard up counts as this many on the flat
SLIDE = 1.5        # sliding down a small drop is this much slower than walking
HARMLESS = 14.57   # Grid.lua: the highest fall without damage
DOOR = 20          # cells a door may run along a tile's edge
FULL = 240         # Recast cells (of about 278 in a cell) from which a node's middle is the cell's
# Directions as Grid.lua's STEPS (dr, dc), then 8 = the same cell.
STEPS = [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)]
DIR_OF = {s: k for k, s in enumerate(STEPS)}
DIR_OF[(0, 0)] = 8


def positions(N):
    gr = N[:, 0] * 64 + N[:, 2]
    gc = N[:, 1] * 64 + N[:, 3]
    n = nr.MAX - (gr + N[:, 9] / 255.0) * nr.FINE
    w = nr.MAX - (gc + N[:, 10] / 255.0) * nr.FINE
    return gr, gc, n, w, N[:, 5] / 10.0


def edge_costs(N, L):
    """(walk seconds, swim seconds, usable) for every link, at the default speeds."""
    _, _, n, w, h = positions(N)
    a, b, k, fall = L[:, 0], L[:, 1], L[:, 2], L[:, 3] / 10.0
    d = np.hypot(n[a] - n[b], w[a] - w[b])
    wet = (N[a, 4] == 1) | (N[b, 4] == 1)
    rise = np.maximum(0, h[b] - h[a])
    walk = np.where(wet, 0, d / RUN + np.where(k == 0, rise * CLIMB / RUN, 0))
    walk = np.where(k == 2, d / RUN * SLIDE, walk)
    swim = np.where(wet & (k != 2), d / SWIM, 0)
    usable = (N[a, 4] != 2) & (N[b, 4] != 2) & ~((k == 2) & (fall > HARMLESS)) & (k != 3)
    return walk.astype(np.float32), swim.astype(np.float32), usable


def find_doors(N, L, usable):
    """The doors: [(low node, high node, way)] for each run of links between two tiles; low is the
    node in the lower-numbered tile, way 0 both ways, 1 only low to high, 2 only high to low."""
    tile = N[:, 0] * 64 + N[:, 1]
    gr, gc, _, _, _ = positions(N)
    cross = usable & (tile[L[:, 0]] != tile[L[:, 1]])
    pairs = {}
    for a, b in L[cross][:, :2]:
        a, b = int(a), int(b)
        lo, hi = (a, b) if tile[a] < tile[b] else (b, a)
        pairs[(lo, hi)] = pairs.get((lo, hi), 0) | (1 if a == lo else 2)
    # Walk links inside tiles, to join a run's nodes.
    inner = usable & (tile[L[:, 0]] == tile[L[:, 1]]) & (L[:, 2] != 2)
    adj = {}
    for a, b in L[inner][:, :2]:
        adj.setdefault(int(a), set()).add(int(b))
    groups = {}
    for (lo, hi), bits in pairs.items():
        way = 0 if bits == 3 else bits
        groups.setdefault((int(tile[lo]), int(tile[hi]), way), []).append((lo, hi))
    doors = []
    for (_, _, way), items in groups.items():
        parent = list(range(len(items)))

        def find(x):
            while parent[x] != x:
                parent[x] = parent[parent[x]]
                x = parent[x]
            return x
        by_lo = {}
        for k, (lo, hi) in enumerate(items):
            by_lo.setdefault(lo, []).append(k)
        for k, (lo, hi) in enumerate(items):
            near_hi = adj.get(hi, set()) | {hi}
            for lo2 in adj.get(lo, set()) | {lo}:
                for k2 in by_lo.get(lo2, ()):
                    if items[k2][1] in near_hi:
                        ra, rb = find(k), find(k2)
                        if ra != rb:
                            parent[ra] = rb
        runs = {}
        for k in range(len(items)):
            runs.setdefault(find(k), []).append(items[k])
        for run in runs.values():
            run.sort(key=lambda x: (gr[x[0]], gc[x[0]]))
            for s0 in range(0, len(run), DOOR):
                part = run[s0:s0 + DOOR]
                lo, hi = part[len(part) // 2]
                doors.append((lo, hi, way))
    return doors


def crossings(N, L, walk, swim, usable, doors, mapid, more=()):
    """Each tile's times between its door nodes (nav_doors.mjs)."""
    tile = (N[:, 0] * 64 + N[:, 1]).astype(np.int32)
    A, B = L[usable, 0], L[usable, 1]
    wv, sv = walk[usable], swim[usable]
    order = np.argsort(A, kind="stable")
    A, B, wv, sv = A[order], B[order], wv[order], sv[order]
    start = np.searchsorted(A, np.arange(len(N) + 1)).astype(np.int32)
    dn = np.unique(np.array([x for d in doors for x in d[:2]] + list(more), dtype=np.int64)).astype(np.int32)
    dn = dn[np.argsort(tile[dn], kind="stable")]
    src = os.path.join(NAV, "%d.doors.in" % mapid)
    out = os.path.join(NAV, "%d.doors.out" % mapid)
    with open(src, "wb") as f:
        f.write(b"WDIN" + struct.pack("<iii", len(N), len(A), len(dn)))
        f.write(tile.astype("<i4").tobytes())
        f.write(start.astype("<i4").tobytes())
        f.write(B.astype("<i4").tobytes())
        f.write(wv.astype("<f4").tobytes())
        f.write(sv.astype("<f4").tobytes())
        f.write(dn.astype("<i4").tobytes())
    r = subprocess.run(["node", os.path.join(HERE, "nav_doors.mjs"), src, out], cwd=ROOT, capture_output=True, text=True)
    if r.returncode:
        raise RuntimeError(r.stderr)
    print("  " + r.stdout.strip())
    b = open(out, "rb").read()
    ne = struct.unpack_from("<i", b, 4)[0]
    rec = np.frombuffer(b, dtype=np.dtype([("a", "<i4"), ("b", "<i4"), ("w", "<f4"), ("s", "<f4")]), count=ne, offset=8)
    return dn, rec


def b64z(data):
    return base64.b64encode(zlib.compress(bytes(data), 9)).decode("ascii")


def encode(mapid, N, L, walk, swim, usable, doors, dn, inner, jumps, places, walks, zone_of, zones):
    """Writes Data/Nav<map>.lua."""
    gr, gc, _, _, h = positions(N)
    tile = N[:, 0] * 64 + N[:, 1]
    cellkey = tile * 4096 + N[:, 2] * 64 + N[:, 3]
    # Each tile's nodes: by cell, then height; local index = place in that order.
    order = np.lexsort((N[:, 5], cellkey))
    tiles = np.unique(tile)
    t_start = np.searchsorted(tile[order], tiles)
    t_end = np.searchsorted(tile[order], tiles, "right")
    local = np.zeros(len(N), dtype=np.int64)
    for s0, e0 in zip(t_start, t_end):
        local[order[s0:e0]] = np.arange(e0 - s0)
    ck_sorted = cellkey[order]
    first = np.ones(len(order), dtype=bool)
    first[1:] = ck_sorted[1:] != ck_sorted[:-1]
    run_start = np.maximum.accumulate(np.where(first, np.arange(len(order)), 0))
    place = np.zeros(len(N), dtype=np.int64)
    place[order] = np.arange(len(order)) - run_start
    cell_first = {int(ck_sorted[i]): int(i) for i in np.nonzero(first)[0]}

    def cell_nodes(key):
        i = cell_first.get(key)
        out = []
        while i is not None and i < len(order) and ck_sorted[i] == key:
            out.append(int(order[i]))
            i += 1
        return out

    def cell_of(t, r, c):
        ty, tx = divmod(t, 64)
        ty, r = ty + r // 64, r % 64
        tx, c = tx + c // 64, c % 64
        return (ty * 64 + tx) * 4096 + r * 64 + c

    HQ = np.clip(np.round(N[:, 5] / 5), -32768, 32767).astype(np.int64)   # heights as stored (half yards)
    lorder = np.argsort(L[:, 0], kind="stable")
    lstart = np.searchsorted(L[lorder, 0], np.arange(len(N) + 1))
    blobs, raw_total = {}, 0
    for s0, e0 in zip(t_start, t_end):
        nodes = order[s0:e0]
        t = int(tile[nodes[0]])
        counts = np.zeros(4096, dtype=np.int64)
        np.add.at(counts, N[nodes, 2] * 64 + N[nodes, 3], 1)
        flags, heights, offs, nextra, extras = bytearray(), bytearray(), bytearray(), bytearray(), bytearray()
        prev = 0
        for i in nodes:
            i = int(i)
            r, c = int(N[i, 2]), int(N[i, 3])
            mask, extra = 0, []
            for li in lorder[lstart[i]:lstart[i + 1]]:
                j = int(L[li, 1])
                kind = int(L[li, 2])
                if kind == 3:
                    continue   # a lift, portal or the tram: in cross
                d = DIR_OF.get((int(gr[j] - gr[i]), int(gc[j] - gc[i])))
                if d is None:
                    continue
                derived = 1 if (N[i, 4] == 1 or N[j, 4] == 1) else 0
                if d < 4 and kind == derived and not (mask >> d) & 1:
                    dr, dc = STEPS[d]
                    cand = cell_nodes(cell_of(t, r + dr, c + dc))
                    # As the game picks it: by the heights it's given (half yards), the first if tied.
                    if cand and min(cand, key=lambda x: (abs(HQ[x] - HQ[i]), place[x])) == j:
                        mask |= 1 << d
                        continue
                extra.append((d | (kind << 4), min(int(place[j]), 255), min(int(round(L[li, 3] / 5)), 255)))
            hq = int(HQ[i])
            off = N[i, 8] < FULL
            busy = N.shape[1] > 11 and N[i, 11]
            flags.append(int(N[i, 4]) | (mask << 2) | (64 if off else 0) | (128 if busy else 0))
            heights += struct.pack("<h", max(-32768, min(32767, hq - prev)))
            prev = hq
            if off:
                offs.append((int(N[i, 9]) >> 4) << 4 | (int(N[i, 10]) >> 4))
            nextra.append(min(len(extra), 255))
            for x in extra[:255]:
                extras += bytes(x)
        raw = bytes(np.minimum(counts, 255).astype(np.uint8)) + flags + heights + offs + nextra + extras
        raw_total += len(raw)
        blobs[t] = b64z(raw)
    # Doors per tile, and the times between them.
    by_tile = {}
    for x in dn:
        by_tile.setdefault(int(tile[x]), []).append(int(x))
    dpos = {}
    for t, lst in by_tile.items():
        lst.sort(key=lambda x: local[x])
        for k, x in enumerate(lst):
            dpos[x] = k
    cost = {}
    for rec in inner:
        cost[(int(rec["a"]), int(rec["b"]))] = (float(rec["w"]), float(rec["s"]))
    door_blobs = {}
    for t, lst in by_tile.items():
        out = bytearray([min(len(lst), 255)])
        for x in lst:
            out += struct.pack("<H", int(local[x]))
        for a in lst:
            for b in lst:
                wv, sv = (0.0, 0.0) if a == b else cost.get((a, b), (None, None))
                if wv is None:
                    out += struct.pack("<HH", 65535, 65535)
                else:
                    out += struct.pack("<HH", min(65534, int(round(wv * 10))), min(65534, int(round(sv * 10))))
        door_blobs[t] = b64z(out)
    # Crossings between tiles, each way a door's link goes.
    link_of = {}
    for li in np.nonzero(usable & (tile[L[:, 0]] != tile[L[:, 1]]))[0]:
        link_of.setdefault((int(L[li, 0]), int(L[li, 1])), int(li))
    cross = bytearray()
    ncross = 0
    for lo, hi, way in doors:
        for a, b in ((lo, hi), (hi, lo)):
            li = link_of.get((a, b))
            if li is None:
                continue
            cross += struct.pack("<HBHBBHHHH", int(tile[a]), dpos[a], int(tile[b]), dpos[b], int(L[li, 2]),
                                 min(65534, int(round(walk[li] * 10))), min(65534, int(round(swim[li] * 10))),
                                 min(65534, int(L[li, 3])), 0)
            ncross += 1
    for li in jumps:
        a, b = int(L[li, 0]), int(L[li, 1])
        cross += struct.pack("<HBHBBHHHH", int(tile[a]), dpos[a], int(tile[b]), dpos[b], 3, 0, 0, 0, min(65534, int(L[li, 3])))
        ncross += 1
    lines = [
        "-- GENERATED by tools/Waypoint/nav_pack.py from the game's own ground (nav_*.py). Do not edit.",
        "-- tiles[ty * 64 + tx]: the tile's nodes; doors[ty * 64 + tx]: its doors and the times between them;",
        "-- cross: the links between tiles' doors. Each zlib + base64; nav_pack.py has the layouts.",
        "local _, ns = ...",
        "ns.NavData = ns.NavData or {}",
        "ns.NavData[%d] = { fine = %.6f, max = %.6f, tiles = {" % (mapid, nr.FINE, nr.MAX),
    ]
    for t in sorted(blobs):
        lines.append('    [%d] = "%s",' % (t, blobs[t]))
    lines.append("}, doors = {")
    for t in sorted(door_blobs):
        lines.append('    [%d] = "%s",' % (t, door_blobs[t]))
    lines.append('}, cross = "%s", crossCount = %d, places = {' % (b64z(cross), ncross))
    for kind, name, n, w, _ in places:
        lines.append('    { "%s", "%s", %.1f, %.1f },' % (kind, name.replace("\\", "\\\\").replace('"', '\\"'), n, w))
    lines.append('}, walks = "%s", zones = {' % b64z(walks))
    for z, level, cap in zones:
        lines.append("    { %d, %d, %d }," % (z, level, cap))
    lines.append("}, zoneOf = {")
    for t in sorted(zone_of):
        lines.append('    [%d] = "%s",' % (t, b64z(zone_of[t])))
    lines.append("} }")
    path = os.path.join(ADDON, "Data", "Nav%d.lua" % mapid)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    tb = sum(len(v) for v in blobs.values()) / 1e6
    db = sum(len(v) for v in door_blobs.values()) / 1e6
    print("  %d tiles (%.1f MB unpacked, %.1f MB packed), %d door nodes (%.2f MB), %d crossings -> %s %.1f MB" % (
        len(blobs), raw_total / 1e6, tb, len(dn), db, ncross, path, os.path.getsize(path) / 1e6))


def walk_table(N, L, walk, swim, usable, jumps, mapid):
    """The fixed places on this map and the walk between every two (nav_walks.mjs): (places, bytes)."""
    from casc import Casc
    places = nav_places.snap_places(N, nav_places.raw_places(mapid, Casc.open().version))
    if not places:
        return [], b""
    fixed = np.zeros(len(L), dtype=np.float32)
    use = usable.copy()
    use[jumps] = True
    fixed[jumps] = L[jumps, 3] / 10.0
    A, B = L[use, 0], L[use, 1]
    wv, sv, fv = walk[use], swim[use], fixed[use]
    order = np.argsort(A, kind="stable")
    A, B, wv, sv, fv = A[order], B[order], wv[order], sv[order], fv[order]
    start = np.searchsorted(A, np.arange(len(N) + 1)).astype(np.int32)
    src = os.path.join(NAV, "%d.walks.in" % mapid)
    out = os.path.join(NAV, "%d.walks.out" % mapid)
    with open(src, "wb") as f:
        f.write(b"WWIN" + struct.pack("<iii", len(N), len(A), len(places)))
        f.write(start.astype("<i4").tobytes())
        f.write(B.astype("<i4").tobytes())
        for arr in (wv, sv, fv):
            f.write(arr.astype("<f4").tobytes())
        f.write(np.array([p[4] for p in places], dtype="<i4").tobytes())
    r = subprocess.run(["node", os.path.join(HERE, "nav_walks.mjs"), src, out], cwd=ROOT, capture_output=True, text=True)
    if r.returncode:
        raise RuntimeError(r.stderr)
    print("  " + r.stdout.strip())
    b = open(out, "rb").read()
    np_ = struct.unpack_from("<i", b, 4)[0]
    m = np.frombuffer(b, "<f4", np_ * np_ * 3, 8).reshape(np_, np_, 3)
    q = np.where(m < 0, 65535, np.minimum(65534, np.round(m * 10))).astype("<u2")
    return places, q.tobytes()


def main(argv):
    for mapid in (int(a) for a in argv):
        t0 = time.time()
        z = np.load(os.path.join(NAV, "%d.graph.npz" % mapid))
        N, L = z["nodes"].astype(np.int64), z["links"].astype(np.int64)
        walk, swim, usable = edge_costs(N, L)
        doors = find_doors(N, L, usable)
        jumps = np.nonzero(L[:, 2] == 3)[0]
        ends = {int(x) for li in jumps for x in L[li, :2]}
        print("map %d: %d nodes, %d links, %d doors, %d lifts, portals and trams (%.0fs)" % (
            mapid, len(N), len(L), len(doors), len(jumps), time.time() - t0))
        dn, inner = crossings(N, L, walk, swim, usable, doors, mapid, ends)
        places, walks = walk_table(N, L, walk, swim, usable, jumps, mapid)
        tiles = sorted({int(t) for t in np.unique(N[:, 0] * 64 + N[:, 1])})
        from casc import Casc
        zone_of, zones = nav_places.zone_tables(mapid, tiles, Casc.open().version)
        print("  %d places, %d zones" % (len(places), len(zones)))
        encode(mapid, N, L, walk, swim, usable, doors, dn, inner, jumps, places, walks, zone_of, zones)
        print("  done in %.0fs" % (time.time() - t0))


if __name__ == "__main__":
    main(sys.argv[1:])
