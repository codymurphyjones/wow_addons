local _, ns = ...
local C = ns.Compat

-- Everyone you've run a dungeon with: who they are, the runs you did together, how those went
-- (finished, wipes), their deaths and how often they were the likely cause of a death, plus your
-- own note and thumbs up/down.
local H = {}
ns.History = H

-- A short tag for a blame reason, to count the most common ones per player.
local REASON_TAGS = {
    { "avoidable", "standing in avoidable damage" }, { "pulled threat", "pulling threat" },
    { "didn't hold", "losing aggro" }, { "healing covered", "low healing" }, { "healer had already", "a dead healer" },
    { "pulled before", "pulling early" }, { "over%-pull", "over-pulling" }, { "interrupted", "missed interrupts" },
    { "died to", "falling or the environment" }, { "no clear cause", "unclear deaths" },
}
local function Tag(reason)
    for _, t in ipairs(REASON_TAGS) do
        if reason:find(t[1]) then return t[2] end
    end
    return "other"
end

function H:Get(full, create)
    local p = full and ns.db.players[full]
    if not p and create and full then
        p = { first = time(), runs = {}, t = { runs = 0, finished = 0, wipes = 0, deaths = 0, fault = 0, faultDeaths = 0, bosses = 0 },
            reasons = {} }
        ns.db.players[full] = p
    end
    return p
end

-- A player by name ("Bob" or "Bob-Realm"), or nil.
function H:Find(text)
    text = ns.Trim(text):lower()
    if text == "" then return nil end
    for full in pairs(ns.db.players) do
        if full:lower() == text or C.Short(full):lower() == text then return full end
    end
end

-- Who tanks and heals, when the game doesn't say: the tank takes the most damage as a class that
-- can tank, the healer does the most healing by a clear margin.
function H:InferRoles(run, f)
    run.roles = run.roles or {}
    local stats = f.stats
    if not stats then return end
    local tank, healer = ns.Blame.Roles(run)
    local taken, healed = 0, {}
    for _, p in pairs(stats) do taken = taken + (p.taken or 0) end
    if not tank then
        local best, bestTaken = nil, 0
        for name, p in pairs(stats) do
            local class = p.class
            if ns.TANK_CLASSES[class or ""] and (p.taken or 0) > bestTaken then best, bestTaken = name, p.taken end
        end
        if best and taken > 0 and bestTaken >= taken * 0.3 then run.roles.tank = best end
    end
    if not healer then
        for name, p in pairs(stats) do healed[#healed + 1] = { name, p.healed or 0 } end
        table.sort(healed, function(a, b) return a[2] > b[2] end)
        local first, second = healed[1], healed[2]
        if first and first[2] > 0 and (not second or first[2] >= second[2] * 2) and first[1] ~= run.roles.tank then
            run.roles.healer = first[1]
        end
    end
end

-- Counts one death: the victim's, and blame for everyone with a share.
function H:OnDeath(run, d)
    local victim = ns.Run:FullName(run, d.victim)
    -- Your own record isn't kept: this is about the people you group with.
    local v = victim and victim ~= run.me and self:Get(victim, true)
    if v then v.t.deaths = v.t.deaths + 1 end
    for who, share in pairs(d.blame or {}) do
        local full = ns.Run:FullName(run, who)
        local p = full and full ~= run.me and self:Get(full, true)
        if p then
            p.t.fault = p.t.fault + share * (d.weight or 1)
            if who == d.top then
                p.t.faultDeaths = p.t.faultDeaths + 1
                local reason = d.reasons and d.reasons[who] and d.reasons[who][1]
                if reason then
                    local tag = Tag(reason)
                    p.reasons[tag] = (p.reasons[tag] or 0) + 1
                end
            end
        end
    end
end

-- A finished run: everyone in it gets it on their record.
function H:AddRun(run)
    local kills = 0
    for _, b in pairs(run.bosses) do kills = kills + (b.kills > 0 and 1 or 0) end
    run.bossKills = kills
    for full, m in pairs(run.members) do
        local p = self:Get(full, true)
        p.class, p.race, p.level = m.class or p.class, m.race or p.race, m.level or p.level
        p.guild = m.guild or p.guild
        p.last, p.lastRole = run.stop or time(), m.role or (run.roles and (run.roles.tank == C.Short(full) and "tank"
            or run.roles.healer == C.Short(full) and "healer")) or p.lastRole
        table.insert(p.runs, run.id)
        p.t.runs = p.t.runs + 1
        if run.finished then p.t.finished = p.t.finished + 1 end
        p.t.wipes = p.t.wipes + (run.wipes or 0)
        p.t.bosses = p.t.bosses + kills
    end
end

-- The most common thing a player gets blamed for.
function H:TopReason(p)
    local best, n = nil, 0
    for tag, count in pairs(p.reasons or {}) do
        if count > n then best, n = tag, count end
    end
    return best, n
end

-- One line about a player, for chat, tooltips and the popup.
function H:Summary(full, short)
    local p = self:Get(full)
    if not p then return nil end
    local t = p.t
    local parts = {}
    parts[#parts + 1] = ("%d run%s together (%d finished)"):format(t.runs, t.runs == 1 and "" or "s", t.finished)
    if t.wipes > 0 then parts[#parts + 1] = ("%d wipe%s"):format(t.wipes, t.wipes == 1 and "" or "s") end
    parts[#parts + 1] = ("%d death%s"):format(t.deaths, t.deaths == 1 and "" or "s")
    if t.runs > 0 then
        parts[#parts + 1] = ("at fault %.1f deaths a run"):format(t.fault / t.runs)
    end
    local reason, n = self:TopReason(p)
    if reason and n >= 2 then parts[#parts + 1] = "often " .. reason end
    local text = table.concat(parts, ", ")
    local last = p.runs[#p.runs] and ns.Run:Get(p.runs[#p.runs])
    if last and not short then
        text = text .. (". Last: %s %s%s"):format(last.instance, date("%m/%d", last.start), last.finished and " (full clear)" or "")
    end
    if p.rating then text = text .. (p.rating > 0 and "  |cff59f28c+|r" or "  |cffd9736b-|r") end
    if p.note and p.note ~= "" then text = text .. "  |cffffd24d\"" .. p.note .. "\"|r" end
    return text
end

-- Runs you did with a player, newest first.
function H:RunsWith(full)
    local p = self:Get(full)
    local out = {}
    for i = #(p and p.runs or {}), 1, -1 do
        local r = ns.Run:Get(p.runs[i])
        if r then out[#out + 1] = r end
    end
    return out
end

-- Every death involving a player (as victim or blamed), newest first: { run, death }.
function H:DeathsOf(full)
    local short = C.Short(full)
    local out = {}
    for _, r in ipairs(self:RunsWith(full)) do
        for i = #r.deaths, 1, -1 do
            local d = r.deaths[i]
            if d.victim == short or (d.blame and d.blame[short]) then out[#out + 1] = { run = r, death = d } end
        end
    end
    return out
end

function H:SetNote(full, note)
    local p = self:Get(full, true)
    note = ns.Trim(note)
    p.note = note ~= "" and note or nil
    ns:Changed()
end

function H:SetRating(full, rating)
    local p = self:Get(full, true)
    p.rating = (p.rating == rating) and nil or rating
    ns:Changed()
end
