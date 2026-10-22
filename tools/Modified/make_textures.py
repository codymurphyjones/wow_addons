"""Draws the white shapes the Bloom (Veil.lua, Lens.lua) tints in game:

    Dot.tga   a soft round bead (beads, the pulse)
    Ring.tga  a thin bright ring (petal and core edges, halos over action buttons)
    Glow.tga  a wide soft glow (the lit petal, the core's aura)
    Disc.tga  a solid disc with a soft edge (empty petals, the seal)

All are 64x64, 32-bit, white with alpha, so SetVertexColor gives them any colour.
Usage: python tools/Modified/make_textures.py [output dir]   (default addons/Modified/Textures)
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
SIZE, SS = 64, 8  # drawn 8x larger, then scaled down for smooth edges
BIG = SIZE * SS


def alpha_shape(draw_fn, blur=0):
    mask = Image.new("L", (BIG, BIG), 0)
    draw_fn(ImageDraw.Draw(mask))
    if blur:
        mask = mask.filter(ImageFilter.GaussianBlur(blur * SS))
    mask = mask.resize((SIZE, SIZE), Image.LANCZOS)
    img = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
    img.putalpha(mask)
    return img


def circle(d, r, **kw):
    c = BIG / 2
    d.ellipse((c - r * SS, c - r * SS, c + r * SS, c + r * SS), **kw)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, "addons", "Modified", "Textures")
    os.makedirs(out, exist_ok=True)
    shapes = {
        "Dot.tga": alpha_shape(lambda d: circle(d, 18, fill=255), blur=4),
        "Ring.tga": alpha_shape(lambda d: circle(d, 28, outline=255, width=3 * SS), blur=0.6),
        "Glow.tga": alpha_shape(lambda d: circle(d, 16, fill=255), blur=9),
        "Disc.tga": alpha_shape(lambda d: circle(d, 29, fill=255), blur=0.8),
    }
    for name, img in shapes.items():
        path = os.path.join(out, name)
        img.save(path)
        print("wrote", path)


if __name__ == "__main__":
    main()
