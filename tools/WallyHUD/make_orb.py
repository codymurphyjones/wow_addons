"""Draws the art for WallyHUD's orb (Orb.lua): a Diablo-inspired glass sphere of liquid in a dark
iron bezel, split by an ornate bar with a gem.

    python tools/WallyHUD/make_orb.py [--preview <dir>]     (needs Pillow and numpy: not -I)

Writes into addons/WallyHUD/Media/Orb (all 32-bit TGA, power-of-two sizes, white or grey where the
game tints them):
  Frame.tga     256  the iron bezel with gold trim and rivets (the orb's outer ring)
  Mask.tga      256  the sphere's inside (a white disc), the mask for the liquid and glass
  Liquid.tga    128  the liquid: grey swirls, tinted per half (status bar texture)
  Swirl.tga     128  soft wisps, turned slowly over the liquid (additive)
  Empty.tga     128  the empty part of the sphere: dark smoky glass
  Glass.tga     256  the glass: specular highlights and the inner shadow at the sphere's edge
  Divider.tga   256  the iron bar across the middle, with a gem (square, transparent around the bar)
  Surface.tga   64x16   the bright line on each liquid's surface (additive)
With --preview, also writes preview.png there: the orb put together at a few fill levels.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.dirname(TOOLS)
OUT = os.path.join(REPO, "addons", "WallyHUD", "Media", "Orb")

INNER = 0.80     # the sphere's radius, as a share of the orb's half-width (the bezel is the rest)
SS = 4           # supersampling


def big(size):
    return Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))


def down(img, size):
    return img.resize((size, size) if isinstance(size, int) else size, Image.LANCZOS)


def radial(n, cx=0.5, cy=0.5):
    """Distance from (cx, cy) in units of the half-width, for an n x n grid."""
    y, x = np.mgrid[0:n, 0:n]
    return np.hypot((x + 0.5) / n - cx, (y + 0.5) / n - cy) * 2


def angle(n):
    y, x = np.mgrid[0:n, 0:n]
    return np.arctan2((y + 0.5) / n - 0.5, (x + 0.5) / n - 0.5)


def to_img(rgb, alpha):
    a = np.clip(alpha, 0, 1)
    arr = np.dstack([np.clip(rgb[..., i], 0, 255) for i in range(3)] + [a * 255]).astype(np.uint8)
    return Image.fromarray(arr, "RGBA")


# --------------------------------------------------------------------------------------------- frame

def frame():
    n = 256 * SS
    r = radial(n)
    th = angle(n)
    ring = (r >= INNER - 0.01) & (r <= 0.97)
    rng = np.random.default_rng(3)
    grain = np.array(Image.fromarray((rng.random((n // 6, n // 6)) * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC)) / 255.0
    t = (r - INNER) / (0.97 - INNER)                       # 0 inner edge .. 1 outer edge
    bevel = np.sin(np.clip(t, 0, 1) * math.pi) ** 0.7      # rounded profile
    light = 0.5 + 0.5 * np.cos(th + math.pi * 0.75)        # light from the top-left
    k = (0.35 + 0.65 * bevel) * (0.55 + 0.45 * light) + 0.12 * (grain - 0.5)
    # Dark iron going warm bronze on the lit crest of the bevel.
    rgb = np.dstack([30 + 120 * k ** 1.4, 24 + 86 * k ** 1.5, 22 + 52 * k ** 1.7])
    img = to_img(rgb, ring.astype(float))
    d = ImageDraw.Draw(img)
    c = n / 2
    gold, gold_dark, iron = (226, 178, 84, 255), (106, 70, 22, 255), (14, 11, 12, 255)

    def circ(rr, col, w):
        R = rr * c
        d.ellipse([c - R, c - R, c + R, c + R], outline=col, width=int(w))

    circ(0.97, iron, 3 * SS)
    circ(0.945, gold_dark, 2 * SS)
    circ(INNER + 0.005, iron, 3 * SS)
    circ(INNER + 0.022, gold, 2 * SS)
    # Engraved ticks round the bezel, like a dial.
    for i in range(48):
        a = i * math.pi * 2 / 48
        r0, r1 = (INNER + 0.06) * c, (INNER + 0.09) * c
        d.line([(c + r0 * math.cos(a), c + r0 * math.sin(a)), (c + r1 * math.cos(a), c + r1 * math.sin(a))], fill=(20, 15, 14, 160), width=SS)
    # Four studs on the diagonals: a dark socket, a gold dome, a glint.
    for kq in range(4):
        a = math.pi / 4 + kq * math.pi / 2
        R = (INNER + 0.97) / 2 * c
        x, y = c + R * math.cos(a), c + R * math.sin(a)
        rr = 5.5 * SS
        d.ellipse([x - rr - 1.5 * SS, y - rr - 1.5 * SS, x + rr + 1.5 * SS, y + rr + 1.5 * SS], fill=iron)
        d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=gold)
        d.ellipse([x - rr * 0.5, y - rr * 0.6, x - rr * 0.05, y - rr * 0.2], fill=(255, 238, 180, 255))
    # The crest at the top: a pointed gold-edged iron piece with a red gem, like a demon's brow.
    cy = c - 0.885 * c
    w, h = 22 * SS, 15 * SS
    d.polygon([(c - w, cy + h * 0.55), (c - w * 0.45, cy - h * 0.15), (c, cy - h), (c + w * 0.45, cy - h * 0.15), (c + w, cy + h * 0.55),
               (c, cy + h * 0.9)], fill=iron)
    w2, h2 = w * 0.84, h * 0.8
    d.polygon([(c - w2, cy + h2 * 0.5), (c - w2 * 0.45, cy - h2 * 0.15), (c, cy - h2), (c + w2 * 0.45, cy - h2 * 0.15), (c + w2, cy + h2 * 0.5),
               (c, cy + h2 * 0.85)], fill=gold)
    w3, h3 = w * 0.62, h * 0.58
    d.polygon([(c - w3, cy + h3 * 0.5), (c, cy - h3), (c + w3, cy + h3 * 0.5), (c, cy + h3 * 0.85)], fill=(58, 40, 30, 255))
    g = 5 * SS
    d.ellipse([c - g, cy - g * 0.6, c + g, cy + g * 1.4], fill=(170, 24, 36, 255))
    d.ellipse([c - g * 0.5, cy - g * 0.3, c - g * 0.05, cy + g * 0.3], fill=(255, 150, 150, 255))
    return down(img, 256)


def mask():
    n = 256 * SS
    img = Image.new("RGBA", (n, n), (255, 255, 255, 0))
    d = ImageDraw.Draw(img)
    R = INNER * n / 2
    d.ellipse([n / 2 - R, n / 2 - R, n / 2 + R, n / 2 + R], fill=(255, 255, 255, 255))
    return down(img, 256)


# --------------------------------------------------------------------------------------------- liquid

def fractal(n, seed, octaves=5):
    rng = np.random.default_rng(seed)
    out = np.zeros((n, n))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        cells = 4 * 2 ** o
        layer = rng.random((cells, cells))
        layer = np.array(Image.fromarray((layer * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC)) / 255.0
        out += layer * amp
        total += amp
        amp *= 0.55
    return out / total


def swirl_coords(n, strength):
    y, x = np.mgrid[0:n, 0:n].astype(float)
    cx = cy = n / 2
    dx, dy = x - cx, y - cy
    r = np.hypot(dx, dy) / (n / 2)
    a = np.arctan2(dy, dx) + strength * np.exp(-r * 1.6)
    return (cx + np.cos(a) * r * n / 2) % n, (cy + np.sin(a) * r * n / 2) % n


def liquid():
    n = 128
    base = fractal(n, 11)
    xs, ys = swirl_coords(n, 3.4)
    sw = base[ys.astype(int) % n, xs.astype(int) % n]
    veins = np.abs(np.sin(sw * 11)) ** 5
    r = radial(n) / INNER                                  # 0 centre .. 1 the sphere's edge
    core = np.clip(1 - r, 0, 1) ** 1.5                     # it glows from inside
    v = 128 + 62 * sw + 38 * veins + 62 * core
    rgb = np.dstack([v, v, v])
    return to_img(rgb, np.ones((n, n))).filter(ImageFilter.GaussianBlur(0.8))


def empty():
    """The empty part of the sphere: dark smoky glass, not a void."""
    n = 128
    smoke = fractal(n, 23, octaves=4)
    xs, ys = swirl_coords(n, 2.0)
    smoke = smoke[ys.astype(int) % n, xs.astype(int) % n]
    r = radial(n) / INNER
    v = 10 + 26 * smoke ** 2 + 10 * np.clip(1 - r, 0, 1)
    rgb = np.dstack([v * 1.0, v * 0.9, v * 1.25])
    return to_img(rgb, np.full((n, n), 0.96))


def swirl():
    n = 128 * SS
    img = big(128)
    d = ImageDraw.Draw(img)
    c = n / 2
    rng = np.random.default_rng(5)
    for k in range(7):
        a0 = rng.random() * 360
        R = (0.25 + 0.6 * rng.random()) * c
        w = (2 + rng.random() * 4) * SS
        d.arc([c - R, c - R * 0.92, c + R, c + R * 0.92], a0, a0 + 70 + rng.random() * 90, fill=(255, 255, 255, 120), width=int(w))
    img = img.filter(ImageFilter.GaussianBlur(3 * SS))
    return down(img, 128)


# --------------------------------------------------------------------------------------------- glass

def glass():
    n = 256 * SS
    r = radial(n)
    inside = r <= INNER
    rr = r / INNER                                         # 0 centre .. 1 the sphere's edge
    # Inner shadow: the sphere darkens towards its edge (it's round), more at the bottom.
    y = np.mgrid[0:n, 0:n][0] / n
    shade = np.clip((rr - 0.55) / 0.45, 0, 1) ** 2 * (0.55 + 0.35 * y)
    alpha = np.where(inside, shade * 0.85, 0)
    rgb = np.zeros((n, n, 3))
    img = to_img(rgb, alpha)
    # Highlights: a soft curved crescent along the top-left of the glass, a small elongated glint,
    # and a faint bounce of light at the bottom.
    hl = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(hl)
    c = n / 2
    R = INNER * c
    d.ellipse([c - R * 0.92, c - R * 0.94, c + R * 0.70, c + R * 0.40], fill=(255, 255, 255, 95))
    d.ellipse([c - R * 0.80, c - R * 0.78, c + R * 0.86, c + R * 0.62], fill=(0, 0, 0, 0))
    hl = hl.filter(ImageFilter.GaussianBlur(5 * SS))
    glint = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    ImageDraw.Draw(glint).ellipse([c - R * 0.60, c - R * 0.66, c - R * 0.30, c - R * 0.54], fill=(255, 255, 255, 230))
    glint = glint.rotate(35, center=(c - R * 0.45, c - R * 0.6)).filter(ImageFilter.GaussianBlur(1.5 * SS))
    hl = Image.alpha_composite(hl, glint)
    bounce = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    ImageDraw.Draw(bounce).ellipse([c - R * 0.55, c + R * 0.66, c + R * 0.55, c + R * 0.92], fill=(255, 255, 255, 34))
    hl = Image.alpha_composite(hl, bounce.filter(ImageFilter.GaussianBlur(8 * SS)))
    # Keep the highlights inside the sphere.
    m = Image.fromarray((inside * 255).astype(np.uint8))
    clipped = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    clipped.paste(hl, (0, 0), m)
    return down(Image.alpha_composite(img, clipped), 256)


def divider():
    """A square image (as big as the orb) with the bar across its middle, so it scales with the orb."""
    w, h = 256 * SS, 256 * SS
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cy = h / 2
    # The bar spans the sphere (its ends tuck under the bezel).
    x0, x1 = w * (0.5 - INNER / 2) - 4 * SS, w * (0.5 + INNER / 2) + 4 * SS
    d.rounded_rectangle([x0, cy - 5 * SS, x1, cy + 5 * SS], radius=3 * SS, fill=(18, 15, 20, 255))
    d.rounded_rectangle([x0, cy - 3.5 * SS, x1, cy + 3.5 * SS], radius=2 * SS, fill=(58, 54, 62, 255))
    d.line([(x0 + 2 * SS, cy - 2 * SS), (x1 - 2 * SS, cy - 2 * SS)], fill=(110, 104, 116, 255), width=SS)
    d.line([(x0, cy - 5 * SS), (x1, cy - 5 * SS)], fill=(200, 156, 64, 255), width=SS)
    d.line([(x0, cy + 5 * SS), (x1, cy + 5 * SS)], fill=(120, 84, 28, 255), width=SS)
    # The gem: a gold-set diamond with a bright facet.
    g = 13 * SS
    cx = w / 2
    d.polygon([(cx, cy - g), (cx + g, cy), (cx, cy + g), (cx - g, cy)], fill=(214, 168, 74, 255))
    g2 = g * 0.72
    d.polygon([(cx, cy - g2), (cx + g2, cy), (cx, cy + g2), (cx - g2, cy)], fill=(150, 20, 34, 255))
    d.polygon([(cx, cy - g2), (cx + g2 * 0.55, cy - g2 * 0.1), (cx, cy), (cx - g2 * 0.4, cy - g2 * 0.3)], fill=(232, 90, 104, 255))
    d.ellipse([cx - g2 * 0.35 - SS, cy - g2 * 0.55 - SS, cx - g2 * 0.35 + SS, cy - g2 * 0.55 + SS], fill=(255, 230, 230, 255))
    return img.resize((256, 256), Image.LANCZOS)


def surface():
    w, h = 64, 16
    y, x = np.mgrid[0:h, 0:w].astype(float)
    a = np.exp(-((y - h / 2 + 0.5) / 2.2) ** 2) * (0.35 + 0.65 * np.sin(np.pi * (x + 0.5) / w) ** 0.6)
    return to_img(np.full((h, w, 3), 255.0), a)


# --------------------------------------------------------------------------------------------- preview

def tint(img, rgb):
    arr = np.array(img).astype(float)
    for i in range(3):
        arr[..., i] *= rgb[i] / 255.0
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def compose(parts, size, hp, mp, top_rgb, bot_rgb, swirl_angle=0):
    """The orb as the game will stack it: bezel, dark glass, the two liquid halves (masked to the
    sphere), the swirl, the surfaces, the divider, the glass."""
    S = size
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    m = parts["Mask.tga"].resize((S, S), Image.LANCZOS).split()[3]
    dark = parts["Empty.tga"].resize((S, S), Image.LANCZOS)
    inner = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    inner.paste(dark, (0, 0), m)
    canvas = Image.alpha_composite(canvas, inner)
    half = S // 2
    liq = parts["Liquid.tga"].resize((S, S), Image.LANCZOS)
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    # Top half: fills from the cut upward, the liquid texture cropped like a status bar.
    top_h = int(half * hp)
    if top_h > 0:
        crop = tint(liq.crop((0, half - top_h, S, half)), top_rgb)
        layer.paste(crop, (0, half - top_h))
    bot_h = int(half * mp)
    if bot_h > 0:
        crop = tint(liq.crop((0, S - bot_h, S, S)), bot_rgb)
        layer.paste(crop, (0, S - bot_h))
    sw = parts["Swirl.tga"].resize((S, S), Image.LANCZOS).rotate(swirl_angle)
    filled = Image.new("L", (S, S), 0)
    fd = ImageDraw.Draw(filled)
    if top_h > 0:
        fd.rectangle([0, half - top_h, S, half], fill=255)
    if bot_h > 0:
        fd.rectangle([0, S - bot_h, S, S], fill=255)
    sw_alpha = np.minimum(np.array(sw.split()[3]).astype(float), np.array(filled).astype(float)) * 0.6
    sw.putalpha(Image.fromarray(sw_alpha.astype(np.uint8)))
    layer = Image.alpha_composite(layer, sw)
    surf = parts["Surface.tga"].resize((S, max(4, S // 16)), Image.LANCZOS)
    for yy, rgb in ((half - top_h, top_rgb), (S - bot_h, bot_rgb)):
        if 0 < yy < S - 2:
            s2 = tint(surf, tuple(min(255, int(c * 0.6 + 110)) for c in rgb))
            layer.alpha_composite(s2, (0, int(yy - s2.height / 2)))
    clipped = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    clipped.paste(layer, (0, 0), m)
    canvas = Image.alpha_composite(canvas, clipped)
    canvas = Image.alpha_composite(canvas, parts["Divider.tga"].resize((S, S), Image.LANCZOS))
    canvas = Image.alpha_composite(canvas, parts["Glass.tga"].resize((S, S), Image.LANCZOS))
    canvas = Image.alpha_composite(canvas, parts["Frame.tga"].resize((S, S), Image.LANCZOS))
    return canvas


def preview(parts, folder):
    states = [(1.0, 1.0, (60, 255, 110), (90, 150, 255)), (0.64, 0.3, (60, 255, 110), (90, 150, 255)),
              (0.22, 0.75, (60, 255, 110), (255, 80, 70)), (0.5, 0.5, (60, 255, 110), (255, 220, 90))]
    sizes = (200, 56, 20)
    W = sum(s + 20 for s in sizes) * len(states)
    sheet = Image.new("RGBA", (len(states) * (200 + 56 + 20 + 80), 240), (34, 44, 38, 255))
    x = 20
    for hp, mp, top, bot in states:
        for s in sizes:
            o = compose(parts, s, hp, mp, top, bot, swirl_angle=25)
            sheet.alpha_composite(o, (x, 20 + (200 - s) // 2))
            x += s + 16
        x += 30
    sheet.save(os.path.join(folder, "preview.png"))


def main():
    prev = None
    if "--preview" in sys.argv:
        prev = sys.argv[sys.argv.index("--preview") + 1]
    os.makedirs(OUT, exist_ok=True)
    parts = {"Frame.tga": frame(), "Mask.tga": mask(), "Liquid.tga": liquid(), "Swirl.tga": swirl(),
             "Glass.tga": glass(), "Divider.tga": divider(), "Surface.tga": surface(), "Empty.tga": empty()}
    if prev:
        os.makedirs(prev, exist_ok=True)
        preview(parts, prev)
        print("preview written to", prev)
        return
    for name, img in parts.items():
        img.save(os.path.join(OUT, name))
    print("orb art written to", OUT)


if __name__ == "__main__":
    main()
