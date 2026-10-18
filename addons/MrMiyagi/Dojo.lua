local _, ns = ...

-- Your record across fights: what keeps killing you, which kinds of mobs, and how you play the
-- fights you win against the ones you lose (interrupts against casters, defensives, healing).
local Dojo = {}
ns.Dojo = Dojo

local WEEK = 7 * 86400
local ORDINAL = { "first", "second", "third", "fourth", "fifth" }

-- A line for the coach window when a death repeats an old pattern.
function Dojo:PatternLine(d)
    local top = d.lessons and d.lessons[1]
    if not top then return nil end
    local n = 0
    for _, other in ipairs(ns.db.deaths) do
        if other ~= d and d.t - other.t < WEEK and other.lessons and other.lessons[1] and other.lessons[1].key == top.key then
            n = n + 1
        end
    end
    if n == 0 then return nil end
    local nth = ORDINAL[n + 1] or ((n + 1) .. "th")
    local line = ("This is the %s time this week: %s."):format(nth, top.title:lower())
    -- Compare with how you play the fights you win.
    if top.key == "casters" then
        local wins, kicks = 0, 0
        for _, f in ipairs(ns.db.fights) do
            if f.won and (f.casters or 0) > 0 then wins, kicks = wins + 1, kicks + (f.interrupts or 0) end
        end
        if wins >= 3 then line = line .. (" In the %d fights against casters you won, you interrupted %.1f times on average."):format(wins, kicks / wins) end
    elseif top.key == "burst" then
        local wins, def = 0, 0
        for _, f in ipairs(ns.db.fights) do
            if f.won and (f.maxDiff or 0) >= 1 then wins, def = wins + 1, def + (f.defensive or 0) end
        end
        if wins >= 3 then line = line .. (" In %d hard fights you won, you used a defensive %.1f times on average."):format(wins, def / wins) end
    end
    return line
end

-- Lines for the Patterns page.
function Dojo:Patterns()
    local lines = {}
    local function Add(s) lines[#lines + 1] = s end
    local deaths, fights = ns.db.deaths, ns.db.fights
    local won, lost = 0, 0
    for _, f in ipairs(fights) do if f.won then won = won + 1 else lost = lost + 1 end end
    Add(("|cffffd100Your record|r: %d fights won, %d lost (the last %d fights)."):format(won, lost, #fights))

    local byKey, titles = {}, {}
    for _, d in ipairs(deaths) do
        local top = d.lessons and d.lessons[1]
        if top then byKey[top.key] = (byKey[top.key] or 0) + 1; titles[top.key] = top.title end
    end
    local keys = {}
    for k, n in pairs(byKey) do keys[#keys + 1] = { k, n } end
    table.sort(keys, function(a, b) return a[2] > b[2] end)
    if #keys > 0 then
        Add(" ")
        Add("|cffffd100What gets you most|r")
        for i = 1, math.min(6, #keys) do Add(("  %s: %d death%s"):format(titles[keys[i][1]], keys[i][2], keys[i][2] == 1 and "" or "s")) end
    end

    -- Wins and losses by mob type.
    local types = {}
    for _, f in ipairs(fights) do
        for kind in (f.kinds or ""):gmatch("[^,]+") do
            types[kind] = types[kind] or { won = 0, lost = 0 }
            if f.won then types[kind].won = types[kind].won + 1 else types[kind].lost = types[kind].lost + 1 end
        end
    end
    local list = {}
    for kind, t in pairs(types) do list[#list + 1] = { kind, t } end
    table.sort(list, function(a, b) return a[2].lost / math.max(1, a[2].won + a[2].lost) > b[2].lost / math.max(1, b[2].won + b[2].lost) end)
    if #list > 0 then
        Add(" ")
        Add("|cffffd100By kind of mob|r")
        for _, e in ipairs(list) do
            local t = e[2]
            Add(("  %s: won %d, lost %d (%d%% wins)"):format(e[1], t.won, t.lost, t.won / math.max(1, t.won + t.lost) * 100))
        end
    end

    -- Habits: wins against losses.
    local function Avg(field, filter)
        local w, wn, l, ln = 0, 0, 0, 0
        for _, f in ipairs(fights) do
            if not filter or filter(f) then
                if f.won then w, wn = w + (f[field] or 0), wn + 1 else l, ln = l + (f[field] or 0), ln + 1 end
            end
        end
        return wn > 0 and w / wn or nil, ln > 0 and l / ln or nil
    end
    Add(" ")
    Add("|cffffd100Habits: fights you won against fights you lost|r")
    local wk, lk = Avg("interrupts", function(f) return (f.casters or 0) > 0 end)
    if wk or lk then Add(("  Interrupts against casters: %.1f when you win, %.1f when you lose"):format(wk or 0, lk or 0)) end
    local wd, ld = Avg("defensive", function(f) return (f.maxDiff or 0) >= 1 or (f.mobs or 0) >= 2 end)
    if wd or ld then Add(("  Defensives in hard fights: %.1f when you win, %.1f when you lose"):format(wd or 0, ld or 0)) end
    local wh, lh = Avg("heals")
    if wh or lh then Add(("  Self-heals per fight: %.1f when you win, %.1f when you lose"):format(wh or 0, lh or 0)) end
    local wm, lm = Avg("mobs")
    if wm or lm then Add(("  Mobs per fight: %.1f when you win, %.1f when you lose"):format(wm or 0, lm or 0)) end
    return lines
end
