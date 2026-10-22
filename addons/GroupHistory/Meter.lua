local _, ns = ...
local C = ns.Compat

-- Reads Blizzard's built-in damage meter (C_DamageMeter) for one fight, for the whole group. This
-- client forbids addons the combat log, but the meter is readable once combat ends (its values are
-- secret during combat). The calls themselves are the shared DamageMeter.lua (addons/shared), which
-- lists the fields.
local Meter = {}
ns.Meter = Meter

local DM = ns.DamageMeter
local RETRIES, RETRY_DELAY = 10, 1

function Meter.Available()
    return DM.Available() and C_DamageMeter.GetCombatSessionFromID and true or false
end

Meter.NewestSessionID = DM.NewestSessionID

-- Sources of one meter type: { [shortName] = { amount, guid, class, recap, deathTime, src } }, or
-- nil, "secret" while the values are hidden.
local function Sources(id, meterType)
    local session, handle = DM.Session(meterType, id)
    local list, why, duration = DM.Sources(session)
    if not list then return nil, why end
    local out = {}
    for _, s in ipairs(list) do
        if type(s) == "table" then
            local name = C.Short(C.Str(s.name))
            if name then
                out[name] = {
                    amount = C.Num(s.totalAmount) or 0, guid = C.Str(s.sourceGUID), class = C.Str(s.classFilename),
                    recap = C.Num(s.deathRecapID), deathTime = C.Num(s.deathTimeSeconds), src = s,
                }
            end
        end
    end
    return out, nil, duration, handle
end

-- Everything about one fight for the group: by short name, { done, healed, taken, avoidable,
-- interrupts, dispels, avoidSpells = { [spellID] = amount }, death = { recapID, time } }, plus the
-- fight's length; or nil, "secret".
function Meter.ReadFight(id)
    if not (Meter.Available() and id) then return nil, "none" end
    local T = Enum.DamageMeterType
    local types = {
        done = T.DamageDone, healed = T.HealingDone, taken = T.DamageTaken, avoidable = T.AvoidableDamageTaken,
        interrupts = T.Interrupts, dispels = T.Dispels, deaths = T.Deaths,
    }
    local out, duration = {}, nil
    local function Get(name)
        local p = out[name]
        if not p then p = { done = 0, healed = 0, taken = 0, avoidable = 0, interrupts = 0, dispels = 0 }; out[name] = p end
        return p
    end
    for field, meterType in pairs(types) do
        if meterType ~= nil then
            local sources, why, len, handle = Sources(id, meterType)
            if not sources then return nil, why end
            duration = duration or len
            for name, s in pairs(sources) do
                local p = Get(name)
                p.class = p.class or s.class
                p.guid = p.guid or s.guid
                if field == "deaths" then
                    p.death = { recapID = s.recap, time = s.deathTime }
                else
                    p[field] = s.amount
                end
                -- The avoidable hits, spell by spell, to recognise them in death recaps.
                if field == "avoidable" and s.amount > 0 then
                    p.avoidSpells = {}
                    for _, sp in ipairs(DM.Spells(handle, s.src) or {}) do
                        local spell = type(sp) == "table" and C.Num(sp.spellID)
                        if spell then p.avoidSpells[spell] = C.Num(sp.totalAmount) or 0 end
                    end
                end
                s.src = nil
            end
        end
    end
    return out, nil, duration
end

-- Who healed whom in a fight: { [healer] = { total, class, targets = { [name] = amount },
-- spells = { [spellID] = amount } } }. Targets come from each heal spell's details; when the
-- client doesn't give them, the healing sits under "?". nil while still secret.
function Meter.Ledger(id)
    if not (Meter.Available() and id) then return nil end
    local T = Enum.DamageMeterType
    local ledger = {}
    for _, meterType in ipairs({ T.HealingDone, T.Absorbs }) do
        if meterType ~= nil then
            local session, handle = DM.Session(meterType, id)
            local list = DM.Sources(session)
            if not list then return nil end
            for _, s in ipairs(list) do
                local name = type(s) == "table" and C.Short(C.Str(s.name))
                if name then
                    local h = ledger[name] or { total = 0, class = C.Str(s.classFilename), targets = {}, spells = {} }
                    ledger[name] = h
                    h.total = h.total + (C.Num(s.totalAmount) or 0)
                    for _, sp in ipairs(DM.Spells(handle, s) or {}) do
                        if type(sp) == "table" then
                            local amount = C.Num(sp.totalAmount) or 0
                            local d = type(sp.combatSpellDetails) == "table" and sp.combatSpellDetails or {}
                            local target = C.Short(C.Str(d.unitName)) or "?"
                            h.targets[target] = (h.targets[target] or 0) + amount
                            local spell = C.Num(sp.spellID) or 0
                            h.spells[spell] = (h.spells[spell] or 0) + amount
                        end
                    end
                end
            end
        end
    end
    return ledger
end

-- Healing each member received, from the ledger: { [name] = { total, by = { [healer] = amount } } }.
function Meter.Received(ledger)
    local out = {}
    for healer, h in pairs(ledger or {}) do
        for target, amount in pairs(h.targets) do
            local r = out[target] or { total = 0, by = {} }
            out[target] = r
            r.total = r.total + amount
            r.by[healer] = (r.by[healer] or 0) + amount
        end
    end
    return out
end

-- After combat: reads the fight once its values stop being secret. done(data, duration) or
-- done(nil, reason).
function Meter.ReadAfterCombat(id, done)
    local attempt = 0
    local function Try()
        attempt = attempt + 1
        if not InCombatLockdown() then
            local data, why, duration = Meter.ReadFight(id)
            if data then return done(data, duration) end
            if why == "none" then return done(nil, "none") end
        end
        if attempt < RETRIES then C_Timer.After(RETRY_DELAY, Try) else done(nil, "secret") end
    end
    C_Timer.After(0.5, Try)
end
