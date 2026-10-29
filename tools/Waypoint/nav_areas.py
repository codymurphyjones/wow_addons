"""The named places inside buildings and caves, for the navigation data (nav_pack.py): which floors
are indoors, and the place's name (the one the game shows, and discovers, as you walk in).

    python -I tools/Waypoint/nav_areas.py <map> [...]     (prints what it finds; nav_pack.py uses it)

The game names a place inside a building or a cave by the building's group you stand in: each group
(MOGP) has a WMOGroupID, and WMOAreaTable gives its name and area by (WMOID, NameSetID, WMOGroupID),
or the building's own row (WMOGroupID -1). Only indoor groups (MOGP flag 0x2000) count: a cave's
tunnels, not the hill over them. A floor is in a group when its middle is inside the group's box
(MOGP's, turned and placed with the building, SLACK yards bigger). Where boxes overlap, the smallest
wins. A cave with no building (shaped ground) has no group: its floors stay unnamed.

Area names that are a whole zone (AreaTable ParentAreaID 0: "Elwynn Forest" on a farmhouse) aren't
kept as names; the floor still counts as indoors.
"""
import csv
import os
import struct
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import nav_extract as ne  # noqa: E402
import nav_reduce as nr  # noqa: E402

bw = ne.bw
CACHE = os.path.join(HERE, ".cache")
INDOOR = 0x2000      # MOGP flag: an indoor group
SLACK = 2.0          # yards a floor may be outside a group's box and still be in it
CORNERS = np.array([[i & 1, (i >> 1) & 1, (i >> 2) & 1] for i in range(8)], dtype=np.float64)


def _rot(rot):
    return bw._rot("y", rot[1] - 90) @ bw._rot("z", -rot[0]) @ bw._rot("x", rot[2])


def wmo_groups(casc, fdid, cache):
    """A building's (wmoID, [(group id, flags, bbox lo, bbox hi)]), its groups' headers only."""
    if fdid in cache:
        return cache[fdid]
    out = (0, [])
    root = casc.read(fdid)
    if root:
        top = {}
        for cid, off, size in bw.chunks(root):
            top.setdefault(cid, (off, size))
        if b"MOHD" in top:
            n_groups = struct.unpack_from("<I", root, top[b"MOHD"][0] + 4)[0]
            wmo_id = struct.unpack_from("<I", root, top[b"MOHD"][0] + 32)[0]
            gfids = []
            if b"GFID" in top:
                off, size = top[b"GFID"]
                gfids = list(struct.unpack_from("<%dI" % (size // 4), root, off))[:n_groups]
            groups = []
            for g in gfids:
                data = g and casc.read(g)
                if not data:
                    continue
                for cid, off, size in bw.chunks(data):
                    if cid == b"MOGP":
                        flags = struct.unpack_from("<I", data, off + 0x08)[0]
                        box = struct.unpack_from("<6f", data, off + 0x0C)
                        gid = struct.unpack_from("<I", data, off + 0x38)[0]
                        groups.append((gid, flags, np.array(box[:3]), np.array(box[3:])))
                        break
            out = (wmo_id, groups)
    cache[fdid] = out
    return out


def area_names(build):
    """(WMOAreaTable by (wmo, name set, group), AreaTable { id: (name, parent) })."""
    wmo = {}
    for r in bw.wago_table("WMOAreaTable", build):
        wmo[(int(r["WMOID"]), int(r["NameSetID"]), int(r["WMOGroupID"]))] = (int(r["AreaTableID"] or 0), r["AreaName_lang"])
    areas = {}
    with open(os.path.join(CACHE, "AreaTable.csv"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            areas[int(r["ID"])] = (r["AreaName_lang"], int(r["ParentAreaID"] or 0))
    return wmo, areas


def indoor_boxes(mapid, casc=None):
    """The map's indoor groups: [(pos, rot matrix, scale, lo, hi, area id, name)], name "" when it
    has none of its own (lo, hi: the group's box in the building's own space)."""
    from casc import Casc
    casc = casc or Casc.open()
    wmo_rows, areas = area_names(casc.version)
    maps = {int(r["ID"]): int(r["WdtFileDataID"] or 0) for r in bw.wago_table("Map", casc.version)}
    files = ne.tile_files(casc, maps[mapid])
    cache, seen, out = {}, set(), []
    for (ty, tx), (_, obj_fdid) in sorted(files.items()):
        obj = obj_fdid and casc.read(obj_fdid)
        if not obj:
            continue
        for cid, off, size in bw.chunks(obj):
            if cid != b"MODF":
                continue
            for k in range(size // 64):
                e = struct.unpack_from("<II3f3f3f3fHHHH", obj, off + k * 64)
                fdid, uid, pos, rot = e[0], e[1], e[2:5], e[5:8]
                name_set, scale = e[16], e[17]
                if uid in seen:
                    continue
                seen.add(uid)
                wmo_id, groups = wmo_groups(casc, fdid, cache)
                m = _rot(rot)
                scale = scale / 1024 if scale else 1.0
                for gid, flags, lo, hi in groups:
                    if not flags & INDOOR:
                        continue
                    row = None
                    for key in ((wmo_id, name_set, gid), (wmo_id, name_set, -1), (wmo_id, 0, gid), (wmo_id, 0, -1)):
                        row = wmo_rows.get(key)
                        if row:
                            break
                    area, name = row or (0, "")
                    if not name and area in areas:
                        name = areas[area][0]
                    if area in areas and areas[area][1] == 0 and name == areas[area][0]:
                        name = ""   # a whole zone: not a place's own name
                    out.append((np.asarray(pos, dtype=np.float64), m, scale, lo, hi, area, name))
    return out


def node_areas(N, boxes):
    """Per node, its box's index in boxes (-1 none): the smallest box its middle is in."""
    gr = N[:, 0] * 64 + N[:, 2]
    gc = N[:, 1] * 64 + N[:, 3]
    n = nr.MAX - (gr + N[:, 9] / 255.0) * nr.FINE
    w = nr.MAX - (gc + N[:, 10] / 255.0) * nr.FINE
    h = N[:, 5] / 10.0
    key = gr * 8192 + gc
    order = np.argsort(key, kind="stable")
    sk = key[order]
    best = np.full(len(N), -1, dtype=np.int64)
    vol = np.full(len(N), np.inf)
    for bi, (pos, m, scale, lo, hi, _, _) in enumerate(boxes):
        size = (hi - lo) * scale
        v = float(np.prod(np.maximum(size, 0.1)))
        # The box's corners in the world, for the cells it may cover.
        corners = lo + CORNERS * (hi - lo)
        yup = np.stack([corners[:, 0], corners[:, 2], -corners[:, 1]], 1) * scale
        p = yup @ m.T + pos
        cn, cw = nr.MAX - p[:, 2], nr.MAX - p[:, 0]
        r0 = int(np.floor((nr.MAX - cn.max() - SLACK) / nr.FINE))
        r1 = int(np.floor((nr.MAX - cn.min() + SLACK) / nr.FINE))
        c0 = int(np.floor((nr.MAX - cw.max() - SLACK) / nr.FINE))
        c1 = int(np.floor((nr.MAX - cw.min() + SLACK) / nr.FINE))
        idx = []
        for r in range(r0, r1 + 1):
            a, b = np.searchsorted(sk, r * 8192 + c0), np.searchsorted(sk, r * 8192 + c1, "right")
            if b > a:
                idx.append(order[a:b])
        if not idx:
            continue
        idx = np.concatenate(idx)
        # Back into the building's own space: the inverse of build_water.place.
        q = np.stack([nr.MAX - w[idx], h[idx], nr.MAX - n[idx]], 1) - pos
        y = (q @ m) / scale
        local = np.stack([y[:, 0], -y[:, 2], y[:, 1]], 1)
        s = SLACK / scale
        inside = np.all((local >= lo - s) & (local <= hi + s), axis=1)
        hit = idx[inside]
        hit = hit[vol[hit] > v]
        best[hit], vol[hit] = bi, v
    return best


def tables(N, boxes):
    """(per node its area's slot, 0 none; [(area id, name)]): every indoor floor has a slot, and
    floors in places with the same area and name share one."""
    best = node_areas(N, boxes)
    slots, areas = {}, []
    of_box = np.zeros(len(boxes) + 1, dtype=np.int64)
    for bi, b in enumerate(boxes):
        key = (b[5], b[6])
        if key not in slots:
            areas.append(key)
            slots[key] = len(areas)
        of_box[bi] = slots[key]
    slot = np.where(best >= 0, of_box[best], 0)
    used = np.unique(slot[slot > 0])
    # Only the areas some floor is in, renumbered.
    remap = np.zeros(len(areas) + 1, dtype=np.int64)
    remap[used] = np.arange(1, len(used) + 1)
    return remap[slot], [areas[i - 1] for i in used]


def main(argv):
    for mapid in (int(a) for a in argv):
        boxes = indoor_boxes(mapid)
        z = np.load(os.path.join(nr.NAV, "%d.graph.npz" % mapid))
        N = z["nodes"].astype(np.int64)
        slot, areas = tables(N, boxes)
        named = sum(1 for _, name in areas if name)
        print("map %d: %d indoor groups; %d of %d floors indoors, in %d places (%d named)" % (
            mapid, len(boxes), (slot > 0).sum(), len(N), len(areas), named))
        counts = np.bincount(slot, minlength=len(areas) + 1)
        for i in np.argsort(-counts[1:])[:15]:
            print("  %6d floors  %s (%d)" % (counts[i + 1], areas[i][1] or "-", areas[i][0]))


if __name__ == "__main__":
    main(sys.argv[1:])
