local _, ns = ...
local PAL = ns.Palette

-- Draggable minimap button: left-click opens SmartPlates, right-click toggles the preview.
-- The button itself is the shared MinimapButton.lua (addons/shared); SimplePanel's drawer takes it.
ns.MinimapButton = ns.NewMinimapButton({
    name = "SmartPlatesMinimapButton", title = "SmartPlates", icon = ns.ICON, angle = 220,
    settings = function() return ns.char and ns.char.minimap end,
    tooltip = function(_, self)
        GameTooltip:AddLine("SmartPlates", PAL.accent[1], PAL.accent[2], PAL.accent[3])
        GameTooltip:AddLine("Role: " .. (ns.Role:Get() == "tank" and "Tank" or "DPS / Healer"), 0.82, 0.89, 0.93)
        GameTooltip:AddLine("Left-click: settings", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("Right-click: preview plates", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("Drag: move around the minimap", 0.75, 0.8, 0.85)
    end,
    click = function(self, mouseButton)
        if mouseButton == "RightButton" then ns.TestMode:Toggle()
        else ns.UI:Toggle() end
    end,
})
