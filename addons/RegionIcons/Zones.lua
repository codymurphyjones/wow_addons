local _, ns = ...

-- Which zones touch the one shown, and where a point of one of them lands on the map shown.
--
-- Neighbours are the zones of the shown zone's continent whose rectangle on it
-- (C_Map.GetMapRectOnMap) touches or overlaps the shown zone's. A continent shown: all its zones
-- with the "continent" option, else none. Any other map (the world, a dungeon): none.
--
-- A point is moved through the same rectangles Blizzard lays its zone maps out with: the source
-- zone's 0-1 point onto the continent, then into the shown map's 0-1. On OpenMap's stitched map,
-- the shared WorldMap.OnCanvas (past 0-1 too: the stitched view shows the zones round it).
local Z = {}
ns.Zones = Z

local TOUCH = 0.01          -- rectangles this close (in the shown zone's widths) touch

local function MapType(name, fallback)
    local t = Enum and Enum.UIMapType
    return t and t[name] or fallback
end

local function MapInfo(mapID)
    if not (mapID and C_Map and C_Map.GetMapInfo) then return nil end
    local ok, info = pcall(C_Map.GetMapInfo, mapID)
    return ok and info or nil
end
Z.MapInfo = MapInfo

function Z.IsContinent(mapID)
    local info = MapInfo(mapID)
    return info and info.mapType == MapType("Continent", 2) or false
end

local continentOf = {}
-- The continent a map is on (its uiMapID), or nil (cached).
function Z.ContinentOf(mapID)
    if not mapID then return nil end
    local cached = continentOf[mapID]
    if cached ~= nil then return cached or nil end
    local continent, id = MapType("Continent", 2), mapID
    local found = false
    for _ = 1, 10 do
        local info = MapInfo(id)
        if not info then break end
        if info.mapType == continent then found = id break end
        id = info.parentMapID
        if not id or id == 0 then break end
    end
    continentOf[mapID] = found
    return found or nil
end

local zonesOf = {}
-- Every zone on a continent: { uiMapID, ... } (cached).
function Z.ZonesOf(continentID)
    if zonesOf[continentID] then return zonesOf[continentID] end
    local out, zone = {}, MapType("Zone", 3)
    local ok, kids = pcall(C_Map.GetMapChildrenInfo, continentID, zone, true)
    if ok and type(kids) == "table" then
        for _, info in ipairs(kids) do
            if info.mapID and info.mapType == zone then out[#out + 1] = info.mapID end
        end
    end
    zonesOf[continentID] = out
    return out
end

local rects = {}
-- A map's rectangle on another (left, right, top, bottom), or nil (cached).
local function Rect(mapID, onMap)
    local key = mapID .. ">" .. onMap
    local r = rects[key]
    if r == nil then
        local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, mapID, onMap)
        if ok and minX and maxX and minY and maxY and maxX > minX and maxY > minY then
            r = { minX, maxX, minY, maxY }
        else
            r = false
        end
        rects[key] = r
    end
    if r then return r[1], r[2], r[3], r[4] end
end
Z.Rect = Rect

local neighbours = {}       -- host (and the continent option) -> { list, set }
local NONE = { {}, {} }

local function Build(host)
    local list = {}
    local info = MapInfo(host)
    if info and info.mapType == MapType("Continent", 2) then
        if ns.db and ns.db.continent then
            for _, z in ipairs(Z.ZonesOf(host)) do
                if z ~= host then list[#list + 1] = z end
            end
        end
    elseif info and info.mapType == MapType("Zone", 3) then
        local continent = Z.ContinentOf(host)
        local l, r, t, b
        if continent then l, r, t, b = Rect(host, continent) end
        if l then
            local gw, gh = (r - l) * TOUCH, (b - t) * TOUCH
            l, r, t, b = l - gw, r + gw, t - gh, b + gh
            for _, z in ipairs(Z.ZonesOf(continent)) do
                if z ~= host then
                    local zl, zr, zt, zb = Rect(z, continent)
                    if zl and zl <= r and zr >= l and zt <= b and zb >= t then list[#list + 1] = z end
                end
            end
        end
    end
    local set = {}
    for _, z in ipairs(list) do set[z] = true end
    return { list, set }
end

local function Entry(host)
    if not host then return NONE end
    local key = host .. (ns.db and ns.db.continent and ":c" or "")
    local e = neighbours[key]
    if not e then
        e = Build(host)
        neighbours[key] = e
    end
    return e
end

-- The zones touching host: { uiMapID, ... } (cached; don't change it).
function Z.Neighbours(host) return Entry(host)[1] end

-- Whether mapID is one of host's neighbours.
function Z.IsNeighbour(host, mapID) return Entry(host)[2][mapID] == true end

function Z.ClearCache()
    wipe(neighbours)
end

function Z.Stitched()
    return ns.WorldMap.Stitched()
end

-- Where a point (0-1) of the zone source lands on the map host shows, or nil off it. On the
-- stitched map past 0-1 too (OpenMap places it); on Blizzard's map only 0-1.
function Z.Place(source, x, y, host)
    if type(x) ~= "number" or type(y) ~= "number" or not (source and host) then return nil end
    if source == host then return x, y end
    if Z.Stitched() then return ns.WorldMap.OnCanvas(source, x, y, host) end
    local continent = Z.ContinentOf(host)
    if continent and Z.ContinentOf(source) == continent then
        local sl, sr, st, sb = Rect(source, continent)
        local hl, hr, ht, hb
        if host == continent then hl, hr, ht, hb = 0, 1, 0, 1 else hl, hr, ht, hb = Rect(host, continent) end
        if sl and hl then
            local px = (sl + x * (sr - sl) - hl) / (hr - hl)
            local py = (st + y * (sb - st) - ht) / (hb - ht)
            if px >= 0 and px <= 1 and py >= 0 and py <= 1 then return px, py end
            return nil
        end
    end
    return ns.WorldMap.Project(source, x, y, host)
end

-- ---------------------------------------------------------------------------------------------
-- Around you (the minimap): zones whose edge is within reach yards of you
-- ---------------------------------------------------------------------------------------------

local worldRects = {}       -- uiMapID -> { continent, n1, n2, w1, w2 } or false

-- A zone's rectangle in the world (continent, north and west ranges), cached.
local function WorldRect(mapID)
    if worldRects[mapID] ~= nil then return worldRects[mapID] end
    local WM = ns.WorldMap
    local c1, n1, w1 = WM.World(mapID, 0, 0)
    local c2, n2, w2 = WM.World(mapID, 1, 1)
    local r = false
    if c1 and c2 and c1 == c2 then
        r = { c1, math.min(n1, n2), math.max(n1, n2), math.min(w1, w2), math.max(w1, w2) }
    end
    worldRects[mapID] = r
    return r
end

-- Yards from (n, w) to a rectangle (0 inside it).
local function DistanceTo(r, n, w)
    local dn = n < r[2] and r[2] - n or (n > r[3] and n - r[3] or 0)
    local dw = w < r[4] and r[4] - w or (w > r[5] and w - r[5] or 0)
    return math.sqrt(dn * dn + dw * dw)
end

-- The zones other than yours whose edge is within reach yards of you (sorted uiMapIDs), and your
-- map; nil when you can't be placed (an instance).
function Z.NearPlayer(reach)
    local WM = ns.WorldMap
    local c, n, w, map = WM.Player()
    if not c then return nil end
    local continent = Z.ContinentOf(map)
    if not continent then return nil end
    local out = {}
    for _, zone in ipairs(Z.ZonesOf(continent)) do
        if zone ~= map then
            local r = WorldRect(zone)
            if r and r[1] == c and DistanceTo(r, n, w) <= reach then out[#out + 1] = zone end
        end
    end
    table.sort(out)
    return out, map
end

-- for the tests
function Z._Reset() wipe(neighbours) wipe(zonesOf) wipe(rects) wipe(continentOf) wipe(worldRects) end
