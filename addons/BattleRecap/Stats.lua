local _, ns = ...

-- Lifetime numbers, kept beyond the 20 saved recaps: who kills you most (your nemeses), by class,
-- spell and school, how fast you die, and your duel record against each opponent. Each death is
-- added as its recap is saved (ns:AddRecap); made-up test recaps are left out.
local S = {}
ns.Stats = S

local function Empty()
    return {
        deaths = 0, byKind = {}, damage = 0, ttd = 0, env = 0, matches = 0, matchDeaths = 0,
        killers = {}, classes = {}, spells = {}, schools = {}, duels = {}, duelStreak = 0,
    }
end

local function DB() return BattleRecapDB.stats end

-- The key a killer is counted under: "Name-Realm" when the recap had it.
function S.Key(k) return k and (k.fullName or k.name) end

local function Short(name) return name and (name:match("^([^%-]+)") or name) end

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------

local function RecordDeath(db, recap)
    local k, T = recap.killer, recap.totals or {}
    db.deaths = db.deaths + 1
    db.byKind[recap.kind or "?"] = (db.byKind[recap.kind or "?"] or 0) + 1
    db.damage = db.damage + (T.damage or 0) + (recap.earlier and recap.earlier.damage or 0)
    db.ttd = db.ttd + (recap.duration or 0)

    if k and k.env then
        db.env = db.env + 1
    elseif k then
        local key = S.Key(k)
        local e = db.killers[key]
        if not e then
            e = { name = k.name, kills = 0, spells = {} }
            db.killers[key] = e
        end
        e.class = k.class or e.class
        e.pet = k.pet or nil
        e.kills = e.kills + 1
        e.last = recap.time
        if k.spell then e.spells[k.spell] = (e.spells[k.spell] or 0) + 1 end
        if k.class then db.classes[k.class] = (db.classes[k.class] or 0) + 1 end
        -- Saved on the recap, so it reads the same when you look back at it later.
        k.timesTotal = e.kills
        k.timesMatch = ns.Match and ns.Match:KillsBy(key) or nil
    end

    local seen = {}
    for _, s in ipairs(recap.spells or {}) do
        local e = db.spells[s.name]
        if not e then
            e = { name = s.name, id = s.id, damage = 0, deaths = 0, kills = 0 }
            db.spells[s.name] = e
        end
        e.damage = e.damage + (s.total or 0)
        if not seen[s.name] then e.deaths = e.deaths + 1; seen[s.name] = true end
    end
    if k and k.spell and db.spells[k.spell] then db.spells[k.spell].kills = db.spells[k.spell].kills + 1 end
    for _, s in ipairs(recap.schools or {}) do
        db.schools[s.school] = (db.schools[s.school] or 0) + (s.total or 0)
    end
end

-- A duel result, counted the moment the game announces it (even if its recap can't be read).
-- Returns the opponent's record.
function S:Duel(name, won)
    local db = DB()
    name = Short(name) or "?"
    local d = db.duels[name]
    if not d then
        d = { name = name, wins = 0, losses = 0, streak = 0 }
        db.duels[name] = d
    end
    if won then
        d.wins = d.wins + 1
        d.streak = d.streak > 0 and d.streak + 1 or 1
        db.duelStreak = db.duelStreak > 0 and db.duelStreak + 1 or 1
    else
        d.losses = d.losses + 1
        d.streak = d.streak < 0 and d.streak - 1 or -1
        db.duelStreak = db.duelStreak < 0 and db.duelStreak - 1 or -1
    end
    d.last = time()
    return d
end

-- Called for every recap as it's saved.
function S:Record(recap)
    if recap.test then return end
    local db = DB()
    if recap.kind == "duel" then
        local k = recap.killer
        local d = k and db.duels[Short(k.name) or ""]
        if d then
            d.class = k.class or d.class
            k.record = { wins = d.wins, losses = d.losses }
        end
        return
    end
    RecordDeath(db, recap)
end

-- A finished battleground or arena (Match.lua).
function S:RecordMatch(deaths)
    local db = DB()
    db.matches = db.matches + 1
    db.matchDeaths = db.matchDeaths + (deaths or 0)
end

-- Creates the store, or rebuilds it from the saved recaps when there's none yet.
function S:Init()
    if type(BattleRecapDB.stats) == "table" then
        local defaults = Empty()
        for key, value in pairs(defaults) do
            if BattleRecapDB.stats[key] == nil then BattleRecapDB.stats[key] = value end
        end
        return
    end
    BattleRecapDB.stats = Empty()
    local db = DB()
    local history = BattleRecapDB.history or {}
    for i = #history, 1, -1 do
        local recap = history[i]
        if not recap.test then
            if recap.kind == "duel" then
                if recap.killer then self:Duel(recap.killer.name, recap.won) end
            else
                RecordDeath(db, recap)
            end
        end
    end
end

function S:Reset()
    BattleRecapDB.stats = Empty()
end

---------------------------------------------------------------------------
-- Lists for the dashboard
---------------------------------------------------------------------------

local function Sorted(map, key)
    local list = {}
    for _, v in pairs(map) do list[#list + 1] = v end
    table.sort(list, function(a, b)
        if (a[key] or 0) ~= (b[key] or 0) then return (a[key] or 0) > (b[key] or 0) end
        return (a.name or "") < (b.name or "")
    end)
    return list
end

-- The spell a killer finished you with most often.
function S.FavouriteSpell(e)
    local best, count
    for spell, n in pairs(e.spells or {}) do
        if not count or n > count or (n == count and spell < best) then best, count = spell, n end
    end
    return best, count
end

function S:Killers() return Sorted(DB().killers, "kills") end
function S:Spells() return Sorted(DB().spells, "damage") end

function S:Duels()
    local list = {}
    for _, d in pairs(DB().duels) do
        d.total = d.wins + d.losses
        list[#list + 1] = d
    end
    table.sort(list, function(a, b)
        if a.total ~= b.total then return a.total > b.total end
        return (a.last or 0) > (b.last or 0)
    end)
    return list
end

function S:Classes()
    local list = {}
    for class, n in pairs(DB().classes) do list[#list + 1] = { class = class, kills = n } end
    table.sort(list, function(a, b)
        if a.kills ~= b.kills then return a.kills > b.kills end
        return a.class < b.class
    end)
    return list
end

function S:Schools()
    local list = {}
    for school, n in pairs(DB().schools) do list[#list + 1] = { school = school, total = n } end
    table.sort(list, function(a, b) return a.total > b.total end)
    return list
end

function S:Get() return DB() end
