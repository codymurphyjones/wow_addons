local _, ns = ...

-- Draggable minimap button: left-click shows or hides the guide, right-click
-- lists the guides.
-- The button itself is the shared MinimapButton.lua (addons/shared); SimplePanel's drawer takes it.
ns.MinimapButton = ns.NewMinimapButton({
    name = "FieldGuideMinimapButton", title = "Field Guide", icon = ns.ICON, angle = 200,
    settings = function() return ns.char and ns.char.minimap end,
    tooltip = function(_, self)
        local E = ns.Engine
        GameTooltip:AddLine(ns.IconMarkup(16) .. " Field Guide", 0.56, 0.82, 0.42)
        if E.section then
            local done, total = E:Progress()
            GameTooltip:AddLine(("%s, levels %d-%d: %d of %d steps"):format(E.section.title, E.section.from, E.section.to, done, total), 1, 1, 1)
        end
        -- Instance priority: every dungeon in your level range whose quests you haven't done.
        local dungeons = ns.Instance:Current()
        if #dungeons > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Dungeon time", 1, 0.82, 0)
            for i, entry in ipairs(dungeons) do
                local inst = entry.inst
                GameTooltip:AddDoubleLine(("%d. %s  (%d-%d)"):format(i, inst.name, inst.from, inst.to),
                    ("%d quest%s left"):format(#entry.open, #entry.open == 1 and "" or "s"),
                    1, 1, 1, ns.char.instance == inst.id and 0.56 or 0.75, 0.82, ns.char.instance == inst.id and 0.42 or 0.8)
                for j, id in ipairs(entry.open) do
                    if j > 4 then
                        GameTooltip:AddLine(("      ...and %d more"):format(#entry.open - 4), 0.6, 0.6, 0.6)
                        break
                    end
                    local q = ns.Quests[id] or {}
                    GameTooltip:AddDoubleLine("      " .. (q.n or ("Quest " .. id)), q.a and ns.Engine:Where(q.a) or "", 0.8, 0.8, 0.8, 0.6, 0.6, 0.6)
                end
            end
            GameTooltip:AddLine("/fg dungeon <number>: guide me there", 0.6, 0.6, 0.6)
            GameTooltip:AddLine(" ")
        end
        if ns.char.paused then GameTooltip:AddLine("Arrow paused: the guide isn't steering Waypoint.", 1, 0.6, 0.3) end
        GameTooltip:AddLine("Left-click: show or hide the guide", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("Shift+click: " .. (ns.char.paused and "resume" or "pause") .. " the arrow", 0.75, 0.8, 0.85)
        if ns.char.instance then GameTooltip:AddLine("Ctrl+click: back to the leveling guide", 0.75, 0.8, 0.85) end
        GameTooltip:AddLine("Right-click: list the guides", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("Drag: move around the minimap", 0.75, 0.8, 0.85)
    end,
    click = function(self, mouseButton)
        if mouseButton == "RightButton" then
            ns.Engine:PrintList()
        elseif IsShiftKeyDown() then
            ns.Engine:SetPaused()
        elseif IsControlKeyDown() and ns.char.instance then
            ns.Instance:Stop()
        else
            ns.db.shown = not ns.db.shown
            ns:Changed()
        end
    end,
})
