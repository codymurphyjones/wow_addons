"""Draws the StatLedger logo: three ranked bars (gold, silver, bronze), each
led by a numbered stat gem (red, green, blue), and a green "move up" arrow,
on a dark round badge with a gold rim (the same badge style as Bandolier's).

Usage: python make_icon.py <output dir>
Writes <output dir>/Icon.tga (128x128, 32-bit, used in game) and
<output dir>/Logo.png (512x512, for CurseForge and other listings)."""
import os, sys
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "_shared"))
import iconkit as ik
from iconkit import C, circle


def font(size):
    for name in ("arialbd.ttf", "DejaVuSans-Bold.ttf", "Arial Bold.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def paint(inside):
    di = ImageDraw.Draw(inside)

    # Ranked bars: (y centre, length, bar colour, bar highlight, gem colour)
    BARS = [
        (330, 470, (226, 178, 64), (255, 226, 130), (214, 52, 52)),
        (512, 360, (176, 182, 196), (228, 232, 240), (58, 178, 74)),
        (694, 250, (178, 110, 56), (222, 160, 104), (60, 120, 220)),
    ]
    X0, H = 250, 120
    digits = font(96)
    # Translucent shine goes on its own layer: drawing it straight onto the bars
    # would replace their colour instead of blending with it.
    shine = ik.layer()
    ds = ImageDraw.Draw(shine)
    for rank, (y, length, bar, light, gem) in enumerate(BARS, 1):
        # bar with a darker edge and a top highlight
        di.rounded_rectangle([X0, y - H / 2 + 8, X0 + length, y + H / 2 + 8], radius=H / 2, fill=(0, 0, 0, 120))
        di.rounded_rectangle([X0, y - H / 2, X0 + length, y + H / 2], radius=H / 2, fill=bar)
        ds.rounded_rectangle([X0 + 96, y - H / 2 + 14, X0 + length - 34, y - 8], radius=22, fill=light + (170,))
        # numbered gem at the left end
        gx = X0 + 4
        circle(di, 78, fill=(20, 18, 26), cx=gx, cy=y)
        circle(di, 66, fill=gem, cx=gx, cy=y)
        circle(di, 22, fill=tuple(min(255, c + 110) for c in gem), cx=gx - 30, cy=y - 30)
        di.text((gx, y + 4), str(rank), font=digits, fill=(255, 255, 255), anchor="mm",
                stroke_width=6, stroke_fill=(20, 18, 26))

    # Green "move up" arrow to the right of the shorter bars
    ik.upgrade_arrow(di, ds, 770, 470, 790)
    inside = Image.alpha_composite(inside, shine)
    return inside


img = ik.badge(paint, inner=(24, 28, 44), glow=([C - 330, C - 300, C + 330, C + 300], (90, 140, 220, 70), 60))
out_dir = ik.out_dir("StatLedger")
ik.save(img, out_dir)
print("saved", os.path.join(out_dir, "Icon.tga"), "and Logo.png")
