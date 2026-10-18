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
import json
import math
import os
import re

import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # sibling modules, also under python -I
from questiedb import DEFAULT_TOC, QuestieDB, lua_list
from instances import FINAL_BOSSES, INSTANCE_MAPS, LEVELS, OUTSIDE_FIRST, WINGS, dungeon_areas, dungeon_entrances, dungeon_of, load_dungeons
from zones import Zones

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.join(os.path.dirname(os.path.dirname(HERE)), "addons", "FieldGuide")  # tools/FieldGuide/ builds addons/FieldGuide/
GUIDES = os.path.join(ADDON, 'Guides')
REPORT = os.path.join(HERE, 'guides_report.txt')
XP_JSON = os.path.join(HERE, 'data', 'wowhead_quests.json')

# XP to go from level i to i + 1 (Classic).
XP_TO_LEVEL = [0, 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400,
               16000, 17700, 19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400,
               44300, 47400, 50800, 54500, 58600, 62800, 67100, 71600, 76100, 80900, 85700, 90700, 95800,
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
KEEP_EFFICIENCY = 0.3  # quests paying under this share of the section's typical XP/minute are dropped
LOG_SIZE = 20
MAX_GRIND_LEVELS = 2   # grind at most this many levels to reach the next quests

REPEATABLE = 1  # specialFlags

QUESTIE = os.path.join(os.path.dirname(os.path.dirname(os.environ.get('QUESTIEDB_TOC') or DEFAULT_TOC)), 'Questie')


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
                    if hostile(npc):
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
        if not points:
            return INSTANCE
        if prefer and any(p.map == prefer for p in points):
            points = [p for p in points if p.map == prefer]
        # The busiest spot: the spawn with the most others nearby, and those around it.
        best, best_n = points[0], -1
        for p in points if len(points) <= 400 else points[::len(points) // 400 + 1]:
            n = sum(1 for o in points if p.dist(o) <= CLUSTER_RADIUS)
            if n > best_n:
                best, best_n = p, n
        near = sorted((o for o in points if best.dist(o) <= CLUSTER_RADIUS * 1.5), key=best.dist)[:24]
        cx = sum(o.x for o in near) / len(near)
        cy = sum(o.y for o in near) / len(near)
        center = Point(best.map, cx, cy)
        mob_level = sum(levels) / len(levels) if levels else None
        return center, near, effort, mob_level


INSTANCE = 'instance'


class Quest:
    """One quest as the planner sees it, for one race and set of zones."""

    def __init__(self, data, qid, maps):
        q = data.quests[qid]
        self.id, self.row = qid, q
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
        self.cost = collections.Counter()    # qid -> units spent on it

    def add_xp(self, xp):
        self.xp += xp
        while self.level < MAX_LEVEL and self.xp >= XP_TO_LEVEL[self.level]:
            self.xp -= XP_TO_LEVEL[self.level]
            self.level += 1

    def level_float(self):
        return self.level + (self.xp / XP_TO_LEVEL[self.level] if self.level < MAX_LEVEL else 0)


def available(q, sim, quests, known_done):
    if q.req > sim.level:
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
            if qid in sim.active:
                if not sim.active[qid] and q.obj:
                    d = sim.pos.dist(q.obj[0]) if sim.pos else 0
                    cand = (d + q.obj[2] * 0.15, 2, 'O', q, q.obj[0], d + q.obj[2])
                else:
                    d = sim.pos.dist(q.ender[0]) if sim.pos else 0
                    cand = (d, 0, 'T', q, q.ender[0], d)
            elif taking and available(q, sim, quests, known_done):
                d = sim.pos.dist(q.giver[0]) if sim.pos else 0
                cand = (d, 1, 'A', q, q.giver[0], d)
            else:
                continue
            if best is None or cand[:2] < best[:2]:
                best = cand
        if best is None:
            # Stuck below the next quests' level: grind to it where you stand, if it's close.
            gate = min((quests[qid].req for qid in chosen if taking is not False and new_quests
                        and qid not in sim.done and qid not in sim.active
                        and quests[qid].req > sim.level and available_ignoring_level(quests[qid], sim, known_done)),
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
                gained = int(kills * kill_xp(round(q.obj[3]), sim.level))
                sim.add_xp(gained)
                sim.gained[q.id] += gained
        else:
            del sim.active[q.id]
            sim.done.add(q.id)
            gained = quest_xp(q.base_xp, q.level, sim.level)
            sim.add_xp(gained)
            sim.gained[q.id] += gained
        sim.steps.append((kind, q.id, where, units))


def needed_by(quests, chosen):
    """Quests that a chosen quest needs first."""
    need = set()
    for qid in chosen:
        q = quests[qid]
        need.update(p for p in q.single + q.group if p in quests)
    return need


def plan_zone(quests, pool, sim, target, known_done, grind=True):
    """Plans one zone from sim's state: (kept quest ids, dropped quest ids, finished Sim).

    Starts from every quest in the pool, then drops the ones paying well under the route's
    typical XP per unit of time, as long as that makes the whole route pay better."""
    import copy

    def trial(chosen):
        t = run(quests, chosen, copy.deepcopy(sim), target, known_done, grind=grind)
        return run(quests, set(t.active), t, None, known_done, new_quests=False, grind=grind)

    def rate(t):
        start = sim.level + sim.xp / XP_TO_LEVEL[sim.level]
        return (t.level_float() - start) / max(1.0, t.units)

    chosen = set(pool)
    best = trial(chosen)
    chosen = {qid for qid in chosen if qid in best.done}
    dropped = set()
    for _ in range(4):
        rates = {qid: best.gained[qid] / max(1.0, best.cost[qid]) for qid in chosen}
        if not rates:
            break
        typical = sorted(rates.values())[len(rates) // 2]
        needed = needed_by(quests, chosen)
        low = {qid for qid, r in rates.items() if r < typical * KEEP_EFFICIENCY and qid not in needed}
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
    return kept, sorted(dropped), best


# --- writing the guides -----------------------------------------------------------------------

def lua_str(s):
    s = (s or '').replace('\\', '\\\\').replace('"', '\\"').replace('\n', ' ').replace('\r', '')
    return '"' + s + '"'


def pt(p):
    return '%d, %.1f, %.1f' % (p.map, p.x, p.y)


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
    the two. A chain in the giver's zone that needs one keeps it as an ordinary quest there.
    Returns {qid: (from zone, to zone)}."""
    needed_here = set()
    for q in quests.values():
        for p in q.single + q.group:
            if p in quests and quests[p].giver[0].map == q.giver[0].map:
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
            if zone in HOME_ZONES[faction] and min(quests[q].req for q in pool) <= 2:
                start_level, known = 1, frozenset()
            else:
                reqs = sorted(quests[q].req for q in pool)
                start_level = max(1, reqs[len(reqs) * 15 // 100])
                # Quests in other zones count as done: the addon sends you back for any a
                # quest here needs that you missed.
                known = frozenset(q for q, x in quests.items() if x.giver[0].map != zone)
            home = start_level == 1
            kept, dropped, sim = plan_zone(quests, pool, Sim(start_level, 0, known), None, known, grind=home)
            if len(kept) < MIN_ZONE_QUESTS // 2:
                continue
            sections.append(('%s-%d-%d' % (faction.lower(), zone, start_level), names[zone], zone, start_level, sim, kept, dropped))
        sections.sort(key=lambda sec: (sec[3], sec[1]))
        # A zone you leave for a while and come back to has several sections: name each by the
        # level it starts at ("Ashenvale 15", "Ashenvale 22").
        per_zone = collections.Counter(sec[2] for sec in sections)
        sections = [(sid, '%s %d' % (title, start) if per_zone[zone] > 1 else title, zone, start, sim, kept, dropped)
                    for sid, title, zone, start, sim, kept, dropped in sections]
        guided = {sec[2] for sec in sections}
        exits = {qid: e for qid, e in exits.items() if e[0] in guided and e[1] in guided}
        guides.append((faction, faction, faction, sections, quests, exits))
        for sec in sections:
            for qid in sec[5]:
                used[qid] = quests[qid]
                add_prerequisites(data, quests[qid], used)
        for qid in exits:
            used[qid] = quests[qid]
            add_prerequisites(data, quests[qid], used)

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
    os.makedirs(GUIDES, exist_ok=True)
    out = ['-- GENERATED by tools/FieldGuide/build_guides.py from QuestieDB (Forever). Do not edit.',
           'local _, ns = ...', '',
           '-- Dungeons for the instance priority: recommended levels, entrance { uiMapID, x, y },',
           '-- the quests each faction can pick up for it beforehand, and (inside) the ones that start',
           '-- from an item you loot in there (all in Guides\Data.lua). map = the game\'s instance map ID;',
           '-- wings = the separately entered wings, in route order (entrance, final bosses, size);',
           '-- wingOf = [quest] = the wing it\'s done in; follow = [inside quest] = the quests it leads to;',
           '-- before = [quest] = done outside before going in (true), or started there ("part").',
           'ns.Instances = {']
    for area, i in sorted(inst.items(), key=lambda kv: kv[1]['levels']):
        if not (i[ALLIANCE] or i[HORDE]):
            continue
        e = i['entrance']
        out.append('    { id = %d, name = %s, from = %d, to = %d,%s' % (
            area, lua_str(i['name']), i['levels'][0], i['levels'][1],
            (' entrance = { %d, %.1f, %.1f },' % e) if e else ''))
        out.append('      Alliance = { %s },' % ', '.join(str(q) for q in i[ALLIANCE]))
        out.append('      Horde = { %s },' % ', '.join(str(q) for q in i[HORDE]))
        out.append('      map = %d,' % INSTANCE_MAPS.get(area, 0))
        out.append('      bosses = { %s },' % ', '.join(lua_str(b) for b in FINAL_BOSSES.get(area, [])))
        if area in WINGS:
            out.append('      wings = {')
            for w in WINGS[area]:
                out.append('          { key = %s, name = %s, entrance = { %d, %.1f, %.1f }, bosses = { %s }%s },' % (
                    lua_str(w['key']), lua_str(w['name']), *w['entrance'],
                    ', '.join(lua_str(b) for b in w['bosses']), (', size = %d' % w['size']) if w.get('size') else ''))
            out.append('      },')
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
             '-- dq = a dungeon\'s quest: only the dungeon routes use it, never the leveling guide.',
             'ns.Quests = {']
    for qid in sorted(used):
        q = used[qid]
        parts = ['n = %s' % lua_str(q.name), 'l = %d' % q.level, 'r = %d' % q.req, 'xp = %d' % q.base_xp]
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
            parts.append('o = { %s }' % ', '.join('{ %s }' % pt(p) for p in [q.obj[0]] + q.obj[1][:12]))
        if q.text:
            parts.append('ot = %s' % lua_str(q.text[:160]))
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
    with open(os.path.join(GUIDES, 'Data.lua'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')

    for key, name, faction, sections, quests, exits in guides:
        out = ['-- GENERATED by tools/FieldGuide/build_guides.py. Do not edit.', 'local _, ns = ...', '',
               'ns.Guides[#ns.Guides + 1] = {',
               '    key = %s, name = %s, faction = %s,' % (lua_str(key), lua_str(name), lua_str(faction)),
               '    sections = {']
        for sid, title, zone, start_level, s, kept, dropped in sections:
            steps = []
            last_map = None
            for kind, qid, where, _ in s.steps:
                if kind == 'G':
                    steps.append('{ "G", %d }' % qid)
                    continue
                if qid not in kept:
                    continue
                if where.map != last_map and last_map is not None:
                    steps.append('{ "Z", %d }' % where.map)
                last_map = where.map
                steps.append('{ "%s", %d }' % (kind, qid))
            out.append('        {')
            top = max(quests[q].level for q in kept)
            out.append('            id = %s, title = %s, zone = %d, from = %d, to = %d, top = %d,' % (
                lua_str(sid), lua_str(title), zone, start_level, int(s.level_float()), top))
            out.append('            minutes = %d,%s' % (s.units * SECONDS_PER_UNIT / 60, ' start = true,' if start_level == 1 else ''))
            if dropped:
                out.append('            skipped = { %s },' % ', '.join(str(d) for d in dropped))
            out.append('            steps = {')
            for i in range(0, len(steps), 6):
                out.append('                ' + ', '.join(steps[i:i + 6]) + ',')
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
