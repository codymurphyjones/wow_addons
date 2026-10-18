local _, ns = ...
local C = ns.Compat

-- World positions. World coordinates come from C_Map.GetWorldPosFromMapPos, whose vector is
-- (north, west) in yards on a continent. (From Waypoint's Nav.lua.)
local Nav = {}
ns.Nav = Nav

-- You: continent, north, west, zone mapID; nil inside instances or when the map can't place you.
function Nav:Player()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local map = C.Call(C_Map.GetBestMapForUnit, "player")
    if not map then return nil end
    local pos = C.Call(C_Map.GetPlayerMapPosition, map, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    if not C.Num(x) or (x == 0 and y == 0) then return nil end
    local continent, world = C.Call(C_Map.GetWorldPosFromMapPos, map, pos)
    if not (continent and world) then return nil end
    local n, w = world:GetXY()
    return continent, n, w, map
end

-- Where a world point lands on onMap, as 0-1 fractions, or nil if it's off that map.
function Nav:Project(continent, n, w, onMap)
    if not (CreateVector2D and C_Map.GetMapPosFromWorldPos) then return nil end
    local _, pos = C.Call(C_Map.GetMapPosFromWorldPos, continent, CreateVector2D(n, w), onMap)
    if not pos then return nil end
    local px, py = pos:GetXY()
    if px and px >= 0 and px <= 1 and py >= 0 and py <= 1 then return px, py end
end

-- The continent a map belongs to, as the world-position APIs number it (nil if unknown).
function Nav:Continent(mapID)
    if not (mapID and CreateVector2D) then return nil end
    local continent = C.Call(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(0.5, 0.5))
    return continent
end

function Nav:ZoneName(mapID)
    local info = mapID and C.Call(C_Map.GetMapInfo, mapID)
    return info and info.name or ("map " .. tostring(mapID))
end
