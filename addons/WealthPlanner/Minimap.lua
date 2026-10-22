local _, ns = ...
local PAL = ns.Palette

-- Draggable minimap button for the Jobs Board: left-click opens the board,
-- right-click your wealth overview.
-- The button itself is the shared MinimapButton.lua (addons/shared); SimplePanel's drawer takes it.
ns.MinimapButton = ns.NewMinimapButton({
    name = "WealthPlannerMinimapButton", title = "Wealth Planner", icon = ns.JOBS_ICON, angle = 200,
    settings = function() return ns.char and ns.char.minimap end,
    tooltip = function(_, self)
        GameTooltip:AddLine("Wealth Planner: Jobs Board", PAL.accent[1], PAL.accent[2], PAL.accent[3])
        local active, best = ns.Jobs:Active(), ns.Jobs:Board()[1]
        if active then
            GameTooltip:AddLine(("On the job: %s"):format(active.title), 0.82, 0.89, 0.93)
            local rate = ns.Session:PerHour()
            if rate then GameTooltip:AddLine(("Earning %s an hour"):format(ns.Compat.Money(rate)), 0.35, 0.95, 0.55) end
        elseif best then
            GameTooltip:AddLine(("Best job: %s (%s/hr)"):format(best.title, ns.Gold(best.pay)), 0.82, 0.89, 0.93)
        end
        GameTooltip:AddLine("Left-click: open the Jobs Board", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("Right-click: your wealth overview", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("Drag: move around the minimap", 0.75, 0.8, 0.85)
    end,
    click = function(self, mouseButton)
        if mouseButton == "RightButton" then ns.UI:Show("overview")
        elseif ns.UI:IsShown() and ns.UI:Active() == "jobs" then WallyAPI.Toggle()
        else ns.UI:Show("jobs") end
    end,
})
