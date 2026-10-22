local _, ns = ...
local C = ns.Compat
local U = ns.Units

-- The world map: the waypoint path as numbered pins joined by lines (gold for yours, blue for a
-- teammate's), plus a marker on whatever else the arrow points at. Every pin on the map is one of
-- these and works the same: Blizzard's pin is the first waypoint (Chain.lua), but its map icon is
-- hidden under Waypoint's own, so there's one way to remove anything.
--   Ctrl+click        add a waypoint (Waypoint takes these over from Blizzard's map); on a town,
--                     dock or path pin too
--   Ctrl+right-click  on a pin: remove that one (any waypoint of the path, a "navigate to", an
--                     addon's target); elsewhere: the waypoint nearest the cursor
--   Ctrl+Z            undo your last path change (up to 10)
-- Plain clicks are left to the map (and to the pins), so it still zooms in and out. Pins are pooled
-- buttons on the map canvas, like WealthPlanner's.
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
    if pin.preview then
        GameTooltip:AddLine(pin.preview.title, THEIRS[1], THEIRS[2], THEIRS[3])
        GameTooltip:AddLine((p.title and (p.title .. ", ") or "") .. ns.Nav:Describe(p), 1, 1, 1)
        if pin.preview.note then GameTooltip:AddLine(pin.preview.note, 0.6, 0.6, 0.6, true) end
    elseif pin.isTarget then
        local e = ns.Targets.current
        GameTooltip:AddLine(e and e.title or "Waypoint", MINE[1], MINE[2], MINE[3])
        if e and e.subtitle then GameTooltip:AddLine(e.subtitle, 1, 1, 1, true) end
        GameTooltip:AddLine(ns.Nav:Describe(p), 0.7, 0.7, 0.7)
        local from = e and (e.request and "your Navigate to" or e.owner == "Questie" and "Questie" or e.owner)
        if from then GameTooltip:AddLine("From " .. from, 0.4, 0.73, 1) end
        GameTooltip:AddLine("Ctrl+right-click: remove it", 0.6, 0.6, 0.6)
    else
        GameTooltip:AddLine(("Waypoint %d%s"):format(pin.index, p.title and (": " .. p.title) or ""), MINE[1], MINE[2], MINE[3])
        GameTooltip:AddLine(ns.Nav:Describe(p), 1, 1, 1)
        if p.by and not U.Same(p.by, U.Me()) then GameTooltip:AddLine("Added by " .. C.Short(p.by), THEIRS[1], THEIRS[2], THEIRS[3]) end
        GameTooltip:AddLine("Ctrl+right-click: remove it", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local function OnPinClick(pin, button)
    if Pins:AddClick(button) then
        Pins:AddAtCursor()
    elseif IsControlKeyDown() then
        if button == "RightButton" then Pins:RemovePin(pin) end
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

    -- The path: lines first, then numbered pins on top. A leg the trip line already shows along
    -- the land (WayLine.lua: the one you're on and Route.lua's next STAGES on that continent)
    -- gets no straight line too; the rest (further on, over the sea, the trip line off) do.
    local points = ns.Chain:Points()
    local planned = {}
    if ns.db.showWay and e and e.owner == "path" and ns.Route and ns.Route.STAGES then
        local start
        for i, q in ipairs(points) do
            if q == current then start = i end
        end
        if start then
            for i = start + 1, math.min(#points, start + ns.Route.STAGES) do
                local a, b = ns.Nav:World(points[i - 1]), ns.Nav:World(points[i])
                if a and a == b then planned[i] = true end
            end
        end
    end
    local prevX, prevY
    for i, p in ipairs(points) do
        local px, py = ns.Nav:OnCanvas(p.mapID, p.x, p.y, mapID)
        local col = U.Same(p.by, me) and MINE or THEIRS
        if px then
            if prevX and not planned[i] then layer:Line(prevX, prevY, px, py, col, LINE, 0.85) end
        end
        -- The first waypoint is Blizzard's pin when the game took it: no second pin on top of it.
        if px then
            local pin = layer:Pin()
            pin.point, pin.index, pin.isTarget, pin.preview = p, i, nil, nil
            pin.icon:SetTexture(DOT); pin.icon:SetVertexColor(col[1], col[2], col[3])
            pin.num:SetText(i)
            local isCurrent = e and e.owner == "path" and current == p
            pin.glow:SetShown(isCurrent and true or false)
            pin.glow:SetSize(PIN * 2.2, PIN * 2.2); pin.glow:SetVertexColor(col[1], col[2], col[3], 0.8)
            layer:Place(pin, px, py, PIN)
        end
        prevX, prevY = px, py
    end

    -- A teammate's waypoint you were shown before deciding (Comm.lua's offer): marked, not on the path.
    local pv = Pins.preview
    if pv then
        local px, py = ns.Nav:OnCanvas(pv.p.mapID, pv.p.x, pv.p.y, mapID)
        if px then
            local pin = layer:Pin()
            pin.point, pin.index, pin.isTarget, pin.preview = pv.p, nil, nil, pv
            pin.icon:SetTexture(TARGET_ICON); pin.icon:SetVertexColor(THEIRS[1], THEIRS[2], THEIRS[3])
            pin.num:SetText("")
            pin.glow:Show(); pin.glow:SetSize(TARGET * 2.4, TARGET * 2.4); pin.glow:SetVertexColor(THEIRS[1], THEIRS[2], THEIRS[3], 0.9)
            layer:Place(pin, px, py, TARGET)
        end
    end

    -- Anything else the arrow points at.
    if e and e.owner ~= "path" and current then
        local px, py = ns.Nav:OnCanvas(current.mapID, current.x, current.y, mapID)
        if px then
            local pin = layer:Pin()
            pin.point, pin.index, pin.isTarget, pin.preview = current, nil, true, nil
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

-- Blizzard's own map icon for its pin, hidden while the pin is one of Waypoint's (the same spot
-- has Waypoint's pin, which removes the same way as every other). Its arrow and tracking stay.
local hooked = setmetatable({}, { __mode = "k" })
local function HideBlizzardPins()
    if not (WorldMapFrame and WorldMapFrame.EnumeratePinsByTemplate) then return end
    local ours = ns.Chain:IsOurs()
    for pin in WorldMapFrame:EnumeratePinsByTemplate("WaypointLocationPinTemplate") do
        if not hooked[pin] then
            hooked[pin] = true
            -- The map shows it again whenever it redraws: hide it then too.
            hooksecurefunc(pin, "Show", function(self) if ns.Chain:IsOurs() then self:Hide() end end)
        end
        if ours then pin:Hide() end
    end
end

-- Ctrl+right-click on one of Waypoint's pins: remove that one.
function Pins:RemovePin(pin)
    if pin.preview then
        self:ClearPreview()
    elseif pin.isTarget then
        ns.Targets:Skip(false) -- the request, an addon's target, a Questie objective: as the arrow's right-click
    elseif pin.point and pin.point.id then
        ns.Chain:Remove(pin.point.id)
    end
end

function Pins:Refresh()
    if ns.db then
        Pins.layer:Refresh()
        HideBlizzardPins()
    end
end

-- Marks a point that isn't on the path (a teammate's waypoint you're deciding about).
function Pins:Preview(p, title, note)
    self.preview = { p = p, title = title, note = note }
    self:Refresh()
end

function Pins:ClearPreview()
    if not self.preview then return end
    self.preview = nil
    self:Refresh()
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

-- Whether this click adds a waypoint: Ctrl+left-click (the map's own pins call it too, so one on
-- a town or dock adds there).
function Pins:AddClick(button)
    return button == "LeftButton" and IsControlKeyDown() and not IsShiftKeyDown() and not IsAltKeyDown()
end

-- Adds a waypoint from a click on a map. One click can reach Waypoint twice (its own map handler
-- and OpenMap's, OpenMap.lua): the second, at the same spot within a moment, is the same click.
local lastAdd
function Pins:Add(mapID, x, y)
    local now = GetTime()
    local last = lastAdd
    if last and now - last.t < 0.3 and last.mapID == mapID and math.abs(last.x - x) < 0.01 and math.abs(last.y - y) < 0.01 then return end
    lastAdd = { t = now, mapID = mapID, x = x, y = y }
    ns.Chain:Request(mapID, x, y)
end

function Pins:AddAtCursor()
    local mapID, x, y = CursorPoint()
    if mapID then self:Add(mapID, x, y) end
end

function Pins:RemoveAtCursor()
    local mapID = WorldMapFrame:GetMapID()
    local x, y = WorldMapFrame:GetNormalizedCursorPosition()
    if not (mapID and x) then return end
    local w, h = Canvas():GetSize()
    ns.Chain:RemoveNearest(mapID, x, y, (h and h > 0) and w / h or 1)
end

-- Clicks on the map: Ctrl+click adds a waypoint, Ctrl+right-click removes the nearest. True when
-- the click was ours: run before Blizzard's own Ctrl+click pin, which then doesn't happen (every
-- waypoint goes through the path, and the path sets Blizzard's pin: Chain.lua).
local function OnCanvasClick(_, button)
    if Pins:AddClick(button) then
        Pins:AddAtCursor()
        return true
    end
    if button == "RightButton" and IsControlKeyDown() then
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

-- Blizzard's "place a map pin" button on the world map's edge: Waypoint's Ctrl+click does that now,
-- so it's hidden, and the buttons stacked under it move up into its place. Found by what it is
-- (the game's WorldMapTrackingPinButtonMixin, or its name), so other addons' buttons are left alone.
local function IsPinButton(f)
    local mixin = rawget(_G, "WorldMapTrackingPinButtonMixin")
    if type(mixin) == "table" and mixin.OnClick and f.OnClick == mixin.OnClick then return true end
    local name = f.GetName and f:GetName()
    return type(name) == "string" and name:find("TrackingPin") ~= nil
end

local function HidePinButton()
    if not (WorldMapFrame and WorldMapFrame.overlayFrames) then return end
    for _, f in ipairs(WorldMapFrame.overlayFrames) do
        if IsPinButton(f) then
            if not f.waypointHidden then
                f.waypointHidden = true
                -- Whatever was anchored to it takes its place, so no gap is left.
                local point, rel, relPoint, x, y = f:GetPoint(1)
                for _, other in ipairs(WorldMapFrame.overlayFrames) do
                    local op, orel = other:GetPoint(1)
                    if other ~= f and orel == f and point then
                        other:ClearAllPoints()
                        other:SetPoint(op == point and op or point, rel, relPoint, x, y)
                    end
                end
                f:HookScript("OnShow", function(self) self:Hide() end)
            end
            f:Hide()
        end
    end
end

ns:On("PLAYER_LOGIN", function()
    if not WorldMapFrame then return end
    if WorldMapFrame.AddCanvasClickHandler then
        WorldMapFrame:AddCanvasClickHandler(OnCanvasClick, 10000)
    elseif WorldMapFrame.ScrollContainer then
        WorldMapFrame.ScrollContainer:HookScript("OnMouseUp", function(_, button) OnCanvasClick(nil, button) end)
    end
    HookKeys()
    HidePinButton()
    -- The map may add its buttons only when it first opens.
    WorldMapFrame:HookScript("OnShow", HidePinButton)
end)
