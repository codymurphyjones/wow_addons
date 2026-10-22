local _, ns = ...
local PAL = ns.Palette

-- Draggable minimap button: left-click opens Quartermaster, right-click opens Lists.
-- The button itself is the shared MinimapButton.lua (addons/shared); SimplePanel's drawer takes it.
ns.MinimapButton = ns.NewMinimapButton({
    name = "QuartermasterMinimapButton", title = "Quartermaster", icon = ns.ICON, angle = 220,
    settings = function() return ns.char and ns.char.minimap end,
    tooltip = function(_, self)
        local list = ns.Lists:Active()
        local total = ns.Lists:Estimate(list)
        GameTooltip:AddLine("Quartermaster", PAL.accent[1], PAL.accent[2], PAL.accent[3])
        GameTooltip:AddLine(("%s: %d item%s, about %s to go"):format(list.name, #list.entries,
            #list.entries == 1 and "" or "s", ns.Compat.Money(total)), 0.82, 0.89, 0.93)
        GameTooltip:AddLine("Left-click: browse items", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("Right-click: your lists", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("Drag: move around the minimap", 0.75, 0.8, 0.85)
    end,
    click = function(self, mouseButton)
        if mouseButton == "RightButton" then ns.UI:Show("lists")
        else ns.UI:Toggle() end
    end,
})
