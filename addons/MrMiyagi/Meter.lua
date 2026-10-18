local _, ns = ...
local C = ns.Compat

-- Reads one fight from Blizzard's damage meter (C_DamageMeter) once combat is over (it's secret
-- until then): your damage by spell, the damage you took by mob and spell (and which of it was
-- avoidable), your interrupts and healing, and the healing ledger, meaning who healed whom with
-- what. Calls and fields as Details! and BattleRecap use them on this client.
local Meter = {}
ns.Meter = Meter

local RETRIES, RETRY_DELAY = 10, 1

function Meter.Available()
    return C_DamageMeter and C_DamageMeter.GetCombatSessionFromID and Enum and Enum.DamageMeterType and true or false
end

function Meter.NewestSessionID()
    if not (C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions) then return nil end
    local list = C.Readable(C.Call(C_DamageMeter.GetAvailableCombatSessions))
    local last = type(list) == "table" and list[#list]
    return type(last) == "table" and C.Num(last.sessionID) or nil
end

local function Session(id, meterType)
    if meterType == nil then return nil end
    return C.Call(C_DamageMeter.GetCombatSessionFromID, id, meterType)
end

local function Sources(id, meterType)
    local session = Session(id, meterType)
    if type(session) ~= "table" then return {}, nil end
    local list = C.Readable(session.combatSources)
    if session.combatSources ~= nil and list == nil then return nil, "secret" end
    for _, s in ipairs(type(list) == "table" and list or {}) do
        if type(s) == "table" and s.name ~= nil and not C.Str(s.name) then return nil, "secret" end
    end
    return type(list) == "table" and list or {}, nil, C.Num(session.durationSeconds)
end

local function Spells(id, meterType, source)
    local s = C.Call(C_DamageMeter.GetCombatSessionSourceFromID, id, meterType, C.Str(source.sourceGUID), C.Num(source.sourceCreatureID))
    local list = type(s) == "table" and C.Readable(s.combatSpells)
    return type(list) == "table" and list or {}
end

local function IsMe(s)
    return C.Readable(s.isLocalPlayer) == true or C.Str(s.sourceGUID) == UnitGUID("player") or C.Short(C.Str(s.name)) == UnitName("player")
end

local function SpellRows(list)
    local rows = {}
    for _, sp in ipairs(list) do
        if type(sp) == "table" then
            local id = C.Num(sp.spellID) or 0
            local d = type(sp.combatSpellDetails) == "table" and sp.combatSpellDetails or {}
            rows[#rows + 1] = {
                spellId = id, spell = C.SpellName(id) or (id == 0 and "Melee") or ("Spell " .. id), melee = id == 0 or id == 6603 or nil,
                amount = C.Num(sp.totalAmount) or 0, overkill = C.Num(sp.overkillAmount),
                other = C.Short(C.Str(d.unitName)) or C.Str(sp.creatureName), otherClass = C.Str(d.unitClassFilename),
                avoidable = C.Readable(sp.isAvoidable) == true or nil, deadly = C.Readable(sp.isDeadly) == true or nil,
            }
        end
    end
    table.sort(rows, function(a, b) return a.amount > b.amount end)
    return rows
end

-- Your rows in one meter type: { total, rows }.
local function Mine(id, meterType)
    local list, why, duration = Sources(id, meterType)
    if not list then return nil, why end
    for _, s in ipairs(list) do
        if type(s) == "table" and IsMe(s) then
            return { total = C.Num(s.totalAmount) or 0, rows = SpellRows(Spells(id, meterType, s)) }, nil, duration
        end
    end
    return { total = 0, rows = {} }, nil, duration
end

-- The healing ledger: { [healer] = { total, class, targets = { [target] = amount }, spells = rows } },
-- and received = { [target] = amount }. Targets come from each spell's details; when the client
-- doesn't give them, the healer's healing sits under "?".
local function Ledger(id)
    local T = Enum.DamageMeterType
    local ledger, received = {}, {}
    for _, meterType in ipairs({ T.HealingDone, T.Absorbs }) do
        if meterType ~= nil then
            local list, why = Sources(id, meterType)
            if not list then return nil, why end
            for _, s in ipairs(list) do
                local name = type(s) == "table" and C.Short(C.Str(s.name))
                if name then
                    local h = ledger[name] or { total = 0, class = C.Str(s.classFilename), targets = {}, spells = {} }
                    ledger[name] = h
                    h.total = h.total + (C.Num(s.totalAmount) or 0)
                    for _, row in ipairs(SpellRows(Spells(id, meterType, s))) do
                        local target = row.other or "?"
                        h.targets[target] = (h.targets[target] or 0) + row.amount
                        received[target] = (received[target] or 0) + row.amount
                        table.insert(h.spells, row)
                    end
                end
            end
        end
    end
    return ledger, received
end

-- Everything about the fight you were in. nil, "secret" while still hidden.
function Meter.Read(id)
    if not (Meter.Available() and id) then return nil, "none" end
    local T = Enum.DamageMeterType
    local out = {}
    local why, duration
    out.done, why, duration = Mine(id, T.DamageDone)
    if not out.done then return nil, why end
    out.taken = Mine(id, T.DamageTaken)
    out.avoidable = T.AvoidableDamageTaken and Mine(id, T.AvoidableDamageTaken) or nil
    out.healed = Mine(id, T.HealingDone)
    out.interrupts = T.Interrupts and Mine(id, T.Interrupts) or nil
    out.duration = duration
    if not out.taken then return nil, "secret" end
    -- Avoidable spells, to flag them in the damage you took.
    local avoid = {}
    for _, r in ipairs(out.avoidable and out.avoidable.rows or {}) do avoid[r.spellId] = true end
    for _, r in ipairs(out.taken.rows) do if avoid[r.spellId] then r.avoidable = true end end
    if IsInGroup() then out.ledger, out.received = Ledger(id) end
    return out
end

-- After combat: done(data) or done(nil, reason).
function Meter.ReadAfterCombat(id, done)
    local attempt = 0
    local function Try()
        attempt = attempt + 1
        if not InCombatLockdown() then
            local data, why = Meter.Read(id)
            if data then return done(data) end
            if why == "none" then return done(nil, "none") end
        end
        if attempt < RETRIES then C_Timer.After(RETRY_DELAY, Try) else done(nil, "secret") end
    end
    C_Timer.After(0.5, Try)
end
