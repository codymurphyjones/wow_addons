"""Draws the BattleRecap logo: a bone-white skull over two crossed swords, with a red glow
behind them, on a dark round badge with a gold rim (the same badge style as StatLedger's).

Usage: python make_icon.py <output dir>
Writes <output dir>/Icon.tga (128x128, 32-bit, used in game) and
<output dir>/Logo.png (512x512, for CurseForge and other listings)."""
import os, sys
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "_shared"))
import iconkit as ik
from iconkit import C, circle


def paint(inside):
    def sword():
        """One upright sword on its own layer, point up, centred on the canvas."""
        layer = ik.layer()
        ds = ImageDraw.Draw(layer)
        top, guard, bottom, w = C - 400, C + 190, C + 360, 46
        blade = [(C, top), (C + w, top + 90), (C + w, guard), (C - w, guard), (C - w, top + 90)]
        ds.polygon([(x + 8, y + 10) for x, y in blade], fill=(0, 0, 0, 120))
        ds.polygon(blade, fill=(200, 208, 220), outline=(60, 66, 80), width=8)
        ds.polygon([(C, top + 30), (C + 14, top + 90), (C + 14, guard - 10), (C, guard - 10)], fill=(245, 248, 255))
        # crossguard, grip and pommel
        ds.rounded_rectangle([C - 130, guard - 6, C + 130, guard + 40], radius=18, fill=(214, 166, 64), outline=(92, 60, 18), width=8)
        ds.rounded_rectangle([C - 26, guard + 40, C + 26, bottom], radius=10, fill=(110, 62, 30), outline=(50, 28, 12), width=6)
        circle(ds, 40, fill=(214, 166, 64), outline=(92, 60, 18), width=8, cx=C, cy=bottom + 26)
        return layer

    for angle in (40, -40):
        inside = Image.alpha_composite(inside, sword().rotate(angle, resample=Image.BICUBIC, center=(C, C)))

    # Skull
    di = ImageDraw.Draw(inside)
    BONE, EDGE, HOLE = (238, 230, 210), (70, 56, 48), (36, 20, 22)
    sx, sy = C, C - 20
    di.ellipse([sx - 196, sy - 200 + 12, sx + 196, sy + 150 + 12], fill=(0, 0, 0, 130))
    di.ellipse([sx - 190, sy - 200, sx + 190, sy + 150], fill=BONE, outline=EDGE, width=12)
    di.rounded_rectangle([sx - 112, sy + 80, sx + 112, sy + 230], radius=40, fill=BONE, outline=EDGE, width=12)
    di.rectangle([sx - 100, sy + 70, sx + 100, sy + 100], fill=BONE)  # hides the seam between head and jaw
    # eyes and nose
    di.ellipse([sx - 140, sy - 40, sx - 30, sy + 70], fill=HOLE)
    di.ellipse([sx + 30, sy - 40, sx + 140, sy + 70], fill=HOLE)
    circle(di, 16, fill=(255, 70, 50), cx=sx - 85, cy=sy + 18)
    circle(di, 16, fill=(255, 70, 50), cx=sx + 85, cy=sy + 18)
    di.polygon([(sx, sy + 80), (sx + 28, sy + 130), (sx - 28, sy + 130)], fill=HOLE)
    # teeth
    for i in range(-2, 3):
        x = sx + i * 40
        di.line([(x, sy + 158), (x, sy + 222)], fill=EDGE, width=8)
    # shine on the dome
    inside = ik.soft_ellipse(inside, [sx - 120, sy - 170, sx + 20, sy - 90], (255, 255, 255, 110), 10)
    return inside


img = ik.badge(paint, inner=(30, 22, 28), glow=([C - 320, C - 300, C + 320, C + 320], (220, 50, 40, 120), 70))
out_dir = ik.out_dir("BattleRecap")
ik.save(img, out_dir)
print("saved", os.path.join(out_dir, "Icon.tga"), "and Logo.png")
