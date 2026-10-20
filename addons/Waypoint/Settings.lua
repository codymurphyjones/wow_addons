local _, ns = ...

-- Options > AddOns > Waypoint, built with Blizzard's Settings API: the arrow, what it follows,
-- the world map, and how routes are planned (Route.lua, Grid.lua). /way options opens it.
local S = {}
ns.Settings = S

local function Thousands(n)
    n = math.floor(n + 0.5)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

function S:Register()
    if self.category or not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
    local category, layout = Settings.RegisterVerticalLayoutCategory("Waypoint " .. ns.IconMarkup(16))
    local CreateCheckbox = Settings.CreateCheckbox or Settings.CreateCheckBox

    local function Header(text)
        if layout and layout.AddInitializer and CreateSettingsListSectionHeaderInitializer then
            layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
        end
    end
    -- A checkbox for a setting: get/set default to ns.db[key] (invert: the setting is the opposite).
    local function Checkbox(key, label, tooltip, get, set)
        if not CreateCheckbox then return end
        get = get or function() return ns.db[key] and true or false end
        set = set or function(value) ns.db[key] = value and true or false end
        local setting = Settings.RegisterProxySetting(category, "Waypoint_" .. key, Settings.VarType.Boolean, label,
            get(), get, function(value)
                set(value)
                ns:Changed()
            end)
        CreateCheckbox(category, setting, tooltip)
    end
    local function Slider(key, label, min, max, step, format, tooltip)
        if not (Settings.CreateSlider and Settings.CreateSliderOptions and Settings.VarType.Number) then return end
        local setting = Settings.RegisterProxySetting(category, "Waypoint_" .. key, Settings.VarType.Number, label,
            ns.DEFAULTS[key], function() return ns.db[key] or ns.DEFAULTS[key] end, function(value)
                ns.db[key] = value
                ns:Changed()
            end)
        local options = Settings.CreateSliderOptions(min, max, step)
        if MinimalSliderWithSteppersMixin then
            options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, format)
        end
        Settings.CreateSlider(category, setting, options, tooltip)
    end

    Header(ns.IconMarkup(28) .. "  Waypoint: the arrow")
    Checkbox("arrowHidden", "Show the arrow", "Show Waypoint's arrow (/way arrow).",
        function() return not ns.db.arrowHidden end, function(v) ns.db.arrowHidden = not v end)
    Checkbox("locked", "Lock the arrow", "The arrow can't be dragged (/way lock).")
    Checkbox("steer", "Lead around lakes and cliffs",
        "When the straight line to where you're headed crosses water you'd rather not swim, a cliff or lava, the arrow points along the way around instead.")
    Checkbox("showHeight", "Terrain under the arrow",
        "A line under the arrow, from Waypoint's land map: a cliff or a slope too steep to climb in front of you (with how far down and what the fall would cost), "
        .. "and how far above or below you the target is (\"Target 60 yd below you\"), once it's 15 yards or more.")
    Checkbox("showWay", "Planned route on the world map",
        "The whole trip as a dashed line on the world map: walking teal, swimming blue, jumps orange, flights pale blue, boats and zeppelins white. "
        .. "If it goes the wrong way, walk the right way once: Waypoint learns any pass its land map missed. RoadLog's narrow passes, roads and blockers count too.")
    Checkbox("showWayMinimap", "Planned route on the minimap", "The part of the trip around you as a trail of dots on the minimap, in the same colours.")
    Checkbox("minimap", "Show the minimap button", "Waypoint's minimap button (/way minimap).",
        function() return not ns.char.minimap.hide end,
        function(v)
            ns.char.minimap.hide = not v
            if ns.MinimapButton then ns.MinimapButton:Refresh() end
        end)
    local CreateDropdown = Settings.CreateDropdown or Settings.CreateDropDown
    if CreateDropdown and Settings.CreateControlTextContainer and Settings.VarType.String then
        local dock = Settings.RegisterProxySetting(category, "Waypoint_DockAlign", Settings.VarType.String,
            "Windows under the arrow", "CENTER",
            function() return ns.db.dockAlign or "CENTER" end,
            function(value) if ns.Arrow then ns.Arrow:SetDockAlign(value) end end)
        CreateDropdown(category, dock, function()
            local c = Settings.CreateControlTextContainer()
            c:Add("LEFT", "Left")
            c:Add("CENTER", "Center")
            c:Add("RIGHT", "Right")
            return c:GetData()
        end, "How windows that sit under the arrow (Field Guide) line up with it.")
    end

    Header("What the arrow follows")
    Checkbox("quests", "Questie quests", "Point at your Questie quests when nothing else asks (/way quests).")
    Checkbox("share", "Share waypoint paths with your group", "Your group sees your waypoint path, and you see theirs (/way share).")
    Checkbox("confirm", "Ask before adding a waypoint", "Ctrl+click on the world map asks first (/way confirm).")

    Header("World map")
    Checkbox("towns", "Town icons", "Town icons on the world map, with what's there (/way towns).")
    Checkbox("transportPins", "Dock icons",
        "Zeppelin, skyship and ship docks on the world map: hover for the ride time, click to go there. On a ride, the dock you left and where it lands show the time left (/way docks).")

    Header("Planning the way there")
    Checkbox("flights", "Flight paths", "Lead to a flight master when flying is quicker (/way flights).")
    Checkbox("autoFly", "Take the planned flight by itself",
        "At a flight master with no menu, take the planned flight right away. Hold Shift as you talk to them to choose yourself (/way autofly).")
    Checkbox("transports", "Boats, zeppelins and skyships", "Plan with the rides from Zeppelin Signs' list of docks.")
    Checkbox("useHearth", "Hearthstone", "Plan with your hearthstone, when it's in your bags (its cooldown counts).")
    Checkbox("useTeleports", "Mage teleports", "Plan with the mage teleports you know, when you have a Rune of Teleportation.")
    Checkbox("useGrid", "Follow the land",
        "Plan walks over Waypoint's land and water map: around lakes, mountains and lava, up the slopes you can climb. Off: straight lines.")
    Checkbox("allowSwim", "Swim when it's quicker", "Swim across water when that beats going around. Off: only swim when there's no other way there.")
    Checkbox("useAquatic", "Aquatic Form", "Count Aquatic Form's speed for swims when you know it.")
    Checkbox("formTips", "Say when to switch to Aquatic Form", "A chat line when you're in the water in your own form.")
    Checkbox("useSafeFall", "Walk on Air, Slow Fall and Levitate",
        "Walk on Air (Skyborne) when it's off cooldown, or Slow Fall or Levitate with a Light Feather in your bags: routes can jump down any cliff (never climb one).")
    Slider("maxFallPct", "Fall damage you'll take", 0, 90, 5, function(value)
        local yards = ns.Grid and ns.Grid.FallHeight(value / 100) or 0
        local hp = ns.Compat.Num(ns.Compat.Call(UnitHealthMax, "player"))
        if value == 0 then return ("0%%: up to %d yd, no damage"):format(yards) end
        return ("%d%%: up to %d yd%s"):format(value, yards, hp and (" (" .. Thousands(hp * value / 100) .. " HP)") or "")
    end, "Without Slow Fall or Levitate, routes jump down drops that cost at most this much of your health. "
        .. "Fall damage is 1.8% of your health per yard fallen, less 24%: no damage up to about 14.6 yards, "
        .. "30% at 30 yards, 60% at 47 yards, and 69 yards kills you from full health. Heights come from the land map "
        .. "(66-yard squares), so a real cliff can be a few yards taller than Waypoint thinks: leave some room.")
    Slider("climb", "Cost of climbing", 0, 3, 0.25, function(value)
        return value == 0 and "Free" or ("1 yd up = %.2g yd"):format(value)
    end, "How much walking uphill counts against a route: each yard up counts as this many yards more on flat ground. "
        .. "Higher keeps you lower down; 0 ignores hills.")
    Slider("minGain", "Time a route must save", 0, 180, 5, function(value) return ("%d s"):format(value) end,
        "On your own continent, a route (flights, boats, hearthstone...) is only used instead of walking when it saves at least this much time...")
    Slider("minShare", "Share of the trip it must save", 0, 50, 5, function(value) return ("%d%%"):format(value) end,
        "...and at least this much of the trip. Lower takes more flights and shortcuts; higher keeps you walking.")
    Checkbox("announce", "Announce routes in chat", "A chat line with the whole trip (\"Fastest way: ...\") when you get a new task, "
        .. "or the ways you'd travel change (a flight, a boat, a hearthstone, jumping with Walk on Air or taking the damage, swimming). "
        .. "Re-planning the same trip as you go stays quiet.")

    Settings.RegisterAddOnCategory(category)
    self.category = category
end

function S:Open()
    if self.category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(self.category:GetID())
    else
        ns:Print("This client has no settings panel: /way help lists the commands.")
    end
end

ns:On("PLAYER_LOGIN", function() S:Register() end)
