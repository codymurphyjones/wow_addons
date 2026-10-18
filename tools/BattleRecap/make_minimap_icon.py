"""Draws BattleRecap's minimap icon: two crossed swords over a field split Alliance blue and
Horde red, with a small skull where the blades cross. Bold shapes and no rim, so it still reads
at minimap size (the button rounds it with a mask and draws the gold ring itself).

Usage: python make_minimap_icon.py <output dir> [preview.png]
Writes <output dir>/MinimapIcon.tga (64x64, 32-bit), and a 256x256 preview if asked."""
import os, sys
from PIL import Image, ImageDraw, ImageFilter

S = 1024                      # supersampled canvas, downscaled at the end
C = S / 2
img = Image.new("RGBA", (S, S), (0, 0, 0, 255))
d = ImageDraw.Draw(img)

# Diagonal split: Alliance blue top-left, Horde red bottom-right, each with a lighter centre.
d.polygon([(0, 0), (S, 0), (0, S)], fill=(28, 70, 170))
d.polygon([(S, 0), (S, S), (0, S)], fill=(170, 28, 24))
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse([C - 380, C - 380, C + 380, C + 380], fill=(255, 220, 140, 90))
img = Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(90)))
d = ImageDraw.Draw(img)
d.line([(S, 0), (0, S)], fill=(250, 210, 90), width=26)   # gold seam between the halves


def sword():
    """One upright sword, point up, centred on the canvas; chunky so it survives downscaling."""
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ds = ImageDraw.Draw(layer)
    top, guard, bottom, w = C - 450, C + 210, C + 400, 70
    blade = [(C, top), (C + w, top + 120), (C + w, guard), (C - w, guard), (C - w, top + 120)]
    ds.polygon([(x + 14, y + 16) for x, y in blade], fill=(0, 0, 0, 150))
    ds.polygon(blade, fill=(225, 232, 242), outline=(30, 34, 46), width=16)
    ds.polygon([(C, top + 50), (C + 22, top + 120), (C + 22, guard - 16), (C, guard - 16)], fill=(255, 255, 255))
    ds.rounded_rectangle([C - 175, guard - 10, C + 175, guard + 62], radius=26, fill=(240, 190, 60), outline=(70, 44, 10), width=14)
    ds.rounded_rectangle([C - 38, guard + 62, C + 38, bottom], radius=14, fill=(110, 62, 30), outline=(40, 22, 8), width=12)
    ds.ellipse([C - 60, bottom - 10, C + 60, bottom + 110], fill=(240, 190, 60), outline=(70, 44, 10), width=14)
    return layer


for angle in (42, -42):
    img = Image.alpha_composite(img, sword().rotate(angle, resample=Image.BICUBIC, center=(C, C)))

# Small skull where the blades cross
d = ImageDraw.Draw(img)
BONE, EDGE, HOLE = (245, 238, 220), (30, 24, 22), (30, 16, 18)
sx, sy, r = C, C - 30, 150
d.ellipse([sx - r, sy - r, sx + r, sy + r * 0.85], fill=BONE, outline=EDGE, width=16)
d.rounded_rectangle([sx - 88, sy + 70, sx + 88, sy + 190], radius=30, fill=BONE, outline=EDGE, width=16)
d.rectangle([sx - 72, sy + 60, sx + 72, sy + 92], fill=BONE)
d.ellipse([sx - 110, sy - 30, sx - 22, sy + 62], fill=HOLE)
d.ellipse([sx + 22, sy - 30, sx + 110, sy + 62], fill=HOLE)
d.polygon([(sx, sy + 74), (sx + 22, sy + 112), (sx - 22, sy + 112)], fill=HOLE)
for i in (-1, 0, 1):
    d.line([(sx + i * 34, sy + 128), (sx + i * 34, sy + 184)], fill=EDGE, width=12)

out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "addons", "BattleRecap", "Media")
os.makedirs(out_dir, exist_ok=True)
img.resize((64, 64), Image.LANCZOS).save(os.path.join(out_dir, "MinimapIcon.tga"))
if len(sys.argv) > 2:
    img.resize((256, 256), Image.LANCZOS).save(sys.argv[2])
print("saved", os.path.join(out_dir, "MinimapIcon.tga"))
