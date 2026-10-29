"""Builds the collection installer (collection_installer.py) into one .exe to hand to friends:
tools/curseforge/dist/<Collection>Installer.exe.

    python tools/curseforge/collection_build.py [--from <AddOns folder>] [--no-bundle]

Run collection_export.py first (it writes collection.json). The addons that allow third-party
distribution are packed into the installer (bundle.zip), from an AddOns folder that has the
collection's own versions installed: by default the game's, found the way the installer finds it
(each folder's version must match its CurseForge file, or the build stops). Addons whose authors
don't allow that are never packed: the installer has the CurseForge app install them. --no-bundle
leaves the files out: the installer then downloads everything.

Needs PyInstaller (pip install --user pyinstaller) and Pillow, so run it without -I.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
WORK = os.path.join(HERE, "build")
DIST = os.path.join(HERE, "dist")
LOGO = os.path.join(ROOT, "addons", "Wally", "Media", "CurseForge", "Wally-400.png")
sys.path.insert(0, HERE)
import collection_installer as ci  # noqa: E402


def toc_version(folder):
    for name in os.listdir(folder):
        if name.lower().endswith(".toc"):
            with open(os.path.join(folder, name), encoding="utf-8", errors="replace") as f:
                for line in f:
                    if line.lower().startswith("## version"):
                        return line.split(":", 1)[1].strip()
    return None


def matches(version, file_name):
    """Whether a TOC's version is the one in a CurseForge file's name ("v1.0.6" in "Bandolier v1.0.6")."""
    if not version or not file_name:
        return True  # nothing to compare: trust the folder
    v = version.lstrip("vV").strip()
    return v.lower() in file_name.lower()


def pack(collection, addons_dir, out):
    """bundle.zip: the folders of every addon that allows distribution, and bundle.json (addon id ->
    file id) so the installer knows which versions it carries."""
    files, problems = {}, []
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for a in collection["addons"]:
            if a["locked"]:
                continue
            folders = a["file"]["folders"]
            missing = [f for f in folders if not os.path.isdir(os.path.join(addons_dir, f))]
            if not folders or missing:
                problems.append("%s: not installed in %s (%s)" % (a["name"], addons_dir, ", ".join(missing) or "no folders"))
                continue
            stale = [f for f in folders if not matches(toc_version(os.path.join(addons_dir, f)), a["file"]["name"])]
            if stale:
                problems.append("%s: %s isn't %s" % (a["name"], ", ".join(
                    "%s is %s" % (f, toc_version(os.path.join(addons_dir, f))) for f in stale), a["file"]["name"]))
                continue
            for f in folders:
                base = os.path.join(addons_dir, f)
                for dirpath, _, names in os.walk(base):
                    for n in names:
                        full = os.path.join(dirpath, n)
                        z.write(full, os.path.relpath(full, addons_dir).replace(os.sep, "/"))
            files[str(a["id"])] = a["file"]["id"]
        z.writestr("bundle.json", json.dumps(files, indent=1))
    return files, problems


def icon(out):
    from PIL import Image
    Image.open(LOGO).convert("RGBA").save(out, sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--from", dest="source", help="the AddOns folder to pack the addons from")
    ap.add_argument("--no-bundle", action="store_true", help="don't pack the addons: the installer downloads them")
    args = ap.parse_args(argv)
    with open(os.path.join(HERE, "collection.json"), encoding="utf-8") as f:
        collection = json.load(f)
    shutil.rmtree(WORK, ignore_errors=True)
    os.makedirs(WORK)
    data = [os.path.join(HERE, "collection.json")]
    if not args.no_bundle:
        source = args.source
        if not source:
            for _, client in ci.find_clients():
                if os.path.isdir(os.path.join(client, "Interface", "AddOns")):
                    source = os.path.join(client, "Interface", "AddOns")
                    break
        if not source:
            sys.exit("No AddOns folder found to pack from - pass --from <AddOns folder>, or --no-bundle.")
        print("packing from", source)
        out = os.path.join(WORK, "bundle.zip")
        files, problems = pack(collection, source, out)
        if problems:
            print("\n".join("  " + p for p in problems))
            sys.exit("Install the collection's versions there first (or export again), or pass --no-bundle.")
        print("  %d addons packed (%.0f MB)" % (len(files), os.path.getsize(out) / 1e6))
        data.append(out)
    ico = os.path.join(WORK, "icon.ico")
    icon(ico)
    data.append(ico)
    name = re.sub(r"[^A-Za-z0-9]+", "", collection.get("name", "Addon Collection").title()) + "Installer"
    cmd = [sys.executable, "-m", "PyInstaller", "--onefile", "--windowed", "--noconfirm", "--clean",
           "--name", name, "--icon", ico, "--distpath", DIST, "--workpath", os.path.join(WORK, "pyi"),
           "--specpath", WORK]
    for d in data:
        cmd += ["--add-data", "%s%s." % (d, os.pathsep)]
    cmd.append(os.path.join(HERE, "collection_installer.py"))
    subprocess.run(cmd, check=True)
    exe = os.path.join(DIST, name + ".exe")
    print("built %s (%.0f MB)" % (exe, os.path.getsize(exe) / 1e6))


if __name__ == "__main__":
    main(sys.argv[1:])
