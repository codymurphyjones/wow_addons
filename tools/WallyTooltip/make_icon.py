"""Draws WallyTooltip's logo: a tooltip box with a mouse pointer beside it, on the suite's dark badge
with a teal rim (as WallyChat's).

    python tools/WallyTooltip/make_icon.py     (needs Pillow: not -I)

Writes addons/WallyTooltip/Media/Icon.tga (128x128), drawn at 4x and scaled down.
"""
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(os.path.dirname(HERE)), "addons", "WallyTooltip", "Media")
SS = 4
ACCENT = (64, 196, 205, 255)
DARK = (16, 19, 25, 255)
TEXT = (237, 240, 245, 255)


def s(v):
    return v * SS


def main():
    os.makedirs(OUT, exist_ok=True)
    img = Image.new("RGBA", (128 * SS, 128 * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([s(6), s(6), s(122), s(122)], radius=s(24), fill=DARK, outline=ACCENT, width=s(4))
    # the tooltip: a box with three lines of text, the first brighter
    d.rounded_rectangle([s(44), s(24), s(108), s(78)], radius=s(8), fill=(28, 33, 42, 255), outline=ACCENT, width=s(3))
    d.rounded_rectangle([s(54), s(36), s(98), s(42)], radius=s(3), fill=TEXT)
    d.rounded_rectangle([s(54), s(49), s(90), s(54)], radius=s(2), fill=(237, 240, 245, 150))
    d.rounded_rectangle([s(54), s(60), s(82), s(65)], radius=s(2), fill=(237, 240, 245, 150))
    # the pointer, below left of it
    d.polygon([(s(24), s(62)), (s(24), s(104)), (s(34), s(94)), (s(42), s(110)), (s(49), s(106)),
               (s(41), s(91)), (s(54), s(90))], fill=TEXT, outline=DARK)
    img.resize((128, 128), Image.LANCZOS).save(os.path.join(OUT, "Icon.tga"))
    print("icon written to", OUT)


if __name__ == "__main__":
    main()
