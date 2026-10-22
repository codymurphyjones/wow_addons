local _, ns = ...

-- A minimap button: left click opens the journal, right click your gear
-- list on the Character window. Drag it around the minimap's edge.
-- The button itself is the shared MinimapButton.lua (addons/shared); SimplePanel's drawer takes it.
-- Journal.lua calls Init once its saved settings are loaded.
local M = {}
ns.Minimap = M

-- SpyGlass's logo (Spyglass\Media).
local ICON = "Interface\\AddOns\\Spyglass\\Media\\Icon"

local button = ns.NewMinimapButton({
    name = "SpyGlassJournalMinimapButton", title = "SpyGlass", icon = ICON, angle = 200, manual = true,
    settings = function() return ns.J and ns.J.db and ns.J.db.minimap end,
    tooltip = function()
        GameTooltip:AddLine("SpyGlass")
        GameTooltip:AddLine("Left-click: open the journal", 1, 1, 1)
        GameTooltip:AddLine("Right-click: your gear list on the Character window", 1, 1, 1)
        GameTooltip:AddLine("Drag: move around the minimap", 0.7, 0.7, 0.7)
    end,
    click = function(_, mouse)
        if mouse == "RightButton" then
            SlashCmdList.SPYGLASS("")
        else
            SpyGlassJournal:Toggle()
        end
    end,
})

function M:Init()
    button:Initialize()
    C_Timer.After(2, function() button:AvoidOthers() end)
    C_Timer.After(8, function() button:AvoidOthers() end)
end

function M:Update()
    button:Refresh()
end
