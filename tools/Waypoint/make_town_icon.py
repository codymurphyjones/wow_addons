"""Draws the world map's town badge (Towns.lua): a white skyline (a gabled house beside a tower) on
a small dark round badge with a gold rim, Waypoint's own badge style, so it reads as Waypoint's and
not a game icon. Also a neutral version on a gold badge (Booty Bay, Gadgetzan...).

Usage: python make_town_icon.py <output dir> [preview dir]
Writes <output dir>/Town.tga and TownNeutral.tga (64x64, 32-bit), and PNG previews when given a
preview dir."""
import os
import sys
from PIL import Image, ImageDraw, ImageFilter

S = 512           # supersampled canvas, downscaled at the end
C = S / 2
OUT = 64


def badge(face, rim, inner):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse([C - 236, C - 228, C + 236, C + 244], fill=(0, 0, 0, 190))
    img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(10)))
    d = ImageDraw.Draw(img)
    d.ellipse([C - 240, C - 240, C + 240, C + 240], fill=rim)
    d.ellipse([C - 212, C - 212, C + 212, C + 212], fill=inner)
    d.ellipse([C - 196, C - 196, C + 196, C + 196], fill=face)

    # Skyline: a gabled house on the left, a taller tower with a pointed roof on the right.
    white, shade = (246, 242, 230, 255), (40, 40, 40, 255)
    base = C + 112
    # house
    d.rectangle([C - 150, C - 10, C - 10, base], fill=white)
    d.polygon([(C - 172, C - 6), (C - 80, C - 96), (C + 12, C - 6)], fill=white)
    d.rectangle([C - 98, C + 40, C - 62, base], fill=shade)             # door
    # tower
    d.rectangle([C + 18, C - 70, C + 128, base], fill=white)
    d.polygon([(C + 4, C - 66), (C + 73, C - 168), (C + 142, C - 66)], fill=white)
    d.rectangle([C + 56, C - 30, C + 90, C + 8], fill=shade)            # window
    # ground line
    d.rectangle([C - 176, base, C + 150, base + 14], fill=white)
    return img.resize((OUT, OUT), Image.LANCZOS)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "addons", "Waypoint", "Media")
    preview = sys.argv[2] if len(sys.argv) > 2 else None
    icons = {
        "Town": badge(face=(28, 42, 56, 255), rim=(214, 166, 64, 255), inner=(92, 60, 18, 255)),
        "TownNeutral": badge(face=(150, 108, 34, 255), rim=(240, 200, 96, 255), inner=(92, 60, 18, 255)),
    }
    for name, img in icons.items():
        img.save(os.path.join(out, name + ".tga"))
        if preview:
            img.resize((256, 256), Image.NEAREST).save(os.path.join(preview, name + ".png"))
    print("wrote", ", ".join(n + ".tga" for n in icons), "to", out)


if __name__ == "__main__":
    main()
