local _, ns = ...
local C = ns.Compat

-- Adds a Wally line to item tooltips.
local COLOR = {
    junk = { 1, 0.45, 0.35 },
    keep = { 0.35, 0.95, 0.55 },
    upgrade = { 0.4, 0.8, 1 },
    learn = { 0.85, 0.75, 0.4 },
}

local function AddLines(tooltip)
    if not ns.db or not ns.db.options.tooltip or tooltip.wallyDone then return end
    local _, link = tooltip:GetItem()
    if not link then return end
    tooltip.wallyDone = true
    -- The tooltip doesn't say which bag slot it shows, so read "Soulbound" off its own lines.
    local bound = false
    local prefix = tooltip:GetName()
    for i = 2, math.min(6, tooltip:NumLines()) do
        local fs = prefix and _G[prefix .. "TextLeft" .. i]
        if fs and fs:GetText() == ITEM_SOULBOUND then bound = true; break end
    end
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

local function Clear(tooltip) tooltip.wallyDone = nil end

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
        if tooltip == GameTooltip or tooltip == ItemRefTooltip then AddLines(tooltip) end
    end)
else
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
        tt:HookScript("OnTooltipSetItem", AddLines)
    end
end
for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
    tt:HookScript("OnHide", Clear)
    if tt:HasScript("OnTooltipCleared") then tt:HookScript("OnTooltipCleared", Clear) end
end
