local _, ns = ...

-- The world map's blockers and narrow passes. Blockers (walls, fences, cliff edges you walked
-- along) are red lines in a dark casing; the one you're logging now is brighter. Narrow passes are
-- blue spots in a dark ring and zone transitions purple ones, with a tooltip; Shift+right-click
-- one to remove it. Drawn on their own frame
-- just above RoadLog's roads (MapLines.lua), pooled like them.
local Marks = {}
ns.Marks = Marks

local LINE = 2.5     -- on-screen thickness of a blocker
local CASING = 2.0   -- its casing's width, times the line's
local EDGE = { 0.15, 0.02, 0.02, 0.85 }
local BLOCKER = { 0.95, 0.25, 0.2, 0.95 }
local NOW = { 1, 0.45, 0.35, 1 }
local PIN = 11       -- on-screen size of a narrow pass spot
local SPOT = { 0.25, 0.6, 1, 1 }           -- a narrow pass
local TRANSITION = { 0.75, 0.45, 1, 1 }     -- a zone transition
local RING = { 0.02, 0.06, 0.18, 0.9 }
local ROUND = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask" -- a round mask
local REFRESH = 1    -- seconds between redraws while you log blockers with the map open

local frame
local lines, used = {}, 0
local pins, usedPins = {}, 0

local function GetLine()
    used = used + 1
    local line = lines[used]
    if not line then
        line = frame:CreateLine(nil, "ARTWORK")
        lines[used] = line
    end
    return line
end

local function OnPinEnter(pin)
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    if pin.kind == "transitions" then
        GameTooltip:AddLine(pin.mark.label or "Zone transition", TRANSITION[1], TRANSITION[2], TRANSITION[3])
        GameTooltip:AddLine("Zone transition", 1, 1, 1)
    else
        GameTooltip:AddLine("Narrow pass", SPOT[1], SPOT[2], SPOT[3])
        GameTooltip:AddLine("You can get through here.", 1, 1, 1)
    end
    if pin.mark and pin.mark.zone then GameTooltip:AddLine(ns.Nav:ZoneName(pin.mark.zone), 0.7, 0.7, 0.7) end
    GameTooltip:AddLine("Shift+right-click: remove", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function OnPinClick(pin, button)
    if button == "RightButton" and IsShiftKeyDown() then
        GameTooltip:Hide()
        ns.Recorder:RemoveMark(pin.continent, pin.mark, pin.kind)
    elseif button == "RightButton" and WorldMapFrame.NavigateToParentMap then
        WorldMapFrame:NavigateToParentMap()
    end
end

local function GetPin(canvas)
    usedPins = usedPins + 1
    local pin = pins[usedPins]
    if not pin then
        pin = CreateFrame("Button", nil, canvas)
        pin:RegisterForClicks("RightButtonUp")
        -- A blue spot in a dark ring: two colour fills, cut round by a mask.
        pin.ring = pin:CreateTexture(nil, "ARTWORK", nil, 0)
        pin.ring:SetAllPoints()
        pin.ring:SetColorTexture(RING[1], RING[2], RING[3], RING[4])
        pin.spot = pin:CreateTexture(nil, "ARTWORK", nil, 1)
        pin.spot:SetPoint("TOPLEFT", 2, -2)
        pin.spot:SetPoint("BOTTOMRIGHT", -2, 2)
        pin.spot:SetColorTexture(SPOT[1], SPOT[2], SPOT[3], SPOT[4])
        if pin.CreateMaskTexture then
            for _, tex in ipairs({ pin.ring, pin.spot }) do
                local mask = pin:CreateMaskTexture()
                mask:SetTexture(ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                mask:SetAllPoints(tex)
                tex:AddMaskTexture(mask)
            end
        end
        pin:SetScript("OnEnter", OnPinEnter)
        pin:SetScript("OnLeave", GameTooltip_Hide)
        pin:SetScript("OnClick", OnPinClick)
        pins[usedPins] = pin
    end
    return pin
end

-- A blocker's points on mapID, as 0-1 fractions (false where it's off the map).
local function Projected(pts, continent, mapID)
    local out = {}
    for i = 1, #pts - 1, 2 do
        local x, y = ns.Nav:Project(continent, pts[i], pts[i + 1], mapID)
        out[i], out[i + 1] = x or false, y or false
    end
    return out
end

local function Draw(xy, canvas, w, h, thickness, col)
    for pass = 1, 2 do
        local c = pass == 1 and EDGE or col
        for i = 3, #xy - 1, 2 do
            local x0, y0, x1, y1 = xy[i - 2], xy[i - 1], xy[i], xy[i + 1]
            if x0 and x1 then
                local line = GetLine()
                line:SetDrawLayer("ARTWORK", pass == 1 and 0 or 1)
                line:SetColorTexture(c[1], c[2], c[3], c[4])
                line:SetThickness(pass == 1 and thickness * CASING or thickness)
                line:SetStartPoint("TOPLEFT", canvas, x0 * w, -y0 * h)
                line:SetEndPoint("TOPLEFT", canvas, x1 * w, -y1 * h)
                line:Show()
            end
        end
    end
end

function Marks:Refresh()
    if not (ns.db and WorldMapFrame and WorldMapFrame:IsShown()) then return end
    for i = 1, used do lines[i]:Hide() end
    for i = 1, usedPins do pins[i]:Hide() end
    used, usedPins = 0, 0
    local mapID = WorldMapFrame:GetMapID()
    local canvas = WorldMapFrame:GetCanvas()
    if not (mapID and canvas and canvas.CreateLine) then return end
    if not frame then
        frame = CreateFrame("Frame", nil, canvas)
        frame:SetAllPoints(canvas)
    end
    -- Just above the roads (MapLines keeps its own under Waypoint's pins, at +2100).
    frame:SetFrameLevel(canvas:GetFrameLevel() + 2095)
    local continent = ns.Nav:Continent(mapID)
    if continent == nil then return end
    local scale = 1 / (WorldMapFrame:GetCanvasScale() or 1)
    local w, h = canvas:GetSize()

    if ns.db.showBlockers then
        for _, seg in ipairs(ns.db.blockers[continent] or {}) do
            Draw(Projected(seg.pts, continent, mapID), canvas, w, h, LINE * scale, BLOCKER)
        end
        local cur = ns.Recorder:Current()
        if cur and cur.kind == "blocker" and cur.continent == continent then
            Draw(Projected(cur.pts, continent, mapID), canvas, w, h, LINE * 1.4 * scale, NOW)
        end
    end
    for _, kind in ipairs({ "passes", "transitions" }) do
        local show = kind == "passes" and ns.db.showPasses or kind == "transitions" and ns.db.showTransitions
        local col = kind == "transitions" and TRANSITION or SPOT
        for _, mark in ipairs(show and ns.db[kind][continent] or {}) do
            local x, y = ns.Nav:Project(continent, mark.n, mark.w, mapID)
            if x then
                local pin = GetPin(canvas)
                pin.mark, pin.continent, pin.kind = mark, continent, kind
                pin.spot:SetColorTexture(col[1], col[2], col[3], col[4])
                pin:SetSize(PIN, PIN)
                pin:SetScale(scale)
                pin:SetFrameLevel(frame:GetFrameLevel() + 1)
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", canvas, "TOPLEFT", x * w / scale, -y * h / scale)
                pin:Show()
            end
        end
    end
end

ns:On("PLAYER_LOGIN", function()
    if not WorldMapFrame then return end
    local function Refresh() Marks:Refresh() end
    hooksecurefunc(WorldMapFrame, "OnMapChanged", Refresh)
    if WorldMapFrame.OnCanvasScaleChanged then hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", Refresh) end
    WorldMapFrame:HookScript("OnShow", Refresh)
    -- The blocker you're logging grows as you walk: redraw now and then while the map is open.
    local acc = 0
    CreateFrame("Frame"):SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < REFRESH then return end
        acc = 0
        local cur = ns.Recorder:Current()
        if WorldMapFrame:IsShown() and cur and cur.kind == "blocker" then Refresh() end
    end)
end)
