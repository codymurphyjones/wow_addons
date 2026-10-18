local _, ns = ...

-- Counter notes: for each enemy class in a recap, the patterns its damage shows (signature spells,
-- and combos timed hit by hit) and how to beat them, with a line for your own class. The advice
-- lives in CounterData.lua (ns.COUNTER_DATA). Only damage is in a recap (no crowd control, buffs or
-- casts that do no damage), so every pattern is one damage can show.
local C = {}
ns.Counter = C

local MAX_PATTERNS = 6
-- Seconds with no damage before a hit that suggest crowd control. Longer for hunters, whose Auto
-- Shot alone comes every 3s or so.
local GAP, GAP_BY_CLASS = 4, { HUNTER = 5.5 }

-- The advice lines whose triggers happened in this fight (CounterAdvice.lua): { text, trigger, ... }.
local function Relevant(list, evidence)
    local out = {}
    for _, entry in ipairs(list or {}) do
        for i = 2, #entry do
            if evidence[entry[i]] then out[#out + 1] = entry[1]; break end
        end
    end
    return out
end

-- Which class a pet (or totem) spell belongs to, when the pet has no class of its own.
local function PetClass(data, a)
    for _, s in ipairs(a.spellList or {}) do
        local owner = data.pets[s.name]
        if owner then return owner[1] end
    end
end

-- Times (rel) of each hit by spell for one attacker, from the hit-by-hit recap.
local function HitsBySpell(recap, name)
    local hits = {}
    for _, e in ipairs(recap.events or {}) do
        if e.kind == "dmg" and e.src == name then
            hits[e.spell] = hits[e.spell] or {}
            table.insert(hits[e.spell], e)
        end
    end
    return hits
end

-- A combo { first, second, within, pattern, tip, critSecond }: a hit of `second` no more than
-- `within` seconds after a hit of `first` (a crit when critSecond).
local function ComboSeen(hits, combo, events)
    local seconds = hits[combo[2]]
    if combo[1] == "GAP" then
        -- After at least combo[3] seconds with no damage from anyone: crowd control.
        if not seconds then return nil end
        for _, b in ipairs(seconds) do
            local prev
            for _, e in ipairs(events) do
                if e == b then break end
                if e.kind == "dmg" then prev = e end
            end
            if prev and b.rel - prev.rel >= combo[3] then return b.amount or 0, b.rel - prev.rel end
        end
        return nil
    end
    local firsts = hits[combo[1]]
    if not firsts or not seconds then return nil end
    for _, a in ipairs(firsts) do
        for _, b in ipairs(seconds) do
            local dt = b.rel - a.rel
            if dt >= 0 and dt <= combo[3] and (not combo.critSecond or b.crit) and a ~= b then
                return a.amount + (b.amount or 0), dt
            end
        end
    end
end

-- One entry per enemy class, most damage first:
-- { class, names = { ... }, damage, pct, killer, patterns = { { spell, icon, total, crits, pattern, tip } },
--   combos = { { label, pattern, tip, amount, dt } }, matchup, general }
function C.Analyze(recap)
    if ns.ResolveRacialAdvice then ns.ResolveRacialAdvice() end
    local data = ns.COUNTER_DATA
    local out = {}
    if not (data and recap) then return out end
    local byClass = {}
    local total = (recap.totals and recap.totals.damage or 0) + (recap.earlier and recap.earlier.damage or 0)
    local killer = recap.killer

    local function Add(a, earlier)
        if a.env then return end
        local class = a.class
        if not (class and data.classes[class]) and a.pet then class = PetClass(data, a) end
        local cd = class and data.classes[class]
        if not cd then return end
        local e = byClass[class]
        if not e then
            e = { class = class, names = {}, seen = {}, damage = 0, patterns = {}, combos = {}, spellSeen = {},
                evidence = {}, cd = cd }
            byClass[class] = e
            out[#out + 1] = e
        end
        if not e.seen[a.name] then e.seen[a.name] = true; e.names[#e.names + 1] = a.name end
        if killer and not killer.env and a.name == killer.name then e.killer = true end
        e.damage = e.damage + (a.damage or 0)
        if a.pet then e.evidence.PET = true end
        for _, s in ipairs(a.spellList or {}) do
            e.evidence[s.name] = true
            if s.name == "Melee" then e.evidence.MELEE = true end
            local info = cd.spells and cd.spells[s.name] or (a.pet and data.pets[s.name] and { data.pets[s.name][2], data.pets[s.name][3] })
            if info then
                local p = e.spellSeen[s.name]
                if not p then
                    p = { spell = s.name, id = s.id, icon = s.icon, total = 0, crits = 0, pattern = info[1], tip = info[2], earlier = earlier }
                    e.spellSeen[s.name] = p
                    e.patterns[#e.patterns + 1] = p
                end
                p.total = p.total + (s.total or 0)
                p.crits = p.crits + (s.crits or 0)
            end
        end
        -- Combos need the hit-by-hit timeline (deaths, not duels).
        if not earlier and not recap.totalsOnly and cd.combos then
            local hits = HitsBySpell(recap, a.name)
            for _, combo in ipairs(cd.combos) do
                local key = combo[1] .. ">" .. combo[2]
                if not e.seen[key] then
                    local amount, dt = ComboSeen(hits, combo, recap.events)
                    if amount then
                        e.seen[key] = true
                        local label = combo[1] == "GAP" and ("Pause, then " .. combo[2]) or (combo[1] .. " > " .. combo[2])
                        e.combos[#e.combos + 1] = { label = label, pattern = combo[4], tip = combo[5],
                            amount = amount, dt = dt }
                    end
                end
            end
        end
    end

    for _, a in ipairs(recap.attackers or {}) do Add(a, false) end
    if recap.earlier and recap.earlier.attackers then
        for _, a in ipairs(recap.earlier.attackers) do Add(a, true) end
    end

    -- A hit from that class right after a pause in all damage: crowd control (stun, Fear, trap).
    if not recap.totalsOnly then
        local prev
        for _, ev in ipairs(recap.events or {}) do
            if ev.kind == "dmg" then
                if prev and ev.srcClass and byClass[ev.srcClass] and ev.rel - prev.rel >= (GAP_BY_CLASS[ev.srcClass] or GAP) then
                    byClass[ev.srcClass].evidence.GAP = true
                end
                prev = ev
            end
        end
    end

    for _, e in ipairs(out) do
        e.general, e.matchup = Relevant(e.cd.general, e.evidence), nil
        local clauses = Relevant(recap.class and e.cd.vs and e.cd.vs[recap.class], e.evidence)
        if #clauses > 0 then
            local text = table.concat(clauses, "; ")
            e.matchup = text:sub(1, 1):upper() .. text:sub(2) .. "."
        end
        e.cd = nil
        e.pct = total > 0 and e.damage / total * 100 or 0
        table.sort(e.patterns, function(a, b) return a.total > b.total end)
        while #e.patterns > MAX_PATTERNS do table.remove(e.patterns) end
        e.seen, e.spellSeen = nil, nil
    end
    table.sort(out, function(a, b)
        if (a.killer and 1 or 0) ~= (b.killer and 1 or 0) then return a.killer and true or false end
        return a.damage > b.damage
    end)
    return out
end

-- The one or two lines worth reading first: the killer's class combo (or biggest pattern), and how
-- your class beats it.
function C.Top(recap)
    local list = C.Analyze(recap)
    local e = list[1]
    if not e then return {}, nil end
    local lines = {}
    local first = e.combos[1] or e.patterns[1]
    if first then
        local label = first.label or first.spell
        lines[#lines + 1] = ("|cffffd100%s|r: %s"):format(label, first.tip)
    end
    if e.matchup then
        lines[#lines + 1] = ("|cff55ccffAs %s|r: %s"):format(ns.ClassName(recap.class) or "you", e.matchup)
    end
    -- General advice against the class, whatever yours is.
    for i = 1, math.min(e.matchup and 1 or 2, #e.general) do
        lines[#lines + 1] = "|cffb0b8c0Anyone|r: " .. e.general[i]
    end
    return lines, e
end
