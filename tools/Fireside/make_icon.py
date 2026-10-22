"""Draws the Fireside logo: a campfire at night. Two travellers sit on either side of a crackling
fire in a ring of stones, lit warm on the side facing the flames; embers rise into a starry sky over
a dark line of pines, and the firelight spills across the ground. On the family's dark round badge
with a gold rim (as StatLedger's and Wealth Planner's).

Usage: python make_icon.py <output dir>
Writes <output dir>/Icon.tga (128x128, 32-bit, used in game) and
<output dir>/Logo.png (512x512, for CurseForge and other listings)."""
import math
import os
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "_shared"))
import iconkit as ik
from iconkit import C, S, layer, soft_ellipse, sparkle

FIRE_X, FIRE_Y = C, 700          # the base of the flames
GROUND_Y = 690                   # where the ground meets the treeline's foot

random.seed(7)


def blend(img, top):
    return Image.alpha_composite(img, top)


def sky(inside):
    """Night overhead, warming towards the fire."""
    grad = layer()
    d = ImageDraw.Draw(grad)
    top, mid = (14, 16, 38), (46, 30, 52)
    for y in range(S):
        t = min(1, max(0, (y - 80) / 620))
        col = tuple(int(top[i] + (mid[i] - top[i]) * t) for i in range(3))
        d.line([(0, y), (S, y)], fill=col + (255,))
    inside = blend(inside, grad)
    d = ImageDraw.Draw(inside)
    for x, y, r in ((250, 210, 15), (360, 140, 10), (190, 340, 9), (470, 190, 7), (640, 150, 13),
                    (760, 230, 9), (830, 330, 12), (560, 250, 6), (300, 270, 6), (700, 300, 6)):
        sparkle(d, x, y, r, (236, 232, 210))
    # a thin moon, high on the right
    moon = layer()
    dm = ImageDraw.Draw(moon)
    dm.ellipse([660, 110, 760, 210], fill=(244, 236, 206, 255))
    dm.ellipse([690, 96, 790, 196], fill=(0, 0, 0, 0))
    return blend(inside, moon)


def pine(d, x, base, h, w, col):
    """A pine silhouette: stacked triangles."""
    tiers = 4
    for i in range(tiers):
        t0 = i / tiers
        top = base - h + h * t0 * 0.75
        bottom = top + h * 0.42
        half = w * (0.35 + 0.65 * (i + 1) / tiers) / 2
        d.polygon([(x, top), (x + half, bottom), (x - half, bottom)], fill=col)
    d.rectangle([x - w * 0.05, base - h * 0.12, x + w * 0.05, base], fill=col)


def treeline(inside):
    trees = layer()
    d = ImageDraw.Draw(trees)
    far = (24, 22, 40, 255)
    for x, h, w in ((90, 300, 150), (180, 380, 170), (270, 300, 140), (760, 310, 150), (850, 390, 170), (940, 300, 150),
                    (360, 220, 110), (660, 230, 110)):
        pine(d, x, GROUND_Y + 10, h, w, far)
    d.rectangle([0, GROUND_Y - 6, S, S], fill=far)
    return blend(inside, trees)


def ground(inside):
    """The clearing, lit warm around the fire."""
    g = layer()
    d = ImageDraw.Draw(g)
    d.ellipse([-120, GROUND_Y - 70, S + 120, S + 420], fill=(40, 26, 24, 255))
    inside = blend(inside, g)
    inside = soft_ellipse(inside, (FIRE_X - 380, FIRE_Y - 120, FIRE_X + 380, FIRE_Y + 180), (210, 110, 40, 130), 60)
    inside = soft_ellipse(inside, (FIRE_X - 220, FIRE_Y - 60, FIRE_X + 220, FIRE_Y + 110), (255, 160, 70, 120), 40)
    return inside


def flame_shape(cx, base, w, h, lean=0.0, sway=0.10, phase=0.0, steps=120):
    """A teardrop flame: a round foot, swelling, then licking up to a curling tip."""
    left, right = [], []
    for i in range(steps + 1):
        t = i / steps                      # 0 at the foot, 1 at the tip
        if t < 0.22:
            half = w / 2 * math.sqrt(max(0.0, 1 - ((0.22 - t) / 0.22) ** 2))
        else:
            half = w / 2 * ((1 - t) / 0.78) ** 1.35
        y = base - h * t
        x = cx + lean * h * t * t + math.sin(t * math.pi * 1.6 + phase) * w * sway * t
        left.append((x - half, y))
        right.append((x + half, y))
    return left + right[::-1]


def fire_glow(inside):
    inside = soft_ellipse(inside, (FIRE_X - 330, FIRE_Y - 430, FIRE_X + 330, FIRE_Y + 90), (255, 110, 30, 110), 90)
    return soft_ellipse(inside, (FIRE_X - 180, FIRE_Y - 300, FIRE_X + 180, FIRE_Y + 50), (255, 180, 80, 110), 50)


def stone(d, x, y, rx, ry, lit):
    d.ellipse([x - rx, y - ry, x + rx, y + ry], fill=(78, 68, 74, 255), outline=(28, 22, 28, 255), width=6)
    d.ellipse([x - rx * 0.7, y - ry * 0.85, x + rx * 0.45, y - ry * 0.1], fill=(206, 146, 96, lit))


def fire(inside):
    # Back stones (behind the logs).
    back = layer()
    d = ImageDraw.Draw(back)
    for x, y, rx, ry in ((FIRE_X - 120, FIRE_Y - 6, 40, 24), (FIRE_X, FIRE_Y - 14, 44, 24), (FIRE_X + 125, FIRE_Y - 6, 40, 24)):
        stone(d, x, y, rx, ry, 120)
    inside = blend(inside, back)

    # Logs: two crossed in front, one lying behind, their cut ends towards us.
    logs = layer()
    d = ImageDraw.Draw(logs)
    for (x0, y0, x1, y1) in ((FIRE_X + 140, FIRE_Y + 10, FIRE_X - 110, FIRE_Y - 60),
                             (FIRE_X - 150, FIRE_Y + 30, FIRE_X + 120, FIRE_Y - 40)):
        d.line([(x0, y0), (x1, y1)], fill=(28, 14, 8, 255), width=64)
        d.line([(x0, y0), (x1, y1)], fill=(104, 58, 30, 255), width=50)
        d.line([(x0, y0 - 14), (x1, y1 - 14)], fill=(156, 96, 52, 255), width=10)
        d.ellipse([x0 - 30, y0 - 30, x0 + 30, y0 + 30], fill=(222, 178, 116, 255), outline=(58, 32, 16, 255), width=7)
        d.ellipse([x0 - 14, y0 - 14, x0 + 14, y0 + 14], outline=(160, 108, 62, 255), width=5)
    inside = blend(inside, logs)

    # Coals.
    inside = soft_ellipse(inside, (FIRE_X - 120, FIRE_Y - 40, FIRE_X + 120, FIRE_Y + 30), (255, 96, 24, 230), 16)

    # Flames, outside in: deep red, orange, gold, a white-hot heart; a few loose tongues around them.
    flames = layer()
    d = ImageDraw.Draw(flames)
    for dx, w, h, lean, sway, phase, col in (
            (-70, 120, 260, -0.30, 0.12, 0.4, (206, 50, 22, 255)),
            (80, 110, 240, 0.32, 0.12, 2.0, (206, 50, 22, 255)),
            (0, 250, 440, 0.06, 0.10, 0.0, (220, 62, 24, 255)),
            (-40, 110, 300, -0.18, 0.14, 1.2, (240, 108, 30, 255)),
            (45, 100, 280, 0.20, 0.14, 2.8, (240, 108, 30, 255)),
            (0, 190, 370, -0.04, 0.10, 1.6, (246, 122, 32, 255)),
            (5, 140, 300, 0.06, 0.10, 0.9, (252, 172, 44, 255)),
            (0, 92, 220, -0.04, 0.10, 2.2, (255, 220, 100, 255)),
            (0, 50, 130, 0.02, 0.08, 0.3, (255, 248, 220, 255))):
        d.polygon(flame_shape(FIRE_X + dx, FIRE_Y - 6, w, h, lean=lean, sway=sway, phase=phase), fill=col)
    inside = blend(inside, flames.filter(ImageFilter.GaussianBlur(2)))
    bloom = flames.filter(ImageFilter.GaussianBlur(30))
    inside = blend(inside, Image.blend(layer(), bloom, 0.5))

    # Front stones, lit on top by the fire.
    front = layer()
    d = ImageDraw.Draw(front)
    for x, y, rx, ry in ((FIRE_X - 190, FIRE_Y + 22, 46, 28), (FIRE_X - 100, FIRE_Y + 52, 50, 30), (FIRE_X + 8, FIRE_Y + 62, 54, 30),
                         (FIRE_X + 112, FIRE_Y + 50, 48, 29), (FIRE_X + 196, FIRE_Y + 20, 44, 27)):
        stone(d, x, y, rx, ry, 170)
    return blend(inside, front)


def traveller(inside, cx, facing):
    """A seated, cloaked and hooded figure leaning towards the fire (facing = +1: the fire is to the
    right). Near-black against the glow, with warm light along the edge that faces the flames."""
    body = layer()
    d = ImageDraw.Draw(body)
    base = FIRE_Y + 70
    f = facing

    def P(x, y): return (cx + x * f, base + y)

    col = (12, 9, 18, 255)
    # Cloak: a rounded back down to the log, shoulders, knees drawn up towards the fire.
    d.polygon([P(-86, 0), P(-90, -80), P(-78, -150), P(-50, -188), P(-6, -204), P(34, -190), P(52, -150),
               P(96, -96), P(122, -70), P(124, -26), P(100, 0)], fill=col)
    # Hooded head, a little forward of the shoulders, the hood's peak falling back.
    d.ellipse([P(-38, -298)[0] if f > 0 else P(58, -298)[0], base - 298, P(58, -298)[0] if f > 0 else P(-38, -298)[0], base - 202],
              fill=col)
    d.polygon([P(-30, -276), P(-52, -244), P(-62, -200), P(-40, -184), P(-10, -212)], fill=col)
    # The hood's opening, faintly lit, on the side towards the fire.
    d.polygon([P(30, -282), P(58, -258), P(58, -224), P(36, -208)], fill=(70, 34, 22, 255))
    # An arm reaching out to the warmth, the hand open to the flames.
    d.line([P(20, -176), P(84, -150), P(140, -142)], fill=col, width=36, joint="curve")
    d.ellipse([P(124, -160)[0] if f > 0 else P(156, -160)[0], base - 160, P(156, -126)[0] if f > 0 else P(124, -126)[0], base - 126], fill=col)
    body = body.filter(ImageFilter.GaussianBlur(1.2))

    # Firelight on the edge that faces the flames: the silhouette minus itself nudged towards the fire.
    alpha = body.split()[3]
    rim = ImageChops.subtract(alpha, ImageChops.offset(alpha, -11 * f, 5)).filter(ImageFilter.GaussianBlur(2))
    rim_layer = Image.new("RGBA", (S, S), (255, 168, 80, 0))
    rim_layer.putalpha(rim.point(lambda v: int(v * 0.9)))

    seat = layer()
    ImageDraw.Draw(seat).rounded_rectangle([cx - 120, base - 4, cx + 120, base + 40], radius=22, fill=(44, 24, 16, 255))
    inside = blend(inside, seat)
    inside = blend(inside, body)
    return blend(inside, rim_layer)


def embers(inside):
    e = layer()
    d = ImageDraw.Draw(e)
    for _ in range(16):
        t = random.random()
        y = FIRE_Y - 380 - t * 200
        x = FIRE_X + random.uniform(-1, 1) * (60 + t * 200) + math.sin(t * 7) * 30
        r = random.uniform(5, 10) * (1 - t * 0.5)
        a = int(255 * (1 - t * 0.6))
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 200 + int(40 * (1 - t)), 100, a))
    glow = e.filter(ImageFilter.GaussianBlur(7))
    return blend(blend(inside, glow), e)


def paint(inside):
    inside = sky(inside)
    inside = treeline(inside)
    inside = ground(inside)
    inside = fire_glow(inside)
    inside = traveller(inside, 230, 1)
    inside = traveller(inside, S - 230, -1)
    inside = fire(inside)
    inside = embers(inside)
    return inside


img = ik.badge(paint, inner=(14, 16, 38))
out_dir = ik.out_dir("Fireside")
ik.save(img, out_dir)
print("saved", os.path.join(out_dir, "Icon.tga"), "and Logo.png")
