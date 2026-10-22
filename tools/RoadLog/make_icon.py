"""Draws the RoadLog logo: a cobbled road winding from the bottom of the badge toward a green
horizon, with a dashed center line, on a dark round badge with a gold rim (the same badge style as
Waypoint's).

Usage: python make_icon.py [output dir]
Writes <output dir>/Icon.tga (128x128, 32-bit, used in game) and
<output dir>/Logo.png (512x512, for CurseForge and other listings).
The output dir defaults to addons/RoadLog/Media."""
import math, os, sys
from PIL import ImageDraw

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "_shared"))
import iconkit as ik
from iconkit import C, S


def paint(inside):
    di = ImageDraw.Draw(inside)

    # Dusk sky: deep blue at the top, warm gold at the horizon
    HORIZON = 430
    for y in range(0, HORIZON):
        t = (y / HORIZON) ** 1.8
        di.line([(0, y), (S, y)], fill=(int(30 + 210 * t), int(48 + 140 * t), int(80 + 30 * t)))
    di.rectangle([0, HORIZON, S, S], fill=(46, 92, 46))
    di.rectangle([0, HORIZON, S, HORIZON + 40], fill=(64, 112, 58))

    # The road: a centerline that winds from the bottom up to a point on the horizon, widening toward
    # the viewer.
    def center(t):  # t = 0 at the horizon, 1 at the bottom
        return C + 150 * math.sin(t * math.pi * 1.25 - 0.4) * t, HORIZON + t * (S - HORIZON)

    def width(t):
        return 10 + 330 * t ** 1.6

    N = 120
    left = [(center(i / N)[0] - width(i / N), center(i / N)[1]) for i in range(N + 1)]
    right = [(center(i / N)[0] + width(i / N), center(i / N)[1]) for i in range(N + 1)]
    di.polygon(left + right[::-1], fill=(150, 120, 80))
    di.line(left, fill=(96, 72, 44), width=14)
    di.line(right, fill=(96, 72, 44), width=14)

    # Dashed center line in gold
    for i in range(N):
        if (i // 8) % 2:
            continue
        t0, t1 = i / N, (i + 1) / N
        di.line([center(t0), center(t1)], fill=(255, 210, 90), width=max(4, int(4 + 26 * t1 ** 1.6)))
    return inside


img = ik.badge(paint, inner=(22, 34, 44))
out_dir = ik.out_dir("RoadLog")
ik.save(img, out_dir)
print("saved", os.path.join(out_dir, "Icon.tga"), "and Logo.png")
