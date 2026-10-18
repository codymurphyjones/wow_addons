local addonName, ns = ...

ns.VERSION = "0.1.0"
-- Waypoint's logo, shipped in the addon (Media\make_icon.py draws it).
ns.ICON = "Interface\\AddOns\\Waypoint\\Media\\Icon"

-- The logo as inline text markup, size x size pixels.
function ns.IconMarkup(size)
    return ("|T%s:%d:%d|t"):format(ns.ICON, size, size)
end

ns.PREFIX = ns.IconMarkup(14) .. " |cffffc94dWaypoint|r"

ns.DEFAULTS = {
    dockAlign = "CENTER", -- windows docked under the arrow (Field Guide): "LEFT", "CENTER" or "RIGHT"
    quests = true,   -- point at Questie quests when nothing else asks
    share = true,    -- share your waypoint path with your group
    confirm = true,  -- ask before adding a waypoint from the map
    locked = false,  -- the arrow can't be dragged
    arrowHidden = false,
    flights = true,  -- lead to a flight master when flying is quicker
    towns = true,    -- town icons on the world map, with what's there (Towns.lua)
    autoFly = true,  -- a flight master with no menu: take the planned flight right away (hold Shift to choose)
    taxi = { nodes = {}, times = {} }, -- flight points' positions and timed flights, for every character
    arrow = { point = "TOP", x = 0, y = -150 },
}

ns.CHAR_DEFAULTS = {
    minimap = { angle = 200, hide = false },
    seq = 0,          -- orders targets: the newest one wins
    chain = {},       -- the waypoint path: { { id, by, mapID, x, y, title } }, in order
    chainStarter = nil,
    chainT = 0,
    reached = {},     -- path waypoint ids you reached, so a resend doesn't bring them back
    idCounter = 0,
    entries = {},     -- targets set by other addons: owner -> fields (no functions)
    taxi = { known = {} }, -- flight points you know (name -> true); mount = fastest mount speed seen
    -- Quest tracking history (Questie.lua): [questID] = { by = "user" or an addon's name, at = seq }.
    -- "user" only for quests you tracked yourself; anything else tracked counts as an addon's.
    tracking = {},
    untracked = {},   -- [questID] = true: you untracked it yourself; no addon tracks it again while it's in your log
}

local function Merge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            Merge(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

function ns:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(self.PREFIX .. ": " .. tostring(msg))
end

-- The next number in the newest-wins order.
-- The arrow's colors. A target picks one with color = "gold" | "green" | "purple": gold for
-- waypoints you put down yourself (and anything that doesn't say), green for a leveling guide's
-- steps, purple for a dungeon's.
ns.COLORS = {
    gold = { 1, 0.79, 0.3 },
    green = { 0.56, 0.82, 0.42 },
    purple = { 0.78, 0.55, 1 },
    request = { 0.35, 0.85, 1 }, -- a request ("Navigate to"): always the next point
}

function ns:ColorOf(entry)
    return entry and self.COLORS[entry.color] or self.COLORS.gold
end

-- In a battleground or arena: Waypoint keeps out of the way entirely there (the arrow and the
-- minimap dot hide; they come back when you leave).
function ns:InBattleground()
    if not IsInInstance then return false end
    local inside, kind = IsInInstance()
    return inside and (kind == "pvp" or kind == "arena") or false
end

function ns:NextSeq()
    self.char.seq = (self.char.seq or 0) + 1
    return self.char.seq
end

-- Targets or the path changed: redraw once, next frame.
local pending
function ns:Changed()
    if pending then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        if ns.Targets then ns.Targets:Tick() end
        if ns.MapPins then ns.MapPins:Refresh() end
        if ns.Arrow then ns.Arrow:Refresh() end
        if ns.MinimapButton then ns.MinimapButton:Refresh() end
        if ns.TownPins then ns.TownPins:Refresh() end
    end)
end

local frame = CreateFrame("Frame")
local handlers = {}
function ns:On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        pcall(frame.RegisterEvent, frame, event)
    end
    table.insert(handlers[event], fn)
end
frame:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event] or {}) do fn(...) end
end)

function ns:OnLoad(fn)
    self.onLoad = self.onLoad or {}
    table.insert(self.onLoad, fn)
end

ns:On("ADDON_LOADED", function(name)
    if name ~= addonName then return end
    WaypointDB = Merge(type(WaypointDB) == "table" and WaypointDB or {}, ns.DEFAULTS)
    WaypointCharDB = Merge(type(WaypointCharDB) == "table" and WaypointCharDB or {}, ns.CHAR_DEFAULTS)
    ns.db, ns.char = WaypointDB, WaypointCharDB
    for _, fn in ipairs(ns.onLoad or {}) do fn() end
end)

ns:On("PLAYER_LOGIN", function()
    ns:Print("v" .. ns.VERSION .. " loaded. Ctrl+click the world map to add waypoints, |cffffffff/way help|r for more.")
end)

local function OnOff(key, label, arg)
    if arg == "on" or arg == "off" then
        ns.db[key] = arg == "on"
    else
        ns.db[key] = not ns.db[key]
    end
    ns:Print(label .. (ns.db[key] and " on." or " off."))
    ns:Changed()
end

local function Help()
    ns:Print("/way - what the arrow points at")
    ns:Print("/way <x> <y> [title] - add a waypoint in your zone to the path")
    ns:Print("/way clear - clear the waypoint path (for your group too)")
    ns:Print("/way undo - undo your last path change (Ctrl+Z with the map open)")
    ns:Print("/way quests on | off - point at Questie quests when nothing else asks")
    ns:Print("/way share on | off - share your path with your group")
    ns:Print("/way confirm on | off - ask before adding a waypoint")
    ns:Print("/way flights [on | off] - lead to a flight master when flying is quicker (no option: what it knows)")
    ns:Print("/way autofly on | off - at a flight master with no menu, take the planned flight right away (hold Shift to choose)")
    ns:Print("/way arrow - show or hide the arrow, /way lock - lock or unlock it")
    ns:Print("/way minimap - show or hide the minimap button")
    ns:Print("/way towns on | off - town icons on the world map (hover: what's there, click: go there)")
    ns:Print("World map: Ctrl+left-click adds a waypoint, Ctrl+right-click removes the nearest one.")
end

SLASH_WAYPOINT1 = "/waypoint"
SLASH_WAYPOINT2 = "/way"
SlashCmdList.WAYPOINT = function(msg)
    if not ns.db then return end
    msg = strtrim(msg or "")
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")
    cmd, arg = strlower(cmd or ""), strlower(arg or "")
    local x, y, title = msg:match("^([%d%.]+)[,%s]+([%d%.]+)%s*(.*)$")
    if x then
        local mapID = C_Map.GetBestMapForUnit("player")
        x, y = tonumber(x), tonumber(y)
        if not (mapID and x and y) then
            ns:Print("Can't tell which zone you're in.")
            return
        end
        if x > 1 or y > 1 then x, y = x / 100, y / 100 end
        ns.Chain:Request(mapID, x, y, title ~= "" and title or nil, true)
    elseif cmd == "clear" then
        ns.Chain:Clear()
    elseif cmd == "undo" then
        ns.Chain:Undo()
    elseif cmd == "quests" then
        OnOff("quests", "Questie quests", arg)
        if not (ns.Questie and ns.Questie:Available()) then
            ns:Print("Questie isn't loaded, so there are no quests to point at (everything else works without it).")
        end
        if ns.Questie then ns.Questie:Select() end
    elseif cmd == "share" then
        OnOff("share", "Sharing with your group", arg)
    elseif cmd == "autofly" then
        OnOff("autoFly", "Taking the planned flight by itself", arg)
    elseif cmd == "flights" then
        if arg == "on" or arg == "off" then OnOff("flights", "Flight paths", arg) else ns.Flight:Status() end
    elseif cmd == "towns" and arg == "debug" then
        ns.TownPins:Debug()
    elseif cmd == "towns" then
        OnOff("towns", "Town icons on the world map", arg)
    elseif cmd == "confirm" then
        OnOff("confirm", "Asking before adding a waypoint", arg)
    elseif cmd == "arrow" then
        ns.db.arrowHidden = not ns.db.arrowHidden
        ns:Print(ns.db.arrowHidden and "Arrow hidden. /way arrow shows it again." or "Arrow shown.")
        ns:Changed()
    elseif cmd == "lock" then
        ns.db.locked = not ns.db.locked
        ns:Print(ns.db.locked and "Arrow locked." or "Arrow unlocked: drag it to move it.")
    elseif cmd == "minimap" then
        ns.char.minimap.hide = not ns.char.minimap.hide
        ns.MinimapButton:Refresh()
        ns:Print(ns.char.minimap.hide and "Minimap button hidden. /way minimap shows it again." or "Minimap button shown.")
    elseif cmd == "help" then
        Help()
    else
        ns:Print(ns.Targets:Describe())
    end
end

function Waypoint_OnCompartmentClick()
    if not ns.db then return end
    ns.db.arrowHidden = not ns.db.arrowHidden
    ns:Changed()
end
