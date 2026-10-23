local _, ns = ...
local C = ns.Compat

-- Where each boat and zeppelin is in its loop (Route.lua's timetables, Data\Transit.lua's routes).
--
-- A route's loop runs the same from one server restart to the next, so one sighting tells where its
-- boat is for days, not hours. A sighting: a boat leaving a dock (you were carried off it), as the
-- server time its loop began. Each route keeps its last MAX_SIGHTINGS (ns.db.loops[name].seen), for
-- every character; a sighting from before the last weekly reset (servers restart then) is dropped.
--
-- The loop's length comes from the world database, which may be a little off the live servers'.
-- So with two sightings or more, the length is fitted to them (whole loops apart; within MAX_DRIFT
-- of the database's), and the newest sighting fixes where the loop starts: a timetable grows more
-- exact the more it's seen (Fit). Each knows how far it may be off by now; past a quarter loop it's
-- unknown again (with one sighting, about a day). A sighting that fits none of the others (MISFIT
-- seconds off, beyond that) means the server restarted since: the others are dropped.
--
-- Sightings are shared with your guild and group (addon messages, prefix WAYPTT, with "Share
-- waypoints" on): just the route and the time, nothing about you. Someone standing at a dock whose
-- loop they don't know asks; whoever knows answers (once a route a minute, after a short random
-- wait so not everyone does).
local TT = {}
ns.Timetable = TT

local MAX_SIGHTINGS = 12
local MAX_DRIFT = 0.005   -- a fitted loop may differ this much from the database's (half a percent)
local MISFIT = 30         -- seconds a sighting may miss the others' fit by before they're dropped
local WEEK = 7 * 86400
local ANSWER_EVERY = 60   -- seconds between answers for one route (from anyone, as heard)
local PREFIX, VER = "WAYPTT", "1"

local function Now() return (GetServerTime and GetServerTime()) or time() end

-- When the servers last restarted for the weekly reset (server time), or a week ago.
local function LastReset()
    local api = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset
    local left = api and C.Num(C.Call(api))
    if left then return Now() + left - WEEK end
    return Now() - WEEK
end

local function DB()
    ns.db.loops = type(ns.db.loops) == "table" and ns.db.loops or {}
    return ns.db.loops
end

local function Route(name)
    for _, b in ipairs(ns.Transit and ns.Transit.boats or {}) do
        if b.name == name then return b end
    end
end

-- A route's record, with old sightings (before the reset) gone: { seen = { { epoch, at, shared } },
-- period, epoch } or nil when there's none left.
local function Record(name)
    local rec = DB()[name]
    if type(rec) ~= "table" then return nil end
    -- (6-hour records from before: { epoch, at })
    if rec.epoch and not rec.seen then rec = { seen = { { epoch = rec.epoch, at = rec.at or 0 } } }; DB()[name] = rec end
    local reset = LastReset()
    local kept = {}
    for _, s in ipairs(rec.seen or {}) do
        if type(s) == "table" and s.epoch and (s.at or 0) >= reset then kept[#kept + 1] = s end
    end
    rec.seen = kept
    if #kept == 0 then
        DB()[name] = nil
        return nil
    end
    return rec
end

-- Fits the loop to a route's sightings: its length, and when (server time) the newest loop began,
-- and how sure that is (rel: the length's error, as a share of it). Sightings join newest first,
-- each only when the loops between it and the newest can't be miscounted at the length's error
-- so far (a quarter loop at most): every one that joins narrows the error, so older ones can join
-- across longer gaps. Older ones that can't are dropped: they can't be told apart from a restart.
local SEEN_ERROR = 3        -- seconds a sighting may be off (when you're noticed being carried off)
local GUESS_ERROR = 0.002   -- the database's loop length's error, before it's been fitted (0.2%)
local function Fit(b, rec)
    local seen = rec.seen
    table.sort(seen, function(x, y) return x.epoch < y.epoch end)
    -- A chain, oldest first: each next sighting joins when the loops since the last one can't be
    -- miscounted at the error so far; one that can't starts the chain again (the older ones go).
    local chain = { seen[1] }
    local period, rel = b.period, GUESS_ERROR
    local origin = seen[1].epoch
    local num, den = 0, 0
    for i = 2, #seen do
        local e = seen[i].epoch
        local last = chain[#chain].epoch
        if (e - last) * rel > period / 4 then
            chain, origin, num, den = { seen[i] }, e, 0, 0
            period, rel = b.period, GUESS_ERROR
        else
            local loops = math.floor((e - origin) / period + 0.5)
            if loops > 0 then
                num, den = num + (e - origin) * loops, den + loops * loops
                period = math.max(b.period * (1 - MAX_DRIFT), math.min(b.period * (1 + MAX_DRIFT), num / den))
                rel = math.min(GUESS_ERROR, 2 * SEEN_ERROR / (e - origin))
            end
            chain[#chain + 1] = seen[i]
        end
    end
    rec.seen, rec.period, rec.epoch, rec.rel = chain, period, chain[#chain].epoch, rel
end

-- Where a route's loop is: the server time a loop began, the loop's length (seconds), and how many
-- seconds that may be off by now. nil when it's not been seen since the reset, or so long ago
-- that it may be off by more than a quarter loop (unknown again).
function TT:Loop(b)
    local rec = Record(b.name)
    if not rec then return nil end
    if not rec.period then Fit(b, rec) end
    local off = SEEN_ERROR + (Now() - rec.epoch) * rec.rel
    if off > rec.period / 4 then return nil end
    return rec.epoch, rec.period, off
end

-- A sighting: route b's loop began at server time epoch (seen now). shared: someone else's.
-- Returns true when it was new (worth telling others).
function TT:Saw(b, epoch, shared)
    if not (b and type(epoch) == "number") then return false end
    local now = Now()
    if epoch > now + 5 or epoch < LastReset() - b.period then return false end
    local rec = Record(b.name) or { seen = {} }
    -- The same departure seen already (by you, or told twice): nothing new. One that agrees with
    -- the fit a day later is new: it makes the fit more exact.
    for _, s in ipairs(rec.seen) do
        if math.abs(s.epoch - epoch) <= SEEN_ERROR then return false end
    end
    local epochNow, period, unsure = self:Loop(b)
    if epochNow then
        local off = ((epoch - epochNow) % period + period / 2) % period - period / 2
        if math.abs(off) > MISFIT + unsure and not shared then
            -- A sighting of your own that fits none of the others: the server restarted since.
            rec.seen = {}
        elseif math.abs(off) > MISFIT + unsure then
            return false -- someone else's that doesn't fit what you've seen: theirs is likely stale
        end
    end
    table.insert(rec.seen, { epoch = epoch, at = now, shared = shared or nil })
    while #rec.seen > MAX_SIGHTINGS do
        local oldest, at = 1, rec.seen[1].at
        for i, s in ipairs(rec.seen) do if s.at < at then oldest, at = i, s.at end end
        table.remove(rec.seen, oldest)
    end
    rec.period, rec.epoch, rec.rel = nil, nil, nil
    DB()[b.name] = rec
    Fit(b, rec)
    return true
end

-- ---------------------------------------------------------------------------------------------
-- Sharing
-- ---------------------------------------------------------------------------------------------

local comm = ns.NewGroupComm and ns.NewGroupComm(PREFIX, {
    framing = "plain", version = VER, pace = 0.5, instance = "first",
    normalize = C.Full, isMe = ns.Units and ns.Units.IsMe,
})

local function Clean(name) return (name:gsub("[|]", "")) end

-- Sends "kind|rest" to your guild and your group.
local function Broadcast(kind, rest)
    if not (comm and ns.db and ns.db.share) then return end
    local wire = kind .. "|" .. VER .. "|" .. rest
    if IsInGuild and IsInGuild() then comm:SendNow(wire, "GUILD") end
    local channel = comm:Channel()
    if channel then comm:SendNow(wire, channel) end
end

local answered = {} -- route name -> GetTime() an answer was last sent or heard

-- You saw a boat leave: kept, and told to others.
function TT:Departed(b, epoch)
    if self:Saw(b, epoch, false) then
        answered[b.name] = GetTime()
        Broadcast("L", Clean(b.name) .. "|" .. math.floor(epoch + 0.5))
    end
end

-- Standing at a dock whose loop you don't know: ask (once a route every few minutes).
local asked = {}
function TT:Ask(b)
    if not b or self:Loop(b) then return end
    if asked[b.name] and GetTime() - asked[b.name] < 300 then return end
    asked[b.name] = GetTime()
    Broadcast("Q", Clean(b.name))
end

if comm then
    -- L|name|epoch: someone's sighting.
    comm:On("L", function(_, _, m)
        local name, epoch = m.fields and m.fields[3], tonumber(m.fields and m.fields[4]) -- fields: kind, version, ...
        local b = name and Route(name)
        if b and epoch then
            answered[b.name] = GetTime()
            TT:Saw(b, epoch, true)
        end
    end)
    -- Q|name: someone asks; answer after a random moment, unless someone else did.
    comm:On("Q", function(_, _, m)
        local name = m.fields and m.fields[3]
        local b = name and Route(name)
        local epoch = b and TT:Loop(b)
        if not epoch then return end
        C_Timer.After(1 + math.random() * 4, function()
            if answered[b.name] and GetTime() - answered[b.name] < ANSWER_EVERY then return end
            answered[b.name] = GetTime()
            Broadcast("L", Clean(b.name) .. "|" .. math.floor((TT:Loop(b)) + 0.5))
        end)
    end)
end
