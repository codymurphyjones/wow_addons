local _, ns = ...

-- OneForAll (optional): when it's loaded, its Map Landmarks own the world map's landmark icons
-- (dungeon and raid entrances, flight masters, zeppelins, ships and the tram), so Waypoint doesn't
-- draw its dock icons on top of them (TransportPins.lua), and its icons take you there instead:
--   click a flight master, zeppelin, ship, tram (or Skyborne) icon: Waypoint leads you there
--     (click again to stop), as Waypoint's own dock icons did;
--   Shift-click an entrance, a zone exit or a book (a plain click keeps OneForAll's action: it opens
--     the dungeon, the next map, the book);
--   Ctrl+click any of them adds a waypoint there, as anywhere else on the map.
-- Waypoint's town icons stay, and every route still uses Waypoint's own data (docks, flights, towns):
-- only the icons are OneForAll's. Without OneForAll (or with its landmarks or transport icons off)
-- nothing changes.
--
-- OneForAll's pins are plain buttons in its own pool (OneForAll.MapLandmarks._pool), each with the
-- landmark it shows in .entry (kind, x and y 0-100, name, dest, list): their click is wrapped once a
-- pin, and reads .entry at the time of the click (the pins are reused).
local O = {}
ns.OneForAll = O

local GO = { flight = true, zeppelin = true, shipA = true, shipH = true, tram = true, leyline = true, convergence = true }
local KIND = { zeppelin = "Zeppelin", shipA = "Ship", shipH = "Ship", tram = "Deeprun Tram", leyline = "Ley line",
    convergence = "Convergence", transition = "Way to", book = "Book" }

local function Lib()
    local ofa = _G.OneForAll
    if type(ofa) == "table" and type(ofa.MapLandmarks) == "table" and type(ofa.QoL) == "table"
        and type(ofa.QoL.Get) == "function" then return ofa end
end

function O:Loaded() return Lib() ~= nil end

local function On(key)
    local ofa = Lib()
    if not ofa then return false end
    local ok, v = pcall(ofa.QoL.Get, key)
    return ok and v ~= false and v ~= nil
end

-- Whether OneForAll draws the zeppelin, ship and tram docks (then Waypoint's dock icons stay off).
function O:DocksShown() return On("mapLandmarks") and On("lmTransport") end

-- What the landmark is called, for the arrow.
local function Title(e)
    if e.kind == "flight" then return e.name or "Flight master" end
    if (e.kind == "dungeon" or e.kind == "raid") and e.list and e.list[1] then
        return (e.list[1].name or "Dungeon") .. " entrance"
    end
    if e.kind == "book" and e.book then return e.book.name or "Book" end
    local first = e.dest and e.dest[1]
    local kind = KIND[e.kind] or "Landmark"
    return first and (kind .. " to " .. first:gsub(",.*$", "")) or kind
end

-- Waypoint's own dock at this spot (within a few map percent), for its ride radius and its master.
local function DockAt(mapID, x, y)
    if not (ns.Route and ns.Route.Docks) then return nil end
    local best, bd
    for _, d in ipairs(ns.Route:Docks()) do
        local p = d.point
        if p.mapID == mapID then
            local dd = (p.x - x) ^ 2 + (p.y - y) ^ 2
            if dd < 0.03 ^ 2 and (not bd or dd < bd) then best, bd = d, dd end
        end
    end
    return best
end

local OWNER = "Landmarks"

local function Going(title)
    local r = ns.Targets:GetRequest()
    return r and (r.owner == OWNER or r.owner == "Docks") and r.title == title
end

-- Leads the arrow to a landmark (or stops, when it's already where you're going).
local function Navigate(e)
    local mapID = e.mapID or (WorldMapFrame and WorldMapFrame:GetMapID())
    if not (mapID and e.x and e.y) then return end
    local x, y = e.x / 100, e.y / 100
    local dock = (e.kind ~= "flight") and DockAt(mapID, x, y)
    local title = dock and dock.point.label or Title(e)
    if Going(title) then
        ns:Print(("Stopped navigating to %s."):format(title))
        return ns.Targets:ClearRequest(true)
    end
    if dock and ns.TransportPins then return ns.TransportPins:Navigate(dock) end
    ns.Targets:SetRequest(OWNER, { title = title,
        points = { { mapID = mapID, x = x, y = y, label = title, npc = e.kind == "flight" and e.name or nil } },
        arrive = 30 })
end

local function Hint(pin)
    local e = pin.entry
    if not e or not GameTooltip:IsOwned(pin) then return end
    local go = GO[e.kind]
    local title = Title(e)
    GameTooltip:AddLine(" ")
    if Going(title) then
        GameTooltip:AddLine((go and "Click" or "Shift-click") .. ": Waypoint stops navigating here", 0.25, 0.77, 0.8)
    else
        GameTooltip:AddLine((go and "Click" or "Shift-click") .. ": Waypoint takes you there", 0.25, 0.77, 0.8)
    end
    GameTooltip:Show()
end

local function Wire(pin)
    if pin.waypointWired then return end
    pin.waypointWired = true
    local theirs = pin:GetScript("OnClick")
    pin:SetScript("OnClick", function(self, button, ...)
        if ns.MapPins and ns.MapPins:AddClick(button) then return ns.MapPins:AddAtCursor() end
        local e = self.entry
        if e and button == "LeftButton" and not IsControlKeyDown() and not IsAltKeyDown() then
            if GO[e.kind] and not IsShiftKeyDown() then return Navigate(e) end
            if not GO[e.kind] and IsShiftKeyDown() then return Navigate(e) end
        end
        if theirs then return theirs(self, button, ...) end
    end)
    pin:HookScript("OnEnter", Hint)
end

-- Whether frame f is one of OneForAll's landmark pins (town badges leave those alone: Towns.lua).
function O:Owns(f)
    if f.waypointWired then return true end
    local ofa = Lib()
    local pool = ofa and ofa.MapLandmarks._pool
    if type(pool) ~= "table" then return false end
    for _, pin in pairs(pool) do
        if pin == f then return true end
    end
    return false
end

local function WireAll()
    local ofa = Lib()
    local pool = ofa and ofa.MapLandmarks._pool
    if type(pool) ~= "table" then return end
    for _, pin in pairs(pool) do
        if type(pin) == "table" and pin.GetScript then pcall(Wire, pin) end
    end
end

-- OneForAll lays its pins out when the map opens, changes or zooms (and when its settings change):
-- each time, the new ones are wired (a moment later, after its own layout).
local function Soon() C_Timer.After(0, WireAll) end

ns:On("PLAYER_LOGIN", function()
    local ofa = Lib()
    if not ofa then return end
    if type(ofa.MapLandmarks.Refresh) == "function" then hooksecurefunc(ofa.MapLandmarks, "Refresh", Soon) end
    if WorldMapFrame then
        WorldMapFrame:HookScript("OnShow", Soon)
        if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", Soon) end
    end
end)
