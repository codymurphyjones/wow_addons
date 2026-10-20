local _, ns = ...

-- Scrolling lists and item row behaviour for the Character window panel.
local W = {}
ns.Widgets = W

function W.MakeList(parent, extent, initializer)
    local box = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
    local bar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 6, 0)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 6, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(extent)
    view:SetElementInitializer("Button", initializer)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
    return box
end

-- Shows list in box; keeps the scroll position unless toTop.
function W.SetList(box, list, toTop)
    box:SetDataProvider(CreateDataProvider(list),
        (not toTop) and ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition or nil)
end

-- r, g, b for an item quality (grey, white, green, blue, purple, orange...).
local QUALITY_FALLBACK = {
    [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 },
    [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 }, [6] = { 0.9, 0.8, 0.5 }, [7] = { 0, 0.8, 1 },
}
function W.QualityColor(quality)
    quality = quality or 1
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color and color.r then return color.r, color.g, color.b end
    local get = (C_Item and C_Item.GetItemQualityColor) or GetItemQualityColor
    if get then
        local ok, r, g, b = pcall(get, quality)
        if ok and r then return r, g, b end
    end
    local c = QUALITY_FALLBACK[quality] or QUALITY_FALLBACK[1]
    return c[1], c[2], c[3]
end

function W.ItemTooltip(row)
    local data = row.data
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(data.itemID)
    -- The game can't say (an encrypted item, or one it never sent): what the
    -- shipped data knows instead.
    local info, shipped = ns:Peek(data.itemID), ns:Shipped(data.itemID)
    if shipped and info and info.baked then
        if GameTooltip:NumLines() == 0 or ns:IsEncrypted(data.itemID) then
            GameTooltip:ClearLines()
            GameTooltip:AddLine(shipped.name or ("Item " .. data.itemID), W.QualityColor(shipped.q))
            if shipped.subType then GameTooltip:AddLine(shipped.subType, 1, 1, 1) end
            for stat, amount in pairs(shipped.stats or {}) do
                GameTooltip:AddLine("+" .. amount .. " " .. ns.Scoring:Label(stat), 1, 1, 1)
            end
            if shipped.classes then GameTooltip:AddLine("Classes: " .. shipped.classes, 1, 1, 1) end
            for _, effect in ipairs(shipped.effects or {}) do GameTooltip:AddLine(effect, 0.12, 1, 0, true) end
        end
        if shipped.src == "wh" then GameTooltip:AddLine("Details from Wowhead", 0.6, 0.6, 0.6) end
    end
    GameTooltip:AddLine(" ")
    if data.failed then
        GameTooltip:AddLine("The server didn't send this item's details.", 1, 0.4, 0.4, true)
        GameTooltip:AddLine("Click: try again", 0.4, 0.73, 1)
    elseif data.placeholder then
        GameTooltip:AddLine("Loading this item's details; its score shows once they arrive.", 0.7, 0.7, 0.7, true)
    else
        GameTooltip:AddDoubleLine("SpyGlass score", string.format("%.1f", data.score), 0.4, 0.73, 1, 1, 1, 1)
        local _, notes = ns.Effects:Stats(data.itemID)
        for _, note in ipairs(notes) do GameTooltip:AddLine(note, 0.7, 0.7, 0.7, true) end
    end
    if data.empty then
        GameTooltip:AddLine("You have nothing in this slot.", 0.25, 1, 0.25)
    elseif data.delta and data.delta > 0.05 then
        GameTooltip:AddLine(string.format("+%.1f over what you wear", data.delta), 0.25, 1, 0.25)
    end
    if data.source then GameTooltip:AddLine(data.source, 0.7, 0.7, 0.7, true) end
    if data.origin then
        for _, line in ipairs(ns.Plugins:Lines(data.origin)) do GameTooltip:AddLine(line, 0.85, 0.85, 0.85, true) end
    end
    -- Lines the page adds itself (a craft's reagents).
    for _, line in ipairs(data.extraLines or {}) do GameTooltip:AddLine(line, 0.85, 0.85, 0.85, true) end
    if data.origin and not data.failed and ns.Plugins:Clickable(data.origin) then
        GameTooltip:AddLine("Click: details", 0.4, 0.73, 1)
    end
    if data.instKey and not data.failed then
        local hint
        if data.inJournal then
            hint = ns.Atlas:Available() and "Right-click: show in AtlasLoot" or nil
        elseif SpyGlassJournal then
            hint = "Click: show in the journal"
        elseif ns.Atlas:Available() then
            hint = "Click: show in AtlasLoot"
        end
        if hint then GameTooltip:AddLine(hint, 0.4, 0.73, 1) end
    end
    GameTooltip:Show()
    if IsShiftKeyDown() and GameTooltip_ShowCompareItem then GameTooltip_ShowCompareItem(GameTooltip) end
end

-- Shift-click links, Ctrl-click previews. A plain click opens the journal
-- on the boss that drops the item (AtlasLoot without the journal). Rows
-- already in the journal (data.inJournal) open AtlasLoot on right-click.
function W.ItemClick(row, button)
    local data = row.data
    if data and data.failed then
        ns:Retry(data.itemID)
        return
    end
    local info = data and ns:Peek(data.itemID)
    local link = info and info.link
    if link and IsModifiedClick() and HandleModifiedItemClick(link) then return end
    -- Plugin items: their origin decides what a click does.
    if data and data.origin and not data.instKey then
        GameTooltip:Hide()
        ns.Plugins:Click(data.origin, data)
        return
    end
    if not (data and data.instKey) then return end
    if data.inJournal then
        if button == "RightButton" then ns.Atlas:OpenTo(data.instKey, data.bossIndex) end
        return
    end
    GameTooltip:Hide()
    if SpyGlassJournal and SpyGlassJournal.OpenTo then
        SpyGlassJournal:OpenTo(data.instKey, data.bossIndex, data.itemID)
    else
        ns.Atlas:OpenTo(data.instKey, data.bossIndex)
    end
end
