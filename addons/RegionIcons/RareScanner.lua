local _, ns = ...

-- RareScanner (optional): its rare, treasure and event icons of the zones touching the one shown.
-- RareScanner draws on a canvas of its own (RSWorldMap, over Blizzard's), not through the world
-- map's providers, so Canvas.lua doesn't see it; this does the same for it.
--
-- RareScanner draws one map's icons. Its data provider (the global RareScannerDataProviderMixin,
-- the live instance it adds to its own canvas) refreshes in RefreshAllData: clear the pins, read
-- the shown map's ID from its canvas (GetMap():GetMapID(), the canvas's mapID field or the
-- player's map), and acquire a pin per POI through GetMap():AcquirePin. Each pin keeps the POI
-- (tooltips, clicks and waypoints use it) and a position, pin.x / pin.y, that every zoom re-applies
-- (RSPinMixin:ApplyCurrentPosition).
--
-- So the wrapped RefreshAllData clears once, keeps RemoveAllData from clearing again, and runs
-- RareScanner's own refresh once per neighbouring zone (the canvas's mapID set to that zone): the
-- pins those passes acquire are moved from the zone's coordinates onto the shown map's. The shown
-- map's own pass runs last, so the route, guide and animations end on it as before. Every override
-- is put back after each pass, even when a pass errors.
--
-- AcquirePin stays wrapped (installed once): overlay spots and guide icons a neighbour's pin opens
-- later (a click) come in its zone's coordinates and are moved the same way.
local M = {}
ns.RareScanner = M

local SAME_SPOT = 0.01      -- the same entity closer than this (shown map's widths) is one icon

local ENTITY_TEMPLATES = { RSEntityPinTemplate = true, RSGroupPinTemplate = true }

local P, RS                 -- RareScanner's provider and its canvas (RSWorldMap)
local origRefresh, origAcquire
local ctx                   -- the pass under way: { source, host, pins, drops } / { collect, pois }
local busy = false
local warned = {}

-- ---------------------------------------------------------------------------------------------
-- A stand-in pin for passes that only collect POIs (the minimap): any field is a no-op that
-- returns itself, so pin.ShowSearchAnim:Play() and pin:ShowOverlay() do nothing.
-- ---------------------------------------------------------------------------------------------
local Stub
Stub = setmetatable({}, {
    __index = function() return Stub end,
    __call = function() return Stub end,
})
M.Stub = Stub

local function nop() end

local function WarnOnce(key, msg)
    if warned[key] then return end
    warned[key] = true
    ns:Print(msg, true)
end
M.WarnOnce = WarnOnce

-- ---------------------------------------------------------------------------------------------
-- Checks: RareScanner's internals this needs, looked at once at login
-- ---------------------------------------------------------------------------------------------

local function Missing(provider)
    if type(provider) ~= "table" then return "RareScannerDataProviderMixin" end
    for _, k in ipairs({ "RefreshAllData", "RemoveAllData", "GetMap" }) do
        if type(provider[k]) ~= "function" then return "RareScannerDataProviderMixin." .. k end
    end
    local ok, map = pcall(provider.GetMap, provider)
    if not ok or type(map) ~= "table" then return "RareScannerDataProviderMixin:GetMap()" end
    for _, k in ipairs({ "AcquirePin", "RemovePin", "GetMapID", "GetMapFrame" }) do
        if type(map[k]) ~= "function" then return "RareScanner's map canvas: " .. k end
    end
    return nil, map
end

function M.Ready() return P ~= nil end

-- ---------------------------------------------------------------------------------------------
-- Positions: a point of a neighbouring zone on the shown map (Zones.Place)
-- ---------------------------------------------------------------------------------------------

function M.Convert(source, x, y, host)
    if type(x) ~= "number" or type(y) ~= "number" or not host then return nil end
    return ns.Zones.Place(source, x, y, host)
end

-- Whether the shown map gets its neighbours' icons now (the option for the map that's up, with
-- the world map open).
function M.ShouldExtend()
    local db = ns.db
    if not (db and db.enabled and db.rarescanner) then return false end
    if ns.Zones.Stitched() then
        if not db.openmap then return false end
    elseif not db.worldmap then
        return false
    end
    local ok, frame = pcall(RS.GetMapFrame, RS)
    return ok and frame and frame:IsVisible() and true or false
end

-- ---------------------------------------------------------------------------------------------
-- Pins
-- ---------------------------------------------------------------------------------------------

-- The zone an overlay spot's or guide icon's pin belongs to: its parent pin's (acquired outside a
-- pass, from a click on a neighbour's pin).
local function ParentSource(template, ...)
    local parent
    if template == "RSOverlayTemplate" then
        local _, _, _, _, _, poi, groupPin = ...
        parent = groupPin or poi
    elseif template == "RSGuideTemplate" then
        local _, pin = ...
        parent = pin
    end
    return type(parent) == "table" and rawget(parent, "nrSource") or nil
end

local function Place(pin, source, host, pass)
    local x, y = M.Convert(source, pin.x, pin.y, host)
    if x then
        pin.x, pin.y = x, y
        if pin.ApplyCurrentPosition then pin:ApplyCurrentPosition() end
    else
        -- Off the shown map: hidden now, given back to RareScanner's pool after the passes
        if pin.Hide then pin:Hide() end
        if pass and pass.drops then pass.drops[#pass.drops + 1] = pin end
    end
end

-- What RareScanner's collecting pass hands over: copies of the POIs, groups as their entities.
local function Copy(POI)
    local c = {}
    for k, v in pairs(POI) do
        if k ~= "POIs" then c[k] = v end
    end
    return c
end

local function Collect(pass, template, POI)
    if type(POI) ~= "table" then return end
    if template == "RSEntityPinTemplate" then
        pass.pois[#pass.pois + 1] = Copy(POI)
    elseif template == "RSGroupPinTemplate" and type(POI.POIs) == "table" then
        for _, child in ipairs(POI.POIs) do
            if type(child) == "table" then pass.pois[#pass.pois + 1] = Copy(child) end
        end
    end
end

local function Acquire(self, template, ...)
    local pass = ctx
    if pass and pass.collect then
        Collect(pass, template, ...)
        return Stub
    end
    local pin = origAcquire(self, template, ...)
    if type(pin) ~= "table" then return pin end
    local source
    if pass then
        source = pass.source
    else
        source = ParentSource(template, ...)
    end
    pin.nrSource = source
    if source then
        local host = pass and pass.host or self:GetMapID()
        Place(pin, source, host, pass)
    end
    if pass and pass.pins and ENTITY_TEMPLATES[template] then pass.pins[#pass.pins + 1] = pin end
    return pin
end

-- ---------------------------------------------------------------------------------------------
-- Passes
-- ---------------------------------------------------------------------------------------------

-- Runs RareScanner's own refresh for one zone with mapID set to it, RemoveAllData a no-op, and
-- ctx = pass; every override back afterwards. Returns ok, err.
local function RunPass(mapID, pass, ...)
    local savedMapID = rawget(RS, "mapID")
    local savedRemove = rawget(P, "RemoveAllData")
    local savedCtx = ctx
    rawset(RS, "mapID", mapID)
    rawset(P, "RemoveAllData", nop)
    ctx = pass
    local ok, err = pcall(origRefresh, P, ...)
    ctx = savedCtx
    rawset(P, "RemoveAllData", savedRemove)
    rawset(RS, "mapID", savedMapID)
    return ok, err
end
M.RunPass = RunPass

local function PinKey(pin)
    local POI = pin.POI
    if type(POI) ~= "table" then return nil end
    if POI.entityID then return tostring(POI.entityID) end
    if type(POI.POIs) == "table" then
        local ids = {}
        for _, c in ipairs(POI.POIs) do ids[#ids + 1] = tostring(c.entityID) end
        table.sort(ids)
        return "g:" .. table.concat(ids, ",")
    end
end

-- One icon per entity and spot: a neighbour's pin where the shown map (or an earlier neighbour)
-- already has the same one goes back to the pool.
local function Dedupe(hostPins, neighbourPins)
    local seen = {}
    local function Near(key, x, y)
        for _, p in ipairs(seen[key] or {}) do
            if math.abs(p[1] - x) < SAME_SPOT and math.abs(p[2] - y) < SAME_SPOT then return true end
        end
        return false
    end
    local function Add(key, x, y)
        seen[key] = seen[key] or {}
        table.insert(seen[key], { x, y })
    end
    for _, pin in ipairs(hostPins) do
        local key = PinKey(pin)
        if key and pin.x and pin.y then Add(key, pin.x, pin.y) end
    end
    local removed = 0
    for _, pin in ipairs(neighbourPins) do
        local key = PinKey(pin)
        if key and pin.x and pin.y and pin.POI then
            if Near(key, pin.x, pin.y) then
                pcall(RS.RemovePin, RS, pin)
                removed = removed + 1
            else
                Add(key, pin.x, pin.y)
            end
        end
    end
    return removed
end

-- The wrapped RefreshAllData.
local function Refresh(self, ...)
    if ns.RareScannerMinimap then ns.RareScannerMinimap:Dirty() end
    if busy or self ~= P or not M.ShouldExtend() then return origRefresh(self, ...) end
    local host = RS:GetMapID()
    local list = host and ns.Zones.Neighbours(host) or {}
    if #list == 0 then return origRefresh(self, ...) end

    busy = true
    -- clear once; the passes don't clear again
    local okClear, errClear = pcall(P.RemoveAllData, P)
    if not okClear then geterrorhandler()(errClear) end

    local neighbourPins, hostPins, drops = {}, {}, {}
    for _, zone in ipairs(list) do
        local ok, err = RunPass(zone, { source = zone, host = host, pins = neighbourPins, drops = drops }, ...)
        if not ok then
            WarnOnce("pass", "RareScanner errored while listing a nearby zone's icons; that zone is skipped.")
            ns:Debug("pass " .. tostring(zone) .. ": " .. tostring(err))
        end
    end
    -- the shown map last, with its own mapID (route, guide and animations end on it)
    local ok, err = RunPass(rawget(RS, "mapID"), { host = host, pins = hostPins }, ...)
    busy = false

    for _, pin in ipairs(drops) do pcall(RS.RemovePin, RS, pin) end
    local okDedupe, errDedupe = pcall(Dedupe, hostPins, neighbourPins)
    if not okDedupe then ns:Debug("dedupe: " .. tostring(errDedupe)) end
    M.last = { host = host, zones = #list, pins = #neighbourPins - #drops }
    if not ok then geterrorhandler()(err) end
end

-- RareScanner's refresh for one zone, its POIs collected instead of drawn (the minimap's harvest):
-- a list of POI copies (each with mapID, x, y), or nil and the error.
function M.CollectZone(mapID)
    if not P or busy then return nil, "busy" end
    busy = true
    local pass = { collect = true, pois = {} }
    local ok, err = RunPass(mapID, pass)
    busy = false
    if not ok then return nil, err end
    return pass.pois
end

-- The world map again (an option changed, OpenMap switched maps).
function M.Redraw()
    if not P then return end
    local ok, frame = pcall(RS.GetMapFrame, RS)
    if ok and frame and frame:IsVisible() then
        local okR, err = pcall(P.RefreshAllData, P)
        if not okR then geterrorhandler()(err) end
    end
end

-- Wraps RareScanner's provider (once). Returns true, or false and what's missing.
function M.Install(provider)
    if P then return true end
    local missing, map = Missing(provider or _G.RareScannerDataProviderMixin)
    if missing then return false, missing end
    P, RS = provider or _G.RareScannerDataProviderMixin, map
    origRefresh = rawget(P, "RefreshAllData") or P.RefreshAllData
    origAcquire = rawget(RS, "AcquirePin") or RS.AcquirePin
    rawset(P, "RefreshAllData", Refresh)
    rawset(RS, "AcquirePin", Acquire)
    return true
end

-- for the tests
function M._State() return { P = P, RS = RS, ctx = ctx, busy = busy } end
function M._Reset() P, RS, origRefresh, origAcquire, ctx, busy = nil, nil, nil, nil, nil, false; wipe(warned) end
