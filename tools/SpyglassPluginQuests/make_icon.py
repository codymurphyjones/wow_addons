"""Draws the SpyGlass Quests logo: the SpyGlass badge, with the brass spyglass
raised toward a golden quest "!" (the quest reward it has spotted) in place
of the glint, and the family's green upgrade arrow.

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

    # The quest the spyglass has spotted: a glow and a golden quest "!".
    gx, gy = 620, 250
    inside = ik.soft_ellipse(inside, [gx - 160, gy - 170, gx + 160, gy + 170], (255, 210, 90, 170), 45)
    di = ImageDraw.Draw(inside)

    def bang(d, ox, oy, fill, outline=None, width=0):
        """A quest "!": a bar tapering downward over a round dot."""
        d.polygon([(gx - 56 + ox, gy - 120 + oy), (gx + 56 + ox, gy - 120 + oy),
                   (gx + 28 + ox, gy + 40 + oy), (gx - 28 + ox, gy + 40 + oy)], fill=fill, outline=outline, width=width)
        d.rounded_rectangle([gx - 56 + ox, gy - 150 + oy, gx + 56 + ox, gy - 90 + oy], radius=28, fill=fill, outline=outline, width=width)
        circle(d, 38, fill=fill, outline=outline, width=width, cx=gx + ox, cy=gy + 102 + oy)

    bang(di, 8, 10, (0, 0, 0, 110))
    bang(di, 0, 0, (255, 206, 40), ik.BRASS_OUTLINE, 14)
    # hide the seam between the bar's cap and its body, then add a highlight
    di.polygon([(gx - 48, gy - 112), (gx + 48, gy - 112), (gx + 42, gy - 80), (gx - 42, gy - 80)], fill=(255, 206, 40))
    di.polygon([(gx - 36, gy - 132), (gx - 14, gy - 132), (gx - 12, gy + 10), (gx - 22, gy + 10)], fill=(255, 244, 180))
    circle(di, 12, fill=(255, 244, 180), cx=gx - 12, cy=gy + 90)
    ik.sparkle(di, gx + 130, gy - 60, 28, (255, 236, 160))
    ik.sparkle(di, gx - 120, gy + 30, 20, (255, 236, 160))

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
out_dir = ik.out_dir("SpyglassPluginQuests")
ik.save(img, out_dir)
print("saved", os.path.join(out_dir, "Icon.tga"), "and Logo.png")
