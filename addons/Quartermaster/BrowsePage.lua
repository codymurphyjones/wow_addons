local _, ns = ...

-- Browse: the Blizzard Browse tab's controls (name, level range, rarity, usable, categories,
-- pages of results) over Auctionator's known items, plus an Advanced row in the style of
-- Auctionator's advanced search.
local W = ns.Widgets
local ACCENT, MUTED = W.ACCENT, W.MUTED
local SetBackdrop, Label, Muted, MakeButton, Hint = W.SetBackdrop, W.Label, W.Muted, W.MakeButton, W.Hint
local MakeEditBox, MakeNumberBox, MakeCheckbox = W.MakeEditBox, W.MakeNumberBox, W.MakeCheckbox

local PER_PAGE = 50
local CAT_W = 150

local function AgeText(days)
    if not days then return "" end
    if days < 1 then return "today" end
    return math.floor(days) .. "d ago"
end

local function Build(p)
    local state = { page = 1, sortKey = "name", desc = false, filters = {}, results = {} }

    Label(p, "Browse", "QuartermasterGameFontNormalLarge", 0, 0)
    p.summary = Muted(Label(p, "", "QuartermasterGameFontHighlightSmall", 0, -24, 620))

    -- Filters: the shared bar (SearchBar.lua); the category tree below feeds it.
    local qty
    local filters = W.MakeFilterBar(p, {
        mode = "offline", categories = "tree",
        onSearch = function(keepPage) p.SearchNow(keepPage) end,
        onLayout = function() if p.PlaceBody then p.PlaceBody() end end,
        onQuantity = function(q) if qty then qty:SetValue(q) end end,
        onReset = function() state.selected = nil end,
        onCategory = function(classID, subClassID) if p.cats then p.cats:Set(classID, subClassID) end end,
    })
    filters:SetPoint("TOPLEFT", 0, -46); filters:SetPoint("TOPRIGHT", 0, -46)

    -- Body: category tree on the left, results on the right, page/add bar at the bottom.
    local body = CreateFrame("Frame", nil, p)
    body:SetPoint("BOTTOMRIGHT", 0, 0)
    local function PlaceBody()
        body:ClearAllPoints()
        body:SetPoint("TOPLEFT", 0, -46 - filters:Height() - 8)
        body:SetPoint("BOTTOMRIGHT", 0, 0)
    end
    PlaceBody()
    p.PlaceBody = PlaceBody

    -- Category tree (Widgets.lua); the filter bar holds the chosen category.
    local cats = W.MakeCategoryTree(body, CAT_W, function() return ns.Search:Categories() end, function(classID, subClassID)
        filters:SetCategory(classID, subClassID)
        state.page = 1
        p.SearchNow()
    end)
    cats:SetPoint("TOPLEFT", 0, 0); cats:SetPoint("BOTTOMLEFT", 0, 40)
    p.cats = cats

    local right = CreateFrame("Frame", nil, body)
    right:SetPoint("TOPLEFT", CAT_W + 10, 0); right:SetPoint("BOTTOMRIGHT", 0, 40)
    local headers = W.MakeColumnHeaders(right, {
        { "name", "Name", nil }, { "level", "Lvl", 46 }, { "ilvl", "iLvl", 46 }, { "price", "Market", 92 }, { "age", "Seen", 62 },
    }, function(key, desc) state.sortKey, state.desc = key, desc; p.SearchNow(true) end)
    headers:SetPoint("TOPLEFT", 0, 0); headers:SetPoint("TOPRIGHT", -26, 0)
    -- Name stretches; the fixed columns sit at the right.
    do
        local b = headers.buttons
        b[1]:ClearAllPoints(); b[1]:SetPoint("LEFT", 0, 0); b[1]:SetPoint("RIGHT", b[2], "LEFT", -2, 0)
        b[5]:ClearAllPoints(); b[5]:SetPoint("RIGHT", 0, 0)
        b[4]:ClearAllPoints(); b[4]:SetPoint("RIGHT", b[5], "LEFT", -2, 0)
        b[3]:ClearAllPoints(); b[3]:SetPoint("RIGHT", b[4], "LEFT", -2, 0)
        b[2]:ClearAllPoints(); b[2]:SetPoint("RIGHT", b[3], "LEFT", -2, 0)
    end
    local list = W.CreateRowList(right, -24, { rowHeight = 30 })
    list.onDrop = function() W.AddCursorItem() end

    -- Bottom bar: pages on the left (like the Browse tab), add-to-list on the right.
    local bar = CreateFrame("Frame", nil, body)
    bar:SetPoint("BOTTOMLEFT", 0, 0); bar:SetPoint("BOTTOMRIGHT", 0, 0); bar:SetHeight(32)
    local prev = MakeButton(bar, "< Prev", 60, 26); prev:SetPoint("LEFT", 0, 0)
    local pageText = Muted(bar:CreateFontString(nil, "OVERLAY", "QuartermasterGameFontHighlightSmall"))
    pageText:SetPoint("LEFT", prev, "RIGHT", 8, 0); pageText:SetWidth(84)
    local nextBtn = MakeButton(bar, "Next >", 60, 26); nextBtn:SetPoint("LEFT", pageText, "RIGHT", 8, 0)
    -- Where Add puts things: any list, or a prebuilt list's targets.
    local targetPicker = W.MakeDropdown(bar, 150, function()
        local opts = { { nil, "Shopping lists", header = true } }
        for i, l in ipairs(ns.Lists:All()) do opts[#opts + 1] = { "list:" .. i, l.name } end
        local all = ns.Prebuilt:All()
        if #all.char > 0 then opts[#opts + 1] = { nil, "Prebuilt (this character)", header = true } end
        for _, t in ipairs(all.char) do opts[#opts + 1] = { "template:" .. t.id, t.name } end
        if #all.account > 0 then opts[#opts + 1] = { nil, "Prebuilt (account)", header = true } end
        for _, t in ipairs(all.account) do opts[#opts + 1] = { "template:" .. t.id, t.name } end
        return opts
    end, function(value)
        local kind, key = value:match("^(%a+):(.+)$")
        if kind == "list" then ns.Lists:SetAddTarget("list", tonumber(key)) else ns.Lists:SetAddTarget("template", key) end
    end)
    targetPicker:SetPoint("RIGHT", 0, 0)
    Hint(targetPicker, "Add to", "Choose the shopping list or prebuilt list that Add (and the + on each row) puts items on. For a prebuilt list the Qty raises its target.")
    local addBtn = MakeButton(bar, "Add to", 60, 26); addBtn:SetPoint("RIGHT", targetPicker, "LEFT", -6, 0)
    qty = MakeNumberBox(bar, 48, "1"); qty:SetPoint("RIGHT", addBtn, "LEFT", -6, 0)
    local qtyLabel = Muted(bar:CreateFontString(nil, "OVERLAY", "QuartermasterGameFontHighlightSmall"))
    qtyLabel:SetPoint("RIGHT", qty, "LEFT", -6, 0); qtyLabel:SetText("Qty")
    local selText = bar:CreateFontString(nil, "OVERLAY", "QuartermasterGameFontHighlightSmall")
    selText:SetPoint("LEFT", nextBtn, "RIGHT", 14, 0); selText:SetPoint("RIGHT", qtyLabel, "LEFT", -10, 0)
    selText:SetJustifyH("RIGHT"); selText:SetWordWrap(false)

    local function Qty() return math.max(1, math.floor(qty:GetValue() or 1)) end
    local function AddEntry(e)
        if e then ns.Lists:AddItem(e.id, Qty()) end
    end

    -- -----------------------------------------------------------------------
    local function ReadFilters() return filters:Read() end
    p.RefreshCategories = function() cats:Refresh() end

    local function ShowPage()
        local results = state.results
        local pages = math.max(1, math.ceil(#results / PER_PAGE))
        state.page = math.min(math.max(1, state.page), pages)
        local target, targetKind = ns.Lists:AddTarget()
        local items = {}
        local first = (state.page - 1) * PER_PAGE
        for i = first + 1, math.min(#results, first + PER_PAGE) do
            local e = results[i]
            local detail = {}
            if e.reqLevel and e.reqLevel > 1 then detail[#detail + 1] = "Lvl " .. e.reqLevel end
            if e.ilvl and e.ilvl > 1 then detail[#detail + 1] = "iLvl " .. e.ilvl end
            local sub = e.classID and e.subClassID and ns.Compat.GetSubClassName(e.classID, e.subClassID)
            if sub then detail[#detail + 1] = sub end
            if e.equipLoc and _G[e.equipLoc] and _G[e.equipLoc] ~= "" then detail[#detail + 1] = _G[e.equipLoc] end
            local onList = ns.Lists:Find(target, e.id)
            items[#items + 1] = {
                icon = W.IconFor(e), link = e.link,
                text = e.name and W.QualityName(e.name, e.quality) or ("|cff8fa3b3Loading item " .. e.id .. "...|r"),
                detail = table.concat(detail, "  ·  ") .. (onList and ("  ·  |cff55d6be%d on list|r"):format(onList.qty) or ""),
                right = W.Money(e.price) .. "  |cff8fa3b3" .. AgeText(e.ageDays) .. "|r",
                selected = state.selected == e,
                hint = "Click to select. Right-click to add the Qty to your list. Shift-click to link.",
                onClick = function() state.selected = e; ShowPage() end,
                onRightClick = function() AddEntry(e) end,
                actions = { { "+", function() AddEntry(e) end, "Add the Qty to " .. target.name } },
            }
        end
        list:Set(items, ns.Catalog:HasData()
            and "No known items match. Auctionator only knows items it has seen at the auction house."
            or "Auctionator has no prices yet. Run its full scan at the auction house.")
        pageText:SetText(("Page %d of %d"):format(state.page, pages))
        prev:SetEnabled(state.page > 1); prev:SetAlpha(state.page > 1 and 1 or 0.4)
        nextBtn:SetEnabled(state.page < pages); nextBtn:SetAlpha(state.page < pages and 1 or 0.4)
        local sel = state.selected
        selText:SetText(sel and ((sel.link or sel.name or "") .. "  " .. W.Money(sel.price)) or "|cff8fa3b3Select an item|r")
        targetPicker:SetValue(nil, (targetKind == "template" and "|cff55d6be" or "") .. target.name .. (targetKind == "template" and "|r" or ""))
        addBtn:SetEnabled(sel ~= nil); addBtn:SetAlpha(sel and 1 or 0.5)

        local pending = ns.Catalog:Pending()
        p.summary:SetText(("%d of %d known items match.%s"):format(#results, #ns.Catalog.entries,
            pending > 0 and ("  |cffffd24dLoading item data (%d left)...|r"):format(pending) or ""))
    end

    -- keepPage: re-sorting or new item data shouldn't send you back to page 1.
    function p.SearchNow(keepPage)
        state.filters = ReadFilters()
        state.results = ns.Search:Run(state.filters, state.sortKey, state.desc)
        if not keepPage then state.page = 1; list:ScrollToTop() end
        ShowPage()
    end

    function p.SearchFor(text)
        filters.name:SetText(text); p.SearchNow()
    end

    prev:SetScript("OnClick", function() state.page = state.page - 1; list:ScrollToTop(); ShowPage() end)
    nextBtn:SetScript("OnClick", function() state.page = state.page + 1; list:ScrollToTop(); ShowPage() end)
    addBtn:SetScript("OnClick", function() AddEntry(state.selected) end)

    p.Refresh = function()
        if not ns.Catalog.built then ns.Catalog:Build() end
        cats:Refresh()
        p.SearchNow(true)
    end
    p.OnCatalogChanged = function()
        cats:Refresh()
        p.SearchNow(true)
    end
end

ns.UI:RegisterPage("browse", Build)
