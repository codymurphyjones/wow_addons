local _, ns = ...

-- RareScanner (optional) on the minimap: its icons of the zones next to you, near a zone border.
--
-- RareScanner's own minimap icons are your zone's only (HereBeDragons' AddMinimapIconMap shows a
-- pin only on its own map). Every few seconds this looks for zones whose edge is within the
-- minimap's reach (Zones.NearPlayer); their POIs come from RareScanner's world-map refresh run for
-- that zone with the pins collected instead of drawn (RareScanner.lua, M.CollectZone), and are
-- drawn here in RareScanner's own minimap pin template, placed by world position
-- (AddMinimapIconWorld), so they show across the border. Collected again when the nearby zones change, RareScanner refreshes its data, or every
-- REFRESH seconds; never in combat, while the world map is open (RareScanner's refresh redraws the
-- route there), or in an instance.
local N = {}
ns.RareScannerMinimap = N

local TICK = 3              -- seconds between looks at where you are
local REFRESH = 30          -- seconds after which the nearby zones' icons are collected again
local MARGIN = 150          -- yards past the minimap's edge a zone's edge may be
local ENTITY_FRAME_LEVEL = 1002 -- as RareScanner's minimap icons
local SAME_SPOT = 5         -- yards: the same entity closer than this is one icon

local HBD, HBDPins
local pool
local shown = {}            -- pins on the minimap now
local lastKey, lastAt = nil, 0
local dirty = true
local ticker

local function RareScannerProfile()
    local ace = LibStub and LibStub("AceAddon-3.0", true)
    local ok, rs = pcall(function() return ace and ace:GetAddon("RareScanner", true) end)
    return ok and rs and rs.db and rs.db.profile or nil
end

local function IconScale()
    local p = RareScannerProfile()
    local s = p and p.map and p.map.minimapscale
    return type(s) == "number" and s or 1
end

-- RareScanner's own "show icons on the minimap" option.
local function RareScannerShowsMinimap()
    local p = RareScannerProfile()
    return not (p and p.map and p.map.displayMinimapIcons == false)
end

local function Clear()
    if HBDPins then HBDPins:RemoveAllMinimapIcons(N) end
    if pool then pool:ReleaseAll() end
    wipe(shown)
    lastKey = nil
end
N.Clear = Clear

function N:Dirty() dirty = true end

-- The zones next to you whose edge is within reach (sorted uiMapIDs), and your map.
function N.NearbyZones()
    return ns.Zones.NearPlayer(ns.WorldMap.MinimapRadius() + MARGIN)
end

local function Usable()
    return ns.db and ns.db.enabled and ns.db.minimap and ns.db.rarescanner and ns.RareScanner.Ready() and HBD and HBDPins and pool
end

local function SpotKey(POI, wx, wy)
    return tostring(POI.entityID) .. ":" .. math.floor(wx / SAME_SPOT + 0.5) .. ":" .. math.floor(wy / SAME_SPOT + 0.5)
end

local function Fix(v)
    v = tonumber(v)
    if not v then return nil end
    if v > 1 then v = v / 10000 end   -- as RareScanner's FixCoord: whole numbers are x10000
    return v
end

local function WorldOf(POI)
    local x, y = Fix(POI.x), Fix(POI.y)
    if not (x and y and type(POI.mapID) == "number") then return nil end
    return HBD:GetWorldCoordinatesFromZone(x, y, POI.mapID)
end

local function AddPin(POI, wx, wy, instance, scale)
    local pin = pool:Acquire()
    pin.POI = POI
    pin.Texture:SetTexture(POI.Texture)
    pin.Texture:SetScale(scale)
    pin:SetFrameLevel(ENTITY_FRAME_LEVEL)
    pin.IconTexture:SetAtlas(POI.iconAtlas)
    if HBDPins:AddMinimapIconWorld(N, pin, instance, wx, wy, false) then
        shown[#shown + 1] = pin
    else
        pool:Release(pin)
    end
end

-- Collects the nearby zones' POIs and draws them.
local function Harvest(zones, ownMap)
    local skip = {}
    -- your own zone's icons are RareScanner's: the same entity in a neighbour isn't drawn again
    local own = ownMap and ns.RareScanner.CollectZone(ownMap)
    for _, POI in ipairs(own or {}) do
        local wx, wy = WorldOf(POI)
        if wx then skip[SpotKey(POI, wx, wy)] = true end
    end
    local list = {}
    for _, zone in ipairs(zones) do
        local pois, err = ns.RareScanner.CollectZone(zone)
        if pois then
            for _, POI in ipairs(pois) do
                if not POI.worldmap then
                    local wx, wy, instance = WorldOf(POI)
                    if wx and instance then
                        local key = SpotKey(POI, wx, wy)
                        if not skip[key] then
                            skip[key] = true
                            list[#list + 1] = { POI, wx, wy, instance }
                        end
                    end
                end
            end
        elseif err ~= "busy" then
            ns:Caught("RareScanner minimap (nearby zone " .. tostring(zone) .. ")", err)
        end
    end
    Clear()
    local scale = IconScale()
    for _, e in ipairs(list) do AddPin(e[1], e[2], e[3], e[4], scale) end
end

function N:Refresh(force)
    if not Usable() or not RareScannerShowsMinimap() or not Minimap:IsVisible() then
        if #shown > 0 then Clear() end
        return
    end
    local inInstance = IsInInstance and IsInInstance()
    if inInstance then
        if #shown > 0 then Clear() end
        return
    end
    local zones, ownMap = N.NearbyZones()
    if not zones or #zones == 0 then
        if #shown > 0 then Clear() end
        lastKey = ""
        return
    end
    local key = table.concat(zones, ",") .. "@" .. tostring(ownMap)
    local now = GetTime()
    if not force and not dirty and key == lastKey and now - lastAt < REFRESH then return end
    -- RareScanner's refresh would redraw its world-map route; and not in combat
    if InCombatLockdown() or (WorldMapFrame and WorldMapFrame:IsShown()) then return end
    dirty = false
    lastAt = now
    Harvest(zones, ownMap)
    lastKey = key
end

function N:Count() return #shown end

function N.Started() return ticker ~= nil end

-- Sets up (once RareScanner's map hooks are in). False and why when it can't.
function N:Start()
    if ticker then return true end
    HBD = LibStub and LibStub("HereBeDragons-2.0", true)
    HBDPins = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
    if not (HBD and HBDPins and HBD.GetWorldCoordinatesFromZone and HBDPins.AddMinimapIconWorld) then
        return false, "HereBeDragons (RareScanner's copy)"
    end
    local okT, info = pcall(C_XMLUtil.GetTemplateInfo, "RSMinimapPinTemplate")
    if not okT or not info then return false, "RSMinimapPinTemplate" end
    pool = CreateFramePool("FRAME", Minimap, "RSMinimapPinTemplate")
    local function Soon() N:Dirty() end
    for _, e in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
        ns:On(e, Soon)
    end
    ns:On("PLAYER_REGEN_ENABLED", function() N:Refresh() end)
    ticker = C_Timer.NewTicker(TICK, function()
        local ok, err = pcall(N.Refresh, N)
        if not ok then ns:Caught("RareScanner minimap", err) end
    end)
    return true
end
