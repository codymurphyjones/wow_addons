local _, ns = ...

-- Turns a lost fight into lessons. Every rule looks at what happened (the fight record, your death
-- recap, the damage meter) and, when it applies, says what to do next time using only what your
-- character actually has: your spells at their ranks, your talents that change them, the items in
-- your bags, your key bindings. It never says to change your stats, gear or talents. Each lesson
-- also says how it would change the fight, so Odds.lua can estimate your chances with the advice.
local L = {}
ns.Lessons = L

local Kit = ns.Kit

-- Mechanic immunity bits (MechanicImmuneMask, 1 << (mechanic - 1)).
local MECH = { fear = 16, root = 64, silence = 256, sleep = 512, snare = 1024, stun = 2048, bleed = 16384, polymorph = 65536, interrupt = 33554432 }
local function Immune(mob, what)
    local mask = mob.mech
    local bit = MECH[what]
    return mask and bit and (math.floor(mask / bit) % 2 == 1) or false
end

local function Icon(s) return s.icon and ("|T" .. s.icon .. ":14:14|t ") or "" end

-- Spells or items you have for a job, as text lines.
local function Options(list, kind)
    local out = {}
    for _, s in ipairs(list) do out[#out + 1] = Icon(s) .. Kit:Describe(s, kind) end
    return out
end

-- Whether you cast a spell (by name) during the fight.
local function Used(f, name)
    for _, c in ipairs(f.casts) do if c.name == name then return true end end
    return false
end

local function UsedAny(f, list)
    for _, s in ipairs(list) do if Used(f, s.name) then return true end end
    return false
end

local function Avg(range) return range and (range[1] + (range[2] or range[1])) / 2 or 0 end

-- ---------------------------------------------------------------------------
-- Rules: each returns a lesson { key, title, what, todo = { lines }, effect, weight } or nil.
-- ---------------------------------------------------------------------------

local Rules = {}

-- Too many mobs at once.
Rules[#Rules + 1] = function(f, ctx)
    if #f.order < 2 then return nil end
    local first = f.mobs[f.order[1]]
    local late = {}
    for i = 2, #f.order do
        local m = f.mobs[f.order[i]]
        late[#late + 1] = ("%s (%s%s) joined at %ds"):format(m.name, m.level and ("level " .. m.level) or "level ??",
            m.kind and (", " .. m.kind) or "", m.at)
    end
    local todo = {}
    -- CC that works on the extra mobs' type and that they aren't immune to.
    local extra = f.mobs[f.order[2]]
    local cc = {}
    for _, tag in ipairs({ "cc", "fear", "stun", "root" }) do
        for _, s in ipairs(Kit:With(tag, extra.kind)) do
            local blocked = (tag == "fear" and Immune(extra, "fear")) or (tag == "stun" and Immune(extra, "stun"))
                or (tag == "root" and Immune(extra, "root")) or (tag == "cc" and (Immune(extra, "polymorph") or Immune(extra, "sleep")))
            if not blocked then cc[#cc + 1] = s end
        end
    end
    if #cc > 0 then
        todo[#todo + 1] = ("Take %s out of the fight while you kill %s:"):format(extra.name, first.name)
        for _, line in ipairs(Options(cc)) do todo[#todo + 1] = "   " .. line end
    end
    local aoe = Kit:With("aoe")
    if #aoe > 0 and #f.order >= 3 then
        todo[#todo + 1] = "Against three or more, your area spells pay off:"
        for _, line in ipairs(Options(aoe)) do todo[#todo + 1] = "   " .. line end
    end
    todo[#todo + 1] = "Pull one at a time: wait for patrols to pass, and pull from range so only one mob comes."
    local escape = Kit:With("escape")
    if #escape > 0 then
        todo[#todo + 1] = "If a second mob joins anyway, reset the fight:"
        for _, line in ipairs(Options(escape)) do todo[#todo + 1] = "   " .. line end
    end
    -- In the model: the extra mobs no longer fight you (CC or a single pull).
    local drop = {}
    for i = 2, #f.order do
        local m = f.mobs[f.order[i]]
        drop[m.name] = m.estHp or 0
    end
    return {
        key = "adds", title = ("%d mobs at once"):format(#f.order),
        what = ("You started on %s; %s."):format(first.name, table.concat(late, "; ")),
        todo = todo, effect = { dropSources = drop }, weight = 3,
    }
end

-- Casters: most of the damage came from spells.
Rules[#Rules + 1] = function(f, ctx)
    local m = f.meter
    if not m or m.taken.total <= 0 then return nil end
    local cast, top = 0, nil
    for _, r in ipairs(m.taken.rows) do
        if not r.melee and r.spellId > 0 then
            cast = cast + r.amount
            if not top or r.amount > top.amount then top = r end
        end
    end
    local share = cast / m.taken.total
    if share < 0.4 or not top then return nil end
    local todo = {}
    local mob
    for _, key in ipairs(f.order) do
        if f.mobs[key].name == top.other then mob = f.mobs[key] end
    end
    local kicks = {}
    for _, s in ipairs(Kit:With("interrupt")) do kicks[#kicks + 1] = s end
    for _, s in ipairs(Kit:With("stun")) do kicks[#kicks + 1] = s end
    local used = 0
    for _, s in ipairs(kicks) do if Used(f, s.name) then used = used + 1 end end
    if mob and Immune(mob, "interrupt") then
        todo[#todo + 1] = mob.name .. " can't be interrupted: break line of sight so it has to walk to you, and save your health for its casts."
    elseif #kicks > 0 then
        todo[#todo + 1] = ("Stop %s mid-cast with:"):format(top.spell)
        for _, line in ipairs(Options(kicks)) do todo[#todo + 1] = "   " .. line end
        if used == 0 then todo[#todo + 1] = "You didn't use any of these this fight." end
    end
    todo[#todo + 1] = "Pull casters around a corner: they stop casting and come to you."
    return {
        key = "casters", title = "The spells did it",
        what = ("%d%% of the damage you took came from spells; the worst was %s from %s (%d)."):format(share * 100, top.spell, top.other or "?", top.amount),
        todo = todo, effect = { castMul = (#kicks > 0 and used == 0) and 0.45 or 0.75 }, weight = 2 + share,
    }
end

-- Big hits, crushing blows or an elite: defensive cooldowns.
Rules[#Rules + 1] = function(f, ctx)
    local hits, maxHp = ctx.hits or {}, f.pre.maxHp
    local big, crush = nil, false
    for _, h in ipairs(hits) do
        if not h.heal and h.amount and (not big or h.amount > big.amount) then big = h end
        if h.crushing then crush = true end
    end
    local elite = false
    for _, key in ipairs(f.order) do
        local m = f.mobs[key]
        if m.rank == "elite" or m.rank == "rareelite" or (m.dbRank or 0) >= 1 then elite = true end
    end
    local bigShare = big and maxHp and big.amount / maxHp or 0
    if bigShare < 0.2 and not crush and not elite then return nil end
    local def = Kit:With("defensive")
    local items = Kit:ItemsWith("defensive")
    local unused = {}
    for _, s in ipairs(def) do if not Used(f, s.name) then unused[#unused + 1] = s end end
    local todo = {}
    if #unused > 0 then
        todo[#todo + 1] = "Open the fight with your defensive cooldowns instead of saving them:"
        for _, line in ipairs(Options(unused)) do todo[#todo + 1] = "   " .. line end
    end
    if #items > 0 then
        for _, line in ipairs(Options(items, "item")) do todo[#todo + 1] = "   " .. line end
    end
    if #todo == 0 then return nil end
    local extra = 0
    for _, s in ipairs(unused) do
        if s.amounts.absorb then extra = extra + Avg(s.amounts.absorb) end
        if s.amounts.reduce and s.amounts.duration then
            extra = extra + (s.amounts.reduce[1] / 100) * Avg(s.amounts.duration) * (ctx.model and ctx.model.inDps or 0)
        end
    end
    return {
        key = "burst", title = elite and "An elite fight" or "Big hits",
        what = big and ("Your biggest hit taken was %s for %d (%d%% of your health)%s."):format(big.spell or "?", big.amount, bigShare * 100,
            crush and ", with crushing blows" or "") or "You fought an elite.",
        todo = todo, effect = { extraHp = extra }, weight = 1.5 + bigShare,
    }
end

-- You had healing and didn't use it.
Rules[#Rules + 1] = function(f, ctx)
    local heals = {}
    for _, s in ipairs(Kit:With("heal")) do
        if not Used(f, s.name) and not s.pet then heals[#heals + 1] = s end
    end
    local potions = Kit:ItemsWith("heal")
    local unusedItems = {}
    for _, it in ipairs(potions) do if not Used(f, it.name) then unusedItems[#unusedItems + 1] = it end end
    if #heals == 0 and #unusedItems == 0 then return nil end
    local todo = {}
    local extra = 0
    if #heals > 0 then
        todo[#todo + 1] = "Heal yourself before it's too late (around half health), not at the end:"
        for _, line in ipairs(Options(heals)) do todo[#todo + 1] = "   " .. line end
        local h = heals[1]
        local casts = 2
        if h.cost and h.cost > 0 and ctx.kit.stats.power then
            casts = math.min(3, math.floor((ctx.kit.stats.power * (f.pre.power or 1)) / h.cost))
        end
        extra = extra + Avg(h.amounts.heal) * math.max(0, casts)
    end
    if #unusedItems > 0 then
        todo[#todo + 1] = "From your bags:"
        for _, line in ipairs(Options(unusedItems, "item")) do todo[#todo + 1] = "   " .. line end
        extra = extra + Avg(unusedItems[1].amounts.heal)
    end
    return {
        key = "heals", title = "Healing left unused", what = "You died with healing you didn't use.",
        todo = todo, effect = { extraHp = extra }, weight = 2,
    }
end

-- Poison, disease, curse or magic ticking on you.
Rules[#Rules + 1] = function(f, ctx)
    local periodic, total = 0, 0
    for _, h in ipairs(ctx.hits or {}) do
        if not h.heal and h.amount then
            total = total + h.amount
            if h.periodic then periodic = periodic + h.amount end
        end
    end
    if total == 0 or periodic / total < 0.3 then return nil end
    -- Which kinds the mobs use, from their spell flags.
    local kinds = {}
    local flags = { p = "poison", D = "disease", C = "curse", m = "magic" }
    for _, key in ipairs(f.order) do
        for _, id in ipairs(f.mobs[key].spells or {}) do
            local sp = ns.Mobs and ns.Mobs.spells[id]
            for letter, kind in pairs(flags) do
                if sp and sp[3] and sp[3]:find(letter, 1, true) then kinds[kind] = true end
            end
        end
    end
    local todo = {}
    local fixes = {}
    for _, s in ipairs(Kit:With("cleanse")) do
        for kind in pairs(kinds) do
            if s.cleanse and s.cleanse[kind] then fixes[#fixes + 1] = s break end
        end
    end
    for _, it in ipairs(Kit:ItemsWith("cleanse")) do fixes[#fixes + 1] = it end
    if #fixes > 0 then
        todo[#todo + 1] = "Remove it as soon as it lands:"
        for _, line in ipairs(Options(fixes)) do todo[#todo + 1] = "   " .. line end
    else
        todo[#todo + 1] = "You have nothing that removes it: kill the mob that applies it first, and heal through the ticks."
    end
    local names = {}
    for k in pairs(kinds) do names[#names + 1] = k end
    return {
        key = "dots", title = "Damage over time",
        what = ("%d%% of the hits that killed you were ticks%s."):format(periodic / total * 100,
            #names > 0 and (" (" .. table.concat(names, ", ") .. ")") or ""),
        todo = todo, effect = { inDpsMul = #fixes > 0 and 0.8 or 0.95 }, weight = 1.5,
    }
end

-- Your pet wasn't out, or died.
Rules[#Rules + 1] = function(f, ctx)
    local summon = {}
    for _, s in ipairs(Kit:With("pet")) do summon[#summon + 1] = s end
    if #summon == 0 then return nil end
    if f.pre.pet then return nil end
    return {
        key = "pet", title = "No pet",
        what = "You went into the fight without your pet.",
        todo = { "Have your pet out before you pull: it takes hits that would be yours.", unpack(Options(summon)) },
        effect = { meleeMul = 0.5 }, weight = 2.5,
    }
end

-- You started the fight hurt or low on mana.
Rules[#Rules + 1] = function(f, ctx)
    local hp, power, ptype = f.pre.hp or 1, f.pre.power or 1, f.pre.powerType
    local lowMana = ptype == "MANA" and power < 0.4
    if hp >= 0.7 and not lowMana then return nil end
    local todo = { "Rest to full before the next pull; a fight started hurt is half lost." }
    for _, it in ipairs(Kit:ItemsWith("rest")) do todo[#todo + 1] = "   " .. Icon(it) .. Kit:Describe(it, "item") end
    local bandages = {}
    for _, s in ipairs(Kit:With("heal")) do if not s.pet then bandages[#bandages + 1] = s end end
    if hp < 0.7 and #bandages > 0 then todo[#todo + 1] = "   or top up with " .. Kit:Describe(bandages[1]) end
    return {
        key = "start", title = "A bad start",
        what = ("You pulled at %d%% health%s."):format(hp * 100, lowMana and (" and %d%% mana"):format(power * 100) or ""),
        todo = todo, effect = { startFull = true }, weight = 1.5 + (1 - hp),
    }
end

-- A humanoid that runs: keep something to stop it.
Rules[#Rules + 1] = function(f, ctx)
    local runner
    for _, key in ipairs(f.order) do
        local m = f.mobs[key]
        if m.flee or (m.kind == "Humanoid" and ns.TYPES.Humanoid.flees) then runner = m break end
    end
    if not runner or #f.order < 2 then return nil end
    local stop = {}
    for _, tag in ipairs({ "stun", "root", "slow" }) do
        for _, s in ipairs(Kit:With(tag, runner.kind)) do
            if not Immune(runner, tag == "slow" and "snare" or tag) then stop[#stop + 1] = s end
        end
    end
    if #stop == 0 then return nil end
    return {
        key = "flee", title = runner.name .. " runs for help",
        what = runner.name .. " is the kind that flees at low health and brings friends back.",
        todo = { "Save one of these for when it turns to run:", unpack(Options(stop)) },
        effect = { dropSources = {} }, weight = 1,
    }
end

-- How you spent your damage, read against your strengths.
Rules[#Rules + 1] = function(f, ctx)
    local m = f.meter
    if not m or m.done.total <= 0 then return nil end
    local auto = 0
    for _, r in ipairs(m.done.rows) do
        if r.melee or r.spellId == 75 or r.spellId == 5019 then auto = auto + r.amount end
    end
    local share = auto / m.done.total
    local stats = ctx.kit.stats
    local manaUser = stats.powerType == "MANA"
    local strongest = stats.order[1]
    if share < 0.6 or not manaUser then return nil end
    -- Damage spells you know that cost mana, cheapest first.
    local spells = {}
    for _, s in ipairs(Kit:With("damage")) do
        if s.cost and s.cost > 0 and not s.pet then spells[#spells + 1] = s end
    end
    table.sort(spells, function(a, b) return (a.cost or 0) < (b.cost or 0) end)
    if #spells == 0 then return nil end
    local todo = {}
    local why = strongest == "int" and "Intellect is your strongest stat, so your mana pool is your weapon"
        or strongest == "spi" and "your Spirit brings mana back quickly between fights" or "you have mana to spend"
    todo[#todo + 1] = ("%s: spend it on"):format(why:gsub("^%l", string.upper))
    for i = 1, math.min(3, #spells) do todo[#todo + 1] = "   " .. Icon(spells[i]) .. Kit:Describe(spells[i]) end
    return {
        key = "damage", title = "Auto attacks did the work",
        what = ("%d%% of your damage was auto attacks, and you had mana left."):format(share * 100),
        todo = todo, effect = { myDpsMul = 1.25 }, weight = 1,
    }
end

-- Falling, lava, drowning.
Rules[#Rules + 1] = function(f, ctx)
    local kb = ctx.hits and ctx.hits[#ctx.hits]
    if not (kb and kb.env) then return nil end
    return {
        key = "env", title = "The world did it",
        what = ("The last blow was %s."):format((kb.spell or "the environment"):lower()),
        todo = { "Watch your footing here; no fight was lost to a mob this time." }, effect = {}, weight = 4,
    }
end

-- In a group: what the healer was doing.
Rules[#Rules + 1] = function(f, ctx)
    local m = f.meter
    if not (m and m.ledger) then return nil end
    local me = UnitName("player")
    local best, bestTotal = nil, 0
    for name, h in pairs(m.ledger) do
        if name ~= me and h.total > bestTotal then best, bestTotal = name, h.total end
    end
    if not best or bestTotal <= 0 then return nil end
    local h = m.ledger[best]
    local onMe = h.targets[me] or 0
    local others = {}
    for target, amount in pairs(h.targets) do
        if target ~= me and target ~= "?" then others[#others + 1] = { target, amount } end
    end
    table.sort(others, function(a, b) return a[2] > b[2] end)
    local what
    if h.targets["?"] and #others == 0 then
        what = ("%s healed %d in this fight (the game didn't say on whom)."):format(best, h.total)
    else
        what = ("%s healed you for %d%s."):format(best, onMe,
            others[1] and (" and %s for %d"):format(others[1][1], others[1][2]) or "")
    end
    local todo = {}
    if onMe < bestTotal * 0.25 then
        todo[#todo + 1] = "Your healer was busy elsewhere: let the tank take the mobs first, and fight where they can see you."
        local drop = Kit:With("threatdrop")
        if #drop > 0 then
            todo[#todo + 1] = "When a mob turns to you, drop it back to the tank:"
            for _, line in ipairs(Options(drop)) do todo[#todo + 1] = "   " .. line end
        end
    else
        todo[#todo + 1] = "Your healer was on you; the damage outpaced them. Use your own defensives earlier so they can catch up."
    end
    return { key = "healer", title = "Healing in the group", what = what, todo = todo, effect = { inDpsMul = 0.85 }, weight = 1.2 }
end

-- ---------------------------------------------------------------------------
-- Too hard: potions for your level, and the honest answer.
-- ---------------------------------------------------------------------------

local function PotionAdvice(f, ctx, out)
    local level = f.level or UnitLevel("player")
    local inBags = Kit:ItemsWith("heal")
    local lines, effect = {}, { extraHp = 0 }
    if #inBags > 0 then
        lines[#lines + 1] = "   " .. Icon(inBags[1]) .. Kit:Describe(inBags[1], "item")
        effect.extraHp = Avg(inBags[1].amounts.heal)
    else
        local best = ns.BestConsumable("heal", level)
        if best then
            lines[#lines + 1] = ("   %s (restores %d-%d health; from the auction house or an alchemist)"):format(best[2], best[5], best[6])
            effect.extraHp = (best[5] + best[6]) / 2
        end
    end
    local armor = ns.BestConsumable("armor", level)
    if armor then
        lines[#lines + 1] = ("   %s (+%d armor for an hour)"):format(armor[2], armor[5])
        effect.inDpsMul = 0.93
    end
    local fort = ns.BestConsumable("health", level)
    if fort then
        lines[#lines + 1] = ("   %s (+%d health for an hour)"):format(fort[2], fort[5])
        effect.extraHp = effect.extraHp + fort[5]
    end
    if ctx.kit.stats.powerType == "MANA" then
        local mana = ns.BestConsumable("mana", level)
        if mana then lines[#lines + 1] = ("   %s, if your mana runs dry"):format(mana[2]) end
    end
    if #lines == 0 then return nil end
    table.insert(lines, 1, "For a fight this hard, bring consumables:")
    local lesson = { key = "potions", title = "Bring potions", what = "This fight is beyond what you can win on your own kit.",
        todo = lines, effect = effect, weight = 2 }
    out[#out + 1] = lesson
    return lesson
end

-- ---------------------------------------------------------------------------

-- Builds the coaching for one lost fight: { lessons, odds, oddsAfter, tooHard, evenLevel, story }.
function L:Build(f, hits, maxHp)
    local kit = Kit:Get()
    if not kit then return nil end
    local model = ns.Odds.Model(f)
    -- Heals in the recap are kept apart from the hits that killed you.
    local dmg, heals = {}, {}
    for _, h in ipairs(hits or {}) do
        if h.heal then heals[#heals + 1] = h else dmg[#dmg + 1] = h end
    end
    local ctx = { kit = kit, hits = dmg, heals = heals, maxHp = maxHp, model = model }
    local lessons = {}
    for _, rule in ipairs(Rules) do
        local ok, lesson = pcall(rule, f, ctx)
        if ok and lesson then lessons[#lessons + 1] = lesson end
    end

    local before = ns.Odds.Chance(model)
    local maxDiff = 0
    for _, key in ipairs(f.order) do maxDiff = math.max(maxDiff, (f.mobs[key].level or f.level) - f.level) end
    local effects = {}
    for _, l in ipairs(lessons) do effects[#effects + 1] = l.effect end
    local after = ns.Odds.Chance(ns.Odds.Apply(model, effects))
    if after < 0.5 or maxDiff >= 4 then
        local potions = PotionAdvice(f, ctx, lessons)
        if potions then
            effects[#effects + 1] = potions.effect
            after = ns.Odds.Chance(ns.Odds.Apply(model, effects))
        end
    end
    -- Each lesson's own share of the improvement, to rank them.
    for _, l in ipairs(lessons) do
        local alone = ns.Odds.Chance(ns.Odds.Apply(model, { l.effect }))
        l.gain = math.max(0, alone - before)
        l.score = l.gain * 10 + (l.weight or 1)
    end
    table.sort(lessons, function(a, b) return a.score > b.score end)
    local tooHard = maxDiff >= 5 or after < 0.2
    return {
        lessons = lessons, odds = before, oddsAfter = after, tooHard = tooHard, maxDiff = maxDiff,
        evenLevel = tooHard and ns.Odds.EvenLevel(model, f.level) or nil, model = model,
    }
end
