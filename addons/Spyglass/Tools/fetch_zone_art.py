"""Pictures for the journal's World tab, one per zone: a scenic view of the zone
(the featured screenshot on its Wowhead page), or, for a zone without one, its
fully revealed map (Wowhead's map images: the game's own map art only shows what
your character has explored, so most tiles would be blank). Cropped to the
tile's shape and saved as small TGAs in Media/Zones/, with Journal/ZoneArt.lua
naming them by zone.

Needs Pillow (python -m pip install --user pillow).

    python Tools/fetch_zone_art.py
"""
import io
import os
import re
import site
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.append(site.getusersitepackages())  # Pillow from a --user install
import fetch_wowhead_quests as fq  # noqa: E402  (its paced, cached fetcher)
from PIL import Image  # noqa: E402

ADDON = fq.ADDON
MEDIA = os.path.join(ADDON, "Media", "Zones")
OUT = os.path.join(ADDON, "Journal", "ZoneArt.lua")
ZONES = "https://www.wowhead.com/forever/zones"
MAP = "https://wow.zamimg.com/images/wow/classic/maps/enus/original/%d.jpg"
SIZE = (256, 128)  # power-of-two sides (the client wants them), about the tile's shape


def zone_list(fetcher):
    """{ name: area ID } for the open-world zones (not instances), classic IDs first."""
    text = fetcher.get(ZONES) or ""
    start = text.find('"template":"zone","data":')
    rows = fq.js_literal(fq.balanced(text, text.index("[", start))) if start >= 0 else []
    out = {}
    for r in sorted(rows, key=lambda r: r["id"]):
        if r.get("instance") == 0 and r.get("name") and r["name"] not in out:
            out[r["name"]] = r["id"]
    return out


def fetch_image(fetcher, url):
    """The image's bytes (cached like every other answer), or None."""
    path = os.path.join(fq.CACHE, "img-" + url.rsplit("/", 1)[-1])
    if os.path.exists(path):
        with open(path, "rb") as f:
            return f.read()
    import urllib.request
    import time
    time.sleep(fq.PACE)
    try:
        req = urllib.request.Request(url, headers={"User-Agent": fq.UA})
        with urllib.request.urlopen(req, timeout=40) as resp:
            data = resp.read()
    except OSError:
        return None
    with open(path, "wb") as f:
        f.write(data)
    return data


ZONE_PAGES = ("https://www.wowhead.com/classic/zone=%d", "https://www.wowhead.com/forever/zone=%d")


def scenic_url(fetcher, area):
    """The zone page's featured screenshot (its og:image), or None."""
    for page in ZONE_PAGES:
        text = fetcher.get(page % area) or ""
        m = re.search(r'<meta property="og:image" content="(https://wow\.zamimg\.com/uploads/screenshots/[^"]+)"', text)
        if m and shot_id(m.group(1)) not in SKIP:
            return m.group(1)
    return None


ATLAS_DATA = os.path.join(ADDON, "..", "AtlasLootClassic_DungeonsAndRaids", "data.lua")
SHOT = "https://wow.zamimg.com/uploads/screenshots/normal/%d.jpg"

# Screenshots that aren't views of the place: Wowhead's batch of loading
# screens (often a zone's featured picture) and annotated dungeon maps.
SKIP = set(range(81100, 81200)) | {2609, 41818, 54108}

# Places sharing one zone on Wowhead, each given its own view (picked by eye
# from the zone's screenshots).
PICKS = {
    "ScarletMonasteryGraveyard": 63896,  # the courtyard outside
    "ScarletMonasteryLibrary": 68359,    # a long hall
    "ScarletMonasteryArmory": 68361,     # Herod's room
    "ScarletMonasteryCathedral": 68362,  # the cathedral
    "DireMaulEast": 78999,               # overgrown Warpwood Quarter
    "DireMaulWest": 9193,                # the crystal pylons
    "DireMaulNorth": 78998,              # Gordok's ruins
    "LowerBlackrockSpire": 69819,        # lava
    "UpperBlackrockSpire": 69820,        # the halls
}


def shot_id(url):
    m = re.search(r"/screenshots/\w+/(\d+)", url or "")
    return int(m.group(1)) if m else None


def instances():
    """AtlasLoot's classic dungeons and raids with a zone: [ (key, area ID) ] in its order
    (the TBC file isn't read; Forever's own places have no zone on Wowhead)."""
    try:
        text = open(ATLAS_DATA, encoding="utf-8").read()
    except OSError:
        return []
    out = []
    for m in re.finditer(r'^data\["([^"]+)"\]\s*=\s*\{', text, re.M):
        mid = re.search(r"MapID\s*=\s*(\d+)", text[m.end():m.end() + 1500])
        if mid:
            out.append((m.group(1), int(mid.group(1))))
    return out


def gallery(fetcher, area):
    """The zone page's screenshots, featured first: wide ones only (they crop to a tile)."""
    urls = []
    featured = scenic_url(fetcher, area)
    if featured:
        urls.append(featured)
    text = fetcher.get(ZONE_PAGES[0] % area) or ""
    m = re.search(r"var lv_screenshots = (\[.*?\]);", text, re.S)
    if m:
        try:
            shots = fq.js_literal(m.group(1))
        except ValueError:
            shots = []
        for shot in shots:
            if shot["id"] not in SKIP and (shot.get("width") or 0) >= 800 and (shot.get("width") or 0) > (shot.get("height") or 0):
                urls.append(SHOT % shot["id"])
    return urls


def save(data, name):
    """Crop the middle to 2:1, shrink, save Media/Zones/<name>.tga. False when it isn't an image."""
    try:
        img = Image.open(io.BytesIO(data)).convert("RGB")
    except OSError:
        return False
    w, h = img.size
    ch = min(h, w // 2)
    top = (h - ch) // 2
    img.crop((0, top, w, top + ch)).resize(SIZE, Image.LANCZOS).save(os.path.join(MEDIA, name + ".tga"))
    return True


def picture(fetcher, urls, area, name):
    """The first of urls that loads (a scenic view), else the area's revealed map: 'view', 'map' or None."""
    for url in urls:
        data = fetch_image(fetcher, url)
        if data and save(data, name):
            return "view"
    data = fetch_image(fetcher, MAP % area)
    if data and save(data, name):
        return "map"
    return None


def main():
    fetcher = fq.Fetcher()
    os.makedirs(MEDIA, exist_ok=True)
    kinds = {"view": 0, "map": 0}

    # World tab: one picture per zone.
    zones, made = zone_list(fetcher), {}
    for name, area in sorted(zones.items()):
        url = scenic_url(fetcher, area)
        kind = picture(fetcher, [url] if url else [], area, str(area))
        if kind:
            made[name] = area
            kinds[kind] += 1
            print("  %-28s %-6d %s" % (name, area, kind))

    # Dungeons and raids (used where the game has no Dungeon Finder picture):
    # places sharing a zone (Scarlet Monastery's wings, Dire Maul's) each get a
    # different screenshot from it.
    inst_made, by_area = {}, {}
    for key, area in instances():
        by_area.setdefault(area, []).append(key)
    for area, keys in by_area.items():
        shots = gallery(fetcher, area)
        for i, key in enumerate(keys):
            name = "inst-" + re.sub(r"[^A-Za-z0-9]", "", key)
            urls = ([SHOT % PICKS[key]] if key in PICKS else []) + shots[i:i + 1] + shots[i + 1:i + 3]
            kind = picture(fetcher, urls, area, name)
            if kind:
                inst_made[key] = name
                kinds[kind] += 1
                print("  %-28s %-6d %s" % (key, area, kind))

    lines = [
        "-- GENERATED by Spyglass/Tools/fetch_zone_art.py: pictures for the journal's tiles",
        "-- (Media\\Zones\\*.tga: scenic views, else revealed maps). Do not edit; run the tool again.",
        "local _, ns = ...",
        "-- World tab zones, by name: Media\\Zones\\<area ID>.tga",
        "ns.ZoneArt = {",
    ]
    lines += ["    [%s] = %d," % (fq.lua_str(n), a) for n, a in sorted(made.items())]
    lines += ["}", "-- Dungeons and raids, by AtlasLoot key: Media\\Zones\\<name>.tga", "ns.InstanceArt = {"]
    lines += ["    [%s] = %s," % (fq.lua_str(k), fq.lua_str(n)) for k, n in sorted(inst_made.items())]
    lines += ["}", ""]
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    print("wrote %d zone and %d instance pictures (%d scenic views, %d maps) and Journal/ZoneArt.lua"
          % (len(made), len(inst_made), kinds["view"], kinds["map"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
