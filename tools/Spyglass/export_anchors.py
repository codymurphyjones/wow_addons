"""Writes the developer's sync history into Data/Anchors.lua for a release.

Sync's trust version 2 (SIMPLE_TRUST = false in Sync.lua) trusts clients that
know recent hashes from the developer's history. That history is the commits the
developer's own SpyGlass made while collecting (/sg collect), saved in
SpyGlassDB.sync.history / .dev. This copies them into Data/Anchors.lua (the
seed hashes are kept), so every new client ships knowing them.

    python tools/Spyglass/export_anchors.py                    # finds WTF/Account/*/SavedVariables/Spyglass.lua
    python tools/Spyglass/export_anchors.py path/to/Spyglass.lua
"""
import os
import re
import sys

from lupa import lua51

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "_shared"))
import savedvars  # noqa: E402

ADDON = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "addons", "Spyglass")  # tools/Spyglass/ builds addons/Spyglass/
OUT = os.path.join(ADDON, "Data", "Anchors.lua")
KEEP = 400  # the newest this many commits


def history(path):
    """{ seq: hash } of the developer's commits in one saved-variables file."""
    db = savedvars.load(path, "SpyGlassDB", lua=lua51.LuaRuntime(), errors="replace")
    out = {}
    sync = db and db.sync
    if not sync:
        return out
    if db.collector:
        for _, c in (sync.history or {}).items():
            if c.seq and c.hash:
                out[int(c.seq)] = str(c.hash)
    for seq, h in (sync.dev or {}).items():
        out[int(seq)] = str(h)
    return out


def main(argv):
    paths = argv or savedvars.files("Spyglass")
    merged = {}
    for path in paths:
        merged.update(history(path))
    if not merged:
        print("No developer history found (collect with /sg collect, then /reload or log out).")
        return 1
    text = open(OUT, encoding="utf-8").read()
    for seq, h in re.findall(r"\[(\d+)\] = \"([0-9a-f]{16})\"", text.split("dev = {", 1)[1]):
        merged.setdefault(int(seq), h)
    keep = sorted(merged)[-KEEP:]
    seeds = re.search(r"seeds = \{[^}]*\}", text).group(0)
    lines = [
        "-- The shared history that decides which SpyGlass clients trust each other when",
        "-- they sync discoveries (Sync.lua). tools/Spyglass/export_anchors.py rewrites the",
        "-- developer's part from the developer's saved commits.",
        "local _, ns = ...",
        "ns.Anchors = {",
        "    -- Version 1 (SIMPLE_TRUST in Sync.lua): every client has these three.",
        "    " + seeds + ",",
        "    -- Version 2: the developer's commits, by sequence number ([seq] = hash).",
        "    dev = {",
    ]
    lines += ['        [%d] = "%s",' % (seq, merged[seq]) for seq in keep]
    lines += ["    },", "}", ""]
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    print("wrote Data/Anchors.lua: %d developer commits (newest #%d)" % (len(keep), keep[-1]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
