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
    seg.taken, seg.dealt, seg.duration = taken or {}, dealt or {}, duration or (seg.finish - seg.start)
    seg.healed, seg.targets = ns.Meter.ReadHealing(seg.sessionID), ns.Meter.ReadTargets(seg.sessionID)
    seg.ledger = ns.Meter.ReadLedger(seg.sessionID)
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
    local later = {}
    for name in pairs(attackers or {}) do later[name] = true end
    local nextStart = before
    for i = #segments, 1, -1 do
        local seg = segments[i]
        if seg.finish and seg.finish <= nextStart + 0.05 then
            local gap = math.max(0, nextStart - seg.finish)
            local same = false
            for name in pairs(seg.attackers or {}) do
                if later[name] then same = true; break end
            end
            if gap > (same and SAME_ENEMY_GRACE or GRACE) then break end
            if seg.read then
                chain[#chain + 1] = seg
                gaps[#gaps + 1] = gap
                for name in pairs(seg.attackers) do later[name] = true end
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
