"""Draws the SpyGlass logo: a brass spyglass raised toward a golden glint
(the upgrade it has spotted), with a green upgrade arrow, on a dark round
night-sky badge with a gold rim (the same badge style as StatLedger's and
Bandolier's).

Usage: python make_icon.py <output dir>
Writes <output dir>/Icon.tga (128x128, 32-bit, used in game) and
<output dir>/Logo.png (512x512, for CurseForge and other listings)."""
import os, sys
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "_shared"))
import iconkit as ik
from iconkit import circle


def paint(inside):
    di = ImageDraw.Draw(inside)
    ik.night_stars(di)

    # The glint the spyglass has spotted: a glow and a big golden sparkle.
    gx, gy = 700, 225
    inside = ik.soft_ellipse(inside, [gx - 150, gy - 150, gx + 150, gy + 150], (255, 210, 90, 170), 45)
    di = ImageDraw.Draw(inside)
    ik.sparkle(di, gx + 6, gy + 8, 90, (0, 0, 0, 90))
    ik.sparkle(di, gx, gy, 90, (255, 214, 92))
    ik.sparkle(di, gx, gy, 46, (255, 246, 200), thin=0.3)
    circle(di, 16, fill=(255, 255, 240), cx=gx, cy=gy)

    # The spyglass, tipped up toward the glint.
    inside = ik.spyglass(inside)
    di = ImageDraw.Draw(inside)

    # Green upgrade arrow, lower right (the family's shared mark)
    shine = ik.layer()
    ik.upgrade_arrow(di, ImageDraw.Draw(shine), 770, 590, 830, head=110, neck=120, shaft=46, drop=(9, 11), width=12,
                     glint=(36, 54, 96))
    inside = Image.alpha_composite(inside, shine)
    return inside


img = ik.badge(paint, inner=(22, 26, 52), glow=([520, 80, 1000, 520], (70, 70, 130, 120), 90))
out_dir = ik.out_dir("Spyglass")
ik.save(img, out_dir)
print("saved", os.path.join(out_dir, "Icon.tga"), "and Logo.png")
