local _, ns = ...

-- Prebuilt: reusable restock lists ("Raid Night"). Left: your character's lists and the account's
-- shared ones. Right: the selected list's items and their target amounts.
local W = ns.Widgets
local Label, Muted, MakeButton, Hint = W.Label, W.Muted, W.MakeButton, W.Hint
local MakeEditBox, MakeNumberBox = W.MakeEditBox, W.MakeNumberBox

local LEFT_W = 210

local function Build(p)
    local selectedID, selectedEntry

    Label(p, "Prebuilt", "QuartermasterGameFontNormalLarge", 0, 0)
    p.summary = Muted(Label(p, "Lists you restock again and again, like Raid Night. Set a target for each item; in the Cart tab at the auction house, tick the lists and Quartermaster buys only what you're missing.", "QuartermasterGameFontHighlightSmall", 0, -24, 640))
    p.summary:SetWordWrap(true)

    -- Left column: create / rename / delete, then the lists themselves.
    local nameBox = MakeEditBox(p, LEFT_W, "Name, e.g. Raid Night")
    nameBox:SetPoint("TOPLEFT", 0, -56)
    local new = MakeButton(p, "New", 66, 24); new:SetPoint("TOPLEFT", 0, -88)
    local rename = MakeButton(p, "Rename", 68, 24); rename:SetPoint("LEFT", new, "RIGHT", 4, 0)
    local delete = MakeButton(p, "Delete", 68, 24); delete:SetPoint("LEFT", rename, "RIGHT", 4, 0)
    Hint(new, "New prebuilt list", "Creates a list for this character. Right-click it later to share it with all your characters.")

    local leftHolder = CreateFrame("Frame", nil, p)
    leftHolder:SetPoint("TOPLEFT", 0, -120); leftHolder:SetPoint("BOTTOMLEFT", 0, 0); leftHolder:SetWidth(LEFT_W + 26)
    local lists = W.CreateRowList(leftHolder, 0, { rowHeight = 32 })

    -- Right side: the selected list's items.
    local right = CreateFrame("Frame", nil, p)
    right:SetPoint("TOPLEFT", LEFT_W + 36, -56); right:SetPoint("BOTTOMRIGHT", 0, 0)
    right.title = Label(right, "", "QuartermasterGameFontNormal", 0, 0)
    right.title:SetPoint("RIGHT", 0, 0); right.title:SetWordWrap(false)
    local items = W.CreateRowList(right, -24, { bottom = 40 })

    local bar = CreateFrame("Frame", nil, right)
    bar:SetPoint("BOTTOMLEFT", 0, 0); bar:SetPoint("BOTTOMRIGHT", 0, 0); bar:SetHeight(32)
    local selText = bar:CreateFontString(nil, "OVERLAY", "QuartermasterGameFontHighlightSmall")
    selText:SetPoint("LEFT", 0, 0); selText:SetWidth(130); selText:SetJustifyH("LEFT"); selText:SetWordWrap(false)
    local targetLabel = Muted(bar:CreateFontString(nil, "OVERLAY", "QuartermasterGameFontHighlightSmall"))
    targetLabel:SetPoint("LEFT", selText, "RIGHT", 6, 0); targetLabel:SetText("Target")
    local target = MakeNumberBox(bar, 46); target:SetPoint("LEFT", targetLabel, "RIGHT", 4, 0)
    local tolLabel = Muted(bar:CreateFontString(nil, "OVERLAY", "QuartermasterGameFontHighlightSmall"))
    tolLabel:SetPoint("LEFT", target, "RIGHT", 10, 0); tolLabel:SetText("Tolerance %")
    local tol = MakeNumberBox(bar, 46); tol:SetPoint("LEFT", tolLabel, "RIGHT", 4, 0)
    Hint(tol, "Tolerance for this item", "How far over market this item may go. Leave empty to use the default from Settings.")
    local save = MakeButton(bar, "Save", 50, 26); save:SetPoint("LEFT", tol, "RIGHT", 6, 0)

    local function Selected()
        local t, scope = ns.Prebuilt:Get(selectedID)
        return t, scope
    end

    local function Select(t)
        selectedID, selectedEntry = t and t.id, nil
        if t then ns.Lists:SetAddTarget("template", t.id) else ns:Changed() end
    end

    local function SaveSelected()
        if not selectedEntry then return end
        if target:GetValue() then ns.Lists:SetQty(selectedEntry, target:GetValue()) end
        local v = tol:GetValue()
        selectedEntry.tolerance = v and v >= 0 and v or nil
        target:ClearFocus(); tol:ClearFocus()
        ns:Changed()
    end
    save:SetScript("OnClick", SaveSelected)
    target:SetScript("OnEnterPressed", SaveSelected)
    tol:SetScript("OnEnterPressed", SaveSelected)

    new:SetScript("OnClick", function()
        local t = ns.Prebuilt:Create(nameBox:GetText(), "char")
        nameBox:SetText(""); nameBox:ClearFocus()
        Select(t)
    end)
    -- Renames straight from the name box if you typed one, otherwise asks with the current name filled in.
    local function AskRename(t)
        W.AskText(("Rename the prebuilt list \"%s\":"):format(t.name), t.name, function(text)
            ns.Prebuilt:Rename(t, text)
        end)
    end
    rename:SetScript("OnClick", function()
        local t = Selected()
        if not t then return end
        if ns.Trim(nameBox:GetText()) ~= "" then
            ns.Prebuilt:Rename(t, nameBox:GetText()); nameBox:SetText(""); nameBox:ClearFocus()
        else
            AskRename(t)
        end
    end)
    Hint(rename, "Rename", "Renames the selected prebuilt list. Type the new name in the box first, or just click to be asked. You can also right-click a list.")
    local function ConfirmDelete(t, scope)
        W.Confirm(("Delete the prebuilt list \"%s\"%s?"):format(t.name,
            scope == "account" and " for all your characters" or ""), function()
            if selectedID == t.id then Select(nil) end
            ns.Prebuilt:Delete(t)
        end)
    end
    delete:SetScript("OnClick", function()
        local t, scope = Selected()
        if t then ConfirmDelete(t, scope) end
    end)

    local function MenuFor(t, scope)
        if scope == "char" then
            W.ContextMenu({
                { t.name, nil, header = true },
                { "Rename", function() AskRename(t) end },
                { "Share with account", function() ns.Prebuilt:Share(t) end },
                { "Duplicate", function() Select(ns.Prebuilt:Duplicate(t, "char")) end },
                { "Delete", function() ConfirmDelete(t, scope) end },
            })
        else
            W.ContextMenu({
                { t.name .. " (account)", nil, header = true },
                { "Rename", function() AskRename(t) end },
                { "Make character-only", function() ns.Prebuilt:MakeCharacterOnly(t) end },
                { "Duplicate to this character", function() Select(ns.Prebuilt:Duplicate(t, "char")) end },
                { "Delete", function() ConfirmDelete(t, scope) end },
            })
        end
    end

    p.Refresh = function()
        local all = ns.Prebuilt:All()
        if not Selected() then
            selectedID = (all.char[1] or all.account[1] or {}).id
            selectedEntry = nil
        end

        -- Left: lists grouped by scope.
        local rows = {}
        local headers = { char = "This character", account = "Account (all characters)" }
        for _, scope in ipairs({ "char", "account" }) do
            rows[#rows + 1] = { noIcon = true, text = "|cff8fa3b3" .. headers[scope] .. "|r",
                detail = #all[scope] == 0 and (scope == "char" and "Type a name and click New." or "Right-click a list above to share it.") or "",
                plainText = headers[scope],
                hint = scope == "char" and "Only this character sees these. Right-click one to share it."
                    or "Every character on this account sees these." }
            for _, t in ipairs(all[scope]) do
                local cost, unknown = ns.Prebuilt:RestockCost(t)
                rows[#rows + 1] = {
                    icon = scope == "account" and "Interface\\Icons\\INV_Misc_GroupNeedMore" or "Interface\\Icons\\INV_Crate_01",
                    text = t.name,
                    detail = ("%d item%s  ·  restock ~%s%s"):format(#t.entries, #t.entries == 1 and "" or "s",
                        ns.Compat.Money(cost), unknown > 0 and "+" or ""),
                    plainText = t.name,
                    hint = "Click to edit. Right-click to Rename, " .. (scope == "char" and "Share with account" or "Make character-only") .. ", Duplicate or Delete.",
                    selected = t.id == selectedID,
                    onClick = function() Select(t) end,
                    onRightClick = function() MenuFor(t, scope) end,
                }
            end
        end
        lists:Set(rows)

        -- Right: the selected list.
        local t, scope = Selected()
        rename:SetEnabled(t ~= nil); delete:SetEnabled(t ~= nil)
        rename:SetAlpha(t and 1 or 0.4); delete:SetAlpha(t and 1 or 0.4)
        if not t then
            right.title:SetText("")
            items:Set({}, "Make a prebuilt list on the left, then add items from Browse or drop them here.")
            selText:SetText("")
        else
            right.title:SetText(("%s  |cff8fa3b3(%s)|r"):format(t.name, scope == "account" and "account" or "this character"))
            if selectedEntry and not ns.Lists:Contains(t, selectedEntry) then selectedEntry = nil end
            local list = {}
            for _, entry in ipairs(t.entries) do
                local e = ns.Catalog:Get(entry.itemID)
                local market, seen = ns.Lists:Price(entry)
                local have = ns.Stock:Have(entry.itemID)
                local need = math.max(0, entry.qty - have)
                local detail = ("target %d  ·  have %d (%s)  ·  %s %s"):format(entry.qty, have,
                    ns.Stock:Describe(entry.itemID), seen and "seen at" or "market", W.Money(market))
                if entry.tolerance then detail = detail .. ("  ·  +%d%%"):format(entry.tolerance) end
                list[#list + 1] = {
                    icon = W.IconFor(e or entry), link = entry.link or (e and e.link),
                    text = ns.Lists:Describe(entry), detail = detail,
                    right = need == 0 and "|cff59f28cstocked|r"
                        or ("need %d%s"):format(need, market and ("  ~" .. ns.Compat.Money(market * need)) or ""),
                    bar = entry.qty > 0 and math.min(1, have / entry.qty) or nil, barText = "",
                    selected = selectedEntry == entry,
                    hint = "Click to set the target and tolerance below.",
                    onClick = function()
                        selectedEntry = entry; target:SetValue(entry.qty); tol:SetValue(entry.tolerance); p.Refresh()
                    end,
                    actions = {
                        { "X", function() if selectedEntry == entry then selectedEntry = nil end; ns.Lists:Remove(t, entry) end, "Remove from the list" },
                        { "+", function() ns.Lists:SetQty(entry, entry.qty + 1) end, "Raise the target" },
                        { "-", function() ns.Lists:SetQty(entry, entry.qty - 1) end, "Lower the target" },
                    },
                }
            end
            items:Set(list, "No items yet. In Browse, choose \"" .. t.name .. "\" as the Add to target, or drop items from your bags here.")
            items.onDrop = function() W.AddCursorItem(t) end
            selText:SetText(selectedEntry and ns.Lists:Describe(selectedEntry) or "|cff8fa3b3Select an item|r")
        end
        for _, w in ipairs({ target, tol, save }) do w:SetEnabled(selectedEntry ~= nil); w:SetAlpha(selectedEntry and 1 or 0.5) end
        if not selectedEntry then target:SetText(""); tol:SetText("") end
    end
end

ns.UI:RegisterPage("prebuilt", Build)

ns:On("BAG_UPDATE_DELAYED", function() if ns.UI:IsShown() then ns.UI:Refresh() end end)
