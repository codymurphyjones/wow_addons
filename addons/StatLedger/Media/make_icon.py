"""Draws the StatLedger logo: three ranked bars (gold, silver, bronze), each
led by a numbered stat gem (red, green, blue), and a green "move up" arrow,
on a dark round badge with a gold rim (the same badge style as Bandolier's).

Usage: python make_icon.py <output dir>
Writes <output dir>/Icon.tga (128x128, 32-bit, used in game) and
<output dir>/Logo.png (512x512, for CurseForge and other listings)."""
import os, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

S = 1024                      # supersampled canvas, downscaled at the end
C = S / 2
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))


def circle(d, r, fill=None, outline=None, width=0, cx=C, cy=C):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill, outline=outline, width=width)


def font(size):
    for name in ("arialbd.ttf", "DejaVuSans-Bold.ttf", "Arial Bold.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


# Soft drop shadow
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(shadow).ellipse([C - 470, C - 455, C + 470, C + 485], fill=(0, 0, 0, 170))
img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(18)))
d = ImageDraw.Draw(img)

# Gold rim and dark badge
circle(d, 480, fill=(120, 82, 24))
circle(d, 462, fill=(214, 166, 64))
circle(d, 446, fill=(92, 60, 18))
circle(d, 432, fill=(24, 28, 44))

# Everything inside the badge is drawn on a layer clipped to the badge.
inside = Image.new("RGBA", (S, S), (0, 0, 0, 0))
di = ImageDraw.Draw(inside)

# A faint glow behind the bars
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse([C - 330, C - 300, C + 330, C + 300], fill=(90, 140, 220, 70))
inside = Image.alpha_composite(inside, glow.filter(ImageFilter.GaussianBlur(60)))
di = ImageDraw.Draw(inside)

# Ranked bars: (y centre, length, bar colour, bar highlight, gem colour)
BARS = [
    (330, 470, (226, 178, 64), (255, 226, 130), (214, 52, 52)),
    (512, 360, (176, 182, 196), (228, 232, 240), (58, 178, 74)),
    (694, 250, (178, 110, 56), (222, 160, 104), (60, 120, 220)),
]
X0, H = 250, 120
digits = font(96)
# Translucent shine goes on its own layer: drawing it straight onto the bars
# would replace their colour instead of blending with it.
shine = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ds = ImageDraw.Draw(shine)
for rank, (y, length, bar, light, gem) in enumerate(BARS, 1):
    # bar with a darker edge and a top highlight
    di.rounded_rectangle([X0, y - H / 2 + 8, X0 + length, y + H / 2 + 8], radius=H / 2, fill=(0, 0, 0, 120))
    di.rounded_rectangle([X0, y - H / 2, X0 + length, y + H / 2], radius=H / 2, fill=bar)
    ds.rounded_rectangle([X0 + 96, y - H / 2 + 14, X0 + length - 34, y - 8], radius=22, fill=light + (170,))
    # numbered gem at the left end
    gx = X0 + 4
    circle(di, 78, fill=(20, 18, 26), cx=gx, cy=y)
    circle(di, 66, fill=gem, cx=gx, cy=y)
    circle(di, 22, fill=tuple(min(255, c + 110) for c in gem), cx=gx - 30, cy=y - 30)
    di.text((gx, y + 4), str(rank), font=digits, fill=(255, 255, 255), anchor="mm",
            stroke_width=6, stroke_fill=(20, 18, 26))

# Green "move up" arrow to the right of the shorter bars
ax, top, bottom = 770, 470, 790
arrow = [(ax, top), (ax + 120, top + 140), (ax + 50, top + 140), (ax + 50, bottom),
         (ax - 50, bottom), (ax - 50, top + 140), (ax - 120, top + 140)]
di.polygon([(x + 8, y + 10) for x, y in arrow], fill=(0, 0, 0, 130))
di.polygon(arrow, fill=(70, 200, 90), outline=(20, 60, 26), width=10)
ds.polygon([(ax, top + 40), (ax + 60, top + 110), (ax - 60, top + 110)], fill=(170, 250, 180, 150))
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

out_dir = sys.argv[1]
os.makedirs(out_dir, exist_ok=True)
icon = img.resize((128, 128), Image.LANCZOS)
icon.save(os.path.join(out_dir, "Icon.tga"))
img.resize((512, 512), Image.LANCZOS).save(os.path.join(out_dir, "Logo.png"))
print("saved", os.path.join(out_dir, "Icon.tga"), "and Logo.png")
