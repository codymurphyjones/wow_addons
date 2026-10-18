"""Draws the Convergence pin and logo: four elements (fire, water, earth, air) as wedges pointing
in to a bright spark where they meet, on a dark round badge with a teal edge.

Usage: python make_icon.py <output dir>
Writes <output dir>/Pin.tga (64x64, the world map pin, drawn at about 12 px),
<output dir>/Icon.tga (128x128, the addon list) and <output dir>/Logo.png (512x512, for listings)."""
import math, os, sys
from PIL import Image, ImageDraw, ImageFilter

S = 1024                      # supersampled canvas, downscaled at the end
C = S / 2
TEAL = (84, 235, 199)

img = Image.new("RGBA", (S, S), (0, 0, 0, 0))


def circle(d, r, fill=None, cx=C, cy=C):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill)


# Soft drop shadow
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(shadow).ellipse([C - 480, C - 470, C + 480, C + 490], fill=(0, 0, 0, 180))
img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(16)))
d = ImageDraw.Draw(img)

# Teal edge, dark rim, badge
circle(d, 490, fill=TEAL)
circle(d, 456, fill=(14, 22, 28))
circle(d, 430, fill=(26, 36, 44))

inside = Image.new("RGBA", (S, S), (0, 0, 0, 0))
di = ImageDraw.Draw(inside)

# Four wedges pointing in to the centre: fire (top), water (right), earth (bottom), air (left).
ELEMENTS = [
    (-90, (255, 112, 48), (255, 196, 92)),   # fire
    (0, (52, 140, 255), (140, 205, 255)),    # water
    (90, (128, 168, 70), (196, 214, 120)),   # earth
    (180, (205, 214, 226), (250, 252, 255)), # air
]
OUTER, INNER, HALF = 400, 70, 34            # wedge: from the rim to near the centre, half-angle in degrees


def polar(r, deg):
    a = math.radians(deg)
    return (C + r * math.cos(a), C + r * math.sin(a))


for deg, dark, light in ELEMENTS:
    wedge = [polar(OUTER, deg - HALF), polar(OUTER, deg + HALF), polar(INNER, deg)]
    di.polygon([(x + 8, y + 10) for x, y in wedge], fill=(0, 0, 0, 120))
    di.polygon(wedge, fill=dark)
    # Lit half, for a little depth
    di.polygon([polar(OUTER, deg - HALF), polar(OUTER * 0.98, deg), polar(INNER, deg)], fill=light)

# The spark where they meet
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
circle(ImageDraw.Draw(glow), 150, fill=(255, 240, 190, 200))
inside = Image.alpha_composite(inside, glow.filter(ImageFilter.GaussianBlur(40)))
di = ImageDraw.Draw(inside)
star = []
for i in range(8):
    r = 120 if i % 2 == 0 else 46
    star.append(polar(r, -90 + i * 45))
di.polygon(star, fill=(255, 250, 225))
circle(di, 40, fill=(255, 255, 255))

mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).ellipse([C - 430, C - 430, C + 430, C + 430], fill=255)
clipped = Image.new("RGBA", (S, S), (0, 0, 0, 0))
clipped.paste(inside, (0, 0), Image.composite(inside.split()[3], Image.new("L", (S, S), 0), mask))
img = Image.alpha_composite(img, clipped)

# Inner shadow under the rim
ring = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(ring).ellipse([C - 438, C - 438, C + 438, C + 438], outline=(0, 0, 0, 150), width=20)
img = Image.alpha_composite(img, ring.filter(ImageFilter.GaussianBlur(8)))

out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "addons", "Convergence", "Media")
os.makedirs(out_dir, exist_ok=True)
img.resize((64, 64), Image.LANCZOS).save(os.path.join(out_dir, "Pin.tga"))
img.resize((128, 128), Image.LANCZOS).save(os.path.join(out_dir, "Icon.tga"))
img.resize((512, 512), Image.LANCZOS).save(os.path.join(out_dir, "Logo.png"))
print("saved Pin.tga, Icon.tga and Logo.png in", out_dir)
