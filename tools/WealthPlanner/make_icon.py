"""Draws Wealth Planner's three icons, each on a dark round badge with a gold rim
(the same badge style as StatLedger's and Bandolier's):

  Icon        the addon: growing stacks of gold coins under a rising green chart line
  JobsIcon    the Jobs Board: a cork board with pinned job notes and a map pin
  InvestIcon  the Invest tab: a pie chart with a gold slice lifted out, and a coin

Usage: python make_icon.py <output dir>
Writes <name>.tga (128x128, 32-bit, used in game) for each icon, and Logo.png
(512x512, the addon icon, for CurseForge and other listings)."""
import os, sys
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "_shared"))
import iconkit as ik
from iconkit import C, S, circle

GREEN, GREEN_DARK = (70, 210, 100), (20, 70, 30)
GOLD, GOLD_EDGE, GOLD_LIGHT = (232, 184, 70), (126, 84, 22), (255, 226, 140)


def coin(d, cx, y, w=150, h=54):
    d.ellipse([cx - w / 2, y - h / 2 + 14, cx + w / 2, y + h / 2 + 14], fill=GOLD_EDGE)
    d.rectangle([cx - w / 2, y, cx + w / 2, y + 14], fill=GOLD_EDGE)
    d.ellipse([cx - w / 2, y - h / 2, cx + w / 2, y + h / 2], fill=GOLD, outline=(150, 102, 30), width=6)
    d.ellipse([cx - w / 2 + 26, y - h / 2 + 10, cx + w / 2 - 26, y + h / 2 - 10], outline=GOLD_LIGHT, width=5)


def paint_addon(layer):
    d = ImageDraw.Draw(layer)
    for cx, count in ((300, 3), (512, 5), (724, 8)):
        for i in range(count):
            coin(d, cx, 800 - i * 44)
    pts = [(200, 560), (330, 450), (430, 500), (560, 340), (650, 380), (790, 220)]
    d.line([(x + 8, y + 12) for x, y in pts], fill=(0, 0, 0, 140), width=46, joint="curve")
    d.line(pts, fill=GREEN, width=40, joint="curve")
    for x, y in pts[1:-1]:
        circle(d, 20, fill=GREEN, cx=x, cy=y)
    hx, hy = pts[-1]
    head = [(hx + 40, hy - 40), (hx - 70, hy - 20), (hx + 20, hy + 70)]
    d.polygon([(x + 8, y + 12) for x, y in head], fill=(0, 0, 0, 140))
    d.polygon(head, fill=GREEN, outline=GREEN_DARK, width=8)
    shine = ik.layer()
    ImageDraw.Draw(shine).line([(x, y - 10) for x, y in pts[:-1]], fill=(190, 255, 200, 120), width=10, joint="curve")
    return Image.alpha_composite(layer, shine)


def paint_jobs(layer):
    d = ImageDraw.Draw(layer)
    # Cork board in a wooden frame
    d.rounded_rectangle([210, 250, 814, 790], radius=26, fill=(0, 0, 0, 130))
    d.rounded_rectangle([196, 232, 828, 772], radius=26, fill=(110, 68, 30))
    d.rounded_rectangle([226, 262, 798, 742], radius=14, fill=(196, 150, 92))
    for x, y in ((300, 330), (520, 300), (700, 420), (380, 600), (640, 650), (460, 470)):
        circle(d, 6, fill=(170, 124, 70), cx=x, cy=y)
    # Pinned notes, each with "text" lines and a coloured pin
    notes = [((256, 300, 486, 500), -4, (232, 64, 64)), ((520, 290, 770, 470), 3, (64, 140, 232)),
             ((300, 530, 530, 720), 2, (70, 190, 90))]
    for (x0, y0, x1, y1), tilt, pin in notes:
        note = ik.layer()
        dn = ImageDraw.Draw(note)
        dn.rectangle([x0 + 8, y0 + 10, x1 + 8, y1 + 10], fill=(0, 0, 0, 90))
        dn.rectangle([x0, y0, x1, y1], fill=(246, 240, 222))
        for k in range(4):
            ly = y0 + 60 + k * 32
            dn.line([(x0 + 26, ly), (x1 - 26 - (k % 2) * 50, ly)], fill=(120, 120, 130), width=10)
        note = note.rotate(tilt, center=((x0 + x1) / 2, (y0 + y1) / 2), resample=Image.BICUBIC)
        layer = Image.alpha_composite(layer, note)
        d = ImageDraw.Draw(layer)
        circle(d, 20, fill=(0, 0, 0, 120), cx=(x0 + x1) / 2 + 4, cy=y0 + 8)
        circle(d, 18, fill=pin, cx=(x0 + x1) / 2, cy=y0 + 2)
        circle(d, 6, fill=(255, 255, 255, 200), cx=(x0 + x1) / 2 - 6, cy=y0 - 4)
    # Gold map pin on the right note: "this is where the job is"
    px, py = 660, 620
    d.ellipse([px - 84, py - 190, px + 84, py - 22], fill=(0, 0, 0, 120))
    d.polygon([(px - 76, py - 100), (px + 76, py - 100), (px, py + 40)], fill=GOLD_EDGE)
    circle(d, 84, fill=GOLD, outline=GOLD_EDGE, width=8, cx=px, cy=py - 112)
    circle(d, 34, fill=(24, 28, 44), cx=px, cy=py - 112)
    return layer


def paint_invest(layer):
    d = ImageDraw.Draw(layer)
    cx, cy, r = 470, 540, 300
    # shadow, then the pie: green (invested) and blue-grey (cash), with a gold slice lifted out
    d.pieslice([cx - r + 10, cy - r + 14, cx + r + 10, cy + r + 14], 0, 360, fill=(0, 0, 0, 130))
    d.pieslice([cx - r, cy - r, cx + r, cy + r], -40, 170, fill=(84, 112, 150), outline=(30, 40, 60), width=8)
    d.pieslice([cx - r, cy - r, cx + r, cy + r], 170, 250, fill=GREEN, outline=GREEN_DARK, width=8)
    ox, oy = 40, -50
    d.pieslice([cx - r + ox, cy - r + oy, cx + r + ox, cy + r + oy], 250, 320, fill=GOLD, outline=GOLD_EDGE, width=8)
    shine = ik.layer()
    ImageDraw.Draw(shine).arc([cx - r + 40, cy - r + 40, cx + r - 40, cy + r - 40], 190, 240, fill=(190, 255, 200, 130), width=14)
    layer = Image.alpha_composite(layer, shine)
    d = ImageDraw.Draw(layer)
    # A coin leaning on the pie, bottom right
    ccx, ccy = 730, 720
    circle(d, 120, fill=(0, 0, 0, 130), cx=ccx + 8, cy=ccy + 12)
    circle(d, 120, fill=GOLD_EDGE, cx=ccx, cy=ccy + 10)
    circle(d, 116, fill=GOLD, outline=(150, 102, 30), width=8, cx=ccx, cy=ccy)
    circle(d, 80, outline=GOLD_LIGHT, width=8, cx=ccx, cy=ccy)
    d.polygon([(ccx, ccy - 52), (ccx + 44, ccy + 4), (ccx + 16, ccy + 4), (ccx + 16, ccy + 50),
               (ccx - 16, ccy + 50), (ccx - 16, ccy + 4), (ccx - 44, ccy + 4)], fill=(150, 102, 30))
    return layer


GLOW = [C - 330, C - 260, C + 330, C + 340]
out_dir = ik.out_dir("WealthPlanner")
for name, paint, inner, glow in (
    ("Icon", paint_addon, (24, 28, 44), (230, 180, 60, 60)),
    ("JobsIcon", paint_jobs, (34, 30, 28), (230, 160, 80, 50)),
    ("InvestIcon", paint_invest, (20, 32, 40), (80, 200, 140, 60)),
):
    img = ik.badge(paint, inner, (GLOW, glow, 60))
    ik.save(img, out_dir, ((name + ".tga", 128), (name + ".png" if name != "Icon" else "Logo.png", 512)))
    print("saved", name)
