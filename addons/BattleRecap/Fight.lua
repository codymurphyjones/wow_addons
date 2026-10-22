local _, ns = ...

-- Keeps one fight together when combat drops in the middle of it: a rogue vanishes, combat ends,
-- they open on you again a few seconds later. The game starts a new damage-meter session each time
-- combat ends (and Details can wipe the meter after combat), so the damage from before the drop
-- would be lost. Each combat is kept here for a few minutes instead, with the damage you took and
-- did read from the meter as soon as it's readable. A combat that ended shortly before the next one
-- started is part of the same fight:
--   GRACE seconds apart, or SAME_ENEMY_GRACE when someone who hit you then hits you again.
local F = {}
ns.Fight = F

local GRACE = 10
local SAME_ENEMY_GRACE = 30
local KEEP_SECONDS = 180  -- combats older than this are forgotten
local MAX_SEGMENTS = 10
local READ_TRIES, READ_DELAY = 8, 1

F.GRACE, F.SAME_ENEMY_GRACE = GRACE, SAME_ENEMY_GRACE

local segments = {} -- oldest first: { start, startServer, finish, finishServer, sessionID, taken, dealt, healed,
                    --   targets, duration, attackers, read }
local current       -- the combat you're in
F._segments = segments

local function ServerNow() return GetServerTime and GetServerTime() or time() end

local function Prune()
    local now = GetTime()
    for i = #segments, 1, -1 do
        local seg = segments[i]
        if seg.finish and now - seg.finish > KEEP_SECONDS then table.remove(segments, i) end
    end
    while #segments > MAX_SEGMENTS do table.remove(segments, 1) end
end

function F:OnCombatStart()
    Prune()
    current = { start = GetTime(), startServer = ServerNow() }
    segments[#segments + 1] = current
end

function F:OnCombatEnd()
    local seg = current
    current = nil
    if not seg then return end -- a /reload in combat: that combat's start wasn't seen
    seg.finish, seg.finishServer = GetTime(), ServerNow()
    seg.sessionID = ns.Meter.NewestSessionID()
    self:ReadPending()
end

-- The meter doesn't always start a new session when combat ends: in a battleground one session can
-- run for most of the match, so what it says after a combat is everything since the session began,
-- not that combat. A reading is such a running total when it's from the same session as the combat
-- before it, or (no session ids) when the meter's session is far longer than the combat was
-- (RUNNING_SLACK). Then what the combat before it read is taken off, spell by spell, enemy by
-- enemy, healer by healer: what's left is this combat's. One with nothing before it to take off (the
-- first after a /reload) can't be told apart, and is left empty rather than wrong.
local RUNNING_SLACK, RUNNING_EXTRA = 1.5, 5

local function RowKey(r)
    return (r.src or "") .. "\001" .. tostring(r.spellId or 0) .. "\001" .. (r.spell or "") .. "\001" .. (r.pet and "p" or "")
end

-- Meter rows less what an earlier reading of the same session had (rows with nothing left dropped).
local function MinusRows(now, before)
    if not before then return now end
    local had = {}
    for _, r in ipairs(before) do had[RowKey(r)] = (had[RowKey(r)] or 0) + (r.amount or 0) end
    local out = {}
    for _, r in ipairs(now or {}) do
        local left = (r.amount or 0) - (had[RowKey(r)] or 0)
        if left > 0 then
            local c = {}
            for k, v in pairs(r) do c[k] = v end
            c.amount = left
            if c.overkill and c.overkill > left then c.overkill = left end
            out[#out + 1] = c
        end
    end
    return out
end

-- Your damage per enemy (Meter.ReadTargets rows) less an earlier reading's.
local function MinusTargets(now, before)
    if not (now and before) then return now end
    local had = {}
    for _, r in ipairs(before) do had[r.name] = r end
    local out = {}
    for _, r in ipairs(now) do
        local b = had[r.name]
        local amount = (r.amount or 0) - (b and b.amount or 0)
        if amount > 0 then
            out[#out + 1] = { name = r.name, class = r.class, amount = amount,
                total = r.total and math.max(0, r.total - (b and b.total or 0)) or nil }
        end
    end
    return out
end

-- Who healed whom (Meter.ReadLedger) less an earlier reading's.
local function MinusLedger(now, before)
    if not (now and before) then return now end
    local out = {}
    for name, h in pairs(now) do
        local b = before[name]
        local total = h.total - (b and b.total or 0)
        if total > 0 then
            local targets = {}
            for target, amount in pairs(h.targets or {}) do
                local left = amount - (b and b.targets and b.targets[target] or 0)
                if left > 0 then targets[target] = left end
            end
            out[name] = { total = total, class = h.class, ally = h.ally, targets = targets }
        end
    end
    return out
end

-- The combat read just before seg (its raw reading is what a running total is taken off from); the
-- last one read is kept even once it's been forgotten (a quiet spell longer than KEEP_SECONDS).
local lastRead
local function Before(seg)
    for i = #segments, 1, -1 do
        if segments[i] == seg then
            for j = i - 1, 1, -1 do
                if segments[j].raw then return segments[j] end
            end
            break
        end
    end
    return lastRead ~= seg and lastRead or nil
end

-- true when read, false while the meter still hides it. Without a session id only the newest
-- combat can be read (as the meter's current session); an older one is given up on.
local function TryRead(seg)
    if not ns.Meter.Available() or (not seg.sessionID and seg ~= segments[#segments]) then
        seg.failed = true
        return true
    end
    local takenType, doneType = ns.Meter.Types()
    local taken, r1, duration = ns.Meter.ReadSpells(takenType, seg.sessionID)
    local dealt, r2 = ns.Meter.ReadSpells(doneType, seg.sessionID)
    if r1 == "secret" or r2 == "secret" then return false end
    local raw = { taken = taken or {}, dealt = dealt or {}, healed = ns.Meter.ReadHealing(seg.sessionID),
        targets = ns.Meter.ReadTargets(seg.sessionID), ledger = ns.Meter.ReadLedger(seg.sessionID) }
    seg.raw = raw
    local prev = Before(seg)
    lastRead = seg
    local measured = math.max(0.1, seg.finish - seg.start)
    local long = (duration or 0) > measured * RUNNING_SLACK + RUNNING_EXTRA
    local otherSession = seg.sessionID and prev and prev.sessionID and prev.sessionID ~= seg.sessionID
    local running = (prev and seg.sessionID and prev.sessionID == seg.sessionID) or (long and not otherSession)
    if running and prev then
        local b = prev.raw
        seg.taken, seg.dealt = MinusRows(raw.taken, b.taken), MinusRows(raw.dealt, b.dealt)
        seg.healed = raw.healed and MinusRows(raw.healed, b.healed) or nil
        seg.targets, seg.ledger = MinusTargets(raw.targets, b.targets), MinusLedger(raw.ledger, b.ledger)
    elseif running then
        seg.taken, seg.dealt, seg.healed, seg.targets, seg.ledger = {}, {}, nil, nil, nil -- no way to tell this combat's share
    else
        seg.taken, seg.dealt, seg.healed, seg.targets, seg.ledger = raw.taken, raw.dealt, raw.healed, raw.targets, raw.ledger
    end
    -- How long it lasted: the meter's own count, unless that's the whole running session.
    seg.duration = (running or long or not duration) and measured or duration
    seg.attackers = {}
    for _, r in ipairs(seg.taken) do seg.attackers[r.src] = true end
    seg.read = true
    return true
end

local function Unread()
    for _, seg in ipairs(segments) do
        if seg.finish and not seg.read and not seg.failed then return true end
    end
    return false
end

-- Reads every finished combat not read yet, retrying while out of combat. What's still unread when
-- combat starts again is tried after the next one ends (by session id).
local reading = false
function F:ReadPending()
    if reading then return end
    reading = true
    local attempt = 0
    local function Try()
        attempt = attempt + 1
        local waiting = InCombatLockdown()
        if not waiting then
            for _, seg in ipairs(segments) do
                if seg.finish and not seg.read and not seg.failed and not TryRead(seg) then waiting = true end
            end
        end
        if waiting and attempt < READ_TRIES and not InCombatLockdown() then
            C_Timer.After(READ_DELAY, Try)
        else
            reading = false
        end
    end
    C_Timer.After(0.5, Try)
end

-- Calls done() once the finished combats have been read (or after a few seconds).
function F:Settle(done)
    local checks = 0
    local function Check()
        checks = checks + 1
        if Unread() and checks < 8 and not InCombatLockdown() then
            C_Timer.After(0.5, Check)
        else
            done()
        end
    end
    Check()
end

-- The newest finished combat, when it ended at or after `since` (GetTime clock) and was read.
function F:LastSince(since)
    local seg = segments[#segments]
    if seg and seg ~= current and seg.read and seg.finish and seg.finish >= since then return seg end
end

-- When the newest combat started (GetTime clock), or nil.
function F:CurrentStart()
    local seg = current or segments[#segments]
    return seg and seg.start
end

-- The earlier combats of the fight that was going on at time `before` (the start of its last
-- combat), newest first, and how long combat had dropped before the last one. attackers is a set
-- of the names that hit you in that last combat.
function F:Earlier(before, attackers)
    local chain, gaps = {}, {}
    if not before then return chain, nil end
    -- Names from the death recap and the meter may differ in shape ("Given Family", "GivenFamily"):
    -- compared compactly.
    local function C(name) return ns.Units.Compact(name) or name end
    local later = {}
    for name in pairs(attackers or {}) do later[C(name)] = true end
    local nextStart = before
    for i = #segments, 1, -1 do
        local seg = segments[i]
        if seg.finish and seg.finish <= nextStart + 0.05 then
            local gap = math.max(0, nextStart - seg.finish)
            local same = false
            for name in pairs(seg.attackers or {}) do
                if later[C(name)] then same = true; break end
            end
            if gap > (same and SAME_ENEMY_GRACE or GRACE) then break end
            if seg.read then
                chain[#chain + 1] = seg
                gaps[#gaps + 1] = gap
                for name in pairs(seg.attackers) do later[C(name)] = true end
            end
            nextStart = seg.start
        end
    end
    return chain, gaps[1]
end

-- A set of the attackers' names in meter rows.
function F.Names(rows)
    local set = {}
    for _, r in ipairs(rows or {}) do set[r.src] = true end
    return set
end
