local _, ns = ...

-- ns.WorldMap: where things are in the world and where to draw them (addons/shared, copied into
-- each addon's Shared\ folder by the build; no other shared file needed).
--   Positions   world positions from C_Map (continent, north, west in yards), projections onto a
--               map (OpenMap's stitched map too), distances, zone names, distance and ETA text.
--   Layers      WM.NewLayer(opts): pooled pins and lines on the world map canvas, the same size on
--               screen at every zoom, redrawn when the map, its zoom or its visibility changes.
--   Minimap     WM.MinimapView(): yards around you as minimap pixels (zoom, indoors, rotation,
--               square minimaps, rim clamping).
-- World coordinates come from C_Map.GetWorldPosFromMapPos, whose vector is (north, west) in yards
-- on a continent. Map coordinates are 0-1 fractions unless a name says otherwise.
-- (From Waypoint's Nav.lua, MapPins.lua and MinimapPin.lua, with the other addons' copies merged in.)
local WM = {}
ns.WorldMap = WM

-- ---------------------------------------------------------------------------------------------
-- Safe reads (as Secrets.lua: a secret or failing value becomes nil)
-- ---------------------------------------------------------------------------------------------

local function Readable(v)
    if v == nil then return nil end
    if canaccessvalue and not canaccessvalue(v) then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
local function Num(v) v = Readable(v); return type(v) == "number" and v or nil end

-- pcall that returns the results, or nothing when the call errors (or fn is missing).
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e = pcall(fn, ...)
    if ok then return a, b, c, d, e end
end
WM.Call, WM.Num = Call, Num

local function Map() return C_Map or {} end

-- A vector's two numbers (nil for a missing or secret one).
local function XY(v)
    if not v then return nil end
    local x, y
    if v.GetXY then x, y = Call(v.GetXY, v) else x, y = v.x, v.y end
    return Num(x), Num(y)
end

-- ---------------------------------------------------------------------------------------------
-- Positions
-- ---------------------------------------------------------------------------------------------

-- Your map position: x, y (0-1), mapID; nil inside instances or when the map can't place you.
function WM.PlayerPos()
    local M = Map()
    local map = Num(Call(M.GetBestMapForUnit, "player"))
    if not map then return nil end
    local x, y = XY(Call(M.GetPlayerMapPosition, map, "player"))
    if not x or (x == 0 and y == 0) then return nil end
    return x, y, map
end

-- A point on a map in the world: continent, north, west; nil when the map can't say.
function WM.World(mapID, x, y)
    local M = Map()
    if not (mapID and x and y and CreateVector2D and M.GetWorldPosFromMapPos) then return nil end
    local continent, world = Call(M.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    local n, w = XY(world)
    if not (continent and n) then return nil end
    return continent, n, w
end

-- You in the world: continent, north, west, mapID, x, y (0-1); nil inside instances or when the
-- map can't place you.
function WM.Player()
    local x, y, map = WM.PlayerPos()
    if not map then return nil end
    local continent, n, w = WM.World(map, x, y)
    if not continent then return nil end
    return continent, n, w, map, x, y
end

-- A point table { mapID, x, y } in the world: continent, north, west, cached on the point once
-- known (fields _c, _n, _w).
function WM.WorldOf(p)
    if p._c then return p._c, p._n, p._w end
    local c, n, w = WM.World(p.mapID, p.x, p.y)
    if not c then return nil end
    p._c, p._n, p._w = c, n, w
    return c, n, w
end

-- The continent a map belongs to, as the world-position APIs number it (nil if unknown).
function WM.Continent(mapID)
    return (WM.World(mapID, 0.5, 0.5))
end

-- Yards between two world points, or nil when they're on different continents.
function WM.Distance(c1, n1, w1, c2, n2, w2)
    if not (c1 and c2 and n1 and n2) or c1 ~= c2 then return nil end
    local dn, dw = n2 - n1, w2 - w1
    return math.sqrt(dn * dn + dw * dw)
end

-- Yards from you to a point on a map, or nil (instance, other continent, unknown).
function WM.DistanceTo(mapID, x, y)
    local c, n, w = WM.Player()
    if not c then return nil end
    local pc, pn, pw = WM.World(mapID, x, y)
    return WM.Distance(c, n, w, pc, pn, pw)
end

-- Yards to a point table and its angle from north (radians, counter-clockwise, like
-- GetPlayerFacing). From you, or from continent, n, w when given. Without a way to measure: nil
-- and why ("instance", "continent" or "unknown").
function WM.To(p, continent, n, w)
    if not continent then continent, n, w = WM.Player() end
    if not continent then return nil, "instance" end
    local pc, pn, pw = WM.WorldOf(p)
    if not pc then return nil, "unknown" end
    if pc ~= continent then return nil, "continent" end
    local dn, dw = pn - n, pw - w
    return math.sqrt(dn * dn + dw * dw), math.atan2 and math.atan2(dw, dn) or math.atan(dw, dn)
end

local function Within(x, y, slack)
    slack = slack or 0
    return x >= -slack and x <= 1 + slack and y >= -slack and y <= 1 + slack
end

-- Where a world point lands on onMap, as 0-1 fractions, or nil off it (slack: how far past 0-1
-- still counts, default 0).
function WM.ProjectWorld(continent, n, w, onMap, slack)
    local M = Map()
    if not (continent and n and w and onMap and CreateVector2D and M.GetMapPosFromWorldPos) then return nil end
    local _, pos = Call(M.GetMapPosFromWorldPos, continent, CreateVector2D(n, w), onMap)
    local px, py = XY(pos)
    if px and py and Within(px, py, slack) then return px, py end
end

-- Where a point on mapID lands on onMap, as 0-1 fractions, or nil off it (slack as above).
function WM.Project(mapID, x, y, onMap, slack)
    if mapID == onMap then return x, y end
    local c, n, w = WM.World(mapID, x, y)
    if not c then return nil end
    return WM.ProjectWorld(c, n, w, onMap, slack)
end

-- OpenMap's stitched map is up (its view runs past the map underneath).
function WM.Stitched()
    local api = OpenMapAPI
    return api and api.IsStitched and api.WorldFromMap and api.MapFromWorld and Call(api.IsStitched) and true or false
end

WM.REACH = 2 -- on the stitched map: how far past onMap's own rectangle (in its widths) points are placed

-- Where to draw a point on mapID on the world map showing onMap, as fractions of its canvas. As
-- Project, but on OpenMap's stitched map past onMap's own 0-1 too (up to WM.REACH): the stitched
-- view shows the zones around it on the same canvas.
function WM.OnCanvas(mapID, x, y, onMap)
    if mapID and onMap and WM.Stitched() then
        local u, v = Call(OpenMapAPI.WorldFromMap, mapID, x, y)
        local px, py
        if u then px, py = Call(OpenMapAPI.MapFromWorld, onMap, u, v) end
        if px then
            local r = WM.REACH
            if px >= -r and px <= 1 + r and py >= -r and py <= 1 + r then return px, py end
            return nil
        end
    end
    return WM.Project(mapID, x, y, onMap)
end

-- A world point on the canvas showing onMap: OpenMap's stitched canvas when it's up (past 0-1
-- too), else ProjectWorld with slack (Waypoint's route line uses 0.05).
function WM.WorldOnCanvas(continent, n, w, onMap, slack)
    local api = OpenMapAPI
    if api and api.IsStitched and api.CanvasFromWorldPos and Call(api.IsStitched) then
        local x, y = Call(api.CanvasFromWorldPos, continent, n, w)
        if x then return x, y end
    end
    return WM.ProjectWorld(continent, n, w, onMap, slack)
end

-- A point on the canvas showing onMap (past 0-1 on the stitched map) as a zone point: mapID, x, y,
-- or nil. On the stitched map, the zone OpenMap draws there.
function WM.FromCanvas(onMap, x, y)
    if not (WM.Stitched() and OpenMapAPI.MapAt) then return nil end
    local u, v = Call(OpenMapAPI.WorldFromMap, onMap, x, y)
    local zone = u and Call(OpenMapAPI.MapAt, u, v)
    local zx, zy
    if zone then zx, zy = Call(OpenMapAPI.MapFromWorld, zone, u, v) end
    if zx and zx >= 0 and zx <= 1 and zy >= 0 and zy <= 1 then return zone, zx, zy end
end

-- A map's name. Without one, fallback: a string ("%s" becomes the map ID: "map %s"), default "?".
-- Names are cached once found.
local names = {}
function WM.ZoneName(mapID, fallback)
    local name = mapID and names[mapID]
    if not name and mapID then
        local info = Call(Map().GetMapInfo, mapID)
        name = info and Readable(info.name)
        if type(name) == "string" and name ~= "" then names[mapID] = name else name = nil end
    end
    if name then return name end
    fallback = fallback or "?"
    if fallback:find("%%s") then return (fallback:gsub("%%s", tostring(mapID))) end
    return fallback
end

-- "Westfall 52, 30" for a point table.
function WM.Describe(p, fallback)
    if not p then return "?" end
    return ("%s %.0f, %.0f"):format(WM.ZoneName(p.mapID, fallback), (p.x or 0) * 100, (p.y or 0) * 100)
end

-- "850 yd", "1.2k yd"
function WM.DistanceText(d)
    if d < 1000 then return ("%d yd"):format(math.floor(d)) end
    return ("%.1fk yd"):format(d / 1000)
end

-- How long d yards takes at your run speed (7 yards a second when it's unknown): "45s", "2m 05s".
function WM.ETA(d)
    local speed = GetUnitSpeed and Num((select(2, Call(GetUnitSpeed, "player")))) or 7
    if not speed or speed <= 0 then speed = 7 end
    local secs = d / speed
    if secs < 60 then return ("%ds"):format(math.floor(secs)) end
    return ("%dm %02ds"):format(math.floor(secs / 60), math.floor(secs % 60))
end

-- ---------------------------------------------------------------------------------------------
-- World map layers
-- ---------------------------------------------------------------------------------------------

-- The frame level the map's own art ends at: the canvas's, or with OpenMap's stitched art over it,
-- so that +2000 is just above that art.
function WM.MapBase(canvas)
    local base = canvas:GetFrameLevel()
    local api = OpenMapAPI
    local top = api and api.ArtTopLevel and Call(api.ArtTopLevel)
    if type(top) == "number" and top >= base + 2000 then base = top + 1 - 2000 end
    return base
end

-- A level above every visible canvas child bigger than minSize on both sides (the map's art,
-- explored areas), starting at base + from and staying under base + below for the children
-- counted; never over base + cap. skip(f) (or a frame) leaves a child out.
function WM.LevelAbove(canvas, base, from, below, cap, minSize, skip)
    local level = base + from
    local isFn = type(skip) == "function"
    for _, f in ipairs({ canvas:GetChildren() }) do
        local skipped = (isFn and skip(f)) or (not isFn and skip ~= nil and f == skip)
        if not skipped and f:IsVisible() then
            local fw, fh = f:GetSize()
            local l = f:GetFrameLevel()
            if fw > minSize and fh > minSize and l < base + below and l >= level then level = l + 1 end
        end
    end
    return math.min(level, base + cap)
end

local Layer = {}
Layer.__index = Layer

-- Layers waiting for PLAYER_LOGIN to hook the map.
local waiting, loginFrame = {}, nil

local function Level(spec, layer, default)
    if type(spec) == "function" then return spec(layer.canvas, layer.base, layer) end
    return layer.base + (spec or default)
end

-- A new world map layer. opts (all optional):
--   refresh(layer, mapID, canvas)  draws: layer:Pin/Place/PinAt/Line/Polyline/Dashed. Called by
--                                  layer:Refresh() with everything hidden and layer.mapID, .canvas,
--                                  .w, .h (canvas size), .scale (1 / canvas zoom) set.
--   create(pin, layer)             builds a new pooled pin (textures, scripts, RegisterForClicks).
--   frameType                      the pins' frame type, default "Button".
--   size                           a pin's on-screen size when Place gets none (default 16).
--   base                           "map" (default: WM.MapBase, over OpenMap's stitched art) or
--                                  "canvas" (canvas:GetFrameLevel()).
--   level                          the line frame's level: an offset from the base (default 2000),
--                                  or function(canvas, base, layer) -> level. Read each refresh.
--   pinLevel                       the pins' level, as level (default: the same as level).
--   lines                          true: the layer draws lines (makes its line frame).
--   stitched                       false: PinAt uses WM.Project, not WM.OnCanvas.
--   hook                           false: don't hook the map (call layer:Hook() yourself).
--   interval, every(layer)         every interval seconds while the map is open, every(layer)
--                                  (default: layer:Refresh()).
--   onHide(layer)                  when the map closes.
--   onStitched(layer)              when OpenMap switches between its stitched map and Blizzard's
--                                  (default: nothing; true: layer:Refresh()).
--   map                            the map frame, default WorldMapFrame.
function WM.NewLayer(opts)
    local layer = setmetatable({ opts = opts or {}, pins = {}, used = 0, lines = {}, usedLines = 0, scale = 1 }, Layer)
    if layer.opts.hook ~= false then
        if IsLoggedIn and IsLoggedIn() then
            layer:Hook()
        else
            waiting[#waiting + 1] = layer
            if not loginFrame and CreateFrame then
                loginFrame = CreateFrame("Frame")
                loginFrame:RegisterEvent("PLAYER_LOGIN")
                loginFrame:SetScript("OnEvent", function()
                    for _, l in ipairs(waiting) do l:Hook() end
                    waiting = {}
                end)
            end
        end
    end
    return layer
end

function Layer:MapFrame() return self.opts.map or WorldMapFrame end

-- Hooks the map: redraw on OnMapChanged, OnCanvasScaleChanged and OnShow, plus the interval,
-- onHide and onStitched options. Once.
function Layer:Hook()
    local map = self:MapFrame()
    if self.hooked or not map then return end
    self.hooked = true
    local opts = self.opts
    local function Refresh() self:Refresh() end
    if hooksecurefunc then
        if map.OnMapChanged then hooksecurefunc(map, "OnMapChanged", Refresh) end
        if map.OnCanvasScaleChanged then hooksecurefunc(map, "OnCanvasScaleChanged", Refresh) end
    end
    map:HookScript("OnShow", Refresh)
    if opts.onHide then map:HookScript("OnHide", function() opts.onHide(self) end) end
    if opts.onStitched and OpenMapAPI and OpenMapAPI.RegisterCallback then
        local fn = opts.onStitched == true and Refresh or function() opts.onStitched(self) end
        pcall(OpenMapAPI.RegisterCallback, self, "OpenMap_StitchedChanged", fn)
    end
    if opts.interval then
        local acc = 0
        CreateFrame("Frame"):SetScript("OnUpdate", function(_, elapsed)
            acc = acc + elapsed
            if acc < opts.interval then return end
            acc = 0
            if map:IsShown() then
                if opts.every then opts.every(self) else self:Refresh() end
            end
        end)
    end
end

-- Hides every pin and line.
function Layer:Clear()
    for i = 1, self.used do self.pins[i]:Hide() end
    for i = 1, self.usedLines do self.lines[i]:Hide() end
    self.used, self.usedLines = 0, 0
end

-- Clears the layer and reads the map: mapID, canvas (nil when there's no map to draw on). Sets
-- layer.mapID, .canvas, .w, .h, .scale, .base, .level and .pinLevel.
function Layer:Begin()
    self:Clear()
    local map = self:MapFrame()
    local mapID = map and map:GetMapID()
    local canvas = map and map:GetCanvas()
    self.mapID, self.canvas = mapID, canvas
    if not (mapID and canvas) then return nil end
    local opts = self.opts
    self.scale = 1 / (map:GetCanvasScale() or 1)
    self.w, self.h = canvas:GetSize()
    self.base = opts.base == "canvas" and canvas:GetFrameLevel() or WM.MapBase(canvas)
    if opts.lines then
        if not self.frame then
            self.frame = CreateFrame("Frame", nil, canvas)
            self.frame:SetAllPoints(canvas)
        end
    end
    self.level = Level(opts.level, self, 2000)
    if self.frame then self.frame:SetFrameLevel(self.level) end
    self.pinLevel = opts.pinLevel and Level(opts.pinLevel, self, 2000) or self.level
    return mapID, canvas
end

-- Redraws the layer while the map is open.
function Layer:Refresh()
    local map = self:MapFrame()
    if not (map and map:IsShown()) then return end
    local mapID, canvas = self:Begin()
    if mapID and self.opts.refresh then self.opts.refresh(self, mapID, canvas) end
end

-- The next pooled pin (not shown until Place).
function Layer:Pin()
    self.used = self.used + 1
    local pin = self.pins[self.used]
    if not pin then
        pin = CreateFrame(self.opts.frameType or "Button", nil, self.canvas)
        if self.opts.create then self.opts.create(pin, self) end
        self.pins[self.used] = pin
    end
    return pin
end

-- Puts the last pin back in the pool (it was taken but isn't drawn).
function Layer:Unpin()
    if self.used > 0 then
        self.pins[self.used]:Hide()
        self.used = self.used - 1
    end
end

-- Shows a pin at canvas fractions px, py, size on screen at any zoom (offsets are in the pin's own
-- units: it's scaled by 1 / zoom).
function Layer:Place(pin, px, py, size)
    size = size or self.opts.size or 16
    local scale = self.scale
    pin:SetSize(size, size)
    pin:SetScale(scale)
    pin:SetFrameLevel(self.pinLevel)
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", self.canvas, "TOPLEFT", px * self.w / scale, -py * self.h / scale)
    pin:Show()
end

-- A pin for a point on mapID, placed on this map: pin, px, py; nil when it's off the map.
function Layer:PinAt(mapID, x, y, size)
    local project = self.opts.stitched == false and WM.Project or WM.OnCanvas
    local px, py = project(mapID, x, y, self.mapID)
    if not px then return nil end
    local pin = self:Pin()
    self:Place(pin, px, py, size)
    return pin, px, py
end

-- True when the layer can draw lines (its frame has CreateLine).
function Layer:CanDrawLines()
    return self.frame and self.frame.CreateLine and true or false
end

-- One line between canvas fractions, thickness on screen; col { r, g, b [, a] } (alpha wins over
-- col[4], default 1); sub: the ARTWORK sublevel (default 0). Returns the line, or nil.
function Layer:Line(x0, y0, x1, y1, col, thickness, alpha, sub)
    if not self:CanDrawLines() then return nil end
    self.usedLines = self.usedLines + 1
    local line = self.lines[self.usedLines]
    if not line then
        line = self.frame:CreateLine(nil, "ARTWORK")
        self.lines[self.usedLines] = line
    end
    local w, h, canvas = self.w, self.h, self.canvas
    line:SetDrawLayer("ARTWORK", sub or 0)
    line:SetColorTexture(col[1], col[2], col[3], alpha or col[4] or 1)
    line:SetThickness(thickness * self.scale)
    line:SetStartPoint("TOPLEFT", canvas, x0 * w, -y0 * h)
    line:SetEndPoint("TOPLEFT", canvas, x1 * w, -y1 * h)
    line:Show()
    return line
end

-- A polyline { x1, y1, x2, y2, ... } in canvas fractions (false where a point is off the map: the
-- line breaks there). With edge, a casing first: edge colour, thickness * (casing or 2), under
-- the core (sublevels 0 and 1).
function Layer:Polyline(xy, col, thickness, edge, casing)
    for pass = edge and 1 or 2, 2 do
        local c = pass == 1 and edge or col
        local t = pass == 1 and thickness * (casing or 2) or thickness
        for i = 3, #xy - 1, 2 do
            local x0, y0, x1, y1 = xy[i - 2], xy[i - 1], xy[i], xy[i + 1]
            if x0 and x1 then self:Line(x0, y0, x1, y1, c, t, nil, pass == 1 and 0 or 1) end
        end
    end
end

-- A polyline in canvas fractions as dashes (dash and gap on screen), carrying the pattern across
-- its corners. Alpha as Line; sub: the ARTWORK sublevel (default 0: over a Polyline casing at 0,
-- pass 1 to be sure it's on top).
function Layer:Dashed(xy, col, thickness, dash, gap, alpha, sub)
    local w, h, scale = self.w, self.h, self.scale
    dash, gap = dash * scale, gap * scale
    local on, left = true, dash
    for i = 3, #xy - 1, 2 do
        local x0, y0, x1, y1 = xy[i - 2] * w, xy[i - 1] * h, xy[i] * w, xy[i + 1] * h
        local len = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
        local at = 0
        while at < len do
            local step = math.min(left, len - at)
            if on then
                local a, b = at / len, (at + step) / len
                self:Line((x0 + (x1 - x0) * a) / w, (y0 + (y1 - y0) * a) / h,
                    (x0 + (x1 - x0) * b) / w, (y0 + (y1 - y0) * b) / h, col, thickness, alpha, sub)
            end
            at = at + step
            left = left - step
            if left <= 0 then
                on = not on
                left = on and dash or gap
            end
        end
    end
end

-- ---------------------------------------------------------------------------------------------
-- Minimap
-- ---------------------------------------------------------------------------------------------

-- Minimap diameter in yards at each zoom level (HereBeDragons' tables).
WM.MINIMAP_OUTDOOR = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }
WM.MINIMAP_INDOOR = { [0] = 300, 240, 180, 120, 80, 50 }

-- The minimap's radius in yards: at zoom (default Minimap:GetZoom()) and indoors (default
-- IsIndoors()).
function WM.MinimapRadius(zoom, indoors)
    if zoom == nil then zoom = Minimap and Num(Call(Minimap.GetZoom, Minimap)) or 0 end
    if indoors == nil then indoors = IsIndoors and Readable(Call(IsIndoors)) and true or false end
    local t = indoors and WM.MINIMAP_INDOOR or WM.MINIMAP_OUTDOOR
    return (t[zoom] or t[0]) / 2
end

-- The minimap turns with you (the rotateMinimap CVar): rotate, sin, cos, known. known is false when
-- it rotates but your facing can't be read (sin, cos are then 0, 1: no turn).
function WM.MinimapRotation(facing)
    local rotate = GetCVar and Call(GetCVar, "rotateMinimap") == "1" or false
    if not rotate then return false, 0, 1, true end
    if facing == nil then facing = GetPlayerFacing and Num(Call(GetPlayerFacing)) end
    if not facing then return true, 0, 1, false end
    return true, math.sin(facing), math.cos(facing), true
end

-- The minimap is square (a shape addon's GetMinimapShape() says "SQUARE").
function WM.MinimapSquare()
    return GetMinimapShape and Call(GetMinimapShape) == "SQUARE" or false
end

local View = {}
View.__index = View

-- What the minimap shows now, for placing things on it. opts (all optional, for overrides and
-- tests): zoom, indoors, facing, rotate (true/false), square (true/false), half (pixels from the
-- centre to the edge; default Minimap:GetWidth() / 2), player (false: don't read your position;
-- or { continent, n, w }).
-- The view: radius (yards), half, rotate, sin, cos, known, square, continent, n, w.
function WM.MinimapView(opts)
    opts = opts or {}
    local v = setmetatable({}, View)
    v.radius = WM.MinimapRadius(opts.zoom, opts.indoors)
    v.half = opts.half or (Minimap and Minimap:GetWidth() / 2) or 70
    if opts.rotate ~= nil then
        v.rotate = opts.rotate
        local f = opts.facing or 0
        v.sin, v.cos, v.known = opts.rotate and math.sin(f) or 0, opts.rotate and math.cos(f) or 1, true
    else
        v.rotate, v.sin, v.cos, v.known = WM.MinimapRotation(opts.facing)
    end
    if opts.square ~= nil then v.square = opts.square else v.square = WM.MinimapSquare() end
    if type(opts.player) == "table" then
        v.continent, v.n, v.w = opts.player[1], opts.player[2], opts.player[3]
    elseif opts.player ~= false then
        v.continent, v.n, v.w = WM.Player()
    end
    return v
end

-- Turns yards east, yards south of you (as the minimap shows them: rotated with you when it turns)
-- into rx, ry.
function View:Turn(x, y)
    if self.rotate then return x * self.cos - y * self.sin, x * self.sin + y * self.cos end
    return x, y
end

-- Within edge yards of the centre on the minimap's shape (edge default radius; round: a circle;
-- square: a square).
function View:Inside(rx, ry, edge)
    edge = edge or self.radius
    if self.square then return math.abs(rx) <= edge and math.abs(ry) <= edge end
    return rx * rx + ry * ry <= edge * edge
end

-- Pixels from the minimap's centre (up positive) for turned yards rx, ry.
function View:Pixels(rx, ry)
    return rx / self.radius * self.half, -ry / self.radius * self.half
end

-- On the rim, inset pixels in, in the direction of rx, ry: px, py. Round: on the circle; square:
-- on the square's edge.
function View:Rim(rx, ry, inset)
    local r = self.half - (inset or 0)
    if self.square then
        local m = math.max(math.abs(rx), math.abs(ry))
        if m == 0 then return 0, 0 end
        return rx / m * r, -ry / m * r
    end
    local len = math.sqrt(rx * rx + ry * ry)
    if len == 0 then return 0, 0 end
    return rx / len * r, -ry / len * r
end

-- Where something x yards east and y yards south of you goes: px, py, inside, rx, ry. With clamp
-- (pixels in from the rim), a point off the minimap goes on its rim instead (inside false). edge as
-- Inside.
function View:Place(x, y, clamp, edge)
    local rx, ry = self:Turn(x, y)
    local inside = self:Inside(rx, ry, edge)
    if not inside and clamp then
        local px, py = self:Rim(rx, ry, clamp)
        return px, py, false, rx, ry
    end
    local px, py = self:Pixels(rx, ry)
    return px, py, inside, rx, ry
end

-- As Place, for a world point: nil when it's on another continent than you (or you're nowhere).
function View:PlaceWorld(continent, n, w, clamp, edge)
    if not (self.continent and continent == self.continent and n and w) then return nil end
    return self:Place(self.w - w, self.n - n, clamp, edge)
end
