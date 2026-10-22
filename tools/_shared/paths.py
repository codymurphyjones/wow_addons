"""Where things are: this repo, and the game's folders the build tools read (never write).

    import paths                                    # tools/_shared on sys.path
    paths.REPO, paths.TOOLS, paths.addon("Spyglass")
    paths.WOW, paths.GAME_ADDONS, paths.WTF, paths.QUESTIEDB_TOC
    paths.atlasloot_data()                          # AtlasLootClassic's data.lua, or None

Environment overrides (each falls back to the WoW Forever install):
  WOW_DIR        the World of Warcraft folder (also casc.py's)
  WOW_ADDONS     the game's Interface/AddOns folder
  WOW_WTF        the game's WTF folder (saved variables)
  QUESTIEDB_TOC  QuestieDB's QuestieDB_Forever.toc
"""
import os

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.dirname(TOOLS)
ADDONS = os.path.join(REPO, "addons")              # the workspace's addons (what ships)

DEFAULT_WOW = r"Z:\Games\World of Warcraft"
CLIENT_FOLDER = "_classic_beta_"                   # WoW Forever's folder inside it
WOW = os.environ.get("WOW_DIR") or DEFAULT_WOW
CLIENT = os.path.join(WOW, CLIENT_FOLDER)
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
