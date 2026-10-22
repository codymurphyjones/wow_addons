"""Draws the Waypoint logo: a gold navigation arrow pointing up and to the right, with a dotted
path of three waypoints trailing behind it, on a dark round badge with a gold rim (the same badge
style as Tape Measure's).

Usage: python make_icon.py <output dir>
Writes <output dir>/Icon.tga (128x128, 32-bit, used in game) and
<output dir>/Logo.png (512x512, for CurseForge and other listings)."""
import math, os, sys
from PIL import ImageDraw

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "_shared"))
import iconkit as ik
from iconkit import C, circle


def paint(inside):
    di = ImageDraw.Draw(inside)

    # The arrow: a classic navigation arrowhead pointing up and to the right.
    ang = math.radians(45)

    def rot(px, py, cx=620, cy=420, k=0.8):
        px, py = px * k, py * k
        return (cx + px * math.cos(ang) - py * math.sin(ang), cy + px * math.sin(ang) + py * math.cos(ang))

    # The path: waypoints joined by a dashed line, from bottom left toward the arrow.
    stops = [(240, 740), (420, 640), (300, 500)]
    tip_base = rot(0, 150)
    route = stops + [tip_base]
    for (x0, y0), (x1, y1) in zip(route, route[1:]):
        length = math.hypot(x1 - x0, y1 - y0)
        n = int(length // 44)
        for i in range(n):
            if i % 2:
                continue
            a, b = i / n, min(1, (i + 1) / n)
            di.line([(x0 + (x1 - x0) * a, y0 + (y1 - y0) * a), (x0 + (x1 - x0) * b, y0 + (y1 - y0) * b)],
                    fill=(150, 200, 255, 230), width=22)
    for i, (x, y) in enumerate(stops):
        circle(di, 46, fill=(0, 0, 0, 120), cx=x + 6, cy=y + 8)
        circle(di, 44, fill=(30, 60, 90), cx=x, cy=y)
        circle(di, 32, fill=(110, 190, 255) if i < 2 else (255, 205, 80), cx=x, cy=y)

    arrow = [rot(0, -300), rot(190, 200), rot(0, 90), rot(-190, 200)]
    di.polygon([(x + 14, y + 18) for x, y in arrow], fill=(0, 0, 0, 140))
    di.polygon(arrow, fill=(236, 178, 52), outline=(90, 56, 12), width=14)
    # Lit half
    lit = [rot(0, -300), rot(0, 90), rot(-190, 200)]
    di.polygon(lit, fill=(255, 220, 120))
    di.line([rot(0, -300), rot(0, 90)], fill=(170, 112, 24), width=8)
    return inside


img = ik.badge(paint, inner=(22, 34, 44), glow=([C - 340, C - 300, C + 340, C + 340], (90, 170, 255, 55), 80))
out_dir = ik.out_dir("Waypoint")
ik.save(img, out_dir)
print("saved", os.path.join(out_dir, "Icon.tga"), "and Logo.png")
