local _, ns = ...
local S = ns.Secrets

-- Blizzard's built-in damage meter (C_DamageMeter), the calls every addon here reads it with
-- (addons/shared; needs Secrets.lua first). This client forbids addons the combat log, but the
-- meter is readable once combat ends (its values are secret until then). The calls and fields are
-- the ones Details! uses on this client (Details/core/parser_nocleu1.lua):
--   GetAvailableCombatSessions()                          -> { { sessionID } }, newest last
--   GetCombatSessionFromID(id, meterType)                 -> { combatSources = { { name, sourceGUID,
--       sourceCreatureID, classFilename, totalAmount, deathRecapID, deathTimeSeconds, isLocalPlayer } },
--       durationSeconds }
--   GetCombatSessionFromType(sessionType, meterType)      -> the same, for the current session
--   GetCombatSessionSourceFromID(id, meterType, guid, creatureID) /
--   GetCombatSessionSourceFromType(sessionType, meterType, guid, creatureID) -> { combatSpells = {
--       { spellID, totalAmount, overkillAmount, creatureName, isAvoidable, isDeadly,
--         combatSpellDetails = { unitName, unitGUID, unitClassFilename, isPet } } } }
local DM = {}
ns.DamageMeter = DM

function DM.Available()
    return C_DamageMeter and (C_DamageMeter.GetCombatSessionFromID or C_DamageMeter.GetCombatSessionFromType)
        and Enum and Enum.DamageMeterType and true or false
end

-- The id of the newest meter session (the one you're in, or just left), or nil.
function DM.NewestSessionID()
    if not (C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions) then return nil end
    local list = S.Readable(S.Call(C_DamageMeter.GetAvailableCombatSessions))
    local last = type(list) == "table" and list[#list]
    return type(last) == "table" and S.Num(last.sessionID) or nil
end

local function Current()
    return Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current
end

-- One meter type of a session: sessionID's, or the current one's when it's nil. Returns the
-- session table (or nil) and a handle for DM.Spells.
function DM.Session(meterType, sessionID)
    if meterType == nil or not DM.Available() then return nil end
    if sessionID and C_DamageMeter.GetCombatSessionFromID then
        return S.Call(C_DamageMeter.GetCombatSessionFromID, sessionID, meterType), { meterType, sessionID, true }
    end
    if C_DamageMeter.GetCombatSessionFromType and Current() ~= nil then
        return S.Call(C_DamageMeter.GetCombatSessionFromType, Current(), meterType), { meterType, nil, false }
    end
end

-- A session's sources and its length: list, nil, duration; or nil, "secret" while the names or the
-- list are still hidden. No session: an empty list.
function DM.Sources(session)
    if type(session) ~= "table" then return {}, nil end
    local list = S.Readable(session.combatSources)
    if session.combatSources ~= nil and list == nil then return nil, "secret" end
    for _, s in ipairs(type(list) == "table" and list or {}) do
        if type(s) == "table" and s.name ~= nil and not S.Str(s.name) then return nil, "secret" end
    end
    return type(list) == "table" and list or {}, nil, S.Num(session.durationSeconds)
end

-- A source's spells (raw combatSpells), or nil when they can't be read.
function DM.Spells(handle, source)
    if not (handle and type(source) == "table") then return nil end
    local meterType, sessionID, byID = handle[1], handle[2], handle[3]
    local guid, creature = S.Str(source.sourceGUID), S.Num(source.sourceCreatureID)
    local s
    if byID then
        if not C_DamageMeter.GetCombatSessionSourceFromID then return nil end
        s = S.Call(C_DamageMeter.GetCombatSessionSourceFromID, sessionID, meterType, guid, creature)
    else
        if not C_DamageMeter.GetCombatSessionSourceFromType then return nil end
        s = S.Call(C_DamageMeter.GetCombatSessionSourceFromType, Current(), meterType, guid, creature)
    end
    local list = type(s) == "table" and S.Readable(s.combatSpells)
    return type(list) == "table" and list or nil
end

function DM.IsMe(source)
    if S.Readable(source.isLocalPlayer) == true or S.Str(source.sourceGUID) == UnitGUID("player") then return true end
    local name = S.Str(source.name)
    if ns.Units then return ns.Units.IsMeLoose(name) end
    return S.Short(name) == UnitName("player")
end

-- Your entry in a list of sources, or nil.
function DM.FindMe(list)
    for _, s in ipairs(type(list) == "table" and list or {}) do
        if type(s) == "table" and DM.IsMe(s) then return s end
    end
end

-- Raw spells as rows { spellId, spell, melee, amount, overkill, other, otherGUID, otherClass, pet,
-- avoidable, deadly }, in the meter's order; or nil, "secret" when an amount is still hidden.
-- other is the unit on the far side: who hit you in damage taken, whom you healed in healing.
function DM.SpellRows(list)
    local rows = {}
    for _, sp in ipairs(list or {}) do
        if type(sp) == "table" then
            local amount = S.Num(sp.totalAmount)
            if amount == nil and sp.totalAmount ~= nil then return nil, "secret" end
            local id = S.Num(sp.spellID) or 0
            local d = type(sp.combatSpellDetails) == "table" and sp.combatSpellDetails or {}
            rows[#rows + 1] = {
                spellId = id, spell = S.SpellName(id) or (id == 0 and "Melee") or ("Spell " .. id),
                melee = id == 0 or id == 6603 or nil, amount = amount or 0, overkill = S.Num(sp.overkillAmount),
                other = S.Short(S.Str(d.unitName)) or S.Str(sp.creatureName), otherGUID = S.Str(d.unitGUID),
                otherClass = S.Str(d.unitClassFilename), pet = S.Readable(d.isPet) == true or nil,
                avoidable = S.Readable(sp.isAvoidable) == true or nil, deadly = S.Readable(sp.isDeadly) == true or nil,
            }
        end
    end
    return rows
end
