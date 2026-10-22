local _, ns = ...
local PAL = ns.Palette

-- Draggable minimap button: left-click opens Fireside (the campfire), right-click your party's history in chat.
-- The button itself is the shared MinimapButton.lua (addons/shared); SimplePanel's drawer takes it.
ns.MinimapButton = ns.NewMinimapButton({
    name = "FiresideMinimapButton", title = "Fireside", icon = ns.ICON, angle = 200,
    settings = function() return ns.char and ns.char.minimap end,
    tooltip = function(_, self)
        GameTooltip:AddLine("Fireside", PAL.accent[1], PAL.accent[2], PAL.accent[3])
        local players = 0
        for _ in pairs(ns.db.players) do players = players + 1 end
        GameTooltip:AddLine(("%d players, %d runs recorded"):format(players, #ns.db.runs), 0.82, 0.89, 0.93)
        local run = ns.Run.current
        if run then GameTooltip:AddLine(("In a run: %s, %d deaths so far"):format(run.instance, #run.deaths), 0.82, 0.89, 0.93) end
        local unread = ns.Feedback.Unread()
        if unread > 0 then GameTooltip:AddLine(("%d new private note%s for you"):format(unread, unread == 1 and "" or "s"), 1, 0.82, 0.3) end
        GameTooltip:AddLine("Left-click: the campfire", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("Right-click: your party's history", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("Drag: move around the minimap", 0.75, 0.8, 0.85)
    end,
    click = function(self, mouseButton)
        if mouseButton == "RightButton" then ns.Popup:ShowParty(true) else ns.UI:Toggle() end
    end,
})
