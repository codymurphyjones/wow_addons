"""Draws the Mr. Miyagi logo: a little bonsai tree in a pot, with a pair of
chopsticks above it, on a dark round badge with a gold rim (the same badge
style as the user's other addons).

Usage: python make_icon.py <output dir>
Writes <output dir>/Icon.tga (128x128, 32-bit, used in game) and
<output dir>/Logo.png (512x512, for CurseForge and other listings)."""
import os, sys
from PIL import ImageDraw

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "_shared"))
import iconkit as ik
from iconkit import C, circle


def paint(inside):
    di = ImageDraw.Draw(inside)

    # A red rising sun behind the tree
    circle(di, 250, fill=(190, 60, 50), cx=C, cy=470)

    # Trunk: a curving bonsai trunk
    trunk = [(500, 760), (470, 680), (520, 600), (470, 520), (530, 450), (560, 470), (520, 530), (575, 600), (530, 690), (560, 760)]
    di.polygon([(x + 8, y + 10) for x, y in trunk], fill=(0, 0, 0, 120))
    di.polygon(trunk, fill=(110, 70, 40), outline=(60, 36, 20), width=8)
    # Foliage pads
    for cx, cy, rx, ry in ((400, 470, 120, 62), (610, 420, 130, 66), (520, 340, 120, 60), (660, 560, 90, 48)):
        di.ellipse([cx - rx + 8, cy - ry + 12, cx + rx + 8, cy + ry + 12], fill=(0, 0, 0, 110))
        di.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=(70, 150, 80), outline=(30, 80, 40), width=8)
        di.ellipse([cx - rx + 30, cy - ry + 14, cx + rx - 50, cy - 4], fill=(120, 200, 120))

    # Pot
    di.polygon([(360 + 8, 760 + 10), (664 + 8, 760 + 10), (620 + 8, 840 + 10), (404 + 8, 840 + 10)], fill=(0, 0, 0, 120))
    di.polygon([(360, 760), (664, 760), (620, 840), (404, 840)], fill=(60, 90, 140), outline=(25, 40, 70), width=8)
    di.rectangle([340, 740, 684, 772], fill=(80, 115, 170), outline=(25, 40, 70), width=8)

    # Chopsticks across the top
    for (x0, y0, x1, y1) in ((250, 250, 700, 175), (270, 290, 720, 240)):
        di.line([(x0 + 6, y0 + 10), (x1 + 6, y1 + 10)], fill=(0, 0, 0, 130), width=26)
        di.line([(x0, y0), (x1, y1)], fill=(220, 180, 110), width=22)
        di.line([(x0, y0 - 6), (x1, y1 - 6)], fill=(250, 220, 160), width=6)
    return inside


img = ik.badge(paint, inner=(30, 24, 30), glow=([C - 330, C - 300, C + 330, C + 300], (230, 120, 90, 50), 70))
out_dir = ik.out_dir("MrMiyagi")
ik.save(img, out_dir)
print("saved", os.path.join(out_dir, "Icon.tga"), "and Logo.png")
