"""Puts every section's steps in the best order a long search can find, on real walks.

build_guides.py walks each section nearest step first, on straight lines: quick, and a start. A plan
in the game has a moment and small moves. This one has minutes, so it searches properly: simulated
annealing, which can take a worse order on the way to a better one, moving steps, runs of steps and
whole quests. The measure is the game's (Engine.lua's StepWeight and Delay: how long XP waits, by the
yards walked to it), on the same walks (quest_walks.py). A quest's steps stay in order, a quest comes
after what it needs, and a quest above the level the route has reached by then counts against it.

It starts from the order there is and keeps a new one only when it scores better, so a section can't
get worse, and running it again goes on from there. Zone changes stay where they are: each stretch
between them is ordered by itself.

Rewrites steps and clear in addons/FieldGuide/Guides/{Horde,Alliance}.lua. Report: optimize_report.txt.

    python -I tools/FieldGuide/optimize_guides.py        (after build_guides.py and quest_walks.py)
"""
import math
import os
import re
import site
import sys

sys.path.append(site.getusersitepackages())

import lupa.lua51 as L  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import zone_walks as Z  # noqa: E402

GUIDES = os.path.join(Z.ROOT, "addons", "FieldGuide", "Guides")
REPORT = os.path.join(HERE, "optimize_report.txt")
ITERATIONS = 120000
PENALTY = 1e12 # as in the search: one step out of order, or above the level reached
XP_TO_LEVEL = [400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400,
               16000, 17700, 19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300,
               47400, 50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700, 95800, 101000, 106300,
               111800, 117500, 123200, 129100, 135100, 141200, 147500, 153900, 160400, 167100, 173900, 180800,
               187900, 195000, 202300, 209800, 217400]
STRETCH = 3    # Engine.lua: a quest waits until you're within this many levels of it
GRIND_GAP = 1  # Engine.lua: the levels a route can gain on its way, between quests
DEATH_RISK = 0.25  # Engine.lua: expected deaths, a level above you squared

SEARCH = r'''
local rng = 0
local function Rand(n)  -- the same order every build
    rng = (rng * 1103515245 + 12345) % 2147483648
    return math.floor(rng / 2147483648 * n)
end
local XP_TO_LEVEL = { 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400,
    16000, 17700, 19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400,
    50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700, 95800, 101000, 106300, 111800,
    117500, 123200, 129100, 135100, 141200, 147500, 153900, 160400, 167100, 173900, 180800, 187900, 195000,
    202300, 209800, 217400 }
return function(n, dist, first, weight, gain, need, startLevel, startXp, quest, pred, fixed, iterations)
    local PENALTY = 1e12
    local pos = {}
    local function Cost(order)
        for i = 1, n do pos[order[i]] = i end
        local total, yards, at = 0, 0, nil
        local reached, xp = startLevel, startXp
        for i = 1, n do
            local j = order[i]
            yards = yards + (at and dist[at][j] or first[j])
            at = j
            total = total + yards * weight[j]
            if need[j] > reached + 1 then total = total + PENALTY end
            for _, p in ipairs(pred[j]) do
                if pos[p] > i then total = total + PENALTY end
            end
            xp = xp + gain[j]
            while reached < 60 and xp >= XP_TO_LEVEL[reached] do
                xp = xp - XP_TO_LEVEL[reached]
                reached = reached + 1
            end
        end
        return total
    end
    local seq = {}
    for i = 1, n do seq[i] = i end
    local cost = Cost(seq)
    local start = cost
    local best, bestCost = { unpack(seq) }, cost
    local low = fixed and 2 or 1
    if n - low < 2 then return best, bestCost, start end
    local hot = (cost % PENALTY) * 0.02 -- (of the walking, not the penalties, or it never settles)
    local members = {}
    for j = 1, n do
        members[quest[j]] = members[quest[j]] or {}
        table.insert(members[quest[j]], j)
    end
    local ids = {}
    for id in pairs(members) do ids[#ids + 1] = id end
    table.sort(ids)
    local inBlock, order, rest = {}, {}, {}
    for it = 1, iterations do
        local temperature = hot * (1 - it / iterations) ^ 2
        for j = 1, n do inBlock[j] = false end
        local part = {}
        local kind = Rand(3)
        if kind == 0 then
            for _, j in ipairs(members[ids[Rand(#ids) + 1]]) do
                if pos[j] and j ~= (fixed and seq[1] or 0) then inBlock[j] = true end
            end
        else
            local len = kind == 1 and 1 or (2 + Rand(4))
            local from = low + Rand(n - low + 1)
            for i = from, math.min(n, from + len - 1) do inBlock[seq[i]] = true end
        end
        local r = 0
        for i = 1, n do
            local j = seq[i]
            if inBlock[j] then part[#part + 1] = j else r = r + 1; rest[r] = j end
        end
        if #part > 0 then
            local at = low + Rand(r - low + 2)
            local o = 0
            for i = 1, at - 1 do o = o + 1; order[o] = rest[i] end
            for i = 1, #part do o = o + 1; order[o] = part[i] end
            for i = at, r do o = o + 1; order[o] = rest[i] end
            local c = Cost(order)
            local delta = c - cost
            if delta < 0 or (temperature > 0 and Rand(1000000) / 1000000 < math.exp(-delta / temperature)) then
                seq, order = order, seq
                cost = c
                if cost < bestCost then
                    bestCost = cost
                    for i = 1, n do best[i] = seq[i] end
                end
            end
        end
    end
    return best, bestCost, start
end
'''


def load_quests(lua):
    lua.execute("ns = { Guides = {} }")
    run = lua.eval("function(s) local f,e=loadstring(s); if not f then error(e) end; f('FieldGuide',ns) end")
    run(open(os.path.join(GUIDES, "Data.lua"), encoding="utf-8").read())
    run(open(os.path.join(GUIDES, "Walks.lua"), encoding="utf-8").read())
    return lua.globals().ns


def quest_xp(base, qlevel, level):
    """As Engine.lua's QuestXP."""
    mult = min(10, max(1, 2 * (qlevel - level) + 20))
    xp = base * mult / 10
    if xp <= 100:
        return 5 * math.floor((xp + 2) / 5)
    if xp <= 500:
        return 10 * math.floor((xp + 5) / 10)
    if xp <= 1000:
        return 25 * math.floor((xp + 12) / 25)
    return 50 * math.floor((xp + 25) / 50)


class Places:
    def __init__(self, ns, assign):
        self.ns, self.assign, self.memo = ns, assign, {}

    def world(self, p):
        key = (p[1], p[2], p[3])
        if key not in self.memo:
            self.memo[key] = Z.C.world(self.assign, int(p[1]), p[2] / 100, p[3] / 100)
        return self.memo[key]

    def walk(self, a, b):
        straight = math.hypot(a[1] - b[1], a[2] - b[2])
        map_ = self.ns.QuestWalks[a[0]]
        if a[0] != b[0] or map_ is None:
            return straight if a[0] == b[0] else 100000
        cell, top = map_.cell, map_.max
        row = map_.rows[int((top - a[1]) // cell) * 1024 + int((top - a[2]) // cell)]
        real = row and row[int((top - b[1]) // cell) * 1024 + int((top - b[2]) // cell)]
        return max(real, straight) if real else straight


def earned(q, level):
    """What a quest brings in: as Engine.lua's QuestEarns."""
    xp = quest_xp(q.xp or 0, q.l or level, level)
    return xp + ((q.k or 0) * min(1, xp / q.xp) if q.xp else 0)


def level_up(level, xp, gain):
    xp += gain
    while level < 60 and xp >= XP_TO_LEVEL[level - 1]:
        xp -= XP_TO_LEVEL[level - 1]
        level += 1
    return level, xp


def order_run(lua, search, places, quests, run, level, xp_now, top):
    """The best order of a stretch of steps: (new steps, score before, score after). It starts from the
    level and XP the stretches before it reached. top: the level all the route's XP gets to; a quest
    needing more than that waits for XP from elsewhere, and no order changes that."""
    rows, spots = [], []
    for kind, qid in run:
        q = quests[qid]
        p = q and ((q.a if kind == "A" else q.t) if kind != "O" else (q.o[1] if q.o else None))
        w = p and places.world(p)
        if not w:
            return run, 0, 0  # somewhere it can't place: left as it is
        rows.append((kind, qid, q))
        spots.append(w)
    n = len(rows)
    if n < 3:
        return run, 0, 0
    dist = lua.table_from([lua.table_from([places.walk(a, b) for b in spots]) for a in spots])
    first = lua.table_from([0.0] + [places.walk(spots[0], b) for b in spots[1:]])
    weight, gain, need, quest, pred = [], [], [], [], []
    index = {(k, i): j + 1 for j, (k, i, _) in enumerate(rows)}
    for kind, qid, q in rows:
        xp = quest_xp(q.xp or 0, q.l or level, level)
        # (As Engine.lua's ExpectedDeaths.)
        over = (q.l or level) - level
        deaths = DEATH_RISK * over * over if over > 0 and q.o else 0
        weight.append(1 + xp / (1 + deaths) * (0.5 if kind == "T" else 0.25))
        # (As Engine.lua's QuestEarns: what it pays, and the kills that go with it.)
        kills = (q.k or 0) * min(1, xp / q.xp) if q.xp else 0
        gain.append(xp + kills if kind == "T" else 0)
        wanted = max(q.r or 1, (q.l or 1) - STRETCH)
        need.append(wanted if kind == "A" and wanted <= top + GRIND_GAP else 0)
        quest.append(qid)
        before = []
        if kind == "O" and ("A", qid) in index:
            before.append(index[("A", qid)])
        if kind == "T":
            before += [index[(k, qid)] for k in ("A", "O") if (k, qid) in index]
        if kind == "A":
            pres = list(q.pre.values()) if q.pre else []
            if q.preAny:
                pres = []  # (any one of them: left to the game)
            before += [index[("T", p)] for p in pres if ("T", p) in index]
        pred.append(lua.table_from(before))
    best, after, start = search(n, dist, first, lua.table_from(weight), lua.table_from(gain), lua.table_from(need),
                                level, xp_now, lua.table_from(quest), lua.table_from(pred), True, ITERATIONS)
    if after >= start:
        return run, start, start
    return [(rows[best[i + 1] - 1][0], rows[best[i + 1] - 1][1]) for i in range(n)], start, after


def format_steps(steps, indent="                "):
    cells = ['{ "%s", %s }' % s for s in steps]
    return "\n".join(indent + ", ".join(cells[i:i + 6]) + "," for i in range(0, len(cells), 6))


def optimize_list(lua, search, places, quests, body, level):
    steps = [(k, int(v)) for k, v in re.findall(r'\{ "([AOTZ])", (\d+)', body)]
    out, run, before, after = [], [], 0, 0
    # The level all of the route's XP reaches, and what each stretch starts from.
    top, spare = level, 0
    for kind, qid in steps:
        if kind == "T" and quests[qid]:
            top, spare = level_up(top, spare, earned(quests[qid], level))
    now, xp_now = level, 0
    for s in steps + [("Z", 0)]:
        if s[0] == "Z":
            new, b, a = order_run(lua, search, places, quests, run, now, xp_now, top)
            out += new
            before, after = before + b, after + a
            for kind, qid in run:
                if kind == "T" and quests[qid]:
                    now, xp_now = level_up(now, xp_now, earned(quests[qid], level))
            run = []
            if s[1]:
                out.append(s)
        else:
            run.append(s)
    return out, before, after


def main():
    lua = L.LuaRuntime(encoding="utf8", unpack_returned_tuples=True)
    search = lua.execute(SEARCH)
    ns = load_quests(lua)
    places = Places(ns, Z.assignments())
    quests = ns.Quests
    report = []
    # (A list can be empty: a section that's only for Zone Clear has no steps.)
    pattern = re.compile(r'(?P<head>(?:steps|clear) = \{\n)(?P<body>.*?)(?P<tail>^            \},)', re.S | re.M)
    for name in ("Horde", "Alliance"):
        path = os.path.join(GUIDES, name + ".lua")
        text = open(path, encoding="utf-8").read()
        title = {"text": "?", "level": 1}

        def replace(m):
            head = text.rfind('title = "', 0, m.start())
            found = re.match(r'title = "([^"]+)", zone = \d+, from = (\d+)', text[head:])
            label, level = (found.group(1), int(found.group(2))) if found else ("?", 1)
            new, before, after = optimize_list(lua, search, places, quests, m.group("body"), level)
            if before:
                broke, was = divmod(before, PENALTY)
                now_broke, now = divmod(after, PENALTY)
                line = "%-8s %-28s %-5s delay %13.0f -> %13.0f  %+6.1f%%   out of order %2d -> %2d" % (
                    name, label, m.group("head").split()[0], was, now, (now - was) / was * 100 if was else 0.0, broke, now_broke)
                report.append(line)
                print(line, flush=True)
            return m.group("head") + (format_steps(new) + "\n" if new else "") + m.group("tail")

        new_text = pattern.sub(replace, text)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(new_text)
    with open(REPORT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(report) + "\n")


if __name__ == "__main__":
    main()
