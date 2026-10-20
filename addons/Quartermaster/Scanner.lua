local _, ns = ...

-- Classic auction house queries (QueryAuctionItems / AUCTION_ITEM_LIST_UPDATE), modelled on
-- Auctionator's Source_LegacyAH/AH/Mixins/Scan.lua. One query at a time; results only count
-- if they arrive for a query we sent and every row matches the item we searched for.
local Scanner = {}
ns.Scanner = Scanner

local PAGE_SIZE = NUM_AUCTION_ITEMS_PER_PAGE or 50
local MAX_PAGES = 10
local TIMEOUT = 10
local OWNER_WAIT = 1.5

-- GetAuctionItemInfo positions (same as Auctionator.Constants.AuctionItemInfo).
local I_COUNT, I_BUYOUT, I_BID_AMOUNT, I_OWNER, I_SALE_STATUS, I_ITEM_ID = 3, 10, 11, 14, 16, 17

local frame = CreateFrame("Frame")
local job         -- { name, query, page, onPage(rows), sent, sentAt, ours }
local sendingOurs = false
local waiting     -- modern search in flight: { id, cb }
local browsing    -- modern browse search in flight: { f, cb, onProgress, sentAt }
local generation = 0

function Scanner:Busy() return job ~= nil or waiting ~= nil or browsing ~= nil end

function Scanner:Abort()
    job, waiting, browsing = nil, nil, nil
    generation = generation + 1
    frame:Hide()
end

function Scanner:Legacy() return QueryAuctionItems ~= nil and AuctionFrame ~= nil and AuctionFrame:IsShown() end
function Scanner:Modern()
    return C_AuctionHouse ~= nil and C_AuctionHouse.SendSearchQuery ~= nil and AuctionHouseFrame ~= nil
        and AuctionHouseFrame:IsShown()
end

local function Send()
    sendingOurs = true
    SortAuctionSetSort("list", "unitprice")
    local q = job.query
    if q then
        QueryAuctionItems(q.text, q.minLevel, q.maxLevel, job.page, q.usable, q.quality, false, q.exact, q.filterData)
    else
        QueryAuctionItems(job.name, nil, nil, job.page, false, nil, false, true)
    end
    sendingOurs = false
    job.sent, job.sentAt = true, GetTime()
end

frame:Hide()
frame:SetScript("OnUpdate", function()
    if not job then frame:Hide() return end
    if not job.sent then
        if CanSendAuctionQuery() then Send() end
    elseif GetTime() - job.sentAt > TIMEOUT then
        job.sent = false -- no answer: ask again
    end
end)

-- Another addon (or the Browse tab) searched while we waited: our page is gone, so ask again.
if QueryAuctionItems then
    hooksecurefunc("QueryAuctionItems", function()
        if job and job.sent and not sendingOurs then job.sent = false end
    end)
end

-- Reads the current "list" page. Returns nil while row data is still incomplete, false if the
-- page holds some other item, and otherwise the rows plus whether every seller name has loaded.
function Scanner:ReadPage(name, page)
    local rows, allOwners = {}, true
    local lname = name and name:lower()
    for index = 1, GetNumAuctionItems("list") do
        local info = { GetAuctionItemInfo("list", index) }
        local link = GetAuctionItemLink("list", index)
        if not info[1] or not link then return nil end
        if lname and info[1]:lower() ~= lname then return false end
        rows[#rows + 1] = {
            index = index, page = page, link = link, name = info[1],
            itemID = info[I_ITEM_ID], variant = ns.Catalog:Variant(link),
            count = info[I_COUNT] or 1,
            buyout = info[I_BUYOUT] or 0,
            bidAmount = info[I_BID_AMOUNT] or 0,
            owner = info[I_OWNER],
            sold = info[I_SALE_STATUS] == 1,
        }
        if not info[I_OWNER] then allOwners = false end
    end
    return rows, allOwners
end

if QueryAuctionItems then
    frame:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
end
frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
frame:SetScript("OnEvent", function(_, event)
    if event == "AUCTION_HOUSE_CLOSED" then return Scanner:Abort() end
    -- Nothing sent this frame can have been answered yet; this is a late update for an older page.
    if not job or not job.sent or GetTime() == job.sentAt then return end
    local rows, allOwners = Scanner:ReadPage(job.name, job.page)
    if rows == nil then return end          -- wait for the rest of the row data
    if rows == false then job.sent = false return end -- someone else's results
    -- Like Auctionator, wait for seller names (they arrive in later updates), but not forever.
    if not allOwners then
        job.firstUpdate = job.firstUpdate or GetTime()
        if GetTime() - job.firstUpdate < OWNER_WAIT - 0.1 then
            C_Timer.After(OWNER_WAIT, function()
                if job and job.sent and job.firstUpdate then frame:GetScript("OnEvent")(frame, "AUCTION_ITEM_LIST_UPDATE") end
            end)
            return
        end
    end
    local current = job
    job = nil
    frame:Hide()
    local _, total = GetNumAuctionItems("list")
    current.onPage(rows, current.page, total or #rows)
end)

-- Every query of ours: a running Auctionator summary scan pauses first (FullScan.lua), and the time
-- is noted so a paused scan only starts again once we've been quiet for a while.
local function BeforeQuery()
    if ns.FullScan then ns.FullScan:Yield() end
    Scanner.lastQuery = GetTime()
end

local function Start(name, page, onPage, query)
    BeforeQuery()
    job = { name = name, query = query, page = page, onPage = onPage, sent = false }
    frame:Show()
end

-- Loads one page so its rows can be bid on. cb(rows)
function Scanner:FocusPage(name, page, cb)
    Start(name, page, function(rows) cb(rows) end)
end

-- Every listing of an item, cheapest unit price first. cb(listings) with
-- listing = { page, index, link, itemID, variant, count, buyout, unit, owner }
-- variant (Catalog:Variant): only copies with that enchant/suffix; nil for every copy.
function Scanner:ScanAll(name, cb, onProgress, variant)
    local all = {}
    local me = UnitName("player")
    local function OnPage(rows, page, total)
        for _, r in ipairs(rows) do
            if r.buyout > 0 and not r.sold and r.owner ~= me and (not variant or r.variant == variant) then
                r.unit = r.buyout / r.count
                all[#all + 1] = r
            end
        end
        if (page + 1) * PAGE_SIZE < total and page + 1 < MAX_PAGES then
            if onProgress then onProgress(page + 1) end
            Start(name, page + 1, OnPage)
        else
            table.sort(all, function(a, b)
                if a.unit ~= b.unit then return a.unit < b.unit end
                return a.count < b.count
            end)
            cb(all)
        end
    end
    Start(name, 0, OnPage)
end

-- ---------------------------------------------------------------------------
-- Modern auction house (C_AuctionHouse), as Auctionator's Source_ModernAH buying tabs use it.
-- One search per item; the answer comes back as a commodity or an item search event.
-- ---------------------------------------------------------------------------

local MODERN_TIMEOUT = 8
local SORTS = { { sortOrder = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0, reverseSort = false } }

-- Every listing of an item, cheapest unit price first, or nil if no answer came. cb(listings) with
-- commodity listing = { unit, count, buyout, commodity = true }
-- item listing      = { unit, count, buyout, auctionID, link, variant }
-- item is an itemID, or the server's itemKey from a browse result (preferred when known).
-- variant (Catalog:Variant): only copies with that enchant/suffix; nil for every copy.
--
-- Blizzard often ignores a search for an item whose key info isn't cached yet, and sometimes answers
-- with no results when there are some (Auctionator's Source_ModernAH/AH/Mixins/SearchScan.lua works
-- around the same thing). So: wait for the key info first, check each answer, and search again when
-- it looks wrong or never comes.
local SEARCH_TRIES = 3
local SEARCH_TRY_TIMEOUT = 4
local KEY_INFO_WAIT = 3

local function HasKeyInfo(key)
    if not C_AuctionHouse.GetItemKeyInfo then return true end
    return C_AuctionHouse.GetItemKeyInfo(key) ~= nil
end

function Scanner:SearchModern(item, cb, variant)
    local key = type(item) == "table" and item or C_AuctionHouse.MakeItemKey(item)
    local itemID = key.itemID
    local mine = generation
    local tries, waited = 0, 0
    local function Send()
        if generation ~= mine or not Scanner:Modern() then return end
        local ready = C_AuctionHouse.IsThrottledMessageSystemReady
        if ready and not ready() then return C_Timer.After(0.5, Send) end
        -- Asking for the key info also requests it; give it a moment to arrive.
        if not HasKeyInfo(key) and waited < KEY_INFO_WAIT then
            waited = waited + 0.2
            return C_Timer.After(0.2, Send)
        end
        tries = tries + 1
        local w = { id = itemID, key = key, cb = cb, variant = variant, retry = tries < SEARCH_TRIES and Send or nil }
        waiting = w
        BeforeQuery()
        C_AuctionHouse.SendSearchQuery(key, SORTS, false)
        C_Timer.After(SEARCH_TRY_TIMEOUT, function()
            if waiting ~= w then return end
            waiting = nil
            if w.retry then w.retry() else cb(nil) end -- ignored: ask again, or give up
        end)
    end
    Send()
end

local function Answer(id, listings)
    if not waiting or waiting.id ~= id then return end
    local cb = waiting.cb
    waiting = nil
    table.sort(listings, function(a, b) return a.unit < b.unit end)
    cb(listings)
end

-- An answer with nothing in it while the server says results are still coming (or none arrived at
-- all) is the empty answer Blizzard sometimes sends: search again while tries are left.
local function RetryIfEmpty(has, full, quantity)
    if not waiting or not waiting.retry then return false end
    if has ~= false and not (full == false and (quantity or 0) == 0) then return false end
    local retry = waiting.retry
    waiting = nil
    C_Timer.After(0.3, retry)
    return true
end

local function Call(fn, ...) if fn then return fn(...) end end

ns:On("COMMODITY_SEARCH_RESULTS_UPDATED", function(id)
    if not waiting or waiting.id ~= id then return end
    local has = Call(C_AuctionHouse.HasSearchResults, waiting.key)
    local full = Call(C_AuctionHouse.HasFullCommoditySearchResults, id)
    local quantity = Call(C_AuctionHouse.GetCommoditySearchResultsQuantity, id)
    if RetryIfEmpty(has, full, quantity) then return end
    local listings = {}
    -- Trade goods have no enchants: a search for an enchanted variant finds none of them.
    local count = ns.Catalog:IsPlain(waiting.variant) and C_AuctionHouse.GetNumCommoditySearchResults(id) or 0
    for i = 1, count do
        local r = C_AuctionHouse.GetCommoditySearchResultInfo(id, i)
        if r and r.unitPrice and r.quantity and r.quantity > 0 and not r.containsOwnerItem then
            listings[#listings + 1] = { unit = r.unitPrice, count = r.quantity, buyout = r.unitPrice * r.quantity,
                commodity = true, itemID = id }
        end
    end
    Answer(id, listings)
end)

ns:On("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
    local id = itemKey and itemKey.itemID
    if not waiting or waiting.id ~= id then return end
    local has = Call(C_AuctionHouse.HasSearchResults, itemKey)
    local full = Call(C_AuctionHouse.HasFullItemSearchResults, itemKey)
    local quantity = Call(C_AuctionHouse.GetItemSearchResultsQuantity, itemKey)
    if RetryIfEmpty(has, full, quantity) then return end
    local listings = {}
    -- Identical auctions come grouped in one row: buyoutAmount is the price of each one, quantity how
    -- many, and a bid on the row's auctionID buys one of them at buyoutAmount (as Auctionator does).
    -- So a listing is one purchase (count 1 at unit = buyout), with `available` at that price.
    for i = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) or 0 do
        local r = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
        local variant = r and (ns.Catalog:Variant(r.itemLink) or tostring(id))
        if r and r.buyoutAmount and r.buyoutAmount > 0 and not r.containsOwnerItem
            and (not waiting.variant or variant == waiting.variant) then
            listings[#listings + 1] = { unit = r.buyoutAmount, count = 1, available = r.quantity or 1, buyout = r.buyoutAmount,
                auctionID = r.auctionID, link = r.itemLink, itemID = id, variant = variant }
        end
    end
    Answer(id, listings)
end)

-- ---------------------------------------------------------------------------
-- Browse searches with the shared filters (Search.lua): everything matching, grouped by item.
-- cb(groups) with group = { itemID, variant, link, name, minUnit, available, ownerHas, ilvl }, cheapest
-- first, or nil if no answer came. Filters the server can't apply are checked here. Classic groups
-- are one variant each (enchant/suffix); modern ones are the server's itemKeys, variant unknown.
-- ---------------------------------------------------------------------------

local MAX_BROWSE_GROUPS = 500
local ITEM_WAIT = 3

-- Waits (briefly) for item data so names, levels and slots can be checked, then filters.
local function FinishBrowse(groups, f, cb, mine)
    local started = GetTime()
    local function Try()
        if generation ~= mine then return end
        local pending = false
        for _, g in ipairs(groups) do
            local e = ns.Catalog:Get(g.itemID)
            if e and not e.loaded then pending = true break end
        end
        if pending and GetTime() - started < ITEM_WAIT then return C_Timer.After(0.25, Try) end
        local out = {}
        for _, g in ipairs(groups) do
            local e = ns.Catalog:Get(g.itemID)
            if e and ns.Search:LiveMatches(e, f, g.minUnit, g.ilvl) then
                g.name, g.link = g.name or e.name, g.link or e.link
                g.quality, g.reqLevel, g.ilvl = e.quality, e.reqLevel, g.ilvl or e.ilvl
                out[#out + 1] = g
            end
        end
        table.sort(out, function(a, b)
            if a.minUnit ~= b.minUnit then return a.minUnit < b.minUnit end
            if a.itemID ~= b.itemID then return a.itemID < b.itemID end
            return (a.variant or "") < (b.variant or "")
        end)
        cb(out)
    end
    Try()
end

-- Modern: C_AuctionHouse.SendBrowseQuery, then more results until the server has sent them all.
local function QualityFilters(f)
    local filters = {}
    local F = Enum and Enum.AuctionHouseFilter
    if not F then return filters end
    if f.usable and F.UsableOnly then filters[#filters + 1] = F.UsableOnly end
    -- No ExactMatch: the server then finds nothing on some clients. Like Auctionator, search by the
    -- name and keep only exact matches here (Search:LiveMatches).
    if f.quality then
        local byQuality = { F.PoorQuality, F.CommonQuality, F.UncommonQuality, F.RareQuality, F.EpicQuality, F.LegendaryQuality, F.ArtifactQuality }
        for q = f.quality, 6 do
            if byQuality[q + 1] then filters[#filters + 1] = byQuality[q + 1] end
        end
    end
    return filters
end

local BROWSE_SORTS = {
    { sortOrder = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0, reverseSort = false },
    { sortOrder = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Name or 1, reverseSort = false },
}

local function BrowseModern(f, cb, onProgress)
    local mine = generation
    local function Send()
        if generation ~= mine or not Scanner:Modern() then return end
        local ready = C_AuctionHouse.IsThrottledMessageSystemReady
        if ready and not ready() then return C_Timer.After(0.5, Send) end
        local b = { f = f, cb = cb, onProgress = onProgress, mine = mine, sentAt = GetTime() }
        browsing = b
        local classFilters = {}
        if f.classID then classFilters[1] = { classID = f.classID, subClassID = f.subClassID } end
        BeforeQuery()
        -- Flagged so FullScan's hook doesn't take our search for another addon's full scan.
        Scanner.sendingOwn = true
        local sent = pcall(C_AuctionHouse.SendBrowseQuery, {
            searchString = f.text or "", sorts = BROWSE_SORTS,
            minLevel = f.minLevel or 0, maxLevel = f.maxLevel or 0,
            filters = QualityFilters(f), itemClassFilters = classFilters,
        })
        Scanner.sendingOwn = false
        if not sent then browsing = nil; return cb(nil) end
        local function Watch()
            if browsing ~= b then return end
            if GetTime() - b.sentAt > MODERN_TIMEOUT then browsing = nil; return cb(nil) end
            C_Timer.After(1, Watch)
        end
        C_Timer.After(1, Watch)
    end
    Send()
end

local function OnBrowseResults()
    local b = browsing
    if not b then return end
    b.sentAt = GetTime()
    local results = C_AuctionHouse.GetBrowseResults() or {}
    if b.onProgress then b.onProgress(#results) end
    if not C_AuctionHouse.HasFullBrowseResults() and #results < MAX_BROWSE_GROUPS then
        local function More()
            if browsing ~= b then return end
            local ready = C_AuctionHouse.IsThrottledMessageSystemReady
            if ready and not ready() then return C_Timer.After(0.3, More) end
            Scanner.lastQuery = GetTime()
            C_AuctionHouse.RequestMoreBrowseResults()
        end
        return More()
    end
    browsing = nil
    local groups = {}
    for _, r in ipairs(results) do
        local key = r.itemKey
        if key and key.itemID and r.minPrice and r.minPrice > 0 and (r.totalQuantity or 0) > 0 then
            groups[#groups + 1] = { itemID = key.itemID, itemKey = key, minUnit = r.minPrice, available = r.totalQuantity,
                ownerHas = r.containsOwnerItem, ilvl = key.itemLevel and key.itemLevel > 0 and key.itemLevel or nil }
        end
    end
    FinishBrowse(groups, b.f, b.cb, b.mine)
end
ns:On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", OnBrowseResults)
ns:On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", OnBrowseResults)

-- Classic: QueryAuctionItems with the filters, page by page, grouped by item here.
local function BrowseLegacy(f, cb, onProgress)
    local mine = generation
    local me = UnitName("player")
    local query = {
        text = f.text or "", minLevel = f.minLevel, maxLevel = f.maxLevel, usable = f.usable or false,
        quality = f.quality, exact = f.exact or false,
        filterData = f.classID and { { classID = f.classID, subClassID = f.subClassID } } or nil,
    }
    local byItem, groups = {}, {}
    local function OnPage(rows, page, total)
        if generation ~= mine then return end
        for _, r in ipairs(rows) do
            if r.itemID and r.buyout > 0 and not r.sold then
                -- One group per variant: an enchant or suffix makes it a different item to buy.
                local variant = r.variant or tostring(r.itemID)
                local g = byItem[variant]
                if not g then
                    g = { itemID = r.itemID, variant = variant, link = r.link, name = r.name, minUnit = math.huge, available = 0 }
                    byItem[variant] = g
                    groups[#groups + 1] = g
                end
                if r.owner == me then g.ownerHas = true
                else
                    g.available = g.available + r.count
                    g.minUnit = math.min(g.minUnit, r.buyout / r.count)
                end
            end
        end
        if (page + 1) * PAGE_SIZE < total and page + 1 < MAX_PAGES then
            if onProgress then onProgress(page + 1) end
            Start(nil, page + 1, OnPage, query)
        else
            local listed = {}
            for _, g in ipairs(groups) do if g.available > 0 then listed[#listed + 1] = g end end
            FinishBrowse(listed, f, cb, mine)
        end
    end
    Start(nil, 0, OnPage, query)
end

function Scanner:Browse(f, cb, onProgress)
    if self:Modern() then BrowseModern(f, cb, onProgress)
    elseif self:Legacy() then BrowseLegacy(f, cb, onProgress)
    else cb(nil) end
end

-- Every listing of one item from a browse result, cheapest first (same shapes as SearchModern/ScanAll).
-- variant: only those copies (default: the group's own variant, if it has one).
function Scanner:Listings(group, cb, onProgress, variant)
    variant = variant or group.variant
    if self:Modern() then return self:SearchModern(group.itemKey or group.itemID, cb, variant) end
    local name = group.name or (ns.Catalog:Get(group.itemID) or {}).name
    if not name then return cb(nil) end
    self:ScanAll(name, cb, onProgress, variant)
end
