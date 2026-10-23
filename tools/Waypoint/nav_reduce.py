"""Reduces a baked tile (nav_bake.mjs's .chf, Recast's walkable floors at CS yards) to nodes the
addon can carry: the floors in each FINE-yard cell, split where they don't join inside it (a wall,
a bridge over a road), with the links between them.

    python -I tools/Waypoint/nav_reduce.py <map>_<row>_<col> ...     (tiles in tools/Waypoint/.nav)

A node: the floors of one cell that join each other (Recast's links, without leaving the cell).
  kind   0 land, 1 water (deeper than DEEP under its surface: you swim, at the surface), 2 lava/slime
  height the floor's height (land: the middle of its floors; water: the surface), and its lowest and
  highest floor (to match a neighbouring tile's links)
  size   how many Recast cells it covers (CS x CS yards each)
Links from a node to a node in one of the 8 neighbouring cells (or the same cell, another floor):
  walk   a Recast link joins them (a step no higher than the CLIMB)
  swim   both are water, side by side (you swim over whatever lies under the water); or water and
         land whose floor is within CLIMB of the water's surface (you climb out)
  drop   no way across, but the floor beyond is lower with open air above it up to your head: you
         jump or fall (its height kept, for fall damage), never climb back
Out: <tile>.npz in tools/Waypoint/.nav: nodes (cell row, cell col, kind, height, low, high (tenths
of a yard), size, middle's offset in the cell from its north and west edges (0-255)) and links (from
node, to tile row offset, to tile col offset, to cell row, to cell col, to height, kind 0 walk /
1 swim / 2 drop, fall (tenths), to node (in this tile; else -1), where it lands (north, west from the
map's corner, tenths)); a link into another tile is matched to its node by nav_stitch.py.
"""
import os
import struct
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
NAV = os.path.join(HERE, ".nav")
TILE = 1600 / 3
MAX = 32 * TILE
FINE_N = 64                    # cells across a tile
FINE = TILE / FINE_N           # yards across a cell (8.33)
DEEP = 1.7                     # yards of water before you swim
CLIMB = 1.0                    # nav_bake.mjs AGENT.CLIMB
TALL = 2.0                     # nav_bake.mjs AGENT.HEIGHT
NOT_CONNECTED = 0x3F
DX = np.array([-1, 0, 1, 0])   # Recast's direction offsets: x (north), z (-west)
DZ = np.array([0, 1, 0, -1])


def read_chf(path):
    b = open(path, "rb").read()
    assert b[:4] == b"WCHF", path
    _, w, h = struct.unpack_from("<III", b, 4)
    bx, by, bz, cs, ch = struct.unpack_from("<5f", b, 16)
    ns = struct.unpack_from("<I", b, 36)[0]
    o = 40
    cells = np.frombuffer(b, "<u4", w * h, o); o += w * h * 4
    spans = np.frombuffer(b, "<u4", ns * 2, o).reshape(-1, 2); o += ns * 8
    areas = np.frombuffer(b, "u1", ns, o)
    return dict(w=w, h=h, bx=bx, by=by, bz=bz, cs=cs, ch=ch, index=(cells & 0xFFFFFF).astype(np.int64),
                count=(cells >> 24).astype(np.int64), y=(spans[:, 0] & 0xFFFF).astype(np.int64),
                con=(spans[:, 1] & 0xFFFFFF).astype(np.int64), sh=(spans[:, 1] >> 24).astype(np.int64), area=areas)


def read_liquids(path):
    """The soup's liquid triangles: (verts Nx3 in x north / y up / z -west, tris, kinds)."""
    b = open(path, "rb").read()
    nv, nt = struct.unpack_from("<II", b, 8)
    o = 16
    V = np.frombuffer(b, "<f4", nv * 3, o).reshape(-1, 3).astype(np.float64); o += nv * 12
    T = np.frombuffer(b, "<i4", nt * 3, o).reshape(-1, 3).astype(np.int64); o += nt * 12
    K = np.frombuffer(b, "u1", nt, o)
    liquid = K > 0
    return V, T[liquid], K[liquid]


def liquid_surface(c, V, T, K):
    """Per Recast column: the highest liquid surface over it (nan for none), and whether it's lava."""
    w, h, cs = c["w"], c["h"], c["cs"]
    top = np.full(w * h, -np.inf)
    bad = np.zeros(w * h, dtype=bool)
    if len(T) == 0:
        return np.where(np.isfinite(top), top, np.nan), bad
    # Column centres in (x, z): x = bx + (i + 0.5) cs, z = bz + (j + 0.5) cs; index i + j w.
    X = (V[:, 0] - c["bx"]) / cs - 0.5
    Z = (V[:, 2] - c["bz"]) / cs - 0.5
    for start in range(0, len(T), 4096):
        t = T[start:start + 4096]
        k = K[start:start + 4096]
        ax, az, bx_, bz_, cx, cz = X[t[:, 0]], Z[t[:, 0]], X[t[:, 1]], Z[t[:, 1]], X[t[:, 2]], Z[t[:, 2]]
        ay, by_, cy = V[t[:, 0], 1], V[t[:, 1], 1], V[t[:, 2], 1]
        x0 = np.clip(np.ceil(np.minimum(np.minimum(ax, bx_), cx)), 0, w - 1).astype(int)
        x1 = np.clip(np.floor(np.maximum(np.maximum(ax, bx_), cx)), 0, w - 1).astype(int)
        z0 = np.clip(np.ceil(np.minimum(np.minimum(az, bz_), cz)), 0, h - 1).astype(int)
        z1 = np.clip(np.floor(np.maximum(np.maximum(az, bz_), cz)), 0, h - 1).astype(int)
        det = (bx_ - ax) * (cz - az) - (cx - ax) * (bz_ - az)
        for i in np.nonzero((x1 >= x0) & (z1 >= z0) & (np.abs(det) > 1e-9))[0]:
            gx, gz = np.meshgrid(np.arange(x0[i], x1[i] + 1), np.arange(z0[i], z1[i] + 1))
            gx, gz = gx.ravel(), gz.ravel()
            l1 = ((gx - ax[i]) * (cz[i] - az[i]) - (cx[i] - ax[i]) * (gz - az[i])) / det[i]
            l2 = ((bx_[i] - ax[i]) * (gz - az[i]) - (gx - ax[i]) * (bz_[i] - az[i])) / det[i]
            inside = (l1 >= -1e-6) & (l2 >= -1e-6) & (l1 + l2 <= 1 + 1e-6)
            if not inside.any():
                continue
            yy = ay[i] + l1 * (by_[i] - ay[i]) + l2 * (cy[i] - ay[i])
            idx = gx[inside] + gz[inside] * w
            np.maximum.at(top, idx, yy[inside])
            if k[i] == 2:
                bad[idx] = True
    return np.where(np.isfinite(top), top, np.nan), bad


def components(n, a, b):
    """Labels 0..k-1 of the parts of a graph of n points joined by edges a-b."""
    label = np.arange(n)
    if len(a):
        while True:
            m = np.minimum(label[a], label[b])
            new = label.copy()
            np.minimum.at(new, a, m)
            np.minimum.at(new, b, m)
            new = new[new]
            new = new[new]
            if np.array_equal(new, label):
                break
            label = new
    _, out = np.unique(label, return_inverse=True)
    return out


def reduce_tile(name):
    mapid, ty, tx = (int(v) for v in name.split("_"))
    c = read_chf(os.path.join(NAV, name + ".chf"))
    V, T, K = read_liquids(os.path.join(NAV, name + ".bin"))
    w, h, cs, ch = c["w"], c["h"], c["cs"], c["ch"]
    ns = len(c["y"])
    if ns == 0:
        return None
    # Each span's column (i, j), floor and room above it, in yards.
    col = np.repeat(np.arange(w * h), c["count"])   # Recast lays spans out column by column, in order
    i, j = col % w, col // w
    fy = c["by"] + c["y"] * ch
    room = c["sh"] * ch
    north = c["bx"] + (i + 0.5) * cs
    west = -(c["bz"] + (j + 0.5) * cs)
    # Which tile and cell each span is in.
    gr = np.floor((MAX - north) / FINE).astype(np.int64)
    gc = np.floor((MAX - west) / FINE).astype(np.int64)
    in_tile = (gr // FINE_N == ty) & (gc // FINE_N == tx)
    # Water: a span under a liquid deeper than DEEP; the liquid's surface is where you swim.
    surface, lava = liquid_surface(c, V, T, K)
    sur = surface[col]
    wet = np.isfinite(sur) & (sur - fy > DEEP) & (fy + room >= sur)
    hot = lava[col] & np.isfinite(sur) & (sur >= fy - 0.5)
    kind = np.where(hot, 2, np.where(wet, 1, 0))

    # Neighbours through Recast's links, per direction.
    nb = np.full((ns, 4), -1, dtype=np.int64)
    for d in range(4):
        cv = (c["con"] >> (6 * d)) & 0x3F
        ii, jj = i + DX[d], j + DZ[d]
        ok = (cv != NOT_CONNECTED) & (ii >= 0) & (ii < w) & (jj >= 0) & (jj < h)
        ncol = ii[ok] + jj[ok] * w
        nb[ok, d] = c["index"][ncol] + cv[ok]
    # Parts of a cell: spans of the same kind joined without leaving the cell; water also joins
    # any water beside it in the cell (you swim over whatever's under it).
    cell = gr * 100000 + gc
    ea, eb = [], []
    for d in range(4):
        s = np.nonzero(nb[:, d] >= 0)[0]
        t = nb[s, d]
        same = (cell[s] == cell[t]) & (kind[s] == kind[t])
        ea.append(s[same]); eb.append(t[same])
    wet_idx = np.nonzero(kind == 1)[0]
    # Water beside water (any floor under it): by column neighbours.
    swim_a, swim_b = water_pairs(c, col, kind, i, j)
    same = cell[swim_a] == cell[swim_b]
    ea.append(swim_a[same]); eb.append(swim_b[same])
    comp = components(ns, np.concatenate(ea), np.concatenate(eb))
    del wet_idx

    # Nodes: the parts whose spans are in this tile.
    keep = in_tile
    ids, node_of = np.unique(comp[keep], return_inverse=True)
    node = np.full(comp.max() + 1, -1, dtype=np.int64)
    node[ids] = np.arange(len(ids))
    sid = np.nonzero(keep)[0]
    nn = len(ids)
    size = np.bincount(node_of, minlength=nn)
    lo = np.full(nn, np.inf); hi = np.full(nn, -np.inf)
    np.minimum.at(lo, node_of, fy[sid]); np.maximum.at(hi, node_of, fy[sid])
    hsum = np.bincount(node_of, weights=fy[sid], minlength=nn)
    nkind = np.zeros(nn, dtype=np.int64)
    np.maximum.at(nkind, node_of, kind[sid])
    wsum = np.bincount(node_of, weights=np.where(kind[sid] == 1, sur[sid], 0), minlength=nn)
    wcnt = np.bincount(node_of, weights=(kind[sid] == 1).astype(float), minlength=nn)
    height = np.where(wcnt > 0, wsum / np.maximum(wcnt, 1), hsum / np.maximum(size, 1))
    cr = gr[sid] - ty * FINE_N
    cc = gc[sid] - tx * FINE_N
    rcell = np.zeros(nn, dtype=np.int64); ccell = np.zeros(nn, dtype=np.int64)
    rcell[node_of] = cr; ccell[node_of] = cc
    # Where its floor's middle is in the cell: 0-255 from the cell's north and west edges.
    ofn = np.bincount(node_of, weights=(MAX - north[sid]) / FINE - gr[sid], minlength=nn) / np.maximum(size, 1)
    ofw = np.bincount(node_of, weights=(MAX - west[sid]) / FINE - gc[sid], minlength=nn) / np.maximum(size, 1)

    # Links out of this tile's nodes: (from node, to span) with a kind and fall.
    la, lb, lk, lf = [], [], [], []
    for d in range(4):
        s = np.nonzero(nb[:, d] >= 0)[0]
        t = nb[s, d]
        m = keep[s] & (comp[s] != comp[t])
        la.append(s[m]); lb.append(t[m]); lk.append(np.where((kind[s[m]] == 1) & (kind[t[m]] == 1), 1, 0)); lf.append(np.zeros(m.sum()))
    m = keep[swim_a] & (comp[swim_a] != comp[swim_b])
    la.append(swim_a[m]); lb.append(swim_b[m]); lk.append(np.ones(m.sum(), dtype=np.int64)); lf.append(np.zeros(m.sum()))
    oa, ob = shore_pairs(c, col, kind, fy, sur, i, j)
    m = keep[oa] & (comp[oa] != comp[ob])
    la.append(oa[m]); lb.append(ob[m]); lk.append(np.ones(m.sum(), dtype=np.int64)); lf.append(np.zeros(m.sum()))
    da, db, dfall = drop_pairs(c, col, kind, fy, room, i, j, nb)
    m = keep[da] & (comp[da] != comp[db])
    la.append(da[m]); lb.append(db[m]); lk.append(np.full(m.sum(), 2)); lf.append(dfall[m])
    la, lb, lk, lf = (np.concatenate(x) for x in (la, lb, lk, lf))
    # One link per (node, the part it reaches, kind): the smallest fall.
    key_to = comp[lb]
    order = np.lexsort((lf, lk, key_to, node[comp[la]]))
    la, lb, lk, lf = la[order], lb[order], lk[order], lf[order]
    first = np.ones(len(la), dtype=bool)
    if len(la):
        fa, ft, fk = node[comp[la]], comp[lb], lk
        first[1:] = (fa[1:] != fa[:-1]) | (ft[1:] != ft[:-1]) | (fk[1:] != fk[:-1])
    la, lb, lk, lf = la[first], lb[first], lk[first], lf[first]
    to_tr, to_tc = gr[lb] // FINE_N - ty, gc[lb] // FINE_N - tx
    # The node reached, when it's in this tile (else -1: nav_stitch.py finds it in the other tile);
    # where the link lands (north, west from the map's corner, tenths of a yard), for matching.
    to_node = np.where(keep[lb], node[comp[lb]], -1)
    links = np.stack([node[comp[la]], to_tr, to_tc, gr[lb] % FINE_N, gc[lb] % FINE_N,
                      np.round(np.where(kind[lb] == 1, sur[lb], fy[lb]) * 10), lk, np.round(lf * 10), to_node,
                      np.round((MAX - north[lb]) * 10), np.round((MAX - west[lb]) * 10)], 1).astype(np.int64)
    nodes = np.stack([rcell, ccell, nkind, np.round(height * 10), np.round(lo * 10), np.round(hi * 10), size,
                      np.clip(np.round(ofn * 255), 0, 255), np.clip(np.round(ofw * 255), 0, 255)], 1).astype(np.int32)
    np.savez_compressed(os.path.join(NAV, name + ".npz"), nodes=nodes, links=links)
    return nn, len(links), int((lk == 2).sum())


def water_pairs(c, col, kind, i, j):
    """Water spans side by side (4 directions), whatever their floors: (a, b) both ways."""
    w, h = c["w"], c["h"]
    wet = np.nonzero(kind == 1)[0]
    if len(wet) == 0:
        return np.zeros(0, dtype=np.int64), np.zeros(0, dtype=np.int64)
    first = {}
    # Per column, its water span (the topmost one).
    by_col = np.full(w * h, -1, dtype=np.int64)
    by_col[col[wet]] = wet
    A, B = [], []
    for d in range(4):
        ii, jj = i[wet] + DX[d], j[wet] + DZ[d]
        ok = (ii >= 0) & (ii < w) & (jj >= 0) & (jj < h)
        t = np.full(len(wet), -1, dtype=np.int64)
        t[ok] = by_col[ii[ok] + jj[ok] * w]
        m = t >= 0
        A.append(wet[m]); B.append(t[m])
    del first
    return np.concatenate(A), np.concatenate(B)


def shore_pairs(c, col, kind, fy, sur, i, j):
    """Water to land beside it whose floor is within CLIMB of the water's surface (you climb out),
    and back: (a, b)."""
    w, h = c["w"], c["h"]
    wet = np.nonzero(kind == 1)[0]
    if len(wet) == 0:
        return np.zeros(0, dtype=np.int64), np.zeros(0, dtype=np.int64)
    A, B = [], []
    start = c["index"]
    count = c["count"]
    for d in range(4):
        ii, jj = i[wet] + DX[d], j[wet] + DZ[d]
        ok = (ii >= 0) & (ii < w) & (jj >= 0) & (jj < h)
        src = wet[ok]
        ncol = ii[ok] + jj[ok] * w
        for k in range(int(count.max())):
            has = count[ncol] > k
            s = src[has]
            t = start[ncol[has]] + k
            m = (kind[t] == 0) & (np.abs(fy[t] - sur[s]) <= CLIMB + 0.5)
            A.append(s[m]); B.append(t[m])
    a, b = np.concatenate(A), np.concatenate(B)
    return np.concatenate([a, b]), np.concatenate([b, a])


DROP_REACH = 3   # Recast cells out a drop's lower floor may be (its ledge filter takes the edge away)


def drop_pairs(c, col, kind, fy, room, i, j, nb):
    """Land spans with a lower floor beside them and nothing in the way: (from, to, fall yards).
    Only where Recast has no link that way. The lower floor is up to DROP_REACH cells out (Recast
    drops the floor at a ledge's very edge), the columns between hold nothing from just under your
    feet up, and the lower floor's open air reaches your head."""
    w, h = c["w"], c["h"]
    count, start = c["count"], c["index"]
    kmax = int(count.max()) if len(count) else 0
    A, B, F = [], [], []
    for d in range(4):
        s = np.nonzero((nb[:, d] < 0) & (kind == 0))[0]
        best = np.full(len(s), -1, dtype=np.int64)
        bestf = np.full(len(s), np.inf)
        blocked = np.zeros(len(s), dtype=bool)
        for step in range(1, DROP_REACH + 1):
            ii, jj = i[s] + DX[d] * step, j[s] + DZ[d] * step
            inside = (ii >= 0) & (ii < w) & (jj >= 0) & (jj < h)
            ncol = np.where(inside, ii + jj * w, 0)
            cnt = np.where(inside, count[ncol], 0)
            found = np.zeros(len(s), dtype=bool)
            near = np.zeros(len(s), dtype=bool)
            for k in range(kmax):
                has = (cnt > k) & ~blocked & (best < 0)
                t = np.where(has, start[ncol] + k, 0)
                fall = fy[s] - fy[t]
                # A floor about level with you here: you'd walk onto it (or it's in the way).
                near |= has & (fall <= CLIMB)
                fits = has & (fall > CLIMB) & (fy[t] + room[t] >= fy[s] + TALL) & (fall < bestf)
                best[fits], bestf[fits] = t[fits], fall[fits]
                found |= fits
            blocked |= near | ~inside
        m = best >= 0
        A.append(s[m]); B.append(best[m]); F.append(bestf[m])
    return np.concatenate(A), np.concatenate(B), np.concatenate(F)


if __name__ == "__main__":
    import time
    for name in sys.argv[1:]:
        t = time.time()
        r = reduce_tile(name)
        print("%s: %s nodes, %s links (%s drops) in %.1fs" % ((name,) + (r or (0, 0, 0)) + (time.time() - t,)))
