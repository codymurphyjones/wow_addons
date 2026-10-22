"""Draws the Field Guide logo: a green field guide with a gold border, a trail of footsteps up its
cover to a waypoint flag, on a dark round badge with a gold rim (the same badge style as Waypoint's).

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

    # The book: a green cover seen from the front, pages showing on the right, a gold clasp.
    L, T, R, B = 270, 230, 720, 800
    di.rounded_rectangle([L + 18, T + 22, R + 18, B + 22], radius=30, fill=(0, 0, 0, 140))
    di.rounded_rectangle([L + 30, T + 16, R + 30, B - 16], radius=24, fill=(236, 226, 196))         # pages
    for i in range(5):
        di.line([(R + 4, T + 40 + i * 6), (R + 4, B - 40 - i * 6)], fill=(190, 178, 150), width=3)
    di.rounded_rectangle([L, T, R, B], radius=30, fill=(46, 104, 58), outline=(20, 48, 26), width=12)  # cover
    di.rectangle([L, T, L + 60, B], fill=(34, 80, 44))                                                 # spine
    di.rounded_rectangle([L + 100, T + 60, R - 50, B - 60], radius=20, outline=(214, 172, 74), width=10)
    # A trail of footsteps up the cover to a waypoint flag.
    steps = [(380, 700), (430, 640), (400, 575), (455, 515), (500, 455)]
    for i, (x, y) in enumerate(steps):
        di.ellipse([x - 16, y - 22, x + 16, y + 22], fill=(236, 214, 140))
    fx, fy = 560, 330
    di.line([(fx, fy), (fx, fy + 150)], fill=(236, 214, 140), width=14)
    di.polygon([(fx, fy), (fx + 110, fy + 35), (fx, fy + 70)], fill=(236, 120, 70))
    circle(di, 18, fill=(236, 214, 140), cx=fx, cy=fy + 150)
    # Clasp
    di.rounded_rectangle([R - 30, (T + B) / 2 - 45, R + 40, (T + B) / 2 + 45], radius=14, fill=(214, 166, 64), outline=(90, 60, 18), width=8)
    return inside


img = ik.badge(paint, inner=(24, 34, 28), glow=([C - 340, C - 300, C + 340, C + 340], (120, 210, 110, 50), 80))
out_dir = ik.out_dir("FieldGuide")
ik.save(img, out_dir)
print("saved", os.path.join(out_dir, "Icon.tga"), "and Logo.png")
