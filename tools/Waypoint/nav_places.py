"""Fixed places and zones for the navigation data (nav_pack.py).

Places, per map: the flight masters (TaxiNodes, wago.tools), the docks (Data/Transports.lua) and
the towns (Data/Towns.lua), each on its nearest floor (within SNAP yards). nav_walks.mjs times the
walk between every two, so Route.lua plans the walks between a landing and the next flight or dock
along the ground, not as a straight line.

Zones, per map chunk (33 yards: a map tile's MCNK area, rolled up to its top zone in AreaTable):
the zone's level is the lower quarter of its quests' levels (QuestieDB); capitals (AreaTable flag
0x100) have none. Route weighs ground in zones well above your level more (NavGrid.lua).
"""
import csv
import os
import re
import struct
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(TOOLS, "_shared"))
import nav_reduce as nr  # noqa: E402

ADDON = os.path.join(os.path.dirname(TOOLS), "addons", "Waypoint")
CACHE = os.path.join(HERE, ".cache")
SNAP = 40            # yards from a place its floor may be
CAPITAL = 0x100      # AreaTable flag of a capital city
RETIRED = re.compile(r"^zz|\bdnt\b|do not use", re.I)


def assignments():
    path = sorted(p for p in os.listdir(CACHE) if p.startswith("UiMapAssignment"))[-1]
    rows = {}
    with open(os.path.join(CACHE, path), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if r["OrderIndex"] == "0":
                rows.setdefault(int(r["UiMapID"]), []).append(r)
    import nav_stitch
    return nav_stitch.world_of_map(rows)


def raw_places(mapid, build):
    """[(kind, name, north, west, height or None)] on this map."""
    import build_water as bw
    conv = assignments()
    out = []
    for r in bw.wago_table("TaxiNodes", build):
        name = r["Name_lang"]
        if int(r["ContinentID"]) == mapid and name and not RETIRED.search(name):
            out.append(("fp", name, float(r["Pos_0"]), float(r["Pos_1"]), float(r["Pos_2"])))
    src = open(os.path.join(ADDON, "Data", "Transports.lua"), encoding="utf-8").read()
    for key, ui, x, y in re.findall(r'key = "([^"]+)",[^\n]*?mapID = (\d+),\s*x = ([\d.]+),\s*y = ([\d.]+)', src):
        w = conv(int(ui), float(x) / 100, float(y) / 100)
        if w and w[0] == mapid:
            out.append(("dock", key, w[1], w[2], None))
    towns = open(os.path.join(ADDON, "Data", "Towns.lua"), encoding="utf-8").read()
    for name, ui, x, y in re.findall(r'\{ "((?:[^"\\]|\\.)*)", (\d+), ([\d.]+), ([\d.]+),', towns):
        w = conv(int(ui), float(x), float(y))
        if w and w[0] == mapid:
            out.append(("town", name, w[1], w[2], None))
    return out


def snap_places(N, places):
    """The places with a floor near them: [(kind, name, north, west, node)]."""
    gr, gc = N[:, 0] * 64 + N[:, 2], N[:, 1] * 64 + N[:, 3]
    pn = nr.MAX - (gr + N[:, 9] / 255.0) * nr.FINE
    pw = nr.MAX - (gc + N[:, 10] / 255.0) * nr.FINE
    h = N[:, 5] / 10.0
    land = N[:, 4] == 0
    out = []
    for kind, name, n, w, z in places:
        d = np.hypot(pn - n, pw - w)
        near = np.nonzero((d <= SNAP) & land)[0]
        if len(near) == 0:
            continue
        if z is not None:
            score = d[near] + np.abs(h[near] - z) * 2
        else:
            score = d[near] - np.minimum(N[near, 8], 278) / 278 * 10   # bigger floors (the open ground) first
        out.append((kind, name, n, w, int(near[np.argmin(score)])))
    return out


def zone_tables(mapid, tiles, build):
    """Per tile, its 16x16 chunks' zone slots (bytes, 0 none), and the zones: [(id, level, capital)]."""
    import build_water as bw
    import nav_extract as ne
    from casc import Casc
    from questiedb import QuestieDB
    areas = {}
    with open(os.path.join(CACHE, "AreaTable.csv"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            areas[int(r["ID"])] = (int(r["ParentAreaID"] or 0), int(r["Flags_0"] or 0))

    def root(a):
        seen = 0
        while a in areas and areas[a][0] and seen < 10:
            a, seen = areas[a][0], seen + 1
        return a
    levels = {}
    db = QuestieDB.load()
    by = {}
    for q in db.quest_ids():
        r = db.quest(q)
        z, lv = r.get("zoneOrSort"), r.get("questLevel")
        if isinstance(z, int) and z > 0 and isinstance(lv, int) and lv > 0:
            by.setdefault(root(z), []).append(lv)
    for z, lv in by.items():
        if len(lv) >= 5:
            levels[z] = int(np.percentile(lv, 25))
    casc = Casc.open()
    maps = {int(r["ID"]): int(r["WdtFileDataID"] or 0) for r in bw.wago_table("Map", build)}
    files = ne.tile_files(casc, maps[mapid])
    slots, zones, per_tile = {}, [], {}
    for t in tiles:
        ty, tx = divmod(t, 64)
        f = files.get((ty, tx))
        data = f and casc.read(f[0])
        grid = bytearray(256)
        if data:
            for cid, off, size in ne.chunks(data):
                if cid == b"MCNK":
                    ix, iy = struct.unpack_from("<II", data, off + 4)
                    area = struct.unpack_from("<I", data, off + 0x34)[0]
                    z = root(area)
                    if z and z not in slots and len(zones) < 255:
                        cap = 1 if (areas.get(z, (0, 0))[1] & CAPITAL) else 0
                        zones.append((z, 0 if cap else levels.get(z, 0), cap))
                        slots[z] = len(zones)
                    grid[iy * 16 + ix] = slots.get(z, 0)
        per_tile[t] = bytes(grid)
    return per_tile, zones
