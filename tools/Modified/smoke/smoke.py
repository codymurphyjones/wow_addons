"""Loads Modified (in TOC order) into Lua 5.5 with a mocked WoW client and plays smoke.lua: the
veil, a bloom, typing, the wheel, modifier taps and holds, braids, seal, unravel, growth.

    python tools/Modified/smoke/smoke.py

Needs lupa (pip install lupa). Lua 5.5 isn't WoW's 5.1, but close enough for the logic.
Globals the addon reads that neither the mock nor the addon define are listed at the end.
"""
import os
import re
import sys

import lupa
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
ADDON = os.path.join(REPO, "addons", "Modified")


SHOTS = os.path.join(HERE, "shots")
TEXTURES = os.path.join(ADDON, "Textures")
ICONS = {135907: ("FH", (142, 230, 255)), 135953: ("Re", (157, 255, 176)), 135940: ("PW", (255, 226, 122)),
         135924: ("Sm", (255, 207, 107)), 136207: ("SW", (197, 139, 255)), 135955: ("Rz", (255, 246, 200)),
         135230: ("Hs", (120, 255, 120)), 134400: ("?", (160, 160, 160))}
_cache = {}


def _font(size):
    for name in ("segoeui.ttf", "arial.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def _shape(name, w, h, rgb, alpha):
    key = (name, w, h)
    if key not in _cache:
        _cache[key] = Image.open(os.path.join(TEXTURES, name + ".tga")).convert("RGBA").resize((max(w, 1), max(h, 1)), Image.LANCZOS)
    base = _cache[key]
    tinted = Image.new("RGBA", base.size, tuple(int(c * 255) for c in rgb) + (0,))
    tinted.putalpha(base.getchannel("A").point(lambda v: int(v * alpha)))
    return tinted


def _segments(text):
    """|cffRRGGBB...|r colour codes to (text, rgb) runs."""
    out, color = [], None
    for part in re.split(r"(\|c[0-9a-fA-F]{8}|\|r)", text):
        if part.startswith("|c"):
            color = tuple(int(part[i:i + 2], 16) for i in (4, 6, 8))
        elif part == "|r":
            color = None
        elif part:
            out.append((part, color))
    return out


def render(lua, name, crop=None):
    """Draws what the mock client would show: the game behind the veil, then every visible texture
    and font string, roughly in creation order."""
    W, H = int(lua.eval("MOCK.W")), int(lua.eval("MOCK.H"))
    img = Image.new("RGBA", (W, H), (40, 58, 78, 255))
    d = ImageDraw.Draw(img)
    for i in range(12):  # Action Bar 1 under the veil
        cx = W / 2 - 270 + i * 49
        d.rectangle((cx - 22, H - 40 - 22, cx + 22, H - 40 + 22), fill=(70, 70, 80, 255), outline=(20, 20, 20, 255))
    if lua.eval("MOCK and NS.Veil.frame and NS.Veil.frame:IsShown()"):
        img.alpha_composite(Image.new("RGBA", (W, H), (3, 4, 8, 168)))
    font = _font(15)
    small = _font(12)
    for item in lua.eval("MOCK.Dump()").values():
        x, y = item["x"], H - item["y"]  # PIL counts y downwards
        w, h, a = int(item["w"] or 0), int(item["h"] or 0), item["a"]
        rgb = (item["r"], item["g"], item["b"])
        if item["kind"] == "Texture":
            tex = item["tex"]
            m = re.search(r"Textures\\(\w+)$", tex)
            if tex == "color" and w > 0 and h > 0:
                layer = Image.new("RGBA", (W, H))
                ImageDraw.Draw(layer).rectangle((x - w / 2, y - h / 2, x + w / 2, y + h / 2),
                                                fill=tuple(int(c * 255) for c in rgb) + (int(255 * a),))
                img.alpha_composite(layer)
            elif m and m.group(1) in ("Dot", "Ring", "Glow", "Disc") and w > 0:
                img.alpha_composite(_shape(m.group(1), w, h, rgb, a), (int(x - w / 2), int(y - h / 2)))
            elif tex.isdigit() and w > 0:
                label, col = ICONS.get(int(tex), ("?", (200, 200, 200)))
                layer = Image.new("RGBA", (W, H))
                ld = ImageDraw.Draw(layer)
                ld.ellipse((x - w / 2, y - h / 2, x + w / 2, y + h / 2), fill=col + (int(255 * a),))
                f = _font(max(int(h * 0.38), 8))
                ld.text((x, y), label, fill=(0, 0, 0, int(200 * a)), font=f, anchor="mm")
                img.alpha_composite(layer)
        else:
            text = item["text"] or ""
            if not text:
                continue
            f = small
            lines = re.sub(r"\|T[^|]*\|t", "o ", text).split("\n")
            layer = Image.new("RGBA", (W, H))
            ld = ImageDraw.Draw(layer)
            lh = 15
            top = y - h / 2
            lh = 15
            wrapped = []
            for line in lines:
                # Greedy word wrap to the font string's width, keeping colours.
                words = []
                for t, col in _segments(line):
                    for word in re.findall(r"\S+\s*|\s+", t):
                        words.append((word, col))
                current, cw = [], 0
                limit = w if (item["justify"] == "LEFT" and w > 40) else 1e9
                for word, col in words:
                    ww = ld.textlength(word, font=f)
                    if current and cw + ww > limit:
                        wrapped.append(current)
                        current, cw = [], 0
                    current.append((word, col))
                    cw += ww
                wrapped.append(current)
            for li, runs in enumerate(wrapped):
                width = sum(ld.textlength(t, font=f) for t, _ in runs)
                if item["justify"] == "LEFT":
                    left = x - w / 2
                elif item["justify"] == "RIGHT":
                    left = x + w / 2 - width
                else:
                    left = x - width / 2
                for t, col in runs:
                    col = col or tuple(int(c * 255) for c in rgb)
                    ld.text((left + 1, top + li * lh + 1), t, fill=(0, 0, 0, int(200 * a)), font=f)
                    ld.text((left, top + li * lh), t, fill=col + (int(255 * a),), font=f)
                    if item["bold"]:
                        ld.text((left + 1, top + li * lh), t, fill=col + (int(255 * a),), font=f)
                    left += ld.textlength(t, font=f)
            img.alpha_composite(layer)
    # the cursor
    cx, cy = lua.eval("MOCK.cursor[1]"), H - lua.eval("MOCK.cursor[2]")
    d = ImageDraw.Draw(img)
    d.polygon([(cx, cy), (cx, cy + 18), (cx + 5, cy + 13), (cx + 12, cy + 13)], fill=(255, 255, 255, 255), outline=(0, 0, 0, 255))
    os.makedirs(SHOTS, exist_ok=True)
    if crop:
        img = img.crop(crop)
    img.convert("RGB").save(os.path.join(SHOTS, name + ".png"))


def toc_files():
    files = []
    with open(os.path.join(ADDON, "Modified.toc"), encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                files.append(os.path.normpath(os.path.join(ADDON, line.replace("\\", os.sep))))
    return files


def run(width, height):
    print(f"=== screen {width}x{height}")
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(f"MOCK_SCREEN = {{ {width}, {height} }}; SHOT = '{width}_'")
    lua.execute(open(os.path.join(HERE, "wowmock.lua"), encoding="utf-8").read())
    lua.execute("""
        MISSING = {}
        setmetatable(_G, { __index = function(_, k) MISSING[k] = true end })
        NS = {}
    """)
    loader = lua.eval("function(src, name) local f, e = load(src, '@' .. name); if not f then error(e) end; f('Modified', NS) end")
    for path in toc_files():
        loader(open(path, encoding="utf-8").read(), os.path.relpath(path, REPO))
    out = []
    lua.globals().print = lambda *a: out.append(" ".join(str(x) for x in a))
    lua.execute("function print(...) local t = {} for i = 1, select('#', ...) do t[#t+1] = tostring((select(i, ...))) end PYPRINT(table.concat(t, ' ')) end")
    lua.globals().PYPRINT = lambda s: print(s)
    lua.globals().SNAP = lambda name: render(lua, name)
    try:
        lua.execute(open(os.path.join(HERE, "smoke.lua"), encoding="utf-8").read())
    except lupa.LuaError as e:
        print("LUA ERROR:", e)
        sys.exit(1)
    missing = sorted(lua.eval("(function() local t = {} for k in pairs(MISSING) do t[#t+1] = k end return table.concat(t, ' ') end)()").split())
    print("globals read but not defined:", " ".join(missing) or "none")


def main():
    for size in ((1920, 1080), (1365, 768)):
        run(*size)


if __name__ == "__main__":
    main()
