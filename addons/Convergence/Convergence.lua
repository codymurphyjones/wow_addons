local addonName, ns = ...

-- Draws a pin for every known convergence on the world map. Pins show on the zone's own map
-- and on any map that contains it (continent, world), so you can plan a route past them.
-- Click a pin to set a map waypoint on it.

-- Four elements converging on a bright spark, in a teal-edged badge (Media\make_icon.py draws it).
local ICON = "Interface\\AddOns\\" .. addonName .. "\\Media\\Pin"
local SIZE = 12 -- on-screen size, kept the same at every zoom level

local pins, used = {}, 0

local function OnEnter(pin)
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Elemental Convergence", 0.33, 0.92, 0.78)
    GameTooltip:AddLine(string.format("%s  %.1f, %.1f", pin.zoneName or "", pin.x, pin.y), 1, 1, 1)
    if C_Map.SetUserWaypoint then GameTooltip:AddLine("Click to set a waypoint", 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

local function OnClick(pin)
    if not (C_Map.SetUserWaypoint and UiMapPoint) then return end
    local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(pin.mapID, pin.x / 100, pin.y / 100))
    if ok and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
end

local function GetPin(canvas)
    used = used + 1
    local pin = pins[used]
    if not pin then
        pin = CreateFrame("Button", nil, canvas)
        pin:SetSize(SIZE, SIZE)
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
        pins[used] = pin
    end
    return pin
end

-- Where a point on zoneID lands on mapID, as 0..1 fractions, or nil if it's off that map.
local function Project(zoneID, x, y, mapID)
    if zoneID == mapID then return x, y end
    local ok, continent, world = pcall(C_Map.GetWorldPosFromMapPos, zoneID, CreateVector2D(x, y))
    if not ok or not world then return end
    local ok2, _, pos = pcall(C_Map.GetMapPosFromWorldPos, continent, world, mapID)
    if not ok2 or not pos then return end
    local px, py = pos:GetXY()
    if px >= 0 and px <= 1 and py >= 0 and py <= 1 then return px, py end
end

local zoneNames = {}
local function ZoneName(id)
    if zoneNames[id] == nil then
        local info = C_Map.GetMapInfo(id)
        zoneNames[id] = info and info.name or ""
    end
    return zoneNames[id]
end

local function Refresh()
    local map = WorldMapFrame
    local mapID = map:GetMapID()
    local canvas = map:GetCanvas()
    for i = 1, used do pins[i]:Hide() end
    used = 0
    if not mapID then return end

    local scale = 1 / (map:GetCanvasScale() or 1)
    local w, h = canvas:GetSize()
    for zoneID, list in pairs(ns.POINTS) do
        for _, p in ipairs(list) do
            local px, py = Project(zoneID, p[1] / 100, p[2] / 100, mapID)
            if px then
                local pin = GetPin(canvas)
                pin.mapID, pin.x, pin.y, pin.zoneName = zoneID, p[1], p[2], ZoneName(zoneID)
                pin:SetScale(scale)
                pin:SetFrameLevel(canvas:GetFrameLevel() + 2000)
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", canvas, "TOPLEFT", px * w / scale, -py * h / scale)
                pin:Show()
            end
        end
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    if not WorldMapFrame then return end
    hooksecurefunc(WorldMapFrame, "OnMapChanged", Refresh)
    hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", Refresh)
    WorldMapFrame:HookScript("OnShow", Refresh)
end)
