local _, ns = ...
local C = ns.Compat

-- Who most probably caused a death. Every rule that fits adds blame points to someone, with a
-- reason in plain words; the points are turned into shares that add up to 100%. The evidence is
-- the death's recap (its last hits: who, what spell, melee or not), the fight's meter data
-- (damage, healing, damage taken, avoidable damage by spell, interrupts) and what was seen live
-- (who pulled, how many mobs, who died first). It's a best guess, and says how sure it is.
local Blame = {}
ns.Blame = Blame

local EARLY = 20          -- seconds into a pull: deaths this early can be the puller's fault
local LOW_HEALING = 0.35  -- healing under this share of the group's damage taken counts as low
local THREAT_LEAD = 1.3   -- a victim doing this much more damage than anyone else pulled threat

-- The tank and healer of a run (assigned roles, else inferred from fights; History.lua).
function Blame.Roles(run)
    local tank, healer
    for full, m in pairs(run.members) do
        if m.role == "tank" then tank = C.Short(full) elseif m.role == "healer" then healer = C.Short(full) end
    end
    local r = run.roles or {}
    return tank or r.tank, healer or r.healer
end

local function ClassOf(run, short)
    local full = ns.Run:FullName(run, short)
    local m = full and run.members[full]
    if m then return m.class end
    if full and full == run.me then return select(2, UnitClass("player")) end
end

function Blame:Analyze(run, f, d)
    local points, reasons = {}, {}
    local function Add(who, pts, why)
        if not who or pts <= 0 then return end
        points[who] = (points[who] or 0) + pts
        reasons[who] = reasons[who] or {}
        table.insert(reasons[who], why)
    end

    local victim = d.victim
    local stats = f.stats or {}
    local vs = stats[victim] or {}
    local tank, healer = Blame.Roles(run)
    -- Heals in the recap are kept apart: they're not what killed anyone.
    local hits, heals = {}, {}
    for _, h in ipairs(d.hits or {}) do
        if h.heal then heals[#heals + 1] = h else hits[#hits + 1] = h end
    end
    d.healsIn = #heals > 0 and heals or nil
    local kb = hits[#hits]
    d.killer, d.spell = kb and kb.src, kb and kb.spell
    d.role = victim == tank and "tank" or victim == healer and "healer" or "damage"

    local total = 0
    for _, h in ipairs(hits) do total = total + (h.amount or 0) end

    -- 1. Avoidable damage: standing in fire, not moving out of a cleave.
    local avoid = vs.avoidSpells or {}
    local avoidDmg, avoidName = 0, nil
    for _, h in ipairs(hits) do
        if h.spellId and h.spellId > 0 and avoid[h.spellId] then
            avoidDmg, avoidName = avoidDmg + (h.amount or 0), h.spell
        end
    end
    if avoidDmg > 0 and total > 0 then
        Add(victim, 3 * avoidDmg / total, ("took avoidable damage from %s (%d%% of the hits that killed them)"):format(
            avoidName or "a spell", avoidDmg / total * 100))
    end

    -- 2. A mob hitting someone who isn't the tank in melee: the tank lost it, or they pulled it off.
    local melee, meleeSrc = 0, nil
    for _, h in ipairs(hits) do
        if h.melee and not h.player then melee, meleeSrc = melee + 1, h.src end
    end
    if melee >= 2 and victim ~= tank then
        local mine, best = vs.done or 0, 0
        for name, p in pairs(stats) do
            if name ~= victim and (p.done or 0) > best then best = p.done end
        end
        if tank and mine > 0 and mine > best * THREAT_LEAD then
            Add(victim, 2, ("pulled threat: %s was hitting them, and they out-damaged everyone by %d%%"):format(
                meleeSrc or "a mob", (mine / math.max(1, best) - 1) * 100))
        elseif tank then
            Add(tank, 2, ("%s was hitting %s in melee: the tank didn't hold it"):format(meleeSrc or "a mob", victim))
        else
            Add(victim, 1, ("%s was hitting them in melee and the group had no tank"):format(meleeSrc or "a mob"))
        end
    end

    -- 3. Healing: a dead healer, or too little healing for the damage coming in.
    if healer and healer ~= victim then
        local hd = f.deaths and f.deaths[healer]
        if hd and hd.at and d.at and hd.at < d.at then
            if hd.top and hd.top ~= victim then
                Add(hd.top, 1.5, "the healer had already died, mostly their doing")
            else
                Add(healer, 0.5, "the healer had already died")
            end
        else
            local hl = f.ledger and f.ledger[healer]
            local known = hl and next(hl.targets) and not (hl.targets["?"] and not next(hl.targets, next(hl.targets)))
            local taken = 0
            for _, p in pairs(stats) do taken = taken + (p.taken or 0) end
            if known then
                -- Who the healer actually healed.
                local onVictim = hl.targets[victim] or 0
                local victimTaken = vs.taken or 0
                if victim == tank then
                    if victimTaken > 0 and onVictim < victimTaken * 0.5 then
                        Add(healer, 1.5, ("healed the tank for %d against %d damage taken (%d%%)"):format(onVictim, victimTaken, onVictim / victimTaken * 100))
                    end
                else
                    -- Healing spent elsewhere while the victim took a big share of the damage.
                    local share = hl.total > 0 and onVictim / hl.total or 0
                    local busy, busyOn = 0, nil
                    for target, amount in pairs(hl.targets) do
                        if target ~= victim and target ~= tank and amount > busy then busy, busyOn = amount, target end
                    end
                    if taken > 0 and victimTaken >= taken * 0.3 and share < 0.15 then
                        Add(healer, 1, ("spent %d%% of their healing on %s while %s took %d%% of the group's damage"):format(
                            (1 - share) * 100, busyOn and busyOn ~= healer and busyOn or "others", victim, victimTaken / taken * 100))
                    end
                end
            elseif taken > 0 and (stats[healer] or {}).healed and stats[healer].healed < taken * LOW_HEALING then
                Add(healer, 1.5, ("healing covered only %d%% of the damage the group took"):format(stats[healer].healed / taken * 100))
            end
        end
    end
    -- What each death got from healers, for the popup and the run page.
    local got = f.received and f.received[victim]
    if got then d.healed = { total = got.total, by = got.by } end

    -- 4. The pull: someone other than the tank started it, or far too many mobs came.
    local early = d.at and d.at <= EARLY
    if f.puller and tank and f.puller ~= tank and early then
        Add(f.puller, 1.5, ("pulled before the tank, and %s died %ds in"):format(victim, d.at))
    end
    local overpull = ns.db.options.overpull or 7
    if (f.mobs or 0) >= overpull then
        Add(f.puller or tank, 1.5, ("%d mobs fighting at once: an over-pull"):format(f.mobs))
    end

    -- 5. A killing spell that could have been interrupted, with no interrupts at all.
    if kb and not kb.melee and not kb.periodic and not kb.env and not avoid[kb.spellId or 0] and (kb.spellId or 0) > 0 then
        local kicks = 0
        for _, p in pairs(stats) do kicks = kicks + (p.interrupts or 0) end
        if f.stats and kicks == 0 then
            local kickers = {}
            for name in pairs(stats) do
                if name ~= victim and ns.INTERRUPTERS[ClassOf(run, name) or ""] then kickers[#kickers + 1] = name end
            end
            for _, name in ipairs(kickers) do
                Add(name, 1 / #kickers, ("nobody interrupted %s, which killed %s"):format(kb.spell or "a cast", victim))
            end
        end
    end

    -- 6. Falling, lava, drowning: that one's on them.
    if kb and kb.env then Add(victim, 3, ("died to %s"):format((kb.spell or "the environment"):lower())) end

    -- 7. Nothing stands out: shared, and marked unclear.
    if not next(points) then
        d.unclear = true
        Add(victim, 1, "no clear cause in the data")
        if tank and tank ~= victim then Add(tank, 0.5, "no clear cause in the data") end
        if healer and healer ~= victim then Add(healer, 0.5, "no clear cause in the data") end
    end

    local sum = 0
    for _, p in pairs(points) do sum = sum + p end
    d.blame, d.reasons = {}, reasons
    local top, topShare = nil, 0
    for who, p in pairs(points) do
        local share = math.floor(p / sum * 100 + 0.5) / 100
        d.blame[who] = share
        if share > topShare then top, topShare = who, share end
    end
    d.top, d.topShare = top, topShare

    -- How sure: lower without a recap, without meter data, or with no clear cause.
    local conf = 0.85
    if not d.hits then conf = conf - 0.35 end
    if not f.stats then conf = conf - 0.25 end
    for _, h in ipairs(hits) do if h.partial then conf = conf - 0.05 break end end
    if d.unclear then conf = math.min(conf, 0.3) end
    d.confidence = math.max(0.1, conf)
    -- The first death of a wipe tends to cause the rest.
    d.weight = (f.wipe and d.nth == 1) and 1.5 or 1
end

-- "Most likely Bob (tank), 60%: lost aggro..." for one death.
function Blame.Summary(d)
    if not d.top then return "no analysis" end
    local why = d.reasons and d.reasons[d.top] and d.reasons[d.top][1] or ""
    return ("most likely %s (%d%%, %s sure): %s"):format(d.top, d.topShare * 100,
        d.confidence >= 0.7 and "fairly" or d.confidence >= 0.45 and "somewhat" or "not very", why)
end
