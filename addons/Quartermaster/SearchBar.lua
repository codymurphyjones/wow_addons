local _, ns = ...
local PAL = ns.Palette

-- The one filter bar used everywhere: the Browse page (offline, Auctionator's prices), the Auction
-- tab and the Cart's Find panel (live auction house). Same controls as the Blizzard Browse tab on
-- the first row, Auctionator's advanced search fields behind Advanced.
--
-- W.MakeFilterBar(parent, opts)
--   opts.mode       "offline" (searches as you type; Max age and Priced only) or "live" (Enter / Search)
--   opts.categories "tree" (the page shows its own tree and calls bar:SetCategory) or "dropdown"
--   opts.onSearch(keepPage)  opts.onLayout()  opts.onQuantity(qty)  opts.onReset()
--   opts.onCategory(classID, subClassID)  when the category changes (Load, Reset), so a tree can follow
--   opts.onPickItem(entry)  a suggestion was picked (the box already holds it as an exact search);
--                           without it, picking just searches
-- The name box suggests matching item names as you type (W.AttachSuggestions below).
-- bar:Read() -> filters   bar:Load(f)   bar:Reset()   bar:SetCategory(classID, subClassID)   bar:Height()
local W = ns.Widgets
local Muted, MakeButton, Hint = W.Muted, W.MakeButton, W.Hint
local MakeEditBox, MakeNumberBox, MakeCheckbox = W.MakeEditBox, W.MakeNumberBox, W.MakeCheckbox

local ROW = 32

local function QualityLabel(q)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    return (c and c.hex or "") .. (_G["ITEM_QUALITY" .. q .. "_DESC"] or ("Quality " .. q)) .. "|r"
end

function W.MakeFilterBar(parent, opts)
    opts = opts or {}
    local live = opts.mode == "live"
    local catRow = opts.categories == "dropdown" -- class/type dropdowns get a row of their own
    local baseRows = catRow and 2 or 1
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(baseRows * ROW - 6)
    bar.classID, bar.subClassID = nil, nil

    local function Search(keepPage) if opts.onSearch then opts.onSearch(keepPage) end end

    -- Row 1: the Browse tab's controls.
    local name = MakeEditBox(bar, live and 200 or 140, live and "Search the auction house" or "Item name")
    name:SetPoint("TOPLEFT", 0, 0)
    Hint(name, "Item name", "Matches any part of the name. Put it in quotes for an exact match, e.g. \"Linen Cloth\". Shift-click an item link here to look it up."
        .. (live and "\nPress Enter to search." or ""))
    bar.name = name
    local level = W.MakeRangeBox(bar, "Lvl", 30)
    level:SetPoint("LEFT", name, "RIGHT", 8, 0)
    local rarity = W.MakeDropdown(bar, 92, function()
        local o = { { -1, "All rarities" } }
        for q = 0, 5 do o[#o + 1] = { q, QualityLabel(q) } end
        return o
    end, function() if not live then Search() end end)
    rarity:SetPoint("LEFT", level, "RIGHT", 6, 0)
    rarity:SetValue(-1, "All rarities")
    Hint(rarity, "Rarity", "This quality and better, like the Browse tab.")
    local usable = MakeCheckbox(bar, "Usable")
    usable:SetPoint("LEFT", rarity, "RIGHT", 2, 0)
    usable:SetScript("OnClick", function() if not live then Search() end end)
    Hint(usable, "Usable items", "Hide anything your character can't use.")

    local advancedBtn = MakeButton(bar, "Advanced", 68, 26)
    advancedBtn:SetPoint("TOPRIGHT", 0, 0)
    local reset = MakeButton(bar, "Reset", 46, 26)
    reset:SetPoint("RIGHT", advancedBtn, "LEFT", -4, 0)
    local search = MakeButton(bar, "Search", 56, 26)
    search:SetPoint("RIGHT", reset, "LEFT", -4, 0)
    bar.searchButton = search

    -- Category dropdowns (class, then subclass) when the page has no tree of its own.
    local catDrop, subDrop
    local function CategoryTree() return live and ns.Search:AllCategories() or ns.Search:Categories() end
    local function FindClass(classID)
        for _, c in ipairs(CategoryTree()) do if c[1] == classID then return c end end
    end
    local function UpdateCategoryLabels()
        if not catDrop then return end
        local c = bar.classID and FindClass(bar.classID)
        catDrop:SetValue(bar.classID or -1, c and c[2] or "All categories")
        local subName = bar.subClassID and ns.Compat.GetSubClassName(bar.classID, bar.subClassID)
        subDrop:SetValue(bar.subClassID or -1, subName or "All types")
        local hasSubs = c and #c.subs > 0
        subDrop:SetEnabled(hasSubs and true or false); subDrop:SetAlpha(hasSubs and 1 or 0.4)
    end
    if catRow then
        local catLabel = Muted(bar:CreateFontString(nil, "OVERLAY", "QuartermasterGameFontHighlightSmall"))
        catLabel:SetPoint("TOPLEFT", 0, -ROW - 7); catLabel:SetText("Category")
        catDrop = W.MakeDropdown(bar, 150, function()
            local o = { { -1, "All categories" } }
            for _, c in ipairs(CategoryTree()) do o[#o + 1] = { c[1], c[2] } end
            return o
        end, function(value)
            bar.classID = value ~= -1 and value or nil
            bar.subClassID = nil
            UpdateCategoryLabels()
            if not live then Search() end
        end)
        catDrop:SetPoint("TOPLEFT", catLabel:GetStringWidth() + 8, -ROW)
        subDrop = W.MakeDropdown(bar, 150, function()
            local o = { { -1, "All types" } }
            local c = bar.classID and FindClass(bar.classID)
            for _, s in ipairs(c and c.subs or {}) do o[#o + 1] = { s[1], s[2] } end
            return o
        end, function(value)
            bar.subClassID = value ~= -1 and value or nil
            UpdateCategoryLabels()
            if not live then Search() end
        end)
        subDrop:SetPoint("LEFT", catDrop, "RIGHT", 4, 0)
        Hint(catDrop, "Category", "Item class, like the Browse tab's category list.")
        Hint(subDrop, "Type", "Item subclass within the category.")
        UpdateCategoryLabels()
    end

    -- Advanced rows (Auctionator's advanced search fields).
    local adv = CreateFrame("Frame", nil, bar)
    adv:SetPoint("TOPLEFT", 0, -ROW * baseRows); adv:SetPoint("TOPRIGHT", 0, -ROW * baseRows)
    adv:SetHeight(ROW * 2 - 6); adv:Hide()
    local ilvl = W.MakeRangeBox(adv, "iLvl", 34)
    ilvl:SetPoint("TOPLEFT", 0, 0)
    local price = W.MakeRangeBox(adv, "Price (g)", 40)
    price:SetPoint("LEFT", ilvl, "RIGHT", 10, 0)
    Hint(price.min, "Price per item", live and "What the auction house asks for one, in gold." or "Auctionator's market price for one, in gold.")
    local anchor = price
    local maxAge, priced
    if not live then
        local ageLabel = Muted(adv:CreateFontString(nil, "OVERLAY", "QuartermasterGameFontHighlightSmall"))
        ageLabel:SetPoint("LEFT", price, "RIGHT", 10, 0); ageLabel:SetText("Max age")
        maxAge = MakeNumberBox(adv, 36, "days")
        maxAge:SetPoint("LEFT", ageLabel, "RIGHT", 6, 0)
        Hint(maxAge, "Max price age", "Only items whose Auctionator price was seen within this many days.")
        anchor = maxAge
    end
    local slot = W.MakeDropdown(adv, 110, function()
        local o = { { "", "Any slot" } }
        for _, s in ipairs(ns.Search:EquipSlots()) do o[#o + 1] = s end
        return o
    end, function() if not live then Search() end end)
    slot:SetPoint("LEFT", anchor, "RIGHT", 8, 0); slot:SetValue("", "Any slot")
    if not live then
        priced = MakeCheckbox(adv, "Priced only")
        priced:SetPoint("LEFT", slot, "RIGHT", 4, 0)
        priced:SetScript("OnClick", function() Search() end)
    end

    local astr = MakeEditBox(adv, 360, "Paste an Auctionator search string, e.g. \"Linen Cloth\";;0;0;0;0;0;0;0;5")
    astr:SetPoint("TOPLEFT", 0, -ROW)
    local import = MakeButton(adv, "Use", 46, 26)
    import:SetPoint("LEFT", astr, "RIGHT", 6, 0)
    Hint(import, "Use Auctionator search", "Fills the filters from an Auctionator search string (name;category;iLvl;level;crafted;price;quality;...). Its quantity, if any, goes into Qty.")
    local copy = MakeButton(adv, "Copy", 46, 26)
    copy:SetPoint("LEFT", import, "RIGHT", 4, 0)
    Hint(copy, "Copy as Auctionator search", "Shows these filters as an Auctionator search string, ready to copy (Ctrl+C) into Auctionator's Shopping tab.")

    -- -----------------------------------------------------------------------
    function bar:Read()
        local f = {}
        f.text, f.exact = ns.Search.ParseText(name:GetText())
        -- A picked suggestion or shift-clicked link: exact, though shown without quotes.
        if f.text and not f.exact and name.exactName == f.text then f.exact = true end
        f.minLevel, f.maxLevel = level:Get()
        f.quality = rarity.value ~= -1 and rarity.value or nil
        f.usable = usable:GetChecked() and true or nil
        f.classID, f.subClassID = self.classID, self.subClassID
        if adv:IsShown() then
            f.minIlvl, f.maxIlvl = ilvl:Get()
            local lo, hi = price:Get()
            f.minPrice = lo and math.floor(lo * 10000 + 0.5) or nil
            f.maxPrice = hi and math.floor(hi * 10000 + 0.5) or nil
            f.equipLoc = slot.value ~= "" and slot.value or nil
            if maxAge then f.maxAge = maxAge:GetValue() end
            if priced then f.hidePriceless = priced:GetChecked() and true or nil end
        end
        -- Fields this bar has no controls for survive a Load/Read round trip.
        local extra = self.extra or {}
        f.minCrafted, f.maxCrafted, f.tier, f.expansion = extra.minCrafted, extra.maxCrafted, extra.tier, extra.expansion
        return f
    end

    function bar:SetAdvanced(shown)
        adv:SetShown(shown)
        W.SetActive(advancedBtn, shown)
        self:SetHeight(self:Height())
        if opts.onLayout then opts.onLayout() end
    end

    function bar:Height() return (baseRows + (adv:IsShown() and 2 or 0)) * ROW - 6 end

    function bar:SetCategory(classID, subClassID)
        local changed = self.classID ~= classID or self.subClassID ~= subClassID
        self.classID, self.subClassID = classID, subClassID
        UpdateCategoryLabels()
        if changed and opts.onCategory then opts.onCategory(classID, subClassID) end
    end

    -- Fills every control from a filter table (a recent search, a list entry, an Auctionator string).
    function bar:Load(f)
        f = f or {}
        if f.text and f.exact then
            -- Show a known item's proper name without quotes; anything else keeps the quotes.
            local e
            for _, c in ipairs(ns.Catalog.entries) do if c.lname == f.text then e = c break end end
            if e then W.SetExactName(name, e.name) else name:SetText('"' .. f.text .. '"') end
        else
            name:SetText(f.text or "")
        end
        level.min:SetValue(f.minLevel); level.max:SetValue(f.maxLevel)
        if f.quality then rarity:SetValue(f.quality, QualityLabel(f.quality)) else rarity:SetValue(-1, "All rarities") end
        usable:SetChecked(f.usable and true or false)
        ilvl.min:SetValue(f.minIlvl); ilvl.max:SetValue(f.maxIlvl)
        price.min:SetValue(f.minPrice and f.minPrice / 10000); price.max:SetValue(f.maxPrice and f.maxPrice / 10000)
        if f.equipLoc and _G[f.equipLoc] then slot:SetValue(f.equipLoc, _G[f.equipLoc]) else slot:SetValue("", "Any slot") end
        if maxAge then maxAge:SetValue(f.maxAge) end
        if priced then priced:SetChecked(f.hidePriceless and true or false) end
        self.extra = { minCrafted = f.minCrafted, maxCrafted = f.maxCrafted, tier = f.tier, expansion = f.expansion }
        self:SetCategory(f.classID, f.subClassID)
        local needsAdv = f.minIlvl or f.maxIlvl or f.minPrice or f.maxPrice or f.equipLoc or f.maxAge or f.hidePriceless
        if needsAdv and not adv:IsShown() then self:SetAdvanced(true) end
    end

    function bar:Reset()
        self:Load({})
        astr:SetText("")
        if opts.onReset then opts.onReset() end
    end

    -- -----------------------------------------------------------------------
    local pending
    name:HookScript("OnTextChanged", function(self, user)
        if user then self.exactName = nil end -- edited: no longer the picked item
        if live or not user or pending then return end
        pending = true
        C_Timer.After(0.35, function() pending = false; Search() end)
    end)
    name:SetScript("OnEnterPressed", function(self) self:ClearFocus(); Search() end)
    if not live then level:OnChanged(function(_, user) if user then Search() end end) end
    for _, box in ipairs({ level.min, level.max, ilvl.min, ilvl.max, price.min, price.max, maxAge }) do
        box:SetScript("OnEnterPressed", function(self) self:ClearFocus(); Search() end)
    end
    search:SetScript("OnClick", function() Search() end)
    reset:SetScript("OnClick", function() bar:Reset(); if not live then Search() end end)
    advancedBtn:SetScript("OnClick", function() bar:SetAdvanced(not adv:IsShown()); if not live then Search(true) end end)
    import:SetScript("OnClick", function()
        local f = ns.Search:FromAuctionatorString(ns.Trim(astr:GetText()))
        if not f then return ns:Print("That isn't an Auctionator search string.", true) end
        bar:Load(f)
        if f.quantity and opts.onQuantity then opts.onQuantity(f.quantity) end
        Search()
    end)
    copy:SetScript("OnClick", function()
        local s = ns.Search:ToAuctionatorString(bar:Read())
        if not s then return ns:Print("This version of Auctionator can't make search strings.", true) end
        astr:SetText(s); astr:SetFocus(); astr:HighlightText()
        ns:Print("Auctionator search string (selected in the box, press Ctrl+C): " .. s, true)
    end)
    W.RegisterLinkBox(name, function() Search() end)
    W.AttachSuggestions(name, { onPick = function(item)
        if item.entry and opts.onPickItem then opts.onPickItem(item.entry) else Search() end
    end })

    return bar
end

-- ---------------------------------------------------------------------------
-- Type-ahead: item names drop down under a name box while you type. Up/Down move, Enter or a
-- click picks (the box gets the item's name as an exact search and onPick runs), Tab takes the highlighted
-- or first one, Escape closes. Names come from every item Auctionator knows, and matching recent
-- searches come first.
-- ---------------------------------------------------------------------------

local MAX_SUGGEST, SUGGEST_ROW, MAX_RECENT_SUGGEST = 10, 24, 2
local popup

local function GetPopup()
    if popup then return popup end
    popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    W.SetBackdrop(popup)
    popup:SetFrameStrata("FULLSCREEN_DIALOG"); popup:SetClampedToScreen(true)
    popup:Hide()
    popup.rows = {}
    return popup
end

local function ByName(a, b)
    if #a.lname ~= #b.lname then return #a.lname < #b.lname end
    return a.lname < b.lname
end

-- Names starting with the text, then names with a word starting with it, then any other match.
function W.Suggestions(text, limit)
    limit = limit or MAX_SUGGEST
    local out, seen = {}, {}
    local recent = ns.char and ns.char.searches and ns.char.searches.recent or {}
    for _, f in ipairs(recent) do
        if #out >= MAX_RECENT_SUGGEST then break end
        local t = f.text
        if t and not f.exact and t ~= text and t:find(text, 1, true) == 1 and not seen[t] then
            seen[t] = true
            out[#out + 1] = { recent = t }
        end
    end
    ns.Catalog:EnsureBuilt()
    local starts, words, contains = {}, {}, {}
    local wordStart = " " .. text
    for _, e in ipairs(ns.Catalog.entries) do
        local n = e.lname
        if n then
            local i = n:find(text, 1, true)
            if i == 1 then starts[#starts + 1] = e
            elseif i then
                if n:find(wordStart, 1, true) then words[#words + 1] = e else contains[#contains + 1] = e end
            end
        end
    end
    for _, group in ipairs({ starts, words, contains }) do
        table.sort(group, ByName)
        for _, e in ipairs(group) do
            if #out >= limit then return out end
            out[#out + 1] = { entry = e }
        end
    end
    return out
end

local function RowDetail(e)
    local parts = {}
    if e.reqLevel and e.reqLevel > 1 then parts[#parts + 1] = "Lvl " .. e.reqLevel end
    if e.ilvl and e.ilvl > 1 then parts[#parts + 1] = "iLvl " .. e.ilvl end
    local sub = e.classID and e.subClassID and ns.Compat.GetSubClassName(e.classID, e.subClassID)
    if sub then parts[#parts + 1] = sub end
    return table.concat(parts, "  ·  ")
end

function W.AttachSuggestions(box, opts)
    opts = opts or {}
    local items, index = {}, 0

    local function Visible() return popup and popup:IsShown() and popup.owner == box end
    local function Hide()
        if Visible() then popup:Hide(); popup.owner = nil end
        index = 0
    end
    local function Highlight()
        for i, row in ipairs(popup.rows) do
            if i == index then
                row:SetBackdropColor(PAL.hover[1], PAL.hover[2], PAL.hover[3], 1); row:SetBackdropBorderColor(W.ACCENT[1], W.ACCENT[2], W.ACCENT[3], 1)
            else
                row:SetBackdropColor(PAL.row[1], PAL.row[2], PAL.row[3], 1); row:SetBackdropBorderColor(0, 0, 0, 0)
            end
        end
    end
    local function Pick(item)
        if not item then return end
        Hide()
        if item.entry then W.SetExactName(box, item.entry.name) else box:SetText(item.recent); box.exactName = nil end
        box:ClearFocus()
        if opts.onPick then opts.onPick(item) end
    end

    local function Show()
        local p = GetPopup()
        for i, item in ipairs(items) do
            local row = p.rows[i]
            if not row then
                row = CreateFrame("Button", nil, p, "BackdropTemplate")
                row:SetHeight(SUGGEST_ROW - 2)
                W.SetBackdrop(row)
                row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(18, 18); row.icon:SetPoint("LEFT", 3, 0)
                row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                row.right = row:CreateFontString(nil, "OVERLAY", "QuartermasterGameFontHighlightSmall")
                row.right:SetPoint("RIGHT", -6, 0); row.right:SetJustifyH("RIGHT"); row.right:SetWordWrap(false)
                row.text = row:CreateFontString(nil, "OVERLAY", "QuartermasterGameFontHighlightSmall")
                row.text:SetPoint("LEFT", 26, 0); row.text:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
                row.text:SetJustifyH("LEFT"); row.text:SetWordWrap(false)
                row:SetScript("OnEnter", function(self) index = self.index; Highlight() end)
                p.rows[i] = row
            end
            row.index = i
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * SUGGEST_ROW); row:SetPoint("TOPRIGHT", -4, -4 - (i - 1) * SUGGEST_ROW)
            if item.entry then
                local e = item.entry
                row.icon:SetTexture(W.IconFor(e)); row.icon:Show()
                row.text:SetText(W.QualityName(e.name, e.quality) .. "  |cff8fa3b3" .. RowDetail(e) .. "|r")
                row.right:SetText(W.Money(e.price))
            else
                row.icon:Hide()
                row.text:SetText("|cff8fa3b3Recent search:|r " .. item.recent)
                row.right:SetText("")
            end
            row:SetScript("OnClick", function() Pick(item) end)
            row:Show()
        end
        for i = #items + 1, #p.rows do p.rows[i]:Hide() end
        p:SetSize(math.max(box:GetWidth(), 340), #items * SUGGEST_ROW + 6)
        p:ClearAllPoints(); p:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -2)
        p.owner = box
        p:Show()
        Highlight()
    end

    local function Update()
        local text = ns.Trim(box:GetText()):lower()
        if #text < 2 or text:find('^"') or not box:HasFocus() then return Hide() end
        items, index = W.Suggestions(text), 0
        if #items == 0 then return Hide() end
        Show()
    end
    box.UpdateSuggestions = Update
    box.SuggestionItems = function() return Visible() and items or {} end

    local pending
    box:HookScript("OnTextChanged", function(_, user)
        if not user or pending then return end
        pending = true
        C_Timer.After(0.15, function() pending = false; Update() end)
    end)
    box:HookScript("OnEditFocusLost", function()
        -- A click on a row takes the focus first; let it land before closing.
        C_Timer.After(0.2, function() if not box:HasFocus() then Hide() end end)
    end)
    box:SetScript("OnArrowPressed", function(_, key)
        if not Visible() then return end
        if key == "DOWN" then index = math.min(#items, index + 1)
        elseif key == "UP" then index = math.max(0, index - 1) end
        Highlight()
    end)
    box:SetScript("OnTabPressed", function()
        if Visible() then Pick(items[index > 0 and index or 1]) end
    end)
    local enter, escape = box:GetScript("OnEnterPressed"), box:GetScript("OnEscapePressed")
    box:SetScript("OnEnterPressed", function(self, ...)
        if Visible() and index > 0 then return Pick(items[index]) end
        Hide()
        if enter then enter(self, ...) end
    end)
    box:SetScript("OnEscapePressed", function(self, ...)
        if Visible() then return Hide() end
        if escape then escape(self, ...) end
    end)
    box:HookScript("OnHide", Hide)
end
