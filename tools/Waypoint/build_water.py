"""Builds Waypoint's land and water map (Data/Water.lua) from the game's own map tiles, so the
route planner knows where you'd have to walk around water, and where swimming across is quicker.

    python -I tools/Waypoint/build_water.py

Reads the local game install (tools/_shared/casc.py, Forever by default; WOW_DIR / WOW_PRODUCT
override) and the liquid tables from wago.tools for the same build (cached in tools/Waypoint/.cache).

For every world map players walk (MAPS), each map tile's terrain heights (MCNK/MCVT) and liquids
(MH2O) are sampled at their 4.17-yard cells, then summed into CELL-sized squares (2 map chunks,
66.7 yards).

Where you can walk: a step between two neighbouring cells is walkable when it rises less than
STEEP per yard, and so is the ground you'd cross: the game draws each cell as four triangles from
its centre to its corners, and a step crosses the triangle on each cell's side facing the other
(climbing no more than HALF_STEEP the way you walk, or no more than a JUMP; a ridge between two
cell centres doesn't show in their heights, but does in those triangles). Deep water is walkable at
its surface (you swim), whatever the ground under it.
Rocks: much of the world's rock (boulders, spires, whole crater walls in Un'Goro) isn't terrain but
models placed on it (MDDF doodads). Each one at least ROCK yards across has its collision mesh
placed the way the game places it and laid over the cells: where its top stands more than CLEAR
yards above the ground, the top is that cell's ground. A rock's sides then rise like cliffs and
can't be climbed; a ramp, a bridge or a tree root you walk on is a slope like any other.
A square's ground: cells joined by walkable steps make regions. Of the regions with at least
MIN_PATCH of their cells in the square, its ground is the one that reaches furthest through the
3x3 squares around it, so a road along a hillside wins over a small hilltop beside it, and two
ledges that only meet far away stay apart. The ground's average height is the square's.
  w  water   at least half of it is water deeper than DEEP (you'd swim)
  h  hazard  a quarter or more is lava, slime or fel
  s  steep   no patch big enough to stand on: a mountain side or cliff face
  l  land    the rest
  v  void    no map tile there (off the edge of the world)
Links: for each of its 8 neighbours, a square can be walked to (a path of walkable steps joins the
two squares' grounds without leaving a 2x2 block of squares that holds both: a real way across,
not two patches that merely touch), or only dropped to (no walkable step, but its side is higher: slide or jump down, never climb back), or
neither. Mountains you can't climb are squares with drops on the way down and no walk links up.
Bends: a walk link only says two squares join; the way between them may zigzag up a hillside or
go round the end of a ridge, and a straight line would point up the slope. Where the straight line
between the two squares' grounds can't be walked, the turns of the real way (fewest cell steps,
then string pulled) are kept, when it swings at least BEND_MIN cells off the line: Waypoint's arrow
and route lines go through them.
Bridges, piers and docks are buildings (WMOs), not terrain, so water under one counts as land:
any water square under a building no bigger than BRIDGE yards across whose top is above the
water (sunken ruins stay water; whole cities are too big to count).
Tunnels and caves run under the terrain, where the map can't see them: PASSAGES (passages.json
beside this script) lists each one's two mouths in world yards and its length, and they're written
as passages[continent] = { { north, west, north, west, yards, name } } for Grid.lua to walk.
Each map is cropped to the squares it uses and written as run-length rows: "12v40l3w...".
Every square also gets a height, in yards: the ground's average, or the water's surface on water
squares and under bridges. Heights are written two characters a square (HEIGHT_CHARS, the yards
plus HEIGHT_BASE), one string per row.

Square (row, col) covers north = MAX - (row + 0.5) * CELL, west = MAX - (col + 0.5) * CELL, in the
same world yards C_Map.GetWorldPosFromMapPos returns.
"""
import collections
import csv
import json
import math
import os
import struct
import sys
import urllib.request

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
ADDON = os.path.join(os.path.dirname(TOOLS), "addons", "Waypoint")  # tools/Waypoint/ builds addons/Waypoint/
OUT = os.environ.get("WATER_OUT") or os.path.join(ADDON, "Data", "Water.lua")  # WATER_OUT: try a build elsewhere
CACHE = os.path.join(HERE, ".cache")
PASSAGES = os.path.join(HERE, "passages.json")  # [ { continent, name, a: [n, w], b: [n, w], yards } ]
sys.path.insert(0, os.path.join(TOOLS, "_shared"))
from casc import Casc  # noqa: E402

TILE = 1600 / 3          # yards per map tile
CHUNK = TILE / 16        # per map chunk
SUB = CHUNK / 8          # per terrain cell
CELL = CHUNK * 2         # per square in the output
MAX = 32 * TILE          # world coordinate of the map's top/left edge
DEEP = 1.7               # yards of water before you swim
# The slope limits come from routes walked in the game (check_water.py checks them): the steepest
# real roads (Felwood's to Felpaw Village, Feralas') climb at most about 47 degrees the way you go,
# the climbs you can't make (out of Tanaris behind Zul'Farrak) about 52. Stricter than this cuts off
# Burning Steppes and Aerie Peak.
STEEP = 1.1              # rise per yard between two cell centres (about 48 degrees), up or down
HALF_STEEP = 1.15        # rise per yard up either half of a step, the way you walk (about 49 degrees)
JUMP = 2                 # yards a jump gets you up: a ledge or a rock no higher you get onto
ROCK = 6                 # yards across a model's collision must be to count as a rock (trees and
                         # posts are smaller and don't change where you can walk)
CLEAR = JUMP             # yards a model must stand above the ground to count: lower you jump onto
MIN_PATCH = 24           # cells (of 256) a square's ground patch needs: under this it's a cliff face
BEND_MARGIN = 8          # cells round a link's two squares its way may swing out to (bends)
BEND_MIN = 3             # cells (12.5 yards) a link's way must swing off the straight line to be kept
BRIDGE = 700             # buildings up to this many yards across can carry you over water
HEIGHT_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
HEIGHT_BASE = 1024       # heights from -1024 to 3071 yards fit in two characters
BEND_OFFSET = 24         # a bend's turn, in cells from its square's corner (-24 to 39), plus this
LINK_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$%&()*+,-."  # no digits: runs are counted

# Map ID (the continent C_Map.GetWorldPosFromMapPos returns) -> name, for the world maps players walk.
MAPS = {0: "Eastern Kingdoms", 1: "Kalimdor", 2991: "Zephras Isle", 2995: "Hyjal Crater", 2980: "Dalaran City"}
HAZARD_WORDS = ("magma", "lava", "slime", "fel - generic")


def wago_table(name, build):
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


def chunks(b, start=0, end=None):
    pos, end = start, end or len(b)
    while pos + 8 <= end:
        cid = b[pos:pos + 4][::-1]
        size = struct.unpack_from("<I", b, pos + 4)[0]
        yield cid, pos + 8, size
        pos += 8 + size


class Liquids:
    """Liquid type -> (vertex format, hazard?) from LiquidType, LiquidMaterial and LiquidObject."""

    def __init__(self, build):
        mats = {r["ID"]: int(r["LVF"]) for r in wago_table("LiquidMaterial", build)}
        self.types = {}
        for r in wago_table("LiquidType", build):
            name = r["Name"].lower()
            hazard = r["SoundBank"] in ("2", "3") or any(w in name for w in HAZARD_WORDS)
            self.types[int(r["ID"])] = (mats.get(r["MaterialID"], 0), hazard)
        self.objects = {int(r["ID"]): int(r["LiquidTypeID"]) for r in wago_table("LiquidObject", build)}

    def info(self, ltype, lvf_or_object):
        lvf, hazard = self.types.get(ltype, (0, False))
        if lvf_or_object < 42:
            lvf = lvf_or_object
        return lvf, hazard


def read_tile(data, liquids):
    """One map tile -> (height, water surface, hazard, outer heights) at its 128x128 terrain cells
    (rows north to south, columns west to east); None where a chunk is missing."""
    height = np.full((128, 128), np.nan, dtype=np.float32)
    outer = np.full((129, 129), np.nan, dtype=np.float32)
    surface = np.full((128, 128), np.nan, dtype=np.float32)
    hazard = np.zeros((128, 128), dtype=bool)
    mh2o = None
    for cid, off, size in chunks(data):
        if cid == b"MCNK":
            ix, iy = struct.unpack_from("<II", data, off + 4)
            z = struct.unpack_from("<3f", data, off + 0x68)[2]
            for sid, soff, ssize in chunks(data, off + 128, off + size):
                if sid == b"MCVT":
                    v = np.frombuffer(data, dtype="<f4", count=145, offset=soff).reshape(-1)
                    rows = [v[r * 17:r * 17 + 9] for r in range(9)]
                    inner = [v[r * 17 + 9:r * 17 + 17] for r in range(8)]
                    outer[iy * 8:iy * 8 + 9, ix * 8:ix * 8 + 9] = np.array(rows) + z
                    height[iy * 8:iy * 8 + 8, ix * 8:ix * 8 + 8] = np.array(inner) + z
                    break
        elif cid == b"MH2O":
            mh2o = (off, size)
    if mh2o:
        base, _ = mh2o
        for i in range(256):
            oi, count, _ = struct.unpack_from("<III", data, base + i * 12)
            iy, ix = divmod(i, 16)
            for k in range(count):
                ltype, lvf_obj, lo, hi, xo, yo, w, h, ob, ov = struct.unpack_from("<HHffBBBBII", data, base + oi + k * 24)
                lvf, bad = liquids.info(ltype, lvf_obj)
                exists = np.ones((h, w), dtype=bool)
                if ob:
                    bits = np.unpackbits(np.frombuffer(data, dtype=np.uint8, count=(w * h + 7) // 8, offset=base + ob),
                                         bitorder="little")[:w * h]
                    exists = bits.reshape(h, w).astype(bool)
                if ov and lvf in (0, 1, 3):
                    verts = np.frombuffer(data, dtype="<f4", count=(w + 1) * (h + 1), offset=base + ov).reshape(h + 1, w + 1)
                    verts = np.where(np.isfinite(verts) & (np.abs(verts) < 20000), verts, hi).astype(np.float64)
                    top = (verts[:-1, :-1] + verts[1:, :-1] + verts[:-1, 1:] + verts[1:, 1:]) / 4
                else:
                    top = np.full((h, w), hi, dtype=np.float32)
                r0, c0 = iy * 8 + yo, ix * 8 + xo
                area = surface[r0:r0 + h, c0:c0 + w]
                area[exists] = np.fmax(area[exists], top[exists])
                if bad:
                    hazard[r0:r0 + h, c0:c0 + w] |= exists
    return height, surface, hazard, outer


def m2_collision(casc, fdid, cache):
    """A model's collision mesh: (vertices Nx3, triangles Mx3), in its own space (z up); None
    without one."""
    if fdid in cache:
        return cache[fdid]
    data = casc.read(fdid)
    mesh = None
    if data and len(data) > 0xE8:
        if data[:4] == b"MD21":
            data = data[8:]                      # the MD20 block, which offsets count from
        n_idx, o_idx = struct.unpack_from("<II", data, 0xD8)
        n_pos, o_pos = struct.unpack_from("<II", data, 0xE0)
        if n_idx >= 3 and n_pos and o_pos + n_pos * 12 <= len(data) and o_idx + n_idx * 2 <= len(data):
            verts = np.frombuffer(data, "<f4", n_pos * 3, o_pos).reshape(n_pos, 3).astype(np.float64)
            tris = np.frombuffer(data, "<u2", n_idx - n_idx % 3, o_idx).reshape(-1, 3).astype(np.int64)
            if tris.max() < n_pos:
                mesh = (verts, tris)
    cache[fdid] = mesh
    return mesh


def doodads(data):
    """A tile's models (MDDF) named by file ID: (unique ID, file ID, position, rotation, scale)."""
    out = []
    for cid, off, size in chunks(data):
        if cid == b"MDDF":
            for k in range(size // 36):
                fdid, uid, px, py, pz, rx, ry, rz, scale, flags = struct.unpack_from("<II3f3fHH", data, off + k * 36)
                if flags & 0x40:                 # named by file ID (every model in these maps)
                    out.append((uid, fdid, (px, py, pz), (rx, ry, rz), scale / 1024))
    return out


def _rot(axis, deg):
    c, s = np.cos(np.radians(deg)), np.sin(np.radians(deg))
    return {"x": np.array([[1, 0, 0], [0, c, -s], [0, s, c]]),
            "y": np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]]),
            "z": np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])}[axis]


def place(verts, pos, rot, scale):
    """A model's vertices placed in the world: (north, west, up) arrays. The game's placement, as map
    editors do it (Noggit): model space turned y-up, then about y by rot.y - 90, z by -rot.x, x by
    rot.z, scaled, and moved to pos (whose x and z count from the map's corner)."""
    yup = np.stack([verts[:, 0], verts[:, 2], -verts[:, 1]], 1) * scale
    m = _rot("y", rot[1] - 90) @ _rot("z", -rot[0]) @ _rot("x", rot[2])
    p = yup @ m.T + np.asarray(pos)
    return MAX - p[:, 2], MAX - p[:, 0], p[:, 1]


def rock_tops(casc, objs):
    """The highest rock over each terrain cell, from every model at least ROCK yards across:
    { (tile row, tile col): 128x128 heights, -inf where there's none }."""
    tops, seen, cache = {}, set(), {}
    for data in objs:
        for uid, fdid, pos, rot, scale in doodads(data):
            if uid in seen:
                continue                         # a model over a tile edge is listed by each tile
            seen.add(uid)
            mesh = m2_collision(casc, fdid, cache)
            if mesh is None:
                continue
            verts, tris = mesh
            span = verts.max(axis=0) - verts.min(axis=0)
            if max(span[0], span[1]) * scale < ROCK or span[2] * scale < CLEAR:
                continue
            n, w, up = place(verts, pos, rot, scale)
            # Cell centres sit at whole numbers of R, C (the cell's row and column on the whole map).
            R, C = (MAX - n) / SUB - 0.5, (MAX - w) / SUB - 0.5
            r0, r1 = int(np.ceil(R.min())), int(np.floor(R.max()))
            c0, c1 = int(np.ceil(C.min())), int(np.floor(C.max()))
            if r1 < r0 or c1 < c0:
                continue
            gr, gc = np.mgrid[r0:r1 + 1, c0:c1 + 1]
            pr, pc = gr.ravel()[:, None].astype(np.float64), gc.ravel()[:, None].astype(np.float64)
            a, b, c = tris[:, 0], tris[:, 1], tris[:, 2]
            ar, ac, br, bc, cr, cc = R[a], C[a], R[b], C[b], R[c], C[c]
            det = (br - ar) * (cc - ac) - (cr - ar) * (bc - ac)
            keep = np.abs(det) > 1e-9                # upright faces cover no ground
            if not keep.any():
                continue
            ar, ac, br, bc, cr, cc, det = ar[keep], ac[keep], br[keep], bc[keep], cr[keep], cc[keep], det[keep]
            ua, ub, uc = up[a][keep], up[b][keep], up[c][keep]
            l1 = ((pr - ar) * (cc - ac) - (cr - ar) * (pc - ac)) / det
            l2 = ((br - ar) * (pc - ac) - (pr - ar) * (bc - ac)) / det
            inside = (l1 >= -1e-6) & (l2 >= -1e-6) & (l1 + l2 <= 1 + 1e-6)
            z = np.where(inside, ua + l1 * (ub - ua) + l2 * (uc - ua), -np.inf).max(axis=1)
            hit = np.isfinite(z)
            for r, cl, h in zip(gr.ravel()[hit], gc.ravel()[hit], z[hit]):
                key = (r // 128, cl // 128)
                t = tops.get(key)
                if t is None:
                    t = tops[key] = np.full((128, 128), -np.inf)
                if h > t[r % 128, cl % 128]:
                    t[r % 128, cl % 128] = h
    return tops


def flat_sides(height, outer, deep):
    """Which of each cell's four triangles (centre to two corners each, the way the game draws the
    terrain) you can walk up: out of the cell that way ("out_" + side), or into it from that side
    ("in_" + side). Only the climb counts, the way you walk: from the centre to the middle of that
    edge (or back) it rises no more than HALF_STEEP per yard, or no more than a jump. Going down a
    steep bit is fine (you slide), and ground tilted steeply to the side of a road is still walked
    (Felwood's); a ridge between two cell centres isn't. A dict of 128x128 masks, "out_n" .. "in_e".
    Deep water counts as flat: you swim over it."""
    nw, ne, sw, se = outer[:-1, :-1], outer[:-1, 1:], outer[1:, :-1], outer[1:, 1:]
    edges = {"n": (nw + ne) / 2, "s": (sw + se) / 2, "w": (nw + sw) / 2, "e": (ne + se) / 2}
    lim = max(HALF_STEEP * SUB / 2, JUMP)
    out = {}
    with np.errstate(invalid="ignore"):
        for side, mid in edges.items():
            rise = mid - height                          # going out that way: up when positive
            out["out_" + side] = deep | (rise <= lim)
            out["in_" + side] = deep | (-rise <= lim)
    return out


def spread(start, eff, walk, uphill):
    """Cells of each square you can get to from start (uphill False: walking, or sliding down any
    drop) or that can get to start (uphill True), by steps inside the square."""
    lim = STEEP * SUB
    col = np.arange(127) % 16 != 15
    got = start.copy()
    for _ in range(300):
        new = got.copy()
        # left/right and up/down neighbours, inside one square
        for axis in (0, 1):
            a = slice(None, -1)
            b = slice(1, None)
            if axis == 1:
                pa, pb, inside = (slice(None), a), (slice(None), b), col[None, :]
            else:
                pa, pb, inside = (a, slice(None)), (b, slice(None)), col[:, None]
            ea, eb = eff[pa], eff[pb]
            both = walk[pa] & walk[pb] & inside
            with np.errstate(invalid="ignore"):
                if uphill:
                    # into X from Y: the step Y -> X rises at most lim
                    new[pa] |= got[pb] & both & (eb - ea <= lim)
                    new[pb] |= got[pa] & both & (ea - eb <= lim)
                else:
                    # out of X to Y: the step X -> Y rises at most lim (any drop is fine)
                    new[pb] |= got[pa] & both & (eb - ea <= lim)
                    new[pa] |= got[pb] & both & (ea - eb <= lim)
        if np.array_equal(new, got):
            break
        got = new
    return got


def analyze(height, surface, hazard, outer, rocks=None):
    """A tile's 128x128 terrain cells -> kinds 8x8 ("l" until the squares' ground is chosen, then
    "s" where there's none), level 8x8 (water surface), eff 128x128 (ground height, the water's
    surface where it's deep, or a rock's top), walk 128x128 (every cell you can stand in), flat
    (flat_sides: which way each triangle can be walked up). rocks: rock_tops for this tile."""
    missing = np.isnan(height)
    deep = ((surface - height) > DEEP) & ~np.isnan(surface)
    eff = np.where(deep, surface, height).astype(np.float32)
    walk = ~missing & ~hazard
    flat = flat_sides(height, outer, deep)
    if rocks is not None:
        # Where a model stands over the ground, its top is the ground: a rock's sides are cliffs, a
        # ramp or a root you walk up is a slope like any other (judged by its heights, cell to cell).
        with np.errstate(invalid="ignore"):
            covered = rocks > eff + CLEAR
        eff = np.where(covered, rocks, eff).astype(np.float32)
        for side in flat:
            flat[side] = flat[side] | covered

    def per_square(a):
        return a.reshape(8, 16, 8, 16).sum(axis=(1, 3))

    n = 256
    kinds = np.full((8, 8), "l", dtype="<U1")
    kinds[per_square(deep) >= 0.5 * n] = "w"
    kinds[per_square(hazard) >= 0.25 * n] = "h"
    kinds[per_square(missing) >= 0.5 * n] = "v"
    per = surface.reshape(8, 16, 8, 16).transpose(0, 2, 1, 3).reshape(8, 8, 256)
    wet = ~np.isnan(per)
    level = np.where(wet.any(axis=2), np.nansum(per, axis=2) / np.maximum(wet.sum(axis=2), 1), np.nan)
    return kinds, level, eff, walk, flat


# Steps between squares, in Grid.lua's order (its STEPS): bit k of a square's links is direction k.
DIRS = [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)]


def cell_steps(eff, walk, flat):
    """The walkable steps between neighbouring cells, over a whole map, each way: east[r, c] from
    cell (r, c) to (r, c + 1), west[r, c] back from (r, c + 1) to (r, c); south[r, c] from (r, c) to
    (r + 1, c), north[r, c] back. A step is walkable when both cells can be stood in, it rises or
    falls no more than STEEP per yard between their centres (or a jump), and the two triangles it
    crosses can be walked up the way it goes (flat_sides)."""
    lim = max(STEEP * SUB, JUMP)
    with np.errstate(invalid="ignore"):
        across = walk[:, :-1] & walk[:, 1:] & (np.abs(eff[:, 1:] - eff[:, :-1]) <= lim)
        down = walk[:-1, :] & walk[1:, :] & (np.abs(eff[1:, :] - eff[:-1, :]) <= lim)
    east = across & flat["out_e"][:, :-1] & flat["in_w"][:, 1:]
    west = across & flat["out_w"][:, 1:] & flat["in_e"][:, :-1]
    south = down & flat["out_s"][:-1, :] & flat["in_n"][1:, :]
    north = down & flat["out_n"][1:, :] & flat["in_s"][:-1, :]
    return east, west, south, north


def regions(across, down, alive, size, off_r, off_c):
    """Cells joined by walkable steps without leaving their block: blocks of size x size squares,
    the first starting off_r, off_c squares in (blocks are cut short at the map's edges). Each cell's
    label is the index (row * width + column) of one of its region's cells; -1 outside alive.
    Blocks are worked out side by side, and ones nobody can stand in are skipped."""
    nr, nc = alive.shape
    B = size * 16
    pt, pl = (-off_r % size) * 16, (-off_c % size) * 16   # padding so a block starts at row/col 0
    Hp, Wp = -(-(nr + pt) // B) * B, -(-(nc + pl) // B) * B
    nbr, nbc = Hp // B, Wp // B

    def blocks(x):
        out = np.zeros((Hp, Wp), dtype=bool)
        out[pt:pt + x.shape[0], pl:pl + x.shape[1]] = x
        return out.reshape(nbr, B, nbc, B).transpose(0, 2, 1, 3).reshape(-1, B, B)

    A = blocks(alive)
    keep = np.flatnonzero(A.any(axis=(1, 2)))
    A = A[keep]
    a = blocks(across)[keep][:, :, :B - 1]                  # steps that stay inside the block
    d = blocks(down)[keep][:, :B - 1, :]
    n = len(keep)
    none = np.int32(n * B * B)
    lab = np.where(A, np.arange(n * B * B, dtype=np.int32).reshape(n, B, B), none)
    while True:
        new = lab.copy()
        np.minimum(new[:, :, :-1], np.where(a, lab[:, :, 1:], none), out=new[:, :, :-1])
        np.minimum(new[:, :, 1:], np.where(a, lab[:, :, :-1], none), out=new[:, :, 1:])
        np.minimum(new[:, :-1, :], np.where(d, lab[:, 1:, :], none), out=new[:, :-1, :])
        np.minimum(new[:, 1:, :], np.where(d, lab[:, :-1, :], none), out=new[:, 1:, :])
        # Jump to the label's own label: regions settle in a few dozen rounds, not their length.
        for _ in range(2):
            new = np.append(new.ravel(), none)[new]            # "none" points at itself
        if np.array_equal(new, lab):
            break
        lab = new
    # Back to the map's own cell indices.
    some = lab < none
    k, loc = np.divmod(lab[some], B * B)
    bi, bj = np.divmod(keep[k], nbc)
    lr, lc = np.divmod(loc, B)
    full = np.full((nbr * nbc, B, B), -1, dtype=np.int32)
    part = np.full(lab.shape, -1, dtype=np.int32)
    part[some] = ((bi * B + lr - pt) * nc + (bj * B + lc - pl)).astype(np.int32)
    full[keep] = part
    full = full.reshape(nbr, nbc, B, B).transpose(0, 2, 1, 3).reshape(Hp, Wp)
    return full[pt:pt + nr, pl:pl + nc]


def choose_ground(across, down, walk):
    """Each square's ground: of the regions with at least MIN_PATCH cells in the square, the one
    that reaches furthest through the 3x3 squares around it (by its cells there). A road along a
    hillside beats a small hilltop beside it; two ledges that only meet far away stay apart.
    Returns usable (the ground's cells; every walkable cell of a square without ground) and main
    (squares with ground)."""
    nr, nc = walk.shape
    sr, sc = nr // 16, nc // 16
    none = np.int64(nr * nc)
    usable = np.zeros_like(walk)
    main = np.zeros((sr, sc), dtype=bool)
    rows = np.arange(nr) // 16
    cols = np.arange(nc) // 16
    sq_of = (rows[:, None] * sc + cols[None, :]).astype(np.int32)    # each cell's square
    for off_r in range(3):
        for off_c in range(3):
            lab = regions(across, down, walk, 3, off_r, off_c)
            blk = (((rows - off_r) // 3)[:, None] * (sc // 3 + 2) + ((cols - off_c) // 3)[None, :]).astype(np.int32)
            live = lab >= 0
            # cells per region in each block
            bkey = blk[live].astype(np.int64) * none + lab[live]
            _, inv, cnt = np.unique(bkey, return_inverse=True, return_counts=True)
            del bkey
            reach = np.zeros(lab.shape, dtype=np.int32)
            reach[live] = cnt[inv]
            del inv
            # the squares at the middle of their block, and their regions' cells in the square
            mid = (((rows - off_r) % 3) == 1)[:, None] & (((cols - off_c) % 3) == 1)[None, :] & live
            skey = sq_of[mid].astype(np.int64) * none + lab[mid]
            us, sinv, scnt = np.unique(skey, return_inverse=True, return_counts=True)
            sreach = np.zeros(len(us), dtype=np.int64)
            sreach[sinv] = reach[mid]
            ok = scnt >= MIN_PATCH
            us, sreach, scnt = us[ok], sreach[ok], scnt[ok]
            if len(us) == 0:
                continue
            sq = us // none
            order = np.lexsort((scnt, sreach, sq))             # by square, then reach, then size
            last = np.r_[sq[order][1:] != sq[order][:-1], True]
            pick = order[last]
            chosen = np.full(sr * sc, -1, dtype=np.int32)
            chosen[sq[pick]] = us[pick] % none
            main.ravel()[sq[pick]] = True
            usable |= mid & (lab == chosen[sq_of])
    # A square without ground: all of it you can stand on (it's a cliff face, slid down).
    no = ~np.repeat(np.repeat(main, 16, axis=0), 16, axis=1)
    usable |= no & walk
    return usable, main


def walk_links(steps, usable, main):
    """Walk links between squares, each way: from A to B when both have ground and you can walk
    from A's ground to B's (steps: cell_steps, so only the climbs the way you go count) without
    leaving a 2x2 block of squares that holds both (a way round through the squares beside them
    counts, a long detour doesn't). Returns uint8 bits per square, in DIRS order."""
    east, west, south, north = steps
    nr, nc = usable.shape
    sr, sc = nr // 16, nc // 16
    bits = np.zeros((sr, sc), dtype=np.uint8)
    ground = usable & np.repeat(np.repeat(main, 16, axis=0), 16, axis=1)
    B = 32
    for off_r in range(2):
        for off_c in range(2):
            pt, pl = off_r * 16, off_c * 16            # padding so a block starts at row/col 0
            Hp, Wp = -(-(nr + pt) // B) * B, -(-(nc + pl) // B) * B
            nbr, nbc = Hp // B, Wp // B

            def blocks(x):
                out = np.zeros((Hp, Wp), dtype=bool)
                out[pt:pt + x.shape[0], pl:pl + x.shape[1]] = x
                return out.reshape(nbr, B, nbc, B).transpose(0, 2, 1, 3).reshape(-1, B, B)

            G = blocks(ground)
            keep = np.flatnonzero(G.any(axis=(1, 2)))
            G = G[keep]
            e, w = blocks(east)[keep][:, :, :B - 1], blocks(west)[keep][:, :, :B - 1]
            s_, n_ = blocks(south)[keep][:, :B - 1, :], blocks(north)[keep][:, :B - 1, :]
            # Each block's four squares are 0 top left, 1 top right, 2 bottom left, 3 bottom right:
            # a cell's bit p is set when square p's ground can walk to it.
            pos = (np.arange(B)[:, None] // 16) * 2 + (np.arange(B)[None, :] // 16)
            got = np.where(G, (1 << pos).astype(np.uint8)[None, :, :], 0).astype(np.uint8)
            while True:
                new = got.copy()
                new[:, :, 1:] |= np.where(e, got[:, :, :-1], 0).astype(np.uint8)
                new[:, :, :-1] |= np.where(w, got[:, :, 1:], 0).astype(np.uint8)
                new[:, 1:, :] |= np.where(s_, got[:, :-1, :], 0).astype(np.uint8)
                new[:, :-1, :] |= np.where(n_, got[:, 1:, :], 0).astype(np.uint8)
                if np.array_equal(new, got):
                    break
                got = new
            # Which squares' ground reaches each square's ground: OR over its ground cells.
            reach = np.zeros((len(keep), 4), dtype=np.uint8)
            for q in range(4):
                qr, qc = divmod(q, 2)
                cells = np.where(G[:, qr * 16:qr * 16 + 16, qc * 16:qc * 16 + 16],
                                 got[:, qr * 16:qr * 16 + 16, qc * 16:qc * 16 + 16], 0)
                reach[:, q] = np.bitwise_or.reduce(cells.reshape(len(keep), -1), axis=1)
            bi, bj = np.divmod(keep, nbc)
            for p in range(4):
                for q in range(4):
                    if p == q:
                        continue
                    (pr, pc), (qr, qc) = divmod(p, 2), divmod(q, 2)
                    k = DIRS.index((qr - pr, qc - pc))
                    # the squares on the map (padding taken off), inside it on both ends
                    ar, ac = bi * 2 + pr - off_r, bj * 2 + pc - off_c
                    br_, bc_ = bi * 2 + qr - off_r, bj * 2 + qc - off_c
                    ok = ((reach[:, q] >> p) & 1 == 1) & (ar >= 0) & (ac >= 0) & (ar < sr) & (ac < sc)                         & (br_ >= 0) & (bc_ >= 0) & (br_ < sr) & (bc_ < sc)
                    bits[ar[ok], ac[ok]] |= np.uint8(1 << k)
    return bits


def bends(steps, usable, main, walk_bits):
    """The way a walk link really goes, where a straight line between the two squares' grounds
    can't be walked: a climb that zigzags up a hillside, a way round the end of a ridge. Returns
    { (square row, square col, direction): [(cell row, cell col), ...] }, the turns in walking
    order (the first square's ground centre and the second's left out), as cells from the first
    square's top left corner; only ways that swing BEND_MIN cells or more off the straight line. The route only knows
    squares, so without these it would point straight up the slope.
    The way is the fewest cell steps from one centre to the other (into the nearest of the second
    square's ground you can get to) inside the two squares and BEND_MARGIN cells round them, and its
    turns are where a straight line stops being walkable (string pulling)."""
    east, west, south, north = steps
    nr, nc = usable.shape
    sr, sc = walk_bits.shape

    def step_ok(r, c, dr, dc):
        if dc == 1:
            return east[r, c]
        if dc == -1:
            return west[r, c - 1]
        if dr == 1:
            return south[r, c]
        return north[r - 1, c]

    def line_ok(a, b):
        # a staircase of single cell steps along the straight line from a to b
        (r, c), (r2, c2) = a, b
        n = max(abs(r2 - r), abs(c2 - c))
        for i in range(1, n + 1):
            tr = round(a[0] + (r2 - a[0]) * i / n)
            tc = round(a[1] + (c2 - a[1]) * i / n)
            if tr != r and tc != c:
                # a diagonal: either way round the corner
                if not ((step_ok(r, c, tr - r, 0) and step_ok(tr, c, 0, tc - c))
                        or (step_ok(r, c, 0, tc - c) and step_ok(r, tc, tr - r, 0))):
                    return False
            elif tr != r or tc != c:
                if not step_ok(r, c, tr - r, tc - c):
                    return False
            r, c = tr, tc
        return True

    centres = {}

    def centre(qr, qc):
        if (qr, qc) not in centres:
            cells = np.argwhere(usable[qr * 16:qr * 16 + 16, qc * 16:qc * 16 + 16])
            if len(cells) == 0:
                centres[(qr, qc)] = None
            else:
                d = ((cells - 7.5) ** 2).sum(axis=1)
                r, c = cells[int(d.argmin())]
                centres[(qr, qc)] = (qr * 16 + int(r), qc * 16 + int(c))
        return centres[(qr, qc)]

    out = {}
    for qr, qc in np.argwhere(main & (walk_bits != 0)):
        a = centre(qr, qc)
        for k, (dr, dc) in enumerate(DIRS):
            if not walk_bits[qr, qc] >> k & 1:
                continue
            br, bc = qr + dr, qc + dc
            if not (0 <= br < sr and 0 <= bc < sc and main[br, bc]):
                continue
            b = centre(br, bc)
            if a is None or b is None or line_ok(a, b):
                continue
            r0 = max(0, min(qr, br) * 16 - BEND_MARGIN)
            r1 = min(nr, (max(qr, br) + 1) * 16 + BEND_MARGIN)
            c0 = max(0, min(qc, bc) * 16 - BEND_MARGIN)
            c1 = min(nc, (max(qc, bc) + 1) * 16 + BEND_MARGIN)
            prev = {a: None}
            queue = collections.deque([a])
            found = None
            while queue:
                u = queue.popleft()
                if u == b:
                    found = b
                    break
                ur, uc = u
                for vr, vc in ((ur, uc + 1), (ur, uc - 1), (ur + 1, uc), (ur - 1, uc)):
                    if r0 <= vr < r1 and c0 <= vc < c1 and (vr, vc) not in prev \
                            and step_ok(ur, uc, vr - ur, vc - uc):
                        prev[(vr, vc)] = u
                        queue.append((vr, vc))
            if found is None:
                # the nearest of the second square's ground the first's reaches
                best = None
                for (vr, vc) in prev:
                    if vr // 16 == br and vc // 16 == bc and usable[vr, vc]:
                        d = (vr - b[0]) ** 2 + (vc - b[1]) ** 2
                        if best is None or d < best[0]:
                            best = (d, (vr, vc))
                if best is None:
                    continue
                found = best[1]
            path = [found]
            while path[-1] != a:
                path.append(prev[path[-1]])
            path.reverse()
            turns, i = [], 0
            while i < len(path) - 1:
                j = len(path) - 1
                while j > i + 1 and not line_ok(path[i], path[j]):
                    j -= 1
                if j < len(path) - 1:
                    turns.append(path[j])
                i = j
            # Only a way that swings well off the straight line: a wiggle round a rock or two doesn't
            # change where to point.
            length = math.hypot(b[0] - a[0], b[1] - a[1]) or 1
            off = max((abs((b[0] - a[0]) * (a[1] - tc) - (a[0] - tr) * (b[1] - a[1])) / length
                       for tr, tc in turns), default=0)
            if off >= BEND_MIN:
                # as cells from the first square's top left corner
                out[(int(qr), int(qc), k)] = [(tr - qr * 16, tc - qc * 16) for tr, tc in turns[:63]]
    return out


def drop_links(eff, reach_cells, back_cells, main, tall, walk_bits):
    """Drop links: no walk, but this square's ground is higher than the neighbour's, and along the
    edge a cell you can get to from this square's ground (walking, or sliding down a cliff face)
    is higher than a cell of the neighbour's that leads on to its ground: you can get down (slide
    or jump), never back up. A cliff you can't get to the top of (behind a ridge or a fence of
    rock) isn't a drop. Returns uint8 bits per square, in DIRS order."""
    nr, nc = main.shape
    drop = np.zeros((nr, nc), dtype=np.uint8)
    Sa = np.where(reach_cells, eff, np.nan)
    Sb = np.where(back_cells, eff, np.nan)

    def border(dr, dc, E):
        """The cells of each square on the side facing (dr, dc), and its neighbour's facing back,
        for the squares that have that neighbour: (a, b, square rows, square cols)."""
        def pick(side, d):
            # the row (or column) offsets of the edge cells facing direction d
            return {-1: 0, 1: 15}[d] if d else None
        rows_a = slice(1, nr) if dr == -1 else slice(0, nr - 1) if dr == 1 else slice(0, nr)
        cols_a = slice(1, nc) if dc == -1 else slice(0, nc - 1) if dc == 1 else slice(0, nc)
        ra, ca = np.arange(nr)[rows_a], np.arange(nc)[cols_a]
        if dr and dc:                                           # a corner cell each
            ar, ac = ra * 16 + pick(0, dr), ca * 16 + pick(0, dc)
            br, bc = (ra + dr) * 16 + pick(0, -dr), (ca + dc) * 16 + pick(0, -dc)
            a = E[np.ix_(ar, ac)][..., None]
            b = E[np.ix_(br, bc)][..., None]
        elif dr:                                                # a row of 16 cells each
            ar, br = ra * 16 + pick(0, dr), (ra + dr) * 16 + pick(0, -dr)
            cols = (ca[:, None] * 16 + np.arange(16)[None, :]).ravel()
            a = E[np.ix_(ar, cols)].reshape(len(ra), len(ca), 16)
            b = E[np.ix_(br, cols)].reshape(len(ra), len(ca), 16)
        else:                                                   # a column of 16 cells each
            ac, bc = ca * 16 + pick(0, dc), (ca + dc) * 16 + pick(0, -dc)
            rows = (ra[:, None] * 16 + np.arange(16)[None, :]).ravel()
            a = E[np.ix_(rows, ac)].reshape(len(ra), 16, len(ca)).transpose(0, 2, 1)
            b = E[np.ix_(rows, bc)].reshape(len(ra), 16, len(ca)).transpose(0, 2, 1)
        return a, b, ra, ca

    with np.errstate(invalid="ignore"):
        for k, (dr, dc) in enumerate(DIRS):
            sa, _, ra, ca = border(dr, dc, Sa)
            _, sb, _, _ = border(dr, dc, Sb)
            reach = np.where(~np.isnan(sa) & ~np.isnan(sb), sa > sb, False).any(axis=2)
            down = reach & (tall[np.ix_(ra, ca)] > tall[np.ix_(ra + dr, ca + dc)] + 1)
            bit = np.uint8(1 << k)
            w = (walk_bits[np.ix_(ra, ca)] & bit) != 0
            d = ~w & down
            drop[np.ix_(ra, ca)] |= np.where(d, bit, 0).astype(np.uint8)
    return drop


def buildings(data):
    """A tile's buildings (MODF): (north min, north max, west min, west max, top height)."""
    out = []
    for cid, off, size in chunks(data):
        if cid == b"MODF":
            for k in range(size // 64):
                e = struct.unpack_from("<II3f3f3f3f", data, off + k * 64)
                lo, hi = e[8:11], e[11:14]
                out.append((MAX - hi[2], MAX - lo[2], MAX - hi[0], MAX - lo[0], hi[1]))
    return out


def build_map(casc, wdt_fdid, liquids):
    wdt = casc.read(wdt_fdid)
    if not wdt:
        return None
    top = {cid: (off, size) for cid, off, size in chunks(wdt)}
    off, size = top[b"MAIN"]
    main_flags = struct.unpack_from("<%dI" % (size // 4), wdt, off)
    off, size = top[b"MAID"]
    maid = struct.unpack_from("<%dI" % (size // 4), wdt, off)
    grid = np.full((512, 512), "v", dtype="<U1")
    level = np.full((512, 512), np.nan)
    tall = np.zeros((512, 512))
    cells = {}   # (ty, tx) -> (eff, walk, flat)
    wmos = {}
    used = [i for i in range(4096) if main_flags[i * 2] & 1 and maid[i * 8]]
    # Models first: a rock over a tile edge is placed from one tile but stands on both.
    objs = {}
    for i in used:
        obj = maid[i * 8 + 1] and casc.read(maid[i * 8 + 1])
        if obj:
            objs[i] = obj
            for b in buildings(obj):
                wmos[b] = True
    rocks = rock_tops(casc, objs.values())
    print("  rock over %d tiles" % len(rocks))
    for i in used:
        data = casc.read(maid[i * 8])
        if not data:
            continue
        ty, tx = divmod(i, 64)
        rows, cols = slice(ty * 8, ty * 8 + 8), slice(tx * 8, tx * 8 + 8)
        height, surface, hazard, outer = read_tile(data, liquids)
        grid[rows, cols], level[rows, cols], eff, walk, flat = analyze(height, surface, hazard, outer, rocks.get((ty, tx)))
        cells[(ty, tx)] = (eff, walk, flat)
    if not cells:
        return None
    # Over the tiles' bounding box at cell resolution: where you can walk, each square's ground.
    tys = [t[0] for t in cells]
    txs = [t[1] for t in cells]
    ty0, tx0 = min(tys), min(txs)
    nty, ntx = max(tys) - ty0 + 1, max(txs) - tx0 + 1
    eff_all = np.full((nty * 128, ntx * 128), np.nan, dtype=np.float32)
    walk_all = np.zeros((nty * 128, ntx * 128), dtype=bool)
    flat_all = {side: np.zeros((nty * 128, ntx * 128), dtype=bool) for side in cells[next(iter(cells))][2]}
    for (ty, tx), (eff, walk, flat) in cells.items():
        y, x = (ty - ty0) * 128, (tx - tx0) * 128
        eff_all[y:y + 128, x:x + 128] = eff
        walk_all[y:y + 128, x:x + 128] = walk
        for side in flat:
            flat_all[side][y:y + 128, x:x + 128] = flat[side]
    steps = cell_steps(eff_all, walk_all, flat_all)
    del flat_all
    # A square's ground: cells joined by steps you can take both ways, so anywhere on it you can get
    # to anywhere else (one-way steps, down a ledge, only count between squares: walk_links).
    use_all, main_all = choose_ground(steps[0] & steps[1], steps[2] & steps[3], walk_all)
    box = (slice(ty0 * 8, (ty0 + nty) * 8), slice(tx0 * 8, (tx0 + ntx) * 8))
    gb = grid[box]
    gb[(gb == "l") & ~main_all] = "s"
    sums = np.where(use_all, eff_all, 0).reshape(nty * 8, 16, ntx * 8, 16).sum(axis=(1, 3))
    counts = use_all.reshape(nty * 8, 16, ntx * 8, 16).sum(axis=(1, 3))
    tall[box] = np.where(counts > 0, sums / np.maximum(counts, 1), 0)
    # Bridges, piers and docks: water under them is land at the water's level, walkable every way.
    bridges = []
    for n0, n1, w0, w1, top_h in wmos:
        if n1 - n0 > BRIDGE or w1 - w0 > BRIDGE:
            continue
        r0, r1 = int((MAX - n1) // CELL), int((MAX - n0) // CELL)
        c0, c1 = int((MAX - w1) // CELL), int((MAX - w0) // CELL)
        for r in range(max(r0, 0), min(r1, 511) + 1):
            for c in range(max(c0, 0), min(c1, 511) + 1):
                if grid[r, c] == "w" and top_h > level[r, c] + 2:
                    grid[r, c] = "l"
                    tall[r, c] = level[r, c]  # the deck, about
                    bridges.append((r, c))
    print("  %d water squares under bridges and piers" % len(bridges))
    # Links. The drops need, per square, the cells you can get to from its ground and back to it.
    reach_all = np.zeros_like(walk_all)
    back_all = np.zeros_like(walk_all)
    for (ty, tx) in cells:
        y, x = (ty - ty0) * 128, (tx - tx0) * 128
        part = (slice(y, y + 128), slice(x, x + 128))
        reach_all[part] = spread(use_all[part], eff_all[part], walk_all[part], False)
        back_all[part] = spread(use_all[part], eff_all[part], walk_all[part], True)
    walk_box = walk_links(steps, use_all, main_all)
    drop_box = drop_links(eff_all, reach_all, back_all, main_all, tall[box], walk_box)
    bend = {(qr + ty0 * 8, qc + tx0 * 8, k): turns
            for (qr, qc, k), turns in bends(steps, use_all, main_all, walk_box).items()}
    print("  %d links bend (a zigzag or a way round, kept as its turns)" % len(bend))
    walk = np.zeros((512, 512), dtype=np.uint8)
    drop = np.zeros((512, 512), dtype=np.uint8)
    walk[ty0 * 8:(ty0 + nty) * 8, tx0 * 8:(tx0 + ntx) * 8] = walk_box
    drop[ty0 * 8:(ty0 + nty) * 8, tx0 * 8:(tx0 + ntx) * 8] = drop_box
    for r, c in bridges:
        for k, (dr, dc) in enumerate(DIRS):
            rr, cc = r + dr, c + dc
            if 0 <= rr < 512 and 0 <= cc < 512 and grid[rr, cc] not in ("v", "h"):
                back = DIRS.index((-dr, -dc))
                walk[r, c] |= 1 << k
                walk[rr, cc] |= 1 << back
                drop[r, c] &= ~np.uint8(1 << k)
                drop[rr, cc] &= ~np.uint8(1 << back)
    return grid, len(cells), tall, walk, drop, bend


def rle(row):
    out, run, prev = [], 0, None
    for ch in row:
        if ch == prev:
            run += 1
        else:
            if prev is not None:
                out.append("%d%s" % (run, prev) if run > 1 else prev)
            prev, run = ch, 1
    out.append("%d%s" % (run, prev) if run > 1 else prev)
    return "".join(out)


def bend_row(bend, r, c0, c1):
    """A row of squares' bends (bends()), in HEIGHT_CHARS: per bending link its column from c0 (two
    characters), direction, number of turns, then each turn as two characters (cell row and column
    from the square's top left corner, plus BEND_OFFSET)."""
    out = []
    for (br, bc, k), turns in sorted(bend.items()):
        if br != r or not c0 <= bc <= c1:
            continue
        c = bc - c0
        out.append(HEIGHT_CHARS[c // 64] + HEIGHT_CHARS[c % 64] + HEIGHT_CHARS[k] + HEIGHT_CHARS[len(turns)])
        for tr, tc in turns:
            out.append(HEIGHT_CHARS[tr + BEND_OFFSET] + HEIGHT_CHARS[tc + BEND_OFFSET])
    return "".join(out)


def heights(row):
    out = []
    for h in row:
        v = int(min(max(round(h) + HEIGHT_BASE, 0), 4095))
        out.append(HEIGHT_CHARS[v // 64] + HEIGHT_CHARS[v % 64])
    return "".join(out)


def link_row(walk, drop):
    """A row of squares' links, three characters each (walk | drop << 8, base 64), runs counted:
    "40AAA" is 40 squares of "AAA"."""
    tokens = []
    for w, d in zip(walk, drop):
        v = int(w) | (int(d) << 8)
        tokens.append(LINK_CHARS[v >> 12] + LINK_CHARS[(v >> 6) & 63] + LINK_CHARS[v & 63])
    out, run, prev = [], 0, None
    for t in tokens + [None]:
        if t == prev:
            run += 1
            continue
        if prev is not None:
            out.append(("%d" % run if run > 1 else "") + prev)
        prev, run = t, 1
    return "".join(out)


def main():
    casc = Casc.open()
    build = casc.version
    maps = {int(r["ID"]): int(r["WdtFileDataID"] or 0) for r in wago_table("Map", build)}
    liquids = Liquids(build)
    lines = [
        "-- GENERATED by tools/Waypoint/build_water.py from the game's map tiles (%s). Do not edit." % build,
        "-- Land and water in %.4g-yard squares: w water (you'd swim), h lava/slime/fel, s steep," % CELL,
        "-- l land, v off the map. maps[continent] = { r0, c0 (first row and column), rows = { run-length",
        "-- rows: \"12v40l3w\" }, heights = { two characters a square: yards + %d, base 64 (%s) } };" % (HEIGHT_BASE, "A-Z a-z 0-9 + /"),
        "-- links = { three characters a square, base 64 (%s), runs counted (\"40AAA\"): walk | drop << 8," % "A-Z a-z ! # $ % & ( ) * + , - .",
        "-- bit k = the step in direction k (Grid.lua's STEPS) },",
        "-- bends = { a row's links that zigzag or go round (build_water.py bend_row): column (2), direction,",
        "-- turns, then each turn's cell row and column from the square's corner + %d; %.4g-yard cells } }." % (BEND_OFFSET, SUB),
        "-- square (r, c) is at north = max - (r + 0.5) * cell, west = max - (c + 0.5) * cell.",
        "-- passages[continent] = { { north, west, north, west, yards, name } }: tunnels and caves, mouth to mouth.",
        "local _, ns = ...",
        "ns.Water = { cell = %.6f, max = %.6f, maps = {" % (CELL, MAX),
    ]
    for mid, name in MAPS.items():
        fdid = maps.get(mid)
        res = fdid and build_map(casc, fdid, liquids)
        if not res:
            print("skipped %s (%d): no map" % (name, mid))
            continue
        grid, tiles, tall, walk, drop, bend = res
        used = np.argwhere(grid != "v")
        r0, c0 = used.min(axis=0)
        r1, c1 = used.max(axis=0)
        crop = grid[r0:r1 + 1, c0:c1 + 1]
        counts = {k: int((crop == k).sum()) for k in "lwshv"}
        print("%s (%d): %d tiles, %dx%d squares %s" % (name, mid, tiles, crop.shape[0], crop.shape[1], counts))
        wc, dc = walk[r0:r1 + 1, c0:c1 + 1], drop[r0:r1 + 1, c0:c1 + 1]
        land = crop != "v"
        print("  links: %.0f%% of steps walkable, %d drop-only steps" % (
            100 * np.unpackbits(wc[land][:, None], axis=1).sum() / max(1, 8 * land.sum()),
            int(np.unpackbits(dc[land][:, None], axis=1).sum())))
        lines.append("    [%d] = { -- %s" % (mid, name))
        lines.append("        r0 = %d, c0 = %d, rows = {" % (r0, c0))
        for row in crop:
            lines.append('            "%s",' % rle(row))
        lines.append("        },")
        lines.append("        heights = {")
        for row in tall[r0:r1 + 1, c0:c1 + 1]:
            lines.append('            "%s",' % heights(row))
        lines.append("        },")
        lines.append("        links = {")
        for wr, dr in zip(walk[r0:r1 + 1, c0:c1 + 1], drop[r0:r1 + 1, c0:c1 + 1]):
            lines.append('            "%s",' % link_row(wr, dr))
        lines.append("        },")
        lines.append("        bends = {")
        for r in range(r0, r1 + 1):
            lines.append('            "%s",' % bend_row(bend, r, c0, c1))
        lines.append("        },")
        lines.append("    },")
    lines.append("}, passages = {")
    passages = {}
    if os.path.exists(PASSAGES):
        with open(PASSAGES, encoding="utf-8") as f:
            for p in json.load(f):
                passages.setdefault(int(p["continent"]), []).append(p)
    for cont, ps in sorted(passages.items()):
        lines.append("    [%d] = {" % cont)
        for p in ps:
            lines.append('        { %.1f, %.1f, %.1f, %.1f, %d, "%s" },' % (
                p["a"][0], p["a"][1], p["b"][0], p["b"][1], round(p["yards"]), p["name"].replace('"', "'")))
        lines.append("    },")
    print("%d passages (tunnels and caves)" % sum(len(v) for v in passages.values()))
    lines.append("} }")
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print("wrote", OUT, "%.0f KB" % (os.path.getsize(OUT) / 1024))


if __name__ == "__main__":
    main()
