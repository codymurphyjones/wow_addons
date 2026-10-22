local _, ns = ...

-- Options > AddOns > Waypoint: the arrow, what it follows, the world map, and how routes are
-- planned (Route.lua, Grid.lua). Built with the shared OptionsPage.lua (addons/shared): the arrow's
-- menu, the minimap button and /way change the same options, so every UI shows the same value.
-- /way options opens it.
local S = {}
ns.Settings = S

local function Thousands(n) return ns.Format.Thousands(n) end

local function RoadModes()
    local out = {}
    for _, mode in ipairs(ns.Route.ROAD_MODES) do out[#out + 1] = { mode.id, mode.name } end
    return out
end

S.page = ns.NewOptionsPage({ name = "Waypoint", icon = true, build = function(p)
    p:Header(ns.IconMarkup(28) .. "  Waypoint: the arrow")
    p:Check({ path = "db.arrowHidden", invert = true, label = "Show the arrow", tooltip = "Show Waypoint's arrow (/way arrow)." })
    p:Check({ path = "db.locked", label = "Lock the arrow", tooltip = "The arrow can't be dragged (/way lock)." })
    p:Check({ path = "db.steer", label = "Lead around lakes and cliffs",
        tooltip = "When the straight line to where you're headed crosses water you'd rather not swim, a cliff or lava, the arrow points along the way around instead." })
    p:Check({ path = "db.showHeight", label = "Terrain under the arrow",
        tooltip = "A line under the arrow, from Waypoint's land map: a cliff or a slope too steep to climb in front of you (with how far down and what the fall would cost), "
            .. "and how far above or below you the target is (\"Target 60 yd below you\"), once it's 15 yards or more." })
    p:Check({ path = "db.showWay", label = "Planned route on the world map",
        tooltip = "The whole trip as a dashed line on the world map: walking teal, swimming blue, jumps orange, flights pale blue, boats and zeppelins white. "
            .. "If it goes the wrong way, walk the right way once: Waypoint learns any pass its land map missed. RoadLog's narrow passes, roads and blockers count too." })
    p:Check({ path = "db.showWayMinimap", label = "Planned route on the minimap", tooltip = "The part of the trip around you as a trail of dots on the minimap, in the same colours." })
    p:Check({ path = "char.minimap.hide", invert = true, label = "Show the minimap button", tooltip = "Waypoint's minimap button (/way minimap).",
        apply = function() if ns.MinimapButton then ns.MinimapButton:Refresh() end end })
    p:Dropdown({ path = "db.dockAlign", label = "Windows under the arrow", default = "CENTER",
        choices = { { "LEFT", "Left" }, { "CENTER", "Center" }, { "RIGHT", "Right" } },
        tooltip = "How windows that sit under the arrow (Field Guide) line up with it (also on the arrow's right-click menu).",
        apply = function() if ns.Arrow then ns.Arrow:PlaceDocked() end end })

    p:Header("What the arrow follows")
    p:Check({ path = "db.quests", label = "Questie quests", tooltip = "Point at your Questie quests when nothing else asks (/way quests).",
        apply = function() if ns.Questie then ns.Questie:Select() end end })
    p:Check({ path = "db.share", label = "Share waypoint paths with your group", tooltip = "Your group sees your waypoint path, and you see theirs (/way share)." })
    p:Check({ path = "db.confirm", label = "Ask before adding a waypoint", tooltip = "Ctrl+clicking the world map asks first (/way confirm)." })

    p:Header("World map")
    p:Check({ path = "db.towns", label = "Town icons", tooltip = "Town icons on the world map, with what's there (/way towns, or the arrow's menu)." })
    p:Check({ path = "db.transportPins", label = "Dock icons",
        tooltip = "Zeppelin, skyship and ship docks on the world map: hover for the ride time, click to go there. On a ride, the dock you left and where it lands show the time left (/way docks)." })

    p:Header("Planning the way there")
    p:Dropdown({ path = "db.roadMode", label = "Roads", default = "balanced", choices = RoadModes,
        tooltip = "Safe keeps to roads, Balanced takes the roads that lead your way, Speed takes the quickest way, roads or not (also the box on the arrow).",
        apply = function() if ns.Flight then ns.Flight.route = nil end end })
    p:Check({ path = "db.flights", label = "Flight paths", tooltip = "Lead to a flight master when flying is quicker (/way flights)." })
    p:Check({ path = "db.autoFly", label = "Take the planned flight by itself",
        tooltip = "At a flight master with no menu, take the planned flight right away. Hold Shift as you talk to them to choose yourself (/way autofly)." })
    p:Check({ path = "db.transports", label = "Boats, zeppelins and skyships", tooltip = "Plan with the rides from Zeppelin Signs' list of docks." })
    p:Check({ path = "db.useHearth", label = "Hearthstone", tooltip = "Plan with your hearthstone, when it's in your bags (its cooldown counts)." })
    p:Check({ path = "db.useTeleports", label = "Mage teleports", tooltip = "Plan with the mage teleports you know, when you have a Rune of Teleportation." })
    p:Check({ path = "db.useGrid", label = "Follow the land",
        tooltip = "Plan walks over Waypoint's land and water map: around lakes, mountains and lava, up the slopes you can climb. Off: straight lines." })
    p:Check({ path = "db.allowSwim", label = "Swim when it's quicker", tooltip = "Swim across water when that beats going around. Off: only swim when there's no other way there." })
    p:Check({ path = "db.useAquatic", label = "Aquatic Form", tooltip = "Count Aquatic Form's speed for swims when you know it." })
    p:Check({ path = "db.formTips", label = "Say when to switch to Aquatic Form", tooltip = "A chat line when you're in the water in your own form." })
    p:Check({ path = "db.useSafeFall", label = "Walk on Air, Slow Fall and Levitate",
        tooltip = "Walk on Air (Skyborne) when it's off cooldown, or Slow Fall or Levitate with a Light Feather in your bags: routes can jump down any cliff (never climb one)." })
    p:Slider({ path = "db.maxFallPct", label = "Fall damage you'll take", min = 0, max = 90, step = 5, format = function(value)
        local yards = ns.Grid and ns.Grid.FallHeight(value / 100) or 0
        local hp = ns.Compat.Num(ns.Compat.Call(UnitHealthMax, "player"))
        if value == 0 then return ("0%%: up to %d yd, no damage"):format(yards) end
        return ("%d%%: up to %d yd%s"):format(value, yards, hp and (" (" .. Thousands(hp * value / 100) .. " HP)") or "")
    end, tooltip = "Without Slow Fall or Levitate, routes jump down drops that cost at most this much of your health. "
        .. "Fall damage is 1.8% of your health per yard fallen, less 24%: no damage up to about 14.6 yards, "
        .. "30% at 30 yards, 60% at 47 yards, and 69 yards kills you from full health. Heights come from the land map "
        .. "(66-yard squares), so a real cliff can be a few yards taller than Waypoint thinks: leave some room." })
    p:Slider({ path = "db.climb", label = "Cost of climbing", min = 0, max = 3, step = 0.25, format = function(value)
        return value == 0 and "Free" or ("1 yd up = %.2g yd"):format(value)
    end, tooltip = "How much walking uphill counts against a route: each yard up counts as this many yards more on flat ground. "
        .. "Higher keeps you lower down; 0 ignores hills." })
    p:Slider({ path = "db.minGain", label = "Time a route must save", min = 0, max = 180, step = 5, format = function(value) return ("%d s"):format(value) end,
        tooltip = "On your own continent, a route (flights, boats, hearthstone...) is only used instead of walking when it saves at least this much time..." })
    p:Slider({ path = "db.minShare", label = "Share of the trip it must save", min = 0, max = 50, step = 5, format = function(value) return ("%d%%"):format(value) end,
        tooltip = "...and at least this much of the trip. Lower takes more flights and shortcuts; higher keeps you walking." })
    p:Check({ path = "db.announce", label = "Announce routes in chat", tooltip = "A chat line with the whole trip (\"Fastest way: ...\") when you get a new task, "
        .. "or the ways you'd travel change (a flight, a boat, a hearthstone, jumping with Walk on Air or taking the damage, swimming). "
        .. "Re-planning the same trip as you go stays quiet." })
end })

function S:Open() return self.page:Open() end
