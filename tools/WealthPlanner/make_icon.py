"""Draws Wealth Planner's three icons, each on a dark round badge with a gold rim
(the same badge style as StatLedger's and Bandolier's):

  Icon        the addon: growing stacks of gold coins under a rising green chart line
  JobsIcon    the Jobs Board: a cork board with pinned job notes and a map pin
  InvestIcon  the Invest tab: a pie chart with a gold slice lifted out, and a coin

Usage: python make_icon.py <output dir>
Writes <name>.tga (128x128, 32-bit, used in game) for each icon, and Logo.png
(512x512, the addon icon, for CurseForge and other listings)."""
import os, sys
from PIL import Image, ImageDraw, ImageFilter

S = 1024                      # supersampled canvas, downscaled at the end
C = S / 2
GREEN, GREEN_DARK = (70, 210, 100), (20, 70, 30)
GOLD, GOLD_EDGE, GOLD_LIGHT = (232, 184, 70), (126, 84, 22), (255, 226, 140)


def circle(d, r, fill=None, outline=None, width=0, cx=C, cy=C):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill, outline=outline, width=width)


def badge(paint, inner=(24, 28, 44), glow_color=(230, 180, 60, 60)):
    """A gold-rimmed badge; paint(draw, layer) draws the content, clipped to the badge."""
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse([C - 470, C - 455, C + 470, C + 485], fill=(0, 0, 0, 170))
    img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(18)))
    d = ImageDraw.Draw(img)
    circle(d, 480, fill=(120, 82, 24))
    circle(d, 462, fill=(214, 166, 64))
    circle(d, 446, fill=(92, 60, 18))
    circle(d, 432, fill=inner)

    inside = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([C - 330, C - 260, C + 330, C + 340], fill=glow_color)
    inside = Image.alpha_composite(inside, glow.filter(ImageFilter.GaussianBlur(60)))
    inside = paint(inside)

    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).ellipse([C - 432, C - 432, C + 432, C + 432], fill=255)
    clipped = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    clipped.paste(inside, (0, 0), Image.composite(inside.split()[3], Image.new("L", (S, S), 0), mask))
    img = Image.alpha_composite(img, clipped)
    ring = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(ring).ellipse([C - 440, C - 440, C + 440, C + 440], outline=(0, 0, 0, 140), width=22)
    return Image.alpha_composite(img, ring.filter(ImageFilter.GaussianBlur(8)))


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
    shine = Image.new("RGBA", (S, S), (0, 0, 0, 0))
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
        note = Image.new("RGBA", (S, S), (0, 0, 0, 0))
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
    shine = Image.new("RGBA", (S, S), (0, 0, 0, 0))
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


out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "addons", "WealthPlanner", "Media")
os.makedirs(out_dir, exist_ok=True)
for name, paint, inner, glow in (
    ("Icon", paint_addon, (24, 28, 44), (230, 180, 60, 60)),
    ("JobsIcon", paint_jobs, (34, 30, 28), (230, 160, 80, 50)),
    ("InvestIcon", paint_invest, (20, 32, 40), (80, 200, 140, 60)),
):
    img = badge(paint, inner, glow)
    img.resize((128, 128), Image.LANCZOS).save(os.path.join(out_dir, name + ".tga"))
    img.resize((512, 512), Image.LANCZOS).save(os.path.join(out_dir, name + ".png" if name != "Icon" else "Logo.png"))
    print("saved", name)
