"""Draws the Zeppelin Signs logo: a striped goblin zeppelin with a wooden gondola
floating over a wooden signpost whose arrow points the way, on a dark round badge
with a gold rim (the same badge style as StatLedger's and TapeMeasure's).

Usage: python make_icon.py <output dir>
Writes <output dir>/Icon.tga (128x128, 32-bit, used in game) and
<output dir>/Logo.png (512x512, for CurseForge and other listings)."""
import os, sys
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
circle(d, 432, fill=(24, 28, 44))

# Everything inside the badge is drawn on a layer clipped to the badge.
inside = Image.new("RGBA", (S, S), (0, 0, 0, 0))

# A faint dusk-blue sky glow behind the zeppelin, and a few soft clouds
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse([C - 380, C - 360, C + 380, C + 160], fill=(90, 150, 235, 70))
inside = Image.alpha_composite(inside, glow.filter(ImageFilter.GaussianBlur(70)))
clouds = Image.new("RGBA", (S, S), (0, 0, 0, 0))
dc = ImageDraw.Draw(clouds)
for cx, cy, rx, ry in [(760, 800, 110, 50), (850, 770, 80, 44), (680, 820, 80, 36),
                       (190, 300, 70, 30), (250, 285, 60, 28)]:
    dc.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=(220, 230, 250, 90))
inside = Image.alpha_composite(inside, clouds.filter(ImageFilter.GaussianBlur(10)))
di = ImageDraw.Draw(inside)
# Translucent shine goes on its own layer so it blends instead of replacing colour.
shine = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ds = ImageDraw.Draw(shine)

# --- The zeppelin -----------------------------------------------------------
EX, EY, RX, RY = 560, 330, 300, 150   # envelope centre and radii

# Tail fins at the back (left) end, drawn first so the envelope covers their roots.
for fin in ([(EX - RX + 70, EY - 30), (EX - RX - 50, EY - 150), (EX - RX + 10, EY - 150), (EX - RX + 140, EY - 40)],
            [(EX - RX + 70, EY + 30), (EX - RX - 50, EY + 150), (EX - RX + 10, EY + 150), (EX - RX + 140, EY + 40)]):
    di.polygon([(x + 8, y + 10) for x, y in fin], fill=(0, 0, 0, 120))
    di.polygon(fin, fill=(150, 40, 30), outline=(54, 14, 10), width=8)

# Ropes from the envelope down to the gondola
GX0, GX1, GY0, GY1 = 460, 680, 520, 590
for top, bottom in [((EX - 120, EY + 120), (GX0 + 20, GY0)), ((EX - 30, EY + 145), (GX0 + 90, GY0)),
                    ((EX + 60, EY + 140), (GX1 - 90, GY0)), ((EX + 150, EY + 115), (GX1 - 20, GY0))]:
    di.line([top, bottom], fill=(150, 120, 80), width=8)

# Envelope: red with orange stripes, clipped to the ellipse, with a dark outline.
di.ellipse([EX - RX + 10, EY - RY + 16, EX + RX + 10, EY + RY + 16], fill=(0, 0, 0, 130))
env = Image.new("RGBA", (S, S), (0, 0, 0, 0))
de = ImageDraw.Draw(env)
de.ellipse([EX - RX, EY - RY, EX + RX, EY + RY], fill=(196, 52, 38))
for i, x in enumerate(range(EX - RX, EX + RX, 75)):
    if i % 2:
        de.rectangle([x, EY - RY, x + 75, EY + RY], fill=(238, 132, 40))
# Darker underside for roundness
env_mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(env_mask).ellipse([EX - RX, EY - RY, EX + RX, EY + RY], fill=255)
under = Image.new("L", (S, S), 0)
ImageDraw.Draw(under).ellipse([EX - RX - 40, EY + 40, EX + RX + 40, EY + RY + 200], fill=110)
under = Image.composite(under.filter(ImageFilter.GaussianBlur(30)), Image.new("L", (S, S), 0), env_mask)
env = Image.alpha_composite(env, Image.merge("RGBA", (Image.new("L", (S, S), 40),) * 3 + (under,)))
inside.paste(env, (0, 0), Image.composite(env.split()[3], Image.new("L", (S, S), 0), env_mask))
di = ImageDraw.Draw(inside)
di.ellipse([EX - RX, EY - RY, EX + RX, EY + RY], outline=(60, 16, 10), width=10)
# Metal nose cap at the front (right) end
di.chord([EX + RX - 70, EY - 60, EX + RX + 4, EY + 60], 270, 90, fill=(176, 182, 194), outline=(52, 54, 62), width=8)
# Highlight across the top of the envelope
ds.ellipse([EX - RX + 80, EY - RY + 24, EX + RX - 120, EY - RY + 80], fill=(255, 230, 200, 110))

# Gondola: a wooden car with portholes and a propeller at the back
di.rounded_rectangle([GX0 + 8, GY0 + 10, GX1 + 8, GY1 + 10], radius=22, fill=(0, 0, 0, 130))
di.rounded_rectangle([GX0, GY0, GX1, GY1], radius=22, fill=(132, 84, 42), outline=(48, 28, 12), width=8)
di.rectangle([GX0 + 10, GY0 + 44, GX1 - 10, GY0 + 52], fill=(96, 58, 26))
for x in range(GX0 + 50, GX1 - 20, 60):
    circle(di, 16, fill=(250, 214, 110), outline=(48, 28, 12), width=6, cx=x, cy=GY0 + 26)
# Propeller
di.line([(GX0 - 10, GY0 + 35), (GX0 - 40, GY0 + 35)], fill=(52, 54, 62), width=12)
di.ellipse([GX0 - 62, GY0 - 30, GX0 - 34, GY0 + 100], fill=(176, 182, 194), outline=(52, 54, 62), width=6)

# --- The signpost ------------------------------------------------------------
PX, PY = 300, 640               # post centre x, top of the sign plank
# Post
di.rectangle([PX - 26 + 10, PY + 20, PX + 26 + 10, 980], fill=(0, 0, 0, 130))
di.rectangle([PX - 26, PY - 20, PX + 26, 980], fill=(120, 76, 36), outline=(48, 28, 12), width=8)
# Arrow-shaped plank pointing right, toward where the zeppelin is headed
plank = [(140, PY), (560, PY), (650, PY + 70), (560, PY + 140), (140, PY + 140)]
di.polygon([(x + 10, y + 12) for x, y in plank], fill=(0, 0, 0, 140))
di.polygon(plank, fill=(196, 140, 72), outline=(60, 34, 14), width=10)
# Wood grain and nails
for y in (PY + 36, PY + 104):
    di.line([(160, y), (540, y)], fill=(160, 108, 50), width=6)
for x in (180, 520):
    circle(di, 10, fill=(70, 70, 80), cx=x, cy=PY + 70)
# "Writing" on the sign
di.rounded_rectangle([220, PY + 52, 480, PY + 88], radius=14, fill=(64, 36, 14))
ds.polygon([(150, PY + 8), (556, PY + 8), (580, PY + 26), (150, PY + 26)], fill=(255, 230, 180, 110))
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
img.resize((128, 128), Image.LANCZOS).save(os.path.join(out_dir, "Icon.tga"))
img.resize((512, 512), Image.LANCZOS).save(os.path.join(out_dir, "Logo.png"))
print("saved", os.path.join(out_dir, "Icon.tga"), "and Logo.png")
