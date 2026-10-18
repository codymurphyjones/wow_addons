"""Draws the SpyGlass Quests logo: the SpyGlass badge, with the brass spyglass
raised toward a golden quest "!" (the quest reward it has spotted) in place
of the glint, and the family's green upgrade arrow.

Usage: python make_icon.py <output dir>
Writes <output dir>/Icon.tga (128x128, 32-bit, used in game) and
<output dir>/Logo.png (512x512, for CurseForge and other listings)."""
import math, os, sys
from PIL import Image, ImageDraw, ImageFilter

S = 1024                      # supersampled canvas, downscaled at the end
C = S / 2
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

BRASS, BRASS_LIGHT, BRASS_DARK, OUTLINE = (214, 164, 62), (250, 214, 120), (140, 96, 30), (48, 30, 12)
LEATHER, LEATHER_DARK = (122, 62, 34), (74, 36, 18)


def circle(d, r, fill=None, outline=None, width=0, cx=C, cy=C):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill, outline=outline, width=width)


def sparkle(d, cx, cy, r, fill, thin=0.22):
    """A four-pointed star."""
    t = r * thin
    d.polygon([(cx, cy - r), (cx + t, cy - t), (cx + r, cy), (cx + t, cy + t),
               (cx, cy + r), (cx - t, cy + t), (cx - r, cy), (cx - t, cy - t)], fill=fill)


# Soft drop shadow
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(shadow).ellipse([C - 470, C - 455, C + 470, C + 485], fill=(0, 0, 0, 170))
img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(18)))
d = ImageDraw.Draw(img)

# Gold rim and dark night-sky badge
circle(d, 480, fill=(120, 82, 24))
circle(d, 462, fill=(214, 166, 64))
circle(d, 446, fill=(92, 60, 18))
circle(d, 432, fill=(22, 26, 52))

# Everything inside the badge is drawn on a layer clipped to the badge.
inside = Image.new("RGBA", (S, S), (0, 0, 0, 0))
di = ImageDraw.Draw(inside)
# a faint lighter sky toward the glint
sky = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(sky).ellipse([520, 80, 1000, 520], fill=(70, 70, 130, 120))
inside = Image.alpha_composite(inside, sky.filter(ImageFilter.GaussianBlur(90)))
di = ImageDraw.Draw(inside)
for x, y, r in ((230, 250, 16), (330, 160, 11), (180, 420, 10), (470, 210, 13), (860, 600, 12), (300, 330, 8)):
    sparkle(di, x, y, r, (230, 226, 200))

# The quest the spyglass has spotted: a glow and a golden quest "!".
gx, gy = 620, 250
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse([gx - 160, gy - 170, gx + 160, gy + 170], fill=(255, 210, 90, 170))
inside = Image.alpha_composite(inside, glow.filter(ImageFilter.GaussianBlur(45)))
di = ImageDraw.Draw(inside)


def bang(d, ox, oy, fill, outline=None, width=0):
    """A quest "!": a bar tapering downward over a round dot."""
    d.polygon([(gx - 56 + ox, gy - 120 + oy), (gx + 56 + ox, gy - 120 + oy),
               (gx + 28 + ox, gy + 40 + oy), (gx - 28 + ox, gy + 40 + oy)], fill=fill, outline=outline, width=width)
    d.rounded_rectangle([gx - 56 + ox, gy - 150 + oy, gx + 56 + ox, gy - 90 + oy], radius=28, fill=fill, outline=outline, width=width)
    circle(d, 38, fill=fill, outline=outline, width=width, cx=gx + ox, cy=gy + 102 + oy)


bang(di, 8, 10, (0, 0, 0, 110))
bang(di, 0, 0, (255, 206, 40), OUTLINE, 14)
# hide the seam between the bar's cap and its body, then add a highlight
di.polygon([(gx - 48, gy - 112), (gx + 48, gy - 112), (gx + 42, gy - 80), (gx - 42, gy - 80)], fill=(255, 206, 40))
di.polygon([(gx - 36, gy - 132), (gx - 14, gy - 132), (gx - 12, gy + 10), (gx - 22, gy + 10)], fill=(255, 244, 180))
circle(di, 12, fill=(255, 244, 180), cx=gx - 12, cy=gy + 90)
sparkle(di, gx + 130, gy - 60, 28, (255, 236, 160))
sparkle(di, gx - 120, gy + 30, 20, (255, 236, 160))

# The spyglass, drawn level on its own layer and then tipped up toward the glint.
tel = Image.new("RGBA", (S, S), (0, 0, 0, 0))
dt = ImageDraw.Draw(tel)
cy = C
# (x0, x1, half height) from the eyepiece to the wide end
sections = [(190, 290, 38), (280, 450, 54), (440, 640, 70), (630, 820, 88)]
for x0, x1, h in sections:
    fill = LEATHER if (x0, x1, h) == sections[2] else BRASS
    dt.rounded_rectangle([x0, cy - h, x1, cy + h], radius=14, fill=fill, outline=OUTLINE, width=12)
    # highlight along the top, shade along the bottom
    light = (176, 96, 56) if fill == LEATHER else BRASS_LIGHT
    dark = LEATHER_DARK if fill == LEATHER else BRASS_DARK
    dt.rectangle([x0 + 18, cy - h + 14, x1 - 18, cy - h + 14 + h * 0.32], fill=light)
    dt.rectangle([x0 + 18, cy + h - 14 - h * 0.3, x1 - 18, cy + h - 14], fill=dark)
# brass bands at the joints and the rim of the wide end
for x, h in ((288, 58), (448, 74), (636, 92)):
    dt.rounded_rectangle([x - 16, cy - h, x + 16, cy + h], radius=8, fill=BRASS, outline=OUTLINE, width=10)
dt.rounded_rectangle([800, cy - 106, 860, cy + 106], radius=16, fill=BRASS, outline=OUTLINE, width=12)
dt.rectangle([814, cy - 90, 846, cy - 40], fill=BRASS_LIGHT)
# eyepiece cap
dt.rounded_rectangle([166, cy - 28, 204, cy + 28], radius=10, fill=BRASS_DARK, outline=OUTLINE, width=10)
# the lens, seen edge-on at the wide end
dt.ellipse([836, cy - 94, 896, cy + 94], fill=(150, 210, 240), outline=OUTLINE, width=12)
dt.ellipse([852, cy - 68, 876, cy - 18], fill=(235, 250, 255))

ang = 33  # degrees, tipped up to the right
tel = tel.rotate(ang, resample=Image.BICUBIC, center=(C, C))
# then moved down a little (an affine transform's offsets are where to read from)
tel = tel.transform((S, S), Image.AFFINE, (1, 0, 10, 0, 1, -95), resample=Image.BICUBIC)
tel_shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
tel_shadow.paste((0, 0, 0, 120), (14, 18), tel.split()[3])
inside = Image.alpha_composite(inside, tel_shadow.filter(ImageFilter.GaussianBlur(6)))
inside = Image.alpha_composite(inside, tel)
di = ImageDraw.Draw(inside)

# Green upgrade arrow, lower right (the family's shared mark)
ax, top, bottom = 770, 590, 830
arrow = [(ax, top), (ax + 110, top + 120), (ax + 46, top + 120), (ax + 46, bottom),
         (ax - 46, bottom), (ax - 46, top + 120), (ax - 110, top + 120)]
di.polygon([(x + 9, y + 11) for x, y in arrow], fill=(0, 0, 0, 130))
di.polygon(arrow, fill=(70, 200, 90), outline=(20, 60, 26), width=12)
shine = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(shine).polygon([(ax, top + 36), (ax + 54, top + 96), (ax - 54, top + 96)], fill=(170, 250, 180, 150))
inside = Image.alpha_composite(inside, shine)

mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).ellipse([C - 432, C - 432, C + 432, C + 432], fill=255)
clipped = Image.new("RGBA", (S, S), (0, 0, 0, 0))
clipped.paste(inside, (0, 0), Image.composite(inside.split()[3], Image.new("L", (S, S), 0), mask))
img = Image.alpha_composite(img, clipped)

# Inner shadow under the rim
ring = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(ring).ellipse([C - 440, C - 440, C + 440, C + 440], outline=(0, 0, 0, 140), width=22)
img = Image.alpha_composite(img, ring.filter(ImageFilter.GaussianBlur(8)))

out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "addons", "SpyglassPluginQuests", "Media")
os.makedirs(out_dir, exist_ok=True)
icon = img.resize((128, 128), Image.LANCZOS)
icon.save(os.path.join(out_dir, "Icon.tga"))
img.resize((512, 512), Image.LANCZOS).save(os.path.join(out_dir, "Logo.png"))
print("saved", os.path.join(out_dir, "Icon.tga"), "and Logo.png")
