local _, ns = ...

-- Options > AddOns > RoadLog, built with Blizzard's Settings API: what the world map shows, how
-- roads are drawn, and the minimap button.
local S = {}
ns.Settings = S

-- A checkbox for ns.db[key]; flip (optional) runs after it changes.
local function Checkbox(category, key, label, tooltip, flip)
    local CreateCheckbox = Settings.CreateCheckbox or Settings.CreateCheckBox
    if not CreateCheckbox then return end
    local setting = Settings.RegisterProxySetting(category, "RoadLog_" .. key, Settings.VarType.Boolean, label,
        ns.DEFAULTS[key] and true or false,
        function() return ns.db[key] and true or false end,
        function(value)
            ns.db[key] = value and true or false
            if flip then flip(value) end
            ns:Changed()
        end)
    CreateCheckbox(category, setting, tooltip)
end

function S:Register()
    if self.category or not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
    local category, layout = Settings.RegisterVerticalLayoutCategory("RoadLog " .. ns.IconMarkup(16))
    local function Header(text)
        if layout and layout.AddInitializer and CreateSettingsListSectionHeaderInitializer then
            layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
        end
    end
    Header(ns.IconMarkup(28) .. "  RoadLog: on the world map")
    Checkbox(category, "showMap", "Show roads",
        "Draw the roads you've recorded on the world map (/roadlog map). Off by default: Waypoint uses your roads either way.")
    Checkbox(category, "showBlockers", "Show blockers",
        "Draw blockers (walls, fences and cliff edges you walked along) as red lines on the world map.")
    Checkbox(category, "showPasses", "Show narrow passes",
        "Mark the narrow passes you logged (spots you can get through) with blue spots on the world map. Shift+right-click one to remove it.")
    Checkbox(category, "showTransitions", "Show zone transitions",
        "Mark the zone transitions you logged with purple spots on the world map; hover one for its name. Shift+right-click one to remove it.")
    Checkbox(category, "showCaves", "Show caves",
        "Draw the caves you logged on the world map, shaded from deep blue (lowest) to pale (highest) once the build has worked out their heights.")
    Header("How roads are drawn")
    Checkbox(category, "smooth", "Clean up roads",
        "Draw roads with the weaving taken out, repeated passes merged and loops faint. What's recorded stays as it is (/roadlog smooth).")
    Header("Minimap")
    local CreateCheckbox = Settings.CreateCheckbox or Settings.CreateCheckBox
    if CreateCheckbox then
        local setting = Settings.RegisterProxySetting(category, "RoadLog_Minimap", Settings.VarType.Boolean,
            "Show the minimap button", true,
            function() return not ns.db.minimap.hide end,
            function(value)
                ns.db.minimap.hide = not value
                ns.MinimapButton:Refresh()
            end)
        CreateCheckbox(category, setting,
            "Left-click turns recording on or off; right-click picks roads or blockers and marks narrow passes and zone transitions (/roadlog minimap).")
    end
    Settings.RegisterAddOnCategory(category)
    self.category = category
end

function S:Open()
    if self.category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(self.category:GetID())
    else
        ns:Print("/roadlog map, /roadlog smooth and /roadlog minimap switch these on this client.")
    end
end

ns:On("PLAYER_LOGIN", function() S:Register() end)
