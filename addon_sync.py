#!/usr/bin/env python3
"""addon_sync - install dev builds or CurseForge releases into your WoW AddOns folder.

For every addon in the workspace (a folder containing <Folder>.toc):
  * dev     - the workspace copy is installed when its files differ from the latest CurseForge
              release (or the addon isn't on CurseForge at all).
  * release - otherwise the latest CurseForge release is downloaded and installed.

Versions are bumped AFTER a deploy, so the workspace always carries the next version number.
Version lines (TOC "## Version:" and Lua `VERSION = "x"` lines) are ignored when comparing, so an
addon whose only difference from its last release is the version number counts as unchanged.
If CurseForge can't be reached, the last release downloaded from it (.addon_sync/cache) stands in;
with none cached, only local checks are used.

SourceCode/ (release_dir) is the upload outbox: sync builds <Name>_v<version>.zip there for every
linked addon that's newer than CurseForge (rebuilt when its files change), and `publish` uploads
those exact files. Upload by hand or with `publish`; whenever the API works, sync deletes zips whose
version CurseForge already has.

Commands (run with -h for options):
  init                    set up .env interactively
  link [NAME ...]         look up CurseForge project ids (written to each TOC as X-Curse-Project-ID)
  link NAME --id ID       set a project id by hand
  status                  show what sync would do (dry run)
  sync [--watch]          apply (default; yarn test); --watch re-syncs on file changes
  dev|release|auto|skip NAME ...   pin an addon to a mode (auto clears the pin)
  publish [NAME]          upload NAME, or every addon newer than CurseForge (yarn deploy). Addons
                          without a project get one first: your existing project is linked, else
                          tools/curseforge/create_projects.py creates it in a browser
  publish --queued        upload what's waiting in SourceCode/
  check [NAME ...]        every addon vs its CurseForge project: what publish would ship (yarn deploy:check)
  bump [NAME ...]         bump the patch version (TOC + Lua VERSION lines); all addons by default
  stop                    restore the AddOns folders sync replaced since the session began (yarn stop)

Shared code: addons/shared holds Lua several addons load. It is never an addon of its own, so it
is never installed or published. An addon loads a shared file by listing its real path in its TOC,
`..\shared\DeathRecap.lua`; every build (the dev copy sync installs, and release zips) copies each
listed file into the addon's own Shared\ folder and rewrites that TOC line to
`Shared\DeathRecap.lua`. Files an XML file there loads come along too. Editing a shared file counts
as a change to every addon that loads it (--watch re-syncs them all).

Every AddOns folder sync replaces is first backed up to .addon_sync/backup (once per test session),
so `stop` can delete what was installed and put the originals back.

There is no config file. Personal settings go in .env (gitignored), CurseForge project ids live in
each addon's TOC (## X-Curse-Project-ID), addons that stay local (never created on CurseForge or
published) are listed in Local.dat, one per line, and pins are kept in .addon_sync/pins.json:
  CURSEFORGE_KEY=...            CurseForge Core API key (console.curseforge.com)
  CURSEFORGE_AUTHOR=...         your CurseForge username (publish refuses projects you don't own)
  CURSEFORGE_UPLOAD_TOKEN=...   author upload token, for publish (authors.curseforge.com)
  WOW_INSTALL=...               WoW folder, a flavor folder (_classic_era_) or its Interface/AddOns
Real environment variables override .env.

Stdlib only; needs Python 3.8+.
"""
import argparse
import difflib
import fnmatch
import functools
import hashlib
import html
import json
import os
import posixpath
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import types
import uuid
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ENV_PATH = ROOT / ".env"
LOCAL_PATH = ROOT / "Local.dat"  # addons that stay local: never created on or published to CurseForge
CREATE_SCRIPT = ROOT / "tools" / "curseforge" / "create_projects.py"
DATA_DIR = ROOT / ".addon_sync"
STATE_PATH = DATA_DIR / "state.json"
PINS_PATH = DATA_DIR / "pins.json"
API_CACHE_DIR = DATA_DIR / "cache" / "api"
FILE_CACHE_DIR = DATA_DIR / "cache" / "files"
BACKUP_DIR = DATA_DIR / "backup"
SESSION_PATH = BACKUP_DIR / "session.json"

API_BASE = "https://api.curseforge.com"
WOW_GAME_ID = 1
API_TTL_SECONDS = 600
USER_AGENT = "addon-sync/1.0"

DEFAULT_CONFIG = {
    "upload_host": "https://wow.curseforge.com",
    "source_dir": "addons",
    "release_dir": "SourceCode",
    "game_version_type_id": None,
    "include_prereleases": False,
    # CurseForge game versions every upload is tagged with (WoW Forever only), whatever else the
    # TOC's ## Interface line loads on. Empty: one per ## Interface number. --game-versions overrides.
    "game_versions": ["1.60.1"],
    "exclude": ["__pycache__", "*.py", "*.pyc", "Tools", "Dev", ".git*", "*.md", "*.txt"],
}
MODES = ("dev", "release", "skip")
SHARED_DIR = "shared"     # <source_dir>/shared: code several addons load; never an addon itself
SHARED_FOLDER = "Shared"  # where each addon's build carries its copies of it


class SyncError(Exception):
    pass


class Unavailable(SyncError):
    """CurseForge couldn't be reached or is having problems - worth retrying later."""


# --------------------------------------------------------------------------- config / state

def load_json(path, default):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except FileNotFoundError:
        return default
    except json.JSONDecodeError as exc:
        raise SyncError(f"{path.name} is not valid JSON: {exc}")


def save_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
    os.replace(tmp, path)


def load_dotenv(path=None):
    """Load KEY=VALUE lines from .env into os.environ (real environment variables win)."""
    path = path or ENV_PATH
    try:
        lines = path.read_text(encoding="utf-8-sig").splitlines()
    except FileNotFoundError:
        return
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if key.startswith("export "):
            key = key[len("export "):].strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
            value = value[1:-1]
        elif " #" in value:
            value = value.split(" #", 1)[0].rstrip()
        os.environ.setdefault(key, value)


def set_dotenv(values, path=None):
    """Set keys in .env, keeping its other lines and comments."""
    path = path or ENV_PATH
    lines = path.read_text(encoding="utf-8-sig").splitlines() if path.exists() else []
    pending = dict(values)
    for i, line in enumerate(lines):
        if "=" not in line or line.lstrip().startswith("#"):
            continue
        key = line.split("=", 1)[0].strip()
        prefix = "export " if key.startswith("export ") else ""
        key = key[len(prefix):].strip()
        if key in pending:
            lines[i] = f"{prefix}{key}={pending.pop(key)}"
        elif key in values:  # a duplicate of a key already set above: drop it
            lines[i] = None
    lines = [line for line in lines if line is not None]
    lines += [f"{k}={v}" for k, v in pending.items()]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def load_config():
    """Settings: built-in defaults, .env for anything personal, TOCs for project ids, local pins."""
    load_dotenv()
    cfg = json.loads(json.dumps(DEFAULT_CONFIG))
    cfg["curseforge_author"] = os.environ.get("CURSEFORGE_AUTHOR", "").strip()
    cfg["overrides"] = load_json(PINS_PATH, {})
    cfg["local"] = local_only()
    cfg["projects"] = {a.name: int(a.toc["x-curse-project-id"]) for a in discover(cfg)
                       if a.toc.get("x-curse-project-id", "").strip().isdigit()}
    return cfg


def local_only():
    """Lowercased addon names listed in Local.dat (one per line, # comments). Every other addon ships."""
    path = next((p for p in ROOT.iterdir() if p.name.lower() == LOCAL_PATH.name.lower()), None)
    if not path:
        return set()
    lines = path.read_text(encoding="utf-8-sig").splitlines()
    return {line.split("#", 1)[0].strip().lower() for line in lines} - {""}


def is_local(cfg, addon):
    return addon.name.lower() in cfg["local"]


def save_pins(cfg):
    save_json(PINS_PATH, cfg["overrides"])


def api_key(cfg):
    return os.environ.get("CURSEFORGE_KEY") or os.environ.get("CURSEFORGE_API_KEY") or ""


def upload_token(cfg):
    return os.environ.get("CURSEFORGE_UPLOAD_TOKEN") or ""


def wow_dir(cfg):
    """The AddOns folder, from WOW_INSTALL (.env)."""
    raw = os.environ.get("WOW_INSTALL")
    if not raw:
        raise SyncError("WOW_INSTALL is not set - add it to .env (or run `python addon_sync.py init`).")
    path = Path(raw.strip().strip('"')).expanduser()
    if not path.is_dir():
        raise SyncError(f"WOW_INSTALL does not exist: {path}")
    if path.name.lower() == "addons":
        return path
    if (path / "Interface" / "AddOns").is_dir():  # a flavor folder like _classic_era_
        return path / "Interface" / "AddOns"
    flavors = [f for f in sorted(path.iterdir()) if (f / "Interface" / "AddOns").is_dir()]
    if len(flavors) == 1:  # the WoW folder with a single game flavor installed
        return flavors[0] / "Interface" / "AddOns"
    if flavors:
        raise SyncError(f"WOW_INSTALL has several game versions ({', '.join(f.name for f in flavors)}) - "
                        f"point it at one, e.g. {flavors[0]}")
    raise SyncError(f"No Interface/AddOns folder found under WOW_INSTALL: {path}")


# --------------------------------------------------------------------------- addons / TOC

def parse_toc(text):
    fields = {}
    for line in text.splitlines():
        m = re.match(r"^##\s*([^:]+?)\s*:\s*(.*?)\s*$", line)
        if m:
            fields.setdefault(m.group(1).lower(), m.group(2))
    return fields


def strip_color(text):
    return re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", text or "").strip()


def toc_matches(stem, name):
    return stem.lower() == name.lower() or re.match(rf"^{re.escape(name)}[-_]", stem, re.I)


def find_toc(folder, name):
    exact = folder / f"{name}.toc"
    if exact.is_file():
        return exact
    for p in sorted(folder.glob("*.toc")):
        if toc_matches(p.stem, name):
            return p
    return None


class Addon:
    def __init__(self, name, path, toc):
        self.name = name
        self.path = path
        self.toc = toc
        self.version = toc.get("version")
        self.title = strip_color(toc.get("title")) or name


def release_dir(cfg):
    return (ROOT / (cfg.get("release_dir") or DEFAULT_CONFIG["release_dir"])).resolve()


def discover(cfg):
    src = (ROOT / cfg["source_dir"]).resolve()
    if not src.is_dir():
        raise SyncError(f"source_dir does not exist: {src}")
    addons = []
    for folder in sorted(p for p in src.iterdir() if p.is_dir()):
        if folder.name.lower() == SHARED_DIR:
            continue  # shared code, copied into the addons that load it (build_files)
        toc = find_toc(folder, folder.name)
        if toc:
            text = toc.read_bytes().decode("utf-8-sig", errors="replace")
            addons.append(Addon(folder.name, folder, parse_toc(text)))
    return addons


def project_name(addon):
    """The CurseForge project name: the TOC's title, with a space before each capitalized word
    run together with the one before it ("WallyHUD" -> "Wally HUD", "MrMiyagi" -> "Mr Miyagi")."""
    return re.sub(r"(?<=[a-z0-9])(?=[A-Z])", " ", addon.title).strip()


def resolve_names(addons, names):
    by_lower = {a.name.lower(): a for a in addons}
    picked = []
    for name in names:
        addon = by_lower.get(name.lower())
        if not addon:
            raise SyncError(f"Unknown addon '{name}'. Known: {', '.join(a.name for a in addons)}")
        picked.append(addon)
    return picked


def is_excluded(parts, patterns):
    rel = "/".join(parts)
    return any(fnmatch.fnmatch(rel, pat) or any(fnmatch.fnmatch(p, pat) for p in parts)
               for pat in patterns)


def iter_files(root, patterns):
    """Yield (relative posix path, absolute path) for non-excluded files, sorted."""
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        base = Path(dirpath).relative_to(root).parts
        dirnames[:] = sorted(d for d in dirnames if not is_excluded(base + (d,), patterns))
        for fname in filenames:
            parts = base + (fname,)
            if not is_excluded(parts, patterns):
                out.append(("/".join(parts), Path(dirpath) / fname))
    return sorted(out)


# A TOC line loading a shared file: ..\shared\<path>
SHARED_LINE = re.compile(rb"^([ \t]*)\.\.[\\/]+" + SHARED_DIR.encode() + rb"[\\/]+([^\r\n]*?)[ \t]*(\r?\n)?$", re.I)
XML_INCLUDE = re.compile(r"<(?:Script|Include)\b[^>]*\bfile\s*=\s*\"([^\"]+)\"", re.I)


class Generated:
    """A build file made in memory (a TOC with its shared lines rewritten), in place of its Path."""

    def __init__(self, data, source):
        self.data, self.source = data, source

    def read_bytes(self):
        return self.data

    def stat(self):
        return types.SimpleNamespace(st_size=len(self.data), st_mtime_ns=self.source.stat().st_mtime_ns)


def rewrite_toc(data):
    """(TOC bytes with each ..\shared\<path> line pointing into Shared\ instead, [<path>, ...])."""
    out, refs = [], []
    for line in data.splitlines(keepends=True):
        m = SHARED_LINE.match(line)
        if m and m.group(2):
            rel = m.group(2).decode("utf-8").replace("\\", "/").strip("/")
            refs.append(rel)
            line = m.group(1) + (SHARED_FOLDER + "/" + rel).replace("/", "\\").encode("utf-8") + (m.group(3) or b"")
        out.append(line)
    return b"".join(out), refs


def shared_root(addon):
    return addon.path.parent / SHARED_DIR


def build_files(addon, patterns):
    """The files an addon's build is made of, listed as iter_files() lists them: the workspace copy,
    its TOCs with shared lines rewritten (as Generated), and the shared files they load, under Shared/."""
    files, wanted = [], []
    for rel, path in iter_files(addon.path, patterns):
        if rel.split("/")[0].lower() == SHARED_FOLDER.lower():
            raise SyncError(f"{addon.name} has a {SHARED_FOLDER}/ folder of its own, which builds fill with "
                            f"its copies of {SHARED_DIR}/ - rename it")
        if "/" not in rel and rel.lower().endswith(".toc"):
            data, refs = rewrite_toc(path.read_bytes())
            if refs:
                path = Generated(data, path)
                wanted += refs
        files.append((rel, path))
    root, seen = shared_root(addon), set()
    while wanted:
        rel = posixpath.normpath(wanted.pop(0))
        if rel.lower() in seen:
            continue
        seen.add(rel.lower())
        src = root / rel
        if rel.startswith("..") or not src.is_file():
            raise SyncError(f"{addon.name}'s TOC loads ..\\{SHARED_DIR}\\{rel.replace('/', chr(92))}, "
                            f"which isn't in {root}")
        files.append((f"{SHARED_FOLDER}/{rel}", src))
        if rel.lower().endswith(".xml"):
            text = re.sub(r"<!--.*?-->", "", src.read_text(encoding="utf-8", errors="replace"), flags=re.S)
            wanted += [posixpath.join(posixpath.dirname(rel), inc.replace("\\", "/"))
                       for inc in XML_INCLUDE.findall(text)]
    return sorted(files, key=lambda f: f[0])


def copy_build_file(src, dest):
    if isinstance(src, Generated):
        dest.write_bytes(src.data)
    else:
        shutil.copy2(src, dest)


def source_hash(addon, patterns):
    h = hashlib.sha256()
    for rel, path in build_files(addon, patterns):
        data = path.read_bytes()
        h.update(f"{rel}\0{len(data)}\0".encode())
        h.update(data)
    return h.hexdigest()


def installed_matches(addon, wow, patterns):
    """Whether the installed copy has every workspace file, at the same size, and nothing else.
    Catches a copy that was cut short (sync deletes the folder before copying it fresh)."""
    target = wow / addon.name
    if not target.exists():
        return False
    want = {rel: path.stat().st_size for rel, path in build_files(addon, patterns)}
    have = {rel: path.stat().st_size for rel, path in iter_files(target, [])}
    return want == have


def source_signature(addon, patterns):
    """Cheap change detector for --watch (paths, sizes, mtimes)."""
    h = hashlib.sha256()
    for rel, path in build_files(addon, patterns):
        st = path.stat()
        h.update(f"{rel}\0{st.st_size}\0{st.st_mtime_ns}\0".encode())
    return h.hexdigest()


TEXT_EXTS = (".toc", ".lua", ".xml", ".md", ".txt")
TOC_VERSION_LINE = re.compile(rb"^\s*##\s*(Version|X-Curse-Project-ID)\s*:", re.I)
LUA_VERSION_LINE = re.compile(rb"""^\s*[\w.]*VERSION\s*=\s*["'][^"']*["']\s*;?\s*$""")


def normalize_content(rel, data):
    """File bytes with version-number lines dropped, so a version bump alone isn't a change."""
    lower = rel.lower()
    if not lower.endswith(TEXT_EXTS):
        return data
    lines = data.replace(b"\r\n", b"\n").split(b"\n")
    if lower.endswith(".toc"):
        lines = [line for line in lines if not TOC_VERSION_LINE.match(line)]
    elif lower.endswith(".lua"):
        lines = [line for line in lines if not LUA_VERSION_LINE.match(line)]
    return b"\n".join(lines)


def _hash_entries(entries):
    h = hashlib.sha256()
    for rel, data in sorted(entries, key=lambda e: e[0]):
        data = normalize_content(rel, data)
        h.update(f"{rel}\0{len(data)}\0".encode())
        h.update(data)
    return h.hexdigest()


def content_hash(addon, patterns):
    """Hash of the workspace copy, ignoring version lines."""
    return _hash_entries((rel, path.read_bytes()) for rel, path in build_files(addon, patterns))


def zip_entries(zpath, addon_name, patterns):
    """[(relative path, bytes)] of <addon_name>/ inside a release zip, excluded files left out."""
    prefix = addon_name.lower() + "/"
    entries = []
    with zipfile.ZipFile(zpath) as zf:
        for info in zf.infolist():
            name = info.filename.replace("\\", "/")
            if info.is_dir() or not name.lower().startswith(prefix):
                continue
            rel = name[len(prefix):]
            if not is_excluded(tuple(rel.split("/")), patterns):
                entries.append((rel, zf.read(info)))
    return entries


def zip_content_hash(zpath, addon_name, patterns):
    """Hash of <addon_name>/ inside a release zip, comparable with content_hash()."""
    return _hash_entries(zip_entries(zpath, addon_name, patterns))


def next_version(version):
    """Patch bump: 1.0.3 -> 1.0.4, 0.1 -> 0.1.1."""
    parts = version.strip().lstrip("vV").split(".")
    if not all(part.isdigit() for part in parts):
        raise SyncError(f"Can't auto-bump version '{version}' - bump it by hand.")
    numbers = [int(part) for part in parts] + [0] * (3 - len(parts))
    numbers[-1] += 1
    return ".".join(map(str, numbers))


def bump_addon(addon, new_version, patterns):
    """Set the version in the addon's TOC(s) and in Lua `VERSION = "<old>"` lines. Returns files changed."""
    old, new = addon.version, new_version.encode()
    changed = []
    for toc in sorted(addon.path.glob("*.toc")):
        if not toc_matches(toc.stem, addon.name):
            continue
        data = toc.read_bytes()
        updated = re.sub(rb"^(\s*##\s*Version\s*:[ \t]*)[^\r\n]*", lambda m: m.group(1) + new,
                         data, flags=re.M | re.I)
        if updated != data:
            toc.write_bytes(updated)
            changed.append(toc.name)
    if old:
        lua_line = re.compile(rb"""^(\s*[\w.]*VERSION\s*=\s*["'])""" + re.escape(old.encode()) + rb"""(["'])""",
                              re.M)
        for rel, path in iter_files(addon.path, patterns):
            if not rel.lower().endswith(".lua"):
                continue
            data = path.read_bytes()
            updated = lua_line.sub(lambda m: m.group(1) + new + m.group(2), data)
            if updated != data:
                path.write_bytes(updated)
                changed.append(rel)
    addon.version = addon.toc["version"] = new_version
    return changed


def set_toc_field(addon, field, value):
    """Set `## field: value` in the addon's TOC file(s), adding it after the header if missing."""
    line_re = re.compile(rb"^(\s*##\s*" + re.escape(field.encode()) + rb"\s*:[ \t]*)[^\r\n]*", re.M | re.I)
    for toc in sorted(addon.path.glob("*.toc")):
        if not toc_matches(toc.stem, addon.name):
            continue
        data = toc.read_bytes()
        if line_re.search(data):
            data = line_re.sub(lambda m: m.group(1) + str(value).encode(), data)
        else:
            eol = b"\r\n" if b"\r\n" in data else b"\n"
            lines = data.split(eol)
            last_header = max((i for i, line in enumerate(lines) if line.lstrip().startswith(b"##")), default=-1)
            lines.insert(last_header + 1, f"## {field}: {value}".encode())
            data = eol.join(lines)
        toc.write_bytes(data)
    addon.toc[field.lower()] = str(value)


def compare_versions(a, b):
    """-1/0/1 comparing dotted versions like 'v1.0.3' and '1.0.10-beta'."""
    def key(v):
        parts = re.split(r"[^0-9A-Za-z]+", v.strip().lstrip("vV"))
        return [(0, int(p), "") if p.isdigit() else (1, 0, p.lower()) for p in parts if p]
    ka, kb = key(a), key(b)
    n = max(len(ka), len(kb))
    ka += [(0, 0, "")] * (n - len(ka))
    kb += [(0, 0, "")] * (n - len(kb))
    return (ka > kb) - (ka < kb)


# --------------------------------------------------------------------------- CurseForge

class CurseForge:
    def __init__(self, key, refresh=False):
        self.key = key
        self.refresh = refresh
        self.down = None  # set once CurseForge is unusable, so later calls fail fast
        self.down_error = SyncError

    def _fail(self, message, error=SyncError):
        self.down, self.down_error = message, error
        raise error(message)

    def _get(self, path, params=None):
        if self.down:
            raise self.down_error(self.down)
        if not self.key:
            self._fail("No CurseForge API key - add CURSEFORGE_KEY to .env.", Unavailable)
        url = API_BASE + path + ("?" + urllib.parse.urlencode(params) if params else "")
        req = urllib.request.Request(url, headers={
            "x-api-key": self.key, "Accept": "application/json", "User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.load(resp)
        except urllib.error.HTTPError as exc:
            if exc.code in (401, 403):
                self._fail(f"CurseForge rejected the API key (HTTP {exc.code}).")
            if exc.code >= 500 or exc.code == 429:
                self._fail(f"CurseForge API unavailable (HTTP {exc.code}).", Unavailable)
            raise SyncError(f"CurseForge API returned HTTP {exc.code} for {path}.")
        except (urllib.error.URLError, OSError, ValueError) as exc:
            self._fail(f"Cannot reach CurseForge: {getattr(exc, 'reason', exc)}", Unavailable)

    def _cached(self, name, fetch):
        path = API_CACHE_DIR / f"{name}.json"
        cached = load_json(path, None)
        if cached and not self.refresh and time.time() - cached["time"] < API_TTL_SECONDS:
            return cached["data"]
        data = fetch()
        save_json(path, {"time": time.time(), "data": data})
        return data

    def mod(self, project_id):
        return self._get(f"/v1/mods/{project_id}")["data"]

    def description(self, project_id):
        """The project page's description, as CurseForge renders it (HTML)."""
        return self._get(f"/v1/mods/{project_id}/description")["data"] or ""

    def latest_file(self, project_id, game_version_type_id=None, include_prereleases=False):
        params = {"pageSize": 50, "index": 0}
        if game_version_type_id:
            params["gameVersionTypeId"] = game_version_type_id
        files = self._cached(
            f"files_{project_id}_{game_version_type_id or 'any'}",
            lambda: self._get(f"/v1/mods/{project_id}/files", params)["data"])
        allowed = {1, 2, 3} if include_prereleases else {1}
        files = [f for f in files if f.get("releaseType") in allowed and f.get("isAvailable", True)]
        return max(files, key=lambda f: f["id"]) if files else None

    def download(self, file, addon_name):
        """Download a release into the cache as <Addon>_v<version>_<fileid>.zip (once)."""
        found = cached_zip(addon_name, file["id"])
        if found:
            return found
        url = file.get("downloadUrl")
        if not url:
            fid = file["id"]
            url = (f"https://edge.forgecdn.net/files/{fid // 1000}/{fid % 1000}/"
                   f"{urllib.parse.quote(file['fileName'])}")
        FILE_CACHE_DIR.mkdir(parents=True, exist_ok=True)
        tmp = FILE_CACHE_DIR / f"{addon_name}_{file['id']}.part"
        try:
            self._fetch(file, url, tmp)
        except (urllib.error.URLError, OSError) as exc:
            tmp.unlink(missing_ok=True)
            raise Unavailable(f"Download failed for {file.get('fileName')}: {exc}")
        if not zipfile.is_zipfile(tmp):
            tmp.unlink(missing_ok=True)
            raise SyncError(f"Downloaded {file.get('fileName')} is not a zip.")
        version = read_zip_toc(tmp, addon_name)[1].get("version") or "unknown"
        dest = FILE_CACHE_DIR / f"{addon_name}_v{safe_version(version)}_{file['id']}.zip"
        os.replace(tmp, dest)
        return dest

    def _fetch(self, file, url, dest):
        req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(req, timeout=120) as resp, open(dest, "wb") as fh:
            shutil.copyfileobj(resp, fh)

    def categories(self):
        """WoW's addon categories (not the classes they sit under)."""
        return self._cached("categories", lambda: [
            c for c in self._get("/v1/categories", {"gameId": WOW_GAME_ID})["data"] if not c.get("isClass")])

    def search(self, text):
        return self._get("/v1/mods/search", {
            "gameId": WOW_GAME_ID, "searchFilter": text, "pageSize": 20})["data"]


def safe_version(version):
    return re.sub(r"[^0-9A-Za-z-]", "_", version)


def cached_zip(addon_name, file_id):
    """This addon's cached download of a CurseForge file id, if any."""
    return next(iter(FILE_CACHE_DIR.glob(f"{addon_name}_v*_{file_id}.zip")), None)


def inspect_release_zip(zpath, addon_name):
    """Return (top-level folders, version from the addon's TOC inside the zip)."""
    folders, toc = read_zip_toc(zpath, addon_name)
    return folders, toc.get("version")


def read_zip_toc(zpath, addon_name):
    """Return (top-level folders, parsed fields of the addon's TOC inside the zip)."""
    with zipfile.ZipFile(zpath) as zf:
        names = zf.namelist()
        for n in names:
            parts = n.replace("\\", "/").split("/")
            if n.startswith(("/", "\\")) or ".." in parts or ":" in n:
                raise SyncError(f"{zpath.name} contains an unsafe path: {n}")
        folders = sorted({n.split("/")[0] for n in names if "/" in n.strip("/")})
        tocs = [n for n in names if n.lower().endswith(".toc") and n.count("/") == 1]
        toc = (next((t for t in tocs if t.split("/")[0].lower() == addon_name.lower()
                     and toc_matches(Path(t).stem, addon_name)), None)
               or next((t for t in tocs if t.split("/")[0].lower() == addon_name.lower()), None))
        fields = parse_toc(zf.read(toc).decode("utf-8-sig", errors="replace")) if toc else {}
    return folders, fields


# --------------------------------------------------------------------------- file ops

def _on_rm_error(func, path, _exc):
    os.chmod(path, stat.S_IWRITE)
    func(path)


def safe_target(wow, name):
    if not name or name in (".", "..") or any(c in name for c in "/\\:"):
        raise SyncError(f"Refusing to touch suspicious folder name: {name!r}")
    return wow / name


def remove_dir(path):
    if path.exists():
        shutil.rmtree(path, onerror=_on_rm_error)


def protect(wow, folders):
    """Back up AddOns folders before a test session first replaces them, so `stop` can restore them."""
    session = load_json(SESSION_PATH, None)
    if session and Path(session["wow"]) != wow:
        raise SyncError(f"A test session for {session['wow']} is still active - run `yarn stop` first.")
    if not session:
        session = {"wow": str(wow), "started": time.strftime("%Y-%m-%d %H:%M"), "folders": {}}
    for folder in folders:
        if folder in session["folders"]:
            continue
        target = safe_target(wow, folder)
        if target.exists():
            backup = BACKUP_DIR / "folders" / folder
            remove_dir(backup)
            try:
                shutil.copytree(target, backup)
            except OSError as exc:
                raise SyncError(f"Couldn't back up {target} - not replacing it: {exc}")
            session["folders"][folder] = "saved"
        else:
            session["folders"][folder] = "absent"
        save_json(SESSION_PATH, session)


def install_dev(addon, wow, patterns):
    target = safe_target(wow, addon.name)
    remove_dir(target)
    for rel, src in build_files(addon, patterns):
        dest = target / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        copy_build_file(src, dest)


def install_release(zpath, folders, wow):
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    tmp = Path(tempfile.mkdtemp(prefix="extract_", dir=DATA_DIR))
    try:
        with zipfile.ZipFile(zpath) as zf:
            zf.extractall(tmp)
        for folder in folders:
            target = safe_target(wow, folder)
            remove_dir(target)
            shutil.copytree(tmp / folder, target)
    finally:
        shutil.rmtree(tmp, onerror=_on_rm_error)


# --------------------------------------------------------------------------- sync

def plan_addon(addon, cfg, state, cf):
    """Decide what an addon should be. Returns a dict describing the decision."""
    st = state.get(addon.name, {})
    patterns = cfg["exclude"]
    override = cfg["overrides"].get(addon.name)
    pid = cfg["projects"].get(addon.name)
    p = {"addon": addon, "hash": source_hash(addon, patterns), "release": None,
         "mode": None, "reason": "", "warn": ""}

    if override == "skip":
        p.update(mode="skip", reason="pinned: skip")
        return p

    rel, cf_error = fetch_release(addon, cfg, cf, st) if pid else (None, None)
    if cf_error:
        p["warn"] = cf_error
    p["release"] = rel
    p["content"] = content_hash(addon, patterns)
    prefix, source = (("CF offline: ", "last downloaded release") if rel and rel.get("cached")
                      else ("", "CF release"))

    if override == "dev":
        p.update(mode="dev", reason="pinned: dev")
    elif rel and addon.name.lower() not in {f.lower() for f in rel["folders"]}:
        # Never install a zip that isn't this addon (wrong project id, or a bad download).
        p.update(mode="skip", release=None,
                 reason=f"release file {rel['file_id']} has no {addon.name}/ folder "
                        f"(contains {', '.join(rel['folders']) or 'nothing'}) - check the project id")
    elif not pid:
        p.update(mode="dev", reason="not linked to CurseForge")
    elif cf_error and not rel:
        plan_offline(p, st, override, cf_error)
    elif override == "release":
        if rel:
            p.update(mode="release", reason=f"{prefix}pinned: release")
        else:
            p.update(mode="skip", reason="pinned: release, but no CF release")
    elif not rel:
        p.update(mode="dev", reason="no release on CurseForge")
    else:
        cmp = compare_versions(addon.version, rel["version"]) if addon.version else 0
        p["release_hash"] = zip_content_hash(rel["zip"], addon.name, patterns)
        if cmp < 0:
            p.update(mode="release", reason=f"{prefix}{source} is current",
                     warn=f"workspace version is older than the {source}")
        elif p["content"] != p["release_hash"]:
            p.update(mode="dev", reason=f"{prefix}local changes since release")
        else:
            p.update(mode="release", reason=f"{prefix}no changes since {source}")

    # Needs an upload zip: linked, content differs from what was released or already shipped,
    # and the version is newer than both (CurseForge having no files yet counts as changed).
    rel = p["release"]
    if pid and addon.version and p["mode"] != "skip" and (rel or not cf_error):
        if rel and "release_hash" not in p:  # pinned modes skip the comparison above
            p["release_hash"] = zip_content_hash(rel["zip"], addon.name, patterns)
        known = {h for h in (p.get("release_hash"), st.get("shipped_hash")) if h}
        newer = all(compare_versions(addon.version, v) > 0
                    for v in (rel and rel["version"], st.get("shipped_version")) if v)
        p["publishable"] = p["content"] not in known and newer
    return p


def fetch_release(addon, cfg, cf, st):
    """(latest CurseForge release, error). Falls back to a cached download when CF can't be used."""
    try:
        f = cf.latest_file(cfg["projects"][addon.name], cfg.get("game_version_type_id"),
                           cfg.get("include_prereleases"))
        if not f:
            return None, None
        zpath = cf.download(f, addon.name)
        folders, version = inspect_release_zip(zpath, addon.name)
        return {"file_id": f["id"], "zip": zpath, "folders": folders,
                "version": version or f.get("displayName", "?")}, None
    except SyncError as exc:
        return cached_release(addon, cfg, st), str(exc)


def cached_release(addon, cfg, st):
    """The newest CurseForge release already in the download cache (for when CF is unreachable)."""
    pid = cfg["projects"].get(addon.name)
    listing = load_json(API_CACHE_DIR / f"files_{pid}_{cfg.get('game_version_type_id') or 'any'}.json", None)
    allowed = {1, 2, 3} if cfg.get("include_prereleases") else {1}
    ids = sorted((f["id"] for f in (listing or {}).get("data", [])
                  if f.get("releaseType") in allowed and f.get("isAvailable", True)), reverse=True)
    for fid in ids + [st.get("installed_file_id")]:
        zpath = cached_zip(addon.name, fid) if isinstance(fid, int) else None
        if zpath:
            try:
                folders, version = inspect_release_zip(zpath, addon.name)
            except (SyncError, zipfile.BadZipFile):
                continue
            return {"file_id": fid, "zip": zpath, "folders": folders, "version": version or "?",
                    "cached": True}
    return None


def plan_offline(p, st, override, cf_error):
    """CurseForge is unusable: decide from local state only, never removing an installed release
    unless the workspace has changed since that release was installed."""
    p["warn"] = cf_error
    has_release = st.get("installed_mode") == "release"
    unchanged = has_release and st.get("release_hash") == p["content"]
    if override == "release" or unchanged:
        p.update(mode="keep", reason="CF offline: keeping installed release" if has_release
                 else "CF offline: pinned release unavailable")
    elif has_release:
        p.update(mode="dev", reason="CF offline: local changes since release")
    else:
        p.update(mode="dev", reason="CF offline: using local copy")


def apply_plan(p, wow, state, patterns, dry_run):
    addon = p["addon"]
    st = state.setdefault(addon.name, {})
    rel = p["release"]
    if p["mode"] == "skip":
        return "skipped"
    if p["mode"] == "keep":
        return "left as is"

    if p["mode"] == "dev":
        current = (st.get("installed_mode") == "dev" and st.get("last_copied_hash") == p["hash"]
                   and installed_matches(addon, wow, patterns))
        if current:
            return "up to date"
        if dry_run:
            return "would copy dev build"
        protect(wow, [addon.name])
        install_dev(addon, wow, patterns)
        st.update(installed_mode="dev", last_copied_hash=p["hash"], installed_file_id=None)
        return "copied dev build"

    current = (st.get("installed_mode") == "release" and st.get("installed_file_id") == rel["file_id"]
               and all((wow / f).exists() for f in rel["folders"]))
    if not current:
        if dry_run:
            return f"would install release {rel['version']}"
        protect(wow, rel["folders"])
        install_release(rel["zip"], rel["folders"], wow)
        st.update(installed_mode="release", installed_file_id=rel["file_id"],
                  installed_folders=rel["folders"])
    if not dry_run:
        st["release_hash"] = p.get("release_hash") or zip_content_hash(rel["zip"], addon.name, patterns)
    return "up to date" if current else f"installed release {rel['version']}"


def print_table(rows):
    print_table_rows(("Addon", "Local", "CurseForge", "Mode", "Action", "Why"), rows)


def print_table_rows(headers, rows):
    widths = [max(len(str(r[i])) for r in [headers] + rows) for i in range(len(headers))]
    line = lambda r: "  ".join(str(c).ljust(w) for c, w in zip(r, widths)).rstrip()
    print(line(headers))
    print(line(["-" * w for w in widths]))
    for r in rows:
        print(line(r))


def run_sync(cfg, only=None, dry_run=False, refresh=False):
    wow = wow_dir(cfg)
    addons = discover(cfg)
    if only:
        addons = resolve_names(addons, only)
    state = load_json(STATE_PATH, {})
    cf = CurseForge(api_key(cfg), refresh=refresh)
    rows, warnings, removed, built, failed = [], [], [], [], False
    for addon in addons:
        try:
            p = plan_addon(addon, cfg, state, cf)
        except SyncError as exc:  # a TOC loading a shared file that isn't there
            rows.append((addon.name, addon.version or "?", "-", "-", f"FAILED: {exc}", ""))
            failed = True
            continue
        removed += clean_outbox(cfg, cf, addon, dry_run)
        if p.get("publishable"):
            try:
                zpath, made = ensure_upload_zip(cfg, addon, state, p["hash"], dry_run)
                if made:
                    built.append(zpath.name)
            except OSError as exc:
                warnings.append(f"{addon.name}: couldn't build upload zip: {exc}")
        try:
            action = apply_plan(p, wow, state, cfg["exclude"], dry_run)
        except (OSError, SyncError, zipfile.BadZipFile) as exc:
            action, failed = f"FAILED: {exc}", True
        if not dry_run:
            save_json(STATE_PATH, state)
        rel = p["release"]
        rows.append((addon.name, addon.version or "?", rel["version"] if rel else "-",
                     p["mode"], action, p["reason"]))
        if p["warn"] and p["warn"] != cf.down:
            warnings.append(f"{addon.name}: {p['warn']}")
        if p["mode"] == "skip" and not p["reason"].startswith("pinned: skip"):
            failed = True
    print(f"WoW AddOns: {wow}")
    print_table(rows)
    if cf.down:
        warnings.append(f"{cf.down} - fell back to cached releases and local checks")
    for w in warnings:
        print(f"warning: {w}")
    if removed:
        print(f"{'Would remove' if dry_run else 'Removed'} from {release_dir(cfg).name} "
              f"(already on CurseForge): {', '.join(removed)}")
    if built:
        print(f"{'Would build' if dry_run else 'Built'} in {release_dir(cfg).name}: {', '.join(built)}")
    waiting = [z.name for z, _, _ in outbox(cfg) if z.name not in removed]
    if waiting:
        print(f"Waiting in {release_dir(cfg).name} for upload: {', '.join(waiting)}\n"
              "  upload them on curseforge.com, or run `yarn deploy`")
    session = load_json(SESSION_PATH, None)
    if session:
        print(f"Test session active since {session['started']} ({len(session['folders'])} AddOns folders replaced) - "
              "`yarn stop` restores them")
    return not failed


OUTBOX_RE = re.compile(r"^(.+?)_v(\d[\w.]*)\.zip$", re.I)


def outbox(cfg):
    """[(zip, addon name, version)] waiting in release_dir, oldest version first per addon."""
    folder = release_dir(cfg)
    items = []
    for zpath in folder.glob("*.zip") if folder.is_dir() else []:
        m = OUTBOX_RE.match(zpath.name)
        items.append((zpath, m.group(1), m.group(2).replace("_", ".")) if m else (zpath, None, None))

    def order(a, b):
        na, nb = (a[1] or a[0].name).lower(), (b[1] or b[0].name).lower()
        if na != nb or not a[2] or not b[2]:
            return (na > nb) - (na < nb)
        return compare_versions(a[2], b[2])
    return sorted(items, key=functools.cmp_to_key(order))


def upload_zip_name(addon):
    return f"{addon.name}_v{addon.version.replace('.', '_')}.zip"


def ensure_upload_zip(cfg, addon, state, src_hash, dry_run=False):
    """Make release_dir/<Addon>_v<version>.zip match the workspace. Returns (path, built?)."""
    dest = release_dir(cfg) / upload_zip_name(addon)
    st = state.setdefault(addon.name, {})
    if dest.exists() and st.get("upload_zip_hash") == src_hash:
        return dest, False
    if dry_run:
        return dest, True
    previous = st.get("upload_zip")
    if previous and previous != dest.name:
        remove_outbox_item(release_dir(cfg) / previous)  # superseded by the new version
    build_release_zip(addon, cfg, release_dir(cfg))
    st.update(upload_zip=dest.name, upload_zip_hash=src_hash)
    return dest, True


def mark_shipped(cfg, state, addon, version, zpath):
    """Record what was uploaded/packaged, then bump the workspace past it (bump-after-deploy)."""
    st = state.setdefault(addon.name, {})
    st.update(shipped_version=version, shipped_hash=zip_content_hash(zpath, addon.name, cfg["exclude"]))
    st.pop("upload_zip", None)
    st.pop("upload_zip_hash", None)
    if addon.version and compare_versions(addon.version, version) <= 0:
        new = next_version(version)
        bump_addon(addon, new, cfg["exclude"])
        print(f"Bumped {addon.name} to {new} for the next release")
    save_json(STATE_PATH, state)


def deploy_status(addon, cfg, state, cf):
    """(changed?, last released/shipped version). changed is None when it can't be told."""
    patterns = cfg["exclude"]
    st = state.get(addon.name, {})
    rel, error = fetch_release(addon, cfg, cf, st) if addon.name in cfg["projects"] else (None, None)
    snapshots = [rel["zip"]] if rel else []
    mine = [i for i in outbox(cfg) if i[1] and i[1].lower() == addon.name.lower()]
    if mine:
        snapshots.append(mine[-1][0])
    known = {st["shipped_hash"]} if st.get("shipped_hash") else set()
    for zpath in snapshots:
        try:
            known.add(zip_content_hash(zpath, addon.name, patterns))
        except (OSError, zipfile.BadZipFile):
            pass
    versions = [v for v in (rel and rel["version"], st.get("shipped_version"), mine and mine[-1][2]) if v]
    last = max(versions, key=functools.cmp_to_key(compare_versions)) if versions else None
    if not known:
        return (None if error and addon.name in cfg["projects"] and cf.key else True), last
    return content_hash(addon, patterns) not in known, last


def bump_if_behind(cfg, addon, last, dry_run):
    """A changed addon whose version isn't past its last release gets bumped before shipping."""
    if last and addon.version and compare_versions(addon.version, last) <= 0:
        new = next_version(last)
        if dry_run:
            print(f"{addon.name}: would bump {addon.version} -> {new} first (version matches the last release)")
            return False
        bump_addon(addon, new, cfg["exclude"])
        print(f"Bumped {addon.name} to {new} before deploying (version matched the last release)")
    return True


def remove_outbox_item(zpath):
    zpath.unlink(missing_ok=True)
    zpath.with_suffix(".json").unlink(missing_ok=True)


def clean_outbox(cfg, cf, addon, dry_run):
    """Delete this addon's outbox zips whose version CurseForge already has. Returns their names."""
    pid = cfg["projects"].get(addon.name)
    items = [i for i in outbox(cfg) if i[1] and i[1].lower() == addon.name.lower()]
    if not pid or not items or cf.down:
        return []
    try:
        latest = cf.latest_file(pid, cfg.get("game_version_type_id"), include_prereleases=True)
        cf_version = latest and inspect_release_zip(cf.download(latest, addon.name), addon.name)[1]
    except (SyncError, zipfile.BadZipFile):
        return []
    if not cf_version:
        return []
    done = [z for z, _, version in items if compare_versions(version, cf_version) <= 0]
    if not dry_run:
        for zpath in done:
            remove_outbox_item(zpath)
    return [z.name for z in done]


# --------------------------------------------------------------------------- commands

def cmd_sync(args):
    cfg = load_config()
    only = split_names(args.only)
    if not args.watch:
        return run_sync(cfg, only, dry_run=False, refresh=args.refresh)
    print(f"Watching for changes every {args.interval}s (Ctrl+C to stop)...")
    last, refresh = {}, args.refresh
    try:
        while True:
            cfg = load_config()
            addons = discover(cfg)
            if only:
                addons = resolve_names(addons, only)
            sig = {a.name: source_signature(a, cfg["exclude"]) for a in addons}
            changed = [n for n in sig if sig[n] != last.get(n)]
            if changed:
                print(f"\n[{time.strftime('%H:%M:%S')}] syncing {', '.join(changed)}")
                try:
                    run_sync(cfg, changed, refresh=refresh)
                except SyncError as exc:
                    print(f"error: {exc}")
                last, refresh = sig, False
            time.sleep(args.interval)
    except KeyboardInterrupt:
        print("\nStopped.")
    return True


def cmd_status(args):
    return run_sync(load_config(), split_names(args.only), dry_run=True, refresh=args.refresh)


def cmd_pin(args):
    cfg = load_config()
    addons = resolve_names(discover(cfg), args.names)
    for addon in addons:
        if args.command == "auto":
            cfg["overrides"].pop(addon.name, None)
        else:
            cfg["overrides"][addon.name] = args.command
        print(f"{addon.name}: {args.command}")
    save_pins(cfg)
    return run_sync(cfg, [a.name for a in addons])


def norm(text):
    return re.sub(r"[^a-z0-9]", "", (text or "").lower())


def owned_matches(cf, addon, author):
    """(exact, all) CurseForge projects by author that could be this addon; exact ones match its
    folder name, title or project name."""
    wanted = {norm(addon.title), norm(addon.name), norm(project_name(addon))}
    results = {}
    for term in dict.fromkeys([addon.title, addon.name, project_name(addon)]):
        for mod in cf.search(term):
            results[mod["id"]] = mod
    mods = list(results.values())
    if author:
        mods = [m for m in mods if any(norm(a.get("name")) == norm(author) for a in m.get("authors", []))]
    exact = [m for m in mods if norm(m.get("name")) in wanted or norm(m.get("slug")) in wanted]
    return exact, mods


def cmd_link(args):
    cfg = load_config()
    addons = discover(cfg)
    if args.id is not None:
        if len(args.names) != 1:
            raise SyncError("--id needs exactly one addon name.")
        addon = resolve_names(addons, args.names)[0]
        set_toc_field(addon, "X-Curse-Project-ID", args.id)
        cfg["projects"][addon.name] = args.id
        print(f"{addon.name} -> {args.id}")
        return True

    targets = (resolve_names(addons, args.names) if args.names
               else [a for a in addons if a.name not in cfg["projects"] and not is_local(cfg, a)])
    if not targets:
        print("Every addon is already linked. Pass names to re-link.")
        return True
    cf = CurseForge(api_key(cfg))
    author = cfg["curseforge_author"]
    interactive = sys.stdin.isatty()
    for addon in targets:
        exact, mods = owned_matches(cf, addon, author)
        if len(exact) == 1:
            pick = exact[0]
        else:
            candidates = (exact or mods)[:10]
            print(f"\n{addon.name} ({addon.title}):")
            if not candidates:
                print("  no matches - set it by hand with: link NAME --id PROJECT_ID")
                continue
            for i, m in enumerate(candidates, 1):
                authors = ", ".join(a.get("name", "?") for a in m.get("authors", []))
                print(f"  [{i}] {m['name']}  id={m['id']}  by {authors}  ({m.get('slug')})")
            if not interactive:
                print("  (not interactive - skipped)")
                continue
            choice = input("  pick a number (blank to skip): ").strip()
            if not choice.isdigit() or not 1 <= int(choice) <= len(candidates):
                continue
            pick = candidates[int(choice) - 1]
        set_toc_field(addon, "X-Curse-Project-ID", pick["id"])
        cfg["projects"][addon.name] = pick["id"]
        print(f"{addon.name} -> {pick['name']} (id {pick['id']})")
    return True


def upload_call(cfg, path, data=None, content_type=None, errors=None):
    """Call the CurseForge Upload API (author token), mapping HTTP errors to SyncError."""
    token = upload_token(cfg)
    if not token:
        raise SyncError("No upload token - add CURSEFORGE_UPLOAD_TOKEN to .env "
                        "(create one at authors.curseforge.com -> API Tokens).")
    url = (cfg.get("upload_host") or DEFAULT_CONFIG["upload_host"]).rstrip("/") + path
    headers = {"X-Api-Token": token, "Accept": "application/json", "User-Agent": USER_AGENT}
    if content_type:
        headers["Content-Type"] = content_type
    req = urllib.request.Request(url, data=data, headers=headers,
                                 method="POST" if data is not None else "GET")
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        try:
            detail = json.loads(body).get("errorMessage") or body
        except (ValueError, AttributeError):
            detail = body
        message = (errors or {}).get(exc.code) or f"Upload API returned HTTP {exc.code} for {path}"
        error = Unavailable if exc.code >= 500 or exc.code == 429 else SyncError
        raise error(f"{message}: {detail.strip()[:500]}" if detail.strip() else message)
    except (urllib.error.URLError, OSError) as exc:
        raise Unavailable(f"Cannot reach {url}: {getattr(exc, 'reason', exc)}")


def encode_multipart(fields, files):
    boundary = uuid.uuid4().hex
    out = []
    for name, value in fields.items():
        out += [f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n'.encode(),
                value.encode(), b"\r\n"]
    for name, (filename, data, ctype) in files.items():
        out += [(f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"; '
                 f'filename="{filename}"\r\nContent-Type: {ctype}\r\n\r\n').encode(), data, b"\r\n"]
    out.append(f"--{boundary}--\r\n".encode())
    return b"".join(out), f"multipart/form-data; boundary={boundary}"


def interface_to_version(interface):
    """TOC interface number -> game version name, e.g. 11507 -> '1.15.7', 120100 -> '12.1.0'."""
    s = str(int(interface))
    if len(s) < 5:
        return None
    return f"{int(s[:-4])}.{int(s[-4:-2])}.{int(s[-2:])}"


def upload_game_versions(cfg, toc):
    """Game version names an upload is tagged with: cfg game_versions, else the TOC's ## Interface."""
    return list(cfg.get("game_versions") or [
        interface_to_version(i) for i in re.split(r"[,\s]+", toc.get("interface", "")) if i.isdigit()])


def build_release_zip(addon, cfg, folder):
    """Zip the workspace copy (same files as a dev install) into folder/<Name>_v1_0_3.zip."""
    dest = folder / upload_zip_name(addon)
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(".part")
    files = build_files(addon, cfg["exclude"])
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zf:
        for rel, path in files:
            if isinstance(path, Generated):
                zf.writestr(f"{addon.name}/{rel}", path.data)
            else:
                zf.write(path, f"{addon.name}/{rel}")
    os.replace(tmp, dest)
    return dest, len(files)


def read_changelog(args, addon):
    if args.changelog:
        return args.changelog, "text"
    path = Path(args.changelog_file) if args.changelog_file else addon.path / "CHANGELOG.md"
    if path.is_file():
        return path.read_text(encoding="utf-8"), "markdown" if path.suffix.lower() == ".md" else "text"
    if args.changelog_file:
        raise SyncError(f"Changelog file not found: {path}")
    return f"Version {addon.version}", "text"


def toc_dependencies(toc):
    """[(addon name, relation type)] from the TOC's ## Dependencies/RequiredDeps/Dep* (required)
    and ## OptionalDeps lines, Blizzard's own addons left out."""
    deps = {}
    for key, value in toc.items():
        if key.startswith(("dep", "requireddeps")):
            kind = "requiredDependency"
        elif key == "optionaldeps":
            kind = "optionalDependency"
        else:
            continue
        for name in re.split(r"[,\s]+", strip_color(value)):
            if name and not name.lower().startswith("blizzard_"):
                if deps.get(name.lower(), (None, None))[1] != "requiredDependency":
                    deps[name.lower()] = (name, kind)
    return list(deps.values())


def upload_relations(cfg, cf, toc):
    """CurseForge relations for the TOC's dependencies: through the X-Curse-Project-ID of the
    matching workspace addon, else a CurseForge project whose slug or name is exactly the folder
    name. Returns ([{"slug", "type"}], [names that couldn't be found])."""
    projects = {name.lower(): pid for name, pid in cfg["projects"].items()}
    relations, unlinked = [], []
    for name, kind in toc_dependencies(toc):
        pid = projects.get(name.lower())
        if pid:
            slug = cf.mod(pid)["slug"]
        else:
            hits = {m["slug"] for m in cf.search(name)
                    if norm(m.get("slug")) == norm(name) or norm(m.get("name")) == norm(name)}
            slug = hits.pop() if len(hits) == 1 else None
        if slug:
            relations.append({"slug": slug, "type": kind})
        else:
            unlinked.append(name)
    return relations, unlinked


def find_description(addon):
    """The addon's CurseForge page text: Description.md in the addon folder (any case), or None."""
    return next((p for p in sorted(addon.path.glob("*.md")) if p.stem.lower() == "description"), None)


def page_words(text, as_html=False):
    """Lowercased words of Markdown or HTML, so a page CurseForge rendered from the Markdown
    compares equal to it whatever the markup, link targets or typography."""
    if as_html:
        text = re.sub(r"<(script|style)\b.*?</\1>", " ", text, flags=re.S | re.I)
        text = html.unescape(re.sub(r"<[^>]+>", " ", text))
    else:
        text = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", text)  # links and images: keep the text
        text = re.sub(r"(?m)^\s*\d+[.)]\s", " ", text)  # numbered list markers aren't text in HTML
        text = re.sub(r"(?m)^\s*```[\w+-]*", " ", text)  # a code fence's language isn't shown
        # Real HTML tags are markup; placeholders like <n> or <list> are shown as text.
        text = re.sub(r"</?(?:a|b|i|u|s|em|strong|br|p|div|span|img|code|pre|hr|h[1-6]|ul|ol|li|table|thead|"
                      r"tbody|tr|td|th|sub|sup|center|font|details|summary|iframe|blockquote)\b[^>]*>", " ", text,
                      flags=re.I)
    return re.findall(r"[^\W_]+", text.lower())


def first_difference(local, live):
    """None when two word lists match, else (local excerpt, live excerpt) around the first change."""
    if local == live:
        return None
    for tag, i1, _, j1, _ in difflib.SequenceMatcher(None, local, live, autojunk=False).get_opcodes():
        if tag != "equal":
            return " ".join(local[max(0, i1 - 4):i1 + 8]), " ".join(live[max(0, j1 - 4):j1 + 8])
    return None


def addon_summary(addon):
    """(the project page's one-line summary, where it came from): description.txt, else the TOC's ## Notes."""
    summary_file = next((p for p in sorted(addon.path.glob("*.txt")) if p.stem.lower() == "description"), None)
    if summary_file:
        return summary_file.read_text(encoding="utf-8-sig").strip(), summary_file.name
    return strip_color(addon.toc.get("notes")), "the TOC's ## Notes"


def page_drift(cf, addon, pid):
    """(project, [(field, what to paste, detail)]) where the CurseForge page differs from the workspace:
    the summary against description.txt (else the TOC's ## Notes), the description against Description.md."""
    mod = cf.mod(pid)
    drift = []
    summary, source = addon_summary(addon)
    if summary and page_words(summary) != page_words(mod.get("summary") or ""):
        drift.append(("Summary", source, (summary, mod.get("summary") or "(empty)")))
    desc = find_description(addon)
    if desc:
        diff = first_difference(page_words(desc.read_text(encoding="utf-8-sig")),
                                page_words(cf.description(pid), as_html=True))
        if diff:
            drift.append(("Description", desc.name,
                          f"first difference - here: \"...{diff[0]}...\", on CurseForge: \"...{diff[1] or '(empty)'}...\""))
    return mod, drift


def report_pages(cfg, cf, addons):
    """Say which CurseForge project pages need their summary or description pasted in by hand:
    the Upload API can't change them. Returns True when every page matches."""
    linked = [a for a in addons if a.name in cfg["projects"]]
    if not linked or not cf.key or cf.down:
        return True
    stale, failed = [], []
    for addon in linked:
        try:
            mod, drift = page_drift(cf, addon, cfg["projects"][addon.name])
        except SyncError as exc:
            failed.append(f"{addon.name} ({exc})")
            continue
        if drift:
            stale.append((addon, mod, drift))
    print()
    if failed:
        print(f"Couldn't compare page text for: {', '.join(failed)}")
    if not stale:
        print(f"CurseForge pages: summary and description match the workspace for all {len(linked) - len(failed)} checked.")
        return True
    print("== Update on CurseForge by hand (uploads can't change project pages)")
    for addon, mod, drift in stale:
        url = (mod.get("links") or {}).get("websiteUrl") or f"project {mod.get('id')}"
        print(f"  {addon.name}  {url}")
        for field, source, detail in drift:
            if field == "Summary":
                print(f"    Summary      paste {source}:")
                print(f"                 {detail[0]}")
                print(f"                 (CurseForge has: {detail[1]})")
            else:
                print(f"    Description  paste {addon.path.relative_to(ROOT).as_posix()}/{source}")
                print(f"                 {detail}")
    return False


def publish_zip(cfg, cf, addon, zpath, meta, yes=False, dry_run=False):
    """Check and upload one zip. Returns ("uploaded", file id), ("already", CurseForge's version),
    ("cancelled", None) or ("dry-run", None). Raises Unavailable if CurseForge can't be reached."""
    if not cf.key or not upload_token(cfg):
        # Not set up with CurseForge yet: same as an outage, the zip waits for a manual upload.
        missing = " and ".join(n for n, v in (("CURSEFORGE_KEY", cf.key),
                                              ("CURSEFORGE_UPLOAD_TOKEN", upload_token(cfg))) if not v)
        raise Unavailable(f"{missing} not set yet")
    pid = cfg["projects"].get(addon.name)
    if not pid:
        raise SyncError(f"{addon.name} isn't linked to a CurseForge project - run `link {addon.name}` first.")
    author = (cfg.get("curseforge_author") or "").strip()
    if not author:
        raise SyncError("Add CURSEFORGE_AUTHOR (your CurseForge username) to .env before publishing.")
    _, toc = read_zip_toc(zpath, addon.name)
    version = toc.get("version") or meta.get("version")
    if not version:
        raise SyncError(f"{zpath.name} has no '## Version:' in its TOC.")

    # Account check: the Upload API can't say who a token belongs to, so at least make sure
    # the project we're about to upload to is owned by the configured author.
    mod = cf.mod(pid)
    authors = [a.get("name", "?") for a in mod.get("authors", [])]
    if norm(author) not in {norm(a) for a in authors}:
        raise SyncError(f"Project {pid} ({mod.get('name')}) is owned by {', '.join(authors) or 'nobody'}, "
                        f"not '{author}'. Refusing to publish.")

    old = None
    latest = cf.latest_file(pid, cfg.get("game_version_type_id"), include_prereleases=True)
    if latest:
        folders, old = inspect_release_zip(cf.download(latest, addon.name), addon.name)
        if addon.name.lower() not in {f.lower() for f in folders} and not meta.get("force"):
            raise SyncError(f"Project {pid} ({mod.get('name')}) currently ships {', '.join(folders) or 'nothing'}, "
                            f"not {addon.name}/ - wrong project id? (--force to publish anyway)")
        old = old or latest.get("displayName")
        if old and compare_versions(version, old) <= 0 and not meta.get("force"):
            return "already", old

    game_versions = upload_call(cfg, "/api/game/versions", errors={
        401: "Upload token is invalid or revoked", 403: "Upload token is invalid or revoked"})
    wanted = meta.get("game_versions") or upload_game_versions(cfg, toc)
    by_name = {}
    for v in game_versions:
        by_name.setdefault(v.get("name"), v["id"])
    ids = list(dict.fromkeys(by_name[w] for w in wanted if w in by_name))
    missing = [w for w in wanted if w not in by_name]
    if missing:
        print(f"warning: no CurseForge game version named {', '.join(map(str, missing))} (skipped)")
    if not ids:
        raise SyncError("No game versions matched - pass --game-versions, e.g. --game-versions 1.15.7")

    relations, unlinked = upload_relations(cfg, cf, toc)
    if unlinked:
        print(f"warning: no CurseForge project found for dependency {', '.join(unlinked)} - "
              "link it, or add that relation on CurseForge by hand")

    changelog = meta.get("changelog") or f"Version {version}"
    release_type = meta.get("releaseType") or "release"
    manual = bool(meta.get("manual"))
    print(f"Account check  : project owned by {', '.join(authors)} (expected '{author}') OK")
    print(f"Project        : {mod.get('name')} (id {pid})")
    print(f"Version        : {old or 'none'} -> {version}")
    print(f"File           : {zpath.name}")
    print(f"Game versions  : {', '.join(w for w in wanted if w in by_name)}")
    print(f"Release type   : {release_type}{' (manual release - hidden until approved)' if manual else ''}")
    print(f"Changelog      : {changelog.splitlines()[0] if changelog else ''}")
    shown = ", ".join(f"{r['slug']} ({r['type']})" for r in relations)
    print(f"Relations      : {shown or 'none'}")
    if dry_run:
        print("Dry run - nothing uploaded.")
        return "dry-run", None
    if not yes:
        if not sys.stdin.isatty():
            raise SyncError("Not interactive - pass --yes to publish.")
        try:
            answer = input("Publish? [y/N] ")
        except EOFError:
            raise SyncError("No answer to the confirmation prompt - pass --yes to publish.")
        if answer.strip().lower() not in ("y", "yes"):
            print("Cancelled.")
            return "cancelled", None

    metadata = {"changelog": changelog, "changelogType": meta.get("changelogType") or "text",
                "displayName": f"{addon.name} v{version}", "gameVersions": ids,
                "releaseType": release_type}
    if manual:
        metadata["isMarkedForManualRelease"] = True
    if relations:
        metadata["relations"] = {"projects": relations}
    body, content_type = encode_multipart({"metadata": json.dumps(metadata)},
                                          {"file": (zpath.name, zpath.read_bytes(), "application/zip")})
    denied = (f"This token's account can't upload to project {pid} ({mod.get('name')}) - "
              "was it created on the wrong CurseForge account?")
    result = upload_call(cfg, f"/api/projects/{pid}/upload-file", body, content_type,
                         errors={401: "Upload token is invalid or revoked", 403: denied})
    print(f"Uploaded {zpath.name} as CurseForge file id {result.get('id')}.")
    return "uploaded", result.get("id")


def after_upload(cfg, addon, manual):
    pid = cfg["projects"][addon.name]
    for cached in API_CACHE_DIR.glob(f"files_{pid}_*.json"):
        cached.unlink(missing_ok=True)
    if manual:
        print("Marked for manual release - approve it on CurseForge, then run sync.")
        return True
    print("CurseForge may take a few minutes to process it; until then sync keeps your dev build.")
    return run_sync(cfg, [addon.name], refresh=True)


def lint(addons):
    """tools/lint.py over these addons: Lua that doesn't compile or a TOC naming a missing file
    stops the command before anything ships."""
    names = [a.name for a in addons]
    if subprocess.call([sys.executable, "-I", str(ROOT / "tools" / "lint.py"), "-q", *names]) != 0:
        raise SyncError("lint found errors (above) - fix them first, or run `yarn lint` for details.")


def ensure_projects(cfg, cf, addons, dry_run=False):
    """Give every addon that ships (everything not in Local.dat) a CurseForge project: link the one
    you already own, else create it on the authors site (tools/curseforge/create_projects.py drives
    a browser). Returns the addons, re-read when new project ids were written to their TOCs."""
    missing = [a for a in addons if a.version and not is_local(cfg, a) and a.name not in cfg["projects"]
               and cfg["overrides"].get(a.name) != "skip"]
    if not missing or not cf.key:
        return addons
    create = []
    for addon in missing:
        try:
            exact, _ = owned_matches(cf, addon, cfg["curseforge_author"])
        except SyncError as exc:
            print(f"{addon.name}: can't look for an existing project ({exc}) - not creating one")
            continue
        if len(exact) == 1:
            pick = exact[0]
            print(f"{addon.name}: {'would link' if dry_run else 'linked'} to your project {pick['name']} (id {pick['id']})")
            if not dry_run:
                set_toc_field(addon, "X-Curse-Project-ID", pick["id"])
                cfg["projects"][addon.name] = pick["id"]
        elif exact:
            print(f"{addon.name}: several of your projects match - pick one with `yarn link {addon.name}`")
        else:
            create.append(addon)
    if not create:
        return addons
    names = ", ".join(f"{a.name} as \"{project_name(a)}\"" for a in create)
    if dry_run:
        print(f"Would create CurseForge projects: {names}")
        return addons
    print(f"Not on CurseForge yet - creating {names}")
    subprocess.call([sys.executable, "-I", str(CREATE_SCRIPT), *[a.name for a in create]])
    fresh = discover(cfg)
    for addon in fresh:
        pid = addon.toc.get("x-curse-project-id", "").strip()
        if pid.isdigit():
            cfg["projects"][addon.name] = int(pid)
    return fresh


def cmd_publish(args):
    cfg = load_config()
    addons = discover(cfg)
    picked = resolve_names(addons, [args.name]) if args.name and not args.queued else addons
    if args.name and not args.queued and is_local(cfg, picked[0]):
        raise SyncError(f"{picked[0].name} is listed in {LOCAL_PATH.name} (local only) - not published. "
                        f"Take it out of {LOCAL_PATH.name} to ship it.")
    lint(picked)
    cf = CurseForge(api_key(cfg), refresh=True)
    if args.queued:
        ok = publish_outbox(cfg, cf, addons, args)
    elif not args.name:
        ok = publish_all(cfg, cf, addons, args)
    else:
        picked = ensure_projects(cfg, cf, picked, args.dry_run)
        ok = publish_addon(cfg, cf, picked[0], args)
    report_pages(cfg, cf, picked)  # after the uploads: page text is edited on the website
    return ok


def publish_all(cfg, cf, addons, args):
    """Upload what's waiting in SourceCode, then every linked addon whose version is newer than
    CurseForge's (saved to SourceCode instead when CurseForge is unavailable)."""
    if args.changelog or args.changelog_file or args.game_versions:
        raise SyncError("--changelog, --changelog-file and --game-versions need an addon name.")
    if not cf.key:
        return package_all(cfg, addons, args)
    ok = True
    if outbox(cfg):
        print(f"== Waiting in {release_dir(cfg).name}")
        ok = publish_outbox(cfg, cf, addons, args)
    addons = ensure_projects(cfg, cf, addons, args.dry_run)

    state = load_json(STATE_PATH, {})
    candidates = []
    for addon in addons:
        if (addon.name not in cfg["projects"] or not addon.version or is_local(cfg, addon)
                or cfg["overrides"].get(addon.name) == "skip"):
            continue
        try:
            changed, last = deploy_status(addon, cfg, state, cf)
        except SyncError as exc:
            print(f"{addon.name}: {exc} - skipped")
            ok = False
            continue
        if changed is None:
            print(f"{addon.name}: CurseForge unavailable and nothing cached to compare - skipped")
        elif changed:
            candidates.append((addon, last))
    if not candidates:
        print("Nothing to deploy - no addon has changes since its last release.")
        return ok
    print("To deploy: " + ", ".join(f"{a.name} (last release {k or 'none'})" for a, k in candidates))
    for addon, _ in candidates:
        print(f"\n== {addon.name}")
        try:
            ok = publish_addon(cfg, cf, addon, args, checked=True) and ok
        except SyncError as exc:
            print(f"error: {exc}")
            ok = False
    return ok


def publish_addon(cfg, cf, addon, args, checked=False):
    """Build and upload one addon; when CurseForge is unavailable, save the zip to SourceCode.
    Afterwards the workspace version is bumped for the next release."""
    if not addon.version:
        raise SyncError(f"{addon.name}'s TOC has no '## Version:' line.")
    state = load_json(STATE_PATH, {})
    if not args.force:
        changed, last = deploy_status(addon, cfg, state, cf)
        if changed is False and not checked:
            print(f"{addon.name} has no changes since its last release (only the version differs) - "
                  "nothing to deploy. Use --force to ship it anyway.")
            return True
        if not bump_if_behind(cfg, addon, last, args.dry_run):
            return True
    meta = upload_meta(args, addon)

    # Upload the zip sync keeps in SourceCode, (re)building it if it's missing or out of date.
    src_hash = source_hash(addon, cfg["exclude"])
    temp = False
    if args.dry_run:
        zpath, stale = ensure_upload_zip(cfg, addon, state, src_hash, dry_run=True)
        if stale:  # don't touch SourceCode on a dry run
            zpath, _ = build_release_zip(addon, cfg, DATA_DIR / "build")
            temp = True
    else:
        zpath, stale = ensure_upload_zip(cfg, addon, state, src_hash)
        save_json(STATE_PATH, state)
    print(f"{'Built' if stale else 'Using'} {zpath.name}")
    try:
        outcome, detail = publish_zip(cfg, cf, addon, zpath, meta, args.yes, args.dry_run)
    except Unavailable as exc:
        if args.dry_run:
            raise
        # Can't auto-push: the zip stays in SourceCode for a manual upload.
        save_json(zpath.with_suffix(".json"), meta)
        print(f"CurseForge unavailable: {exc}")
        print(f"{zpath} is ready to upload (changelog and settings in {zpath.with_suffix('.json').name}).\n"
              "Upload it on curseforge.com and delete it, or run `yarn deploy` later.\n"
              "Sync deletes it automatically once CurseForge has this version.")
        mark_shipped(cfg, state, addon, meta["version"], zpath)
        return True
    finally:
        if temp:
            zpath.unlink(missing_ok=True)
    if outcome == "already":
        if not temp and not args.dry_run:
            remove_outbox_item(zpath)
        raise SyncError(f"Local version {addon.version} is not newer than CurseForge's {detail}. "
                        "Bump '## Version:' in the TOC, or pass --force.")
    if outcome == "uploaded":
        mark_shipped(cfg, state, addon, meta["version"], zpath)
        remove_outbox_item(zpath)
        return after_upload(cfg, addon, args.manual)
    return True


def upload_meta(args, addon):
    """Upload settings for an addon's current version (also saved next to a waiting zip)."""
    changelog, changelog_type = read_changelog(args, addon)
    return {"addon": addon.name, "version": addon.version, "changelog": changelog,
            "changelogType": changelog_type, "releaseType": args.type, "manual": args.manual,
            "force": args.force, "game_versions": split_names(args.game_versions)}


def package_all(cfg, addons, args):
    """No CurseForge key yet: package every addon whose content changed since its last release
    (or last packaged zip) for a manual upload, then bump it for the next release."""
    folder = release_dir(cfg)
    state = load_json(STATE_PATH, {})
    cf = CurseForge("")
    packaged = []
    for addon in addons:
        if not addon.version or is_local(cfg, addon) or cfg["overrides"].get(addon.name) == "skip":
            continue
        changed, last = deploy_status(addon, cfg, state, cf)
        if not changed:
            continue
        if not bump_if_behind(cfg, addon, last, args.dry_run):
            packaged.append(f"{addon.name} (after a bump)")
            continue
        label = f"{addon.name} {addon.version} (last release {last or 'none'})"
        if not args.dry_run:
            zpath, _ = ensure_upload_zip(cfg, addon, state, source_hash(addon, cfg["exclude"]))
            save_json(zpath.with_suffix(".json"), upload_meta(args, addon))
            mark_shipped(cfg, state, addon, addon.version, zpath)
        packaged.append(label)

    print("No CURSEFORGE_KEY yet - packaging for a manual upload instead of uploading.")
    if packaged:
        print(f"{'Would package' if args.dry_run else 'Packaged in ' + folder.name}:")
        for line in packaged:
            print(f"  {line}")
        print(f"Upload the zips in {folder} on curseforge.com (changelog and settings are in the .json "
              "next to each), then delete them.")
    else:
        print("Nothing to package - no addon has changes since its last release.")
    return True


def publish_outbox(cfg, cf, addons, args):
    items = outbox(cfg)
    if not items:
        print(f"Nothing waiting in {release_dir(cfg).name}.")
        return True
    by_lower = {a.name.lower(): a for a in addons}
    ok = True
    for zpath, name, version in items:
        state = load_json(STATE_PATH, {})  # after_upload's sync may have written it
        addon = by_lower.get((name or "").lower())
        if not addon:
            print(f"\n{zpath.name}: no matching addon in {cfg['source_dir']} - left in place")
            continue
        print(f"\n== {zpath.name}")
        if addon.version and compare_versions(version, addon.version) == 0 and not args.dry_run:
            # The workspace may have changed since sync built this zip.
            if ensure_upload_zip(cfg, addon, state, source_hash(addon, cfg["exclude"]))[1]:
                save_json(STATE_PATH, state)
                print(f"Rebuilt {zpath.name} from the current workspace")
        meta = load_json(zpath.with_suffix(".json"), None)
        if meta is None:  # built by sync: take settings from this run
            meta = {"releaseType": args.type, "manual": args.manual}
            if addon.version and compare_versions(version, addon.version) == 0:
                meta["changelog"], meta["changelogType"] = read_changelog(args, addon)
        try:
            outcome, detail = publish_zip(cfg, cf, addon, zpath, meta, args.yes, args.dry_run)
        except Unavailable as exc:
            print(f"CurseForge unavailable: {exc} - everything stays in {release_dir(cfg).name}.")
            return False
        except (SyncError, zipfile.BadZipFile) as exc:
            print(f"error: {exc} - left in {release_dir(cfg).name}")
            ok = False
            continue
        if outcome == "already":
            if not args.dry_run:
                remove_outbox_item(zpath)
            print(f"CurseForge already has {detail} - {'would remove' if args.dry_run else 'removed'} {zpath.name}")
        elif outcome == "uploaded":
            mark_shipped(cfg, state, addon, version, zpath)
            remove_outbox_item(zpath)
            ok = after_upload(cfg, addon, meta.get("manual")) and ok
    return ok


def diff_release(addon, patterns, zpath):
    """(added, removed, changed) paths between the workspace and <addon>/ in a release zip.
    Version lines are ignored, like content_hash()."""
    local = dict(build_files(addon, patterns))
    released = dict(zip_entries(zpath, addon.name, patterns))
    changed = [rel for rel in sorted(set(local) & set(released))
               if normalize_content(rel, local[rel].read_bytes()) != normalize_content(rel, released[rel])]
    return sorted(set(local) - set(released)), sorted(set(released) - set(local)), changed


def print_paths(label, paths, limit=None):
    if not paths:
        return
    shown = paths if limit is None else paths[:limit]
    print(f"    {label} ({len(paths)}):")
    for rel in shown:
        print(f"      {rel}")
    if len(shown) < len(paths):
        print(f"      ... and {len(paths) - len(shown)} more (--files lists them all)")


def check_outbox(cfg, cf, addons, only=None):
    """What `deploy` would do with the zips waiting in release_dir. Returns their upload labels."""
    picked = {a.name.lower() for a in only} if only else None
    items = [i for i in outbox(cfg) if picked is None or (i[1] or "").lower() in picked]
    if not items:
        return []
    by_lower = {a.name.lower(): a for a in addons}
    uploads = []
    print(f"== Waiting in {release_dir(cfg).name} (uploaded first)")
    for zpath, name, version in items:
        addon = by_lower.get((name or "").lower())
        pid = addon and cfg["projects"].get(addon.name)
        if not addon:
            print(f"  {zpath.name}: no matching addon - left in place")
            continue
        if not pid:
            print(f"  {zpath.name}: {addon.name} isn't linked - would fail (run `yarn link {addon.name}`)")
            continue
        try:
            latest = cf.latest_file(pid, cfg.get("game_version_type_id"), include_prereleases=True)
            cf_version = latest and (inspect_release_zip(cf.download(latest, addon.name), addon.name)[1]
                                     or latest.get("displayName"))
        except (SyncError, zipfile.BadZipFile) as exc:
            print(f"  {zpath.name}: can't compare with CurseForge ({exc})")
            continue
        if cf_version and compare_versions(version, cf_version) <= 0:
            print(f"  {zpath.name}: CurseForge already has {cf_version} - would be removed, not uploaded")
        else:
            with zipfile.ZipFile(zpath) as zf:
                count = sum(1 for i in zf.infolist() if not i.is_dir())
            print(f"  {zpath.name}: WOULD UPLOAD {version} over {cf_version or 'nothing'} ({count} files)")
            uploads.append(f"{zpath.name} (queued)")
    print()
    return uploads


def cmd_check(args):
    """Read-only preview of `deploy`: every addon matched with its CurseForge project and latest
    file, and exactly what would be uploaded. Writes nothing but the download cache."""
    cfg = load_config()
    every = discover(cfg)
    addons = resolve_names(every, args.names) if args.names else every
    cf = CurseForge(api_key(cfg), refresh=args.refresh)
    patterns = cfg["exclude"]
    author = cfg["curseforge_author"]
    token = upload_token(cfg)
    state = load_json(STATE_PATH, {})

    print("Setup")
    print(f"  CURSEFORGE_KEY           {'set' if cf.key else 'MISSING - deploy packages zips for a manual upload'}")
    print(f"  CURSEFORGE_UPLOAD_TOKEN  {'set' if token else 'MISSING - uploads fail'}")
    print(f"  CURSEFORGE_AUTHOR        {author or 'MISSING - uploads are refused'}")
    print(f"  Never shipped            {', '.join(patterns)}")
    game_versions = None
    if token:
        try:
            game_versions = {v.get("name") for v in upload_call(cfg, "/api/game/versions", errors={
                401: "Upload token is invalid or revoked", 403: "Upload token is invalid or revoked"})}
        except SyncError as exc:
            print(f"  Upload API               {exc}")
    print()

    deploying = check_outbox(cfg, cf, every, addons if args.names else None) if cf.key else []
    rows, blocked = [], []
    for addon in addons:
        pid = cfg["projects"].get(addon.name)
        print(f"== {addon.name} {addon.version or '(no version)'}")
        rel = None
        if pid:
            try:
                mod = cf.mod(pid)
                owners = [a.get("name", "?") for a in mod.get("authors", [])]
                owned = bool(author) and norm(author) in {norm(o) for o in owners}
                print(f"  Project     {mod.get('name')} (id {pid}) by {', '.join(owners) or 'nobody'}"
                      f"{'' if owned or not author else f' - NOT {author}'}")
                print(f"  Page        {(mod.get('links') or {}).get('websiteUrl') or '-'}")
            except SyncError as exc:
                owned = None
                print(f"  Project     id {pid} - can't look it up: {exc}")
            rel, error = fetch_release(addon, cfg, cf, state.get(addon.name, {}))
            if rel:
                print(f"  CurseForge  {rel['version']} (file {rel['file_id']}{', cached copy' if rel.get('cached') else ''})"
                      f" ships {', '.join(rel['folders']) or 'nothing'}")
            else:
                print(f"  CurseForge  {'no files yet' if not error else error}")
        else:
            owned = None
            print("  Project     not linked")
            if cf.key and not cf.down:
                try:
                    hits = {m["id"]: m for term in dict.fromkeys([addon.title, addon.name]) for m in cf.search(term)}
                    mine = [m for m in hits.values()
                            if not author or any(norm(a.get("name")) == norm(author) for a in m.get("authors", []))]
                    wanted = {norm(addon.title), norm(addon.name)}
                    for m in [m for m in mine if norm(m.get("name")) in wanted or norm(m.get("slug")) in wanted][:3]:
                        print(f"  Candidate   {m['name']} (id {m['id']}) - `yarn link {addon.name}` to link it")
                except SyncError:
                    pass

        def verdict(text, why=""):
            print(f"  Verdict     {text}{f' - {why}' if why else ''}\n")
            rows.append((addon.name, addon.version or "?", rel["version"] if rel else "-", text, why))

        if is_local(cfg, addon):
            verdict("LOCAL", f"listed in {LOCAL_PATH.name} - never published")
            continue
        if not addon.version:
            verdict("SKIP", "no '## Version:' in the TOC")
            continue
        if cfg["overrides"].get(addon.name) == "skip":
            verdict("SKIP", "pinned: skip")
            continue
        if cf.key and not pid:
            verdict("CREATE", f"not on CurseForge yet - deploy links your existing project or creates "
                              f"\"{project_name(addon)}\" in a browser, then uploads it")
            continue
        if rel and addon.name.lower() not in {f.lower() for f in rel["folders"]}:
            verdict("BLOCKED", f"CurseForge file has no {addon.name}/ folder - wrong project id?")
            blocked.append(addon.name)
            continue
        try:
            changed, last = deploy_status(addon, cfg, state, cf)
        except SyncError as exc:
            verdict("ERROR", str(exc))
            blocked.append(addon.name)
            continue
        if changed is None:
            verdict("UNKNOWN", "CurseForge unavailable and nothing cached to compare")
            continue
        if not changed:
            why = f"same files as {last or 'the last release'} (version lines ignored)"
            if pid and last and (not rel or compare_versions(last, rel["version"]) > 0):
                why += (f"; CurseForge lists {rel['version'] if rel else 'nothing'} yet - if {last} isn't "
                        f"processing there, `yarn deploy {addon.name} --force` uploads it")
            verdict("UP TO DATE", why)
            continue

        version = addon.version
        if last and compare_versions(version, last) <= 0:
            version = next_version(last)
            print(f"  Version     {addon.version} is not past {last} - deploy bumps it to {version} first")
        files = build_files(addon, patterns)
        size = sum(path.stat().st_size for _, path in files)
        name = f"{addon.name}_v{version.replace('.', '_')}.zip"
        print(f"  Zip         {name}: {len(files)} files, {size / 1024:.0f} KB, all under {addon.name}/")
        if args.files:
            print_paths("Contents", [rel for rel, _ in files])
        if rel:
            added, removed, edited = diff_release(addon, patterns, rel["zip"])
            print(f"  Changes vs  {rel['version']}: {len(added)} added, {len(edited)} changed, {len(removed)} removed")
            limit = None if args.files else 15
            print_paths("Added", added, limit)
            print_paths("Changed", edited, limit)
            print_paths("Removed", removed, limit)
        else:
            print("  Changes vs  nothing on CurseForge yet - every file is new")
        wanted = upload_game_versions(cfg, addon.toc)
        known = "" if game_versions is None else (
            " (" + ", ".join(f"{w} {'OK' if w in game_versions else 'UNKNOWN to CurseForge'}" for w in wanted) + ")")
        print(f"  Game        {', '.join(map(str, wanted)) or 'none - pass --game-versions'}{known}")
        deps = toc_dependencies(addon.toc)
        print(f"  Relations   {', '.join(f'{n} ({k})' for n, k in deps) or 'none'}")
        changelog = "CHANGELOG.md" if (addon.path / "CHANGELOG.md").is_file() else f'none - uploads say "Version {version}"'
        print(f"  Changelog   {changelog}")

        if not cf.key:
            verdict("PACKAGE", f"v{version} zipped to {release_dir(cfg).name} for a manual upload (no CURSEFORGE_KEY)")
            deploying.append(f"{addon.name} {version} (package)")
            continue
        problems = [why for bad, why in ((not token, "no CURSEFORGE_UPLOAD_TOKEN"),
                                         (not author, "no CURSEFORGE_AUTHOR"),
                                         (owned is False, f"project isn't owned by {author}"),
                                         (game_versions is not None and not any(w in game_versions for w in wanted),
                                          "no game version CurseForge knows"))
                    if bad]
        if problems:
            verdict("BLOCKED", "; ".join(problems))
            blocked.append(addon.name)
        else:
            verdict("DEPLOY", f"v{version} over {last or 'nothing'}")
            deploying.append(f"{addon.name} {version}")

    print_table_rows(("Addon", "Local", "CurseForge", "Verdict", "Why"), rows)
    print()
    if cf.down:
        print(f"warning: {cf.down} - compared against cached releases where possible")
    print(f"`yarn deploy` would ship: {', '.join(deploying) if deploying else 'nothing'}")
    if blocked:
        print(f"Blocked: {', '.join(blocked)} - fix the problems above first")
    report_pages(cfg, cf, addons)
    return not blocked


def cmd_bump(args):
    cfg = load_config()
    addons = discover(cfg)
    targets = resolve_names(addons, args.names) if args.names else addons
    if args.to and len(targets) != 1:
        raise SyncError("--to needs exactly one addon name.")
    lint(targets)
    for addon in targets:
        if not addon.version:
            print(f"{addon.name}: no '## Version:' line - skipped")
            continue
        old = addon.version
        files = bump_addon(addon, args.to or next_version(old), cfg["exclude"])
        print(f"{addon.name}: {old} -> {addon.version}  ({', '.join(files)})")
    return True


def cmd_stop(args):
    """End the test session: delete what sync installed and put the original folders back."""
    session = load_json(SESSION_PATH, None)
    if not session:
        print("No test session to stop.")
        return True
    wow = Path(session["wow"])
    state = load_json(STATE_PATH, {})
    failed = []
    for folder, kind in list(session["folders"].items()):
        try:
            target = safe_target(wow, folder)
            remove_dir(target)
            if kind == "saved":
                shutil.copytree(BACKUP_DIR / "folders" / folder, target)
        except (OSError, SyncError) as exc:
            print(f"{folder}: FAILED: {exc}")
            failed.append(folder)
            continue
        print(f"{folder}: {'restored' if kind == 'saved' else 'removed (was not installed before)'}")
        del session["folders"][folder]
        remove_dir(BACKUP_DIR / "folders" / folder)
        for name, st in state.items():
            if name.lower() == folder.lower() or folder in st.get("installed_folders", []):
                for key in ("installed_mode", "installed_file_id", "installed_folders", "last_copied_hash"):
                    st.pop(key, None)
    save_json(STATE_PATH, state)
    if failed:
        save_json(SESSION_PATH, session)
        print(f"Couldn't restore {', '.join(failed)} - backups kept in {BACKUP_DIR}; run stop again.")
        return False
    remove_dir(BACKUP_DIR)
    print(f"Test session from {session['started']} stopped - {wow} is back to how it was.")
    return True


def guess_wow_dirs():
    bases = [Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / "World of Warcraft",
             Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "World of Warcraft"]
    bases += [Path(f"{d}:/World of Warcraft") for d in "CDEFG"]
    bases += [Path(f"{d}:/Games/World of Warcraft") for d in "CDEFG"]
    found = []
    for base in bases:
        try:
            for flavor in sorted(base.iterdir()):
                addons = flavor / "Interface" / "AddOns"
                if addons.is_dir() and addons not in found:
                    found.append(addons)
        except OSError:
            pass
    return found


def cmd_init(args):
    load_dotenv()
    if os.environ.get("CURSEFORGE_KEY") and os.environ.get("WOW_INSTALL") and not args.force:
        print(f"{ENV_PATH.name} already has CURSEFORGE_KEY and WOW_INSTALL (use --force to change them).")
        return True
    values = {}
    key = input("CurseForge API key (console.curseforge.com, blank to skip): ").strip()
    if key:
        values["CURSEFORGE_KEY"] = key
    token = input("CurseForge upload token for publishing (authors.curseforge.com, blank to skip): ").strip()
    if token:
        values["CURSEFORGE_UPLOAD_TOKEN"] = token
    author = input("Your CurseForge username (blank to skip): ").strip()
    if author:
        values["CURSEFORGE_AUTHOR"] = author
    found = guess_wow_dirs()
    for i, path in enumerate(found, 1):
        print(f"  [{i}] {path}")
    prompt = "WoW AddOns folder (number or path): " if found else "WoW folder or AddOns folder path: "
    answer = input(prompt).strip().strip('"')
    if answer.isdigit() and 1 <= int(answer) <= len(found):
        answer = str(found[int(answer) - 1])
    if answer:
        values["WOW_INSTALL"] = answer.replace("\\", "/")
    if values:
        set_dotenv(values)
        print(f"Saved {', '.join(values)} to {ENV_PATH.name} (gitignored).")
    print("Next: `yarn link`, then `yarn status`.")
    return True


def split_names(values):
    return [n for v in (values or []) for n in v.split(",") if n.strip()] or None


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Install dev builds or CurseForge releases into your WoW AddOns folder.")
    sub = parser.add_subparsers(dest="command")

    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--only", action="append", metavar="NAME[,NAME]",
                        help="limit to these addons")
    common.add_argument("--refresh", action="store_true",
                        help="ignore the 10-minute CurseForge API cache")

    p = sub.add_parser("sync", parents=[common], help="apply (default)")
    p.add_argument("--watch", action="store_true", help="re-sync whenever addon files change")
    p.add_argument("--interval", type=float, default=2.0, help="watch poll interval in seconds")
    p.set_defaults(func=cmd_sync)

    sub.add_parser("status", parents=[common], help="dry run").set_defaults(func=cmd_status)

    for mode, text in (("dev", "always install the workspace copy"),
                       ("release", "always install the CurseForge release"),
                       ("skip", "never touch this addon"),
                       ("auto", "clear the pin")):
        p = sub.add_parser(mode, help=text)
        p.add_argument("names", nargs="+")
        p.set_defaults(func=cmd_pin)

    p = sub.add_parser("link", help="find CurseForge project ids")
    p.add_argument("names", nargs="*")
    p.add_argument("--id", type=int, help="set this project id for the single named addon")
    p.set_defaults(func=cmd_link)

    p = sub.add_parser("publish", help="zip the workspace copy and upload it to CurseForge")
    p.add_argument("name", nargs="?")
    p.add_argument("--queued", action="store_true",
                   help="upload the zips waiting in release_dir (SourceCode) instead")
    p.add_argument("--type", choices=("release", "beta", "alpha"), default="release")
    group = p.add_mutually_exclusive_group()
    group.add_argument("--changelog", help="changelog text")
    group.add_argument("--changelog-file", help="changelog file (default: CHANGELOG.md in the addon)")
    p.add_argument("--game-versions", action="append", metavar="V[,V]",
                   help="game version names (default: 1.60.1, WoW Forever)")
    p.add_argument("--manual", action="store_true", help="upload hidden until approved on CurseForge")
    p.add_argument("--dry-run", action="store_true", help="run every check and build the zip, no upload")
    p.add_argument("--yes", action="store_true", help="don't ask for confirmation")
    p.add_argument("--force", action="store_true", help="publish even if the version isn't newer")
    p.set_defaults(func=cmd_publish)

    p = sub.add_parser("check", help="show exactly what publish would deploy, changing nothing")
    p.add_argument("names", nargs="*")
    p.add_argument("--files", action="store_true", help="list every file in each zip and every change")
    p.add_argument("--refresh", action="store_true", help="ignore the 10-minute CurseForge API cache")
    p.set_defaults(func=cmd_check)

    p = sub.add_parser("bump", help="bump the patch version (all addons by default)")
    p.add_argument("names", nargs="*")
    p.add_argument("--to", help="set this exact version (one addon)")
    p.set_defaults(func=cmd_bump)

    sub.add_parser("stop", help="restore the AddOns folders sync replaced since the session began"
                   ).set_defaults(func=cmd_stop)

    p = sub.add_parser("init", help="set up .env")
    p.add_argument("--force", action="store_true")
    p.set_defaults(func=cmd_init)

    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv or (argv[0].startswith("-") and argv[0] not in ("-h", "--help")):
        argv = ["sync"] + argv
    args = parser.parse_args(argv)
    try:
        ok = args.func(args)
    except SyncError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("Cancelled.", file=sys.stderr)
        return 1
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
