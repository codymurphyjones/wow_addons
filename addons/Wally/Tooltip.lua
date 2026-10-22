local _, ns = ...
local C = ns.Compat

-- Adds a Wally line to item tooltips.
local COLOR = {
    junk = { 1, 0.45, 0.35 },
    keep = { 0.35, 0.95, 0.55 },
    upgrade = { 0.4, 0.8, 1 },
    learn = { 0.85, 0.75, 0.4 },
}

-- Returns false (try again on the next update) while the saved data isn't loaded or the line is off.
local function AddLines(tooltip, link)
    if not ns.db or not ns.db.options.tooltip then return false end
    -- The tooltip doesn't say which bag slot it shows, so read "Soulbound" off its own lines.
    local bound = ns.Tooltip.Soulbound(tooltip)
    local isJunk, reason, verdict = ns.JunkFilter:Evaluate(link, { bound = bound })
    if isJunk then
        local c = COLOR.junk
        tooltip:AddLine("Wally: Junk - " .. reason, c[1], c[2], c[3])
    elseif reason and (verdict == "keep" or verdict == "upgrade") then
        local c = COLOR[verdict]
        tooltip:AddLine("Wally: " .. reason, c[1], c[2], c[3])
    end
    -- Reagents get their worth; protected items already show it in the line above.
    if verdict ~= "keep" and ns.Value:IsReagent(link) then
        local worth, source = ns.Value:UnitWorth(link)
        if worth and worth > 0 then
            tooltip:AddLine(("Wally: worth ~%s each (%s)"):format(C.Money(worth), source == "auction" and "auction price" or "estimate"),
                0.6, 0.75, 0.8)
        end
    end
    local key = ns.Key(C.NameFromLink(link))
    local h = key and ns.db.habits[key]
    if h and not isJunk and verdict ~= "keep" and (h.score or 0) > 0 then
        local c = COLOR.learn
        tooltip:AddLine(("Wally: learning %d%% (sold %d, bought back %d)"):format(math.floor((h.score or 0) * 100), h.sold or 0, h.boughtBack or 0), c[1], c[2], c[3])
    end
    local ah = key and ns.db.auctionHabits[key]
    if ah and (ah.score or 0) > 0 and not ns.db.auctionList[key] and not ns.db.neverAuction[key] then
        local c = COLOR.learn
        tooltip:AddLine(("Wally: auction learning %d%% (posted %d)"):format(math.floor((ah.score or 0) * 100), ah.posted or 0), c[1], c[2], c[3])
    end
    tooltip:Show()
end

ns.Tooltip.HookItem(AddLines)
