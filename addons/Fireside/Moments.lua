local _, ns = ...
local C = ns.Compat

-- Moments: what the data saw each member do well in a run, worded as something to thank them for,
-- each with the kudo it suggests. And the run's lessons for the whole group: what the deaths had in
-- common, worded as what to try, with no names. The Campfire shows both; blame per person stays on
-- the private run and death pages.
local Mo = {}
ns.Moments = Mo

local function Plural(n, word) return ("%d %s%s"):format(n, word, n == 1 and "" or "s") end

local function Abbrev(n) return AbbreviateNumbers and AbbreviateNumbers(n) or tostring(n) end

-- Per member over the whole run, by short name: { done, healed, taken, avoidable, interrupts,
-- dispels, fights (fights with their meter data), died }.
function Mo.Totals(run)
    local out = {}
    local function Get(name)
        local t = out[name]
        if not t then t = { done = 0, healed = 0, taken = 0, avoidable = 0, interrupts = 0, dispels = 0, fights = 0, died = 0 }; out[name] = t end
        return t
    end
    for _, f in ipairs(run.fights or {}) do
        for name, p in pairs(f.stats or {}) do
            local t = Get(name)
            for _, k in ipairs({ "done", "healed", "taken", "avoidable", "interrupts", "dispels" }) do t[k] = t[k] + (p[k] or 0) end
            t.fights = t.fights + 1
        end
    end
    for _, d in ipairs(run.deaths or {}) do
        local t = d.victim and Get(d.victim)
        if t then t.died = t.died + 1 end
    end
    return out
end

-- Fights where a healer kept someone alive who took a big share of the damage: { [healer] = { [target] = fights } }.
local function Saves(run)
    local out = {}
    for i, f in ipairs(run.fights or {}) do
        local stats, ledger = f.stats, f.ledger
        if stats and ledger then
            local taken = 0
            for _, p in pairs(stats) do taken = taken + (p.taken or 0) end
            local died = {}
            for _, d in ipairs(run.deaths or {}) do if d.fight == i then died[d.victim] = true end end
            for healer, h in pairs(ledger) do
                for target, amount in pairs(h.targets or {}) do
                    local t = stats[target]
                    if target ~= "?" and target ~= healer and t and not died[target] and taken > 0
                        and (t.taken or 0) >= taken * 0.3 and amount >= (t.taken or 0) * 0.5 then
                        out[healer] = out[healer] or {}
                        out[healer][target] = (out[healer][target] or 0) + 1
                    end
                end
            end
        end
    end
    return out
end

-- The run's likely-cause deaths per member and reason tag: { [short] = { [tag] = n } }.
function Mo.Slips(run)
    local out = {}
    for _, d in ipairs(run.deaths or {}) do
        local why = d.top and d.reasons and d.reasons[d.top] and d.reasons[d.top][1]
        if why and not d.unclear then
            out[d.top] = out[d.top] or {}
            local tag = ns.History.Tag(why)
            out[d.top][tag] = (out[d.top][tag] or 0) + 1
        end
    end
    return out
end

-- Moments for every member, as seen by you: { [short] = { { text, kudo, weight }, ... } }, best
-- first. "you" in the texts is the viewer.
function Mo.For(run)
    local totals = Mo.Totals(run)
    local tank, healer = ns.Blame.Roles(run)
    local slips = Mo.Slips(run)
    local saves = Saves(run)
    local me = C.Short(run.me)
    local out = {}
    local function Add(name, text, kudo, weight)
        out[name] = out[name] or {}
        table.insert(out[name], { text = text, kudo = kudo, weight = weight })
    end
    local groupTaken, groupDone, groupHealed = 0, 0, 0
    for _, t in pairs(totals) do groupTaken, groupDone, groupHealed = groupTaken + t.taken, groupDone + t.done, groupHealed + t.healed end
    local fights = #(run.fights or {})

    for name, t in pairs(totals) do
        local s = slips[name] or {}
        if t.interrupts >= 2 then Add(name, ("Interrupted %s"):format(Plural(t.interrupts, "cast")), "kicks", 2 + t.interrupts) end
        if name == tank and t.fights >= 2 then
            if not s["losing aggro"] then
                Add(name, ("Tanked %s without losing a mob to the group"):format(Plural(t.fights, "pull")), "steady", 6)
            end
            if not s["over-pulling"] and (run.wipes or 0) == 0 then
                Add(name, ("%s, no over-pulls, no wipes"):format(Plural(t.fights, "pull")), "pulls", 4)
            end
        end
        if name == healer and t.healed > 0 then
            local cover = groupTaken > 0 and t.healed / groupTaken or 0
            local died = 0
            for other, o in pairs(totals) do if other ~= name then died = died + o.died end end
            Add(name, ("Healed %s, %d%% of everything the group took%s"):format(Abbrev(t.healed), math.min(999, cover * 100),
                died == 0 and ", and nobody else died" or ""), "kept", died == 0 and 7 or 3 + cover * 3)
        end
        for target, n in pairs(saves[name] or {}) do
            if target == me then
                Add(name, ("Kept you alive through %s"):format(Plural(n, "hard pull")), "saved", 8 + n)
            else
                Add(name, ("Kept %s alive through %s"):format(target, Plural(n, "hard pull")), "kept", 3 + n)
            end
        end
        if name ~= tank and name ~= healer and groupDone > 0 and t.done >= groupDone * 0.3 then
            Add(name, ("%d%% of the group's damage (%s)"):format(t.done / groupDone * 100, Abbrev(t.done)), "damage", 3 + t.done / groupDone * 5)
        end
        if fights >= 3 and t.fights >= 3 and t.taken > 0 and t.avoidable == 0 then
            Add(name, ("No avoidable damage taken in %s"):format(Plural(t.fights, "fight")), "aware", 3)
        end
        if t.dispels >= 2 then
            Add(name, ("Removed %s"):format(Plural(t.dispels, "debuff")), name == healer and "kept" or "saved", 2 + t.dispels / 2)
        end
    end
    -- Everyone who stayed through a wipe to the end.
    if (run.wipes or 0) > 0 and run.finished then
        for full, m in pairs(run.members or {}) do
            if not m.left then Add(C.Short(full), ("Stayed through %s to the last boss"):format(Plural(run.wipes, "wipe")), "calm", 4) end
        end
        Add(me, ("Stayed through %s to the last boss"):format(Plural(run.wipes, "wipe")), "calm", 4)
    end
    -- The sparks you sent during the run add up to the kudo they point at.
    local sent = {}
    for _, e in ipairs(run.sparks or {}) do
        local spark = ns.Marks.spark[e.s]
        if spark and spark.kudo and C.IsMe(e.from) and not C.IsMe(e.to) then
            local to = C.Short(e.to)
            sent[to] = sent[to] or {}
            local k = sent[to][spark.kudo] or { n = 0, s = e.s }
            k.n = k.n + 1
            sent[to][spark.kudo] = k
        end
    end
    for to, kudos in pairs(sent) do
        for kudo, k in pairs(kudos) do
            Add(to, ("You sent them %s"):format(k.n == 1 and ("a \"" .. ns.Marks.SparkLabel(k.s) .. "\"")
                or (k.n .. " sparks like \"" .. ns.Marks.SparkLabel(k.s) .. "\"")), kudo, 5 + k.n * 2)
        end
    end
    for _, list in pairs(out) do table.sort(list, function(a, b) return a.weight > b.weight end) end
    return out
end

-- After one fight: the best small thing someone else did, to offer you a spark for it, or nil.
-- { to (short name), s (spark), text }. deaths: the fight's deaths ({ victim }).
function Mo.FightPrompt(run, f, deaths)
    local stats, ledger = f.stats, f.ledger
    if not stats or f.wipe then return nil end
    local me = C.Short(run.me)
    local died = {}
    for _, d in ipairs(deaths or {}) do died[d.victim] = true end
    local taken = 0
    for _, p in pairs(stats) do taken = taken + (p.taken or 0) end
    local best
    local function Offer(to, s, text, weight)
        if to and to ~= me and (not best or weight > best.weight) then best = { to = to, s = s, text = text, weight = weight } end
    end
    -- Someone's healing carried you through it.
    local mine = stats[me]
    for healer, h in pairs(ledger or {}) do
        local onMe = h.targets and h.targets[me] or 0
        if mine and not died[me] and taken > 0 and (mine.taken or 0) >= taken * 0.3 and onMe >= (mine.taken or 0) * 0.5 then
            Offer(healer, "clutch", ("%s kept you up through that pull"):format(healer), 10)
        end
    end
    local tank = ns.Blame.Roles(run)
    for name, p in pairs(stats) do
        if (p.interrupts or 0) >= 2 then
            Offer(name, "kick", ("%s interrupted %d casts that fight"):format(name, p.interrupts), 5 + p.interrupts)
        end
        if (p.dispels or 0) >= 2 then
            Offer(name, "cleanse", ("%s removed %d debuffs that fight"):format(name, p.dispels), 4 + p.dispels / 2)
        end
    end
    if tank and (f.mobs or 0) >= 4 and not next(died) then
        Offer(tank, "pull", ("%s held a %d-mob pull and nobody died"):format(tank, f.mobs), 3 + f.mobs / 2)
    end
    return best
end

-- The kudo the data suggests you give a member (their best moment you haven't given yet).
function Mo.Suggest(run, short, moments, given)
    for _, m in ipairs((moments or Mo.For(run))[short] or {}) do
        if not (given and given[m.kudo]) then return m end
    end
end

-- The tips the data suggests for a member (private: only in your tip composer): { [tipID] = "why" }.
function Mo.TipHints(run, short)
    local out = {}
    for tag, n in pairs(Mo.Slips(run)[short] or {}) do
        for _, tip in ipairs(ns.Marks.TIPS) do
            if tip.tag == tag then out[tip.id] = ("the data saw %s %s"):format(tag, n == 1 and "once" or (n .. " times")) end
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Lessons: the group's, no names
-- ---------------------------------------------------------------------------

local LESSONS = {
    ["standing in avoidable damage"] = { "Watch the ground", "%s started in avoidable damage%s." },
    ["pulling threat"] = { "Give the tank a few seconds", "%s came from pulled threat%s." },
    ["losing aggro"] = { "Mind the loose mobs", "%s came from mobs hitting someone other than the tank%s." },
    ["low healing"] = { "Healing ran short", "%s came when the healing couldn't keep up%s." },
    ["a dead healer"] = { "Protect the healer", "%s followed the healer going down%s." },
    ["pulling early"] = { "Let the tank pull", "%s followed a pull before the tank's%s." },
    ["over-pulling"] = { "Smaller pulls", "%s followed big pulls%s." },
    ["missed interrupts"] = { "Interrupt the casters", "%s came from casts nobody interrupted%s." },
    ["falling or the environment"] = { "Mind the edges", "%s came from falls or the environment%s." },
}

-- What the run teaches, most deaths first: { { title, text } }. A clean run says so.
function Mo.Lessons(run)
    local by, spells = {}, {}
    for _, d in ipairs(run.deaths or {}) do
        local why = d.top and d.reasons and d.reasons[d.top] and d.reasons[d.top][1]
        local tag = why and not d.unclear and ns.History.Tag(why)
        if tag and LESSONS[tag] then
            by[tag] = (by[tag] or 0) + 1
            if d.spell then spells[tag] = spells[tag] or {}; spells[tag][d.spell] = true end
        end
    end
    local list = {}
    for tag, n in pairs(by) do
        local names = {}
        for s in pairs(spells[tag] or {}) do names[#names + 1] = s end
        table.sort(names)
        local l = LESSONS[tag]
        local spell = #names > 0 and (" (" .. table.concat(names, ", ", 1, math.min(2, #names)) .. ")") or ""
        list[#list + 1] = { n = n, title = l[1], text = l[2]:format(n == 1 and "One death" or (n .. " deaths"), spell) }
    end
    table.sort(list, function(a, b) return a.n > b.n end)
    if #list == 0 then
        if #(run.deaths or {}) == 0 then
            list[1] = { title = "A clean run", text = (run.finished and "Nobody died, all the way to the last boss." or "Nobody died.") }
        else
            list[1] = { title = "No clear lesson", text = "The deaths had no cause in common the data could see." }
        end
    end
    return list
end
