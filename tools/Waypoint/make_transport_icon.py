"""Draws the world map's dock icons (TransportPins.lua) in Waypoint's badge style (make_town_icon.py:
a small dark round badge with a gold rim), with a white zeppelin (also used for skyships) or a
white sailing ship on it, so they read as Waypoint's and not a game icon.

Usage: python make_transport_icon.py <output dir> [preview dir]
Writes <output dir>/Zeppelin.tga and Ship.tga (64x64, 32-bit), and PNG previews when given a
preview dir. With no output dir, writes into addons/Waypoint/Media."""
import os
import sys
from PIL import Image, ImageDraw, ImageFilter

S = 512           # supersampled canvas, downscaled at the end
C = S / 2
OUT = 64
WHITE, SHADE = (246, 242, 230, 255), (40, 40, 40, 255)


def badge(face, rim, inner):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse([C - 236, C - 228, C + 236, C + 244], fill=(0, 0, 0, 190))
    img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(10)))
    d = ImageDraw.Draw(img)
    d.ellipse([C - 240, C - 240, C + 240, C + 240], fill=rim)
    d.ellipse([C - 212, C - 212, C + 212, C + 212], fill=inner)
    d.ellipse([C - 196, C - 196, C + 196, C + 196], fill=face)
    return img, d


def zeppelin():
    img, d = badge(face=(28, 42, 56, 255), rim=(214, 166, 64, 255), inner=(92, 60, 18, 255))
    # The balloon: a long ellipse, with two seams.
    d.ellipse([C - 160, C - 120, C + 140, C + 30], fill=WHITE)
    d.line([(C - 120, C - 45), (C + 110, C - 45)], fill=SHADE, width=10)
    d.arc([C - 60, C - 120, C + 40, C + 30], 270, 90, fill=SHADE, width=10)
    # Tail fins, top and bottom.
    d.polygon([(C + 110, C - 60), (C + 172, C - 130), (C + 182, C - 50)], fill=WHITE)
    d.polygon([(C + 110, C - 30), (C + 172, C + 40), (C + 182, C - 40)], fill=WHITE)
    # The gondola hung under it.
    d.line([(C - 60, C + 20), (C - 40, C + 70)], fill=WHITE, width=12)
    d.line([(C + 40, C + 20), (C + 20, C + 70)], fill=WHITE, width=12)
    d.rounded_rectangle([C - 80, C + 66, C + 50, C + 116], radius=18, fill=WHITE)
    d.rectangle([C - 54, C + 80, C - 30, C + 100], fill=SHADE)
    d.rectangle([C - 6, C + 80, C + 18, C + 100], fill=SHADE)
    return img.resize((OUT, OUT), Image.LANCZOS)


def ship():
    img, d = badge(face=(24, 48, 70, 255), rim=(214, 166, 64, 255), inner=(92, 60, 18, 255))
    # Two sails on a mast.
    d.rectangle([C - 8, C - 160, C + 8, C + 70], fill=WHITE)
    d.polygon([(C - 20, C - 140), (C - 20, C + 50), (C - 150, C + 50)], fill=WHITE)
    d.polygon([(C + 20, C - 120), (C + 20, C + 50), (C + 120, C + 50)], fill=WHITE)
    d.polygon([(C + 8, C - 160), (C + 70, C - 140), (C + 8, C - 120)], fill=WHITE)  # pennant
    # The hull, and the sea under it.
    d.polygon([(C - 170, C + 70), (C + 170, C + 70), (C + 120, C + 140), (C - 120, C + 140)], fill=WHITE)
    d.rectangle([C - 110, C + 92, C + 110, C + 104], fill=SHADE)
    d.line([(C - 150, C + 168), (C + 150, C + 168)], fill=WHITE, width=12)
    return img.resize((OUT, OUT), Image.LANCZOS)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.dirname(here)), "addons", "Waypoint", "Media")
    preview = sys.argv[2] if len(sys.argv) > 2 else None
    icons = {"Zeppelin": zeppelin(), "Ship": ship()}
    for name, img in icons.items():
        img.save(os.path.join(out, name + ".tga"))
        if preview:
            img.resize((256, 256), Image.NEAREST).save(os.path.join(preview, name + ".png"))
    print("wrote", ", ".join(n + ".tga" for n in icons), "to", out)


if __name__ == "__main__":
    main()
