local _, ns = ...

-- The world map: every recorded road as tan lines, and the stretch you're walking now brighter.
-- Lines are pooled on the map canvas, like Waypoint's MapPins.lua. Where a stretch lands on a
-- given map is worked out once per map and kept for the session (not saved).
local Lines = {}
ns.MapLines = Lines

local LINE = 2       -- on-screen line thickness
local ROAD = { 0.85, 0.72, 0.48, 0.9 }
local NOW = { 1, 0.93, 0.55, 1 }
local REFRESH = 1    -- seconds between redraws while you record with the map open

local lines, used = {}, 0
local lineFrame
local cache = setmetatable({}, { __mode = "k" }) -- [segment] = { [mapID] = { x1, y1, x2, y2, ... } (false: off the map) }

local function GetLine()
    used = used + 1
    local line = lines[used]
    if not line then
        line = lineFrame:CreateLine(nil, "ARTWORK")
        lines[used] = line
    end
    return line
end

-- A stretch's points as 0-1 fractions on mapID.
local function Projected(seg, continent, mapID, keep)
    local byMap = cache[seg]
    if byMap and byMap[mapID] then return byMap[mapID] end
    local out, pts = {}, seg.pts
    for i = 1, #pts - 1, 2 do
        local x, y = ns.Nav:Project(continent, pts[i], pts[i + 1], mapID)
        out[i], out[i + 1] = x or false, y or false
    end
    if keep then
        cache[seg] = byMap or {}
        cache[seg][mapID] = out
    end
    return out
end

local function Draw(xy, canvas, w, h, thickness, col)
    for i = 3, #xy - 1, 2 do
        local x0, y0, x1, y1 = xy[i - 2], xy[i - 1], xy[i], xy[i + 1]
        if x0 and x1 then
            local line = GetLine()
            line:SetColorTexture(col[1], col[2], col[3], col[4])
            line:SetThickness(thickness)
            line:SetStartPoint("TOPLEFT", canvas, x0 * w, -y0 * h)
            line:SetEndPoint("TOPLEFT", canvas, x1 * w, -y1 * h)
            line:Show()
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
    lineFrame:SetFrameLevel(canvas:GetFrameLevel() + 1900)
    local thickness = LINE / (WorldMapFrame:GetCanvasScale() or 1)
    local w, h = canvas:GetSize()

    local continent = ns.Nav:Continent(mapID)
    if continent == nil then return end
    for _, seg in ipairs(ns.db.roads[continent] or {}) do
        Draw(Projected(seg, continent, mapID, true), canvas, w, h, thickness, ROAD)
    end
    local cur = ns.Recorder:Current()
    if cur and cur.continent == continent then
        Draw(Projected(cur, continent, mapID, false), canvas, w, h, thickness * 1.5, NOW)
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
