"""Draws the Waypoint logo: a gold navigation arrow pointing up and to the right, with a dotted
path of three waypoints trailing behind it, on a dark round badge with a gold rim (the same badge
style as Tape Measure's).

Usage: python make_icon.py <output dir>
Writes <output dir>/Icon.tga (128x128, 32-bit, used in game) and
<output dir>/Logo.png (512x512, for CurseForge and other listings)."""
import math, os, sys
from PIL import Image, ImageDraw, ImageFilter

S = 1024                      # supersampled canvas, downscaled at the end
C = S / 2
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))


def circle(d, r, fill=None, outline=None, width=0, cx=C, cy=C):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill, outline=outline, width=width)


# Soft drop shadow
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(shadow).ellipse([C - 470, C - 455, C + 470, C + 485], fill=(0, 0, 0, 170))
img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(18)))
d = ImageDraw.Draw(img)

# Gold rim and dark badge
circle(d, 480, fill=(120, 82, 24))
circle(d, 462, fill=(214, 166, 64))
circle(d, 446, fill=(92, 60, 18))
circle(d, 432, fill=(22, 34, 44))

inside = Image.new("RGBA", (S, S), (0, 0, 0, 0))

# A faint blue glow, like a map
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse([C - 340, C - 300, C + 340, C + 340], fill=(90, 170, 255, 55))
inside = Image.alpha_composite(inside, glow.filter(ImageFilter.GaussianBlur(80)))
di = ImageDraw.Draw(inside)

# The arrow: a classic navigation arrowhead pointing up and to the right.
ang = math.radians(45)


def rot(px, py, cx=620, cy=420, k=0.8):
    px, py = px * k, py * k
    return (cx + px * math.cos(ang) - py * math.sin(ang), cy + px * math.sin(ang) + py * math.cos(ang))



# The path: waypoints joined by a dashed line, from bottom left toward the arrow.
stops = [(240, 740), (420, 640), (300, 500)]
tip_base = rot(0, 150)
route = stops + [tip_base]
for (x0, y0), (x1, y1) in zip(route, route[1:]):
    length = math.hypot(x1 - x0, y1 - y0)
    n = int(length // 44)
    for i in range(n):
        if i % 2:
            continue
        a, b = i / n, min(1, (i + 1) / n)
        di.line([(x0 + (x1 - x0) * a, y0 + (y1 - y0) * a), (x0 + (x1 - x0) * b, y0 + (y1 - y0) * b)],
                fill=(150, 200, 255, 230), width=22)
for i, (x, y) in enumerate(stops):
    circle(di, 46, fill=(0, 0, 0, 120), cx=x + 6, cy=y + 8)
    circle(di, 44, fill=(30, 60, 90), cx=x, cy=y)
    circle(di, 32, fill=(110, 190, 255) if i < 2 else (255, 205, 80), cx=x, cy=y)

arrow = [rot(0, -300), rot(190, 200), rot(0, 90), rot(-190, 200)]
di.polygon([(x + 14, y + 18) for x, y in arrow], fill=(0, 0, 0, 140))
di.polygon(arrow, fill=(236, 178, 52), outline=(90, 56, 12), width=14)
# Lit half
lit = [rot(0, -300), rot(0, 90), rot(-190, 200)]
di.polygon(lit, fill=(255, 220, 120))
di.line([rot(0, -300), rot(0, 90)], fill=(170, 112, 24), width=8)

mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).ellipse([C - 432, C - 432, C + 432, C + 432], fill=255)
clipped = Image.new("RGBA", (S, S), (0, 0, 0, 0))
clipped.paste(inside, (0, 0), Image.composite(inside.split()[3], Image.new("L", (S, S), 0), mask))
img = Image.alpha_composite(img, clipped)

# Inner shadow under the rim
ring = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(ring).ellipse([C - 440, C - 440, C + 440, C + 440], outline=(0, 0, 0, 140), width=22)
img = Image.alpha_composite(img, ring.filter(ImageFilter.GaussianBlur(8)))

out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "addons", "Waypoint", "Media")
os.makedirs(out_dir, exist_ok=True)
img.resize((128, 128), Image.LANCZOS).save(os.path.join(out_dir, "Icon.tga"))
img.resize((512, 512), Image.LANCZOS).save(os.path.join(out_dir, "Logo.png"))
print("saved", os.path.join(out_dir, "Icon.tga"), "and Logo.png")
