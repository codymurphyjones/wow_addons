local _, ns = ...

-- Options > AddOns > RoadLog, built with the shared OptionsPage.lua (addons/shared): recording,
-- what the world map shows, how roads are drawn, and the minimap button. /roadlog, the minimap
-- button and its menu change the same options, so the page always shows the current value.
local S = {}
ns.Settings = S

local MODES = {
    { "road", "Roads" },
    { "blocker", "Blockers (walls, fences, cliff edges)" },
    { "cave", "Caves (paths and heights through caves)" },
}

S.page = ns.NewOptionsPage({ name = "RoadLog", icon = true, build = function(p)
    p:Header(ns.IconMarkup(28) .. "  RoadLog: recording")
    -- ns:SetEnabled and Recorder:SetMode keep their own side effects (start or finish a stretch,
    -- the chat line) and tell the page themselves (ns:OptionChanged).
    p:Check({ id = "Enabled", path = "db.enabled", label = "Record",
        set = function(value) ns:SetEnabled(value) end,
        tooltip = "While on, every step you walk is logged as the mode below (/roadlog on, /roadlog off, or left-click the minimap button)." })
    p:Dropdown({ id = "Mode", path = "db.mode", label = "Log", choices = MODES,
        set = function(value) ns.Recorder:SetMode(value) end,
        tooltip = "What you're logging: roads (walk the middle of the road), blockers (walk along the wall, fence or cliff edge) "
            .. "or caves (walk every passage; heights are worked out by the next build). /roadlog road, blocker or cave, or the minimap button's right-click menu." })

    p:Header("On the world map")
    p:Check({ id = "showMap", path = "db.showMap", label = "Show roads",
        tooltip = "Draw the roads you've recorded on the world map (/roadlog map). Off by default: Waypoint uses your roads either way." })
    p:Check({ id = "showBlockers", path = "db.showBlockers", label = "Show blockers",
        tooltip = "Draw blockers (walls, fences and cliff edges you walked along) as red lines on the world map." })
    p:Check({ id = "showPasses", path = "db.showPasses", label = "Show narrow passes",
        tooltip = "Mark the narrow passes you logged (spots you can get through) with blue spots on the world map. Shift+right-click one to remove it." })
    p:Check({ id = "showTransitions", path = "db.showTransitions", label = "Show zone transitions",
        tooltip = "Mark the zone transitions you logged with purple spots on the world map; hover one for its name. Shift+right-click one to remove it." })
    p:Check({ id = "showCaves", path = "db.showCaves", label = "Show caves",
        tooltip = "Draw the caves you logged on the world map, shaded from deep blue (lowest) to pale (highest) once the build has worked out their heights." })

    p:Header("How roads are drawn")
    p:Check({ id = "smooth", path = "db.smooth", label = "Clean up roads",
        tooltip = "Draw roads with the weaving taken out, repeated passes merged and loops faint. What's recorded stays as it is (/roadlog smooth)." })

    p:Header("Minimap")
    p:Check({ id = "Minimap", path = "db.minimap.hide", invert = true, label = "Show the minimap button",
        tooltip = "Left-click turns recording on or off; right-click picks roads or blockers and marks narrow passes and zone transitions (/roadlog minimap).",
        apply = function() if ns.MinimapButton then ns.MinimapButton:Refresh() end end })
end })

function S:Open()
    if not self.page.headless then return self.page:Open() end
    ns:Print("/roadlog map, /roadlog smooth and /roadlog minimap switch these on this client.")
end
