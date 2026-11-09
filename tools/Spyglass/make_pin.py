"""Draws the dungeon map's pack marker: a clean round disc, white inside a thin black edge, smoothed
(drawn 8x over and shrunk). The game tints the white to the pack's colour; the edge stays black, so
a marker reads on any map art without a mask (masked squares came out as soft blobs).

Usage: python -I tools/Spyglass/make_pin.py
Writes addons/Spyglass/Media/Pin.tga (64x64, 32-bit)."""
import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(os.path.dirname(HERE)), "addons", "Spyglass", "Media", "Pin.tga")

SIZE, SS = 64, 8
EDGE = 5  # pixels of black edge at 64 (about 1.5 on an 18-pixel marker)

big = Image.new("RGBA", (SIZE * SS, SIZE * SS), (0, 0, 0, 0))
d = ImageDraw.Draw(big)
pad = SS  # half a pixel's room so the edge isn't clipped
d.ellipse([pad, pad, SIZE * SS - 1 - pad, SIZE * SS - 1 - pad], fill=(0, 0, 0, 255))
inner = pad + EDGE * SS
d.ellipse([inner, inner, SIZE * SS - 1 - inner, SIZE * SS - 1 - inner], fill=(255, 255, 255, 255))
img = big.resize((SIZE, SIZE), Image.LANCZOS)
img.save(OUT)
print("wrote", OUT)
