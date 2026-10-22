local _, ns = ...

-- OpenMaps: Region Icons: every addon's map icons of the zones touching the one you look at, on
-- OpenMap's stitched map, Blizzard's world map and the minimap near a border. No addon is changed
-- and none is needed:
--   Canvas.lua       the world map's icon providers (other addons', a few of Blizzard's)
--   Pins.lua         HereBeDragons' pins (Questie, TomTom, gatherers, notes ...)
--   RareScanner.lua  RareScanner's own canvas (and RareScannerMinimap.lua), with RareScanner loaded
--   Zones.lua        which zones touch the shown one, and where their points land on it
-- Events, saved variables and /regionicons: the shared Core.lua (addons/shared).
ns.PREFIX = "|cff55d6beRegion Icons|r"
ns.SAVED = { db = "RegionIconsDB" }
-- The options (Options > AddOns > Region Icons, Settings.lua; /regionicons; OpenMap's menu).
ns.DEFAULTS = {
    enabled = true,
    -- where
    openmap = true,     -- OpenMap's stitched map
    worldmap = true,    -- Blizzard's world map
    minimap = true,     -- the minimap near a zone border
    continent = false,  -- a continent shown: every zone's icons on it
    -- whose
    pins = true,        -- HereBeDragons' pins: Questie, TomTom, gatherers, notes ...
    addons = true,      -- other addons' world map icons (each can be turned off: off)
    blizzard = true,    -- Blizzard's flight points, dungeon entrances and points of interest
    rarescanner = true, -- RareScanner's rares, treasures and events
    off = {},           -- addon name -> true: its world map icons left alone
    debug = false,
}

local SURFACES = {
    { key = "openmap", word = "openmap", label = "OpenMap's stitched map" },
    { key = "worldmap", word = "worldmap", label = "Blizzard's world map" },
    { key = "minimap", word = "minimap", label = "the minimap near zone borders" },
    { key = "continent", word = "continent", label = "every zone on a continent map" },
}
local SOURCES = {
    { key = "pins", word = "pins", label = "map pins (Questie, TomTom, gatherers, notes ...)" },
    { key = "addons", word = "addons", label = "other addons' world map icons" },
    { key = "blizzard", word = "blizzard", label = "Blizzard's flight points, dungeons and points of interest" },
    { key = "rarescanner", word = "rarescanner", label = "RareScanner's rares, treasures and events" },
}
ns.SURFACES, ns.SOURCES = SURFACES, SOURCES

-- Redraws whatever an option changed (every UI's change comes through ns:SetOption).
function ns.Apply()
    if not ns.active then return end
    ns.Zones.ClearCache()
    ns.Canvas.Redraw()
    ns.Pins.Redraw()
    if ns.RareScanner.Ready() then ns.RareScanner.Redraw() end
    if ns.RareScannerMinimap.Started() then ns.RareScannerMinimap:Dirty() ns.RareScannerMinimap:Refresh(true) end
end

local function OnOff(v) return v and "|cff40ff40on|r" or "|cffff5050off|r" end

local function Status()
    if not ns.active then
        ns:Print("Not running: " .. tostring(ns.failed or "not started yet") .. ".", true)
        return
    end
    if not ns.db.enabled then ns:Print("Off (/regionicons on).", true) end
    for _, s in ipairs(SURFACES) do ns:Print(s.label .. ": " .. OnOff(ns.db[s.key]), true) end
    for _, s in ipairs(SOURCES) do ns:Print(s.label .. ": " .. OnOff(ns.db[s.key]), true) end
    for _, c in ipairs(ns.Pins.Copies()) do
        ns:Print(("%s: %d icons placed for nearby zones on the world map, %d minimap icons of nearby zones."):format(
            c.name, c.placed, c.nearby), true)
    end
    if ns.RareScanner.Ready() then
        local last = ns.RareScanner.last
        if last then
            ns:Print(("RareScanner: map %s, %d nearby zones, %d icons added."):format(tostring(last.host), last.zones, last.pins), true)
        end
        ns:Print(("RareScanner minimap: %d nearby icons."):format(ns.RareScannerMinimap:Count()), true)
    end
    ns:Print("World map icons of: /regionicons sources", true)
end

-- The world map's providers found, and whether each gets the neighbours.
local function Sources()
    local list = ns.Canvas.Sources()
    if #list == 0 then ns:Print("No other world map icons found (open the world map once, then try again).", true) return end
    for _, s in ipairs(list) do
        local state
        if s.global then state = "|cff808080same on every map: left alone|r"
        else state = OnOff(s.on) .. (s.pins and (" (%d icons added last time)"):format(s.pins) or "") end
        local how = s.owner and ("  /regionicons source " .. s.owner) or ""
        ns:Print(s.label .. ": " .. state .. how, true)
    end
end

-- One addon's world map icons on or off.
local function Source(name)
    name = ns.Trim(name)
    if name == "" then return Sources() end
    for _, s in ipairs(ns.Canvas.Sources()) do
        if s.owner and s.owner:lower() == name:lower() then
            local off = not (ns.db.off[s.owner] and true or false)
            ns.db.off[s.owner] = off or nil
            ns:Print(s.owner .. "'s map icons on nearby zones: " .. OnOff(not off), true)
            ns.Apply()
            return
        end
    end
    ns:Print("No world map icons of an addon named " .. name .. " (/regionicons sources lists them).", true)
end

-- OpenMap's menu: a switch per option, in its own section.
local function OpenMapToggles()
    local api = OpenMapAPI
    if not (api and type(api.RegisterMenuToggle) == "function") then return end
    local function Toggle(s, prefix)
        pcall(api.RegisterMenuToggle, "RegionIcons", {
            id = s.key,
            label = prefix .. s.label,
            section = "Region Icons",
            icon = "Interface\\Icons\\INV_Misc_Spyglass_03",
            get = function() return ns.db and ns.db[s.key] and true or false end,
            set = function(v) ns:SetOption("db." .. s.key, v and true or false) end,
        })
    end
    for _, s in ipairs(SURFACES) do Toggle(s, "Nearby zones' icons on ") end
    for _, s in ipairs(SOURCES) do Toggle(s, "Nearby zones: ") end
    if type(api.RegisterCallback) == "function" then
        pcall(api.RegisterCallback, ns, "OpenMap_StitchedChanged", function() ns.Apply() end)
    end
end

local function Start()
    if ns.active then return end
    local okC, whyC = ns.Canvas.Install()
    if not okC then
        ns.failed = "the world map isn't as expected (" .. tostring(whyC) .. ")"
        ns:Print("Off: " .. ns.failed .. ". An update of Region Icons may be needed.", true)
        return
    end
    ns.active = true
    ns.Pins.Install()
    ns.Canvas.Scan()    -- (again, now that HereBeDragons' providers are known: those are Pins.lua's)

    -- RareScanner, when it's there
    if _G.RareScannerDataProviderMixin then
        local ok, missing = ns.RareScanner.Install()
        if not ok then
            ns:Print("RareScanner changed (" .. tostring(missing) .. " is missing), so its icons are left out. "
                .. "An update of Region Icons may be needed.", true)
        else
            local okM, why = ns.RareScannerMinimap:Start()
            if not okM then ns:Debug("RareScanner minimap icons off: " .. tostring(why) .. " isn't there") end
        end
    end
    OpenMapToggles()

    -- addons loaded later, and their copies of HereBeDragons: looked for as the map opens
    if WorldMapFrame then
        WorldMapFrame:HookScript("OnShow", function()
            ns.Pins.Scan()
            ns.Canvas.Scan()
        end)
    end
    ns.Apply()
end

ns:On("PLAYER_LOGIN", function()
    -- RareScanner and the other map addons set their maps up as they're enabled (also at login)
    C_Timer.After(0, Start)
end)

local slashHelp
local function Toggle(key, label)
    return function()
        local v = ns:ToggleOption("db." .. key)
        ns:Print(label .. ": " .. OnOff(v), true)
    end
end

local commands = {
    { { "status", "s" }, Status, "what's on, and the last counts" },
    { "on", function() ns:SetOption("db.enabled", true) ns:Print("On.", true) end, "turn Region Icons on" },
    { "off", function() ns:SetOption("db.enabled", false) ns:Print("Off.", true) end, "turn Region Icons off" },
    { "sources", Sources, "the addons whose world map icons were found" },
    { "source", Source, "<addon>: that addon's world map icons on nearby zones, on or off" },
    { "refresh", function() ns.Apply() ns:Print("Refreshed.", true) end, "draw the icons again" },
    { { "config", "options" }, function() if ns.Settings then ns.Settings:Open() end end, "open Options > AddOns > Region Icons" },
    { "debug", Toggle("debug", "Debug messages"), nil },
}
for _, s in ipairs(SURFACES) do
    commands[#commands + 1] = { s.word, Toggle(s.key, "Nearby zones' icons on " .. s.label), "toggle icons on " .. s.label }
end
for _, s in ipairs(SOURCES) do
    commands[#commands + 1] = { s.word, Toggle(s.key, "Nearby zones: " .. s.label), "toggle " .. s.label }
end
commands.default = function(msg)
    if msg == "" then return Status() end
    slashHelp()
end
slashHelp = ns:Slash({ "/regionicons", "/ricons" }, commands)
