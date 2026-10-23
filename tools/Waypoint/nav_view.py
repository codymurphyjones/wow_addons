"""A picture of a baked tile (nav_bake.mjs's .chf), to check the bake by eye.

    python tools/Waypoint/nav_view.py <tile.chf> [out.png]

Seen from above, north up: each column's highest walkable floor shaded by its height (hill shading),
columns with two or more walkable floors tinted blue (a bridge over a road, a floor over a cellar),
three or more purple; ground you can't walk on (walls, cliffs, eroded edges) dark red; nothing black.
Needs Pillow (run without -I if it's in your user site-packages).
"""
import struct
import sys

import numpy as np
from PIL import Image


def read_chf(path):
    b = open(path, "rb").read()
    assert b[:4] == b"WCHF"
    _, w, h = struct.unpack_from("<III", b, 4)
    bx, by, bz, cs, ch = struct.unpack_from("<5f", b, 16)
    ns = struct.unpack_from("<I", b, 36)[0]
    o = 40
    cells = np.frombuffer(b, "<u4", w * h, o); o += w * h * 4
    spans = np.frombuffer(b, "<u4", ns * 2, o).reshape(-1, 2); o += ns * 8
    areas = np.frombuffer(b, "u1", ns, o)
    return dict(w=w, h=h, bmin=(bx, by, bz), cs=cs, ch=ch, index=cells & 0xFFFFFF, count=cells >> 24,
                y=spans[:, 0] & 0xFFFF, con=spans[:, 1] & 0xFFFFFF, sh=spans[:, 1] >> 24, area=areas)


def render(c):
    w, h = c["w"], c["h"]
    top = np.full(w * h, np.nan)
    floors = np.zeros(w * h, dtype=np.int32)
    solid = c["count"] > 0
    idx, cnt, y, area = c["index"], c["count"], c["y"], c["area"]
    for k in range(int(cnt.max()) if len(cnt) else 0):
        has = cnt > k
        s = idx[has] + k
        walk = area[s] != 0
        cellsk = np.nonzero(has)[0][walk]
        floors[cellsk] += 1
        top[cellsk] = np.fmax(top[cellsk], y[s[walk]] * c["ch"])
    # Cells are x (north) fastest? Recast: index = x + z * width; x = north, z = -west.
    top = top.reshape(h, w)
    floors = floors.reshape(h, w)
    solid = solid.reshape(h, w)
    # Picture: north up, west left. Row = north descending = x descending; column = west descending = z ascending.
    top, floors, solid = top.T[::-1], floors.T[::-1], solid.T[::-1]
    gy, gx = np.gradient(np.nan_to_num(top, nan=np.nanmin(top) if np.isfinite(top).any() else 0))
    shade = np.clip(0.6 + 0.35 * (gx - gy) / (np.hypot(gx, gy) + 0.3), 0.2, 1.0)
    lo, hi = np.nanpercentile(top, 2), np.nanpercentile(top, 98)
    t = np.clip((np.nan_to_num(top, nan=lo) - lo) / max(hi - lo, 1), 0, 1)
    rgb = np.zeros((*top.shape, 3))
    base = np.stack([0.35 + 0.5 * t, 0.55 + 0.35 * t, 0.3 + 0.2 * t], -1)
    rgb[:] = base * shade[..., None]
    multi = floors >= 2
    rgb[multi] = rgb[multi] * 0.5 + np.array([0.15, 0.35, 0.9]) * 0.5
    rgb[floors >= 3] = rgb[floors >= 3] * 0.5 + np.array([0.6, 0.2, 0.8]) * 0.5
    rgb[(floors == 0) & solid] = [0.35, 0.08, 0.08]
    rgb[~solid] = 0
    return Image.fromarray((rgb * 255).astype(np.uint8)), floors


if __name__ == "__main__":
    c = read_chf(sys.argv[1])
    img, floors = render(c)
    out = sys.argv[2] if len(sys.argv) > 2 else sys.argv[1].replace(".chf", ".png")
    img.save(out)
    print("%s: %d walkable columns, %d with 2+ floors, %d with 3+ -> %s" % (
        sys.argv[1], (floors > 0).sum(), (floors >= 2).sum(), (floors >= 3).sum(), out))
