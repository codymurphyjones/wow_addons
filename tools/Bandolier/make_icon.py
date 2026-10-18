"""Draws the Bandolier logo: a leather bandolier strap across a dark round
badge with a gold rim, carrying four potion vials (health, mana, buff, food
colours) and a brass buckle.

Usage: python make_icon.py <output dir> [preview.png]
Writes <output dir>/Icon.tga (128x128, 32-bit) for the addon."""
import math, os, sys
from PIL import Image, ImageDraw, ImageFilter

S = 1024                      # supersampled canvas, downscaled at the end
C = S / 2
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))


def circle(d, r, fill=None, outline=None, width=0, cx=C, cy=C):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill, outline=outline, width=width)


def rotated(points, angle, cx, cy):
    a = math.radians(angle)
    ca, sa = math.cos(a), math.sin(a)
    return [(cx + (x - cx) * ca - (y - cy) * sa, cy + (x - cx) * sa + (y - cy) * ca) for x, y in points]


# Soft drop shadow
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(shadow).ellipse([C - 470, C - 455, C + 470, C + 485], fill=(0, 0, 0, 170))
img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(18)))
d = ImageDraw.Draw(img)

# Gold rim and dark badge
circle(d, 480, fill=(120, 82, 24))
circle(d, 462, fill=(214, 166, 64))
circle(d, 446, fill=(92, 60, 18))
circle(d, 432, fill=(30, 24, 34))

# Everything inside the badge is drawn on a layer clipped to the badge.
inside = Image.new("RGBA", (S, S), (0, 0, 0, 0))
di = ImageDraw.Draw(inside)

ANGLE = -35                   # strap runs from lower left to upper right
STRAP_W = 150

# Leather strap
strap = [(C - 700, C - STRAP_W / 2), (C + 700, C - STRAP_W / 2),
         (C + 700, C + STRAP_W / 2), (C - 700, C + STRAP_W / 2)]
di.polygon(rotated(strap, ANGLE, C, C), fill=(120, 72, 36))
for off, col in ((-STRAP_W / 2 + 10, (160, 102, 54)), (STRAP_W / 2 - 14, (84, 48, 24))):
    edge = [(C - 700, C + off), (C + 700, C + off), (C + 700, C + off + 6), (C - 700, C + off + 6)]
    di.polygon(rotated(edge, ANGLE, C, C), fill=col)
# Stitching
for x in range(int(C - 680), int(C + 680), 34):
    for off in (-STRAP_W / 2 + 26, STRAP_W / 2 - 30):
        dash = [(x, C + off), (x + 18, C + off), (x + 18, C + off + 5), (x, C + off + 5)]
        di.polygon(rotated(dash, ANGLE, C, C), fill=(214, 176, 120))

# Vials sitting in loops on the strap: health, mana, buff, food
VIALS = [(-270, (196, 40, 40)), (-90, (44, 96, 204)), (90, (226, 170, 48)), (270, (64, 160, 72))]


def vial(layer, x, color):
    """One upright vial whose centre sits on the strap at offset x."""
    v = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dv = ImageDraw.Draw(v)
    cx, cy = C + x, C
    # glass body
    dv.rounded_rectangle([cx - 46, cy - 120, cx + 46, cy + 110], radius=40, fill=(225, 230, 240))
    dv.rounded_rectangle([cx - 36, cy - 70, cx + 36, cy + 100], radius=32, fill=color)
    dv.rounded_rectangle([cx - 36, cy - 70, cx + 36, cy - 40], radius=14,
                         fill=tuple(min(255, c + 50) for c in color))
    dv.rounded_rectangle([cx - 26, cy - 50, cx - 10, cy + 70], radius=8, fill=(255, 255, 255, 120))
    # cork
    dv.rounded_rectangle([cx - 34, cy - 160, cx + 34, cy - 112], radius=10, fill=(150, 104, 58))
    dv.rounded_rectangle([cx - 34, cy - 160, cx + 34, cy - 144], radius=8, fill=(186, 134, 80))
    # leather loop holding it to the strap
    dv.rectangle([cx - 54, cy - 28, cx + 54, cy + 24], fill=(98, 58, 28))
    dv.rectangle([cx - 54, cy - 28, cx + 54, cy - 20], fill=(140, 90, 46))
    # place along the strap, kept upright
    a = math.radians(ANGLE)
    dx, dy = x * math.cos(a) - x, x * math.sin(a)
    shifted = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shifted.paste(v, (int(dx), int(dy)), v)
    return Image.alpha_composite(layer, shifted)


for x, color in VIALS:
    inside = vial(inside, x, color)

# Brass buckle on the strap, at the lower left
bx, by = rotated([(C - 420, C)], ANGLE, C, C)[0]
buckle = Image.new("RGBA", (S, S), (0, 0, 0, 0))
db = ImageDraw.Draw(buckle)
db.rounded_rectangle([bx - 70, by - 95, bx + 70, by + 95], radius=18, outline=(226, 184, 82), width=26)
db.line([bx, by - 70, bx, by + 70], fill=(226, 184, 82), width=18)
buckle = buckle.rotate(-ANGLE, center=(bx, by))
inside = Image.alpha_composite(inside, buckle)

mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).ellipse([C - 432, C - 432, C + 432, C + 432], fill=255)
clipped = Image.new("RGBA", (S, S), (0, 0, 0, 0))
clipped.paste(inside, (0, 0), Image.composite(inside.split()[3], Image.new("L", (S, S), 0), mask))
img = Image.alpha_composite(img, clipped)

# Inner shadow under the rim
ring = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(ring).ellipse([C - 440, C - 440, C + 440, C + 440], outline=(0, 0, 0, 140), width=22)
img = Image.alpha_composite(img, ring.filter(ImageFilter.GaussianBlur(8)))

out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "addons", "Bandolier", "Media")
os.makedirs(out_dir, exist_ok=True)
icon = img.resize((128, 128), Image.LANCZOS)
icon.save(os.path.join(out_dir, "Icon.tga"))
if len(sys.argv) > 2:
    img.resize((256, 256), Image.LANCZOS).save(sys.argv[2])
print("saved", os.path.join(out_dir, "Icon.tga"), icon.size, icon.mode)
