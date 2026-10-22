local _, ns = ...
local C = ns.Compat

-- Reads one fight from Blizzard's damage meter (C_DamageMeter) once combat is over (it's secret
-- until then): your damage by spell, the damage you took by mob and spell (and which of it was
-- avoidable), your interrupts and healing, and the healing ledger, meaning who healed whom with
-- what. The calls themselves are the shared DamageMeter.lua (addons/shared).
local Meter = {}
ns.Meter = Meter

local DM = ns.DamageMeter
local RETRIES, RETRY_DELAY = 10, 1

function Meter.Available()
    return DM.Available() and C_DamageMeter.GetCombatSessionFromID and true or false
end

Meter.NewestSessionID = DM.NewestSessionID

local function SpellRows(handle, source)
    local rows, why = DM.SpellRows(DM.Spells(handle, source))
    if rows then table.sort(rows, function(a, b) return a.amount > b.amount end) end
    return rows, why
end

-- Your rows in one meter type: { total, rows }.
local function Mine(id, meterType)
    local session, handle = DM.Session(meterType, id)
    local list, why, duration = DM.Sources(session)
    if not list then return nil, why end
    local s = DM.FindMe(list)
    if not s then return { total = 0, rows = {} }, nil, duration end
    local rows, secret = SpellRows(handle, s)
    if not rows then return nil, secret end
    return { total = C.Num(s.totalAmount) or 0, rows = rows }, nil, duration
end

-- The healing ledger: { [healer] = { total, class, targets = { [target] = amount }, spells = rows } },
-- and received = { [target] = amount }. Targets come from each spell's details; when the client
-- doesn't give them, the healer's healing sits under "?".
local function Ledger(id)
    local T = Enum.DamageMeterType
    local ledger, received = {}, {}
    for _, meterType in ipairs({ T.HealingDone, T.Absorbs }) do
        if meterType ~= nil then
            local session, handle = DM.Session(meterType, id)
            local list, why = DM.Sources(session)
            if not list then return nil, why end
            for _, s in ipairs(list) do
                -- Healers and who they healed in one shape (you by C.Me(), your group by their keys).
                local name = type(s) == "table" and C.Canon(C.Str(s.name))
                if name then
                    local h = ledger[name] or { total = 0, class = C.Str(s.classFilename), targets = {}, spells = {} }
                    ledger[name] = h
                    h.total = h.total + (C.Num(s.totalAmount) or 0)
                    for _, row in ipairs(SpellRows(handle, s) or {}) do
                        local target = C.Canon(row.other) or "?"
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
