"""Draws the RoadLog logo: a cobbled road winding from the bottom of the badge toward a green
horizon, with a dashed center line, on a dark round badge with a gold rim (the same badge style as
Waypoint's).

Usage: python make_icon.py [output dir]
Writes <output dir>/Icon.tga (128x128, 32-bit, used in game) and
<output dir>/Logo.png (512x512, for CurseForge and other listings).
The output dir defaults to addons/RoadLog/Media."""
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
di = ImageDraw.Draw(inside)

# Dusk sky: deep blue at the top, warm gold at the horizon
HORIZON = 430
for y in range(0, HORIZON):
    t = (y / HORIZON) ** 1.8
    di.line([(0, y), (S, y)], fill=(int(30 + 210 * t), int(48 + 140 * t), int(80 + 30 * t)))
di.rectangle([0, HORIZON, S, S], fill=(46, 92, 46))
di.rectangle([0, HORIZON, S, HORIZON + 40], fill=(64, 112, 58))


# The road: a centerline that winds from the bottom up to a point on the horizon, widening toward
# the viewer.
def center(t):  # t = 0 at the horizon, 1 at the bottom
    return C + 150 * math.sin(t * math.pi * 1.25 - 0.4) * t, HORIZON + t * (S - HORIZON)


def width(t):
    return 10 + 330 * t ** 1.6


N = 120
left = [(center(i / N)[0] - width(i / N), center(i / N)[1]) for i in range(N + 1)]
right = [(center(i / N)[0] + width(i / N), center(i / N)[1]) for i in range(N + 1)]
di.polygon(left + right[::-1], fill=(150, 120, 80))
di.line(left, fill=(96, 72, 44), width=14)
di.line(right, fill=(96, 72, 44), width=14)

# Dashed center line in gold
for i in range(N):
    if (i // 8) % 2:
        continue
    t0, t1 = i / N, (i + 1) / N
    di.line([center(t0), center(t1)], fill=(255, 210, 90), width=max(4, int(4 + 26 * t1 ** 1.6)))

mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).ellipse([C - 432, C - 432, C + 432, C + 432], fill=255)
clipped = Image.new("RGBA", (S, S), (0, 0, 0, 0))
clipped.paste(inside, (0, 0), Image.composite(inside.split()[3], Image.new("L", (S, S), 0), mask))
img = Image.alpha_composite(img, clipped)

# Inner shadow under the rim
ring = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(ring).ellipse([C - 440, C - 440, C + 440, C + 440], outline=(0, 0, 0, 140), width=22)
img = Image.alpha_composite(img, ring.filter(ImageFilter.GaussianBlur(8)))

out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "addons", "RoadLog", "Media")
os.makedirs(out_dir, exist_ok=True)
img.resize((128, 128), Image.LANCZOS).save(os.path.join(out_dir, "Icon.tga"))
img.resize((512, 512), Image.LANCZOS).save(os.path.join(out_dir, "Logo.png"))
print("saved", os.path.join(out_dir, "Icon.tga"), "and Logo.png")
