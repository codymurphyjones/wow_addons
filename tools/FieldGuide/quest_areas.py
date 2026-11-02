"""Hunting areas: places to go for several objectives at once.

A mob or a chest has a hundred spawns, so an objective isn't a spot, it's an area. Left to itself each
objective picks its own densest spot, and the route walks to each in turn, past the same fields again and
again. Here every zone's objectives are looked at together: the spot where the most of them can be done
inside one area becomes that area, and all of them go there. The route then has one stop for the lot.

Only objectives of about one level share an area (LEVELS): you'd never be there for both otherwise. An
objective with nothing to share with keeps its own densest spot.

An objective with few spawns (a pitcher by a well, a named mob) is a place, not an area: the arrow has to
point right at it, so it keeps its own spot (FEW_SPAWNS). The route already stops for it.

assign(objectives) takes [{key, level, points}] and returns {key: (center, [points inside])}.
"""
import collections

RADIUS = 6.0       # map %: an area is about this far across each way (around 350 yd in a big zone)
LEVELS = 4         # objectives this many levels apart can share an area
FEW_SPAWNS = 5     # this many spawns or fewer: a place, not an area
MIN_SPAWNS = 3     # an objective needs this many spawns inside (or all it has) to be doable there
SHARED = 2         # objectives it takes to make an area
CANDIDATES = 300   # spots tried per zone


def centre_of(points, Point):
    x = sum(p.x for p in points) / len(points)
    y = sum(p.y for p in points) / len(points)
    return Point(points[0].map, x, y)


def assign(objectives, Point):
    by_map = collections.defaultdict(list)
    for o in objectives:
        maps = collections.Counter(p.map for p in o['points'])
        if maps:
            by_map[maps.most_common(1)[0][0]].append(o)
    out = {}
    for zone, group in by_map.items():
        for o in group:
            o['here'] = [p for p in o['points'] if p.map == zone]
        left = [o for o in group if len(o['here']) > FEW_SPAWNS]
        while len(left) >= SHARED:
            spots = [p for o in left for p in o['here'][:: max(1, len(o['here']) // 12)]]
            spots = spots[:: max(1, len(spots) // CANDIDATES)]
            best, members = None, []
            for spot in spots:
                near = []
                for o in left:
                    inside = sum(1 for p in o['here'] if p.dist(spot) <= RADIUS)
                    if inside >= min(MIN_SPAWNS, len(o['here'])):
                        near.append(o)
                # The largest set of those within LEVELS of each other.
                near.sort(key=lambda o: o['level'])
                for i in range(len(near)):
                    band = [o for o in near[i:] if o['level'] - near[i]['level'] <= LEVELS]
                    if len(band) > len(members):
                        best, members = spot, band
            if len(members) < SHARED:
                break
            inside = {o['key']: [p for p in o['here'] if p.dist(best) <= RADIUS] for o in members}
            centre = centre_of([p for pts in inside.values() for p in pts], Point)
            for o in members:
                out[o['key']] = (centre, inside[o['key']][:12])
                left.remove(o)
    return out
