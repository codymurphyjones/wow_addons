"""A picture of a stitched map (nav_stitch.py's <map>.graph.npz), one pixel a cell, north up:
land you can reach green (lighter higher), water blue, lava orange, cells with a drop out of them
darker. To check the bake by eye.

    python tools/Waypoint/nav_map.py <map> [scale]
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
NAV = os.path.join(HERE, ".nav")

mapid = int(sys.argv[1])
z = np.load(os.path.join(NAV, "%d.graph.npz" % mapid))
N, L = z["nodes"], z["links"]
gr = N[:, 0] * 64 + N[:, 2]
gc = N[:, 1] * 64 + N[:, 3]
r0, c0 = gr.min(), gc.min()
H, W = gr.max() - r0 + 1, gc.max() - c0 + 1
img = np.zeros((H, W, 3))
h = N[:, 5] / 10.0
lo, hi = np.percentile(h, 2), np.percentile(h, 98)
t = np.clip((h - lo) / max(hi - lo, 1), 0, 1)
col = np.stack([0.2 + 0.5 * t, 0.45 + 0.45 * t, 0.15 + 0.2 * t], 1)
col[N[:, 4] == 1] = [0.15, 0.35, 0.75]
col[N[:, 4] == 2] = [0.95, 0.45, 0.1]
# Topmost node per cell wins the pixel (land over water under it is rare).
order = np.argsort(h)
img[gr[order] - r0, gc[order] - c0] = col[order]
drops = np.zeros(len(N), dtype=bool)
drops[L[L[:, 2] == 2, 0]] = True
d = drops & (N[:, 4] == 0)
img[gr[d] - r0, gc[d] - c0] *= 0.6
out = os.path.join(NAV, "%d.png" % mapid)
im = Image.fromarray((img * 255).astype(np.uint8))
scale = float(sys.argv[2]) if len(sys.argv) > 2 else 1
if scale != 1:
    im = im.resize((int(W * scale), int(H * scale)), Image.LANCZOS)
im.save(out)
print("%dx%d cells -> %s" % (W, H, out))
