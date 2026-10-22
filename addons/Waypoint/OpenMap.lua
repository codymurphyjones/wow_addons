local _, ns = ...

-- OpenMap (third party): Waypoint owns the waypoint flow on its map too.
--   * Its Ctrl+click and its pin button's next click add a Waypoint waypoint (not an OpenMap pin).
--   * "Follow" on one of its saved pins makes that the current waypoint; "stop following" clears
--     the current one: the same as clearing Blizzard's pin (Chain.lua).
--   * Its own waypoint marker isn't drawn: Waypoint's pins are the only ones (MapPins.lua).
--   * Its "Drop a pin" button on the map is replaced by Waypoint's "Drop a waypoint" (OpenMapAPI's
--     menu toggle, starred in its place). OpenMap's menu still lists its own "Drop a pin" tile, but
--     that now does the same.
-- OpenMapAPI (version 1+) is public; the rest are OpenMap's module functions (OpenMap:GetModule),
-- which it calls through the module table, so they can be replaced. All of it is looked for and
-- left alone when it isn't there: an OpenMap update that changes them just loses this.
local OM = {}
ns.OpenMap = OM

local TOGGLE = "pin"
local FAVORITE = "ext.Waypoint." .. TOGGLE

local function Module()
    local addon = rawget(_G, "OpenMap")
    if type(addon) ~= "table" or type(addon.GetModule) ~= "function" then return end
    local ok, mod = pcall(addon.GetModule, addon, "worldmap")
    return ok and type(mod) == "table" and mod or nil
end

-- A point of OpenMap's stitched world (u, v) as a zone point: mapID, x, y.
local function ZonePoint(u, v)
    local api = rawget(_G, "OpenMapAPI")
    if not (api and type(u) == "number" and type(v) == "number") then return end
    local mapID = api.MapAt(u, v)
    if not mapID then return end
    local x, y = api.MapFromWorld(mapID, u, v)
    if x and y then return mapID, x, y end
end

-- Its button on the map: Waypoint's in place of "Drop a pin" (each login: it stays replaced).
local function SwapFavorite(mod)
    local favs = mod.db and mod.db.favorites
    if type(favs) ~= "table" then return end
    local at, have
    for i = #favs, 1, -1 do
        if favs[i] == TOGGLE then
            at = i
            table.remove(favs, i)
        elseif favs[i] == FAVORITE then
            have = true
        end
    end
    if at and not have then table.insert(favs, math.min(at, #favs + 1), FAVORITE) end
    if mod.RefreshPanel then pcall(mod.RefreshPanel, mod) end
    if mod.RefreshRail then pcall(mod.RefreshRail) end
end

function OM:Hook()
    local mod = Module()
    if not mod or self.hooked then return end
    self.hooked = true

    -- Ctrl+click on its map, and its pin button's next click.
    if mod.DropWaypoint then
        mod.DropWaypoint = function(u, v)
            local mapID, x, y = ZonePoint(u, v)
            if mapID then ns.MapPins:Add(mapID, x, y) end
        end
    end
    -- "Follow" a saved pin of its own: that's the current waypoint now.
    if mod.TrackPoint then
        mod.TrackPoint = function(mapID, x, y, title)
            if type(mapID) == "number" and type(x) == "number" and type(y) == "number" then
                ns.Chain:Follow(mapID, x, y, title)
            end
        end
    end
    -- "Stop following" (its pin button's right-click, a pin's card): the current waypoint is done.
    if mod.ClearPin then
        mod.ClearPin = function()
            if ns.Chain:IsOurs() and C_Map and C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
        end
    end
    -- Its own waypoint marker: none (Waypoint draws them all).
    if mod.WaypointPoint then
        mod.WaypointPoint = function() return nil end
    end

    -- Waypoint's button, in OpenMap's menu and on the map where "Drop a pin" was.
    local api = rawget(_G, "OpenMapAPI")
    if api and api.RegisterMenuToggle and mod.SetPinMode and mod.PinMode then
        pcall(api.RegisterMenuToggle, "Waypoint", {
            id = TOGGLE, label = "Drop a waypoint", icon = ns.ICON, section = "Waypoint",
            get = function() return mod.PinMode() and true or false end,
            set = function(on) mod.SetPinMode(on) end,
        })
        SwapFavorite(mod)
    end
end

ns:On("PLAYER_LOGIN", function() OM:Hook() end)
