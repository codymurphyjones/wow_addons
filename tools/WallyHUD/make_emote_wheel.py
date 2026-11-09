"""Draws the art for WallyHUD's emote wheel (EmoteWheel.lua): a round ring of dark glass in the suite's
look (see-through surface, 1px hairlines, an iron rim like the orb's bezel), the lit wedge that
follows the cursor, and the spokes between the wedges. The hub reuses the orb's art (Media/Orb).

    python tools/WallyHUD/make_emote_wheel.py [--preview <dir>]     (needs Pillow and numpy: not -I)

Writes into addons/WallyHUD/Media/EmoteWheel (32-bit TGA, 512 px, white where the game tints them):
  Ring.tga     the ring: dark glass from INNER to OUTER, an iron rim outside, hairlines on both edges
  Wedge4.tga   a quarter of the ring, centred at the top, brighter toward its outer edge (tinted accent)
  Wedge8.tga   an eighth of the ring, the same
  Spokes4.tga  the hairlines between four wedges (on the diagonals)
  Spokes8.tga  the hairlines between eight wedges
With --preview, also writes preview.png there: the ring with a lit wedge, on a mid-grey.
"""
import math
import os
import sys

import numpy as np
from PIL import Image

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.dirname(TOOLS)
OUT = os.path.join(REPO, "addons", "WallyHUD", "Media", "EmoteWheel")

SIZE = 512
SS = 2
INNER = 0.40   # the ring's inner edge, as a share of the half-width (EmoteWheel.lua's RING_INNER)
OUTER = 0.92   # the glass's outer edge (EmoteWheel.lua's RING_OUTER); the rim runs from here to RIM
RIM = 0.985


def grid():
    n = SIZE * SS
    y, x = np.mgrid[0:n, 0:n]
    dx, dy = (x + 0.5) / n - 0.5, (y + 0.5) / n - 0.5
    r = np.hypot(dx, dy) * 2
    a = np.arctan2(dx, -dy)  # 0 at the top, clockwise
    return r, a, 1.0 / (n / 2)


def band(r, lo, hi, soft):
    return np.clip((r - lo) / soft + 0.5, 0, 1) * np.clip((hi - r) / soft + 0.5, 0, 1)


def to_img(rgb, alpha):
    a = np.clip(alpha, 0, 1)
    arr = np.dstack([np.clip(rgb[i], 0, 255) * np.ones_like(a) for i in range(3)] + [a * 255]).astype(np.uint8)
    img = Image.fromarray(arr, "RGBA")
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def ring():
    r, a, px = grid()
    glass = band(r, INNER, OUTER, px * 1.5)
    # The surface: the suite's base colour, a touch darker toward the outside, see-through.
    t = np.clip((r - INNER) / (OUTER - INNER), 0, 1)
    shade = 1.0 - 0.35 * t
    alpha = glass * (0.80 - 0.10 * t)
    rgb = [10 * shade + 6 * (1 - t), 12 * shade + 7 * (1 - t), 16 * shade + 9 * (1 - t)]
    # An inner shadow along both edges, so it reads as a recessed well.
    edge = np.minimum(np.abs(r - INNER), np.abs(r - OUTER))
    shadow = np.exp(-edge / 0.035) * glass
    rgb = [c * (1 - 0.6 * shadow) for c in rgb]
    alpha = np.maximum(alpha, glass * 0.85 * shadow)
    # The iron rim: a dark band with a soft bevel (light from the top).
    rim = band(r, OUTER, RIM, px * 1.5)
    rt = np.clip((r - OUTER) / (RIM - OUTER), 0, 1)
    bevel = np.sin(rt * math.pi) * (0.55 + 0.45 * np.cos(a))
    iron = [30 + 38 * bevel, 33 + 40 * bevel, 40 + 44 * bevel]
    rgb = [rgb[i] * (1 - rim) + iron[i] * rim for i in range(3)]
    alpha = alpha * (1 - rim) + rim * 0.95
    # The hairlines: the inner edge, and the glass's outer edge where it meets the rim.
    hair = (np.exp(-((r - INNER) / (px * 1.2)) ** 2) * 0.16 + np.exp(-((r - OUTER) / (px * 1.2)) ** 2) * 0.22)
    rgb = [rgb[i] + (255 - rgb[i]) * hair for i in range(3)]
    alpha = np.maximum(alpha, hair)
    return to_img(rgb, alpha)


def wedge(n):
    r, a, px = grid()
    half = math.pi / n
    # Soft sides, a little inside the spokes.
    side = np.clip((half - np.abs(a) - 0.01) / 0.025, 0, 1)
    inside = band(r, INNER + 0.01, OUTER - 0.005, px * 2)
    t = np.clip((r - INNER) / (OUTER - INNER), 0, 1)
    # A wash that grows toward the outside, and a bright arc at the outer edge.
    wash = 0.18 + 0.32 * t ** 1.6
    arc = np.exp(-((r - (OUTER - 0.02)) / 0.018) ** 2) * 0.9
    alpha = side * inside * np.clip(wash + arc, 0, 1)
    return to_img([255, 255, 255], alpha)


def spokes(n):
    r, a, px = grid()
    inside = band(r, INNER + 0.02, OUTER - 0.02, px * 2)
    alpha = np.zeros_like(r)
    for k in range(n):
        ang = (k + 0.5) * 2 * math.pi / n
        # Distance from the spoke's line, in the image's units of the half-width.
        d = np.abs(np.sin(a - ang)) * r
        ahead = np.cos(a - ang) > 0
        alpha = np.maximum(alpha, np.exp(-(d / (px * 1.1)) ** 2) * ahead)
    # Faded toward both ends.
    t = np.clip((r - INNER) / (OUTER - INNER), 0, 1)
    alpha = alpha * inside * np.sin(t * math.pi) ** 0.6
    return to_img([255, 255, 255], alpha)


def tint(img, rgb, alpha=1.0):
    arr = np.array(img).astype(np.float32)
    for i in range(3):
        arr[..., i] = arr[..., i] * rgb[i] / 255
    arr[..., 3] *= alpha
    return Image.fromarray(arr.clip(0, 255).astype(np.uint8), "RGBA")


def preview(parts, folder):
    canvas = Image.new("RGBA", (SIZE, SIZE), (70, 80, 70, 255))
    canvas = Image.alpha_composite(canvas, parts["Ring.tga"])
    canvas = Image.alpha_composite(canvas, tint(parts["Spokes8.tga"], (255, 255, 255), 0.12))
    canvas = Image.alpha_composite(canvas, tint(parts["Wedge8.tga"], (64, 196, 205), 0.9))
    os.makedirs(folder, exist_ok=True)
    canvas.save(os.path.join(folder, "preview.png"))


def main():
    parts = {"Ring.tga": ring(), "Wedge4.tga": wedge(4), "Wedge8.tga": wedge(8),
             "Spokes4.tga": spokes(4), "Spokes8.tga": spokes(8)}
    os.makedirs(OUT, exist_ok=True)
    for name, img in parts.items():
        img.save(os.path.join(OUT, name))
        print("wrote", os.path.join(OUT, name))
    if "--preview" in sys.argv:
        preview(parts, sys.argv[sys.argv.index("--preview") + 1])


if __name__ == "__main__":
    main()
