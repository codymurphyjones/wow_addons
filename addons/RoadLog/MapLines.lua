local _, ns = ...

-- The world map: every recorded road as a gold line in a dark casing (it reads on sand, grass and
-- snow alike), and the stretch you're walking now thicker and brighter. Lines are pooled on the
-- map canvas, like Waypoint's MapPins.lua. Where a stretch lands on a given map is worked out once
-- per map and kept for the session (not saved).
local Lines = {}
ns.MapLines = Lines

local LINE = 2.5     -- on-screen line thickness (the core; the casing is wider)
local CASING = 2.2   -- the casing's width, times the core's
local EDGE = { 0.18, 0.10, 0.03, 0.85 }
local ROAD = { 1, 0.80, 0.35, 1 }
local DETOUR = { 1, 0.86, 0.55, 0.45 } -- loops and side trips (Smooth.Network): thin and faint
local DETOUR_EDGE = { 0.18, 0.10, 0.03, 0.30 }
local NOW = { 1, 0.96, 0.62, 1 }
local CAVE_LOW = { 0.12, 0.30, 0.85 }   -- a cave's lowest point (Caves.lua heights), shading up to
local CAVE_HIGH = { 0.80, 0.97, 1.00 }  -- its highest
local CAVE_FLAT = { 0.25, 0.77, 0.80, 1 } -- a cave with no heights yet (logged since the last build)
local CAVE_EDGE = { 0.02, 0.08, 0.14, 0.85 }
local LAYER_CAP = 2090 -- the lines' frame level stays under this (Waypoint's own pins sit at +2100)
local REFRESH = 1    -- seconds between redraws while you record with the map open

local lines, used = {}, 0
local Network -- below
local lineFrame
local cache = setmetatable({}, { __mode = "k" }) -- [segment] = { [mapID] = { x1, y1, x2, y2, ... } (false: off the map) }
local cleaned = setmetatable({}, { __mode = "k" }) -- [segment] = its points with the weaving out (Smooth.lua)

local function GetLine()
    used = used + 1
    local line = lines[used]
    if not line then
        line = lineFrame:CreateLine(nil, "ARTWORK")
        lines[used] = line
    end
    return line
end

-- The points to draw for a stretch: cleaned of weaving (Smooth.lua) unless /roadlog smooth is off.
local function Points(seg, keep)
    if seg.net or not (ns.db.smooth and ns.Smooth) then return seg.pts end
    if cleaned[seg] then return cleaned[seg] end
    local pts = ns.Smooth.Clean(seg.pts)
    if keep then cleaned[seg] = pts end
    return pts
end

-- A continent's roads as one network (Smooth.Network), rebuilt whenever a stretch is added or
-- removed there, so anything walked later is merged the same way by itself.
local networks = {} -- [continent] = { sig, pieces }
Network = function(continent)
    local segs = ns.db.roads[continent] or {}
    local last = segs[#segs]
    local sig = #segs .. ":" .. tostring(last and last.at)
    local cached = networks[continent]
    if cached and cached.sig == sig then return cached.pieces end
    local stretches = {}
    for i, seg in ipairs(segs) do stretches[i] = Points(seg, true) end
    local pieces = ns.Smooth.Network(stretches)
    for _, piece in ipairs(pieces) do piece.net = true end
    networks[continent] = { sig = sig, pieces = pieces }
    return pieces
end

-- A stretch's points as 0-1 fractions on mapID.
local function Projected(seg, continent, mapID, keep)
    local key = ns.db.smooth and "s" .. mapID or mapID
    local byMap = cache[seg]
    if byMap and byMap[key] then return byMap[key] end
    local out, pts = {}, Points(seg, keep)
    for i = 1, #pts - 1, 2 do
        local x, y = ns.Nav:Project(continent, pts[i], pts[i + 1], mapID)
        out[i], out[i + 1] = x or false, y or false
    end
    if keep then
        cache[seg] = byMap or {}
        cache[seg][key] = out
    end
    return out
end

local function Draw(xy, canvas, w, h, thickness, col, edge)
    -- The casing first, for the whole stretch, then the core on top of it.
    for pass = 1, 2 do
        local c = pass == 1 and (edge or EDGE) or col
        local t = pass == 1 and thickness * CASING or thickness
        for i = 3, #xy - 1, 2 do
            local x0, y0, x1, y1 = xy[i - 2], xy[i - 1], xy[i], xy[i + 1]
            if x0 and x1 then
                local line = GetLine()
                line:SetDrawLayer("ARTWORK", pass == 1 and 0 or 1)
                line:SetColorTexture(c[1], c[2], c[3], c[4])
                line:SetThickness(t)
                line:SetStartPoint("TOPLEFT", canvas, x0 * w, -y0 * h)
                line:SetEndPoint("TOPLEFT", canvas, x1 * w, -y1 * h)
                line:Show()
            end
        end
    end
end

-- The lines' frame level: above every layer that covers the whole map. The explored areas'
-- painted art is one, and anything under it is hidden there (a road through an explored zone
-- vanished). Under Waypoint's own pins, and layers at or over that are left out.
local function LineLevel(canvas)
    local base = canvas:GetFrameLevel()
    local level = base + 1900
    for _, f in ipairs({ canvas:GetChildren() }) do
        if f ~= lineFrame and f:IsVisible() then
            local fw, fh = f:GetSize()
            local l = f:GetFrameLevel()
            if fw > 48 and fh > 48 and l < base + 2100 and l >= level then level = l + 1 end
        end
    end
    return math.min(level, base + LAYER_CAP)
end

-- A cave stretch, each piece shaded by its height between the cave's lowest and highest point:
-- deep blue at the bottom, pale at the top. Without heights it's one flat teal.
local function DrawCave(xy, z, canvas, w, h, thickness)
    if not z then return Draw(xy, canvas, w, h, thickness, CAVE_FLAT, CAVE_EDGE) end
    local lo, hi = math.huge, -math.huge
    for _, v in ipairs(z) do lo, hi = math.min(lo, v), math.max(hi, v) end
    local span = math.max(hi - lo, 1)
    for pass = 1, 2 do
        for i = 3, #xy - 1, 2 do
            local x0, y0, x1, y1 = xy[i - 2], xy[i - 1], xy[i], xy[i + 1]
            if x0 and x1 then
                local line = GetLine()
                line:SetDrawLayer("ARTWORK", pass == 1 and 0 or 1)
                if pass == 1 then
                    line:SetColorTexture(CAVE_EDGE[1], CAVE_EDGE[2], CAVE_EDGE[3], CAVE_EDGE[4])
                    line:SetThickness(thickness * CASING)
                else
                    local k = (((z[(i - 1) / 2] + z[(i + 1) / 2]) / 2) - lo) / span
                    line:SetColorTexture(CAVE_LOW[1] + (CAVE_HIGH[1] - CAVE_LOW[1]) * k, CAVE_LOW[2] + (CAVE_HIGH[2] - CAVE_LOW[2]) * k,
                        CAVE_LOW[3] + (CAVE_HIGH[3] - CAVE_LOW[3]) * k, 1)
                    line:SetThickness(thickness)
                end
                line:SetStartPoint("TOPLEFT", canvas, x0 * w, -y0 * h)
                line:SetEndPoint("TOPLEFT", canvas, x1 * w, -y1 * h)
                line:Show()
            end
        end
    end
end

function Lines:Refresh()
    if not (ns.db and WorldMapFrame and WorldMapFrame:IsShown()) then return end
    for i = 1, used do lines[i]:Hide() end
    used = 0
    local mapID = WorldMapFrame:GetMapID()
    local canvas = WorldMapFrame:GetCanvas()
    if not (ns.db.showMap and mapID and canvas and canvas.CreateLine) then return end

    if not lineFrame then
        lineFrame = CreateFrame("Frame", nil, canvas)
        lineFrame:SetAllPoints(canvas)
    end
    lineFrame:SetFrameLevel(LineLevel(canvas))
    local thickness = LINE / (WorldMapFrame:GetCanvasScale() or 1)
    local w, h = canvas:GetSize()

    local continent = ns.Nav:Continent(mapID)
    if continent == nil then return end
    if ns.db.smooth and ns.Smooth and ns.Smooth.Network then
        -- The roads as one network: repeated passes merged, loops and side trips faint.
        for _, piece in ipairs(Network(continent)) do
            if piece.faint then
                Draw(Projected(piece, continent, mapID, true), canvas, w, h, thickness * 0.6, DETOUR, DETOUR_EDGE)
            else
                Draw(Projected(piece, continent, mapID, true), canvas, w, h, thickness, ROAD)
            end
        end
    else
        for _, seg in ipairs(ns.db.roads[continent] or {}) do
            Draw(Projected(seg, continent, mapID, true), canvas, w, h, thickness, ROAD)
        end
    end
    -- Caves, drawn as recorded (never smoothed: every point carries a height).
    if ns.db.showCaves then
        for _, seg in ipairs(ns.db.caves[continent] or {}) do
            local xy = {}
            local pts = seg.pts
            for i = 1, #pts - 1, 2 do
                local x, y = ns.Nav:Project(continent, pts[i], pts[i + 1], mapID)
                xy[i], xy[i + 1] = x or false, y or false
            end
            DrawCave(xy, ns.Caves and ns.Caves:Heights(continent, seg), canvas, w, h, thickness)
        end
    end
    local cur = ns.Recorder:Current()
    if cur and cur.continent == continent and cur.kind == "road" then
        Draw(Projected(cur, continent, mapID, false), canvas, w, h, thickness * 1.4, NOW)
    elseif cur and cur.continent == continent and cur.kind == "cave" and ns.db.showCaves then
        local xy = {}
        for i = 1, #cur.pts - 1, 2 do
            local x, y = ns.Nav:Project(continent, cur.pts[i], cur.pts[i + 1], mapID)
            xy[i], xy[i + 1] = x or false, y or false
        end
        Draw(xy, canvas, w, h, thickness * 1.4, CAVE_FLAT, CAVE_EDGE)
    end
end

ns:On("PLAYER_LOGIN", function()
    if not WorldMapFrame then return end
    local function Refresh() Lines:Refresh() end
    hooksecurefunc(WorldMapFrame, "OnMapChanged", Refresh)
    if WorldMapFrame.OnCanvasScaleChanged then hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", Refresh) end
    WorldMapFrame:HookScript("OnShow", Refresh)
    -- The stretch you're on grows as you walk: redraw now and then while the map is open.
    local acc = 0
    CreateFrame("Frame"):SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < REFRESH then return end
        acc = 0
        if WorldMapFrame:IsShown() and ns.Recorder:Current() then Refresh() end
    end)
end)
