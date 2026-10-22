local _, ns = ...
local C = ns.Compat
local U = ns.Units

-- The world map: the waypoint path as numbered pins joined by lines (gold for yours, blue for a
-- teammate's), plus a marker on whatever else the arrow points at.
--   Ctrl+left-click   add a waypoint (asks first)
--   Ctrl+right-click  remove the waypoint nearest the cursor; the path joins up around it
--   Ctrl+Z            undo your last path change (up to 10)
-- Plain clicks are left to the map, so it still zooms in and out. Pins are pooled buttons on the
-- map canvas, like WealthPlanner's.
local Pins = {}
ns.MapPins = Pins
local WM = ns.WorldMap

local PIN = 16       -- on-screen size of a path pin
local TARGET = 24    -- on-screen size of the target marker
local LINE = 2.5     -- on-screen line thickness
local MINE = { 1, 0.79, 0.3 }
local THEIRS = { 0.4, 0.75, 1 }
local DOT = "Interface\\COMMON\\Indicator-Gray"
local GLOW = "Interface\\Cooldown\\star4"
local TARGET_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"

local keys

local function Canvas() return WorldMapFrame:GetCanvas() end

local function OnPinEnter(pin)
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    local p = pin.point
    if pin.isTarget then
        local e = ns.Targets.current
        GameTooltip:AddLine(e and e.title or "Waypoint", MINE[1], MINE[2], MINE[3])
        if e and e.subtitle then GameTooltip:AddLine(e.subtitle, 1, 1, 1, true) end
        GameTooltip:AddLine(ns.Nav:Describe(p), 0.7, 0.7, 0.7)
        local from = e and (e.owner == "Questie" and "Questie" or e.owner)
        if from then GameTooltip:AddLine("From " .. from, 0.4, 0.73, 1) end
    else
        GameTooltip:AddLine(("Waypoint %d%s"):format(pin.index, p.title and (": " .. p.title) or ""), MINE[1], MINE[2], MINE[3])
        GameTooltip:AddLine(ns.Nav:Describe(p), 1, 1, 1)
        if p.by and not U.Same(p.by, U.Me()) then GameTooltip:AddLine("Added by " .. C.Short(p.by), THEIRS[1], THEIRS[2], THEIRS[3]) end
        GameTooltip:AddLine("Ctrl+right-click: remove it", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local function OnPinClick(pin, button)
    if IsControlKeyDown() then
        if button == "RightButton" and not pin.isTarget then
            ns.Chain:Remove(pin.point.id)
        elseif button == "LeftButton" then
            Pins:AddAtCursor()
        end
    elseif button == "RightButton" and WorldMapFrame.NavigateToParentMap then
        WorldMapFrame:NavigateToParentMap()
    end
end

local function CreatePin(pin)
    pin.waypoint = true -- town badges never cover Waypoint's own pins (Towns.lua)
    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pin.glow = pin:CreateTexture(nil, "BACKGROUND")
    pin.glow:SetPoint("CENTER"); pin.glow:SetTexture(GLOW); pin.glow:SetBlendMode("ADD")
    pin.icon = pin:CreateTexture(nil, "ARTWORK"); pin.icon:SetAllPoints()
    pin.num = pin:CreateFontString(nil, "OVERLAY", "WaypointGameFontHighlightSmall")
    pin.num:SetPoint("CENTER", 0, 0)
    pin:SetScript("OnEnter", OnPinEnter)
    pin:SetScript("OnLeave", GameTooltip_Hide)
    pin:SetScript("OnClick", OnPinClick)
end

-- Pins and lines keep their size on screen however far the map is zoomed (the shared
-- WorldMap.lua layer below): lines at +2000 over the map's art, pins at +2100.
local function Refresh(layer, mapID)
    if not ns.db then return end
    local e, current = ns.Targets.current, ns.Targets.point
    local me = U.Me()

    -- The path: lines first, then numbered pins on top.
    local prevX, prevY
    for i, p in ipairs(ns.Chain:Points()) do
        local px, py = ns.Nav:OnCanvas(p.mapID, p.x, p.y, mapID)
        local col = U.Same(p.by, me) and MINE or THEIRS
        if px then
            if prevX then layer:Line(prevX, prevY, px, py, col, LINE, 0.85) end
            local pin = layer:Pin()
            pin.point, pin.index, pin.isTarget = p, i, nil
            pin.icon:SetTexture(DOT); pin.icon:SetVertexColor(col[1], col[2], col[3])
            pin.num:SetText(i)
            local isCurrent = e and e.owner == "path" and current == p
            pin.glow:SetShown(isCurrent and true or false)
            pin.glow:SetSize(PIN * 2.2, PIN * 2.2); pin.glow:SetVertexColor(col[1], col[2], col[3], 0.8)
            layer:Place(pin, px, py, PIN)
        end
        prevX, prevY = px, py
    end

    -- Anything else the arrow points at.
    if e and e.owner ~= "path" and current then
        local px, py = ns.Nav:OnCanvas(current.mapID, current.x, current.y, mapID)
        if px then
            local pin = layer:Pin()
            pin.point, pin.index, pin.isTarget = current, nil, true
            -- A request ("Navigate to") gets Waypoint's own icon, so it stands out from other targets.
            pin.icon:SetTexture(e.request and ns.ICON or TARGET_ICON); pin.icon:SetVertexColor(1, 1, 1)
            pin.num:SetText("")
            local col = ns:ColorOf(e)
            pin.glow:Show(); pin.glow:SetSize(TARGET * 1.8, TARGET * 1.8); pin.glow:SetVertexColor(col[1], col[2], col[3], 0.8)
            layer:Place(pin, px, py, TARGET)
        end
    end
end

-- One layer on the world map (shared WorldMap.lua): redrawn when the map, its zoom or its
-- visibility changes, and every half second while it's open (the current target can move as you
-- walk: the nearest spawn).
Pins.layer = WM.NewLayer({ lines = true, level = 2000, pinLevel = 2100, create = CreatePin, refresh = Refresh, interval = 0.5 })

function Pins:Refresh()
    if ns.db then Pins.layer:Refresh() end
end

-- Where the cursor is on the map, as a zone point when it's over one: mapID, x, y. On OpenMap's
-- stitched map, past the map underneath too: the zone OpenMap draws there.
local function CursorPoint()
    local mapID = WorldMapFrame:GetMapID()
    local x, y = WorldMapFrame:GetNormalizedCursorPosition()
    if not (mapID and x and y) then return nil end
    if x < 0 or x > 1 or y < 0 or y > 1 then return ns.Nav:FromCanvas(mapID, x, y) end
    local info = C.Call(C_Map.GetMapInfoAtPosition, mapID, x, y)
    if info and info.mapID and info.mapID ~= mapID and Enum and Enum.UIMapType and info.mapType == Enum.UIMapType.Zone then
        local zx, zy = ns.Nav:Project(mapID, x, y, info.mapID)
        if zx then return info.mapID, zx, zy end
    end
    return mapID, x, y
end

function Pins:AddAtCursor()
    local mapID, x, y = CursorPoint()
    if mapID then ns.Chain:Request(mapID, x, y) end
end

function Pins:RemoveAtCursor()
    local mapID = WorldMapFrame:GetMapID()
    local x, y = WorldMapFrame:GetNormalizedCursorPosition()
    if not (mapID and x) then return end
    local w, h = Canvas():GetSize()
    ns.Chain:RemoveNearest(mapID, x, y, (h and h > 0) and w / h or 1)
end

-- Ctrl+clicks on the map. True when the click was ours.
local function OnCanvasClick(_, button)
    if not IsControlKeyDown() then return false end
    if button == "LeftButton" then
        Pins:AddAtCursor()
        return true
    elseif button == "RightButton" then
        Pins:RemoveAtCursor()
        return true
    end
    return false
end

-- Ctrl+Z while the map is open. Every other key goes on to the game as usual.
local function HookKeys()
    keys = CreateFrame("Frame", nil, WorldMapFrame)
    keys:EnableKeyboard(true)
    if not InCombatLockdown() then keys:SetPropagateKeyboardInput(true) end
    keys:SetScript("OnKeyDown", function(self, key)
        local undoKey = key == "Z" and IsControlKeyDown()
        if not InCombatLockdown() then self:SetPropagateKeyboardInput(not undoKey) end
        if undoKey then ns.Chain:Undo() end
    end)
end

ns:On("PLAYER_LOGIN", function()
    if not WorldMapFrame then return end
    if WorldMapFrame.AddCanvasClickHandler then
        WorldMapFrame:AddCanvasClickHandler(OnCanvasClick, 10000)
    elseif WorldMapFrame.ScrollContainer then
        WorldMapFrame.ScrollContainer:HookScript("OnMouseUp", function(_, button) OnCanvasClick(nil, button) end)
    end
    HookKeys()
end)
