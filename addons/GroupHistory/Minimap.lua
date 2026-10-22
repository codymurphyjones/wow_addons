local _, ns = ...
local PAL = ns.Palette

-- Draggable minimap button: left-click opens Group History, right-click the party popup.
-- The button itself is the shared MinimapButton.lua (addons/shared); SimplePanel's drawer takes it.
ns.MinimapButton = ns.NewMinimapButton({
    name = "GroupHistoryMinimapButton", title = "Group History", icon = ns.ICON, angle = 200,
    settings = function() return ns.char and ns.char.minimap end,
    tooltip = function(_, self)
        GameTooltip:AddLine("Group History", PAL.accent[1], PAL.accent[2], PAL.accent[3])
        local players = 0
        for _ in pairs(ns.db.players) do players = players + 1 end
        GameTooltip:AddLine(("%d players, %d runs recorded"):format(players, #ns.db.runs), 0.82, 0.89, 0.93)
        local run = ns.Run.current
        if run then GameTooltip:AddLine(("In a run: %s, %d deaths so far"):format(run.instance, #run.deaths), 0.82, 0.89, 0.93) end
        GameTooltip:AddLine("Left-click: open Group History", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("Right-click: your party's history", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("Drag: move around the minimap", 0.75, 0.8, 0.85)
    end,
    click = function(self, mouseButton)
        if mouseButton == "RightButton" then ns.Popup:ShowParty(true) else ns.UI:Toggle() end
    end,
})
