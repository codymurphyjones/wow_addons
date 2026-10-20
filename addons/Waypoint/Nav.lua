local _, ns = ...
local C = ns.Compat

-- World positions: where you are, where a point is, how far and which way. World coordinates come
-- from C_Map.GetWorldPosFromMapPos, whose vector is (north, west) in yards on a continent.
-- (From WealthPlanner's Nav.lua.)
local Nav = {}
ns.Nav = Nav

-- You: continent, north, west; nil inside instances or when the map can't place you.
function Nav:Player()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local map = C.Call(C_Map.GetBestMapForUnit, "player")
    if not map then return nil end
    local pos = C.Call(C_Map.GetPlayerMapPosition, map, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    if not x or (x == 0 and y == 0) then return nil end
    local continent, world = C.Call(C_Map.GetWorldPosFromMapPos, map, pos)
    if not (continent and world) then return nil end
    local n, w = world:GetXY()
    return continent, n, w
end

-- A point { mapID, x, y } (0-1) in the world: continent, north, west. Cached on the point once known.
function Nav:World(p)
    if p._c then return p._c, p._n, p._w end
    if not (p.mapID and p.x and p.y and CreateVector2D) then return nil end
    local continent, world = C.Call(C_Map.GetWorldPosFromMapPos, p.mapID, CreateVector2D(p.x, p.y))
    if not (continent and world) then return nil end
    p._c = continent
    p._n, p._w = world:GetXY()
    return p._c, p._n, p._w
end

-- Yards to a point and its angle from north (radians, counter-clockwise, like GetPlayerFacing).
-- Without a way to measure: nil and why ("instance", "continent" or "unknown").
function Nav:To(p, continent, n, w)
    if not continent then continent, n, w = self:Player() end
    if not continent then return nil, "instance" end
    local pc, pn, pw = self:World(p)
    if not pc then return nil, "unknown" end
    if pc ~= continent then return nil, "continent" end
    local dn, dw = pn - n, pw - w
    return math.sqrt(dn * dn + dw * dw), math.atan2(dw, dn)
end

-- Where a point on mapID lands on onMap, as 0-1 fractions, or nil if it's off that map.
function Nav:Project(mapID, x, y, onMap)
    if mapID == onMap then return x, y end
    if not (mapID and onMap and CreateVector2D) then return nil end
    local continent, world = C.Call(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if not world then return nil end
    local _, pos = C.Call(C_Map.GetMapPosFromWorldPos, continent, world, onMap)
    if not pos then return nil end
    local px, py = pos:GetXY()
    if px >= 0 and px <= 1 and py >= 0 and py <= 1 then return px, py end
end

-- OpenMap's stitched map is up (its view runs past the map underneath).
function Nav:Stitched()
    return OpenMapAPI and OpenMapAPI.IsStitched and OpenMapAPI.WorldFromMap and OpenMapAPI.MapFromWorld
        and OpenMapAPI.IsStitched() and true or false
end

local REACH = 2 -- on the stitched map: how far past onMap's own rectangle (in its widths) things are placed

-- Where to draw a point on mapID on the world map showing onMap, as fractions of its canvas. As
-- Project, but on OpenMap's stitched map past onMap's own 0-1 too: the stitched view shows the
-- zones around it on the same canvas.
function Nav:OnCanvas(mapID, x, y, onMap)
    if self:Stitched() and mapID and onMap then
        local u, v = OpenMapAPI.WorldFromMap(mapID, x, y)
        local px, py
        if u then px, py = OpenMapAPI.MapFromWorld(onMap, u, v) end
        if px then
            if px >= -REACH and px <= 1 + REACH and py >= -REACH and py <= 1 + REACH then return px, py end
            return nil
        end
    end
    return self:Project(mapID, x, y, onMap)
end

-- A point on the map showing onMap (its canvas fractions, past 0-1 on the stitched map) as a zone
-- point: mapID, x, y, or nil. On the stitched map, the zone OpenMap draws there.
function Nav:FromCanvas(onMap, x, y)
    if not (self:Stitched() and OpenMapAPI.MapAt) then return nil end
    local u, v = OpenMapAPI.WorldFromMap(onMap, x, y)
    local zone = u and OpenMapAPI.MapAt(u, v)
    local zx, zy
    if zone then zx, zy = OpenMapAPI.MapFromWorld(zone, u, v) end
    if zx and zx >= 0 and zx <= 1 and zy >= 0 and zy <= 1 then return zone, zx, zy end
end

function Nav:ZoneName(mapID)
    local info = mapID and C.Call(C_Map.GetMapInfo, mapID)
    return info and info.name or "?"
end

-- "Westfall 52, 30"
function Nav:Describe(p)
    if not p then return "?" end
    return ("%s %.0f, %.0f"):format(self:ZoneName(p.mapID), (p.x or 0) * 100, (p.y or 0) * 100)
end

function Nav.Distance(d)
    if d < 1000 then return ("%d yd"):format(d) end
    return ("%.1fk yd"):format(d / 1000)
end

function Nav.ETA(d)
    local speed = GetUnitSpeed and C.Num(select(2, GetUnitSpeed("player"))) or 7
    if not speed or speed <= 0 then speed = 7 end
    local secs = d / speed
    if secs < 60 then return ("%ds"):format(secs) end
    return ("%dm %02ds"):format(secs / 60, secs % 60)
end
