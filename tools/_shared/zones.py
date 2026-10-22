"""Zone lookups from QuestieDB's Forever support data: area ID -> parent zone -> uiMapID.

QuestieDB keeps these as Lua tables inside long strings (support/Forever/Zones/*.lua); a regex
over `[id] = id` pairs is all they need. Read-only on the game folder.
"""
import os
import re

import paths

ZONES_DIR = os.path.join(os.path.dirname(paths.QUESTIEDB_TOC), 'support', 'Forever', 'Zones')
PAIR = re.compile(r'\[(-?\d+)\]\s*=\s*(-?\d+),?\s*(?:--\s*(.*))?')


def _pairs(name):
    out, names = {}, {}
    with open(os.path.join(ZONES_DIR, name), encoding='utf-8') as f:
        for line in f:
            m = PAIR.search(line)
            if m:
                k, v = int(m.group(1)), int(m.group(2))
                out.setdefault(k, v)  # the first (override) entry wins, like ZoneDB
                if m.group(3):
                    names.setdefault(k, m.group(3).strip())
    return out, names


class Zones:
    def __init__(self):
        self.ui_map, self.names = _pairs('areaIdToUiMapId.lua')
        self.parent, parent_names = _pairs('subZoneToParentZone.lua')
        for k, v in parent_names.items():
            self.names.setdefault(k, v.split('->')[0].strip())

    def zone_of(self, area_id):
        """The top-level zone area ID for a (sub)zone area ID."""
        seen = 0
        while area_id in self.parent and self.parent[area_id] != area_id and seen < 5:
            area_id = self.parent[area_id]
            seen += 1
        return area_id

    def map_of(self, area_id):
        """uiMapID for an area ID (or its parent zone), or None."""
        m = self.ui_map.get(area_id)
        if m:
            return m
        return self.ui_map.get(self.zone_of(area_id)) or None

    def name(self, area_id):
        return self.names.get(area_id, str(area_id))
