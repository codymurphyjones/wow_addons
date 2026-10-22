"""The suite's instance facts: one copy, for tools/shared/build_instances.py (which writes
addons/shared/Instances.lua) and tools/FieldGuide/build_guides.py (the dungeon routes).

    import instancedata                              # tools/_shared on sys.path
    instancedata.INSTANCES                           # the static facts, below
    instancedata.by_area()                           # { areaID: entry }
    instancedata.LEVELS, FINAL_BOSSES, INSTANCE_MAPS, WINGS   # the leveling dungeons' views
    instancedata.load_dungeons(), dungeon_areas(), dungeon_entrances()   # read from QuestieDB

Where each fact comes from:
  * Area IDs, alternative (sub-)area IDs, names and entrances: QuestieDB's Forever support data
    (support/Forever/Zones/dungeons.lua, read-only in the game folder). Authoritative.
  * Instance map IDs (GetInstanceInfo's 8th value): QuestieDB's instanceIdToAreaId.lua; the IDs
    below agree with it (build_instances.py checks).
  * Names the game gives (GetInstanceInfo's 1st value): the classic Map table (MapName_lang, as
    tools/Spyglass/fetch_pulls.py reads it from wago.tools) where it differs from QuestieDB's.
  * Recommended levels of the classic dungeons: the usual Classic recommendations (Questie has no
    level ranges). Raids are 60. WoW Forever's own dungeons: AtlasLoot Continued's range (as
    SpyGlass ships it in Data/Loot.lua).
  * Final bosses (one per wing: when one dies, the run is over), wings, wing entrances: checked by
    hand (see WINGS).
  * uiMapIDs (the dungeon's floors): the game's UiMap table (SpyGlass's Journal/PullData.lua),
    plus QuestieDB's uiMap -> area aliases.
  * key: SpyGlass's (AtlasLoot's) instance key; a dungeon whose wings have their own loot pages
    gets one key for the whole place, and each wing names its page (loot).
"""
import os
import re

import paths

ZONES_DIR = os.path.join(os.path.dirname(paths.QUESTIEDB_TOC), 'support', 'Forever', 'Zones')
DUNGEONS_LUA = os.path.join(ZONES_DIR, 'dungeons.lua')
INSTANCE_IDS_LUA = os.path.join(ZONES_DIR, 'instanceIdToAreaId.lua')
UIMAP_LUA = os.path.join(ZONES_DIR, 'uiMapIdToAreaId.lua')

# Dungeons with wings you enter separately (each is its own run). For each wing, in the order
# the route runs them: its key and name, its entrance (uiMapID, x, y; the portal or door you step
# into), its final bosses, and what places a quest in it (FieldGuide's builder): the names of its
# mobs and objects, and QuestieDB's sub-area IDs for it (Dire Maul files its mobs by wing).
#   - Scarlet Monastery: the four portals in the monastery hall (Tirisfal Glades). Coordinates
#     from WoW Forever guides, approximate: Graveyard far left, Cathedral door left, Armory door
#     right, Library far right.
#   - Dire Maul (Feralas) and Stratholme (Eastern Plaguelands): QuestieDB's entrances.
#   - Blackrock Spire: Lower and Upper share the entrance; Upper is the 10-player one.
# loot: the wing's own page in SpyGlass's loot (AtlasLoot's key). uiMaps: the dungeon maps that
# are only in this wing (QuestieDB's uiMap aliases for Dire Maul's floors and Upper Blackrock
# Spire). aliases: other names the wing goes by (AtlasLoot's, the old Lower / Upper names).
WINGS = {
    796: [
        {'key': 'gy', 'name': 'Graveyard', 'entrance': (1420, 84.8, 30.3), 'bosses': ['Bloodmage Thalnos'],
         'names': ['Interrogator Vishas', 'Bloodmage Thalnos', 'Azshir the Sleepless', 'Fallen Champion', 'Ironspine',
                   'Scarlet Torturer', 'Haunting Phantasm', 'Anguished Dead', 'Unfettered Spirit', 'Vorrel Sengutz'],
         'areas': [6109], 'loot': 'ScarletMonasteryGraveyard', 'aliases': ['Scarlet Monastery - Graveyard']},
        {'key': 'lib', 'name': 'Library', 'entrance': (1420, 85.4, 32.5), 'bosses': ['Arcanist Doan'],
         'names': ['Houndmaster Loksey', 'Arcanist Doan', 'Scarlet Gallant', 'Scarlet Adept', 'Scarlet Beastmaster',
                   'Scarlet Tracking Hound', 'Scarlet Diviner', 'Scarlet Chaplain', 'Scarlet Monk',
                   'Mythology of the Titans', 'Beginnings of the Undead Threat', 'Compendium of the Fallen'],
         'areas': [10008], 'loot': 'ScarletMonasteryLibrary', 'aliases': ['Scarlet Monastery - Library']},
        {'key': 'arm', 'name': 'Armory', 'entrance': (1420, 85.7, 31.9), 'bosses': ['Herod'],
         'names': ['Herod', 'Scarlet Trainee', 'Scarlet Defender', 'Scarlet Guardsman', 'Scarlet Protector',
                   'Scarlet Myrmidon', 'Scarlet Soldier', 'Scarlet Conjuror'],
         'areas': [10009], 'loot': 'ScarletMonasteryArmory', 'aliases': ['Scarlet Monastery - Armory']},
        {'key': 'cath', 'name': 'Cathedral', 'entrance': (1420, 85.3, 30.3),
         'bosses': ['High Inquisitor Whitemane', 'Scarlet Commander Mograine'],
         'names': ['Scarlet Commander Mograine', 'High Inquisitor Whitemane', 'High Inquisitor Fairbanks',
                   'Scarlet Abbot', 'Scarlet Champion', 'Scarlet Centurion', 'Scarlet Wizard', 'Scarlet Sorcerer'],
         'areas': [6386, 10010], 'loot': 'ScarletMonasteryCathedral', 'aliases': ['Scarlet Monastery - Cathedral']},
    ],
    2557: [
        {'key': 'east', 'name': 'East', 'entrance': (1444, 64.8, 30.2), 'bosses': ['Alzzin the Wildshaper'],
         'names': ['Lethtendris', 'Pusillin', 'Zevrim Thornhoof', 'Hydrospawn', 'Alzzin the Wildshaper', 'Isalien'],
         'areas': [10026, 10027], 'loot': 'DireMaulEast', 'uiMaps': [239, 240], 'aliases': ['Dire Maul East']},
        {'key': 'west', 'name': 'West', 'entrance': (1444, 60.3, 30.2), 'bosses': ['Prince Tortheldrin'],
         'names': ['Tendris Warpwood', 'Illyanna Ravenoak', 'Magister Kalendris', "Immol'thar", 'Prince Tortheldrin'],
         'areas': [10023, 10024, 10025], 'loot': 'DireMaulWest', 'uiMaps': [236, 237, 238], 'aliases': ['Dire Maul West']},
        {'key': 'north', 'name': 'North', 'entrance': (1444, 62.5, 24.9), 'bosses': ['King Gordok'],
         'names': ['Guard Mol\'dar', 'Stomper Kreeg', 'Guard Fengus', "Guard Slip'kik", 'Captain Kromcrush',
                   "Cho'Rush the Observer", 'King Gordok'],
         'areas': [10022], 'loot': 'DireMaulNorth', 'uiMaps': [235], 'aliases': ['Dire Maul North']},
    ],
    1583: [
        {'key': 'lower', 'name': 'Lower', 'entrance': (1427, 34.8, 85.3), 'bosses': ['Overlord Wyrmthalak'],
         'names': ['Highlord Omokk', "Shadow Hunter Vosh'gajin", 'War Master Voone', 'Mother Smolderweb',
                   'Urok Doomhowl', 'Quartermaster Zigris', 'Halycon', 'Gizrul the Slavener', 'Overlord Wyrmthalak',
                   'Bannok Grimaxe', 'Ghok Bashguud', 'Spirestone Butcher', 'Crystal Fang',
                   "Fifth Mosh'aru Tablet", "Sixth Mosh'aru Tablet", 'Spire Spider Egg'],
         'areas': [10003, 10004, 10005, 10006], 'size': 5, 'loot': 'LowerBlackrockSpire',
         'aliases': ['Lower Blackrock Spire']},
        {'key': 'upper', 'name': 'Upper', 'entrance': (1427, 34.8, 85.3), 'bosses': ['General Drakkisath'],
         'names': ['Pyroguard Emberseer', 'Solakar Flamewreath', 'Jed Runewatcher', 'Goraluk Anvilcrack',
                   'Warchief Rend Blackhand', 'Gyth', 'The Beast', 'General Drakkisath'],
         'areas': [10007], 'size': 10, 'loot': 'UpperBlackrockSpire', 'uiMaps': [255],
         'aliases': ['Upper Blackrock Spire']},
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

# The instances, in QuestieDB's order. area: QuestieDB's area ID; instanceID: the game's instance
# map ID; levels: recommended (from, to); bosses: the final bosses (one per wing); game: the name
# GetInstanceInfo gives when it isn't QuestieDB's; aliases: other names it goes by; uiMaps: its
# floors; custom: one of WoW Forever's own instances.
INSTANCES = [
    {'key': 'ShadowfangKeep', 'area': 209, 'instanceID': 33, 'kind': 'dungeon', 'levels': (22, 30),
     'bosses': ['Archmage Arugal'], 'uiMaps': [310, 311, 312, 313, 314, 315, 316]},
    {'key': 'RazorfenKraul', 'area': 491, 'instanceID': 47, 'kind': 'dungeon', 'levels': (29, 38),
     'bosses': ['Charlga Razorflank'], 'uiMaps': [301]},
    {'key': 'TheStockade', 'area': 717, 'instanceID': 34, 'kind': 'dungeon', 'levels': (24, 32),
     'bosses': ['Bazil Thredd'], 'game': 'Stormwind Stockade', 'uiMaps': [225]},
    {'key': 'WailingCaverns', 'area': 718, 'instanceID': 43, 'kind': 'dungeon', 'levels': (17, 24),
     'bosses': ['Mutanus the Devourer'], 'uiMaps': [279]},
    {'key': 'BlackfathomDeeps', 'area': 719, 'instanceID': 48, 'kind': 'dungeon', 'levels': (24, 32),
     'bosses': ["Aku'mai"], 'uiMaps': [221, 222, 223]},
    {'key': 'Gnomeregan', 'area': 721, 'instanceID': 90, 'kind': 'dungeon', 'levels': (29, 38),
     'bosses': ['Mekgineer Thermaplugg'], 'uiMaps': [226, 227, 228, 229]},
    {'key': 'RazorfenDowns', 'area': 722, 'instanceID': 129, 'kind': 'dungeon', 'levels': (37, 46),
     'bosses': ['Amnennar the Coldbringer'], 'uiMaps': [300]},
    {'key': 'ScarletMonastery', 'area': 796, 'instanceID': 189, 'kind': 'dungeon', 'levels': (28, 45),
     'bosses': ['Bloodmage Thalnos', 'Arcanist Doan', 'Herod', 'High Inquisitor Whitemane'],
     'uiMaps': [302, 303, 304, 305]},
    {'key': "Zul'Farrak", 'area': 1176, 'instanceID': 209, 'kind': 'dungeon', 'levels': (44, 54),
     'bosses': ['Chief Ukorz Sandscalp'], 'uiMaps': [219]},
    {'key': 'Uldaman', 'area': 1337, 'instanceID': 70, 'kind': 'dungeon', 'levels': (41, 51),
     'bosses': ['Archaedas'], 'uiMaps': [230, 231]},
    {'key': "TheTempleOfAtal'Hakkar", 'area': 1477, 'instanceID': 109, 'kind': 'dungeon', 'levels': (50, 56),
     'bosses': ['Shade of Eranikus'], 'game': 'Sunken Temple', 'uiMaps': [220]},
    {'key': 'TheDeadmines', 'area': 1581, 'instanceID': 36, 'kind': 'dungeon', 'levels': (17, 26),
     'bosses': ['Edwin VanCleef'], 'game': 'Deadmines', 'uiMaps': [291, 292]},
    {'key': 'BlackrockSpire', 'area': 1583, 'instanceID': 229, 'kind': 'dungeon', 'levels': (55, 60),
     'bosses': ['Overlord Wyrmthalak', 'General Drakkisath'], 'uiMaps': [250, 251, 252, 253, 254, 255]},
    {'key': 'BlackrockDepths', 'area': 1584, 'instanceID': 230, 'kind': 'dungeon', 'levels': (52, 60),
     'bosses': ['Emperor Dagran Thaurissan'], 'uiMaps': [242, 243]},
    {'key': "Zul'Gurub", 'area': 1977, 'instanceID': 309, 'kind': 'raid', 'levels': (60, 60),
     'bosses': ['Hakkar'], 'uiMaps': [233]},
    {'key': 'Stratholme', 'area': 2017, 'instanceID': 329, 'kind': 'dungeon', 'levels': (58, 60),
     'bosses': ['Baron Rivendare', 'Balnazzar'], 'uiMaps': [317, 318]},
    {'key': 'Scholomance', 'area': 2057, 'instanceID': 289, 'kind': 'dungeon', 'levels': (58, 60),
     'bosses': ['Darkmaster Gandling'], 'uiMaps': [306, 307, 308, 309]},
    {'key': 'Maraudon', 'area': 2100, 'instanceID': 349, 'kind': 'dungeon', 'levels': (46, 55),
     'bosses': ['Princess Theradras'], 'uiMaps': [280, 281]},
    {'key': 'Onyxia', 'area': 2159, 'instanceID': 249, 'kind': 'raid', 'levels': (60, 60),
     'bosses': ['Onyxia'], 'uiMaps': [248]},
    {'key': 'Ragefire', 'area': 2437, 'instanceID': 389, 'kind': 'dungeon', 'levels': (13, 18),
     'bosses': ['Bazzalan'], 'uiMaps': [213]},
    {'key': 'DireMaul', 'area': 2557, 'instanceID': 429, 'kind': 'dungeon', 'levels': (55, 60),
     'bosses': ['Alzzin the Wildshaper', 'Prince Tortheldrin', 'King Gordok'], 'uiMaps': [235, 236, 237, 238, 239, 240]},
    {'key': 'BlackwingLair', 'area': 2677, 'instanceID': 469, 'kind': 'raid', 'levels': (60, 60),
     'bosses': ['Nefarian'], 'uiMaps': [287, 288, 289, 290]},
    {'key': 'MoltenCore', 'area': 2717, 'instanceID': 409, 'kind': 'raid', 'levels': (60, 60),
     'bosses': ['Ragnaros'], 'uiMaps': [232]},
    {'key': 'TheTempleofAhnQiraj', 'area': 3428, 'instanceID': 531, 'kind': 'raid', 'levels': (60, 60),
     'bosses': ["C'Thun"], 'game': "Ahn'Qiraj Temple", 'aliases': ["Ahn'Qiraj"], 'uiMaps': [319, 320, 321]},
    {'key': 'TheRuinsofAhnQiraj', 'area': 3429, 'instanceID': 509, 'kind': 'raid', 'levels': (60, 60),
     'bosses': ['Ossirian the Unscarred'], 'uiMaps': [247]},
    {'key': 'Naxxramas', 'area': 3456, 'instanceID': 533, 'kind': 'raid', 'levels': (60, 60),
     'bosses': ["Kel'Thuzad"], 'uiMaps': [162, 163, 164, 165, 166, 167]},
    {'key': 'CityOfDalaran', 'area': 16544, 'instanceID': 2959, 'kind': 'dungeon', 'levels': (28, 33),
     'custom': True},
    {'key': 'TheRuinsOfLordaeron', 'area': 16611, 'instanceID': 2999, 'kind': 'dungeon', 'levels': (13, 18),
     'custom': True},
    {'key': 'ExcavationSiteWetlands', 'area': 16732, 'instanceID': 2998, 'kind': 'dungeon', 'levels': (24, 29),
     'custom': True},
    {'key': 'TheHallOfThanes', 'area': 16919, 'instanceID': 3065, 'kind': 'dungeon', 'levels': (13, 18),
     'custom': True, 'aliases': ['Hall of Thanes']},
]


def by_area():
    """{ areaID: entry } for INSTANCES."""
    return {i['area']: i for i in INSTANCES}


# The classic 5-player dungeons Field Guide routes: their views, keyed by area ID.
_LEVELING = [i for i in INSTANCES if i['kind'] == 'dungeon' and not i.get('custom')]
LEVELS = {i['area']: i['levels'] for i in _LEVELING}
FINAL_BOSSES = {i['area']: list(i['bosses']) for i in _LEVELING}
INSTANCE_MAPS = {i['area']: i['instanceID'] for i in _LEVELING}


# --- QuestieDB's Forever dungeon list (read-only) ------------------------------------------------

ENTRY = re.compile(r'^\s*\[(\d+)\]\s*=\s*\{"([^"]+)",(\{[^}]*\}|nil),(\d+),\{(.*)\}\},?')
POINT = re.compile(r'\{(\d+),\s*([\d.]+),\s*([\d.]+)\}')


def _entries():
    """QuestieDB's dungeons.lua base table, in file order: (area, name, alternative areas,
    entrances [(areaId, x, y)]). Commented-out lines and the later expansions' overrides don't match."""
    with open(DUNGEONS_LUA, encoding='utf-8') as f:
        for line in f:
            m = ENTRY.match(line)
            if m:
                alts = [int(a) for a in re.findall(r'\d+', m.group(3))] if m.group(3) != 'nil' else []
                entrances = [(int(a), float(x), float(y)) for a, x, y in POINT.findall(m.group(5))]
                yield int(m.group(1)), m.group(2), alts, entrances


def load_dungeons(areas=None):
    """areaId -> { name, areas (the dungeon's own and its alternatives), entrances [(areaId, x, y)] }
    for the given area IDs (default: the leveling dungeons, LEVELS), in QuestieDB's order."""
    out = {}
    for area, name, alts, entrances in _entries():
        out.setdefault(area, {'name': name, 'areas': {area, *alts}, 'entrances': entrances})
    # Dire Maul's wings are listed separately (10022-10027), and Stratholme's Gauntlet (10001):
    # fold them into the dungeon.
    for area, d in list(out.items()):
        if area != 2557 and d['name'] == 'Dire Maul' and 2557 in out:
            out[2557]['areas'] |= d['areas']
            del out[area]
        if area != 2017 and d['name'] == 'Stratholme' and 2017 in out:
            out[2017]['areas'] |= d['areas']
            del out[area]
    keep = LEVELS if areas is None else areas
    return {a: d for a, d in out.items() if a in keep}


def dungeon_areas():
    """Every area ID inside any dungeon or raid (its own and its alternatives)."""
    out = set()
    for area, _, alts, _ in _entries():
        out.add(area)
        out.update(alts)
    return out


def dungeon_entrances():
    """Every dungeon and raid entrance: [(areaId, x, y)]. QuestieDB files some mobs that only live
    inside a dungeon at its entrance, out in the zone."""
    out = []
    for _, _, _, entrances in _entries():
        out += entrances
    return out


def instance_ids():
    """QuestieDB's { instance map ID: area ID } (instanceIdToAreaId.lua), where it names the area
    by number or by one of ZoneDB's zoneIDs (resolved through the zones enum when it's there)."""
    enum = {}
    enum_lua = os.path.join(os.path.dirname(paths.QUESTIEDB_TOC), 'src', 'corrections', 'enum', 'zones.lua')
    if os.path.exists(enum_lua):
        with open(enum_lua, encoding='utf-8') as f:
            for m in re.finditer(r'^\s*([A-Z0-9_]+)\s*=\s*(\d+)', f.read(), re.M):
                enum.setdefault(m.group(1), int(m.group(2)))
    out = {}
    with open(INSTANCE_IDS_LUA, encoding='utf-8') as f:
        for m in re.finditer(r'\[(\d+)\]\s*=\s*(?:ZoneDB\.zoneIDs\.([A-Z0-9_]+)|(\d+))', f.read()):
            area = enum.get(m.group(2)) if m.group(2) else int(m.group(3))
            if area:
                out.setdefault(int(m.group(1)), area)
    return out


def ui_map_areas():
    """QuestieDB's { uiMapID: areaID } (uiMapIdToAreaId.lua, its override list included)."""
    out = {}
    with open(UIMAP_LUA, encoding='utf-8') as f:
        for m in re.finditer(r'\[(\d+)\]\s*=\s*(\d+)', f.read()):
            out.setdefault(int(m.group(1)), int(m.group(2)))
    return out
