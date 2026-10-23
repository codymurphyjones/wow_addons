"""The ground you can collide with, straight from the game's files, for the navigation bake
(nav_bake.mjs): every map tile's terrain, buildings (WMOs) and models (M2s), as one triangle soup.

    python -I tools/Waypoint/nav_extract.py <map> <tile row> <tile col> [out.bin]

Terrain: each map chunk's 9x9 + 8x8 heights (MCVT), four triangles a cell from its centre to its
corners, the way the game draws it, with the chunk's holes (MCNK) left out.
Models (MDDF on the tile's _obj0): their collision mesh (M2 bounding triangles), placed as the game
places them (build_water.place).
Buildings (MODF): every group's collidable triangles (MOPY: a collision face, or a rendered face
that isn't detail), and the models inside them (MODD) of the building's doodad set and the default
set, placed in the building and then in the world.
Liquids (MH2O): water, lava and slime surfaces, kept apart (kind 1 water, 2 hazard) so the bake
can tell swimming from walking.

Everything within MARGIN yards of the tile is included (a building over the edge is placed from one
tile's list but stands on both); the bake clips to its own bounds.

Out (little-endian): "WNAV", version, vertex count, triangle count; vertices as float32 (x, y, z)
with y up: x = north, y = up, z = -west (world yards, a right-handed frame, so the game's winding
keeps up-facing triangles up-facing); triangles as int32 triples; then a uint8 kind per triangle:
0 solid, 1 water surface, 2 lava/slime surface.
"""
import importlib.util
import os
import struct
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("build_water", os.path.join(HERE, "build_water.py"))
bw = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(bw)

TILE, CHUNK, SUB, MAX = bw.TILE, bw.CHUNK, bw.SUB, bw.MAX
MARGIN = 16          # yards past the tile's edge that are included
NAV_DIR = os.path.join(HERE, ".nav")  # the bake's working files (not packed: rebuilt from the game)
chunks = bw.chunks

# MOPY flags (wowdev): a face collides when it's a collision face, or rendered and not detail.
F_DETAIL, F_COLLISION, F_RENDER = 0x04, 0x08, 0x20


def tile_bounds(ty, tx, margin=MARGIN):
    """(north min, north max, west min, west max) of a tile, with margin."""
    n1 = MAX - ty * TILE
    w1 = MAX - tx * TILE
    return n1 - TILE - margin, n1 + margin, w1 - TILE - margin, w1 + margin


class Soup:
    """Triangles in world (north, west, up), with a kind each."""

    def __init__(self):
        self.verts, self.tris, self.kinds, self.n = [], [], [], 0

    def add(self, n, w, u, tris, kind=0):
        if len(tris) == 0:
            return
        self.verts.append(np.stack([n, w, u], 1).astype(np.float64))
        self.tris.append(np.asarray(tris, dtype=np.int64) + self.n)
        self.kinds.append(np.full(len(tris), kind, dtype=np.uint8))
        self.n += len(n)

    def clip(self, bounds):
        """Only triangles touching bounds; vertices renumbered."""
        V = np.concatenate(self.verts)
        T = np.concatenate(self.tris)
        K = np.concatenate(self.kinds)
        n0, n1, w0, w1 = bounds
        tn, tw = V[T, 0], V[T, 1]
        keep = (tn.max(1) >= n0) & (tn.min(1) <= n1) & (tw.max(1) >= w0) & (tw.min(1) <= w1)
        T, K = T[keep], K[keep]
        used, inv = np.unique(T, return_inverse=True)
        return V[used], inv.reshape(-1, 3), K

    def write(self, path, bounds):
        V, T, K = self.clip(bounds)
        rc = np.stack([V[:, 0], V[:, 2], -V[:, 1]], 1).astype("<f4")   # x north, y up, z -west
        with open(path, "wb") as f:
            f.write(b"WNAV" + struct.pack("<III", 1, len(rc), len(T)))
            f.write(rc.tobytes())
            f.write(T.astype("<i4").tobytes())
            f.write(K.astype("u1").tobytes())
        return len(rc), len(T)


# ---------------------------------------------------------------------------------------------
# Terrain
# ---------------------------------------------------------------------------------------------

def _hole(flags, hdr, data, off, cy, cx):
    """Whether terrain cell (cy, cx) of 8x8 in a chunk is a hole."""
    if flags & 0x10000:
        bits = struct.unpack_from("<Q", data, off + 0x14)[0]
        return bool(bits >> (cy * 8 + cx) & 1)
    low = struct.unpack_from("<H", data, off + 0x3C)[0]
    return bool(low >> ((cy // 2) * 4 + cx // 2) & 1)


def terrain(soup, data, ty, tx):
    """A tile's terrain triangles."""
    for cid, off, size in chunks(data):
        if cid != b"MCNK":
            continue
        flags, ix, iy = struct.unpack_from("<III", data, off)
        z = struct.unpack_from("<3f", data, off + 0x68)[2]
        for sid, soff, ssize in chunks(data, off + 128, off + size):
            if sid != b"MCVT":
                continue
            v = np.frombuffer(data, dtype="<f4", count=145, offset=soff).astype(np.float64) + z
            n0 = MAX - ty * TILE - iy * CHUNK
            w0 = MAX - tx * TILE - ix * CHUNK
            # Vertex k of 145: rows of 9 outer then 8 inner.
            ns, ws = np.empty(145), np.empty(145)
            k = 0
            for r in range(17):
                if r % 2 == 0:
                    for c in range(9):
                        ns[k], ws[k] = n0 - (r // 2) * SUB, w0 - c * SUB
                        k += 1
                else:
                    for c in range(8):
                        ns[k], ws[k] = n0 - (r // 2 + 0.5) * SUB, w0 - (c + 0.5) * SUB
                        k += 1
            tris = []
            for cy in range(8):
                for cx in range(8):
                    if _hole(flags, None, data, off, cy, cx):
                        continue
                    tl = cy * 17 + cx
                    tr, bl, br = tl + 1, tl + 17, tl + 18
                    m = tl + 9
                    # Four triangles round the centre, wound counter-clockwise seen from above in
                    # (north, west, up) (north x west = up).
                    tris += [(m, tl, bl), (m, bl, br), (m, br, tr), (m, tr, tl)]
            soup.add(ns, ws, v, tris)
            break


def liquids(soup, data, ty, tx, liq):
    """A tile's liquid surfaces (MH2O), as flat quads per liquid cell."""
    mh2o = None
    for cid, off, size in chunks(data):
        if cid == b"MH2O":
            mh2o = off
    if mh2o is None:
        return
    base = mh2o
    for i in range(256):
        oi, count, _ = struct.unpack_from("<III", data, base + i * 12)
        iy, ix = divmod(i, 16)
        for k in range(count):
            ltype, lvf_obj, lo, hi, xo, yo, w, h, ob, ov = struct.unpack_from("<HHffBBBBII", data, base + oi + k * 24)
            lvf, bad = liq.info(ltype, lvf_obj)
            exists = np.ones((h, w), dtype=bool)
            if ob:
                bits = np.unpackbits(np.frombuffer(data, dtype=np.uint8, count=(w * h + 7) // 8, offset=base + ob),
                                     bitorder="little")[:w * h]
                exists = bits.reshape(h, w).astype(bool)
            if ov and lvf in (0, 1, 3):
                hv = np.frombuffer(data, dtype="<f4", count=(w + 1) * (h + 1), offset=base + ov).reshape(h + 1, w + 1)
                hv = np.where(np.isfinite(hv) & (np.abs(hv) < 20000), hv, hi).astype(np.float64)
            else:
                hv = np.full((h + 1, w + 1), hi, dtype=np.float64)
            n0 = MAX - ty * TILE - iy * CHUNK - yo * SUB
            w0 = MAX - tx * TILE - ix * CHUNK - xo * SUB
            rr, cc = np.mgrid[0:h + 1, 0:w + 1]
            ns, ws = (n0 - rr * SUB).ravel(), (w0 - cc * SUB).ravel()
            tris = []
            for r in range(h):
                for c in range(w):
                    if exists[r, c]:
                        a, b = r * (w + 1) + c, r * (w + 1) + c + 1
                        d, e = a + w + 1, b + w + 1
                        tris += [(a, d, e), (a, e, b)]
            soup.add(ns, ws, hv.ravel(), tris, 2 if bad else 1)


# ---------------------------------------------------------------------------------------------
# Models and buildings
# ---------------------------------------------------------------------------------------------

def quat_matrix(x, y, z, w):
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])


def wmo_liquid(data, off, size, kind):
    """A building group's liquid (MLIQ): (verts, tris, kind) in the building's space, or None. Its
    grid of xtiles x ytiles cells (SUB yards) from its corner; a tile with flags & 0xF == 0xF is dry."""
    if size < 30:
        return None
    xv, yv, xt, yt = struct.unpack_from("<4I", data, off)
    cx, cy, cz = struct.unpack_from("<3f", data, off + 16)
    if not (xt and yt and xv == xt + 1 and yv == yt + 1) or off + 30 + xv * yv * 8 + xt * yt > off + size:
        return None
    hv = np.frombuffer(data, "<f4", xv * yv * 2, off + 30)[1::2].astype(np.float64)
    hv = np.where(np.isfinite(hv) & (np.abs(hv) < 20000), hv, cz)
    tiles = np.frombuffer(data, np.uint8, xt * yt, off + 30 + xv * yv * 8)
    gx, gy = np.meshgrid(np.arange(xv), np.arange(yv))
    verts = np.stack([cx + gx.ravel() * SUB, cy + gy.ravel() * SUB, hv], 1)
    tris = []
    for j in range(yt):
        for i in range(xt):
            if tiles[j * xt + i] & 0xF == 0xF:
                continue
            a = j * xv + i
            tris += [(a, a + 1, a + xv + 1), (a, a + xv + 1, a + xv)]
    return (verts, np.array(tris, dtype=np.int64), kind) if tris else None


class Wmo:
    """A building's collidable triangles in its own space (z up), its liquids, and its doodads by set."""

    def __init__(self, casc, fdid, m2cache, liq=None):
        self.verts, self.tris = np.zeros((0, 3)), np.zeros((0, 3), dtype=np.int64)
        self.liquids = []
        self.sets, self.doodads, self.names = [], [], []
        root = casc.read(fdid)
        if not root:
            return
        top = {}
        for cid, off, size in chunks(root):
            top.setdefault(cid, (off, size))
        n_groups = struct.unpack_from("<I", root, top[b"MOHD"][0] + 4)[0] if b"MOHD" in top else 0
        # Its liquids' types are the game's own (MOHD flag 4), or the old water/ocean/magma/slime.
        root_flags = struct.unpack_from("<H", root, top[b"MOHD"][0] + 60)[0] if b"MOHD" in top else 0
        gfids = []
        if b"GFID" in top:
            off, size = top[b"GFID"]
            gfids = list(struct.unpack_from("<%dI" % (size // 4), root, off))[:n_groups]
        if b"MODS" in top:
            off, size = top[b"MODS"]
            for k in range(size // 32):
                start, count = struct.unpack_from("<II", root, off + k * 32 + 20)
                self.sets.append((start, count))
        if b"MODI" in top:
            off, size = top[b"MODI"]
            self.names = list(struct.unpack_from("<%dI" % (size // 4), root, off))
        if b"MODD" in top:
            off, size = top[b"MODD"]
            for k in range(size // 40):
                word, px, py, pz, qx, qy, qz, qw, scale = struct.unpack_from("<I3f4ff", root, off + k * 40)
                self.doodads.append((word & 0xFFFFFF, (px, py, pz), (qx, qy, qz, qw), scale))
        vs, ts, base = [], [], 0
        for g in gfids:
            data = g and casc.read(g)
            if not data:
                continue
            for cid, off, size in chunks(data):
                if cid != b"MOGP":
                    continue
                sub = {}
                for sid, soff, ssize in chunks(data, off + 0x44, off + size):
                    sub.setdefault(sid, (soff, ssize))
                if b"MLIQ" in sub:
                    gl = struct.unpack_from("<I", data, off + 52)[0]
                    if root_flags & 4 or gl >= 21:
                        bad = bool(liq and liq.types.get(gl, (0, False))[1])
                    else:
                        bad = gl > 0 and (gl - 1) % 4 in (2, 3)
                    lq = wmo_liquid(data, *sub[b"MLIQ"], 2 if bad else 1)
                    if lq:
                        self.liquids.append(lq)
                if b"MOVT" not in sub or not (b"MOPY" in sub or b"MPY2" in sub) or not (b"MOVI" in sub or b"MOVX" in sub):
                    continue
                # Per triangle: flags and material, 1 byte each (MOPY) or 2 (MPY2, newer files).
                if b"MPY2" in sub:
                    po, ps = sub[b"MPY2"]
                    flags = np.frombuffer(data, "<u2", ps // 4 * 2, po)[0::2]
                else:
                    po, ps = sub[b"MOPY"]
                    flags = np.frombuffer(data, np.uint8, ps // 2 * 2, po)[0::2]
                if b"MOVX" in sub:
                    io, isz = sub[b"MOVX"]
                    idx = np.frombuffer(data, "<u4", isz // 4, io).astype(np.int64).reshape(-1, 3)
                else:
                    io, isz = sub[b"MOVI"]
                    idx = np.frombuffer(data, "<u2", isz // 2, io).astype(np.int64).reshape(-1, 3)
                vo, vsz = sub[b"MOVT"]
                v = np.frombuffer(data, "<f4", vsz // 4, vo).astype(np.float64).reshape(-1, 3)
                nt = min(len(idx), len(flags))
                f = flags[:nt]
                keep = ((f & F_COLLISION) != 0) | (((f & F_RENDER) != 0) & ((f & F_DETAIL) == 0))
                t = idx[:nt][keep]
                if len(t):
                    vs.append(v)
                    ts.append(t + base)
                    base += len(v)
        if vs:
            self.verts, self.tris = np.concatenate(vs), np.concatenate(ts)
        self.m2cache = m2cache

    def doodad_meshes(self, casc, sets):
        """The models of the given doodad sets, in the building's space: [(verts, tris)]."""
        out = []
        for s in sets:
            if s >= len(self.sets):
                continue
            start, count = self.sets[s]
            for name, pos, quat, scale in self.doodads[start:start + count]:
                fdid = self.names[name] if name < len(self.names) else 0
                mesh = fdid and bw.m2_collision(casc, fdid, self.m2cache)
                if mesh is None or not fdid:
                    continue
                verts, tris = mesh
                v = verts @ quat_matrix(*quat).T * scale + np.asarray(pos)
                out.append((v, tris))
        return out


def objects(soup, casc, obj, wmo_cache, m2cache, seen, liq=None):
    """A tile's models and buildings."""
    for uid, fdid, pos, rot, scale in bw.doodads(obj):
        if ("m", uid) in seen:
            continue
        seen.add(("m", uid))
        mesh = bw.m2_collision(casc, fdid, m2cache)
        if mesh is None:
            continue
        verts, tris = mesh
        n, w, u = bw.place(verts, pos, rot, scale)
        soup.add(n, w, u, tris)
    for cid, off, size in chunks(obj):
        if cid != b"MODF":
            continue
        for k in range(size // 64):
            e = struct.unpack_from("<II3f3f3f3fHHHH", obj, off + k * 64)
            fdid, uid, pos, rot = e[0], e[1], e[2:5], e[5:8]
            flags, dset, _, scale = e[14], e[15], e[16], e[17]
            if ("w", uid) in seen:
                continue
            seen.add(("w", uid))
            scale = scale / 1024 if scale else 1.0
            wmo = wmo_cache.get(fdid)
            if wmo is None:
                wmo = wmo_cache[fdid] = Wmo(casc, fdid, m2cache, liq)
            if len(wmo.tris):
                n, w, u = bw.place(wmo.verts, pos, rot, scale)
                soup.add(n, w, u, wmo.tris)
            for verts, tris, kind in wmo.liquids:
                n, w, u = bw.place(verts, pos, rot, scale)
                soup.add(n, w, u, tris, kind)
            for verts, tris in wmo.doodad_meshes(casc, sorted({0, dset})):
                n, w, u = bw.place(verts, pos, rot, scale)
                soup.add(n, w, u, tris)


def tile_files(casc, wdt_fdid):
    """{ (row, col): (terrain fdid, obj0 fdid) } of a map's tiles."""
    wdt = casc.read(wdt_fdid)
    top = {cid: (off, size) for cid, off, size in chunks(wdt)}
    off, size = top[b"MAIN"]
    main_flags = struct.unpack_from("<%dI" % (size // 4), wdt, off)
    off, size = top[b"MAID"]
    maid = struct.unpack_from("<%dI" % (size // 4), wdt, off)
    out = {}
    for i in range(4096):
        if main_flags[i * 2] & 1 and maid[i * 8]:
            out[divmod(i, 64)] = (maid[i * 8], maid[i * 8 + 1])
    return out


def extract(casc, files, liq, ty, tx, out, caches=None):
    """One tile's soup (with its neighbours' objects and terrain near its edges) to out."""
    wmo_cache, m2cache = caches or ({}, {})
    soup, seen = Soup(), set()
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            f = files.get((ty + dy, tx + dx))
            if not f:
                continue
            data = casc.read(f[0])
            if data:
                terrain(soup, data, ty + dy, tx + dx)
                liquids(soup, data, ty + dy, tx + dx, liq)
            obj = f[1] and casc.read(f[1])
            if obj:
                objects(soup, casc, obj, wmo_cache, m2cache, seen, liq)
    if soup.n == 0:
        return None
    return soup.write(out, tile_bounds(ty, tx))


def main(argv):
    from casc import Casc  # noqa: E402  (tools/_shared, on the path through build_water)
    mapid, ty, tx = int(argv[0]), int(argv[1]), int(argv[2])
    out = argv[3] if len(argv) > 3 else os.path.join(NAV_DIR, "%d_%d_%d.bin" % (mapid, ty, tx))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    casc = Casc.open()
    build = casc.version
    maps = {int(r["ID"]): int(r["WdtFileDataID"] or 0) for r in bw.wago_table("Map", build)}
    files = tile_files(casc, maps[mapid])
    res = extract(casc, files, bw.Liquids(build), ty, tx, out)
    print("tile %d_%d_%d: %s" % (mapid, ty, tx, res and ("%d vertices, %d triangles -> %s" % (res[0], res[1], out)) or "no tile"))


if __name__ == "__main__":
    main(sys.argv[1:])
