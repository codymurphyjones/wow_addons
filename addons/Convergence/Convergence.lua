local addonName, ns = ...

-- Draws a pin for every known convergence on the world map. Pins show on the zone's own map
-- and on any map that contains it (continent, world), so you can plan a route past them.
-- Click a pin to point the Waypoint addon's arrow at it (Shift: every spot, nearest first), or, without
-- Waypoint, to set the game's own map waypoint on it.

-- Four elements converging on a bright spark, in a teal-edged badge (Media\make_icon.py draws it).
local ICON = "Interface\\AddOns\\" .. addonName .. "\\Media\\Pin"
local SIZE = 12 -- on-screen size, kept the same at every zoom level

local WM = ns.WorldMap

-- The Waypoint addon's arrow, when it's installed.
local function HasArrow() return type(Waypoint) == "table" and Waypoint.Set ~= nil end

local function ZoneName(id) return WM.ZoneName(id, "") end

local function OnEnter(pin)
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Elemental Convergence", 0.33, 0.92, 0.78)
    GameTooltip:AddLine(string.format("%s  %.1f, %.1f", pin.zoneName or "", pin.x, pin.y), 1, 1, 1)
    if HasArrow() then
        GameTooltip:AddLine("Click: point the Waypoint arrow here", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Shift-click: lead to the nearest convergence, then the next", 0.6, 0.6, 0.6)
    elseif C_Map.SetUserWaypoint then
        GameTooltip:AddLine("Click to set a waypoint", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

-- Hands the spot (or, with Shift, every known spot) to Waypoint's arrow. Nearest first, then on.
local function SetArrow(pin, all)
    local points = {}
    if all then
        for zoneID, list in pairs(ns.POINTS) do
            for _, p in ipairs(list) do points[#points + 1] = { mapID = zoneID, x = p[1] / 100, y = p[2] / 100 } end
        end
    else
        points[1] = { mapID = pin.mapID, x = pin.x / 100, y = pin.y / 100 }
    end
    pcall(Waypoint.Set, Waypoint, "Convergence", {
        title = "Elemental Convergence",
        subtitle = all and ("%d known spots, nearest first"):format(#points)
            or string.format("%s  %.1f, %.1f", pin.zoneName or "", pin.x, pin.y),
        points = points, arrive = 20,
    })
end

local function OnClick(pin)
    if HasArrow() then return SetArrow(pin, IsShiftKeyDown()) end
    if not (C_Map.SetUserWaypoint and UiMapPoint) then return end
    local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(pin.mapID, pin.x / 100, pin.y / 100))
    if ok and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
end

-- The pins: one layer on the world map (shared WorldMap.lua), redrawn when the map, its zoom or
-- its visibility changes. Pins show on the zone's own map and every map that contains it.
local function CreatePin(pin)
    local icon = pin:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(ICON)
    local glow = pin:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints()
    glow:SetTexture(ICON)
    glow:SetBlendMode("ADD")
    glow:SetAlpha(0.4)
    pin:SetScript("OnEnter", OnEnter)
    pin:SetScript("OnLeave", GameTooltip_Hide)
    pin:SetScript("OnClick", OnClick)
end

local function Refresh(layer)
    for zoneID, list in pairs(ns.POINTS) do
        for _, p in ipairs(list) do
            local pin = layer:PinAt(zoneID, p[1] / 100, p[2] / 100)
            if pin then pin.mapID, pin.x, pin.y, pin.zoneName = zoneID, p[1], p[2], ZoneName(zoneID) end
        end
    end
end

-- base "canvas" and stitched = false: the levels and maps the pins always used.
ns.layer = WM.NewLayer({ base = "canvas", level = 2000, size = SIZE, stitched = false, create = CreatePin, refresh = Refresh })
