"""Draws WallyTooltip's logo: a tooltip box with a mouse pointer beside it, on the suite's dark badge
with a teal rim (as WallyChat's).

    python tools/WallyTooltip/make_icon.py     (needs Pillow: not -I)

Writes addons/WallyTooltip/Media/Icon.tga (128x128), drawn at 4x and scaled down.
"""
import os, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "_shared"))
import iconkit as ik
from iconkit import s

ACCENT, DARK = ik.WALLY_ACCENT, ik.WALLY_DARK
TEXT = (237, 240, 245, 255)


def main():
    out = ik.out_dir("WallyTooltip", use_argv=False)
    img, d = ik.canvas(128)
    ik.wally_badge(d)
    # the tooltip: a box with three lines of text, the first brighter
    d.rounded_rectangle([s(44), s(24), s(108), s(78)], radius=s(8), fill=(28, 33, 42, 255), outline=ACCENT, width=s(3))
    d.rounded_rectangle([s(54), s(36), s(98), s(42)], radius=s(3), fill=TEXT)
    d.rounded_rectangle([s(54), s(49), s(90), s(54)], radius=s(2), fill=(237, 240, 245, 150))
    d.rounded_rectangle([s(54), s(60), s(82), s(65)], radius=s(2), fill=(237, 240, 245, 150))
    # the pointer, below left of it
    d.polygon([(s(24), s(62)), (s(24), s(104)), (s(34), s(94)), (s(42), s(110)), (s(49), s(106)),
               (s(41), s(91)), (s(54), s(90))], fill=TEXT, outline=DARK)
    ik.save(img, out, (("Icon.tga", 128), ("Logo.png", 512)))  # Logo.png: for CurseForge
    print("icon written to", out)


if __name__ == "__main__":
    main()
