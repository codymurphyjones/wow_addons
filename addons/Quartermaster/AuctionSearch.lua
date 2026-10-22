local _, ns = ...
local PAL = ns.Palette

-- The live auction house search panel, used by the Buying tab and the Cart's Find panel. Laid out
-- like the /qm Browse page:
--
--   summary   status on the left; Recent & saved, Save search, Search a list, Add search on the right
--             (in edit mode: Save to entry / Cancel, for a Cart search entry)
--   filters   the shared filter bar (SearchBar.lua) in live mode, with type-ahead name suggestions
--   body      category tree on the left; matching items in sortable columns on the right, 50 a page,
--             + adds one to your list; click an item for its listings
--   bar       Prev / Page / Next (items) or the big Buy button (listings); Add to and the list picker.
--             Buy and Add to work alike: stackable items ask how many first (W.QuantityDialog), then
--             buy (after the exact price, for trade goods) or add to the list.
--
-- ns.AuctionSearch:Create(parent, { compact, target = function() return list end }) -> view
local AuctionSearch = { views = {} }
ns.AuctionSearch = AuctionSearch

local W = ns.Widgets
local ACCENT, MUTED = W.ACCENT, W.MUTED
local Label, Muted, MakeButton, Hint, MakeNumberBox = W.Label, W.Muted, W.MakeButton, W.Hint, W.MakeNumberBox
local Money = ns.Compat.Money

local COOL_GREEN = { 0.35, 0.95, 0.55 }
local MAX_RECENT = 20
local PER_PAGE = 50
local BUY_PAD = 10 -- space kept between the Buy button's text and its edges

-- ---------------------------------------------------------------------------
-- Recent and saved searches
-- ---------------------------------------------------------------------------

local function Recent() return ns.char.searches.recent end
local function Saved() return ns.db.searches.saved end

local function Remember(f)
    if ns.Search.IsEmpty(f) then return end
    local key = ns.Search:Describe(f)
    local recent = Recent()
    for i = #recent, 1, -1 do
        if ns.Search:Describe(recent[i]) == key then table.remove(recent, i) end
    end
    table.insert(recent, 1, ns.Search.Copy(f))
    while #recent > MAX_RECENT do table.remove(recent) end
end

local function SaveSearch(name, f)
    name = ns.Trim(name)
    if name == "" then return end
    local saved = Saved()
    for _, s in ipairs(saved) do
        if s.name == name then s.filter = ns.Search.Copy(f); return ns:Print(("Updated saved search \"%s\"."):format(name), true) end
    end
    saved[#saved + 1] = { name = name, filter = ns.Search.Copy(f) }
    table.sort(saved, function(a, b) return a.name:lower() < b.name:lower() end)
    ns:Print(("Saved search \"%s\"."):format(name), true)
end

local function DeleteSaved(name)
    local saved = Saved()
    for i, s in ipairs(saved) do
        if s.name == name then table.remove(saved, i) break end
    end
end

-- A list entry as a search: exact entries become an exact name search.
local function EntryFilter(entry)
    if entry.filter then return entry.filter end
    local name = entry.name or (ns.Catalog:Get(entry.itemID) or {}).name
    if not name then return nil end
    return { text = name:lower(), exact = true }
end

-- ---------------------------------------------------------------------------
-- The view
-- ---------------------------------------------------------------------------

function AuctionSearch:Create(parent, opts)
    opts = opts or {}
    local v = CreateFrame("Frame", nil, parent)
    v.state = "idle"     -- idle | searching | listing | quoting | focusing | buying
    v.mode = "groups"    -- groups | listings
    v.groups, v.listings = {}, {}
    v.sortKey, v.desc, v.page = "price", false, 1
    self.views[#self.views + 1] = v
    local treeW = opts.compact and 130 or 150

    -- Summary line: status left, toolbar right ------------------------------
    v.status = Muted(v:CreateFontString(nil, "OVERLAY", "QuartermasterGameFontHighlightSmall"))
    v.status:SetPoint("TOPLEFT", 0, -7); v.status:SetJustifyH("LEFT"); v.status:SetWordWrap(false)

    local recentDrop = W.MakeDropdown(v, 140, function()
        local o = {}
        local saved, recent = Saved(), Recent()
        if #saved > 0 then o[#o + 1] = { nil, "Saved searches", header = true } end
        for i, sv in ipairs(saved) do o[#o + 1] = { "saved:" .. i, "|cff55d6be" .. sv.name .. "|r" } end
        if #recent > 0 then o[#o + 1] = { nil, "Recent searches", header = true } end
        for i, f in ipairs(recent) do o[#o + 1] = { "recent:" .. i, ns.Search:Describe(f) } end
        if #saved > 0 then o[#o + 1] = { "delete", "|cff8fa3b3Delete a saved search...|r" } end
        if #recent > 0 then o[#o + 1] = { "clear", "|cff8fa3b3Clear recent searches|r" } end
        if #o == 0 then o[1] = { nil, "No searches yet", header = true } end
        return o
    end, function(value)
        v.recentDrop:SetValue(nil, "Recent & saved")
        local kind, i = tostring(value):match("^(%a+):(%d+)$")
        i = tonumber(i)
        if kind == "saved" and Saved()[i] then v:Run(Saved()[i].filter, true)
        elseif kind == "recent" and Recent()[i] then v:Run(Recent()[i], true)
        elseif value == "clear" then wipe(Recent())
        elseif value == "delete" then
            local menu = {}
            for _, sv in ipairs(Saved()) do
                menu[#menu + 1] = { "Delete \"" .. sv.name .. "\"", function() DeleteSaved(sv.name) end }
            end
            W.ContextMenu(menu)
        end
    end)
    recentDrop:SetValue(nil, "Recent & saved")
    Hint(recentDrop, "Recent and saved searches", "Pick one to search again. Saved searches are shared by all your characters.")
    v.recentDrop = recentDrop

    local save = MakeButton(v, "Save search", 84, 26)
    save:SetScript("OnClick", function()
        local f = v.filters:Read()
        if ns.Search.IsEmpty(f) then return ns:Print("Set some filters first.", true) end
        W.AskText("Name this search:", f.text or ns.Search:Describe(f), function(name) SaveSearch(name, f) end)
    end)

    local listDrop = W.MakeDropdown(v, 120, function()
        local o = { { nil, "Search every entry of...", header = true } }
        for i, l in ipairs(ns.Lists:All()) do o[#o + 1] = { i, l.name .. " |cff8fa3b3(" .. #l.entries .. ")|r" } end
        return o
    end, function(index)
        v.listDrop:SetValue(nil, "Search a list")
        local list = ns.Lists:All()[index]
        if list then v:RunList(list) end
    end)
    listDrop:SetValue(nil, "Search a list")
    Hint(listDrop, "Search a whole list", "Searches every entry of a shopping list one after another and shows everything together, like Auctionator's Search All.")
    v.listDrop = listDrop

    local addSearch = MakeButton(v, "Add search", 80, 26)
    Hint(addSearch, "Add this search to a list", "Adds the current filters as one Cart entry: the Cart then buys that many of anything matching, cheapest first, within the max price (or each item's market price plus tolerance).")
    local cancelEdit = MakeButton(v, "Cancel", 56, 26); cancelEdit:Hide()
    local saveEntry = MakeButton(v, "Save to entry", 96, 26); saveEntry:Hide()
    Hint(saveEntry, "Save to entry", "Saves these filters back to the Cart search entry you're editing.")

    addSearch:SetPoint("TOPRIGHT", 0, 0)
    cancelEdit:SetPoint("TOPRIGHT", 0, 0)
    saveEntry:SetPoint("RIGHT", cancelEdit, "LEFT", -4, 0)
    listDrop:SetPoint("RIGHT", addSearch, "LEFT", -4, 0)
    save:SetPoint("RIGHT", listDrop, "LEFT", -4, 0)
    recentDrop:SetPoint("RIGHT", save, "LEFT", -4, 0)
    v.status:SetPoint("RIGHT", recentDrop, "LEFT", -10, 0)
    v.addSearch, v.saveEntry, v.cancelEdit = addSearch, saveEntry, cancelEdit

    -- Filters ---------------------------------------------------------------
    local tree
    v.filters = W.MakeFilterBar(v, {
        mode = "live", categories = "tree",
        onSearch = function() v:Run(v.filters:Read()) end,
        onLayout = function() v:Layout() end,
        onQuantity = function(q) v.defaultQty = q end, -- an imported Auctionator string's quantity
        onCategory = function(classID, subClassID) if tree then tree:Set(classID, subClassID) end end,
        -- A picked suggestion goes straight to that item's listings (the buy screen); Enter or
        -- Search still shows the list of matching items.
        onPickItem = function(e) v:Run(v.filters:Read(), false, e.id) end,
    })
    v.filters:SetPoint("TOPLEFT", 0, -32); v.filters:SetPoint("TOPRIGHT", 0, -32)

    -- Body: category tree left, results right, bar at the bottom -------------
    local body = CreateFrame("Frame", nil, v)
    v.body = body
    tree = W.MakeCategoryTree(body, treeW, function() return ns.Search:AllCategories() end, function(classID, subClassID)
        v.filters:SetCategory(classID, subClassID)
        v:Run(v.filters:Read())
    end)
    tree:SetPoint("TOPLEFT", 0, 0); tree:SetPoint("BOTTOMLEFT", 0, 40)
    v.tree = tree

    local results = CreateFrame("Frame", nil, body)
    results:SetPoint("TOPLEFT", treeW + 10, 0); results:SetPoint("BOTTOMRIGHT", 0, 40)
    local headers = W.MakeColumnHeaders(results, {
        { "name", "Name", nil }, { "level", "Lvl", 46 }, { "ilvl", "iLvl", 46 }, { "available", "Available", 74 }, { "price", "Price each", 130 },
    }, function(key, desc) v.sortKey, v.desc = key, desc; v:ShowGroups(true) end)
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
    headers:Set("price", false)
    -- Listings view: Back and the item's name in place of the headers.
    local back = MakeButton(results, "< Back", 60, 20); back:SetPoint("TOPLEFT", 0, 0); back:Hide()
    back:SetScript("OnClick", function() v:Back() end)
    local title = results:CreateFontString(nil, "OVERLAY", "QuartermasterGameFontHighlightSmall")
    title:SetPoint("LEFT", back, "RIGHT", 8, 0); title:SetPoint("RIGHT", results, "RIGHT", -30, 0)
    title:SetJustifyH("LEFT"); title:SetWordWrap(false); title:Hide()
    local list = W.CreateRowList(results, -24, { rowHeight = 30 })
    v.back, v.title, v.headers, v.list, v.results = back, title, headers, list, results

    local bar = CreateFrame("Frame", nil, body)
    bar:SetPoint("BOTTOMLEFT", 0, 0); bar:SetPoint("BOTTOMRIGHT", 0, 0); bar:SetHeight(32)
    -- Items: pages, like the Browse tab.
    local prev = MakeButton(bar, "< Prev", 60, 26); prev:SetPoint("LEFT", 0, 0)
    local pageText = Muted(bar:CreateFontString(nil, "OVERLAY", "QuartermasterGameFontHighlightSmall"))
    pageText:SetPoint("LEFT", prev, "RIGHT", 8, 0); pageText:SetWidth(84)
    local nextBtn = MakeButton(bar, "Next >", 60, 26); nextBtn:SetPoint("LEFT", pageText, "RIGHT", 8, 0)
    prev:SetScript("OnClick", function() v.page = v.page - 1; v:ShowGroups() end)
    nextBtn:SetScript("OnClick", function() v.page = v.page + 1; v:ShowGroups() end)
    v.prev, v.pageText, v.nextBtn = prev, pageText, nextBtn
    -- Listings: one big Buy button, one click per purchase.
    local buy = MakeButton(bar, "Buy", opts.compact and 250 or 280, 30)
    buy:SetPoint("LEFT", 0, 0)
    buy.text:SetFontObject("QuartermasterGameFontHighlight")
    -- Keep the text off the edges; UpdateButton widens the button to fit, up to a limit.
    buy.text:ClearAllPoints()
    buy.text:SetPoint("LEFT", BUY_PAD, 0); buy.text:SetPoint("RIGHT", -BUY_PAD, 0)
    buy.text:SetJustifyH("CENTER"); buy.text:SetWordWrap(false)
    buy.minWidth, buy.maxWidth = opts.compact and 250 or 280, opts.compact and 400 or 460
    buy.fill = buy:CreateTexture(nil, "BACKGROUND", nil, 1)
    buy.fill:SetPoint("TOPLEFT", 1, -1); buy.fill:SetPoint("BOTTOMRIGHT", -1, 1)
    buy.fill:SetColorTexture(1, 1, 1, 1); buy.fill:SetVertexColor(0, 0, 0, 0)
    buy:SetScript("OnClick", function() v:Buy() end)
    Hint(buy, "Buy", "Single auctions are bought right away. Stackable trade goods ask how many, then show the exact price to confirm.")
    buy:Hide()
    v.buy = buy

    -- Right side: where Add puts things, the caller's list (the Cart's) or a picker like Browse's.
    local targetPicker
    if not opts.target then
        targetPicker = W.MakeDropdown(bar, 150, function()
            local o = { { nil, "Shopping lists", header = true } }
            for i, l in ipairs(ns.Lists:All()) do o[#o + 1] = { "list:" .. i, l.name } end
            local all = ns.Prebuilt:All()
            if #all.char > 0 then o[#o + 1] = { nil, "Prebuilt (this character)", header = true } end
            for _, t in ipairs(all.char) do o[#o + 1] = { "template:" .. t.id, t.name } end
            if #all.account > 0 then o[#o + 1] = { nil, "Prebuilt (account)", header = true } end
            for _, t in ipairs(all.account) do o[#o + 1] = { "template:" .. t.id, t.name } end
            return o
        end, function(value)
            local kind, key = value:match("^(%a+):(.+)$")
            if kind == "list" then ns.Lists:SetAddTarget("list", tonumber(key)) else ns.Lists:SetAddTarget("template", key) end
            v:Refresh()
            if v.mode == "groups" then v:ShowGroups(true) end
        end)
        targetPicker:SetPoint("RIGHT", 0, 0)
        Hint(targetPicker, "Add to", "The shopping list or prebuilt list that Add to, the + buttons and Add search use. Prebuilt lists only take exact items.")
    end
    v.targetPicker = targetPicker
    local addItem = MakeButton(bar, "Add to", 60, 26)
    if targetPicker then addItem:SetPoint("RIGHT", targetPicker, "LEFT", -6, 0) else addItem:SetPoint("RIGHT", 0, 0) end
    Hint(addItem, "Add to list", "Adds the item you're looking at to the list" .. (targetPicker and " on the right" or " the Cart is buying") .. ". Stackable items ask how many first.")
    v.addItem = addItem

    function v:Target()
        if opts.target then return opts.target() end
        return (ns.Lists:AddTarget())
    end

    addItem:SetScript("OnClick", function()
        local id = v:SelectedItem()
        if not id then return ns:Print("Click an item first.", true) end
        -- A selected listing knows its own enchant (modern groups hold every enchant of an item).
        v:AddItem(id, nil, (v.mode == "listings" and v.selected) or v.group)
    end)
    addSearch:SetScript("OnClick", function()
        v:AddSearch()
    end)
    saveEntry:SetScript("OnClick", function() v:SaveEdit() end)
    cancelEdit:SetScript("OnClick", function() v:EndEdit() end)

    -- The Buy button depends on the AH throttle, which has no event; poll it lightly.
    local elapsed = 0
    v:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.25 then return end
        elapsed = 0
        if v.mode == "listings" then v:UpdateButton() end
    end)
    v:SetScript("OnShow", function() tree:Refresh() end)

    for k, fn in pairs(AuctionSearch.methods) do v[k] = fn end
    tree:Refresh()
    v:Layout()
    v:ShowGroups()
    return v
end

-- ---------------------------------------------------------------------------
-- View methods
-- ---------------------------------------------------------------------------

local M = {}
AuctionSearch.methods = M

function M:Layout()
    self.body:ClearAllPoints()
    self.body:SetPoint("TOPLEFT", 0, -32 - self.filters:Height() - 8)
    self.body:SetPoint("BOTTOMRIGHT", 0, 0)
end

-- Stops this view's search or purchase (the Cart is about to take the auction house over).
function M:Stop()
    -- A quantity popup this panel opened would buy after the Cart took over: close it.
    local d = QuartermasterQuantityDialog
    if d and d:IsShown() then d:Hide() end
    if self.state == "idle" then return end
    if self.state == "searching" or self.state == "listing" or self.state == "focusing" then ns.Scanner:Abort() end
    if self.state == "quoting" or self.state == "buying" then ns.Purchase:Cancel() end
    self.state, self.candidate, self.token = "idle", nil, (self.token or 0) + 1
    self:SetStatus("Stopped.")
    self:Refresh()
end

-- The item whose listings a visible panel is showing (for /qm testprice).
function AuctionSearch:CurrentItem()
    for _, v in ipairs(self.views) do
        if v:IsVisible() and v.mode == "listings" and v.group then return v.group.itemID end
    end
end

function AuctionSearch:StopAll(except)
    for _, v in ipairs(self.views) do if v ~= except then v:Stop() end end
end

-- Takes the auction house over for a search: the Cart's quiet price checks and other views stop.
local function Claim(self)
    if ns.Buyer:Running() then
        ns:Print("The Cart is buying. Stop it first, or wait until it finishes.", true)
        return false
    end
    if not (ns.Scanner:Legacy() or ns.Scanner:Modern()) then
        ns:Print("Open the auction house first.", true)
        return false
    end
    ns.Compare:StopCheck()
    AuctionSearch:StopAll(self)
    ns.Scanner:Abort()
    ns.Purchase:Cancel()
    self.token = (self.token or 0) + 1
    return self.token
end

function M:SetStatus(text) self.status:SetText(text or "") end

-- Runs a search. load = fill the filter bar from f first (recent/saved searches).
-- openItemID: open that item's listings as soon as the results are in (a picked suggestion).
function M:Run(f, load, openItemID)
    if load then self.filters:Load(f) end
    -- No filters at all would list the whole auction house (and look like a full scan to other addons).
    if ns.Search.IsEmpty(f) then
        self:SetStatus("|cffffd24dType a name or pick a category first.|r")
        return
    end
    local token = Claim(self)
    if not token then return end
    self.f, self.multi, self.before = ns.Search.Copy(f), nil, nil
    Remember(f)
    self.state, self.candidate, self.selected = "searching", nil, nil
    self.groups, self.mode, self.page = {}, "groups", 1
    self:SetStatus("|cffffd24dSearching...|r")
    self:Refresh()
    ns.Scanner:Browse(self.f, function(groups)
        if self.token ~= token then return end
        self.state = "idle"
        if not groups then
            self:SetStatus("|cffd9736bNo answer from the auction house. Try again.|r")
        else
            self.groups = groups
            self:SetStatus(("%d item%s match"):format(#groups, #groups == 1 and "" or "s"))
        end
        self:ShowGroups()
        if openItemID and groups then
            for _, g in ipairs(groups) do
                if g.itemID == openItemID then return self:Open(g) end
            end
            self:SetStatus("|cffd9736bNone listed right now.|r")
        end
    end, function(n)
        if self.token ~= token then return end
        self:SetStatus(("|cffffd24dSearching... %s|r"):format(ns.Scanner:Modern() and (n .. " found") or ("page " .. (n + 1))))
    end)
end

-- Searches every entry of a list in turn and shows the results under one heading per entry.
function M:RunList(list)
    local token = Claim(self)
    if not token then return end
    local todo = {}
    for _, entry in ipairs(list.entries) do
        local f = EntryFilter(entry)
        if f then todo[#todo + 1] = { entry = entry, f = f } end
    end
    if #todo == 0 then return ns:Print(list.name .. " has nothing to search for.", true) end
    self.multi, self.f, self.before = { list = list, sections = {} }, nil, nil
    self.state, self.candidate, self.selected, self.mode, self.groups = "searching", nil, nil, "groups", {}
    self.page = 1
    local i = 0
    local function Next()
        if self.token ~= token then return end
        i = i + 1
        local t = todo[i]
        if not t then
            self.state = "idle"
            local found = 0
            for _, s in ipairs(self.multi.sections) do found = found + #s.groups end
            self:SetStatus(("%s: %d entr%s, %d item%s listed"):format(list.name, #todo, #todo == 1 and "y" or "ies", found, found == 1 and "" or "s"))
            return self:ShowGroups()
        end
        self:SetStatus(("|cffffd24dSearching %d/%d: %s|r"):format(i, #todo, ns.Lists:Describe(t.entry)))
        ns.Scanner:Browse(t.f, function(groups)
            if self.token ~= token then return end
            local section = { entry = t.entry, groups = groups or {}, failed = groups == nil }
            -- An exact entry only wants its own item (the same name can match more than one), and
            -- only its own enchant. Modern groups don't know their enchant: they stay, and their
            -- listings show each copy's.
            if not t.entry.filter and groups then
                local mine, key = {}, ns.Lists:Key(t.entry)
                for _, g in ipairs(groups) do
                    if g.itemID == t.entry.itemID and (not g.variant or g.variant == key) then mine[#mine + 1] = g end
                end
                section.groups = mine
            end
            table.insert(self.multi.sections, section)
            self:ShowGroups(true)
            Next()
        end)
    end
    self:Refresh()
    Next()
end

-- Clicking an item: a supply crate (Crates.lua) shows itself and what fills it; anything else, or
-- the crate inside that view, opens its listings.
function M:Open(g)
    local inCrate = self.multi and self.multi.crate
    local e = ns.Catalog:Get(g.itemID) or {}
    local filler = not inCrate and ns.Crates:Filler(g.itemID, g.name or e.name)
    if filler then return self:RunCrate(g, filler) end
    self:OpenGroup(g)
end

-- A crate and what fills it, under one heading each. The filler is found with a live search: by
-- exact name when Auctionator knows the item, otherwise by part of the name, keeping the items
-- whose name fits (or, if none does, everything but other crates).
function M:RunCrate(g, filler)
    local token = Claim(self)
    if not token then return end
    self.before = { groups = self.groups, f = self.f, multi = self.multi, page = self.page, status = self.status:GetText() }
    local fill = { filler = filler, groups = {}, searching = true }
    self.multi = { crate = g, sections = { { crate = true, groups = { g } }, fill } }
    self.state, self.candidate, self.selected, self.mode, self.page = "searching", nil, nil, "groups", 1
    local crateName = g.link or g.name or "crate"
    self:SetStatus(("|cffffd24dLooking up what fills %s...|r"):format(crateName))
    self:ShowGroups()
    ns.Scanner:Browse({ text = filler.search, exact = filler.exact }, function(groups)
        if self.token ~= token then return end
        self.state, fill.searching, fill.failed = "idle", nil, groups == nil
        local mine, others = {}, {}
        for _, x in ipairs(groups or {}) do
            local name = x.name or (ns.Catalog:Get(x.itemID) or {}).name
            if x.itemID == filler.id or (name and filler.names[name:lower()]) then mine[#mine + 1] = x
            elseif not ns.Crates:Is(name) then others[#others + 1] = x end
        end
        fill.groups = #mine > 0 and mine or others
        -- Found it live though Auctionator didn't know it: now + can add it.
        if not filler.id and #mine > 0 then
            filler.id = mine[1].itemID
            filler.label = mine[1].name or filler.label
        end
        self:SetStatus(("%s: the crate and what fills it"):format(crateName))
        self:ShowGroups(true)
    end)
end

-- Back: from listings to the items; from a crate to the search it came from.
function M:Back()
    if self.mode == "listings" then return self:ShowGroups() end
    local b = self.before
    if not (self.multi and self.multi.crate and b) then return self:ShowGroups() end
    if self.state == "searching" then
        ns.Scanner:Abort()
        self.state, self.token = "idle", (self.token or 0) + 1
    end
    self.groups, self.f, self.multi, self.page, self.before = b.groups or {}, b.f, b.multi, b.page, nil
    self:SetStatus(b.status)
    self:ShowGroups()
end

local SORTERS = {
    name = function(a, b) return (a.name or "~"):lower() < (b.name or "~"):lower() end,
    level = function(a, b) return (a.reqLevel or 0) < (b.reqLevel or 0) end,
    ilvl = function(a, b) return (a.ilvl or 0) < (b.ilvl or 0) end,
    available = function(a, b) return (a.available or 0) < (b.available or 0) end,
    price = function(a, b) return a.minUnit < b.minUnit end,
}

local function SortGroups(groups, key, desc)
    local cmp = SORTERS[key] or SORTERS.price
    table.sort(groups, function(a, b)
        if cmp(a, b) then return not desc end
        if cmp(b, a) then return desc end
        if a.itemID ~= b.itemID then return a.itemID < b.itemID end
        return (a.variant or "") < (b.variant or "")
    end)
end

-- A group's (or listing's) market price: its own variant's (Catalog:MarketFor), so an enchanted copy
-- isn't measured against the plain item's price. Modern groups don't know their variant: plain.
local function MarketOf(x, itemID)
    return ns.Catalog:MarketFor(itemID or x.itemID, x.variant, x.link)
end

-- "  (30-day normal 1g 5s)", from Wealth Planner's price history, when it keeps one.
local function NormalHint(itemID, market)
    local normal = ns.AuctionPrice.Normal(itemID)
    if not normal then return "" end
    local spike = market and market > normal * 1.15
    return ("  (30-day normal %s%s)"):format(Money(normal), spike and ": spiked, buys stop at normal" or "")
end

-- "1g 20s  |cff..(-12%)|r" against the market price.
local function PriceText(unit, market)
    if not market then return Money(unit) end
    local color = ns.Compare:Diff(market, unit)
    local pct = math.floor((unit - market) / market * 100 + 0.5)
    return ("%s %s(%s%d%%)|r"):format(Money(unit), color, pct < 0 and "" or "+", pct)
end

-- One matching item, like a Browse row: name, "Lvl 26 · iLvl 31 · Guns · Ranged", price, +.
local function GroupRow(self, g, target)
    local e = ns.Catalog:Get(g.itemID) or {}
    local detail = {}
    local reqLevel = g.reqLevel or e.reqLevel
    if reqLevel and reqLevel > 1 then detail[#detail + 1] = "Lvl " .. reqLevel end
    if g.ilvl and g.ilvl > 1 then detail[#detail + 1] = "iLvl " .. g.ilvl end
    local sub = e.classID and e.subClassID and ns.Compat.GetSubClassName(e.classID, e.subClassID)
    if sub then detail[#detail + 1] = sub end
    if e.equipLoc and _G[e.equipLoc] and _G[e.equipLoc] ~= "" then detail[#detail + 1] = _G[e.equipLoc] end
    detail[#detail + 1] = g.available .. " available"
    if g.ownerHas then detail[#detail + 1] = "|cffffd24dyou have some listed|r" end
    local onList = target and ns.Lists:Find(target, g.itemID, g.variant)
    if onList then detail[#detail + 1] = ("|cff55d6be%d on list|r"):format(onList.qty) end
    local market = MarketOf(g)
    local plain = ns.Catalog:IsPlain(g.variant)
    local add = function() self:AddItem(g.itemID, nil, g) end
    local tag = not plain and g.link and ns.Catalog:VariantTag(g.link) or ""
    return {
        icon = W.IconFor(e.icon and e or { itemID = g.itemID }), link = g.link or e.link,
        text = (g.name or e.name) and (W.QualityName(g.name or e.name, g.quality or e.quality) .. tag) or ("|cff8fa3b3item " .. g.itemID .. "|r"),
        detail = table.concat(detail, "  ·  "),
        right = PriceText(g.minUnit, market),
        hint = (market and ("Market: " .. Money(market) .. NormalHint(g.itemID, market) .. "\n")
            or (not plain and "No market price for this enchant: Auctionator prices the plain item only.\n" or ""))
            .. "Click to see its listings and buy. Right-click or + adds it to your list. Shift-click to link.",
        onClick = function() self:Open(g) end,
        onRightClick = add,
        actions = { { "+", add, "Add to " .. (target and target.name or "your list") } },
    }
end

-- A section's heading: a list entry (Search a list), or a crate and what fills it (RunCrate).
local function SectionHead(self, sec, target)
    local found = sec.searching and "|cffffd24dsearching...|r" or sec.failed and "|cffd9736bno answer|r"
        or (#sec.groups == 0 and "|cffd9736bnone listed|r" or (#sec.groups .. " item" .. (#sec.groups == 1 and "" or "s")))
    if sec.entry then
        local need = ns.Lists:Remaining(sec.entry)
        return {
            noIcon = true, text = ns.Lists:Describe(sec.entry),
            detail = found .. ("  ·  need %d"):format(need),
            dim = need == 0 and 0.55 or nil,
        }
    end
    if sec.crate then
        return { noIcon = true, text = "|cff55d6beCrate|r", detail = "Click it for its listings" }
    end
    local f = sec.filler
    local detail = { found }
    if f.qty then detail[#detail + 1] = "need " .. f.qty end
    if f.id then detail[#detail + 1] = "you have " .. ns.Stock:Have(f.id) end
    local d = {
        noIcon = true, text = "|cff55d6beFilled with:|r " .. f.label, detail = table.concat(detail, "  ·  "),
        hint = "What the crate is filled with. Click a row below for its listings.",
    }
    if f.id then
        d.actions = { { "+", function() self:AddItem(f.id, f.qty) end,
            "Add " .. (f.qty or "some") .. " to " .. (target and target.name or "your list") } }
    end
    return d
end

-- Matching items, 50 a page (after Search a list: items under one heading per list entry; for a
-- crate: the crate, then what fills it).
function M:ShowGroups(keepScroll)
    self.mode, self.listings, self.candidate, self.selected = "groups", {}, nil, nil
    if self.state == "listing" or self.state == "focusing" or self.state == "quoting" then
        ns.Scanner:Abort(); ns.Purchase:Cancel(); self.state = "idle"
    end
    self.group = nil
    local crate = self.multi and self.multi.crate
    if crate then
        local e = ns.Catalog:Get(crate.itemID) or {}
        self.back:Show(); self.headers:Hide(); self.title:Show()
        self.title:SetText(("%s  |cff8fa3b3and what fills it|r"):format(crate.link or e.link or e.name or "?"))
    else
        self.back:Hide(); self.title:Hide(); self.headers:Show()
    end
    local target = self:Target()
    local all = {}
    if self.multi then
        for _, sec in ipairs(self.multi.sections) do
            all[#all + 1] = SectionHead(self, sec, target)
            SortGroups(sec.groups, "price", false)
            for _, g in ipairs(sec.groups) do all[#all + 1] = GroupRow(self, g, target) end
        end
    else
        SortGroups(self.groups, self.sortKey, self.desc)
        for _, g in ipairs(self.groups) do all[#all + 1] = GroupRow(self, g, target) end
    end
    local pages = math.max(1, math.ceil(#all / PER_PAGE))
    self.page = math.min(math.max(1, self.page or 1), pages)
    local items = {}
    for i = (self.page - 1) * PER_PAGE + 1, math.min(#all, self.page * PER_PAGE) do items[#items + 1] = all[i] end
    self.pages = pages
    local empty
    if self.state == "searching" then empty = "Searching the auction house..."
    elseif self.f or self.multi then empty = "Nothing matches. Try fewer filters."
    else empty = "Type a name (suggestions drop down as you type) and press Enter,\nor pick a category on the left." end
    self.list:Set(items, empty)
    if not keepScroll then self.list:ScrollToTop() end
    self:Refresh()
end

-- One item's listings, ready to buy.
function M:OpenGroup(g)
    local token = Claim(self)
    if not token then return end
    self.group, self.mode, self.state = g, "listings", "listing"
    self.listings, self.selected, self.candidate = {}, nil, nil
    self:ShowListings()
    ns.Scanner:Listings(g, function(listings)
        if self.token ~= token then return end
        self.state = "idle"
        self.listings = listings or {}
        -- The Cart's price check counts these too, for this variant only.
        local key = g.variant or tostring(g.itemID)
        local same = listings
        if listings and not g.variant then
            same = {}
            for _, l in ipairs(listings) do if (l.variant or key) == key then same[#same + 1] = l end end
        end
        ns.Compare:SetLive(key, same)
        if not listings then self:SetStatus("|cffd9736bNo answer from the auction house.|r") end
        self:ShowListings()
    end, function(page)
        if self.token ~= token then return end
        self:SetStatus(("|cffffd24dReading page %d...|r"):format(page + 1))
    end)
end

function M:ShowListings()
    local g = self.group
    if not g then return self:ShowGroups() end
    self.back:Show(); self.title:Show(); self.headers:Hide()
    self.list:ScrollToTop()
    local e = ns.Catalog:Get(g.itemID) or {}
    local market = MarketOf(g)
    local tag = g.link and ns.Catalog:VariantTag(g.link) or ""
    self.title:SetText(("%s%s  |cff8fa3b3%s|r"):format(g.link or e.link or e.name or "?", tag,
        market and ("market " .. Money(market)) or "no market price"))
    local items = {}
    local commodity = self.listings[1] and self.listings[1].commodity
    -- Modern groups hold every enchant of an item: one heading per enchant, each cheapest first.
    local order, byVariant = {}, {}
    for _, l in ipairs(self.listings) do
        local key = l.variant or g.variant or tostring(g.itemID)
        if not byVariant[key] then byVariant[key] = {}; order[#order + 1] = key end
        table.insert(byVariant[key], l)
    end
    for _, key in ipairs(order) do
        local rows = byVariant[key]
        local first = rows[1]
        if #order > 1 then
            local plain = ns.Catalog:IsPlain(key)
            local vm = MarketOf(first, g.itemID)
            items[#items + 1] = {
                noIcon = true,
                text = plain and "|cff55d6bePlain|r" or ("|cff55d6beEnchanted:|r" .. ns.Catalog:VariantTag(first.link)),
                detail = (#rows .. " listing" .. (#rows == 1 and "" or "s")) .. "  ·  "
                    .. (vm and ("market " .. Money(vm)) or "no market price for this enchant"),
            }
        end
        for _, l in ipairs(rows) do
            local link = l.link or g.link
            local ltag = link and ns.Catalog:VariantTag(link) or ""
            local d = {
                icon = W.IconFor(e.icon and e or { itemID = g.itemID }), link = link or e.link,
                text = ("%dx %s%s"):format(l.available or l.count, link or e.name or "?", ltag),
                detail = ("%s each  ·  %s for all%s"):format(PriceText(l.unit, MarketOf(l.link and l or g, g.itemID)),
                    Money(l.unit * (l.available or l.count)), l.owner and ("  ·  " .. tostring(ns.Units.Display(l.owner))) or ""),
                right = Money(l.unit * (l.available or l.count)),
                selected = self.selected == l,
            }
            if commodity then
                d.hint = "Trade goods are bought by quantity, cheapest first: click Buy and choose how many."
            else
                d.hint = "Click to select, then Buy."
                d.onClick = function() self:Select(l) end
            end
            items[#items + 1] = d
        end
    end
    self.list:Set(items, self.state == "listing" and "Reading listings..." or "None listed right now.")
    self:Refresh()
end

-- Non-commodity listing: modern ones can be bought as they are; classic ones need their page loaded.
function M:Select(l)
    if self.state ~= "idle" then return end
    self.selected, self.candidate = l, nil
    if l.auctionID then
        self.candidate = l
    elseif l.page then
        local token = Claim(self)
        if not token then return end
        self.state = "focusing"
        ns.Scanner:FocusPage(l.name, l.page, function(rows)
            if self.token ~= token or self.selected ~= l then return end
            self.state = "idle"
            for _, r in ipairs(rows) do
                if r.buyout > 0 and not r.sold and not r.mine and r.link == l.link and r.count == l.count
                    and r.buyout == l.buyout and r.bidAmount ~= r.buyout then
                    r.unit = r.buyout / r.count
                    self.candidate = r
                    break
                end
            end
            if not self.candidate then
                ns:Print("That auction is gone. Reading the listings again.", true)
                return self:OpenGroup(self.group)
            end
            self:Refresh()
        end)
    end
    self:ShowListings()
end

local function ItemLink(g)
    local e = ns.Catalog:Get(g.itemID) or {}
    return g.link or e.link or e.name or "?"
end

-- Cheapest first, the way trade goods are sold: total for qty, and how many are listed at all.
local function CommodityCost(listings, qty)
    local cost, got = 0, 0
    for _, l in ipairs(listings) do
        local take = math.min(l.count, qty - got)
        if take <= 0 then break end
        cost, got = cost + take * l.unit, got + take
    end
    return cost, got
end

local function IsStackable(self, itemID)
    if self.group and self.group.itemID == itemID and self.listings[1] and self.listings[1].commodity then return true end
    local e = ns.Catalog:Get(itemID)
    return e and (e.maxStack or 1) > 1
end

-- The Buy button: a trade good asks how many (then the exact price); a single auction buys now.
function M:Buy()
    if self.state ~= "idle" or self.mode ~= "listings" then return end
    if ns.Buyer:Running() then return ns:Print("The Cart is buying. Stop it first.", true) end
    if self.listings[1] and self.listings[1].commodity then return self:BuyDialog() end
    local c = self.candidate
    if c and ns.Purchase:CanBuy(c) then self:BuyNow(c) end
end

-- Buying a trade good is a click session. Choose how many, then each round of at most one stack
-- takes two clicks, each making the one call that needs a hardware event: "Get price"
-- (StartCommoditiesPurchase) and "Confirm" (ConfirmCommoditiesPurchase). The popup counts the clicks
-- left and what's been bought so far; closing it keeps whatever was already bought.
function M:BuyDialog()
    local g = self.group
    local available = 0
    for _, l in ipairs(self.listings) do available = available + l.count end
    if available <= 0 then return end
    local link, token = ItemLink(g), self.token
    local e = ns.Catalog:Get(g.itemID) or {}
    local stack = available -- one purchase can take any quantity, as in Auctionator
    local session -- { target, bought, spent } once Buy is pressed
    local quoted  -- { qty, unit, total, estimate } once the server has priced this round
    local tag = {}

    local function Listings() return (self.group == g and self.listings) or {} end
    local function Round() return math.min(stack, session.target - session.bought) end
    local function ClicksLeft()
        local rounds = math.ceil((session.target - session.bought) / stack)
        return rounds * 2 - (quoted and 1 or 0)
    end
    local function Plural(n, word) return n .. " " .. word .. (n == 1 and "" or "s") end

    local function Update(d)
        if not session then return end
        d:SetProgress(("Bought %d / %d  ·  spent %s  ·  %s left"):format(session.bought, session.target,
            Money(session.spent), Plural(ClicksLeft(), "click")))
        if quoted then
            local color = quoted.total > quoted.estimate * 1.02 and "|cffd9736b" or "|cff59f28c"
            d:SetMainLabel(("Confirm %d - %s"):format(quoted.qty, Money(quoted.total)))
            d:SetLine(("Exact price for these %d: %s%s|r (%s each). Click Confirm to buy them."):format(
                quoted.qty, color, Money(quoted.total), Money(quoted.unit)))
        else
            local round = Round()
            local cost = CommodityCost(Listings(), round)
            d:SetMainLabel(("Get price: %d more"):format(round))
            d:SetLine(("Next: %d for about %s. Click to get the exact price."):format(round, Money(cost)))
        end
    end

    local function Finish(d)
        d:SetBusy(true)
        d:SetMainLabel("Done")
        d:SetProgress(("Bought %d / %d  ·  spent %s"):format(session.bought, session.target, Money(session.spent)))
        d:SetLine(("|cff59f28cDone: bought %d for %s.|r"):format(session.bought, Money(session.spent)))
        C_Timer.After(1.2, function()
            if d:IsShown() and d.opts and d.opts.tag == tag then d:Close(true) end
            if self.token == token and self.group == g then self:OpenGroup(g) end
        end)
    end

    W.QuantityDialog({
        tag = tag,
        title = "Buy " .. link, icon = W.IconFor(e.icon and e or { itemID = g.itemID }),
        qty = math.min(self.defaultQty or 1, available), max = available, mainLabel = "Buy",
        describe = function(q)
            if session then return nil end
            local cost = CommodityCost(Listings(), q)
            return ("About %s for %d (%s each), cheapest first. %d listed.\nTwo clicks: get the exact price, then confirm."):format(
                Money(cost), q, Money(cost / q), available)
        end,
        onMain = function(q, d)
            if self.token ~= token or ns.Buyer:Running() then return d:Close() end
            local starting = not session
            if starting then session = { target = q, bought = 0, spent = 0 } end
            -- Every branch below makes its game call before touching the popup (Purchase.lua).
            if quoted then
                -- Confirm click: buy this round at the quoted price.
                local c = { commodity = true, itemID = g.itemID, count = quoted.qty, buyout = quoted.total,
                    unit = quoted.unit, link = link, confirmed = true }
                if GetMoney() < c.buyout then return d:SetLine("|cffd9736bNot enough gold for " .. Money(c.buyout) .. ".|r") end
                ns.Purchase:Buy(c, {
                    onBought = function(bought)
                        quoted = nil
                        session.bought = session.bought + bought.count
                        session.spent = session.spent + bought.buyout
                        self.spent = (self.spent or 0) + bought.buyout
                        ns.Stock:RecordPurchase(bought.itemID, bought.count)
                        ns.Compare:RecordPaid(tostring(bought.itemID), bought.count, bought.buyout)
                        ns:Changed()
                        self:SetStatus(("Bought %d / %d %s  ·  spent %s"):format(session.bought, session.target, link, Money(session.spent)))
                        if session.bought >= session.target then return Finish(d) end
                        d:SetBusy(false)
                        Update(d)
                        -- What's left on the market changed: refresh the listings for the next estimate.
                        ns.Scanner:Listings(g, function(listings)
                            if listings and self.token == token and self.group == g then
                                self.listings = listings
                                self:ShowListings()
                                if d:IsShown() and d.opts and d.opts.tag == tag and not d.busy then Update(d) end
                            end
                        end)
                    end,
                    onGone = function()
                        quoted = nil
                        d:SetBusy(false); Update(d)
                        d:SetLine("|cffd9736bSomeone bought those first. Click to price the next ones.|r")
                    end,
                    onFail = function(reason)
                        quoted = nil
                        d:SetBusy(false); Update(d)
                        d:SetLine("|cffd9736bNot bought (" .. reason .. "). Click to try again.|r")
                    end,
                    onCancel = function() d:SetBusy(false); Update(d) end,
                })
                if ns.Purchase.state == "bidding" then d:SetBusy(true); d:SetMainLabel("Buying...") end
                return
            end
            -- Get-price click: ask the exact price of the next round.
            local round = Round()
            local estimate = CommodityCost(Listings(), round)
            ns.Purchase:Quote(g.itemID, round, {
                onPrice = function(unit, total)
                    quoted = { qty = round, unit = unit, total = total, estimate = estimate }
                    d:SetBusy(false)
                    Update(d)
                end,
                onFail = function(reason)
                    d:SetBusy(false)
                    Update(d)
                    d:SetLine("|cffd9736bNo price yet (" .. reason .. "). Click again.|r")
                end,
            })
            if starting then d:LockQty(true) end
            if ns.Purchase.state == "quoting" then d:SetBusy(true); d:SetMainLabel("Getting price...") end
        end,
        onCancel = function()
            if quoted then ns.Purchase:Cancel() end
            if session and session.bought > 0 and session.bought < session.target and self.token == token then
                self:SetStatus(("Bought %d of %d %s  ·  spent %s"):format(session.bought, session.target, link, Money(session.spent)))
                if self.group == g then self:OpenGroup(g) end
            end
        end,
    })
end

function M:BuyNow(c)
    if self.state ~= "idle" or not c then return end
    local token, g = self.token, self.group
    self.state = "buying"
    C_Timer.After(0, function() self:Refresh() end) -- after the game call below (Purchase.lua)
    local function Again()
        if self.token ~= token then return end
        self.state = "idle"
        if g then self:OpenGroup(g) else self:Refresh() end
    end
    ns.Purchase:Buy(c, {
        onBought = function(bought)
            if self.token ~= token then return end
            ns.Stock:RecordPurchase(bought.itemID, bought.count)
            ns.Compare:RecordPaid(bought.variant or (bought.itemID and tostring(bought.itemID)), bought.count, bought.buyout)
            self.spent = (self.spent or 0) + bought.buyout
            ns:Print(("Bought %dx %s for %s."):format(bought.count, bought.link or "?", Money(bought.buyout)))
            self:SetStatus(("Bought %dx for %s  ·  spent this visit %s"):format(bought.count, Money(bought.buyout), Money(self.spent)))
            ns:Changed()
            Again()
        end,
        onGone = function()
            if self.token ~= token then return end
            ns:Print("Someone bought that first.", true)
            Again()
        end,
        onFail = function(reason)
            if self.token ~= token then return end
            self:SetStatus("|cffd9736bNot bought: " .. reason .. "|r")
            Again()
        end,
        onCancel = function()
            if self.token ~= token then return end
            self.state = "idle"; self:Refresh()
        end,
    })
    if self.state == "buying" and not ns.Purchase:Busy() then self.state = "idle"; self:Refresh() end
end

-- Add to: stackable items ask how many first, like Buy; anything else adds one (or qty).
-- qty: the amount the dialog starts at (a crate's filler). g: the group it was picked from; an
-- enchanted (or random-suffix) group goes on the list as that variant, with its cheapest price.
function M:AddItem(itemID, qty, g)
    local target = self:Target()
    if g and g.link and not ns.Catalog:IsPlain(g.variant) then
        return ns.Lists:AddItem(g.link, qty or 1, target, g.minUnit or g.unit)
    end
    if not IsStackable(self, itemID) then return ns.Lists:AddItem(itemID, qty or 1, target) end
    local e = ns.Catalog:Get(itemID) or {}
    local market = ns.Catalog:PriceFor(itemID)
    W.QuantityDialog({
        title = "Add " .. (e.link or e.name or ("item " .. itemID)) .. " to " .. target.name,
        icon = W.IconFor(e.icon and e or { itemID = itemID }), qty = qty or self.defaultQty or 1, mainLabel = "Add",
        describe = function(q)
            if not market then return "No market price yet." end
            return ("Market %s each, about %s for %d."):format(Money(market), Money(market * q), q)
        end,
        onMain = function(q, d) d:Close(); ns.Lists:AddItem(itemID, q, target) end,
    })
end

-- Add search: how many the Cart should buy of anything matching.
function M:AddSearch()
    local f, target = self.filters:Read(), self:Target()
    if ns.Search.IsEmpty(f) then return ns:Print("That search has no filters. Type a name or pick some filters first.", true) end
    W.QuantityDialog({
        title = "Add search to " .. target.name, icon = "Interface\\Icons\\INV_Misc_Spyglass_03",
        qty = self.defaultQty or 1, mainLabel = "Add",
        describe = function(q) return ("The Cart buys %d of anything matching: %s"):format(q, ns.Search:Describe(f)) end,
        onMain = function(q, d) d:Close(); ns.Lists:AddSearch(f, q, target) end,
    })
end

function M:SelectedItem()
    if self.group then return self.group.itemID end
end

-- Cart search entries: load one into the filters and offer Save to entry.
function M:EditEntry(entry)
    self.editing = entry
    self.filters:Load(entry.filter)
    self:Refresh()
    self:Run(entry.filter)
end

function M:SaveEdit()
    local entry = self.editing
    if not entry then return end
    local f = self.filters:Read()
    if ns.Search.IsEmpty(f) then return ns:Print("That search has no filters.", true) end
    entry.filter = ns.Search.Copy(f)
    entry.filter.quantity = nil
    entry.label = nil
    ns:Print("Updated the search entry: " .. ns.Lists:Describe(entry), true)
    self:EndEdit()
    ns:Changed()
end

function M:EndEdit()
    self.editing = nil
    self:Refresh()
    if self.onEndEdit then self.onEndEdit() end
end

function M:UpdateFooter()
    local editing = self.editing ~= nil
    self.addSearch:SetShown(not editing)
    self.saveEntry:SetShown(editing); self.cancelEdit:SetShown(editing)
    if self.targetPicker then
        local target, kind = ns.Lists:AddTarget()
        self.targetPicker:SetValue(nil, (kind == "template" and "|cff55d6be" or "") .. target.name .. (kind == "template" and "|r" or ""))
    end
    local listings = self.mode == "listings"
    -- Items: pages; listings: Buy.
    for _, w in ipairs({ self.prev, self.pageText, self.nextBtn }) do w:SetShown(not listings) end
    self.buy:SetShown(listings)
    if not listings then
        local page, pages = self.page or 1, self.pages or 1
        self.pageText:SetText(("Page %d of %d"):format(page, pages))
        self.prev:SetEnabled(page > 1); self.prev:SetAlpha(page > 1 and 1 or 0.4)
        self.nextBtn:SetEnabled(page < pages); self.nextBtn:SetAlpha(page < pages and 1 or 0.4)
    end
    local hasItem = self:SelectedItem() ~= nil
    self.addItem:SetEnabled(hasItem); self.addItem:SetAlpha(hasItem and 1 or 0.5)
end

function M:ButtonState()
    local s = self.state
    if s == "searching" then return "Searching...", false end
    if s == "listing" then return "Reading listings...", false end
    if s == "focusing" then return "Finding auction...", false end
    if s == "buying" then return ns.Purchase.state == "confirm" and "Waiting for you..." or "Buying...", false end
    if self.mode ~= "listings" then return "Pick an item to buy", false end
    if ns.Buyer:Running() then return "The Cart is buying", false end
    local first = self.listings[1]
    if first and first.commodity then
        -- Trade goods: Buy asks how many; this is the cheapest price each.
        return ("Buy %s - %s each"):format(ItemLink(self.group), Money(first.unit)), ns.Purchase:CanQuery() and not ns.Purchase:Busy()
    end
    local c = self.candidate
    if not c then return #self.listings > 0 and "Select a listing" or "Nothing to buy", false end
    if GetMoney() < c.buyout then return "Not enough gold - " .. Money(c.buyout), false end
    local name = c.link or ItemLink(self.group)
    if (c.count or 1) > 1 then name = c.count .. "x " .. name end
    return ("Buy %s - %s"):format(name, Money(c.buyout)), ns.Purchase:CanBuy(c)
end

function M:UpdateButton()
    local text, enabled = self:ButtonState()
    local b = self.buy
    b.text:SetText(text)
    local fit = math.ceil(b.text:GetStringWidth() or 0) + BUY_PAD * 2 + 4
    b:SetWidth(math.min(b.maxWidth, math.max(b.minWidth, fit)))
    b:SetEnabled(enabled)
    b.text:SetAlpha(enabled and 1 or 0.6)
    if enabled then
        b.fill:SetVertexColor(COOL_GREEN[1], COOL_GREEN[2], COOL_GREEN[3], 0.35)
        b:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    else
        b.fill:SetVertexColor(0, 0, 0, 0)
        b:SetBackdropBorderColor(PAL.border[1], PAL.border[2], PAL.border[3], 1)
    end
end

function M:Refresh()
    self:UpdateFooter()
    self:UpdateButton()
end

ns:On("AUCTION_HOUSE_CLOSED", function()
    if QuartermasterQuantityDialog and QuartermasterQuantityDialog:IsShown() then QuartermasterQuantityDialog:Hide() end
    for _, v in ipairs(AuctionSearch.views) do
        v.state, v.candidate, v.token = "idle", nil, (v.token or 0) + 1
        if v.mode == "listings" then v:ShowGroups() end
    end
end)
ns:On("PLAYER_MONEY", function()
    for _, v in ipairs(AuctionSearch.views) do if v:IsVisible() then v:UpdateButton() end end
end)
