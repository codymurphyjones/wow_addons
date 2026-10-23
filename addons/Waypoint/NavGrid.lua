local _, ns = ...

-- Travel over the game's own ground (Data\Nav<map>.lua, baked from the game's files by
-- tools\Waypoint\nav_*.py): the floors you can stand on in every 8-yard cell of the world, the
-- buildings, bridges, caves and stairs included, a cell holding as many floors as are stacked in it,
-- and the links between them: a walk, a swim, or a drop with how far you fall.
--
-- It takes Grid.lua's place (the same calls, so Route.lua works with either), for the maps it has
-- data for; the others stay with Grid.lua. A route is found in two steps:
--   1. door to door: each map tile (533 yards) has doors on its edges, with the times across the
--      tile between them baked in (walking and swimming apart, scaled here by your speeds). A field
--      is your tile searched node by node, then every door of the map from there.
--   2. node by node: where a way is needed (the walk to the next stop, the lines on the map), the
--      tiles it crosses are searched node by node between its doors, with your own settings (fall
--      damage, safe falls, climbing, roads).
-- Tiles are unpacked (C_EncodingUtil) the first time they're needed, and the least used dropped.
local Old = ns.Grid
local DATA = ns.NavData
if not (Old and DATA and next(DATA) and C_EncodingUtil and C_EncodingUtil.DecompressString) then return end

local G = setmetatable({}, { __index = Old })
ns.Grid = G

local BUDGET = 2          -- milliseconds of work per frame (none in combat)
local RUSH = 6            -- ...while you're waiting for a route
local KEEP_TILES = 160    -- unpacked tiles kept
local MOVE_YARDS = 150    -- yards you can move before your field is worked out again
local REFINE_BUDGET = 12  -- milliseconds a path may spend walking tiles out node by node, per call
local RUN, SWIM = 7.0, 4.72   -- the speeds the doors' times were baked at (nav_pack.py)
local SLIDE = 1.5         -- sliding down a small drop is this much slower than walking
local JUMP_COST = 30      -- a jump you'd take damage from (or need a safe fall for): seconds extra
local HARMLESS = Old.HARMLESS
local NONE = {}
local STEPS = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 }, { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } }
local floor, sqrt, abs, huge = math.floor, math.sqrt, math.abs, math.huge

-- ---------------------------------------------------------------------------------------------
-- Data
-- ---------------------------------------------------------------------------------------------

local function Unpack(s)
    local z = C_EncodingUtil.DecodeBase64(s)
    return z and C_EncodingUtil.DecompressString(z, Enum.CompressionMethod.Zlib)
end

local maps = {} -- continent -> state
local Doors    -- below

local function Map(continent)
    local m = maps[continent]
    if m ~= nil then return m or nil end
    local d = DATA[continent]
    if not d then
        maps[continent] = false
        return nil
    end
    m = { continent = continent, d = d, fine = d.fine, max = d.max, tiles = {}, used = {}, count = 0, clock = 0,
        block = {}, roads = nil, cities = nil }
    maps[continent] = m
    return m
end

local function I16(raw, o)
    local a, b = raw:byte(o, o + 1)
    local v = a + b * 256
    return v >= 32768 and v - 65536 or v
end

local function U16(raw, o)
    local a, b = raw:byte(o, o + 1)
    return a + b * 256
end

-- A tile's nodes, unpacked (nav_pack.py's layout): or nil when the tile has none.
local function Tile(m, t)
    local T = m.tiles[t]
    m.clock = m.clock + 1
    if T then
        m.used[t] = m.clock
        return T
    end
    if T == false then return nil end
    local s = m.d.tiles[t]
    local raw = s and Unpack(s)
    if not raw then
        m.tiles[t] = false
        return nil
    end
    -- Too many unpacked: drop the least used.
    if m.count >= KEEP_TILES then
        local oldest, at
        for k, u in pairs(m.used) do
            if not at or u < at then oldest, at = k, u end
        end
        if oldest then
            m.tiles[oldest], m.used[oldest] = nil, nil
            m.count = m.count - 1
        end
    end
    local first, cnt, cellOf = {}, {}, {}
    local n = 0
    for c = 0, 4095 do
        local k = raw:byte(c + 1)
        if k > 0 then
            first[c], cnt[c] = n + 1, k
            for i = n + 1, n + k do cellOf[i] = c end
            n = n + k
        end
    end
    local kind, mask, h, on, ow, xo, ne, busy = {}, {}, {}, {}, {}, {}, {}, {}
    local o = 4096
    local offs = {}
    for i = 1, n do
        local f = raw:byte(o + i)
        kind[i] = f % 4
        mask[i] = floor(f / 4) % 16
        offs[i] = floor(f / 64) % 2 == 1
        busy[i] = f >= 128 or nil -- frequented: creatures and objects stand there (nav_stitch.py)
    end
    o = o + n
    local prev = 0
    for i = 1, n do
        prev = prev + I16(raw, o + 2 * i - 1)
        h[i] = prev * 0.5
    end
    o = o + 2 * n
    for i = 1, n do
        if offs[i] then
            o = o + 1
            local b = raw:byte(o)
            on[i], ow[i] = (floor(b / 16) + 0.5) / 16, (b % 16 + 0.5) / 16
        end
    end
    local p = o + n
    for i = 1, n do
        ne[i] = raw:byte(o + i)
        xo[i] = p
        p = p + 3 * ne[i]
    end
    T = { t = t, ty = floor(t / 64), tx = t % 64, n = n, first = first, cnt = cnt, cell = cellOf, kind = kind,
        mask = mask, h = h, on = on, ow = ow, xo = xo, ne = ne, raw = raw, nb = {}, rev = {}, busy = busy }
    m.tiles[t], m.used[t] = T, m.clock
    m.count = m.count + 1
    return T
end

local function Id(t, i) return t * 65536 + i end
local function Split(id) return floor(id / 65536), id % 65536 end

-- The global cell (row, column) of a node, and its world position and height.
local function Where(m, id)
    local t, i = Split(id)
    local T = Tile(m, t)
    if not T then return nil end
    local c = T.cell[i]
    local gr, gc = T.ty * 64 + floor(c / 64), T.tx * 64 + c % 64
    local n = m.max - (gr + (T.on[i] or 0.5)) * m.fine
    local w = m.max - (gc + (T.ow[i] or 0.5)) * m.fine
    return n, w, T.h[i], T.kind[i], gr, gc
end

-- The tile and cell of a global cell (row, column).
local function CellAt(gr, gc)
    return floor(gr / 64) * 64 + floor(gc / 64), (gr % 64) * 64 + gc % 64
end

-- The nodes of a global cell: tile, first node, count.
local function CellNodes(m, gr, gc)
    local t, c = CellAt(gr, gc)
    local T = Tile(m, t)
    if not T or not T.first[c] then return nil end
    return T, T.first[c], T.cnt[c]
end

-- A node's links: { to, kind (0 walk, 1 swim, 2 drop), fall } each, worked out once.
local function Links(m, id)
    local t, i = Split(id)
    local T = Tile(m, t)
    if not T then return NONE end
    local out = T.nb[i]
    if out then return out end
    out = {}
    local c = T.cell[i]
    local gr, gc = T.ty * 64 + floor(c / 64), T.tx * 64 + c % 64
    local mk, hi, wet = T.mask[i], T.h[i], T.kind[i] == 1
    for d = 0, 3 do
        if floor(mk / 2 ^ d) % 2 == 1 then
            local s = STEPS[d + 1]
            local U, f, k = CellNodes(m, gr + s[1], gc + s[2])
            if U then
                local best, bd
                for j = f, f + k - 1 do
                    local dd = abs(U.h[j] - hi)
                    if not bd or dd < bd then best, bd = j, dd end
                end
                out[#out + 1] = { Id(U.t, best), (wet or U.kind[best] == 1) and 1 or 0, 0 }
            end
        end
    end
    local raw, o = T.raw, T.xo[i]
    for k = 0, T.ne[i] - 1 do
        local a, place, fall = raw:byte(o + 3 * k + 1, o + 3 * k + 3)
        local dir, kind = a % 16, floor(a / 16)
        local U, f, cnt
        if dir == 8 then
            U, f, cnt = T, T.first[c], T.cnt[c]
        else
            local s = STEPS[dir + 1]
            U, f, cnt = CellNodes(m, gr + s[1], gc + s[2])
        end
        if U and place < cnt then out[#out + 1] = { Id(U.t, f + place), kind, fall * 0.5 } end
    end
    -- A lift, portal or the tram from here: kind 3, its seconds in place of a fall.
    for _, j in ipairs(Doors(m).jump[id] or NONE) do out[#out + 1] = { j[1], 3, j[2] } end
    T.nb[i] = out
    return out
end

-- The links into a node: { from, kind, fall } each (the nodes of its cell and the 8 around it
-- that link to it).
local function Into(m, id)
    local t, i = Split(id)
    local T = Tile(m, t)
    if not T then return NONE end
    local out = T.rev[i]
    if out then return out end
    out = {}
    local c = T.cell[i]
    local gr, gc = T.ty * 64 + floor(c / 64), T.tx * 64 + c % 64
    for dr = -1, 1 do
        for dc = -1, 1 do
            local U, f, k = CellNodes(m, gr + dr, gc + dc)
            if U then
                for j = f, f + k - 1 do
                    local from = Id(U.t, j)
                    for _, l in ipairs(Links(m, from)) do
                        if l[1] == id and l[2] ~= 3 then out[#out + 1] = { from, l[2], l[3] } end
                    end
                end
            end
        end
    end
    for _, j in ipairs(Doors(m).jumpIn[id] or NONE) do out[#out + 1] = { j[1], 3, j[2] } end
    T.rev[i] = out
    return out
end

-- The node at a world point: of its cell's floors, the one nearest the height (or the ground's,
-- Grid.lua's, without one); an empty cell (inside a wall, out at sea) takes the nearest within 3.
local function Locate(m, n, w, height)
    local gr, gc = floor((m.max - n) / m.fine), floor((m.max - w) / m.fine)
    height = height or Old:Height(m.continent, n, w)
    for ring = 0, 3 do
        local best, bd
        for dr = -ring, ring do
            for dc = -ring, ring do
                if ring == 0 or abs(dr) == ring or abs(dc) == ring then
                    local T, f, k = CellNodes(m, gr + dr, gc + dc)
                    if T then
                        for j = f, f + k - 1 do
                            if T.kind[j] ~= 2 then
                                local d = (height and abs(T.h[j] - height) or 0) + (abs(dr) + abs(dc)) * m.fine
                                if not bd or d < bd then best, bd = Id(T.t, j), d end
                            end
                        end
                    end
                end
            end
        end
        if best then return best end
    end
end

-- ---------------------------------------------------------------------------------------------
-- Costs
-- ---------------------------------------------------------------------------------------------

-- The override key of a step between two cells (global row, column): cell * 2^24 + cell.
local function CellKey(gr, gc) return gr * 4096 + gc end
local function StepKey(a, b) return a * 16777216 + b end

-- Seconds (and the weight the search goes by) for the step u -> v along link l, the way you walk
-- it; nil when you can't take it (fields' settings: speed, swim, safe, maxDrop, climb, offroad).
local Hazard -- below

local function StepCost(m, f, u, v, kind, fall)
    if kind == 3 then return fall, fall end
    local un, uw, uh, uk, ur, uc = Where(m, u)
    local vn, vw, vh, vk, vr, vc = Where(m, v)
    if not (un and vn) or vk == 2 or uk == 2 then return nil end
    local ka, kb = CellKey(ur, uc), CellKey(vr, vc)
    if ka ~= kb and m.block[StepKey(ka, kb)] then return nil end
    local dn, dw = un - vn, uw - vw
    local d = sqrt(dn * dn + dw * dw)
    local secs
    if kind == 2 then
        if fall > f.maxDrop and not f.safe then return nil end
        secs = d / f.speed * (fall > HARMLESS and 1 or SLIDE) + (fall > HARMLESS and JUMP_COST or 0)
    elseif kind == 1 or uk == 1 or vk == 1 then
        if f.swim <= 0 then return nil end
        secs = d / f.swim
    else
        secs = d / f.speed
        local rise = vh - uh
        if rise > 0 then secs = secs + rise * f.climb / f.speed end
    end
    local weight = secs * Hazard(m, f, vr, vc)
    local roads = m.roads
    if roads and not (roads[ka] and roads[kb]) then
        local wt = (m.cities and (m.cities[ka] or m.cities[kb])) and math.max(f.offroad, m.cityOffroad or 1) or f.offroad
        if wt ~= 1 then weight = secs * wt end
    end
    return weight, secs
end

-- A binary heap.
local function Heap()
    local hk, hv, size = {}, {}, 0
    local H = {}
    function H.push(k, v)
        size = size + 1
        local i = size
        while i > 1 do
            local p = floor(i / 2)
            if hk[p] <= k then break end
            hk[i], hv[i] = hk[p], hv[p]
            i = p
        end
        hk[i], hv[i] = k, v
    end
    function H.pop()
        local k, v = hk[1], hv[1]
        local lk, lv = hk[size], hv[size]
        hk[size], hv[size] = nil, nil
        size = size - 1
        if size > 0 then
            local i = 1
            while true do
                local l = i * 2
                if l > size then break end
                local r = l + 1
                local c = (r <= size and hk[r] < hk[l]) and r or l
                if hk[c] >= lk then break end
                hk[i], hv[i] = hk[c], hv[c]
                i = c
            end
            hk[i], hv[i] = lk, lv
        end
        return k, v
    end
    function H.size() return size end
    return H
end

-- Within one tile, node by node, from seeds { [node] = weight } (and their seconds): every node's
-- weight, seconds and the node it was reached from. reverse: the walk ends at the seeds (each step
-- costed the way you'd walk it). goal: stop once it's reached. yieldable: give way to the frame.
local function Search(m, f, t, seeds, secs0, reverse, goal, yieldable, heuristic)
    local dist, secs, from, done = {}, {}, {}, {}
    local H = Heap()
    for id, d in pairs(seeds) do
        dist[id], secs[id] = d, secs0 and secs0[id] or d
        H.push(d + (heuristic and heuristic(id) or 0), id)
    end
    local count, start = 0, debugprofilestop()
    while H.size() > 0 do
        local _, u = H.pop()
        if not done[u] then
            done[u] = true
            if u == goal then break end
            local du = dist[u]
            for _, l in ipairs(reverse and Into(m, u) or Links(m, u)) do
                local v = l[1]
                if floor(v / 65536) == t and not done[v] then
                    local wgt, s
                    if reverse then wgt, s = StepCost(m, f, v, u, l[2], l[3]) else wgt, s = StepCost(m, f, u, v, l[2], l[3]) end
                    if wgt then
                        local nd = du + wgt
                        local old = dist[v]
                        if not old or nd < old then
                            dist[v], secs[v], from[v] = nd, secs[u] + s, u
                            H.push(nd + (heuristic and heuristic(v) or 0), v)
                        end
                    end
                end
            end
            count = count + 1
            if yieldable and count % 200 == 0 and debugprofilestop() - start > (G.rush and RUSH or BUDGET) then
                coroutine.yield()
                start = debugprofilestop()
            end
        end
    end
    return { dist = dist, secs = secs, from = from }
end

-- ---------------------------------------------------------------------------------------------
-- Doors
-- ---------------------------------------------------------------------------------------------

-- A map's doors, unpacked the first time: per tile its doors' nodes and the times between them;
-- the links between tiles; door ids 1..n.
Doors = function(m)
    if m.doors then return m.doors end
    local D = { node = {}, tile = {}, pos = {}, of = {}, mat = {}, base = {}, size = {}, out = {}, into = {},
        jump = {}, jumpIn = {} }
    local id = 0
    for t, s in pairs(m.d.doors) do
        local raw = Unpack(s)
        if raw then
            local k = raw:byte(1)
            D.base[t], D.size[t], D.mat[t] = id, k, { raw = raw, o = 2 + 2 * k }
            for j = 1, k do
                id = id + 1
                local node = Id(t, U16(raw, 2 + 2 * (j - 1)) + 1)
                D.node[id], D.tile[id], D.pos[id] = node, t, j
                D.of[node] = id
            end
        end
    end
    D.count = id
    local raw = Unpack(m.d.cross)
    for r = 0, (m.d.crossCount or 0) - 1 do
        local o = r * 15 + 1
        local ta, da = U16(raw, o), raw:byte(o + 2)
        local tb, db = U16(raw, o + 3), raw:byte(o + 5)
        local kind = raw:byte(o + 6)
        local walk, swim, fixed = U16(raw, o + 7) / 10, U16(raw, o + 9) / 10, U16(raw, o + 13) / 10
        local a, b = D.base[ta] and D.base[ta] + da + 1, D.base[tb] and D.base[tb] + db + 1
        if a and b then
            D.out[a] = D.out[a] or {}
            D.into[b] = D.into[b] or {}
            table.insert(D.out[a], { b, walk, swim, fixed })
            table.insert(D.into[b], { a, walk, swim, fixed })
            if kind == 3 then
                local na, nb = D.node[a], D.node[b]
                D.jump[na] = D.jump[na] or {}
                D.jumpIn[nb] = D.jumpIn[nb] or {}
                table.insert(D.jump[na], { nb, fixed })
                table.insert(D.jumpIn[nb], { na, fixed })
            end
        end
    end
    m.doors = D
    return D
end

local TileHazard -- below

-- Seconds across a tile from door a to door b (same tile), at the field's speeds; nil: no way.
local function Inner(D, f, a, b)
    local t = D.tile[a]
    local M, k = D.mat[t], D.size[t]
    local o = M.o + ((D.pos[a] - 1) * k + (D.pos[b] - 1)) * 4
    local walk = U16(M.raw, o)
    if walk == 65535 then return nil end
    local swim = U16(M.raw, o + 2)
    if swim > 0 and f.swim <= 0 then return nil end
    return (walk / 10 * RUN / f.speed + (swim > 0 and swim / 10 * SWIM / f.swim or 0)) * TileHazard(f.m, f, t)
end

-- ---------------------------------------------------------------------------------------------
-- Hazards: zones well above your level, and the other faction's towns
-- ---------------------------------------------------------------------------------------------

-- Ground in a zone at least LEVEL_GAP levels above you (its quests' lower quarter, nav_places.py)
-- weighs ZONE_WEIGHT times more, within TOWN_RADIUS yards of the other faction's towns
-- TOWN_WEIGHT times: a walk goes round them when it can. Never the zone (or town) you start in or
-- are going to, and never a capital. Times stay real; only the choice of way changes.
local LEVEL_GAP = 4
local ZONE_WEIGHT = 4
local TOWN_WEIGHT = 6
local TOWN_RADIUS = 150

-- The zone of a global cell (its place in the map's zones), or 0.
local function ZoneAt(m, gr, gc)
    local t, c = CellAt(gr, gc)
    m.zoneOf = m.zoneOf or {}
    local z = m.zoneOf[t]
    if z == nil then
        local s = m.d.zoneOf and m.d.zoneOf[t]
        z = s and Unpack(s) or false
        m.zoneOf[t] = z
    end
    if not z then return 0 end
    local r, cc = floor(c / 64), c % 64
    return z:byte(floor(r / 4) * 16 + floor(cc / 4) + 1) or 0
end

-- The other faction's towns on this map (ns.Towns), as cells: { [cell key] = town number }.
local function EnemyCells(m, faction)
    if m.enemyFor == faction then return m.enemy end
    local cells = {}
    local mine = faction == "Alliance" and "A" or faction == "Horde" and "H" or nil
    if mine and type(ns.Towns) == "table" then
        local r = math.ceil(TOWN_RADIUS / m.fine)
        for k, town in ipairs(ns.Towns) do
            local side = town[5]
            if side == "A" or side == "H" then
                if side ~= mine then
                    local c, n, w = ns.Nav:World({ mapID = town[2], x = town[3], y = town[4] })
                    if c == m.continent then
                        local gr, gc = floor((m.max - n) / m.fine), floor((m.max - w) / m.fine)
                        for dr = -r, r do
                            for dc = -r, r do
                                if (dr * dr + dc * dc) * m.fine * m.fine <= TOWN_RADIUS * TOWN_RADIUS then
                                    cells[CellKey(gr + dr, gc + dc)] = k
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    m.enemy, m.enemyFor = cells, faction
    return cells
end

-- How much more a step onto cell (gr, gc) weighs for field f (1: no more).
Hazard = function(m, f, gr, gc)
    local hz = f.hz
    if not hz then return 1 end
    local wt = 1
    local zi = ZoneAt(m, gr, gc)
    if zi > 0 and not hz.exempt[zi] then
        local z = m.d.zones and m.d.zones[zi]
        if z and z[3] == 0 and z[2] > 0 and z[2] >= hz.level + LEVEL_GAP then wt = ZONE_WEIGHT end
    end
    local town = hz.enemy[CellKey(gr, gc)]
    if town and not hz.exemptTown[town] then wt = math.max(wt, TOWN_WEIGHT) end
    return wt
end

-- A tile's crossing weight for field f: its chunks' weights, averaged (worked out once a field).
TileHazard = function(m, f, t)
    local hz = f.hz
    if not hz then return 1 end
    local v = hz.tiles[t]
    if v then return v end
    local ty, tx = floor(t / 64), t % 64
    local sum = 0
    for r = 0, 15 do
        for c = 0, 15 do sum = sum + Hazard(m, f, ty * 64 + r * 4 + 2, tx * 64 + c * 4 + 2) end
    end
    v = sum / 256
    hz.tiles[t] = v
    return v
end

-- Your level, or nil when the game won't say.
local function Level()
    local lv = UnitLevel and UnitLevel("player")
    if type(lv) ~= "number" or (issecretvalue and issecretvalue(lv)) then return nil end
    return lv
end

-- A field's hazards: your level and faction, and what's exempt (where it starts and is headed).
local function Hazards(m, src, goal)
    local lv = Level()
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    if not lv and not faction then return nil end
    local hz = { level = lv or 999, exempt = {}, exemptTown = {}, tiles = {}, enemy = EnemyCells(m, faction) }
    local function Exempt(gr, gc)
        local z = ZoneAt(m, gr, gc)
        if z > 0 then hz.exempt[z] = true end
        local town = hz.enemy[CellKey(gr, gc)]
        if town then hz.exemptTown[town] = true end
    end
    local _, _, _, _, gr, gc = Where(m, src)
    if gr then Exempt(gr, gc) end
    if goal then Exempt(floor((m.max - goal[1]) / m.fine), floor((m.max - goal[2]) / m.fine)) end
    return hz
end

-- ---------------------------------------------------------------------------------------------
-- Places: the walk between flight masters, docks and towns, baked (nav_places.py, nav_walks.mjs)
-- ---------------------------------------------------------------------------------------------

local PLACE_NEAR = 60 -- yards from a place a point may be to count as it

-- The fixed place at a world point (within PLACE_NEAR yards): its number, or nil.
function G:Place(continent, n, w)
    local m = Map(continent)
    if not (m and m.d.places) then return nil end
    local best, bd
    for i, p in ipairs(m.d.places) do
        local d = (p[3] - n) ^ 2 + (p[4] - w) ^ 2
        if d <= PLACE_NEAR * PLACE_NEAR and (not bd or d < bd) then best, bd = i, d end
    end
    return best
end

-- Seconds walking from place i to place j at your speeds (lifts, portals and the tram included),
-- or nil when there's no way on foot.
function G:PlaceWalk(continent, i, j, speed, swim)
    local m = Map(continent)
    local d = m and m.d
    if not (d and d.walks and i and j) then return nil end
    if i == j then return 0 end
    m.walks = m.walks or Unpack(d.walks)
    local np = #d.places
    local o = ((i - 1) * np + (j - 1)) * 6 + 1
    local wv, sv, fv = U16(m.walks, o), U16(m.walks, o + 2), U16(m.walks, o + 4)
    if wv == 65535 then return nil end
    if sv > 0 and (swim or 0) <= 0 then return nil end
    return wv / 10 * RUN / speed + (sv > 0 and sv / 10 * SWIM / swim or 0) + fv / 10
end

-- ---------------------------------------------------------------------------------------------
-- Fields
-- ---------------------------------------------------------------------------------------------

local fields, jobs, queue, listeners = {}, {}, {}, {}
local TileField, LocateReached, Advance -- below

-- Whether every door of tile t the field can reach is settled (the field's search is past them).
local function TileSettled(f, D, t)
    for j = 1, D.size[t] or 0 do
        if not f.doorDone[D.base[t] + j] then return false end
    end
    return true
end

-- The door search, carried on from where it stopped: until it's done, or, with a goal tile, once
-- that tile's doors are settled and the search has gone MARGIN past them (seconds: twice the
-- goal's, at least a few minutes). Every place a plan weighs is near the way to the goal, or no
-- quicker than going there. yieldable: give way to the frame now and then (in the background).
local MARGIN_MIN = 180
function Advance(f, goal, yieldable, untilTile)
    local D = Doors(f.m)
    local dist, from, done, H = f.door, f.doorFrom, f.doorDone, f.H
    local stopAt
    local count, start = 0, debugprofilestop()
    while H.size() > 0 do
        local k, a = H.pop()
        if not done[a] then
            if stopAt and k > stopAt then
                H.push(k, a)
                f.partial = true
                return
            end
            done[a] = true
            local da = dist[a]
            local ta = D.tile[a]
            -- Across its tile to its other doors.
            for j = 1, D.size[ta] do
                local b = D.base[ta] + j
                if b ~= a and not done[b] then
                    local c = f.reverse and Inner(D, f, b, a) or Inner(D, f, a, b)
                    if c then
                        local nd = da + c
                        if not dist[b] or nd < dist[b] then
                            dist[b], from[b] = nd, a
                            H.push(nd, b)
                        end
                    end
                end
            end
            -- Into the next tile.
            for _, e in ipairs((f.reverse and D.into[a] or D.out[a]) or NONE) do
                local b = e[1]
                if not done[b] and (e[3] == 0 or f.swim > 0) then
                    local c = (e[4] or 0) + e[2] * RUN / f.speed + (e[3] > 0 and e[3] * SWIM / f.swim or 0)
                    local nd = da + c
                    if not dist[b] or nd < dist[b] then
                        dist[b], from[b] = nd, a
                        H.push(nd, b)
                    end
                end
            end
            if untilTile and ta == untilTile and TileSettled(f, D, untilTile) then
                f.partial = H.size() > 0
                return
            end
            if goal and not stopAt and ta == goal and TileSettled(f, D, goal) then
                stopAt = math.max(da * 2, da + MARGIN_MIN)
            end
            count = count + 1
            if yieldable and count % 200 == 0 and debugprofilestop() - start > (G.rush and RUSH or BUDGET) then
                coroutine.yield()
                start = debugprofilestop()
            end
        end
    end
    f.partial = false
end

-- The field's search carried on until tile t's doors are settled (a place past where it stopped).
local function Ensure(f, t)
    if f.partial and not TileSettled(f, Doors(f.m), t) then Advance(f, nil, false, t) end
end

local function Work(f)
    local m = f.m
    local D = Doors(m)
    local t = floor(f.src / 65536)
    -- 1. Your tile, node by node.
    f.home = Search(m, f, t, { [f.src] = 0 }, nil, f.reverse, nil, true)
    -- 2. The doors of the map, from your tile's doors: until the goal's tile is settled and a margin
    -- past it (Advance); the rest when something asks (Ensure).
    f.door, f.doorFrom, f.doorDone, f.H = {}, {}, {}, Heap()
    for j = 1, D.size[t] or 0 do
        local id = D.base[t] + j
        local d = f.home.dist[D.node[id]]
        if d then
            f.door[id], f.doorFrom[id] = d, 0
            f.H.push(d, id)
        end
    end
    Advance(f, f.goalTile, true)
end

local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self)
    -- Nothing in combat: the frames are yours. It carries on when the fight's over.
    if InCombatLockdown and InCombatLockdown() then return end
    local key = queue[1]
    local job = key and jobs[key]
    if not job then
        if key then table.remove(queue, 1) else self:Hide() end
        return
    end
    local ok, err = coroutine.resume(job.co)
    if not ok then
        jobs[key] = nil
        table.remove(queue, 1)
        geterrorhandler()("Waypoint nav: " .. tostring(err))
    elseif coroutine.status(job.co) == "dead" then
        job.field.ready = true
        fields[key] = job.field
        jobs[key] = nil
        table.remove(queue, 1)
        for _, fn in ipairs(listeners) do
            local ok2, err2 = pcall(fn, key)
            if not ok2 then geterrorhandler()(err2) end
        end
    end
end)

local function Settings(opts)
    return {
        speed = math.max(1, floor(opts.speed * 10 + 0.5) / 10),
        swim = floor((opts.swim or 0) * 10 + 0.5) / 10,
        safe = opts.safe and true or false,
        maxDrop = floor((opts.maxDrop or HARMLESS) * 10 + 0.5) / 10,
        climb = opts.climb or 1,
        offroad = floor((opts.offroad or 1) * 100 + 0.5) / 100,
        level = Level() or 0,   -- a new level changes which zones are above you
    }
end

local function Fits(f, continent, n, w, o, slack, src)
    if not f or f.version ~= G.version or f.continent ~= continent then return false end
    for k, v in pairs(o) do
        if f[k] ~= v then return false end
    end
    if slack == 0 then return f.src == src end
    local dn, dw = f.n - n, f.w - w
    -- Moved a little: the field still serves, but only if it was worked out from your floor (or
    -- its own search reached it). One from a floor you're not on (a walkway under you, before your
    -- floor was settled) leads through walls from where you really are: worked out again.
    return floor(f.src / 65536) == floor(src / 65536) and dn * dn + dw * dw <= MOVE_YARDS * MOVE_YARDS
        and (f.src == src or (f.home ~= nil and f.home.dist[src] ~= nil))
end

-- ---------------------------------------------------------------------------------------------
-- Your floor: where floors are stacked (a city's streets under its bridges and roofs), which one
-- you're on. The game gives addons your place on the map but not your height (UnitPosition's
-- height is 0 on most clients; when it isn't, that settles it). So it's tracked as you move: a few
-- floors you could be on are kept, and each is followed along the map's links as you go; one that
-- can't follow where you walked (a roof ends where the street goes on, a ledge isn't linked to the
-- way you went) drops out. Starting afresh (logging in, a port, a long jump), the floors there are
-- ranked: ones that lead nowhere (a sealed pocket under the city) last, ones the target can be
-- reached from first, then frequented ones (where creatures and objects stand: a city's streets,
-- not the mountain over it), then the lowest. A few steps settle it.
-- ---------------------------------------------------------------------------------------------

local TRACK_KEEP = 8      -- floors kept as candidates
local TRACK_FAR = 60      -- yards moved since the last look past which it starts afresh
local SEALED_REACH = 300  -- nodes a floor reaches inside its tile to count as leading somewhere
local here                -- { c, n, w, node, h, cands = { node, ... }, z }

-- Your height from the game, when it gives one (nil when it's hidden or always 0).
local function PlayerZ()
    if not UnitPosition then return nil end
    local ok, _, _, z = pcall(UnitPosition, "player")
    if not ok or type(z) ~= "number" or (issecretvalue and issecretvalue(z)) or z == 0 then return nil end
    return z
end

-- Whether a floor leads nowhere: from it, inside its tile, neither a door nor many nodes are reached.
local function Sealed(m, id)
    m.sealed = m.sealed or {}
    local v = m.sealed[id]
    if v ~= nil then return v end
    local D = Doors(m)
    local t = floor(id / 65536)
    local seen, queue, head, count = { [id] = true }, { id }, 1, 1
    v = true
    while v and queue[head] do
        local u = queue[head]
        head = head + 1
        if D.of[u] then v = false break end
        for _, l in ipairs(Links(m, u)) do
            local x = l[1]
            if not seen[x] then
                if floor(x / 65536) ~= t then v = false break end
                seen[x], count = true, count + 1
                queue[#queue + 1] = x
            end
        end
        if count >= SEALED_REACH then v = false end
    end
    m.sealed[id] = v
    return v
end

-- The floors of the cell at a world point (out to 2 cells when it has none), lava left out.
local function FloorsAt(m, n, w)
    local gr, gc = floor((m.max - n) / m.fine), floor((m.max - w) / m.fine)
    for ring = 0, 2 do
        local out = {}
        for dr = -ring, ring do
            for dc = -ring, ring do
                if ring == 0 or abs(dr) == ring or abs(dc) == ring then
                    local T, f, k = CellNodes(m, gr + dr, gc + dc)
                    if T then
                        for j = f, f + k - 1 do
                            if T.kind[j] ~= 2 then out[#out + 1] = Id(T.t, j) end
                        end
                    end
                end
            end
        end
        if #out > 0 then return out end
    end
    return {}
end

-- The nodes of (n, w)'s cell you can get to from node `from` within `reach` yards along the links
-- (walks, swims and drops; not lifts or portals: those you'd notice).
local function Follow(m, from, n, w, reach)
    local gr, gc = floor((m.max - n) / m.fine), floor((m.max - w) / m.fine)
    local out, dist, queue, head = {}, { [from] = 0 }, { from }, 1
    while queue[head] and head <= 600 do
        local u = queue[head]
        head = head + 1
        local un, uw, _, _, ur, uc = Where(m, u)
        if ur == gr and uc == gc then out[#out + 1] = u end
        for _, l in ipairs(Links(m, u)) do
            local x = l[1]
            if dist[x] == nil and l[2] ~= 3 then
                local xn, xw = Where(m, x)
                if xn then
                    local d = dist[u] + sqrt((xn - un) ^ 2 + (xw - uw) ^ 2)
                    if d <= reach then
                        dist[x] = d
                        queue[#queue + 1] = x
                    end
                end
            end
        end
    end
    return out
end

-- How likely you're on floor id: higher is likelier (see above). prevH: the floor you were on.
local function FloorScore(m, id, prevH)
    local _, _, h, kind = Where(m, id)
    local t, i = Split(id)
    local T = Tile(m, t)
    local s = 0
    if Sealed(m, id) then s = s - 1000 end
    local target = fields.target
    if target and target.nav and target.m == m and target.door then
        local tf = TileField(target, t)
        if tf.dist[id] then s = s + 200 end
    end
    local swimming = IsSwimming and IsSwimming()
    if not (issecretvalue and issecretvalue(swimming)) and (swimming and true or false) == (kind == 1) then s = s + 100 end
    if T.busy[i] then s = s + 300 end -- where creatures and objects stand: where people are
    if prevH then s = s - abs(h - prevH) * 2 else s = s - h * 0.05 end
    return s
end

-- Your floor at (n, w) on continent: the node, tracked from where you were.
local function Track(m, continent, n, w)
    local prev = here and here.c == continent and here or nil
    local moved = prev and sqrt((prev.n - n) ^ 2 + (prev.w - w) ^ 2)
    local z = PlayerZ()
    local cands
    if z then
        local best, bd
        for _, id in ipairs(FloorsAt(m, n, w)) do
            local d = abs(select(3, Where(m, id)) - z)
            if not bd or d < bd then best, bd = id, d end
        end
        cands = best and { best } or nil
    elseif prev and prev.cands and moved < TRACK_FAR then
        local seen = {}
        cands = {}
        for _, c in ipairs(prev.cands) do
            for _, x in ipairs(Follow(m, c, n, w, moved * 1.5 + 12)) do
                if not seen[x] then
                    seen[x] = true
                    cands[#cands + 1] = x
                end
            end
        end
        if #cands == 0 then cands = nil end
    end
    cands = cands or FloorsAt(m, n, w)
    if #cands == 0 then return nil end
    local scored = {}
    for _, id in ipairs(cands) do scored[#scored + 1] = { id, FloorScore(m, id, prev and prev.h) } end
    table.sort(scored, function(a, b) return a[2] > b[2] end)
    local keep = {}
    for k = 1, math.min(TRACK_KEEP, #scored) do keep[k] = scored[k][1] end
    local best = keep[1]
    here = { c = continent, n = n, w = w, node = best, h = select(3, Where(m, best)), cands = keep, z = z }
    return best
end

-- Your tracked floor, when (n, w) is where you were last placed (within a few yards).
local function HereNode(continent, n, w)
    if here and here.c == continent and (here.n - n) ^ 2 + (here.w - w) ^ 2 < 100 then return here.node end
end

function G:Field(key, continent, n, w, opts)
    local m = Map(continent)
    if not m then return Old:Field(key, continent, n, w, opts) end
    local src
    local mine = fields.here
    if key == "here" then
        src = Track(m, continent, n, w)
    elseif mine and mine.nav and mine.continent == continent and mine.version == G.version then
        src = LocateReached(mine, n, w)
    else
        src = Locate(m, n, w)
    end
    if not src then return nil end
    local o = Settings(opts)
    local slack = (opts.slack or 0) > 0 and 1 or 0
    local f = fields[key]
    if Fits(f, continent, n, w, o, slack, src) then return f end
    local job = jobs[key]
    if job and Fits(job.field, continent, n, w, o, slack, src) then return nil end
    -- Where the plan is headed (the target, for a field from you; you, for one to the target): its
    -- tile is where the door search may stop (Advance).
    local goal = opts.goal or opts.toward
    local goalTile = goal and CellAt(floor((m.max - goal[1]) / m.fine), floor((m.max - goal[2]) / m.fine))
    local field = { nav = true, continent = continent, m = m, src = src, n = n, w = w, reverse = opts.reverse and true or false,
        version = G.version, tilesDone = {}, steps = {}, goalTile = goalTile, hz = Hazards(m, src, goal) }
    for k, v in pairs(o) do field[k] = v end
    if not jobs[key] then
        if opts.reverse and not opts.later then table.insert(queue, 1, key) else queue[#queue + 1] = key end
    end
    jobs[key] = { field = field, co = coroutine.create(function() Work(field) end) }
    driver:Show()
    return nil
end

function G:Partial(key)
    local job = jobs[key]
    local f = job and job.field or fields[key]
    if f and f.nav then return nil end
    return Old:Partial(key)
end

function G:Settled(f, n, w)
    if f and f.nav then return false end
    return Old:Settled(f, n, w)
end

function G:Busy() return queue[1] ~= nil or Old:Busy() end
function G:Working(key) return jobs[key] ~= nil or Old:Working(key) end
function G:OnReady(fn)
    listeners[#listeners + 1] = fn
    Old:OnReady(fn)
end

-- A tile walked node by node from its doors, as the field reached them (cached on the field).
TileField = function(f, t)
    local tf = f.tilesDone[t]
    if tf then return tf end
    local m, D = f.m, Doors(f.m)
    if t == floor(f.src / 65536) then
        tf = f.home
    else
        Ensure(f, t)
        local seeds = {}
        for j = 1, D.size[t] or 0 do
            local id = D.base[t] + j
            if f.door[id] then seeds[D.node[id]] = f.door[id] end
        end
        tf = Search(m, f, t, seeds, nil, f.reverse)
        tf.seeded = seeds
    end
    f.tilesDone[t] = tf
    return tf
end

-- The node at a world point the field reaches: of the floors in its cell (or the nearest cells, out
-- to 3), those the field gets to, the one nearest the ground's height. A town inside a mountain
-- (Ironforge) has the mountainside over it; this picks the floor you can get to. None reached: Locate.
LocateReached = function(f, n, w)
    local m = f.m
    -- Where you stand: your tracked floor (or the next likeliest still in play) when the field
    -- reaches it, not a guess from the ground's height (a walkway under the one you're on).
    if HereNode(m.continent, n, w) then
        for _, id in ipairs(here.cands or { here.node }) do
            if TileField(f, floor(id / 65536)).dist[id] then return id end
        end
    end
    local gr, gc = floor((m.max - n) / m.fine), floor((m.max - w) / m.fine)
    local hint = Old:Height(m.continent, n, w)
    for ring = 0, 3 do
        local best, bd
        for dr = -ring, ring do
            for dc = -ring, ring do
                if ring == 0 or abs(dr) == ring or abs(dc) == ring then
                    local T, fi, k = CellNodes(m, gr + dr, gc + dc)
                    if T then
                        local tf = TileField(f, T.t)
                        for j = fi, fi + k - 1 do
                            local id = Id(T.t, j)
                            if T.kind[j] ~= 2 and tf.dist[id] then
                                local d = (hint and abs(T.h[j] - hint) or 0) + (abs(dr) + abs(dc)) * m.fine
                                if not bd or d < bd then best, bd = id, d end
                            end
                        end
                    end
                end
            end
        end
        if best then return best end
    end
    return Locate(m, n, w)
end

-- Seconds from the field's source to a world point (it's reverse: from the point to the source),
-- or nil. Exact in tiles worked out node by node; elsewhere the nearest door plus the straight way.
function G:Cost(f, n, w)
    if not (f and f.nav) then return Old:Cost(f, n, w) end
    local m = f.m
    local p = Locate(m, n, w)
    if not p then return nil end
    local t = floor(p / 65536)
    local tf = f.tilesDone[t]
    if tf then
        p = LocateReached(f, n, w)
        return p and TileField(f, floor(p / 65536)).secs[p]
    end
    local D = Doors(m)
    Ensure(f, t)
    local pn, pw = Where(m, p)
    local best
    for j = 1, D.size[t] or 0 do
        local id = D.base[t] + j
        local d = f.door[id]
        if d then
            local dn, dw = Where(m, D.node[id])
            local c = d + sqrt((dn - pn) ^ 2 + (dw - pw) ^ 2) * 1.2 / f.speed
            if not best or c < best then best = c end
        end
    end
    return best
end

-- The quickest way from node a to node b inside tile t, node by node (A*): { a, ..., b }, or nil.
local function Walk(f, t, a, b, yieldable)
    local m = f.m
    local bn, bw = Where(m, b)
    local per = 1 / math.max(f.speed, f.swim)
    local r = Search(m, f, t, { [a] = 0 }, nil, false, b, yieldable, function(id)
        local n, w = Where(m, id)
        return sqrt((n - bn) ^ 2 + (w - bw) ^ 2) * per
    end)
    if not r.dist[b] then return nil end
    local out, x = {}, b
    while x do
        table.insert(out, 1, x)
        x = r.from[x]
    end
    return out
end

-- Tiles crossed door to door, walked out node by node in the background once a path has needed
-- them (Nodes ran out of its budget): { field, tile, from, to, key } each. Listeners hear "refine"
-- when they're done, and plan again with the whole way.
local refining = {}

local function QueueRefine(f, t, a, b, key)
    refining[#refining + 1] = { f, t, a, b, key }
    if jobs.refine then return end
    jobs.refine = { field = {}, co = coroutine.create(function()
        while refining[1] do
            local r = table.remove(refining, 1)
            local rf = r[1]
            if rf.steps[r[5]] == nil then rf.steps[r[5]] = Walk(rf, r[2], r[3], r[4], true) or false end
        end
    end) }
    queue[#queue + 1] = "refine"
    driver:Show()
end

-- The nodes from a point back to the field's source (the way the field reached it), each with its
-- seconds from the source. The tiles between are walked out node by node, nearest you first, while
-- the budget lasts; past it they're joined door to door for now (and walked out in the background).
local function Nodes(f, p)
    local m, D = f.m, Doors(f.m)
    local t = floor(p / 65536)
    local tf = TileField(f, t)
    if not tf.dist[p] then return nil end
    local out = {}
    local function Add(id, s) out[#out + 1] = { id, s } end
    -- In the point's tile: back to the door it came in by (or the source).
    local x = p
    while x do
        Add(x, tf.secs[x])
        local nx = tf.from[x]
        if not nx then break end
        x = nx
    end
    if x == f.src then return out end
    local door = D.of[x]
    if not door then return out end
    -- The doors back to the source's tile.
    local hops = {}
    while door and door ~= 0 do
        local prev = f.doorFrom[door]
        hops[#hops + 1] = { prev or 0, door }
        if not prev or prev == 0 then break end
        door = prev
    end
    -- Walk out the tiles crossed, nearest you first: you're the source of a field from you (the end
    -- of the list), the point of one to the target (its start).
    local start = debugprofilestop()
    local from, to, step = 1, #hops, 1
    if not f.reverse then from, to, step = #hops, 1, -1 end
    for k = from, to, step do
        local prev, dr = hops[k][1], hops[k][2]
        if prev ~= 0 and D.tile[prev] == D.tile[dr] then
            local a, b = D.node[prev], D.node[dr]
            local key = a .. ">" .. b
            if f.steps[key] == nil then
                local ta, tb = a, b
                if f.reverse then ta, tb = b, a end
                if debugprofilestop() - start < REFINE_BUDGET then
                    f.steps[key] = Walk(f, D.tile[prev], ta, tb) or false
                else
                    f.coarse = true
                    QueueRefine(f, D.tile[prev], ta, tb, key)
                end
            end
        end
    end
    for _, hop in ipairs(hops) do
        local prev, dr = hop[1], hop[2]
        if prev == 0 then
            -- Into the source's tile: back to the source through it.
            local y = f.home.from[D.node[dr]]
            while y do
                Add(y, f.home.secs[y])
                y = f.home.from[y]
            end
            return out
        end
        local a, b = D.node[prev], D.node[dr]
        local way = D.tile[prev] == D.tile[dr] and f.steps[a .. ">" .. b]
        if way then
            -- Back from b to a: b is there already.
            local ds, dp = f.door[dr] or 0, f.door[prev] or 0
            local nn = #way
            for k = nn - 1, 1, -1 do
                local id = f.reverse and way[nn - k + 1] or way[k]
                Add(id, dp + (ds - dp) * (k - 1) / math.max(1, nn - 1))
            end
        else
            Add(a, f.door[prev])
        end
    end
    return out
end

-- Points straight enough to leave out: a point within TOLERANCE yards of the line between the ones
-- kept either side. Where you go into or out of water, and both ends of a drop, are always kept.
local TOLERANCE = 2.5

local function Simplify(pts, keep)
    local n = #pts
    if n <= 2 then return pts end
    keep[1], keep[n] = true, true
    local function Far(i, j)
        local a, b = pts[i], pts[j]
        local dn, dw = b.n - a.n, b.w - a.w
        local len = sqrt(dn * dn + dw * dw)
        local best, bi = TOLERANCE, nil
        for k = i + 1, j - 1 do
            local p = pts[k]
            local d
            if len < 0.01 then
                d = sqrt((p.n - a.n) ^ 2 + (p.w - a.w) ^ 2)
            else
                d = abs((p.n - a.n) * dw - (p.w - a.w) * dn) / len
            end
            if d > best then best, bi = d, k end
        end
        return bi
    end
    local stack, last = {}, 1
    for k = 2, n do
        if keep[k] then
            stack[#stack + 1] = { last, k }
            last = k
        end
    end
    while #stack > 0 do
        local seg = table.remove(stack)
        local k = Far(seg[1], seg[2])
        if k then
            keep[k] = true
            stack[#stack + 1] = { seg[1], k }
            stack[#stack + 1] = { k, seg[2] }
        end
    end
    local out = {}
    for k = 1, n do
        if keep[k] then out[#out + 1] = pts[k] end
    end
    return out
end

-- Path(f, n, w): the points from a world point back to the field's source, the way the field reached
-- it: { { n, w, water, face, h, t = seconds from the source, node } } in that order.
function G:Path(f, n, w)
    if not (f and f.nav) then return Old:Path(f, n, w) end
    local m = f.m
    local p = LocateReached(f, n, w)
    if not p then return nil end
    local nodes = Nodes(f, p)
    if not nodes then return nil end
    local pts = {}
    for k, e in ipairs(nodes) do
        local pn, pw, h, kind = Where(m, e[1])
        pts[k] = { n = pn, w = pw, water = kind == 1, face = false, h = h, t = e[2], node = e[1] }
    end
    -- Each step's way (walking order: a field from you has the source behind, so b then a; one to the
    -- target has it ahead, a then b); drops' ends and water's edges are kept.
    local keep, drop = {}, {}
    for k = 2, #pts do
        local a, b = pts[k - 1], pts[k]
        local wu, wv = f.reverse and a or b, f.reverse and b or a
        for _, l in ipairs(Links(m, wu.node)) do
            if l[1] == wv.node then
                if l[2] == 2 then
                    drop[k] = l[3]
                    keep[k - 1], keep[k] = true, true
                end
                break
            end
        end
        if a.water ~= b.water then keep[k - 1], keep[k] = true, true end
    end
    local out = Simplify(pts, keep)
    -- The way each step of the result goes, for G:Step (a few thousand kept, then started again).
    if not m.stepAt or m.stepCount > 20000 then m.stepAt, m.stepCount = {}, 0 end
    local idx = {}
    for k, pt in ipairs(pts) do idx[pt] = k end
    for k = 2, #out do
        local a, b = out[k - 1], out[k]
        local ia, ib = idx[a], idx[b]
        local fall = ib == ia + 1 and drop[ib]
        local wu, wv = f.reverse and a or b, f.reverse and b or a
        m.stepAt[floor(wu.n) .. "," .. floor(wu.w) .. ">" .. floor(wv.n) .. "," .. floor(wv.w)] = fall and { "drop", fall } or { "walk", 0 }
        m.stepCount = m.stepCount + 1
    end
    return out
end

-- How a step between two points goes, the way you'd walk it: "walk", "drop" (and how far), or nil.
function G:Step(continent, n1, w1, n2, w2)
    local m = Map(continent)
    if not m then return Old:Step(continent, n1, w1, n2, w2) end
    local s = m.stepAt and m.stepAt[floor(n1) .. "," .. floor(w1) .. ">" .. floor(n2) .. "," .. floor(w2)]
    if s then return s[1], s[2] end
    local a = Locate(m, n1, w1)
    local b = a and Locate(m, n2, w2, select(3, Where(m, a)))
    if not (a and b) then return nil end
    if a == b then return "walk", 0 end
    for _, l in ipairs(Links(m, a)) do
        if l[1] == b then
            if l[2] == 2 then return "drop", l[3] end
            return "walk", 0
        end
    end
    return nil
end

function G:Height(continent, n, w)
    local m = Map(continent)
    if not m then return Old:Height(continent, n, w) end
    local p = HereNode(continent, n, w) or Locate(m, n, w)
    if not p then return Old:Height(continent, n, w) end
    return (select(3, Where(m, p)))
end

-- Whether a straight line between two points stays on ground you walk (or water, when it starts
-- in water) without a drop: cell by cell along the line, each step a link of the map.
function G:Clear(continent, n1, w1, n2, w2)
    local m = Map(continent)
    if not m then return Old:Clear(continent, n1, w1, n2, w2) end
    local a = HereNode(continent, n1, w1) or Locate(m, n1, w1)
    if not a then return false end
    local swimming = select(4, Where(m, a)) == 1
    local d = sqrt((n2 - n1) ^ 2 + (w2 - w1) ^ 2)
    local steps = math.ceil(d / (m.fine * 0.5))
    local cur = a
    local cr, cc = floor((m.max - n1) / m.fine), floor((m.max - w1) / m.fine)
    for i = 1, steps do
        local n, w = n1 + (n2 - n1) * i / steps, w1 + (w2 - w1) * i / steps
        local r, c = floor((m.max - n) / m.fine), floor((m.max - w) / m.fine)
        if r ~= cr or c ~= cc then
            local nxt
            for _, l in ipairs(Links(m, cur)) do
                local _, _, _, k, lr, lc = Where(m, l[1])
                if lr == r and lc == c and l[2] ~= 2 and (k == 1) == swimming then nxt = l[1] break end
            end
            if not nxt then return false end
            cur, cr, cc = nxt, r, c
        end
    end
    return true
end

-- The ways a path's points join are already the map's own: nothing to put in.
function G:Detail(continent, path)
    if Map(continent) then return path end
    return Old:Detail(continent, path)
end

-- ---------------------------------------------------------------------------------------------
-- Overrides: closed steps (RoadLog's blockers, "this way is blocked"), roads and cities
-- ---------------------------------------------------------------------------------------------

-- Keys are steps between cells (StepKey). A step key's two cells: who it's from and to.
function G:LinkKey(continent, n1, w1, n2, w2)
    local m = Map(continent)
    if not m then return Old:LinkKey(continent, n1, w1, n2, w2) end
    local a = CellKey(floor((m.max - n1) / m.fine), floor((m.max - w1) / m.fine))
    local b = CellKey(floor((m.max - n2) / m.fine), floor((m.max - w2) / m.fine))
    if a == b then return nil end
    return StepKey(a, b), StepKey(b, a)
end

-- A narrow pass: the map has its own (it sees every gap): nothing to open.
function G:SquareKeys(continent, n, w)
    if Map(continent) then return {} end
    return Old:SquareKeys(continent, n, w)
end

-- Every step between two neighbouring cells whose middles a wall from (n1, w1) to (n2, w2) runs between.
function G:CrossingKeys(continent, n1, w1, n2, w2)
    local m = Map(continent)
    if not m then return Old:CrossingKeys(continent, n1, w1, n2, w2) end
    local out = {}
    local function Side(pn, pw, qn, qw, xn, xw) return (qn - pn) * (xw - pw) - (qw - pw) * (xn - pn) end
    local ra, rb = floor((m.max - math.max(n1, n2)) / m.fine) - 1, floor((m.max - math.min(n1, n2)) / m.fine) + 1
    local ca, cb = floor((m.max - math.max(w1, w2)) / m.fine) - 1, floor((m.max - math.min(w1, w2)) / m.fine) + 1
    for r = ra, rb do
        for c = ca, cb do
            local an, aw = m.max - (r + 0.5) * m.fine, m.max - (c + 0.5) * m.fine
            for _, s in ipairs(STEPS) do
                local bn, bw = m.max - (r + s[1] + 0.5) * m.fine, m.max - (c + s[2] + 0.5) * m.fine
                local d1, d2 = Side(n1, w1, n2, w2, an, aw), Side(n1, w1, n2, w2, bn, bw)
                local d3, d4 = Side(an, aw, bn, bw, n1, w1), Side(an, aw, bn, bw, n2, w2)
                if d1 * d2 < 0 and d3 * d4 < 0 then
                    out[#out + 1] = StepKey(CellKey(r, c), CellKey(r + s[1], c + s[2]))
                end
            end
        end
    end
    return out
end

-- Only closed steps count here: steps you walked and narrow passes the map already has. Fields
-- worked out before are dropped only when what's closed changed.
-- Ground that changed (a way closed or opened, a road added) in some tiles: a field whose own tile
-- changed is worked out again; the others only forget their node-by-node work in those tiles. The
-- rest of what they've worked out stands, so nothing far away is redone (or redrawn).
local function Touch(m, tiles)
    if not next(tiles) then return end
    m.stepAt, m.stepCount = nil, 0
    local function Fix(f)
        if not (f and f.nav and f.m == m) then return end
        if tiles[floor(f.src / 65536)] then
            f.version = -1
            return
        end
        for t in pairs(tiles) do f.tilesDone[t] = nil end
        for key in pairs(f.steps) do
            local a = tonumber(key:match("^(%d+)>"))
            if a and tiles[floor(a / 65536)] then f.steps[key] = nil end
        end
    end
    for _, f in pairs(fields) do Fix(f) end
    for _, j in pairs(jobs) do Fix(j.field) end
end

local function TileOfCell(key)
    return (CellAt(floor(key / 4096), key % 4096))
end

-- Only closed steps count here: steps you walked and narrow passes the map already has.
function G:SetOverrides(continent, open, block)
    local m = Map(continent)
    if not m then return Old:SetOverrides(continent, open, block) end
    block = block or {}
    local tiles = {}
    local function Changed(key)
        tiles[TileOfCell(floor(key / 16777216))] = true
        tiles[TileOfCell(key % 16777216)] = true
    end
    for k in pairs(block) do if not m.block[k] then Changed(k) end end
    for k in pairs(m.block) do if not block[k] then Changed(k) end end
    m.block = block
    Touch(m, tiles)
end

-- Roads: the cells along each road step (from G:LinkKey's keys: the line between their two cells).
-- Steps off them weigh more by a field's offroad. Only the tiles whose roads changed are redone.
function G:SetRoads(continent, keys)
    local m = Map(continent)
    if not m then return Old:SetRoads(continent, keys) end
    local cells, count = {}, 0
    for key in pairs(keys or NONE) do
        local a, b = floor(key / 16777216), key % 16777216
        local ar, ac, br, bc = floor(a / 4096), a % 4096, floor(b / 4096), b % 4096
        local steps = math.max(abs(br - ar), abs(bc - ac), 1)
        for i = 0, steps do
            local k = CellKey(floor(ar + (br - ar) * i / steps + 0.5), floor(ac + (bc - ac) * i / steps + 0.5))
            if not cells[k] then cells[k], count = true, count + 1 end
        end
    end
    local old, tiles = m.roads or NONE, {}
    for k in pairs(cells) do if not old[k] then tiles[TileOfCell(k)] = true end end
    for k in pairs(old) do if not cells[k] then tiles[TileOfCell(k)] = true end end
    -- Roads at all or none: every step's weight changes.
    if (m.roads == nil) ~= (count == 0) then G.version = G.version + 1 end
    m.roads, m.roadCount = count > 0 and cells or nil, count
    Touch(m, tiles)
end

function G:SetCities(continent, rects, weight)
    local m = Map(continent)
    if not m then return Old:SetCities(continent, rects, weight) end
    local cells, count = {}, 0
    for _, rc in ipairs(rects) do
        local r1, r2 = floor((m.max - math.max(rc[1], rc[3])) / m.fine), floor((m.max - math.min(rc[1], rc[3])) / m.fine)
        local c1, c2 = floor((m.max - math.max(rc[2], rc[4])) / m.fine), floor((m.max - math.min(rc[2], rc[4])) / m.fine)
        for r = r1, r2 do
            for c = c1, c2 do
                cells[CellKey(r, c)] = true
                count = count + 1
            end
        end
    end
    if m.cityCount ~= count or m.cityOffroad ~= weight then G.version = G.version + 1 end
    m.cities, m.cityCount, m.cityOffroad = count > 0 and cells or nil, count, weight
end

function G:Has(continent) return Map(continent) ~= nil or Old:Has(continent) end
G.version = Old.version or 0

-- Where Waypoint thinks you are: "floor at 21 yd (of 4 it could be; height from the game)", for /way where.
function G:WhereText()
    if not here then return "not placed yet" end
    local m = Map(here.c)
    if not m then return "no walkable ground here" end
    local n = #FloorsAt(m, here.n, here.w)
    local text = ("on the floor at %.0f yd (%d floor%s here; %d still possible%s)"):format(here.h or 0, n, n == 1 and "" or "s",
        #(here.cands or {}), here.z and ("; the game says you're at " .. math.floor(here.z + 0.5)) or "; tracked as you move")
    -- The routes in use: which floor each starts from (yours, or one it reached yours from).
    for _, key in ipairs({ "here", "target" }) do
        local f = fields[key]
        if f and f.nav and f.m == m then
            local p = key == "here" and f.src or LocateReached(f, here.n, here.w)
            local h = p and select(3, Where(m, p))
            text = text .. ("; %s from the floor at %s"):format(key == "here" and "your way out starts" or "the way to the target starts",
                h and ("%.0f yd"):format(h) or "none (it can't reach you)")
        end
    end
    return text
end

-- For tests and /way debugging.
G.navDebug = { Map = Map, Locate = Locate, Where = Where, Links = Links, Into = Into, Doors = Doors, TileField = TileField,
    Nodes = Nodes, Tile = Tile, Sealed = function(m, id) return Sealed(m, id) end }
