"""Draws the Mr. Miyagi logo: a little bonsai tree in a pot, with a pair of
chopsticks above it, on a dark round badge with a gold rim (the same badge
style as the user's other addons).

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
circle(d, 432, fill=(30, 24, 30))

inside = Image.new("RGBA", (S, S), (0, 0, 0, 0))
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse([C - 330, C - 300, C + 330, C + 300], fill=(230, 120, 90, 50))
inside = Image.alpha_composite(inside, glow.filter(ImageFilter.GaussianBlur(70)))
di = ImageDraw.Draw(inside)

# A red rising sun behind the tree
circle(di, 250, fill=(190, 60, 50), cx=C, cy=470)

# Trunk: a curving bonsai trunk
trunk = [(500, 760), (470, 680), (520, 600), (470, 520), (530, 450), (560, 470), (520, 530), (575, 600), (530, 690), (560, 760)]
di.polygon([(x + 8, y + 10) for x, y in trunk], fill=(0, 0, 0, 120))
di.polygon(trunk, fill=(110, 70, 40), outline=(60, 36, 20), width=8)
# Foliage pads
for cx, cy, rx, ry in ((400, 470, 120, 62), (610, 420, 130, 66), (520, 340, 120, 60), (660, 560, 90, 48)):
    di.ellipse([cx - rx + 8, cy - ry + 12, cx + rx + 8, cy + ry + 12], fill=(0, 0, 0, 110))
    di.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=(70, 150, 80), outline=(30, 80, 40), width=8)
    di.ellipse([cx - rx + 30, cy - ry + 14, cx + rx - 50, cy - 4], fill=(120, 200, 120))

# Pot
di.polygon([(360 + 8, 760 + 10), (664 + 8, 760 + 10), (620 + 8, 840 + 10), (404 + 8, 840 + 10)], fill=(0, 0, 0, 120))
di.polygon([(360, 760), (664, 760), (620, 840), (404, 840)], fill=(60, 90, 140), outline=(25, 40, 70), width=8)
di.rectangle([340, 740, 684, 772], fill=(80, 115, 170), outline=(25, 40, 70), width=8)

# Chopsticks across the top
for (x0, y0, x1, y1) in ((250, 250, 700, 175), (270, 290, 720, 240)):
    di.line([(x0 + 6, y0 + 10), (x1 + 6, y1 + 10)], fill=(0, 0, 0, 130), width=26)
    di.line([(x0, y0), (x1, y1)], fill=(220, 180, 110), width=22)
    di.line([(x0, y0 - 6), (x1, y1 - 6)], fill=(250, 220, 160), width=6)

mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).ellipse([C - 432, C - 432, C + 432, C + 432], fill=255)
clipped = Image.new("RGBA", (S, S), (0, 0, 0, 0))
clipped.paste(inside, (0, 0), Image.composite(inside.split()[3], Image.new("L", (S, S), 0), mask))
img = Image.alpha_composite(img, clipped)
ring = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(ring).ellipse([C - 440, C - 440, C + 440, C + 440], outline=(0, 0, 0, 140), width=22)
img = Image.alpha_composite(img, ring.filter(ImageFilter.GaussianBlur(8)))

out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "addons", "MrMiyagi", "Media")
os.makedirs(out_dir, exist_ok=True)
img.resize((128, 128), Image.LANCZOS).save(os.path.join(out_dir, "Icon.tga"))
img.resize((512, 512), Image.LANCZOS).save(os.path.join(out_dir, "Logo.png"))
print("saved", os.path.join(out_dir, "Icon.tga"), "and Logo.png")
