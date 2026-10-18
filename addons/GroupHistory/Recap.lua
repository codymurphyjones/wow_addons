local _, ns = ...
local C = ns.Compat

-- Death recaps (C_DeathRecap): the last hits before a death, with who dealt them, the spell, the
-- amount and the victim's health. The meter gives every group member's death a recap ID; your own
-- latest recap is also readable without one. (Fields as in BattleRecap's Log.lua.)
local Recap = {}
ns.Recap = Recap

local KEEP = 8 -- hits kept per death
local band = bit and bit.band or function(a, b) return a % (b * 2) >= b and b or 0 end
local TYPE_PLAYER = 0x00000400

local function Convert(r)
    local sub = C.Str(r.event) or ""
    local h = {
        t = C.Num(r.timestamp), amount = C.Num(r.amount), overkill = C.Num(r.overkill), hp = C.Num(r.currentHP),
        crit = C.Readable(r.critical) and true or nil,
    }
    if sub == "SWING_DAMAGE" then
        h.spellId, h.spell, h.melee = 0, "Melee", true
    elseif sub == "ENVIRONMENTAL_DAMAGE" then
        h.spellId, h.env = 0, true
        h.spell = C.Str(r.environmentalType) or "Environment"
    else
        h.spellId = C.Num(r.spellId) or 0
        h.spell = C.Str(r.spellName) or C.SpellName(h.spellId) or "Unknown spell"
        h.periodic = sub == "SPELL_PERIODIC_DAMAGE" or nil
        h.ranged = sub == "RANGE_DAMAGE" or nil
    end
    if sub:find("HEAL") then h.heal = true end
    h.src = C.Short(C.Str(r.sourceName))
    local flags = C.Num(r.sourceFlags)
    if flags and band(flags, TYPE_PLAYER) ~= 0 then h.player = true end
    if not h.amount then h.partial = true end
    return h
end

-- A recap as hits, oldest first (the killing blow last), trimmed to the last KEEP; and the
-- victim's max health. id nil = your own latest recap.
function Recap.Read(id)
    if not C_DeathRecap then return nil end
    if id == nil and not C.Call(C_DeathRecap.HasRecapEvents) then return nil end
    if id ~= nil and C_DeathRecap.HasRecapEvents and not C.Call(C_DeathRecap.HasRecapEvents, id) then return nil end
    local raw = C.Readable(id and C.Call(C_DeathRecap.GetRecapEvents, id) or C.Call(C_DeathRecap.GetRecapEvents))
    if type(raw) ~= "table" or #raw == 0 then return nil end
    local maxHp = C.Num(id and C.Call(C_DeathRecap.GetRecapMaxHealth, id) or C.Call(C_DeathRecap.GetRecapMaxHealth))
    local hits = {}
    for i, r in ipairs(raw) do
        if type(r) == "table" then
            local h = Convert(r)
            h.order = i
            hits[#hits + 1] = h
        end
    end
    -- Blizzard lists the killing blow first.
    table.sort(hits, function(a, b)
        if a.t and b.t and a.t ~= b.t then return a.t < b.t end
        return a.order > b.order
    end)
    while #hits > KEEP do table.remove(hits, 1) end
    local last = hits[#hits]
    for _, h in ipairs(hits) do
        h.rel = (h.t and last and last.t) and math.floor((h.t - last.t) * 10 + 0.5) / 10 or nil
        h.order, h.t = nil, nil
    end
    return hits, maxHp
end

-- Your own recap after you die, retried while it isn't ready. done(hits, maxHp) or done(nil).
function Recap.ReadOwnAfterDeath(done)
    local delays, i = { 0.3, 1, 2 }, 0
    local function Try()
        i = i + 1
        local hits, maxHp = Recap.Read(nil)
        if hits or i >= #delays then return done(hits, maxHp) end
        C_Timer.After(delays[i + 1] - delays[i], Try)
    end
    C_Timer.After(delays[1], Try)
end

-- Plain text for one hit: "Shadow Bolt 412 (crit) from Defias Wizard".
function Recap.Describe(h)
    if h.heal then
        return ("|cff59f28cHealed|r %s by %s%s"):format(h.amount and tostring(h.amount) or "?", h.src or "?", h.spell and (" (" .. h.spell .. ")") or "")
    end
    return ("%s %s%s%s"):format(h.spell or "?", h.amount and tostring(h.amount) or "?", h.crit and " (crit)" or "",
        h.src and (" from " .. h.src) or "")
end
