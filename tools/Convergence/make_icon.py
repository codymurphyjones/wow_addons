"""Draws the Convergence pin and logo: four elements (fire, water, earth, air) as wedges pointing
in to a bright spark where they meet, on a dark round badge with a teal edge.

Usage: python make_icon.py <output dir>
Writes <output dir>/Pin.tga (64x64, the world map pin, drawn at about 12 px),
<output dir>/Icon.tga (128x128, the addon list) and <output dir>/Logo.png (512x512, for listings)."""
import math, os, sys
from PIL import ImageDraw

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "_shared"))
import iconkit as ik
from iconkit import C, circle


TEAL = (84, 235, 199)


def paint(inside):
    di = ImageDraw.Draw(inside)

    # Four wedges pointing in to the centre: fire (top), water (right), earth (bottom), air (left).
    ELEMENTS = [
        (-90, (255, 112, 48), (255, 196, 92)),   # fire
        (0, (52, 140, 255), (140, 205, 255)),    # water
        (90, (128, 168, 70), (196, 214, 120)),   # earth
        (180, (205, 214, 226), (250, 252, 255)), # air
    ]
    OUTER, INNER, HALF = 400, 70, 34            # wedge: from the rim to near the centre, half-angle in degrees

    def polar(r, deg):
        a = math.radians(deg)
        return (C + r * math.cos(a), C + r * math.sin(a))

    for deg, dark, light in ELEMENTS:
        wedge = [polar(OUTER, deg - HALF), polar(OUTER, deg + HALF), polar(INNER, deg)]
        di.polygon([(x + 8, y + 10) for x, y in wedge], fill=(0, 0, 0, 120))
        di.polygon(wedge, fill=dark)
        # Lit half, for a little depth
        di.polygon([polar(OUTER, deg - HALF), polar(OUTER * 0.98, deg), polar(INNER, deg)], fill=light)

    # The spark where they meet
    inside = ik.soft_ellipse(inside, [C - 150, C - 150, C + 150, C + 150], (255, 240, 190, 200), 40)
    di = ImageDraw.Draw(inside)
    star = []
    for i in range(8):
        r = 120 if i % 2 == 0 else 46
        star.append(polar(r, -90 + i * 45))
    di.polygon(star, fill=(255, 250, 225))
    circle(di, 40, fill=(255, 255, 255))
    return inside


img = ik.badge(paint, inner=(26, 36, 44), rims=((490, TEAL), (456, (14, 22, 28))), radius=430,
               shadow=([C - 480, C - 470, C + 480, C + 490], 180, 16), ring=(438, 20, 150))
out_dir = ik.out_dir("Convergence")
ik.save(img, out_dir, (("Pin.tga", 64),) + ik.ICON_AND_LOGO)
print("saved Pin.tga, Icon.tga and Logo.png in", out_dir)
