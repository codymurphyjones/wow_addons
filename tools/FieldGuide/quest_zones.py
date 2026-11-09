"""Quest areas: where in each zone the questing is, and which of those places pays best for its level.

Every quest a faction can do, as the guide builder sees it (build_guides.py's Quest: its giver, its
hand-in, where its objectives are done, its XP and how long its objectives take), is put where its
work is: its objective's spot, or for a quest with nothing to do but talk, where it's handed in. In
each zone, quests whose work lies close together (AREA_RADIUS) and whose levels are near each other
(LEVEL_LINK, an area spanning at most LEVEL_SPAN) make one quest area. For each area:
  * its quests, their levels (lowest, typical, highest), their XP (the quest's own XP at its level,
    plus the fights its objectives take),
  * how long it takes: the objectives' minutes, plus a walk through every spot it needs (pick-ups,
    objectives, hand-ins) nearest-first, at running speed,
  * XP a minute, and where its quests are picked up and handed in (inside the area, or a hub outside).
Areas are then ranked per zone by their typical level, best XP a minute first among those of a
level. This is the analysis the planner will follow (see the plan): nothing here changes the guides.

    python tools/FieldGuide/quest_zones.py
Writes tools/FieldGuide/quest_zones.json (the areas) and quest_zones_report.txt (a readable list).
"""
import collections
import json
import math
import os
import statistics
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_guides as B  # noqa: E402

AREA_RADIUS = 9.0   # map units (1% of a zone's height, width counted 1.5x): about 500 yd in a big zone
MAX_SPREAD = 20.0   # map units: an area no wider than this (two area widths)
JOIN_RADIUS = 15.0
LARGE = 12          # an area with more quests than this is split in three by where their work is (Thirds)
WORTH = 1.25        # a one-quest stop keeps its place when its XP a minute is this much over its zone's typical area
LEVEL_GAP = 3       # quest levels this far apart inside one area: two areas, one a level group each (ByLevel).
                    # They may overlap on the map: each is its own area, with its own id and levels  # a lone quest (or one with nothing to do but talk) joins an area this close, of about its level
LEVEL_LINK = 2      # quests this many levels apart can be linked into one area
LEVEL_SPAN = 2      # an area's quests are at most this many levels apart: 3 levels (a quest line rarely gives more)
OUT_JSON = os.path.join(HERE, 'quest_zones.json')
OUT_REPORT = os.path.join(HERE, 'quest_zones_report.txt')


def work_spot(q):
    """Where a quest's work is: its objective's spot, else its hand-in."""
    if q.obj and q.obj[0]:
        return q.obj[0]
    return q.ender[0] if q.ender else (q.giver[0] if q.giver else None)


def minutes_of(q):
    """Its objectives' time and the fights on the way, in minutes (as the builder counts them)."""
    if q.obj:
        return q.obj[2] * B.SECONDS_PER_UNIT / 60 + q.extra_minutes
    return q.extra_minutes


def walk_minutes(points):
    """A walk through the points, nearest first from the first one, in minutes."""
    if len(points) < 2:
        return 0.0
    left = list(points[1:])
    at, units = points[0], 0.0
    while left:
        nxt = min(left, key=at.dist)
        units += at.dist(nxt)
        left.remove(nxt)
        at = nxt
    return units * B.SECONDS_PER_UNIT / 60


def cluster(quests):
    """Quests of one zone -> areas: lists of quests, linked when their work is close and their
    levels are near; an area wider than LEVEL_SPAN levels is split at its biggest level gap."""
    n = len(quests)
    parent = list(range(n))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    spots = [work_spot(q) for q in quests]
    for i in range(n):
        for j in range(i + 1, n):
            if abs(quests[i].level - quests[j].level) <= LEVEL_LINK and spots[i].dist(spots[j]) <= AREA_RADIUS:
                parent[find(i)] = find(j)
    groups = collections.defaultdict(list)
    for i in range(n):
        groups[find(i)].append(quests[i])
    out = []
    pending = list(groups.values())
    while pending:
        g = pending.pop()
        g.sort(key=lambda q: q.level)
        if g[-1].level - g[0].level > LEVEL_SPAN:
            gaps = [(g[k + 1].level - g[k].level, k) for k in range(len(g) - 1)]
            _, k = max(gaps)
            pending += [g[:k + 1], g[k + 1:]]
            continue
        # Linked in a chain round a hub, an area can stretch across a zone: one wider than
        # MAX_SPREAD is split by its two farthest quests (each takes those nearer to it).
        if len(g) > 2:
            pairs = [(work_spot(a).dist(work_spot(b)), a, b) for i, a in enumerate(g) for b in g[i + 1:]]
            far, a, b = max(pairs, key=lambda t: t[0])
            if far > MAX_SPREAD:
                sa, sb = work_spot(a), work_spot(b)
                left = [q for q in g if work_spot(q).dist(sa) <= work_spot(q).dist(sb)]
                right = [q for q in g if q not in left]
                pending += [left, right]
                continue
        out.append(g)
    return out


def tidy(areas):
    """A lone quest joins the nearest area of about its level within JOIN_RADIUS, when there is one."""
    big = [a for a in areas if len(a) > 1]
    out = [list(a) for a in big]
    for a in areas:
        if len(a) > 1:
            continue
        q = a[0]
        spot = work_spot(q)
        best, bd = None, None
        for g in out:
            lv = [x.level for x in g]
            if min(lv) - LEVEL_LINK <= q.level <= max(lv) + LEVEL_LINK:
                d = min(spot.dist(work_spot(x)) for x in g)
                if d <= JOIN_RADIUS and (bd is None or d < bd):
                    best, bd = g, d
        if best is not None:
            best.append(q)
        else:
            out.append([q])
    return out


def thirds(area):
    """A large area as three by place: k-means on its quests' work spots, started from three far-apart
    quests (the first, the one farthest from it, the one farthest from both). Empty parts are dropped."""
    spots = {id(q): work_spot(q) for q in area}
    a = area[0]
    b = max(area, key=lambda q: spots[id(q)].dist(spots[id(a)]))
    c = max(area, key=lambda q: min(spots[id(q)].dist(spots[id(a)]), spots[id(q)].dist(spots[id(b)])))
    centres = [(spots[id(x)].x, spots[id(x)].y) for x in (a, b, c)]
    zone = spots[id(a)].map
    parts = [area]
    for _ in range(12):
        parts = [[], [], []]
        for q in area:
            p = spots[id(q)]
            k = min(range(3), key=lambda i: B.Point(zone, *centres[i]).dist(p))
            parts[k].append(q)
        new = [(statistics.mean(spots[id(q)].x for q in g), statistics.mean(spots[id(q)].y for q in g)) if g else centres[i]
               for i, g in enumerate(parts)]
        if new == centres:
            break
        centres = new
    return [g for g in parts if g]


def by_level(area):
    """An area whose quests fall into level groups LEVEL_GAP or more apart, or that spans more than
    LEVEL_SPAN levels, as one area a group (cut at the biggest gap, again until neither is true). The
    parts overlap on the map; they're kept apart."""
    area = sorted(area, key=lambda q: q.level)
    if len(area) < 2:
        return [area]
    gap, k = max((area[i + 1].level - area[i].level, i) for i in range(len(area) - 1))
    # (Or spread across more than LEVEL_SPAN levels in small steps: cut at its biggest step all the same.)
    if gap < LEVEL_GAP and area[-1].level - area[0].level <= LEVEL_SPAN:
        return [area]
    return by_level(area[:k + 1]) + by_level(area[k + 1:])


def describe(area, names):
    levels = [q.level for q in area]
    xp = sum(q.base_xp + q.kill_xp for q in area)
    work = [work_spot(q) for q in area]
    givers = [q.giver[0] for q in area if q.giver]
    enders = [q.ender[0] for q in area if q.ender]
    centre = B.Point(work[0].map, statistics.mean(p.x for p in work), statistics.mean(p.y for p in work))
    inside = lambda p: p is not None and p.map == centre.map and p.dist(centre) <= AREA_RADIUS * 1.5  # noqa: E731
    objective_minutes = sum(minutes_of(q) for q in area)
    walk = walk_minutes(givers + work + enders)
    minutes = max(1.0, objective_minutes + walk)
    hubs = collections.Counter()
    for q in area:
        if q.giver and not inside(q.giver[0]):
            hubs[q.giver[1]] += 1
    chained = sum(1 for q in area if any(p in {x.id for x in area} for p in q.single + q.group))
    reqs = [q.req for q in area]
    return {
        # Required: you can pick up every quest of it. Preferred: its quests are at your level (full
        # XP, mobs your level).
        'required': max(reqs), 'preferred': int(round(statistics.median(levels))),
        'zone': centre.map, 'zoneName': names.get(centre.map, str(centre.map)),
        'centre': [centre.map, round(centre.x, 1), round(centre.y, 1)],
        'levels': [min(levels), int(statistics.median(levels)), max(levels)],
        'quests': [{'id': q.id, 'name': q.name, 'level': q.level, 'xp': q.base_xp + q.kill_xp,
                    'minutes': round(minutes_of(q), 1)} for q in sorted(area, key=lambda q: (q.level, q.name))],
        'xp': xp, 'minutes': round(minutes, 1), 'walkMinutes': round(walk, 1),
        'xpPerMinute': round(xp / minutes),
        'pickupsInside': sum(1 for q in area if q.giver and inside(q.giver[0])),
        'handInsInside': sum(1 for q in area if q.ender and inside(q.ender[0])),
        'hubs': [h for h, _ in hubs.most_common(3)],
        'chained': chained,
    }


def analyse():
    data = B.Data()
    names = B.zone_names(data.zones)
    result = {}
    lines = []
    for faction in (B.ALLIANCE, B.HORDE):
        quests = B.candidates(data, B.FACTION_MASK[faction], None)
        B.place_objectives(quests.values())
        # Quests another quest needs first: a one-quest stop for one of these is never left for later.
        needed = set()
        for q in quests.values():
            needed.update(q.single + q.group)
        by_zone = collections.defaultdict(list)
        talk = collections.defaultdict(list)  # nothing to do but talk: they join an area, never make one
        for q in quests.values():
            spot = work_spot(q)
            if spot is None or not (q.giver and q.ender):
                continue
            if q.obj and q.obj[0]:
                by_zone[spot.map].append(q)
            else:
                talk[spot.map].append(q)
        zones = []
        for zone, qs in by_zone.items():
            # (Capitals: their quests are errands to people in town, not a place to quest.)
            if zone not in names or zone in B.CAPITALS or len(qs) < 3:
                continue
            groups = tidy(cluster(qs))
            for q in talk.get(zone, []):
                spot = work_spot(q)
                near = [g for g in groups if min(spot.dist(work_spot(x)) for x in g) <= JOIN_RADIUS
                        and min(x.level for x in g) - LEVEL_LINK <= q.level <= max(x.level for x in g) + LEVEL_LINK]
                if near:
                    min(near, key=lambda g: min(spot.dist(work_spot(x)) for x in g)).append(q)
            # (Split last, once every quest has joined its area.)
            split = []
            for g in groups:
                for part in (thirds(g) if len(g) > LARGE else [g]):
                    split += by_level(part)
            areas = [describe(a, names) for a in split]
            # Ranked by typical level, then XP a minute (best first).
            # One-quest stops come after the areas of their level, unless they're worth it on their own:
            # a quest other quests need first (a prerequisite), or XP a minute well over the zone's
            # typical area (WORTH). Whether one is needed to reach a level is the planner's call (it
            # depends on where you are): this only orders them.
            rates = sorted(a['xpPerMinute'] for a in areas if len(a['quests']) > 1) or [0]
            typical = rates[len(rates) // 2]
            for a in areas:
                a['lone'] = len(a['quests']) == 1
                reason = None
                if a['lone']:
                    qid = a['quests'][0]['id']
                    if qid in needed:
                        reason = 'prerequisite'
                    elif typical and a['xpPerMinute'] >= typical * WORTH:
                        reason = 'worth the time'
                a['keep'] = reason
                a['demoted'] = a['lone'] and reason is None
            areas.sort(key=lambda a: (a['preferred'], a['demoted'], -a['xpPerMinute']))
            for i, a in enumerate(areas, 1):
                a['rank'] = i
                a['id'] = '%s-%d-%d' % (faction[0].lower(), zone, i)
            # Areas sharing ground with another (a level group of the same place): named, so the planner
            # and the page know they're different areas over one spot.
            for a in areas:
                ca = B.Point(zone, a['centre'][1], a['centre'][2])
                a['overlaps'] = [b['rank'] for b in areas if b is not a
                                 and ca.dist(B.Point(zone, b['centre'][1], b['centre'][2])) <= AREA_RADIUS]
            zones.append({'zone': zone, 'name': names[zone], 'levels': [min(a['levels'][0] for a in areas),
                                                                          max(a['levels'][2] for a in areas)],
                          # The zone's own: the level its areas start being takeable, and the level most of
                          # its quest XP is at (its areas' preferred levels, weighted by their XP).
                          'required': min(a['required'] for a in areas),
                          'preferred': int(round(sum(a['preferred'] * a['xp'] for a in areas) / max(1, sum(a['xp'] for a in areas)))),
                          'areas': areas})
        zones.sort(key=lambda z: (z['levels'][0], z['name']))
        result[faction] = zones
        lines.append('== %s: %d zones, %d areas' % (faction, len(zones), sum(len(z['areas']) for z in zones)))
        for z in zones:
            lines.append('  %s (levels %d-%d, required %d, preferred %d): %d areas' % (z['name'], z['levels'][0], z['levels'][1],
                                                                                z['required'], z['preferred'], len(z['areas'])))
            for a in z['areas']:
                lv = a['levels']
                lines.append('    %2d. %4.1f,%4.1f  lv %2d-%2d req %2d pref %2d  %2d quests  %6d XP  %5.1f min  %4d XP/min  '
                             'pick-ups here %d/%d%s%s' % (a['rank'], a['centre'][1], a['centre'][2], lv[0], lv[2], a['required'], a['preferred'],
                                                       len(a['quests']), a['xp'], a['minutes'], a['xpPerMinute'],
                                                       a['pickupsInside'], len(a['quests']),
                                                       (('  overlaps ' + ','.join(map(str, a['overlaps']))) if a['overlaps'] else '')
                                                       + ('  [one quest: %s]' % (a['keep'] or 'later')) if a['lone'] else
                                                       (('  overlaps ' + ','.join(map(str, a['overlaps']))) if a['overlaps'] else ''),
                                                       ('  from: ' + ', '.join(a['hubs'])) if a['hubs'] else ''))
        lines.append('')
    with open(OUT_JSON, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(result, f, indent=1)
    with open(OUT_REPORT, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')
    for faction, zones in result.items():
        print('%s: %d zones, %d areas' % (faction, len(zones), sum(len(z['areas']) for z in zones)))
    print('wrote', OUT_JSON, 'and', OUT_REPORT)


if __name__ == '__main__':
    analyse()
