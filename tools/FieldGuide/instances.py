"""Dungeons for Field Guide's instance priority: each classic 5-player dungeon's recommended
levels, entrance, and the quests each faction can do there.

Entrances and the area IDs a dungeon's quests use come from QuestieDB's
support/Forever/Zones/dungeons.lua (read-only). Questie has no level ranges, so those are the
usual Classic recommendations below.
"""
import os
import re

from questiedb import DEFAULT_TOC, lua_list

DUNGEONS_LUA = os.path.join(os.path.dirname(os.environ.get('QUESTIEDB_TOC') or DEFAULT_TOC),
                            'support', 'Forever', 'Zones', 'dungeons.lua')

# areaId: (recommended levels from, to). Raids and battlegrounds aren't leveling.
LEVELS = {
    2437: (13, 18),   # Ragefire Chasm
    718: (17, 24),    # Wailing Caverns
    1581: (17, 26),   # The Deadmines
    209: (22, 30),    # Shadowfang Keep
    719: (24, 32),    # Blackfathom Deeps
    717: (24, 32),    # The Stockade
    721: (29, 38),    # Gnomeregan
    491: (29, 38),    # Razorfen Kraul
    796: (28, 45),    # Scarlet Monastery
    722: (37, 46),    # Razorfen Downs
    1337: (41, 51),   # Uldaman
    1176: (44, 54),   # Zul'Farrak
    2100: (46, 55),   # Maraudon
    1477: (50, 56),   # The Temple of Atal'Hakkar
    1584: (52, 60),   # Blackrock Depths
    1583: (55, 60),   # Blackrock Spire
    2557: (55, 60),   # Dire Maul
    2057: (58, 60),   # Scholomance
    2017: (58, 60),   # Stratholme
}

ENTRY = re.compile(r'^\s*\[(\d+)\]\s*=\s*\{"([^"]+)",(\{[^}]*\}|nil),(\d+),\{(.*)\}\},?')


def load_dungeons():
    """areaId -> { name, areas (the dungeon's own and its alternatives), entrances [(areaId, x, y)] }"""
    out = {}
    with open(DUNGEONS_LUA, encoding='utf-8') as f:
        for line in f:
            m = ENTRY.match(line)
            if not m:
                continue
            area = int(m.group(1))
            alts = [int(a) for a in re.findall(r'\d+', m.group(3))] if m.group(3) != 'nil' else []
            entrances = [(int(a), float(x), float(y))
                         for a, x, y in re.findall(r'\{(\d+),\s*([\d.]+),\s*([\d.]+)\}', m.group(5))]
            out.setdefault(area, {'name': m.group(2), 'areas': {area, *alts}, 'entrances': entrances})
    # Dire Maul's wings are listed separately (10022-10027): fold them into Dire Maul.
    for area, d in list(out.items()):
        if area != 2557 and d['name'] == 'Dire Maul' and 2557 in out:
            out[2557]['areas'] |= d['areas']
            del out[area]
        if area != 2017 and d['name'] == 'Stratholme' and 2017 in out:
            out[2017]['areas'] |= d['areas']
            del out[area]
    return {a: d for a, d in out.items() if a in LEVELS}


def dungeon_of(quest_row, dungeons):
    """The dungeon (areaId) a quest is for, from its zone, or None."""
    zone = quest_row.get('zoneOrSort') or 0
    for area, d in dungeons.items():
        if zone in d['areas']:
            return area
    return None


def dungeon_areas():
    """Every area ID inside any dungeon or raid (its own and its alternatives)."""
    out = set()
    with open(DUNGEONS_LUA, encoding='utf-8') as f:
        for line in f:
            m = ENTRY.match(line)
            if m:
                out.add(int(m.group(1)))
                if m.group(3) != 'nil':
                    out.update(int(a) for a in re.findall(r'\d+', m.group(3)))
    return out



# Each dungeon's final bosses (one per wing), by name: when one dies, the run is over.
FINAL_BOSSES = {
    2437: ['Bazzalan'],
    718: ['Mutanus the Devourer'],
    1581: ['Edwin VanCleef'],
    209: ['Archmage Arugal'],
    719: ["Aku'mai"],
    717: ['Bazil Thredd'],
    721: ['Mekgineer Thermaplugg'],
    491: ['Charlga Razorflank'],
    796: ['Bloodmage Thalnos', 'Arcanist Doan', 'Herod', 'High Inquisitor Whitemane'],
    722: ['Amnennar the Coldbringer'],
    1337: ['Archaedas'],
    1176: ['Chief Ukorz Sandscalp'],
    2100: ['Princess Theradras'],
    1477: ['Shade of Eranikus'],
    1584: ['Emperor Dagran Thaurissan'],
    1583: ['Overlord Wyrmthalak', 'General Drakkisath'],
    2557: ['Alzzin the Wildshaper', 'Prince Tortheldrin', 'King Gordok'],
    2057: ['Darkmaster Gandling'],
    2017: ['Baron Rivendare', 'Balnazzar'],
}


def dungeon_entrances():
    """Every dungeon and raid entrance: [(areaId, x, y)]. QuestieDB files some mobs that only live
    inside a dungeon at its entrance, out in the zone."""
    out = []
    with open(DUNGEONS_LUA, encoding='utf-8') as f:
        for line in f:
            m = ENTRY.match(line)
            if m:
                out += [(int(a), float(x), float(y))
                        for a, x, y in re.findall(r'\{(\d+),\s*([\d.]+),\s*([\d.]+)\}', m.group(5))]
    return out


# Dungeons with wings you enter separately (each is its own run). For each wing, in the order
# the route runs them: its name, its entrance (uiMapID, x, y; the portal or door you step into),
# its final bosses, and what places a quest in it: the names of its mobs and objects, and
# QuestieDB's sub-area IDs for it (Dire Maul files its mobs by wing).
#   - Scarlet Monastery: the four portals in the monastery hall (Tirisfal Glades). Coordinates
#     from WoW Forever guides, approximate: Graveyard far left, Cathedral door left, Armory door
#     right, Library far right.
#   - Dire Maul (Feralas) and Stratholme (Eastern Plaguelands): QuestieDB's entrances.
#   - Blackrock Spire: Lower and Upper share the entrance; Upper is the 10-player one.
# The addon tells which wing you're in from where you stepped in (nearest entrance), the
# dungeon's own map once it has learned it, the size of the instance (Blackrock Spire), or the
# final boss you killed.
WINGS = {
    796: [
        {'key': 'gy', 'name': 'Graveyard', 'entrance': (1420, 84.8, 30.3), 'bosses': ['Bloodmage Thalnos'],
         'names': ['Interrogator Vishas', 'Bloodmage Thalnos', 'Azshir the Sleepless', 'Fallen Champion', 'Ironspine',
                   'Scarlet Torturer', 'Haunting Phantasm', 'Anguished Dead', 'Unfettered Spirit', 'Vorrel Sengutz'],
         'areas': [6109]},
        {'key': 'lib', 'name': 'Library', 'entrance': (1420, 85.4, 32.5), 'bosses': ['Arcanist Doan'],
         'names': ['Houndmaster Loksey', 'Arcanist Doan', 'Scarlet Gallant', 'Scarlet Adept', 'Scarlet Beastmaster',
                   'Scarlet Tracking Hound', 'Scarlet Diviner', 'Scarlet Chaplain', 'Scarlet Monk',
                   'Mythology of the Titans', 'Beginnings of the Undead Threat', 'Compendium of the Fallen'],
         'areas': [10008]},
        {'key': 'arm', 'name': 'Armory', 'entrance': (1420, 85.7, 31.9), 'bosses': ['Herod'],
         'names': ['Herod', 'Scarlet Trainee', 'Scarlet Defender', 'Scarlet Guardsman', 'Scarlet Protector',
                   'Scarlet Myrmidon', 'Scarlet Soldier', 'Scarlet Conjuror'],
         'areas': [10009]},
        {'key': 'cath', 'name': 'Cathedral', 'entrance': (1420, 85.3, 30.3),
         'bosses': ['High Inquisitor Whitemane', 'Scarlet Commander Mograine'],
         'names': ['Scarlet Commander Mograine', 'High Inquisitor Whitemane', 'High Inquisitor Fairbanks',
                   'Scarlet Abbot', 'Scarlet Champion', 'Scarlet Centurion', 'Scarlet Wizard', 'Scarlet Sorcerer'],
         'areas': [6386, 10010]},
    ],
    2557: [
        {'key': 'east', 'name': 'East', 'entrance': (1444, 64.8, 30.2), 'bosses': ['Alzzin the Wildshaper'],
         'names': ['Lethtendris', 'Pusillin', 'Zevrim Thornhoof', 'Hydrospawn', 'Alzzin the Wildshaper', 'Isalien'],
         'areas': [10026, 10027]},
        {'key': 'west', 'name': 'West', 'entrance': (1444, 60.3, 30.2), 'bosses': ['Prince Tortheldrin'],
         'names': ['Tendris Warpwood', 'Illyanna Ravenoak', 'Magister Kalendris', "Immol'thar", 'Prince Tortheldrin'],
         'areas': [10023, 10024, 10025]},
        {'key': 'north', 'name': 'North', 'entrance': (1444, 62.5, 24.9), 'bosses': ['King Gordok'],
         'names': ['Guard Mol\'dar', 'Stomper Kreeg', 'Guard Fengus', "Guard Slip'kik", 'Captain Kromcrush',
                   "Cho'Rush the Observer", 'King Gordok'],
         'areas': [10022]},
    ],
    1583: [
        {'key': 'lower', 'name': 'Lower', 'entrance': (1427, 34.8, 85.3), 'bosses': ['Overlord Wyrmthalak'],
         'names': ['Highlord Omokk', "Shadow Hunter Vosh'gajin", 'War Master Voone', 'Mother Smolderweb',
                   'Urok Doomhowl', 'Quartermaster Zigris', 'Halycon', 'Gizrul the Slavener', 'Overlord Wyrmthalak',
                   'Bannok Grimaxe', 'Ghok Bashguud', 'Spirestone Butcher', 'Crystal Fang',
                   "Fifth Mosh'aru Tablet", "Sixth Mosh'aru Tablet", 'Spire Spider Egg'],
         'areas': [10003, 10004, 10005, 10006], 'size': 5},
        {'key': 'upper', 'name': 'Upper', 'entrance': (1427, 34.8, 85.3), 'bosses': ['General Drakkisath'],
         'names': ['Pyroguard Emberseer', 'Solakar Flamewreath', 'Jed Runewatcher', 'Goraluk Anvilcrack',
                   'Warchief Rend Blackhand', 'Gyth', 'The Beast', 'General Drakkisath'],
         'areas': [10007], 'size': 10},
    ],
    2017: [
        {'key': 'live', 'name': 'Main Gate', 'entrance': (1423, 26.5, 10.4), 'bosses': ['Balnazzar'],
         'names': ['Timmy the Cruel', 'Malor the Zealous', 'Cannon Master Willey', 'Archivist Galford',
                   'Balnazzar', 'Grand Crusader Dathrohan', 'Hearthsinger Forresten', 'Skul', 'Postmaster Malown', 'Ezra Grimm'],
         'areas': []},
        {'key': 'dead', 'name': 'Service Entrance', 'entrance': (1423, 41.5, 17.7), 'bosses': ['Baron Rivendare'],
         'names': ['Baroness Anastari', "Nerub'enkan", 'Maleki the Pallid', 'Magistrate Barthilas',
                   'Ramstein the Gorger', 'Baron Rivendare', 'Black Guard Sentry'],
         'areas': [10001]},
    ],
}

# The game's instance map ID for each dungeon (GetInstanceInfo's 8th value): tells which dungeon
# you're in whatever the client calls it.
INSTANCE_MAPS = {
    2437: 389, 718: 43, 1581: 36, 209: 33, 717: 34, 719: 48, 796: 189, 491: 47, 721: 90, 722: 129,
    1337: 70, 1176: 209, 2100: 349, 1477: 109, 1584: 230, 1583: 229, 2557: 429, 2057: 289, 2017: 329,
}

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
