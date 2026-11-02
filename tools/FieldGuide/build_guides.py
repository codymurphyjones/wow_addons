"""Builds Field Guide's leveling guides from Questie's Forever database and Wowhead's quest XP.

For every race it plans sections (one zone and level range each). It simulates a character
questing through each zone:
  * Every quest the race can take whose giver stands in the zone is a candidate. Class quests,
    repeatables and quests started from items are left out.
  * The route walks from step to step, always taking the nearest one: pick up (batched at each
    quest giver), do the objectives (at the busiest spot of the mobs, objects or drops it needs),
    or turn in. A quest only becomes available once its prerequisites are turned in and the
    simulated character is high enough for it.
  * XP: Wowhead's quest XP, scaled to the character's level as the game does (Questie's cmangos
    formula), plus an estimate for the kills along the way.
  * Quests worth too little for the walk (XP per minute well below the section's typical rate)
    are dropped, unless a kept quest needs them first. Dropped quests are listed in the report.
  * If the next quests need a higher level than the route reaches, a "grind" step says how far.

Output: Guides/Data.lua (the quests the guides use, with where to go for each step) and
Guides/<Race>.lua (each race's sections), plus tools/FieldGuide/guides_report.txt.

    python tools/FieldGuide/fetch_xp.py        # once: quest XP from Wowhead (cached)
    python tools/FieldGuide/build_guides.py
"""
import collections
import csv
import io
import json
import math
import os
import re
import tarfile

import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # sibling modules, also under python -I
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "_shared"))
import luawrite  # noqa: E402
import paths  # noqa: E402
from questiedb import QuestieDB, lua_list  # noqa: E402
from instances import LEVELS, OUTSIDE_FIRST, WINGS, dungeon_areas, dungeon_entrances, dungeon_of, load_dungeons  # noqa: E402
from zones import Zones
from quest_areas import assign as assign_areas
from quest_text import action_line, callout, goal, prose_actions

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.join(os.path.dirname(os.path.dirname(HERE)), "addons", "FieldGuide")  # tools/FieldGuide/ builds addons/FieldGuide/
GUIDES = os.path.join(ADDON, 'Guides')
REPORT = os.path.join(HERE, 'guides_report.txt')
XP_JSON = os.path.join(HERE, 'data', 'wowhead_quests.json')

# XP to go from level i to i + 1 (Classic).
XP_TO_LEVEL = [0, 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400,
               16000, 17700, 19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400,
               44300, 47400, 50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700, 95800,
               101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200, 147500, 153900, 160400,
               167100, 173900, 180800, 187900, 195000, 202300, 209800]
MAX_LEVEL = 60

ALLIANCE, HORDE = 'Alliance', 'Horde'
SKY_A, SKY_H = 2 ** 32, 2 ** 33

ZONE = {1429: 'Elwynn Forest', 1436: 'Westfall', 1426: 'Dun Morogh', 1432: 'Loch Modan', 1438: 'Teldrassil',
        1439: 'Darkshore', 1411: 'Durotar', 1413: 'The Barrens', 1412: 'Mulgore', 1420: 'Tirisfal Glades',
        1421: 'Silverpine Forest', 2521: 'Zephras Isle'}

# The early bracket, as zone guides per faction. Anyone of the faction can follow any of them:
# the planner plans for every race of the faction, and the addon skips quests your race can't
# take. Home zones start at level 1; each next zone starts where the zones leading to it end.
FACTION_MASK = {ALLIANCE: 1 + 4 + 8 + 64 + SKY_A, HORDE: 2 + 16 + 32 + 128 + SKY_H}
HOME_ZONES = {ALLIANCE: [1429, 1426, 1438, 2521], HORDE: [1411, 1412, 1420, 2521]}
NEXT_ZONES = {ALLIANCE: {1436: [1429], 1432: [1426], 1439: [1438, 2521]},
              HORDE: {1413: [1411, 1412, 2521], 1421: [1420]}}
# Capital cities: hand-off quests that only send you to report in town don't count as a way on.
CAPITALS = {1453, 1454, 1455, 1456, 1457, 1458}
MIN_ZONE_QUESTS = 6   # a zone gets a guide when the faction has at least this many quests there
BAND_GAP = 6          # a gap this wide between quest levels splits a zone into two sections

# Route costs, in "map units": one percent of a zone map's height (the width counts 1.5x, like
# the map image). One unit is roughly five seconds of running.
SECONDS_PER_UNIT = 5
KILL_UNITS = 6        # one kill
LOOT_UNITS = 3        # one object to click
DROP_RATE = 0.45      # items looted from mobs: kills per item = 1 / rate
ZONE_CHANGE_UNITS = 120
NEAR = 2.0            # steps this close together count as one stop
CLUSTER_RADIUS = 7.0  # spawns within this of the busiest spawn make up an objective's area
GROUP_SHARE = 0.4     # a group this dense, of the densest one, is a place to do the objective
MAX_GROUPS = 8        # groups looked at for a quest
PLACE_RADIUS = 10.0   # map units: what's this close to a group is around it (place_objectives)
PLACE_WEIGHT = 0.15   # what each thing around a group counts for: a densest group is worth 1
PLACE_LEVELS = 4      # other quests up to this many levels above are ones you'd do on the same trip
PLACE_ROUNDS = 3
KEEP_EFFICIENCY = 0.3  # quests paying under this share of the section's typical XP/minute are dropped
LOG_SIZE = 20
MAX_GRIND_LEVELS = 2   # grind at most this many levels to reach the next quests
LEVEL_PULL = 8         # units a step counts as farther per level its quest is above you: finish camp before moving on
STARTER_LEVEL = 5      # a home zone's quests up to this level are never dropped: they're how a new character levels
# Fights along the way: hostile mobs this near the walk to a quest's objective and hand-in (map units,
# about 18 yards), of which FIGHT_SHARE end up in a fight. Mobs SAFE_LEVELS under you or more leave you
# alone (and pay little); mobs far over you, you go round. FIGHT_SHARE is set from a real character's
# journey log: to level 6, 34% of its XP came from quests, so everything earned is about 3x quest XP.


def kill_seconds(level):
    """A kill, with the walk to the next mob: 18 seconds early on (the journey log's pace: level 6 in 52
    minutes of real play), 35 by level 60, as fights get longer."""
    return 18 + 17 * max(0, min(55, level - 5)) / 55


PATH_UNITS = 3.5
FIGHT_SHARE = 0.14
SAFE_LEVELS = 6
STEP_UNITS = 2.0       # how often the walk is sampled
STRETCH = 3            # a quest waits until you're within this many levels of it (Engine.lua has the same rule)

REPEATABLE = 1  # specialFlags

QUESTIE = os.path.join(os.path.dirname(os.path.dirname(paths.QUESTIEDB_TOC)), 'Questie')


def hidden_quests():
    """Quests Questie never shows: its blacklist (the unconditional entries) and holiday quests."""
    out = set()
    try:
        with open(os.path.join(QUESTIE, 'Database', 'Corrections', 'QuestieQuestBlacklist.lua'), encoding='utf-8') as f:
            out.update(int(m) for m in re.findall(r'\[(\d+)\]\s*=\s*true', f.read()))
        holidays = os.path.join(QUESTIE, 'Database', 'Corrections', 'Holidays')
        for root, _, files in os.walk(holidays):
            for name in files:
                with open(os.path.join(root, name), encoding='utf-8') as f:
                    out.update(int(m) for m in re.findall(r'eventQuests,\s*\{\s*"[^"]*",\s*(\d+)', f.read()))
    except OSError as e:
        print('Questie corrections not found (%s): blacklisted and holiday quests may slip in.' % e)
    return out


def battleground_areas():
    """The area IDs of the battlegrounds, from the game's tables: a quest filed under one is a PvP quest.
    Waypoint's cached Map table says which maps are battlegrounds (InstanceType 3); not all of them
    give their area, so it's matched by name in AreaTable too."""
    with tarfile.open(os.path.join(os.path.dirname(HERE), 'Waypoint', '.cache.tar.xz'), 'r:xz') as t:
        names = [m.name for m in t.getmembers()]
        def table(name):
            found = sorted(n for n in names if os.path.basename(n).startswith(name))[-1]
            return list(csv.DictReader(io.StringIO(t.extractfile(found).read().decode('utf-8'))))
        maps = [r for r in table('Map-') if r.get('InstanceType') == '3']
        areas = table('AreaTable')
    wanted = {r.get('MapName_lang') for r in maps}
    out = {int(r['AreaTableID']) for r in maps if int(r['AreaTableID'] or 0)}
    # (Top-level areas only: a zone's own place of the same name isn't the battleground.)
    out |= {int(r['ID']) for r in areas if r.get('AreaName_lang') in wanted and not int(r.get('ParentAreaID') or 0)}
    return out


PVP_AREAS = battleground_areas()


def practical_level(q):
    """The level a quest is worth taking at: its required level, or STRETCH under the quest's own
    level. QuestieDB says a level 8 quest needs only level 1 (Sharing the Land), and its mobs are level 8."""
    return max(q.req, q.level - STRETCH)


def can_take(mask, faction_mask):
    """Some race of the faction can take it."""
    return not mask or (mask & faction_mask) != 0


def quest_xp(base, qlevel, level):
    """The game's quest XP at a character level (Questie's cmangos formula)."""
    if not base or level >= MAX_LEVEL:
        return 0
    mult = min(10, max(1, 2 * (qlevel - level) + 20))
    xp = base * mult / 10
    if xp <= 100:
        xp = 5 * math.floor((xp + 2) / 5)
    elif xp <= 500:
        xp = 10 * math.floor((xp + 5) / 10)
    elif xp <= 1000:
        xp = 25 * math.floor((xp + 12) / 25)
    else:
        xp = 50 * math.floor((xp + 25) / 50)
    return int(xp)


def gray_level(level):
    if level <= 5:
        return 0
    if level <= 39:
        return level - level // 10 - 5
    return level - level // 5 - 1


def zero_difference(level):
    for top, zd in ((7, 5), (9, 6), (11, 7), (15, 8), (19, 9), (29, 11), (39, 12), (44, 13), (49, 14), (54, 15), (59, 16)):
        if level <= top:
            return zd
    return 17


def kill_xp(mob_level, level):
    """Classic XP for one kill of a mob of mob_level at character level."""
    if mob_level <= gray_level(level):
        return 0
    base = 45 + 5 * mob_level
    if mob_level >= level:
        return int(base * (1 + 0.05 * min(4, mob_level - level)))
    return int(base * (1 - (level - mob_level) / zero_difference(level)))


def npc_level(npc):
    return ((npc.get('minLevel') or 1) + (npc.get('maxLevel') or 1)) / 2


def hostile(npc):
    """A mob you kill: not friendly to a faction, with a real level (scripted NPCs say 9999)."""
    return not npc.get('friendlyToFaction') and 0 < npc_level(npc) <= 63


class Point:
    __slots__ = ('map', 'x', 'y')

    def __init__(self, m, x, y):
        self.map, self.x, self.y = m, x, y

    def dist(self, o):
        if o is None:
            return 0
        if self.map != o.map:
            return ZONE_CHANGE_UNITS
        return math.hypot((self.x - o.x) * 1.5, self.y - o.y)


# --- the quest data ---------------------------------------------------------------------------

def field(table, i):
    """Index i (1-based) of a Lua array that CBOR gave as a list or a map."""
    if isinstance(table, list):
        return table[i - 1] if len(table) >= i else None
    if isinstance(table, dict):
        return table.get(i)
    return None


class Data:
    def __init__(self):
        self.db = QuestieDB.load()
        self.zones = Zones()
        self.wowhead = {}
        try:
            with open(XP_JSON, encoding='utf-8') as f:
                self.wowhead = {int(k): v for k, v in json.load(f).items()}
        except (OSError, ValueError):
            print('No Wowhead XP yet (run tools/FieldGuide/fetch_xp.py): XP is estimated from quest levels.')
        hidden = hidden_quests()
        self.quests = {qid: self.db.quest(qid) for qid in self.db.quest_ids() if qid not in hidden}
        self.inside_areas = dungeon_areas()
        self.entrances = [Point(m, x, y) for m, x, y in
                          ((self.zones.map_of(a), x, y) for a, x, y in dungeon_entrances()) if m]
        self._xp_by_level = self._typical_xp()
        self._grid = None

    def _typical_xp(self):
        by = collections.defaultdict(list)
        for qid, row in self.wowhead.items():
            if row.get('xp') and row.get('level'):
                by[row['level']].append(row['xp'])
        return {lvl: sorted(v)[len(v) // 2] for lvl, v in by.items()}

    def xp(self, qid):
        row = self.wowhead.get(qid)
        if row and row.get('xp'):
            return row['xp'], 'wowhead'
        level = self.quests[qid].get('questLevel') or 1
        return self._xp_by_level.get(level, int(100 * level ** 1.4)), 'estimate'

    def hostile_grid(self):
        """{(uiMapID, cell x, cell y): [(x, y, level)]}: every mob that would attack you, by map cell."""
        if self._grid is None:
            self._grid = collections.defaultdict(list)
            for npc_id in self.db.ids('Npc-'):
                npc = self.db.npc(npc_id)
                if not npc or npc.get('friendlyToFaction') or not hostile(npc):
                    continue
                level = npc_level(npc)
                for p in self.spawns(npc.get('spawns'), None):
                    self._grid[(p.map, int(p.x // 5), int(p.y // 5))].append((p.x, p.y, level))
        return self._grid

    def fights(self, points, level):
        """(kills, XP) from hostile mobs along a walk through points, for a character of this level."""
        grid = self.hostile_grid()
        seen, kills, xp = set(), 0.0, 0.0
        for a, b in zip(points, points[1:]):
            if a.map != b.map:
                continue
            steps = max(1, int(a.dist(b) / STEP_UNITS))
            for i in range(steps + 1):
                x, y = a.x + (b.x - a.x) * i / steps, a.y + (b.y - a.y) * i / steps
                cx, cy = int(x // 5), int(y // 5)
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        for m in grid.get((a.map, cx + dx, cy + dy), ()):
                            if m in seen or abs(m[0] - x) * 1.5 > PATH_UNITS or abs(m[1] - y) > PATH_UNITS:
                                continue
                            seen.add(m)
                            if level - SAFE_LEVELS < m[2] <= level + 3:
                                kills += FIGHT_SHARE
                                xp += FIGHT_SHARE * kill_xp(round(m[2]), level)
        return kills, xp

    def spawns(self, spawns, maps):
        """Spawn points of an NPC or object inside the given uiMapIDs."""
        out = []
        # {[1] = ...} (Dun Morogh's area ID is 1) comes through CBOR as an array.
        if isinstance(spawns, list):
            spawns = {i: v for i, v in enumerate(spawns, 1) if v}
        if not isinstance(spawns, dict):
            return out
        for area, pts in spawns.items():
            m = self.zones.map_of(int(area))
            if not m or (maps is not None and m not in maps):
                continue
            for p in lua_list(pts):
                p = lua_list(p)
                if len(p) >= 2 and p[0] is not None and p[0] >= 0 and p[1] >= 0:
                    out.append(Point(m, float(p[0]), float(p[1])))
        return out

    def drop_area(self, item):
        """Where an item drops out in the world: (mob name, [Points] busiest first, at a dungeon
        entrance?), or None when it only drops inside dungeons and raids (or nowhere Questie
        knows). Mobs QuestieDB places at a dungeon's entrance count as out in the world: you walk
        to the entrance and kill them there."""
        points, names = [], {}
        for npc_id in lua_list(item.get('npcDrops')):
            npc = self.db.npc(npc_id)
            if not npc or not hostile(npc):
                continue
            spawns = npc.get('spawns')
            if isinstance(spawns, list):
                spawns = {i: v for i, v in enumerate(spawns, 1) if v}
            for area, pts in (spawns or {}).items():
                if int(area) in self.inside_areas:
                    continue
                for p in self.spawns({area: pts}, None):
                    points.append(p)
                    names[id(p)] = npc.get('name') or '?'
        if not points:
            return None
        best, best_n = points[0], -1
        for p in points if len(points) <= 400 else points[::len(points) // 400 + 1]:
            n = sum(1 for o in points if p.dist(o) <= CLUSTER_RADIUS)
            if n > best_n:
                best, best_n = p, n
        near = sorted((o for o in points if best.dist(o) <= CLUSTER_RADIUS * 1.5), key=best.dist)[:12]
        at_entrance = any(e.map == best.map and best.dist(e) <= 4 for e in self.entrances)
        return names[id(best)], near, at_entrance

    def sources(self, q, item=None):
        """The NPCs and objects a quest's objectives (or the item that starts it) come from:
        [(name, {area IDs it spawns in})]."""
        out = []

        def add(row):
            if not row:
                return
            spawns = row.get('spawns')
            if isinstance(spawns, list):
                spawns = {i: v for i, v in enumerate(spawns, 1) if v}
            out.append((row.get('name') or '', {int(a) for a in (spawns or {})}))

        def add_item(it):
            if not it:
                return
            add(it)  # some objects share the item's name (a book you take it from)
            for npc_id in lua_list(it.get('npcDrops')):
                add(self.db.npc(npc_id))
            for obj_id in lua_list(it.get('objectDrops')):
                add(self.db.object(obj_id))

        objs = q.get('objectives')
        for entry in lua_list(field(objs, 1)):
            add(self.db.npc(lua_list(entry)[0]))
        for entry in lua_list(field(objs, 2)):
            add(self.db.object(lua_list(entry)[0]))
        for entry in lua_list(field(objs, 3)):
            add_item(self.db.item(lua_list(entry)[0]))
        for entry in lua_list(field(objs, 5)):
            for npc_id in lua_list(lua_list(entry)[0] if lua_list(entry) else []):
                add(self.db.npc(npc_id))
        if item:
            add_item(self.db.item(item))
        return out

    def wing_of(self, area, q, item=None):
        """The wing of a dungeon with wings that a quest is done in: the last one (in route order)
        any of its mobs or objects is in, or None when it isn't tied to one."""
        wings = WINGS.get(area)
        if not wings:
            return None
        found = -1
        for name, areas in self.sources(q, item):
            for i, w in enumerate(wings):
                if name in w['names'] or areas & set(w['areas']):
                    found = max(found, i)
        return wings[found]['key'] if found >= 0 else None

    def person(self, givers, maps):
        """Where to find a quest giver or ender: (Point, name, kind, id) or None."""
        for kind, idx in (('npc', 1), ('object', 2)):
            for pid in lua_list(field(givers, idx)):
                row = self.db.npc(pid) if kind == 'npc' else self.db.object(pid)
                if not row:
                    continue
                pts = self.spawns(row.get('spawns'), maps)
                if pts:
                    return pts[0], row.get('name') or '?', kind, pid
        return None

    def objective(self, q, maps, prefer=None):
        """The objective area: (center Point, [Points], effort units, mob level), None when there's
        nothing to do but talk, or INSTANCE when everything it needs is inside a dungeon or raid.
        prefer: a uiMapID whose spawns win when the objective is found in several zones."""
        objs = q.get('objectives')
        if not objs or not any(lua_list(field(objs, i)) for i in (1, 2, 3, 5)):
            return None
        text = ' '.join(lua_list(q.get('objectivesText')))
        nums = [int(n) for n in re.findall(r'\b(\d{1,2})\b', text)]
        count = max(1, min(30, nums[0] if nums else 1))
        points, effort, levels = [], 0, []
        for entry in lua_list(field(objs, 1)):  # creatures: kill them, or talk to the friendly ones
            npc = self.db.npc(lua_list(entry)[0])
            if npc:
                points += self.spawns(npc.get('spawns'), maps)
                if hostile(npc):
                    levels.append(npc_level(npc))
                    effort += count * KILL_UNITS
                else:
                    effort += LOOT_UNITS
        for entry in lua_list(field(objs, 2)):  # objects
            obj = self.db.object(lua_list(entry)[0])
            if obj:
                points += self.spawns(obj.get('spawns'), maps)
                effort += count * LOOT_UNITS
        for entry in lua_list(field(objs, 3)):  # items
            item = self.db.item(lua_list(entry)[0])
            if not item:
                continue
            for npc_id in lua_list(item.get('npcDrops')):
                npc = self.db.npc(npc_id)
                if npc:
                    points += self.spawns(npc.get('spawns'), maps)
                    # (Whatever drops it gets killed, neutral beasts like Mulgore's plainstriders too.)
                    if npc_level(npc) > 0:
                        levels.append(npc_level(npc))
            for obj_id in lua_list(item.get('objectDrops')):
                obj = self.db.object(obj_id)
                if obj:
                    points += self.spawns(obj.get('spawns'), maps)
            effort += count * (KILL_UNITS / DROP_RATE if item.get('npcDrops') else LOOT_UNITS)
        for entry in lua_list(field(objs, 5)):  # kill credit
            for npc_id in lua_list(lua_list(entry)[0] if lua_list(entry) else []):
                npc = self.db.npc(npc_id)
                if npc:
                    points += self.spawns(npc.get('spawns'), maps)
            effort += count * KILL_UNITS
            for npc_id in lua_list(lua_list(entry)[0] if lua_list(entry) else []):
                npc = self.db.npc(npc_id)
                if npc and npc_level(npc) > 0:
                    levels.append(npc_level(npc))
        if not points:
            return INSTANCE
        if prefer and any(p.map == prefer for p in points):
            points = [p for p in points if p.map == prefer]
        # Every dense group of what it needs, densest first: place_objectives picks between them.
        counted = []
        for p in points if len(points) <= 400 else points[::len(points) // 400 + 1]:
            counted.append((sum(1 for o in points if p.dist(o) <= CLUSTER_RADIUS), p))
        counted.sort(key=lambda c: -c[0])
        top = counted[0][0]
        groups = []
        for n, p in counted:
            if n < top * GROUP_SHARE or len(groups) >= MAX_GROUPS:
                break
            if all(p.dist(g[2]) > CLUSTER_RADIUS * 2 for g in groups):
                near = sorted((o for o in points if p.dist(o) <= CLUSTER_RADIUS * 1.5), key=p.dist)[:24]
                cx = sum(o.x for o in near) / len(near)
                cy = sum(o.y for o in near) / len(near)
                groups.append((Point(p.map, cx, cy), near, p, n / top))
        mob_level = sum(levels) / len(levels) if levels else None
        return groups[0][0], groups[0][1], effort, mob_level, groups


def place_objectives(quests):
    """Where each quest's objective is done, of its dense groups: the one that's densest and has the
    most of the other quests around it (their objectives, givers and hand-ins), of its level or just above.
    Quests done in one place are one trip: a group off on its own means walking there and back. Each
    quest's pick moves the others', so it's gone over a few times."""
    by_map = collections.defaultdict(list)
    for q in quests:
        if q.obj:
            by_map[q.obj[0].map].append(q)
    for group in by_map.values():
        for _ in range(PLACE_ROUNDS):
            for q in group:
                choices = q.obj[4]
                if len(choices) < 2:
                    continue
                others = []
                for o in group:
                    # (Not quests below it: by then they're behind you, and it's no trip to go back.)
                    if o is not q and 0 <= o.level - q.level <= PLACE_LEVELS:
                        others.append(o.obj[0])
                        others += [x[0] for x in (o.giver, o.ender) if x and x[0].map == q.obj[0].map]
                others += [x[0] for x in (q.giver, q.ender) if x and x[0].map == q.obj[0].map]

                def score(g):
                    return g[3] + PLACE_WEIGHT * sum(1 for p in others if g[0].dist(p) <= PLACE_RADIUS)
                best = max(choices, key=score)
                q.obj = (best[0], best[1], q.obj[2], q.obj[3], choices)


INSTANCE = 'instance'


class Quest:
    """One quest as the planner sees it, for one race and set of zones."""

    def __init__(self, data, qid, maps):
        q = data.quests[qid]
        self.id, self.row = qid, q
        self.pvp = q.get('zoneOrSort') in PVP_AREAS  # Zone Clear's, not a leveling route's
        self.name = q.get('name') or ('Quest %d' % qid)
        self.level = q.get('questLevel') or 1
        if self.level < 0:
            self.level = 1
        self.req = q.get('requiredLevel') or 1
        self.base_xp, self.xp_source = data.xp(qid)
        self.giver = data.person(q.get('startedBy'), maps)
        # Started from an item (you loot it and click it): the item, and where it drops outside.
        self.item, self.drop = None, None
        items = lua_list(field(q.get('startedBy'), 3))
        if not self.giver and items:
            row = data.db.item(items[0]) or {}
            self.item = (items[0], row.get('name') or ('item %d' % items[0]))
            self.drop = data.drop_area(row)
        self.ender = data.person(q.get('finishedBy'), maps)
        self.obj = data.objective(q, maps, self.giver and self.giver[0].map)
        self.dungeon = self.obj == INSTANCE
        if self.dungeon:
            self.obj = None
        self.text = ' '.join(lua_list(q.get('objectivesText')))
        # Nothing to do but hand it in (a delivery, "speak with ..."): no objectives of any kind,
        # no place to explore, not started from an item. Leveling's detours look for these.
        objs = q.get('objectives')
        self.talk = (not (objs and any(lua_list(field(objs, i)) for i in (1, 2, 3, 4, 5)))
                     and not q.get('triggerEnd') and not self.item and not self.dungeon)
        # XP from fighting, at the quest's level: the kills its objectives take, and the mobs along the way.
        self.kill_xp, self.extra_minutes = 0, 0.0
        lv = max(1, min(59, self.level))
        if self.obj and self.obj[3]:
            self.kill_xp += int(self.obj[2] / KILL_UNITS * kill_xp(round(self.obj[3]), lv))
        walk = [p for p in ((self.giver and self.giver[0]), (self.obj and self.obj[0]), (self.ender and self.ender[0])) if p]
        if len(walk) > 1:
            kills, xp = data.fights(walk, lv)
            self.kill_xp += int(xp)
            self.extra_minutes = kills * KILL_UNITS * SECONDS_PER_UNIT / 60
        self.single = [abs(x) for x in lua_list(q.get('preQuestSingle'))]
        self.group = [abs(x) for x in lua_list(q.get('preQuestGroup'))]
        self.exclusive = lua_list(q.get('exclusiveTo'))
        self.breadcrumb_for = q.get('breadcrumbForQuestId')
        self.races = q.get('requiredRaces') or 0


# Every dungeon's quests (filed under the dungeon in QuestieDB), and later the rest of what the
# dungeon routes use: none of them goes into a zone guide, in any capacity.
DUNGEON_QUESTS = set()


def dungeon_quests(data):
    if not DUNGEON_QUESTS:
        every = load_dungeons()
        DUNGEON_QUESTS.update(qid for qid, q in data.quests.items() if dungeon_of(q, every) is not None)
    return DUNGEON_QUESTS


def candidates(data, bit, maps, dungeons=None):
    """Quests some race of the faction can do. With dungeons ({areaId: dungeon}): only the
    quests for those dungeons, as {areaId: [Quest]}. Without: never a dungeon's quest."""
    out = {} if dungeons is None else collections.defaultdict(list)
    skip = dungeon_quests(data) if dungeons is None else ()
    for qid, q in data.quests.items():
        if qid in skip:
            continue
        area = dungeon_of(q, dungeons) if dungeons is not None else None
        if dungeons is not None and area is None:
            continue
        if q.get('requiredClasses') or (q.get('specialFlags') or 0) & REPEATABLE:
            continue
        if not can_take(q.get('requiredRaces') or 0, bit):
            continue
        if (q.get('questLevel') or 0) > 60 or q.get('requiredSkill') or q.get('requiredMinRep'):
            continue
        quest = Quest(data, qid, maps)
        if not (quest.giver and quest.ender):
            continue
        # Reward tokens and the like: max-level "quests" anyone can take, with no known XP.
        if quest.xp_source == 'estimate' and (quest.level >= MAX_LEVEL or quest.level - quest.req > 10):
            continue
        if quest.name.startswith('Legacy Reward'):
            continue
        if dungeons is not None:
            out[area].append(quest)
            continue
        # Dungeon and raid quests: the zone guides are for questing out in the world.
        if quest.dungeon:
            continue
        out[qid] = quest
    return out


# --- the route simulation ---------------------------------------------------------------------

SPLIT_DISTANCE = 6.0  # map % (about 350 yd): a quest whose objectives are further apart gets one route stop each


def densest(points, limit=6):
    """The spots of the densest group of these, densest first."""
    if not points:
        return []
    sample = points if len(points) <= 200 else points[::len(points) // 200 + 1]
    best = max(sample, key=lambda p: sum(1 for o in sample if p.dist(o) <= CLUSTER_RADIUS))
    near = [p for p in sample if p.dist(best) <= CLUSTER_RADIUS]
    return [best] + [p for p in near if p is not best][:limit - 1]


def quest_actions(data, qid, text, talk, prefer=None):
    """What a quest asks, one thing at a time: [{line, name, kind, points}]. Built from the game's own
    objectives (what to kill, what drops where), so it says what the prose runs together. The prose
    adds what the data doesn't know: an item to use first, someone to keep alive. Quests with no
    objectives in the data fall back on the prose alone."""
    q = data.db.quest(qid) or {}
    objs = q.get('objectives')
    maps = None
    out = []

    def add(line, name, points):
        if not any(a['line'] == line for a in out):
            out.append({'line': line, 'name': name, 'kind': None, 'points': points})

    for entry in lua_list(field(objs, 1)) if objs else []:
        npc = data.db.npc(lua_list(entry)[0])
        if not npc or not npc.get('name'):
            continue
        name = npc['name']
        add(action_line('Kill' if hostile(npc) else 'Talk to', name, text), name, data.spawns(npc.get('spawns'), maps))
    for entry in lua_list(field(objs, 2)) if objs else []:
        obj = data.db.object(lua_list(entry)[0])
        if obj and obj.get('name'):
            # (The quest's own word when it has one: "burn the Highvale Records".)
            verb = re.search(r'\b(burn|destroy|douse|mark|deface|open|search|examine|read|inspect)\b', text, re.I)
            add(action_line(verb.group(1).capitalize() if verb else 'Use', obj['name'], text), obj['name'],
                data.spawns(obj.get('spawns'), maps))
    for entry in lua_list(field(objs, 3)) if objs else []:
        item = data.db.item(lua_list(entry)[0])
        if not item or not item.get('name'):
            continue
        name = item['name']
        drops = [data.db.object(i) for i in lua_list(item.get('objectDrops'))]
        drops = [d for d in drops if d and d.get('name')]
        mobs = [data.db.npc(i) for i in lua_list(item.get('npcDrops'))]
        mobs = [m for m in mobs if m and m.get('name')]
        points = []
        for d in drops:
            points += data.spawns(d.get('spawns'), maps)
        for m in mobs:
            points += data.spawns(m.get('spawns'), maps)
        if drops:
            same = drops[0]['name'].lower() in (name.lower(), 'a ' + name.lower())
            add(action_line('Pick up', name, text, None if same else drops[0]['name']), name, points)
        elif len(mobs) == 1:
            add(action_line('Loot', name, text, mobs[0]['name']), name, points)
        elif mobs:
            add(action_line('Loot', name, text), name, points)
        else:
            add(action_line('Get', name, text), name, points)
    if prefer:
        for a in out:
            here = [p for p in a['points'] if p.map == prefer]
            a['points'] = here or a['points']
    prose = prose_actions(text)
    if not out:
        keep = len(prose) > 1 or any(k for _, k in prose)
        return [{'line': c, 'name': None, 'kind': k, 'points': []} for c, k in prose] if keep else []
    # The first thing to do if it's an item to use; someone to keep alive at the top too.
    first = [{'line': c, 'name': None, 'kind': k, 'points': []} for c, k in prose if k]
    return first + out


def area_actions(data, quests):
    """quests: [(qid, Quest)]. Every quest's actions, with the hunting areas of the zones worked out
    together (quest_areas.py): {qid: actions}, an action in an area having 'area' = (center, [spots])."""
    actions, objectives = {}, []
    for qid, q in quests:
        if not q.text:
            continue
        actions[qid] = quest_actions(data, qid, q.text, q.talk, q.giver and q.giver[0].map)
        for i, a in enumerate(actions[qid]):
            if a['points']:
                objectives.append({'key': (qid, i), 'level': q.level, 'points': a['points']})
    for (qid, i), area in assign_areas(objectives, Point).items():
        actions[qid][i]['area'] = area
    return actions


def spread(points, cell=2.0, limit=40):
    """Where something is across a zone, thinned to one spot a cell: enough to tell what's near you."""
    if not points:
        return []
    zone = collections.Counter(p.map for p in points).most_common(1)[0][0]
    seen, out = set(), []
    for p in points:
        key = (int(p.x / cell), int(p.y / cell))
        if p.map == zone and key not in seen:
            seen.add(key)
            out.append(p)
    return out[:: max(1, len(out) // limit + 1)] if len(out) > limit else out


def action_spots(a):
    area = a.get('area')
    return [area[0]] + area[1] if area else densest(a['points'])


def action_fields(actions):
    """The quest's `g` and `sp` for Data.lua, and `o` when it's in a hunting area (or None)."""
    if not actions:
        return [], None
    rows = []
    centres = []
    for a in actions:
        spots = action_spots(a)
        if spots:
            centres.append(spots[0])
        bits = ['l = %s' % lua_str(a['line'])]
        if a['name']:
            bits.append('n = %s' % lua_str(a['name']))
        if a['kind']:
            bits.append('k = %s' % lua_str(a['kind']))
        if a.get('area'):
            bits.append('z = true')
        if spots:
            bits.append('p = { %s }' % ', '.join('{ %s }' % pt(p) for p in spots))
        everywhere = spread(a['points'])
        if len(everywhere) > 1:
            bits.append('w = { %s }' % ', '.join('{ %s }' % pt(p) for p in everywhere))
        rows.append('{ %s }' % ', '.join(bits))
    parts = ['g = { %s }' % ', '.join(rows)]
    if any(a.dist(b) > SPLIT_DISTANCE for a in centres for b in centres if a is not b and a.map == b.map):
        parts.append('sp = true')
    objective = None
    if any(a.get('area') for a in actions):
        spots = [p for a in actions for p in action_spots(a)[:4]]
        objective = 'o = { %s }' % ', '.join('{ %s }' % pt(p) for p in spots[:13])
    return parts, objective


class Sim:
    def __init__(self, level=1, xp=0, done=None, pos=None):
        self.level, self.xp = level, xp
        self.done = set(done or ())
        self.active = {}       # qid -> objectives done?
        self.pos = pos
        self.steps = []        # (kind, qid or level, Point, units)
        self.units = 0
        self.grind_units = 0
        self.gained = collections.Counter()  # qid -> xp it brought (turn-in + kills)
        self.share = collections.Counter()   # qid -> the same, in shares of the level it was earned at
        self.cost = collections.Counter()    # qid -> units spent on it

    def add_xp(self, xp):
        self.xp += xp
        while self.level < MAX_LEVEL and self.xp >= XP_TO_LEVEL[self.level]:
            self.xp -= XP_TO_LEVEL[self.level]
            self.level += 1

    def earn(self, qid, xp):
        """XP from a quest: 170 XP is 42% of level 1, and 2% of level 15."""
        self.gained[qid] += xp
        if self.level < MAX_LEVEL:
            self.share[qid] += xp / XP_TO_LEVEL[self.level]
        self.add_xp(xp)

    def level_float(self):
        return self.level + (self.xp / XP_TO_LEVEL[self.level] if self.level < MAX_LEVEL else 0)


def available(q, sim, quests, known_done):
    if practical_level(q) > sim.level:
        return False
    return available_ignoring_level(q, sim, known_done)


def available_ignoring_level(q, sim, known_done):
    if q.id in sim.done or q.id in sim.active:
        return False
    if any(e in sim.done or e in sim.active for e in q.exclusive):
        return False
    if q.breadcrumb_for and (q.breadcrumb_for in sim.done or q.breadcrumb_for in sim.active):
        return False
    done = sim.done | known_done
    if q.single and not any(p in done for p in q.single):
        return False
    if q.group and not all(p in done for p in q.group):
        return False
    return True


def run(quests, chosen, sim, target=None, known_done=frozenset(), new_quests=True, grind=True):
    """Walks the route over the chosen quests. target: stop taking new quests at this level."""
    while True:
        best = None
        taking = new_quests and (target is None or sim.level < target) and len(sim.active) < LOG_SIZE
        for qid in chosen:
            q = quests[qid]
            pull = max(0, q.level - sim.level) * LEVEL_PULL
            if qid in sim.active:
                if not sim.active[qid] and q.obj:
                    d = sim.pos.dist(q.obj[0]) if sim.pos else 0
                    cand = (d + q.obj[2] * 0.15 + pull, 2, 'O', q, q.obj[0], d + q.obj[2])
                else:
                    d = sim.pos.dist(q.ender[0]) if sim.pos else 0
                    cand = (d, 0, 'T', q, q.ender[0], d)
            elif taking and available(q, sim, quests, known_done):
                d = sim.pos.dist(q.giver[0]) if sim.pos else 0
                cand = (d + pull, 1, 'A', q, q.giver[0], d)
            else:
                continue
            if best is None or cand[:2] < best[:2]:
                best = cand
        if best is None:
            # Stuck below the next quests' level: grind to it where you stand, if it's close.
            gate = min((practical_level(quests[qid]) for qid in chosen if taking is not False and new_quests
                        and qid not in sim.done and qid not in sim.active
                        and practical_level(quests[qid]) > sim.level and available_ignoring_level(quests[qid], sim, known_done)),
                       default=None)
            if gate is None or gate > MAX_LEVEL or (target and gate > target):
                return sim
            if not grind or gate - sim.level > MAX_GRIND_LEVELS:
                # Out in the world you'd level elsewhere meanwhile; the guide shows these quests
                # as "needs level N" until then.
                sim.add_xp(sum(XP_TO_LEVEL[lv] for lv in range(sim.level, gate)) - sim.xp)
                continue
            need = sum(XP_TO_LEVEL[lv] for lv in range(sim.level, gate)) - sim.xp
            per_kill = max(1, kill_xp(sim.level, sim.level))
            units = need / per_kill * KILL_UNITS
            sim.add_xp(need)
            sim.units += units
            sim.grind_units += units
            sim.steps.append(('G', gate, sim.pos, units))
            continue
        _, _, kind, q, where, units = best
        sim.pos = where
        sim.units += units
        sim.cost[q.id] += units
        if kind == 'A':
            sim.active[q.id] = q.obj is None
        elif kind == 'O':
            sim.active[q.id] = True
            if q.obj[3]:
                kills = q.obj[2] / KILL_UNITS
                sim.earn(q.id, int(kills * kill_xp(round(q.obj[3]), sim.level)))
        else:
            del sim.active[q.id]
            sim.done.add(q.id)
            sim.earn(q.id, quest_xp(q.base_xp, q.level, sim.level))
        sim.steps.append((kind, q.id, where, units))


def needed_by(quests, chosen):
    """Quests that a chosen quest needs first."""
    need = set()
    for qid in chosen:
        q = quests[qid]
        need.update(p for p in q.single + q.group if p in quests)
    return need


def plan_zone(quests, pool, sim, target, known_done, grind=True, keep_to=0):
    """Plans one zone from sim's state: (kept quest ids, dropped quest ids, finished Sim).

    Starts from every quest in the pool, then drops the ones paying well under the route's
    typical share of a level per unit of time, as long as that makes the whole route pay better.
    (Shares, not XP: a zone's first quests pay little XP and a lot of a level.) Quests up to
    level keep_to always stay."""
    import copy

    def trial(chosen):
        t = run(quests, chosen, copy.deepcopy(sim), target, known_done, grind=grind)
        return run(quests, set(t.active), t, None, known_done, new_quests=False, grind=grind)

    def rate(t):
        start = sim.level + sim.xp / XP_TO_LEVEL[sim.level]
        return (t.level_float() - start) / max(1.0, t.units)

    chosen = set(pool)
    best = trial(chosen)
    full = best  # every quest in the pool: Zone Clear's route (see write)
    chosen = {qid for qid in chosen if qid in best.done}
    dropped = set()
    for _ in range(4):
        rates = {qid: best.share[qid] / max(1.0, best.cost[qid]) for qid in chosen}
        if not rates:
            break
        typical = sorted(rates.values())[len(rates) // 2]
        needed = needed_by(quests, chosen)
        low = {qid for qid, r in rates.items() if r < typical * KEEP_EFFICIENCY and qid not in needed
               and quests[qid].level > keep_to}
        if not low:
            break
        t = trial(chosen - low)
        if rate(t) <= rate(best) or (target and t.level < target <= best.level):
            break
        chosen -= low
        dropped |= low
        best = t
        chosen = {qid for qid in chosen if qid in best.done}
    kept = [qid for qid in chosen if qid in best.done]
    best.full = full
    best.rest = sorted(qid for qid in pool if qid not in full.done)  # never finished on the walk (level gates)
    return kept, sorted(dropped), best


# --- writing the guides -----------------------------------------------------------------------

def lua_str(s):
    return luawrite.lua_str(s, lf='space', cr='drop')


def pt(p):
    return '%d, %.1f, %.1f' % (p.map, p.x, p.y)


def starting_point(quests, pool, zone):
    """Where a new character stands in a home zone: the giver of its lowest-level quest that needs
    nothing first, among those the one with the most of the zone's quests around it."""
    free = [quests[q] for q in pool if not (quests[q].single or quests[q].group) and quests[q].giver[0].map == zone]
    if not free:
        return None
    low = min(q.level for q in free)
    spots = [q.giver[0] for q in free if q.level == low]
    return max(spots, key=lambda p: sum(1 for q in free if q.giver[0].dist(p) <= CLUSTER_RADIUS))


def add_prerequisites(data, q, used, depth=0):
    """Every quest q needs first, anywhere, so the addon can send you back for a missed one."""
    if depth > 30:
        return
    for p in q.single + q.group:
        if p in used or p not in data.quests:
            continue
        pq = Quest(data, p, None)
        if pq.ender and (pq.giver or pq.item):
            used[p] = pq
            add_prerequisites(data, pq, used, depth + 1)


def hand_offs(quests, zones):
    """Quests that take you from one zone to another: picked up in one zone and turned in in
    another one with a guide (breadcrumbs, "report to ..."), their objectives, if any, in one of
    the two. A quest that opens another one, in any zone, stays an ordinary quest of its route: left
    to the hand-off at a zone's end, the whole chain behind it hangs on making that exact move.
    Returns {qid: (from zone, to zone)}."""
    needed_here = set()
    for q in quests.values():
        for p in q.single + q.group:
            if p in quests:
                needed_here.add(p)
    out = {}
    for qid, q in quests.items():
        a, t = q.giver[0].map, q.ender[0].map
        if a == t or t in CAPITALS or t not in zones or qid in needed_here:
            continue
        if q.obj and q.obj[0].map not in (a, t):
            continue
        out[qid] = (a, t)
    return out


def zone_names(zones):
    """uiMapID -> zone name, from the top-level areas that map to it."""
    out = {}
    for area, m in sorted(zones.ui_map.items()):
        if m and m not in out and zones.zone_of(area) == area and area in zones.names:
            out[m] = zones.names[area]
    out.update(ZONE)
    return out


def bands(quests, pool):
    """A zone's quests split into level bands wherever quest levels jump by more than BAND_GAP.
    Prerequisites stay with the quests that need them (a band takes what its quests need)."""
    order = sorted(pool, key=lambda q: quests[q].level)
    out, band, top = [], [], None
    for qid in order:
        lv = quests[qid].level
        if band and lv - top > BAND_GAP:
            out.append(band)
            band = []
        band.append(qid)
        top = lv if not band[:-1] else max(top, lv)
    if band:
        out.append(band)
    # A prerequisite from an earlier band in the same zone goes along with the band needing it.
    for i, b in enumerate(out):
        need = set()
        for qid in b:
            q = quests[qid]
            need.update(p for p in q.single + q.group if p in pool)
        for j in range(i):
            moved = [p for p in out[j] if p in need]
            out[j] = [p for p in out[j] if p not in need]
            b.extend(moved)
    return [b for b in out if b]


def build():
    data = Data()
    names = zone_names(data.zones)
    used = {}            # qid -> Quest (for Data.lua)
    guides = []
    report = []
    for faction in (ALLIANCE, HORDE):
        fmask = FACTION_MASK[faction]
        quests = candidates(data, fmask, None)
        place_objectives(quests.values())
        by_zone = collections.defaultdict(list)
        for qid, q in quests.items():
            by_zone[q.giver[0].map].append(qid)
        zones = [m for m, qs in by_zone.items() if len(qs) >= MIN_ZONE_QUESTS and m in names]
        # Hand-offs to another zone aren't part of a zone's route: the addon offers one once
        # the zone is done for your level, to send you on to the next zone.
        exits = hand_offs(quests, set(zones))
        for zone in by_zone:
            rest = [q for q in by_zone[zone] if q not in exits]
            if len(rest) >= 2 * MIN_ZONE_QUESTS:
                by_zone[zone] = rest
            else:
                # Too few quests left without them: a small zone keeps its hand-offs in its route.
                for q in by_zone[zone]:
                    exits.pop(q, None)
        sections = []
        for zone, pool in ((z, b) for z in zones for b in bands(quests, by_zone[z])):
            if len(pool) < MIN_ZONE_QUESTS // 2:
                continue
            pos = None
            if zone in HOME_ZONES[faction] and min(practical_level(quests[q]) for q in pool) <= 2:
                start_level, known = 1, frozenset()
                pos = starting_point(quests, pool, zone)
            else:
                reqs = sorted(practical_level(quests[q]) for q in pool)
                start_level = max(1, reqs[len(reqs) * 15 // 100])
                # Quests in other zones count as done: the addon sends you back for any a
                # quest here needs that you missed.
                known = frozenset(q for q, x in quests.items() if x.giver[0].map != zone)
            home = start_level == 1
            kept, dropped, sim = plan_zone(quests, pool, Sim(start_level, 0, known, pos), None, known, grind=home,
                                            keep_to=STARTER_LEVEL if home else 0)
            # (PvP quests aren't leveling, but Zone Clear still needs their section.)
            if len(kept) < MIN_ZONE_QUESTS // 2 and not any(quests[q].pvp for q in pool):
                continue
            sections.append(('%s-%d-%d' % (faction.lower(), zone, start_level), names[zone], zone, start_level, sim, kept, dropped))
        sections.sort(key=lambda sec: (sec[3], sec[1]))
        # A zone you leave for a while and come back to has several sections: name each by the
        # level it starts at ("Ashenvale 15", "Ashenvale 22").
        per_zone = collections.Counter(sec[2] for sec in sections)
        sections = [(sid, '%s %d' % (title, start) if per_zone[zone] > 1 else title, zone, start, sim, kept, dropped)
                    for sid, title, zone, start, sim, kept, dropped in sections]
        # Bands of one zone that start at the same level: number them, so ids (the addon saves
        # the one you're on) and titles stay apart.
        seen = collections.Counter()
        unique = []
        for sid, title, zone, start, sim, kept, dropped in sections:
            seen[sid] += 1
            n = seen[sid]
            unique.append((sid if n == 1 else '%s-%d' % (sid, n), title if n == 1 else '%s (%d)' % (title, n),
                           zone, start, sim, kept, dropped))
        sections = unique
        guided = {sec[2] for sec in sections}
        exits = {qid: e for qid, e in exits.items() if e[0] in guided and e[1] in guided}
        guides.append((faction, faction, faction, sections, quests, exits))
        for sec in sections:
            # Kept, and for Zone Clear (and Leveling's detours) the quests dropped or never reached too.
            for qid in set(sec[5]) | set(sec[6]) | set(sec[4].rest) | {st[1] for st in sec[4].full.steps if st[0] != 'G'}:
                used[qid] = quests[qid]
                add_prerequisites(data, quests[qid], used)
        for qid in exits:
            used[qid] = quests[qid]
            add_prerequisites(data, quests[qid], used)

        pvp = sorted(q for q in quests if quests[q].pvp)
        print('%s: %d PvP quests, Zone Clear only: %s' % (faction, len(pvp), ', '.join(quests[q].name for q in pvp[:8])))
        report.append('== %s (%d zones)' % (faction, len(sections)))
        for sid, title, zone, start_level, s, k, d in sections:
            grinds = [st for st in s.steps if st[0] == 'G']
            report.append('  %-26s from level %2d to %5.2f   %3d quests, %3d dropped   ~%d min%s'
                          % (title, start_level, s.level_float(), len(k), len(d), s.units * SECONDS_PER_UNIT / 60,
                             ('   (grind to %s: ~%d min)' % (', '.join(str(g[1]) for g in grinds),
                                                           s.grind_units * SECONDS_PER_UNIT / 60)) if grinds else ''))
            est = [quests[q].name for q in k if quests[q].xp_source != 'wowhead']
            if est:
                report.append('     XP estimated: ' + ', '.join(est[:12]) + (' ...' if len(est) > 12 else ''))
            if d:
                report.append('     dropped (low XP for the walk): ' + ', '.join(
                    '%s [%d]' % (quests[q].name, q) for q in d[:20]) + (' ...' if len(d) > 20 else ''))
        report.append('  Hand-offs to another zone: %d' % len(exits))
        by_from = collections.defaultdict(list)
        for qid, (a, t) in exits.items():
            by_from[a].append('%s -> %s (%d)' % (quests[qid].name, names.get(t, t), quests[qid].req))
        for a in sorted(by_from, key=lambda m: names.get(m, '')):
            report.append('    %s: %s' % (names.get(a, a), '; '.join(sorted(by_from[a]))))
        report.append('')

    # Instance priority: each dungeon's quests per faction, for the "time for a dungeon" popup.
    dungeons = load_dungeons()
    inst = {area: {'name': d['name'], 'levels': LEVELS[area], 'entrance': None, ALLIANCE: [], HORDE: [],
                   'inside': {ALLIANCE: [], HORDE: []}, 'wings': {}, 'follow': {}}
            for area, d in dungeons.items()}
    for area, d in dungeons.items():
        for e_area, x, y in d['entrances']:
            m = data.zones.map_of(e_area)
            if m:
                inst[area]['entrance'] = (m, x, y)
                break
    report.append('== Dungeons (quests per faction)')
    for faction in (ALLIANCE, HORDE):
        for area, qs in candidates(data, FACTION_MASK[faction], None, dungeons).items():
            lo, hi = LEVELS[area]
            for q in sorted(qs, key=lambda q: (q.level, q.id)):
                if q.level <= hi + 5:
                    inst[area][faction].append(q.id)
                    used[q.id] = q
                    wing = data.wing_of(area, q.row)
                    if wing:
                        inst[area]['wings'][q.id] = wing
                    add_prerequisites(data, q, used)
        # Quests that start inside, from an item you loot there (Blackfathom's Damp Note): not
        # something to pick up before going in, but worth knowing about, and handing in after.
        for area, qs in inside_quests(data, FACTION_MASK[faction], dungeons).items():
            lo, hi = LEVELS[area]
            for q in sorted(qs, key=lambda q: (q.level, q.id)):
                if q.level <= hi + 5:
                    # Dropped out in the world: fetched before going in, like the quests picked up
                    # there; dropped inside: something to watch for during the run.
                    if q.drop:
                        inst[area][faction].append(q.id)
                    else:
                        inst[area]['inside'][faction].append(q.id)
                        wing = data.wing_of(area, q.row, q.item[0])
                        if wing:
                            inst[area]['wings'][q.id] = wing
                        # What the found item leads on to: the quests after it, handed in after the run.
                        follow = follow_ups(data, q.id, FACTION_MASK[faction], hi + 5)
                        if follow:
                            inst[area]['follow'][q.id] = follow
                            for f in follow:
                                used[f] = Quest(data, f, None)
                    used[q.id] = q
                    add_prerequisites(data, q, used)
    for area, i in sorted(inst.items(), key=lambda kv: kv[1]['levels']):
        report.append('  %-28s %2d-%2d   Alliance %2d   Horde %2d   started inside: Alliance %d, Horde %d' % (
            i['name'], i['levels'][0], i['levels'][1], len(i[ALLIANCE]), len(i[HORDE]),
            len(i['inside'][ALLIANCE]), len(i['inside'][HORDE])))
    write_instances(inst)
    for i in inst.values():
        DUNGEON_QUESTS.update(i[ALLIANCE], i[HORDE], i['inside'][ALLIANCE], i['inside'][HORDE])
        for follow in i['follow'].values():
            DUNGEON_QUESTS.update(follow)

    write(data, used, guides)
    with open(REPORT, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(report) + '\n')
    print('\n'.join(report))


def inside_quests(data, bit, dungeons):
    """Quests some race of the faction can do that start from an item, for a dungeon:
    {areaId: [Quest]} (the Quest's `item` is (itemID, name))."""
    out = collections.defaultdict(list)
    for qid, q in data.quests.items():
        area = dungeon_of(q, dungeons)
        if area is None or q.get('requiredClasses') or (q.get('specialFlags') or 0) & REPEATABLE:
            continue
        if not can_take(q.get('requiredRaces') or 0, bit) or q.get('requiredSkill') or q.get('requiredMinRep'):
            continue
        items = lua_list(field(q.get('startedBy'), 3))
        if not items:
            continue
        quest = Quest(data, qid, None)
        if quest.giver or not quest.ender:
            continue
        item = data.db.item(items[0]) or {}
        quest.item = (items[0], item.get('name') or ('item %d' % items[0]))
        out[area].append(quest)
    return out


def follow_ups(data, qid, bit, max_level=60, depth=0):
    """The quests a quest leads to (the next in its chain, and those that need it), that some race
    of the faction can do, in chain order: [questID]."""
    if depth > 6:
        return []
    out = []
    for oid, o in data.quests.items():
        pre = [abs(x) for x in lua_list(o.get('preQuestSingle'))] + [abs(x) for x in lua_list(o.get('preQuestGroup'))]
        if qid not in pre or oid == qid:
            continue
        if o.get('requiredClasses') or (o.get('specialFlags') or 0) & REPEATABLE:
            continue
        if not can_take(o.get('requiredRaces') or 0, bit) or o.get('requiredSkill') or o.get('requiredMinRep'):
            continue
        fq = Quest(data, oid, None)
        if not (fq.giver and fq.ender) or fq.level > max_level:
            continue
        out.append(oid)
        out += [f for f in follow_ups(data, oid, bit, max_level, depth + 1) if f not in out]
    return out


def write_instances(inst):
    """Guides/Instances.lua: each dungeon's quests. What the dungeon is (name, levels, entrance,
    instance map ID, final bosses, wings) is the suite's addons/shared/Instances.lua
    (tools/shared/build_instances.py), which Instance.lua joins it with by area ID."""
    os.makedirs(GUIDES, exist_ok=True)
    out = ['-- GENERATED by tools/FieldGuide/build_guides.py from QuestieDB (Forever). Do not edit.',
           'local _, ns = ...', '',
           '-- The quests of each dungeon for the instance priority, by level: the ones each faction can',
           '-- pick up for it beforehand, and (inside) the ones that start from an item you loot in there',
           '-- (all in Guides\\Data.lua). id = the dungeon\'s area ID: its name, levels, entrance, map,',
           '-- final bosses and wings are ns.Instances\' (shared\\Instances.lua).',
           '-- wingOf = [quest] = the wing it\'s done in; follow = [inside quest] = the quests it leads to;',
           '-- before = [quest] = done outside before going in (true), or started there ("part").',
           'ns.DungeonQuests = {']
    for area, i in sorted(inst.items(), key=lambda kv: kv[1]['levels']):
        if not (i[ALLIANCE] or i[HORDE]):
            continue
        out.append('    { id = %d, -- %s' % (area, i['name']))
        out.append('      Alliance = { %s },' % ', '.join(str(q) for q in i[ALLIANCE]))
        out.append('      Horde = { %s },' % ', '.join(str(q) for q in i[HORDE]))
        if i['wings']:
            out.append('      wingOf = { %s },' % ', '.join('[%d] = %s' % (q, lua_str(w)) for q, w in sorted(i['wings'].items())))
        before = [q for q in sorted(set(i[ALLIANCE]) | set(i[HORDE])) if q in OUTSIDE_FIRST]
        if before:
            out.append('      before = { %s },' % ', '.join('[%d] = %s' % (q, 'true' if OUTSIDE_FIRST[q] is True else '"part"')
                                                      for q in before))
        if i['follow']:
            out.append('      follow = { %s },' % ', '.join('[%d] = { %s }' % (q, ', '.join(str(f) for f in fs))
                                                      for q, fs in sorted(i['follow'].items())))
        out.append('      inside = { Alliance = { %s }, Horde = { %s } } },' % (
            ', '.join(str(q) for q in i['inside'][ALLIANCE]), ', '.join(str(q) for q in i['inside'][HORDE])))
    out.append('}')
    with open(os.path.join(GUIDES, 'Instances.lua'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(out) + '\n')


def write(data, used, guides):
    os.makedirs(GUIDES, exist_ok=True)
    lines = ['-- GENERATED by tools/FieldGuide/build_guides.py from QuestieDB (Forever) and Wowhead quest XP. Do not edit.',
             'local _, ns = ...', '',
             '-- [questID] = { name, level, required level, base XP, pick up, objectives, turn in, prerequisites }',
             '-- ia = the item that starts it (it has no pick up then: you loot the item and click it);',
             '-- dm, d = the mob that drops it out in the world and where (none: it drops inside a dungeon);',
             '-- de = that spot is a dungeon entrance (walk to the entrance and kill it there);',
             '-- a / t = { uiMapID, x, y, "who" }; o = { { uiMapID, x, y }, ... } (busiest spot first);',
             '-- pre = quests needed first (any one of them if preAny), from the same database;',
             '-- rm = the races that can take it (QuestieDB race mask; none: everyone);',
             '-- dq = a dungeon\'s quest: only the dungeon routes use it, never the leveling guide;',
             '-- talk = nothing to do but hand it in (no objectives, nowhere to explore);',
             '-- m = about how many minutes its objectives and the fights on the way take, walking aside;',
             '-- k = XP from those kills at the quest\'s level (objectives, and hostile mobs along the walk).',
             '-- ot = what to do, shortened (quest_text.py); g = the same one action at a time: l = the line, n = the name in the',
             '-- game\'s objective text, k = "use" or "keep" (shown in colour), p = where; sp = objectives far apart: one stop each.',
             'ns.Quests = {']
    everything = area_actions(data, sorted(used.items()))
    for qid in sorted(used):
        q = used[qid]
        parts = ['n = %s' % lua_str(q.name)] + (['pvp = true'] if q.pvp else []) + ['l = %d' % q.level, 'r = %d' % q.req, 'xp = %d' % q.base_xp]
        if q.giver:
            parts.append('a = { %s, %s }' % (pt(q.giver[0]), lua_str(q.giver[1])))
        if q.item:
            parts.append('ia = %s' % lua_str(q.item[1]))
            if q.drop:
                parts.append('dm = %s, d = { %s }' % (lua_str(q.drop[0]), ', '.join('{ %s }' % pt(p) for p in q.drop[1])))
                if q.drop[2]:
                    parts.append('de = true')
        parts.append('t = { %s, %s }' % (pt(q.ender[0]), lua_str(q.ender[1])))
        if q.obj:
            parts.append(action_fields(everything.get(qid))[1]
                         or 'o = { %s }' % ', '.join('{ %s }' % pt(p) for p in [q.obj[0]] + q.obj[1][:12]))
            parts.append('m = %.1f' % ((q.obj[2] * SECONDS_PER_UNIT / 60 + q.extra_minutes) * kill_seconds(q.level) / (KILL_UNITS * SECONDS_PER_UNIT)))
        elif q.extra_minutes >= 0.2:
            parts.append('m = %.1f' % (q.extra_minutes * kill_seconds(q.level) / (KILL_UNITS * SECONDS_PER_UNIT)))
        if q.kill_xp:
            parts.append('k = %d' % q.kill_xp)
        if q.text:
            parts.append('ot = %s' % lua_str(goal(q.text, q.talk)))
            parts += action_fields(everything.get(qid))[0]
        if q.talk:
            parts.append('talk = true')
        if q.races:
            parts.append('rm = %d' % q.races)
        if qid in DUNGEON_QUESTS:
            parts.append('dq = true')
        pre = q.single or q.group
        if pre:
            parts.append('pre = { %s }' % ', '.join(str(p) for p in pre))
            if q.single:
                parts.append('preAny = true')
        lines.append('    [%d] = { %s },' % (qid, ', '.join(parts)))
    lines.append('}')
    # Real walking times between zones (tools/FieldGuide/zone_walks.py).
    lines.append('')
    lines.append('-- [zone] = { [zone] = minutes on foot over the real map }: none: there\'s no way on foot.')
    lines.append('ns.ZoneWalks = {')
    try:
        with open(os.path.join(HERE, 'data', 'zone_walks.json'), encoding='utf-8') as w:
            walks = json.load(w)
    except OSError:
        walks = {}
    for a in sorted(walks, key=int):
        lines.append('    [%s] = { %s },' % (a, ', '.join('[%s] = %s' % (b, walks[a][b]) for b in sorted(walks[a], key=int))))
    lines.append('}')
    with open(os.path.join(GUIDES, 'Data.lua'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')

    for key, name, faction, sections, quests, exits in guides:
        out = ['-- GENERATED by tools/FieldGuide/build_guides.py. Do not edit.', 'local _, ns = ...', '',
               'ns.Guides[#ns.Guides + 1] = {',
               '    key = %s, name = %s, faction = %s,' % (lua_str(key), lua_str(name), lua_str(faction)),
               '    sections = {']
        def route(sim_steps, keep, grind=True):
            steps = []
            last_map = None
            for kind, qid, where, _ in sim_steps:
                if kind == 'G':
                    if grind:
                        steps.append('{ "G", %d }' % qid)
                    continue
                if qid not in keep:
                    continue
                if where.map != last_map and last_map is not None:
                    steps.append('{ "Z", %d }' % where.map)
                last_map = where.map
                steps.append('{ "%s", %d }' % (kind, qid))
            return steps

        for sid, title, zone, start_level, s, kept, dropped in sections:
            steps = route(s.steps, {q for q in kept if not quests[q].pvp})
            # Zone Clear's route: every quest of the pool, in the order the full walk took them (no
            # grinding: quests above your level wait at the end of the route instead).
            clear = route(s.full.steps, s.full.done, grind=False)
            if clear == [st for st in steps if not st.startswith('{ "G"')]:
                clear = None
            out.append('        {')
            top = max(quests[q].level for q in kept)
            out.append('            id = %s, title = %s, zone = %d, from = %d, to = %d, top = %d,' % (
                lua_str(sid), lua_str(title), zone, start_level, int(s.level_float()), top))
            out.append('            minutes = %d,%s' % (s.units * SECONDS_PER_UNIT / 60, ' start = true,' if start_level == 1 else ''))
            if dropped:
                out.append('            skipped = { %s },' % ', '.join(str(d) for d in dropped))
            if s.rest:
                out.append('            rest = { %s },' % ', '.join(str(q) for q in s.rest))
            for name, lst in (('steps', steps), ('clear', clear)):
                if lst is None:
                    continue
                out.append('            %s = {' % name)
                for i in range(0, len(lst), 6):
                    out.append('                ' + ', '.join(lst[i:i + 6]) + ',')
                out.append('            },')
            out.append('        },')
        out.append('    },')
        # Hand-offs: [zone] = { { quest, zone it takes you to }, ... }, lowest level first.
        by_from = collections.defaultdict(list)
        for qid, (a, t) in exits.items():
            by_from[a].append((quests[qid].req, qid, t))
        out.append('    exits = {')
        for a in sorted(by_from):
            out.append('        [%d] = { %s },' % (a, ', '.join('{ %d, %d }' % (qid, t) for _, qid, t in sorted(by_from[a]))))
        out.append('    },')
        out.append('}')
        with open(os.path.join(GUIDES, key + '.lua'), 'w', encoding='utf-8', newline='\n') as f:
            f.write('\n'.join(out) + '\n')


if __name__ == '__main__':
    build()
