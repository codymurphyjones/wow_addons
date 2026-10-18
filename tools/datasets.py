"""The build tools' datasets (scraped Wowhead pages, game tables), kept packed when not in use.

Each tools/<Addon>/.wowhead_cache/ and .cache/ folder is a dataset: hundreds of megabytes of pages
that compress to a few percent as one solid archive, tools/<Addon>/<folder>.tar.xz. A build needs
the folders, so build_all.py unpacks them first and packs them again when it's done.

    python tools/datasets.py status     # each dataset: packed, unpacked, or both, and its size
    python tools/datasets.py unpack     # archives -> folders (files already there are kept)
    python tools/datasets.py pack       # folders -> archives, then the folders are removed
    python tools/datasets.py pack --keep

Packing never loses data: anything the old archive holds that the folder doesn't is put back in
the folder first, and the new archive is checked against the folder (every file, by SHA-1) before
it replaces the old one and the folder is removed.
"""
import argparse
import hashlib
import os
import shutil
import sys
import tarfile
import time

TOOLS = os.path.dirname(os.path.abspath(__file__))
FOLDERS = (".wowhead_cache", ".cache")  # dataset folder names inside tools/<Addon>/
PRESET = 9                              # xz level: these pages compress to ~4% at 9


def datasets():
    """(name, folder, archive) for every dataset, packed or not."""
    out = []
    for addon in sorted(os.listdir(TOOLS)):
        base = os.path.join(TOOLS, addon)
        if not os.path.isdir(base) or addon.startswith(("_", ".")):
            continue
        for name in FOLDERS:
            folder = os.path.join(base, name)
            archive = folder + ".tar.xz"
            if os.path.isdir(folder) or os.path.isfile(archive):
                out.append(("%s/%s" % (addon, name), folder, archive))
    return out


def _files(folder):
    """Relative paths (with /) of every file in folder."""
    out = []
    for root, _, names in os.walk(folder):
        for n in names:
            out.append(os.path.relpath(os.path.join(root, n), folder).replace(os.sep, "/"))
    return sorted(out)


def _sha1(data_or_path):
    h = hashlib.sha1()
    if isinstance(data_or_path, bytes):
        h.update(data_or_path)
    else:
        with open(data_or_path, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
    return h.hexdigest()


def _extract(archive, folder, only_missing=True):
    """Extracts archive into folder (only files the folder lacks): how many were written."""
    os.makedirs(folder, exist_ok=True)
    have = set(_files(folder)) if only_missing else set()
    n = 0
    with tarfile.open(archive, "r:xz") as tar:
        members = [m for m in tar.getmembers() if m.isfile() and m.name not in have]
        if members:
            tar.extractall(folder, members=members, filter="data")
            n = len(members)
    return n


def _size(folder):
    return sum(os.path.getsize(os.path.join(folder, f)) for f in _files(folder))


def mb(n):
    return "%.1f MB" % (n / 1e6)


def status():
    for name, folder, archive in datasets():
        state = []
        if os.path.isfile(archive):
            state.append("packed %s" % mb(os.path.getsize(archive)))
        if os.path.isdir(folder):
            state.append("unpacked %s (%d files)" % (mb(_size(folder)), len(_files(folder))))
        print("  %-30s %s" % (name, ", ".join(state)))


def unpack(quiet=False):
    for name, folder, archive in datasets():
        if not os.path.isfile(archive):
            continue
        t = time.time()
        n = _extract(archive, folder)
        if not quiet or n:
            print("unpacked %-30s %5d files  %.0fs" % (name, n, time.time() - t), flush=True)


def pack(keep=False):
    ok = True
    for name, folder, archive in datasets():
        if not os.path.isdir(folder):
            continue
        t = time.time()
        # Nothing the old archive holds is lost: put back what the folder lacks first.
        if os.path.isfile(archive):
            _extract(archive, folder)
        files = _files(folder)
        if not files:
            continue
        tmp = archive + ".tmp"
        with tarfile.open(tmp, "w:xz", preset=PRESET) as tar:
            for rel in files:
                tar.add(os.path.join(folder, rel), arcname=rel, recursive=False)
        # Check the new archive against the folder, file by file, before trusting it.
        expect = {rel: _sha1(os.path.join(folder, rel)) for rel in files}
        seen = {}
        with tarfile.open(tmp, "r:xz") as tar:
            for m in tar:
                if m.isfile():
                    seen[m.name] = _sha1(tar.extractfile(m).read())
        if seen != expect:
            os.remove(tmp)
            print("NOT packed %-28s the archive didn't match the folder; folder kept" % name, flush=True)
            ok = False
            continue
        os.replace(tmp, archive)
        raw = sum(os.path.getsize(os.path.join(folder, rel)) for rel in files)
        if not keep:
            shutil.rmtree(folder)
        print("packed   %-30s %5d files  %s -> %s  %.0fs%s" % (name, len(files), mb(raw), mb(os.path.getsize(archive)),
                                                              time.time() - t, "" if keep else "  (folder removed)"), flush=True)
    return ok


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("action", choices=("status", "unpack", "pack"))
    ap.add_argument("--keep", action="store_true", help="pack: keep the unpacked folders too")
    a = ap.parse_args(argv)
    if a.action == "status":
        status()
    elif a.action == "unpack":
        unpack()
    else:
        return 0 if pack(a.keep) else 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
