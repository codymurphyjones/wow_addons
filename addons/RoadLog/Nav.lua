local _, ns = ...
local C = ns.Compat

-- World positions, from the shared WorldMap.lua. World coordinates come from
-- C_Map.GetWorldPosFromMapPos, whose vector is (north, west) in yards on a continent.
local WM = ns.WorldMap
local Nav = {}
ns.Nav = Nav

-- You: continent, north, west, zone mapID; nil inside instances or when the map can't place you.
function Nav:Player() local c, n, w, m = WM.Player() return c, n, w, m end

-- Where a world point lands on onMap, as 0-1 fractions, or nil if it's off that map.
function Nav:Project(continent, n, w, onMap) return WM.ProjectWorld(continent, n, w, onMap) end

-- The continent a map belongs to, as the world-position APIs number it (nil if unknown).
function Nav:Continent(mapID) return WM.Continent(mapID) end

function Nav:ZoneName(mapID) return WM.ZoneName(mapID, "map %s")
end

local ZONE = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
local CONTINENT = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2

-- The first map of the given type at or above mapID (a town or a cave belongs to its zone).
local function Up(mapID, mapType)
    for _ = 1, 6 do
        local info = mapID and C.Call(C_Map.GetMapInfo, mapID)
        if not info then return nil end
        if info.mapType == mapType then return mapID end
        if info.mapType and info.mapType < mapType then return nil end -- went past it
        mapID = info.parentMapID
    end
end

function Nav:Zone(mapID) return Up(mapID, ZONE) end

-- The nearest zone that isn't fromZone to a world point, looking outward on the continent map in
-- rings STEP yards apart, up to REACH yards: its mapID, or nil.
local STEP, REACH, DIRECTIONS = 10, 500, 24
function Nav:NearestOtherZone(continent, n, w, fromZone)
    local map = Up(fromZone, CONTINENT)
    if not (map and C_Map.GetMapInfoAtPosition) then return nil end
    for r = STEP, REACH, STEP do
        local best, bestCount = nil, 0
        local seen = {}
        for k = 0, DIRECTIONS - 1 do
            local a = 2 * math.pi * k / DIRECTIONS
            local x, y = self:Project(continent, n + r * math.cos(a), w + r * math.sin(a), map)
            local info = x and C.Call(C_Map.GetMapInfoAtPosition, map, x, y)
            local zone = info and Up(info.mapID, ZONE)
            if zone and zone ~= fromZone then
                -- The zone most of this ring falls in, where two show up at once.
                seen[zone] = (seen[zone] or 0) + 1
                if seen[zone] > bestCount then best, bestCount = zone, seen[zone] end
            end
        end
        if best then return best end
    end
end
