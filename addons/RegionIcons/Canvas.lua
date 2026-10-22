local addonName, ns = ...

-- Every map icon provider on the world map, for the zones touching the one shown.
--
-- A world map data provider (MapCanvasDataProviderMixin) draws in RefreshAllData: it asks its map
-- which map is shown (self:GetMap():GetMapID()), reads that map's icons and acquires a pin for each
-- (GetMap():AcquirePin), placed at that map's 0-1 coordinates (pin:SetPosition). So after the
-- provider's own refresh (hooksecurefunc: Blizzard's own refresh stays as it was), its refresh runs
-- again once per neighbouring zone, on a stand-in for the provider. The stand-in's GetMap() is a
-- stand-in for the map whose GetMapID() answers the neighbour and whose AcquirePin moves each new
-- pin from the neighbour's coordinates onto the shown map's (Zones.Place; off it: hidden, given
-- back once the passes are done). RemoveAllData and RemoveAllPinsByTemplate do nothing during a
-- pass, so the shown map's own pins stay. Everything else the provider reads or writes is its own.
--
-- Which providers: every addon's (issecurevariable names the addon that made it) except those
-- whose icons come here another way: HereBeDragons' (Pins.lua: Questie, TomTom, gatherers ...),
-- RareScanner's (RareScanner.lua), OpenMap's (its stitched map has every zone's already) and ours.
-- Of Blizzard's, only those listing a map's fixed places (BLIZZARD), and only on Blizzard's own
-- map (OpenMap draws its own on the stitched map). A provider that never asks which map is shown
-- draws the same icons for every map: its pass is dropped, and it's left alone from then on.
local C = {}
ns.Canvas = C

local SAME_SPOT = 0.005     -- a neighbour's pin this close (shown map's widths) to one of its kind is the same icon

-- Blizzard's providers whose icons are a map's fixed places: mixin -> what they show
local BLIZZARD = {
    FlightPointDataProviderMixin = "Blizzard: flight points",
    DungeonEntranceDataProviderMixin = "Blizzard: dungeon entrances",
    AreaPOIDataProviderMixin = "Blizzard: points of interest",
}
-- Addons whose icons come here another way, or that show every zone's already
local SKIP_ADDONS = { OpenMap = true, RareScanner = true, Questie = true }

local map                   -- WorldMapFrame
local seen = {}             -- provider -> its entry (below), or false: not one of ours
local busy = false
local warned = {}

local function nop() end

-- ---------------------------------------------------------------------------------------------
-- Which providers
-- ---------------------------------------------------------------------------------------------

-- The Blizzard provider's label (BLIZZARD), when it's one of those: one of its own methods (not the
-- base mixin's) is the mixin's (CreateFromMixins copies them in; RemoveAllData first, as other
-- addons hook RefreshAllData).
local function BlizzardLabel(provider)
    local base = MapCanvasDataProviderMixin or {}
    for name, label in pairs(BLIZZARD) do
        local mixin = _G[name]
        if type(mixin) == "table" then
            for _, k in ipairs({ "RemoveAllData", "RefreshAllData", "OnMapChanged" }) do
                local f = rawget(provider, k)
                if type(f) == "function" and f == mixin[k] and f ~= base[k] then return label end
            end
        end
    end
end

-- The addon that made a provider (its RefreshAllData), or nil for Blizzard's.
local function Owner(provider)
    if not issecurevariable then return nil end
    local ok, secure, by = pcall(issecurevariable, provider, "RefreshAllData")
    if not ok or secure then return nil end
    return by
end

-- A provider's entry: { kind = "blizzard" | "addon", label, owner, orig, global, pins }, or nil.
local function Classify(provider)
    local label = BlizzardLabel(provider)
    if label then return { kind = "blizzard", label = label } end
    local owner = Owner(provider)
    if not owner or owner == addonName or SKIP_ADDONS[owner] then return nil end
    return { kind = "addon", label = owner, owner = owner }
end

-- Whether a provider's icons go on the neighbours now.
local function Wanted(e)
    local db = ns.db
    if not (db and db.enabled) or e.global then return false end
    if ns.Zones.Stitched() then
        if not db.openmap or e.kind == "blizzard" then return false end
    elseif not db.worldmap then
        return false
    end
    if e.kind == "blizzard" then return db.blizzard and true or false end
    return db.addons and not (db.off and db.off[e.owner]) or false
end

-- ---------------------------------------------------------------------------------------------
-- A pass: the provider's refresh for one zone
-- ---------------------------------------------------------------------------------------------

-- A pin a pass acquired, moved from the zone's coordinates onto the shown map's.
local function Move(pass, pin)
    local x, y = rawget(pin, "normalizedX") or pin.normalizedX, rawget(pin, "normalizedY") or pin.normalizedY
    local px, py
    if type(x) == "number" and type(y) == "number" then px, py = ns.Zones.Place(pass.zone, x, y, pass.host) end
    if px and type(pin.SetPosition) == "function" and pcall(pin.SetPosition, pin, px, py) then
        pass.pins[#pass.pins + 1] = pin
    else
        -- off the shown map (or a pin that doesn't say where it is): given back after the passes
        if pin.Hide then pin:Hide() end
        pass.drops[#pass.drops + 1] = pin
    end
end

-- The stand-in map: the zone's mapID, pins moved, no clearing. Only during the pass; a pin that
-- keeps the stand-in (as its provider's map) gets the real map afterwards.
local function StandInMap(pass)
    local stand
    stand = setmetatable({}, { __index = function(_, k)
        if pass.live then
            if k == "GetMapID" then
                return function() pass.asked = true return pass.zone end
            elseif k == "AcquirePin" then
                return function(_, template, ...)
                    local pin = map:AcquirePin(template, ...)
                    if type(pin) == "table" then Move(pass, pin) end
                    return pin
                end
            elseif k == "RemoveAllPinsByTemplate" then
                return nop
            end
        end
        local v = map[k]
        if type(v) == "function" then
            return function(self, ...)
                if self == stand then return v(map, ...) end
                return v(self, ...)
            end
        end
        return v
    end })
    return stand
end

-- The stand-in provider: its map is the stand-in, RemoveAllData does nothing; the rest (reads and
-- writes) is the provider's own. A plain value it sets (the last map it drew, a flag ...) is put
-- back after the passes (Restore), so it keeps describing the shown map; a table it sets (its pin
-- list) stays, so it can still let go of the neighbours' pins.
local function StandIn(provider, pass, kept)
    local stand = StandInMap(pass)
    return setmetatable({}, {
        __index = function(_, k)
            if k == "owningMap" then return pass.live and stand or provider.owningMap end
            if k == "GetMap" then
                return function() if pass.live then return stand end return provider:GetMap() end
            end
            if k == "RemoveAllData" and pass.live then return nop end
            return provider[k]
        end,
        __newindex = function(_, k, v)
            local was = rawget(provider, k)
            if kept[k] == nil and type(was) ~= "table" and type(v) ~= "table" then
                kept[k] = { was }
            end
            provider[k] = v
        end,
    })
end

local function Restore(provider, kept)
    for k, was in pairs(kept) do provider[k] = was[1] end
end

local function WarnOnce(key, msg)
    if warned[key] then return end
    warned[key] = true
    ns:Print(msg, true)
end
C.WarnOnce = WarnOnce

-- One icon per kind and spot: a neighbour's pin where the shown map (or an earlier neighbour)
-- already has one of the same template goes back to the pool.
local function Dedupe(pins)
    local ours, byTemplate = {}, {}
    for _, pin in ipairs(pins) do ours[pin] = true end
    local function Spots(template)
        local list = byTemplate[template]
        if list then return list end
        list = {}
        local ok, it, state, first = pcall(map.EnumeratePinsByTemplate, map, template)
        if ok and it then
            for pin in it, state, first do
                if not ours[pin] and pin:IsShown() and pin.normalizedX then
                    list[#list + 1] = { pin.normalizedX, pin.normalizedY }
                end
            end
        end
        byTemplate[template] = list
        return list
    end
    local removed = 0
    for _, pin in ipairs(pins) do
        local template, x, y = pin.pinTemplate, pin.normalizedX, pin.normalizedY
        if template and x and y then
            local list, dup = Spots(template), false
            for _, s in ipairs(list) do
                if math.abs(s[1] - x) < SAME_SPOT and math.abs(s[2] - y) < SAME_SPOT then dup = true break end
            end
            if dup then
                pcall(map.RemovePin, map, pin)
                removed = removed + 1
            else
                list[#list + 1] = { x, y }
            end
        end
    end
    return removed
end

-- One neighbour's pass: the provider's refresh for that zone. Its plain values are put back
-- straight after (Restore), off-map pins given back and duplicates dropped, so the provider is
-- itself again between passes. Returns false when the provider turned out to draw the same for
-- every map (no more passes for it).
local function RunZone(provider, e, job, zone)
    local pass = { zone = zone, host = job.host, pins = {}, drops = {}, live = true }
    local kept = {}
    busy = true
    local ok, err = pcall(e.orig, StandIn(provider, pass, kept), unpack(job.args, 1, job.args.n))
    busy = false
    pass.live = false
    Restore(provider, kept)
    for _, pin in ipairs(pass.drops) do pcall(map.RemovePin, map, pin) end
    if not pass.asked then
        -- the same icons whatever the map: not one to repeat for the neighbours
        e.global = true
        for _, pin in ipairs(pass.pins) do pcall(map.RemovePin, map, pin) end
        ns:Debug(e.label .. " doesn't draw per map: left alone")
        return false
    end
    if not ok then ns:Caught(e.label .. " (nearby zone " .. tostring(zone) .. ")", err) end
    local okD, removed = pcall(Dedupe, pass.pins)
    job.count = job.count + #pass.pins - (okD and removed or 0)
    return true
end

-- After a provider's own refresh: its refresh again for every neighbour, one neighbour per frame
-- (the shown map's own icons are up at once; the neighbours' follow, without one long frame).
-- A newer refresh of the provider (its own clears ours along with its) takes over; the map closing
-- or changing stops the rest.
local jobs = {}             -- provider -> the job under way
local function AfterRefresh(provider, ...)
    if busy then return end
    local e = seen[provider]
    if not e or not Wanted(e) or not map:IsVisible() then return end
    local host = map:GetMapID()
    local list = ns.Zones.Neighbours(host)
    if #list == 0 then return end
    local job = { host = host, zones = list, i = 0, count = 0, args = { n = select("#", ...), ... } }
    jobs[provider] = job
    local function Step()
        if jobs[provider] ~= job then return end
        if e.global or not map:IsVisible() or map:GetMapID() ~= host or not Wanted(e) then
            jobs[provider] = nil
            return
        end
        job.i = job.i + 1
        local zone = job.zones[job.i]
        local more = zone and RunZone(provider, e, job, zone)
        e.pins, e.host = job.count, host
        if more and job.zones[job.i + 1] then C_Timer.After(0, Step) else jobs[provider] = nil end
    end
    Step()
end

-- ---------------------------------------------------------------------------------------------
-- Set up
-- ---------------------------------------------------------------------------------------------

-- Looks at the world map's providers (again: an addon loaded later adds its own).
function C.Scan()
    if not map then return end
    local skip = ns.Pins and ns.Pins.Providers() or {}
    for provider in pairs(map.dataProviders or {}) do
        if seen[provider] == nil and type(provider) == "table" and type(provider.RefreshAllData) == "function" then
            local e = not skip[provider] and Classify(provider) or nil
            if e then
                e.orig = provider.RefreshAllData
                hooksecurefunc(provider, "RefreshAllData", AfterRefresh)
                seen[provider] = e
            else
                seen[provider] = false
            end
        end
    end
end

-- Finds the world map. It doesn't look at the providers yet: Core.lua's Start sets Pins.lua up
-- first, so HereBeDragons' providers are known to be Pins.lua's and left alone here (handled by
-- both, the same icon frame would be fought over and lost).
function C.Install()
    if map then return true end
    map = WorldMapFrame
    if not (map and map.dataProviders and map.AcquirePin) then
        map = nil
        return false, "the world map's providers"
    end
    if map.AddDataProvider then hooksecurefunc(map, "AddDataProvider", function() C.Scan() end) end
    return true
end

-- Draws the icons again (an option changed): every provider of ours refreshes.
function C.Redraw()
    if not (map and map:IsVisible()) then return end
    for provider, e in pairs(seen) do
        if e then
            local ok, err = pcall(provider.RefreshAllData, provider)
            if not ok then ns:Caught(e.label .. " refresh", err) end
        end
    end
end

-- The providers found: { label, kind, owner, on, global, pins } sorted by label.
function C.Sources()
    local out = {}
    for _, e in pairs(seen) do
        if e then
            out[#out + 1] = { label = e.label, kind = e.kind, owner = e.owner, global = e.global,
                on = not e.global and Wanted(e), pins = e.pins }
        end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end

-- for the tests
function C._Reset() map, busy = nil, false; wipe(seen); wipe(warned); wipe(jobs) end
