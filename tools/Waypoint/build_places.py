"""Places for Waypoint's "Navigate to" (trainers, services, vendors, quartermasters, mailboxes...), from
QuestieDB (Forever).

    python -I tools/Waypoint/build_places.py          (from the Waypoint folder)

Writes Waypoint/Data/Places.lua (inside this repo, never the game folder):
  npcs[id]      { name, subtitle, "A"|"H"|"AH" (friendly to), "uiMapID,x,y;..." (0-1) }; objects (mailboxes,
                meeting stones) are stored under negative IDs
  categories    the menu, in order: { name, { ids }, menu path ("Supplies > Profession supplies"), class }
  sells[item]   { npcIDs } for every vendor-sold crafting material (Quartermaster's reagents ask Waypoint)

How each kind is found:
  services      NPC flags (repair, innkeeper, banker, auctioneer, flight master, stable master, spirit healer)
  trainers      subtitles: "<Class> Trainer" (+ Pet, Portal and Demon trainers), profession trainers by rank
                (Journeyman / Expert / Artisan, "Master ..." specialists count as artisan), Weapon Master,
                Riding Instructor
  supplies      what a vendor sells (Questie's Townsfolk item lists), profession supply shops by subtitle
  quartermasters subtitles ("... Quartermaster", "... Supply Officer", faction names) plus known ones
  mailboxes, meeting stones   QuestieDB objects
Vendors inside instances are left out. questiedb.py and zones.py are copies of FieldGuide's.
"""
import collections
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from questiedb import QuestieDB, DEFAULT_TOC  # noqa: E402
from zones import Zones, _pairs  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.join(os.path.dirname(os.path.dirname(HERE)), 'addons', 'Waypoint')  # tools/Waypoint/ builds addons/Waypoint/
OUT = os.path.join(ADDON, 'Data', 'Places.lua')

F = dict(VENDOR=4, FLIGHT=8, TRAINER=16, SPIRIT_HEALER=32, INNKEEPER=128, BANKER=256, AUCTIONEER=4096,
         STABLE=8192, REPAIR=16384)
MERGE = 0.01  # spawns closer than this (0-1 map units) count as one

# Questie's Townsfolk lists (Modules/QuestieMenu/Townsfolk.lua), Classic-era ids.
TRADE_GOODS = [
    14256, 12810, 13463, 8845, 8846, 4234, 3713, 8170, 14341, 4389, 3357, 2453, 13464,
    3355, 3356, 3358, 4371, 4304, 5060, 2319, 18256, 8925, 3857, 10940, 2321, 785, 4404, 2692,
    2605, 3372, 2320, 6217, 2449, 4399, 4364, 10938, 18567, 4382, 4289, 765, 3466, 3371, 2447, 2880,
    2928, 4361, 10647, 10648, 4291, 4357, 8924, 8343, 4363, 2678, 5173, 4400, 2930, 4342, 2325, 4340,
    6261, 8923, 2324, 2604, 6260, 4378, 10290, 17194, 4341,
]
REAGENTS = [17031, 17032, 17020, 17030, 17029, 17028, 21177, 17033, 5565, 16583,
            17034, 17026, 17035, 17021, 17038, 17036, 17037]
POISONS = [5140, 2928, 8924, 5173, 2930, 8923]
DRINK = [159, 8766, 1179, 1708, 1645, 1205, 17404, 19300, 19299]
FOOD = [8932, 4536, 8952, 19301, 13724, 8953, 3927, 11109, 8957, 4608, 4599, 4593, 4592, 117, 3770, 3771, 4539,
        8950, 8948, 7228, 2287, 4601, 422, 16166, 4537, 4602, 4542, 4594, 1707, 4540, 414, 4538, 4607, 17119, 19225,
        2070, 21552, 787, 4544, 18632, 16167, 4606, 16170, 4541, 4605, 17408, 17406, 11444, 21033, 22324, 18635, 21030,
        17407, 19305, 18633, 4604, 21031, 16168, 19306, 16169, 19304, 17344, 19224, 19223]
AMMO = [11285, 3030, 19316, 2515, 2512, 11284, 19317, 2519, 2516, 3033]

GENERAL = {'General Goods', 'General Supplies', 'General Goods Vendor', 'General Store', 'General Merchant'}
SUPPLY_PROFS = ['Tailoring', 'Leatherworking', 'Alchemy', 'Engineering', 'Enchanting', 'Blacksmithing',
                'Cooking', 'Fishing', 'Mining', 'Herbalism', 'First Aid']
SUPPLY_RE = re.compile(r'^(%s) Suppl' % '|'.join(SUPPLY_PROFS))

CLASSES = ['Warrior', 'Paladin', 'Hunter', 'Rogue', 'Priest', 'Shaman', 'Mage', 'Warlock', 'Druid']
CLASS_EXTRA = {'Pet Trainer': ('HUNTER', 'Pet trainer'), 'Portal Trainer': ('MAGE', 'Portal trainer'),
               'Demon Trainer': ('WARLOCK', 'Demon trainer')}
TRAINER_PROFS = [  # menu name, subtitle pattern
    ('Alchemy', r'Alchem'), ('Blacksmithing', r'Blacksmith|Armor Crafter|Weapon Crafter'), ('Enchanting', r'Enchant'),
    ('Engineering', r'Engineer'), ('Herbalism', r'Herbal'), ('Leatherworking', r'Leatherwork'),
    ('Mining', r'\bMin(er|ing)\b'), ('Skinning', r'Skin'), ('Tailoring', r'Tailor'), ('Cooking', r'\bCook|Chef'),
    ('First Aid', r'First Aid|Physician|Medic|Trauma Surgeon'), ('Fishing', r'Fish'),
]

# Reputation quartermasters QuestieDB doesn't name in their subtitle: id -> faction.
# (Lokhtos Darkbargainer, Thorium Brotherhood, stands inside Blackrock Depths, so instances drop him.)
KNOWN_QUARTERMASTERS = {11557: 'Timbermaw Hold', 12944: 'Thorium Brotherhood', 11536: 'Argent Dawn',
                        10856: 'Argent Dawn', 10857: 'Argent Dawn', 14921: 'Zandalar Tribe'}
# Rank reward vendors ("Armor Quartermaster", a bare "Supply Officer"...): one entry for all of them.
PVP_QM = {'', 'Officer Accessories', 'Accessories', 'Armor', 'Weapons', 'Mount'}
QM_RE = re.compile(r'^(.*?)\s*(Quartermaster|Supply Officer|Supplies and Repair)$')
QM_FACTIONS = {'The Argent Dawn': 'Argent Dawn', 'The Thorium Brotherhood': 'Thorium Brotherhood',
               'Wintersaber Trainers': 'Wintersaber Trainers', 'Brotherhood of the Light': 'Brotherhood of the Light'}

MATERIAL_CLASSES = {5, 7}  # vendor-sold Reagents and Trade Goods count as crafting materials
# Vendors whose stock is a few now and then: the Darkmoon Faire's (there a week a month), the exotic
# goods merchants (Lhara, Vi'el: a handful, restocked slowly).
LIMITED_RE = re.compile(r'Darkmoon Faire|Exotic')


def as_list(v):
    if v is None:
        return []
    if isinstance(v, dict):
        return [v[k] for k in sorted(v)]
    return list(v)


def lua_str(s):
    return '"' + str(s).replace('\\', '\\\\').replace('"', '\\"') + '"'


def main():
    db = QuestieDB.load()
    zones = Zones()
    instance_areas = set(_pairs('instanceIdToAreaId.lua')[0].values())

    cache = {}

    def npc(i):
        if i not in cache:
            cache[i] = db.npc(i) if i > 0 else db.object(-i)
        return cache[i]

    def spots(n):
        out = []
        spawns = n.get('spawns') or {}
        pairs = spawns.items() if isinstance(spawns, dict) else enumerate(spawns, 1)  # keyed 1..n: a list
        for area, pts in pairs:
            area = int(area)
            if area in instance_areas:
                continue
            m = zones.map_of(area)
            if not m:
                continue
            for p in as_list(pts):
                p = as_list(p)
                if len(p) < 2 or p[0] is None or p[0] < 0:
                    continue
                x, y = round(p[0] / 100, 4), round(p[1] / 100, 4)
                if any(mm == m and math.hypot(x - xx, y - yy) < MERGE for mm, xx, yy in out):
                    continue
                out.append((m, x, y))
        return out

    def faction(i):
        if i < 0:
            return 'AH'  # mailboxes and meeting stones: anyone
        f = (npc(i) or {}).get('friendlyToFaction')
        # Reputation quartermasters of neutral factions (Timbermaw) serve anyone with the reputation.
        return f or ('AH' if i in KNOWN_QUARTERMASTERS else None)

    def usable(i):
        n = npc(i)
        return bool(n and faction(i) in ('A', 'H', 'AH') and spots(n))

    categories = []

    def add(name, ids, path=None, cls=None):
        ids = sorted({i for i in ids if usable(i)})
        if ids:
            categories.append((name, ids, path, cls))

    vendors_of = {}

    def item_vendors(item_id):
        if item_id not in vendors_of:
            vendors_of[item_id] = [int(n) for n in as_list((db.item(item_id) or {}).get('vendors'))]
        return vendors_of[item_id]

    def selling(items):
        return {n for i in items for n in item_vendors(i)}

    all_npcs = [i for i in db.ids('Npc-') if npc(i)]
    flags = {i: npc(i).get('npcFlags') or 0 for i in all_npcs}
    sub = {i: npc(i).get('subName') or '' for i in all_npcs}

    def with_flag(f):
        return [i for i in all_npcs if flags[i] & f]

    trainers = [i for i in all_npcs if flags[i] & F['TRAINER']]

    # The menu, in order: what players hunt for most first.
    for cls in CLASSES:
        add('Class trainer', [i for i in trainers if sub[i] == cls + ' Trainer'], None, cls.upper())
    for subname, (cls, name) in CLASS_EXTRA.items():
        add(name, [i for i in all_npcs if sub[i] == subname], None, cls)
    for prof, pat in TRAINER_PROFS:
        rx = re.compile(pat)
        mine = [i for i in trainers if rx.search(sub[i])]
        expert = [i for i in mine if sub[i].startswith('Expert')]
        artisan = [i for i in mine if re.match(r'(Artisan|Master|Superior)\b', sub[i])]
        path = 'Profession trainers > ' + prof
        add(prof + ' trainer', mine, path)
        add('Expert ' + prof.lower() + ' trainer', expert + artisan, path)
        add('Artisan ' + prof.lower() + ' trainer', artisan, path)
    add('Repair', with_flag(F['REPAIR']))
    add('Reagents', selling(REAGENTS))
    add('Weapon master', [i for i in trainers if sub[i] == 'Weapon Master'])
    objects = collections.defaultdict(list)
    for oid in db.ids('Object-'):
        o = db.object(oid) or {}
        if o.get('name') in ('Mailbox', 'Meeting Stone'):
            objects[o['name']].append(-oid)
    add('Mailbox', objects['Mailbox'])
    add('Auctioneer', with_flag(F['AUCTIONEER']))
    add('Banker', with_flag(F['BANKER']))
    add('Flight master', with_flag(F['FLIGHT']), 'Flight master')
    quartermasters = collections.defaultdict(list)
    for i in all_npcs:
        s = sub[i]
        if i in KNOWN_QUARTERMASTERS:
            quartermasters[KNOWN_QUARTERMASTERS[i]].append(i)
        elif not flags[i] & F['VENDOR']:
            continue
        elif s in QM_FACTIONS:
            quartermasters[QM_FACTIONS[s]].append(i)
        else:
            m = QM_RE.match(s)
            if m:
                quartermasters['PvP rewards' if m.group(1) in PVP_QM else m.group(1)].append(i)
    for fac in sorted(quartermasters, key=lambda f: (f == 'PvP rewards', f)):
        add(fac, quartermasters[fac], 'Reputation quartermasters')
    add('Stable master', with_flag(F['STABLE']))
    add('Spirit healer', with_flag(F['SPIRIT_HEALER']))
    add('Meeting stone', objects['Meeting Stone'])
    add('Innkeeper', with_flag(F['INNKEEPER']))
    add('Riding instructor', [i for i in trainers if 'Riding Instructor' in sub[i]])
    add('Trade Supplies', selling(TRADE_GOODS), 'Supplies')
    add('Poisons', selling(POISONS), 'Supplies')
    add('Food & Drink', selling(FOOD + DRINK), 'Supplies')
    add('Ammo', selling(AMMO), 'Supplies')
    add('General Goods', [i for i in all_npcs if flags[i] & F['VENDOR'] and sub[i] in GENERAL], 'Supplies')
    for prof in SUPPLY_PROFS:
        add(prof + ' Supplies', [i for i in all_npcs if flags[i] & F['VENDOR'] and SUPPLY_RE.match(sub[i])
                                 and SUPPLY_RE.match(sub[i]).group(1) == prof], 'Supplies > Profession supplies')

    # Who sells each vendor crafting material (for Quartermaster's reagents, through Waypoint's API).
    # Not the vendors with a few in stock now and then (LIMITED_RE): a material only they sell isn't
    # one you can buy when you need it (Medium Leather from the Darkmoon Faire), so it's farmed or
    # bought at the auction house like any other.
    sells = {}
    for item_id in db.ids('Item-'):
        it = db.item(item_id) or {}
        if it.get('class') in MATERIAL_CLASSES or item_id in TRADE_GOODS:
            ids = sorted({n for n in (int(v) for v in as_list(it.get('vendors')))
                          if usable(n) and not LIMITED_RE.search(sub.get(n, ''))})
            if ids:
                sells[item_id] = ids

    used = set()
    for _, ids, _, _ in categories:
        used.update(ids)
    for ids in sells.values():
        used.update(ids)

    def fmt(v):
        return ('%.4f' % v).rstrip('0').rstrip('.')

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
        f.write('-- GENERATED by tools/Waypoint/build_places.py from QuestieDB (Forever). Do not edit.\n')
        f.write('-- Source: %s\n' % os.path.basename(os.environ.get('QUESTIEDB_TOC') or DEFAULT_TOC))
        f.write('local _, ns = ...\nns.Places = {}\n\n')
        f.write('-- npcs[id] = { name, subtitle, "A"|"H"|"AH" (friendly to), "uiMapID,x,y;..." (0-1) }; objects < 0\n')
        f.write('ns.Places.npcs = {\n')
        for i in sorted(used):
            n = npc(i)
            pts = ';'.join('%d,%s,%s' % (m, fmt(x), fmt(y)) for m, x, y in spots(n))
            f.write('    [%d] = { %s, %s, "%s", "%s" },\n' % (i, lua_str(n.get('name') or '?'), lua_str(n.get('subName') or ''),
                                                            faction(i), pts))
        f.write('}\n\n-- categories, menu order: { name, { ids }, menu path or nil, class or nil }\n')
        f.write('ns.Places.categories = {\n')
        for name, ids, path, cls in categories:
            f.write('    { %s, { %s }, %s, %s },\n' % (lua_str(name), ', '.join(map(str, ids)),
                                                     lua_str(path) if path else 'nil', lua_str(cls) if cls else 'nil'))
        f.write('}\n\n-- sells[itemID] = { npcIDs }: vendor-sold crafting materials\n')
        f.write('ns.Places.sells = {\n')
        for item_id in sorted(sells):
            f.write('    [%d] = { %s },\n' % (item_id, ', '.join(map(str, sells[item_id]))))
        f.write('}\n')

    build_towns(db, zones, npc, spots, faction, all_npcs, flags, sub, objects, categories)

    print('places written: %d' % len(used))
    for name, ids, path, cls in categories:
        print('  %-34s %4d  %s%s' % (name, len(ids), path or '', (' [' + cls + ']') if cls else ''))
    print('materials with vendors: %d (Fine Thread 2321: %d)' % (len(sells), len(sells.get(2321, []))))
    for i, fac in KNOWN_QUARTERMASTERS.items():
        n = npc(i) or {}
        print('  known quartermaster %d: %s <%s> (%s)' % (i, n.get('name'), n.get('subName'), fac))
    print('%s: %.0f KB' % (os.path.relpath(OUT, os.path.dirname(os.path.dirname(HERE))), os.path.getsize(OUT) / 1024))


# ---------------------------------------------------------------------------------------------
# Towns: every town, village, camp and quest hub with what's there, for the world map's town icons
# (Towns.lua). Where a subzone is comes from the game's own tables (wago.tools CSVs of the Classic
# build): WorldMapOverlay puts each explorable subzone on its zone's map art (UiMapXMapArt: which
# art a map uses; UiMapArtStyleLayer: the 1002x668 canvas), AreaTable names it. Each NPC that serves
# players (innkeeper, repair, banker, vendor, trainer, quest giver...) and each mailbox goes in the
# smallest subzone around it; NPCs outside every subzone are grouped into camps. Capitals have
# their own maps: each is one town.
# ---------------------------------------------------------------------------------------------

WAGO = 'https://wago.tools/db2/%s/csv?build=%s'
CLASSIC = '1.15.9.70003'  # Classic Era: the towns' subzones
CACHE = os.path.join(HERE, '.cache')
OUT_TOWNS = os.path.join(ADDON, 'Data', 'Towns.lua')
CITY_MAPS = {1453: 'Stormwind City', 1455: 'Ironforge', 1457: 'Darnassus', 1454: 'Orgrimmar',
             1456: 'Thunder Bluff', 1458: 'Undercity'}
CAMP_NEAR = 0.03   # members outside every subzone this close (0-1) make one camp
CAMP_JOIN = 0.06   # a camp this close to a named town's amenities is part of it (across Lakeshire's lake)
FLIGHT_NEAR = 0.2  # a flight master serves the nearest town on its map, up to this far (0-1): they
                   # often stand outside the town's subzone (Lakeshire's is across the lake)
MAX_NAMES = 4      # names per tooltip line before "+N more"
MAX_LABELS = 8     # kinds on one line before it lists just the kinds (capitals)


def wago_table(name, build=CLASSIC):
    import csv
    import io
    import subprocess
    import time
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, name + ('.csv' if build == CLASSIC else '.%s.csv' % build))
    if not os.path.exists(path):
        print('fetching %s ...' % name)
        data = subprocess.run(['curl', '-s', '-f', '-A', 'Mozilla/5.0', WAGO % (name, build)], capture_output=True, check=True).stdout
        if not data.startswith(b'ID'):
            raise SystemExit('wago.tools sent something other than a CSV for %s' % name)
        with open(path, 'wb') as f:
            f.write(data)
        time.sleep(0.5)
    with open(path, encoding='utf-8') as f:
        return list(csv.DictReader(io.StringIO(f.read())))


def subzone_rects():
    """{ uiMapID: [ (area, name, l, t, r, b) ] } in 0-1 map coordinates."""
    style = next(r for r in wago_table('UiMapArtStyleLayer') if r['UiMapArtStyleID'] == '1' and r['LayerIndex'] == '0')
    cw, ch = float(style['LayerWidth']), float(style['LayerHeight'])
    art_maps = collections.defaultdict(list)
    for r in wago_table('UiMapXMapArt'):
        art_maps[int(r['UiMapArtID'])].append(int(r['UiMapID']))
    names = {int(r['ID']): r['AreaName_lang'] for r in wago_table('AreaTable')}
    out = collections.defaultdict(list)
    for r in wago_table('WorldMapOverlay'):
        area = int(r['AreaID_0'])
        if not area or area not in names:
            continue
        hl, hr, ht, hb = (int(r[k]) for k in ('HitRectLeft', 'HitRectRight', 'HitRectTop', 'HitRectBottom'))
        if hr > hl and hb > ht:
            l, t, rr, b = hl, ht, hr, hb
        else:
            l, t = int(r['OffsetX']), int(r['OffsetY'])
            rr, b = l + int(r['TextureWidth']), t + int(r['TextureHeight'])
        for m in art_maps.get(int(r['UiMapArtID']), []):
            out[m].append((area, names[area], l / cw, t / ch, rr / cw, b / ch))
    return out


def build_towns(db, zones, npc, spots, faction, all_npcs, flags, sub, objects, categories):
    rects = subzone_rects()

    # What each place is, for the tooltip: npc id -> [(line, label)].
    roles = collections.defaultdict(list)
    for name, ids, path, cls in categories:
        if path and path.startswith('Supplies') or name == 'Reagents':
            line, label = 'Vendors', name
        elif name == 'Class trainer':
            line, label = 'Trainers', cls.title()
        elif name in ('Pet trainer', 'Portal trainer', 'Demon trainer', 'Weapon master', 'Riding instructor'):
            line, label = 'Trainers', name[0].upper() + name[1:]
        elif path and path.startswith('Profession trainers'):
            line, label = 'Trainers', name.replace(' trainer', '').title()
        elif path == 'Reputation quartermasters':
            line, label = 'Quartermasters', name
        elif name in ('Mailbox', 'Stable master', 'Spirit healer', 'Meeting stone'):
            line, label = 'Services', name
        else:
            continue
        for i in ids:
            roles[i].append((line, label))
    # A trainer listed as "Tailoring", "Expert Tailoring" and "Artisan Tailoring": keep the highest.
    for i, rs in roles.items():
        keep = []
        for line, label in rs:
            base = label.split(' ', 1)[-1] if label.split(' ', 1)[0] in ('Expert', 'Artisan') else None
            if line == 'Trainers' and any(l2 == 'Trainers' and l2b.endswith(' ' + label) for l2, l2b in rs):
                continue  # "Tailoring" when "Expert Tailoring" is there too
            if base and label.startswith('Expert') and ('Trainers', 'Artisan ' + base) in rs:
                continue
            keep.append((line, label))
        roles[i] = keep

    def member_kinds(i):
        """(line, label, name) for one NPC or object, or [] when it isn't a town amenity."""
        n = npc(i) or {}
        name = n.get('name') or '?'
        if i < 0:
            return [(line, label, None) for line, label in roles.get(i, [])]
        f = flags.get(i, 0)
        out = [(line, label, name) for line, label in roles.get(i, [])]
        if f & F['INNKEEPER']:
            out.append(('Innkeeper', None, name))
        if f & F['REPAIR']:
            out.append(('Repair', None, name))
        if f & F['BANKER']:
            out.append(('Bank', None, name))
        if f & F['AUCTIONEER']:
            out.append(('Auction House', None, name))
        if f & F['FLIGHT']:
            out.append(('Flight', None, name))
        if f & F['VENDOR'] and not any(k[0] in ('Vendors', 'Quartermasters', 'Trainers') for k in out) and sub.get(i):
            out.append(('Other vendors', sub[i], name))
        if as_list(n.get('questStarts')):
            out.append(('Quests', None, name))
        return out

    # Every amenity's spots: (map, x, y, id, kinds, faction).
    members = []
    candidates = list(all_npcs) + [i for ids in objects.values() for i in ids]
    for i in candidates:
        kinds = member_kinds(i)
        if not kinds:
            continue
        n = npc(i)
        fac = faction(i)
        if fac not in ('A', 'H', 'AH'):
            continue
        for m, x, y in spots(n):
            members.append((m, x, y, i, kinds, fac))

    # Into subzones (smallest rectangle around each spot), city maps, or camps.
    groups = collections.defaultdict(list)  # (map, area or name) -> members
    loose = collections.defaultdict(list)
    for mem in members:
        m, x, y = mem[0], mem[1], mem[2]
        if m in CITY_MAPS:
            groups[(m, CITY_MAPS[m])].append(mem)
            continue
        inside = [r for r in rects.get(m, []) if r[2] <= x <= r[4] and r[3] <= y <= r[5]]
        if inside:
            r = min(inside, key=lambda r: (r[4] - r[2]) * (r[5] - r[3]))
            groups[(m, r[1])].append(mem)
        else:
            loose[m].append(mem)
    for m, mems in loose.items():
        camps = []
        for mem in mems:
            for c in camps:
                cx, cy = c['x'] / len(c['m']), c['y'] / len(c['m'])
                if math.hypot(mem[1] - cx, mem[2] - cy) < CAMP_NEAR:
                    c['m'].append(mem); c['x'] += mem[1]; c['y'] += mem[2]
                    break
            else:
                camps.append({'m': [mem], 'x': mem[1], 'y': mem[2]})
        for c in camps:
            cx, cy = c['x'] / len(c['m']), c['y'] / len(c['m'])
            # Part of a named town nearby?
            join, join_d = None, CAMP_JOIN
            for key, gm in groups.items():
                if key[0] != m:
                    continue
                d = min(math.hypot(a[1] - b[1], a[2] - b[2]) for a in c['m'] for b in gm)
                if d < join_d:
                    join, join_d = key, d
            if join:
                groups[join].extend(c['m'])
                continue
            near = min(rects.get(m, []), key=lambda r: math.hypot((r[2] + r[4]) / 2 - cx, (r[3] + r[5]) / 2 - cy), default=None)
            name = ('Camp near ' + near[1]) if near else 'Camp'
            key = (m, name)
            while key in groups:
                key = (m, key[1] + ' ')
            groups[key] = c['m']

    flight_spots = collections.defaultdict(list)
    for mem in members:
        if any(k[0] == 'Flight' for k in mem[4]):
            flight_spots[mem[0]].append((mem[1], mem[2]))

    towns, town_mems = [], []
    for (m, name), mems in groups.items():
        lines = collections.OrderedDict((k, collections.OrderedDict()) for k in (
            'Innkeeper', 'Repair', 'Bank', 'Auction House', 'Vendors', 'Other vendors', 'Trainers', 'Quartermasters', 'Services'))
        quests, flight, inn, ids_seen = set(), False, None, set()
        for mem in mems:
            mm, x, y, i, kinds, fac = mem
            for line, label, who in kinds:
                if line == 'Quests':
                    quests.add(i)
                elif line == 'Flight':
                    flight = True  # (for whether it's a town; which town it serves is decided below)
                else:
                    if line == 'Innkeeper' and not inn:
                        inn = (x, y)
                    bucket = lines[line].setdefault(label or '', [])
                    if who and who not in bucket:
                        bucket.append(who)
            ids_seen.add(i)
        services = sum(1 for k, v in lines.items() if k != 'Innkeeper' and v)
        if not (inn or flight or services >= 2 or len(quests) >= 3):
            continue
        facs = collections.Counter(mem[5] for mem in mems if mem[3] > 0)
        a, h = facs['A'], facs['H']
        fac = 'A' if a > h and a >= facs['AH'] else 'H' if h > a and h >= facs['AH'] else 'AH'
        x, y = inn or (sum(mem[1] for mem in mems) / len(mems), sum(mem[2] for mem in mems) / len(mems))
        text = []
        for line, labels in lines.items():
            if not labels:
                continue
            if len(labels) > MAX_LABELS:
                # A capital's dozens of merchants and trainers: just the kinds.
                kinds = [label for label in labels if label]
                text.append('%s|%s' % (line, ', '.join(kinds) if kinds else '%d of them' % sum(len(v) for v in labels.values())))
                continue
            parts = []
            for label, who in labels.items():
                names = ', '.join(who[:MAX_NAMES]) + (' +%d more' % (len(who) - MAX_NAMES) if len(who) > MAX_NAMES else '')
                if label and who:
                    parts.append('%s (%s)' % (label, names))
                elif label:
                    parts.append(label)
                else:
                    parts.append(names)
            text.append('%s|%s' % (line, '; '.join(parts)))
        # Each quest giver's quests, so the game can count the givers with something for you now.
        givers = [sorted({int(q) for q in as_list((npc(i) or {}).get('questStarts'))}) for i in sorted(quests)]
        towns.append([name.strip(), m, x, y, fac, False, len(quests), text, [g for g in givers if g]])
        town_mems.append(mems)

    # Capitals: also on their zone's map, where that map's overlay shows the city.
    copies = []  # (copy on the zone map, the city's own town)
    for m, city in CITY_MAPS.items():
        town = next((t for t in towns if t[1] == m), None)
        for zm, rs in rects.items():
            for r in rs:
                if town and r[1] == city and zm not in CITY_MAPS:
                    same = next((t for t in towns if t[1] == zm and t[0] == city), None)
                    if same:
                        same[4:] = town[4:]  # the NPCs at the city's foot already made a town: it's the city
                        copies.append((same, town))
                        continue
                    cx, cy = (r[2] + r[4]) / 2, (r[3] + r[5]) / 2
                    towns.append([city, zm, cx, cy] + town[4:])
                    town_mems.append([(zm, cx, cy, 0, [], town[4])])
                    copies.append((towns[-1], town))

    # Each flight master serves one town on its map: the nearest with an inn if one is in reach (the
    # real hub), else the nearest at all (distance to the town's nearest amenity).
    for m, fms in flight_spots.items():
        for fx, fy in fms:
            near = []
            for t, mems in zip(towns, town_mems):
                if t[1] == m:
                    d = min(math.hypot(mem[1] - fx, mem[2] - fy) for mem in mems)
                    if d < FLIGHT_NEAR:
                        near.append((not any(line.startswith('Innkeeper|') for line in t[7]), d, id(t), t))
            if near:
                min(near)[3][5] = True
    for copy, town in copies:
        copy[5] = copy[5] or town[5]

    towns.sort(key=lambda t: (t[1], t[0]))
    with open(OUT_TOWNS, 'w', encoding='utf-8', newline='\n') as f:
        f.write('-- GENERATED by tools/Waypoint/build_places.py from QuestieDB (Forever) and the game\'s map tables\n'
                '-- (wago.tools, Classic build). Do not edit.\n')
        f.write('-- { name, uiMapID, x, y (0-1), "A"|"H"|"AH", flight master?, quest givers, "Line|text", ...,\n'
                '--   g = { { quest IDs one giver starts }, ... } }\n')
        f.write('local _, ns = ...\nns.Towns = {\n')
        for name, m, x, y, fac, flight, quests, text, givers in towns:
            g = (', g = { %s }' % ', '.join('{ %s }' % ', '.join(map(str, q)) for q in givers)) if givers else ''
            f.write('    { %s, %d, %s, %s, "%s", %s, %d%s%s },\n' % (
                lua_str(name), m, ('%.4f' % x).rstrip('0').rstrip('.'), ('%.4f' % y).rstrip('0').rstrip('.'), fac,
                'true' if flight else 'false', quests, ''.join(', ' + lua_str(t) for t in text), g))
        f.write('}\n')

    print('towns written: %d (%s)' % (len(towns), ', '.join('%s %d' % (k, v) for k, v in
                                                          collections.Counter(t[4] for t in towns).items())))
    for want in ('Lakeshire', 'Goldshire', 'The Crossroads', 'Booty Bay', 'Stormwind City'):
        for t in towns:
            if t[0] == want:
                print('  %s (map %d, %s, flight=%s, quests=%d)' % (t[0], t[1], t[4], t[5], t[6]))
                for line in t[7]:
                    print('      ' + line)
                break
        else:
            print('  %s: NOT FOUND' % want)
    print('%s: %.0f KB' % (os.path.relpath(OUT_TOWNS, os.path.dirname(os.path.dirname(HERE))), os.path.getsize(OUT_TOWNS) / 1024))


if __name__ == '__main__':
    main()
