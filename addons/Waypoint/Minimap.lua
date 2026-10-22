local _, ns = ...

-- Draggable minimap button: left-click shows or hides the arrow, right-click
-- opens the Navigate to menu (Navigate.lua: trainers, services, vendors...; without MenuUtil it
-- says what it points at).
-- The button itself is the shared MinimapButton.lua (addons/shared); SimplePanel's drawer takes it.
ns.MinimapButton = ns.NewMinimapButton({
    name = "WaypointMinimapButton", title = "Waypoint", icon = ns.ICON, angle = 200,
    settings = function() return ns.char and ns.char.minimap end,
    tooltip = function(_, self)
        GameTooltip:AddLine(ns.IconMarkup(16) .. " Waypoint", 1, 0.79, 0.3)
        GameTooltip:AddLine(ns.Targets:Describe(), 1, 1, 1, true)
        if ns.Chain:Count() > 0 then
            GameTooltip:AddLine(("Waypoint path: %d waypoint%s"):format(ns.Chain:Count(), ns.Chain:Count() == 1 and "" or "s"), 0.82, 0.89, 0.93)
        end
        GameTooltip:AddLine("Left-click: show or hide the arrow", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("Right-click: Navigate to a trainer, vendor, bank, mailbox...", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("World map: double-click adds a waypoint, Ctrl+right-click removes one", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("Drag: move around the minimap", 0.75, 0.8, 0.85)
    end,
    click = function(self, mouseButton)
        if mouseButton == "RightButton" then
            GameTooltip:Hide()
            ns.Navigate:ShowMenu(self)
        else
            ns:ToggleOption("db.arrowHidden")
        end
    end,
})
