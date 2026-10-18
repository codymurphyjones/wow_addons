local _, ns = ...

-- Reads Blizzard's built-in damage meter (C_DamageMeter) for duels: the damage you took and the
-- damage you did. A duel ends at 1 health, so there's no death and no death recap. The meter only has totals per attacker
-- and spell (no single hits, no health), and keeps them secret until combat ends. The calls and
-- fields are the ones Details! uses on this client (Details/core/parser_nocleu1.lua):
--   GetCombatSessionFromType(sessionType, meterType)            -> { combatSources, durationSeconds }
--   GetCombatSessionSourceFromType(sessionType, meterType, guid) -> { combatSpells = { { spellID,
--       totalAmount, overkillAmount, combatSpellDetails = { unitName, unitClassFilename, isPet } } } }
local Meter = {}
ns.Meter = Meter

local Readable, SafeCall = ns.Log.Readable, ns.Log.SafeCall

local RETRIES, RETRY_DELAY = 8, 1   -- after combat ends, wait up to this long for readable values

local function Num(v) v = Readable(v); return type(v) == "number" and v or nil end
local function Str(v) v = Readable(v); return (type(v) == "string" and v ~= "") and v or nil end
local function ShortName(name) return name and (name:match("^([^%-]+)") or name) end

function Meter.Available()
    return C_DamageMeter and C_DamageMeter.GetCombatSessionFromType and C_DamageMeter.GetCombatSessionSourceFromType
        and Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageTaken
        and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current and true or false
end

function Meter.Types() return Enum.DamageMeterType.DamageTaken, Enum.DamageMeterType.DamageDone end

-- Your entry in a session (damage taken or done).
local function FindMe(session)
    local sources = type(session) == "table" and Readable(session.combatSources)
    if type(sources) ~= "table" then return nil end
    local guid, name = UnitGUID("player"), UnitName("player")
    for _, s in ipairs(sources) do
        if type(s) == "table" then
            if Readable(s.isLocalPlayer) == true or Str(s.sourceGUID) == guid or Str(s.name) == name then return s end
        end
    end
end

-- The id of the newest meter session (the one you're in, or just left), or nil.
function Meter.NewestSessionID()
    if not (C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions) then return nil end
    local list = Readable(SafeCall(C_DamageMeter.GetAvailableCombatSessions))
    local last = type(list) == "table" and list[#list]
    return type(last) == "table" and Num(last.sessionID) or nil
end

-- A meter session of meterType (the current one, or sessionID when given), and a source's spells in it.
local function Session(meterType, sessionID)
    if sessionID and C_DamageMeter.GetCombatSessionFromID and C_DamageMeter.GetCombatSessionSourceFromID then
        return SafeCall(C_DamageMeter.GetCombatSessionFromID, sessionID, meterType), true
    end
    return SafeCall(C_DamageMeter.GetCombatSessionFromType, Enum.DamageMeterSessionType.Current, meterType), false
end

local function SourceSpells(meterType, sessionID, byID, source)
    local spells
    if byID then
        spells = SafeCall(C_DamageMeter.GetCombatSessionSourceFromID, sessionID, meterType, Str(source.sourceGUID), Num(source.sourceCreatureID))
    else
        spells = SafeCall(C_DamageMeter.GetCombatSessionSourceFromType, Enum.DamageMeterSessionType.Current, meterType,
            Str(source.sourceGUID), Num(source.sourceCreatureID))
    end
    local list = type(spells) == "table" and Readable(spells.combatSpells)
    return type(list) == "table" and list or nil
end

-- Rows { src, srcClass, pet, spellId, spell, amount, overkill } of your spells in a meter session
-- (the current one, or sessionID when given) of meterType, and its length; or nil, "secret" /
-- "none". For damage taken, src is who hit you; for damage done and healing it's you (or your pet).
function Meter.ReadSpells(meterType, sessionID)
    if not Meter.Available() or meterType == nil then return nil, "none" end
    local session, byID = Session(meterType, sessionID)
    if type(session) ~= "table" then return nil, "none" end
    local me = FindMe(session)
    if not me then
        -- Names still secret means the meter isn't readable yet, not that you took no damage.
        local sources = Readable(session.combatSources)
        if session.combatSources ~= nil and sources == nil then return nil, "secret" end
        local first = type(sources) == "table" and sources[1]
        if type(first) == "table" and first.name ~= nil and not Str(first.name) then return nil, "secret" end
        return nil, "none"
    end
    local list = SourceSpells(meterType, sessionID, byID, me)
    if not list then return nil, "secret" end

    local rows = {}
    for _, sp in ipairs(list) do
        if type(sp) == "table" then
            local amount = Num(sp.totalAmount)
            if amount == nil then return nil, "secret" end
            local d = type(sp.combatSpellDetails) == "table" and sp.combatSpellDetails or {}
            local id = Num(sp.spellID) or 0
            local name
            if id > 0 then
                if C_Spell and C_Spell.GetSpellName then name = Str(SafeCall(C_Spell.GetSpellName, id))
                elseif GetSpellInfo then name = Str(SafeCall(GetSpellInfo, id)) end
            end
            rows[#rows + 1] = {
                src = ShortName(Str(d.unitName)) or Str(sp.creatureName) or "Unknown", srcClass = Str(d.unitClassFilename),
                pet = Readable(d.isPet) == true or nil, spellId = id, spell = name or (id == 0 and "Melee") or ("Spell " .. id),
                melee = id == 0 or (id == 6603) or nil, amount = amount, overkill = Num(sp.overkillAmount),
            }
        end
    end
    return rows, nil, Num(session.durationSeconds)
end

-- Your healing in a session (rows as ReadSpells), or nil on clients without that meter.
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
    local session, byID = Session(t, sessionID)
    local sources = type(session) == "table" and Readable(session.combatSources)
    if type(sources) ~= "table" then return nil end
    local me, guid = UnitName("player"), UnitGUID("player")
    local out = {}
    for i, s in ipairs(sources) do
        if i > MAX_ENEMIES then break end
        local name = type(s) == "table" and Str(s.name)
        local list = name and SourceSpells(t, sessionID, byID, s)
        if list then
            local mine = 0
            for _, sp in ipairs(list) do
                local d = type(sp) == "table" and type(sp.combatSpellDetails) == "table" and sp.combatSpellDetails
                if d and (ShortName(Str(d.unitName)) == me or (guid and Str(d.unitGUID) == guid)) then
                    mine = mine + (Num(sp.totalAmount) or 0)
                end
            end
            if mine > 0 then
                out[#out + 1] = { name = ShortName(name), class = Str(s.classFilename), amount = mine, total = Num(s.totalAmount) }
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
    local me = UnitName("player")
    local out = {}
    for _, meterType in ipairs({ T.HealingDone, T.Absorbs }) do
        if meterType ~= nil then
            local session, byID = Session(meterType, sessionID)
            local sources = type(session) == "table" and Readable(session.combatSources)
            for _, s in ipairs(type(sources) == "table" and sources or {}) do
                local name = type(s) == "table" and ShortName(Str(s.name))
                if name then
                    local h = out[name]
                    if not h then
                        local ally = name == me or Readable(s.isLocalPlayer) == true
                            or (UnitInParty and Readable(UnitInParty(name)) == true) or (UnitInRaid and Readable(UnitInRaid(name)) ~= nil)
                        h = { total = 0, class = Str(s.classFilename), ally = ally and true or false, targets = {} }
                        out[name] = h
                    end
                    h.total = h.total + (Num(s.totalAmount) or 0)
                    for _, sp in ipairs(SourceSpells(meterType, sessionID, byID, s) or {}) do
                        if type(sp) == "table" then
                            local d = type(sp.combatSpellDetails) == "table" and sp.combatSpellDetails or {}
                            local target = ShortName(Str(d.unitName)) or "?"
                            h.targets[target] = (h.targets[target] or 0) + (Num(sp.totalAmount) or 0)
                        end
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
