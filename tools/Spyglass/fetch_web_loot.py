"""Fetches boss loot that AtlasLoot doesn't have yet from wowtbc.gg's
WoW Forever loot tables, into Data/web_loot.json.

The pages give item names only; tools/Spyglass/build_items.py matches them to item
IDs from the /sg harvest and writes them into Data/Items.lua.

    python tools/Spyglass/fetch_web_loot.py
"""
import datetime
import html.parser
import json
import os
import subprocess
import sys
import time
import urllib.request

ADDON = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "addons", "Spyglass")  # tools/Spyglass/ builds addons/Spyglass/
OUT = os.path.join(ADDON, "Data", "web_loot.json")
BASE = "https://wowtbc.gg/warcraftforever/loot-tables/"

# wowtbc.gg page -> AtlasLoot instance key (only the ones AtlasLoot has no loot for).
PAGES = {
    "dungeons/city-of-dalaran/": "CityOfDalaran",
    "dungeons/the-drowned-city/": "TheDrownedCity",
    "dungeons/krol-dok-stronghold/": "KroldokStronghold",
    "dungeons/alcaz-prison/": "AlcazPrison",
    "dungeons/blackmaw-hold/": "BlackmawHold",
    "dungeons/shaper-s-terrace/": "ShapersTerrace",
    "raids/hyjal-summit/": "MountHyjal",
    "raids/barrow-deeps/": "BarrowDeepsRaid",
    "raids/onyxia-s-lair/": "OnyxiasLairNew",
}


class LootPage(html.parser.HTMLParser):
    """Boss headers (h3.database__boss__wrapper__header) and the item name
    and slot divs after each, stopping at the quest rewards section."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.bosses = []
        self.capture = None  # "boss", "name" or "slot" while inside one
        self.text = ""
        self.done = False

    def handle_starttag(self, tag, attrs):
        if self.done:
            return
        cls = dict(attrs).get("class") or ""
        if tag == "h3" and "database__boss__wrapper__header" in cls:
            self.capture = "boss"
        elif tag == "div" and "database__item__name" in cls:
            self.capture = "name"
        elif tag == "div" and "database__item__slot" in cls:
            self.capture = "slot"
        else:
            return
        self.text = ""

    def handle_data(self, data):
        if self.capture:
            self.text += data
        elif not self.done and "No drops discovered yet" in data and self.bosses:
            self.bosses[-1]["empty"] = True

    def handle_endtag(self, tag):
        if not self.capture or tag not in ("h3", "div"):
            return
        text = " ".join(self.text.split())
        if self.capture == "boss":
            if text.lower().startswith("quest rewards"):
                self.done = True  # quest rewards, not boss drops (the quest plugin's business)
            else:
                self.bosses.append({"boss": text, "items": [], "empty": False})
        elif self.capture == "name" and self.bosses:
            self.bosses[-1]["items"].append({"name": text})
        elif self.capture == "slot" and self.bosses and self.bosses[-1]["items"]:
            self.bosses[-1]["items"][-1]["slot"] = text
        self.capture = None


UA = "Mozilla/5.0 (SpyGlass addon data tool)"


def fetch(url):
    # curl first: it uses the system's certificate store, which some Python
    # installs' bundled store lags behind.
    try:
        out = subprocess.run(["curl", "-sSfL", "--max-time", "30", "-A", UA, url],
                             capture_output=True, check=True)
        return out.stdout.decode("utf-8", "replace")
    except (OSError, subprocess.CalledProcessError):
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.read().decode("utf-8", "replace")


def main():
    out = {"source": BASE, "fetched": datetime.date.today().isoformat(), "instances": {}}
    for i, (path, key) in enumerate(PAGES.items()):
        if i:
            time.sleep(2)
        url = BASE + path
        try:
            page = LootPage()
            page.feed(fetch(url))
        except Exception as e:  # keep going; one bad page shouldn't lose the rest
            print("%-18s failed: %s" % (key, e))
            continue
        bosses = [b for b in page.bosses if b["items"]]
        out["instances"][key] = {"url": url, "bosses": bosses}
        waiting = [b["boss"] for b in page.bosses if not b["items"]]
        print("%-18s %2d bosses with loot, %3d items%s" % (key, len(bosses), sum(len(b["items"]) for b in bosses),
              ("; no drops listed yet: " + ", ".join(waiting)) if waiting else ""))
    if not out["instances"]:
        print("Nothing fetched; Data/web_loot.json left as it was.")
        return 1
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        json.dump(out, f, indent=1, ensure_ascii=False)
    print("wrote Data/web_loot.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
