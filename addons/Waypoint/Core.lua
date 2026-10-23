local addonName, ns = ...

ns.VERSION = "0.1.1"
-- Waypoint's logo, shipped in the addon (Media\make_icon.py draws it).
ns.ICON = "Interface\\AddOns\\Waypoint\\Media\\Icon"

ns.PREFIX = ns.IconMarkup(14) .. " |cffffc94dWaypoint|r"

-- Events, saved variables, Print, Changed and timers: the shared Core.lua (addons/shared).
ns.SAVED = { db = "WaypointDB", char = "WaypointCharDB" }

ns.DEFAULTS = {
    dockAlign = "CENTER", -- windows docked under the arrow (Field Guide): "LEFT", "CENTER" or "RIGHT"
    quests = true,   -- point at Questie quests when nothing else asks
    share = true,    -- share your waypoint path with your group
    confirm = false, -- ask before adding a waypoint from the map (Ctrl+click is deliberate: off)
    locked = false,  -- the arrow can't be dragged
    arrowHidden = false,
    flights = true,  -- lead to a flight master when flying is quicker
    transports = true, -- also plan with boats, zeppelins and skyships (Route.lua)
    useHearth = true,  -- ...your hearthstone
    useTeleports = true, -- ...mage teleports (with a rune in your bags)
    useGrid = true,    -- follow the land and water map (Grid.lua): around lakes and cliffs; off: straight lines
    allowSwim = true,  -- swim where that's quicker (off: only where there's no other way)
    useAquatic = true, -- count Aquatic Form's speed when you know it
    formTips = true,   -- say in chat when to switch to Aquatic Form
    useSafeFall = true, -- jump down any cliff with Slow Fall or Levitate (spell and Light Feather)
    maxFallPct = 0,    -- fall damage you'll take without one, % of your health (0: only harmless drops)
    climb = 1,         -- each yard climbed counts as this many yards more on the flat
    roadMode = "balanced", -- how much a walk keeps to roads (Route.lua ROAD_MODES): safe, balanced or speed
    minGain = 45,      -- a route instead of walking must save this many seconds...
    minShare = 15,     -- ...and this % of the trip
    announce = true,   -- the "Fastest way: ..." chat line
    steer = true,      -- the arrow leads around lakes and cliffs
    showHeight = true, -- the arrow says how far above or below you the target is
    showWay = true,    -- draw the planned trip as a dashed line on the world map (WayLine.lua)
    showWayMinimap = true, -- ...and as a trail of dots on the minimap
    learned = {},      -- steps you walked that the land map said you couldn't: [continent] = { [link key] = true }
    blocked = {},      -- steps you said are blocked ("This way is blocked"): [continent] = { [link key] = true }
    rides = {},      -- rides you've taken: [dock key] = { secs (waiting included), n, m, x, y (where it landed) }
    teleports = {},  -- where mage teleports land: [spellID] = { m, x, y }
    towns = true,    -- town icons on the world map, with what's there (Towns.lua)
    transportPins = true, -- zeppelin, skyship and ship docks on the world map (TransportPins.lua)
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
    hearth = {},      -- where your hearthstone takes you: { bind = GetBindLocation(), m, x, y }
    -- Quest tracking history (Questie.lua): [questID] = { by = "user" or an addon's name, at = seq }.
    -- "user" only for quests you tracked yourself; anything else tracked counts as an addon's.
    tracking = {},
    untracked = {},   -- [questID] = true: you untracked it yourself; no addon tracks it again while it's in your log
}

-- The next number in the newest-wins order.
-- The arrow's colors. A target picks one with color = "gold" | "green" | "purple": gold for
-- waypoints you put down yourself (and anything that doesn't say), green for a leveling guide's
-- steps, purple for a dungeon's.
ns.COLORS = {
    gold = { 1, 0.79, 0.3 },
    green = { 0.56, 0.82, 0.42 },
    purple = { 0.78, 0.55, 1 },
    request = { 0.35, 0.85, 1 }, -- a request ("Navigate to"): always the next point
    corpse = { 0.85, 0.92, 1 },   -- your body, while you're a ghost
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

-- Targets or the path changed: redraw (once, next frame: ns:Changed).
ns:OnChanged(function()
    if ns.Targets then ns.Targets:Tick() end
    if ns.MapPins then ns.MapPins:Refresh() end
    if ns.Arrow then ns.Arrow:Refresh() end
    if ns.MinimapButton then ns.MinimapButton:Refresh() end
    if ns.TownPins then ns.TownPins:Refresh() end
    if ns.TransportPins then ns.TransportPins:Refresh() end
end)

-- The frame level Waypoint's world map layers count up from (+2000 the path's lines, +2050 the
-- planned trip, town badges up to +2090, +2100 the path's pins): the canvas's, lifted over
-- OpenMap's stitched art when it reaches them (it sits above the map's own layers, and anything
-- under its top is hidden by it).
-- (The shared WorldMap.lua's MapBase.)
function ns:MapBase(canvas) return ns.WorldMap.MapBase(canvas) end

ns:On("PLAYER_LOGIN", function()
    ns:Print("v" .. ns.VERSION .. " loaded. Ctrl+click the world map to add waypoints, |cffffffff/way help|r for more.")
end)

-- Slash toggles change the same options as Options > AddOns > Waypoint (ns:SetOption), so the page shows them.
local function OnOff(key, label, arg)
    if arg == "on" or arg == "off" then
        ns:SetOption("db." .. key, arg == "on")
    else
        ns:ToggleOption("db." .. key)
    end
    ns:Print(label .. (ns.db[key] and " on." or " off."))
end

local function Help()
    ns:Print("/way - what the arrow points at")
    ns:Print("/way <x> <y> [title] - add a waypoint in your zone to the path")
    ns:Print("/way clear - clear the waypoint path (for your group too)")
    ns:Print("/way undo - undo your last path change (Ctrl+Z with the map open)")
    ns:Print("/way list - your waypoints, numbered")
    ns:Print("/way remove <number> - remove one of them (or Ctrl+right-click it on the map)")
    ns:Print("/way quests on | off - point at Questie quests when nothing else asks")
    ns:Print("/way share on | off - share your path with your group")
    ns:Print("/way confirm on | off - ask before adding a waypoint")
    ns:Print("/way flights [on | off] - lead to a flight master when flying is quicker (no option: what it knows)")
    ns:Print("/way where - which floor Waypoint has you on, where floors are stacked (a city's streets and bridges)")
    ns:Print("/way transports on | off - also plan with boats, zeppelins, skyships, your hearthstone and mage teleports")
    ns:Print("/way options - all of Waypoint's settings (Options > AddOns > Waypoint)")
    ns:Print("/way blocked - the way the arrow leads isn't there (a fence, a ledge): block it and find another; /way unblock forgets them")
    ns:Print("/way autofly on | off - at a flight master with no menu, take the planned flight right away (hold Shift to choose)")
    ns:Print("/way arrow - show or hide the arrow, /way lock - lock or unlock it")
    ns:Print("/way minimap - show or hide the minimap button")
    ns:Print("/way towns on | off - town icons on the world map (hover: what's there, click: go there)")
    ns:Print("/way docks on | off - zeppelin, skyship and ship docks on the world map (hover: ride time, click: go there)")
    ns:Print("World map: Ctrl+click adds a waypoint (the first is Blizzard's map pin), Ctrl+right-click any pin removes it, Ctrl+Z undoes.")
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
    elseif cmd == "list" then
        local points = ns.Chain:Points()
        local r = ns.Targets:GetRequest()
        if #points == 0 and not r then ns:Print("No waypoints.") end
        for i, p in ipairs(points) do
            ns:Print(("%d. %s%s"):format(i, p.title and (p.title .. ", ") or "", ns.Nav:Describe(p)))
        end
        if r then ns:Print(("Navigate to: %s"):format(r.title or "your destination")) end
        if #points > 0 then ns:Print("/way remove <number> removes one.") end
    elseif cmd == "remove" then
        local n = tonumber(arg)
        if n and ns.Chain:RemoveAt(n) then return end
        ns:Print(("There's no waypoint %s. /way list shows them."):format(arg ~= "" and arg or "with that number"))
    elseif cmd == "quests" then
        OnOff("quests", "Questie quests", arg)
        if not (ns.Questie and ns.Questie:Available()) then
            ns:Print("Questie isn't loaded, so there are no quests to point at (everything else works without it).")
        end
    elseif cmd == "share" then
        OnOff("share", "Sharing with your group", arg)
    elseif cmd == "autofly" then
        OnOff("autoFly", "Taking the planned flight by itself", arg)
    elseif cmd == "transports" then
        OnOff("transports", "Boats, zeppelins, hearthstone and teleports", arg)
        ns:SetOption("db.useHearth", ns.db.transports)
        ns:SetOption("db.useTeleports", ns.db.transports)
    elseif cmd == "blocked" or cmd == "block" then
        ns.Route:BlockAhead()
    elseif cmd == "unblock" then
        ns.Route:ClearBlocks()
    elseif cmd == "options" or cmd == "settings" or cmd == "config" then
        if ns.Settings then ns.Settings:Open() end
    elseif cmd == "flights" then
        if arg == "on" or arg == "off" then OnOff("flights", "Flight paths", arg) else ns.Flight:Status() end
    elseif cmd == "where" then
        ns:Print("Where Waypoint has you: " .. (ns.Grid.WhereText and ns.Grid:WhereText() or "the land map only (no walkable-ground data here)"))
    elseif cmd == "towns" and arg == "debug" then
        ns.TownPins:Debug()
    elseif cmd == "towns" then
        OnOff("towns", "Town icons on the world map", arg)
    elseif cmd == "docks" then
        OnOff("transportPins", "Dock icons on the world map", arg)
    elseif cmd == "confirm" then
        OnOff("confirm", "Asking before adding a waypoint", arg)
    elseif cmd == "arrow" then
        ns:ToggleOption("db.arrowHidden")
        ns:Print(ns.db.arrowHidden and "Arrow hidden. /way arrow shows it again." or "Arrow shown.")
    elseif cmd == "lock" then
        ns:ToggleOption("db.locked")
        ns:Print(ns.db.locked and "Arrow locked." or "Arrow unlocked: drag it to move it.")
    elseif cmd == "minimap" then
        ns:ToggleOption("char.minimap.hide")
        ns:Print(ns.char.minimap.hide and "Minimap button hidden. /way minimap shows it again." or "Minimap button shown.")
    elseif cmd == "help" then
        Help()
    else
        ns:Print(ns.Targets:Describe())
    end
end

ns:Compartment(function() ns:ToggleOption("db.arrowHidden") end)
