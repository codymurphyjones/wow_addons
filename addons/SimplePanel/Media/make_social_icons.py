"""Draws the Friends and Guild icons SimplePanel shows on the bar.

Both are white on transparent so the bar can tint them (Friends follows the accent color, Guild the
green). Drawn at 256 px and scaled down for clean edges. Run: python make_social_icons.py
"""
import os
from PIL import Image, ImageDraw

S = 256
WHITE = (255, 255, 255, 255)
SOFT = (255, 255, 255, 150)
out = os.path.dirname(os.path.abspath(__file__))


def person(d, cx, top, scale, fill):
    """A head and rounded shoulders, centered on cx."""
    r = 30 * scale
    d.ellipse((cx - r, top, cx + r, top + 2 * r), fill=fill)
    w, h = 62 * scale, 70 * scale
    body_top = top + 2 * r + 8 * scale
    d.rounded_rectangle((cx - w, body_top, cx + w, body_top + h + 40 * scale), radius=int(48 * scale), fill=fill)


def friends():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # The friend behind, a little smaller and softer, then you in front.
    person(d, 162, 46, 0.86, SOFT)
    person(d, 100, 62, 1.0, WHITE)
    # Cut the canvas so the bodies end in a straight line, like a bust.
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rectangle((0, 0, S, 226), fill=255)
    img.putalpha(Image.composite(img.getchannel("A"), Image.new("L", (S, S), 0), mask))
    return img


def guild():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # Pole with a round finial.
    d.rounded_rectangle((52, 34, 70, 232), radius=9, fill=WHITE)
    d.ellipse((44, 18, 78, 52), fill=WHITE)
    # A swallowtail pennant flying from the pole.
    d.polygon([(70, 52), (222, 52), (190, 104), (222, 156), (70, 156)], fill=WHITE)
    # A notch of emblem: a small diamond cut out of the banner.
    d.polygon([(136, 82), (160, 104), (136, 126), (112, 104)], fill=(0, 0, 0, 0))
    return img


for name, draw in (("Friends", friends), ("Guild", guild)):
    draw().resize((64, 64), Image.LANCZOS).save(os.path.join(out, name + ".tga"))
    print("wrote", name + ".tga")
