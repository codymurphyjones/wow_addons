local _, ns = ...

-- HereBeDragons' pins (Questie, TomTom, GatherMate2, HandyNotes ... each may bring its own copy of
-- the library, Questie a renamed one): the zones touching yours, on Blizzard's world map and the
-- minimap. OpenMap's stitched map already shows every copy's pins of the zones round the view
-- (OpenMap's Extras.lua), so nothing is done there.
--
-- World map. A copy's provider places each pin in HandlePin. A pin added for a zone
-- (AddWorldMapIconMap, data.uiMapID) shows only on that zone's map; Questie's copy shows the
-- neighbours' too, but from the library's world coordinates, which on Forever don't match
-- Blizzard's zone maps. So after the library's own HandlePin, a pin of a touching zone is placed
-- (or moved) from its zone point through Blizzard's map rectangles (Zones.Place), in the copy's own
-- pin template. The zone point: Questie's data.mapX / mapY, else the library's own world position
-- turned back into its zone (the copy's GetZoneCoordinatesFromWorld). A pin its addon keeps to its
-- own map (Questie's HBD_PINS_WORLDMAP_SHOW_CURRENT) stays there; pins added by world position
-- (AddWorldMapIconWorld) show on every zone of their continent already.
--
-- Minimap. The standard copy shows a zone's pin (AddMinimapIconMap) only while you're in that
-- zone, so a gathering node or note a few yards over the border isn't there. Every TICK seconds the
-- zones whose edge is within the minimap's reach are looked up; their pins have their uiMapID held
-- aside (the library then treats them as world pins and shows the ones in range), and get it back
-- once you've moved away. Pins that float on the minimap's edge (waypoints) are left alone. Questie's
-- copy already shows every pin in range.
local P = {}
ns.Pins = P

local STRICT = -1           -- Questie's HBD_PINS_WORLDMAP_SHOW_CURRENT: only ever on its own map
local TICK = 2              -- seconds between looks at where you are (the minimap)
local MARGIN = 100          -- yards past the minimap's edge a zone's edge may be

local copies = {}           -- lib -> its copy: { name, lib, core, provider, questie, template, stash, placed }
local providers = {}        -- the copies' world map providers (Canvas.lua leaves them alone)
local near, nearKey = {}, nil
local ticker

function P.Providers() return providers end

local function QuestieHidesOnContinents()
    local q = _G.Questie
    local p = q and q.db and q.db.profile
    return p and p.hideIconsOnContinents and true or false
end

function P.WorldMapOn()
    local db = ns.db
    return db and db.enabled and db.pins and db.worldmap and not ns.Zones.Stitched() or false
end

function P.MinimapOn()
    local db = ns.db
    return db and db.enabled and db.pins and db.minimap or false
end

-- ---------------------------------------------------------------------------------------------
-- World map
-- ---------------------------------------------------------------------------------------------

-- The template a copy's pins are drawn in: the world map's pool that is the copy's.
local function TemplateOf(c)
    if c.template then return c.template end
    local pools = WorldMapFrame and WorldMapFrame.pinPools
    if not pools then return nil end
    for template, pool in pairs(pools) do
        if pool == c.lib.worldmapPinsPool then c.template = template return template end
    end
end

-- A pin's point on its own zone (0-1), or nil.
local function ZonePoint(c, data)
    if type(data.mapX) == "number" and type(data.mapY) == "number" then return data.mapX, data.mapY end
    local core = c.core
    if not (core and core.GetZoneCoordinatesFromWorld and data.x and data.y) then return nil end
    local ok, x, y = pcall(core.GetZoneCoordinatesFromWorld, core, data.x, data.y, data.uiMapID, true)
    if ok and type(x) == "number" and type(y) == "number" then return x, y end
end

local function AfterHandlePin(c, provider, icon, data)
    if type(data) ~= "table" or type(icon) ~= "table" or not P.WorldMapOn() then return end
    local uiMapID = data.uiMapID
    if not uiMapID then return end
    local m = provider:GetMap()
    local host = m and m:GetMapID()
    if not host or host == uiMapID or not ns.Zones.IsNeighbour(host, uiMapID) then return end
    if data.worldMapShowFlag == STRICT then return end
    if c.questie and ns.Zones.IsContinent(host) and QuestieHidesOnContinents() then return end
    local mx, my = ZonePoint(c, data)
    local x, y = ns.Zones.Place(uiMapID, mx, my, host)
    if not x then return end
    local holder = icon.GetParent and icon:GetParent()
    if holder and holder.icon == icon and holder.SetPosition then
        holder:SetPosition(x, y)        -- placed by the library, from its own coordinates: moved
        c.placed = c.placed + 1
        return
    end
    local template = TemplateOf(c)
    if template then
        m:AcquirePin(template, icon, x, y, data.frameLevelType)
        c.placed = c.placed + 1
    end
end

-- ---------------------------------------------------------------------------------------------
-- Minimap
-- ---------------------------------------------------------------------------------------------

-- A pin of a nearby zone gets its uiMapID held aside; one no longer nearby gets it back. True when
-- it changed.
local function Apply(c, icon, data)
    if data.uiMapID ~= nil then
        if near[data.uiMapID] and not data.floatOnEdge then
            c.stash[icon] = data.uiMapID
            data.uiMapID = nil
            return true
        end
    else
        local held = c.stash[icon]
        if held and not near[held] then
            data.uiMapID = held
            c.stash[icon] = nil
            return true
        end
    end
    return false
end

-- Every pin of a copy, against the nearby zones.
local function Sweep(c)
    local pins = c.lib.minimapPins
    if type(pins) ~= "table" then return end
    for icon in pairs(c.stash) do
        if not pins[icon] then c.stash[icon] = nil end
    end
    local changed = false
    for icon, data in pairs(pins) do
        if type(data) == "table" and Apply(c, icon, data) then changed = true end
    end
    -- (the library redraws its minimap pins at once on a new minimap object, the same one here)
    if changed and c.lib.SetMinimapObject then pcall(c.lib.SetMinimapObject, c.lib, c.lib.Minimap) end
end

local function SweepAll()
    for _, c in pairs(copies) do
        if not c.questie then Sweep(c) end
    end
end

function P.Tick()
    local zones
    if P.MinimapOn() and not (IsInInstance and IsInInstance()) then
        zones = ns.Zones.NearPlayer(ns.WorldMap.MinimapRadius() + MARGIN)
    end
    zones = zones or {}
    local key = table.concat(zones, ",")
    if key == nearKey then return end
    nearKey = key
    wipe(near)
    for _, z in ipairs(zones) do near[z] = true end
    SweepAll()
end

-- ---------------------------------------------------------------------------------------------
-- Set up
-- ---------------------------------------------------------------------------------------------

local function SetUp(name, lib)
    if copies[lib] then return end
    local provider = lib.worldmapProvider
    if type(provider) ~= "table" or type(provider.HandlePin) ~= "function" then return end
    local c = {
        name = name, lib = lib, provider = provider, stash = {}, placed = 0,
        questie = name:find("Questie", 1, true) ~= nil,
        core = LibStub(name:gsub("%-Pins%-2%.0$", "-2.0"), true),
    }
    copies[lib] = c
    providers[provider] = true

    local handle = provider.HandlePin
    provider.HandlePin = function(self, icon, data, ...)
        handle(self, icon, data, ...)
        local ok, err = pcall(AfterHandlePin, c, self, icon, data)
        if not ok then ns:Caught(name .. " pin", err) end
    end
    local refresh = provider.RefreshAllData
    if type(refresh) == "function" then
        provider.RefreshAllData = function(self, ...)
            c.placed = 0
            return refresh(self, ...)
        end
    end

    if not c.questie then
        -- a pin added again starts afresh: a world pin keeps no uiMapID, a zone pin is looked at
        local addWorld, addMap = lib.AddMinimapIconWorld, lib.AddMinimapIconMap
        if type(addWorld) == "function" then
            lib.AddMinimapIconWorld = function(self, ref, icon, ...)
                if icon then c.stash[icon] = nil end
                return addWorld(self, ref, icon, ...)
            end
        end
        if type(addMap) == "function" then
            lib.AddMinimapIconMap = function(self, ref, icon, ...)
                local r1, r2 = addMap(self, ref, icon, ...)
                local data = icon and self.minimapPins and self.minimapPins[icon]
                if data and P.MinimapOn() then Apply(c, icon, data) end
                return r1, r2
            end
        end
    end
end

-- Every copy of the pins library loaded so far (one loaded later: the next time the map opens).
function P.Scan()
    if not (LibStub and LibStub.IterateLibraries) then return end
    for name, lib in LibStub:IterateLibraries() do
        if type(name) == "string" and name:match("^HereBeDragons.*%-Pins%-2%.0$") and type(lib) == "table" then
            local ok, err = pcall(SetUp, name, lib)
            if not ok then ns:Caught("setting up " .. name, err) end
        end
    end
end

function P.Install()
    P.Scan()
    if not ticker then
        ticker = C_Timer.NewTicker(TICK, function()
            local ok, err = pcall(P.Tick)
            if not ok then ns:Caught("minimap pins", err) end
        end)
    end
    return true
end

-- Draws the pins again (an option changed).
function P.Redraw()
    nearKey = nil
    pcall(P.Tick)
    if not (WorldMapFrame and WorldMapFrame:IsVisible()) then return end
    for _, c in pairs(copies) do
        c.provider.forceUpdate = true   -- (Questie's copy redraws only on a new map, or with this)
        local ok, err = pcall(c.provider.RefreshAllData, c.provider)
        if not ok then ns:Caught(c.name .. " refresh", err) end
    end
end

-- The copies found: { name, questie, placed (on the world map now), nearby (minimap pins held) }.
function P.Copies()
    local out = {}
    for _, c in pairs(copies) do
        local held = 0
        for _ in pairs(c.stash) do held = held + 1 end
        out[#out + 1] = { name = c.name, questie = c.questie, placed = c.placed, nearby = held }
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- for the tests
function P._Reset() wipe(copies) wipe(providers) wipe(near) nearKey = nil end
