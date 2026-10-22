local _, ns = ...
local C = ns.Compat

-- Everyone you've run a dungeon with: who they are, the runs you did together, how those went
-- (finished, wipes), their deaths and how often they were the likely cause of a death, plus your
-- private note and "would group again". The feedback about them (Marks.lua, Feedback.lua) lives on
-- the same record: p.given (kudos you gave), p.heard (kudos others told your party they gave) and
-- p.banner (the kudos their own Fireside says they've received).
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
H.Tag = Tag

-- Players by compact name ("aranaliacaelmyr"), so every shape of a name finds its record.
local byCompact, indexed

local function Index()
    local players = ns.db.players
    if indexed ~= players then
        indexed, byCompact = players, {}
        for key in pairs(players) do
            local c = type(key) == "string" and ns.Units.Compact(key)
            if c and (not byCompact[c] or key:find(" ", 1, true)) then byCompact[c] = key end
        end
    end
    return byCompact
end

-- The key a player is saved under, whatever shape the name came in ("Given Family",
-- "GivenFamily", "Given Family-Server", "Given-Family"), or the key a new record gets.
function H:Key(name)
    local key = ns.Units.KeyOf(name)
    if not key or ns.db.players[key] then return key end
    local c = ns.Units.Compact(key)
    local found = c and Index()[c]
    if found and ns.db.players[found] then return found end
    return key
end

function H:Get(full, create)
    full = full and self:Key(full)
    local p = full and ns.db.players[full]
    if not p and create and full then
        p = { first = time(), runs = {}, t = { runs = 0, finished = 0, wipes = 0, deaths = 0, fault = 0, faultDeaths = 0, bosses = 0 },
            reasons = {} }
        ns.db.players[full] = p
        local c = ns.Units.Compact(full)
        if c and indexed == ns.db.players then byCompact[c] = full end
    end
    return p
end

-- Two records of one player (saved under an old and the new key): counts added up, the rest kept
-- from whichever has it.
local function MergePlayer(kept, moved)
    if type(kept) ~= "table" or type(moved) ~= "table" then return end
    kept.t, moved.t = kept.t or {}, moved.t or {}
    for k, v in pairs(moved.t) do
        if type(v) == "number" then kept.t[k] = (kept.t[k] or 0) + v end
    end
    kept.reasons = kept.reasons or {}
    for tag, n in pairs(moved.reasons or {}) do kept.reasons[tag] = (kept.reasons[tag] or 0) + n end
    kept.runs = kept.runs or {}
    for _, id in ipairs(moved.runs or {}) do table.insert(kept.runs, id) end
    table.sort(kept.runs)
    if moved.first and (not kept.first or moved.first < kept.first) then kept.first = moved.first end
    if moved.last and (not kept.last or moved.last > kept.last) then
        kept.last, kept.lastRole = moved.last, moved.lastRole or kept.lastRole
    end
    for _, k in ipairs({ "class", "race", "level", "guild", "note", "rating", "banner" }) do
        if kept[k] == nil then kept[k] = moved[k] end
    end
    if type(moved.given) == "table" then
        kept.given = kept.given or {}
        for id, n in pairs(moved.given) do kept.given[id] = (kept.given[id] or 0) + n end
    end
    if type(moved.heard) == "table" then
        kept.heard = kept.heard or {}
        for giver, h in pairs(moved.heard) do
            if not kept.heard[giver] or (h.t or 0) > (kept.heard[giver].t or 0) then kept.heard[giver] = h end
        end
    end
    if type(moved.flak) == "table" then
        kept.flak = kept.flak or {}
        for _, e in ipairs(moved.flak) do table.insert(kept.flak, e) end
    end
    if type(moved.reports) == "table" then
        kept.reports = kept.reports or {}
        for key, r in pairs(moved.reports) do
            local had = kept.reports[key]
            if not had or (r.hand or 2) < (had.hand or 2) then kept.reports[key] = r end
        end
    end
end

-- WoW Forever names: earlier versions saved other players as "Given-Family" (UnitName's two values
-- joined), with the server ("Given Family-ClassicBetaPvP") or compact ("GivenFamily"); the key is
-- "Given Family" now. ns.Units.MigrateNames also merges keys that are one player in two shapes
-- ("GivenFamily" next to "Given Family") into the spaced one; MergePlayer adds the other record in
-- (without a merge it's dropped). Runs once per load; nothing moves once everything has.
ns:OnLoad(function()
    local U = ns.Units
    U.MigrateNames(ns.db.players, MergePlayer)
    for _, run in ipairs(ns.db.runs or {}) do
        if type(run) == "table" then
            U.MigrateNames(run.members)
            if type(run.me) == "string" then run.me = U.KeyOf(run.me) or run.me end
        end
    end
    indexed = nil
end)

-- A player by name ("Given Family" in any shape, or the given name alone), or nil.
function H:Find(text)
    text = ns.Trim(text)
    if text == "" then return nil end
    local key = self:Key(text)
    if key and ns.db.players[key] then return key end
    text = text:lower()
    for full in pairs(ns.db.players) do
        if full:lower() == text or (full:match("^(%S+) ") or ""):lower() == text then return full end
    end
end

-- A value in a table keyed by players' names (a death's blame or reasons), found by any shape.
function H.ByName(tbl, name)
    if type(tbl) ~= "table" or name == nil then return nil end
    if tbl[name] ~= nil then return tbl[name] end
    for k, v in pairs(tbl) do
        if C.SameName(k, name) then return v end
    end
end

-- Who tanks and heals. The tank is whoever has taken the most damage over the run so far, whatever
-- role the game assigned (Blame.DataTank); the healer, when the game doesn't say, does the most
-- healing by a clear margin.
function H:InferRoles(run, f)
    run.roles = run.roles or {}
    local stats = f.stats
    if not stats then return end
    run.roles.tank = ns.Blame.DataTank(run, f) or run.roles.tank
    run.roles.dataTank = true
    local _, healer = ns.Blame.Roles(run)
    local healed = {}
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
    run.bossKills = ns.Run.BossKills(run)
    for full, m in pairs(run.members) do
        local p = self:Get(full, true)
        p.class, p.race, p.level = m.class or p.class, m.race or p.race, m.level or p.level
        p.guild = m.guild or p.guild
        p.last, p.lastRole = run.stop or time(), ns.Blame.RoleOf(run, full)
        -- Someone who left before the run began (kicked while forming) sat at its fire, but didn't run it.
        if not m.before then
            table.insert(p.runs, run.id)
            p.t.runs = p.t.runs + 1
            if run.finished then p.t.finished = p.t.finished + 1 end
            p.t.wipes = p.t.wipes + (run.wipes or 0)
            p.t.bosses = p.t.bosses + kills
        end
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

-- One line about a player, for chat, tooltips and the popups: what they're known for (the kudos
-- that reached you), your runs together, and your own private take (would group again, your note).
-- Never their faults: those stay on their page, for you (H:Private).
function H:Summary(full, short)
    local p = self:Get(full)
    if not p then return nil end
    local t = p.t
    local parts = {}
    -- Flak first: the warning for a pattern, and (strongly) any you gave them yourself.
    local warning, mine = ns.Marks.FlakLines(full, short)
    if warning then parts[#parts + 1] = warning end
    if mine then parts[#parts + 1] = mine end
    local known = ns.Marks.KnownLine(full, short and 2 or 3)
    if known then parts[#parts + 1] = known end
    if t.runs > 0 then
        local together = ("%d run%s together (%d finished)"):format(t.runs, t.runs == 1 and "" or "s", t.finished)
        local last = p.runs[#p.runs] and ns.Run:Get(p.runs[#p.runs])
        if last and not short then
            together = together .. (", last %s %s"):format(last.instance, date("%m/%d", last.start))
        end
        parts[#parts + 1] = together
    elseif #parts == 0 then
        return nil
    end
    local text = table.concat(parts, "  -  ")
    if p.rating then text = text .. (p.rating > 0 and "  |cff59f28cwould group again|r" or "  |cffd9736bwouldn't group again|r") end
    if p.note and p.note ~= "" then text = text .. "  |cffffd24d\"" .. p.note .. "\"|r" end
    return text
end

-- What the data saw, for your eyes only (their page): deaths, and how often they likely set one off.
function H:Private(full)
    local p = self:Get(full)
    if not p or p.t.runs == 0 then return nil end
    local t = p.t
    local parts = { ("%d death%s in %d run%s"):format(t.deaths, t.deaths == 1 and "" or "s", t.runs, t.runs == 1 and "" or "s") }
    if t.wipes > 0 then parts[#parts + 1] = ("%d wipe%s"):format(t.wipes, t.wipes == 1 and "" or "s") end
    parts[#parts + 1] = ("likely set off %.1f deaths a run"):format(t.fault / t.runs)
    local reason, n = self:TopReason(p)
    if reason and n >= 2 then parts[#parts + 1] = "most often " .. reason end
    return table.concat(parts, ", ")
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
            if d.victim == short or C.SameName(d.victim, short) or H.ByName(d.blame, short) then
                out[#out + 1] = { run = r, death = d }
            end
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

-- For other addons (SimplePanel's Social switches, tooltips and person menus). name is the player's
-- name in any shape ("Given Family", "GivenFamily", "Given Family-Server"); guid, when given,
-- supplies the name when there's none or only the given name. Event "CHANGED" (no arguments) after
-- what Fireside knows changes (a run, a rating, a note), at most once a frame.
local _, FireAPI = ns.NewAPI("FiresideAPI", 1)
ns:OnChanged(function() FireAPI("CHANGED") end)

local function Resolve(name, guid)
    name = C.Str(name)
    if guid and not (name and ns.Trim(ns.Units.Short(name) or ""):find(" ", 1, true)) then
        -- ns.Units.Call: C.Call passes on only five results, and the name is the sixth.
        local _, _, _, _, _, n = ns.Units.Call(GetPlayerInfoByGUID, guid)
        n = C.Str(n)
        if n and (not name or ns.Trim(ns.Units.Short(n) or ""):find(" ", 1, true)) then name = n end
    end
    -- The key the player is saved under, found by any shape of the name.
    return name and H:Key(name)
end

-- What you know of a player, or nil if you've never grouped with them (nor rated or noted them).
-- Returns { full, rating = 1 / -1 / nil, runs, finished, wipes, deaths, bosses, note, last, summary,
-- knownFor = { { id, label, givers } } (the kudos that reached you, most givers first) }.
function FiresideAPI.Get(name, guid)
    if not (ns.db and ns.db.players) then return nil end
    local full = Resolve(name, guid)
    local p = full and H:Get(full)
    if not p then return nil end
    local t = p.t
    local known = {}
    for _, e in ipairs(ns.Marks.KnownFor(full)) do
        known[#known + 1] = { id = e.id, label = ns.Marks.kudo[e.id].label, givers = e.weight }
    end
    return { full = full, rating = p.rating, runs = t.runs, finished = t.finished, wipes = t.wipes, deaths = t.deaths,
        bosses = t.bosses, note = p.note, last = p.last, summary = H:Summary(full, true), knownFor = known }
end

-- Opens the Fireside window on a player.
function FiresideAPI.Show(name, guid)
    if not ns.db then return end
    local full = Resolve(name, guid)
    ns.UI:ShowPlayer(full and (H:Get(full) and full or H:Find(full)))
end

-- Thumbs up (1) or down (-1); the same rating again clears it.
function FiresideAPI.SetRating(name, guid, rating)
    local full = ns.db and Resolve(name, guid)
    if full then H:SetRating(full, rating) end
end

-- Your note on a player; "" clears it.
function FiresideAPI.SetNote(name, guid, note)
    local full = ns.db and Resolve(name, guid)
    if full then H:SetNote(full, note or "") end
end
