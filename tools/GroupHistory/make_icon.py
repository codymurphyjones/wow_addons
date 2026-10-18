"""Draws the Group History logo: an open record scroll with a tally and a small
skull, in front of two party silhouettes, on a dark round badge with a gold rim
(the same badge style as StatLedger's and Wealth Planner's).

Usage: python make_icon.py <output dir>
Writes <output dir>/Icon.tga (128x128, 32-bit, used in game) and
<output dir>/Logo.png (512x512, for CurseForge and other listings)."""
import os, sys
from PIL import Image, ImageDraw, ImageFilter

S = 1024
C = S / 2


def circle(d, r, fill=None, outline=None, width=0, cx=C, cy=C):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill, outline=outline, width=width)


img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(shadow).ellipse([C - 470, C - 455, C + 470, C + 485], fill=(0, 0, 0, 170))
img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(18)))
d = ImageDraw.Draw(img)
circle(d, 480, fill=(120, 82, 24))
circle(d, 462, fill=(214, 166, 64))
circle(d, 446, fill=(92, 60, 18))
circle(d, 432, fill=(26, 26, 40))

inside = Image.new("RGBA", (S, S), (0, 0, 0, 0))
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse([C - 330, C - 300, C + 330, C + 300], fill=(80, 200, 180, 55))
inside = Image.alpha_composite(inside, glow.filter(ImageFilter.GaussianBlur(60)))
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

mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).ellipse([C - 432, C - 432, C + 432, C + 432], fill=255)
clipped = Image.new("RGBA", (S, S), (0, 0, 0, 0))
clipped.paste(inside, (0, 0), Image.composite(inside.split()[3], Image.new("L", (S, S), 0), mask))
img = Image.alpha_composite(img, clipped)
ring = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(ring).ellipse([C - 440, C - 440, C + 440, C + 440], outline=(0, 0, 0, 140), width=22)
img = Image.alpha_composite(img, ring.filter(ImageFilter.GaussianBlur(8)))

out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "addons", "GroupHistory", "Media")
os.makedirs(out_dir, exist_ok=True)
img.resize((128, 128), Image.LANCZOS).save(os.path.join(out_dir, "Icon.tga"))
img.resize((512, 512), Image.LANCZOS).save(os.path.join(out_dir, "Logo.png"))
print("saved", os.path.join(out_dir, "Icon.tga"), "and Logo.png")
