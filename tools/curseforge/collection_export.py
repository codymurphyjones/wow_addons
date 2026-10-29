"""Writes a CurseForge app addon group (a "collection" you made in the CurseForge Windows app) as
tools/curseforge/collection.json, for the collection installer (collection_installer.py) to install
on a friend's PC.

    python tools/curseforge/collection_export.py                       the only WoW group, or the first
    python tools/curseforge/collection_export.py "Wally Addon Collection"

The app keeps groups on your PC only (agent/GameInstances/groups.json; the addons' groupId in
AddonGameInstance.json), so there is no link to share. This reads them, then asks CurseForge (with
CURSEFORGE_KEY from .env) for each addon's newest file for the game version the app's WoW install
is on (Forever: 1.60.1), and the libraries it requires. The installer needs no key: it downloads
straight from the files' public links.

Addons whose authors don't allow third-party distribution have no download link: the installer
opens the CurseForge app's own install link for those (curseforge://install), and the app installs
them.

Commit and push collection.json: the installer reads the newest one from GitHub every time it runs
(its own copy is the fallback), so friends get changes without a new installer.
"""
import json
import os
import sys
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, ROOT)
import addon_sync  # noqa: E402  (.env, the API key)

OUT = os.path.join(HERE, "collection.json")
APP = os.path.join(os.environ.get("APPDATA", ""), "CurseForge", "agent", "GameInstances")
API = "https://api.curseforge.com"
WOW = 1                     # CurseForge's game id for World of Warcraft
REQUIRED = 3                # file dependency relationType: required dependency
FOREVER_TYPE = 88568        # the WoW Forever game version type, when the app's install doesn't say


def app_json(name):
    with open(os.path.join(APP, name), encoding="utf-8") as f:
        return json.load(f)


class Api:
    def __init__(self, key):
        self.key = key
        self.mods = {}

    def get(self, path, params=None):
        url = API + path + ("?" + urllib.parse.urlencode(params) if params else "")
        req = urllib.request.Request(url, headers={"x-api-key": self.key, "Accept": "application/json",
                                                   "User-Agent": addon_sync.USER_AGENT})
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)["data"]

    def mod(self, pid):
        if pid not in self.mods:
            self.mods[pid] = self.get("/v1/mods/%d" % pid)
        return self.mods[pid]

    def newest(self, pid, version_type):
        """The newest file for this game version: a release, else a beta, else an alpha."""
        files = self.get("/v1/mods/%d/files" % pid, {"gameVersionTypeId": version_type, "pageSize": 50})
        files = [f for f in files if f.get("isAvailable", True)]
        for kind in (1, 2, 3):
            pick = [f for f in files if f.get("releaseType") == kind]
            if pick:
                return max(pick, key=lambda f: f["id"])
        return None


def entry(api, pid, version_type, required_by=None):
    mod = api.mod(pid)
    f = api.newest(pid, version_type)
    if not f:
        print("  %s: no file for this game version - left out" % mod["name"])
        return None
    url = f.get("downloadUrl")
    e = {
        "id": pid,
        "name": mod["name"].strip(),
        "page": (mod.get("links") or {}).get("websiteUrl") or "",
        "file": {"id": f["id"], "name": f.get("displayName") or f.get("fileName"), "url": url,
                 "folders": [m["name"] for m in f.get("modules") or []]},
        "locked": not url,
    }
    if required_by:
        e["requiredBy"] = required_by
    e["requires"] = [d["modId"] for d in f.get("dependencies") or [] if d.get("relationType") == REQUIRED]
    return e


def main(argv):
    key = addon_sync.api_key(addon_sync.load_config())
    if not key:
        sys.exit("No CurseForge API key - add CURSEFORGE_KEY to .env.")
    groups = [g for g in app_json("groups.json") if g.get("gameId") == WOW]
    if not groups:
        sys.exit("The CurseForge app has no World of Warcraft addon groups.")
    want = argv[0] if argv else None
    group = next((g for g in groups if g["name"] == want), None) if want else groups[0]
    if not group:
        sys.exit("No group named %r - the app has: %s" % (want, ", ".join(g["name"] for g in groups)))
    ids, version_type = [], None
    for inst in app_json("AddonGameInstance.json"):
        if inst.get("gameTypeID") != WOW:
            continue
        for a in inst.get("installedAddons") or []:
            if a.get("groupId") == group["id"] and a["addonID"] not in ids:
                ids.append(a["addonID"])
                version_type = version_type or inst.get("gameVersionTypeId")
    version_type = version_type or FOREVER_TYPE
    print("%s: %d addons (game version type %d)" % (group["name"], len(ids), version_type))
    api = Api(key)
    out, seen, queue = [], set(), [(pid, None) for pid in ids]
    while queue:
        pid, by = queue.pop(0)
        if pid in seen:
            continue
        seen.add(pid)
        e = entry(api, pid, version_type, by)
        if not e:
            continue
        out.append(e)
        for dep in e["requires"]:
            if dep not in seen:
                queue.append((dep, e["name"]))
    out.sort(key=lambda e: e["name"].lower())
    data = {"name": group["name"], "gameVersionTypeId": version_type, "addons": out}
    with open(OUT, "w", encoding="utf-8", newline="") as f:
        json.dump(data, f, indent=1, ensure_ascii=False)
        f.write("\n")
    locked = [e["name"] for e in out if e["locked"]]
    libs = [e["name"] for e in out if e.get("requiredBy")]
    print("wrote %s: %d addons, %d installed straight, %d through the CurseForge app (%s)%s" % (
        OUT, len(out), len(out) - len(locked), len(locked), ", ".join(locked) or "none",
        ("; required libraries added: " + ", ".join(libs)) if libs else ""))


if __name__ == "__main__":
    main(sys.argv[1:])
