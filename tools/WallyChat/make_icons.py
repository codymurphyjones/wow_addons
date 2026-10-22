"""Draws WallyChat's icons: white glyphs on transparent squares (the addon tints them, monochrome at
rest and full colour under the mouse, the suite's ghost buttons), and its logo.

    python -I tools/WallyChat/make_icons.py

Writes into addons/WallyChat/Media:
  Friends.tga, Channels.tga, Menu.tga, FullScreen.tga, Exit.tga, Bottom.tga   64x64, the toolbar
  Icon.tga                                                                     128x128, the addon list
Each is drawn at 4x and scaled down, for smooth edges.
"""
import os, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "_shared"))
import iconkit as ik
from iconkit import canvas, s

WHITE = (255, 255, 255, 255)
ACCENT, DARK = ik.WALLY_ACCENT, ik.WALLY_DARK


def save(img, name, size):
    ik.save(img, OUT, ((name, size),))


def friends():
    img, d = canvas(64)
    d.ellipse([s(22), s(8), s(42), s(28)], fill=WHITE)                        # head
    d.pieslice([s(12), s(30), s(52), s(70)], 180, 360, fill=WHITE)            # shoulders
    save(img, "Friends.tga", 64)


def channels():
    img, d = canvas(64)
    d.rectangle([s(10), s(24), s(22), s(40)], fill=WHITE)                    # speaker box
    d.polygon([(s(22), s(24)), (s(36), s(12)), (s(36), s(52)), (s(22), s(40))], fill=WHITE)
    for r in (10, 18):                                                         # sound waves
        d.arc([s(36 - r), s(32 - r), s(36 + r), s(32 + r)], -45, 45, fill=WHITE, width=s(4))
    save(img, "Channels.tga", 64)


def menu():
    img, d = canvas(64)
    d.rounded_rectangle([s(8), s(12), s(56), s(44)], radius=s(9), fill=WHITE)   # bubble
    d.polygon([(s(18), s(42)), (s(30), s(42)), (s(16), s(56))], fill=WHITE)      # tail
    for x in (22, 32, 42):                                                     # three dots, cut out
        d.ellipse([s(x - 3), s(25), s(x + 3), s(31)], fill=(0, 0, 0, 0))
    save(img, "Menu.tga", 64)


def corners(name, outward):
    img, d = canvas(64)
    w, a = s(5), s(14)
    for cx, cy, dx, dy in ((10, 10, 1, 1), (54, 10, -1, 1), (10, 54, 1, -1), (54, 54, -1, -1)):
        x, y = s(cx), s(cy)
        if not outward:  # the corner turned in: at the same spot, pointing to the middle
            x, y = s(cx + dx * 14), s(cy + dy * 14)
            dx, dy = -dx, -dy
        d.line([(x, y), (x + dx * a, y)], fill=WHITE, width=w)
        d.line([(x, y), (x, y + dy * a)], fill=WHITE, width=w)
        d.rectangle([x - w // 2, y - w // 2, x + w // 2, y + w // 2], fill=WHITE)
    save(img, name, 64)


def bottom():
    img, d = canvas(64)
    d.line([(s(14), s(22)), (s(32), s(40)), (s(50), s(22))], fill=WHITE, width=s(6), joint="curve")
    d.line([(s(14), s(50)), (s(50), s(50))], fill=WHITE, width=s(5))
    save(img, "Bottom.tga", 64)


def logo():
    """A conversation: a message (a dark bubble with lines of text, tail down left) answered by a
    teal bubble with three typing dots (tail down right), overlapping it."""
    img, d = canvas(128)
    ik.wally_badge(d)
    panel = (28, 33, 42, 255)
    text = (237, 240, 245, 255)
    # the message
    d.rounded_rectangle([s(18), s(22), s(84), s(66)], radius=s(11), fill=panel, outline=ACCENT, width=s(3))
    d.polygon([(s(28), s(64)), (s(42), s(64)), (s(24), s(80))], fill=panel)
    d.line([(s(28), s(64)), (s(24), s(80)), (s(42), s(64))], fill=ACCENT, width=s(3), joint="curve")
    d.rounded_rectangle([s(28), s(33), s(72), s(39)], radius=s(3), fill=text)
    d.rounded_rectangle([s(28), s(45), s(62), s(50)], radius=s(2), fill=(237, 240, 245, 150))
    # the reply, in front: a dark gap round it so the two bubbles read apart
    d.rounded_rectangle([s(48), s(52), s(112), s(96)], radius=s(13), fill=DARK)
    d.rounded_rectangle([s(52), s(56), s(108), s(92)], radius=s(11), fill=ACCENT)
    d.polygon([(s(88), s(90)), (s(102), s(90)), (s(106), s(106))], fill=ACCENT)
    for x in (66, 80, 94):
        d.ellipse([s(x - 4.5), s(69.5), s(x + 4.5), s(78.5)], fill=DARK)
    save(img, "Icon.tga", 128)
    save(img, "Logo.png", 512)  # for CurseForge


if __name__ == "__main__":
    OUT = ik.out_dir("WallyChat", use_argv=False)
    friends()
    channels()
    menu()
    corners("FullScreen.tga", True)
    corners("Exit.tga", False)
    bottom()
    logo()
    print("icons written to", OUT)
