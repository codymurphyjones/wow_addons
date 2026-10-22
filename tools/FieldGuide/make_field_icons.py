"""Draws the field's icons (UI.lua): sixteen round markers that stand in for words on the field.

Each icon is a dark disc with a colored rim and one bold symbol, outlined in black so it reads over
any ground (sand, snow, grass). Drawn at 512 px and scaled down.

    pickup    !          a quest to pick up (the game's own yellow mark)
    turnin    ?          a quest to turn in
    objective target     do the quest's objectives
    loot      bag        an item that drops and starts a quest
    grind     swords     kill what's around you until a level
    travel    footprints go to another zone
    dungeon   gate       run a dungeon
    missed    back arrow a quest you missed earlier
    exit      arrow out  the quest that leads to the next zone
    locked    padlock    needs a higher level
    done      check      done it (throw up)
    skip      skip       skip (throw down)
    pause     pause      let the arrow go (throw sideways)
    play      play       the arrow follows the guide again
    leveling  up arrow   back to the leveling guide
    xp        XP         the experience a quest pays

Usage: python make_field_icons.py [output dir]
Writes <output dir>/<name>.tga (64x64, 32-bit) for each icon (default addons/FieldGuide/Media/Field)
and tools/FieldGuide/field_icons_preview.png (every icon on light and dark ground, to check them)."""
import os, sys, math
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, "addons", "FieldGuide", "Media", "Field")
S, C = 512, 256

GOLD = (255, 209, 0)
WHITE = (245, 245, 240)
GREEN = (143, 209, 106)
BLUE = (102, 187, 255)
PURPLE = (199, 140, 255)
AMBER = (240, 160, 70)
TAN = (217, 160, 102)
RED = (235, 90, 80)
GRAY = (190, 195, 190)


def font(size):
    for name in ("arialbd.ttf", "C:/Windows/Fonts/arialbd.ttf", "DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def blank():
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))


def icon(rim, draw):
    """A dark disc with a rim, and the symbol draw(d) paints (on its own layer), outlined in black."""
    base = blank()
    d = ImageDraw.Draw(base)
    d.ellipse([12, 12, S - 12, S - 12], fill=(0, 0, 0, 120))                     # soft edge
    base = base.filter(ImageFilter.GaussianBlur(6))
    d = ImageDraw.Draw(base)
    d.ellipse([22, 22, S - 22, S - 22], fill=(18, 20, 18, 235), outline=rim + (255,), width=22)
    sym = blank()
    draw(ImageDraw.Draw(sym))
    # Black outline: the symbol's shape, grown, under it.
    alpha = sym.split()[3].filter(ImageFilter.MaxFilter(25))
    outline = Image.new("RGBA", (S, S), (0, 0, 0, 255))
    outline.putalpha(alpha)
    out = Image.alpha_composite(base, outline)
    return Image.alpha_composite(out, sym)


def text(d, s, col, size, dy=0):
    f = font(size)
    box = d.textbbox((0, 0), s, font=f)
    w, h = box[2] - box[0], box[3] - box[1]
    d.text((C - w / 2 - box[0], C - h / 2 - box[1] + dy), s, font=f, fill=col + (255,))


def arrow_head(d, tip, angle, size, col):
    a = math.radians(angle)
    left = (tip[0] - size * math.cos(a - 0.6), tip[1] - size * math.sin(a - 0.6))
    right = (tip[0] - size * math.cos(a + 0.6), tip[1] - size * math.sin(a + 0.6))
    d.polygon([tip, left, right], fill=col + (255,))


def pickup(d): text(d, "!", GOLD, 330, 6)
def turnin(d): text(d, "?", GOLD, 320, 4)


def objective(d):
    d.ellipse([C - 130, C - 130, C + 130, C + 130], outline=WHITE + (255,), width=34)
    for x0, y0, x1, y1 in ((C, 70, C, 170), (C, S - 170, C, S - 70), (70, C, 170, C), (S - 170, C, S - 70, C)):
        d.line([x0, y0, x1, y1], fill=WHITE + (255,), width=34)
    d.ellipse([C - 34, C - 34, C + 34, C + 34], fill=RED + (255,))


def loot(d):
    d.ellipse([C - 140, C - 60, C + 140, C + 170], fill=TAN + (255,))            # the sack
    d.polygon([(C - 60, C - 50), (C + 60, C - 50), (C + 90, C - 140), (C - 90, C - 140)], fill=TAN + (255,))
    d.rectangle([C - 75, C - 75, C + 75, C - 45], fill=(120, 72, 30, 255))     # the tie
    text(d, "$", (90, 55, 20), 150, 70)


def grind(d):
    # Two crossed swords: blade with a point, crossguard, grip, pommel, drawn along each diagonal.
    for sgn in (1, -1):
        ux, uy = sgn / math.sqrt(2), -1 / math.sqrt(2)          # along the blade, toward its point
        px, py = -uy, ux                                         # across it
        def at(t, w):
            return (C + ux * t + px * w, C + uy * t + py * w)
        d.polygon([at(-60, -22), at(140, -22), at(185, 0), at(140, 22), at(-60, 22)], fill=WHITE + (255,))
        d.polygon([at(-80, -70), at(-58, -70), at(-58, 70), at(-80, 70)], fill=AMBER + (255,))
        d.polygon([at(-150, -16), at(-80, -16), at(-80, 16), at(-150, 16)], fill=TAN + (255,))
        cx, cy = at(-168, 0)
        d.ellipse([cx - 24, cy - 24, cx + 24, cy + 24], fill=AMBER + (255,))


def travel(d):
    # Two footprints walking up.
    for cx, cy, tilt in ((C - 70, C + 60, -10), (C + 70, C - 50, 10)):
        d.ellipse([cx - 52, cy - 85, cx + 52, cy + 60], fill=BLUE + (255,))
        d.ellipse([cx - 40, cy + 75, cx + 40, cy + 140], fill=BLUE + (255,))


def dungeon(d):
    # A stone gate with a swirling portal.
    d.rectangle([C - 150, C - 40, C + 150, C + 170], fill=GRAY + (255,))
    d.pieslice([C - 150, C - 190, C + 150, C + 110], 180, 360, fill=GRAY + (255,))
    d.rectangle([C - 95, C - 30, C + 95, C + 170], fill=PURPLE + (255,))
    d.pieslice([C - 95, C - 135, C + 95, C + 55], 180, 360, fill=PURPLE + (255,))
    d.arc([C - 55, C - 50, C + 55, C + 60], 30, 300, fill=(250, 235, 255, 255), width=18)


def missed(d):
    # A curved arrow turning back.
    d.arc([C - 140, C - 140, C + 140, C + 140], 200, 520 - 360 + 360 - 30, fill=AMBER + (255,), width=46)
    a = math.radians(200)
    tip = (C + 140 * math.cos(a) - 10, C + 140 * math.sin(a) + 70)
    arrow_head(d, tip, 100, 110, AMBER)


def exit_(d):
    # An arrow leaving through a doorway.
    d.rectangle([C - 150, C - 150, C - 30, C + 150], outline=GRAY + (255,), width=30)
    d.line([C - 80, C, C + 110, C], fill=BLUE + (255,), width=48)
    arrow_head(d, (C + 175, C), 0, 120, BLUE)


def locked(d):
    d.arc([C - 85, C - 175, C + 85, C], 180, 360, fill=GRAY + (255,), width=40)
    d.line([C - 85, C - 90, C - 85, C - 20], fill=GRAY + (255,), width=40)
    d.line([C + 85, C - 90, C + 85, C - 20], fill=GRAY + (255,), width=40)
    d.rounded_rectangle([C - 130, C - 30, C + 130, C + 160], radius=24, fill=RED + (255,))
    d.ellipse([C - 22, C + 30, C + 22, C + 74], fill=(40, 20, 20, 255))
    d.rectangle([C - 10, C + 60, C + 10, C + 115], fill=(40, 20, 20, 255))


def done(d):
    d.line([(C - 140, C + 10), (C - 40, C + 110), (C + 150, C - 120)], fill=GREEN + (255,), width=64, joint="curve")


def skip(d):
    for x in (C - 150, C - 30):
        d.polygon([(x, C - 120), (x + 130, C), (x, C + 120)], fill=WHITE + (255,))
    d.rectangle([C + 110, C - 120, C + 150, C + 120], fill=WHITE + (255,))


def pause(d):
    d.rectangle([C - 100, C - 130, C - 30, C + 130], fill=AMBER + (255,))
    d.rectangle([C + 30, C - 130, C + 100, C + 130], fill=AMBER + (255,))


def play(d):
    d.polygon([(C - 85, C - 140), (C + 140, C), (C - 85, C + 140)], fill=GREEN + (255,))


def leveling(d):
    d.line([C, C + 150, C, C - 40], fill=GREEN + (255,), width=60)
    arrow_head(d, (C, C - 160), -90, 170, GREEN)


def xp(d): text(d, "XP", PURPLE, 190, 4)


ICONS = [
    ("pickup", GOLD, pickup), ("turnin", GOLD, turnin), ("objective", WHITE, objective), ("loot", TAN, loot),
    ("grind", AMBER, grind), ("travel", BLUE, travel), ("dungeon", PURPLE, dungeon), ("missed", AMBER, missed),
    ("exit", BLUE, exit_), ("locked", RED, locked), ("done", GREEN, done), ("skip", WHITE, skip),
    ("pause", AMBER, pause), ("play", GREEN, play), ("leveling", GREEN, leveling), ("xp", PURPLE, xp),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    images = []
    for name, rim, draw in ICONS:
        img = icon(rim, draw)
        img.resize((64, 64), Image.LANCZOS).save(os.path.join(OUT, name + ".tga"))
        images.append((name, img))
    # The preview: each icon at game size (32 px) and big, on sand and on night.
    cell = 120
    sheet = Image.new("RGBA", (cell * 8, cell * 4), (0, 0, 0, 255))
    d = ImageDraw.Draw(sheet)
    small = font(13)
    for i, (name, img) in enumerate(images):
        col, row = i % 8, (i // 8) * 2
        for r, ground in ((row, (196, 120, 70, 255)), (row + 1, (30, 34, 44, 255))):
            x, y = col * cell, r * cell
            d.rectangle([x, y, x + cell, y + cell], fill=ground)
            sheet.alpha_composite(img.resize((64, 64), Image.LANCZOS), (x + 8, y + 8))
            sheet.alpha_composite(img.resize((24, 24), Image.LANCZOS), (x + 82, y + 28))
            d.text((x + 8, y + 96), name, font=small, fill=(255, 255, 255, 255))
    preview = os.path.join(HERE, "field_icons_preview.png")
    sheet.convert("RGB").save(preview)
    print("wrote", len(images), "icons to", OUT, "and", preview)


if __name__ == "__main__":
    main()
