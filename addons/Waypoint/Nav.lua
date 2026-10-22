local _, ns = ...

-- World positions: where you are, where a point is, how far and which way. A thin front on the
-- shared WorldMap.lua (ns.WorldMap), so every ns.Nav: call site stays as it was. World coordinates
-- come from C_Map.GetWorldPosFromMapPos, whose vector is (north, west) in yards on a continent.
local WM = ns.WorldMap
local Nav = {}
ns.Nav = Nav

-- You: continent, north, west; nil inside instances or when the map can't place you.
function Nav:Player() local c, n, w = WM.Player() return c, n, w end

-- A point { mapID, x, y } (0-1) in the world: continent, north, west. Cached on the point once known.
function Nav:World(p) return WM.WorldOf(p) end

-- Yards to a point and its angle from north (radians, counter-clockwise, like GetPlayerFacing).
-- Without a way to measure: nil and why ("instance", "continent" or "unknown").
function Nav:To(p, continent, n, w) return WM.To(p, continent, n, w) end

-- Where a point on mapID lands on onMap, as 0-1 fractions, or nil if it's off that map.
function Nav:Project(mapID, x, y, onMap) return WM.Project(mapID, x, y, onMap) end

-- OpenMap's stitched map is up (its view runs past the map underneath).
function Nav:Stitched() return WM.Stitched() end

-- Where to draw a point on mapID on the world map showing onMap, as fractions of its canvas. As
-- Project, but on OpenMap's stitched map past onMap's own 0-1 too: the stitched view shows the
-- zones around it on the same canvas.
function Nav:OnCanvas(mapID, x, y, onMap) return WM.OnCanvas(mapID, x, y, onMap) end

-- A point on the map showing onMap (its canvas fractions, past 0-1 on the stitched map) as a zone
-- point: mapID, x, y, or nil. On the stitched map, the zone OpenMap draws there.
function Nav:FromCanvas(onMap, x, y) return WM.FromCanvas(onMap, x, y) end

function Nav:ZoneName(mapID) return WM.ZoneName(mapID) end

-- "Westfall 52, 30"
function Nav:Describe(p) return WM.Describe(p) end

-- "850 yd", "1.2k yd"; how long that takes at your run speed: "45s", "2m 05s".
Nav.Distance, Nav.ETA = WM.DistanceText, WM.ETA
