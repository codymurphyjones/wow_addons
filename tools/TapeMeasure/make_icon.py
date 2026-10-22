"""Draws the Tape Measure logo: a teal tape-measure case with yellow tape pulled
out across the badge, ticks and all, and a green "upgrade" arrow above the tape,
on a dark round badge with a gold rim (the same badge style as StatLedger's).

Usage: python make_icon.py <output dir>
Writes <output dir>/Icon.tga (128x128, 32-bit, used in game) and
<output dir>/Logo.png (512x512, for CurseForge and other listings)."""
import os, sys
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "_shared"))
import iconkit as ik
from iconkit import C, circle


def paint(inside):
    di = ImageDraw.Draw(inside)
    # Translucent shine goes on its own layer so it blends instead of replacing colour.
    shine = ik.layer()
    ds = ImageDraw.Draw(shine)

    CX, CY, R = 390, 450, 250     # the case

    # The tape: a yellow strip pulled out from under the case to a metal end hook.
    # Drawn first so the case covers its start and it seems to come out of it.
    TY, TH = 640, 150              # tape centre line and height
    TX0, TX1 = CX, 830
    di.rectangle([TX0, TY - TH / 2 + 12, TX1, TY + TH / 2 + 12], fill=(0, 0, 0, 130))
    di.rectangle([TX0, TY - TH / 2, TX1, TY + TH / 2], fill=(242, 196, 46))
    di.rectangle([TX0, TY + TH / 2 - 16, TX1, TY + TH / 2], fill=(196, 146, 24))
    ds.rectangle([CX + R - 20, TY - TH / 2 + 10, TX1, TY - TH / 2 + 30], fill=(255, 240, 160, 170))
    # Ticks: short every 36px, long every 3rd, hanging from the top edge of the tape.
    for i, x in enumerate(range(CX + R + 10, TX1 - 10, 36)):
        long = i % 3 == 0
        di.rectangle([x - 6, TY - TH / 2, x + 6, TY - TH / 2 + (78 if long else 42)], fill=(40, 30, 16))
    # Metal end hook: a plate across the tape end with a lip bent down below it.
    di.rectangle([TX1 - 6, TY - TH / 2 - 24, TX1 + 34, TY + TH / 2 + 50], fill=(170, 176, 188), outline=(52, 54, 62), width=8)
    ds.rectangle([TX1 + 2, TY - TH / 2 - 16, TX1 + 12, TY + TH / 2 + 40], fill=(255, 255, 255, 120))

    # The case: a teal round body with a dark rim, a metal hub and a stop button.
    circle(di, R + 14, fill=(0, 0, 0, 130), cx=CX + 10, cy=CY + 14)
    circle(di, R, fill=(16, 70, 62), cx=CX, cy=CY)
    circle(di, R - 22, fill=(44, 178, 150), cx=CX, cy=CY)
    circle(di, R - 70, fill=(32, 140, 120), cx=CX, cy=CY)
    ds.ellipse([CX - R + 70, CY - R + 50, CX - 10, CY - 70], fill=(170, 255, 230, 90))
    # Hub
    circle(di, 92, fill=(20, 24, 30), cx=CX, cy=CY)
    circle(di, 78, fill=(196, 202, 214), cx=CX, cy=CY)
    circle(di, 26, fill=(110, 116, 128), cx=CX, cy=CY)
    circle(di, 18, fill=(240, 244, 250), cx=CX - 26, cy=CY - 26)
    # Stop button on top of the case
    di.rounded_rectangle([CX - 46, CY - R - 40, CX + 46, CY - R + 26], radius=18, fill=(214, 60, 52), outline=(70, 18, 16), width=8)

    # Green "upgrade" arrow, above the tape on the right
    ik.upgrade_arrow(di, ds, 770, 200, 500)
    inside = Image.alpha_composite(inside, shine)
    return inside


img = ik.badge(paint, inner=(24, 28, 44), glow=([C - 360, C - 330, C + 300, C + 330], (84, 235, 200, 60), 70))
out_dir = ik.out_dir("TapeMeasure")
ik.save(img, out_dir)
print("saved", os.path.join(out_dir, "Icon.tga"), "and Logo.png")
