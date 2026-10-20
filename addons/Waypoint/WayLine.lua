local _, ns = ...
local C = ns.Compat

-- The planned trip (Route.lua's R:Lines) drawn as a dashed line: on the world map the whole way,
-- on the minimap the part around you as a trail of dots. Each kind of travel has a colour family
-- (walking yellow, flights and rides purple, jumps red, swimming green) of 10 shades; each stage
-- of the plan (a task the arrow follows, a waypoint of your path) takes its own shade, so the legs
-- of a path you dropped stand apart. Walks, swims and jumps follow the land map; flights and
-- rides are drawn straight from stop to stop.
-- Seeing it shows straight away when the land map has the ground wrong: walk the pass it missed
-- once and it learns it (Route.lua), or mark it in RoadLog.
local Way = {}
ns.WayLine = Way

-- Hue (degrees), saturation and brightness range of each family.
local FAMILIES = {
    yellow = { 38, 64, 0.65, 1.0 },
    purple = { 252, 302, 0.45, 0.85 },
    red = { -12, 18, 0.65, 0.95 },
    green = { 82, 150, 0.55, 0.9 },
}
local FAMILY = { walk = "yellow", fly = "purple", ride = "purple", drop = "red", swim = "green" }
-- The shades in the order stages take them: each is several steps from the one before.
local ORDER = { 0, 5, 2, 7, 4, 9, 1, 6, 3, 8 }

local function HSV(h, s, v)
    h = (h % 360) / 60
    local i, f = math.floor(h), h - math.floor(h)
    local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    if i == 0 then return v, t, p elseif i == 1 then return q, v, p elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v elseif i == 4 then return t, p, v end
    return v, p, q
end

-- PALETTE[family][1..10]: shades running across the family's hues, light and dark alternating.
local PALETTE = {}
for name, f in pairs(FAMILIES) do
    local shades = {}
    for k = 1, 10 do
        local i = ORDER[k]
        local t = i / 9
        local hue = f[1] + (f[2] - f[1]) * t
        local value = (i % 2 == 0) and 1.0 or 0.72
        local r, g, b = HSV(hue, f[3] + (f[4] - f[3]) * (1 - t), value)
        shades[k] = { r, g, b }
    end
    PALETTE[name] = shades
end
Way.PALETTE = PALETTE

-- A line's colour: its kind's family, at its stage's shade.
local function Color(seg)
    local shades = PALETTE[FAMILY[seg.kind] or "yellow"]
    return shades[seg.shade or 1] or shades[1]
end
local LINE = 2.25       -- world map: on-screen thickness
local DASH, GAP = 4, 2  -- world map: on-screen dash and gap lengths (fine, so the route's bends show)
local REFRESH = 1      -- world map: seconds between redraws while it's open
local DOT = 5          -- minimap: dot size
local DOTS = 120       -- minimap: dots at most
local MINI_UPDATE = 0.1

local function Lines()
    return ns.Route and ns.Route:Lines()
end

-- ---------------------------------------------------------------------------------------------
-- World map
-- ---------------------------------------------------------------------------------------------

local lines, used = {}, 0
local frame

local function GetLine()
    used = used + 1
    local line = lines[used]
    if not line then
        line = frame:CreateLine(nil, "ARTWORK")
        lines[used] = line
    end
    return line
end

-- A world point on mapID, as 0-1 fractions (nil off it). On OpenMap's stitched map the view runs
-- past mapID's own rectangle: there OpenMap says where the point is on the canvas, past 0-1 too.
local function Project(continent, n, w, mapID)
    if OpenMapAPI and OpenMapAPI.IsStitched and OpenMapAPI.CanvasFromWorldPos and OpenMapAPI.IsStitched() then
        local x, y = OpenMapAPI.CanvasFromWorldPos(continent, n, w)
        if x then return x, y end
    end
    if not (CreateVector2D and C_Map.GetMapPosFromWorldPos) then return nil end
    local _, pos = C.Call(C_Map.GetMapPosFromWorldPos, continent, CreateVector2D(n, w), mapID)
    if not pos then return nil end
    local x, y = pos:GetXY()
    if x and x >= -0.05 and x <= 1.05 and y >= -0.05 and y <= 1.05 then return x, y end
end

-- A polyline in canvas units (x, y down) as dashes, carrying the dash pattern across its corners.
local function Dashed(xy, canvas, thickness, col, scale)
    local dash, gap = DASH * scale, GAP * scale
    local on, left = true, dash
    for i = 3, #xy - 1, 2 do
        local x0, y0, x1, y1 = xy[i - 2], xy[i - 1], xy[i], xy[i + 1]
        local len = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
        local at = 0
        while at < len do
            local step = math.min(left, len - at)
            if on then
                local a, b = at / len, (at + step) / len
                local line = GetLine()
                line:SetColorTexture(col[1], col[2], col[3], 0.9)
                line:SetThickness(thickness)
                line:SetStartPoint("TOPLEFT", canvas, x0 + (x1 - x0) * a, -(y0 + (y1 - y0) * a))
                line:SetEndPoint("TOPLEFT", canvas, x0 + (x1 - x0) * b, -(y0 + (y1 - y0) * b))
                line:Show()
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

function Way:Refresh()
    if not (ns.db and WorldMapFrame and WorldMapFrame:IsShown()) then return end
    for i = 1, used do lines[i]:Hide() end
    used = 0
    local trip = ns.db.showWay and Lines()
    local mapID = WorldMapFrame:GetMapID()
    local canvas = WorldMapFrame:GetCanvas()
    if not (trip and mapID and canvas and canvas.CreateLine) then return end
    if not frame then
        frame = CreateFrame("Frame", nil, canvas)
        frame:SetAllPoints(canvas)
    end
    frame:SetFrameLevel(ns:MapBase(canvas) + 2050)
    local scale = 1 / (WorldMapFrame:GetCanvasScale() or 1)
    local w, h = canvas:GetSize()
    for _, seg in ipairs(trip) do
        local xy, run = {}, nil
        local function Flush()
            if run and #run >= 4 then Dashed(run, canvas, LINE * scale, Color(seg), scale) end
            run = nil
        end
        for i = 1, #seg.pts - 1, 2 do
            local x, y = Project(seg.continent, seg.pts[i], seg.pts[i + 1], mapID)
            if x then
                run = run or {}
                run[#run + 1], run[#run + 2] = x * w, y * h
            else
                Flush() -- off this map: the line breaks there
            end
        end
        Flush()
    end
end

-- ---------------------------------------------------------------------------------------------
-- Minimap: the part of the trip around you, as dots
-- ---------------------------------------------------------------------------------------------

-- Minimap diameter in yards at each zoom level (as MinimapPin.lua).
local OUTDOOR = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }
local INDOOR = { [0] = 300, 240, 180, 120, 80, 50 }

local dots, shownDots = {}, 0

local function GetDot(i)
    local dot = dots[i]
    if not dot then
        dot = Minimap:CreateTexture(nil, "OVERLAY")
        dot:SetTexture("Interface\\COMMON\\Indicator-Gray")
        dot:SetSize(DOT, DOT)
        dots[i] = dot
    end
    return dot
end

local function UpdateMinimap()
    if not Minimap then return end
    local count = 0
    local trip = ns.db and ns.db.showWayMinimap and not ns:InBattleground() and Lines()
    local c, n, w = ns.Nav:Player()
    if trip and c then
        local zoom = Minimap:GetZoom() or 0
        local t = (IsIndoors and IsIndoors()) and INDOOR or OUTDOOR
        local radius, half = (t[zoom] or t[0]) / 2, Minimap:GetWidth() / 2
        local spacing = radius / 10
        local rotate = GetCVar and GetCVar("rotateMinimap") == "1"
        local sin, cos = 0, 1
        if rotate then
            local facing = GetPlayerFacing and C.Num(GetPlayerFacing())
            if facing then sin, cos = math.sin(facing), math.cos(facing) end
        end
        local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
        local edge = radius * 0.95
        local function Place(pn, pw, col)
            local x, y = w - pw, n - pn -- yards east, yards south
            if rotate then x, y = x * cos - y * sin, x * sin + y * cos end
            local inside = square and (math.abs(x) <= edge and math.abs(y) <= edge) or (x * x + y * y <= edge * edge)
            if not inside or count >= DOTS then return end
            count = count + 1
            local dot = GetDot(count)
            dot:SetVertexColor(col[1], col[2], col[3], 0.95)
            dot:ClearAllPoints()
            dot:SetPoint("CENTER", Minimap, "CENTER", x / radius * half, -y / radius * half)
            dot:Show()
        end
        for _, seg in ipairs(trip) do
            if seg.continent == c then
                local col = Color(seg)
                local carry = 0
                for i = 3, #seg.pts - 1, 2 do
                    local n0, w0, n1, w1 = seg.pts[i - 2], seg.pts[i - 1], seg.pts[i], seg.pts[i + 1]
                    local len = math.sqrt((n1 - n0) ^ 2 + (w1 - w0) ^ 2)
                    local at = carry
                    while at < len do
                        local f = at / len
                        Place(n0 + (n1 - n0) * f, w0 + (w1 - w0) * f, col)
                        at = at + spacing
                    end
                    carry = at - len
                end
            end
        end
    end
    for i = count + 1, shownDots do dots[i]:Hide() end
    shownDots = count
end

ns:On("PLAYER_LOGIN", function()
    if WorldMapFrame then
        local function Refresh() Way:Refresh() end
        hooksecurefunc(WorldMapFrame, "OnMapChanged", Refresh)
        if WorldMapFrame.OnCanvasScaleChanged then hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", Refresh) end
        WorldMapFrame:HookScript("OnShow", Refresh)
        -- OpenMap switching between its stitched map and Blizzard's: the line, the pins and the
        -- town badges go somewhere else, at other levels.
        if OpenMapAPI and OpenMapAPI.RegisterCallback then
            pcall(OpenMapAPI.RegisterCallback, Way, "OpenMap_StitchedChanged", function()
                Refresh()
                ns:Changed()
            end)
        end
    end
    local mapAcc, miniAcc = 0, 0
    CreateFrame("Frame"):SetScript("OnUpdate", function(_, elapsed)
        mapAcc, miniAcc = mapAcc + elapsed, miniAcc + elapsed
        if mapAcc >= REFRESH then
            mapAcc = 0
            if WorldMapFrame and WorldMapFrame:IsShown() then Way:Refresh() end
        end
        if miniAcc >= MINI_UPDATE then
            miniAcc = 0
            UpdateMinimap()
        end
    end)
end)
