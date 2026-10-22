local _, ns = ...

-- Turns the hits from Blizzard's death recap (Log.lua) into a recap: who killed you, how, and
-- every hit on the way. Build is a pure function of its inputs, so Test() can feed it made-up data.
local A = {}
ns.Analysis = A

A.FORMAT = 2         -- saved recaps of another format are dropped on load (Core.lua)
local FULL_HP = 0.9   -- the death window starts the last time you were at or above this

local function SortBy(list, key)
    table.sort(list, function(a, b)
        if a[key] ~= b[key] then return (a[key] or 0) > (b[key] or 0) end
        return (a.name or "") < (b.name or "")
    end)
    return list
end

local function Positive(n) return (n and n > 0) and n or 0 end

local function NewSpell(e)
    return {
        name = e.spell, id = e.spellId, school = e.school, icon = e.icon, periodic = e.periodic,
        hits = 0, crits = 0, total = 0, max = 0, min = nil, absorbed = 0, resisted = 0, blocked = 0,
    }
end

local function AddHit(s, e)
    local amount = e.amount or 0
    s.hits = s.hits + 1
    s.total = s.total + amount
    if e.crit then s.crits = s.crits + 1 end
    if amount > s.max then s.max = amount end
    if not s.min or amount < s.min then s.min = amount end
    s.absorbed = s.absorbed + Positive(e.absorbed)
    s.resisted = s.resisted + Positive(e.resisted)
    s.blocked = s.blocked + Positive(e.blocked)
end

local function Finish(s)
    s.avg = s.hits > 0 and s.total / s.hits or 0
    s.critPct = s.hits > 0 and s.crits / s.hits * 100 or 0
    s.min = s.min or 0
end

local function NewRecap(meta, events)
    return {
        v = A.FORMAT, time = time(), kind = meta.kind, zone = meta.zone, player = meta.player, class = meta.class,
        race = meta.race, level = meta.level, maxHp = meta.maxHp, events = events,
    }
end

-- events: Log.lua events, oldest first, rel = seconds before the killing blow (<= 0).
-- meta: { kind = "bg" | "arena" | "pvp", zone, player, class, maxHp }.
function A.Build(events, meta)
    local recap = NewRecap(meta, events)
    for _, e in ipairs(events) do
        e.icon = e.melee and ns.MELEE_ICON or ns.SpellIcon(e.spellId, e.spell)
        if e.partial then recap.partial = true end
        if e.pvp then recap.pvp = true end
    end

    -- Killing blow: the last hit with overkill, else the last hit.
    local kb
    for i = #events, 1, -1 do
        local e = events[i]
        if e.kind == "dmg" then
            if Positive(e.overkill) > 0 then kb = e; break end
            kb = kb or e
        end
    end
    if kb then kb.killingBlow = true end

    -- Death window: from the last hit that left you at FULL_HP or more, else the first hit.
    local start = events[1] and events[1].rel or 0
    for i = #events, 1, -1 do
        local e = events[i]
        if e.hp and e.hpMax and e.hpMax > 0 and e.hp / e.hpMax >= FULL_HP then start = e.rel; break end
    end
    recap.windowStart = start
    recap.duration = math.max(0, -start)
    recap.span = events[1] and -events[1].rel or 0

    local T = { damage = 0, hits = 0, crits = 0, absorbed = 0, resisted = 0, blocked = 0, overkill = 0 }
    local attackers, attackerList = {}, {}
    local spells, spellList = {}, {}
    local schools = {}
    local biggest

    for _, e in ipairs(events) do
        e.inWindow = e.rel >= start or nil
        if e.inWindow and e.kind == "dmg" then
            local name, class = e.src or "Unknown", e.srcClass
            local a = attackers[name]
            if not a then
                a = { name = name, fullName = e.srcFull, class = class, env = e.env, pet = e.pet, damage = 0, hits = 0, crits = 0,
                    spells = {}, spellList = {}, first = e.rel }
                attackers[name] = a
                attackerList[#attackerList + 1] = a
            end
            a.last = e.rel
            a.damage = a.damage + (e.amount or 0)
            a.hits = a.hits + 1
            if e.crit then a.crits = a.crits + 1 end
            local s = a.spells[e.spell]
            if not s then
                s = NewSpell(e)
                a.spells[e.spell] = s
                a.spellList[#a.spellList + 1] = s
            end
            AddHit(s, e)

            local key = name .. "\001" .. e.spell
            local g = spells[key]
            if not g then
                g = NewSpell(e)
                g.src, g.srcClass = name, class
                spells[key] = g
                spellList[#spellList + 1] = g
            end
            AddHit(g, e)

            local _, bit = ns.School(e.school)
            schools[bit] = (schools[bit] or 0) + (e.amount or 0)
            T.damage = T.damage + (e.amount or 0)
            T.hits = T.hits + 1
            if e.crit then T.crits = T.crits + 1 end
            T.absorbed = T.absorbed + Positive(e.absorbed)
            T.resisted = T.resisted + Positive(e.resisted)
            T.blocked = T.blocked + Positive(e.blocked)
            T.overkill = T.overkill + Positive(e.overkill)
            if not biggest or (e.amount or 0) > biggest.amount then
                biggest = { amount = e.amount or 0, spell = e.spell, id = e.spellId, icon = e.icon,
                    src = name, srcClass = class, crit = e.crit, rel = e.rel }
            end
        end
    end

    for _, a in ipairs(attackerList) do
        a.pct = T.damage > 0 and a.damage / T.damage * 100 or 0
        for _, s in ipairs(a.spellList) do
            Finish(s)
            s.pct = a.damage > 0 and s.total / a.damage * 100 or 0
        end
        SortBy(a.spellList, "total")
        a.spells = nil
    end
    recap.attackers = SortBy(attackerList, "damage")
    for _, g in ipairs(spellList) do
        Finish(g)
        g.pct = T.damage > 0 and g.total / T.damage * 100 or 0
    end
    recap.spells = SortBy(spellList, "total")

    local schoolList = {}
    for bit, amount in pairs(schools) do
        schoolList[#schoolList + 1] = { school = bit, name = ns.SchoolName(bit), total = amount,
            pct = T.damage > 0 and amount / T.damage * 100 or 0 }
    end
    recap.schools = SortBy(schoolList, "total")

    T.enemies = 0
    for _, a in ipairs(attackerList) do if not a.env then T.enemies = T.enemies + 1 end end
    T.dps = recap.duration > 0.1 and T.damage / recap.duration or T.damage
    T.biggest = biggest
    recap.totals = T

    if kb then
        local k = { name = kb.src or "Unknown", fullName = kb.srcFull, class = kb.srcClass, env = kb.env, pet = kb.pet,
            spell = kb.spell, id = kb.spellId, icon = kb.icon, school = kb.school, amount = kb.amount,
            overkill = Positive(kb.overkill), crit = kb.crit, rel = kb.rel }
        for _, a in ipairs(recap.attackers) do
            if a.name == k.name then
                k.damage, k.pct, k.spells, k.hits = a.damage, a.pct, a.spellList, a.hits
                break
            end
        end
        recap.killer = k
    end
    return recap
end

local function MeterSpell(r)
    local s = { name = r.spell, id = r.spellId, school = 1, total = r.amount, hits = 0, crits = 0, max = 0, min = 0,
        absorbed = 0, resisted = 0, blocked = 0, src = r.src, srcClass = r.srcClass,
        icon = r.melee and ns.MELEE_ICON or ns.SpellIcon(r.spellId, r.spell) }
    Finish(s)
    return s
end

-- Meter rows from several combats as one list, adding up the same attacker's same spell.
function A.MergeRows(lists)
    local out, byKey = {}, {}
    for _, rows in ipairs(lists) do
        for _, r in ipairs(rows or {}) do
            local key = (r.src or "?") .. "\001" .. (r.spellId or 0) .. "\001" .. (r.spell or "")
            local m = byKey[key]
            if not m then
                m = {}
                for k, v in pairs(r) do m[k] = v end
                m.amount = 0
                byKey[key] = m
                out[#out + 1] = m
            end
            m.amount = m.amount + (r.amount or 0)
        end
    end
    return out
end

-- The damage you took earlier in the same fight, before combat dropped (a vanish, say), from the
-- combats Fight.lua kept: totals per attacker and spell, kept apart from the hit-by-hit recap.
-- gap: how long combat had dropped.
function A.AddEarlier(recap, segments, gap)
    local lists, span = {}, 0
    for i, seg in ipairs(segments) do
        lists[i] = seg.taken
        span = span + (seg.duration or 0)
    end
    local rows = A.MergeRows(lists)
    if #rows == 0 then return end
    local e = { damage = 0, count = #segments, gap = gap, span = span, attackers = {} }
    local byName = {}
    for _, r in ipairs(rows) do
        local a = byName[r.src]
        if not a then
            a = { name = r.src, class = r.srcClass, pet = r.pet, damage = 0, spellList = {} }
            byName[r.src] = a
            e.attackers[#e.attackers + 1] = a
        end
        local s = MeterSpell(r)
        a.spellList[#a.spellList + 1] = s
        a.damage = a.damage + r.amount
        e.damage = e.damage + r.amount
    end
    for _, a in ipairs(e.attackers) do
        a.pct = e.damage > 0 and a.damage / e.damage * 100 or 0
        for _, s in ipairs(a.spellList) do s.pct = a.damage > 0 and s.total / a.damage * 100 or 0 end
        SortBy(a.spellList, "total")
    end
    SortBy(e.attackers, "damage")
    recap.earlier = e
end

-- Your damage to each enemy (Meter.ReadTargets) from several combats as one list, by name.
function A.MergeTargets(lists)
    local out, byName = {}, {}
    for _, rows in ipairs(lists) do
        for _, r in ipairs(rows or {}) do
            local m = byName[r.name]
            if not m then
                m = { name = r.name, class = r.class, amount = 0 }
                byName[r.name] = m
                out[#out + 1] = m
            end
            m.class = m.class or r.class
            m.amount = m.amount + (r.amount or 0)
            if r.total then m.total = (m.total or 0) + r.total end
        end
    end
    return out
end

-- Meter rows as one spell list, adding up the same spell (healing rows come one per target).
local function SpellTotals(rows)
    local list, byKey, total = {}, {}, 0
    for _, r in ipairs(rows or {}) do
        local key = (r.pet and r.src or "") .. "\001" .. (r.spellId or 0) .. "\001" .. (r.spell or "")
        local s = byKey[key]
        if not s then
            s = MeterSpell(r)
            s.total, s.pet = 0, r.pet
            byKey[key] = s
            list[#list + 1] = s
        end
        s.total = s.total + r.amount
        total = total + r.amount
    end
    for _, s in ipairs(list) do s.pct = total > 0 and s.total / total * 100 or 0 end
    return SortBy(list, "total"), total
end

-- What you did in the fight, from the damage meter: { total, dps, duration, spells, taken (damage
-- you took in the same combats), targets = { { name, class, amount, pct, total, share } },
-- healing = { total, spells } }, or nil when the meter had nothing.
-- opts: { duration, taken, healed (rows), targets (Meter.ReadTargets rows) }.
function A.Dealt(rows, opts)
    opts = opts or {}
    local spells, total = SpellTotals(rows)
    local heals, healed = SpellTotals(opts.healed)
    if total <= 0 and healed <= 0 then return nil end
    local d = { total = total, spells = spells, duration = opts.duration, taken = opts.taken }
    d.dps = (d.duration or 0) > 0.1 and total / d.duration or nil
    if healed > 0 then d.healing = { total = healed, spells = heals } end
    if opts.targets and #opts.targets > 0 then
        local targets = {}
        for _, t in ipairs(opts.targets) do
            targets[#targets + 1] = { name = t.name, class = t.class, amount = t.amount, total = t.total,
                pct = total > 0 and math.min(100, t.amount / total * 100) or 0,
                share = (t.total or 0) > 0 and math.min(100, t.amount / t.total * 100) or nil }
        end
        table.sort(targets, function(a, b) return a.amount > b.amount end)
        d.targets = targets
    end
    return d
end

-- Who healed whom over the fight you died in, both sides: recap.ledger = { healers = { { name,
-- class, ally, total, onMe, onKiller, targets = { { name, amount } } } }, onMe, allyTotal,
-- enemyTotal }, healers by most healing.
function A.AddLedger(recap, segments)
    local merged = {}
    for _, seg in ipairs(segments or {}) do
        for name, h in pairs(seg.ledger or {}) do
            local m = merged[name] or { name = name, class = h.class, ally = h.ally, total = 0, targets = {} }
            merged[name] = m
            m.total = m.total + h.total
            for target, amount in pairs(h.targets) do m.targets[target] = (m.targets[target] or 0) + amount end
        end
    end
    if not next(merged) then return end
    local killer = recap.killer and not recap.killer.env and (recap.killer.fullName or recap.killer.name)
    local L = { healers = {}, onMe = 0, allyTotal = 0, enemyTotal = 0 }
    for _, m in pairs(merged) do
        -- Targets are named as the meter gives them; you and the killer by any shape of the name.
        m.onMe, m.onKiller = 0, 0
        for target, amount in pairs(m.targets) do
            if ns.IsMe(target) then m.onMe = m.onMe + amount
            elseif killer and ns.SameName(target, killer) then m.onKiller = m.onKiller + amount end
        end
        local list = {}
        for target, amount in pairs(m.targets) do list[#list + 1] = { name = target, amount = amount } end
        table.sort(list, function(a, b) return a.amount > b.amount end)
        m.targets = list
        if m.ally then
            L.allyTotal = L.allyTotal + m.total
            L.onMe = L.onMe + m.onMe
        else
            L.enemyTotal = L.enemyTotal + m.total
        end
        L.healers[#L.healers + 1] = m
    end
    table.sort(L.healers, function(a, b) return a.total > b.total end)
    recap.ledger = L
end

-- Your damage and healing over the combats of the fight you died in (Fight.lua segments).
function A.AddDealt(recap, segments)
    local dealt, healed, targets, duration, taken = {}, {}, {}, 0, 0
    for _, seg in ipairs(segments or {}) do
        dealt[#dealt + 1] = seg.dealt
        healed[#healed + 1] = seg.healed
        targets[#targets + 1] = seg.targets
        duration = duration + (seg.duration or 0)
        for _, r in ipairs(seg.taken or {}) do taken = taken + (r.amount or 0) end
    end
    if #segments == 0 then return end
    recap.dealt = A.Dealt(A.MergeRows(dealt), { duration = duration, taken = taken, healed = A.MergeRows(healed),
        targets = A.MergeTargets(targets) })
end

-- A duel, from the damage meter's totals (Meter.lua): rows { src, srcClass, pet, spellId, spell,
-- melee, amount, overkill } of the damage you took. There are no single hits, so hit counts stay 0
-- and the windows check recap.totalsOnly. meta also has opponent, duration, won (you won), dealt and
-- healed (rows of your own damage and healing) and targets (your damage to each enemy).
function A.BuildFromMeter(rows, meta)
    local recap = NewRecap(meta, {})
    recap.totalsOnly = true
    recap.won = meta.won or nil
    recap.earlier = meta.earlier -- { count, gap } when combat dropped mid-duel (rows already merged)
    recap.duration = meta.duration or 0
    recap.windowStart, recap.span = -recap.duration, recap.duration
    local T = { damage = 0, hits = 0, crits = 0, absorbed = 0, resisted = 0, blocked = 0, overkill = 0 }
    local attackers, attackerList, spellList = {}, {}, {}
    for _, r in ipairs(rows) do
        local a = attackers[r.src]
        if not a then
            a = { name = r.src, class = r.srcClass, pet = r.pet, damage = 0, hits = 0, crits = 0, spellList = {} }
            attackers[r.src] = a
            attackerList[#attackerList + 1] = a
        end
        local s = MeterSpell(r)
        a.spellList[#a.spellList + 1] = s
        spellList[#spellList + 1] = s
        a.damage = a.damage + r.amount
        T.damage = T.damage + r.amount
    end
    for _, a in ipairs(attackerList) do
        a.pct = T.damage > 0 and a.damage / T.damage * 100 or 0
        for _, s in ipairs(a.spellList) do s.pct = a.damage > 0 and s.total / a.damage * 100 or 0 end
        SortBy(a.spellList, "total")
    end
    for _, s in ipairs(spellList) do s.pct = T.damage > 0 and s.total / T.damage * 100 or 0 end
    recap.attackers = SortBy(attackerList, "damage")
    recap.spells = SortBy(spellList, "total")
    recap.schools = {}
    T.enemies = #attackerList
    T.dps = recap.duration > 0.1 and T.damage / recap.duration or T.damage
    recap.totals = T

    -- Your own damage.
    recap.dealt = A.Dealt(meta.dealt, { duration = recap.duration, taken = T.damage, healed = meta.healed, targets = meta.targets })

    -- The opponent; their biggest spell stands in for the killing blow, which the meter doesn't know.
    local opponent = meta.opponent and ns.Units.Short(meta.opponent)
    local top
    for _, a in ipairs(recap.attackers) do
        if a.name == opponent or ns.SameName(a.name, opponent) then top = a; break end
    end
    top = top or recap.attackers[1]
    local k = { name = opponent or (top and top.name) or "Unknown", fullName = meta.opponentFull,
        class = (top and top.class) or meta.opponentClass, duel = true, won = meta.won or nil }
    if top then
        local s = top.spellList[1]
        k.damage, k.pct, k.spells = top.damage, top.pct, top.spellList
        if s then k.spell, k.id, k.icon, k.school, k.amount = s.name, s.id, s.icon, s.school, s.total end
    end
    recap.killer = k
    return recap
end

---------------------------------------------------------------------------
-- A made-up death, to try the windows outside a battleground (/brecap test)
---------------------------------------------------------------------------

-- { seconds before death, source, class, spellId, spell, school, amount, extra fields }
local SCRIPT = {
    { -9.6, "Smashgrip", "WARRIOR", 0, "Melee", 1, 310, { melee = true } },
    { -8.4, "Smashgrip", "WARRIOR", 12294, "Mortal Strike", 1, 612 },
    { -7.6, "Stabbyface", "ROGUE", 1752, "Sinister Strike", 1, 498, { crit = true } },
    { -7.0, "Stabbyface", "ROGUE", 0, "Melee", 1, 182, { melee = true } },
    { -6.4, "Stabbyface", "ROGUE", 0, "Melee", 1, 160, { melee = true, glancing = true } },
    { -5.9, "Smashgrip", "WARRIOR", 12294, "Mortal Strike", 1, 680, { absorbed = 120 } },
    { -4.8, "Stabbyface", "ROGUE", 0, "Melee", 1, 175, { melee = true } },
    { -4.2, "Smashgrip", "WARRIOR", 0, "Melee", 1, 590, { melee = true, crit = true } },
    { -3.5, "Stabbyface", "ROGUE", 1752, "Sinister Strike", 1, 270 },
    { -2.6, "Smashgrip", "WARRIOR", 12294, "Mortal Strike", 1, 650 },
    { -1.4, "Snarl", nil, 17253, "Bite", 1, 88, { pet = true } },
    { -0.9, "Smashgrip", "WARRIOR", 0, "Melee", 1, 330, { melee = true, blocked = 40 } },
    { -0.4, "Arrowtoe", "HUNTER", 3044, "Arcane Shot", 64, 140, { resisted = 35, ranged = true } },
    { 0.0, "Stabbyface", "ROGUE", 2098, "Eviscerate", 1, 1120, { crit = true } },
}

function A.Test()
    local maxHp = 5000
    local hp = maxHp
    local events = {}
    for _, row in ipairs(SCRIPT) do
        local rel, src, class, id, spell, school, amount, extra = unpack(row)
        local e = { kind = "dmg", rel = rel, src = src, srcClass = class, spellId = id, spell = spell,
            school = school, amount = amount }
        for k, v in pairs(extra or {}) do e[k] = v end
        hp = hp - amount
        if hp <= 0 then e.overkill = -hp; hp = 0 end
        e.hp, e.hpMax = hp, maxHp
        events[#events + 1] = e
    end
    local recap = A.Build(events, {
        kind = "bg", zone = "Warsong Gulch (test)", player = UnitName("player"), class = select(2, UnitClass("player")), maxHp = maxHp,
    })
    recap.dealt = A.Dealt({
        { spellId = 133, spell = "Fireball", amount = 2380 },
        { spellId = 116, spell = "Frostbolt", amount = 1460 },
        { spellId = 2136, spell = "Fire Blast", amount = 610 },
        { spellId = 0, spell = "Melee", melee = true, amount = 95 },
    }, {
        duration = 24.5, taken = 6900,
        healed = { { spellId = 2061, spell = "Flash Heal", amount = 1240 } },
        targets = {
            { name = "Smashgrip", class = "WARRIOR", amount = 2950, total = 4100 },
            { name = "Stabbyface", class = "ROGUE", amount = 1595, total = 3300 },
        },
    })
    recap.test = true
    return recap
end

-- A made-up duel (/brecap test duel, /brecap test win).
function A.TestDuel(won)
    local rows = {
        { src = "Smashgrip", srcClass = "WARRIOR", spellId = 0, spell = "Melee", melee = true, amount = 1840 },
        { src = "Smashgrip", srcClass = "WARRIOR", spellId = 12294, spell = "Mortal Strike", amount = 1310 },
        { src = "Smashgrip", srcClass = "WARRIOR", spellId = 1680, spell = "Whirlwind", amount = 720 },
        { src = "Smashgrip", srcClass = "WARRIOR", spellId = 1715, spell = "Hamstring", amount = 95 },
    }
    local dealt = {
        { spellId = 133, spell = "Fireball", amount = won and 3900 or 2100 },
        { spellId = 116, spell = "Frostbolt", amount = won and 1650 or 900 },
        { spellId = 2136, spell = "Fire Blast", amount = 620 },
    }
    if won then
        for _, r in ipairs(rows) do r.amount = math.floor(r.amount * 0.6) end
    end
    local recap = A.BuildFromMeter(rows, {
        kind = "duel", zone = "Orgrimmar (test)", player = UnitName("player"), class = select(2, UnitClass("player")),
        opponent = "Smashgrip", duration = 21.4, won = won, dealt = dealt,
        targets = { { name = "Smashgrip", class = "WARRIOR", amount = won and 6170 or 3620, total = won and 6170 or 3620 } },
    })
    recap.test = true
    return recap
end
