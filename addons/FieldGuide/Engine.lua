local _, ns = ...

-- Follows the guide for you. Your race doesn't matter: the guide is your faction's, and the section
-- is the zone you're in if it has quests worth doing at your level (walk into a zone and its guide
-- takes over), otherwise the one you were on, or else the nearest one for your level. Quests
-- worth too little XP for your level are left out (see Worth), unless one you'll do needs them. It works out which steps are done from your quest log and
-- finished quests, skips quests your race can't take, and puts the quests a section needs first
-- (if you skipped them somewhere else) in front of it. The current step goes to Waypoint's arrow.
--
-- Moving on: a zone ends with a hand-off quest to the next zone that suits your level (a
-- breadcrumb or "report to ..." quest; the exits in Guides\*.lua). If the zone you're in has
-- nothing left for your level, the guide looks for such a quest here; failing that, it sends you
-- to the nearest zone that has quests for your level.
--
-- Preference (ns.char.preference, the settings' "Preference"):
--   Leveling  (above) XP and convenience first, and a quick quest a little off the route (nothing to
--             do but hand it in) is picked up on the way when it pays its walk (see AddDetours).
--             Every zone is weighed the same way, wherever you are: what its quests you can reach
--             pay, against the time they take and the walk there (see Value). You stay while where
--             you are pays best, and go when somewhere else pays better, walk included.
--   Zone Clear every quest of the zone you're on that you haven't done, whatever its XP (all of the
--             zone's sections as one, see ClearSections), and what they need first wherever it is: the
--             zone stays yours while you fetch it. Quests above your level wait at the end ("later");
--             with only those left the zone is cleared, and the guide moves on as above. A quest you
--             skip goes after the rest of the zone (ns.char.deferred); skipped again, it's gone.
-- Either way a quest only goes on the route once the server says it exists, and leaves it when its
-- giver doesn't offer it (Exists.lua).
--
-- Steps (from Guides\*.lua): { "A", quest } pick up, { "O", quest } objectives, { "T", quest }
-- turn in, { "G", level } grind to a level, { "Z", uiMapID } travel to another zone, and (made
-- here) { "L", quest } loot the item that starts a quest, { "I", dungeon } run a dungeon.
local E = {}
ns.Engine = E
E.hunting = {} -- [questID] = { [step key] = true }: hunting areas you've moved on from

local P
local MIN_SHARE = 0.015 -- a quest is shown when it pays at least this share of your next level
-- Automatic considers a zone's guide when its levels come within RANGE of yours, up or down (8 in
-- all), and prefers the ones whose quests are at your level to 2 above (see Score). A zone you
-- pick yourself always shows; for one quest in an old zone, Questie has you covered.
local RANGE = 4
local TARGET = 2 -- the ideal: quests from your level up to this many above
local CATCHUP = 6 -- quests needed first are only routed to when they need at most this many over yours
local MAX_REACH = 4 -- levels past that you'll reach for quests the game offers, when nothing nearer is left
local STRETCH = 3 -- a quest waits until you're within this many levels of it (build_guides.py has the same rule)
-- Weighing a zone (see Value).
local YARDS_A_MINUTE = 420 -- on foot
local OCEAN_MINUTES = 45   -- another continent: straight-line yards don't apply (a whole HORIZON: only if nothing's nearer)
local MAX_LEG = 15         -- minutes: past this you'd take a flight path, not walk it
local LONG_TRIP = 10        -- minutes: a trip this long to a zone that doesn't touch yours is asked about first
local TOUCHING_YARDS = 1500 -- Leveling: zones whose quest areas are this close are neighbours (see Touching)
local MIN_MINUTES = 3      -- what's left of a route takes at least this long
local GRIND_GAP = 1        -- the levels a route can gain on its way, between quests
local HORIZON = 45         -- minutes: a zone elsewhere is judged by what it pays in this long, the walk there included
local GROUP_MINUTES = 3    -- finding a group (Forever's group boards: 1 to 5 minutes)
local RUN_MINUTES = 35     -- the dungeon itself
-- A run's kills, in single kills of your level. Set from a real run: Ragefire Chasm at 15 came to about
-- 1.3 levels (19,000 XP) with its quests.
local RUN_KILL_XP = 100
-- Forever pays far more for dungeon quests than the Classic-era XP in our data. Only for weighing
-- dungeons against questing: replace it with real numbers once Forever's quest XP is known.
local DUNGEON_QUEST_PAY = 2
local WAITING_RATE = 1e-5   -- a zone with nothing you can do yet keeps this much of its worth: it ranks, behind any with work
local LOOSE_QUESTS = 8      -- quests on a list of loose ends at a time
local LOOSE_MINUTES = 5    -- what one of them takes, to weigh the zones by
local STAY_EDGE = 1.2      -- leaving the zone you're on has to pay this much better: no flipping back and forth

-- The level a quest is worth taking at: what it needs, or STRETCH under its own level (the data
-- says a level 8 quest needs only level 1, and its mobs are level 8).
local reach = 0 -- levels past STRETCH you're reaching, while nothing nearer your level is left (see PickSection)
local function Practical(q)
    return math.max(q and q.r or 1, (q and q.l or 1) - STRETCH - reach)
end

-- Minutes on foot between two quest data points { uiMapID, x, y (0-100) }.
local function WalkMinutes(a, b)
    if not (a and b) or a[1] == b[1] then return 0 end
    -- The real walk where there is one (mountains and all), from the build. Otherwise the straight line:
    -- lifts and the like aren't on the walking map, and an ocean is an ocean.
    local real = ns.ZoneWalks and ns.ZoneWalks[a[1]] and ns.ZoneWalks[a[1]][b[1]]
    if real then return real end
    local WM = ns.WorldMap
    local c1, n1, w1 = WM.World(a[1], a[2] / 100, a[3] / 100)
    local c2, n2, w2 = WM.World(b[1], b[2] / 100, b[3] / 100)
    local yards = c1 and c2 and WM.Distance(c1, n1, w1, c2, n2, w2)
    if not yards then return OCEAN_MINUTES end
    return yards / YARDS_A_MINUTE
end

-- The section's levels come within RANGE of yours.
local function InRange(s, level)
    return (s.from or 1) <= level + RANGE and (s.to or 60) >= level - RANGE
end

-- How well a section's levels suit you: 0 when it covers your level to TARGET above; otherwise
-- how far off it is, a section under you counting double (you'd be catching up, not leveling).
local function Score(s, level)
    local from, to = s.from or 1, s.to or 60
    if to <= level then return (level - to) * 2 + 1 end -- (ending at your level: it has nothing ahead of you)
    if from > level + TARGET then return from - (level + TARGET) end
    return 0
end

-- XP to go from level i to i + 1 (Classic).
-- (Wowhead's Forever experience calculator agrees with every value.)
local XP_TO_LEVEL = { 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400,
    16000, 17700, 19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400,
    50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700, 95800, 101000, 106300, 111800,
    117500, 123200, 129100, 135100, 141200, 147500, 153900, 160400, 167100, 173900, 180800, 187900, 195000,
    202300, 209800 }

E.guide, E.section, E.steps, E.current = nil, nil, {}, nil

local function Q(id) return ns.Quests[id] end

-- The XP a quest pays at your level, the way the game scales it (Questie's cmangos formula).
local function QuestXP(q, level)
    if not (q and q.xp) or level >= 60 then return 0 end
    local mult = math.min(10, math.max(1, 2 * ((q.l or level) - level) + 20))
    local xp = q.xp * mult / 10
    if xp <= 100 then xp = 5 * math.floor((xp + 2) / 5)
    elseif xp <= 500 then xp = 10 * math.floor((xp + 5) / 10)
    elseif xp <= 1000 then xp = 25 * math.floor((xp + 12) / 25)
    else xp = 50 * math.floor((xp + 25) / 50) end
    return xp
end

-- All a quest earns you at your level: what it pays, and the kills that go with it (its objectives and
-- the mobs along the way: q.k, at the quest's own level, shrinking as it does for you).
local function QuestEarns(q, level)
    local xp = QuestXP(q, level)
    if not (q and q.k and q.xp and q.xp > 0) then return xp end
    return xp + q.k * math.min(1, xp / q.xp)
end
E.QuestEarns = function(_, id) return QuestEarns(Q(id), P:Level()) end

-- A death is a big chunk of time, so a quest above your level is worth less than its XP says. The
-- deaths it can be expected to cost grow with the square of the levels it's above you (DEATH_RISK a
-- level), and fade as you level. Only with something to fight: a quest with no objectives is a walk.
local DEATH_RISK = 0.25
local DEATH_MINUTES = 3 -- the run back, and getting going again
local function ExpectedDeaths(q, level)
    local over = (q and q.l or level) - level
    if over <= 0 or not (q and q.o) then return 0 end
    return DEATH_RISK * over * over
end

-- Worth doing at your level: it pays a fair share of what your next level needs.
local function Worth(id, level)
    local need = XP_TO_LEVEL[level]
    if not need then return false end
    return QuestXP(Q(id), level) >= need * MIN_SHARE
end
E.QuestXP = function(_, id) return QuestXP(Q(id), P:Level()) end

-- ---------------------------------------------------------------------------------------------
-- Choosing the guide and section
-- ---------------------------------------------------------------------------------------------

local function GuideByKey(key)
    if not key then return nil end
    key = strlower(key)
    for _, g in ipairs(ns.Guides) do
        if strlower(g.key) == key or strlower(g.name) == key then return g end
    end
end

function E:Guide()
    return GuideByKey(ns.char.guide) or GuideByKey((UnitFactionGroup("player")))
end

local function StepKey(step)
    return step[1] .. ":" .. tostring(step[2]) .. (step.wing and (":" .. step.wing) or "") .. (step.part and ("#" .. step.part) or "")
end

local function Clearing() return ns.char.preference == "clear" end

-- Zone Clear: one section per zone, its sections' routes one after the other (each with every
-- quest of the zone's pool, its "clear" route, and the quests the planner never got to, "rest"),
-- by the level they start at. Built once per guide.
local clearSections = {} -- guide -> { list = { section, ... }, byZone = { [uiMapID] = section } }
local function ClearSections(guide)
    local c = clearSections[guide]
    if c then return c end
    c = { list = {}, byZone = {} }
    local seen = {}
    for _, s in ipairs(guide.sections) do
        local z = c.byZone[s.zone]
        if not z then
            local info = C_Map.GetMapInfo(s.zone)
            z = { id = "clear-" .. s.zone, zone = s.zone, zoneClear = true, from = s.from, to = s.to, minutes = 0,
                title = info and info.name or (s.title:gsub("%s+%d+.*$", "")), steps = {} }
            c.byZone[s.zone] = z
            c.list[#c.list + 1] = z
            seen[z] = {}
        end
        z.from, z.to = math.min(z.from or 1, s.from or 1), math.max(z.to or 1, s.to or 1)
        z.minutes = z.minutes + (s.minutes or 0)
        for _, st in ipairs(s.clear or s.steps) do
            local key = StepKey(st)
            if st[1] ~= "G" and not seen[z][key] then
                seen[z][key] = true
                z.steps[#z.steps + 1] = st
            end
        end
    end
    -- The quests no walk got to (most need a level the zone's route never reached), at the end.
    for _, s in ipairs(guide.sections) do
        local z = c.byZone[s.zone]
        for _, id in ipairs(s.rest or {}) do
            local q = Q(id)
            if q and not seen[z]["A:" .. id] then
                seen[z]["A:" .. id] = true
                z.steps[#z.steps + 1] = { "A", id }
                if q.o then z.steps[#z.steps + 1] = { "O", id } end
                z.steps[#z.steps + 1] = { "T", id }
            end
        end
    end
    clearSections[guide] = c
    return c
end

-- The sections Automatic picks from: the guide's, or with Zone Clear one per zone.
local function Sections(guide)
    return Clearing() and ClearSections(guide).list or guide.sections
end
-- The section to follow for one of the guide's own (a pick in the settings): with Zone Clear, its zone's.
local function AsPicked(guide, s)
    return s and Clearing() and ClearSections(guide).byZone[s.zone] or s
end

-- ---------------------------------------------------------------------------------------------
-- Is a step done?
-- ---------------------------------------------------------------------------------------------

local function PrereqsDone(q)
    if not q.pre then return true end
    if q.preAny then
        for _, p in ipairs(q.pre) do if P:Done(p) then return true end end
        return false
    end
    for _, p in ipairs(q.pre) do if not P:Done(p) then return false end end
    return true
end

-- Needs a quest first that the guides can't send you to: one that starts from an item (the
-- Damp Note that drops in Blackfathom Deeps starts the quest Je'neu needs before she offers
-- "Allegiance to the Old Gods"), or one only another race can do. Until you've done it, the
-- quest giver won't offer this one, so the guide leaves it out.
--
-- A quest started by an item that drops out in the world is reachable: the guide sends you to the
-- mobs (a "Loot" step). One whose item drops inside a dungeon isn't, ahead of the run: the run
-- itself looks for the item, and what needs that quest waits for the next run.
local function CanFetch(p, pq, depth)
    if P:InLog(p) then return true end
    if not pq or not P:RaceAllowed(pq.rm) or ns.char.ignored[p] or ns.char.notOffered[p] then return false end
    if ns.Exists:Missing(p) then return false end
    if pq.ia and not pq.d then return false end
    return not E.Unreachable(pq, depth + 1)
end

function E.Unreachable(q, depth)
    if not q.pre or depth > 10 or PrereqsDone(q) then return false end
    if q.preAny then
        for _, p in ipairs(q.pre) do
            if CanFetch(p, Q(p), depth) then return false end
        end
        return true
    end
    for _, p in ipairs(q.pre) do
        if not P:Done(p) and not CanFetch(p, Q(p), depth) then return true end
    end
    return false
end
local Unreachable = E.Unreachable

-- A quest you can't get: another race's; one that needs a quest first that no guide can send you
-- to (see Unreachable); or one Questie says you can't take though nothing it needs is missing
-- (your class, reputation, or a quest that rules it out).
local function Unavailable(id)
    P = P or ns.Progress
    local q = Q(id)
    if q and not P:RaceAllowed(q.rm) then return true end
    if P:Done(id) then return false end
    -- Skipped by hand (or left because its item didn't drop): never suggested again, even while
    -- it's in your log. It's yours to finish on your own.
    if ns.char.ignored[id] then return true end
    if P:InLog(id) then return false end
    -- Its giver didn't offer it when you got there, or the server has no such quest (or hasn't
    -- said yet: it goes on the route once it does).
    if ns.char.notOffered[id] or ns.Exists:Missing(id) or ns.Exists:Pending(id) then return true end
    if q and Unreachable(q, 0) then return true end
    return q and PrereqsDone(q) and not P:Doable(id)
end

E.Unavailable = function(_, id) return Unavailable(id) end
E.PrereqsDone = function(_, id)
    P = P or ns.Progress
    local q = Q(id)
    return not q or PrereqsDone(q)
end

-- A quest you could still do: not done, and not ruled out.
function E:QuestOpen(id)
    P = P or ns.Progress
    return not P:Done(id) and not Unavailable(id)
end

-- "Run the dungeon" (or one wing of it): see Instance:RunDone.
local function DungeonDone(step)
    local inst = ns.Instance:Get(step[2])
    if not inst then return true end
    return ns.Instance:RunDone(inst, step)
end

function E:StepDone(step)
    local kind, id = step[1], step[2]
    if ns.char.skipped[StepKey(step)] then return true end
    if kind == "G" then return P:Level() >= id end
    if kind == "I" then return DungeonDone(step) end
    if kind == "L" then return P:Done(id) or P:InLog(id) or ns.char.ignored[id] == true end
    -- A quest that starts inside the dungeon: only to turn in if you found its item.
    if kind == "T" and step.inside and not P:InLog(id) then return true end
    if kind == "Z" then return false end -- settled by the steps after it (see Build)
    if P:Done(id) then return true end
    if Unavailable(id) then return true end
    if kind == "A" then return P:InLog(id) end
    -- Done outside before a run. All of it outside: while you're in the dungeon it waits, and
    -- if it isn't finished it comes back when you're out. Started outside ("part"): the rest is
    -- done inside, so it's over once you've gone in.
    if kind == "O" and step.before then
        local inst = ns.Instance:Get(step.inst)
        local part = inst and inst.before and inst.before[id] == "part"
        if part and ns.Instance:Entered(inst) or ns.Instance:InRun(inst) then return true end
    end
    if kind == "O" and step.part then return P:ReadyToTurnIn(id) or self:ActionDone(id, step.part) end
    if kind == "O" then return P:ReadyToTurnIn(id) or not (Q(id) and Q(id).o) and P:InLog(id) end
    return false
end

-- ---------------------------------------------------------------------------------------------
-- Building the section's steps, with what it needs first
-- ---------------------------------------------------------------------------------------------

-- Which of a quest's "any one of these" to go for: one the route has anyway, else the one in the
-- quest's own zone, else the nearest. (Camping 101 takes The Great Outdoors from any of seven
-- starting zones: yours, not the first on the list.) When one of them belongs to the quest's own
-- zone, the others are that quest for other zones: none of them is worth the trip, so with the
-- zone's own out of reach there's no answer, and the quest leaves the route (see Build).
local function BestAlternative(q, route)
    local best, bestRank
    local local_ = false
    for _, p in ipairs(q.pre) do
        local pq = Q(p)
        if pq and pq.a and q.a and pq.a[1] == q.a[1] then local_ = true end
    end
    for _, p in ipairs(q.pre) do
        local pq = Q(p)
        if pq and P:RaceAllowed(pq.rm) and not Unavailable(p) then
            local rank
            if route[p] then
                rank = -2
            elseif pq.a and q.a and pq.a[1] == q.a[1] then
                rank = -1
            elseif not local_ then
                rank = pq.a and ns.WorldMap.DistanceTo(pq.a[1], pq.a[2] / 100, pq.a[3] / 100) or math.huge
            end
            if rank and (not best or rank < bestRank) then best, bestRank = p, rank end
        end
    end
    return best
end

-- Quests a quest needs that you haven't done, deepest first. route: the quests on the section.
local function Missing(id, out, seen, depth, route)
    local q = Q(id)
    if not q or not q.pre or depth > 25 then return end
    local list = q.pre
    if q.preAny then
        for _, p in ipairs(q.pre) do if P:Done(p) or P:InLog(p) then return end end
        local p = BestAlternative(q, route)
        list = p and { p } or {}
    end
    for _, p in ipairs(list) do
        if not seen[p] and Q(p) and P:RaceAllowed(Q(p).rm) and not P:Done(p) then
            seen[p] = true
            Missing(p, out, seen, depth + 1, route)
            out[#out + 1] = p
        end
    end
end

-- Needs a dungeon's quest first that you haven't done: the leveling guide leaves it out (dungeon
-- quests are the dungeon routes' business).
local function NeedsDungeon(id, depth)
    local q = Q(id)
    if not q or not q.pre or depth > 15 then return false end
    for _, p in ipairs(q.pre) do
        local pq = Q(p)
        if pq and not P:Done(p) and (pq.dq or NeedsDungeon(p, depth + 1)) then return true end
    end
    return false
end

-- Cloth donations ("A Donation of Silk", ...): handed in on the spot at a city's cloth
-- quartermaster with DONATION_COUNT of that cloth from your bags, with nothing to pick up first.
-- Their quest data points at where the cloth drops, so on their own they'd send you off farming.
-- They only show when the cloth is already in your bags and the quartermaster is close by: in the
-- zone you're in, the city in it, or the zone around the city you're in. Never their "Do" step.
local CLOTH = { Wool = 2592, Silk = 4306, Mageweave = 4338, Runecloth = 14047 }
local DONATION_COUNT = 60

local function DonationCloth(q)
    local kind = q and type(q.n) == "string" and q.n:match("^A Donation of (%a+)$")
    return kind and CLOTH[kind] or nil
end

local function ParentMap(map)
    local info = map and C_Map.GetMapInfo(map)
    return info and info.parentMapID or nil
end

local function DonationReady(q)
    local item = DonationCloth(q)
    if not item then return true end
    if (GetItemCount and GetItemCount(item) or 0) < DONATION_COUNT then return false end
    local qm = q.a and q.a[1]
    local here = C_Map.GetBestMapForUnit("player")
    if not (qm and here) then return false end
    local near = { [here] = true }
    local up = ParentMap(here)
    if up then near[up] = true end
    return near[qm] or near[ParentMap(qm) or -1] or false
end
E.DonationCloth = function(_, id) return DonationCloth(Q(id)) end

-- The quests left on a section that you'd really get to: walking up them by level from yours, with
-- the XP each one pays (and the kills around it) carrying you on, and leaving out what pays too little
-- at the level you'd be by then. A level gap the route doesn't carry you over ends it, unless bridge
-- is set: then the gap is XP to earn on the way, and the zone is still there on the other side of it.
-- Returns { [quest] = true }, how many, what they pay at your level, and the XP to earn in gaps.
-- XP a minute from kills alone, rest included: a kill and the walk to the next, as the build counts it,
-- and about 10 seconds' rest (Classic's XP for a mob of your level).
local function KillPace(level)
    local seconds = 28 + 17 * math.max(0, math.min(55, level - 5)) / 55
    return (45 + 5 * level) * 60 / seconds
end

local function Reachable(section, level, bridge)
    local list, seen = {}, {}
    for _, s in ipairs(section.steps) do
        local id = s[2]
        if s[1] == "A" and not seen[id] then
            seen[id] = true
            local q = Q(id)
            if q and not q.dq and E:QuestOpen(id) and not NeedsDungeon(id, 0) and DonationReady(q) then
                list[#list + 1] = id
            end
        end
    end
    table.sort(list, function(a, b)
        local x, y = Practical(Q(a)), Practical(Q(b))
        if x ~= y then return x < y end
        return a < b
    end)
    local set, count, xp, lv, bank, gaps, kills = {}, 0, 0, level, 0, 0, 0
    for _, id in ipairs(list) do
        local need = Practical(Q(id))
        if need > lv + GRIND_GAP and not bridge then break end
        -- (The route gains GRIND_GAP on its way; before its first quest there's nothing to gain it from.)
        local free = count > 0 and GRIND_GAP or 0
        while lv < need do
            if lv < 60 and need - lv > free then gaps = gaps + XP_TO_LEVEL[lv] - bank end
            lv, bank = lv + 1, 0
        end
        if lv >= 60 then break end
        local pays = QuestXP(Q(id), lv)
        if pays >= XP_TO_LEVEL[lv] * MIN_SHARE then
            set[id], count, xp = true, count + 1, xp + QuestXP(Q(id), level)
            bank = bank + QuestEarns(Q(id), lv)
            kills = kills + QuestEarns(Q(id), level) - QuestXP(Q(id), level)
            while lv < 60 and bank >= XP_TO_LEVEL[lv] do
                bank = bank - XP_TO_LEVEL[lv]
                lv = lv + 1
            end
        end
    end
    return set, count, xp, gaps, kills
end

-- Something on this list you could do right now.
local function HasWork(set, level)
    for id in pairs(set) do
        if Practical(Q(id)) <= level and PrereqsDone(Q(id)) then return true end
    end
    return false
end

E.BAND = 2           -- levels: a zone is judged by brackets this wide (see Value)
E.EXIT_SECONDS = 5   -- how long the choice of hand-off out of a zone is kept (PickExit)
E.GROUP_YARDS = 300  -- quest givers this close are one place: a bracket doesn't split them (E.Brackets)
E.EARLY_LOG = 15     -- quests in the log past which nothing's taken early (E.WithEarly)

-- A zone's quests in level brackets: { from, pays, minutes, ids } each. list: { id, l, pays, minutes }.
-- By level first, E.BAND wide from the lowest quest left. Then what belongs with them comes down from the
-- bracket above, so a town's quests or a chain aren't cut in two by a level: one you can take in this range
-- whose giver is by a giver already in (E.GROUP_YARDS), or that follows on from a quest already in.
function E.Brackets(list)
    table.sort(list, function(a, b)
        if a.l ~= b.l then return a.l < b.l end
        return a.id < b.id
    end)
    local WM, used, out = ns.WorldMap, {}, {}
    local function Spot(e)
        if e.c == nil then
            local a = Q(e.id).a
            e.c = false
            if a then e.c, e.n, e.w = WM.World(a[1], a[2] / 100, a[3] / 100) end
        end
        return e.c
    end
    local function Belongs(e, b)
        local q = Q(e.id)
        for _, p in ipairs(q.pre or {}) do
            if b.has[p] then return true end
        end
        if not Spot(e) then return false end
        for _, m in ipairs(b.members) do
            if Spot(m) == e.c then
                local dn, dw = m.n - e.n, m.w - e.w
                if dn * dn + dw * dw <= E.GROUP_YARDS * E.GROUP_YARDS then return true end
            end
        end
        return false
    end
    for i, first in ipairs(list) do
        if not used[i] then
            local start = first.l
            local b = { from = start, pays = 0, minutes = 0, members = {}, has = {}, ids = {} }
            local function Add(k, e)
                used[k] = true
                b.members[#b.members + 1], b.has[e.id], b.ids[#b.ids + 1] = e, true, e.id
                b.pays, b.minutes = b.pays + e.pays, b.minutes + e.minutes
            end
            for k = i, #list do
                if not used[k] and list[k].l < start + E.BAND then Add(k, list[k]) end
            end
            local grew = true
            while grew do
                grew = false
                for k = i, #list do
                    local e = list[k]
                    if e.l >= start + 2 * E.BAND then break end
                    if not used[k] and (Q(e.id).r or 1) < start + E.BAND and Belongs(e, b) then
                        Add(k, e)
                        grew = true
                    end
                end
            end
            out[#out + 1] = b
        end
    end
    return out
end

-- What a section is worth from where you are, in XP a minute. A zone is judged a level band at a time:
-- its quests left, from the lowest level up, in brackets E.BAND levels wide that start where the quests
-- do (Barrens 20-22, then 23-25): a range to attend, not levels you'll gain. Quests that belong together
-- stay together (E.Brackets). You stay around until it's done,
-- so its average is what it really pays, where its best quest alone would flatter it. The quests are
-- timed as the plan times them (QuestRate). A zone's worth is its best band you can do now:
--     the band's XP / (the walk there + the band's minutes)
-- One sum, in your zone or out of it, so nothing jumps as you cross a border, and a marginal gain never
-- takes you further: a zone further off has to pay better by as much as its walk costs. The sum a dungeon
-- has too (E:DungeonRate).
-- from: a data point for where you stand, or nil (no walk). Also returns the XP, the minutes of walking
-- and waiting, and the band's first and last levels.
local function Value(section, level, from)
    local set, count, xp, gaps, kills = Reachable(section, level, true)
    if count == 0 then return 0, 0, 0 end
    local first
    for _, s in ipairs(section.steps) do
        if s[1] == "A" and not first and set[s[2]] then first = Q(s[2]).a end
    end
    local walk = from and WalkMinutes(from, first) or 0
    -- Nothing to do there yet: anywhere with work beats it, wherever you're standing. The levels it
    -- would take count against it, at the pace kills alone earn.
    if not HasWork(set, level) then
        return WAITING_RATE * (xp + kills) / math.max(MIN_MINUTES, gaps / KillPace(level)), xp, walk
    end
    -- (Each timed from its own giver: the walk to the zone is one walk, counted once.)
    local list = {}
    for id in pairs(set) do
        local q = Q(id)
        if Practical(q) <= level + GRIND_GAP then
            local _, pays, minutes = E.QuestRate(id)
            if pays > 0 then list[#list + 1] = { id = id, l = q.l or level, pays = pays, minutes = minutes } end
        end
    end
    local best, from_, to = 0, nil, nil
    for _, b in ipairs(E.Brackets(list)) do
        local worth = b.pays / (walk + math.max(MIN_MINUTES, b.minutes))
        if worth > best then best, from_, to = worth, b.from, b.from + E.BAND end
    end
    return best, xp, walk, from_, to
end

-- What a dungeon's worth from where you are, in the same XP a minute as a zone: its quests and its
-- kills, over the trip to collect them and reach the entrance, and the run. No leg of it counts for
-- more than MAX_LEG, even over an ocean: by then you've boats and flight paths. entry: from I:Current.
-- Also returns the XP and the minutes.
function E:DungeonRate(entry)
    P = P or ns.Progress
    local level = P:Level()
    local x, y, map = ns.WorldMap.PlayerPos()
    local at = x and { map, x * 100, y * 100 } or nil
    local xp, stops = (45 + 5 * level) * RUN_KILL_XP, {}
    for _, id in ipairs(entry.open) do
        local q = Q(id)
        xp = xp + QuestXP(q, level) * DUNGEON_QUEST_PAY
        if q and q.a and not P:InLog(id) then stops[#stops + 1] = q.a end
    end
    -- The givers, farthest from the entrance first, ending there: the way the route goes.
    local minutes, entrance = GROUP_MINUTES + RUN_MINUTES, entry.inst.entrance
    local function Leg(from, to) return from and to and math.min(MAX_LEG, WalkMinutes(from, to)) or 0 end
    table.sort(stops, function(p, r) return Leg(p, entrance) > Leg(r, entrance) end)
    for _, spot in ipairs(stops) do
        minutes = minutes + Leg(at, spot)
        at = spot
    end
    minutes = minutes + Leg(at, entrance)
    return xp / minutes, xp, minutes
end

-- What questing where you are pays, in the same XP a minute.
function E:QuestingRate()
    local s = self.section
    if not s or s.instance or s.travel then return 0 end
    return (Value(s, P:Level()))
end

-- A quest that costs too much time for what it does for your level: the share of a level it pays, per
-- hour of doing it (QuestRate, which counts its walking and its objectives). The size of a quest says
-- nothing alone: a small quick one is good, a big slow one is the most time you can lose. Nothing still
-- open may come after it: what leads on is judged by what it leads to.
-- Only for what you'd pick up: one already in your log stays, or the route goes back and forth for it.
E.SLOW_RATE = 0.15 -- share of a level an hour: 4 minutes for each 1% of a level
function E.TooSlow(id, level)
    if not E.leadsTo then
        E.leadsTo = {}
        for other, q in pairs(ns.Quests) do
            for _, p in ipairs(q.pre or {}) do
                E.leadsTo[p] = E.leadsTo[p] or {}
                table.insert(E.leadsTo[p], other)
            end
        end
    end
    local rate = E.QuestRate(id)
    if rate <= 0 or rate >= E.SLOW_RATE then return false end
    for _, other in ipairs(E.leadsTo[id] or {}) do
        if E:QuestOpen(other) and not E.TooSlow(other, level) then return false end
    end
    return true
end

-- Which of a section's quests to show: those you'd really get to (see Reachable), those in your log,
-- and anything a shown quest needs first.
local function Shown(section, level)
    local show = {}
    if section.instance then
        -- A dungeon's quests are the reason for the trip: all of them show.
        for _, s in ipairs(section.steps) do show[s[2]] = true end
        return show
    end
    local function Need(id, depth)
        local q = Q(id)
        if not q or not q.pre or depth > 25 then return end
        for _, p in ipairs(q.pre) do
            if not show[p] and not (Q(p) and Q(p).dq) then
                show[p] = true
                Need(p, depth + 1)
            end
        end
    end
    if section.zoneClear then
        -- Zone Clear: every quest, whatever it pays (but not a dungeon's, nor one that needs one, and a
        -- cloth donation only with the cloth in your bags).
        for _, s in ipairs(section.steps) do
            local id = s[2]
            if s[1] == "A" and not show[id] and not (Q(id) and Q(id).dq) and not NeedsDungeon(id, 0)
                and (DonationReady(Q(id)) or P:InLog(id)) then
                show[id] = true
                Need(id, 0)
            end
        end
        return show
    end
    local reachable = Reachable(section, level, true)
    for _, s in ipairs(section.steps) do
        local id = s[2]
        if s[1] == "A" and not show[id] and not (Q(id) and Q(id).dq) and not NeedsDungeon(id, 0)
            and (P:InLog(id) or (reachable[id] and not E.TooSlow(id, level))) then
            show[id] = true
            Need(id, 0)
        end
    end
    return show
end

-- ---------------------------------------------------------------------------------------------
-- Moving on to the next zone
-- ---------------------------------------------------------------------------------------------

-- The section in a zone that suits a level best (in range, lowest Score), or nil.
local function SectionFor(guide, zone, level)
    local best
    for _, s in ipairs(guide.sections) do
        if s.zone == zone and InRange(s, level) and (not best or Score(s, level) < Score(best, level)) then best = s end
    end
    return best
end

-- The hand-off quest out of a zone for a level: one already in your log, else the one you can
-- take that leads to the zone that pays best from its giver, by the measure every zone is weighed with
-- (Value): what the zone pays, walk included. Not by whether its levels fit: a zone can fit and be a
-- long way off for less.
local function PickExit(guide, zone, level)
    local list = guide and guide.exits and guide.exits[zone]
    if not list then return nil end
    -- (Weighing zones isn't cheap, and this is asked every time the list is built: the answer only
    -- changes with your level or your log, so it's kept a few seconds.)
    E.exitMemo = E.exitMemo or {}
    local key = table.concat({ level, #P:LogQuests(), math.floor(GetTime() / E.EXIT_SECONDS) }, ":")
    local kept = E.exitMemo[zone]
    if kept and kept.key == key then return kept.exit or nil end
    local best, bestWorth
    for _, e in ipairs(list) do
        local id, q = e[1], Q(e[1])
        if q and q.dq then
            -- a dungeon's quest is never a way out of a zone
        elseif q and P:InLog(id) then
            E.exitMemo[zone] = { key = key, exit = e }
            return e
        -- (Taken now, so within reach of the level you are now, whatever level it's chosen for.)
        elseif q and Practical(q) <= level and E:QuestOpen(id) and PrereqsDone(q) then
            local s = SectionFor(guide, e[2], level)
            local worth = s and (Value(s, level, q.a))
            if worth and (not best or worth > bestWorth) then best, bestWorth = e, worth end
        end
    end
    E.exitMemo[zone] = { key = key, exit = best or false }
    return best
end

local function ExitSteps(e, steps)
    local id = e[1]
    steps[#steps + 1] = { "A", id, exit = true }
    if Q(id).o then steps[#steps + 1] = { "O", id, exit = true } end
    steps[#steps + 1] = { "Z", e[2] }
    steps[#steps + 1] = { "T", id, exit = true }
    return steps
end

-- A quest in your log that isn't on the zone's route joins it if finishing it pays what the route does,
-- all of it counted, wherever the rest of it is (QuestRate). Looked at again as you go, so one you come
-- near gets in; once in, it stays until it's out of your log: a route that dropped it would be changing
-- its mind. Zone Clear takes everything.
function E.Carried(section, id)
    if section.zoneClear then return true end
    ns.char.carried = ns.char.carried or {}
    if ns.char.carried[id] then return true end
    local c, n, w = ns.WorldMap.Player()
    if not c then return false end
    local _, pays, minutes = E.QuestRate(id, { c, n, w })
    if minutes > 0 and pays / minutes >= Value(section, P:Level()) then
        ns.char.carried[id] = true
        return true
    end
    return false
end

-- Quests in your log that aren't part of the zone's route (a hand-off that brought you here, one
-- picked up elsewhere, or one you took on your way): the guide works from the path you're on, so
-- their objectives here and their turn-ins here join the route, when they're worth it (E.Carried).
local function TurnInsHere(section, inSection, steps)
    for id in pairs(ns.char.carried or {}) do
        if not P:InLog(id) then ns.char.carried[id] = nil end
    end
    for _, id in ipairs(P:LogQuests()) do
        local q = Q(id)
        -- Ready: its objectives are done, or it has none (the game's word; Questie's spots only
        -- when the game can't say, since a quest done inside a dungeon has none outside).
        local none = P:NoObjectives(id)
        local ready = P:ReadyToTurnIn(id) or none == true or (none == nil and not q.o)
        local here = q and not q.dq and not inSection[id]
            and ((not ready and q.o and q.o[1][1] == section.zone) or (ready and q.t and q.t[1] == section.zone))
        if here and E.Carried(section, id) then
            if not ready and q.o and q.o[1][1] == section.zone then
                steps[#steps + 1] = { "O", id }
                inSection[id] = true
            end
            if q.t and q.t[1] == section.zone and (ready or inSection[id]) then
                steps[#steps + 1] = { "T", id }
                inSection[id] = true
            end
        end
    end
end

-- The section's steps worth doing, after the quests they need that come from somewhere else.
local function Build(section)
    if section.travel then return section.steps end
    local level = P:Level()
    local show = Shown(section, level)
    local inSection, steps = {}, {}
    for _, s in ipairs(section.steps) do
        if s[1] ~= "G" and s[1] ~= "Z" and s[1] ~= "I" then inSection[s[2]] = true end
    end
    if not section.instance then TurnInsHere(section, inSection, steps) end
    local missing, seen, routeRate = {}, {}, nil
    for _, s in ipairs(section.steps) do
        -- (Not for a quest you can't get yet: its missing part may only drop inside a dungeon.)
        if s[1] == "A" and show[s[2]] and not Unavailable(s[2]) and not P:InLog(s[2]) then
            -- What it needs first, on its own: routed to only when every quest in it needs at most
            -- CATCHUP levels over yours. Otherwise the quest waits too (it can't be done before them).
            local chain, mine = {}, {}
            for id in pairs(seen) do mine[id] = true end
            Missing(s[2], chain, mine, 0, inSection)
            local near = true
            -- The trip back for them has to pay what the route does: there and back, against what
            -- they and this quest pay.
            local trip, pays = 0, QuestEarns(Q(s[2]), level)
            for _, id in ipairs(chain) do
                if Practical(Q(id)) > level + CATCHUP then near = false; break end
                if not inSection[id] then
                    trip = trip + 2 * WalkMinutes(Q(s[2]).a, Q(id).a)
                    pays = pays + QuestEarns(Q(id), level)
                end
            end
            routeRate = routeRate or Value(section, level)
            if trip > 0 and pays / trip < routeRate then near = false end
            -- Needs something first, and there's nothing the guide can send you to.
            local stuck = #chain == 0 and not PrereqsDone(Q(s[2]))
            if (near or section.zoneClear) and not stuck then -- (Zone Clear fetches them wherever they are)
                for _, id in ipairs(chain) do
                    seen[id] = true
                    missing[#missing + 1] = id
                end
            else
                show[s[2]] = nil
            end
        end
    end
    for _, id in ipairs(missing) do
        if not inSection[id] and not (section.instance == nil and Q(id).dq) then
            -- Started by an item: loot it where it drops instead of picking it up.
            steps[#steps + 1] = { Q(id).ia and "L" or "A", id, catchup = true }
            if Q(id).o then steps[#steps + 1] = { "O", id, catchup = true } end
            steps[#steps + 1] = { "T", id, catchup = true }
        end
    end
    for _, s in ipairs(section.steps) do
        local farm = s[1] == "O" and DonationCloth(Q(s[2])) -- a donation's "Do": the cloth is in your bags
        if s[1] == "G" or s[1] == "Z" or s[1] == "I" or (show[s[2]] and not farm) then steps[#steps + 1] = s end
    end
    -- The zone ends with the hand-off to the next zone for the level you'll have by then.
    if not section.instance then
        local e = PickExit(E.guide, section.zone, math.max(level, section.to or level))
        -- Zone Clear: they're the zone's quests too: all of them, the one leading on last.
        if section.zoneClear then
            for _, other in ipairs(E.guide and E.guide.exits and E.guide.exits[section.zone] or {}) do
                local q = Q(other[1])
                if other ~= e and q and not q.dq and not inSection[other[1]] and (P:InLog(other[1]) or E:QuestOpen(other[1])) then
                    inSection[other[1]] = true
                    ExitSteps(other, steps)
                end
            end
        end
        if e and not inSection[e[1]] then ExitSteps(e, steps) end
    end
    -- Zone Clear: the quests above your level wait at the end ("later": they don't hold the zone).
    -- Before them, what you skipped once ("last"): to do, but after everything else. With nothing
    -- else left they're an ordinary route, in the order that walks best.
    if section.zoneClear then
        local now, last, later, others = {}, {}, {}, false
        for _, s in ipairs(steps) do
            local q = s[1] ~= "G" and s[1] ~= "Z" and s[1] ~= "I" and Q(s[2])
            if q and Practical(q) > level and not P:InLog(s[2]) then
                later[#later + 1] = { s[1], s[2], later = true, catchup = s.catchup, exit = s.exit }
            elseif q and ns.char.deferred[s[2]] then
                last[#last + 1] = s
            else
                now[#now + 1] = s
                others = others or (q and not E:StepDone(s))
            end
        end
        for _, s in ipairs(last) do
            if others then
                local copy = {}
                for k, v in pairs(s) do copy[k] = v end
                copy.last = true
                s = copy
            end
            now[#now + 1] = s
        end
        for _, s in ipairs(later) do now[#now + 1] = s end
        steps = now
    end
    -- A zone change with nothing after it (its quests were left out at your level) goes too:
    -- otherwise a section of nothing but "Go to ..." would look like it had work left.
    local kept = {}
    for i, s in ipairs(steps) do
        local nxt = steps[i + 1]
        if s[1] ~= "Z" or (nxt and nxt[1] ~= "Z") then kept[#kept + 1] = s end
    end
    return E.SplitParts(kept)
end

-- The zone you're in (a city or cave counts as the zone around it).
local function CurrentZone()
    local map = C_Map.GetBestMapForUnit("player")
    for _ = 1, 5 do
        local info = map and C_Map.GetMapInfo(map)
        if not info then return map end
        if not Enum.UIMapType or info.mapType <= Enum.UIMapType.Zone then return map end
        map = info.parentMapID
    end
    return map
end

-- A step you can't act on yet: its quest isn't in your log, and it's too high for you or what it
-- needs first isn't done. A dungeon's route keeps its own order.
-- A quest of a higher bracket taken early (E.WithEarly): its objectives and hand-in wait for its level.
function E.Early(s) return s[1] ~= "A" and ns.char.early ~= nil and ns.char.early[s[2]] == true end

local function Waits(s)
    if ns.char.instance or s[1] == "G" or s[1] == "Z" or s[1] == "I" then return false end
    if s[1] == "T" and E.hunting[s[2]] and not P:ReadyToTurnIn(s[2]) then return true end
    local q = Q(s[2])
    if s.early then return false end
    if E.Early(s) and q and Practical(q) > P:Level() and not P:ReadyToTurnIn(s[2]) then return true end
    if not q or P:InLog(s[2]) or P:Done(s[2]) then return false end
    return Practical(q) > P:Level() or not PrereqsDone(q)
end
E.Waits = function(_, s) return Waits(s) end

-- The first step left, passing over those that wait; with only those left, the first of them (it
-- says what level it needs, and the zone doesn't look finished). A zone change counts as done once
-- a step after it is, or once you're there.
local function FirstLeft(steps)
    local waiting
    E.farming = nil
    for i, s in ipairs(steps) do
        if s.later or E:MovedOn(s) then
            -- Zone Clear's quests above your level: listed, but nothing to do yet.
        elseif s[1] == "Z" then
            local after = steps[i + 1]
            if after and not E:StepDone(after) and not Waits(after) then
                if CurrentZone() ~= s[2] and C_Map.GetBestMapForUnit("player") ~= s[2] then return i end
            end
        elseif not E:StepDone(s) then
            if not Waits(s) then return i end
            waiting = waiting or i
        end
    end
    return waiting
end

local function Remaining(section)
    return FirstLeft(Build(section)) ~= nil
end

-- Yards from you to the middle of a zone, if it's on your continent.
-- (shared WorldMap.lua)
local function DistanceTo(zone) return ns.WorldMap.DistanceTo(zone, 0.5, 0.5) end

local lastPick

-- A section for your level: in range (see RANGE), with something still worth doing.
local function Fits(s, level)
    return InRange(s, level) and Remaining(s)
end

-- The pick only changes when something it depends on does (zone, level, quests taken or handed
-- in); objective progress just moves you along the steps.
local pickDirty = true
function E:Invalidate() pickDirty = true; detourCache = nil end

local relocate = true -- you may be anywhere (login, Play): the next choices start from where you stand
local logReady = false -- the game has given us your quest log since login (LogIsIn)
local holdKey         -- the step you're on: it stays yours until it's done or you skip it
local holdStep        -- that step

-- The step you're on is still to do in this section.
local function Holding(section)
    if relocate or not holdKey or not section then return false end
    -- On your way to another zone: the zones you cross don't change the plan.
    if holdKey:sub(1, 2) == "Z:" then return true end
    for _, s in ipairs(E.planSteps or Build(section)) do
        if StepKey(s) == holdKey then return not E:StepDone(s) and not Waits(s) end
    end
    return false
end

-- You skipped a trip while still in the zone: { zone, section }, and the guide stays in that zone
-- for as long as you do (see E:SkipTravel).
local stay
local trip -- the trip you're on: { key = its step, from = the zone it started in }

local travel -- the section that hands you off from a zone that's done for your level
local Touching   -- do two zones touch? (below)
local offer      -- a far zone that's waiting for your answer: { section, rate, here, level }
local moveOk     -- the section you said to go to
local declinedAt -- the level it was last asked at (Stay here: not asked again until you level up)
local moved -- why Leveling just left a zone: { from, from's XP a minute, to's } (for the chat line)

-- No zone has work left for your level, but quests can still be open off the routes: ones the planner
-- dropped, a zone's leftovers, a zone you've outgrown. The zone paying most for the trip, as a short list.
local function LooseEnds(level, spot)
    local zones, seen = {}, {}
    for id, q in pairs(ns.Quests) do
        if q.a and not q.dq and not seen[q.n] and E:QuestOpen(id) and not P:InLog(id) and Practical(q) <= level
            and PrereqsDone(q) and Worth(id, level) and not NeedsDungeon(id, 0) and DonationReady(q) then
            seen[q.n] = true
            local z = q.a[1]
            zones[z] = zones[z] or { pays = 0, quests = {} }
            zones[z].pays = zones[z].pays + QuestEarns(q, level)
            table.insert(zones[z].quests, id)
        end
    end
    local best, bestRate
    for z, list in pairs(zones) do
        table.sort(list.quests)
        local rate = list.pays / (WalkMinutes(spot, Q(list.quests[1]).a) + #list.quests * LOOSE_MINUTES)
        if not best or rate > bestRate or (rate == bestRate and z < best) then best, bestRate = z, rate end
    end
    if not best then return nil end
    local steps = { { "Z", best } }
    for i, id in ipairs(zones[best].quests) do
        if i > LOOSE_QUESTS then break end
        steps[#steps + 1] = { "A", id }
        if Q(id).o then steps[#steps + 1] = { "O", id } end
        steps[#steps + 1] = { "T", id }
    end
    local info = C_Map.GetMapInfo(best)
    return { id = "loose-" .. best, travel = true, loose = true, zone = best, from = level, to = level, steps = steps,
        title = info and info.name or "Loose ends",
        note = "The routes have nothing left for your level, so these are the best quests still open." }
end

-- The brackets of a section at your level, for the tests: "from: quest levels" each.
function E.BracketText(section)
    local level, list = P:Level(), {}
    for id in pairs((Reachable(section, level, true))) do
        local q = Q(id)
        local _, pays, minutes = E.QuestRate(id)
        list[#list + 1] = { id = id, l = q.l or level, pays = pays, minutes = minutes }
    end
    local out = {}
    for _, b in ipairs(E.Brackets(list)) do
        local ls = {}
        for i, id in ipairs(b.ids) do ls[i] = Q(id).l or 0 end
        out[#out + 1] = b.from .. "-" .. (b.from + E.BAND) .. ": " .. table.concat(ls, " ")
    end
    return table.concat(out, " | ")
end

-- A section's worth from where you stand (the tests, and /fg why).
function E.ValueOf(section)
    local x, y, map = ns.WorldMap.PlayerPos()
    if not Fits(section, P:Level()) then return 0 end
    return Value(section, P:Level(), x and { map, x * 100, y * 100 } or nil)
end

function E:PickSection(guide)
    lastPick = lastPick or ns.char.lastPick -- the zone you were on, across a /reload
    if stay and stay.section then
        pickDirty = false
        return stay.section
    end
    if not pickDirty and lastPick then
        if travel and travel.id == lastPick and Remaining(travel) then return travel end
        for _, s in ipairs(Sections(guide)) do
            if s.id == lastPick and Remaining(s) then return s end
        end
    end
    if ns.char.section then
        pickDirty = false
        for _, s in ipairs(guide.sections) do
            if s.id == ns.char.section then return AsPicked(guide, s) end
        end
    end
    -- On a flight: nothing changes until you land.
    if lastPick and UnitOnTaxi and UnitOnTaxi("player") then
        if travel and travel.id == lastPick then return travel end
        for _, s in ipairs(Sections(guide)) do
            if s.id == lastPick then return s end
        end
    end
    pickDirty = false
    local level, zone = P:Level(), CurrentZone()
    local current, here
    moved = nil
    for _, s in ipairs(Sections(guide)) do
        if s.id == lastPick then current = s end
        if s.zone == zone and not here and InRange(s, level) then here = s end
    end
    -- Still asking the server which quests exist: a zone whose quests aren't answered for yet only
    -- looks empty. Hold where you are and choose once the answers are in.
    if ns.Exists:Busy() then
        pickDirty = true
        return here or current
    end
    -- Zone Clear: the zone you're on stays until it's cleared, even while you're off fetching what
    -- its quests need first, and the zone you walk into is next.
    if Clearing() then
        if current and Fits(current, level) then return current end
        for _, s in ipairs(Sections(guide)) do
            if s.zone == zone and Fits(s, level) then return s end
        end
    end
    -- The step you're on stays yours, whatever you handed in or wherever that took you: zones are
    -- weighed when it's done, or when you've been away.
    if travel and travel.id == lastPick and holdKey and holdKey:sub(1, 2) == "Z:" and not relocate then return travel end
    if Holding(current) then return current end
    -- (A short list of loose ends is worked through before anything's weighed again.)
    if travel and travel.loose and travel.id == lastPick and Remaining(travel) and not relocate then return travel end
    -- Every zone, the same way: XP a minute from where you stand, the walk included.
    local x, y, map = ns.WorldMap.PlayerPos()
    local spot = x and { map, x * 100, y * 100 } or { zone, 50, 50 }
    local best, bestRate, currentRate
    local function Weigh()
        best, bestRate, currentRate = nil, 0, 0
        for _, s in ipairs(Sections(guide)) do
            if Fits(s, level) then
                local rate = Value(s, level, spot)
                if s == current then
                    currentRate = rate
                    rate = rate * STAY_EDGE
                end
                if rate > bestRate then best, bestRate = s, rate end
            end
        end
        if best and HasWork((Reachable(best, level, true)), level) then return true end
        -- Nothing to do anywhere on the routes: take what's still open anywhere else.
        local loose = LooseEnds(level, spot)
        if loose then best = loose end
        return loose ~= nil
    end
    -- Still nothing: the game may well offer quests a little above you, and those beat waiting for a level.
    reach = 0
    while not Weigh() and reach < MAX_REACH do reach = reach + 1 end
    if not best then return nil end
    -- A long way to somewhere that doesn't touch where you are: that's yours to decide.
    local there = current or here
    local _, _, trip = Value(best, level, spot)
    if best ~= current and best.zone ~= zone and trip >= LONG_TRIP and moveOk ~= best.id
        and not (there and Touching(there, best)) and StaticPopup_Show then
        if declinedAt ~= level then
            declinedAt = level
            offer = { section = best, rate = bestRate, here = there, level = level }
            C_Timer.After(0, function() E:OfferMove() end)
        end
        return there
    end
    if best.loose then
        travel = best
        return best
    end
    if current and best ~= current then moved = { from = current, fromRate = currentRate, toRate = bestRate } end
    -- A quest that takes you there is the way to go, unless there's work around the way there: then
    -- that's the plan's to weigh. (A hand-off goes round the plan, which would turn back to that work
    -- as soon as you came near it.)
    local onTheWay = false
    for _, s in ipairs(Sections(guide)) do
        if s ~= best and s.zone ~= best.zone and s.zone ~= zone and Touching(best, s) and Fits(s, level)
            and HasWork((Reachable(s, level, true)), level) then
            onTheWay = true
            break
        end
    end
    if best.zone ~= zone and not onTheWay then
        local e = PickExit(guide, zone, level)
        if e and e[2] == best.zone then
            local mapInfo = C_Map.GetMapInfo(e[2])
            local name = mapInfo and mapInfo.name or "the next zone"
            travel = { id = "exit-" .. e[1], travel = true, zone = zone, from = level, to = level,
                title = "On to " .. name, steps = ExitSteps(e, {}),
                note = ("%s takes you on to %s, where the quests pay best for level %d."):format(Q(e[1]).n or "A quest", name, level) }
            return travel
        end
    end
    return best
end

-- What the guide thinks of a section's quests: how many are in each state, with the first few IDs.
local function QuestStates(s)
    local K = ns.QuestieKit
    local states, seen = {}, {}
    local function Add(name, id)
        local st = states[name]
        if not st then st = { n = 0, ids = {} }; states[name] = st end
        st.n = st.n + 1
        if #st.ids < 6 then st.ids[#st.ids + 1] = id end
    end
    for _, step in ipairs(s.steps) do
        local id, q = step[2], step[1] == "A" and Q(step[2])
        if q and not seen[id] then
            seen[id] = true
            if K.IsDone(id) then Add("finished", id)
            elseif P:Done(id) then Add("inferred", id)
            elseif P:InLog(id) then Add("log", id)
            elseif ns.char.ignored[id] then Add("skipped", id)
            elseif ns.char.notOffered[id] then Add("notOffered", id)
            elseif ns.Exists:Missing(id) then Add("noServer", id)
            elseif ns.Exists:Pending(id) then Add("pending", id)
            elseif not P:RaceAllowed(q.rm) then Add("race", id)
            elseif Unreachable(q, 0) then Add("unreachable", id)
            elseif PrereqsDone(q) and not P:Doable(id) then Add("questieNo", id)
            elseif not PrereqsDone(q) then Add("needsFirst", id)
            elseif Practical(q) > P:Level() then Add("tooHigh", id)
            else Add("open", id) end
        end
    end
    local names, out = {}, {}
    for name in pairs(states) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        out[#out + 1] = ("%s %d (%s)"):format(name, states[name].n, table.concat(states[name].ids, ","))
    end
    return table.concat(out, "; ")
end

-- Why the guide is where it is: your state, then what it sees in your zone's sections and the
-- section it picked. For /fg why, and saved in ns.char.whyLog when it picks a section elsewhere.
function E:Why()
    P = P or ns.Progress
    local guide, level, zone = self:Guide(), P:Level(), CurrentZone()
    local _, _, race = P:Race()
    local section = self.section
    local lines = { ("level %d, race %s, zone %s, picked %s, lastPick %s, %s, lookup %s, busy %s"):format(level,
        tostring(race), tostring(zone), section and section.id or "none", tostring(ns.char.lastPick),
        tostring(ns.char.preference),
        ns.Exists:Broken() and "off" or "on", tostring(ns.Exists:Busy())) }
    for _, s in ipairs(guide and guide.sections or {}) do
        if s.zone == zone or (section and s.id == section.id) then
            local rate, xp, walk, band, bandTo = Value(s, level, { zone, 50, 50 })
            lines[#lines + 1] = ("%s: fits %s, %d XP a minute%s (%d XP, %d min walk): %s"):format(s.id,
                tostring(Fits(s, level)), math.floor(rate), band and (", levels %d-%d"):format(band, bandTo) or "",
                math.floor(xp), math.floor(walk), QuestStates(s))
        end
    end
    lines[#lines + 1] = ("questing here: %d XP a minute"):format(math.floor(self:QuestingRate()))
    for _, entry in ipairs(ns.Instance.Current and ns.Instance:Current() or {}) do
        local rate, xp, minutes = self:DungeonRate(entry)
        lines[#lines + 1] = ("%s: %d XP a minute (%d XP, %d min)"):format(entry.inst.name, math.floor(rate), math.floor(xp), math.floor(minutes))
    end
    for i = 1, math.min(5, self.ranked and #self.ranked or 0) do
        local r = self.ranked[i]
        lines[#lines + 1] = ("%d. %s: %d%% of a level an hour (%d XP, %.1f min)"):format(i, self:QuestName(r.id),
            math.floor(r.rate * 100), math.floor(r.xp), r.minutes)
    end
    return lines
end

-- Natural transition (Leveling): a zone doesn't hold you. Zones that touch know each other's quests,
-- whichever of them you're in, so their plans are made from the same picture and agree: when one runs
-- short for your level the plan fills the gap from the next, and it knows to come back, because the
-- zone it came from is on the plan there too. They all compete on the same XP an hour. Zone Clear
-- stays on its zone.
local near -- { section = id, list = { section, ... } }: worked out when the plan is

-- The world area of a section's quest givers: { continent, north, south, west, east }. Kept on the section.
local function QuestArea(section)
    if section.area ~= nil then return section.area end
    local box = false
    for _, st in ipairs(section.steps) do
        local q = st[1] == "A" and Q(st[2])
        local c, n, w
        if q and q.a then c, n, w = ns.WorldMap.World(q.a[1], q.a[2] / 100, q.a[3] / 100) end
        if c then
            if not box then
                box = { c, n, n, w, w }
            elseif box[1] == c then
                box[2], box[3] = math.max(box[2], n), math.min(box[3], n)
                box[4], box[5] = math.max(box[4], w), math.min(box[5], w)
            end
        end
    end
    section.area = box
    return box
end

-- Two zones touch when their quest areas come within TOUCHING_YARDS. It goes both ways, and it doesn't
-- depend on where you are.
Touching = function(a, b)
    local x, y = QuestArea(a), QuestArea(b)
    if not (x and y) or x[1] ~= y[1] then return false end
    local dn = math.max(0, y[3] - x[2], x[3] - y[2])
    local dw = math.max(0, y[5] - x[4], x[5] - y[4])
    return dn * dn + dw * dw <= TOUCHING_YARDS * TOUCHING_YARDS
end

local function FindNeighbours(section, guide)
    local list = {}
    local level = P:Level()
    for _, s in ipairs(guide.sections) do
        if s ~= section and s.zone ~= section.zone and Touching(section, s) and Fits(s, level) then
            list[#list + 1] = s
        end
    end
    return list
end

local function WithNeighbours(section, steps, guide)
    if Clearing() or not section or section.instance or section.travel or section.zoneClear or stay then return steps end
    if pickDirty or not near or near.section ~= section.id or relocate then
        near = { section = section.id, list = FindNeighbours(section, guide) }
    end
    local seen, out = {}, {}
    for _, s in ipairs(steps) do
        out[#out + 1] = s
        seen[StepKey(s)] = true
    end
    for _, n in ipairs(near.list) do
        for _, s in ipairs(Build(n)) do
            if s[1] ~= "Z" and s[1] ~= "G" and not seen[StepKey(s)] then
                seen[StepKey(s)] = true
                out[#out + 1] = s
            end
        end
    end
    -- The step you're on stays on the list wherever it came from, even if its zone has dropped out of
    -- the plan, and the rest of its quest with it.
    for _, mine in ipairs({ holdKey or false, trip and trip.target or false }) do
        if mine and not seen[mine] and mine:sub(1, 2) ~= "Z:" then
            local found
            for _, sec in ipairs(guide.sections) do
                for _, s in ipairs(sec.steps) do
                    if StepKey(s) == mine then found = sec end
                end
                if found then break end
            end
            if found then
                local id = tonumber(mine:match(":(%d+)"))
                for _, s in ipairs(found.steps) do
                    if s[2] == id and s[1] ~= "G" and s[1] ~= "Z" and not seen[StepKey(s)] then
                        seen[StepKey(s)] = true
                        out[#out + 1] = s
                    end
                end
            -- (A hand-off to the next zone isn't on any section's route: the step itself is kept.)
            elseif holdStep and StepKey(holdStep) == mine then
                seen[mine] = true
                out[#out + 1] = holdStep
            elseif trip and trip.step and StepKey(trip.step) == mine then
                seen[mine] = true
                out[#out + 1] = trip.step
            end
        end
    end
    return out
end

-- Asking before a long trip. Says when this zone has more for you, if it does.
StaticPopupDialogs["FIELDGUIDE_MOVE"] = {
    text = "%s", button1 = "Take me there", button2 = "Stay here",
    OnAccept = function() E:AcceptMove() end,
    timeout = 0, whileDead = 1, preferredIndex = 3,
}

function E:OfferMove()
    if not offer then return end
    local level, next = offer.level, nil
    for _, s in ipairs(offer.here and offer.here.steps or {}) do
        local q = s[1] == "A" and Q(s[2])
        if q and self:QuestOpen(s[2]) and Practical(q) > level and (not next or Practical(q) < next) then next = Practical(q) end
    end
    -- (The zones' own names, without a section's level: "Teldrassil", not "Teldrassil 1".)
    local function ZoneName(s)
        local info = s and C_Map.GetMapInfo(s.zone)
        return info and info.name or "here"
    end
    StaticPopup_Show("FIELDGUIDE_MOVE", ("There are no more quests for you around %s for now.%s\n\nThe best option right now is %s. Travel there?"):format(
        ZoneName(offer.here), next and (" More open up here at level %d."):format(next) or "", ZoneName(offer.section)))
end

function E:AcceptMove()
    if offer then moveOk = offer.section.id end
    offer, pickDirty, relocate, holdKey = nil, true, true, nil
    ns:Changed()
end

-- ---------------------------------------------------------------------------------------------
-- Leveling's detours
-- ---------------------------------------------------------------------------------------------

-- A quick quest off the route: one with nothing to do but hand it in (a delivery, "talk to ...",
-- an auto turn-in), taken on the way when the extra walk to its giver and to whoever takes it
-- costs at most db.detourMinutes, and it pays at least the route's usual XP per minute. One you
-- carry already only needs the hand-in. Worked out for the section you follow (never for the
-- sections Automatic weighs), again when the pick changes (see Invalidate).
local RUN_SPEED = 7     -- yards a second, on foot
local MAX_DETOURS = 5
local MIN_DETOUR = 0.25 -- minutes: talking to the giver and whoever takes it costs this much anyway
local SAME_SPOT = 15    -- yards: a giver who takes the quest back right there

local byMap -- giver's uiMapID -> { questID, ... } (quests with nothing to do but hand them in)
local function QuestsOn(map)
    if not byMap then
        byMap = {}
        for id, q in pairs(ns.Quests) do
            if q.talk and q.a and q.t and not q.dq then
                local list = byMap[q.a[1]]
                if not list then list = {}; byMap[q.a[1]] = list end
                list[#list + 1] = id
            end
        end
    end
    return byMap[map] or {}
end

-- A quest data point { uiMapID, x, y (0-100) } in the world: { continent, north, west } (cached
-- on the point), or nil.
local function World(p)
    if not p then return nil end
    if p._c == nil then
        local c, n, w = ns.WorldMap.World(p[1], p[2] / 100, p[3] / 100)
        p._c, p._n, p._w = c or false, n, w
    end
    if p._c then return { p._c, p._n, p._w } end
end

local function Yards(a, b)
    if not (a and b) then return nil end
    return ns.WorldMap.Distance(a[1], a[2], a[3], b[1], b[2], b[3])
end

-- The way from a to b through the exits of the areas it leaves and enters, when one of them has only
-- one or two ways in (Guides\Gates.lua), or nil.
local function ThroughExits(a, b)
    local map = ns.QuestGates and ns.QuestGates[a[1]]
    if not map then return nil end
    local function Area(p)
        return map.of[math.floor((map.max - p[2]) / map.cell) * 1024 + math.floor((map.max - p[3]) / map.cell)]
    end
    local from, to = Area(a), Area(b)
    if from == to then return nil end
    local best
    local function Try(yards)
        if yards and (not best or yards < best) then best = yards end
    end
    local function Point(e) return { a[1], e[1], e[2] } end
    for _, x in ipairs(from and map.exits[from] or { false }) do
        for _, y in ipairs(to and map.exits[to] or { false }) do
            local px, py = x and Point(x), y and Point(y)
            if px and py then
                Try(Yards(a, px) + Yards(px, py) + Yards(py, b))
            elseif px then
                Try(Yards(a, px) + Yards(px, b))
            elseif py then
                Try(Yards(a, py) + Yards(py, b))
            end
        end
    end
    return best
end

-- The walk from a to b, for putting a route in order: the real one where a straight line is badly
-- wrong (the only way down from a mesa, Guides\Walks.lua), else through the exits between them
-- (ThroughExits), else the straight line. You aren't on a quest point: a stands in for the nearest
-- one within WALK_RING squares.
local WALK_RING = 3
local function Walked(a, b)
    local straight = Yards(a, b)
    local map = straight and a[1] == b[1] and ns.QuestWalks and ns.QuestWalks[a[1]]
    if not map then return straight end
    local cell, max = map.cell, map.max
    -- (The quest points around a spot, nearest first, found once: a plan asks thousands of times.)
    local near = a.walks
    if not near then
        near = {}
        local rows = map.rows
        local r0, c0 = math.floor((max - a[2]) / cell), math.floor((max - a[3]) / cell)
        for ring = 0, WALK_RING do
            for dr = -ring, ring do
                for dc = -ring, ring do
                    if ring == 0 or math.abs(dr) == ring or math.abs(dc) == ring then
                        local row = rows[(r0 + dr) * 1024 + c0 + dc]
                        if row then near[#near + 1] = row end
                    end
                end
            end
        end
        a.walks = near
    end
    local to = math.floor((max - b[2]) / cell) * 1024 + math.floor((max - b[3]) / cell)
    for i = 1, #near do
        local real = near[i][to]
        if real then return math.max(real, straight) end
    end
    return math.max(ThroughExits(a, b) or 0, straight)
end

-- Where a step takes you, in the world, or nil.
local function StepSpot(step)
    local kind = step[1]
    if kind == "I" then -- a dungeon's run: its entrance
        local inst = ns.Instance:Get(step[2])
        local wing = inst and step.wing and ns.Instance:Wing(inst, step.wing)
        return World((wing and wing.entrance) or (inst and inst.entrance))
    end
    local q = kind ~= "G" and kind ~= "Z" and kind ~= "I" and Q(step[2])
    if not q then return nil end
    return World((kind == "A" and q.a) or (kind == "T" and q.t) or (kind == "O" and E.ObjectivePoint(step, q))
        or (kind == "L" and q.d and q.d[1]) or nil)
end

-- The cheapest place to fit a stop at spot into the route, at index `from` or later: the index to
-- put it after, and the yards it adds. route = { { step key (nil: where you stand), spot }, ... }.
local function Cheapest(route, spot, from)
    local bestAt, bestCost
    for i = from, #route do
        local a, b = route[i], route[i + 1]
        local cost
        if not b then
            cost = Yards(a[2], spot)
        else
            local ab, ax, xb = Yards(a[2], b[2]), Yards(a[2], spot), Yards(spot, b[2])
            cost = ab and ax and xb and (ax + xb - ab)
        end
        if cost and (not bestCost or cost < bestCost) then bestAt, bestCost = i, cost end
    end
    return bestAt, bestCost
end

local detourCache -- { key = section id, list = what PlanDetours found }

-- The detours for a section's steps: { { id = quest, a = step key to pick it up after (nil and
-- aStart: before the next step; nil alone: it's in your log), t, tStart (the same for the hand-in),
-- minutes }, ... }, best XP per minute first.
local function PlanDetours(section, steps)
    local budget = ns.db.detourMinutes or 0
    if budget <= 0 then return {} end
    local level = P:Level()
    local route = {}
    local c, n, w = ns.WorldMap.Player()
    if c then route[1] = { nil, { c, n, w } } end
    local maps, onRoute, xp = { [section.zone] = true }, {}, 0
    for _, st in ipairs(steps) do
        local q = st[1] ~= "G" and st[1] ~= "Z" and st[1] ~= "I" and Q(st[2])
        if q then
            onRoute[st[2]] = true
            if st[1] == "A" then xp = xp + QuestXP(q, level) end
            if q.a then maps[q.a[1]] = true end
            if q.t then maps[q.t[1]] = true end
        end
        if not E:StepDone(st) then
            local spot = StepSpot(st)
            if spot then route[#route + 1] = { StepKey(st), spot } end
        end
    end
    if #route < 2 then return {} end
    local rate = xp / math.max(1, section.minutes or 60) -- the route's usual XP per minute
    local found = {}
    for map in pairs(maps) do
        for _, id in ipairs(QuestsOn(map)) do
            local q = Q(id)
            local carried = P:InLog(id)
            if not onRoute[id] and not q.pvp and Practical(q) <= level and not DonationCloth(q) and Worth(id, level)
                and E:QuestOpen(id) and (carried or PrereqsDone(q)) and not NeedsDungeon(id, 0) then
                local aSpot, tSpot = World(q.a), World(q.t)
                local aAt, aCost = 1, 0
                if not carried then aAt, aCost = Cheapest(route, aSpot, 1) end
                local tAt, tCost
                local near = not carried and Yards(aSpot, tSpot)
                if near and near < SAME_SPOT then
                    tAt, tCost = aAt, 0
                elseif aAt then
                    tAt, tCost = Cheapest(route, tSpot, aAt) -- (handed in after it's picked up)
                end
                if aAt and aCost and tAt and tCost then
                    local minutes = math.max(MIN_DETOUR, (aCost + tCost) / RUN_SPEED / 60)
                    local gain = QuestXP(q, level)
                    if minutes <= budget and gain / minutes >= rate then
                        found[#found + 1] = { id = id, minutes = minutes, value = gain / minutes,
                            a = not carried and route[aAt][1] or nil, aStart = not carried and route[aAt][1] == nil,
                            t = route[tAt][1], tStart = route[tAt][1] == nil }
                    end
                end
            end
        end
    end
    table.sort(found, function(x, y) return x.value > y.value end)
    while #found > MAX_DETOURS do table.remove(found) end
    return found
end

-- The section's steps with its detours fitted in (each marked detour = its minutes).
local function AddDetours(section, steps)
    if Clearing() or section.instance or section.travel then return steps end
    if not (detourCache and detourCache.key == section.id) then
        detourCache = { key = section.id, list = PlanDetours(section, steps) }
    end
    if #detourCache.list == 0 then return steps end
    local after, start = {}, {} -- step key -> steps to put after it; start: before the next step left
    local function Put(key, atStart, step)
        local list = atStart and start or after[key]
        if not list then list = {}; after[key] = list end
        list[#list + 1] = step
    end
    for _, d in ipairs(detourCache.list) do
        if d.a or d.aStart then Put(d.a, d.aStart, { "A", d.id, detour = d.minutes }) end
        Put(d.t, d.tStart, { "T", d.id, detour = d.minutes })
    end
    local out, placed = {}, #start == 0
    for _, st in ipairs(steps) do
        if not placed and st[1] ~= "Z" and not E:StepDone(st) then
            for _, x in ipairs(start) do out[#out + 1] = x end
            placed = true
        end
        out[#out + 1] = st
        for _, x in ipairs(after[StepKey(st)] or {}) do out[#out + 1] = x end
    end
    if not placed then
        for _, x in ipairs(start) do out[#out + 1] = x end
    end
    return out
end

-- ---------------------------------------------------------------------------------------------
-- The order of the next steps
-- ---------------------------------------------------------------------------------------------

-- The guide's order is its route's, planned from nowhere in particular. The next WINDOW steps left
-- (pick-ups, objectives, hand-ins, loot) go in the order that walks the least from where you stand:
-- every order they can go in is timed (Walked's yards at RUN_SPEED, from you through each step),
-- and the quickest wins. A quest's own steps keep their order (pick up, do, hand in), and so
-- do a quest and one that needs it.
--
-- The order is worked out now and then, not on every change: at login, on Play (unpausing), when
-- the section changes, after Skip or "Done it" (E:Reorder), and once every step it holds is done.
-- Until then it stays, so finishing four quests on the way doesn't turn the arrow round four
-- times: a hand-in that comes up meanwhile waits after the planned steps, for the next order.
local WINDOW = 8     -- steps: up to this many, every order is tried
local BESIDE_WORK = 75 -- yards: a giver this close to a step of a quest you have goes with it (see Improved)
local LOOKAHEAD = 30 -- quests planned at once: the ones paying the most of a level an hour (see QuestRate)
local PLAN_MS = 1000   -- a plan's working time, at most: spread over frames (see StartPlan)
local SLICE_MS = 4     -- of it, in any one frame
local OFF_COURSE_SECONDS = 30 -- moving this long without getting closer: the route is worked out again
local AT_WORK_YARDS = 150     -- this near an objective you're working on it, not off course
local SCAN_STEPS = 150 -- steps looked through to find them
local MIN_GAIN = 40   -- yards: a new order has to bring the XP in at least this much sooner than the guide's
local FAR = 100000    -- yards: a leg to another continent (straight-line yards don't apply)
local order           -- { section = id, keys = { step key, ... } in the chosen order }
local orderDirty = true

function E:Reorder() orderDirty = true end
function E:ReleaseHold() holdKey, holdStep = nil, nil end

local function Orderable(s)
    local k = s[1]
    -- (A dungeon's route: what's done outside before the run is planned too. The run itself stops
    -- the plan, so nothing crosses it: what comes before stays before, the hand-ins after.)
    return (k == "A" or k == "O" or k == "T" or k == "L") and not (s.later or s.last or s.inside)
        and (not s.before or ns.char.instance ~= nil)
end

-- Step b has to come after step a: the same quest, or b's quest needs a's.
function E.After(a, b) return E.AfterStep(a, b) end
local function After(a, b)
    if b[1] == "I" then return true end -- the run is where a route's plan ends
    if a[2] == b[2] then return not (a.part and b.part) end -- (a quest's objectives: in any order)
    local q = Q(b[2])
    for _, p in ipairs(q and q.pre or {}) do
        if p == a[2] then return true end
    end
    return false
end

E.AfterStep = After

-- The next steps left from index `from` that can be put in another order, with their spots: up to
-- WINDOW, stopping at a step that can't (a zone change, grinding, a dungeon, no place to go) or
-- that can't be done yet from what's in the list (a hand-in whose objectives are neither done nor
-- listed, a quest step for a quest you haven't got and won't pick up first).
-- A quest whose objectives aren't all in one place: far apart in a zone (q.sp), or in different zones.
E.spread = {}
function E.Spread(q)
    local known = E.spread[q]
    if known ~= nil then return known end
    local apart = q.sp == true
    local map
    for _, a in ipairs(q.g or {}) do
        local m = a.p and a.p[1][1]
        if m and map and m ~= map then apart = true end
        map = map or m
    end
    apart = apart and q.g ~= nil
    E.spread[q] = apart
    return apart
end

-- What a quest is worth from where you stand: the share of your current level it pays, per hour.
-- Against the whole level, not what's left of it, so a quest is worth the same just after a ding as
-- just before one. The time: the walk to its giver (unless you have it), to every objective left and to
-- its hand-in, and the objectives themselves (the build's estimate). A quest you've finished has only the
-- walk to the hand-in left. Returns the rate, and the XP and minutes behind it.
local function QuestRate(id, start)
    local q = Q(id)
    local level = P:Level()
    local need = XP_TO_LEVEL[level]
    if not q or not need then return 0, 0, 0 end
    local xp = QuestEarns(q, level)
    local yards, at = 0, start
    local function To(point)
        local spot = point and World(point)
        if at and spot then yards = yards + (Walked(at, spot) or FAR) end
        at = spot or at
    end
    local carried = P:InLog(id)
    if not carried then To(q.a) end
    local ready = carried and (P:ReadyToTurnIn(id) or not q.o)
    if q.o and not ready then
        if E.Spread(q) then
            -- Objectives apart: a stop for each one left, nearest next.
            local left = {}
            for _, a in ipairs(q.g) do
                local done = carried and a.n and (P:Objective(id, a.n)) == true
                if a.p and not done then left[#left + 1] = a.p[1] end
            end
            while #left > 0 do
                local best, bestYards = 1, nil
                for i, point in ipairs(left) do
                    local spot = at and World(point)
                    local d = spot and Yards(at, spot) or FAR
                    if not bestYards or d < bestYards then best, bestYards = i, d end
                end
                To(table.remove(left, best))
            end
        else
            To(q.o[1])
        end
    end
    To(q.t)
    local minutes = math.max(0.25, yards / RUN_SPEED / 60 + (ready and 0 or (q.m or 0)))
    if not ready then minutes = minutes + ExpectedDeaths(q, level) * DEATH_MINUTES end
    return xp / need / minutes * 60, xp, minutes
end
E.QuestRate = QuestRate
function E.YardsTo(point) -- (the simulator's diagnostics)
    local c, n, w = ns.WorldMap.Player()
    local spot = c and World(point)
    local yards = spot and Yards({ c, n, w }, spot)
    return yards and math.floor(yards) or nil
end

-- The LOOKAHEAD quests paying best right now, each with what it needs first. keep: a quest that has
-- to be in (the step you're on). Returns { [quest] = true }, and fills E.ranked for /fg why.
local function BestQuests(ids, start, keep)
    local rate, order = {}, {}
    E.ranked = {}
    for id in pairs(ids) do
        local r, xp, minutes = QuestRate(id, start)
        rate[id] = r
        order[#order + 1] = id
        E.ranked[#E.ranked + 1] = { id = id, rate = r, xp = xp, minutes = minutes }
    end
    table.sort(order, function(a, b)
        if rate[a] ~= rate[b] then return rate[a] > rate[b] end
        return a < b
    end)
    table.sort(E.ranked, function(a, b)
        if a.rate ~= b.rate then return a.rate > b.rate end
        return a.id < b.id
    end)
    local chosen, count = {}, 0
    local function Take(id, depth)
        if chosen[id] or depth > 10 then return end
        local q = Q(id)
        for _, p in ipairs(q and q.pre or {}) do
            if ids[p] then
                Take(p, depth + 1)
                if q.preAny then break end
            end
        end
        if not chosen[id] and count < LOOKAHEAD then chosen[id], count = true, count + 1 end
    end
    if keep and ids[keep] then Take(keep, 0) end
    -- The quests you have are always in: left out, their steps wait behind everything planned, and the
    -- route walks away from work you've started because a town's new quests pay more an hour.
    for _, id in ipairs(order) do
        if P:InLog(id) then Take(id, 0) end
    end
    for _, id in ipairs(order) do
        if count >= LOOKAHEAD then break end
        Take(id, 0)
    end
    return chosen
end

-- Quests too high for you now that the plan gets you to: step -> { [the hand-ins that earn it] = true }.
-- They have to come after those (see Gated).
local earnedBy = {}

local function Gated(a, b)
    return earnedBy[b] ~= nil and earnedBy[b][a] == true
end

local function Window(steps, from, start, keep)
    local list, spots, has = {}, {}, {}
    wipe(earnedBy)
    -- The level you'll have reached at this point of the plan, from the XP of what's planned so far.
    local level = P:Level()
    local reached, xpNow = level, UnitXP and UnitXP("player") or 0
    if type(xpNow) ~= "number" or (issecretvalue and issecretvalue(xpNow)) then xpNow = 0 end
    local handIns = {}
    -- A follow-up: what it needs comes earlier in this list, so it opens up along the way.
    local function FollowUp(s)
        local q = Q(s[2])
        -- (GRIND_GAP: a route gains levels on the way that its quests' XP alone doesn't show.)
        if not q or Practical(q) > reached + GRIND_GAP or P:InLog(s[2]) then return false end
        if not q.pre then return true end -- (only its level was in the way)
        for _, p in ipairs(q.pre) do
            local there = has[p .. "T"] or P:Done(p)
            if q.preAny and there then return true end
            if not q.preAny and not there then return false end
        end
        return not q.preAny
    end
    -- Pass after pass: what's planned earns XP and hands quests in, which opens more, until nothing
    -- else fits. That's what fills the plan: a quest is in as long as what unlocks it is.
    local placed, stop, added = {}, #steps, true
    while added do
        added = false
        for i = from or 1, stop do
            if #list >= SCAN_STEPS then break end
            local s = steps[i]
            if placed[s] then
                -- (in the plan from an earlier pass)
            elseif s[1] == "Z" then
                -- A zone change doesn't end the plan: it covers the whole trip, and WithTravel puts the
                -- zone changes back in where the finished plan crosses from one zone to another.
            elseif s[1] == "I" and not E:StepDone(s) then
                -- The dungeon does: everything before it leads to its entrance, so that's the last stop.
                local spot = StepSpot(s)
                if spot then list[#list + 1], spots[#list + 1] = s, spot end
                placed[s], stop = true, i
                break
            elseif not E:StepDone(s) and (not Waits(s) or FollowUp(s) or (has[s[2] .. "A"] and not E.Early(s))) then
                if not Orderable(s) then stop = i; break end
                local id, kind = s[2], s[1]
                local q = Q(id)
                -- A step of a quest that can't be placed yet (its pick-up isn't in the plan, its objectives
                -- aren't done or planned) is passed over: the plan reads on.
                local placeable = true
                if kind == "O" or kind == "T" then
                    if not (P:InLog(id) or has[id .. "A"] or has[id .. "L"]) then placeable = false end
                    if kind == "T" and q and q.o and not (P:ReadyToTurnIn(id) or has[id .. "O"]) then placeable = false end
                end
                if placeable then
                    local spot = StepSpot(s)
                    -- (Nothing to walk to: a quest's "speak to" that ticks off on the way. It doesn't end the plan.)
                    if spot then
                        list[#list + 1], spots[#list + 1] = s, spot
                    elseif kind ~= "O" then
                        stop = i
                        break
                    end
                    has[id .. kind] = true
                    placed[s], added = true, true
                    if kind == "A" and Practical(q) > level and not s.early and not ns.char.instance then
                        local need = {}
                        for _, t in ipairs(handIns) do need[t] = true end
                        earnedBy[s] = need
                    end
                    if kind == "T" and spot then
                        handIns[#handIns + 1] = s
                        xpNow = xpNow + QuestEarns(q, reached)
                        while reached < 60 and xpNow >= XP_TO_LEVEL[reached] do
                            xpNow = xpNow - XP_TO_LEVEL[reached]
                            reached = reached + 1
                        end
                    end
                end
            end
        end
    end
    -- More than can be planned at once: the ones worth doing now. The rest stay on the route, after them.
    local ids, count = {}, 0
    for _, s in ipairs(list) do
        if not ids[s[2]] then ids[s[2]], count = true, count + 1 end
    end
    local chosen = BestQuests(ids, start, keep)
    if count > LOOKAHEAD then
        local kept, keptSpots = {}, {}
        for i, s in ipairs(list) do
            if chosen[s[2]] then kept[#kept + 1], keptSpots[#kept + 1] = s, spots[i] end
        end
        return kept, keptSpots
    end
    return list, spots
end

-- Yards from `start` (nil: anywhere) through the spots in the order given.
local function Walk(spots, seq, start)
    local yards, at = 0, start
    for _, j in ipairs(seq) do
        if at then yards = yards + (Walked(at, spots[j]) or FAR) end
        at = spots[j]
    end
    return yards
end

-- What getting to a step early is worth: the quest's XP at your level, less for the deaths it's likely
-- to cost, shared over its pick-up (a quarter), objectives (a quarter) and hand-in (the rest), and a
-- little for any step at all, so the walk counts when nothing pays.
local function StepWeight(s)
    -- (A dungeon's run counts for its kills, at least: it's what the route is for.)
    if s[1] == "I" then return 1 + (45 + 5 * P:Level()) * RUN_KILL_XP end
    local xp = QuestXP(Q(s[2]), P:Level()) / (1 + ExpectedDeaths(Q(s[2]), P:Level()))
    return 1 + xp * (s[1] == "T" and 0.5 or 0.25)
end

-- How long XP waits along an order: each step's weight times the yards walked to reach it. Lower
-- is better. The same measure as choosing a zone: XP as soon as possible, not the fewest yards.
local function Delay(list, spots, seq, start)
    local total, yards, at = 0, 0, start
    for _, j in ipairs(seq) do
        if at then yards = yards + (Walked(at, spots[j]) or FAR) end
        at = spots[j]
        total = total + yards * StepWeight(list[j])
    end
    return total
end

-- A plan runs as a coroutine, a slice of each frame (see StartPlan). Breathe gives the frame back when
-- the slice is used up; spent is the working time so far.
local sliceStart, spent

local function Breathe()
    if not sliceStart then return end
    local used = debugprofilestop() - sliceStart
    if used > SLICE_MS then
        spent = spent + used
        coroutine.yield()
        sliceStart = debugprofilestop()
    end
end

local function OutOfTime()
    return sliceStart and spent + debugprofilestop() - sliceStart > PLAN_MS
end

-- A good order for a list too long to try every one: from the guide's, move each quest's steps as a
-- block, each step, and each run of two or three (a quest's steps at one stop), to wherever it brings
-- the XP in soonest, until nothing moves. Keeps what has to come first first, and the opening step first.
local function Improved(list, spots, start, opening, before, weight, fromWork)
    local n = #list
    local seq, pos = {}, {}
    if opening then seq[1] = opening end
    for j = 1, n do
        if j ~= opening then seq[#seq + 1] = j end
    end
    local legs = {}
    for a = 1, n do
        legs[a] = {}
        for b = 1, n do legs[a][b] = a ~= b and (Walked(spots[a], spots[b]) or FAR) or 0 end
    end
    local first = {}
    for j = 1, n do first[j] = start and (Walked(start, spots[j]) or FAR) or 0 end
    -- The Delay of an order, or nil when something comes before what it needs, or it's already past
    -- limit: a total only grows, so most of the orders tried stop early. (Most of a plan's time is here.)
    local function Cost(order, limit)
        local total, yards, at = 0, 0, nil
        for i = 1, n do
            local j = order[i]
            yards = yards + (at and legs[at][j] or first[j])
            at = j
            total = total + yards * weight[j]
            if limit and total >= limit then return nil end
        end
        for i = 1, n do pos[order[i]] = i end
        for j = 1, n do
            for _, b in ipairs(before[j]) do
                if pos[b] > pos[j] then return nil end
            end
        end
        return total
    end
    local best = Cost(seq)
    if not best then return nil, math.huge end
    local low = opening and 2 or 1
    -- Small moves can't take a whole town's steps behind a far-off trip, so where a search starts decides
    -- what it can find. One search (see Quickest) starts from the quests you have. That's only a place
    -- to start from: nothing favours it, the order that scores better is the one kept.
    if fromWork then
        -- (With the quests whose giver is beside that work: you'd take them as you go by.)
        local mine = {}
        for j = 1, n do
            if P:InLog(list[j][2]) then mine[list[j][2]] = true end
        end
        for a = 1, n do
            if list[a][1] == "A" and not mine[list[a][2]] then
                for b = 1, n do
                    if P:InLog(list[b][2]) and legs[a][b] <= BESIDE_WORK then mine[list[a][2]] = true end
                end
            end
        end
        local seed = {}
        for j = 1, n do
            if mine[list[j][2]] then seed[#seed + 1] = j end
        end
        for j = 1, n do
            if not mine[list[j][2]] then seed[#seed + 1] = j end
        end
        local cost = Cost(seed)
        if cost then seq, best = seed, cost end
    end
    for _ = 1, 6 do
        local moved = false
        for run = 1, 3 do
            for from = low, n - run + 1 do
                if OutOfTime() then return seq, best end
                Breathe()
                local bestAt, bestCost, bestSeq = nil, best, nil
                local rest, part = {}, {}
                for i = 1, n do
                    if i >= from and i < from + run then part[#part + 1] = seq[i] else rest[#rest + 1] = seq[i] end
                end
                for at = low, #rest + 1 do
                    if at ~= from then
                        local order = {}
                        for i = 1, at - 1 do order[#order + 1] = rest[i] end
                        for i = 1, run do order[#order + 1] = part[i] end
                        for i = at, #rest do order[#order + 1] = rest[i] end
                        local cost = Cost(order, bestCost)
                        if cost and cost < bestCost then bestAt, bestCost, bestSeq = at, cost, order end
                    end
                end
                if bestAt then seq, best, moved = bestSeq, bestCost, true end
            end
        end
        -- A quest's steps as one block: a run can't take a pick-up later without its far-off hand-in,
        -- so an errand would stay wherever it landed. Whole, it can slide to when the route goes by.
        local quests = {}
        for i = low, n do
            local id = list[seq[i]][2]
            if not quests[id] then quests[id] = true; quests[#quests + 1] = id end
        end
        for _, id in ipairs(quests) do
            if OutOfTime() then return seq, best end
            Breathe()
            local rest, part = {}, {}
            for i = 1, n do
                if i >= low and list[seq[i]][2] == id then part[#part + 1] = seq[i] else rest[#rest + 1] = seq[i] end
            end
            if #part >= 2 then
                local bestCost, bestSeq = best, nil
                for at = low, #rest + 1 do
                    local order = {}
                    for i = 1, at - 1 do order[#order + 1] = rest[i] end
                    for _, j in ipairs(part) do order[#order + 1] = j end
                    for i = at, #rest do order[#order + 1] = rest[i] end
                    local cost = Cost(order, bestCost)
                    if cost and cost < bestCost then bestCost, bestSeq = cost, order end
                end
                if bestSeq then seq, best, moved = bestSeq, bestCost, true end
            end
        end
        if not moved then break end
    end
    return seq, best
end

-- The best order for list (indexes into it) that keeps what has to come first first, with its Delay
-- and yards. Up to WINDOW steps, branch and bound over every order, the guide's own tried first and
-- winning ties; a longer list, see Improved. opening: the step it has to start with, or nil.
local function Quickest(list, spots, start, opening)
    local n = #list
    local before, weight = {}, {}
    for j = 1, n do
        weight[j] = StepWeight(list[j])
        before[j] = {}
        for i = 1, j - 1 do
            if After(list[i], list[j]) or Gated(list[i], list[j]) then before[j][#before[j] + 1] = i end
        end
    end
    if n > WINDOW then
        if opening then return Improved(list, spots, start, opening, before, weight) end
        -- From the quests you have first: if time runs out, that's the one worth having.
        local best, cost = Improved(list, spots, start, nil, before, weight, true)
        if OutOfTime() then return best, cost end
        local other, otherCost = Improved(list, spots, start, nil, before, weight)
        if other and otherCost < cost then return other, otherCost end
        return best, cost
    end
    local best, bestDelay = nil, math.huge
    local used, path = {}, {}
    local function Go(depth, at, yards, delay)
        if delay >= bestDelay then return end
        if depth <= 4 then Breathe() end
        if depth > n then
            best, bestDelay = { unpack(path, 1, n) }, delay
            return
        end
        for j = 1, n do
            if not used[j] and (depth > 1 or not opening or j == opening) then
                local ready = true
                for _, i in ipairs(before[j]) do
                    if not used[i] then ready = false; break end
                end
                if ready then
                    local reach = yards + (at and (Walked(at, spots[j]) or FAR) or 0)
                    used[j], path[depth] = true, j
                    Go(depth + 1, spots[j], reach, delay + reach * weight[j])
                    used[j] = false
                end
            end
        end
    end
    Go(1, start, 0, 0)
    return best, bestDelay
end

-- The last look over a finished order: where along the whole route a pick-up adds the least walking,
-- anywhere before what needs it and after what it needs. 480 yards there now against 130 when the
-- route goes by it later, and later it goes. A move has to save more than SAVE_YARDS. Pick-ups pay
-- nothing by themselves, so all that matters is what they cost to fetch. The step the order opens
-- with stays. seq is changed in place.
local SAVE_YARDS = 40
local STEP_RANK = { A = 1, L = 1, O = 2, T = 3 }
local function Tuck(list, spots, seq, start, opening)
    local n = #seq
    local function Leg(a, b) -- (seq indexes into list; a nil: where you stand)
        if not a then return start and (Walked(start, spots[b]) or FAR) or 0 end
        return Walked(spots[a], spots[b]) or FAR
    end
    local function Added(prev, j, nxt)
        local added = Leg(prev, j)
        if nxt then added = added + Leg(j, nxt) - Leg(prev, nxt) end
        return added
    end
    -- (seq as it stands; an errand's steps are looked for in it below.)
    for _ = 1, 3 do
        local moved = false
        for _, j in ipairs({ unpack(seq) }) do
            if list[j][1] == "A" and j ~= opening then
                local from
                for i = 1, n do
                    if seq[i] == j then from = i end
                end
                local now = Added(seq[from - 1], j, seq[from + 1])
                table.remove(seq, from)
                local lo, hi = (opening and j ~= opening) and 2 or 1, n
                for i = 1, n - 1 do
                    local a, b = list[seq[i]], list[j]
                    -- (After says a quest's steps go together both ways: their kinds say which way.)
                    local mine = a[2] == b[2]
                    if mine and STEP_RANK[a[1]] > STEP_RANK[b[1]] or (not mine and (After(b, a) or Gated(b, a))) then
                        hi = math.min(hi, i)
                    end
                    if mine and STEP_RANK[a[1]] < STEP_RANK[b[1]] or (not mine and (After(a, b) or Gated(a, b))) then
                        lo = math.max(lo, i + 1)
                    end
                end
                local at, best = from, now - SAVE_YARDS
                for i = lo, hi do
                    local added = Added(seq[i - 1], j, seq[i])
                    if added < best then at, best = i, added end
                end
                table.insert(seq, at, j)
                if at ~= from then moved = true end
            end
        end
        if not moved then break end
    end
    -- An errand: a quest that's a pick-up and a hand-in, nothing to do between them. Each is tied to
    -- the other, so moving either alone gets nowhere and one placed badly can pull the whole route out
    -- of its way. Taken out together, each goes where it adds the least, the hand-in after the pick-up.
    local function Total(order)
        local yards, at = 0, nil
        for _, j in ipairs(order) do
            yards = yards + Leg(at, j)
            at = j
        end
        return yards
    end
    for _, pick in ipairs({ unpack(seq) }) do
        local id, give, other = list[pick][2], nil, false
        if list[pick][1] == "A" and pick ~= opening then
            for _, j in ipairs(seq) do
                if j ~= pick and list[j][2] == id then
                    if list[j][1] == "T" then give = j else other = true end
                end
            end
        end
        if give and give ~= opening and not other then
            local before = Total(seq)
            local rest = {}
            for _, j in ipairs(seq) do
                if j ~= pick and j ~= give then rest[#rest + 1] = j end
            end
            local count = #rest
            -- After what the quest needs, before what needs it.
            local lo, hi = opening and 2 or 1, count + 1
            for i = 1, count do
                local a = list[rest[i]]
                if After(a, list[pick]) or Gated(a, list[pick]) then lo = math.max(lo, i + 1) end
                if After(list[give], a) or Gated(list[give], a) then hi = math.min(hi, i) end
            end
            -- Least added: the pick-up at i, the hand-in at k >= i. From the end, the best hand-in so far.
            local bestPick, bestGive, bestAdded
            local tail, tailAt
            for i = hi, lo, -1 do
                local added = Added(rest[i - 1], give, rest[i])
                if not tail or added < tail then tail, tailAt = added, i end
                local together = Added(rest[i - 1], pick, give) + Leg(give, rest[i] or give)
                    - (rest[i] and rest[i - 1] and Leg(rest[i - 1], rest[i]) or 0)
                local apart = i < tailAt and Added(rest[i - 1], pick, rest[i]) + tail or nil
                if apart and (not bestAdded or apart < bestAdded) then bestPick, bestGive, bestAdded = i, tailAt, apart end
                if not bestAdded or together < bestAdded then bestPick, bestGive, bestAdded = i, i, together end
            end
            if bestPick then
                local trial = {}
                for i = 1, count + 1 do
                    if i == bestPick then trial[#trial + 1] = pick end
                    if i == bestGive then trial[#trial + 1] = give end
                    if rest[i] then trial[#trial + 1] = rest[i] end
                end
                if before - Total(trial) > SAVE_YARDS then
                    for i = 1, #trial do seq[i] = trial[i] end
                end
            end
        end
    end
end

local function Minutes(yards) return math.max(1, math.floor(yards / RUN_SPEED / 60 + 0.5)) end

-- Where to start from after you've been away (at login, on Play, in a new section): the step you were
-- on, if you're still around it; nil while the route is around you, for the plan to choose freely;
-- else, when its next step is over a minute's walk off, the step nearest you that you can do now.
-- You may have gone anywhere since it was last followed; the steps before it wait (see ApplyOrder).
local function NearestStep(steps, start)
    local at, best = FirstLeft(steps), math.huge
    if not start then return at end
    -- The step you were on when you logged out, while you're still around it: finished quests and
    -- unfinished ones alike, it stays yours.
    local saved = ns.char.onStep
    for i, s in ipairs(steps) do
        if saved and StepKey(s) == saved and Orderable(s) and not E:StepDone(s) and not Waits(s) then
            local q = Q(s[2])
            local yards = Yards(start, StepSpot(s))
            if yards and yards <= RUN_SPEED * 60
                and (s[1] ~= "T" or P:ReadyToTurnIn(s[2]) or not (q and q.o)) then
                return i
            end
            break
        end
    end
    -- Still where the route is: no step has to come first, the plan sorts out what's around you.
    local ahead = at and Yards(start, StepSpot(steps[at]))
    if ahead and ahead <= RUN_SPEED * 60 then return nil end
    for i, s in ipairs(steps) do
        if Orderable(s) and not E:StepDone(s) and not Waits(s) then
            local id, kind = s[2], s[1]
            local q = Q(id)
            local doable = kind == "A" or kind == "L" or (P:InLog(id)
                and (kind == "O" or P:ReadyToTurnIn(id) or not (q and q.o)))
            local yards = doable and Yards(start, StepSpot(s))
            if yards and yards < best then at, best = i, yards end
        end
    end
    return at
end

-- Works out the order of the next steps (see above). Returns the new order, or nil.
-- What's at the place you've reached is done on that visit. Doing a step where you already stand can
-- never add a yard, and leaving and coming back always does, so this holds for every plan, whatever
-- the search found: anything at the same place (BESIDE_YARDS) moves up to the first visit, as long as
-- what it needs comes first. The first step stays first.
function E.Gather(list, spots, seq)
    local out, placed, left = {}, {}, {}
    for i, j in ipairs(seq) do left[i] = j end
    local function Free(j)
        for i = 1, j - 1 do
            if not placed[i] and (E.AfterStep(list[i], list[j]) or Gated(list[i], list[j])) then return false end
        end
        return true
    end
    while #left > 0 do
        local here = spots[left[1]]
        local moved = true
        while moved do
            moved = false
            for i, j in ipairs(left) do
                local yards = i == 1 and 0 or Yards(here, spots[j])
                if yards and yards <= E.BESIDE_YARDS and Free(j) then
                    out[#out + 1], placed[j] = j, true
                    table.remove(left, i)
                    moved = true
                    break
                end
            end
        end
        -- (A first step that has to wait for something: what it waits for goes first.)
        if left[1] and spots[left[1]] == here then
            local j = table.remove(left, 1)
            out[#out + 1], placed[j] = j, true
        end
    end
    -- Before a long walk away, what's still to do close by: leaving it means coming all the way back.
    wipe(placed)
    local i = 1
    while i < #out do
        placed[out[i]] = true
        local at = spots[out[i]]
        local leg = Yards(at, spots[out[i + 1]])
        if leg and leg > E.LEAVE_YARDS then
            for k = i + 2, #out do
                local j = out[k]
                local yards = Yards(at, spots[j])
                if yards and yards <= E.CLOSE_YARDS and Free(j) then
                    table.remove(out, k)
                    table.insert(out, i + 1, j)
                    break
                end
            end
        end
        i = i + 1
    end
    return out
end
E.LEAVE_YARDS, E.CLOSE_YARDS = 400, 300 -- a walk this long leaves what's this close behind
E.LOOK_STOPS = 3 -- stops ahead that say whether you're leaving (BesideYou)

local function PlanOrder(section, steps, away)
    local c, n, w = ns.WorldMap.Player()
    local start = c and { c, n, w } or nil
    -- The step you're on stays the one you're on, whatever you did meanwhile: what's after it can move.
    local held
    if not away and holdKey then
        for i, s in ipairs(steps) do
            if StepKey(s) == holdKey and Orderable(s) and not E:StepDone(s) and not Waits(s) then held = i; break end
        end
    end
    -- (A dungeon's route is all to do, ending at the entrance: planned whole, not from the nearest step.)
    -- The plan reads everything left; the step to start with is only that: the one you're on, or after
    -- being away, the nearest you can do.
    local lead = held or (away and not section.instance and NearestStep(steps, start)) or nil
    local list, spots = Window(steps, FirstLeft(steps), start, lead and steps[lead][2])
    local opening
    for j, s in ipairs(list) do
        if lead and s == steps[lead] then opening = j end
    end
    -- (After being away even one step is an order: it's the one to start with.)
    if #list < (away and 1 or 2) then return nil end
    local guideSeq = {}
    for j = 1, #list do guideSeq[j] = j end
    local guideYards = Walk(spots, guideSeq, start)
    local guideDelay = Delay(list, spots, guideSeq, start)
    local weights = 0
    for _, s in ipairs(list) do weights = weights + StepWeight(s) end
    -- The one search has no step held first: the step you're on is weighed against what it finds, below.
    -- (A dungeon's route starts where it starts.)
    local held = opening
    if held and not section.instance then opening = nil end
    local seq, delay = Quickest(list, spots, start, opening)
    -- (A new order has to bring the XP in MIN_GAIN yards sooner, on average.)
    if not seq or (not opening and guideDelay - delay < MIN_GAIN * weights) then seq, delay = guideSeq, guideDelay end
    -- Orders that close are the same order: of those, the one that starts with what's beside you.
    local nearest, nearestYards
    for j = 1, section.instance and 0 or #list do
        local free = true
        for i = 1, #list do
            if i ~= j and (After(list[i], list[j]) or Gated(list[i], list[j])) and i < j then free = false; break end
        end
        local yards = free and Yards(start, spots[j])
        if yards and (not nearestYards or yards < nearestYards) then nearest, nearestYards = j, yards end
    end
    if nearest and seq[1] ~= nearest and not opening and not held then
        local beside, besideDelay = Quickest(list, spots, start, nearest)
        if beside and besideDelay - delay < MIN_GAIN * weights then seq = beside end
    end
    if not section.instance then
        Tuck(list, spots, seq, start, opening)
        -- The step you're on stays first, unless that walks more than SAVE_YARDS further than this route.
        -- The same route with it first, against the route: what it costs to do it now and not when
        -- the route comes to it.
        if held then
            local first = { held }
            for _, j in ipairs(seq) do
                if j ~= held then first[#first + 1] = j end
            end
            local legal = true
            for i = 2, #first do
                if After(list[first[i]], list[held]) and list[first[i]][2] ~= list[held][2] then legal = false end
            end
            local saves = legal and Walk(spots, first, start) - Walk(spots, seq, start) or 0
            E.lastBump = ("%s: %d yd saved by moving it"):format(StepKey(list[held]), saves)
            if saves > SAVE_YARDS then
                ns:Print(("Moved %s later: saves %d yd."):format(E:QuestName(list[held][2]), saves))
            else
                Tuck(list, spots, first, start, held)
                seq, opening = first, held
            end
        end
    end
    -- (Nothing held it, or it moved: the step you're on is whatever comes first now.)
    if not opening then holdKey, holdStep = nil, nil end
    seq = E.Gather(list, spots, seq)
    local yards = Walk(spots, seq, start)
    local keys, moved = {}, false
    for i, j in ipairs(seq) do
        keys[i] = StepKey(list[j])
        if j ~= i then moved = true end
    end
    if moved and Minutes(yards) < Minutes(guideYards) then
        ns:Print(("Next %d steps put in the quickest order: about %d min of walking instead of %d."):format(
            #list, Minutes(yards), Minutes(guideYards)))
    end
    return { section = section.id, keys = keys, minutes = yards / RUN_SPEED / 60 }
end

-- Plans run in the background: a few milliseconds a frame, with the order you have staying in use
-- until the new one is ready, and the spinner up meanwhile.
local job

local function RunJob()
    if not job then return end
    sliceStart = debugprofilestop and debugprofilestop() or nil
    local ok, result = coroutine.resume(job.co)
    if not ok then
        job = nil
        if ns.UI and ns.UI.Planning then ns.UI:Planning(false) end
        geterrorhandler()(result)
        return
    end
    if coroutine.status(job.co) == "dead" then
        job, sliceStart = nil, nil
        order = result
        if ns.UI and ns.UI.Planning then ns.UI:Planning(false) end
        ns:Changed()
    else
        C_Timer.After(0, RunJob)
    end
end

local function StartPlan(section, steps, away)
    spent = 0
    job = { co = coroutine.create(function() return PlanOrder(section, steps, away) end) }
    if ns.UI and ns.UI.Planning then ns.UI:Planning(true) end
    RunJob()
end

-- The steps with the order's steps where its first one is, in its order; the others that were
-- ahead of them and are left to do (they came up after the order was made) wait after them.
-- Zone changes, grinding and dungeons stay where they are.
local function ApplyOrder(steps, keys)
    local inOrder, byKey, first = {}, {}, nil
    for _, k in ipairs(keys) do inOrder[k] = true end
    for i, s in ipairs(steps) do
        local k = StepKey(s)
        if inOrder[k] and not byKey[k] then
            byKey[k] = s
            first = first or i
        end
    end
    if not first then return steps end
    local out, waiting = {}, {}
    local firstQuest = Q(steps[first][2])
    local firstPoint = firstQuest and ((steps[first][1] == "T" and firstQuest.t) or firstQuest.a)
    for i = 1, first - 1 do
        local s = steps[i]
        -- A zone change ahead of them goes with the steps it leads to, unless it leads here.
        local otherZone = s[1] == "Z" and not (firstPoint and firstPoint[1] == s[2])
        if otherZone or (Orderable(s) and not E:StepDone(s)) then waiting[#waiting + 1] = s else out[#out + 1] = s end
    end
    for _, k in ipairs(keys) do
        if byKey[k] then out[#out + 1] = byKey[k] end
    end
    for _, s in ipairs(waiting) do out[#out + 1] = s end
    for i = first, #steps do
        local s = steps[i]
        if not (inOrder[StepKey(s)] and byKey[StepKey(s)] == s) then out[#out + 1] = s end
    end
    return out
end

-- The zone a step is in, or nil.
local function StepMap(s)
    local kind = s[1]
    local q = kind ~= "G" and kind ~= "Z" and kind ~= "I" and Q(s[2])
    local p = q and ((kind == "A" and q.a) or (kind == "T" and q.t) or (kind == "O" and E.ObjectivePoint(s, q))
        or (kind == "L" and q.d and q.d[1]))
    return p and p[1] or nil
end

-- The steps with their zone changes, where the plan really crosses from one zone to another. Each
-- is a task of its own: `from` the zone you leave, `back` when the plan brings you back there (an
-- errand) and not when you're moving on.
local function WithTravel(steps)
    local out, at = {}, CurrentZone()
    for i, s in ipairs(steps) do
        if s[1] ~= "Z" then
            local map = not s.later and not E:StepDone(s) and not Waits(s) and StepMap(s)
            if map and map ~= at then
                local back = false
                for j = i + 1, #steps do
                    local later = steps[j]
                    if StepMap(later) == at and not E:StepDone(later) and not Waits(later) then back = true; break end
                end
                out[#out + 1] = { "Z", map, from = at, back = back }
                at = map
            end
            out[#out + 1] = s
        end
    end
    return out
end

-- Whether the order still has a step to do on these steps.
local function OrderLive(steps)
    local inOrder = {}
    for _, k in ipairs(order.keys) do inOrder[k] = true end
    for _, s in ipairs(steps) do
        if inOrder[StepKey(s)] and not E:StepDone(s) then return true end
    end
    return false
end

-- The section's steps in the order to do them (see above).
-- What you can do in the area comes first, whatever the order says: a quest to pick up, or one ready
-- to hand in, a short walk from you. It takes moments, and coming back for it later doesn't. (Turning
-- a quest in often opens the next one at the same person.) Stops at a dungeon's run: hand-ins after
-- it stay after it. The step you were on carries on after them.
local BESIDE_YARDS = 75
E.BESIDE_YARDS = BESIDE_YARDS
local inArea = {} -- step key -> true: up front only because it's close (it doesn't become the step you're on)
E.promised = {} -- step key -> true: came up front, and stays there until it's done (BesideYou)

local function BesideYou(steps)
    wipe(inArea)
    local c, n, w = ns.WorldMap.Player()
    if not c then return steps end
    local at, first, rest = { c, n, w }, {}, {}
    local past = false
    -- Where you're headed. A hand-in that's ready beside it is done there first, even when the plan has
    -- it further on (you finished the quest sooner than it expected): it pays, and it's on your way.
    local stop
    for _, s in ipairs(steps) do
        if s[1] == "I" then break end
        if Orderable(s) and not E:StepDone(s) and not Waits(s) then
            stop = StepSpot(s)
            break
        end
    end
    -- Walking away: what's close that the route will want anyway comes first, whatever its place in the
    -- order, or the route comes all the way back for it. A plan is made once, and doesn't see you about to
    -- leave. This is looked at every time, so it holds however the plan came out.
    -- (The next few stops, not only the first: a short hop on the way out is still leaving.)
    local leaving, ahead = false, 0
    for _, s in ipairs(steps) do
        if s[1] == "I" or ahead >= E.LOOK_STOPS then break end
        if Orderable(s) and not E:StepDone(s) and not Waits(s) then
            ahead = ahead + 1
            local yards = Yards(at, StepSpot(s))
            if yards and yards > E.LEAVE_YARDS then leaving = true end
        end
    end
    local reach = leaving and E.CLOSE_YARDS or BESIDE_YARDS
    local dist = {}
    -- What came up front stays up front until it's done: this is looked at again from each spot, and one
    -- short hop later you're no longer "leaving", or it's a few yards out of reach, and it would drop back
    -- to its place in the order and you'd leave without it. Let go of only once you're well away from it.
    local promised = E.promised
    for _, s in ipairs(steps) do
        if s[1] == "I" then past = true end
        local here = false
        local key = StepKey(s)
        local fight = (leaving or promised[key]) and s[1] == "O" and Orderable(s) and P:InLog(s[2]) and not E:MovedOn(s)
        if not past and (s[1] == "A" or s[1] == "T" or fight) and not (s.later or s.last) and not E:StepDone(s) and not Waits(s) then
            local q = Q(s[2])
            local doable = s[1] == "A" or fight or (P:InLog(s[2]) and (P:ReadyToTurnIn(s[2]) or not (q and q.o)))
            local spot = doable and StepSpot(s)
            local yards = spot and Yards(at, spot)
            here = yards and (yards <= reach or (promised[key] and yards <= E.LEAVE_YARDS))
            promised[key] = here and true or nil
            dist[s] = yards
            if not here and s[1] == "T" and spot and stop then
                local fromStop = Yards(stop, spot)
                here = fromStop and fromStop <= BESIDE_YARDS
            end
        end
        if here then
            first[#first + 1] = s
            inArea[StepKey(s)] = true
        else
            rest[#rest + 1] = s
        end
    end
    -- (Nearest first: each one looked at again from where the last one leaves you.)
    table.sort(first, function(a, b) return (dist[a] or 0) < (dist[b] or 0) end)
    -- The step you're on comes straight after them, whatever else the order says: it stays yours until
    -- it's done, you skip it, or you've been away. This is the one place that says so, so nothing can
    -- get round it. (A hand-in you can't make yet, its objectives not done, isn't something to do now.)
    local held
    local pinned = holdKey -- (on a trip: the step it's taking you to, if it's still to do)
    if trip and trip.target then
        for _, s in ipairs(rest) do
            if StepKey(s) == trip.target and not E:StepDone(s) then pinned = trip.target end
        end
    end
    for i, s in ipairs(rest) do
        if StepKey(s) == pinned and not E:StepDone(s) and not Waits(s) then
            local q = Q(s[2])
            if s[1] ~= "T" or P:ReadyToTurnIn(s[2]) or not (q and q.o) then held = i end
            break
        end
    end
    if not (held and not relocate) then
        if #first == 0 then return rest end
        for _, s in ipairs(rest) do first[#first + 1] = s end
        return first
    end
    -- What's beside you comes before the step you're on only if that saves real walking: going to the
    -- step first and back has to be over SAVE_YARDS longer than taking this first. Else straight after.
    local mine = table.remove(rest, held)
    local spot = StepSpot(mine)
    local out, later = {}, {}
    for _, s in ipairs(first) do
        local here = StepSpot(s)
        local there, back = spot and Yards(at, spot), spot and here and Yards(spot, here)
        local near = here and Yards(at, here)
        if there and back and near and there + back - (near + back) > SAVE_YARDS then
            out[#out + 1] = s
        else
            later[#later + 1] = s
            inArea[StepKey(s)] = nil
        end
    end
    out[#out + 1] = mine
    for _, s in ipairs(later) do out[#out + 1] = s end
    for _, s in ipairs(rest) do out[#out + 1] = s end
    return out
end

-- Finished quests in your log that aren't on the route, however you came to finish them (a dungeon's, one
-- the guide never had): the XP is earned but for the walk, so a hand-in joins the plan once that walk
-- pays what questing does, by the measure the plan uses (QuestRate). Once in, it stays until it's handed
-- in, wherever you walk: a route that dropped it again would be changing its mind. Otherwise it's looked
-- at again as you go, so one you come near gets picked up. One within CLOSE_YARDS is in whatever it pays:
-- it costs next to nothing now, and a trip back later. Only quests with a known place to hand in.
function E.WithHandIns(section, steps)
    if not section or section.instance or stay or Clearing() or not logReady then return steps end
    ns.char.handIns = ns.char.handIns or {}
    local kept = ns.char.handIns
    for id in pairs(kept) do
        if not P:InLog(id) then kept[id] = nil end
    end
    local listed = {}
    for _, s in ipairs(steps) do
        if s[1] == "T" then listed[s[2]] = true end
    end
    local out, rate, start = steps, nil, nil
    for _, id in ipairs(P:LogQuests()) do
        local q = Q(id)
        if q and q.t and not listed[id] and not ns.char.ignored[id] and P:ReadyToTurnIn(id) then
            if not kept[id] then
                if not start then
                    local c, n, w = ns.WorldMap.Player()
                    start = c and { c, n, w } or false
                    rate = E:QuestingRate()
                end
                local _, pays, minutes = QuestRate(id, start or nil)
                local spot = start and StepSpot({ "T", id })
                local yards = spot and Yards(start, spot)
                if start and ((yards and yards <= E.CLOSE_YARDS) or (minutes > 0 and pays / minutes >= rate)) then
                    kept[id], orderDirty = true, true
                end
            end
            if kept[id] then
                if out == steps then
                    out = {}
                    for i, s in ipairs(steps) do out[i] = s end
                end
                out[#out + 1] = { "T", id }
            end
        end
    end
    return out
end

-- A quest from a higher bracket whose giver is at a place the route stops anyway (or where you stand), and
-- that the game already lets you take: it's picked up on this visit, as you won't be back this way for a
-- while, and what it asks waits until it's your level (Waits). Only while the log has room to spare.
function E.WithEarly(section, steps)
    if not section or section.instance or section.travel or stay or Clearing() or not logReady then return steps end
    ns.char.early = ns.char.early or {}
    for id in pairs(ns.char.early) do
        if not P:InLog(id) then ns.char.early[id] = nil end
    end
    if #P:LogQuests() >= E.EARLY_LOG then return steps end
    local level = P:Level()
    local stops
    local out = steps
    for i, s in ipairs(steps) do
        local q = s[1] == "A" and Waits(s) and not E:StepDone(s) and Q(s[2])
        if q and q.a and (q.r or 1) <= level and PrereqsDone(q) then
            if not stops then
                stops = {}
                local c, n, w = ns.WorldMap.Player()
                if c then stops[1] = { c, n, w } end
                for _, t in ipairs(steps) do
                    if (t[1] == "A" or (t[1] == "T" and P:ReadyToTurnIn(t[2]))) and not E:StepDone(t) and not Waits(t) then
                        local spot = StepSpot(t)
                        if spot then stops[#stops + 1] = spot end
                    end
                end
            end
            local spot = StepSpot(s)
            for _, stop in ipairs(stops) do
                local yards = spot and Yards(stop, spot)
                if yards and yards <= BESIDE_YARDS then
                    if out == steps then
                        out = {}
                        for k, v in ipairs(steps) do out[k] = v end
                    end
                    local copy = {}
                    for k, v in pairs(s) do copy[k] = v end
                    copy.early = true
                    out[i] = copy
                    ns.char.early[s[2]] = true
                    break
                end
            end
        end
    end
    return out
end

-- All that's left of a quest in your log is within CLOSE_YARDS of you. An objective with no known place
-- isn't here: it could be anywhere. A dungeon's quest never is: its work is inside.
function E.AllHere(id, at)
    local q = Q(id)
    if not q or q.dq then return false end
    for _, left in ipairs(E:ActionsLeft(id)) do
        local near = false
        for _, point in ipairs(left.action.w or left.action.p or {}) do
            local spot = World(point)
            local yards = spot and Yards(at, spot)
            if yards and yards <= E.CLOSE_YARDS then near = true; break end
        end
        if not near then return false end
    end
    return true
end

-- A quest worth doing with its giver within CLOSE_YARDS of you, on the route or not: you're here now, and
-- anything left behind is a trip back later (the next zone's route, the loose ends). It's worth it by the
-- measure everything else uses: it pays what questing does. Once taken on, a quest stays on the plan,
-- pick-up, objectives and hand-in, until it's done, whichever zone you're following.
function E.WithNearby(section, steps)
    if not section or section.instance or stay or Clearing() or not logReady then return steps end
    ns.char.adopted = ns.char.adopted or {}
    local kept = ns.char.adopted
    local listed = {}
    for _, s in ipairs(steps) do listed[s[1] .. s[2]] = true end
    local c, n, w = ns.WorldMap.Player()
    local zone = CurrentZone()
    if not E.byZone then
        E.byZone = {}
        for id, q in pairs(ns.Quests) do
            local map = q.a and q.a[1]
            if map then
                E.byZone[map] = E.byZone[map] or {}
                table.insert(E.byZone[map], id)
            end
        end
    end
    local level = P:Level()
    if c and #P:LogQuests() < E.EARLY_LOG then
        local start, rate = { c, n, w }, nil
        for _, id in ipairs(E.byZone[zone] or {}) do
            local q = Q(id)
            if not kept[id] and not listed["A" .. id] and not q.dq and not P:InLog(id) and E:QuestOpen(id)
                and Practical(q) <= level and PrereqsDone(q) and not NeedsDungeon(id, 0) then
                local spot = StepSpot({ "A", id })
                local yards = spot and Yards(start, spot)
                if yards and yards <= E.CLOSE_YARDS then
                    rate = rate or E:QuestingRate()
                    local _, pays, minutes = QuestRate(id, start)
                    if minutes > 0 and pays / minutes >= rate then
                        kept[id], orderDirty = true, true
                    end
                end
            end
        end
    end
    local out = steps
    local function Add(kind, id)
        if listed[kind .. id] then return end
        if out == steps then
            out = {}
            for i, s in ipairs(steps) do out[i] = s end
        end
        out[#out + 1] = { kind, id }
    end
    -- What's unfinished in your log right here stays on the plan too, whatever leg you're on: a hand-off to
    -- the next zone lists only itself, and would walk you away from it. "Right here" is the whole of what's
    -- left of the quest, not one spot of it: the rest may be across the map, or inside a dungeon.
    if c then
        for _, id in ipairs(P:LogQuests()) do
            local q = Q(id)
            if q and q.o and not ns.char.ignored[id] and not P:ReadyToTurnIn(id) then
                local step = { "O", id }
                local spot = StepSpot(step)
                local yards = spot and Yards({ c, n, w }, spot)
                if yards and yards <= E.CLOSE_YARDS and E.AllHere(id, { c, n, w }) then Add("O", id) end
            end
        end
    end
    for id in pairs(kept) do
        if P:Done(id) or not E:QuestOpen(id) then
            kept[id] = nil
        else
            if not P:InLog(id) then Add("A", id) end
            if Q(id).o then Add("O", id) end
            Add("T", id)
        end
    end
    return out
end

local function Ordered(section, steps)
    if not section or section.travel then
        order = nil
        -- (A leg of travel has no plan, but what's beside you still comes first.)
        return section and BesideYou(steps) or steps
    end
    local keep = order and order.section == section.id and OrderLive(steps)
    -- The order has to start with the step you're on, if that's still to do.
    if keep and holdKey and not job then
        local now = FirstLeft(ApplyOrder(steps, order.keys))
        local ordered = now and ApplyOrder(steps, order.keys)[now]
        if ordered and StepKey(ordered) ~= holdKey then
            for _, st in ipairs(steps) do
                if StepKey(st) == holdKey and Orderable(st) and not E:StepDone(st) and not Waits(st) then
                    orderDirty = true
                end
            end
        end
    end
    -- Paused: the order isn't worked out again until Play. Still asking the server which quests
    -- exist: the steps may change in a moment (the guide's order meanwhile).
    if (orderDirty or not keep) and not job and not ns.char.paused and not ns.Exists:Busy() then
        orderDirty = false
        local away = relocate or not order or order.section ~= section.id
        relocate = false
        StartPlan(section, steps, away)
        keep = order and order.section == section.id and OrderLive(steps)
    end
    local out = BesideYou(keep and ApplyOrder(steps, order.keys) or steps)
    return section.instance and out or WithTravel(out)
end

-- ---------------------------------------------------------------------------------------------
-- Things to do on the way
-- ---------------------------------------------------------------------------------------------

-- When two or more objectives of quests in your log lie along the walk to the next place you have
-- to be (a pick-up or a hand-in), they become one task: look for them on the way there. The group
-- is fixed when it forms, so walking doesn't shuffle it, and each objective leaves it when it's done.
-- Reach the place first and the walk to the next place is looked at the same way, so tasks chain and
-- you keep moving; those not on that walk stay on the route as regular steps. Only when nothing lies
-- along it does what's left become the task: finish them, nearest first. With one left it's a
-- regular step again. The steps themselves stay as they are; the task is the step that's
-- current, marked with what goes with it (`with`), so ticking off, Skip and the arrow all still work.
local CORRIDOR = 120 -- yards either side of the walk
local MIN_LEG = 150  -- yards: a walk shorter than this has no "on the way"
-- { section = id, dest = step key (nil: finishing), items = { step key, ... }, was = the step you
-- were on when the task formed: back to it when the task is over }
local group

local function OpenObjective(s)
    local q = s[1] == "O" and not (s.before or s.inside or s.later or E:MovedOn(s)) and Q(s[2])
    return q and q.o and P:InLog(s[2]) and not E:StepDone(s) or false
end

-- A place you can go to and get something done there: a pick-up, or a hand-in that's ready.
local function Destination(s)
    if E:StepDone(s) or Waits(s) then return false end
    if s[1] == "A" then return true end
    if s[1] ~= "T" or not P:InLog(s[2]) then return false end
    local q = Q(s[2])
    return P:ReadyToTurnIn(s[2]) or not (q and q.o)
end

-- Some spot of the quest's objectives lies along the walk from a to b.
local function OnTheWay(q, a, b)
    local dn, dw = b[2] - a[2], b[3] - a[3]
    local len2 = dn * dn + dw * dw
    if a[1] ~= b[1] or len2 == 0 then return false end
    for _, o in ipairs(q.o) do
        local p = World(o)
        if p and p[1] == a[1] then
            local t = ((p[2] - a[2]) * dn + (p[3] - a[3]) * dw) / len2
            if t >= 0 and t <= 1 then
                local en, ew = a[2] + t * dn - p[2], a[3] + t * dw - p[3]
                if en * en + ew * ew <= CORRIDOR * CORRIDOR then return true end
            end
        end
    end
    return false
end

-- Marks step i as the task: a copy (the section's own steps stay as they are).
local function Mark(steps, i, items, at, going)
    local copy = {}
    for k, v in pairs(steps[i]) do copy[k] = v end
    copy.plain, copy.with, copy.going = steps[i], {}, going
    for _, key in ipairs(items) do
        if not going and at[key] == i then
            table.insert(copy.with, 1, steps[at[key]])
        else
            copy.with[#copy.with + 1] = steps[at[key]]
        end
    end
    steps[i] = copy
    return i
end

-- A task for the walk to the next place, if two or more objectives lie along it: the step to be on.
local function Form(section, steps, current, at, from)
    if not from then return nil end
    local dest
    for i = current, math.min(#steps, current + 2 * WINDOW) do
        local s = steps[i]
        if s[1] == "Z" or s[1] == "G" or s[1] == "I" then break end
        if Destination(s) then dest = i; break end
    end
    local to = dest and StepSpot(steps[dest])
    local leg = to and Yards(from, to)
    if not leg or leg < MIN_LEG then return nil end
    local items = {}
    for i = current, #steps do
        local s = steps[i]
        if OpenObjective(s) and s[2] ~= steps[dest][2] and OnTheWay(Q(s[2]), from, to) then
            items[#items + 1] = StepKey(s)
        end
    end
    if #items < 2 then return nil end
    group = { section = section.id, dest = StepKey(steps[dest]), items = items,
        was = group and group.was or StepKey(steps[current]) }
    return Mark(steps, dest, items, at, true)
end

-- The step to be on, given the first one left: the task, if there is one. See above.
local function Consolidate(section, steps, current)
    if not current or section.instance or section.travel then group = nil; return current end
    if group and group.section ~= section.id then group = nil end
    local at = {}
    for i, s in ipairs(steps) do
        local key = StepKey(s)
        at[key] = at[key] or i
    end
    local c, n, w = ns.WorldMap.Player()
    local from = c and { c, n, w } or nil
    if group then
        local live = {}
        for _, key in ipairs(group.items) do
            if at[key] and OpenObjective(steps[at[key]]) then live[#live + 1] = key end
        end
        group.items = live
        local dest = group.dest and at[group.dest]
        if dest and not Destination(steps[dest]) then dest, group.dest = nil, nil end
        if #live == 0 or (dest and #live == 1) then
            local was = group.was and at[group.was]
            group = nil
            if was and not E:StepDone(steps[was]) and not Waits(steps[was]) then return was end
            return current
        end
        -- The step you're on isn't part of this: it comes first, and the task ends here.
        local first = steps[current]
        if first and StepKey(first) == holdKey and StepKey(first) ~= group.dest and first[1] ~= "Z" then
            local mine = false
            for _, key in ipairs(live) do
                if key == holdKey then mine = true end
            end
            if not mine then
                group = nil
                return current
            end
        end
        if dest then return Mark(steps, dest, live, at, true) end
        -- The place is done. On to the next one if the walk there takes in two or more of them...
        local chained = #live >= 2 and Form(section, steps, current, at, from)
        if chained then return chained end
        -- ...otherwise what's left is the task, the nearest of them first.
        local best, bestYards = at[live[1]], math.huge
        for _, key in ipairs(live) do
            local yards = from and Yards(from, StepSpot(steps[at[key]]))
            if yards and yards < bestYards then best, bestYards = at[key], yards end
        end
        if #live == 1 then return best end
        return Mark(steps, best, live, at, false)
    end
    return Form(section, steps, current, at, from) or current
end

-- About how many minutes of walking the ordered steps take (from where you stood), or nil.
function E:OrderMinutes() return order and order.minutes end

do -- (in a block: this file is at Lua's limit of 200 locals)
-- ---------------------------------------------------------------------------------------------
-- What a quest asks, one action at a time (q.g, from tools\FieldGuide\build_guides.py)
-- ---------------------------------------------------------------------------------------------

-- Where a "Do" step is: its own objective's spot when the quest is split into stops (see SplitParts).
function E.ObjectivePoint(step, q)
    if step.part then return q.g[step.part].p[1] end
    return q.o and q.o[1]
end

-- The objectives done at the same place as number i: one stop for all of them.
local function SamePlace(q, i, j)
    local a, b = q.g[i].p, q.g[j].p
    if i == j then return true end
    if not (a and b) then return false end
    return a[1][1] == b[1][1] and a[1][2] == b[1][2] and a[1][3] == b[1][3]
end

function E:ActionDone(id, i)
    local q = Q(id)
    for j, a in ipairs(q.g) do
        if SamePlace(q, i, j) and a.n and (P:Objective(id, a.n)) ~= true then return false end
    end
    return true
end

local CALLOUT = { use = "|cffffd100%s|r", keep = "|cffff9933%s|r" }

-- The actions still to do, in order, with your progress from the quest log ("Kill 8 Prowlers (3/8)"),
-- and an item to use or someone to keep alive in colour. With part: that stop's actions, and those
-- with no place of their own go with the first stop.
function E:ActionsLeft(id, part)
    local out = {}
    local q = Q(id)
    for i, a in ipairs(q and q.g or {}) do
        local mine = not part or SamePlace(q, part, i) or (not a.p and part == q.firstPart)
        if mine then
            local done, have, need = P:Objective(id, a.n)
            if not done then
                local text = a.l
                if need and need > 1 then text = ("%s (%d/%d)"):format(text, have or 0, need) end
                if CALLOUT[a.k] then text = CALLOUT[a.k]:format(text) end
                out[#out + 1] = { text = text, action = a }
            end
        end
    end
    return out
end

-- A quest whose objectives are far apart (q.sp) is a stop for each: the route picks up each one when
-- it goes by, instead of doing them all in one trip. Before a dungeon or inside one, it stays whole.
function E.SplitParts(steps)
    local out = {}
    for _, s in ipairs(steps) do
        local q = s[1] == "O" and not (s.before or s.inside or s.part or s.later) and Q(s[2])
        if q and q.sp and q.g then
            for i, a in ipairs(q.g) do
                local lead = a.p ~= nil
                for j = 1, i - 1 do
                    if q.g[j].p and SamePlace(q, i, j) then lead = false end
                end
                if lead then
                    q.firstPart = q.firstPart or i
                    local copy = {}
                    for k, v in pairs(s) do copy[k] = v end
                    copy.part = i
                    out[#out + 1] = copy
                end
            end
        else
            out[#out + 1] = s
        end
    end
    return out
end

-- ---------------------------------------------------------------------------------------------
-- Hunting areas (q.g[i].z) and farm routes
-- ---------------------------------------------------------------------------------------------
-- Several quests' objectives share an area (tools\FieldGuide\quest_areas.py). A short while after you
-- walk in the arrow moves on: mobs here may be dead, and what's left comes up on the way. What you're
-- still after stays listed under the arrow, and its hand-in waits. When there's nothing else close by,
-- the next step is the farm: a walk through the spots of everything you're still hunting, round and
-- round (Waypoint starts its points over), until it's done. A place with few spawns (no z) isn't
-- moved on from: the arrow stays on it.
local MOVE_ON_SECONDS = 5
local AREA_YARDS = 90 -- yards from the center of an area that count as being in it
local FARM_NEAR = 500 -- yards: anything further than this from the hunt, and you farm first

local function InArea(step)
    local q = step[1] == "O" and not (step.before or step.inside) and Q(step[2])
    if not (q and q.g and P:InLog(step[2])) then return false end
    for i, a in ipairs(q.g) do
        if a.z and (not step.part or SamePlace(q, step.part, i)) then return true end
    end
    return false
end

function E:MovedOn(s)
    local hunt = s[1] == "O" and self.hunting[s[2]]
    return hunt and hunt[StepKey(s)] and not s.farm and not self:StepDone(s) or false
end

-- What you can get done right where you are: every objective of the quests in your log with a spawn
-- close to you, nearest first. Not only the step you're on: this is what's worth stopping for.
local NEAR_YARDS = 150
function E:NearbyActions()
    local out, seen = {}, {}
    local c, n, w = ns.WorldMap.Player()
    if not c then return out end
    local me = { c, n, w }
    for _, s in ipairs(self.steps) do
        if s[1] == "O" and not seen[s[2]] and not s.later and P:InLog(s[2]) then
            seen[s[2]] = true
            for _, left in ipairs(self:ActionsLeft(s[2])) do
                local best
                for _, p in ipairs(left.action.w or left.action.p or {}) do
                    local spot = World(p)
                    local yards = spot and spot[1] == c and Yards(me, spot)
                    if yards and yards <= NEAR_YARDS and (not best or yards < best) then best = yards end
                end
                if best then out[#out + 1] = { text = left.text, title = self:QuestName(s[2]), yards = best } end
            end
        end
    end
    table.sort(out, function(a, b) return a.yards < b.yards end)
    return out
end

-- Every spot of what you're still hunting.
function E:FarmSpots()
    local spots, seen = {}, {}
    for id in pairs(self.hunting) do
        local q = Q(id)
        for i, a in ipairs(q and q.g or {}) do
            if a.p and not (a.n and (P:Objective(id, a.n)) == true) then
                for _, p in ipairs(a.p) do
                    local key = p[1] .. ":" .. p[2] .. ":" .. p[3]
                    if not seen[key] then
                        seen[key] = true
                        spots[#spots + 1] = p
                    end
                end
            end
        end
    end
    return spots
end

-- Quests finished, or no longer in the log, stop being hunted.
function E:TidyHunt()
    local changed = false
    for id in pairs(self.hunting) do
        if P:ReadyToTurnIn(id) or not P:InLog(id) then
            self.hunting[id] = nil
            changed = true
        end
    end
    return changed
end

function E:CheckHunt()
    if self:TidyHunt() then
        self.farmStep = nil
        self:Invalidate()
    end
    local step = self.current and self.steps[self.current]
    local c, n, w = ns.WorldMap.Player()
    -- The hunts you're standing in: the step's own, or those of a task of several ("on the way").
    local here = {}
    if step and not step.farm and c then
        for _, s in ipairs(step.with or { step.plain or step }) do
            local spot = InArea(s) and not self:StepDone(s) and StepSpot(s)
            local yards = spot and Yards({ c, n, w }, spot)
            if yards and yards <= AREA_YARDS then here[#here + 1] = s end
        end
    end
    if #here == 0 then
        self.enteredAt, self.enteredKey = nil, nil
        return
    end
    local key = StepKey(here[1])
    if self.enteredKey ~= key then
        self.enteredKey, self.enteredAt = key, GetTime()
    elseif GetTime() - self.enteredAt >= MOVE_ON_SECONDS then
        for _, s in ipairs(here) do
            self.hunting[s[2]] = self.hunting[s[2]] or {}
            self.hunting[s[2]][StepKey(s)] = true
        end
        self.enteredAt, self.enteredKey = nil, nil
        self:ReleaseHold()
        self:Invalidate()
        self.secondaryDirty = true
        ns:Changed()
    end
end

-- With nothing close by to do, the hunt comes first: a step that farms what's left.
function E:FarmFirst(index)
    if not next(self.hunting) then return index end
    local nextStep = index and self.steps[index]
    if nextStep and nextStep.with then return index end -- the task isn't over: farming is for its end
    local spots = self:FarmSpots()
    if #spots == 0 then return index end
    local near = false
    if nextStep and nextStep[1] ~= "Z" then
        local there = StepSpot(nextStep.plain or nextStep)
        for _, p in ipairs(spots) do
            local yards = Yards(there, World(p))
            if yards and yards <= FARM_NEAR then near = true end
        end
    end
    if near then return index end
    for i, s in ipairs(self.steps) do
        local hunt = s[1] == "O" and self.hunting[s[2]]
        if hunt and hunt[StepKey(s)] and not self:StepDone(s) then
            local copy = {}
            for k, v in pairs(s) do copy[k] = v end
            copy.plain, copy.farm = s, true
            self.steps[i] = copy
            return i
        end
    end
    return index
end

end

-- ---------------------------------------------------------------------------------------------
-- Describing a step
-- ---------------------------------------------------------------------------------------------

local function Where(spot)
    if not spot then return "" end
    local info = C_Map.GetMapInfo(spot[1])
    return ("%s %.0f, %.0f"):format(info and info.name or "?", spot[2], spot[3])
end
function E:Where(spot) return Where(spot) end

-- A quest's name, with "(part 1)", "(part 2)" when the route has several quests of that name
-- (Blackfathom's two "Allegiance to the Old Gods").
local parts = {} -- questID -> its part number on the current route
function E:QuestName(id)
    local q = Q(id) or {}
    local name = q.n or ("Quest " .. id)
    return parts[id] and ("%s (part %d)"):format(name, parts[id]) or name
end

local function NumberParts(steps)
    wipe(parts)
    local byName, order = {}, {}
    for _, s in ipairs(steps) do
        local q = s[1] ~= "G" and s[1] ~= "Z" and s[1] ~= "I" and Q(s[2])
        if q and q.n then
            local list = byName[q.n]
            if not list then list = {}; byName[q.n] = list end
            if not order[s[2]] then
                order[s[2]] = true
                list[#list + 1] = s[2]
            end
        end
    end
    for _, list in pairs(byName) do
        if #list > 1 then
            for i, id in ipairs(list) do parts[id] = i end
        end
    end
end

-- Who a step is with: the person (or thing) you pick it up from or turn it in to, else nil.
function E:Who(step)
    local q = Q(step[2]) or {}
    if step[1] == "A" then return q.a and q.a[4] end
    if step[1] == "T" then return q.t and q.t[4] end
end

-- verb, quest name, detail line, { mapID, x (0-1), y } points for the arrow
function E:Describe(step)
    -- A task: everything that goes with this step. The arrow leads to the place it's on the way to,
    -- or, finishing them, to any of their spots.
    if step.with then
        local names, points, named = {}, {}, {}
        for _, s in ipairs(step.with) do
            if not named[s[2]] then
                named[s[2]] = true
                names[#names + 1] = E:QuestName(s[2])
            end
            for _, o in ipairs(s.part and Q(s[2]).g[s.part].p or Q(s[2]).o or {}) do
                points[#points + 1] = { o[1], o[2] / 100, o[3] / 100 }
            end
        end
        local list = table.concat(names, ", ")
        if step.going then
            local verb, name, detail, spot = E:Describe(step.plain)
            return "On the way", list, ("You're heading to: %s %s. %s"):format(strlower(verb), name, detail), spot
        end
        return "Finish", list, "Still to do from your way here.", points
    end
    local kind, id = step[1], step[2]
    if kind == "G" then
        return "Grind", ("Reach level %d"):format(id), "Kill what's around you until you're level " .. id .. ".", nil
    end
    if kind == "I" then
        local inst = ns.Instance:Get(id)
        if not inst then return "Run", "Run the dungeon", "", nil end
        local wing = step.wing and ns.Instance:Wing(inst, step.wing)
        local e = wing and wing.entrance or inst.entrance
        local watch = {}
        for _, q in ipairs(ns.Instance:MissingItems(inst, step.wing)) do watch[#watch + 1] = ns.Instance:InsideText(q) end
        local where = e and (wing and (". Its entrance: %s (inside the dungeon's outer gate)"):format(Where(e))
            or (". Entrance: " .. Where(e))) or "."
        return "Run", ns.Instance:RunName(inst, step.wing),
            (wing and "Do its quests in this wing" or "Do its quests inside") .. where
                .. (#watch > 0 and (" Watch for: " .. table.concat(watch, ", ") .. ".") or ""),
            e and { { e[1], e[2] / 100, e[3] / 100 } }
    end
    if kind == "L" then
        local q = Q(id) or {}
        local item = q.ia or "the item"
        if step.inside or not q.d then
            local inst = step.inst and ns.Instance:Get(step.inst)
            local wing = inst and step.wing and ns.Instance:Wing(inst, step.wing)
            local e = wing and wing.entrance or (inst and inst.entrance)
            local name = inst and ns.Instance:RunName(inst, step.wing) or "the dungeon"
            return "Loot", item, ("Drops inside %s. It starts %s.%s"):format(name,
                    E:QuestName(id), step.again and " Run it again to find it." or ""),
                step.again and e and { { e[1], e[2] / 100, e[3] / 100 } } or nil
        end
        local points = {}
        for _, p in ipairs(q.d) do points[#points + 1] = { p[1], p[2] / 100, p[3] / 100 } end
        if q.de then
            return "Loot", item, ("Walk to the dungeon entrance (%s) and kill %s until it drops. Click it to start %s."):format(
                Where(q.d[1]), q.dm or "the mobs there", E:QuestName(id)), points
        end
        return "Loot", item, ("Kill %s around %s until it drops. Click it to start %s."):format(q.dm or "mobs", Where(q.d[1]), E:QuestName(id)),
            points
    end
    if kind == "Z" then
        local info = C_Map.GetMapInfo(id)
        local name = info and info.name or "the next zone"
        local from = step.from and C_Map.GetMapInfo(step.from)
        return "Travel", "Go to " .. name, step.back
            and ("An errand: the plan brings you back to %s after it."):format(from and from.name or "this zone")
            or ("The next quests are in %s."):format(name), nil
    end
    local q = Q(id) or {}
    local name = E:QuestName(id)
    if kind == "A" then
        local d = ("%s, %s"):format(q.a and q.a[4] or "?", Where(q.a))
        local xp = QuestXP(q, P:Level())
        if xp > 0 then d = d .. ("  |cff8a948e(%d XP)|r"):format(xp) end
        if Practical(q) > P:Level() then d = ("Needs level %d. %s"):format(Practical(q), d) end
        if step.detour then d = d .. ("  |cff8a948e(detour, ~%d min)|r"):format(math.max(1, math.floor(step.detour + 0.5))) end
        return "Pick up", name, d, q.a and { { q.a[1], q.a[2] / 100, q.a[3] / 100 } }
    elseif kind == "O" then
        local points = {}
        for _, o in ipairs(step.farm and self:FarmSpots() or step.part and q.g[step.part].p or q.o or {}) do
            points[#points + 1] = { o[1], o[2] / 100, o[3] / 100 }
        end
        local left = self:ActionsLeft(id, step.part)
        local detail = left[1] and left[1].text or q.ot or ""
        if step.before and q.o then
            local inst = ns.Instance:Get(step.inst)
            local e, o = inst and inst.entrance, q.o[1]
            local atEntrance = e and o[1] == e[1] and math.sqrt(((o[2] - e[2]) * 1.5) ^ 2 + (o[3] - e[3]) ^ 2) <= 4
            local part = inst and inst.before and inst.before[id] == "part"
            detail = ("Before you go in, %s: %s%s"):format(atEntrance and ("at the entrance, outside the portal (" .. Where(o) .. ")")
                or ("out in the world (" .. Where(o) .. ")"), detail,
                part and " Get what you can out here; the rest is inside." or "")
        end
        return "Do", name, detail, #points > 0 and points or nil
    else
        return "Turn in", name, ("%s, %s"):format(q.t and q.t[4] or "?", Where(q.t)),
            q.t and { { q.t[1], q.t[2] / 100, q.t[3] / 100 } }
    end
end

-- ---------------------------------------------------------------------------------------------
-- Following along
-- ---------------------------------------------------------------------------------------------

local lastSection, lastKey, lastTask
local stoppedKey -- the step you told the arrow to stop pointing at (right-click); the next step points again

-- Sends the step to Waypoint's arrow. False when it has nowhere to point.
local lastPlan -- the plan last handed to Waypoint, joined
local lastStops -- the stops after it last handed over (NextStops), joined

-- The guide's plan for the arrow: the keys of the current step and the next unfinished ones (up to
-- 5). Waypoint compares it with the target it holds to know whether you changed the arrow, and
-- only then shows its restore icon. Empty when the current step has nowhere to point.
function E:Plan()
    local out = {}
    local step = self.current and self.steps[self.current]
    if not step or ns.char.paused then return out end
    local target = step
    if step[1] == "Z" then
        for i = self.current + 1, #self.steps do
            if self.steps[i][1] ~= "Z" and self.steps[i][1] ~= "G" then target = self.steps[i]; break end
        end
    end
    local _, _, _, points = self:Describe(target)
    if not points then return out end
    out[1] = StepKey(step)
    for i = self.current + 1, #self.steps do
        if #out >= 5 then break end
        local s = self.steps[i]
        if not self:StepDone(s) and not Waits(s) then out[#out + 1] = StepKey(s) end
    end
    return out
end

-- The places you'll go after the step you're on, for Waypoint to draw on the world map: steps at one
-- place are one stop. Up to AHEAD_STOPS; a dungeon's run ends them, nothing's planned past it.
local AHEAD_STOPS = 5
local SAME_STOP = 75 -- yards (as BESIDE_YARDS: what the guide calls one place)

-- A step in words, for hovering the line on the map: what to do, where, and what it's for.
local function StepInfo(s)
    local verb, name, detail = E:Describe(s)
    local q = s[2] and Q(s[2])
    local why
    if q and s[1] == "A" then
        local giver = q.t and type(q.t[4]) == "string" and q.t[4] ~= "?" and q.t[4]
        why = ("Worth about %d XP%s."):format(QuestEarns(q, P:Level()), giver and (", handed in to " .. giver) or "")
    elseif q and s[1] == "O" then
        why = q.ot
    elseif q and s[1] == "T" then
        why = ("Hand in for about %d XP."):format(QuestEarns(q, P:Level()))
    end
    return { title = verb .. ": " .. name, detail = detail, why = why }
end

local function NextStops()
    local out, last, here_info = {}, nil, {}
    local step = E.current and E.steps[E.current]
    local here = step and step[1] ~= "Z" and step[1] ~= "G" and StepSpot(step) or nil
    last = here
    for i = (E.current or 0) + 1, #E.steps do
        if #out >= AHEAD_STOPS then break end
        local s = E.steps[i]
        if s[1] == "I" then break end
        if s[1] ~= "Z" and s[1] ~= "G" and not s.later and not E:StepDone(s) and not Waits(s) then
            local q = Q(s[2])
            local p = q and ((s[1] == "A" and q.a) or (s[1] == "T" and q.t) or (s[1] == "O" and E.ObjectivePoint(s, q))
                or (s[1] == "L" and q.d and q.d[1]))
            local spot = p and World(p)
            if spot then
                local yards = last and Yards(last, spot)
                if not (yards and yards <= SAME_STOP) then
                    out[#out + 1] = { mapID = p[1], x = p[2] / 100, y = p[3] / 100, info = {} }
                    last = spot
                end
                local stop = out[#out]
                table.insert(stop and stop.info or here_info, StepInfo(s))
            end
        end
    end
    return out, here_info
end

local function StopsKey(stops)
    local parts = {}
    for i, p in ipairs(stops) do parts[i] = p.mapID .. ":" .. p.x .. ":" .. p.y end
    return table.concat(parts, "|")
end

-- What else you can get done on the walk to the current step: quests you have, or an item that starts
-- one, with a place of theirs within ON_THE_WAY yards of the straight line there. Waypoint lists them
-- under the arrow ("keep an eye out"). Up to MAX_SECONDARY, in route order; a quest once.
do -- (in a block: this file is at Lua's limit of 200 locals)
local ON_THE_WAY = 60
local MAX_SECONDARY = 6

local function FromLine(p, a, b)
    local dn, dw = b[2] - a[2], b[3] - a[3]
    local len = dn * dn + dw * dw
    local t = len > 0 and math.max(0, math.min(1, ((p[2] - a[2]) * dn + (p[3] - a[3]) * dw) / len)) or 0
    local n, w = a[2] + t * dn - p[2], a[3] + t * dw - p[3]
    return math.sqrt(n * n + w * w)
end

function E:SecondaryTasks()
    local out = {}
    local step = self.current and self.steps[self.current]
    if not step or ns.char.paused then return out end
    -- What you can do right here comes first, wherever the arrow is pointing.
    local listed = {}
    for _, t in ipairs(self:NearbyActions()) do
        if #out < MAX_SECONDARY then
            out[#out + 1], listed[t.text] = t, true
        end
    end
    -- The rest of what the step you're on asks: the first of it is on the arrow.
    if step[1] == "O" then
        local left = self:ActionsLeft(step[2], step.part)
        for i = 2, #left do
            if #out < MAX_SECONDARY and not listed[left[i].text] then
                out[#out + 1], listed[left[i].text] = { text = left[i].text, title = self:QuestName(step[2]) }, true
            end
        end
    end
    -- A task of several: everything it's after.
    for _, s in ipairs(step.with or {}) do
        for _, a in ipairs(self:ActionsLeft(s[2], s.part)) do
            if #out < MAX_SECONDARY and not listed[a.text] then
                out[#out + 1], listed[a.text] = { text = a.text, title = self:QuestName(s[2]) }, true
            end
        end
    end
    -- What you're still hunting from the areas you've moved on from.
    for id in pairs(self.hunting) do
        if id ~= step[2] then
            for _, a in ipairs(self:ActionsLeft(id)) do
                if #out < MAX_SECONDARY and not listed[a.text] then
                    out[#out + 1], listed[a.text] = { text = a.text, title = self:QuestName(id) }, true
                end
            end
        end
    end
    local target = step
    if step[1] == "Z" then
        for i = self.current + 1, #self.steps do
            if self.steps[i][1] ~= "Z" and self.steps[i][1] ~= "G" then target = self.steps[i]; break end
        end
    end
    local c, n, w = ns.WorldMap.Player()
    local to = StepSpot(target)
    if not (c and to) or to[1] ~= c then return out end
    local from, seen = { c, n, w }, { [target[2]] = true }
    for _, s in ipairs(self.steps) do
        if #out >= MAX_SECONDARY then break end
        local q = (s[1] == "O" or s[1] == "L") and not s.later and not s.last and not seen[s[2]] and Q(s[2])
        if q and (s[1] == "L" or P:InLog(s[2])) and not self:StepDone(s) and not Waits(s) then
            for _, p in ipairs((s[1] == "O" and q.o) or q.d or {}) do
                local spot = World(p)
                if spot and spot[1] == c and FromLine(spot, from, to) <= ON_THE_WAY then
                    seen[s[2]] = true
                    -- One line an objective, the same lines as everywhere else; the quest's own text
                    -- only when it has none, or it says the same thing twice.
                    local left = self:ActionsLeft(s[2], s.part)
                    if #left == 0 and not q.g then left = { { text = q.ot or q.n } } end
                    for _, a in ipairs(left) do
                        if #out < MAX_SECONDARY and not listed[a.text] then
                            out[#out + 1], listed[a.text] = { text = a.text, title = self:QuestName(s[2]) }, true
                        end
                    end
                    break
                end
            end
        end
    end
    return out
end

local lastSecondary
function E:SendSecondary(clear)
    if not (Waypoint and Waypoint.SetSecondary) then return end
    local tasks = clear and {} or E:SecondaryTasks()
    local parts = {}
    for i, t in ipairs(tasks) do parts[i] = t.text end
    local key = table.concat(parts, "|")
    if key == lastSecondary then return end
    lastSecondary = key
    Waypoint:SetSecondary("FieldGuide", tasks)
end

-- What's on the way changes with what you finish, between one step and the next.
ns:On("QUEST_LOG_UPDATE", function() E.secondaryDirty = true end)
end

local function PointArrow(step)
    if not (Waypoint and Waypoint.Set) then return false end
    if not step or ns.char.paused then
        Waypoint:Clear("FieldGuide")
        E:SendSecondary(true)
        return false
    end
    -- A zone change aims at where the next step is.
    local target = step
    if step[1] == "Z" then
        for i = E.current + 1, #E.steps do
            if E.steps[i][1] ~= "Z" and E.steps[i][1] ~= "G" then target = E.steps[i]; break end
        end
    end
    local verb, name, detail, points = E:Describe(target)
    if not points then
        Waypoint:Clear("FieldGuide")
        E:SendSecondary(true)
        return false
    end
    if step.farm then verb, name = "Farm", "what you're still after" end
    local wp = { key = StepKey(step), title = verb .. ": " .. name, subtitle = detail, arrive = target[1] == "O" and 30 or 12,
        color = ns.char.instance and "purple" or "green", -- a dungeon's route, or the leveling guide
        onClick = function() ns.db.shown = true; ns:Changed() end, points = {} }
    -- Who to talk to (a pick-up or turn-in): Waypoint makes that line a /target button.
    local giver = (target[1] == "A" or target[1] == "T") and (Q(target[2]) or {})[target[1] == "A" and "a" or "t"]
    if giver and type(giver[4]) == "string" and giver[4] ~= "?" then wp.targetName = giver[4] end
    -- The step after this one, for the arrow's tooltip.
    for i = (E.current or 0) + 1, #E.steps do
        local s = E.steps[i]
        if s ~= target and s[1] ~= "Z" and not E:StepDone(s) and not Waits(s) then
            local nVerb, nName = E:Describe(s)
            wp.next = nVerb .. ": " .. nName
            break
        end
    end
    -- What Waypoint compares against to tell whether you changed the arrow (see Plan).
    wp.plan = E:Plan()
    lastPlan = table.concat(wp.plan, "|")
    local hereInfo
    wp.ahead, hereInfo = NextStops()
    lastStops = StopsKey(wp.ahead)
    -- What the line up to here is for: this step, and the others done at the same place.
    wp.info = { StepInfo(target) }
    for _, line in ipairs(hereInfo) do wp.info[#wp.info + 1] = line end
    for _, p in ipairs(points) do wp.points[#wp.points + 1] = { mapID = p[1], x = p[2], y = p[3] } end
    E:SendSecondary()
    return Waypoint:Set("FieldGuide", wp) and true or false
end

-- Keeps the arrow on the current step. Waypoint can lose it (you stopped it from the arrow, or
-- something cleared it), and then the arrow falls back to Questie's quests: put it back, unless
-- you stopped this very step.
function E:CheckArrow()
    if not (Waypoint and Waypoint.Get) then return end
    local step = self.current and self.steps[self.current]
    local key = step and StepKey(step)
    if not key or key == stoppedKey or ns.char.paused then return end
    local mine = Waypoint:Get("FieldGuide")
    if mine and mine.key == key then return end
    PointArrow(step)
end

-- Waypoint's arrow carries a Play icon while the guide is paused, and a Pause icon while it runs
-- (Waypoint 1.x with SetButton).
local function PlayButton()
    if not (Waypoint and Waypoint.SetButton) then return false end
    if ns.char.paused then
        Waypoint:SetButton("FieldGuide", {
            text = "Play", color = ns.char.instance and "purple" or "green",
            icon = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up",
            iconPushed = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down",
            tooltip = "Field Guide is paused. Show the guide again, and point the arrow at your current step.",
            onClick = function() E:SetPaused(false) end,
        })
    else
        Waypoint:SetButton("FieldGuide", {
            text = "Pause",
            icon = "Interface\\TimeManager\\PauseButton",
            tooltip = "Hide the guide and leave Waypoint's arrow alone. Play brings it back.",
            onClick = function() E:SetPaused(true) end,
        })
    end
    return true
end

-- While it isn't paused, the guide owns Waypoint's arrow: its step wins over other addons', only
-- your own waypoint path goes on top, right-click on the arrow leaves it alone, and the arrow's
-- restore icon points it at the current step again. Pausing gives the arrow up.
local function Own()
    if not (Waypoint and Waypoint.SetManager) then return end
    if ns.char.paused then
        Waypoint:SetManager("FieldGuide", nil)
    else
        Waypoint:SetManager("FieldGuide", { name = "Field Guide", expected = function() return E:Plan() end,
            yield = function() return not ns.db.shown end, -- window closed: quests you tracked come first
            pause = function() E:SetPaused(true) end, -- "Pause Field Guide" in the arrow's menu
            -- "Focus" in the arrow's menu: Leveling or Zone Clear.
            choices = { title = "Focus",
                { label = "Leveling", selected = function() return ns.char.preference ~= "clear" end,
                    select = function() E:SetPreference("leveling") end },
                { label = "Zone Clear", selected = function() return ns.char.preference == "clear" end,
                    select = function() E:SetPreference("clear") end } },
            restore = function()
            stoppedKey = nil
            local step = E.current and E.steps[E.current]
            if not PointArrow(step) then ns:Print("The current step has no place to point at.") end
        end })
    end
end

-- Whether pausing hides the guide window: only when Waypoint can show the Play button to bring it back.
function E:HidesWhilePaused()
    return ns.char.paused and Waypoint ~= nil and Waypoint.SetButton ~= nil
end

-- Pause: the guide stops steering Waypoint's arrow (it goes back to Questie, your path or other
-- addons) and its window hides; a "Play" button on the arrow brings both back. It keeps
-- following your progress meanwhile.
function E:SetPaused(paused)
    if paused == nil then paused = not ns.char.paused end
    ns.char.paused = paused and true or false
    local play = PlayButton()
    Own()
    if paused then
        if Waypoint and Waypoint.Clear then Waypoint:Clear("FieldGuide") end
        ns:Print(play and "Paused: the guide is hidden and leaves Waypoint's arrow alone. Press Play on the arrow (or /fg resume) to come back."
            or "Paused: the guide won't move Waypoint's arrow. Resume from the guide window, Shift+click the minimap button, or /fg resume.")
    else
        stoppedKey = nil
        -- Play: you may be anywhere by now. Everything is worked out again from where you are.
        orderDirty, pickDirty, relocate = true, true, true
        group = nil
        stay, ns.char.waitZone = nil, nil
        PointArrow(self.current and self.steps[self.current])
        ns:Print("Resumed: the arrow follows the guide again.")
    end
    ns:Changed()
end

-- /fg arrow: point at the current step again.
function E:ResumeArrow()
    if ns.char.paused then return self:SetPaused(false) end
    stoppedKey = nil
    local step = self.current and self.steps[self.current]
    if step and PointArrow(step) then
        ns:Print("The arrow points at your current step again.")
    else
        ns:Print("The current step has no place to point at.")
    end
end

local function OnWaypoint(event, entry)
    if type(event) == "string" and event:upper() == "CLEARED" and entry and entry.owner == "FieldGuide" then
        stoppedKey = entry.key
        ns:Print("Arrow stopped for this step. It points again at the next one, or now with /fg arrow.")
    end
end

-- Just after login the game may not have your quest log yet, and a finished quest reads as unfinished,
-- so its hand-in is left out of the plan. When the log is in, the plan is made again.
local function LogIsIn()
    if logReady then return end
    logReady = true
    orderDirty, pickDirty, relocate, holdKey = true, true, true, nil
    ns:Changed()
end
ns:On("QUEST_LOG_UPDATE", LogIsIn)

-- After a run of hand-ins and pick-ups the route is worked out again, to see that it's still the best
-- one: what you've done and the level you've reached change it. Not in the middle of the run, while the
-- quest log is still changing, but when it's over: LOG_CHANGES changes at least, none for QUIET_SECONDS,
-- no quest window open, and the step you're on isn't one more pick-up or hand-in right here. The step
-- you're on stays, unless a route without it first saves real walking (PlanOrder).
local LOG_CHANGES = 2
local QUIET_SECONDS = 3
local logChanges, lastChange = 0, 0
local function LogChanged()
    logChanges, lastChange = logChanges + 1, GetTime()
end
ns:On("QUEST_TURNED_IN", LogChanged)
-- A quest whose next part is offered right where you handed it in: the list has to have it now, or
-- you walk off and come back for it. Every other hand-in leaves the list as it is.
ns:On("QUEST_TURNED_IN", function(id)
    local done = Q(id)
    local at = done and done.t and World(done.t)
    if not at then return end
    for _, q in pairs(ns.Quests) do
        local spot = q.pre and q.a and World(q.a)
        if spot and Yards(at, spot) and Yards(at, spot) <= BESIDE_YARDS then
            for _, p in ipairs(q.pre) do
                if p == id then pickDirty, orderDirty = true, true; return end
            end
        end
    end
end)
ns:On("QUEST_ACCEPTED", LogChanged)

-- You took a quest you'd skipped: that's a change of mind, so it's back on the list while it's still
-- within RANGE levels of yours (Zone Clear takes the low ones too, as it takes every quest). Otherwise
-- it stays yours to do on your own. The one pick-up that works the route out again by itself.
local function QuestTaken(a, b)
    local id = b or a
    P = P or ns.Progress
    local deferred, ignored = ns.char.deferred[id], ns.char.ignored[id]
    if not (deferred or ignored) then return end
    local q, level = Q(id), P:Level()
    if ignored then
        local over = (q and q.l or level) - level
        if over > RANGE or (over < -RANGE and not Clearing()) then return end
    end
    ns.char.deferred[id], ns.char.ignored[id] = nil, nil
    pickDirty, orderDirty = true, true
    if ignored then ns:Print(("%s is back on your list."):format(E:QuestName(id))) end
    ns:Changed()
end
ns:On("QUEST_ACCEPTED", QuestTaken)

-- The guide has you picking this quest up: a pick-up (or an item that starts it) on your list that isn't
-- waiting for your level. (A quest taken early is on the list to take now: WithEarly marks it.)
function E:WantsQuest(id)
    for _, s in ipairs(self.steps or {}) do
        if (s[1] == "A" or s[1] == "L") and s[2] == id and (s.early or not Waits(s)) then return true end
    end
    return false
end

-- The step you're on is a pick-up or a hand-in you can do where you stand.
local function AtQuestGiver()
    local step = E.current and E.steps[E.current]
    if not step or (step[1] ~= "A" and step[1] ~= "T") then return false end
    local q = Q(step[2])
    if step[1] == "T" and not (P:ReadyToTurnIn(step[2]) or not (q and q.o)) then return false end
    local c, n, w = ns.WorldMap.Player()
    local yards = c and Yards({ c, n, w }, StepSpot(step))
    return yards ~= nil and yards <= BESIDE_YARDS
end

local function RunOver()
    if logChanges < LOG_CHANGES or GetTime() - lastChange < QUIET_SECONDS then return false end
    for _, frame in ipairs({ QuestFrame or false, GossipFrame or false }) do
        if frame and frame:IsShown() then return false end
    end
    return not AtQuestGiver()
end

local function CheckRun()
    if not (ns.db and RunOver()) then return end
    logChanges = 0
    orderDirty = true
    ns:Changed()
end

ns:On("PLAYER_LOGIN", function()
    if Waypoint and Waypoint.RegisterCallback then Waypoint:RegisterCallback("FieldGuide", OnWaypoint) end
    PlayButton()
    Own()
    C_Timer.After(5, LogIsIn) -- (should the game have nothing to update)
    C_Timer.NewTicker(2, function() if ns.db then E:CheckArrow() end end)
    C_Timer.NewTicker(1, function() if ns.db then E:CheckCourse(1) end end)
    C_Timer.NewTicker(1, CheckRun)
end)

function E:Update()
    -- (What's near you changes as you walk.)
    if GetTime() - (self.nearAt or 0) >= 2 then
        self.nearAt = GetTime()
        self.secondaryDirty = true
    end
    if self.secondaryDirty then
        self.secondaryDirty = false
        self:SendSecondary()
        -- (A farm route loses the spots of what you've finished; left alone otherwise, so it keeps going round.)
        local farm = self.current and self.steps[self.current]
        if farm and farm.farm and #self:FarmSpots() ~= self.farmSpots then
            self.farmSpots = #self:FarmSpots()
            PointArrow(farm)
        end
    end
    self:CheckHunt()
    if not ns.db then return end
    P = P or ns.Progress
    local guide = self:Guide()
    self.guide = guide
    if not guide then
        self.section, self.steps, self.current = nil, {}, nil
        PointArrow(nil)
        return
    end
    -- You've left the zone you were staying in, or waiting to leave. (Only a real zone counts: the
    -- map can say the continent for a moment at login.)
    local zoneNow = CurrentZone()
    local zoneInfo = zoneNow and C_Map.GetMapInfo(zoneNow)
    if zoneInfo and zoneInfo.mapType == Enum.UIMapType.Zone then
        if ns.char.waitZone and zoneNow ~= ns.char.waitZone then
            self:SetPaused(false)
        elseif stay and zoneNow ~= stay.zone then
            stay = nil
            orderDirty, pickDirty, relocate = true, true, true
        end
    end
    local section
    local inst = ns.char.instance and ns.Instance:Get(ns.char.instance)
    if inst then
        section = ns.Instance:Section(inst)
        if not FirstLeft(Build(section)) then
            ns:Print(("Done with %s's quests. Back to questing."):format(inst.name))
            ns.Instance:Stop(true)
            section = nil
        end
    elseif ns.char.instance then
        ns.char.instance = nil
    end
    section = section or self:PickSection(guide)
    self.section = section
    lastPick = section and section.id
    if section and not section.instance and not section.travel then ns.char.lastPick = section.id end
    self.steps = section and AddDetours(section, Build(section)) or {}
    -- A section in another zone starts with going there.
    local away = section and not section.instance and not section.travel and section.zone ~= CurrentZone()
    if away and self.steps[1] and self.steps[1][1] ~= "Z" then
        local steps = { { "Z", section.zone } }
        for _, s in ipairs(self.steps) do steps[#steps + 1] = s end
        self.steps = steps
    end
    -- Quests that were waiting have opened up (a level, a quest handed in): they join the plan.
    -- A trip you skipped: what's in this zone, for as long as you stay.
    if stay then
        local here = {}
        for _, s in ipairs(self.steps) do
            if s[1] == "G" or StepMap(s) == stay.zone then here[#here + 1] = s end
        end
        self.steps = here
    end
    self.steps = WithNeighbours(section, self.steps, guide)
    self.steps = self.WithEarly(section, self.WithHandIns(section, self.WithNearby(section, self.steps)))
    self.planSteps = self.steps
    -- A level is when quests open up and old ones pay less: the plan looks again.
    if self.planLevel ~= P:Level() then
        self.planLevel = P:Level()
        orderDirty = true
    end
    self.steps = Ordered(section, self.steps)
    NumberParts(self.steps)
    self.current = section and Consolidate(section, self.steps, FirstLeft(self.steps)) or FirstLeft(self.steps)
    self.current = self:FarmFirst(self.current)
    if stay and not stay.asked then
        local left = false
        for _, s in ipairs(self.steps) do
            if s[1] ~= "Z" and not self:StepDone(s) and not Waits(s) then left = true; break end
        end
        if not left then
            stay.asked = true
            self:AskStay()
        end
    end
    if ns.Exists:Busy() then
        -- Still asking the server which quests are there: the pick may change in a moment.
    elseif section and section.id ~= lastSection then
        lastSection = section.id
        if section.zone ~= CurrentZone() and not section.instance then
            ns.char.whyLog = ns.char.whyLog or {}
            table.insert(ns.char.whyLog, 1, self:Why())
            ns.char.whyLog[6] = nil
        end
        if section.note then
            ns:Print(guide.name .. ": " .. section.note)
        elseif moved then
            ns:Print(("%s: %s is the better place to level now, walk included. On to %s."):format(
                guide.name, section.title, section.title))
        elseif away then
            ns:Print(("%s: nothing left here for your level. Head to %s (levels %d-%d)."):format(
                guide.name, section.title, section.from, section.to))
        else
            ns:Print(("%s: %s (levels %d-%d)."):format(guide.name, section.title, section.from, section.to))
        end
    elseif not section and lastSection then
        lastSection = nil
        ns:Print(guide.name .. ": no zone has quests worth doing at your level right now.")
    end
    local step = self.current and self.steps[self.current]
    if step and step[1] == "L" and step.inside and not step.again and inst then
        local wings = ns.Instance:RouteWings(inst)
        C_Timer.After(0.5, function() ns.Instance:AskAgain(inst, step.wing or wings[#wings]) end)
    end
    local key = step and StepKey(step)
    -- (Not before the quest log is in: a plan made without it isn't where you left off.)
    if logReady then ns.char.onStep = key end
    -- (A task doesn't take over: the step you were on stays yours underneath it, and comes back after.)
    if not (key and inArea[key]) and not (step and step.with) then holdKey, holdStep = key, step end
    if not (step and step[1] == "Z") then
        if not (key and inArea[key]) then trip = nil end -- (a quick stop on the way isn't the end of the trip)
    elseif not (trip and trip.key == key and trip.planned) then
        -- (What it's for: the first step you can do once you're there. Only the finished plan can say:
        -- until then the steps are in the guide's order, and the first of those may be the far end of
        -- the zone.)
        local planned = not job and not orderDirty and order and order.section == section.id
        local after
        for i = self.current + 1, #self.steps do
            local s = self.steps[i]
            if s[1] ~= "Z" and not self:StepDone(s) and not Waits(s) then after = s; break end
        end
        -- (Rerouted on the way, by another zone: the step it's for is the same one, if that's still to do.)
        local target, kept = planned and trip and trip.target, nil
        for _, s in ipairs(self.steps) do
            if StepKey(s) == target and not self:StepDone(s) then kept = s end
        end
        local goal = planned and (kept or after) or nil
        trip = { key = key, from = trip and trip.from or CurrentZone(), planned = planned,
            target = goal and StepKey(goal) or nil, step = goal }
    end
    -- The task's list got shorter: the arrow's text follows.
    local text = step and step.with and select(2, self:Describe(step)) or nil
    if text ~= lastTask then
        lastTask = text
        if key == lastKey then PointArrow(step) end
    end
    if key == lastKey and key ~= stoppedKey and not ns.char.paused and lastPlan
        and (table.concat(self:Plan(), "|") ~= lastPlan or StopsKey(NextStops()) ~= lastStops) then
        local mine = Waypoint and Waypoint.Get and Waypoint:Get("FieldGuide")
        if mine and mine.key == key then PointArrow(step) end
    end
    if key ~= lastKey then
        lastKey, stoppedKey = key, nil
        PointArrow(step)
        if step and step[1] ~= "G" and step[1] ~= "Z" and step[1] ~= "I" then P:FocusQuestie(step[2]) end
    end
    self:SyncTracking()
end

-- Whether a step counts toward the section's total: zone changes don't, and neither do the
-- turn-ins and follow-ups of an item found inside until you have its quest (or did it).
function E:Counts(s)
    if s[1] == "Z" or s.later then return false end
    if s.inside and s[1] ~= "L" then
        local id = s[2]
        if P:Done(id) or P:InLog(id) then return true end
        return s[1] == "A" and not Unavailable(id)
    end
    return true
end

-- Quest tracking: the guide tracks the quests in your log that its current and next steps are
-- about, and untracks the others that aren't yours (quests you tracked yourself stay, and one you
-- untracked yourself isn't tracked again; and nothing is untracked while none of the guide's
-- quests are in your log). Off with ns.db.manageTracking, or while paused.
local TRACK_AHEAD = 5
function E:SyncTracking()
    if not (ns.db.manageTracking and Waypoint and Waypoint.TrackQuest and Waypoint.TrackedQuests) or ns.char.paused then return end
    local want, n = {}, 0
    for i = self.current or 1, #self.steps do
        if n >= TRACK_AHEAD then break end
        local s = self.steps[i]
        if s[1] ~= "G" and s[1] ~= "Z" and s[1] ~= "I" and not self:StepDone(s) then
            n = n + 1
            if P:InLog(s[2]) then want[s[2]] = true end
        end
    end
    -- A dungeon route's run: its quests in your log.
    local step = self.current and self.steps[self.current]
    if step and step[1] == "I" then
        for _, id in ipairs(step.needs or {}) do
            if P:InLog(id) then want[id] = true end
        end
    end
    for id in pairs(want) do Waypoint:TrackQuest("FieldGuide", id) end
    -- Nothing of the guide's in your log (a travel stretch: "Go to Desolace"): leave tracking as it
    -- is. Untracking everything empties Questie's tracker, and Questie then hides it altogether,
    -- header and all, so there's nothing left to click to bring it back.
    if not next(want) then return end
    for id, by in pairs(Waypoint:TrackedQuests()) do
        if by ~= "user" and not want[id] then Waypoint:UntrackQuest("FieldGuide", id) end
    end
end

-- The step you're on: its key, or nil. (Nearby pick-ups that come first aren't it.)
function E:Held() return holdKey end

-- What a trip you're on is for: its step's key, or nil.
function E:TripTarget() return trip and trip.target end

-- Zone Clear: quests finished and in all on the zone (those above your level count too), or nil.
function E:ZoneProgress()
    if not (self.section and self.section.zoneClear) then return nil end
    local done, total, seen = 0, 0, {}
    for _, s in ipairs(self.steps) do
        local id = s[1] ~= "G" and s[1] ~= "Z" and s[1] ~= "I" and s[2]
        if id and not seen[id] then
            seen[id] = true
            if P:Done(id) then
                done, total = done + 1, total + 1
            elseif not Unavailable(id) then
                total = total + 1
            end
        end
    end
    return done, total
end

-- Steps done and total in the current section.
function E:Progress()
    local done, total = 0, 0
    for _, s in ipairs(self.steps) do
        if self:Counts(s) then
            total = total + 1
            if self:StepDone(s) then done = done + 1 end
        end
    end
    return done, total
end

-- Off course: you keep moving and don't get any closer to the step you're on. Measured along the
-- arrow's planned trip when there is one (going round a cliff isn't going away), else in a straight
-- line. The clock only runs while you're moving and out of combat: stopping or a fight stops it, it
-- doesn't reset it. Getting closer than you've been resets it, and so does being at work near an
-- objective. When it runs out, the route is worked out again from where you are.
local course

local function NearestObjective(step, at)
    local best
    for _, s in ipairs(step.with or { step }) do
        local q = s[1] == "O" and Q(s[2])
        for _, o in ipairs(q and (s.part and q.g[s.part].p or q.o) or {}) do
            local yards = Yards(at, World(o))
            if yards and (not best or yards < best) then best = yards end
        end
    end
    return best
end

function E:Clock() return course and course.clock or "reset" end

function E:CheckCourse(seconds)
    local step = self.current and self.steps[self.current]
    if not step or ns.char.paused or ns.char.instance or (UnitOnTaxi and UnitOnTaxi("player")) then
        course = nil
        return
    end
    local key = StepKey(step)
    if not (course and course.key == key) then course = { key = key, clock = 0 } end
    if UnitAffectingCombat("player") or (GetUnitSpeed("player") or 0) == 0 then return end
    local c, n, w = ns.WorldMap.Player()
    if not c then return end
    local at = { c, n, w }
    local target = step[1] == "Z" and self.steps[self.current + 1] or step
    local near = NearestObjective(step, at)
    if near and near <= AT_WORK_YARDS then
        course.clock, course.best = 0, nil
        return
    end
    local left = (Waypoint and Waypoint.RouteYards and Waypoint:RouteYards(c, n, w))
        or (target and Yards(at, StepSpot(target))) or near
    if not left then return end
    if not course.best or left < course.best - 5 then
        course.best, course.clock = left, 0
        return
    end
    course.clock = course.clock + seconds
    if course.clock >= OFF_COURSE_SECONDS then
        course = nil
        group, holdKey = nil, nil
        orderDirty, pickDirty, relocate = true, true, true
        ns:Changed()
    end
end

-- Leveling or Zone Clear: a change of aim, so everything's worked out again from where you are.
function E:SetPreference(mode)
    if ns.char.preference == mode then return end
    orderDirty, pickDirty, relocate = true, true, true
    group, stay, holdKey = nil, nil, nil
    ns:SetOption("char.preference", mode) -- (the options page shows it, and works the route out again)
end

-- Skipping a trip. Still in the zone you were leaving: the guide works out what you can do here
-- without leaving, and asks if that's nothing. Already gone: it starts from where you are.
function E:SkipTravel(step)
    local zone = CurrentZone()
    holdKey = nil
    orderDirty, pickDirty = true, true
    local from = trip and trip.from or step.from
    trip = nil
    if from and zone == from then
        stay = { zone = zone, section = self.section }
        ns:Print("Trip skipped: staying here.")
    else
        relocate = true
        ns:Print("Trip skipped: working it out from where you are.")
    end
    ns:Changed()
end

-- Nothing left here without leaving: wait, or go back to following the route.
StaticPopupDialogs["FIELDGUIDE_STAY"] = {
    text = "%s", button1 = "Wait for a new zone", button2 = "Back to the route",
    OnAccept = function() E:WaitForZone() end,
    OnCancel = function() E:BackToRoute() end,
    timeout = 0, whileDead = 1, preferredIndex = 3,
}

function E:AskStay()
    local info = stay and C_Map.GetMapInfo(stay.zone)
    StaticPopup_Show("FIELDGUIDE_STAY", ("There's nothing left to do in %s without leaving it.\n\n"
        .. "Wait here and the guide will resume when you enter a new zone, or go back to the route and carry on as planned."):format(
        info and info.name or "this zone"))
end

function E:WaitForZone()
    ns.char.waitZone = stay and stay.zone or CurrentZone()
    self:SetPaused(true)
end

function E:BackToRoute()
    stay = nil
    orderDirty, pickDirty = true, true
    ns:Changed()
end

function E:SkipCurrent()
    local step = self.current and self.steps[self.current]
    if not step then return end
    if step[1] == "Z" and not step.exitStep then return self:SkipTravel(step) end
    -- A quest goes whole (pick up, objectives, hand in): Field Guide doesn't suggest it again, nor
    -- what needs it first. Yours to do on your own if you want it later (/fg unskip undoes it).
    if step[1] ~= "G" and step[1] ~= "Z" and step[1] ~= "I" then
        -- Zone Clear means every quest: the first skip only puts it off until the rest are done.
        if Clearing() and not ns.char.instance and not ns.char.deferred[step[2]] then
            ns.char.deferred[step[2]] = true
            pickDirty, orderDirty, holdKey = true, true, nil
            ns:Print(("%s moved to the end of the list. Skip it again to drop it."):format(self:QuestName(step[2])))
            return ns:Changed()
        end
        ns.char.deferred[step[2]] = nil
        ns.char.ignored[step[2]] = true
        pickDirty, orderDirty = true, true
        ns:Print(("Skipped %s%s. Field Guide won't suggest it again (/fg unskip brings it back)."):format(
            self:QuestName(step[2]), DonationCloth(Q(step[2])) and ": your cloth stays with you" or ""))
        return ns:Changed()
    end
    -- Grinding, travelling, a dungeon run: just this step.
    ns.char.skipped[StepKey(step)] = true
    pickDirty, orderDirty = true, true
    local verb, name = self:Describe(step)
    ns:Print(("Skipped %s: %s. /fg unskip brings skipped steps back."):format(strlower(verb), name))
    ns:Changed()
end

-- "Done it": the current step's quest is finished, whatever the game's record says. Every step of
-- it goes away, and quests that needed it count it as done.
function E:MarkDone()
    local step = self.current and self.steps[self.current]
    if not step or step[1] == "G" or step[1] == "Z" or step[1] == "I" then return end
    local id = step[2]
    ns.char.doneByHand[id] = true
    pickDirty, orderDirty = true, true
    ns:Print(("Marked %s as done. /fg unskip brings it back."):format(Q(id) and Q(id).n or ("quest " .. id)))
    ns:Changed()
end

function E:ChooseGuide(arg)
    pickDirty = true
    arg = strtrim(arg or "")
    if arg == "" or strlower(arg) == "auto" then
        ns.char.guide, ns.char.section = nil, nil
        ns:Print("Following your faction's guide.")
    else
        local g = GuideByKey(arg)
        if not g then
            ns:Print("No guide called " .. arg .. ". /fg list shows them.")
            return
        end
        ns.char.guide, ns.char.section = g.key, nil
        ns:Print("Following " .. g.name .. ".")
    end
    ns:OptionChanged("char.section") -- Options > AddOns > Field Guide shows the zone (and calls ns:Changed)
end

-- The settings' zone dropdown: a section id, or nil for automatic.
function E:SetSection(id)
    pickDirty = true
    local guide = self:Guide()
    local chosen
    for _, s in ipairs(guide and guide.sections or {}) do
        if s.id == id then chosen = s end
    end
    ns.char.section = chosen and chosen.id or nil
    ns:Print(chosen and ("Following " .. chosen.title .. ". Pick Automatic in the settings (or /fg section auto) to go back.")
        or "Following the next section worth doing.")
    ns:OptionChanged("char.section")
end

function E:ChooseSection(arg)
    pickDirty = true
    arg = strlower(strtrim(arg or ""))
    local guide = self:Guide()
    if arg == "" or arg == "auto" or not guide then
        ns.char.section = nil
        ns:Print("Following the next section worth doing.")
    else
        local s = guide.sections[tonumber(arg) or 0]
        if not s then
            ns:Print("No section " .. arg .. ". /fg list shows them.")
            return
        end
        ns.char.section = s.id
        ns:Print("Following " .. s.title .. ".")
    end
    ns:OptionChanged("char.section") -- /fg section: the page's zone dropdown follows
end

function E:PrintList()
    P = P or ns.Progress
    local mine = self:Guide()
    for _, g in ipairs(ns.Guides) do
        ns:Print(("%s%s (%s)%s"):format(g == mine and "|cff8fd16a" or "", g.name, g.faction, g == mine and "|r" or ""))
        for i, s in ipairs(g.sections) do
            print(("   %d. %s, levels %d-%d, about %d min%s"):format(i, s.title, s.from, s.to, s.minutes or 0,
                s == self.section and "  |cff8fd16a<- now|r" or ""))
        end
    end
end

-- Enough cloth for a donation in your bags (or not any more): the plan changes.
local clothReady = {}
ns:On("BAG_UPDATE_DELAYED", function()
    if not (ns.db and GetItemCount) then return end
    local changed = false
    for _, item in pairs(CLOTH) do
        local ready = (GetItemCount(item) or 0) >= DONATION_COUNT
        if clothReady[item] ~= ready then
            if clothReady[item] ~= nil then changed = true end
            clothReady[item] = ready
        end
    end
    if changed then
        E:Invalidate()
        ns:Changed()
    end
end)
