"""Works out the heights along the caves you logged with RoadLog's Cave Logs (Data/Caves.lua), from
the caves' floors in the game files: the game doesn't tell addons your height.

    python -I tools/RoadLog/build_caves.py          (or: yarn build --dev)

Reads RoadLogDB.caves from the saved variables (WOW_WTF, the Forever client's by default; read
only) and the local game install (tools/_shared/casc.py; WOW_DIR / WOW_PRODUCT override).

For each logged stretch (a point every 2 yards, with the falls you took):
  1. Floors. Every building model (WMO) placed in the map tiles under the stretch (MODF, in each
     tile's _obj0 file) whose bounds it crosses is read: its groups' collision triangles, placed in
     the world the way the game places them. A floor is one facing up no steeper than FLOOR_SLOPE.
     The terrain's own height there counts too (the way in, and caves dug into terrain), except at
     points the game had you indoors: there you're inside, not on the ground above.
  2. Every point gets the heights of all the floors over or under it: one per level.
  3. The level you were on is followed from point to point (the cheapest path through the
     candidates, Viterbi): walking changes height a little at a time, a climb steeper than CLIMB
     can't be walked, and a drop is only cheap where you fell (a fall logged on that point).
Points with no floor at all (a gap in the model) get heights in line with their neighbours.

Writes addons/RoadLog/Data/Caves.lua:
    ns.CaveMap = { [continent] = { [at] = { z = { height per point }, lo = lowest, hi = highest } } }
keyed by each logged stretch's time, the way Caves.lua looks them up.

The WMO reading (wmo_collision, placements, place, placed_floors) is meant to be imported by other
builds too (tools/Waypoint/build_water.py, for tunnels).
"""
import csv
import glob
import math
import os
import struct
import sys
import urllib.request

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
ADDON = os.path.join(os.path.dirname(TOOLS), "addons", "RoadLog")  # tools/RoadLog/ builds addons/RoadLog/
OUT = os.environ.get("CAVES_OUT") or os.path.join(ADDON, "Data", "Caves.lua")
CACHE = os.path.join(HERE, ".cache")
WOW_WTF = os.environ.get("WOW_WTF") or r"Z:\Games\World of Warcraft\_classic_beta_\WTF"
sys.path.insert(0, os.path.join(TOOLS, "_shared"))
from casc import Casc  # noqa: E402

TILE = 1600 / 3          # yards per map tile
SUB = TILE / 128         # per terrain cell
MAX = 32 * TILE          # world coordinate of the map's top/left edge
FLOOR_SLOPE = 0.5        # a floor's normal points at least this much up (60 degrees at most)
CLIMB = 1.4              # yards up per yard across you can walk (with a little slack)
STEP_UP = 2.0            # yards up a jump gets you, however short the step
NEAR_FALL = 2            # points either side of a logged fall where a drop is a fall
GRID = 4.0               # yards per bucket in the floor index
MARGIN = 30              # yards around a stretch to look for its cave

# MOPY triangle flags (wowdev.wiki): collidable = F_COLLISION, or a render face that isn't detail.
F_DETAIL, F_COLLISION, F_RENDER = 0x04, 0x08, 0x20


# ---------------------------------------------------------------------------- game files

def chunks(b, start=0, end=None):
    """(id, data offset, size) of each chunk in b[start:end]; ids read the right way round."""
    pos, end = start, end or len(b)
    while pos + 8 <= end:
        cid = b[pos:pos + 4][::-1]
        size = struct.unpack_from("<I", b, pos + 4)[0]
        yield cid, pos + 8, size
        pos += 8 + size


def wago_table(name, build):
    """A game table for this build from wago.tools, cached in tools/RoadLog/.cache."""
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, "%s-%s.csv" % (name, build))
    if not os.path.exists(path):
        url = "https://wago.tools/db2/%s/csv?build=%s" % (name, build)
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "wow-addons build"})) as r:
            data = r.read()
        with open(path, "wb") as f:
            f.write(data)
    with open(path, encoding="utf-8") as f:
        return list(csv.DictReader(f))


def tile_files(casc, wdt_fdid):
    """A map's tiles: { (ty, tx): (root file ID, _obj0 file ID) }, ty counting south from the
    north edge and tx east from the west edge."""
    wdt = casc.read(wdt_fdid)
    if not wdt:
        return {}
    top = {cid: (off, size) for cid, off, size in chunks(wdt)}
    if b"MAIN" not in top or b"MAID" not in top:
        return {}
    off, size = top[b"MAIN"]
    flags = struct.unpack_from("<%dI" % (size // 4), wdt, off)
    off, size = top[b"MAID"]
    maid = struct.unpack_from("<%dI" % (size // 4), wdt, off)
    out = {}
    for i in range(4096):
        if flags[i * 2] & 1 and maid[i * 8]:
            out[divmod(i, 64)] = (maid[i * 8], maid[i * 8 + 1])
    return out


def placements(obj0):
    """A tile's building models (MODF): dicts with fdid, uid, pos, rot, scale and their bounds in
    world yards (n0, n1, w0, w1, z0, z1)."""
    out = []
    for cid, off, size in chunks(obj0):
        if cid == b"MODF":
            for k in range(size // 64):
                e = struct.unpack_from("<II3f3f3f3fHHHH", obj0, off + k * 64)
                lo, hi, flags = e[8:11], e[11:14], e[14]
                out.append({"fdid": e[0], "uid": e[1], "pos": e[2:5], "rot": e[5:8],
                            "scale": e[17] / 1024 if flags & 0x4 else 1.0,
                            "n0": MAX - hi[2], "n1": MAX - lo[2], "w0": MAX - hi[0], "w1": MAX - lo[0],
                            "z0": lo[1], "z1": hi[1]})
    return out


def wmo_collision(casc, fdid, cache=None):
    """A building model's collision, in its own space (z up): (vertices Nx3, triangles Mx3,
    vertex normals Nx3), all its groups together; None if it isn't stored locally."""
    if cache is not None and fdid in cache:
        return cache[fdid]
    mesh = None
    root = casc.read(fdid)
    if root:
        top = {cid: (off, size) for cid, off, size in chunks(root)}
        groups = []
        if b"MOHD" in top and b"GFID" in top:
            n_groups = struct.unpack_from("<I", root, top[b"MOHD"][0] + 4)[0]
            off, size = top[b"GFID"]
            groups = struct.unpack_from("<%dI" % (size // 4), root, off)[:n_groups]
        verts, tris, norms, base = [], [], [], 0
        for g in groups:
            data = g and casc.read(g)
            if not data:
                continue
            for cid, off, size in chunks(data):
                if cid != b"MOGP":
                    continue
                sub = {sid: (soff, ssize) for sid, soff, ssize in chunks(data, off + 0x44, off + size)}
                # Older files: MOPY (a byte of flags and one of material per triangle) and 16-bit
                # MOVI indices; newer ones (this client): MPY2 (16 bits each) and maybe 32-bit MOVX.
                faces = b"MPY2" if b"MPY2" in sub else b"MOPY"
                index = b"MOVX" if b"MOVX" in sub else b"MOVI"
                if not all(k in sub for k in (faces, index, b"MOVT")):
                    break
                v = np.frombuffer(data, "<f4", sub[b"MOVT"][1] // 4, sub[b"MOVT"][0]).reshape(-1, 3).astype(np.float64)
                wide = index == b"MOVX"
                t = np.frombuffer(data, "<u4" if wide else "<u2", sub[index][1] // (4 if wide else 2), sub[index][0]).astype(np.int64)
                t = t[:len(t) - len(t) % 3].reshape(-1, 3)
                if faces == b"MPY2":
                    mopy = np.frombuffer(data, "<u2", sub[faces][1] // 2, sub[faces][0]).reshape(-1, 2)[:, 0].astype(np.int64)
                else:
                    mopy = np.frombuffer(data, np.uint8, sub[faces][1], sub[faces][0]).reshape(-1, 2)[:, 0].astype(np.int64)
                n = len(v)
                if b"MONR" in sub and sub[b"MONR"][1] // 12 == n:
                    nr = np.frombuffer(data, "<f4", n * 3, sub[b"MONR"][0]).reshape(-1, 3).astype(np.float64)
                else:
                    nr = np.zeros((n, 3))
                k = min(len(t), len(mopy))
                t, mopy = t[:k], mopy[:k]
                keep = ((mopy & F_COLLISION) != 0) | (((mopy & F_RENDER) != 0) & ((mopy & F_DETAIL) == 0))
                t = t[keep & (t.max(axis=1) < n)]
                verts.append(v)
                norms.append(nr)
                tris.append(t + base)
                base += n
                break
        if verts:
            mesh = (np.concatenate(verts), np.concatenate(tris), np.concatenate(norms))
    if cache is not None:
        cache[fdid] = mesh
    return mesh


def _rot(axis, deg):
    c, s = np.cos(np.radians(deg)), np.sin(np.radians(deg))
    return {"x": np.array([[1, 0, 0], [0, c, -s], [0, s, c]]),
            "y": np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]]),
            "z": np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])}[axis]


def place(verts, pos, rot, scale=1.0, direction=False):
    """A model's vertices placed in the world: an Nx3 array of (north, west, up) yards. The game's
    placement, as map editors do it (Noggit; the same as build_water.py's): model space turned
    y-up, then about y by rot.y - 90, z by -rot.x, x by rot.z, scaled, and moved to pos (whose x
    and z count from the map's corner). direction=True turns normals instead (no scale, no move)."""
    yup = np.stack([verts[:, 0], verts[:, 2], -verts[:, 1]], 1)
    m = _rot("y", rot[1] - 90) @ _rot("z", -rot[0]) @ _rot("x", rot[2])
    if direction:
        p = yup @ m.T
        return np.stack([-p[:, 2], -p[:, 0], p[:, 1]], 1)
    p = (yup * scale) @ m.T + np.asarray(pos)
    return np.stack([MAX - p[:, 2], MAX - p[:, 0], p[:, 1]], 1)


def placed_floors(casc, entry, cache=None):
    """A placed building's floors in the world: triangles as three Kx3 arrays (north, west, up) of
    corners, facing up no steeper than FLOOR_SLOPE. Which way a triangle faces comes from the
    model's vertex normals (winding alone isn't reliable across models)."""
    mesh = wmo_collision(casc, entry["fdid"], cache)
    if mesh is None or len(mesh[1]) == 0:
        return None
    verts, tris, norms = mesh
    p = place(verts, entry["pos"], entry["rot"], entry["scale"])
    a, b, c = p[tris[:, 0]], p[tris[:, 1]], p[tris[:, 2]]
    face = np.cross(b - a, c - a)
    length = np.linalg.norm(face, axis=1)
    ok = length > 1e-6
    face[ok] /= length[ok, None]
    vn = place(norms, None, entry["rot"], direction=True)
    avg = vn[tris[:, 0]] + vn[tris[:, 1]] + vn[tris[:, 2]]
    flip = (face * avg).sum(axis=1) < 0
    up = np.where(flip, -face[:, 2], face[:, 2])
    keep = ok & (up >= FLOOR_SLOPE)
    return a[keep], b[keep], c[keep]


def terrain_outer(root):
    """A tile's terrain heights at its 129x129 corner vertices (rows north to south, columns west
    to east); NaN where a chunk is missing."""
    outer = np.full((129, 129), np.nan)
    for cid, off, size in chunks(root):
        if cid == b"MCNK":
            ix, iy = struct.unpack_from("<II", root, off + 4)
            z = struct.unpack_from("<3f", root, off + 0x68)[2]
            for sid, soff, ssize in chunks(root, off + 128, off + size):
                if sid == b"MCVT":
                    v = np.frombuffer(root, "<f4", 145, soff)
                    rows = [v[r * 17:r * 17 + 9] for r in range(9)]
                    outer[iy * 8:iy * 8 + 9, ix * 8:ix * 8 + 9] = np.array(rows) + z
                    break
    return outer


# ---------------------------------------------------------------------------- heights

class Floors:
    """Every floor near a stretch, bucketed GRID yards square, asked for heights at a point."""

    def __init__(self):
        self.a, self.b, self.c = [], [], []
        self.terrain = {}   # (ty, tx) -> 129x129 heights
        self.buckets = {}

    def add(self, a, b, c):
        base = sum(len(x) for x in self.a)
        self.a.append(a)
        self.b.append(b)
        self.c.append(c)
        lo = np.minimum(np.minimum(a, b), c)
        hi = np.maximum(np.maximum(a, b), c)
        for k in range(len(a)):
            for gn in range(int(lo[k, 0] // GRID), int(hi[k, 0] // GRID) + 1):
                for gw in range(int(lo[k, 1] // GRID), int(hi[k, 1] // GRID) + 1):
                    self.buckets.setdefault((gn, gw), []).append(base + k)

    def finish(self):
        self.A = np.concatenate(self.a) if self.a else np.zeros((0, 3))
        self.B = np.concatenate(self.b) if self.b else np.zeros((0, 3))
        self.C = np.concatenate(self.c) if self.c else np.zeros((0, 3))

    def terrain_at(self, n, w):
        ty, tx = int((MAX - n) // TILE), int((MAX - w) // TILE)
        outer = self.terrain.get((ty, tx))
        if outer is None:
            return None
        fr, fc = (MAX - n) / SUB - ty * 128, (MAX - w) / SUB - tx * 128
        r, c = min(int(fr), 127), min(int(fc), 127)
        dr, dc = fr - r, fc - c
        q = outer[r:r + 2, c:c + 2]
        h = q[0, 0] * (1 - dr) * (1 - dc) + q[0, 1] * (1 - dr) * dc + q[1, 0] * dr * (1 - dc) + q[1, 1] * dr * dc
        return None if math.isnan(h) else float(h)

    def heights(self, n, w, ground=True):
        """The heights of every floor over or under (n, w), lowest first, and the terrain's unless
        ground is False."""
        out = []
        idx = self.buckets.get((int(n // GRID), int(w // GRID)))
        if idx:
            idx = np.asarray(idx)
            a, b, c = self.A[idx], self.B[idx], self.C[idx]
            v0, v1 = b[:, :2] - a[:, :2], c[:, :2] - a[:, :2]
            v2 = np.array([n, w]) - a[:, :2]
            den = v0[:, 0] * v1[:, 1] - v1[:, 0] * v0[:, 1]
            good = np.abs(den) > 1e-9
            den = np.where(good, den, 1)
            s = (v2[:, 0] * v1[:, 1] - v1[:, 0] * v2[:, 1]) / den
            t = (v0[:, 0] * v2[:, 1] - v2[:, 0] * v0[:, 1]) / den
            inside = good & (s >= -1e-6) & (t >= -1e-6) & (s + t <= 1 + 1e-6)
            z = a[:, 2] + s * (b[:, 2] - a[:, 2]) + t * (c[:, 2] - a[:, 2])
            out = sorted(float(x) for x in z[inside])
        if ground:
            h = self.terrain_at(n, w)
            if h is not None:
                out.append(h)
        merged = []
        for z in sorted(out):
            if not merged or z - merged[-1] > 0.5:
                merged.append(z)
        return merged


def follow(pts, falls, cands):
    """The floor you were on at each point: Viterbi over each point's candidate heights. pts: flat
    (n, w) list; falls: point numbers (1-based) where you landed from a fall; cands: candidate
    heights per point (may be empty). Returns a height per point (None where it has none)."""
    fell = set()
    for f in falls:
        for k in range(f - NEAR_FALL, f + NEAR_FALL + 1):
            fell.add(k)
    k = len(cands)
    best = [None] * k     # per point: costs per candidate
    back = [None] * k
    prev = None           # the last point with candidates
    for i in range(k):
        zs = cands[i]
        if not zs:
            continue
        if prev is None:
            best[i] = [0.0] * len(zs)
            back[i] = [None] * len(zs)
            prev = i
            continue
        d = math.hypot(pts[2 * i] - pts[2 * prev], pts[2 * i + 1] - pts[2 * prev + 1])
        limit = max(STEP_UP, CLIMB * d)
        costs, links = [], []
        for zb in zs:
            bc, bl = math.inf, None
            for j, za in enumerate(cands[prev]):
                up = zb - za
                if up > limit:
                    step = math.inf                            # too steep to walk up
                elif up < -limit:
                    step = 1 + 0.1 * -up if (i + 1) in fell else 30 - up   # a drop: cheap where you fell
                else:
                    step = abs(up)
                total = best[prev][j] + step
                if total < bc:
                    bc, bl = total, j
            if bl is None:    # nothing reaches it: start afresh from the cheapest
                j = int(np.argmin(best[prev]))
                bc, bl = best[prev][j] + 100 + abs(zb - cands[prev][j]), j
            costs.append(bc)
            links.append((prev, bl))
        best[i], back[i] = costs, links
        prev = i
    out = [None] * k
    if prev is None:
        return out
    j = int(np.argmin(best[prev]))
    i = prev
    while i is not None:
        out[i] = cands[i][j]
        link = back[i][j]
        if link is None:
            break
        i, j = link
    return out


def fill(z):
    """Heights for the points without one, in line with their neighbours."""
    known = [i for i, v in enumerate(z) if v is not None]
    if not known:
        return None
    out = list(z)
    for i in range(len(z)):
        if out[i] is None:
            before = max((k for k in known if k < i), default=None)
            after = min((k for k in known if k > i), default=None)
            if before is None:
                out[i] = z[after]
            elif after is None:
                out[i] = z[before]
            else:
                f = (i - before) / (after - before)
                out[i] = z[before] + f * (z[after] - z[before])
    return out


# ---------------------------------------------------------------------------- the build

def logged_caves():
    """RoadLogDB.caves from every account's saved variables: { continent: [ stretch ] }, each
    stretch { at, name, pts (flat n, w list), falls (point numbers), inside ("0101", indoors per
    point) }."""
    import lupa
    out = {}
    for path in glob.glob(os.path.join(WOW_WTF, "Account", "*", "SavedVariables", "RoadLog.lua")):
        lua = lupa.LuaRuntime()
        with open(path, encoding="utf-8") as f:
            lua.execute(f.read())
        db = lua.globals().RoadLogDB
        caves = db and db["caves"]
        if not caves:
            continue
        for continent, segs in caves.items():
            for _, seg in sorted(segs.items()):
                pts = [float(v) for _, v in sorted(seg["pts"].items())]
                falls = [int(k) for k in (seg["falls"] or {}).keys()] if seg["falls"] else []
                out.setdefault(int(continent), []).append(
                    {"at": int(seg["at"] or 0), "name": seg["name"], "pts": pts, "falls": falls,
                     "inside": seg["inside"] or ""})
    return out


def heights_for(casc, tiles, seg, cache):
    pts = seg["pts"]
    ns_, ws_ = pts[0::2], pts[1::2]
    n0, n1 = min(ns_) - MARGIN, max(ns_) + MARGIN
    w0, w1 = min(ws_) - MARGIN, max(ws_) + MARGIN
    floors = Floors()
    seen = set()
    for ty in range(int((MAX - n1) // TILE), int((MAX - n0) // TILE) + 1):
        for tx in range(int((MAX - w1) // TILE), int((MAX - w0) // TILE) + 1):
            files = tiles.get((ty, tx))
            if not files:
                continue
            root = casc.read(files[0])
            if root:
                floors.terrain[(ty, tx)] = terrain_outer(root)
            obj = files[1] and casc.read(files[1])
            for e in placements(obj) if obj else []:
                if e["uid"] in seen or e["n1"] < n0 or e["n0"] > n1 or e["w1"] < w0 or e["w0"] > w1:
                    continue
                seen.add(e["uid"])
                tri = placed_floors(casc, e, cache)
                if tri is not None and len(tri[0]):
                    floors.add(*tri)
    floors.finish()
    inside = seg.get("inside") or ""
    cands = [floors.heights(pts[2 * i], pts[2 * i + 1], ground=inside[i:i + 1] != "1")
             for i in range(len(pts) // 2)]
    z = fill(follow(pts, seg["falls"], cands))
    return z, cands, len(seen)


def main():
    caves = logged_caves()
    if not caves:
        print("No logged caves in", WOW_WTF, "(turn on Cave Logs in RoadLog and walk a cave).")
    casc = Casc.open() if caves else None
    lines = [
        "-- GENERATED by tools/RoadLog/build_caves.py from your logged caves and the game's cave floors. Do not edit.",
        "-- ns.CaveMap = { [continent] = { [at] = { z = { height per point, yards }, lo = lowest, hi = highest } } }",
        "local _, ns = ...",
        "ns.CaveMap = {",
    ]
    if caves:
        maps = {int(r["ID"]): int(r["WdtFileDataID"] or 0) for r in wago_table("Map", casc.version)}
        cache = {}
        for continent, segs in sorted(caves.items()):
            tiles = tile_files(casc, maps.get(continent, 0))
            if not tiles:
                print("continent %d: no map tiles, skipped" % continent)
                continue
            lines.append("    [%d] = {" % continent)
            for seg in segs:
                z, cands, models = heights_for(casc, tiles, seg, cache)
                count = len(seg["pts"]) // 2
                if z is None:
                    print("  %s (%d points): no floor found, skipped" % (seg["name"] or seg["at"], count))
                    continue
                multi = sum(1 for c in cands if len(c) > 1)
                print("  %s: %d points, %d models, %d with more than one level, heights %.1f to %.1f yd" % (
                    seg["name"] or seg["at"], count, models, multi, min(z), max(z)))
                lines.append("        [%d] = { lo = %.1f, hi = %.1f, z = { %s } }," % (
                    seg["at"], min(z), max(z), ", ".join("%.1f" % v for v in z)))
            lines.append("    },")
    lines.append("}")
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print("wrote", OUT)


if __name__ == "__main__":
    main()
