"""Draws the world map's marker for where the arrow is leading (MapPins.lua): a target ring with a dot
in the middle and four ticks, white on a dark edge, so the game can tint it to the target's colour and
it reads on any map. It's a place, not a quest: quest markers are the game's and Questie's.

Usage: python tools/Waypoint/make_target_icon.py [output dir] [preview dir]
Writes <output dir>/Target.tga (64x64, 32-bit), and a PNG preview when given a preview dir."""
import math
import os
import sys

from PIL import Image, ImageDraw

S = 512   # supersampled canvas, downscaled at the end
C = S / 2
OUT = 64
INK = (255, 255, 255, 255)
EDGE = (16, 20, 28, 255)
RING, RING_WIDTH = 150, 44
DOT = 52
TICK_FROM, TICK_TO, TICK_WIDTH = 176, 244, 40
BORDER = 18


def shape(d, fill, grow):
    d.ellipse([C - RING - grow, C - RING - grow, C + RING + grow, C + RING + grow], outline=fill,
              width=RING_WIDTH + grow * 2)
    d.ellipse([C - DOT - grow, C - DOT - grow, C + DOT + grow, C + DOT + grow], fill=fill)
    half = TICK_WIDTH / 2 + grow
    for a in (0, 90, 180, 270):
        c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
        points = []
        for along, side in ((TICK_FROM - grow, -half), (TICK_TO + grow, -half), (TICK_TO + grow, half), (TICK_FROM - grow, half)):
            points.append((C + along * c - side * s, C + along * s + side * c))
        d.polygon(points, fill=fill)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.dirname(here)), "addons", "Waypoint", "Media")
    preview = sys.argv[2] if len(sys.argv) > 2 else None
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    shape(d, EDGE, BORDER)
    shape(d, INK, 0)
    icon = img.resize((OUT, OUT), Image.LANCZOS)
    icon.save(os.path.join(out, "Target.tga"))
    if preview:
        back = Image.new("RGBA", (256, 256), (70, 120, 50, 255))
        big = icon.resize((256, 256), Image.LANCZOS)
        back.alpha_composite(big)
        back.save(os.path.join(preview, "Target.png"))
    print("wrote Target.tga to", out)


if __name__ == "__main__":
    main()
