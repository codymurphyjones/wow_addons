local _, ns = ...
local PAL = ns.Palette

-- Draggable minimap button: left-click opens the dojo, right-click the last lesson.
-- The button itself is the shared MinimapButton.lua (addons/shared); SimplePanel's drawer takes it.
ns.MinimapButton = ns.NewMinimapButton({
    name = "MrMiyagiMinimapButton", title = "Mr. Miyagi", icon = ns.ICON, angle = 200,
    settings = function() return ns.char and ns.char.minimap end,
    tooltip = function(_, self)
        GameTooltip:AddLine("Mr. Miyagi", PAL.accent[1], PAL.accent[2], PAL.accent[3])
        GameTooltip:AddLine(("%d lessons, %d fights recorded"):format(#ns.db.deaths, #ns.db.fights), 0.82, 0.89, 0.93)
        GameTooltip:AddLine("Left-click: open the dojo", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("Right-click: the last lesson", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("Drag: move around the minimap", 0.75, 0.8, 0.85)
    end,
    click = function(self, mouseButton)
        if mouseButton == "RightButton" then
            local d = ns.db.deaths[#ns.db.deaths]
            if d then ns.Coach:Show(d) end
        else
            ns.UI:Toggle()
        end
    end,
})
