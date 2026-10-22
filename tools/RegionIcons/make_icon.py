"""Draws the OpenMaps: Region Icons logo: a map of two neighbouring zones split by a dashed border,
with map pins on both sides of the line (a quest marker, a rare, a herb, a waypoint): the icons of
the zone next door show too. On the family's dark round badge with a gold rim.

Usage: python make_icon.py <output dir>
Writes <output dir>/Icon.tga (128x128, 32-bit, used in game) and
<output dir>/Logo.png (512x512, for CurseForge and other listings)."""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "_shared"))
import iconkit as ik
from iconkit import C, S, layer


def border_points(wave=34, x0=520):
    """The zone border: a wavy line from top to bottom."""
    pts = []
    for i in range(41):
        y = i / 40 * S
        pts.append((x0 + math.sin(i / 40 * math.pi * 2.6 + 0.6) * wave, y))
    return pts


def pin(d, x, y, r, fill, dark):
    """A teardrop map pin, its point at (x, y)."""
    cy = y - r * 2.1
    d.polygon([(x, y), (x - r * 0.82, cy + r * 0.55), (x + r * 0.82, cy + r * 0.55)], fill=dark)
    d.ellipse([x - r, cy - r, x + r, cy + r], fill=fill, outline=dark, width=10)
    d.ellipse([x - r * 0.38, cy - r * 0.38, x + r * 0.38, cy + r * 0.38], fill=(250, 246, 236))
    return cy


def paint(inside):
    d = ImageDraw.Draw(inside)
    line = border_points()
    # The two zones: the one you're in (left, greener) and the one next door (right, sandy).
    d.polygon([(0, 0)] + line + [(0, S)], fill=(126, 156, 96, 255))
    d.polygon([(S, 0)] + line + [(S, S)], fill=(208, 178, 118, 255))

    # Terrain: a river crossing the border, a few trees, a hill.
    d.line([(60, 760), (260, 700), (420, 730), (600, 650), (760, 690), (980, 610)], fill=(70, 120, 170, 255), width=34, joint="curve")
    d.line([(60, 760), (260, 700), (420, 730), (600, 650), (760, 690), (980, 610)], fill=(120, 170, 210, 255), width=14, joint="curve")
    for x, y in ((180, 330), (240, 400), (150, 470), (330, 560), (260, 860)):
        d.ellipse([x - 30, y - 30, x + 30, y + 30], fill=(70, 110, 60, 255), outline=(46, 74, 40, 255), width=6)
    d.polygon([(740, 360), (830, 240), (920, 360)], fill=(176, 144, 92, 255), outline=(120, 92, 54, 255))
    d.polygon([(830, 240), (860, 280), (810, 280)], fill=(240, 232, 214, 255))

    # The dashed zone border.
    for i in range(0, len(line) - 1, 2):
        d.line([line[i], line[i + 1]], fill=(70, 46, 26, 255), width=16)

    # Pins: the left zone's own, and the zone next door's (lit, they're the point).
    pins = layer()
    dp = ImageDraw.Draw(pins)
    shadow = layer()
    ds = ImageDraw.Draw(shadow)
    spots = ((330, 330, 62, (214, 60, 52), (96, 22, 18)),      # a red waypoint, here
             (720, 590, 70, (60, 130, 220), (20, 48, 100)),    # a blue node, next door
             (760, 850, 56, (90, 190, 90), (30, 80, 34)))      # a green herb, next door
    for x, y, r, fill, dark in spots:
        ds.ellipse([x - r * 0.8, y - 14, x + r * 0.8, y + 14], fill=(0, 0, 0, 110))
        pin(dp, x, y, r, fill + (255,), dark + (255,))
    inside = Image.alpha_composite(inside, shadow.filter(ImageFilter.GaussianBlur(6)))
    inside = Image.alpha_composite(inside, pins)

    # A quest "!" in the zone next door, with a soft glow.
    glow = layer()
    ImageDraw.Draw(glow).ellipse([520, 150, 720, 350], fill=(255, 220, 80, 150))
    inside = Image.alpha_composite(inside, glow.filter(ImageFilter.GaussianBlur(30)))
    d = ImageDraw.Draw(inside)
    bang = [(592, 170), (650, 170), (636, 282), (606, 282)]
    d.polygon(bang, fill=(255, 210, 40, 255))
    d.line(bang + [bang[0]], fill=(110, 72, 0, 255), width=10)
    d.ellipse([598, 296, 644, 342], fill=(255, 210, 40, 255), outline=(110, 72, 0, 255), width=8)
    return inside


img = ik.badge(paint, inner=(126, 156, 96))
out_dir = ik.out_dir("RegionIcons")
ik.save(img, out_dir)
print("saved", os.path.join(out_dir, "Icon.tga"), "and Logo.png")
