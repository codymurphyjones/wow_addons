local _, ns = ...

-- The leveling planner: work, wherever it is. Every pick-up, every objective stop and every hand-in
-- is a task of its own (a quest whose objectives are in different places has one stop each, done in
-- any order: Engine.lua's SplitParts), and zones don't matter: what's chosen is the task areas
-- (Guides\Areas.lua, tools/FieldGuide/task_areas.py: clusters of objective spots in world yards,
-- across zone borders) that pay the most XP a minute from where you are, travel included, until the
-- plan holds LOOKAHEAD quests. The quests in your log are always in it. The engine then puts their
-- tasks in the quickest order (Engine.lua's planner), and the "go to ..." steps come from that order.
--
-- A quest's only promise: all of it done and handed in while it still pays (Engine.lua's Worth, a
-- share of your level). lastLevel is the last level it does; one within a level or two of it weighs
-- more in the order (Urgency) and in choosing its area, so it's done in time.
--
-- Zone Clear, a section you picked yourself and dungeon routes keep the zone sections (Section returns
-- nil and Engine.lua's PickSection decides). Leveling never does: "stay in this zone" only narrows the
-- areas to that zone's, and with nothing you can act on now the plan starts by levelling where its work
-- is (a "reach level N" step), never a zone section.
local T = {}
ns.Tasks = T

local LOOKAHEAD = 30   -- quests in a plan
local KEEP_SHARE = 0.35 -- an area joins the plan only when it pays at least this share of the best one's rate
local LEVEL_ABOVE = 3  -- areas whose quests start up to this many levels over yours are looked at
local REFILL = 10      -- the plan is chosen again when fewer than this many of its quests are left
local CATCHUP = 6      -- what a quest needs first may be up to this many levels over yours
local MOVED = 1500     -- yards from where the plan was chosen: choose again (you went somewhere else)
local SOON = 2         -- quests that open within this many levels count too: the plan's own XP gets you there
local SOON_SHARE = 0.5 -- ...at this share of what they pay (they wait until then)
local LOG_ROOM = 18    -- quests the log may hold (the game's 20, less a margin): new ones only up to that
local OCEAN = 60       -- minutes to another continent (a boat or zeppelin, and the walks to and from it)
local ABROAD = 2.5     -- an area on another continent has to pay this many times as much (the data's kill XP
                       -- varies more than the trip is worth: Mulgore's looked better than Tirisfal's from Tirisfal)

local P
local pathBonus = {}    -- questID -> extra XP from an accepted dungeon path (DungeonPaths.lua), this plan
local lastLevelOf = {}  -- questID -> the last level it pays at
local index             -- faction -> { areas = ns.TaskAreas[faction], of = { [questID] = { area, ... } }, parts = { [questID] = n } }
local current           -- the section handed out: { key, section, chosen = { questID, ... }, areas = { ... } }
local offPlan = 0       -- quests handed in this session that weren't on the plan (part of the plan's key)

local function L() return ns.Engine.lib end

-- The last level a quest still pays at (Worth), or 0.
function T:LastLevel(id)
    local v = lastLevelOf[id]
    if v then return v end
    v = 0
    local q = L().Q(id)
    if q then
        for level = math.max(1, q.l or 1), 60 do
            if L().Worth(id, level) then v = level else break end
        end
        -- (A small one that never pays that share, a quick hand-in: the game pays it in full until 5
        -- levels over its own, and that's its window.)
        if v == 0 then v = (q.l or 1) + 5 end
    end
    lastLevelOf[id] = v
    return v
end

-- How much more a quest weighs as it gets close to no longer paying: 1, 2 with a level left, 3 at its last.
function T:Urgency(id)
    P = P or ns.Progress
    local left = self:LastLevel(id) - P:Level()
    if left >= 2 then return 1 end
    if left == 1 then return 2 end
    return 3
end

local function Index()
    local faction = UnitFactionGroup("player")
    local areas = ns.TaskAreas and ns.TaskAreas[faction]
    if not areas then return nil end
    index = index or {}
    local x = index[faction]
    if x then return x end
    x = { areas = areas, of = {}, parts = {} }
    for _, a in ipairs(areas) do
        a.quests = {}
        local t = a.t
        for i = 1, #t - 1, 2 do
            local id = t[i]
            if not a.quests[id] then
                a.quests[id] = 0
                x.of[id] = x.of[id] or {}
                table.insert(x.of[id], a)
            end
            a.quests[id] = a.quests[id] + 1
            x.parts[id] = (x.parts[id] or 0) + 1
        end
    end
    index[faction] = x
    return x
end

-- Could be on the plan at this level: yours to take, not done or ruled out, and paying. (Cheap: the
-- server isn't asked here, only for the quests chosen, by the engine.)
-- (What only changes with your level, worked out once a level: the quests your race could take at it.)
local static = {} -- level -> { questID, ... }
local function Static(level)
    local list = static[level]
    if list then return list end
    list = {}
    local lib = L()
    for id, q in pairs(ns.Quests) do
        if not q.dq and not q.pvp and P:RaceAllowed(q.rm) and lib.Practical(q) <= level + SOON
            and T:LastLevel(id) >= level and not lib.NeedsDungeon(id, 0) then
            list[#list + 1] = id
        end
    end
    static[level] = list
    return list
end

-- path: on an accepted dungeon path (DungeonPaths.lua): in whatever it pays by itself, and a dungeon
-- quest's pick-up too (the path's last step).
local function Open(id, q, level, path)
    if not q or (q.dq and not path) or q.pvp or not P:RaceAllowed(q.rm) or P:Done(id) then return false end
    if ns.char.ignored[id] or ns.char.notOffered[id] or ns.Exists:Missing(id) then return false end
    local later = ns.char.later and ns.char.later[id]
    if later and level <= later then return false end
    if P:InLog(id) then return true end
    local lib = L()
    if lib.Practical(q) > level + SOON or (not path and T:LastLevel(id) < level) then return false end
    if lib.NeedsDungeon(id, 0) or (lib.DonationReady and not lib.DonationReady(q)) then return false end
    return true
end

-- The quests the plan can choose from: { [questID] = true }. A quest whose earlier quests aren't done
-- is in when they're all in the pool or your log too (any one of them for preAny), up to CATCHUP over you.
local function Pool(level)
    local lib = L()
    local pool, waiting = {}, {}
    local ids = {}
    for _, id in ipairs(Static(level)) do ids[#ids + 1] = id end
    for _, id in ipairs(P:LogQuests()) do ids[#ids + 1] = id end
    for id in pairs(pathBonus) do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do
        local q = ns.Quests[id]
        if not pool[id] and Open(id, q, level, pathBonus[id] ~= nil) then
            if P:InLog(id) or lib.PrereqsDone(q) then
                if P:InLog(id) or not q.pre or P:Doable(id) then pool[id] = true end
            elseif not lib.Unreachable(q, 0) then
                waiting[#waiting + 1] = id
            end
        end
    end
    -- What they need first: open, near enough your level, and itself ready (one step of a chain a
    -- plan; the next plan takes the next step).
    for _, id in ipairs(waiting) do
        local q = ns.Quests[id]
        local ok = not q.preAny
        for _, p in ipairs(q.pre) do
            local pq = ns.Quests[p]
            local fine = P:Done(p) or P:InLog(p) or pool[p]
                or (pq and Open(p, pq, level + CATCHUP) and lib.PrereqsDone(pq) and lib.Practical(pq) <= level + CATCHUP)
            if q.preAny and fine then ok = true; break end
            if not q.preAny and not fine then ok = false; break end
        end
        if ok then pool[id] = true end
    end
    return pool
end

local function Minutes(yards) return yards and yards / L().Speed() / 60 or OCEAN end

-- A trip the quickest way (Engine.lua's TravelMinutes: walking or riding, the hearthstone, a flight),
-- and the way; OCEAN when there's none. opts.noHearth: this plan has used the hearthstone already.
local function Travel(from, to, opts)
    if not (from and to) then return 0, "walk" end
    local m, way = L().TravelMinutes(from, to, opts)
    if not m then return OCEAN, "ocean" end
    return m, way
end
local NO_HEARTH = { noHearth = true }

-- A transition quest (q.tr: a pick-up and hand-in, nothing else, whose hand-in is in another questing
-- area) is picked up on the way there: its pick-up costs the detour from where you come from to the giver
-- and on to the area, over walking straight there, not a walk back from the area.
local function Detour(from, giver, centre)
    if not (from and giver and centre) then return nil end
    local lib = L()
    local a, b, direct = lib.TravelMinutes(from, giver, NO_HEARTH), lib.TravelMinutes(giver, centre, NO_HEARTH),
        lib.TravelMinutes(from, centre, NO_HEARTH)
    if not (a and b and direct) then return nil end
    return math.max(0, a + b - direct)
end

-- Transition blocks: the quests picked up at a stop on the way from one area of work to the next and
-- handed in where that way ends, around a transition quest (q.tr: a delivery that takes you there). A
-- Rogue's Deal (Calvin Montague), Gordo's Task (Gordo) and Fields of Grief, all picked up on the road
-- from Deathknell and handed in at Brill, are one block. When the plan takes one, it takes the others
-- it can, so the trip does them all. questID -> { questID, ... } (itself included).
local BLOCK_YARDS = 600 -- givers this close to the transition quest's giver, and hand-ins to its hand-in
local TRANSIT_MINUTES = 4 -- a transition quest's detour from where you are, at most, to go on a trip by itself
local blocks
local function Block(id)
    if not blocks then
        blocks = {}
        local lib = L()
        local function Near(x, y)
            return x[1] == y[1] and (x[2] - y[2]) ^ 2 + (x[3] - y[3]) ^ 2 <= BLOCK_YARDS * BLOCK_YARDS
        end
        -- Every quest's giver and hand-in, the givers in BLOCK_YARDS squares.
        local list, cells = {}, {}
        for qid, q in pairs(ns.Quests) do
            local a, t = q.a and not q.dq and lib.World(q.a), q.t and lib.World(q.t)
            if a and t then
                local e = { id = qid, a = a, t = t, tr = q.tr }
                list[#list + 1] = e
                local key = a[1] .. ":" .. math.floor(a[2] / BLOCK_YARDS) .. ":" .. math.floor(a[3] / BLOCK_YARDS)
                cells[key] = cells[key] or {}
                table.insert(cells[key], e)
            end
        end
        local parent = {}
        local function Find(x)
            while parent[x] and parent[x] ~= x do x = parent[x] end
            return x
        end
        for _, e in ipairs(list) do parent[e.id] = e.id end
        for _, e in ipairs(list) do
            if e.tr then
                local cn, cw = math.floor(e.a[2] / BLOCK_YARDS), math.floor(e.a[3] / BLOCK_YARDS)
                for dn = -1, 1 do
                    for dw = -1, 1 do
                        for _, o in ipairs(cells[e.a[1] .. ":" .. (cn + dn) .. ":" .. (cw + dw)] or {}) do
                            if o ~= e and Near(e.a, o.a) and Near(e.t, o.t) then parent[Find(o.id)] = Find(e.id) end
                        end
                    end
                end
            end
        end
        local groups = {}
        for _, e in ipairs(list) do
            local r = Find(e.id)
            if r ~= e.id or groups[r] then
                groups[r] = groups[r] or { r }
                if r ~= e.id then table.insert(groups[r], e.id) end
            end
        end
        for _, g in pairs(groups) do
            if #g > 1 then
                table.sort(g)
                for _, qid in ipairs(g) do blocks[qid] = g end
            end
        end
    end
    return blocks[id]
end

-- What an area pays from a spot (world { c, n, w }): XP a minute, with its XP, the quests that count
-- and the way you'd get there (TravelMinutes). opts.noHearth: the plan has used the hearthstone.
local function Score(x, a, from, pool, taken, level, opts)
    local lib = L()
    local xp, work, extra, quests = 0, 0, 0, {}
    local centre = lib.World(a.c)
    for id, n in pairs(a.quests) do
        if pool[id] and not taken[id] then
            local q = ns.Quests[id]
            local share = n / math.max(1, x.parts[id] or n)
            local soon = (not P:InLog(id) and lib.Practical(q) > level) and SOON_SHARE or 1
            -- (A dungeon quest is only picked up here, for an accepted path: it pays in the dungeon,
            -- and counts the path's share of that, like the path's other quests.)
            xp = xp + (q.dq and 0 or lib.QuestEarns(q, level) * T:Urgency(id) * soon) * share
                + (pathBonus[id] or 0) * share
            work = work + (q.dq and 0.2 or math.max(0.5, (q.m or 1))) * share
                + (q.dq and 0 or lib.ExpectedDeaths(q, level) * lib.DEATH_MINUTES * share)
            -- The walk to its giver and back to its hand-in, from here, as far as it's this area's.
            -- (Kept on the area in yards: the spots never move, your speed does. No giver or hand-in
            -- is 0; one there's no walk to is false, which Minutes makes OCEAN.)
            a.walk = a.walk or {}
            local w = a.walk[id]
            if not w then
                local function Way(point)
                    if not point then return 0 end
                    return centre and lib.Walked(centre, lib.World(point)) or false
                end
                w = { Way(q.a), Way(q.t) }
                a.walk[id] = w
            end
            if not P:InLog(id) then
                local detour = q.tr and q.a and Detour(from, lib.World(q.a), centre)
                extra = extra + (detour or Minutes(w[1])) * share
            end
            if not q.dq then extra = extra + Minutes(w[2]) * share * 0.5 end
            quests[#quests + 1] = id
        end
    end
    if #quests == 0 then return 0 end
    local travel, way = Travel(from, centre, opts)
    local rate = xp / (travel + work + extra + 1)
    if from and centre and from[1] ~= centre[1] then rate = rate / ABROAD end
    return rate, xp, quests, way
end

local function Here()
    local c, n, w = ns.WorldMap.Player()
    return c and { c, n, w } or nil
end

local function ZoneName(map)
    local info = map and C_Map.GetMapInfo(map)
    return info and info.name or nil
end

-- Steps for a quest: picked up (or its item looted), its objectives (one stop each, by SplitParts
-- in the engine's Build), handed in.
local function QuestSteps(id, steps)
    local q = ns.Quests[id]
    -- A dungeon quest (an accepted path's last step): picked up now, done with its dungeon.
    if q.dq then
        if not P:InLog(id) then steps[#steps + 1] = { "A", id, path = true } end
        return
    end
    if not P:InLog(id) then steps[#steps + 1] = { q.ia and not q.a and "L" or "A", id } end
    if q.o then steps[#steps + 1] = { "O", id } end
    if q.t then steps[#steps + 1] = { "T", id } end
end

local function LogKey()
    local ids = {}
    for _, id in ipairs(P:LogQuests()) do ids[#ids + 1] = id end
    table.sort(ids)
    return table.concat(ids, ",")
end

-- The plan's quests you can act on now: one of its steps is still to do and isn't waiting (for a
-- level, or for a quest it needs first).
local function Live(section)
    local E, n, seen = ns.Engine, 0, {}
    for _, s in ipairs(section.steps) do
        local id = s[2]
        if not seen[id] and not E:StepDone(s) and not E:Waits(s) then
            seen[id] = true
            n = n + 1
        end
    end
    return n
end

-- Still where the plan was chosen (or near enough): false when you've gone somewhere else, or where
-- you were wasn't known then.
local function StillHere(at)
    local now = Here()
    if not now then return true end
    if not at or at[1] ~= now[1] then return false end
    return (at[2] - now[2]) ^ 2 + (at[3] - now[3]) ^ 2 <= MOVED * MOVED
end

-- Choose: the areas, best XP a minute first, each from where the last one leaves you.
-- pin: a zone (map) you chose from the guide list (GuidePicker.lua): its areas come first, as long as
-- any of them has work for you, then the rest as usual. estimate: for the guide list's numbers, the log
-- isn't full (room for REFILL new quests at least). pool: Pool(level), when it's already worked out.
-- Also returns whether a pinned area was taken.
-- The minutes a quest of a dungeon path adds to the plan, from the nearest of its stops (where you are,
-- the areas chosen): there to the giver, its objectives (not a dungeon quest's: only picked up), the
-- hand-in, and back. nil: no way there.
local function PathMinutes(q, stops)
    local lib = L()
    local g = q.a and lib.World(q.a)
    if not g then return nil end
    local points = { g }
    if not q.dq then
        local o = q.o and q.o[1] and lib.World(q.o[1])
        if o then points[#points + 1] = o end
        local t = q.t and lib.World(q.t)
        if t then points[#points + 1] = t end
    end
    local best
    for _, from in ipairs(stops) do
        local total, at = 0, from
        for _, pt in ipairs(points) do
            local m = lib.TravelMinutes(at, pt, NO_HEARTH)
            if not m then total = nil; break end
            total, at = total + m, pt
        end
        local back = total and lib.TravelMinutes(at, from, NO_HEARTH)
        if back then
            total = total + back
            if not best or total < best then best = total end
        end
    end
    if not best then return nil end
    local work = q.dq and 0.2 or (q.o and math.max(0.5, q.m or 1) or 0.3)
    return best + work
end

local function Choose(level, pin, estimate, pool)
    local x = Index()
    if not x then return nil end
    pathBonus = ns.DungeonPaths and (ns.DungeonPaths:Bonus()) or {}
    pool = pool or Pool(level)
    local taken, chosen, picked = {}, {}, {}
    -- Your log first: always in the plan.
    for _, id in ipairs(P:LogQuests()) do
        local q = ns.Quests[id]
        if q and not q.dq and pool[id] and not taken[id] then
            taken[id] = true
            chosen[#chosen + 1] = id
        end
    end
    local from = Here()
    local deferred = ns.char.deferredAreas or {}
    local lock = ns.char.zoneLock -- "stay in this zone": its areas only
    local candidates = {}
    for i, a in ipairs(x.areas) do
        if a.lo <= level + LEVEL_ABOVE and a.hi >= level - 8 and not (deferred[i] and deferred[i] >= level)
            and (not lock or a.c[1] == lock) then
            for id in pairs(a.quests) do
                if pool[id] then candidates[#candidates + 1] = a; break end
            end
        end
    end
    local best, totalXp, totalMinutes = nil, 0, 0
    -- The hearthstone, from pick to pick: a plan uses it once (then it's on cooldown).
    local opts = { noHearth = false }
    -- New quests only as far as the log has room: the plan is chosen again after each hand-in.
    local room = LOG_ROOM - #P:LogQuests()
    if estimate then room = math.max(room, REFILL) end
    local new, pinnedAny = 0, false
    while #chosen < LOOKAHEAD and new < room do
        local top, topRate, topQuests, topXp, topWay
        local function Look(onlyPin)
            for _, a in ipairs(candidates) do
                -- (One continent a plan: the first area's. The next plan can cross an ocean, this one doesn't.)
                local c = picked[1] and L().World(a.c)
                local sameContinent = not picked[1] or (c and c[1] == picked.continent)
                if sameContinent and not picked[a] and (not onlyPin or a.c[1] == pin) then
                    local rate, xp, quests, way = Score(x, a, from, pool, taken, level, opts)
                    if rate > 0 and (not topRate or rate > topRate) then
                        top, topRate, topQuests, topXp, topWay = a, rate, quests, xp, way
                    end
                end
            end
        end
        -- The zone you chose: its areas first, whatever else pays more.
        local pinned = false
        if pin then
            Look(true)
            pinned = top ~= nil
        end
        if not pinned then Look(false) end
        if not top or (not pinned and best and topRate < best * KEEP_SHARE) then break end
        if pinned then pinnedAny = true end
        best = best or topRate
        if topWay == "hearth" then opts.noHearth = true end
        picked[top] = true
        picked[#picked + 1] = top
        picked.ways = picked.ways or {}
        picked.ways[#picked] = topWay
        if not picked.continent then
            local c = L().World(top.c)
            picked.continent = c and c[1]
        end
        totalXp = totalXp + topXp
        totalMinutes = totalMinutes + topXp / topRate
        table.sort(topQuests)
        local function Take(id)
            if not taken[id] and (P:InLog(id) or new < room) then
                taken[id] = true
                chosen[#chosen + 1] = id
                if not P:InLog(id) then new = new + 1 end
                return true
            end
        end
        for _, id in ipairs(topQuests) do
            if Take(id) then
                -- A quest of a transition block brings the rest of it (those you can take now).
                for _, other in ipairs(Block(id) or {}) do
                    if pool[other] then Take(other) end
                end
            end
        end
        from = L().World(top.c) or from
    end
    -- Transition quests on the way: one that ends where the plan is going (within BLOCK_YARDS of a chosen
    -- area) and costs at most TRANSIT_MINUTES of detour from where you are is taken, with its block. Its
    -- own area may never be chosen (a delivery is a task at its hand-in, and a few talk hand-ins pay too
    -- little to win an area: A Rogue's Deal was missing from Tirisfal's plan), but on a trip you take
    -- anyway it's nearly free. With the log full, they take the place of the last quests chosen (the
    -- areas that paid least).
    local here = Here()
    local dests = {}
    for _, a in ipairs(picked) do dests[#dests + 1] = L().World(a.c) end
    local function Heading(t)
        for _, d in ipairs(dests) do
            if d and d[1] == t[1] and (d[2] - t[2]) ^ 2 + (d[3] - t[3]) ^ 2 <= BLOCK_YARDS * BLOCK_YARDS then return true end
        end
        return false
    end
    local extra, inExtra = {}, {}
    for id in pairs(pool) do
        local q = ns.Quests[id]
        if q.tr and q.a and q.t and not taken[id] and not P:InLog(id) then
            local a, t = L().World(q.a), L().World(q.t)
            local detour = a and t and Heading(t) and Detour(here, a, t)
            if detour and detour <= TRANSIT_MINUTES then
                for _, other in ipairs(Block(id) or { id }) do
                    if pool[other] and not taken[other] and not inExtra[other] and not P:InLog(other) then
                        inExtra[other] = true
                        extra[#extra + 1] = other
                    end
                end
            end
        end
    end
    table.sort(extra)
    local need = new + #extra - room
    for i = #chosen, 1, -1 do
        if need <= 0 then break end
        local id = chosen[i]
        if not P:InLog(id) and not inExtra[id] then
            table.remove(chosen, i)
            taken[id], new, need = nil, new - 1, need - 1
        end
    end
    for _, id in ipairs(extra) do
        if new < room then
            taken[id] = true
            chosen[#chosen + 1] = id
            new = new + 1
        end
    end
    -- Dungeon paths you accepted (DungeonPaths.lua): a step of one that no chosen area took is fitted in
    -- when it pays as well as the plan's last area would have to (KEEP_SHARE of the best), counting the
    -- path's share of the dungeon quest, over the detour from the nearest stop. On your way it's nearly
    -- free and goes in; far off, it waits until a plan goes near it. Like the transition quests, it takes
    -- the place of the last quests chosen when the log is full.
    local floor = (best or 0) * KEEP_SHARE
    local stops = { here }
    for _, a in ipairs(picked) do stops[#stops + 1] = L().World(a.c) end
    local fits = {}
    for id, b in pairs(pathBonus) do
        local q = ns.Quests[id]
        if q and pool[id] and not taken[id] and not P:InLog(id) and L().PrereqsDone(q) then
            local minutes = PathMinutes(q, stops)
            local value = (q.dq and 0 or L().QuestEarns(q, level)) + b
            if minutes and value / minutes >= floor then fits[#fits + 1] = { id = id, r = value / minutes } end
        end
    end
    table.sort(fits, function(a, b) return a.r > b.r end)
    local need2 = new + #fits - room
    for i = #chosen, 1, -1 do
        if need2 <= 0 then break end
        local id = chosen[i]
        if not P:InLog(id) and not inExtra[id] and not pathBonus[id] then
            table.remove(chosen, i)
            taken[id], new, need2 = nil, new - 1, need2 - 1
        end
    end
    for _, f in ipairs(fits) do
        if new < room then
            taken[f.id] = true
            chosen[#chosen + 1] = f.id
            new = new + 1
        end
    end
    return chosen, picked, totalMinutes > 0 and totalXp / totalMinutes or 0, pinnedAny
end

-- Every quest in your log is on the plan: nothing was taken that the plan didn't choose.
local function LogOnPlan(plan)
    local on = {}
    for _, id in ipairs(plan.chosen) do on[id] = true end
    for _, id in ipairs(P:LogQuests()) do
        if not on[id] and not P:Done(id) then return false end
    end
    return true
end

-- The section for the engine (see the top), or nil when the zone sections decide.
-- The plan is kept while it has work enough (REFILL quests you can act on): handing in or taking
-- one of its quests changes nothing (what follows a quest is on it already), at the same level and
-- near where it was chosen. A quest taken or handed in that wasn't on it, a new level, or the plan
-- running low: chosen again.
function T:Section(guide)
    P = P or ns.Progress
    local lib = ns.Engine and ns.Engine.lib
    if not lib or lib.Clearing() or ns.char.section or ns.char.instance then return nil end
    if not Index() then return nil end
    local level = P:Level()
    local paths = 0
    for _ in pairs(ns.char.dungeonPaths or {}) do paths = paths + 1 end
    local key = table.concat({ level, LogKey(), offPlan, tostring(ns.char.zoneLock), tostring(ns.char.guideZone), paths }, "|")
    if current and StillHere(current.at) then
        local live = Live(current.section)
        if live > 0 and (current.key == key or (current.level == level and current.offPlan == offPlan
            and live >= REFILL and LogOnPlan(current))) then
            current.key = key
            return current.section
        end
    end
    local pin = ns.char.guideZone
    local chosen, areas, rate, pinnedAny = Choose(level, pin)
    chosen, areas = chosen or {}, areas or {}
    -- The zone you chose from the guide list has nothing left for you: back to the best plan.
    if pin and not pinnedAny then
        ns.char.guideZone = nil
        ns:Print(("%s has nothing left for you now: back to the best plan."):format(ZoneName(pin) or "That zone"))
        key = table.concat({ level, LogKey(), offPlan, tostring(ns.char.zoneLock), "nil", paths }, "|")
    end
    local steps = {}
    for _, id in ipairs(chosen) do QuestSteps(id, steps) end
    local zones, seenZone = {}, {}
    for _, a in ipairs(areas) do
        local name = ZoneName(a.c[1])
        if name and not seenZone[name] then
            seenZone[name] = true
            zones[#zones + 1] = name
        end
    end
    local section = {
        id = "tasks", tasks = true, steps = steps, rate = rate,
        title = #zones > 0 and ("Leveling: " .. table.concat(zones, ", ", 1, math.min(2, #zones))) or "Leveling",
        zone = areas[1] and areas[1].c[1] or lib.CurrentZone(), from = level, to = level + 1, top = level + 1,
    }
    -- Nothing in it you can do now (all of it waits for a level, or nothing was chosen): level up first,
    -- where you are, to the level the first of its quests opens at (the next level when there's none).
    if Live(section) == 0 then
        local need
        for _, id in ipairs(chosen) do
            local q = ns.Quests[id]
            local at = q and lib.Practical(q)
            if at and at > level and (not need or at < need) then need = at end
        end
        table.insert(steps, 1, { "G", need or (level + 1) })
    end
    local before = current and table.concat(current.chosen, ",")
    current = { key = key, level = level, offPlan = offPlan, section = section, chosen = chosen, areas = areas, at = Here() }
    if before ~= table.concat(chosen, ",") then lib.Reorder("new work chosen") end
    return section
end

-- Choose again (a quest skipped, an area put off).
function T:Refresh() current = nil end

-- The guide list (GuidePicker.lua): the best plan, then up to OPTION_ZONES zones you could follow, each
-- with the XP a minute its plan pays from where you are (Choose, as if your log had room). Worked out a
-- piece a frame, so opening the list never hitches; done(list) gets
--     { { kind = "best" | "zone", map, name, rate, lo, hi, quests, zones, current }, ... }
-- the best plan first, then the zones, best rate first.
local OPTION_ZONES = 6
local working
function T:Options(done)
    P = P or ns.Progress
    if working then working.done = done; return end
    local x = Index()
    if not x then done({}); return end
    local job = { done = done }
    working = job
    local co = coroutine.create(function()
        local level = P:Level()
        local pool = Pool(level)
        coroutine.yield()
        -- Rank the zones by their best area from here (one look each), then plan the best few in full.
        local from, opts, zones = Here(), { noHearth = false }, {}
        local deferred = ns.char.deferredAreas or {}
        for i, a in ipairs(x.areas) do
            if a.lo <= level + LEVEL_ABOVE and a.hi >= level - 8 and not (deferred[i] and deferred[i] >= level) then
                local rate = Score(x, a, from, pool, {}, level, opts)
                if rate > 0 then
                    local z = zones[a.c[1]]
                    if not z then
                        z = { map = a.c[1], best = 0, lo = a.lo, hi = a.hi }
                        zones[a.c[1]] = z
                        zones[#zones + 1] = z
                    end
                    z.best = math.max(z.best, rate)
                    z.lo, z.hi = math.min(z.lo, a.lo), math.max(z.hi, a.hi)
                end
            end
            if i % 40 == 0 then coroutine.yield() end
        end
        table.sort(zones, function(a, b) return a.best > b.best end)
        local out = {}
        local chosen, picked, rate = Choose(level, nil, true, pool)
        local names, seen = {}, {}
        for _, a in ipairs(picked or {}) do
            local n = ZoneName(a.c[1])
            if n and not seen[n] then seen[n] = true; names[#names + 1] = n end
        end
        out[1] = { kind = "best", name = "Best plan", rate = rate or 0, quests = chosen and #chosen or 0,
            zones = table.concat(names, ", ", 1, math.min(2, #names)), current = ns.char.guideZone == nil }
        for i = 1, math.min(OPTION_ZONES, #zones) do
            coroutine.yield()
            local z = zones[i]
            local zc, zp, zr, any = Choose(level, z.map, true, pool)
            if any and (zr or 0) > 0 then
                out[#out + 1] = { kind = "zone", map = z.map, name = ZoneName(z.map) or ("Map " .. z.map), rate = zr,
                    lo = z.lo, hi = z.hi, quests = zc and #zc or 0, current = ns.char.guideZone == z.map }
            end
        end
        local tail = {}
        for i = 2, #out do tail[#tail + 1] = out[i] end
        table.sort(tail, function(a, b) return a.rate > b.rate end)
        for i, o in ipairs(tail) do out[i + 1] = o end
        return out
    end)
    local function Step()
        if working ~= job then return end
        local ok, result = coroutine.resume(co)
        if not ok then
            working = nil
            geterrorhandler()(result)
            job.done({})
        elseif coroutine.status(co) == "dead" then
            working = nil
            job.done(result or {})
        else
            C_Timer.After(0, Step)
        end
    end
    Step()
end

-- Follow a zone from the guide list (nil: the best plan again). The plan is chosen again at once.
function T:Follow(map)
    ns.char.guideZone = map
    current = nil
end

-- The plan's quests, in the order chosen (for /fg why and the simulator), or nil.
function T:Chosen() return current and current.chosen end

-- Put off the area a step is in, for this level (skipping a long trip): the plan looks elsewhere.
function T:DeferAreaOf(id)
    P = P or ns.Progress
    local x = Index()
    if not x or not x.of[id] then return false end
    ns.char.deferredAreas = ns.char.deferredAreas or {}
    for i, a in ipairs(x.areas) do
        for _, b in ipairs(x.of[id]) do
            if a == b then ns.char.deferredAreas[i] = P:Level() end
        end
    end
    current = nil
    return true
end

-- /fg why: the areas chosen and the quests close to no longer paying.
function T:Why(lines)
    if not current then return end
    P = P or ns.Progress
    lines[#lines + 1] = ("Leveling plan: %d quests in %d task areas, about %d XP a minute"):format(#current.chosen,
        #current.areas, current.section.rate or 0)
    for i, a in ipairs(current.areas) do
        if i > 6 then break end
        local way = current.areas.ways and current.areas.ways[i]
        local how = (way == "hearth" and ", hearthstone there") or (way == "fly" and ", fly there") or ""
        lines[#lines + 1] = ("  area at %s %.0f, %.0f (levels %d-%d%s)"):format(ZoneName(a.c[1]) or a.c[1], a.c[2], a.c[3], a.lo, a.hi, how)
    end
    local soon = {}
    for _, id in ipairs(current.chosen) do
        if not P:Done(id) and self:LastLevel(id) - P:Level() <= 1 then
            soon[#soon + 1] = ("%s (pays to level %d)"):format(ns.Engine:QuestName(id), self:LastLevel(id))
        end
    end
    if #soon > 0 then lines[#lines + 1] = "  Do soon, before they stop paying: " .. table.concat(soon, ", ") end
    if ns.DungeonPaths then ns.DungeonPaths:Why(lines) end
end

ns:On("QUEST_TURNED_IN", function(id)
    if current then
        for _, c in ipairs(current.chosen) do
            if c == id then return end -- on the plan: it goes on as planned
        end
    end
    offPlan = offPlan + 1
end)
