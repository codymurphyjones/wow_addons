"""The collection installer: installs a CurseForge addon collection (collection.json, made by
collection_export.py) into a friend's World of Warcraft Forever, with no CurseForge key or account.

Built into a single .exe by collection_build.py; it also runs as a script:

    python tools/curseforge/collection_installer.py

1. Finds the game: Battle.net's install list (ProgramData/Battle.net/Agent/product.db), the
   registry, then the usual folders on every drive. A client folder whose .flavor.info says "wowf"
   is Forever and comes first; other clients that hold addons for it (the beta) are offered too, and
   any folder can be picked by hand (the game's folder, a client's, Interface or AddOns).
2. Reads the newest collection.json from GitHub (the copy built in is the fallback).
3. Unpacks each addon into Interface/AddOns: from the copy built into the installer (bundle.zip,
   collection_build.py) when it's the collection's version, else downloaded from its public link (a
   newer release put into the online list since). A folder it replaces is moved to
   Interface/AddOns-backup/<date time> first.
4. Addons whose authors don't allow third-party downloads are installed through the CurseForge app:
   its own install link (curseforge://install), one at a time. Without the app, their pages open.

The CurseForge app finds the installed addons by itself when it next scans the game, and keeps them
updated from then on.
"""
import datetime
import json
import os
import queue
import re
import shutil
import string
import sys
import tempfile
import threading
import time
import urllib.request
import webbrowser
import zipfile

REMOTE = "https://raw.githubusercontent.com/codymurphyjones/wow_addons/main/tools/curseforge/collection.json"
USER_AGENT = "WallyCollectionInstaller/1.0"
FOREVER = "wowf"            # .flavor.info's product code of WoW Forever
LINK_GAP = 4                # seconds between CurseForge app install links


# ---------------------------------------------------------------------------------------------
# The collection
# ---------------------------------------------------------------------------------------------

def bundled_path(name):
    base = getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(base, name)


def load_collection():
    """(collection, where it came from): GitHub's newest, else the one built in."""
    try:
        req = urllib.request.Request(REMOTE, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.load(resp)
        if isinstance(data.get("addons"), list):
            return data, "online (newest)"
    except Exception:
        pass
    with open(bundled_path("collection.json"), encoding="utf-8") as f:
        return json.load(f), "built in"


# ---------------------------------------------------------------------------------------------
# Finding the game
# ---------------------------------------------------------------------------------------------

def battle_net_roots():
    """WoW folders Battle.net knows about (product.db is protobuf: its paths are plain text in it)."""
    path = os.path.join(os.environ.get("ProgramData", r"C:\ProgramData"), "Battle.net", "Agent", "product.db")
    try:
        raw = open(path, "rb").read()
    except OSError:
        return []
    found = re.findall(rb"[A-Za-z]:[/\\][\x20-\x7e]{2,200}?(?=[\x00-\x1f])", raw)
    return [p.decode("latin1") for p in found if b"warcraft" in p.lower()]


def registry_roots():
    try:
        import winreg
    except ImportError:
        return []
    out = []
    for key in (r"SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft",
                r"SOFTWARE\Blizzard Entertainment\World of Warcraft"):
        try:
            with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, key) as k:
                out.append(winreg.QueryValueEx(k, "InstallPath")[0])
        except OSError:
            pass
    return out


def usual_roots():
    out = []
    for d in string.ascii_uppercase:
        drive = d + ":\\"
        if not os.path.exists(drive):
            continue
        for rel in ("World of Warcraft", r"Games\World of Warcraft", r"Program Files (x86)\World of Warcraft",
                    r"Program Files\World of Warcraft", r"Blizzard\World of Warcraft", r"Battle.net\World of Warcraft"):
            out.append(drive + rel)
    return out


def flavor(client):
    try:
        text = open(os.path.join(client, ".flavor.info"), encoding="latin1").read()
    except OSError:
        return None
    m = re.search(r"Product Flavor!STRING:0\s+(\S+)", text)
    return m.group(1) if m else text.strip().split()[-1] if text.strip() else None


def find_clients():
    """[(label, client folder)], Forever first: every game client folder found."""
    roots, seen = [], set()
    for r in battle_net_roots() + registry_roots() + usual_roots():
        r = os.path.normpath(r.strip().strip('"').rstrip("\\/"))
        # A path Battle.net keeps may be a client folder or its game folder.
        if os.path.basename(r).startswith("_") and r.endswith("_"):
            r = os.path.dirname(r)
        key = r.lower()
        if key not in seen and os.path.isdir(r):
            seen.add(key)
            roots.append(r)
    clients = []
    for root in roots:
        for name in sorted(os.listdir(root)):
            client = os.path.join(root, name)
            if not (name.startswith("_") and name.endswith("_") and os.path.isdir(client)):
                continue
            fl = flavor(client)
            forever = fl == FOREVER or name.lower() == "_forever_"
            beta = name.lower() == "_classic_beta_"
            if forever or beta:
                has = os.path.isdir(os.path.join(client, "Interface", "AddOns"))
                label = "%s  (%s%s)" % (client, "WoW Forever" if forever else "Forever beta",
                                        ", has addons" if has else "")
                clients.append((0 if forever else 1, label, client))
    clients.sort(key=lambda c: c[0])
    return [(label, client) for _, label, client in clients]


def addons_dir(picked):
    """The AddOns folder for a picked folder: the game's, a client's, Interface or AddOns itself."""
    p = os.path.normpath(picked)
    if os.path.basename(p).lower() == "addons":
        return p
    if os.path.basename(p).lower() == "interface":
        return os.path.join(p, "AddOns")
    if os.path.exists(os.path.join(p, ".flavor.info")) or os.path.isdir(os.path.join(p, "Interface")) \
            or any(f.lower().startswith("wow") and f.lower().endswith(".exe") for f in os.listdir(p)):
        return os.path.join(p, "Interface", "AddOns")
    for name in os.listdir(p):  # the game's folder: its Forever client
        client = os.path.join(p, name)
        if os.path.isdir(client) and (flavor(client) == FOREVER or name.lower() == "_forever_"):
            return os.path.join(client, "Interface", "AddOns")
    return None


# ---------------------------------------------------------------------------------------------
# Installing
# ---------------------------------------------------------------------------------------------

def download(url, dest):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=120) as resp, open(dest, "wb") as f:
        shutil.copyfileobj(resp, f)


def bundle():
    """(path, { addon id: file id }) of the addons built into the installer, or (None, {})."""
    path = bundled_path("bundle.zip")
    if not os.path.exists(path):
        return None, {}
    with zipfile.ZipFile(path) as z:
        files = {int(k): v for k, v in json.loads(z.read("bundle.json")).items()}
    return path, files


def unpack(zpath, addons, backup, log, only=None):
    """Unpack an addon zip into AddOns (only: just these top folders); folders it replaces go to
    backup first."""
    with zipfile.ZipFile(zpath) as z:
        names = [n for n in z.namelist() if n and not n.startswith(("/", "\\")) and ".." not in n.split("/")]
        if only is not None:
            names = [n for n in names if n.split("/")[0] in only]
        tops = sorted({n.split("/")[0] for n in names if "/" in n})
        for top in tops:
            old = os.path.join(addons, top)
            if os.path.exists(old):
                os.makedirs(backup, exist_ok=True)
                shutil.move(old, os.path.join(backup, top))
        for n in names:
            if "/" not in n:
                continue  # a loose file beside the folders (a readme): not an addon's
            target = os.path.join(addons, *n.split("/"))
            if n.endswith("/"):
                os.makedirs(target, exist_ok=True)
                continue
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with z.open(n) as src, open(target, "wb") as out:
                shutil.copyfileobj(src, out)
    return tops


def curseforge_app():
    try:
        import winreg
        with winreg.OpenKey(winreg.HKEY_CLASSES_ROOT, r"curseforge\shell\open\command"):
            return True
    except OSError:
        return False


def install(collection, addons, chosen, log, done):
    """Install the chosen addons (ids) into AddOns, logging as it goes. Runs off the window's thread."""
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H%M%S")
    backup = os.path.join(os.path.dirname(addons), "AddOns-backup", stamp)
    os.makedirs(addons, exist_ok=True)
    items = [a for a in collection["addons"] if a["id"] in chosen]
    direct = [a for a in items if not a["locked"]]
    locked = [a for a in items if a["locked"]]
    ok, failed = 0, []
    packed, packed_files = bundle()
    with tempfile.TemporaryDirectory() as tmp:
        for i, a in enumerate(direct, 1):
            log("(%d/%d) %s %s" % (i, len(direct), a["name"], a["file"]["name"] or ""))
            try:
                if packed and packed_files.get(a["id"]) == a["file"]["id"]:
                    folders = unpack(packed, addons, backup, log, only=set(a["file"]["folders"]))
                else:
                    z = os.path.join(tmp, "%d.zip" % a["file"]["id"])
                    download(a["file"]["url"], z)
                    folders = unpack(z, addons, backup, log)
                log("      installed: " + ", ".join(folders))
                ok += 1
            except Exception as exc:
                failed.append(a["name"])
                log("      FAILED: %s" % exc)
    if locked:
        app = curseforge_app()
        log("")
        if app:
            log("%d addons don't allow downloads outside CurseForge: the CurseForge app installs them." % len(locked))
            log("Accept each one in the CurseForge window as it opens.")
        else:
            log("%d addons don't allow downloads outside CurseForge, and the CurseForge app isn't installed:" % len(locked))
            log("their pages open in your browser: install them from there (or get the CurseForge app).")
        for a in locked:
            log("  " + a["name"])
            if app:
                os.startfile("curseforge://install?addonId=%d&fileId=%d&gameId=1" % (a["id"], a["file"]["id"]))
            elif a.get("page"):
                webbrowser.open(a["page"])
            time.sleep(LINK_GAP)
    log("")
    log("Done: %d installed%s into %s" % (ok, (", %d failed (%s)" % (len(failed), ", ".join(failed))) if failed else "", addons))
    if os.path.isdir(backup):
        log("Folders that were replaced are in " + backup)
    log("Restart World of Warcraft (or /reload) to load them.")
    done(not failed)


# ---------------------------------------------------------------------------------------------
# The window
# ---------------------------------------------------------------------------------------------

def run_window():
    import tkinter as tk
    from tkinter import filedialog, messagebox, ttk

    collection, source = load_collection()
    root = tk.Tk()
    root.title("%s installer" % collection.get("name", "Addon collection"))
    root.geometry("760x620")
    try:
        root.iconbitmap(bundled_path("icon.ico"))
    except Exception:
        pass
    pad = {"padx": 10, "pady": 4}

    ttk.Label(root, text=collection.get("name", "Addon collection"), font=("Segoe UI", 14, "bold")).pack(anchor="w", **pad)
    ttk.Label(root, text="%d addons for World of Warcraft Forever  ·  list: %s" % (len(collection["addons"]), source)).pack(anchor="w", padx=10)

    frm = ttk.LabelFrame(root, text="Install into")
    frm.pack(fill="x", **pad)
    clients = find_clients()
    choice = tk.StringVar(value=clients[0][0] if clients else "")
    paths = dict(clients)
    combo = ttk.Combobox(frm, textvariable=choice, values=[c[0] for c in clients], state="readonly", width=90)
    combo.pack(side="left", fill="x", expand=True, padx=6, pady=6)

    def browse():
        picked = filedialog.askdirectory(title="Pick your World of Warcraft folder (or its _forever_ folder)")
        if picked:
            target = addons_dir(picked)
            if not target:
                messagebox.showerror("Not a WoW folder", "Couldn't find World of Warcraft Forever in:\n" + picked)
                return
            label = "%s  (picked)" % os.path.dirname(os.path.dirname(target))
            paths[label] = os.path.dirname(os.path.dirname(target))
            combo["values"] = list(combo["values"]) + [label]
            choice.set(label)

    ttk.Button(frm, text="Browse...", command=browse).pack(side="right", padx=6)
    where = ttk.Label(root, text="", foreground="#555")
    where.pack(anchor="w", padx=10)

    def show_target(*_):
        client = paths.get(choice.get())
        where.configure(text=("Addons go into:  " + os.path.join(client, "Interface", "AddOns")) if client else "")
    choice.trace_add("write", show_target)
    show_target()
    if not clients:
        ttk.Label(root, text="World of Warcraft Forever wasn't found automatically: use Browse to pick its folder.",
                  foreground="#b00").pack(anchor="w", padx=10)

    lst = ttk.LabelFrame(root, text="Addons (uncheck any you don't want)")
    lst.pack(fill="both", expand=True, **pad)
    canvas = tk.Canvas(lst, highlightthickness=0, height=200)
    bar = ttk.Scrollbar(lst, orient="vertical", command=canvas.yview)
    inner = ttk.Frame(canvas)
    inner.bind("<Configure>", lambda e: canvas.configure(scrollregion=canvas.bbox("all")))
    canvas.create_window((0, 0), window=inner, anchor="nw")
    canvas.configure(yscrollcommand=bar.set)
    canvas.pack(side="left", fill="both", expand=True)
    bar.pack(side="right", fill="y")
    canvas.bind_all("<MouseWheel>", lambda e: canvas.yview_scroll(int(-e.delta / 120), "units"))
    checks = {}
    for a in collection["addons"]:
        v = tk.BooleanVar(value=True)
        checks[a["id"]] = v
        note = "  (through the CurseForge app)" if a["locked"] else ("  (needed by %s)" % a["requiredBy"] if a.get("requiredBy") else "")
        ttk.Checkbutton(inner, text=a["name"] + note, variable=v).pack(anchor="w")

    out = tk.Text(root, height=9, wrap="word", font=("Consolas", 9))
    out.pack(fill="both", **pad)
    msgs = queue.Queue()

    def log(text):
        msgs.put(text)

    def pump():
        while not msgs.empty():
            out.insert("end", msgs.get() + "\n")
            out.see("end")
        root.after(100, pump)
    pump()

    go = ttk.Button(root, text="Install")

    def finished(success):
        msgs.put("")
        root.after(0, lambda: go.configure(state="normal", text="Install again"))

    def start():
        label = choice.get()
        client = paths.get(label)
        if not client:
            messagebox.showerror("No folder", "Pick the World of Warcraft Forever folder first (Browse).")
            return
        target = os.path.join(client, "Interface", "AddOns")
        chosen = {i for i, v in checks.items() if v.get()}
        if not chosen:
            return
        go.configure(state="disabled", text="Installing...")
        log("Installing into " + target)
        threading.Thread(target=install, args=(collection, target, chosen, log, finished), daemon=True).start()

    go.configure(command=start)
    go.pack(pady=8)
    root.mainloop()


if __name__ == "__main__":
    run_window()
