local _, ns = ...

-- Lists: pick, create, rename and delete shopping lists; edit quantities and per-item tolerance.
local W = ns.Widgets
local Label, Muted, MakeButton, Hint = W.Label, W.Muted, W.MakeButton, W.Hint
local MakeEditBox, MakeNumberBox = W.MakeEditBox, W.MakeNumberBox

local function Build(p)
    local selected

    Label(p, "Lists", "QuartermasterGameFontNormalLarge", 0, 0)
    p.summary = Muted(Label(p, "", "QuartermasterGameFontHighlightSmall", 0, -24, 620))

    local picker = W.MakeDropdown(p, 170, function()
        local opts = {}
        for i, l in ipairs(ns.Lists:All()) do opts[#opts + 1] = { i, l.name .. " |cff8fa3b3(" .. #l.entries .. ")|r" } end
        return opts
    end, function(index) selected = nil; ns.Lists:SetActive(index) end)
    picker:SetPoint("TOPLEFT", 0, -46)
    Hint(picker, "Active list", "Browse adds to this list, and the Cart tab at the auction house buys it.")

    local nameBox = MakeEditBox(p, 140, "List name")
    nameBox:SetPoint("LEFT", picker, "RIGHT", 10, 0)
    local new = MakeButton(p, "New", 50, 26); new:SetPoint("LEFT", nameBox, "RIGHT", 6, 0)
    local rename = MakeButton(p, "Rename", 64, 26); rename:SetPoint("LEFT", new, "RIGHT", 4, 0)
    local delete = MakeButton(p, "Delete", 60, 26); delete:SetPoint("LEFT", rename, "RIGHT", 4, 0)
    local export = MakeButton(p, "Send to Auctionator", 140, 26); export:SetPoint("TOPRIGHT", 0, -80)
    Hint(export, "Send to Auctionator", "Creates (or replaces) an Auctionator shopping list called \"Quartermaster - <name>\" with exact searches for each item and the quantity still needed.")

    new:SetScript("OnClick", function()
        ns.Lists:Create(nameBox:GetText()); nameBox:SetText(""); nameBox:ClearFocus(); selected = nil
    end)
    rename:SetScript("OnClick", function()
        ns.Lists:Rename(ns.Lists:Active(), nameBox:GetText()); nameBox:SetText(""); nameBox:ClearFocus()
    end)
    delete:SetScript("OnClick", function()
        local list = ns.Lists:Active()
        W.Confirm(("Delete the list \"%s\" (%d items)?"):format(list.name, #list.entries), function()
            ns.Lists:Delete(list); selected = nil
        end)
    end)
    export:SetScript("OnClick", function() ns.Lists:ExportToAuctionator(ns.Lists:Active()) end)
    local savePre = MakeButton(p, "Save as prebuilt", 116, 26); savePre:SetPoint("RIGHT", export, "LEFT", -6, 0)
    Hint(savePre, "Save as prebuilt", "Copies this list into a new prebuilt list for this character. Each quantity becomes a target that the Cart restocks you to.")
    savePre:SetScript("OnClick", function()
        ns.Prebuilt:FromList(ns.Lists:Active())
        ns.UI:Show("prebuilt")
    end)

    local list = W.CreateRowList(p, -114, { bottom = 40 })
    list.onDrop = function() W.AddCursorItem() end

    -- Bottom bar: edit the selected entry; list-wide actions on the right.
    local bar = CreateFrame("Frame", nil, p)
    bar:SetPoint("BOTTOMLEFT", 0, 0); bar:SetPoint("BOTTOMRIGHT", 0, 0); bar:SetHeight(32)
    local selText = bar:CreateFontString(nil, "OVERLAY", "QuartermasterGameFontHighlightSmall")
    selText:SetPoint("LEFT", 0, 0); selText:SetWidth(170); selText:SetJustifyH("LEFT"); selText:SetWordWrap(false)
    local qtyLabel = Muted(bar:CreateFontString(nil, "OVERLAY", "QuartermasterGameFontHighlightSmall"))
    qtyLabel:SetPoint("LEFT", selText, "RIGHT", 6, 0); qtyLabel:SetText("Qty")
    local qty = MakeNumberBox(bar, 46); qty:SetPoint("LEFT", qtyLabel, "RIGHT", 4, 0)
    local tolLabel = Muted(bar:CreateFontString(nil, "OVERLAY", "QuartermasterGameFontHighlightSmall"))
    tolLabel:SetPoint("LEFT", qty, "RIGHT", 10, 0); tolLabel:SetText("Tolerance %")
    local tol = MakeNumberBox(bar, 46); tol:SetPoint("LEFT", tolLabel, "RIGHT", 4, 0)
    Hint(tol, "Tolerance for this item", "How far over market this item may go. Leave empty to use the default from Settings.")
    local save = MakeButton(bar, "Save", 50, 26); save:SetPoint("LEFT", tol, "RIGHT", 6, 0)
    local clear = MakeButton(bar, "Clear list", 74, 26); clear:SetPoint("RIGHT", 0, 0)
    local resetBtn = MakeButton(bar, "Reset bought", 92, 26); resetBtn:SetPoint("RIGHT", clear, "LEFT", -6, 0)
    Hint(resetBtn, "Reset bought", "Sets every item's bought count back to 0, so the Cart buys the full amounts again.")

    local function SaveSelected()
        if not selected then return end
        if qty:GetValue() then ns.Lists:SetQty(selected, qty:GetValue()) end
        local t = tol:GetValue()
        selected.tolerance = t and t >= 0 and t or nil
        qty:ClearFocus(); tol:ClearFocus()
        ns:Changed()
    end
    save:SetScript("OnClick", SaveSelected)
    qty:SetScript("OnEnterPressed", SaveSelected)
    tol:SetScript("OnEnterPressed", SaveSelected)
    clear:SetScript("OnClick", function()
        local l = ns.Lists:Active()
        W.Confirm(("Remove all %d items from \"%s\"?"):format(#l.entries, l.name), function() ns.Lists:Clear(l); selected = nil end)
    end)
    resetBtn:SetScript("OnClick", function() ns.Lists:ResetProgress(ns.Lists:Active()) end)

    p.Refresh = function()
        local active = ns.Lists:Active()
        picker:SetValue(ns.char.activeList, active.name)
        delete:SetEnabled(#ns.Lists:All() > 1); delete:SetAlpha(#ns.Lists:All() > 1 and 1 or 0.4)
        if selected and not ns.Lists:Contains(active, selected) then selected = nil end

        local items = {}
        for _, entry in ipairs(active.entries) do
            local f = entry.filter
            local e = not f and ns.Catalog:Get(entry.itemID)
            local market, seen
            if f then market = f.maxPrice else market, seen = ns.Lists:Price(entry) end
            local tolerance = ns.Lists:Tolerance(entry)
            local remaining = ns.Lists:Remaining(entry)
            local detail
            if f then
                detail = ("%d/%d bought  ·  any matching item, cheapest first  ·  "):format(entry.bought or 0, entry.qty)
                    .. (f.maxPrice and ("max %s each"):format(ns.Compat.Money(f.maxPrice))
                        or ("max market +%d%%%s per item"):format(tolerance, entry.tolerance and ", custom" or ""))
            else
                detail = ("%d/%d bought  ·  %s %s"):format(entry.bought or 0, entry.qty, seen and "seen at" or "market", W.Money(market))
                if market then detail = detail .. ("  ·  max %s (+%d%%%s)"):format(ns.Compat.Money(market * (1 + tolerance / 100)),
                    tolerance, entry.tolerance and ", custom" or "") end
            end
            local actions = {
                { "X", function() if selected == entry then selected = nil end; ns.Lists:Remove(active, entry) end, "Remove from the list" },
                { "+", function() ns.Lists:SetQty(entry, entry.qty + 1) end, "One more" },
                { "-", function() ns.Lists:SetQty(entry, entry.qty - 1) end, "One fewer" },
            }
            if f then
                table.insert(actions, { "Edit", function()
                    if not (ns.AuctionTab and ns.AuctionTab:EditEntry(entry)) then
                        ns:Print("Searches are edited in the Buying tab: open the auction house first.", true)
                    end
                end, "Change this search in the Buying tab (at the auction house)" })
            end
            items[#items + 1] = {
                icon = f and "Interface\\Icons\\INV_Misc_Spyglass_03" or W.IconFor(e or entry), link = entry.link or (e and e.link),
                text = ns.Lists:Describe(entry), detail = detail,
                right = remaining > 0 and market and ("~" .. ns.Compat.Money(market * remaining)) or (remaining == 0 and "|cff59f28cdone|r" or nil),
                bar = entry.qty > 0 and math.min(1, (entry.bought or 0) / entry.qty) or nil,
                barText = "",
                selected = selected == entry,
                dim = remaining == 0 and 0.55 or nil,
                hint = f and ("A search entry: the Cart buys any items matching it.\n" .. ns.Search:Describe(f)
                    .. "\nClick to edit quantity and tolerance below.") or "Click to edit quantity and tolerance below.",
                onClick = function()
                    selected = entry; qty:SetValue(entry.qty); tol:SetValue(entry.tolerance); p.Refresh()
                end,
                actions = actions,
            }
        end
        list:Set(items, "This list is empty. Add items from Browse, drop them here, or use /qm add <item> [qty].")

        local total, unknown = ns.Lists:Estimate(active)
        p.summary:SetText(("%d item%s on %s. Still to buy: about %s%s."):format(#active.entries, #active.entries == 1 and "" or "s",
            active.name, ns.Compat.Money(total), unknown > 0 and (" plus " .. unknown .. " without a market price") or ""))
        selText:SetText(selected and ns.Lists:Describe(selected) or "|cff8fa3b3Select an item|r")
        for _, w in ipairs({ qty, tol, save }) do w:SetEnabled(selected ~= nil); w:SetAlpha(selected and 1 or 0.5) end
        if not selected then qty:SetText(""); tol:SetText("") end
    end
end

ns.UI:RegisterPage("lists", Build)
