local _, ns = ...
local PAL = ns.Palette
local C = ns.Compat

-- The Wally manager: Junk List, Never Sell, Learning, In Bags, History, Settings.
local UI = {}
ns.UI = UI

local win -- the window (shared\Window.lua), made under "Window" below
local RULE_ICON = "Interface\\Icons\\INV_Misc_Note_01"

-- Widgets live in Widgets.lua (shared with the auction house tab).
local W = ns.Widgets
local ROW_H, ROW_GAP, ACCENT, MUTED, UNKNOWN_ICON = W.ROW_H, W.ROW_GAP, W.ACCENT, W.MUTED, W.UNKNOWN_ICON
local SetBackdrop, Label, Muted, MakeButton, Hint = W.SetBackdrop, W.Label, W.Muted, W.MakeButton, W.Hint
local MakeCheckbox, MakeEditBox, EntryText, IconFor, When = W.MakeCheckbox, W.MakeEditBox, W.EntryText, W.IconFor, W.When
local Confirm, AddCursorItem, NewRow, LayoutRow, CreateRowList = W.Confirm, W.AddCursorItem, W.NewRow, W.LayoutRow, W.CreateRowList

-- ---------------------------------------------------------------------------
-- Pages
-- ---------------------------------------------------------------------------

local function NewPage(name) return win:NewPage(name) end

local SOURCES = { "all", "manual", "learned", "import" }
local SOURCE_LABEL = { all = "All sources", manual = "Added by you", learned = "Learned", import = "Imported" }

local function CreateListPage(name, kind)
    local p = NewPage(name)
    local isJunk = kind == "inclusions"
    local patternKind = isJunk and "include" or "exclude"
    local otherKind = ns.Lists.OPPOSITE[kind]
    local otherLabel = ns.Lists.LABEL[otherKind]
    p.source = "all"

    Label(p, ns.Lists.LABEL[kind], "WallyGameFontNormalLarge", 0, 0)
    p.summary = Muted(Label(p, "", "WallyGameFontHighlightSmall", 0, -24, 560))

    p.search = MakeEditBox(p, 200, "Search...")
    p.search:SetPoint("TOPLEFT", 0, -46)
    p.search:SetScript("OnTextChanged", function() UI:RefreshPage(name) end)

    local sourceBtn = MakeButton(p, SOURCE_LABEL.all, 120, 26)
    sourceBtn:SetPoint("LEFT", p.search, "RIGHT", 8, 0)
    sourceBtn:SetScript("OnClick", function(self)
        for i, s in ipairs(SOURCES) do
            if s == p.source then p.source = SOURCES[i % #SOURCES + 1]; break end
        end
        self.text:SetText(SOURCE_LABEL[p.source]); UI:RefreshPage(name)
    end)
    Hint(sourceBtn, "Filter by source", "Show everything, only items you added, items Wally learned from your selling, or imported items.")

    local clear = MakeButton(p, "Remove all", 96, 26)
    clear:SetPoint("TOPRIGHT", 0, -46)
    clear:SetScript("OnClick", function()
        Confirm("Remove every item from " .. ns.Lists.LABEL[kind] .. "?\n(Rules are kept.)", function() ns.Lists:RemoveAll(kind) end)
    end)

    p.add = MakeEditBox(p, 300, "Item name, link or ID (or drag an item here)")
    p.add:SetPoint("TOPLEFT", 0, -80)
    local function AddTyped()
        local text = ns.Trim(p.add:GetText())
        if text == "" then return end
        ns.Lists:Add(kind, text, "manual"); p.add:SetText(""); p.add:ClearFocus()
    end
    p.add:SetScript("OnEnterPressed", AddTyped)
    p.add:SetScript("OnReceiveDrag", function() AddCursorItem(kind) end)
    p.add:SetScript("OnMouseDown", function(self) if not AddCursorItem(kind) then self:SetFocus() end end)

    local addItem = MakeButton(p, "Add item", 80, 26)
    addItem:SetPoint("LEFT", p.add, "RIGHT", 8, 0)
    addItem:SetScript("OnClick", AddTyped)
    Hint(addItem, "Add an exact item", "Matches items with exactly this name. Shift-click an item into the box, drag one in, or type its name or item ID.")

    local addRule = MakeButton(p, "Add rule", 80, 26)
    addRule:SetPoint("LEFT", addItem, "RIGHT", 6, 0)
    addRule:SetScript("OnClick", function()
        local text = ns.Trim(p.add:GetText())
        if text == "" then return end
        if text:find("|Hitem:") then text = C.NameFromLink(text) or text end
        ns.Lists:AddPattern(patternKind, text); p.add:SetText(""); p.add:ClearFocus()
    end)
    Hint(addRule, isJunk and "Add a junk rule" or "Add a keep rule",
        "Any item whose name contains this text is " .. (isJunk and "treated as junk" or "never sold") .. ". Example: \"linen\" covers Linen Cloth, Linen Belt, ...")

    p.list = CreateRowList(p, -116)
    p.list.onDrop = function() AddCursorItem(kind) end
    p:EnableMouse(true)
    p:SetScript("OnReceiveDrag", function() AddCursorItem(kind) end)
    p:SetScript("OnMouseUp", function() AddCursorItem(kind) end)
    p.addBox = p.add

    p.Refresh = function()
        local items = {}
        local search = ns.Key(p.search:GetText())
        if p.source == "all" then
            for _, rule in ipairs(ns.db.patterns[patternKind]) do
                if not search or rule:find(search, 1, true) then
                    items[#items + 1] = {
                        icon = RULE_ICON, text = ("Name contains |cffffffff\"%s\"|r"):format(rule),
                        detail = "Rule", detailColor = { 1, 0.82, 0.3 }, plainText = "Rule: name contains \"" .. rule .. "\"",
                        actions = { { "Remove", function() ns.Lists:RemovePattern(patternKind, rule) end } },
                        onRightClick = function() ns.Lists:RemovePattern(patternKind, rule) end,
                        hint = "Right-click: remove rule",
                    }
                end
            end
        end
        local rows = ns.Lists:Search(kind, search, p.source)
        for _, r in ipairs(rows) do
            local e, key = r.entry, r.key
            items[#items + 1] = {
                icon = IconFor(e), text = EntryText(e, key), link = e.link, plainText = e.name or key,
                detail = (SOURCE_LABEL[e.source] or "Added by you") .. "  -  " .. When(e.added),
                detailColor = e.source == "learned" and { 0.85, 0.75, 0.4 } or nil,
                actions = {
                    { "Remove", function() ns.Lists:Remove(kind, key) end },
                    { isJunk and "Never sell" or "Junk", function() ns.Lists:Move(kind, key) end, "Move to " .. otherLabel },
                },
                onRightClick = function(shift) if shift then ns.Lists:Move(kind, key) else ns.Lists:Remove(kind, key) end end,
                hint = "Right-click: remove\nShift+right-click: move to " .. otherLabel,
            }
        end
        local ruleCount = #ns.db.patterns[patternKind]
        local total = 0
        for _ in pairs(ns.db[kind]) do total = total + 1 end
        p.summary:SetText(("%d item%s, %d rule%s. %s"):format(total, total == 1 and "" or "s", ruleCount, ruleCount == 1 and "" or "s",
            isJunk and "These are sold at merchants." or "These are never sold, whatever other rules say."))
        p.list:Set(items, (search or p.source ~= "all") and "Nothing matches." or
            (isJunk and "Your junk list is empty.\n\nDrag items here, or keep selling things by hand:\nWally will offer to add them for you."
                or "Nothing protected yet.\n\nDrag items here to make sure they're never sold."))
    end
end

local function CreateLearningPage()
    local p = NewPage("learning")
    Label(p, "Learning", "WallyGameFontNormalLarge", 0, 0)
    p.summary = Muted(Label(p, "", "WallyGameFontHighlightSmall", 0, -24, 560))
    p.search = MakeEditBox(p, 200, "Search...")
    p.search:SetPoint("TOPLEFT", 0, -62)
    p.search:SetScript("OnTextChanged", function() UI:RefreshPage("learning") end)
    local reset = MakeButton(p, "Forget everything", 130, 26)
    reset:SetPoint("TOPRIGHT", 0, -62)
    reset:SetScript("OnClick", function() Confirm("Forget all selling habits Wally has learned?\n(Your lists are kept.)", function() ns.Learning:ResetAll() end) end)
    p.list = CreateRowList(p, -98)

    p.Refresh = function()
        local threshold = ns.db.options.threshold
        p.summary:SetText(("Selling an item by hand raises its score; buying it back lowers it. At %d%% Wally asks whether it's junk.\nWally's own sales and items already on a list don't count."):format(threshold * 100))
        local items = {}
        for _, r in ipairs(ns.Learning:List(p.search:GetText())) do
            local h, key = r.habit, r.key
            local status
            if ns.db.inclusions[key] then status = "On Junk List"
            elseif ns.db.exclusions[key] then status = "On Never Sell"
            elseif h.snoozedUntil and h.snoozedUntil > time() then status = "Asked, waiting a day"
            elseif h.pending then status = "Waiting for your answer" end
            local detail = ("Sold %d, bought back %d, %s earned"):format(h.sold or 0, h.boughtBack or 0, C.Money(h.copper or 0))
            if status then detail = detail .. "  -  |cffffd24d" .. status .. "|r" end
            items[#items + 1] = {
                icon = IconFor(h), text = EntryText(h, key), link = h.link, plainText = h.name or key,
                detail = detail, bar = h.score or 0, marker = threshold,
                barText = ("%d%%"):format(math.floor((h.score or 0) * 100)),
                actions = {
                    { "Forget", function() ns.Learning:Forget(key) end, "Reset what Wally learned about this item" },
                    { "Never", function() ns.Lists:Add("exclusions", h.link or key, "manual") end, "Add to Never Sell" },
                    { "Junk", function() ns.Lists:Add("inclusions", h.link or key, "learned") end, "Add to the Junk List" },
                },
                hint = "Last sold " .. When(h.lastSold),
            }
        end
        p.list:Set(items, "Nothing learned yet.\n\nSell items to a merchant by hand (right-click them in your bags)\nand Wally will start noticing your habits.")
    end
end

-- Auction List / Never Auction / Learning (auction habits). Posting happens on the auction house tab.
local AUCTION_VIEWS = { { "auctionList", "Auction List" }, { "neverAuction", "Never Auction" }, { "learning", "Learning" }, { "market", "On Market" } }
local TIME_BAND = ns.Compat.AUCTION_TIME_BAND
local BAND_LEFT = { [0] = 1800, 7200, 43200, 172800 }

-- Time left on one of your auctions; a remembered one counts down from when it was seen.
local function MarketTimeLeft(a, live)
    local s
    if live then
        s = a.timeLeftSeconds
        if not s then return TIME_BAND[a.timeLeft] or "" end
    elseif a.expires then
        s = math.max(0, a.expires - time())
    else
        return ""
    end
    local text = s >= 3600 and ("%dh %dm"):format(s / 3600, s % 3600 / 60) or ("%dm"):format(math.max(1, s / 60))
    -- Only a time-left band was known: this is the most it can have left.
    if not live and not a.exact then text = "up to " .. text end
    return text .. " left"
end

local function CreateAuctionPage()
    local p = NewPage("auction")
    p.view = "auctionList"
    Label(p, "Auctions", "WallyGameFontNormalLarge", 0, 0)
    p.summary = Muted(Label(p, "", "WallyGameFontHighlightSmall", 0, -24, 560))

    p.viewButtons = {}
    for i, v in ipairs(AUCTION_VIEWS) do
        local b = MakeButton(p, v[2], 100, 26); b:SetPoint("TOPLEFT", (i - 1) * 104, -46)
        b:SetScript("OnClick", function() p.view = v[1]; UI:RefreshPage("auction") end)
        p.viewButtons[v[1]] = b
    end
    p.search = MakeEditBox(p, 160, "Search...")
    p.search:SetPoint("TOPRIGHT", 0, -46)
    p.search:SetScript("OnTextChanged", function() UI:RefreshPage("auction") end)

    local function Kind() return (p.view == "learning" or p.view == "market") and "auctionList" or p.view end
    p.add = MakeEditBox(p, 300, "Item name, link or ID (or drag an item here)")
    p.add:SetPoint("TOPLEFT", 0, -80)
    local function AddTyped()
        local text = ns.Trim(p.add:GetText())
        if text == "" then return end
        ns.Lists:Add(Kind(), text, "manual"); p.add:SetText(""); p.add:ClearFocus()
    end
    p.add:SetScript("OnEnterPressed", AddTyped)
    p.add:SetScript("OnReceiveDrag", function() AddCursorItem(Kind()) end)
    p.add:SetScript("OnMouseDown", function(self) if not AddCursorItem(Kind()) then self:SetFocus() end end)
    local addItem = MakeButton(p, "Add item", 80, 26)
    addItem:SetPoint("LEFT", p.add, "RIGHT", 8, 0)
    addItem:SetScript("OnClick", AddTyped)
    p.addItem = addItem
    local forget = MakeButton(p, "Forget everything", 130, 26)
    forget:SetPoint("TOPRIGHT", 0, -80)
    forget:SetScript("OnClick", function()
        Confirm("Forget all auction habits Wally has learned?\n(Your lists are kept.)", function() ns.AuctionLearning:ResetAll() end)
    end)
    p.forget = forget

    p.list = CreateRowList(p, -116)
    p.list.onDrop = function() AddCursorItem(Kind()) end
    p:EnableMouse(true)
    p:SetScript("OnReceiveDrag", function() AddCursorItem(Kind()) end)
    p.addBox = p.add

    p.Refresh = function()
        for key, b in pairs(p.viewButtons) do
            if key == p.view then b:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
            else b:SetBackdropBorderColor(PAL.border[1], PAL.border[2], PAL.border[3], 1) end
        end
        p.forget:SetShown(p.view == "learning")
        p.add:SetShown(p.view ~= "market"); p.addItem:SetShown(p.view ~= "market")
        local search = p.search:GetText()
        local items = {}
        if p.view == "market" then
            local list, seen, live = ns.Auction:Market()
            local text = ns.Key(search)
            local sorted, total = {}, 0
            for _, a in ipairs(list) do
                total = total + (a.unit or 0) * (a.quantity or 1)
                if not text or (a.key or ""):find(text, 1, true) then sorted[#sorted + 1] = a end
            end
            -- Soonest to run out first.
            local function Left(a)
                if live then return a.timeLeftSeconds or (BAND_LEFT[a.timeLeft] or math.huge) end
                return a.expires or math.huge
            end
            table.sort(sorted, function(a, b)
                local la, lb = Left(a), Left(b)
                if la ~= lb then return la < lb end
                return (a.key or "") < (b.key or "")
            end)
            for _, a in ipairs(sorted) do
                local q = a.quantity or 1
                local price = a.unit and (q > 1 and ("%s each, %s"):format(C.Money(a.unit), C.Money(a.unit * q)) or C.Money(a.unit)) or "No buyout"
                local detail = price .. "  -  " .. MarketTimeLeft(a, live)
                if ns.db.auctionList[a.key] then detail = detail .. "  -  |cff59f28cOn Auction List|r" end
                if a.someSold then detail = detail .. "  -  |cffffd24dSome sold|r" end
                items[#items + 1] = {
                    icon = a.icon or IconFor(a), link = a.link, plainText = a.key,
                    text = (a.link or a.key or "?") .. "  |cffffffffx" .. q .. "|r", detail = detail,
                }
            end
            local count = #list
            local head = ("%d auction%s up, %s in buyouts."):format(count, count == 1 and "" or "s", C.Money(total))
            if live then
                p.summary:SetText(head .. " Live from the auction house.")
            elseif seen then
                p.summary:SetText(head .. (" As of your last auction house visit (%s), minus what has run out since.\nSales and expiries are picked up from chat; visit the auction house for an exact list."):format(When(seen)))
            else
                p.summary:SetText("Visit the auction house once and Wally will remember your auctions here.")
            end
            p.list:Set(items, text and "Nothing matches." or (seen and "None of your auctions are still up." or "No auctions seen yet."))
            return
        end
        if p.view == "learning" then
            local threshold = ns.db.options.threshold
            p.summary:SetText(("Posting an item by hand raises its score; cancelling lowers it. At %d%% Wally asks whether to auction it for you.\nPost from Wally's tab at the auction house."):format(threshold * 100))
            for _, r in ipairs(ns.AuctionLearning:List(search)) do
                local h, key = r.habit, r.key
                local detail = ("Posted %d, cancelled %d"):format(h.posted or 0, h.cancelled or 0)
                if h.snoozedUntil and h.snoozedUntil > time() then detail = detail .. "  -  |cffffd24dAsked, waiting a day|r"
                elseif h.pending then detail = detail .. "  -  |cffffd24dWaiting for your answer|r" end
                items[#items + 1] = {
                    icon = IconFor(h), text = EntryText(h, key), link = h.link, plainText = h.name or key,
                    detail = detail, bar = h.score or 0, marker = threshold,
                    barText = ("%d%%"):format(math.floor((h.score or 0) * 100)),
                    actions = {
                        { "Forget", function() ns.AuctionLearning:Forget(key) end, "Reset what Wally learned about this item" },
                        { "Never", function() ns.Lists:Add("neverAuction", h.link or key, "manual") end, "Add to Never Auction" },
                        { "Auction", function() ns.Lists:Add("auctionList", h.link or key, "learned") end, "Add to the Auction List" },
                    },
                    hint = "Last posted " .. When(h.lastPosted),
                }
            end
            p.list:Set(items, "Nothing learned yet.\n\nPost items at the auction house by hand\nand Wally will start noticing your habits.")
            return
        end
        local kind = p.view
        local other = ns.Lists.OPPOSITE[kind]
        local total = 0
        for _ in pairs(ns.db[kind]) do total = total + 1 end
        p.summary:SetText(("%d item%s. %s"):format(total, total == 1 and "" or "s", kind == "auctionList"
            and "Wally posts these from its auction house tab, and never sells them to a vendor."
            or "Wally never offers to auction these."))
        for _, r in ipairs(ns.Lists:Search(kind, search)) do
            local e, key = r.entry, r.key
            local detail = (e.source == "learned" and "Learned" or "Added by you") .. "  -  " .. When(e.added)
            local dur = e.duration and ns.Compat.AUCTION_HOURS[e.duration] and (ns.Compat.AUCTION_HOURS[e.duration] .. "h")
            if dur then detail = detail .. "  -  " .. dur end
            items[#items + 1] = {
                icon = IconFor(e), text = EntryText(e, key), link = e.link, plainText = e.name or key,
                detail = detail, detailColor = e.source == "learned" and { 0.85, 0.75, 0.4 } or nil,
                actions = {
                    { "Remove", function() ns.Lists:Remove(kind, key) end },
                    { kind == "auctionList" and "Never" or "Auction", function() ns.Lists:Move(kind, key) end, "Move to " .. ns.Lists.LABEL[other] },
                },
                onRightClick = function(shift) if shift then ns.Lists:Move(kind, key) else ns.Lists:Remove(kind, key) end end,
                hint = "Right-click: remove\nShift+right-click: move to " .. ns.Lists.LABEL[other],
            }
        end
        p.list:Set(items, ns.Key(search) and "Nothing matches." or (kind == "auctionList"
            and "Your Auction List is empty.\n\nDrag items here, or keep posting them by hand:\nWally will offer to add them for you."
            or "Nothing here yet."))
    end
end

local VERDICT_COLOR = {
    junk = { 1, 0.5, 0.4 }, keep = { 0.35, 0.95, 0.55 }, upgrade = { 0.4, 0.8, 1 }, none = MUTED,
}

local function CreateBagsPage()
    local p = NewPage("bags")
    Label(p, "In Bags", "WallyGameFontNormalLarge", 0, 0)
    p.summary = Muted(Label(p, "", "WallyGameFontHighlightSmall", 0, -24, 560))
    p.showAll = MakeCheckbox(p, "Show every item")
    p.showAll:SetPoint("TOPLEFT", -4, -46)
    p.showAll:SetScript("OnClick", function() UI:RefreshPage("bags") end)
    p.sell = MakeButton(p, "Sell junk now", 110, 26)
    p.sell:SetPoint("TOPRIGHT", 0, -46)
    p.sell:SetScript("OnClick", function() ns.Seller:Start(false) end)
    Hint(p.sell, "Sell junk", "Only works while a merchant window is open.")
    p.sort = MakeButton(p, "Sort bags", 90, 26)
    p.sort:SetPoint("RIGHT", p.sell, "LEFT", -8, 0)
    p.sort:SetScript("OnClick", function() ns.Sorter:Start("bags") end)
    Hint(p.sort, "Sort bags", "Sorts your bags using your rules in Bag Sorting.")
    local sortOptions = MakeButton(p, "Sort options", 96, 26)
    sortOptions:SetPoint("RIGHT", p.sort, "LEFT", -8, 0)
    sortOptions:SetScript("OnClick", function() UI:OpenSettings("sorting") end)
    Hint(sortOptions, "Bag Sorting", "Choose how your bags are sorted. Lives in Options > AddOns > Wally.")
    p.list = CreateRowList(p, -82)

    p.Refresh = function()
        local items, junkCount, junkValue, protected = {}, 0, 0, 0
        local rows = ns.JunkFilter:ScanBags()
        local order = { junk = 1, upgrade = 2, keep = 3, none = 4 }
        table.sort(rows, function(a, b)
            if order[a.verdict] ~= order[b.verdict] then return order[a.verdict] < order[b.verdict] end
            return (C.NameFromLink(a.info.link) or "") < (C.NameFromLink(b.info.link) or "")
        end)
        for _, r in ipairs(rows) do
            if r.isJunk then junkCount = junkCount + (r.info.count or 1); junkValue = junkValue + r.value end
            if r.verdict == "upgrade" then protected = protected + 1 end
            if p.showAll:GetChecked() or r.verdict ~= "none" then
                local link = r.info.link
                local actions
                if r.isJunk then
                    actions = { { "Keep", function() ns.Lists:Add("exclusions", link, "manual") end, "Add to Never Sell" } }
                elseif r.verdict ~= "keep" then
                    actions = { { "Junk", function() ns.Lists:Add("inclusions", link, "manual") end, "Add to the Junk List" } }
                end
                local count = (r.info.count or 1) > 1 and (" x" .. r.info.count) or ""
                items[#items + 1] = {
                    icon = r.info.icon, text = link .. count, link = link,
                    detail = (r.isJunk and ("Sells for " .. C.Money(r.value) .. "  -  ") or "") .. (r.reason or "Not junk"),
                    detailColor = VERDICT_COLOR[r.verdict], actions = actions,
                    onRightClick = function()
                        if r.isJunk then ns.Lists:Add("exclusions", link, "manual") else ns.Lists:Add("inclusions", link, "manual") end
                    end,
                    hint = r.isJunk and "Right-click: never sell this" or "Right-click: mark as junk",
                }
            end
        end
        p.summary:SetText(("%d junk item%s worth %s.  %d grey/white piece%s kept as possible upgrades."):format(
            junkCount, junkCount == 1 and "" or "s", C.Money(junkValue), protected, protected == 1 and "" or "s"))
        local atMerchant = MerchantFrame and MerchantFrame:IsShown()
        p.sell:SetAlpha(atMerchant and 1 or 0.5)
        p.list:Set(items, "No junk, upgrades or protected items in your bags.")
    end
end

local function CreateHistoryPage()
    local p = NewPage("history")
    Label(p, "History", "WallyGameFontNormalLarge", 0, 0)
    p.summary = Muted(Label(p, "", "WallyGameFontHighlightSmall", 0, -24, 560))
    local clear = MakeButton(p, "Clear history", 110, 26)
    clear:SetPoint("TOPRIGHT", 0, -46)
    clear:SetScript("OnClick", function() Confirm("Clear the sell / buyback history?", function() wipe(ns.db.history); ns:Changed() end) end)
    local archive = MakeButton(p, "Sale History by session", 170, 26)
    archive:SetPoint("RIGHT", clear, "LEFT", -8, 0)
    archive:SetScript("OnClick", function() UI:OpenSettings("history") end)
    Hint(archive, "Sale History", "Everything Wally sold for you, kept per login session. Lives in Options > AddOns > Wally.")
    p.list = CreateRowList(p, -82)

    p.Refresh = function()
        local items, soldCopper = {}, 0
        for _, h in ipairs(ns.db.history) do
            local sold = h.kind == "sold"
            if sold then soldCopper = soldCopper + (h.copper or 0) end
            local verb = sold and "|cffff8866Sold|r " or "|cff55d6beBought back|r "
            local who = sold and (h.byWally and "by Wally" or "by hand") or ""
            local link = h.link
            items[#items + 1] = {
                icon = link and select(5, C.GetItemInfoInstant(link)) or UNKNOWN_ICON,
                text = verb .. ((h.count or 1) > 1 and (h.count .. "x ") or "") .. (link or "?"), link = link,
                detail = When(h.t) .. "  -  " .. C.Money(h.copper or 0) .. (who ~= "" and ("  -  " .. who) or ""),
                actions = link and {
                    { "Never", function() ns.Lists:Add("exclusions", link, "manual") end, "Add to Never Sell" },
                    { "Junk", function() ns.Lists:Add("inclusions", link, "manual") end, "Add to the Junk List" },
                } or nil,
            }
        end
        p.summary:SetText(("Last %d sells and buybacks (%s sold)."):format(#ns.db.history, C.Money(soldCopper)))
        p.list:Set(items, "No merchant activity recorded yet.")
    end
end

local OPTION_DEFS = {
    { "autoSell", "Sell junk automatically", "Sell as soon as you open a merchant." },
    { "safeSell", "Safe sell (12 at a time)", "Never sell more than you can buy back." },
    { "sellGreys", "Grey items are junk", "Every poor-quality item counts as junk." },
    { "protectUpgrades", "Protect possible upgrades", "Keep grey/white gear that may beat what you wear." },
    { "sellUnusableBound", "Sell unusable soulbound gear", "Gear you can't use. Enchanters keep greens+." },
    { "autoRepair", "Repair gear automatically", "At any vendor who repairs. Uses guild funds first if allowed." },
    { "learn", "Learn from my selling", "Watch what you sell by hand and buy back." },
    { "autoAcceptLearned", "Add learned items silently", "Skip the question and add straight to the Junk List." },
    { "tooltip", "Item tooltip lines", "Show Wally's verdict on item tooltips." },
    { "chat", "Chat messages", "Print sale totals and other notices." },
}

-- Sales of a non-stacking item needed to reach a score.
local function SalesToReach(threshold)
    local s, n = 0, 0
    repeat s = s + (1 - s) * 0.382; n = n + 1 until s >= threshold or n > 50
    return n
end

-- Lists subpage: import / export, the junk manager, forgetting what Wally learned, and clearing
-- the sale history (Options > AddOns > Wally > Lists).
local function BuildListTools(p)
    Label(p, "Lists", "WallyGameFontNormalLarge", 0, 0):SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])

    Label(p, "Import / export lists", "WallyGameFontHighlight", 0, -38)
    Muted(Label(p, "One per line. J: junk, N: never sell, J*: / N*: rules.", "WallyGameFontHighlightSmall", 0, -58, 400))
    local box = CreateFrame("Frame", nil, p, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 0, -78); box:SetSize(400, 200)
    SetBackdrop(box); box:SetBackdropColor(PAL.field[1], PAL.field[2], PAL.field[3], 1)
    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6); scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetFontObject("WallyGameFontHighlightSmall")
    edit:SetWidth(364); edit:SetHeight(190)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(edit)
    box:EnableMouse(true); box:SetScript("OnMouseDown", function() edit:SetFocus() end)
    p.io = edit

    local export = MakeButton(p, "Export", 86, 26); export:SetPoint("TOPLEFT", 0, -286)
    export:SetScript("OnClick", function() edit:SetText(ns.Lists:Export()); edit:SetFocus(); edit:HighlightText() end)
    Hint(export, "Export", "Fills the box with your lists and rules. Press Ctrl+C to copy.")
    local import = MakeButton(p, "Import", 86, 26); import:SetPoint("LEFT", export, "RIGHT", 8, 0)
    import:SetScript("OnClick", function() ns.Lists:Import(edit:GetText()); edit:ClearFocus() end)
    Hint(import, "Import", "Adds every line in the box to your lists. Nothing is removed.")
    local clearBox = MakeButton(p, "Clear", 86, 26); clearBox:SetPoint("LEFT", import, "RIGHT", 8, 0)
    clearBox:SetScript("OnClick", function() edit:SetText("") end)

    local open = MakeButton(p, "Open junk manager", 140, 26); open:SetPoint("TOPLEFT", 0, -330)
    open:SetScript("OnClick", function() UI:Show() end)
    Hint(open, "Junk manager", "Junk List, Never Sell, Learning, In Bags and History. Also /wally.")
    local forget = MakeButton(p, "Forget learning", 120, 26); forget:SetPoint("LEFT", open, "RIGHT", 8, 0)
    forget:SetScript("OnClick", function() Confirm("Forget all selling habits Wally has learned?\n(Your lists are kept.)", function() ns.Learning:ResetAll() end) end)
    local history = MakeButton(p, "Clear sale history", 130, 26); history:SetPoint("LEFT", forget, "RIGHT", 8, 0)
    history:SetScript("OnClick", function() Confirm("Delete Wally's entire sale history?", function() ns.Sessions:Clear() end) end)
    Hint(history, "Clear sale history", "Deletes every session on the Sale History page. Your lists are kept.")
    p.Refresh = function() end
end

-- Sale History: Wally's own sales, one entry per login session, inside the settings panel.
local function BuildSaleHistory(p)
    Label(p, "Sale History", "WallyGameFontNormalLarge", 0, 0):SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    p.summary = Muted(Label(p, "", "WallyGameFontHighlightSmall", 0, -24, 560))

    Label(p, "Keep last", "WallyGameFontHighlightSmall", 0, -54)
    local minus = MakeButton(p, "-", 24, 22); minus:SetPoint("TOPLEFT", 58, -48)
    p.keep = Label(p, "", "WallyGameFontHighlight", 90, -53, 30); p.keep:SetJustifyH("CENTER")
    local plus = MakeButton(p, "+", 24, 22); plus:SetPoint("TOPLEFT", 124, -48)
    Label(p, "sessions", "WallyGameFontHighlightSmall", 156, -54)
    local S = ns.Sessions
    minus:SetScript("OnClick", function() S:SetKeep(ns.db.options.keepSessions - S.KEEP_STEP) end)
    plus:SetScript("OnClick", function() S:SetKeep(ns.db.options.keepSessions + S.KEEP_STEP) end)
    Hint(minus, "Keep fewer sessions", "The oldest sessions are deleted right away.")
    Hint(plus, "Keep more sessions", "Up to " .. S.KEEP_MAX .. " login sessions.")
    local clear = MakeButton(p, "Clear all", 90, 26); clear:SetPoint("TOPRIGHT", 0, -46)
    clear:SetScript("OnClick", function() Confirm("Delete Wally's entire sale history?", function() S:Clear() end) end)

    local left = CreateFrame("Frame", nil, p)
    left:SetPoint("TOPLEFT", 0, -84); left:SetPoint("BOTTOMLEFT", 0, 0); left:SetWidth(236)
    Label(left, "Sessions", "WallyGameFontHighlight", 0, 0)
    p.sessionList = CreateRowList(left, -20)

    local right = CreateFrame("Frame", nil, p)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 12, 0); right:SetPoint("BOTTOMRIGHT", 0, 0)
    p.title = Label(right, "", "WallyGameFontHighlight", 0, 0)
    p.title:SetPoint("RIGHT", -26, 0); p.title:SetWordWrap(false)
    p.totals = Muted(Label(right, "", "WallyGameFontHighlightSmall", 0, -16))
    p.totals:SetPoint("RIGHT", -26, 0); p.totals:SetWordWrap(false)
    p.saleList = CreateRowList(right, -36)

    local function SessionName(s)
        if S:IsCurrent(s) then return "|cff55d6beThis session|r" end
        return date("%a %m/%d %H:%M", s.start)
    end

    p.Refresh = function()
        local sessions = ns.db.sessions
        p.keep:SetText(ns.db.options.keepSessions)
        local count, copper = S:Totals()
        p.summary:SetText(("Everything Wally sold for you. %d session%s kept: %d item%s for %s, after buybacks."):format(
            #sessions, #sessions == 1 and "" or "s", count, count == 1 and "" or "s", C.Money(copper)))

        local found
        for _, s in ipairs(sessions) do if s == p.selected then found = true end end
        if not found then p.selected = sessions[1] end

        local rows = {}
        for _, s in ipairs(sessions) do
            rows[#rows + 1] = {
                icon = ns.ICON, text = SessionName(s), selected = s == p.selected,
                detail = ("%d item%s, %s"):format(s.count or 0, (s.count or 0) == 1 and "" or "s", C.Money(s.copper or 0)),
                plainText = s.char or "", onClick = function() p.selected = s; p.Refresh() end,
                hint = ("%s to %s"):format(date("%m/%d %H:%M", s.start), date("%H:%M", s.finish or s.start)),
            }
        end
        p.sessionList:Set(rows, "No sales yet.\n\nWally logs every\nitem it sells here.")

        local s = p.selected
        local sales = {}
        if s then
            p.title:SetText(("%s  -  %s to %s  -  %s"):format(SessionName(s), date("%m/%d %H:%M", s.start), date("%H:%M", s.finish or s.start), s.char or "?"))
            local totals = ("Sold %d item%s for %s"):format(s.count or 0, (s.count or 0) == 1 and "" or "s", C.Money(s.copper or 0))
            if (s.boughtBackCount or 0) > 0 then
                totals = totals .. (", bought back %d (%s)"):format(s.boughtBackCount, C.Money(s.boughtBackCopper or 0))
            end
            p.totals:SetText(totals)
            for i = #s.sales, 1, -1 do
                local sale = s.sales[i]
                local link = sale.link
                sales[#sales + 1] = {
                    icon = link and select(5, C.GetItemInfoInstant(link)) or UNKNOWN_ICON,
                    text = ((sale.count or 1) > 1 and (sale.count .. "x ") or "") .. (link or "?"), link = link,
                    detail = date("%H:%M:%S", sale.t) .. "  -  " .. C.Money(sale.copper or 0) ..
                        (sale.boughtBack and "  -  |cffff8866bought back|r" or ""),
                    actions = link and { { "Never", function() ns.Lists:Add("exclusions", link, "manual") end, "Never sell this again" } } or nil,
                }
            end
        else
            p.title:SetText(""); p.totals:SetText("")
        end
        p.saleList:Set(sales, s and "This session has no sales." or "")
    end
end

-- Bag Sorting: rule order, group order, options, untouched bags and pinned items.
local SORT_OPTIONS = {
    { "junkLast", "Junk goes last", "Everything Wally would sell ends up together." },
    { "fillFromEnd", "Fill from the end of the last bag", "Like Blizzard's sort. Off: start at the backpack." },
    { "bagButton", "Sort button on bags and bank", "Adds a sort button to the bag and bank windows." },
    { "afterSell", "Sort after Wally sells junk", "Closes the gaps that selling leaves." },
    { "onMerchantClose", "Sort when you close a merchant", "Tidies up every time you leave a vendor." },
    { "onBagsClose", "Sort when you close your bags", "Ctrl-right-click an item in your bags to anchor it in place." },
    { "onMailClose", "Sort when you close the mailbox", "Tidies up after taking your mail." },
}
local PIN_TOP = -710

local function ArrowButton(parent, up)
    local b = MakeButton(parent, "", 22, 20)
    local t = b:CreateTexture(nil, "ARTWORK"); t:SetSize(16, 16); t:SetPoint("CENTER", 0, -1)
    t:SetTexture(up and "Interface\\Buttons\\Arrow-Up-Up" or "Interface\\Buttons\\Arrow-Down-Up")
    return b
end

local function OrderRow(parent, x, y, width)
    local r = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    r:SetSize(width, 24); r:SetPoint("TOPLEFT", x, y)
    SetBackdrop(r); r:SetBackdropColor(PAL.row[1], PAL.row[2], PAL.row[3], 1)
    r.down = ArrowButton(r, false); r.down:SetPoint("RIGHT", -2, 0)
    r.up = ArrowButton(r, true); r.up:SetPoint("RIGHT", r.down, "LEFT", -2, 0)
    return r
end

local function BagLabel(bag)
    local name = C.GetBagName(bag)
    if bag == 0 then return "Backpack" end
    if bag == C.BANK then return "Bank" end
    local n = bag > C.NUM_BAGS and (bag - C.NUM_BAGS) or bag
    return n .. ": " .. (name or "empty slot")
end

local function PinCursorItem()
    local cursorType, id, link = GetCursorInfo()
    if cursorType ~= "item" then return false end
    ClearCursor()
    ns.Sorter:Pin(link or id)
    return true
end

-- Auction settings. The checkboxes, duration and stale days are on the main list; this subpage
-- (Options > AddOns > Wally > Auctions) edits the undercut amount, which can be any copper amount.
local AUCTION_OPTION_DEFS = {
    { "learn", "Learn from my auctions", "Watch what you post by hand and cancel." },
    { "autoAccept", "Add learned items silently", "Skip the question and add straight to the Auction List." },
    { "scanFirst", "Scan before first post", "Full Auctionator scan when you first open Wally's tab, unless one ran in the last 4 hours." },
    { "hideTabs", "Hide unused auction tabs", "Hides Buy, Sell, Auctions, Cancelling and Auctionator. Shopping, Selling, Wally and Cart stay." },
}
local DURATIONS = {}
for i, h in ipairs(ns.Compat.AUCTION_HOURS) do DURATIONS[i] = h .. " hours" end

local function BuildAuctionSettings(p)
    Label(p, "Auctions", "WallyGameFontNormalLarge", 0, 0):SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    p.summary = Muted(Label(p, "", "WallyGameFontHighlightSmall", 0, -24, 560))

    p.undercutOn = MakeCheckbox(p, "Undercut Auctionator's price"); p.undercutOn:SetPoint("TOPLEFT", -4, -60)
    p.undercutOn.label:SetFontObject("WallyGameFontHighlight")
    p.undercutOn:SetScript("OnClick", function(self) ns.Value:SetUndercutOn(self:GetChecked()) end)
    Muted(Label(p, "Off: price match, 1 below Auctionator. Prices round down to whole silver, never under vendor price.", "WallyGameFontHighlightSmall", 0, -84, 400))
    p.undercut = MakeEditBox(p, 70, ""); p.undercut:SetPoint("TOPLEFT", 0, -116)
    p.undercut:SetScript("OnEnterPressed", function(self)
        local n = tonumber(self:GetText())
        if n then ns.Value:SetUndercut(n, ns.db.options.auction.undercutMode) end
        self:ClearFocus()
    end)
    Hint(p.undercut, "Undercut amount", "Percent (up to 90) or copper, by the button beside it. Press Enter to save.")
    p.mode = MakeButton(p, "", 90, 26); p.mode:SetPoint("LEFT", p.undercut, "RIGHT", 6, 0)
    p.mode:SetScript("OnClick", function()
        local o = ns.db.options.auction
        ns.Value:SetUndercut(o.undercut, o.undercutMode == "percent" and "copper" or "percent")
    end)

    local manage = MakeButton(p, "Auction lists", 120, 26); manage:SetPoint("TOPLEFT", 0, -160)
    manage:SetScript("OnClick", function() UI:Show("auction") end)
    Hint(manage, "Auction lists", "Auction List, Never Auction and what Wally learned. Also /wally auction.")

    p.Refresh = function()
        local o = ns.db.options.auction
        p.undercutOn:SetChecked(o.undercutOn)
        p.undercut:SetShown(o.undercutOn); p.mode:SetShown(o.undercutOn)
        if not p.undercut:HasFocus() then p.undercut:SetText(tostring(o.undercut or 0)) end
        p.mode.text:SetText(o.undercutMode == "copper" and "copper" or "percent")
        p.summary:SetText(("Wally learns what you post at the auction house and posts it for you from its own tab there, one click per item, at Auctionator's price minus %s."):format(ns.Value:DescribeUndercut()))
    end
end

local function BuildSortSettings(p)
    local S = ns.Sorter
    Label(p, "Bag Sorting", "WallyGameFontNormalLarge", 0, 0):SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    p.summary = Muted(Label(p, "", "WallyGameFontHighlightSmall", 0, -24))
    p.summary:SetPoint("RIGHT", 0, 0)
    local sortBags = MakeButton(p, "Sort bags now", 120, 26); sortBags:SetPoint("TOPLEFT", 0, -58)
    sortBags:SetScript("OnClick", function() S:Start("bags") end)
    p.sortBank = MakeButton(p, "Sort bank now", 120, 26); p.sortBank:SetPoint("LEFT", sortBags, "RIGHT", 8, 0)
    p.sortBank:SetScript("OnClick", function() S:Start("bank") end)
    Hint(p.sortBank, "Sort bank", "Only works while your bank is open.")

    local scroll = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -96); scroll:SetPoint("BOTTOMRIGHT", -26, 0)
    local c = CreateFrame("Frame", nil, scroll); c:SetSize(560, 800)
    scroll:SetScrollChild(c)
    scroll:SetScript("OnSizeChanged", function(_, w) c:SetWidth(w) end)

    -- Left column: rule order and options.
    Label(c, "Sort order", "WallyGameFontHighlight", 0, 0)
    Muted(Label(c, "The top rule decides first. Tick the rules you want.", "WallyGameFontHighlightSmall", 0, -18, 280))
    for i, preset in ipairs(S.PRESETS) do
        local b = MakeButton(c, preset.label, 66, 22); b:SetPoint("TOPLEFT", (i - 1) * 70, -38)
        b:SetScript("OnClick", function() S:ApplyPreset(i) end)
        Hint(b, preset.label .. " preset", preset.hint)
    end
    p.critRows = {}
    for i = 1, #S.CRITERIA do
        local r = OrderRow(c, 0, -68 - (i - 1) * 28, 280)
        r.check = MakeCheckbox(r, ""); r.check:SetPoint("LEFT", -2, 0)
        r.check.label:SetWidth(100); r.check.label:SetJustifyH("LEFT"); r.check.label:SetWordWrap(false)
        r.check:SetScript("OnClick", function(self)
            ns.db.options.sort.criteria[i].on = self:GetChecked() and true or false; ns:Changed()
        end)
        r.check:HookScript("OnEnter", function(self)
            if not r.hint then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(r.hint, 0.85, 0.9, 0.95, true); GameTooltip:Show()
        end)
        r.check:HookScript("OnLeave", function() GameTooltip:Hide() end)
        r.dir = MakeButton(r, "", 88, 20); r.dir:SetPoint("RIGHT", r.up, "LEFT", -6, 0)
        r.dir:SetScript("OnClick", function()
            local e = ns.db.options.sort.criteria[i]; e.desc = not e.desc; ns:Changed()
        end)
        r.up:SetScript("OnClick", function() S:MoveEntry(ns.db.options.sort.criteria, i, -1) end)
        r.down:SetScript("OnClick", function() S:MoveEntry(ns.db.options.sort.criteria, i, 1) end)
        p.critRows[i] = r
    end

    local optTop = -68 - #S.CRITERIA * 28 - 14
    Label(c, "Options", "WallyGameFontHighlight", 0, optTop)
    p.optChecks = {}
    for i, d in ipairs(SORT_OPTIONS) do
        local y = optTop - 20 - (i - 1) * 44
        local b = MakeCheckbox(c, d[2]); b:SetPoint("TOPLEFT", -4, y)
        b:SetScript("OnClick", function(self)
            ns.db.options.sort[d[1]] = self:GetChecked() and true or false
            S:RefreshButtons(); ns:Changed()
        end)
        Muted(Label(c, d[3], "WallyGameFontHighlightSmall", 27, y - 24, 255))
        p.optChecks[d[1]] = b
    end

    -- Right column: group order and bags to leave alone.
    local R = 300
    Label(c, "Group order", "WallyGameFontHighlight", R, 0)
    Muted(Label(c, "Used by the Group rule.", "WallyGameFontHighlightSmall", R, -18, 260))
    p.catRows = {}
    for i = 1, #S.CATEGORIES do
        local r = OrderRow(c, R, -38 - (i - 1) * 26, 260)
        r.text = Label(r, "", "WallyGameFontHighlightSmall", 8, -6)
        r.up:SetScript("OnClick", function() S:MoveEntry(ns.db.options.sort.categories, i, -1) end)
        r.down:SetScript("OnClick", function() S:MoveEntry(ns.db.options.sort.categories, i, 1) end)
        p.catRows[i] = r
    end

    local bagTop = -38 - #S.CATEGORIES * 26 - 14
    Label(c, "Don't move items in", "WallyGameFontHighlight", R, bagTop)
    p.bagChecks = {}
    local function BagChecks(title, bags, top)
        Muted(Label(c, title, "WallyGameFontHighlightSmall", R, top))
        for i, bag in ipairs(bags) do
            local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
            local b = MakeCheckbox(c, "")
            b:SetPoint("TOPLEFT", R - 4 + col * 132, top - 14 - row * 24)
            b.label:SetWidth(100); b.label:SetJustifyH("LEFT"); b.label:SetWordWrap(false)
            b.bag = bag
            b:SetScript("OnClick", function(self) S:SetIgnored(bag, self:GetChecked()) end)
            Hint(b, "Leave this bag alone", "Sorting won't move anything in or out of it.")
            p.bagChecks[#p.bagChecks + 1] = b
        end
        return top - 14 - math.ceil(#bags / 2) * 24 - 10
    end
    local bankTop = BagChecks("Bags", C.BagList("bags"), bagTop - 20)
    local valTop = BagChecks("Bank", C.BagList("bank"), bankTop) - 8

    -- Left column, under Options: which side of the bag search box the sort button sits on.
    local sideTop = optTop - 20 - #SORT_OPTIONS * 44 - 6
    Label(c, "Bag button:", "WallyGameFontHighlightSmall", 0, sideTop - 5)
    p.sideButtons = {}
    for i, side in ipairs({ "left", "right" }) do
        local b = MakeButton(c, side == "left" and "Left of search" or "Right of search", 100, 22)
        b:SetPoint("TOPLEFT", 70 + (i - 1) * 104, sideTop)
        b:SetScript("OnClick", function()
            ns.db.options.sort.buttonSide = side
            S:RefreshButtons(); ns:Changed()
        end)
        Hint(b, "Sort button position", "Where the sort button sits next to the search box on your backpack.")
        p.sideButtons[side] = b
    end

    -- Right column, under the bags: valuables.
    Label(c, "Valuables", "WallyGameFontHighlight", R, valTop)
    Label(c, "Protect the", "WallyGameFontHighlightSmall", R, valTop - 26)
    local minus = MakeButton(c, "-", 24, 22); minus:SetPoint("TOPLEFT", R + 70, valTop - 20)
    p.protectTop = Label(c, "", "WallyGameFontHighlight", R + 98, valTop - 25, 30); p.protectTop:SetJustifyH("CENTER")
    local plus = MakeButton(c, "+", 24, 22); plus:SetPoint("TOPLEFT", R + 132, valTop - 20)
    Label(c, "top stacks", "WallyGameFontHighlightSmall", R + 164, valTop - 26)
    minus:SetScript("OnClick", function() ns.Value:SetProtectTop(ns.db.options.sort.protectTop - 1) end)
    plus:SetScript("OnClick", function() ns.Value:SetProtectTop(ns.db.options.sort.protectTop + 1) end)
    Hint(minus, "Protect fewer", "Your most valuable stacks sort first and are never sold as junk. 0 turns this off.")
    Hint(plus, "Protect more", "Up to 40 stacks. Worth comes from Auctionator prices, or Wally's estimate.")
    local VALUE_OPTIONS = {
        { "protectRare", "Rare and better are always protected", "Blue and purple items, whatever their rank." },
        { "reagentsByWorth", "Order reagents by worth", "Most valuable trade goods first, by tier and rarity." },
    }
    for i, d in ipairs(VALUE_OPTIONS) do
        local y = valTop - 50 - (i - 1) * 44
        local b = MakeCheckbox(c, d[2]); b:SetPoint("TOPLEFT", R - 4, y)
        b:SetScript("OnClick", function(self) ns.db.options.sort[d[1]] = self:GetChecked() and true or false; ns:Changed() end)
        Muted(Label(c, d[3], "WallyGameFontHighlightSmall", R + 27, y - 24, 240))
        p.optChecks[d[1]] = b
    end
    p.worthSource = Muted(Label(c, "", "WallyGameFontHighlightSmall", R, valTop - 142, 260))

    -- Full width: pinned items.
    Label(c, "Pinned first", "WallyGameFontHighlight", 0, PIN_TOP)
    Muted(Label(c, "These always take the first slots, in this order. Drag an item onto the box, shift-click one, or type its name.",
        "WallyGameFontHighlightSmall", 0, PIN_TOP - 18, 540))
    p.pinBox = MakeEditBox(c, 260, "Item name or link")
    p.pinBox:SetPoint("TOPLEFT", 0, PIN_TOP - 50)
    local function PinTyped()
        local text = ns.Trim(p.pinBox:GetText())
        if text ~= "" then S:Pin(text); p.pinBox:SetText("") end
        p.pinBox:ClearFocus()
    end
    p.pinBox:SetScript("OnEnterPressed", PinTyped)
    p.pinBox:SetScript("OnReceiveDrag", PinCursorItem)
    p.pinBox:SetScript("OnMouseDown", function(self) if not PinCursorItem() then self:SetFocus() end end)
    local pin = MakeButton(c, "Pin", 70, 26); pin:SetPoint("LEFT", p.pinBox, "RIGHT", 8, 0)
    pin:SetScript("OnClick", function() if not PinCursorItem() then PinTyped() end end)

    local holder = CreateFrame("Frame", nil, c)
    holder:SetPoint("TOPLEFT", 0, PIN_TOP - 86); holder:SetPoint("TOPRIGHT", c, "TOPRIGHT", 0, PIN_TOP - 86)
    holder:SetHeight(1)
    local pinList = { content = holder, rows = {}, onDrop = PinCursorItem }
    p.pinEmpty = Muted(Label(c, "Nothing pinned. Your hearthstone is a good start.", "WallyGameFontHighlightSmall", 0, PIN_TOP - 92))

    p.Refresh = function()
        local opt = ns.db.options.sort
        p.summary:SetText(S:Describe())
        p.sortBank:SetAlpha(S.bankOpen and 1 or 0.5)
        for i, r in ipairs(p.critRows) do
            local e = opt.criteria[i]
            local info = e and S:CriterionInfo(e.key)
            if info then
                r.check:SetChecked(e.on)
                r.check.label:SetText(info.label)
                if e.on then r.check.label:SetTextColor(1, 1, 1) else Muted(r.check.label) end
                r.dir.text:SetText(info.dir[e.desc and 2 or 1]); r.dir:SetAlpha(e.on and 1 or 0.45)
                r.hint = info.hint
                r.up:SetAlpha(i > 1 and 1 or 0.3); r.down:SetAlpha(i < #opt.criteria and 1 or 0.3)
            end
        end
        for i, r in ipairs(p.catRows) do
            r.text:SetText(i .. ".  " .. S:CategoryLabel(opt.categories[i]))
            r.up:SetAlpha(i > 1 and 1 or 0.3); r.down:SetAlpha(i < #opt.categories and 1 or 0.3)
        end
        for key, b in pairs(p.optChecks) do b:SetChecked(opt[key]) end
        for side, b in pairs(p.sideButtons) do
            if (opt.buttonSide or "left") == side then b:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
            else b:SetBackdropBorderColor(PAL.border[1], PAL.border[2], PAL.border[3], 1) end
        end
        p.protectTop:SetText(opt.protectTop or 0)
        p.worthSource:SetText(ns.Value:HasAuctionator() and "Worth uses Auctionator's auction prices, with estimates for items it hasn't scanned."
            or "Auctionator not found: worth is estimated from rarity, tier and kind of item.")
        for _, b in ipairs(p.bagChecks) do
            b:SetChecked(S:IsIgnored(b.bag)); b.label:SetText(BagLabel(b.bag))
        end

        for i, pinEntry in ipairs(opt.pinned) do
            local row = pinList.rows[i] or NewRow(pinList)
            pinList.rows[i] = row
            local key = pinEntry.key
            LayoutRow(row, {
                icon = IconFor(pinEntry), text = EntryText(pinEntry, key), link = pinEntry.link,
                plainText = pinEntry.name or key,
                actions = {
                    { "Remove", function() S:Unpin(key) end },
                    { "Down", function() S:MoveEntry(opt.pinned, i, 1) end, "Move down" },
                    { "Up", function() S:MoveEntry(opt.pinned, i, -1) end, "Move up" },
                },
                onRightClick = function() S:Unpin(key) end,
                hint = "Right-click: unpin",
            }, i)
        end
        for i = #opt.pinned + 1, #pinList.rows do pinList.rows[i]:Hide(); pinList.rows[i].data = nil end
        p.pinEmpty:SetShown(#opt.pinned == 0)
        c:SetHeight(-PIN_TOP + 100 + #opt.pinned * (ROW_H + ROW_GAP))
    end
end

-- ---------------------------------------------------------------------------
-- Options > AddOns > Wally, built with the shared OptionsPage.lua (addons/shared): the standard
-- list, plus subpages for what a list can't hold (Bag Sorting, Lists, Sale History, Auctions).
-- The window's Settings tab, the auction house tab and /wally change the same options
-- (ns:SetOption), so every UI shows the same value.
-- ---------------------------------------------------------------------------

local SUBPAGES = { history = "Sale History", sorting = "Bag Sorting", auctions = "Auctions", lists = "Lists" }
local views = {} -- subpage name -> its view (the existing builders' frames)

-- A subpage that hosts one of the builders above: build(view) once, view.Refresh() each time.
local function Hosted(name, build)
    return {
        name = name,
        build = function(f)
            local v = CreateFrame("Frame", nil, f)
            v:SetPoint("TOPLEFT", 16, -16); v:SetPoint("BOTTOMRIGHT", -16, 16)
            views[name] = v
            build(v)
        end,
        refresh = function() local v = views[name]; if v and v.Refresh then v.Refresh() end end,
    }
end

UI.page = ns.NewOptionsPage({ name = "Wally", icon = true, build = function(p)
    p:Header("Wally")
    for _, d in ipairs(OPTION_DEFS) do
        p:Check({ path = "db.options." .. d[1], label = d[2], tooltip = d[3] })
        if d[1] == "autoRepair" then
            p:Check({ path = "db.options.guildRepair", label = "Repair with guild funds",
                tooltip = "When your guild lets you, repairs are paid from the guild bank first." })
        end
    end
    p:Check({ path = "db.options.bags.window", label = "Wally's bag window",
        tooltip = "Your backpack, bags and reagent bag in one window in Wally's style, in place of the game's bag windows. Bank bags stay the game's.",
        apply = function() ns.BagWindow:Apply() end })
    p:Slider({ path = "db.options.bags.columns", label = "Bag window columns", min = 8, max = 20, step = 1,
        format = function(v) return ("%d slots wide"):format(v) end,
        apply = function() ns.BagWindow:Relayout() end })
    p:Check({ path = "char.minimap.hide", invert = true, label = "Minimap button", tooltip = "Wally's minimap button (/wally minimap).",
        apply = function() if ns.MinimapButton then ns.MinimapButton:Refresh() end end })
    p:Slider({ path = "db.options.threshold", label = "Ask after this habit score", min = 0.2, max = 0.95, step = 0.05, scale = 100,
        set = function(v) ns:SetOption("db.options.threshold", math.floor(v * 20 + 0.5) / 20) end,
        format = function(v) return ("%d%%: about %d sales"):format(v, SalesToReach(v / 100)) end,
        tooltip = "Wally asks to add an item to the Junk List once your habit of selling it reaches this score: about that many sales of a single item, or fewer for full stacks." })
    p:Slider({ path = "db.options.keepSessions", label = "Sale history: keep last", min = ns.Sessions.KEEP_MIN, max = ns.Sessions.KEEP_MAX,
        step = ns.Sessions.KEEP_STEP, format = function(v) return ("%d sessions"):format(v) end,
        apply = function() ns.Sessions:Trim() end,
        tooltip = "Login sessions kept on the Sale History page. The oldest sessions are deleted right away." })
    p:Button({ label = "Sale History", text = "Open", fn = function() UI.page:Open(SUBPAGES.history) end,
        tooltip = "Everything Wally has sold, grouped by login session (/wally history)." })

    if ns:AuctionsEnabled() then
        p:Header("Auctions")
        for _, d in ipairs(AUCTION_OPTION_DEFS) do
            p:Check({ path = "db.options.auction." .. d[1], label = d[2], tooltip = d[3] })
        end
        p:Check({ path = "db.options.auction.undercutOn", label = "Undercut Auctionator's price",
            tooltip = "Off: price match, 1 below Auctionator. Prices round down to whole silver, never under vendor price. "
                .. "Set the amount on the Auctions page under this one, or on Wally's auction house tab." })
        p:Dropdown({ path = "db.options.auction.undercutMode", label = "Undercut by",
            choices = { { "percent", "Percent" }, { "copper", "Copper" } },
            tooltip = "Undercut Auctionator's price by a percentage, or by a fixed amount of copper.",
            apply = function(mode)
                local o = ns.db.options.auction
                if mode == "percent" and (tonumber(o.undercut) or 0) > 90 then o.undercut = 90 end
            end })
        p:Button({ label = "Undercut amount", text = "Edit", fn = function() UI.page:Open(SUBPAGES.auctions) end,
            tooltip = "The amount to undercut by, in percent or copper (/wally auction undercut <number>[%])." })
        p:Dropdown({ path = "db.options.auction.duration", label = "Default duration",
            choices = { { 1, DURATIONS[1] }, { 2, DURATIONS[2] }, { 3, DURATIONS[3] } },
            tooltip = "Until you post an item by hand; then Wally uses the duration you chose." })
        p:Slider({ path = "db.options.auction.staleDays", label = "Stale price after", min = 0, max = 30, step = 1,
            format = function(v) return ("%d days"):format(v) end,
            tooltip = "Auctionator prices older than this many days are shown in yellow." })
    end

    p:Subpage(Hosted(SUBPAGES.sorting, BuildSortSettings))
    p:Subpage(Hosted(SUBPAGES.lists, BuildListTools))
    p:Subpage(Hosted(SUBPAGES.history, BuildSaleHistory))
    if ns:AuctionsEnabled() then p:Subpage(Hosted(SUBPAGES.auctions, BuildAuctionSettings)) end
end })

-- Opens Options > AddOns > Wally, or one of its subpages: "history", "sorting", "auctions", "lists".
function UI:OpenSettings(view)
    win:Hide()
    return self.page:Open(SUBPAGES[view or ""])
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------

local TABS = {
    { "junk", "Junk List", "INV_Misc_Coin_02" },
    { "never", "Never Sell", "INV_Shield_06" },
    { "learning", "Learning", "INV_Misc_Book_09" },
    { "bags", "In Bags", "INV_Misc_Bag_08" },
    { "history", "History", "INV_Misc_PocketWatch_01" },
    { "auction", "Auctions", "INV_Misc_Coin_01", when = function() return ns:AuctionsEnabled() end },
    { "settings", "Settings", "INV_Misc_Gear_01", onClick = function() UI:OpenSettings() end,
        hint = { "Settings", "Opens Options > AddOns > Wally." } },
}

win = ns.NewWindow({
    name = "WallyWindow", title = "Wally", subtitle = "Learns your junk so you don't have to",
    tabs = TABS, active = "junk", pluginsBefore = "settings",
    refresh = function() UI:Refresh() end,
    -- With plugin tabs there's no room left for the tips.
    sideNote = function(w)
        if #w.plugins == 0 then
            return "Drag items onto a list\nto add them.\n\nShift-click links into\nthe add box.\n\nAt a merchant, drop items\non the Wally button."
        end
    end,
    build = function()
        CreateListPage("junk", "inclusions")
        CreateListPage("never", "exclusions")
        CreateLearningPage(); CreateBagsPage(); CreateHistoryPage()
        if ns:AuctionsEnabled() then CreateAuctionPage() end
    end,
})
UI.window = win

-- Tabs added by plugins (API.lua): builder(page), shown before Settings. Texture paths work as icons.
function UI:AddPluginTab(key, label, icon, builder)
    return win:AddTab({ key, label, icon, build = builder }) -- false once the window is built: shows after /reload
end

function UI:RefreshPage(name) win:RefreshPage(name) end

function UI:Refresh()
    if not ns.db then return end
    if self.page then self.page:Refresh() end
    win:Refresh()
end

function UI:Toggle()
    if not ns.db then return end
    win:Toggle()
end

function UI:Show(tab)
    if not ns.db then return end
    win:Build()
    win:Show(tab and win.pages[tab] and tab or nil)
end

function UI:ActiveTab() return win:IsShown() and win.active or nil end

-- Shift-clicking an item while an add box has focus inserts its link there.
local function InsertLink(link)
    if not link then return end
    local pinBox = views[SUBPAGES.sorting] and views[SUBPAGES.sorting].pinBox
    if pinBox and pinBox:HasFocus() then pinBox:SetText(link); return true end
    if not win:IsShown() then return end
    for _, name in ipairs({ "junk", "never", "auction" }) do
        local box = win.pages[name] and win.pages[name].addBox
        if box and box:HasFocus() then box:SetText(link); return true end
    end
end
if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", InsertLink) end

ns:On("BAG_UPDATE_DELAYED", function() if win.active == "bags" or win.active == "learning" then UI:Refresh() end end)
ns:On("MERCHANT_SHOW", function() UI:Refresh() end)
ns:On("MERCHANT_CLOSED", function() UI:Refresh() end)
ns:On("BANKFRAME_OPENED", function() UI:Refresh() end)
ns:On("BANKFRAME_CLOSED", function() UI:Refresh() end)
