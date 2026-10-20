"""Draws WallyChat's icons: white glyphs on transparent squares (the addon tints them, monochrome at
rest and full colour under the mouse, the suite's ghost buttons), and its logo.

    python -I tools/WallyChat/make_icons.py

Writes into addons/WallyChat/Media:
  Friends.tga, Channels.tga, Menu.tga, FullScreen.tga, Exit.tga, Bottom.tga   64x64, the toolbar
  Icon.tga                                                                     128x128, the addon list
Each is drawn at 4x and scaled down, for smooth edges.
"""
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(os.path.dirname(HERE)), "addons", "WallyChat", "Media")
SS = 4
WHITE = (255, 255, 255, 255)
ACCENT = (64, 196, 205, 255)
DARK = (16, 19, 25, 255)


def canvas(size):
    img = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def save(img, name, size):
    img.resize((size, size), Image.LANCZOS).save(os.path.join(OUT, name))


def s(v):
    """64-unit design coordinates to the supersampled canvas."""
    return v * SS


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
    img, d = canvas(128)
    d.rounded_rectangle([s(6), s(6), s(122), s(122)], radius=s(24), fill=DARK, outline=ACCENT, width=s(4))
    d.rounded_rectangle([s(26), s(32), s(102), s(82)], radius=s(14), fill=ACCENT)
    d.polygon([(s(40), s(80)), (s(60), s(80)), (s(36), s(100))], fill=ACCENT)
    for x in (46, 64, 82):
        d.ellipse([s(x - 5), s(52), s(x + 5), s(62)], fill=DARK)
    save(img, "Icon.tga", 128)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    friends()
    channels()
    menu()
    corners("FullScreen.tga", True)
    corners("Exit.tga", False)
    bottom()
    logo()
    print("icons written to", OUT)
