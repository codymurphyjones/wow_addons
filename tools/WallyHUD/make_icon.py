"""Draws WallyHUD's logo: a miniature game screen laid out the quiet, tidy way WallyHUD dresses
yours: unit-frame bars top left, a round minimap top right, an action bar along the bottom, and a
small density slider; on the suite's dark badge with a teal rim (as WallyChat's and WallyTooltip's).

    python tools/WallyHUD/make_icon.py     (needs Pillow: not -I)

Writes addons/WallyHUD/Media/Icon.tga (128x128), drawn at 4x and scaled down.
"""
import os, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "_shared"))
import iconkit as ik
from iconkit import s

ACCENT, DARK = ik.WALLY_ACCENT, ik.WALLY_DARK
PANEL = (28, 33, 42, 255)
TEXT = (237, 240, 245, 255)
DIM = (237, 240, 245, 110)


def main():
    out = ik.out_dir("WallyHUD", use_argv=False)
    img, d = ik.canvas(128)
    ik.wally_badge(d)
    # the screen
    d.rounded_rectangle([s(20), s(24), s(108), s(92)], radius=s(8), fill=PANEL, outline=ACCENT, width=s(3))
    # unit frames: a health bar (teal) and a power bar (dim), top left
    d.rounded_rectangle([s(28), s(32), s(66), s(38)], radius=s(3), fill=ACCENT)
    d.rounded_rectangle([s(28), s(42), s(56), s(46)], radius=s(2), fill=DIM)
    # the minimap, top right
    d.ellipse([s(82), s(31), s(100), s(49)], outline=TEXT, width=s(3))
    d.ellipse([s(89.5), s(38.5), s(92.5), s(41.5)], fill=ACCENT)
    # the action bar, bottom
    for i in range(6):
        x = 32 + i * 11
        d.rounded_rectangle([s(x), s(74), s(x + 8), s(82)], radius=s(2), fill=TEXT if i < 4 else DIM)
    # the density slider, under the screen
    d.rounded_rectangle([s(30), s(102), s(98), s(106)], radius=s(2), fill=DIM)
    d.rounded_rectangle([s(30), s(102), s(66), s(106)], radius=s(2), fill=ACCENT)
    d.ellipse([s(60), s(98), s(72), s(110)], fill=TEXT, outline=DARK, width=s(1))
    ik.save(img, out, (("Icon.tga", 128),))
    print("icon written to", out)


if __name__ == "__main__":
    main()
