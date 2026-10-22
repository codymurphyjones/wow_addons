local _, ns = ...
local PAL = ns.Palette

-- Draggable minimap button: left-click opens Wally, right-click opens In Bags.
-- The button itself is the shared MinimapButton.lua (addons/shared); SimplePanel's drawer takes it.
ns.MinimapButton = ns.NewMinimapButton({
    name = "WallyMinimapButton", title = "Wally", icon = ns.ICON, angle = 200,
    settings = function() return ns.char and ns.char.minimap end,
    tooltip = function(_, self)
        local count, total = ns.JunkFilter:Report()
        GameTooltip:AddLine("Wally", PAL.accent[1], PAL.accent[2], PAL.accent[3])
        GameTooltip:AddLine(("%d junk item%s in bags (%s)"):format(count, count == 1 and "" or "s", ns.Compat.Money(total)), 0.82, 0.89, 0.93)
        GameTooltip:AddLine("Left-click: open Wally", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("Right-click: what's in your bags", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("Shift-right-click: sort your bags", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("Drag: move around the minimap", 0.75, 0.8, 0.85)
    end,
    click = function(self, mouseButton)
        if mouseButton == "RightButton" and IsShiftKeyDown() then ns.Sorter:Start("bags")
        elseif mouseButton == "RightButton" then ns.UI:Show("bags")
        else ns.UI:Toggle() end
    end,
})
