"""Where things are: this repo, and the game's folders the build tools read (never write).

    import paths                                    # tools/_shared on sys.path
    paths.REPO, paths.TOOLS, paths.addon("Spyglass")
    paths.WOW, paths.GAME_ADDONS, paths.WTF, paths.QUESTIEDB_TOC
    paths.atlasloot_data()                          # AtlasLootClassic's data.lua, or None

The game's folder is WOW_INSTALL, from the environment or the repo's .env (what `yarn test`
installs into), else Z:/Games/World of Warcraft/_forever_.
Environment overrides (each falls back to that install):
  WOW_DIR        the World of Warcraft folder (also casc.py's)
  WOW_ADDONS     the game's Interface/AddOns folder
  WOW_WTF        the game's WTF folder (saved variables)
  QUESTIEDB_TOC  QuestieDB's QuestieDB_Forever.toc
"""
import os

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.dirname(TOOLS)
ADDONS = os.path.join(REPO, "addons")              # the workspace's addons (what ships)



def _dotenv(key):
    """A value from the repo's .env (gitignored; addon_sync.py reads the same file), or None."""
    try:
        with open(os.path.join(REPO, ".env"), encoding="utf-8-sig") as f:
            for line in f:
                line = line.strip()
                if line.startswith("export "):
                    line = line[7:].strip()
                if line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                if k.strip() == key:
                    v = v.strip()
                    if len(v) >= 2 and v[0] == v[-1] and v[0] in "'\"":
                        return v[1:-1]
                    return v.split(" #", 1)[0].rstrip() or None
    except OSError:
        pass
    return None


def _client():
    """The game-version folder (WoW Forever's, holding Interface and WTF) from WOW_INSTALL, the same
    setting `yarn test` installs into (an environment variable, else .env): the folder itself, or
    its Interface/AddOns. None when it isn't set or isn't there."""
    raw = os.environ.get("WOW_INSTALL") or _dotenv("WOW_INSTALL")
    if not raw:
        return None
    path = os.path.normpath(raw.strip().strip('"'))
    if os.path.basename(path).lower() == "addons":
        path = os.path.dirname(os.path.dirname(path))
    return path if os.path.isdir(os.path.join(path, "Interface", "AddOns")) else None


DEFAULT_WOW = r"Z:\Games\World of Warcraft"
CLIENT = _client() or os.path.join(os.environ.get("WOW_DIR") or DEFAULT_WOW, "_forever_")
WOW = os.environ.get("WOW_DIR") or os.path.dirname(CLIENT)
GAME_ADDONS = os.environ.get("WOW_ADDONS") or os.path.join(CLIENT, "Interface", "AddOns")
WTF = os.environ.get("WOW_WTF") or os.path.join(CLIENT, "WTF")
DEFAULT_QUESTIEDB_TOC = os.path.join(GAME_ADDONS, "QuestieDB", "QuestieDB_Forever.toc")
QUESTIEDB_TOC = os.environ.get("QUESTIEDB_TOC") or DEFAULT_QUESTIEDB_TOC


def addon(name):
    """addons/<name> in this repo."""
    return os.path.join(ADDONS, name)


def tool(name):
    """tools/<name> in this repo (a tool folder: its caches and working files)."""
    return os.path.join(TOOLS, name)


ATLASLOOT_DATA = os.path.join("AtlasLootClassic_DungeonsAndRaids", "data.lua")


def atlasloot_data():
    """AtlasLootClassic_DungeonsAndRaids/data.lua (third party, read only): a copy beside the
    workspace's addons first, else the game's. None when neither is there."""
    for folder in (ADDONS, GAME_ADDONS):
        path = os.path.join(folder, ATLASLOOT_DATA)
        if os.path.exists(path):
            return path
    return None
