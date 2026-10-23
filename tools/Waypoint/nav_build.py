"""Waypoint's navigation data (Data/Nav<map>.lua) for every world map players walk, from the game's
own files: each map tile's ground is extracted (nav_extract.py), baked with Recast (nav_bake.mjs,
Node and @recast-navigation from the repo's package.json), reduced to nodes (nav_reduce.py), all
in parallel; then each map's tiles are joined and pruned to where players can get to
(nav_stitch.py) and packed (nav_pack.py). Working files go to tools/Waypoint/.nav (rebuilt from
the game; not packed into the datasets).

    python -I tools/Waypoint/nav_build.py [--maps 0,1] [--tiles 48_30,48_31] [--force] [--jobs N] [--clean]

A tile is done again only when its nodes are older than the scripts that make them (or with
--force). --clean deletes each tile's soup and heightfield once reduced (they're large: about
15 GB for both continents).
"""
import argparse
import multiprocessing as mp
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import nav_extract as ne  # noqa: E402
import nav_reduce as nr  # noqa: E402

NAV = ne.NAV_DIR
ROOT = os.path.dirname(os.path.dirname(HERE))
SCRIPTS = [os.path.join(HERE, f) for f in ("nav_extract.py", "nav_bake.mjs", "build_water.py")]
REDUCE = os.path.join(HERE, "nav_reduce.py")

_w = {}


def _init():
    from casc import Casc
    casc = Casc.open()
    build = casc.version
    _w["casc"] = casc
    _w["liq"] = ne.bw.Liquids(build)
    _w["maps"] = {int(r["ID"]): int(r["WdtFileDataID"] or 0) for r in ne.bw.wago_table("Map", build)}
    _w["files"] = {}
    _w["caches"] = ({}, {})


def _extract(job):
    mapid, ty, tx, out = job
    files = _w["files"].get(mapid)
    if files is None:
        files = _w["files"][mapid] = ne.tile_files(_w["casc"], _w["maps"][mapid])
    # Caches of buildings and models grow without end over a continent: start again now and then.
    if len(_w["caches"][0]) > 3000 or len(_w["caches"][1]) > 20000:
        _w["caches"] = ({}, {})
    try:
        res = ne.extract(_w["casc"], files, _w["liq"], ty, tx, out, _w["caches"])
        return job, res, None
    except Exception as e:  # one bad tile shouldn't stop the bake
        return job, None, repr(e)


def _reduce(name):
    try:
        return name, nr.reduce_tile(name), None
    except Exception as e:
        return name, None, repr(e)


def stale(path, newest):
    return not os.path.exists(path) or os.path.getmtime(path) < newest


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--maps", default=",".join(str(m) for m in ne.bw.MAPS))
    ap.add_argument("--tiles", default="")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 4) - 2))
    ap.add_argument("--clean", action="store_true", help="delete each tile's soup and heightfield once reduced")
    ap.add_argument("--no-pack", action="store_true", help="stop after reducing the tiles (no stitch, no Data/Nav*.lua)")
    args = ap.parse_args(argv)
    os.makedirs(NAV, exist_ok=True)
    newest = max(os.path.getmtime(p) for p in SCRIPTS)
    from casc import Casc
    casc = Casc.open()
    maps = {int(r["ID"]): int(r["WdtFileDataID"] or 0) for r in ne.bw.wago_table("Map", casc.version)}
    wanted = {tuple(int(x) for x in t.split("_")) for t in args.tiles.split(",") if t}
    jobs = []
    for mapid in (int(m) for m in args.maps.split(",")):
        for ty, tx in sorted(ne.tile_files(casc, maps[mapid])):
            if wanted and (ty, tx) not in wanted:
                continue
            out = os.path.join(NAV, "%d_%d_%d.bin" % (mapid, ty, tx))
            # Done already: its nodes are newer than every script (its soup may be cleaned away).
            done = not stale(out[:-4] + ".npz", max(newest, os.path.getmtime(REDUCE)))
            if args.force or (stale(out, newest) and not done):
                jobs.append((mapid, ty, tx, out))
    t0 = time.time()
    print("extracting %d tiles with %d workers" % (len(jobs), args.jobs))
    failed = []
    if jobs:
        with mp.Pool(args.jobs, initializer=_init) as pool:
            for i, (job, res, err) in enumerate(pool.imap_unordered(_extract, jobs, chunksize=4), 1):
                if err:
                    failed.append((job, err))
                if i % 50 == 0 or i == len(jobs):
                    print("  %d/%d extracted (%.0fs)" % (i, len(jobs), time.time() - t0), flush=True)
    for job, err in failed:
        print("  extract failed %d_%d_%d: %s" % (job[0], job[1], job[2], err))

    # Bake every soup whose heightfield is missing or older, split over node processes.
    bake = []
    for name in sorted(os.listdir(NAV)):
        if not name.endswith(".bin"):
            continue
        parts = name[:-4].split("_")
        if int(parts[0]) not in {int(m) for m in args.maps.split(",")}:
            continue
        if wanted and (int(parts[1]), int(parts[2])) not in wanted:
            continue
        src = os.path.join(NAV, name)
        out = src[:-4] + ".chf"
        if args.force or stale(out, max(newest, os.path.getmtime(src))):
            bake.append((src, out))
    print("baking %d tiles" % len(bake))
    procs = []
    n = max(1, min(args.jobs, len(bake)))
    for k in range(n):
        part = bake[k::n]
        if not part:
            continue
        lst = os.path.join(NAV, "bake_%d.txt" % k)
        with open(lst, "w", encoding="utf-8") as f:
            f.write("\n".join("%s\t%s" % p for p in part) + "\n")
        procs.append(subprocess.Popen(["node", os.path.join(HERE, "nav_bake.mjs"), "--list", lst], cwd=ROOT,
                                      stdout=subprocess.PIPE, text=True))
    bad = 0
    for p in procs:
        out, _ = p.communicate()
        for line in out.splitlines():
            if "FAILED" in line:
                bad += 1
                print("  " + line)
    # Reduce every heightfield whose nodes are missing or older.
    red = []
    for name in sorted(os.listdir(NAV)):
        if name.endswith(".chf"):
            src = os.path.join(NAV, name)
            out = src[:-4] + ".npz"
            parts = name[:-4].split("_")
            if int(parts[0]) not in {int(m) for m in args.maps.split(",")}:
                continue
            if wanted and (int(parts[1]), int(parts[2])) not in wanted:
                continue
            if args.force or stale(out, max(os.path.getmtime(REDUCE), os.path.getmtime(src))):
                red.append(name[:-4])
    print("reducing %d tiles" % len(red), flush=True)
    rfail, nodes = 0, 0
    if red:
        with mp.Pool(args.jobs) as pool:
            for k, (name, res, err) in enumerate(pool.imap_unordered(_reduce, red, chunksize=2), 1):
                if err:
                    rfail += 1
                    print("  reduce failed %s: %s" % (name, err))
                elif res:
                    nodes += res[0]
                if k % 100 == 0:
                    print("  %d/%d reduced (%.0fs)" % (k, len(red), time.time() - t0), flush=True)
                if args.clean and not err:
                    for ext in (".bin", ".chf"):
                        try:
                            os.remove(os.path.join(NAV, name + ext))
                        except OSError:
                            pass
    print("done in %.0fs: %d extracted (%d failed), %d baked (%d failed), %d reduced (%d failed, %d nodes)" % (
        time.time() - t0, len(jobs) - len(failed), len(failed), len(bake) - bad, bad, len(red) - rfail, rfail, nodes))
    if args.no_pack:
        return
    # Join each map's tiles and pack them for the addon (Data/Nav<map>.lua).
    import nav_stitch
    import nav_pack
    for mapid in (int(m) for m in args.maps.split(",")):
        nav_stitch.main([str(mapid)])
        nav_pack.main([str(mapid)])


if __name__ == "__main__":
    main(sys.argv[1:])
