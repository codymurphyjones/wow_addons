local _, ns = ...
local C = ns.Compat
local F = ns.Flight
local G = ns.Grid

-- The route planner: the quickest way to the target using everything you can travel by. It's a
-- shortest-path search (Dijkstra) over a small graph, run about once a second:
--   points   you, the target, the flight points you know (any continent), every dock and where
--            its ride lands, where your hearthstone takes you, where your mage teleports land
--   walk     from you, and to the target: along the land and water map (Grid.lua), around
--            lakes and cliffs, swimming where that's quicker; the walk is split into walk and
--            swim legs where it crosses water. Any other two points on one land: the straight
--            line, times DETOUR, at your travel speed
--   swim     between shores of different lands (an island and the mainland), at your swimming
--            speed: Aquatic Form's once you know it. The docks are the shores, as boats cross
--            where the water is narrowest
--   fly      known flight points on one continent: OVERHEAD + the flight (Flight.lua)
--   ride     a dock to where its boat, zeppelin or skyship lands: the time you took last times,
--            waiting included, else WAIT
--   hearth   you to your bind location: what's left of the cooldown + CAST + LOAD
--   teleport you to the city, for each mage teleport you know and can cast: CAST + LOAD
-- On your own continent a route is only used when it beats walking by ns.db.minGain seconds and
-- ns.db.minShare percent of the trip (as flights always were). Anywhere you can't walk to, the
-- quickest wins. Everything you can travel by can be switched off in the settings (Settings.lua).
--
-- It learns as you travel: how long each ride really took (from reaching the dock to arriving)
-- and where it landed when only the town was known, where your hearthstone takes you (when you
-- use it, or set it at an innkeeper), and where each teleport lands.
local R = {}
ns.Route = R

local CAST = 10               -- casting a hearthstone or teleport, in seconds
local LOAD = 15               -- the loading screen after it
local SWIM = 4.72             -- yards per second in the water
local SWIM_DETOUR = 1.05      -- a swim runs nearly straight
local AQUATIC = 1066          -- Aquatic Form (druid): swimming 50% faster
local AQUATIC_FORM = 4        -- its GetShapeshiftFormID()
local WAIT = { zeppelin = 240, skyship = 240, ship = 300 } -- a ride you haven't timed, waiting included
local MAX_RIDE = 12 * 60      -- a ride that takes longer than this wasn't one
local ARRIVE = 150            -- yards from where a ride lands that count as arrived
local ARRIVE_TOWN = 600       -- the same, when only its town is known
local function MinGain() return ns.db.minGain or 45 end
local function MinShare() return (ns.db.minShare or 15) / 100 end
local HEARTHSTONE = ns.Items.ITEMS.HEARTHSTONE -- the item (6948)
local HEARTH_SPELL = 8690     -- the spell it casts
local RUNE = 17031            -- Rune of Teleportation: what a mage teleport uses up (classic)
local FEATHER = 17056         -- Light Feather: what Slow Fall and Levitate use up
-- Spells that make a cliff safe to jump: { spell ID, name, reagent (item ID) or nil }. Walk on Air
-- (the Skyborne racial: glide down for 10 seconds) needs nothing but its 90-second cooldown, so
-- it's tried first.
local FALLS = { { 1259416, "Walk on Air" }, { 1308663, "Walk on Air" },
    { 130, "Slow Fall", 17056 }, { 1706, "Levitate", 17056 } }
local INF = math.huge

-- Zones you can't walk to from the rest of their continent.
local ISLAND = { [1438] = "Teldrassil", [1457] = "Teldrassil" }
local LABEL = { zeppelin = "Zeppelin", skyship = "Skyship", ship = "Ship" }

R.riding = nil -- { d = dock, since, left, expect }: on a boat, zeppelin or skyship

local function Dist(n1, w1, n2, w2)
    local dn, dw = n1 - n2, w1 - w2
    return math.sqrt(dn * dn + dw * dw)
end

-- Where you stand, as a map position.
local function Here()
    local map = C.Call(C_Map.GetBestMapForUnit, "player")
    local pos = map and C.Call(C_Map.GetPlayerMapPosition, map, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    if not x or (x == 0 and y == 0) then return nil end
    return map, x, y
end

-- A town by name, as a point. Later entries win, so a city's own map beats its zone's entrance.
local towns
local function Town(name)
    if not towns then
        towns = {}
        for _, t in ipairs(ns.Towns or {}) do
            towns[t[1]] = { mapID = t[2], x = t[3], y = t[4], label = t[1] }
        end
    end
    return name and towns[name]
end

-- Which island a point is on, or false for the mainland. Continent-wide maps (flight points
-- learned from the flight map) are looked up by the zone at that spot.
local function Island(p)
    if p._island ~= nil then return p._island end
    local mapID = p.mapID
    local island = ISLAND[mapID] or false
    if not island and mapID and Enum and Enum.UIMapType then
        local info = C.Call(C_Map.GetMapInfo, mapID)
        if info and info.mapType and info.mapType <= Enum.UIMapType.Continent then
            local sub = C.Call(C_Map.GetMapInfoAtPosition, mapID, p.x, p.y)
            island = sub and ISLAND[sub.mapID] or false
        end
    end
    p._island = island
    return island
end

local function MyFaction()
    local f = UnitFactionGroup and C.Readable(UnitFactionGroup("player"))
    return f == "Horde" and "H" or f == "Alliance" and "A" or nil
end

-- ---------------------------------------------------------------------------------------------
-- Docks
-- ---------------------------------------------------------------------------------------------

-- Every dock on this client: { t = transport, point, c, n, w }. ZeppelinSigns' moved and added
-- signs count too. Rebuilt every 10 seconds at most.
local docks, docksAt = nil, -INF

local function ZepDB()
    return type(ZeppelinSignsDB) == "table" and ZeppelinSignsDB or nil
end

function R:Docks()
    if docks and GetTime() - docksAt < 10 then return docks end
    docks, docksAt = {}, GetTime()
    local list = {}
    for _, t in ipairs(ns.Transports or {}) do list[#list + 1] = t end
    local zdb = ZepDB()
    for _, s in ipairs(zdb and type(zdb.custom) == "table" and zdb.custom or {}) do
        if type(s) == "table" and s.key and s.mapID and s.x and s.y and type(s.dest) == "string" then
            list[#list + 1] = { key = s.key, kind = s.kind == "zeppelin" and "zeppelin" or "ship", dest = s.dest, custom = s }
        end
    end
    for _, t in ipairs(list) do
        local moved = zdb and type(zdb.moved) == "table" and zdb.moved[t.key]
        local src = t.custom or (type(moved) == "table" and moved.mapID and moved)
        local point = src and { mapID = src.mapID, x = src.x, y = src.y }
            or { mapID = t.mapID, x = t.x / 100, y = t.y / 100 }
        point.label = ("%s to %s"):format(LABEL[t.kind] or "Ship", t.dest)
        local c, n, w = ns.Nav:World(point)
        if c then docks[#docks + 1] = { t = t, point = point, c = c, n = n, w = w } end
    end
    return docks
end

-- How long a ride takes, waiting included, and whether that's timed (true) or a guess.
function R:RideSecs(t)
    local rec = ns.db.rides[t.key]
    if rec and rec.secs then return rec.secs, true end
    return WAIT[t.kind] or 300, false
end

-- Where a dock's ride lands: where you landed last time (when only the town was known), else a
-- dock in the destination town (the one sailing back, if there is one), else the town. Second
-- value: true when that's only the town.
local landCache = {}
local function Landing(d)
    local t = d.t
    local rec = ns.db.rides[t.key]
    if rec and rec.m then
        local p = landCache[t.key]
        if not (p and p.mapID == rec.m and p.x == rec.x and p.y == rec.y) then
            p = { mapID = rec.m, x = rec.x, y = rec.y, label = t.dest }
            landCache[t.key] = p
        end
        return p, false
    end
    local back, any
    for _, o in ipairs(R:Docks()) do
        if o.t.place and o.t.place == t.dest then
            any = any or o
            if o.t.dest == t.place then back = o end
        end
    end
    local o = back or any
    if o then return o.point, false end
    local town = Town(t.town or t.dest)
    if town then return town, true end
end

-- ---------------------------------------------------------------------------------------------
-- Hearthstone and teleports
-- ---------------------------------------------------------------------------------------------

-- In combat this client hides your bags and cooldowns from addons (secret values), and you
-- couldn't use a hearthstone or teleport then anyway. So the plan doesn't change in combat: these
-- answer with what was read just before it, and the arrow says to wait (R:Action).
local seen = {}   -- [what] = the last answer read out of combat
local function InCombat()
    return InCombatLockdown and C.Readable(C.Call(InCombatLockdown)) and true or false
end
local function Held(key, read)
    if InCombat() and seen[key] ~= nil then return seen[key] end
    local value = read()
    seen[key] = value
    return value
end

local function ItemCount(id)
    return Held("count:" .. id, function() return ns.Items.ItemCount(id) end)
end

local function ItemCooldown(id)
    -- held as the time it's ready, so the wait still counts down in combat
    local ready = Held("ready:" .. id, function()
        local start, duration = ns.Items.ItemCooldown(id) -- 0, 0 when ready or unreadable
        if start == 0 then return 0 end
        return start + duration
    end)
    return math.max(0, ready - GetTime())
end

local HasRune -- below
local function SpellKnown(id)
    return Held("known:" .. id, function()
        if IsPlayerSpell and C.Readable(C.Call(IsPlayerSpell, id)) then return true end
        if IsSpellKnown and C.Readable(C.Call(IsSpellKnown, id)) then return true end
        return false
    end)
end

-- Castable now: known, with its reagent in your bags.
local function SpellUsable(id)
    return Held("usable:" .. id, function()
        local fn = (C_Spell and C_Spell.IsSpellUsable) or IsUsableSpell
        if not fn then return true end
        return C.Readable(C.Call(fn, id)) and true or false
    end)
end

local function SpellName(id)
    local name = C_Spell and C_Spell.GetSpellName and C.Call(C_Spell.GetSpellName, id)
    if not name and GetSpellInfo then name = C.Call(GetSpellInfo, id) end
    return C.Readable(name)
end

-- Whether you know Aquatic Form: by its spell ID, then by name among your shapeshift forms and in
-- your spellbook (in case this client numbers it differently).
local function KnowsAquatic()
    if SpellKnown(AQUATIC) then return true end
    local name = SpellName(AQUATIC) or "Aquatic Form"
    for i = 1, C.Num(C.Call(GetNumShapeshiftForms)) or 0 do
        for _, v in ipairs({ C.Call(GetShapeshiftFormInfo, i) }) do
            v = C.Readable(v)
            if v == name or v == AQUATIC or (type(v) == "number" and v > 1000 and SpellName(v) == name) then return true end
        end
    end
    local info = C_Spell and C_Spell.GetSpellInfo and C.Call(C_Spell.GetSpellInfo, name)
    if type(info) == "table" and info.spellID then return true end
    return GetSpellInfo and C.Readable(C.Call(GetSpellInfo, name)) ~= nil or false
end

local function InAquatic()
    return GetShapeshiftFormID and C.Num(C.Call(GetShapeshiftFormID)) == AQUATIC_FORM or false
end

-- Mage teleports use a Rune of Teleportation: one has to be in your bags.
HasRune = function()
    return ItemCount(RUNE) > 0
end

-- Whether a spell is off its cooldown (the global cooldown doesn't count).
local SpellReadyNow -- below
local function SpellReady(id)
    return Held("spellready:" .. id, function() return SpellReadyNow(id) end)
end
SpellReadyNow = function(id)
    local start, duration
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C.Call(C_Spell.GetSpellCooldown, id)
        if type(info) == "table" then start, duration = C.Num(info.startTime), C.Num(info.duration) end
    elseif GetSpellCooldown then
        local a, b = C.Call(GetSpellCooldown, id)
        start, duration = C.Num(a), C.Num(b)
    end
    return not (start and duration) or start == 0 or duration <= 1.5
end

-- A safe fall you can cast now: the spell (Walk on Air, Slow Fall, Levitate), its reagent in your
-- bags (a Light Feather) and off cooldown. Its name, or nil; and whether it's once only on the way
-- (no reagent, so it's its cooldown that counts: Walk on Air).
-- A ghost takes no fall damage: it can go down any cliff.
local function IsGhost()
    return C.Readable(C.Call(UnitIsGhost, "player")) and true or false
end

function R:SafeFall()
    if not ns.db.useSafeFall then return nil end
    for _, s in ipairs(FALLS) do
        if SpellKnown(s[1]) and (not s[3] or ItemCount(s[3]) > 0) and SpellReady(s[1]) then
            return SpellName(s[1]) or s[2], not s[3]
        end
    end
end

-- Your swimming speed, and whether that's Aquatic Form: the speed you swam in it last time, else
-- 50% over plain swimming. It's counted as soon as you know the form; Waypoint tells you when to
-- shift (R:FormTip).
-- With swimming turned off it's still the way when there's no other (getting there beats not
-- getting there): counted AVOID_SWIM times slower, so any reasonable way round wins.
local AVOID_SWIM = 6
function R:SwimSpeed()
    if not ns.db.allowSwim then return SWIM / AVOID_SWIM, false end
    if ns.db.useAquatic and KnowsAquatic() then return ns.char.taxi.aquatic or SWIM * 1.5, true end
    return SWIM, false
end

-- The highest drop you'll jump without a safe fall: how much fall damage you'll take (the
-- maxFallPct setting) as yards.
function R:MaxDrop()
    return G and G.FallHeight((ns.db.maxFallPct or 0) / 100) or 0
end

-- Your maximum health, when the game says.
local function MaxHealth()
    return C.Num(C.Call(UnitHealthMax, "player"))
end

-- "about 35% of your health (1,200 HP)" for a fall of that many yards.
function R:FallText(yards)
    local share = G and G.FallDamage(yards) or 0
    local hp = MaxHealth()
    local amount = hp and (" (%s HP)"):format(ns.Format.Thousands(share * hp)) or ""
    return ("about %d%% of your health%s"):format(math.floor(share * 100 + 0.5), amount)
end

-- "Switch to Aquatic Form" when a swim leg counts on it and you're not in it yet, else nil.
function R:FormTip(leg)
    if leg and leg.kind == "swim" and leg.aquatic and not InAquatic() and ns.db.useAquatic then
        return "Switch to " .. (SpellName(AQUATIC) or "Aquatic Form")
    end
end

local function Bind()
    local bind = C.Readable(C.Call(GetBindLocation))
    if type(bind) == "string" and bind ~= "" then return bind end
end

-- Where your hearthstone takes you: where it took you last time, or where you set it, else the
-- town of that name.
local hearthPoint
local function HearthPoint()
    local bind = Bind()
    if not bind then return nil end
    local h = ns.char.hearth
    if h.bind == bind and h.m then
        if not (hearthPoint and hearthPoint.mapID == h.m and hearthPoint.x == h.x and hearthPoint.y == h.y) then
            hearthPoint = { mapID = h.m, x = h.x, y = h.y, label = bind }
        end
        return hearthPoint, bind
    end
    return Town(bind), bind
end

local portPoints = {}
local function TeleportPoint(id, city)
    local rec = ns.db.teleports[id]
    if rec and rec.m then
        local p = portPoints[id]
        if not (p and p.mapID == rec.m and p.x == rec.x and p.y == rec.y) then
            p = { mapID = rec.m, x = rec.x, y = rec.y, label = city }
            portPoints[id] = p
        end
        return p
    end
    return Town(city)
end

-- ---------------------------------------------------------------------------------------------
-- Planning
-- ---------------------------------------------------------------------------------------------

-- A point of the graph, or nil when the map can't place it.
local function Vertex(point, kind)
    if not point then return nil end
    local c, n, w = ns.Nav:World(point)
    if not c then return nil end
    return { point = point, c = c, n = n, w = w, land = Island(point), kind = kind }
end

-- What a leg is called in chat.
local function LegText(leg)
    if leg.kind == "fly" then return ("fly %s to %s"):format(leg.from.node.name, leg.to.node.name) end
    if leg.kind == "ride" then
        local t = leg.from.dock.t
        return ("%s to %s"):format((LABEL[t.kind] or "Ship"):lower(), t.dest)
    end
    if leg.kind == "hearth" then return "hearth to " .. leg.to.name end
    if leg.kind == "teleport" then return "teleport to " .. leg.to.name end
    if leg.kind == "swim" then return "swim to " .. (leg.to.name or "the far shore") .. (leg.aquatic and " in Aquatic Form" or "") end
    if leg.kind == "drop" then
        if leg.fall then return "jump down with " .. leg.fall end
        return ("jump down %d yd (%s)"):format(leg.height or 0, R:FallText(leg.height or 0))
    end
    return "walk"
end

-- The ways a trip travels, as a key: each flight, ride, hearthstone and teleport, and whether it
-- swims, jumps with a safe fall (which one) or jumps taking damage. How many jumps or swims, and
-- exactly where, don't count.
local announced -- { target = the task (Plan's taskKey, and the waypoint), ways }: what was last said in chat
local function Ways(legs)
    local seen, keys = {}, {}
    for _, leg in ipairs(legs) do
        local key
        if leg.kind == "drop" then
            key = "jump:" .. (leg.fall or "hurt")
        elseif leg.kind == "swim" then
            key = "swim"
        elseif leg.kind ~= "walk" then
            key = LegText(leg)
        end
        if key and not seen[key] then
            seen[key] = true
            keys[#keys + 1] = key
        end
    end
    return table.concat(keys, "|")
end

-- Same route as before: the same legs, apart from walking.
local function Signature(legs)
    local parts = {}
    for _, leg in ipairs(legs) do
        if leg.kind ~= "walk" then parts[#parts + 1] = LegText(leg) end
    end
    return table.concat(parts, "|")
end

-- Walking and swimming along the land and water map (Grid.lua): a leg's squares, in order, split
-- into walks, swims and jumps. steps: { n, w, water, h = height, e = seconds from the leg's start }.
-- Water shorter than SWIM_MIN squares (a stream, a ford) stays part of the walk. A step down a
-- cliff you'd take damage from (the map's links, Grid.lua) is a jump: with your safe fall (fall:
-- its name) when you have one, else taking the damage (up to your setting's limit).
local SWIM_MIN = 3
local HasJump -- below

-- Whether the walk from your field's source to a point jumps down a cliff you'd take damage from.
HasJump = function(field, to)
    local path = G:Path(field, to.n, to.w)
    if not path then return false end
    local fall = 0
    for i = #path, 2, -1 do
        local a, b = path[i], path[i - 1]
        local how, down = G:Step(field.continent, a.n, a.w, b.n, b.w)
        if how == "drop" then
            fall = (a.face and fall or 0) + down
            if fall > G.HARMLESS then return true end
        else
            fall = 0
        end
    end
    return false
end

local function Split(leg, steps, total, fall)
    local runs = {}
    for i, s in ipairs(steps) do
        local what, down = s.water and "swim" or "walk", 0
        if i > 1 and not s.water then
            local how, d = G:Step(leg.from.c, steps[i - 1].n, steps[i - 1].w, s.n, s.w)
            if how == "drop" then what, down = "drop", d end
        end
        local run = runs[#runs]
        -- Drops in a row are one fall while you land on cliff face; landing on ground, the next
        -- drop is a new jump.
        local same = run and run.what == what and (what ~= "drop" or steps[i - 1].face)
        if same then
            run.last = i
            run.down = run.down + down
        else
            runs[#runs + 1] = { what = what, first = i, last = i, down = down }
        end
    end
    for _, run in ipairs(runs) do
        if run.what == "swim" and run.last - run.first + 1 < SWIM_MIN then run.what = "walk" end
        -- Drops in a row are one fall: only one you'd take damage from is a jump.
        if run.what == "drop" and run.down <= G.HARMLESS then run.what = "walk" end
    end
    local merged = {}
    for _, run in ipairs(runs) do
        local prev = merged[#merged]
        -- Jumps in a row are one cast of your safe fall; without one, each is a fall of its own.
        if prev and prev.what == run.what and (run.what ~= "drop" or fall) then
            prev.last = run.last
            prev.down = (prev.down or 0) + (run.down or 0)
        else
            merged[#merged + 1] = run
        end
    end
    if #merged == 1 and merged[1].what == "walk" then return { leg } end
    local out, from, e0 = {}, leg.from, 0
    for k, run in ipairs(merged) do
        local to, e
        if k == #merged then
            to, e = leg.to, total
        elseif run.what ~= "drop" and merged[k + 1].what == "drop" then
            -- A walk or swim up to a jump ends at the cliff's edge: the last square before it.
            local s = steps[merged[k + 1].first - 1]
            to = { c = leg.from.c, n = s.n, w = s.w, kind = "edge",
                point = { _c = leg.from.c, _n = s.n, _w = s.w, _island = false, label = "the cliff edge" } }
            e = s.e
        else
            local s = steps[merged[k + 1].first] -- the next run's first square: the shore, the cliff's foot
            to = { c = leg.from.c, n = s.n, w = s.w, kind = "shore",
                point = { _c = leg.from.c, _n = s.n, _w = s.w, _island = false,
                    label = run.what == "swim" and "the far shore" or run.what == "drop" and "the bottom" or "the shore" } }
            e = s.e
        end
        local drop = run.what == "drop"
        out[#out + 1] = { kind = run.what, from = from, to = to, secs = e - e0,
            aquatic = run.what == "swim" and leg.aquatic, fall = drop and fall or nil, height = drop and run.down or nil }
        from, e0 = to, e
    end
    -- A jump starts at the cliff's edge, where the walk before it ended.
    for i = 2, #out do
        if out[i].kind == "drop" and out[i - 1].kind ~= "drop" then out[i].from = out[i - 1].to end
    end
    return out
end

-- ---------------------------------------------------------------------------------------------
-- City streets: the land map's squares (66 yards) are coarser than a city's streets, and it doesn't
-- see the buildings between them: all of Orgrimmar is a few squares across, and the roads touch
-- nearly every one, so a way across the huts looks like a road. In the major cities a walk follows
-- the roads themselves instead (RoadLog's, and Waypoint's own from Data\Roads.lua): a network of
-- their points (every STREET_STEP yards; roads this close to another meet there, STREET_JOIN), and
-- each stretch of a way inside a city is replaced by the way along the streets between where it
-- starts and ends: onto the streets near its start, off them near its end.
-- ---------------------------------------------------------------------------------------------

local AllRoads                   -- below (Learning the ground)
local cityRects = {}             -- continent -> { { nmin, nmax, wmin, wmax } } (R:MarkCities)
local streets = {}               -- continent -> the street network, false when there's none
local STREET_STEP = 10           -- yards between the network's points along a road
local STREET_JOIN = 9            -- roads this close meet
local STREET_MARGIN = 100        -- yards past a city's map the streets still count (its gates)
local STREET_ENTER = 120         -- the farthest you'd walk to get onto a street (or off it, to where you go)
local STREET_OFF = 1.5           -- walking to or from the street weighs this much more than along it
local STREET_ON = 12             -- yards from a street that count as on it
local STREET_LEFT = 25           -- yards from every street that count as having left them

local function InCity(c, n, w, margin)
    margin = margin or 0
    for _, r in ipairs(cityRects[c] or {}) do
        if n >= r[1] - margin and n <= r[2] + margin and w >= r[3] - margin and w <= r[4] + margin then return true end
    end
    return false
end

-- The street network of a continent's cities: { n = {}, w = {}, adj = { [i] = { [j] = yards } } }, or nil.
local function Streets(c)
    local g = streets[c]
    if g ~= nil then return g or nil end
    if not (cityRects[c] and AllRoads) then streets[c] = false return nil end
    g = { n = {}, w = {}, adj = {}, road = {}, cells = {} }
    local function Cell(n, w) return math.floor(n / STREET_JOIN) .. ":" .. math.floor(w / STREET_JOIN) end
    local function Node(n, w, road)
        local i = #g.n + 1
        g.n[i], g.w[i], g.adj[i], g.road[i] = n, w, {}, road
        local key = Cell(n, w)
        g.cells[key] = g.cells[key] or {}
        table.insert(g.cells[key], i)
        return i
    end
    local function Link(a, b)
        local d = Dist(g.n[a], g.w[a], g.n[b], g.w[b])
        g.adj[a][b], g.adj[b][a] = d, d
    end
    -- Each road, a point every STREET_STEP yards, while it's in a city.
    for road, pts in ipairs(AllRoads()[c] or {}) do
        local ln, lw, prev
        for i = 1, #pts - 1, 2 do
            local n, w = pts[i], pts[i + 1]
            local parts = ln and math.max(1, math.ceil(Dist(ln, lw, n, w) / STREET_STEP)) or 1
            for k = 1, parts do
                local an, aw = n, w
                if ln then an, aw = ln + (n - ln) * k / parts, lw + (w - lw) * k / parts end
                if InCity(c, an, aw, STREET_MARGIN) then
                    local j = Node(an, aw, road)
                    if prev then Link(prev, j) end
                    prev = j
                else
                    prev = nil
                end
            end
            ln, lw = n, w
        end
    end
    -- Where roads meet: points of two roads this close (or of one road that comes back on itself).
    for i = 1, #g.n do
        local cn, cw = math.floor(g.n[i] / STREET_JOIN), math.floor(g.w[i] / STREET_JOIN)
        for dn = -1, 1 do
            for dw = -1, 1 do
                for _, j in ipairs(g.cells[(cn + dn) .. ":" .. (cw + dw)] or {}) do
                    if j > i and not g.adj[i][j] and (g.road[i] ~= g.road[j] or j - i > 3)
                        and Dist(g.n[i], g.w[i], g.n[j], g.w[j]) <= STREET_JOIN then
                        Link(i, j)
                    end
                end
            end
        end
    end
    g.cells = nil
    if #g.n == 0 then streets[c] = false return nil end
    streets[c] = g
    return g
end

-- The way along the streets from (an, aw) to (bn, bw): { { n, w, via = true, street = true } },
-- or nil when there's no street near either end or they don't connect. Onto the streets and off
-- them where the whole way weighs least (the walk to and from them weighing STREET_OFF more).
local function StreetWay(c, an, aw, bn, bw)
    local g = Streets(c)
    if not g then return nil end
    local dist, from, done = {}, {}, {}
    local hk, hv, size = {}, {}, 0
    local function Push(d, i)
        size = size + 1
        local k = size
        while k > 1 do
            local p = math.floor(k / 2)
            if hk[p] <= d then break end
            hk[k], hv[k] = hk[p], hv[p]
            k = p
        end
        hk[k], hv[k] = d, i
    end
    local function Pop()
        local d, i = hk[1], hv[1]
        local lk, lv = hk[size], hv[size]
        hk[size], hv[size] = nil, nil
        size = size - 1
        if size > 0 then
            local k = 1
            while true do
                local l = k * 2
                if l > size then break end
                local r = l + 1
                local child = (r <= size and hk[r] < hk[l]) and r or l
                if hk[child] >= lk then break end
                hk[k], hv[k] = hk[child], hv[child]
                k = child
            end
            hk[k], hv[k] = lk, lv
        end
        return d, i
    end
    for i = 1, #g.n do
        local d = Dist(an, aw, g.n[i], g.w[i])
        if d <= STREET_ENTER then
            dist[i] = d * STREET_OFF
            Push(dist[i], i)
        end
    end
    if size == 0 then return nil end
    local best, bestAt
    while size > 0 do
        local d, i = Pop()
        if best and d >= best then break end
        if not done[i] then
            done[i] = true
            local off = Dist(g.n[i], g.w[i], bn, bw)
            if off <= STREET_ENTER and (not best or d + off * STREET_OFF < best) then best, bestAt = d + off * STREET_OFF, i end
            for j, yards in pairs(g.adj[i]) do
                local nd = d + yards
                if not done[j] and (not dist[j] or nd < dist[j]) then
                    dist[j], from[j] = nd, i
                    Push(nd, j)
                end
            end
        end
    end
    if not bestAt then return nil end
    local out, i = {}, bestAt
    while i do
        table.insert(out, 1, { n = g.n[i], w = g.w[i], via = true, street = true, water = false, face = false })
        i = from[i]
    end
    return out
end

-- How far the nearest street is (yards), or nil when there are none.
local function NearestStreet(c, n, w)
    local g = Streets(c)
    if not g then return nil end
    local best
    for i = 1, #g.n do
        local d = (g.n[i] - n) ^ 2 + (g.w[i] - w) ^ 2
        if not best or d < best then best = d end
    end
    return best and math.sqrt(best)
end

-- Stepping off the streets is yours to do: once you've walked off them (from on one to more than
-- STREET_LEFT yards from all of them), your own stretch isn't pulled back onto them for the rest of
-- the way to that target; back on a street (or another target), they lead again.
local street = { key = nil, on = false, free = false }
local function StreetState(c, n, w, p)
    local key = p and (tostring(p.mapID) .. ":" .. tostring(p.x) .. ":" .. tostring(p.y)) or nil
    if key ~= street.key then street.key, street.on, street.free = key, false, false end
    local d = cityRects[c] and InCity(c, n, w, STREET_MARGIN) and NearestStreet(c, n, w)
    if d and d <= STREET_ON then
        street.on, street.free = true, false
    elseif street.on and (not d or d > STREET_LEFT) then
        street.free = true
    end
end

-- A way (squares in walking order, between a start and an end) with each stretch of it inside a
-- city along the streets instead: the squares in between, as a new list (start and end not in it).
-- fromYou: the way starts where you stand (then a stretch you've walked off the streets stays yours).
local function CityWay(c, sn, sw, way, en, ew, fromYou)
    if not (way and cityRects[c]) then return way end
    local seq = { { n = sn, w = sw } }
    for _, s in ipairs(way) do seq[#seq + 1] = s end
    seq[#seq + 1] = { n = en, w = ew }
    local out, i, changed = {}, 1, false
    while i <= #seq do
        if InCity(c, seq[i].n, seq[i].w) then
            local j = i
            while j < #seq and InCity(c, seq[j + 1].n, seq[j + 1].w) do j = j + 1 end
            local road = j > i and not (i == 1 and fromYou and street.free) and StreetWay(c, seq[i].n, seq[i].w, seq[j].n, seq[j].w)
            if road then
                out[#out + 1] = seq[i]
                for _, s in ipairs(road) do out[#out + 1] = s end
                out[#out + 1] = seq[j]
                changed = true
            else
                for k = i, j do out[#out + 1] = seq[k] end
            end
            i = j + 1
        else
            out[#out + 1] = seq[i]
            i = i + 1
        end
    end
    if not changed then return way end
    table.remove(out, 1)
    table.remove(out)
    return out
end

-- The way from where you stand toward aim, as squares in order ({ n, w, ... }), or nil. To the
-- target it follows the field to the target, which leads there from any square, so it starts
-- right where you are. To another stop (a flight master, a dock) it follows your own field, from
-- its square nearest you: that field was worked out where you stood a little while ago.
local function WayFrom(hereField, targetField, toTarget, c, n, w, aim)
    local ac, an, aw = ns.Nav:World(aim)
    if toTarget and targetField and targetField.continent == c then
        local way = G:Detail(c, G:Path(targetField, n, w))
        return ac == c and CityWay(c, n, w, way, an, aw, true) or way
    end
    if not (hereField and hereField.continent == c) then return nil end
    if ac ~= c then return nil end
    local path = G:Path(hereField, an, aw) -- from aim back to where the field started
    if not path then return nil end
    local nearest, best
    for i, s in ipairs(path) do
        local d = (s.n - n) ^ 2 + (s.w - w) ^ 2
        if not best or d < best then nearest, best = i, d end
    end
    local out = {}
    for i = nearest, 1, -1 do out[#out + 1] = path[i] end
    return CityWay(c, n, w, G:Detail(c, out), an, aw, true)
end

-- The point to steer at on the way: the farthest square along it that you can see in a straight
-- line over land (or water, while swimming); nil when the straight line to aim is fine. A turn of
-- a zigzag or a way round (a via, G:Detail) is never looked past: the straight line beyond it
-- goes up the slope. A turn of the step you're on is behind you once you've been within REACHED
-- yards of it (or of a later one), and stays so while it's on the way.
local REACHED = 10
local reached = {} -- "north:west" of the turns you've reached
local function Steer(way, c, n, w, aim)
    if not (way and way[2] and aim) then return nil end
    local ac, an, aw = ns.Nav:World(aim)
    -- Along a city's streets the straight line is no good: the land map doesn't see the buildings.
    local onStreets = false
    for i = 1, math.min(#way, 150) do if way[i].street then onStreets = true break end end
    if ac == c and not onStreets and G:Clear(c, n, w, an, aw) then return nil end
    local start, still = 1, {}
    for i = 2, #way do
        local s = way[i]
        if not s.via then break end
        local key = math.floor(s.n) .. ":" .. math.floor(s.w)
        if reached[key] or (s.n - n) ^ 2 + (s.w - w) ^ 2 <= REACHED * REACHED then
            still[key] = true
            start = i + 1
        end
    end
    reached = still
    local best
    for i = start, math.min(#way, 150) do
        local s = way[i]
        if s.via then
            best = best or s
            break
        end
        if G:Clear(c, n, w, s.n, s.w) then best = s elseif i > start then break end
    end
    if not best or best == way[1] then best = way[math.max(start, 2)] or way[2] end
    return { _c = c, _n = best.n, _w = best.w, _island = false, label = "the way" }
end

-- The way Waypoint plans to walk from where you are: { continent, squares }.
function R:Way() return self.way end

-- The whole planned trip as lines, for the world map and the minimap (WayLine.lua):
-- { { kind = "walk" | "swim" | "drop" | "fly" | "ride", continent, pts = { n1, w1, n2, w2, ... } } }.
function R:Lines() return self.lines end

-- A field's path between two world points, in walking order, when the field covers both: from
-- your field (its source near where the leg starts), or the target's (it ends at the target).
-- nil when neither does: then the leg is drawn straight.
local function FieldPath(hereField, targetField, leg, toTarget)
    local f, n1, w1, n2, w2 = nil, leg.from.n, leg.from.w, leg.to.n, leg.to.w
    if toTarget and targetField and targetField.continent == leg.from.c then
        local path = G:Path(targetField, n1, w1) -- from the leg's start to the target
        return path
    end
    f = hereField
    if not (f and f.continent == leg.from.c) then return nil end
    local path = G:Path(f, n2, w2) -- from the leg's end back to where the field started
    if not path then return nil end
    local nearest, best
    for i, sq in ipairs(path) do
        local d = (sq.n - n1) ^ 2 + (sq.w - w1) ^ 2
        if not best or d < best then nearest, best = i, d end
    end
    if best > ((G.MOVE + 1) * 66.7) ^ 2 then return nil end -- the field doesn't run past the leg's start
    local out = {}
    for i = nearest, 1, -1 do out[#out + 1] = path[i] end
    return out
end

-- A waypoint's shade (1-10): from its number in your path, so it keeps its colour as you go.
local function ShadeOf(pt)
    local num = type(pt.id) == "string" and tonumber(pt.id:match("#(%d+)$")) or 0
    return num % 10 + 1
end

-- The legs of your waypoint path after the one you're on: from each waypoint to the next (up to
-- STAGES), along the land map (a field per leg, worked out in the background) and straight until
-- that's ready. Each in its waypoint's shade.
local STAGES = 5
local function StageLines(lines, current, opts)
    local chain = ns.Chain and ns.Chain:Points() or {}
    local start
    for i, q in ipairs(chain) do
        if q.id == current.id then start = i break end
    end
    if not start then return end
    local prev = current
    for i = start + 1, math.min(#chain, start + STAGES) do
        local q = chain[i]
        local pc, pn, pw = ns.Nav:World(prev)
        local qc, qn, qw = ns.Nav:World(q)
        if pc and pc == qc then
            local shade = ShadeOf(q)
            local f = opts and G:Field("stage" .. (i - start), qc, qn, qw, opts)
            local path = f and G:Detail(qc, G:Path(f, pn, pw))
            if path then
                local kind, pts = nil, { pn, pw }
                for _, sq in ipairs(path) do
                    local k = sq.water and "swim" or "walk"
                    if kind and k ~= kind then
                        pts[#pts + 1], pts[#pts + 2] = sq.n, sq.w
                        lines[#lines + 1] = { kind = kind, continent = qc, pts = pts, shade = shade }
                        pts = { sq.n, sq.w }
                    end
                    kind = k
                    pts[#pts + 1], pts[#pts + 2] = sq.n, sq.w
                end
                pts[#pts + 1], pts[#pts + 2] = qn, qw
                lines[#lines + 1] = { kind = kind or "walk", continent = qc, pts = pts, shade = shade }
            else
                lines[#lines + 1] = { kind = "walk", continent = qc, pts = { pn, pw, qn, qw }, shade = shade }
            end
        end
        prev = q
    end
end

-- The trip's lines: each leg along the land map where a field covers it, else straight.
local function BuildLines(route, way, hereField, targetField, target, c, n, w)
    local lines = {}
    local function Add(kind, continent, pts)
        if #pts >= 4 then lines[#lines + 1] = { kind = kind, continent = continent, pts = pts } end
    end
    if not route then
        -- Walking all the way: the way from where you are, split where it swims.
        if not way then return nil end
        local kind, pts = nil, { n, w }
        for _, sq in ipairs(way.squares) do
            local k = sq.water and "swim" or "walk"
            if kind and k ~= kind then
                pts[#pts + 1], pts[#pts + 2] = sq.n, sq.w
                Add(kind, c, pts)
                pts = { sq.n, sq.w }
            end
            kind = k
            pts[#pts + 1], pts[#pts + 2] = sq.n, sq.w
        end
        Add(kind or "walk", c, pts)
        return lines
    end
    for i, leg in ipairs(route.legs) do
        local a, b = leg.from, leg.to
        if leg.kind == "fly" or leg.kind == "ride" then
            if a.c == b.c then Add(leg.kind, a.c, { a.n, a.w, b.n, b.w }) end
        elseif leg.kind == "walk" or leg.kind == "swim" or leg.kind == "drop" then
            local pts = {}
            if i == 1 then pts[1], pts[2] = n, w end
            local path = a.c == b.c and G:Detail(a.c, FieldPath(hereField, targetField, leg, b == target) or nil)
            if path then path = CityWay(a.c, i == 1 and n or a.n, i == 1 and w or a.w, path, b.n, b.w, i == 1) end
            if path then
                for _, sq in ipairs(path) do pts[#pts + 1], pts[#pts + 2] = sq.n, sq.w end
                pts[#pts + 1], pts[#pts + 2] = b.n, b.w
            elseif a.c == b.c then
                if i ~= 1 then pts[1], pts[2] = a.n, a.w end
                pts[#pts + 1], pts[#pts + 2] = b.n, b.w
            end
            Add(leg.kind, a.c, pts)
        end
    end
    return lines
end

-- How far above or below you point p is, by the land map: "  -  60 yd above you", or "" when
-- it's about level (or the map can't tell).
local LEVEL = 15
function R:HeightText(p)
    if not (G and p and ns.db.showHeight) then return "" end
    local c, n, w = ns.Nav:Player()
    local pc, pn, pw = ns.Nav:World(p)
    if not c or pc ~= c then return "" end
    local mine, theirs = G:Height(c, n, w), G:Height(c, pn, pw)
    if not (mine and theirs) or math.abs(theirs - mine) < LEVEL then return "" end
    return ("  -  %d yd %s you"):format(math.floor(math.abs(theirs - mine) / 5 + 0.5) * 5, theirs > mine and "above" or "below")
end

-- What's in front of you, by the land map: the steps from your square onward the way you face.
-- A cliff spread over several squares is one fall: the drops in a row are added up.
-- "Cliff ahead: 85 yd down (lethal)", "Too steep to climb ahead", or nil.
local AHEAD = { 45, 100, 160, 220, 280 } -- yards ahead to look
function R:AheadText()
    if not (G and ns.db.useGrid and ns.db.showHeight) then return nil end
    if IsGhost() then return nil end -- no fall damage: a cliff is the quick way down
    local c, n, w = ns.Nav:Player()
    local facing = GetPlayerFacing and C.Num(C.Call(GetPlayerFacing))
    if not (c and facing) then return nil end
    -- GetPlayerFacing: 0 is north, turning anticlockwise (toward west).
    local dn, dw = math.cos(facing), math.sin(facing)
    local pn, pw = n, w
    local total = 0
    local function Cliff()
        local fall = self:SafeFall()
        local share = G.FallDamage(total)
        local cost = fall and (fall .. " ready")
            or share >= 1 and "|cffff4040lethal|r"
            or ("about %d%% health"):format(math.floor(share * 100 + 0.5))
        return ("|cffffa040Cliff ahead|r: %d yd down (%s)"):format(total, cost)
    end
    for _, yards in ipairs(AHEAD) do
        local an, aw = n + dn * yards, w + dw * yards
        local how, down = G:Step(c, pn, pw, an, aw)
        if how == "drop" then
            total = total + down
        elseif total > G.HARMLESS then
            return Cliff() -- the bottom of the cliff
        elseif total > 0 and how == "walk" then
            total = 0 -- a small step down, and level again
        end
        if how == nil then
            if total > G.HARMLESS then return Cliff() end
            if total > 0 then return nil end
            local mine, theirs = G:Height(c, pn, pw), G:Height(c, an, aw)
            if mine and theirs and theirs > mine + 5 then return "|cffffa040Too steep to climb ahead|r" end
            if mine and theirs and theirs < mine - 5 then return "|cffffa040Cliff ahead|r" end
            return nil
        end
        pn, pw = an, aw
    end
    if total > G.HARMLESS then return Cliff() end
end

-- The arrow's terrain line: what's ahead, and how far up or down where it leads is. nil: nothing to say.
function R:TerrainText(p)
    local ahead = self:AheadText()
    local height = self:HeightText(p):gsub("^  %-  ", "")
    if height ~= "" then height = (height:gsub("^(%d)", "Target %1")) end
    if ahead and height ~= "" then return ahead .. "  -  " .. height end
    if ahead then return ahead end
    if height ~= "" then return height end
end

-- Where to point the arrow on the way to point p: around lakes and cliffs (nil: straight at it).
function R:SteerPoint(p)
    if not ns.db.steer then return nil end
    local s = self.steer
    if s and s.aim == p then return s.point end
end

-- A different plan has to beat the one you're on by this much (seconds, and share of the trip),
-- so the strategy doesn't flip between two that cost about the same as you move.
local KEEP_SECS, KEEP_SHARE = 60, 0.15
local COMMITTED = { fly = true, ride = true, hearth = true, teleport = true }
-- Yards from where a flight or ride starts beyond which it's been taken (or given up): the plan
-- made with it no longer stands.
local LEFT_STOP = 200

-- What the route planned before would take from where you are now: the way to where its next step
-- starts, that step, and the rest as planned. nil when it no longer applies (another target, or
-- its next step is only walking).
local function StillTakes(last, p, hereField, c, n, w, speed)
    local q = last and last.p
    local same = q and (q == p or (q.mapID == p.mapID and q.x == p.x and q.y == p.y))
    local nx = same and last.next
    if not (nx and COMMITTED[nx.kind]) then return nil end
    local at
    for i, leg in ipairs(last.legs) do
        if leg == nx then at = i break end
    end
    if not at then return nil end
    local secs
    if nx.kind == "hearth" then
        if ItemCount(HEARTHSTONE) == 0 then return nil end
        secs = ItemCooldown(HEARTHSTONE) + CAST + LOAD
    elseif nx.kind == "teleport" then
        secs = CAST + LOAD
    else
        local from = nx.from
        if from.c ~= c then return nil end
        local walk = hereField and G:Cost(hereField, from.n, from.w) or Dist(n, w, from.n, from.w) * F.DETOUR / speed
        if not walk then return nil end
        secs = walk + nx.secs
    end
    for i = at + 1, #last.legs do secs = secs + last.legs[i].secs end
    return secs
end

-- The quickest route to point p when it beats walking there (or you can't walk there), else nil.
-- last: the route planned before, so a route in use isn't dropped at the edge.
-- The planned route's shade (1-10, WayLine.lua): it moves on to the next with each new task the
-- arrow follows (a quest objective, a guide step, an addon's target); stepping through your own
-- waypoint path keeps it.
R.shade = 1
local taskKey

-- Whether two targets are the same point.
local function Same(a, b)
    return a and b and (a == b or (a.mapID == b.mapID and a.x == b.x and a.y == b.y)) or false
end

-- Returns the route (or nil), and true when the land and water map is still being worked out for
-- it: then the plan made before for this target stands as it was (its route, its lines on the
-- map, where the arrow steers), or for a new target nothing is drawn yet, rather than a guess.
-- Grid reports when it's ready, and the plan is made again then (Flight.lua).
function R:Plan(p, last)
    local kept = { lines = self.lines, steer = self.steer, way = self.way, p = self.plannedFor }
    self.steer, self.lines, self.plannedFor = nil, nil, nil
    local e = ns.Targets and ns.Targets.current
    local key = e and (e.owner == "path" and "path" or (tostring(e.owner) .. ":" .. tostring(e.key or e.title or "")))
    if key and key ~= taskKey then
        if taskKey then self.shade = self.shade % 10 + 1 end
        taskKey = key
    end
    if self.riding or not p then return nil end
    local c, n, w = ns.Nav:Player()
    if not c then return nil end
    local target = Vertex(p, "target")
    if not target then return nil end
    StreetState(c, n, w, p)
    local zone = C.Call(C_Map.GetBestMapForUnit, "player")
    local here = { c = c, n = n, w = w, land = zone and Island({ mapID = zone }) or false, kind = "you",
        shore = C.Readable(C.Call(IsSwimming)) and true or false } -- already in the water: swim from here
    local speed = F:Speed()
    local swim, aquatic = self:SwimSpeed()
    -- Times over the land and water map from you, and to the target (nil until worked out).
    local ghost = IsGhost()
    -- A ghost takes no fall damage; Walk on Air is once only on the way (its cooldown).
    local fall, once = true, false
    if not ghost then fall, once = self:SafeFall() end
    local grid = G and ns.db.useGrid
    local maxDrop, climb = self:MaxDrop(), ns.db.climb or 1
    local offroad = R:Offroad()
    local hereField = grid and G:Field("here", c, n, w, { speed = speed, swim = swim, safe = fall, once = once,
        maxDrop = maxDrop, climb = climb, offroad = offroad, slack = G.MOVE }) or nil
    -- To the target: worked out toward you first (A*), so the walk from here is there early.
    local targetOpts = { speed = speed, swim = swim, safe = fall, once = once, maxDrop = maxDrop, climb = climb,
        offroad = offroad, slack = 0, reverse = true, toward = target.c == c and { n, w } or nil }
    local targetField = grid and G:Field("target", target.c, target.n, target.w, targetOpts) or nil
    G.rush = false
    if grid and ((not hereField and G:Working("here")) or (not targetField and G:Working("target"))) then
        -- The plan made before still stands while the new one is worked out, unless its next step
        -- is behind you: a flight, ride or port you've taken (you're far from where it starts).
        local nx = last and last.next
        if nx and COMMITTED[nx.kind] and nx.from and nx.kind ~= "hearth" and nx.kind ~= "teleport"
            and (nx.from.c ~= c or Dist(n, w, nx.from.n, nx.from.w) > LEFT_STOP) then
            last, kept.p = nil, nil
            self.lines, self.steer = nil, nil
        end
        if Same(kept.p, p) then
            self.lines, self.steer, self.way, self.plannedFor = kept.lines, kept.steer, kept.way, p
            -- You've moved on since it was planned: the way on from its square nearest you, and the
            -- arrow steering along it from where you are now (not from where you were).
            local way = kept.way
            if way and way.continent == c and #way.squares > 1 then
                local nearest, best
                for i, s in ipairs(way.squares) do
                    local d = (s.n - n) ^ 2 + (s.w - w) ^ 2
                    if not best or d < best then nearest, best = i, d end
                end
                local rest = {}
                for i = nearest, #way.squares do rest[#rest + 1] = way.squares[i] end
                self.way = { continent = c, squares = rest }
                if kept.steer then
                    self.steer = { aim = kept.steer.aim, point = Steer(rest, c, n, w, kept.steer.aim) }
                end
            end
            return Same(last and last.p, p) and last or nil, true
        end
        -- Nothing planned for this target yet. The target's field reaches you first, so the walk
        -- from here can be followed while the rest of the plan (flights, boats) is worked out.
        local partial = target.c == c and G:Partial("target")
        if partial and G:Settled(partial, n, w) then
            local way = CityWay(c, n, w, G:Detail(c, G:Path(partial, n, w)), target.n, target.w, true)
            self.way = way and { continent = c, squares = way } or nil
            self.lines = BuildLines(nil, self.way, nil, nil, target, c, n, w)
            self.steer = ns.db.steer and { aim = p, point = Steer(way, c, n, w, p) } or nil
            return nil, true
        end
        -- Nothing to follow at all: the fields get more time each frame until there is.
        G.rush = true
        self.way = nil
        return nil, true
    end
    self.plannedFor = p
    -- Everything for this target is worked out: the way to where the arrow goes next is worked out
    -- now, in the background, so it's ready the moment the target changes (G:Field takes it over).
    if grid and not G:Busy() then
        local up = ns.Targets.Upcoming and ns.Targets:Upcoming()
        local uc, un, uw
        if up then uc, un, uw = ns.Nav:World(up) end
        if uc then
            G:Field("next", uc, un, uw, { speed = speed, swim = swim, safe = fall, once = once, maxDrop = maxDrop,
                climb = climb, offroad = offroad, slack = 0, reverse = true, later = true,
                toward = uc == target.c and { target.n, target.w } or nil })
        end
    end
    local function Done(route)
        local aim = route and route.aim or (not route and p) or nil
        local way = aim and WayFrom(hereField, targetField, aim == p, c, n, w, aim)
        self.way = way and { continent = c, squares = way } or nil
        self.lines = BuildLines(route, self.way, hereField, targetField, target, c, n, w)
        -- This task's shade; on your waypoint path, the waypoint's own, and the legs after it too.
        local onPath = e and e.owner == "path" and p.id
        local shade = onPath and ShadeOf(p) or self.shade
        for _, seg in ipairs(self.lines or {}) do seg.shade = shade end
        if onPath then
            self.lines = self.lines or {}
            StageLines(self.lines, p, grid and { speed = speed, swim = swim, safe = fall, once = once, maxDrop = maxDrop,
                climb = climb, offroad = offroad, slack = 0, reverse = true } or nil)
        end
        self.steer = aim and ns.db.steer and { aim = aim, point = Steer(way, c, n, w, aim) } or nil
        return route
    end
    local direct
    if hereField and target.c == c then
        direct = G:Cost(hereField, target.n, target.w) or INF
    else
        local walkable = target.c == c and target.land == here.land
        direct = walkable and Dist(n, w, target.n, target.w) * F.DETOUR / speed or INF
    end
    -- A short walk needs no planning, unless there's a jump on it (that's a step of its own).
    if direct < MinGain() + F.OVERHEAD and not (hereField and HasJump(hereField, target)) then return Done(nil) end
    -- A ghost can't take a flight, a boat or the hearthstone: back to the body on foot.
    if ghost then return Done(nil) end

    local V = { here, target }
    local fps = 0
    if ns.db.flights then
        -- Only flight points a flight master's map has offered you (F:FlightPoints): what the
        -- client calls discovered isn't what you can fly to.
        for name in pairs(F:FlightPoints()) do
            local node = F.Node(name)
            if node then
                local v = Vertex(node.point, "fp")
                if v then
                    v.node = node
                    V[#V + 1] = v
                    if node.c == c then fps = fps + 1 end
                end
            end
        end
        -- A long trip and no flight points to plan with: say how to fix that, once a session.
        if fps < 2 and not F.hinted and direct > 120 and direct < INF then
            F.hinted = true
            ns:Print("Waypoint doesn't know your flight paths yet, so it can't route you through them. Open any flight master's map once (talk to them) and it will.")
        end
    end
    -- Every dock is a shore to swim from; its ride counts when transports are on and it's yours.
    local mine = MyFaction()
    for _, d in ipairs(self:Docks()) do
        local dep = { point = d.point, c = d.c, n = d.n, w = d.w, land = Island(d.point), kind = "dock", dock = d,
            name = d.t.place or d.t.dest, shore = true }
        V[#V + 1] = dep
        if ns.db.transports and (not d.t.faction or d.t.faction == mine) then
            local lp, approx = Landing(d)
            local arrive = Vertex(lp, "landing")
            if arrive then
                arrive.name, arrive.shore = d.t.dest, not approx
                V[#V + 1] = arrive
                dep.ride = #V
                dep.rideSecs = self:RideSecs(d.t)
            end
        end
    end
    local starts = {} -- legs that start where you stand: { index, secs, kind }
    do
        if ns.db.useHearth and ItemCount(HEARTHSTONE) > 0 then
            local hp, bind = HearthPoint()
            local v = Vertex(hp, "hearth")
            if v then
                v.name = bind
                V[#V + 1] = v
                starts[#starts + 1] = { index = #V, secs = ItemCooldown(HEARTHSTONE) + CAST + LOAD, kind = "hearth" }
            end
        end
        for id, city in pairs(ns.db.useTeleports and ns.Transports.TELEPORTS or {}) do
            if SpellKnown(id) and HasRune() and SpellUsable(id) then
                local v = Vertex(TeleportPoint(id, city), "teleport")
                if v then
                    v.name, v.spell = city, id
                    V[#V + 1] = v
                    starts[#starts + 1] = { index = #V, secs = CAST + LOAD, kind = "teleport" }
                end
            end
        end
    end

    -- Dijkstra from you (1) to the target (2). Walks from you and to the target follow the land
    -- and water map when it's ready; the rest are straight lines.
    local dist, prev, how, done = {}, {}, {}, {}
    for i = 1, #V do dist[i] = INF end
    dist[1] = 0
    while true do
        local u, best = nil, INF
        for i = 1, #V do
            if not done[i] and dist[i] < best then u, best = i, dist[i] end
        end
        if not u or u == 2 then break end
        done[u] = true
        local a = V[u]
        for v = 2, #V do
            local b = V[v]
            if not done[v] and b.c == a.c then
                local cost, kind
                if u == 1 and hereField then
                    cost, kind = G:Cost(hereField, b.n, b.w), "walk"
                elseif v == 2 and targetField then
                    cost, kind = G:Cost(targetField, a.n, a.w), "walk"
                else
                    local d = Dist(a.n, a.w, b.n, b.w)
                    if a.land == b.land then
                        cost, kind = d * F.DETOUR / speed, "walk"
                    elseif a.shore and b.shore and swim > 0 then
                        cost, kind = d * SWIM_DETOUR / swim, "swim"
                    end
                end
                if cost and best + cost < dist[v] then dist[v], prev[v], how[v] = best + cost, u, kind end
                -- A flight only where that flight master's map offered it (or you've flown it).
                if a.node and b.node and F:CanFly(a.node.name, b.node.name) then
                    cost = F.OVERHEAD + F:FlightTime(a.node, b.node)
                    if best + cost < dist[v] then dist[v], prev[v], how[v] = best + cost, u, "fly" end
                end
            end
        end
        if a.ride and best + a.rideSecs < dist[a.ride] then
            dist[a.ride], prev[a.ride], how[a.ride] = best + a.rideSecs, u, "ride"
        end
        if u == 1 then
            for _, s in ipairs(starts) do
                if s.secs < dist[s.index] then dist[s.index], prev[s.index], how[s.index] = s.secs, 1, s.kind end
            end
        end
    end
    if dist[2] == INF then return Done(nil) end

    -- The legs, in order. The walks from you and to the target are split where they cross water;
    -- then walks in a row are joined into one.
    local chain = {}
    local v = 2
    while v ~= 1 do
        local u = prev[v]
        table.insert(chain, 1, { kind = how[v], from = V[u], to = V[v], secs = dist[v] - dist[u], aquatic = how[v] == "swim" and aquatic })
        v = u
    end
    local expanded = {}
    for i, leg in ipairs(chain) do
        local parts = { leg }
        if leg.kind == "walk" then
            leg.aquatic = aquatic
            if i == 1 and hereField then
                local path = G:Path(hereField, leg.to.n, leg.to.w)
                if path then
                    local steps = {}
                    for k = #path, 1, -1 do
                        local s = path[k]
                        steps[#steps + 1] = { n = s.n, w = s.w, water = s.water, face = s.face, h = s.h, e = s.t }
                    end
                    parts = Split(leg, steps, leg.secs, fall)
                end
            elseif i == #chain and leg.to == target and targetField then
                local path = G:Path(targetField, leg.from.n, leg.from.w)
                if path and path[1] then
                    local steps, t0 = {}, path[1].t
                    for _, s in ipairs(path) do
                        steps[#steps + 1] = { n = s.n, w = s.w, water = s.water, face = s.face, h = s.h, e = t0 - s.t }
                    end
                    parts = Split(leg, steps, leg.secs, fall)
                end
            end
        end
        for _, part in ipairs(parts) do expanded[#expanded + 1] = part end
    end
    local legs, swims = {}, false
    for _, leg in ipairs(expanded) do
        local prevLeg = legs[#legs]
        if prevLeg and prevLeg.kind == "walk" and leg.kind == "walk" then
            prevLeg.to, prevLeg.secs = leg.to, prevLeg.secs + leg.secs
        else
            legs[#legs + 1] = leg
        end
        if leg.kind == "swim" or leg.kind == "drop" then swims = true end
    end
    if #legs == 1 and legs[1].kind == "walk" then return Done(nil) end

    local route = { legs = legs, total = dist[2], direct = direct, gain = direct - dist[2], sig = Signature(legs), p = p }
    local same = last and last.sig == route.sig
    -- Another plan than the one you're on (hearth, then fly; or fly from somewhere else): only
    -- if it's clearly quicker. Otherwise the old one stands, with its time from where you are now.
    if last and not same then
        local still = StillTakes(last, p, hereField, c, n, w, speed)
        local beatsWalking = still and (direct >= INF or direct - still >= math.max(MinGain(), direct * MinShare()) / 2)
        if still and beatsWalking and route.total > still - math.max(KEEP_SECS, still * KEEP_SHARE) then
            last.total, last.gain = still, (last.direct or INF) - still
            return Done(last)
        end
    end
    -- All on foot: nothing to beat, but a swim across is still worth saying.
    local onFoot = true
    for _, leg in ipairs(legs) do
        if leg.kind ~= "walk" and leg.kind ~= "swim" and leg.kind ~= "drop" then onFoot = false end
    end
    route.onFoot = onFoot -- it is the walk, so it saves nothing on it
    if direct < INF and not (onFoot and swims) then
        local need = math.max(MinGain(), direct * MinShare())
        if same then need = need / 2 end -- don't flip back and forth at the edge
        if route.gain < need then return Done(nil) end
    end
    -- What to do next, and where the arrow leads for it.
    for _, leg in ipairs(legs) do
        if leg.kind ~= "walk" then route.next = leg break end
    end
    if legs[1].kind == "walk" or legs[1].kind == "swim" or legs[1].kind == "drop" then route.aim = legs[1].to.point end
    if route.next.kind == "fly" then route.from, route.to = route.next.from.node, route.next.to.node end
    -- Said in chat only when the ways you'd travel change (a flight, a ride, a hearthstone, jumps
    -- with Walk on Air or taking damage, swims), or the target does: re-planning as you go keeps
    -- coming up with slightly different versions of the same trip, and those stay quiet.
    local ways, task = Ways(legs), tostring(taskKey) .. ":" .. tostring(p.id or "")
    if ns.db.announce and not (announced and announced.target == task and announced.ways == ways) then
        announced = { target = task, ways = ways }
        local parts = {}
        for _, leg in ipairs(legs) do
            if leg.kind ~= "walk" then
                local text = LegText(leg)
                if leg.kind == "drop" and not leg.fall then text = "jump down" end
                local prev = parts[#parts]
                if prev and prev.text == text then prev.count = prev.count + 1 else parts[#parts + 1] = { text = text, count = 1 } end
            end
        end
        local out = {}
        for _, part in ipairs(parts) do
            out[#out + 1] = part.count > 1 and ("%s (%d times)"):format(part.text, part.count) or part.text
        end
        if legs[#legs].kind == "walk" then out[#out + 1] = "walk" end
        local hurt = 0
        for _, leg in ipairs(legs) do
            if leg.kind == "drop" and not leg.fall then hurt = hurt + G.FallDamage(leg.height or 0) end
        end
        if hurt > 0 then
            out[#out] = out[#out] .. ("; the jumps cost about %d%% of your health in all"):format(math.floor(hurt * 100 + 0.5))
        end
        ns:Print(("Fastest way: |cffffffff%s|r (about %s%s)."):format(table.concat(out, ", then "),
            F.Clock(route.total), (direct < INF and not onFoot) and (" instead of " .. F.Clock(direct) .. " on foot") or ""))
    end
    return Done(route)
end

-- ---------------------------------------------------------------------------------------------
-- Text for the arrow
-- ---------------------------------------------------------------------------------------------

-- The arrow's title for a leg.
function R:Title(leg)
    if leg.kind == "fly" then return ("Fly: %s to %s"):format(leg.from.node.name, leg.to.node.name) end
    if leg.kind == "ride" then
        local t = leg.from.dock.t
        return ("%s to %s"):format(LABEL[t.kind] or "Ship", t.dest)
    end
    if leg.kind == "hearth" then return "Hearthstone to " .. leg.to.name end
    if leg.kind == "swim" then return "Swim to " .. (leg.to.name or "the far shore") end
    if leg.kind == "drop" then
        if leg.fall then return "Jump down with " .. leg.fall end
        return ("Jump down %d yd"):format(leg.height or 0)
    end
    return "Teleport: " .. leg.to.name
end

-- What to do for a leg that starts where you stand (hearthstone, teleport).
function R:Action(leg)
    if InCombat() then
        return leg.kind == "hearth" and "Hearthstone once combat ends" or "Teleport once combat ends"
    end
    if leg.kind == "hearth" then
        local cd = ItemCooldown(HEARTHSTONE)
        return cd > 1 and ("Hearthstone ready in " .. F.Clock(cd)) or "Use your Hearthstone now"
    end
    return ("Cast %s now"):format(SpellName(leg.to.spell) or ("Teleport: " .. leg.to.name))
end

-- What the place is called where a leg starts ("1.2 km to the zeppelin").
function R:Place(leg)
    if leg.kind == "fly" then return "flight master" end
    if leg.kind == "ride" then return (LABEL[leg.from.dock.t.kind] or "Ship"):lower() end
    if leg.kind == "swim" then return "shore" end
    if leg.kind == "drop" then return "cliff edge" end
    return "start"
end

-- How close counts as there.
function R:Radius(leg)
    if leg.kind == "ride" then return ns.Transports.RADIUS[leg.from.dock.t.kind] or 30 end
    if leg.kind == "swim" then return 40 end
    if leg.kind == "drop" then return 30 end
    return 20
end

-- What to do once you're there.
function R:AtText(leg)
    if leg.kind == "fly" then return "Talk to the flight master" end
    if leg.kind == "ride" then
        local t = leg.from.dock.t
        return ("Wait for the %s to %s"):format((LABEL[t.kind] or "Ship"):lower(), t.dest)
    end
    if leg.kind == "swim" then
        local tip = self:FormTip(leg)
        return (tip and (tip .. " and swim to %s") or "Swim to %s"):format(leg.to.name or "the far shore")
    end
    if leg.kind == "drop" then
        if leg.fall then return ("Cast %s and jump down"):format(leg.fall) end
        -- Your health now against what the jump costs: jumps in a row add up.
        local share = G and G.FallDamage(leg.height or 0) or 0
        local hp, top = C.Num(C.Call(UnitHealth, "player")), MaxHealth()
        local left = hp and top and top > 0 and (hp / top - share)
        if left and left <= 0 then
            return ("|cffff4040Heal first|r: this %d yd jump would kill you"):format(leg.height or 0)
        elseif left and left < 0.15 then
            return ("|cffffa040Heal first|r: this jump leaves you about %d%% health"):format(math.floor(left * 100 + 0.5))
        end
        return ("Jump down: %s"):format(self:FallText(leg.height or 0))
    end
    return self:Action(leg)
end

-- The ride ZeppelinSigns says you're on (its Rides.lua times every ride from boarding), or nil.
local function ZepRide()
    local api = ZeppelinSignsAPI
    if not (api and api.Ride) then return nil end
    local ok, z = pcall(api.Ride)
    return ok and type(z) == "table" and z or nil
end
R.ZepRide = ZepRide

-- On a ride: { label = "zeppelin to Undercity", left = seconds, timed }. ZeppelinSigns' countdown
-- when it has the ride (timed: a learned length, not a guess), else Waypoint's own.
function R:Riding()
    local r = self.riding
    local z = ZepRide()
    if z then
        local kind = r and r.d.t.kind or z.kind
        return { label = ("%s to %s"):format((LABEL[kind] or "Ship"):lower(), z.dest), left = z.left, timed = z.timed }
    end
    if not r then return nil end
    local t = r.d.t
    return { label = ("%s to %s"):format((LABEL[t.kind] or "Ship"):lower(), t.dest),
        left = math.max(0, r.since + r.expect - GetTime()) }
end

-- ---------------------------------------------------------------------------------------------
-- Learning: rides, hearthstone, teleports
-- ---------------------------------------------------------------------------------------------

local atDock -- { d, since }: the dock you stand at, since when
local trip   -- { d, since, left }: the dock you walked away from, until you arrive or give up
local port   -- { kind, spell, at, c, n, w }: a hearthstone or teleport just cast
local last   -- { c, n, w }: where you were at the last check
local swimSince, tipAt = nil, -INF -- swimming in your own form since; when we last said to shift

local function NearestDock(c, n, w)
    local best, bestD
    for _, d in ipairs(R:Docks()) do
        if d.c == c then
            local dd = Dist(n, w, d.n, d.w)
            if dd <= (ns.Transports.RADIUS[d.t.kind] or 30) and (not bestD or dd < bestD) then best, bestD = d, dd end
        end
    end
    return best
end

-- A ride you took: its time (an average that follows the last few trips), and where it landed
-- when only the town was known.
local function Learn(t, secs, approx)
    if secs < 20 then return end
    local rec = ns.db.rides[t.key] or {}
    local weight = math.min(rec.n or 0, 4)
    rec.secs = math.floor(((rec.secs or 0) * weight + secs) / (weight + 1) + 0.5)
    rec.n = (rec.n or 0) + 1
    if approx then
        local m, x, y = Here()
        if m then rec.m, rec.x, rec.y = m, x, y end
    end
    ns.db.rides[t.key] = rec
    landCache[t.key] = nil
end

-- ---------------------------------------------------------------------------------------------
-- Learning the ground: steps you walk, and RoadLog's marks
-- ---------------------------------------------------------------------------------------------

-- The land map misses passes narrower than its squares. Any step you walk from one square into
-- the next on your own feet (not falling, flying, swimming or on a flight) that the map says you
-- can't take is remembered (ns.db.learned[continent][key], for every character) and opens that
-- link from then on: walked uphill or on the level, both ways; walked down a big drop, only down.
-- RoadLog's narrow passes open every link of their square, its roads count as walked, and its
-- blockers close the links that cross them.
local walkFrom -- { c, n, w, at }: where you were at the last check, on your own feet

-- True for a state the game says is on; false for off, unknown or secret.
local function Flag(fn, ...)
    return C.Readable(C.Call(fn, ...)) and true or false
end

-- Each step from square to square along a road (flat { n, w, ... }): fn(key, back), the link keys
-- both ways. Points are put in every ROAD_STEP yards first: a cleaned road's straight stretches have
-- their points far apart, and only neighbouring squares make a step.
local ROAD_STEP = 20
local function RoadSteps(c, pts, fn)
    local pn, pw
    for i = 1, #pts - 1, 2 do
        local n, w = pts[i], pts[i + 1]
        if pn then
            local parts = math.max(1, math.ceil(math.sqrt((n - pn) ^ 2 + (w - pw) ^ 2) / ROAD_STEP))
            for k = 1, parts do
                local an, aw = pn + (n - pn) * (k - 1) / parts, pw + (w - pw) * (k - 1) / parts
                local bn, bw = pn + (n - pn) * k / parts, pw + (w - pw) * k / parts
                local key, back = G:LinkKey(c, an, aw, bn, bw)
                if key then fn(key, back) end
            end
        end
        pn, pw = n, w
    end
end

-- How much more a step off the roads weighs, by your road preference (ns.db.roadMode):
--   safe      roads first: a way off them has to be far quicker to be taken
--   balanced  roads where they lead your way, left for the last stretch to where you're going
--   speed     the quickest way, roads or not; a road only when it's about as quick (then it's the
--             way you'd walk anyway)
R.ROAD_MODES = {
    { id = "safe", name = "Safe", offroad = 2.5,
        text = "Keeps to roads. Leaves them only where a way off the road is far quicker, or there's no road." },
    { id = "balanced", name = "Balanced", offroad = 1.5,
        text = "Takes the roads that lead your way, and leaves them for the last stretch to where you're going." },
    { id = "speed", name = "Speed", offroad = 1.08,
        text = "The quickest way, roads or not. A road only when it's about as quick." },
}
function R:RoadMode()
    local id = ns.db and ns.db.roadMode
    for _, mode in ipairs(self.ROAD_MODES) do
        if mode.id == id then return mode end
    end
    return self.ROAD_MODES[2]
end
function R:Offroad() return self:RoadMode().offroad end

-- Through ns:SetOption, so Options > AddOns > Waypoint shows it; the option drops the planned flight.
function R:SetRoadMode(id)
    ns:SetOption("db.roadMode", id)
end

-- The roads Waypoint knows (Data\Roads.lua, from RoadLog, for everyone) and the ones RoadLog has
-- logged here: { [continent] = { flat, flat, ... } }.
AllRoads = function()
    local out = {}
    local function Add(c, pts)
        out[c] = out[c] or {}
        table.insert(out[c], pts)
    end
    for c, data in pairs(ns.Roads or {}) do
        for _, pts in ipairs(data.roads or {}) do Add(c, pts) end
    end
    local rl = type(RoadLogDB) == "table" and RoadLogDB or nil
    for c, segs in pairs(rl and type(rl.roads) == "table" and rl.roads or {}) do
        for _, seg in ipairs(segs) do
            if type(seg.pts) == "table" then Add(c, seg.pts) end
        end
    end
    return out
end

local function Overrides()
    if not (G and ns.db) then return end
    local open, block = {}, {}
    local function Open(c, key) if key then open[c] = open[c] or {}; open[c][key] = true end end
    for c, keys in pairs(ns.db.learned or {}) do
        for key in pairs(keys) do Open(c, key) end
    end
    -- Ways you said are blocked (R:BlockAhead): closed, whatever else says.
    for c, keys in pairs(ns.db.blocked or {}) do
        block[c] = block[c] or {}
        for key in pairs(keys) do block[c][key] = true end
    end
    -- Narrow passes and blockers: Waypoint's own (Data\Roads.lua) and RoadLog's.
    local rl = type(RoadLogDB) == "table" and RoadLogDB or nil
    local passes, blockers = {}, {}
    local function Add(into, c, item)
        into[c] = into[c] or {}
        table.insert(into[c], item)
    end
    for c, data in pairs(ns.Roads or {}) do
        for _, p in ipairs(data.passes or {}) do Add(passes, c, { n = p[1], w = p[2] }) end
        for _, pts in ipairs(data.blockers or {}) do Add(blockers, c, pts) end
    end
    if rl then
        for c, pins in pairs(type(rl.passes) == "table" and rl.passes or {}) do
            for _, pin in ipairs(pins) do Add(passes, c, pin) end
        end
        for c, segs in pairs(type(rl.blockers) == "table" and rl.blockers or {}) do
            for _, seg in ipairs(segs) do Add(blockers, c, seg.pts or {}) end
        end
    end
    for c, pins in pairs(passes) do
        for _, pin in ipairs(pins) do
            if pin.n and pin.w then
                for _, key in ipairs(G:SquareKeys(c, pin.n, pin.w)) do Open(c, key) end
            end
        end
    end
    -- Roads count as walked, and their steps are what the road preference keeps to.
    local roads = {}
    for c, list in pairs(AllRoads()) do
        roads[c] = roads[c] or {}
        for _, pts in ipairs(list) do
            RoadSteps(c, pts, function(key, back)
                Open(c, key); Open(c, back)
                roads[c][key], roads[c][back] = true, true
            end)
        end
    end
    for c, list in pairs(blockers) do
        block[c] = block[c] or {}
        for _, pts in ipairs(list) do
            for i = 3, #pts - 1, 2 do
                for _, key in ipairs(G:CrossingKeys(c, pts[i - 2], pts[i - 1], pts[i], pts[i + 1])) do
                    block[c][key] = true
                end
            end
        end
    end
    local continents = {}
    for c in pairs(open) do continents[c] = true end
    for c in pairs(block) do continents[c] = true end
    for c in pairs(continents) do G:SetOverrides(c, open[c], block[c]) end
    for c, keys in pairs(roads) do G:SetRoads(c, keys) end
    streets = {} -- the street network again, from the roads as they are now
    R:MarkCities()
end

-- The major cities keep to their roads whatever your road preference (Safe's weight at least):
-- their streets are the way through, and the land map doesn't see their buildings.
local CITY_MAPS = { 1453, 1454, 1455, 1456, 1457, 1458 } -- Stormwind, Orgrimmar, Ironforge, Thunder Bluff, Darnassus, Undercity
function R:MarkCities()
    if not (CreateVector2D and C_Map.GetWorldPosFromMapPos) then return end
    local rects = {}
    for _, mapID in ipairs(CITY_MAPS) do
        local c, a = C.Call(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(0, 0))
        local c2, b = C.Call(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(1, 1))
        if c and a and b and c == c2 then
            local n1, w1 = a:GetXY()
            local n2, w2 = b:GetXY()
            rects[c] = rects[c] or {}
            table.insert(rects[c], { n1, w1, n2, w2 })
        end
    end
    cityRects, streets = {}, {}
    for c, list in pairs(rects) do
        G:SetCities(c, list, self.ROAD_MODES[1].offroad)
        cityRects[c] = {}
        for _, rc in ipairs(list) do
            table.insert(cityRects[c], { math.min(rc[1], rc[3]), math.max(rc[1], rc[3]), math.min(rc[2], rc[4]), math.max(rc[2], rc[4]) })
        end
    end
end

-- What RoadLog has logged, as a short signature, so a change is picked up.
local function RoadLogSignature()
    local rl = type(RoadLogDB) == "table" and RoadLogDB or nil
    if not rl then return "" end
    local parts = {}
    for _, key in ipairs({ "roads", "blockers", "passes" }) do
        local n, last = 0, 0
        for _, items in pairs(type(rl[key]) == "table" and rl[key] or {}) do
            n = n + #items
            local item = items[#items]
            if item and (item.at or 0) > last then last = item.at end
        end
        parts[#parts + 1] = n .. "@" .. last
    end
    return table.concat(parts, ",")
end

local roadLogSig, roadLogAt = nil, 0
local function LearnStep(c, n, w, now)
    if not (G and ns.db and ns.db.useGrid) then return end
    if now - roadLogAt > 15 then
        roadLogAt = now
        local sig = RoadLogSignature()
        if sig ~= roadLogSig then
            roadLogSig = sig
            Overrides()
        end
    end
    if Flag(IsFalling) or Flag(IsFlying) or Flag(IsSwimming) or Flag(UnitOnTaxi, "player") or R.riding then
        walkFrom = nil
        return
    end
    local prev = walkFrom
    if prev and prev.c == c and now - prev.at <= 2 then
        local key, back = G:LinkKey(c, prev.n, prev.w, n, w)
        -- Into the next square (still in the same one, or skipped one: nothing to learn).
        local hp, hc = G:Height(c, prev.n, prev.w), G:Height(c, n, w)
        -- A drop you'd take damage from isn't a walk, even if you made it.
        if key and hp and hc and hc >= hp - G.HARMLESS and G:Step(c, prev.n, prev.w, n, w) ~= "walk" then
            local learned = ns.db.learned
            learned[c] = learned[c] or {}
            learned[c][key] = true
            if hc >= hp - 10 then learned[c][back] = true end
            Overrides()
        end
    end
    walkFrom = { c = c, n = n, w = w, at = now }
end

-- "This way is blocked" (the arrow's menu, /way blocked): the map shows a way that isn't there (a
-- fence, a building, a ledge you can't get down). Closes the next step the plan takes from your
-- square: every drop out of it when the next step is a jump, else the step along the planned way.
-- Saved for every character (ns.db.blocked) and planned around from then on.
function R:BlockAhead()
    if not G then return end
    local c, n, w = ns.Nav:Player()
    if not c then
        ns:Print("Can't tell where you are here.")
        return
    end
    local blocked = ns.db.blocked
    blocked[c] = blocked[c] or {}
    local count = 0
    local function Block(key)
        if key and not blocked[c][key] then
            blocked[c][key] = true
            count = count + 1
        end
    end
    local route = F.route
    local jump = route and route.next and route.next.kind == "drop"
    if jump then
        -- every drop out of your square and the cliff edge's (the jump may start from either)
        for _, from in ipairs({ { n, w }, { route.next.from.n, route.next.from.w } }) do
            for k = 0, 7 do
                local a = k * math.pi / 4
                local tn, tw = from[1] + math.cos(a) * 66.7, from[2] + math.sin(a) * 66.7
                if G:Step(c, from[1], from[2], tn, tw) ~= "walk" then Block((G:LinkKey(c, from[1], from[2], tn, tw))) end
            end
        end
    end
    local way = self.way and self.way.squares
    if not jump and way then
        for i = 1, #way do
            local key = G:LinkKey(c, n, w, way[i].n, way[i].w)
            if key then
                Block(key)
                break
            end
        end
    end
    if count == 0 then
        ns:Print("Nothing to block here: walk a little toward where the arrow points, then try again.")
        return
    end
    Overrides()
    F.route = nil
    ns:Print(("Blocked that way (%d step%s); finding another. /way unblock forgets the ways you've blocked."):format(
        count, count == 1 and "" or "s"))
    ns:Changed()
end

-- How many steps you've blocked.
function R:BlockedCount()
    local n = 0
    for _, keys in pairs(ns.db.blocked or {}) do
        for _ in pairs(keys) do n = n + 1 end
    end
    return n
end

function R:ClearBlocks()
    local n = self:BlockedCount()
    wipe(ns.db.blocked)
    if G then
        -- the overrides are rebuilt without them; a continent left with none is cleared too
        for c in pairs(ns.Water and ns.Water.maps or {}) do G:SetOverrides(c, {}, {}) end
        Overrides()
    end
    ns:Print(("Forgot %d blocked step%s."):format(n, n == 1 and "" or "s"))
    ns:Changed()
end

-- Waypoint's own ride; one ZeppelinSigns has ends when it says so (Watch).
local function StopRiding()
    if R.riding and not R.riding.zep then
        R.riding = nil
        ns:Changed()
    end
end

local function Watch()
    if not ns.db then return end
    local now = GetTime()
    -- In Aquatic Form: how fast it really swims, for planning swims.
    if InAquatic() then
        local swim = C.Num(select(4, C.Call(GetUnitSpeed, "player")))
        if swim and swim > SWIM and swim < 20 then ns.char.taxi.aquatic = swim end
    end
    -- In the water on foot when you could swim faster: say so (on a planned swim right away, any
    -- other swim after a few seconds; once a minute at most).
    if C.Readable(C.Call(IsSwimming)) and not InAquatic() and not C.Readable(C.Call(UnitIsDeadOrGhost, "player")) then
        swimSince = swimSince or now
        local nx = F.route and F.route.next
        local planned = nx and nx.kind == "swim"
        if ns.db.formTips and ns.db.useAquatic and (planned or now - swimSince > 4) and now - tipAt > 60 and KnowsAquatic() then
            tipAt = now
            ns:Print(("In the water: switch to |cffffffff%s|r to swim 50%% faster."):format(SpellName(AQUATIC) or "Aquatic Form"))
        end
    else
        swimSince = nil
    end
    if UnitOnTaxi and C.Readable(C.Call(UnitOnTaxi, "player")) then
        trip, atDock, last = nil, nil, nil
        StopRiding()
        return
    end
    -- ZeppelinSigns' ride, while it has one: the arrow shows its countdown and the planner waits it
    -- out (Plan plans nothing while riding).
    local z = ZepRide()
    if z then
        if not (R.riding and R.riding.zep == z.key) then
            local d
            for _, o in ipairs(R:Docks()) do
                if o.t.key == z.key then d = o; break end
            end
            R.riding = { d = d or { t = { key = z.key, kind = z.kind, dest = z.dest } }, since = now - z.elapsed, left = now,
                expect = z.elapsed + z.left, zep = z.key }
            F.route = nil
            ns:Changed()
        end
    elseif R.riding and R.riding.zep then
        R.riding = nil
        ns:Changed()
    end
    local c, n, w = ns.Nav:Player()

    -- Landed after a hearthstone or teleport: that's where it goes.
    if port then
        if now - port.at > 60 then
            port = nil
        elseif c and (c ~= port.c or Dist(n, w, port.n, port.w) > 300) then
            local m, x, y = Here()
            if m then
                if port.kind == "hearth" then
                    ns.char.hearth = { bind = Bind(), m = m, x = x, y = y }
                else
                    ns.db.teleports[port.spell] = { m = m, x = x, y = y }
                end
            end
            port = nil
        end
    end
    if not c then return end
    LearnStep(c, n, w, now)

    -- Off the ride you were on: it arrived, or you never got on.
    local r = R.riding
    if r then
        local stayed = r.d.c == c and now - r.left > 20 and Dist(n, w, r.d.n, r.d.w) < 40
        if now - r.since > 2 * r.expect + 60 or stayed or C.Readable(C.Call(IsSwimming)) then StopRiding() end
    end

    -- Arrived where the dock you left goes.
    if trip then
        if now - trip.since > MAX_RIDE then
            trip = nil
            StopRiding()
        else
            local lp, approx = Landing(trip.d)
            local lc, ln, lw
            if lp then lc, ln, lw = ns.Nav:World(lp) end
            if lc == c and Dist(n, w, ln, lw) <= (approx and ARRIVE_TOWN or ARRIVE) then
                Learn(trip.d.t, now - trip.since, approx)
                trip = nil
                StopRiding()
            end
        end
    end

    -- Carried along: you moved while not moving yourself (standing on a boat or zeppelin).
    local carried = false
    if last and last.c == c then
        local speed = C.Num(GetUnitSpeed and C.Call(GetUnitSpeed, "player")) or 0
        carried = speed == 0 and Dist(n, w, last.n, last.w) > 3
    end
    last = { c = c, n = n, w = w }

    -- At a dock, or just walked off one.
    local d = NearestDock(c, n, w)
    if d then
        if not atDock or atDock.d.t.key ~= d.t.key then
            -- Back at the dock you left: still the same wait.
            atDock = { d = d, since = (trip and trip.d.t.key == d.t.key) and trip.since or now }
        end
        trip = nil
        StopRiding()
    elseif atDock then
        trip = { d = atDock.d, since = atDock.since, left = now }
        atDock = nil
    end
    -- Carried away from the dock you left: you're on its ride.
    if trip and carried and not R.riding then
        R.riding = { d = trip.d, since = trip.since, left = now, expect = R:RideSecs(trip.d.t) }
        F.route = nil
        ns:Changed()
    end
end

local acc = 0
CreateFrame("Frame"):SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.5 then return end
    acc = 0
    Watch()
end)

-- ZeppelinSigns boarded, landed or gave up a ride: catch up right away, not at the next check.
if ZeppelinSignsAPI and ZeppelinSignsAPI.OnChange then
    ZeppelinSignsAPI.OnChange(function() acc = 0.5 end)
end

ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit ~= "player" then return end
    local id = C.Num(spellID)
    local kind = id == HEARTH_SPELL and "hearth" or (id and ns.Transports.TELEPORTS[id] and "teleport")
    if not kind then return end
    local c, n, w = ns.Nav:Player()
    if c then port = { kind = kind, spell = id, at = GetTime(), c = c, n = n, w = w } end
end)

-- Setting your hearthstone at an innkeeper: it takes you about here.
ns:On("HEARTHSTONE_BOUND", function()
    local m, x, y = Here()
    local bind = Bind()
    if m and bind then ns.char.hearth = { bind = bind, m = m, x = x, y = y } end
end)

-- /way flights: what the planner knows besides flights.
function R:Status()
    local count, timed, mine = 0, 0, MyFaction()
    for _, d in ipairs(self:Docks()) do
        if not d.t.faction or d.t.faction == mine then
            count = count + 1
            if ns.db.rides[d.t.key] then timed = timed + 1 end
        end
    end
    ns:Print(("Boats, zeppelins and skyships %s: %d docks you can use, %d rides timed. /way transports on | off"):format(
        ns.db.transports and "on" or "off", count, timed))
    local hp, bind = HearthPoint()
    if ItemCount(HEARTHSTONE) == 0 then
        ns:Print("Hearthstone: not in your bags.")
    elseif not bind then
        ns:Print("Hearthstone: no bind location.")
    else
        local known = ns.char.hearth.bind == bind and ns.char.hearth.m
        ns:Print(("Hearthstone: %s (%s)."):format(bind, known and "spot learned"
            or hp and "guessed from the town until you use it" or "use it once so Waypoint learns where it goes"))
    end
    local swim, aquatic = self:SwimSpeed()
    ns:Print(("Swimming: %.1f yards/s%s."):format(swim, not ns.db.allowSwim and " (turned off: counted that slow, so routes only swim when there's no other way)"
        or aquatic and (ns.char.taxi.aquatic and " (Aquatic Form)" or " (Aquatic Form, until Waypoint sees you swim in it)") or ""))
    local fall = self:SafeFall()
    if fall then
        local feathers = ItemCount(FEATHER)
        ns:Print(("Cliffs: %s ready%s, so routes can jump down any cliff."):format(fall,
            feathers > 0 and (" (%d Light Feather%s)"):format(feathers, feathers == 1 and "" or "s") or ""))
    end
    ns:Print(("Without it, routes jump drops up to %d yd (%s). Options > AddOns > Waypoint sets that."):format(
        self:MaxDrop(), self:FallText(self:MaxDrop())))
    local ports = {}
    for id, city in pairs(ns.Transports.TELEPORTS) do
        if SpellKnown(id) then ports[#ports + 1] = city .. (ns.db.teleports[id] and "" or " (not cast yet)") end
    end
    if #ports > 0 then
        table.sort(ports)
        ns:Print("Teleports: " .. table.concat(ports, ", ") .. ".")
    end
end
