"""Draws SimplePanel's icon: an info bar across the top (skill bar, gold coin, clock, quest marker)
with a tooltip hanging from the coin, holding a small chart. Wally's palette.

Drawn at 1024 px and scaled down. Run: python make_icon.py <folder>  (writes Icon.tga, Icon.png and Logo.png)
"""
import os
import sys
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "_shared"))
import iconkit as ik
from iconkit import S

BASE = (9, 11, 15, 255)
SIDE = (16, 22, 29, 255)
WELL = (24, 33, 42, 255)
BORDER = (41, 61, 74, 255)
ACC = (84, 235, 199, 255)
ACC_DIM = (84, 235, 199, 70)
YEL = (255, 209, 77, 255)
YEL_DARK = (196, 140, 30, 255)
MUT = (133, 163, 179, 255)
GREEN = (89, 242, 140, 255)


img, d = ik.canvas(S, 1)
# Frame, like the sibling add-ons' icons.
d.rounded_rectangle([40, 40, S - 40, S - 40], radius=150, fill=BASE, outline=BORDER, width=24)

# The bar: a strip across the top with the accent glow line under it.
BAR = (110, 130, S - 110, 330)
d.rounded_rectangle(BAR, radius=36, fill=SIDE, outline=BORDER, width=10)
d.rectangle([140, 312, S - 140, 324], fill=ACC)
cy = (BAR[1] + BAR[3]) // 2 - 6

# Left: a skill bar, outlined, part filled.
d.rounded_rectangle([160, cy - 34, 400, cy + 34], radius=10, fill=WELL, outline=MUT, width=8)
d.rounded_rectangle([170, cy - 24, 310, cy + 24], radius=6, fill=ACC)

# Dividers between the groups.
for x in (440, 640):
    d.rectangle([x - 4, cy - 56, x + 4, cy + 56], fill=BORDER)

# Middle: a gold coin.
COIN = (540, cy)
r = 62
d.ellipse([COIN[0] - r, COIN[1] - r, COIN[0] + r, COIN[1] + r], fill=YEL_DARK)
d.ellipse([COIN[0] - r + 12, COIN[1] - r + 12, COIN[0] + r - 12, COIN[1] + r - 12], fill=YEL)
d.ellipse([COIN[0] - 22, COIN[1] - 22, COIN[0] + 22, COIN[1] + 22], fill=YEL_DARK)

# Right: a clock face, then a green quest dot.
CLK = (740, cy)
r = 58
d.ellipse([CLK[0] - r, CLK[1] - r, CLK[0] + r, CLK[1] + r], outline=MUT, width=14)
d.line([CLK, (CLK[0], CLK[1] - 38)], fill=MUT, width=14)
d.line([CLK, (CLK[0] + 30, CLK[1] + 8)], fill=MUT, width=14)
d.ellipse([CLK[0] - 10, CLK[1] - 10, CLK[0] + 10, CLK[1] + 10], fill=MUT)
d.ellipse([850, cy - 34, 918, cy + 34], fill=GREEN)

# The tooltip hanging from the coin: a notch, a panel, two text lines and a chart.
TIP = (210, 430, S - 210, S - 130)
d.polygon([(COIN[0] - 44, TIP[1] + 6), (COIN[0] + 44, TIP[1] + 6), (COIN[0], TIP[1] - 52)], fill=BORDER)
d.rounded_rectangle(TIP, radius=44, fill=SIDE, outline=BORDER, width=12)
d.polygon([(COIN[0] - 30, TIP[1] + 14), (COIN[0] + 30, TIP[1] + 14), (COIN[0], TIP[1] - 22)], fill=SIDE)
d.rounded_rectangle([TIP[0] + 50, TIP[1] + 60, TIP[0] + 330, TIP[1] + 100], radius=20, fill=MUT)
d.rounded_rectangle([TIP[0] + 380, TIP[1] + 60, TIP[2] - 50, TIP[1] + 100], radius=20, fill=YEL)
d.rounded_rectangle([TIP[0] + 50, TIP[1] + 135, TIP[0] + 250, TIP[1] + 170], radius=17, fill=BORDER)

x0, x1 = TIP[0] + 60, TIP[2] - 60
base = TIP[3] - 60
ys = [0.25, 0.45, 0.35, 0.7, 0.55, 0.9]
pts = [(x0 + (x1 - x0) * i / (len(ys) - 1), base - 190 * v) for i, v in enumerate(ys)]
over, od = ik.canvas(S, 1)
od.polygon(pts + [(x1, base), (x0, base)], fill=ACC_DIM)
img = Image.alpha_composite(img, over)
d = ImageDraw.Draw(img)
d.line(pts, fill=ACC, width=30, joint="curve")
for p in pts:
    d.ellipse([p[0] - 22, p[1] - 22, p[0] + 22, p[1] + 22], fill=ACC)

ik.save(img, ik.out_dir("SimplePanel"), (("Icon.tga", 128), ("Icon.png", 128), ("Logo.png", 512)))
