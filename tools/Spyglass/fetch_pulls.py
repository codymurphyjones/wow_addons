"""Data for the Dungeon Pull Planner: every floor of every dungeon and raid in
Journal/ZoneArt.lua's ns.InstanceArt, its map picture, and the mob packs on it.
Writes Journal/PullData.lua and Media/Pulls/<Key>-<floor>.blp.

Where things come from (Wowhead shows no creature coordinates inside instances,
on any branch, so spawns come from the open CMaNGOS classic world database):

  * AtlasLootClassic's data.lua (read only): the instance keys, their zone (area)
    IDs and boss NPC IDs (bosses also decide which wing owns a floor of a shared
    instance: Scarlet Monastery, Dire Maul, Blackrock Spire).
  * wago.tools DB2 exports (the game's own tables): Map (classic era names, as
    GetInstanceInfo() returns them), UiMap / UiMapGroupMember (floors and their
    names), UiMapAssignment (each floor's world rectangle and height range: turns a
    spawn's world position into its floor and 0-100 map coordinates), AreaTable
    (subzone names per floor), UiMapXMapArt / UiMapArtTile (the floor's map art,
    downloaded tile by tile), FactionTemplate (which factions are hostile).
  * CMaNGOS classic-db (github.com/cmangos/classic-db): creature spawns and templates.
  * Wowhead (forever branch) zone pages: the NPC list's levels, elite class and
    reaction override the database's where Wowhead lists the NPC.

Packs: spawns per floor, single-linkage clustered (3 map units); bosses alone.
Pictures: the 1002x668 map art scaled to 768x512 in the top-left of a 1024x512
DXT1 BLP2 with mipmaps (w/h in PullData give the used region).

Every download is cached in tools/Spyglass/.wowhead_cache (Wowhead pages paced 1.5-3 s,
retried with backoff; stops after 5 straight failures), so reruns cost nothing.

    python tools/Spyglass/fetch_pulls.py
"""
import csv
import gzip
import hashlib
import io
import json
import os
import random
import re
import site
import struct
import sys
import time

sys.path.append(site.getusersitepackages())  # Pillow / numpy from a --user install
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "_shared"))
import webfetch  # noqa: E402  (pages from a real browser: Wowhead refuses curl)

ADDON = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "addons", "Spyglass")  # tools/Spyglass/ builds addons/Spyglass/
OUT = os.path.join(ADDON, "Journal", "PullData.lua")
MEDIA = os.path.join(ADDON, "Media", "Pulls")
ZONE_ART = os.path.join(ADDON, "Journal", "ZoneArt.lua")
CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".wowhead_cache")
WOWHEAD = "https://www.wowhead.com/forever/"
WAGO = "https://wago.tools/db2/%s/csv"
CLASSIC_BUILD = "1.15.9.70003"  # classic era: only its Map table is complete on wago
CASC = "https://wago.tools/api/casc/%d"
CMANGOS = "https://raw.githubusercontent.com/cmangos/classic-db/master/Full_DB/ClassicDB_1_12_1_z2815.sql.gz"
# A plain UA: Wowhead answers longer custom ones with an empty HTTP 202 bot
# challenge, and full browser strings with 403.
UA = "Mozilla/5.0"
PACE = (1.5, 3.0)   # seconds between Wowhead requests
FILE_PACE = 0.4     # between wago / GitHub downloads
LINK = 3.0          # pack clustering distance, map units (0-100)
TEX_W, TEX_H = 1024, 512
USED_W, USED_H = 768, 512   # the 1002x668 art keeps its 3:2 shape
ART_W, ART_H = 1002, 668

ATLAS_PATHS = [
    os.path.join(ADDON, "..", "AtlasLootClassic_DungeonsAndRaids", "data.lua"),
    r"Z:\Games\World of Warcraft\_classic_beta_\Interface\AddOns\AtlasLootClassic_DungeonsAndRaids\data.lua",
]

# Zone (area) ID -> instance map ID (Map.db; GetInstanceInfo()'s 8th value).
INSTANCE_MAP = {
    209: 33, 717: 34, 1581: 36, 718: 43, 491: 47, 719: 48, 1337: 70, 721: 90, 1477: 109,
    722: 129, 796: 189, 1176: 209, 978: 209, 1583: 229, 1584: 230, 2159: 249, 2057: 289,
    1977: 309, 2017: 329, 2100: 349, 2437: 389, 2717: 409, 2557: 429, 2677: 469,
    3429: 509, 3428: 531, 3456: 533,
}

# Shared instances: floor name -> wing key, where the bosses alone can't tell
# (floors with no boss of their own). Checked against the boss counts printed.
WING_FLOORS = {
    "Chamber of Battle": "UpperBlackrockSpire",  # Hall of Binding, the Rookery: UBRS
    "Capital Gardens": "DireMaulWest",           # Tendris Warpwood's gardens
}


# ---------------------------------------------------------------------------
# Fetching: paced, cached, retried (pattern from fetch_wowhead_quests.py)
# ---------------------------------------------------------------------------

class RetryLater(Exception):
    pass


def download(url, binary=False):
    # A real browser session (tools/_shared/webfetch.py): Wowhead refuses curl and urllib.
    code, body = webfetch.fetch(url, binary=binary, timeout=120)
    if code in (403, 429) or code >= 500 or code == 0:
        raise RetryLater("HTTP %d" % code)
    if code == 404:
        return None
    if code == 202 or not body.strip():
        raise RetryLater("HTTP %d, empty answer" % code)  # a bot challenge: never cached
    return body


class Fetcher:
    def __init__(self):
        self.last, self.requests, self.failures = 0.0, 0, 0
        os.makedirs(CACHE, exist_ok=True)

    def get(self, url, binary=False, name=None):
        path = os.path.join(CACHE, name or hashlib.sha1(url.encode("utf-8")).hexdigest() + ".html")
        if os.path.exists(path) and os.path.getsize(path) > 0:  # empty: a refused answer
            if binary:
                with open(path, "rb") as f:
                    return f.read()
            with open(path, encoding="utf-8") as f:
                return f.read()
        wowhead = "wowhead.com" in url
        delay = random.uniform(*PACE) if wowhead else FILE_PACE
        for _ in range(6):
            wait = self.last + delay - time.time()
            if wait > 0:
                time.sleep(wait)
            self.last = time.time()
            self.requests += 1
            try:
                data = download(url, binary)
            except RetryLater as e:
                print("  %s (%s); waiting %.0fs" % (url, e, max(delay, 2) * 4), flush=True)
                delay = max(delay, 2) * 4
                continue
            self.failures = 0
            if data is None:
                return None
            if binary:
                with open(path, "wb") as f:
                    f.write(data)
            else:
                with open(path, "w", encoding="utf-8", newline="\n") as f:
                    f.write(data)
            return data
        self.failures += 1
        if self.failures >= 5:
            raise SystemExit("Downloads keep failing; stopped. Rerun later: the cache keeps what's done.")
        return None

    def table(self, name, build=None):
        url = WAGO % name + ("?build=" + build if build else "")
        text = self.get(url) or ""
        return list(csv.DictReader(io.StringIO(text)))


# ---------------------------------------------------------------------------
# Wowhead's JS literals (from fetch_wowhead_quests.py)
# ---------------------------------------------------------------------------

KEY = re.compile(r"([A-Za-z_]\w*)(\s*:)")


def js_literal(text):
    out, i, n, last = [], 0, len(text), ""
    while i < n:
        c = text[i]
        if c == '"':
            j = i + 1
            while text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            out.append(text[i:j + 1])
            last, i = '"', j + 1
            continue
        if last in ("{", ","):
            m = KEY.match(text, i)
            if m:
                out.append('"%s"%s' % (m.group(1), m.group(2)))
                last, i = ":", m.end()
                continue
        out.append(c)
        if not c.isspace():
            last = c
        i += 1
    return json.loads("".join(out))


def balanced(s, i):
    depth, j, in_str = 0, i, False
    while j < len(s):
        c = s[j]
        if in_str:
            if c == "\\":
                j += 1
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c in "[{":
            depth += 1
        elif c in "]}":
            depth -= 1
            if depth == 0:
                return s[i:j + 1]
        j += 1
    raise ValueError("unbalanced literal")


def zone_npcs(fetcher, area):
    """{ npcID: row } from the Wowhead zone page's NPC list."""
    text = fetcher.get(WOWHEAD + "zone=%d" % area) or ""
    i = text.find("new Listview({template: 'npc'")
    if i < 0:
        return {}
    j = text.index("data:", i)
    try:
        rows = js_literal(balanced(text, text.index("[", j)))
    except ValueError:
        return {}
    return {r["id"]: r for r in rows}


# ---------------------------------------------------------------------------
# Inputs
# ---------------------------------------------------------------------------

def instance_keys():
    text = open(ZONE_ART, encoding="utf-8").read()
    block = text[text.index("ns.InstanceArt"):]
    return re.findall(r'\["([^"]+)"\]\s*=', block[:block.index("}")])


def atlas_instances():
    """{ key: (area, [boss npcIDs]) } from AtlasLootClassic."""
    for path in ATLAS_PATHS:
        if os.path.exists(path):
            text = open(path, encoding="utf-8").read()
            break
    else:
        raise SystemExit("AtlasLootClassic_DungeonsAndRaids/data.lua not found")
    heads = list(re.finditer(r'^data\["([^"]+)"\]\s*=\s*\{', text, re.M))
    out = {}
    for n, m in enumerate(heads):
        body = text[m.end():heads[n + 1].start() if n + 1 < len(heads) else len(text)]
        mid = re.search(r"MapID\s*=\s*(\d+)", body)
        bosses = []
        for b in re.finditer(r"npcID\s*=\s*(\{[^}]*\}|\d+)", body):
            bosses += [int(x) for x in re.findall(r"\d+", b.group(1))]
        if mid:
            out[m.group(1)] = (int(mid.group(1)), bosses)
    return out


def sql_rows(text, table):
    """Value tuples of every INSERT INTO `table`."""
    rows = []
    for m in re.finditer(r"INSERT INTO `%s` VALUES " % table, text):
        i, n = m.end(), len(text)
        while i < n and text[i] == "(":
            row, i = parse_tuple(text, i + 1)
            rows.append(row)
            if text[i] == ",":
                i += 1
            while text[i] in "\r\n ":
                i += 1
            if text[i] == ";":
                break
    return rows


def parse_tuple(s, i):
    vals, cur = [], []
    while True:
        c = s[i]
        if c == "'":
            j, buf = i + 1, []
            while True:
                if s[j] == "\\":
                    buf.append(s[j + 1])
                    j += 2
                elif s[j] == "'" and s[j + 1] == "'":
                    buf.append("'")
                    j += 2
                elif s[j] == "'":
                    break
                else:
                    buf.append(s[j])
                    j += 1
            vals.append("".join(buf))
            i = j + 1
            cur = None
        elif c in ",)":
            if cur is not None:
                tok = "".join(cur).strip()
                vals.append(None if tok == "NULL" else (float(tok) if "." in tok or "e" in tok.lower() else int(tok)))
            cur = []
            i += 1
            if c == ")":
                return vals, i
        else:
            if cur is not None:
                cur.append(c)
            i += 1


def columns(text, table):
    m = re.search(r"CREATE TABLE `%s` \((.*?)\n\) ENGINE" % table, text, re.S)
    return [ln.strip().split()[0].strip("`") for ln in m.group(1).split("\n") if ln.strip().startswith("`")]


def world_db(fetcher, maps):
    data = fetcher.get(CMANGOS, binary=True, name="cmangos-classic-db.sql.gz")
    text = gzip.decompress(data).decode("utf-8", "replace")
    ccol = columns(text, "creature")
    spawns = [dict(zip(ccol, r)) for r in sql_rows(text, "creature")]
    spawns = [s for s in spawns if s["map"] in maps]
    entry = {}
    for g, e in sql_rows(text, "creature_spawn_entry"):
        entry.setdefault(g, e)
    for s in spawns:
        if not s["id"]:
            s["id"] = entry.get(s["guid"], 0)
    # Spawn groups: spawns whose entry is drawn from the group's list (bosses with
    # their adds, random rares), and groups where only MaxCount spots are used.
    groups = {r[0]: r for r in sql_rows(text, "spawn_group") if r[2] == 0}
    members, entries = {}, {}
    for gid, guid, _slot, _chance in sql_rows(text, "spawn_group_spawn"):
        if gid in groups:
            members.setdefault(gid, []).append(guid)
    for gid, e, lo, hi, chance in sql_rows(text, "spawn_group_entry"):
        if gid in groups:
            entries.setdefault(gid, []).append((e, lo, hi, chance))
    by_guid = {s["guid"]: s for s in spawns}
    drop = set()
    for gid, guids in members.items():
        guids = sorted(g for g in guids if g in by_guid)
        cap = groups[gid][3]
        if cap and cap < len(guids):
            drop.update(guids[cap:])
            guids = guids[:cap]
        free = [g for g in guids if not by_guid[g]["id"]]
        if not free or gid not in entries:
            continue
        pool = sorted(entries[gid], key=lambda r: (-r[1], -r[3], r[0]))
        picks = [e for e, lo, hi, _ in pool for _ in range(lo)]
        while len(picks) < len(free):
            room = [e for e, lo, hi, _ in pool if not hi or picks.count(e) < hi]
            if not room:
                break
            picks.append(room[(len(picks)) % len(room)])
        for g, e in zip(free, picks):
            by_guid[g]["id"] = e
    spawns = [s for s in spawns if s["guid"] not in drop and s["id"]]
    tcol = columns(text, "creature_template")
    keep = ("Entry", "Name", "MinLevel", "MaxLevel", "Faction", "CreatureType", "NpcFlags",
            "UnitFlags", "ExtraFlags", "Rank")
    templates = {}
    for r in sql_rows(text, "creature_template"):
        t = dict(zip(tcol, r))
        templates[t["Entry"]] = {k: t[k] for k in keep}
    return spawns, templates


# ---------------------------------------------------------------------------
# Floors
# ---------------------------------------------------------------------------

class Floors:
    def __init__(self, fetcher):
        self.uimap = {int(r["ID"]): r for r in fetcher.table("UiMap")}
        self.group = {int(r["UiMapID"]): r for r in fetcher.table("UiMapGroupMember")}
        self.areas = {int(r["ID"]): r["AreaName_lang"] for r in fetcher.table("AreaTable")}
        self.assign = {}
        for r in fetcher.table("UiMapAssignment"):
            m = int(r["MapID"])
            row = {k: float(r[k]) for k in ("UiMin_0", "UiMin_1", "UiMax_0", "UiMax_1", "Region_0", "Region_1",
                                             "Region_2", "Region_3", "Region_4", "Region_5")}
            row.update(uimap=int(r["UiMapID"]), area=int(r["AreaID"]), order=int(r["OrderIndex"]))
            self.assign.setdefault(m, []).append(row)
        self.art = {}
        for r in fetcher.table("UiMapXMapArt"):
            if r["PhaseID"] == "0":
                self.art.setdefault(int(r["UiMapID"]), int(r["UiMapArtID"]))
        self.tiles = {}
        for r in fetcher.table("UiMapArtTile"):
            if r["LayerIndex"] == "0":
                self.tiles.setdefault(int(r["UiMapArtID"]), []).append(
                    (int(r["RowIndex"]), int(r["ColIndex"]), int(r["FileDataID"])))

    def maps_of(self, mapid):
        """The instance's floors in order: dungeon maps (type 4), else its orphan map (type 6)."""
        ids = {a["uimap"] for a in self.assign.get(mapid, [])}
        floors = [u for u in ids if self.uimap.get(u, {}).get("Type") == "4"]
        if not floors:
            floors = [u for u in ids if self.uimap.get(u, {}).get("Type") == "6"]
        return sorted(floors, key=lambda u: (int(self.group[u]["FloorIndex"]) if u in self.group else 0, u))

    def floor_name(self, u):
        g = self.group.get(u)
        return g["Name_lang"] if g and g["Name_lang"] else self.uimap[u]["Name_lang"]

    def subzones(self, u, own):
        names = []
        for a in self.assign_rows(u):
            n = self.areas.get(a["area"])
            if a["area"] and n and n not in names and n != own:
                names.append(n)
        return names

    def assign_rows(self, u):
        return [a for rows in self.assign.values() for a in rows if a["uimap"] == u]

    def candidates(self, mapid, x, y, z, allowed):
        """{ uiMap: (u, v) 0-100 } for every floor whose rectangle (and height range) holds the
        position. The game picks among them by the WMO group the player stands in, which a
        spawn doesn't record, so several floors can qualify (see pick_floors)."""
        out, near = {}, {}
        for a in self.assign.get(mapid, []):
            if a["uimap"] not in allowed:
                continue
            x0, y0, z0, x1, y1, z1 = (a["Region_%d" % i] for i in range(6))
            if not (x0 <= x <= x1 and y0 <= y <= y1):
                continue
            u = a["UiMin_0"] + (a["Region_4"] - y) / (a["Region_4"] - a["Region_1"]) * (a["UiMax_0"] - a["UiMin_0"])
            v = a["UiMin_1"] + (a["Region_3"] - x) / (a["Region_3"] - a["Region_0"]) * (a["UiMax_1"] - a["UiMin_1"])
            if not (0 <= u <= 1 and 0 <= v <= 1):
                continue
            (out if z0 <= z <= z1 else near)[a["uimap"]] = (u * 100, v * 100)
        return out or near

    def world_rect(self, u):
        """World X at the map's top and bottom edge, world Y at its left and right edge."""
        rows = self.assign_rows(u)
        a = max(rows, key=lambda a: (a["UiMax_0"] - a["UiMin_0"]) * (a["UiMax_1"] - a["UiMin_1"]))
        sy = (a["Region_4"] - a["Region_1"]) / (a["UiMax_0"] - a["UiMin_0"])
        sx = (a["Region_3"] - a["Region_0"]) / (a["UiMax_1"] - a["UiMin_1"])
        left = a["Region_4"] + a["UiMin_0"] * sy
        top = a["Region_3"] + a["UiMin_1"] * sx
        return top, left, top - sx, left - sy


# ---------------------------------------------------------------------------
# Pictures: map art -> DXT1 BLP2 with mipmaps
# ---------------------------------------------------------------------------

ARTS = {}


def floor_art(fetcher, floors, u):
    """The floor's 1002x668 map art (RGB), or None."""
    if u in ARTS:
        return ARTS[u]
    tiles = floors.tiles.get(floors.art.get(u)) or []
    canvas = Image.new("RGB", (1024, 768))
    for row, col, fdid in tiles:
        data = fetcher.get(CASC % fdid, binary=True, name="casc-%d.blp" % fdid)
        if not data:
            tiles = None
            break
        canvas.paste(Image.open(io.BytesIO(data)).convert("RGB"), (col * 256, row * 256))
    ARTS[u] = canvas.crop((0, 0, ART_W, ART_H)) if tiles else None
    return ARTS[u]


def floor_image(fetcher, floors, u):
    art = floor_art(fetcher, floors, u)
    if art is None:
        return None
    tex = Image.new("RGB", (TEX_W, TEX_H))
    tex.paste(art.resize((USED_W, USED_H), Image.LANCZOS), (0, 0))
    return tex


LIT = {}


def lit(fetcher, floors, u):
    """How brightly the floor's art is drawn around each pixel, in standard deviations
    from its middle: a dungeon floor map draws its own rooms light and the floors
    above and below dimmed, so this tells which floor a point belongs to."""
    if u not in LIT:
        art = floor_art(fetcher, floors, u)
        if art is None:
            LIT[u] = None
        else:
            from PIL import ImageFilter
            a = np.asarray(art.convert("L").filter(ImageFilter.BoxBlur(4)), dtype=np.float32)
            LIT[u] = (a - np.median(a)) / max(float(a.std()), 1.0)
    return LIT[u]


def pick_floors(fetcher, floors, pts):
    """pts: [(spawn, { uiMap: (u, v) })]. Spawns standing over several floors are grouped
    with their neighbours (20 yards across, 6 up or down) and each group goes to the
    floor whose art is lit brightest under it. Returns [(uiMap, u, v, npc)]."""
    out, open_ = [], []
    for s, cands in pts:
        if len(cands) == 1:
            (u, (x, y)), = cands.items()
            out.append((u, x, y, s["id"]))
        else:
            open_.append((s, cands))
    n = len(open_)
    parent = list(range(n))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for i in range(n):
        a = open_[i][0]
        for j in range(i + 1, n):
            b = open_[j][0]
            if abs(a["position_z"] - b["position_z"]) <= 6 and \
                    (a["position_x"] - b["position_x"]) ** 2 + (a["position_y"] - b["position_y"]) ** 2 <= 400:
                parent[find(i)] = find(j)
    groups = {}
    for i in range(n):
        groups.setdefault(find(i), []).append(open_[i])
    for members in groups.values():
        score = {}
        for s, cands in members:
            for u, (x, y) in cands.items():
                m = lit(fetcher, floors, u)
                v = -9.0 if m is None else float(m[min(ART_H - 1, int(y / 100 * ART_H)), min(ART_W - 1, int(x / 100 * ART_W))])
                score[u] = score.get(u, 0.0) + v
        best = max(score, key=lambda u: (score[u], -u))
        for s, cands in members:
            if best in cands:
                out.append((best, cands[best][0], cands[best][1], s["id"]))
            else:
                u = max(cands, key=lambda u: score.get(u, -1e9))
                out.append((u, cands[u][0], cands[u][1], s["id"]))
    return out


def to565(c):
    c = np.clip(np.rint(c), 0, 255).astype(np.int32)
    return ((c[..., 0] >> 3) << 11) | ((c[..., 1] >> 2) << 5) | (c[..., 2] >> 3)


def from565(v):
    r = (v >> 11) & 31
    g = (v >> 5) & 63
    b = v & 31
    return np.stack([(r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)], -1).astype(np.float32)


def dxt1(img):
    """DXT1 blocks of an RGB image (sides multiples of 4, or padded)."""
    a = np.asarray(img, dtype=np.float32)
    h, w = a.shape[:2]
    ph, pw = max(4, (h + 3) // 4 * 4), max(4, (w + 3) // 4 * 4)
    if (ph, pw) != (h, w):
        a = np.pad(a, ((0, ph - h), (0, pw - w), (0, 0)), mode="edge")
    blocks = a.reshape(ph // 4, 4, pw // 4, 4, 3).transpose(0, 2, 1, 3, 4).reshape(-1, 16, 3)
    # Endpoints along the block's principal axis (inset a little).
    mean = blocks.mean(1, keepdims=True)
    d = blocks - mean
    cov = np.einsum("nki,nkj->nij", d, d)
    axis = np.ones((len(blocks), 3), np.float32)
    for _ in range(8):
        axis = np.einsum("nij,nj->ni", cov, axis)
        axis /= np.maximum(np.linalg.norm(axis, axis=1, keepdims=True), 1e-6)
    proj = np.einsum("nki,ni->nk", d, axis)
    lo, hi = proj.min(1), proj.max(1)
    inset = (hi - lo) / 32
    c0 = mean[:, 0] + axis * (hi - inset)[:, None]
    c1 = mean[:, 0] + axis * (lo + inset)[:, None]
    e0, e1 = to565(c0), to565(c1)
    swap = e0 < e1
    e0, e1 = np.where(swap, e1, e0), np.where(swap, e0, e1)
    same = e0 == e1
    e0 = np.where(same & (e0 < 0xFFFF), e0 + 1, e0)  # keep four-colour mode
    e1 = np.where(same & (e0 == e1), e1 - 1, e1)
    p0, p1 = from565(e0), from565(e1)
    pal = np.stack([p0, p1, (2 * p0 + p1) / 3, (p0 + 2 * p1) / 3], 1)
    dist = ((blocks[:, :, None, :] - pal[:, None, :, :]) ** 2).sum(-1)
    idx = dist.argmin(-1).astype(np.uint32)
    bits = (idx << (2 * np.arange(16, dtype=np.uint32))).sum(1).astype(np.uint32)
    out = np.zeros(len(blocks), dtype=[("c0", "<u2"), ("c1", "<u2"), ("bits", "<u4")])
    out["c0"], out["c1"], out["bits"] = e0, e1, bits
    return out.tobytes()


def save_blp(img, path):
    mips, level = [], img
    while True:
        mips.append(dxt1(level))
        if level.size == (1, 1):
            break
        level = level.resize((max(1, level.size[0] // 2), max(1, level.size[1] // 2)), Image.BOX)
    header_size = 4 + 4 + 4 + 8 + 64 + 64 + 1024
    offsets, sizes, pos = [], [], header_size
    for m in mips:
        offsets.append(pos)
        sizes.append(len(m))
        pos += len(m)
    offsets += [0] * (16 - len(offsets))
    sizes += [0] * (16 - len(sizes))
    with open(path, "wb") as f:
        f.write(b"BLP2")
        f.write(struct.pack("<I", 1))                 # type: BLP2 with data
        f.write(struct.pack("<BBBB", 2, 0, 0, 1))     # DXT, no alpha, DXT1, has mipmaps
        f.write(struct.pack("<II", img.size[0], img.size[1]))
        f.write(struct.pack("<16I", *offsets))
        f.write(struct.pack("<16I", *sizes))
        f.write(b"\0" * 1024)                          # palette (unused)
        for m in mips:
            f.write(m)


# ---------------------------------------------------------------------------
# Packs
# ---------------------------------------------------------------------------

def clusters(points):
    """Single-linkage groups of [(x, y, npc)] within LINK."""
    n = len(points)
    parent = list(range(n))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for i in range(n):
        for j in range(i + 1, n):
            if (points[i][0] - points[j][0]) ** 2 + (points[i][1] - points[j][1]) ** 2 <= LINK * LINK:
                parent[find(i)] = find(j)
    groups = {}
    for i in range(n):
        groups.setdefault(find(i), []).append(points[i])
    return list(groups.values())


def hostile_factions(fetcher):
    """Faction templates players can fight: hostile or neutral, i.e. not friendly to players
    and not aligned with the Alliance or the Horde (city guards and the like). Many
    hostile mobs (wolves: "Prey") are hostile only through their faction's default
    reputation, so friendliness is what is tested, not the enemy masks."""
    out = set()
    for r in fetcher.table("FactionTemplate"):
        group, friend = int(r["FactionGroup"]), int(r["FriendGroup"])
        if group & 7 or friend & 7:
            continue
        out.add(int(r["ID"]))
    return out


def fmt(v):
    s = "%.1f" % v
    return "0.0" if s == "-0.0" else s


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def file_name(key, n):
    return re.sub(r"[^A-Za-z0-9]", "", key) + "-%d" % n


# ---------------------------------------------------------------------------

def main():
    fetcher = Fetcher()
    os.makedirs(MEDIA, exist_ok=True)
    keys = instance_keys()
    atlas = atlas_instances()
    missing = [k for k in keys if k not in atlas]
    if missing:
        print("not in AtlasLoot:", missing)
    floors = Floors(fetcher)
    names = {int(r["ID"]): r["MapName_lang"] for r in fetcher.table("Map", CLASSIC_BUILD)}
    hostile = hostile_factions(fetcher)

    by_map = {}
    for k in keys:
        if k in atlas:
            by_map.setdefault(INSTANCE_MAP[atlas[k][0]], []).append(k)
    spawns, templates = world_db(fetcher, set(by_map))
    print("%d spawns in %d instances" % (len(spawns), len(by_map)))

    wh = {}
    for k in keys:
        if k in atlas and atlas[k][0] not in wh:
            wh[atlas[k][0]] = zone_npcs(fetcher, atlas[k][0])

    npcs, out, report, total_bytes = {}, {}, [], 0
    for mapid, mkeys in sorted(by_map.items()):
        area = atlas[mkeys[0]][0]
        listed = wh.get(area, {})
        boss_of = {}
        for k in mkeys:
            for b in atlas[k][1]:
                boss_of.setdefault(b, k)
        maps = floors.maps_of(mapid)
        allowed = set(maps)

        # Spawns -> floors.
        pts = {u: [] for u in maps}
        skipped, placed = 0, []
        for s in spawns:
            if s["map"] != mapid:
                continue
            t = templates.get(s["id"])
            if not t or not keep_npc(t, listed.get(s["id"]), hostile, s["id"] in boss_of):
                skipped += 1
                continue
            cands = floors.candidates(mapid, s["position_x"], s["position_y"], s["position_z"], allowed)
            if not cands:
                skipped += 1
                continue
            placed.append((s, cands))
        for u, x, y, nid in pick_floors(fetcher, floors, placed):
            pts[u].append((x, y, nid))

        # Floors -> wings (shared instances): by where each wing's bosses stand.
        owner = {}
        for u in maps:
            if len(mkeys) == 1:
                owner[u] = mkeys[0]
                continue
            votes = {}
            for x, y, nid in pts[u]:
                if nid in boss_of:
                    votes[boss_of[nid]] = votes.get(boss_of[nid], 0) + 1
            fname = floors.floor_name(u)
            owner[u] = WING_FLOORS.get(fname) or (max(votes, key=votes.get) if votes else mkeys[0])
            print("  %-26s floor %-28s bosses %s -> %s" % (names.get(mapid), fname, votes, owner[u]))

        for k in mkeys:
            kfloors = [u for u in maps if owner[u] == k]
            entry = {"name": names.get(mapid), "instanceID": mapid, "area": area, "uiMap": kfloors,
                     "floors": [], "packs": []}
            for n, u in enumerate(kfloors, 1):
                fname = file_name(k, n)
                path = os.path.join(MEDIA, fname + ".blp")
                img = floor_image(fetcher, floors, u)
                if img is None:
                    report.append("%s floor %d (%d): no map art" % (k, n, u))
                else:
                    save_blp(img, path)
                    total_bytes += os.path.getsize(path)
                entry["floors"].append({
                    "file": fname, "w": USED_W, "h": USED_H, "name": floors.floor_name(u), "uiMap": u,
                    "subzones": floors.subzones(u, names.get(mapid)), "world": floors.world_rect(u)})
                bosses = [p for p in pts[u] if p[2] in boss_of or (listed.get(p[2]) or {}).get("classification") == 3]
                trash = [p for p in pts[u] if p not in bosses]
                packs = [(g, None) for g in clusters(trash)] + [([b], b[2]) for b in bosses]
                for g, boss in packs:
                    counts = {}
                    for p in g:
                        counts[p[2]] = counts.get(p[2], 0) + 1
                        npcs[p[2]] = npc_row(templates[p[2]], listed.get(p[2]), p[2] in boss_of)
                    entry["packs"].append((n, sum(p[0] for p in g) / len(g), sum(p[1] for p in g) / len(g),
                                           sorted(counts.items(), key=lambda c: (-c[1], c[0])), boss))
            entry["packs"].sort(key=lambda p: (p[0], round(p[2], 1), round(p[1], 1), p[3]))
            seen = {p[2] for f in kfloors for p in pts[f]}
            lost = [b for b in atlas[k][1] if b not in seen]
            if lost:
                report.append("%s: bosses without a spawn (scripted/summoned): %s" % (k, lost))
            out[k] = entry
            print("%-28s %d floors, %d packs (%d skipped spawns in map)" % (k, len(kfloors), len(entry["packs"]), skipped))

    write(out, npcs)
    print("wrote Journal/PullData.lua: %d instances, %d packs, %d NPCs, %d floors, images %.1f MB"
          % (len(out), sum(len(e["packs"]) for e in out.values()), len(npcs),
             sum(len(e["floors"]) for e in out.values()), total_bytes / 1048576.0))
    for r in report:
        print("  gap:", r)
    print("%d downloads this run" % fetcher.requests)
    return 0


def keep_npc(t, w, hostile, boss):
    if boss:
        return True
    if w is not None and w.get("react") and all(r is not None and r >= 0 for r in w["react"]):
        return False  # Wowhead: friendly or neutral to both sides
    if t["CreatureType"] == 8 or t["NpcFlags"] or t["UnitFlags"] & 0x02000000 or t["ExtraFlags"] & 0x80:
        return False  # critters, vendors / gossip, unselectable, invisible triggers
    if re.search(r"trigger|\bDND\b|\[|invisible|stalker|dummy", t["Name"], re.I):
        return False
    return t["Faction"] in hostile


def npc_row(t, w, boss):
    name = (w or {}).get("name") or t["Name"]
    lo = (w or {}).get("minlevel") or t["MinLevel"]
    hi = (w or {}).get("maxlevel") or t["MaxLevel"]
    cls = (w or {}).get("classification")
    elite = (cls in (1, 2, 3)) if cls is not None else t["Rank"] in (1, 2, 3)
    return name, lo, hi, 1 if elite or boss else 0, boss or cls == 3


def write(out, npcs):
    L = [
        "local _, ns = ...",
        "-- Generated by tools/Spyglass/fetch_pulls.py. Do not edit.",
        "-- npcs[id] = { name, minLevel, maxLevel, elite (1/0), boss (1/nil) }",
        "-- instances[key]: name (GetInstanceInfo), instanceID (Map.db), area (zone ID), uiMap (floor uiMapIDs);",
        "--   floors[i]: file (Media\\Pulls\\<file>.blp, 1024x512; the map fills w x h from the top left),",
        "--     name, uiMap, subzones, world = { X at top edge, Y at left edge, X at bottom edge, Y at right edge }",
        "--   packs[i] = { floor, x, y (0-100 map coordinates), { {npcID, count}, ... }, boss = npcID }",
        "ns.PullData = {",
        "  npcs = {",
    ]
    for nid in sorted(npcs):
        name, lo, hi, elite, boss = npcs[nid]
        L.append("    [%d] = { %s, %d, %d, %d%s }," % (nid, lua_str(name), lo, hi, elite, ", 1" if boss else ""))
    L += ["  },", "  instances = {"]
    for k in sorted(out):
        e = out[k]
        L.append("    [%s] = {" % lua_str(k))
        L.append("      name = %s, instanceID = %d, area = %d," % (lua_str(e["name"] or k), e["instanceID"], e["area"]))
        L.append("      uiMap = { %s }," % ", ".join(str(u) for u in e["uiMap"]))
        L.append("      floors = {")
        for f in e["floors"]:
            L.append("        { file = %s, w = %d, h = %d, name = %s, uiMap = %d, subzones = { %s }, world = { %s } },"
                     % (lua_str(f["file"]), f["w"], f["h"], lua_str(f["name"]), f["uiMap"],
                        ", ".join(lua_str(s) for s in f["subzones"]), ", ".join(fmt(v) for v in f["world"])))
        L.append("      },")
        L.append("      packs = {")
        for floor, x, y, mobs, boss in e["packs"]:
            ms = ", ".join("{ %d, %d }" % m for m in mobs)
            L.append("        { %d, %s, %s, { %s }%s }," % (floor, fmt(x), fmt(y), ms, ", boss = %d" % boss if boss else ""))
        L.append("      },")
        L.append("    },")
    L += ["  },", "}", ""]
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(L))


if __name__ == "__main__":
    sys.exit(main())
