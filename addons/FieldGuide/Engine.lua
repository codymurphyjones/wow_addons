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
-- Steps (from Guides\*.lua): { "A", quest } pick up, { "O", quest } objectives, { "T", quest }
-- turn in, { "G", level } grind to a level, { "Z", uiMapID } travel to another zone, and (made
-- here) { "L", quest } loot the item that starts a quest, { "I", dungeon } run a dungeon.
local E = {}
ns.Engine = E

local P
local MIN_SHARE = 0.015 -- a quest is shown when it pays at least this share of your next level
-- Automatic considers a zone's guide when its levels come within RANGE of yours, up or down (8 in
-- all), and prefers the ones whose quests are at your level to 2 above (see Score). A zone you
-- pick yourself always shows; for one quest in an old zone, Questie has you covered.
local RANGE = 4
local TARGET = 2 -- the ideal: quests from your level up to this many above
local REACH = 3  -- a quest on a route shows when it needs at most this many levels over yours
local CATCHUP = 6 -- quests needed first are only routed to when they need at most this many over yours

-- The section's levels come within RANGE of yours.
local function InRange(s, level)
    return (s.from or 1) <= level + RANGE and (s.to or 60) >= level - RANGE
end

-- How well a section's levels suit you: 0 when it covers your level to TARGET above; otherwise
-- how far off it is, a section under you counting double (you'd be catching up, not leveling).
local function Score(s, level)
    local from, to = s.from or 1, s.to or 60
    if to < level then return (level - to) * 2 end
    if from > level + TARGET then return from - (level + TARGET) end
    return 0
end

-- Walking into a zone whose guide doesn't suit your level right now (it ends under your level, or
-- starts more than TARGET above it) is travel, or something specific Questie can guide you
-- through: the zone you were on stays.
local function Passing(s, level) return Score(s, level) > 0 end

-- XP to go from level i to i + 1 (Classic).
local XP_TO_LEVEL = { 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400,
    16000, 17700, 19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400,
    50800, 54500, 58600, 62800, 67100, 71600, 76100, 80900, 85700, 90700, 95800, 101000, 106300, 111800,
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

local function StepKey(step) return step[1] .. ":" .. tostring(step[2]) .. (step.wing and (":" .. step.wing) or "") end

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
    if not pq or not P:RaceAllowed(pq.rm) or ns.char.ignored[p] then return false end
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
    if q and Unreachable(q, 0) then return true end
    return q and PrereqsDone(q) and not P:Doable(id)
end

E.Unavailable = function(_, id) return Unavailable(id) end

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
    if kind == "O" then return P:ReadyToTurnIn(id) or not (Q(id) and Q(id).o) and P:InLog(id) end
    return false
end

-- ---------------------------------------------------------------------------------------------
-- Building the section's steps, with what it needs first
-- ---------------------------------------------------------------------------------------------

-- Quests a quest needs that you haven't done, deepest first.
local function Missing(id, out, seen, depth)
    local q = Q(id)
    if not q or not q.pre or depth > 25 then return end
    local list = q.pre
    if q.preAny then
        for _, p in ipairs(q.pre) do if P:Done(p) or P:InLog(p) then return end end
        list = {}
        for _, p in ipairs(q.pre) do
            if Q(p) and P:RaceAllowed(Q(p).rm) then list = { p }; break end
        end
    end
    for _, p in ipairs(list) do
        if not seen[p] and Q(p) and P:RaceAllowed(Q(p).rm) and not P:Done(p) then
            seen[p] = true
            Missing(p, out, seen, depth + 1)
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

-- Which of a section's quests to show: those worth the XP at your level, those in your log, and
-- anything a shown quest needs first.
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
    for _, s in ipairs(section.steps) do
        local id = s[2]
        -- Within reach: a quest needing more than REACH levels over yours waits (a higher quest pays
        -- more XP, so Worth alone would show a level 50 quest at 30, and every quest it needs first
        -- with it as "missed earlier").
        local reach = (Q(id) and Q(id).r or 1) <= level + REACH
        if s[1] == "A" and not show[id] and not (Q(id) and Q(id).dq) and not NeedsDungeon(id, 0)
            and ((reach and Worth(id, level) and DonationReady(Q(id))) or P:InLog(id)) then
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
-- take that leads to the zone best suited to the level (see Score).
local function PickExit(guide, zone, level)
    local list = guide and guide.exits and guide.exits[zone]
    if not list then return nil end
    local best, bestS
    for _, e in ipairs(list) do
        local id, q = e[1], Q(e[1])
        if q and q.dq then
            -- a dungeon's quest is never a way out of a zone
        elseif q and P:InLog(id) then return e
        -- (Taken now, so within reach of the level you are now, whatever level it's chosen for.)
        elseif q and (q.r or 1) <= math.min(level, P:Level() + REACH) and E:QuestOpen(id) and PrereqsDone(q) then
            local s = SectionFor(guide, e[2], level)
            if s and (not best or Score(s, level) < Score(bestS, level)) then best, bestS = e, s end
        end
    end
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

-- Quests in your log that you turn in in this zone but that aren't part of its route (a
-- hand-off that brought you here, or one picked up elsewhere).
local function TurnInsHere(section, inSection, steps)
    for _, id in ipairs(P:LogQuests()) do
        local q = Q(id)
        -- Ready: its objectives are done, or it has none (the game's word; Questie's spots only
        -- when the game can't say, since a quest done inside a dungeon has none outside).
        local none = P:NoObjectives(id)
        local ready = P:ReadyToTurnIn(id) or none == true or (none == nil and not q.o)
        if q and not q.dq and q.t and q.t[1] == section.zone and not inSection[id] and ready then
            steps[#steps + 1] = { "T", id }
            inSection[id] = true
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
    local missing, seen = {}, {}
    for _, s in ipairs(section.steps) do
        -- (Not for a quest you can't get yet: its missing part may only drop inside a dungeon.)
        if s[1] == "A" and show[s[2]] and not Unavailable(s[2]) and not P:InLog(s[2]) then
            -- What it needs first, on its own: routed to only when every quest in it needs at most
            -- CATCHUP levels over yours. Otherwise the quest waits too (it can't be done before them).
            local chain, mine = {}, {}
            for id in pairs(seen) do mine[id] = true end
            Missing(s[2], chain, mine, 0)
            local near = true
            for _, id in ipairs(chain) do
                if (Q(id).r or 1) > level + CATCHUP then near = false; break end
            end
            if near then
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
        if e and not inSection[e[1]] then ExitSteps(e, steps) end
    end
    -- A zone change with nothing after it (its quests were left out at your level) goes too:
    -- otherwise a section of nothing but "Go to ..." would look like it had work left.
    local kept = {}
    for i, s in ipairs(steps) do
        local nxt = steps[i + 1]
        if s[1] ~= "Z" or (nxt and nxt[1] ~= "Z") then kept[#kept + 1] = s end
    end
    return kept
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

-- The first step left; a zone change counts as done once a step after it is, or once you're there.
local function FirstLeft(steps)
    for i, s in ipairs(steps) do
        if s[1] == "Z" then
            local after = steps[i + 1]
            if after and not E:StepDone(after) then
                if CurrentZone() ~= s[2] and C_Map.GetBestMapForUnit("player") ~= s[2] then return i end
            end
        elseif not E:StepDone(s) then
            return i
        end
    end
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
function E:Invalidate() pickDirty = true end

local travel -- the section that hands you off from a zone that's done for your level

function E:PickSection(guide)
    lastPick = lastPick or ns.char.lastPick -- the zone you were on, across a /reload
    if not pickDirty and lastPick then
        if travel and travel.id == lastPick and Remaining(travel) then return travel end
        for _, s in ipairs(guide.sections) do
            if s.id == lastPick and Remaining(s) then return s end
        end
    end
    if ns.char.section then
        pickDirty = false
        for _, s in ipairs(guide.sections) do
            if s.id == ns.char.section then return s end
        end
    end
    -- On a flight: nothing changes until you land.
    if lastPick and UnitOnTaxi and UnitOnTaxi("player") then
        if travel and travel.id == lastPick then return travel end
        for _, s in ipairs(guide.sections) do
            if s.id == lastPick then return s end
        end
    end
    pickDirty = false
    local level, zone = P:Level(), CurrentZone()
    local keep, here, passing
    for _, s in ipairs(guide.sections) do
        if s.zone == zone then
            -- The zone you're in takes over when it suits your level now (your level to 2 above);
            -- one under or well over your level you're passing through: the zone you were on stays.
            if Passing(s, level) then
                passing = true
            elseif Fits(s, level) then
                here = here or s
            end
        end
        if s.id == lastPick and Fits(s, level) then keep = s end
    end
    if here then return here end
    if keep then return keep end
    -- Nothing left here for your level: a quest that takes you on from here, if there is one
    -- (not from a zone you're only passing through).
    local e = not passing and PickExit(guide, zone, level)
    if e then
        local info = C_Map.GetMapInfo(e[2])
        local name = info and info.name or "the next zone"
        travel = { id = "exit-" .. e[1], travel = true, zone = zone, from = level, to = level,
            title = "On to " .. name, steps = ExitSteps(e, {}),
            note = ("Nothing left here for level %d: %s takes you on to %s."):format(level, Q(e[1]).n or "a quest", name) }
        return travel
    end
    -- Otherwise the zone that suits your level best (your level to 2 above), the nearest of those.
    local best, bestScore, bestD
    for _, s in ipairs(guide.sections) do
        if Fits(s, level) then
            local score, d = Score(s, level), DistanceTo(s.zone) or math.huge
            if not best or score < bestScore or (score == bestScore and d < bestD) then
                best, bestScore, bestD = s, score, d
            end
        end
    end
    return best
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
        return "Travel", "Go to " .. name, "The next quests are in " .. name .. ".", nil
    end
    local q = Q(id) or {}
    local name = E:QuestName(id)
    if kind == "A" then
        local d = ("%s, %s"):format(q.a and q.a[4] or "?", Where(q.a))
        local xp = QuestXP(q, P:Level())
        if xp > 0 then d = d .. ("  |cff8a948e(%d XP)|r"):format(xp) end
        if (q.r or 1) > P:Level() then d = ("Needs level %d. %s"):format(q.r, d) end
        return "Pick up", name, d, q.a and { { q.a[1], q.a[2] / 100, q.a[3] / 100 } }
    elseif kind == "O" then
        local points = {}
        for _, o in ipairs(q.o or {}) do points[#points + 1] = { o[1], o[2] / 100, o[3] / 100 } end
        local detail = q.ot or ""
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

local lastSection, lastKey
local stoppedKey -- the step you told the arrow to stop pointing at (right-click); the next step points again

-- Sends the step to Waypoint's arrow. False when it has nowhere to point.
local lastPlan -- the plan last handed to Waypoint, joined

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
        if not self:StepDone(s) then out[#out + 1] = StepKey(s) end
    end
    return out
end

local function PointArrow(step)
    if not (Waypoint and Waypoint.Set) then return false end
    if not step or ns.char.paused then
        Waypoint:Clear("FieldGuide")
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
        return false
    end
    local wp = { key = StepKey(step), title = verb .. ": " .. name, subtitle = detail, arrive = target[1] == "O" and 30 or 12,
        color = ns.char.instance and "purple" or "green", -- a dungeon's route, or the leveling guide
        onClick = function() ns.db.shown = true; ns:Changed() end, points = {} }
    -- The step after this one, for the arrow's tooltip.
    for i = (E.current or 0) + 1, #E.steps do
        local s = E.steps[i]
        if s ~= target and s[1] ~= "Z" and not E:StepDone(s) then
            local nVerb, nName = E:Describe(s)
            wp.next = nVerb .. ": " .. nName
            break
        end
    end
    -- What Waypoint compares against to tell whether you changed the arrow (see Plan).
    wp.plan = E:Plan()
    lastPlan = table.concat(wp.plan, "|")
    for _, p in ipairs(points) do wp.points[#wp.points + 1] = { mapID = p[1], x = p[2], y = p[3] } end
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

ns:On("PLAYER_LOGIN", function()
    if Waypoint and Waypoint.RegisterCallback then Waypoint:RegisterCallback("FieldGuide", OnWaypoint) end
    PlayButton()
    Own()
    C_Timer.NewTicker(2, function() if ns.db then E:CheckArrow() end end)
end)

function E:Update()
    if not ns.db then return end
    P = P or ns.Progress
    local guide = self:Guide()
    self.guide = guide
    if not guide then
        self.section, self.steps, self.current = nil, {}, nil
        PointArrow(nil)
        return
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
    self.steps = section and Build(section) or {}
    -- A section in another zone starts with going there.
    local away = section and not section.instance and not section.travel and section.zone ~= CurrentZone()
    if away and self.steps[1] and self.steps[1][1] ~= "Z" then
        local steps = { { "Z", section.zone } }
        for _, s in ipairs(self.steps) do steps[#steps + 1] = s end
        self.steps = steps
    end
    NumberParts(self.steps)
    self.current = FirstLeft(self.steps)
    if section and section.id ~= lastSection then
        lastSection = section.id
        if section.note then
            ns:Print(guide.name .. ": " .. section.note)
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
    if key == lastKey and key ~= stoppedKey and not ns.char.paused and lastPlan
        and table.concat(self:Plan(), "|") ~= lastPlan then
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
    if s[1] == "Z" then return false end
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

function E:SkipCurrent()
    local step = self.current and self.steps[self.current]
    if not step then return end
    -- A quest goes whole (pick up, objectives, hand in): Field Guide doesn't suggest it again, nor
    -- what needs it first. Yours to do on your own if you want it later (/fg unskip undoes it).
    if step[1] ~= "G" and step[1] ~= "Z" and step[1] ~= "I" then
        ns.char.ignored[step[2]] = true
        pickDirty = true
        ns:Print(("Skipped %s%s. Field Guide won't suggest it again (/fg unskip brings it back)."):format(
            self:QuestName(step[2]), DonationCloth(Q(step[2])) and ": your cloth stays with you" or ""))
        return ns:Changed()
    end
    -- Grinding, travelling, a dungeon run: just this step.
    ns.char.skipped[StepKey(step)] = true
    pickDirty = true
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
    pickDirty = true
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
