local _, ns = ...
local PAL = ns.Palette

-- Draggable minimap button: left-click opens Tape Measure, right-click opens Upgrades.
-- The button itself is the shared MinimapButton.lua (addons/shared); SimplePanel's drawer takes it.
ns.MinimapButton = ns.NewMinimapButton({
    name = "TapeMeasureMinimapButton", title = "Tape Measure", icon = ns.ICON, angle = 200,
    settings = function() return ns.char and ns.char.minimap end,
    tooltip = function(_, self)
        local count = #ns.Scoring:ScanBags()
        GameTooltip:AddLine(ns.IconMarkup(16) .. " Tape Measure", PAL.accent[1], PAL.accent[2], PAL.accent[3])
        GameTooltip:AddLine(ns:ColoredSpecText(), 1, 1, 1)
        GameTooltip:AddLine(("%d upgrade%s in your bags"):format(count, count == 1 and "" or "s"), 0.82, 0.89, 0.93)
        GameTooltip:AddLine("Left-click: open Tape Measure", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("Right-click: upgrades in your bags", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("Shift-right-click: edit stat priority", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("Drag: move around the minimap", 0.75, 0.8, 0.85)
    end,
    click = function(self, mouseButton)
        if mouseButton == "RightButton" and IsShiftKeyDown() then ns:OpenStatLedger()
        elseif mouseButton == "RightButton" then ns.UI:Show("upgrades")
        else ns.UI:Toggle() end
    end,
})
