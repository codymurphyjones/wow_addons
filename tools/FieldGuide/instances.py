"""Dungeons for Field Guide's instance priority: each classic 5-player dungeon's recommended
levels, entrance, and the quests each faction can do there.

The instance facts (levels, final bosses, instance map IDs, wings) are the suite's one copy in
tools/_shared/instancedata.py, which tools/shared/build_instances.py also writes into
addons/shared/Instances.lua; entrances and the area IDs a dungeon's quests use come from
QuestieDB's support/Forever/Zones/dungeons.lua (read-only). What's here is Field Guide's own:
which dungeon a quest is for, and the quests done outside before going in.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "_shared"))  # also when imported on its own
from instancedata import (DUNGEONS_LUA, FINAL_BOSSES, INSTANCE_MAPS, LEVELS, WINGS,  # noqa: E402,F401
                          dungeon_areas, dungeon_entrances, load_dungeons)


def dungeon_of(quest_row, dungeons):
    """The dungeon (areaId) a quest is for, from its zone, or None."""
    zone = quest_row.get('zoneOrSort') or 0
    for area, d in dungeons.items():
        if zone in d['areas']:
            return area
    return None


# Dungeon quests with objectives out in the world, done before going in (checked by hand:
# QuestieDB files many mobs that live inside a dungeon under the zone around it, so its data
# can't tell). True: all of it is outside; 'part': start it outside, the rest is inside.
OUTSIDE_FIRST = {
    6563: True,     # The Essence of Aku'Mai: sapphires in the tunnel outside Blackfathom's portal
    1275: True,     # Researching the Corruption: Fallenroot satyrs, Darkshore's southern coast
    1486: 'part',   # Deviate Hides: deviates in the Wailing Caverns' outer cave
    962: 'part',    # Serpentbloom: the outer cave, and inside
    6626: True,     # A Host of Evil: around Razorfen Downs' entrance
    6521: True,     # An Unholy Alliance: Ambassador Malcin, outside Razorfen Downs
    2926: 'part',   # Gnogaine: irradiated invaders outside Gnomeregan
    704: True,      # Agmond's Fate: urns at Uldaman's outer dig site
    709: True,      # Solution to Doom: the tablet in Uldaman's outer cave
    1360: True,     # Reclaimed Treasures (Alliance): Krom Stoutarm's chest, Uldaman's outer cave
    2342: True,     # Reclaimed Treasures (Horde): the Garrett family chest, Uldaman's outer cave
    2283: 'part',   # Necklace Recovery: Shadowforge dwarves in the outer cave, and inside
    2418: 'part',   # Power Stones: the outer cave, and inside
    17: 'part',     # Uldaman Reagent Run (Alliance): magenta caps, outer cave and inside
    2202: 'part',   # Uldaman Reagent Run (Horde)
    7068: True,     # Shadowshard Fragments: Maraudon's outer caves
    7070: True,     # Shadowshard Fragments
    7029: 'part',   # Vyletongue Corruption: fill the vial at the orange pool outside, use it inside
    7041: 'part',   # Vyletongue Corruption
}
