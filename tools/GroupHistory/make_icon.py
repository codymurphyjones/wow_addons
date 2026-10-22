"""Draws the Group History logo: an open record scroll with a tally and a small
skull, in front of two party silhouettes, on a dark round badge with a gold rim
(the same badge style as StatLedger's and Wealth Planner's).

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

    # Two party silhouettes behind the scroll
    for cx, col in ((370, (70, 150, 200)), (654, (90, 190, 120))):
        circle(di, 78, fill=col, cx=cx, cy=300)
        di.pieslice([cx - 150, 380, cx + 150, 680], 180, 360, fill=col)

    # The scroll: parchment with rolled ends
    x0, y0, x1, y1 = 250, 430, 774, 800
    di.rounded_rectangle([x0 + 10, y0 + 14, x1 + 10, y1 + 14], radius=20, fill=(0, 0, 0, 130))
    di.rounded_rectangle([x0, y0, x1, y1], radius=20, fill=(240, 226, 190), outline=(150, 112, 60), width=8)
    for y in (y0, y1):
        di.rounded_rectangle([x0 - 26, y - 26, x1 + 26, y + 26], radius=26, fill=(205, 170, 110), outline=(130, 92, 44), width=8)
    # Text lines
    for i, w in enumerate((380, 300, 340)):
        yy = y0 + 70 + i * 52
        di.line([(x0 + 50, yy), (x0 + 50 + w, yy)], fill=(120, 100, 80), width=12)
    # Tally: four strokes and a slash
    tx, ty = x0 + 60, y1 - 110
    for i in range(4):
        di.line([(tx + i * 34, ty), (tx + i * 34, ty + 70)], fill=(60, 50, 40), width=12)
    di.line([(tx - 14, ty + 60), (tx + 120, ty + 8)], fill=(60, 50, 40), width=12)
    # Small skull, bottom right
    sx, sy = x1 - 110, y1 - 80
    circle(di, 52, fill=(250, 250, 245), outline=(60, 50, 40), width=6, cx=sx, cy=sy - 10)
    di.rounded_rectangle([sx - 30, sy + 22, sx + 30, sy + 56], radius=8, fill=(250, 250, 245), outline=(60, 50, 40), width=6)
    circle(di, 13, fill=(40, 30, 30), cx=sx - 20, cy=sy - 10)
    circle(di, 13, fill=(40, 30, 30), cx=sx + 20, cy=sy - 10)
    return inside


img = ik.badge(paint, inner=(26, 26, 40), glow=([C - 330, C - 300, C + 330, C + 300], (80, 200, 180, 55), 60))
out_dir = ik.out_dir("GroupHistory")
ik.save(img, out_dir)
print("saved", os.path.join(out_dir, "Icon.tga"), "and Logo.png")
