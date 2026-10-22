local _, ns = ...

-- Reads Blizzard's built-in damage meter (C_DamageMeter) for duels: the damage you took and the
-- damage you did. A duel ends at 1 health, so there's no death and no death recap. The meter only
-- has totals per attacker and spell (no single hits, no health), and keeps them secret until combat
-- ends. The calls themselves are the shared DamageMeter.lua (addons/shared), which lists the fields.
local Meter = {}
ns.Meter = Meter

local S, DM = ns.Secrets, ns.DamageMeter
local Readable, Num, Str = S.Readable, S.Num, S.Str

local RETRIES, RETRY_DELAY = 8, 1   -- after combat ends, wait up to this long for readable values

function Meter.Available()
    return C_DamageMeter and C_DamageMeter.GetCombatSessionFromType and C_DamageMeter.GetCombatSessionSourceFromType
        and Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageTaken
        and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current and true or false
end

function Meter.Types() return Enum.DamageMeterType.DamageTaken, Enum.DamageMeterType.DamageDone end

-- The id of the newest meter session (the one you're in, or just left), or nil.
Meter.NewestSessionID = DM.NewestSessionID

-- Rows { src, srcClass, pet, spellId, spell, amount, overkill } of your spells in a meter session
-- (the current one, or sessionID when given) of meterType, and its length; or nil, "secret" /
-- "none". For damage taken, src is who hit you; for damage done and healing it's you (or your pet).
function Meter.ReadSpells(meterType, sessionID)
    if not Meter.Available() or meterType == nil then return nil, "none" end
    local session, handle = DM.Session(meterType, sessionID)
    if type(session) ~= "table" then return nil, "none" end
    local sources, why = DM.Sources(session)
    -- Names still secret means the meter isn't readable yet, not that you took no damage.
    if not sources then return nil, why end
    local me = DM.FindMe(sources)
    if not me then return nil, "none" end
    local list = DM.Spells(handle, me)
    if not list then return nil, "secret" end
    local rows, secret = DM.SpellRows(list)
    if not rows then return nil, secret end
    for _, r in ipairs(rows) do
        r.src, r.srcClass = r.other or "Unknown", r.otherClass
        r.other, r.otherGUID, r.otherClass, r.avoidable, r.deadly = nil, nil, nil, nil, nil
    end
    return rows, nil, Num(session.durationSeconds)
end

-- Your healing in a session (rows as ReadSpells), or nil when the game has no such meter.
function Meter.ReadHealing(sessionID)
    local t = Meter.Available() and Enum.DamageMeterType.HealingDone
    if t == nil or t == false then return nil end
    return (Meter.ReadSpells(t, sessionID))
end

local MAX_ENEMIES = 40

-- Your damage to each enemy in a session, from the meter's damage taken by enemies (each enemy's
-- hits, with who did them): rows { name, class, amount (yours), total (from everyone) }, or nil.
function Meter.ReadTargets(sessionID)
    local t = Meter.Available() and Enum.DamageMeterType.EnemyDamageTaken
    if t == nil or t == false then return nil end
    local session, handle = DM.Session(t, sessionID)
    local sources = type(session) == "table" and Readable(session.combatSources)
    if type(sources) ~= "table" then return nil end
    local guid = UnitGUID("player")
    local out = {}
    for i, s in ipairs(sources) do
        if i > MAX_ENEMIES then break end
        local name = type(s) == "table" and Str(s.name)
        local rows = name and DM.SpellRows(DM.Spells(handle, s))
        if rows then
            local mine = 0
            for _, r in ipairs(rows) do
                if (guid and r.otherGUID == guid) or ns.IsMe(r.other) then mine = mine + r.amount end
            end
            if mine > 0 then
                out[#out + 1] = { name = S.Short(name), class = Str(s.classFilename), amount = mine, total = Num(s.totalAmount) }
            end
        end
    end
    return out
end

function Meter.ReadDamageTaken() return Meter.ReadSpells(Enum.DamageMeterType.DamageTaken) end

-- Everyone's healing in a session, both sides: { [healer] = { total, class, ally, targets = { [name] =
-- amount } } }. Who was healed comes from each heal spell's details; when the client doesn't give
-- it, the healing sits under "?". Allies are you and your group; everyone else is on the other side.
function Meter.ReadLedger(sessionID)
    if not Meter.Available() then return nil end
    local T = Enum.DamageMeterType
    local out = {}
    for _, meterType in ipairs({ T.HealingDone, T.Absorbs }) do
        if meterType ~= nil then
            local session, handle = DM.Session(meterType, sessionID)
            local sources = type(session) == "table" and Readable(session.combatSources)
            for _, s in ipairs(type(sources) == "table" and sources or {}) do
                -- Healers and who they healed in one shape (you and your group by your keys).
                local name = type(s) == "table" and ns.Canon(Str(s.name))
                if name then
                    local h = out[name]
                    if not h then
                        local ally = ns.IsMe(name) or Readable(s.isLocalPlayer) == true
                            or ns.InGroup(name)
                            or (UnitInParty and Readable(UnitInParty(name)) == true) or (UnitInRaid and Readable(UnitInRaid(name)) ~= nil)
                        h = { total = 0, class = Str(s.classFilename), ally = ally and true or false, targets = {} }
                        out[name] = h
                    end
                    h.total = h.total + (Num(s.totalAmount) or 0)
                    for _, r in ipairs(DM.SpellRows(DM.Spells(handle, s)) or {}) do
                        local target = ns.Canon(r.other) or "?"
                        h.targets[target] = (h.targets[target] or 0) + r.amount
                    end
                end
            end
        end
    end
    return out
end

-- Waits for combat to end, then reads the damage you took and did (retrying while the values are
-- still secret). done(taken, dealt, duration), either list possibly empty, or done(nil, nil, nil, reason).
function Meter.ReadAfterCombat(done)
    local attempt = 0
    local function Try()
        attempt = attempt + 1
        if not InCombatLockdown() then
            local takenType, doneType = Meter.Types()
            local taken, r1, duration = Meter.ReadSpells(takenType)
            local dealt, r2, duration2 = Meter.ReadSpells(doneType)
            if r1 ~= "secret" and r2 ~= "secret" and (taken or dealt) then
                return done(taken or {}, dealt or {}, duration or duration2)
            end
            if r1 == "none" and r2 == "none" and attempt > 2 then return done(nil, nil, nil, "none") end
        end
        if attempt < RETRIES then
            C_Timer.After(RETRY_DELAY, Try)
        else
            done(nil, nil, nil, "secret")
        end
    end
    C_Timer.After(0.5, Try)
end
