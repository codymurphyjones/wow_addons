"""Shared drawing kit for the addons' icon scripts (tools/<Addon>/make_icon.py).

Every logo is drawn large on a supersampled canvas and scaled down with LANCZOS. Most sit on the
family's round badge: a soft drop shadow, a gold rim, a dark face, the picture clipped to the face,
and a soft inner shadow under the rim. The Wally suite's icons use a rounded square with a teal rim
instead, drawn at 4x.

    sys.path.insert(0, os.path.join(TOOLS, "_shared"))
    import iconkit as ik

    def paint(inside):          # draw the picture on the badge's face; return the layer
        ...
        return inside

    img = ik.badge(paint, inner=(24, 28, 44), glow=((ik.C - 330, ik.C - 300, ik.C + 330, ik.C + 300), (90, 140, 220, 70), 60))
    ik.save(img, ik.out_dir("StatLedger"))   # Icon.tga 128x128 and Logo.png 512x512

Needs Pillow."""
import os, sys
from PIL import Image, ImageDraw, ImageFilter

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

S = 1024                      # supersampled badge canvas, downscaled at the end
C = S / 2
SS = 4                        # supersampling for icons drawn in output-pixel design units


# --- Canvases and shapes ---------------------------------------------------------------------------

def layer(size=S):
    """A blank transparent square layer."""
    return Image.new("RGBA", (size, size), (0, 0, 0, 0))


def canvas(size, ss=SS):
    """A blank layer for a size x size icon drawn at ss times, and its ImageDraw."""
    img = layer(size * ss)
    return img, ImageDraw.Draw(img)


def s(v):
    """Design units (output pixels) to the SS-times supersampled canvas."""
    return v * SS


def circle(d, r, fill=None, outline=None, width=0, cx=C, cy=C):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill, outline=outline, width=width)


def soft_ellipse(img, box, fill, blur):
    """img with a Gaussian-blurred ellipse composited over it (glows, drop shadows, soft shine)."""
    glow = layer(img.size[0])
    ImageDraw.Draw(glow).ellipse(box, fill=fill)
    return Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(blur)))


def sparkle(d, cx, cy, r, fill, thin=0.22):
    """A four-pointed star."""
    t = r * thin
    d.polygon([(cx, cy - r), (cx + t, cy - t), (cx + r, cy), (cx + t, cy + t),
               (cx, cy + r), (cx - t, cy + t), (cx - r, cy), (cx - t, cy - t)], fill=fill)


# --- The round badge -------------------------------------------------------------------------------

GOLD_RIM = ((480, (120, 82, 24)), (462, (214, 166, 64)), (446, (92, 60, 18)))


def badge(paint=None, inner=(24, 28, 44), glow=None, rims=GOLD_RIM, radius=432,
          shadow=((C - 470, C - 455, C + 470, C + 485), 170, 18), ring=(440, 22, 140)):
    """A round badge on an S x S canvas.

    paint(layer) draws the picture on a transparent layer and returns it; it is clipped to the face.
    inner   the face colour (radius `radius`), inside the rims: (radius, colour) from the outside in.
    glow    (box, rgba, blur): a soft glow put on the face's layer before paint, or None.
    shadow  (box, alpha, blur): the drop shadow under the badge.
    ring    (radius, width, alpha): the inner shadow under the rim, blurred 8."""
    box, alpha, blur = shadow
    img = soft_ellipse(layer(), box, (0, 0, 0, alpha), blur)
    d = ImageDraw.Draw(img)
    for r, colour in rims:
        circle(d, r, fill=colour)
    circle(d, radius, fill=inner)

    inside = layer()
    if glow:
        inside = soft_ellipse(inside, *glow)
    if paint:
        inside = paint(inside)

    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).ellipse([C - radius, C - radius, C + radius, C + radius], fill=255)
    clipped = layer()
    clipped.paste(inside, (0, 0), Image.composite(inside.split()[3], Image.new("L", (S, S), 0), mask))
    img = Image.alpha_composite(img, clipped)
    r, width, alpha = ring
    rim_shadow = layer()
    ImageDraw.Draw(rim_shadow).ellipse([C - r, C - r, C + r, C + r], outline=(0, 0, 0, alpha), width=width)
    return Image.alpha_composite(img, rim_shadow.filter(ImageFilter.GaussianBlur(8)))


def upgrade_arrow(d, shine, ax, top, bottom, head=120, neck=140, shaft=50, drop=(8, 10), width=10,
                  glint=(40, 60, 110)):
    """The family's green "move up" arrow, point at (ax, top), with its drop shadow on d and a
    translucent glint on shine (a separate layer's draw, so it blends instead of replacing colour).
    head/shaft are half widths, neck the arrowhead's height, glint (top, half width, bottom)."""
    arrow = [(ax, top), (ax + head, top + neck), (ax + shaft, top + neck), (ax + shaft, bottom),
             (ax - shaft, bottom), (ax - shaft, top + neck), (ax - head, top + neck)]
    d.polygon([(x + drop[0], y + drop[1]) for x, y in arrow], fill=(0, 0, 0, 130))
    d.polygon(arrow, fill=(70, 200, 90), outline=(20, 60, 26), width=width)
    g0, gw, g1 = glint
    shine.polygon([(ax, top + g0), (ax + gw, top + g1), (ax - gw, top + g1)], fill=(170, 250, 180, 150))


# --- The SpyGlass family (Spyglass, SpyglassPluginQuests) ------------------------------------------

BRASS, BRASS_LIGHT, BRASS_DARK, BRASS_OUTLINE = (214, 164, 62), (250, 214, 120), (140, 96, 30), (48, 30, 12)
LEATHER, LEATHER_DARK = (122, 62, 34), (74, 36, 18)
NIGHT_SKY = (22, 26, 52)                                                # the badge face
NIGHT_GLOW = ((520, 80, 1000, 520), (70, 70, 130, 120), 90)             # lighter sky to the upper right


def night_stars(d):
    for x, y, r in ((230, 250, 16), (330, 160, 11), (180, 420, 10), (470, 210, 13), (860, 600, 12), (300, 330, 8)):
        sparkle(d, x, y, r, (230, 226, 200))


def spyglass(inside):
    """inside with the brass spyglass, tipped up to the right, and its shadow composited on it."""
    tel = layer()
    dt = ImageDraw.Draw(tel)
    cy = C
    # (x0, x1, half height) from the eyepiece to the wide end
    sections = [(190, 290, 38), (280, 450, 54), (440, 640, 70), (630, 820, 88)]
    for x0, x1, h in sections:
        fill = LEATHER if (x0, x1, h) == sections[2] else BRASS
        dt.rounded_rectangle([x0, cy - h, x1, cy + h], radius=14, fill=fill, outline=BRASS_OUTLINE, width=12)
        # highlight along the top, shade along the bottom
        light = (176, 96, 56) if fill == LEATHER else BRASS_LIGHT
        dark = LEATHER_DARK if fill == LEATHER else BRASS_DARK
        dt.rectangle([x0 + 18, cy - h + 14, x1 - 18, cy - h + 14 + h * 0.32], fill=light)
        dt.rectangle([x0 + 18, cy + h - 14 - h * 0.3, x1 - 18, cy + h - 14], fill=dark)
    # brass bands at the joints and the rim of the wide end
    for x, h in ((288, 58), (448, 74), (636, 92)):
        dt.rounded_rectangle([x - 16, cy - h, x + 16, cy + h], radius=8, fill=BRASS, outline=BRASS_OUTLINE, width=10)
    dt.rounded_rectangle([800, cy - 106, 860, cy + 106], radius=16, fill=BRASS, outline=BRASS_OUTLINE, width=12)
    dt.rectangle([814, cy - 90, 846, cy - 40], fill=BRASS_LIGHT)
    # eyepiece cap
    dt.rounded_rectangle([166, cy - 28, 204, cy + 28], radius=10, fill=BRASS_DARK, outline=BRASS_OUTLINE, width=10)
    # the lens, seen edge-on at the wide end
    dt.ellipse([836, cy - 94, 896, cy + 94], fill=(150, 210, 240), outline=BRASS_OUTLINE, width=12)
    dt.ellipse([852, cy - 68, 876, cy - 18], fill=(235, 250, 255))

    tel = tel.rotate(33, resample=Image.BICUBIC, center=(C, C))         # tipped up to the right
    # then moved down a little (an affine transform's offsets are where to read from)
    tel = tel.transform((S, S), Image.AFFINE, (1, 0, 10, 0, 1, -95), resample=Image.BICUBIC)
    tel_shadow = layer()
    tel_shadow.paste((0, 0, 0, 120), (14, 18), tel.split()[3])
    inside = Image.alpha_composite(inside, tel_shadow.filter(ImageFilter.GaussianBlur(6)))
    return Image.alpha_composite(inside, tel)


# --- The Wally suite's rounded-square badge --------------------------------------------------------

WALLY_ACCENT = (64, 196, 205, 255)
WALLY_DARK = (16, 19, 25, 255)


def wally_badge(d):
    """The suite's dark rounded square with a teal rim, on a 128-unit canvas at SS."""
    d.rounded_rectangle([s(6), s(6), s(122), s(122)], radius=s(24), fill=WALLY_DARK, outline=WALLY_ACCENT, width=s(4))


# --- Output ----------------------------------------------------------------------------------------

ICON_AND_LOGO = (("Icon.tga", 128), ("Logo.png", 512))


def out_dir(addon, use_argv=True):
    """The folder to write into: the first command-line argument if given (and use_argv), else
    addons/<addon>/Media in this repo. Created if missing."""
    folder = sys.argv[1] if use_argv and len(sys.argv) > 1 else os.path.join(REPO, "addons", addon, "Media")
    os.makedirs(folder, exist_ok=True)
    return folder


def save(img, folder, outputs=ICON_AND_LOGO):
    """Scale img down to each (file name, size) in outputs and save it in folder: .tga is 32-bit
    for the game, .png for listings. Returns the paths written."""
    paths = []
    for name, size in outputs:
        path = os.path.join(folder, name)
        img.resize((size, size), Image.LANCZOS).save(path)
        paths.append(path)
    return paths
