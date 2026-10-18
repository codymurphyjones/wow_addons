local _, ns = ...
local C = ns.Compat

-- Wealth Planner's own price history, one entry per item per day:
--   d[day] = { lo, hi, c (last price seen that day), q (most listed at once), n (samples),
--              qm (listed at or near the lowest price, last scan), a (most auctions at once),
--              ms, sc (sum and count of scans' lowest prices: their average is the day's typical low) }
--   w[week] = { lo, hi, cs, cn (closes summed and counted), q, qn } once a day is older than the
--             history setting (kept two years)
--   s = the last SAMPLES raw samples { t, p, q }, for intraday views.
--   x = every scan's figures for the last two weeks (History.lua)
-- Prices come from three places, all optional:
--   1. Browse results at the auction house, whoever asked for them (Auctionator's summary scan,
--      another addon, the Blizzard UI, or our own "Scan market"). These carry supply too.
--   2. Auctionator's public API after each of its scans (price only).
--   3. Our own full browse scan (/wp scan).
local Prices = {}
ns.Prices = Prices

local SAMPLES = 48
local SAMPLE_GAP = 10 * 60   -- a new raw sample at most every 10 minutes per item
local SCAN_TIMEOUT = 20      -- seconds without results before a scan is given up

Prices.scan = nil -- { started, groups } while our own scan runs

local function Items()
    local key = ns.RealmKey()
    local realm = ns.db.realms[key]
    if not realm then realm = { items = {} }; ns.db.realms[key] = realm end
    return realm.items
end
Prices.Items = Items

function Prices:Entry(id) return id and Items()[id] end

-- Records one observation. qty is the number listed, if known. extra (from a scan, History.lua):
-- { qm = listed at the lowest price, a = auctions, scan = true when part of a whole-market scan }.
function Prices:Record(id, price, qty, extra)
    if not (id and price and price > 0) then return end
    local items = Items()
    local e = items[id]
    if not e then e = { d = {}, s = {} }; items[id] = e end
    local now, day = time(), ns.Today()
    local d = e.d[day]
    if not d then
        d = { lo = price, hi = price, c = price, q = qty, n = 0 }
        e.d[day] = d
    end
    if price < d.lo then d.lo = price end
    if price > d.hi then d.hi = price end
    d.c, d.n = price, d.n + 1
    if qty and (not d.q or qty > d.q) then d.q = qty end
    if extra then
        if extra.qm then d.qm = extra.qm end
        if extra.a and (not d.a or extra.a > d.a) then d.a = extra.a end
        if extra.scan then d.ms, d.sc = (d.ms or 0) + price, (d.sc or 0) + 1 end
    end
    local last = e.s[#e.s]
    if last and now - last[1] < SAMPLE_GAP then
        last[2], last[3] = price, qty or last[3]
    else
        e.s[#e.s + 1] = { now, price, qty }
        while #e.s > SAMPLES do table.remove(e.s, 1) end
    end
    e.t = now
    if ns.Analytics then ns.Analytics:Invalidate(id) end
    if ns.Patterns then ns.Patterns:Observe(id, price, qty) end
    if self.onRecord then self.onRecord(id, price) end
end

-- Latest known price: today's, else the newest sample, else Auctionator's.
function Prices:Price(id)
    local e = self:Entry(id)
    if e then
        local d = e.d[ns.Today()]
        if d then return d.c, e.t end
        local s = e.s[#e.s]
        if s then return s[2], s[1] end
    end
    return self:AuctionatorPrice(id), nil
end

-- Vendor sell price, the floor under any market price.
function Prices:Vendor(id)
    local sell = select(11, C.GetItemInfo(id))
    return sell and sell > 0 and sell or nil
end

-- ---------------------------------------------------------------------------
-- Vendor goods: items any vendor sells (Data\VendorItems.lua, from QuestieDB)
-- ---------------------------------------------------------------------------

-- Vendors sell it (for gold, unlimited or restocking).
function Prices:VendorSold(id) return ns.VendorItems and ns.VendorItems[id] ~= nil or false end

-- What a vendor charges for one, and whether that's the price you've seen (true) or an estimate:
-- vendors usually charge four times what they pay you for an item.
function Prices:VendorBuy(id)
    if not self:VendorSold(id) then return nil end
    local seen = ns.db.vendorBuy[id]
    if seen then return seen, true end
    local sell = self:Vendor(id)
    if sell then return sell * 4, false end
    return nil
end

-- Learns vendors' prices from every merchant window you open.
local function ReadMerchant()
    local learned = false
    for i = 1, (GetMerchantNumItems and GetMerchantNumItems() or 0) do
        local id = C.IDFromLink(GetMerchantItemLink(i))
        local _, _, price, quantity, _, _, _, extendedCost = GetMerchantItemInfo(i)
        price, quantity = C.Num and C.Num(price) or price, C.Num and C.Num(quantity) or quantity
        if id and type(price) == "number" and price > 0 and not extendedCost then
            local each = math.floor(price / math.max(1, quantity or 1) + 0.5)
            if ns.db.vendorBuy[id] ~= each then
                ns.db.vendorBuy[id] = each
                if ns.Analytics then ns.Analytics:Invalidate(id) end
                learned = true
            end
        end
    end
    if learned then ns:Changed() end
end
ns:On("MERCHANT_SHOW", function() C_Timer.After(0.2, ReadMerchant) end)
ns:On("MERCHANT_UPDATE", ReadMerchant)

-- ---------------------------------------------------------------------------
-- Auctionator (public API only)
-- ---------------------------------------------------------------------------

local function API() return type(Auctionator) == "table" and Auctionator.API and Auctionator.API.v1 end

function Prices:HasAuctionator() return API() and API().GetAuctionPriceByItemID ~= nil or false end

function Prices:AuctionatorPrice(id)
    local api = API()
    if not (api and api.GetAuctionPriceByItemID) then return nil end
    local ok, price = pcall(api.GetAuctionPriceByItemID, ns.CALLER, id)
    return ok and type(price) == "number" and price > 0 and price or nil
end

-- Items worth sampling from Auctionator: the watchlist, your holdings and everything farmable.
function Prices:Tracked()
    local out = {}
    for id in pairs(ns.db.watch) do out[id] = true end
    for _, h in pairs(ns.db.holdings) do
        for id in pairs(h.bags or {}) do out[id] = true end
        for id in pairs(h.bank or {}) do out[id] = true end
    end
    if ns.FarmData then for id in pairs(ns.FarmData.items) do out[id] = true end end
    return out
end

-- Days since Auctionator last saw the item, or nil.
function Prices:AuctionatorAge(id)
    local api = API()
    if not (api and api.GetAuctionAgeByItemID) then return nil end
    local ok, age = pcall(api.GetAuctionAgeByItemID, ns.CALLER, id)
    return ok and type(age) == "number" and age or nil
end

local function SampleAuctionator()
    local items = Items()
    for id in pairs(Prices:Tracked()) do
        -- An old price isn't today's price: only what Auctionator saw today is recorded.
        local price = Prices:AuctionatorAge(id) == 0 and Prices:AuctionatorPrice(id) or nil
        -- The API only knows the last price: record it once per change, not on every callback.
        local e = items[id]
        local last = e and e.s[#e.s]
        if price and not (last and last[2] == price and time() - last[1] < 6 * 3600) then
            Prices:Record(id, price, nil)
        end
    end
    Prices:ImportAuctionator()
    ns:Changed()
end

-- Auctionator's daily history (its own database, not the v1 API, so every call is guarded): the
-- days Wealth Planner wasn't there for, so signals and averages work without weeks of our own
-- scans. Only days we have no entry for are filled (ours always win), marked src = "a". Items we
-- already know plus the tracked ones, IMPORT_STEP a frame, at most once every IMPORT_GAP seconds.
local IMPORT_STEP, IMPORT_GAP = 500, 10 * 60
local importAt, importing = 0, false
function Prices:ImportAuctionator()
    local db = type(Auctionator) == "table" and Auctionator.Database
    local day0 = type(Auctionator) == "table" and Auctionator.Constants and Auctionator.Constants.SCAN_DAY_0
    if importing or not (db and db.GetPriceHistory and day0) or time() - importAt < IMPORT_GAP then return end
    importing, importAt = true, time()
    local items = Items()
    local ids = {}
    for id in pairs(items) do ids[#ids + 1] = id end
    for id in pairs(self:Tracked()) do if not items[id] then ids[#ids + 1] = id end end
    local oldest = ns.Today() - (ns.db.options.historyDays or 120)
    local i, added = 1, 0
    local function Step()
        for _ = 1, IMPORT_STEP do
            local id = ids[i]
            if not id then break end
            i = i + 1
            local ok, hist = pcall(db.GetPriceHistory, db, tostring(id))
            if ok and type(hist) == "table" then
                for _, h in ipairs(hist) do
                    local raw, lo, hi = tonumber(h.rawDay), tonumber(h.minSeen), tonumber(h.maxSeen)
                    if raw and lo and lo > 0 then
                        -- Auctionator's days start at local midnight: noon of it is safely inside our day.
                        local day = math.floor((raw * 86400 + day0 + 43200) / 86400)
                        local e = items[id]
                        if day >= oldest and not (e and e.d[day]) then
                            if not e then e = { d = {}, s = {} }; items[id] = e end
                            e.d[day] = { lo = lo, hi = math.max(lo, hi or lo), c = lo, q = tonumber(h.available), n = 0, src = "a" }
                            added = added + 1
                        end
                    end
                end
            end
        end
        if ids[i] then return C_Timer.After(0, Step) end
        importing = false
        if added > 0 then
            if ns.Analytics then ns.Analytics:Invalidate() end
            ns:Changed()
        end
    end
    Step()
end

-- ---------------------------------------------------------------------------
-- Browse results, whoever asked for them
-- ---------------------------------------------------------------------------

local seenThisQuery = {} -- itemID -> { price, quantity } already recorded from the current result set

-- Gear comes back once per item level or suffix: one record per item, at the cheapest variant,
-- with every variant's quantity.
local function TakeResults(results)
    if type(results) ~= "table" then return 0 end
    local best, qty = {}, {}
    for _, r in ipairs(results) do
        local key = r.itemKey
        local id, price, q = key and key.itemID, r.minPrice, r.totalQuantity
        if id and price and price > 0 and (q or 0) > 0 then
            if not best[id] or price < best[id] then best[id] = price end
            qty[id] = (qty[id] or 0) + q
        end
    end
    local n = 0
    for id, price in pairs(best) do
        local seen = seenThisQuery[id]
        if not seen or seen[1] ~= price or seen[2] ~= qty[id] then
            seenThisQuery[id] = { price, qty[id] }
            if ns.History and ns.History.current then
                ns.History:Item(id, price, qty[id])
            else
                Prices:Record(id, price, qty[id])
            end
            n = n + 1
        end
    end
    return n
end

local function OnBrowseUpdated()
    if not (C_AuctionHouse and C_AuctionHouse.GetBrowseResults) then return end
    local ok, results = pcall(C_AuctionHouse.GetBrowseResults)
    if ok then TakeResults(results) end
    Prices:ContinueScan(ok and results or nil)
    if ns.History then ns.History:OnBrowseResults() end
end

-- The added results are also in the full list, which TakeResults reads whole (variants together).
local function OnBrowseAdded()
    local ok, results = pcall(C_AuctionHouse.GetBrowseResults)
    if ok then TakeResults(results) end
    Prices:ContinueScan(ok and results or nil)
    if ns.History then ns.History:OnBrowseResults() end
end

-- ---------------------------------------------------------------------------
-- Our own full scan: one blank browse query, then more results until the server has sent all.
-- ---------------------------------------------------------------------------

local auctionOpen = false

-- Starts Auctionator's own scan, as its Scan button does (its full scan or its summary scan, as
-- set in its options), so one scan updates Auctionator's prices and ours: History.lua reads
-- either kind as it comes in. Auctionator's internals, not its public API: guarded, and false
-- when it isn't there or didn't take it.
local function StartAuctionatorScan()
    local A = type(Auctionator) == "table" and Auctionator
    local state, config = A and A.State, A and A.Config
    if not (state and config and config.Get and config.Options) then return false end
    local frame = config.Get(config.Options.REPLICATE_SCAN) and state.FullScanFrameRef or state.IncrementalScanFrameRef
    if not (frame and frame.InitiateScan) then return false end
    return (pcall(frame.InitiateScan, frame))
end

function Prices:ScanMarket()
    if not auctionOpen then return ns:Print("Open the auction house first.", true) end
    if self.scan then return ns:Print("A market scan is already running.", true) end
    if StartAuctionatorScan() then
        return ns:Print("Started Auctionator's scan: Wealth Planner records it as it comes in.")
    end
    local ready = C_AuctionHouse.IsThrottledMessageSystemReady
    if ready and not ready() then return C_Timer.After(0.5, function() Prices:ScanMarket() end) end
    wipe(seenThisQuery)
    self.scan = { started = GetTime(), last = GetTime(), groups = 0 }
    if ns.History then ns.History:Begin("market") end
    local order = Enum and Enum.AuctionHouseSortOrder
    local ok = pcall(C_AuctionHouse.SendBrowseQuery, {
        searchString = "", minLevel = 0, maxLevel = 0, filters = {}, itemClassFilters = {},
        sorts = {
            { sortOrder = order and order.Price or 0, reverseSort = false },
            { sortOrder = order and order.Name or 1, reverseSort = false },
        },
    })
    if not ok then
        self.scan = nil
        return ns:Print("The auction house didn't accept the scan. Try again in a moment.", true)
    end
    ns:Print("Scanning the auction house...")
    local function Watch()
        local s = Prices.scan
        if not s then return end
        if GetTime() - s.last > SCAN_TIMEOUT then Prices:FinishScan(false) return end
        C_Timer.After(1, Watch)
    end
    C_Timer.After(1, Watch)
    ns:Changed()
end

function Prices:ContinueScan(results)
    local s = self.scan
    if not s then return end
    s.last = GetTime()
    s.groups = results and #results or s.groups
    if C_AuctionHouse.HasFullBrowseResults and C_AuctionHouse.HasFullBrowseResults() then
        return self:FinishScan(true)
    end
    local function More()
        if self.scan ~= s or not auctionOpen then return end
        local ready = C_AuctionHouse.IsThrottledMessageSystemReady
        if ready and not ready() then return C_Timer.After(0.3, More) end
        pcall(C_AuctionHouse.RequestMoreBrowseResults)
    end
    More()
    ns:Changed()
end

function Prices:FinishScan(complete)
    local s = self.scan
    if not s then return end
    self.scan = nil
    Items()
    ns.db.realms[ns.RealmKey()].lastScan = time()
    if ns.History then ns.History:Finish() end
    ns:Print(("Market scan %s: %d items priced."):format(complete and "done" or "stopped early", s.groups))
    if ns.Analytics then ns.Analytics:Invalidate() end
    ns:Changed()
end

function Prices:CancelScan()
    if self.scan then self:FinishScan(false) end
end

-- ---------------------------------------------------------------------------
-- Watchlist
-- ---------------------------------------------------------------------------

function Prices:Watch(id, on)
    if on then
        ns.db.watch[id] = ns.db.watch[id] or { added = time() }
        local name = C.GetItemInfo(id)
        ns:Print(("Watching %s."):format(name or ("item " .. id)))
    else
        ns.db.watch[id] = nil
    end
    ns:Changed()
end

function Prices:IsWatched(id) return ns.db.watch[id] ~= nil end

-- Target prices: a chat alert when a scan sees the price at or under buy, or at or over sell.
function Prices:SetTarget(id, which, copper)
    local w = ns.db.watch[id]
    if not w then w = { added = time() }; ns.db.watch[id] = w end
    w[which] = copper and copper > 0 and copper or nil
    w[which .. "Alerted"] = nil
    ns:Changed()
end

Prices.onRecord = function(id, price)
    local w = ns.db.watch[id]
    if not (w and ns.db.options.alerts) then return end
    local name = select(2, C.GetItemInfo(id)) or ("item " .. id)
    if w.buy and price <= w.buy and not w.buyAlerted then
        w.buyAlerted = true
        ns:Print(("|cff59f28cBuy alert|r: %s is at %s (your target %s)."):format(name, C.Money(price), C.Money(w.buy)), true)
    elseif w.buy and price > w.buy then
        w.buyAlerted = nil
    end
    if w.sell and price >= w.sell and not w.sellAlerted then
        w.sellAlerted = true
        ns:Print(("|cffffd24dSell alert|r: %s is at %s (your target %s)."):format(name, C.Money(price), C.Money(w.sell)), true)
    elseif w.sell and price < w.sell then
        w.sellAlerted = nil
    end
end

-- ---------------------------------------------------------------------------

function Prices:Debug(id)
    local e = self:Entry(id)
    local name = select(2, C.GetItemInfo(id)) or ("item " .. id)
    if not e then return ns:Print(name .. ": no price history yet.", true) end
    local days = {}
    for day in pairs(e.d) do days[#days + 1] = day end
    table.sort(days)
    ns:Print(("%s: %d days, %d samples."):format(name, #days, #e.s), true)
    for i = math.max(1, #days - 9), #days do
        local d = e.d[days[i]]
        ns:Print(("  %s  low %s  high %s  last %s  listed %s  (%d seen)"):format(date("!%m/%d", days[i] * 86400),
            C.Money(d.lo), C.Money(d.hi), C.Money(d.c), d.q and tostring(d.q) or "?", d.n), true)
    end
end

local WEEKS_KEPT = 104

-- Days older than the history setting are rolled into weekly figures (e.w), kept two years.
local function Prune()
    local oldest = ns.Today() - (ns.db.options.historyDays or 120)
    local oldestWeek = math.floor(ns.Today() / 7) - WEEKS_KEPT
    for _, realm in pairs(ns.db.realms) do
        for id, e in pairs(realm.items or {}) do
            for day, d in pairs(e.d) do
                if day < oldest then
                    local wk = math.floor(day / 7)
                    e.w = e.w or {}
                    local w = e.w[wk]
                    if not w then w = { lo = d.lo, hi = d.hi, cs = 0, cn = 0, q = 0, qn = 0 }; e.w[wk] = w end
                    if d.lo < w.lo then w.lo = d.lo end
                    if d.hi > w.hi then w.hi = d.hi end
                    w.cs, w.cn = w.cs + d.c, w.cn + 1
                    if d.q then w.q, w.qn = w.q + d.q, w.qn + 1 end
                    e.d[day] = nil
                end
            end
            for wk in pairs(e.w or {}) do
                if wk < oldestWeek then e.w[wk] = nil end
            end
            if not next(e.d) and not next(e.s) and not (e.w and next(e.w)) and not e.x then realm.items[id] = nil end
        end
    end
end

ns:OnLoad(function()
    Prune()
    ns:On("AUCTION_HOUSE_SHOW", function() auctionOpen = true; wipe(seenThisQuery); ns:Changed() end)
    ns:On("AUCTION_HOUSE_CLOSED", function()
        auctionOpen = false
        Prices:CancelScan()
        ns:Changed()
    end)
    if C_AuctionHouse and C_AuctionHouse.GetBrowseResults then
        ns:On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", OnBrowseUpdated)
        ns:On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", OnBrowseAdded)
        -- A new query starts a new result set: the same price may be recorded again.
        if C_AuctionHouse.SendBrowseQuery then
            hooksecurefunc(C_AuctionHouse, "SendBrowseQuery", function() wipe(seenThisQuery) end)
        end
    end
end)

ns:On("PLAYER_LOGIN", function()
    local api = API()
    if api and api.RegisterForDBUpdate then pcall(api.RegisterForDBUpdate, ns.CALLER, SampleAuctionator) end
    C_Timer.After(2, function() Prices:ImportAuctionator() end)
end)

function Prices:AuctionOpen() return auctionOpen end

-- ---------------------------------------------------------------------------
-- Depth: how many are listed at each price. A browse scan only gives an item's lowest price and
-- how many are listed at all prices together; the real count at a price comes from the item's
-- own listings (a search for that one item). Those are recorded whenever they come back, whoever
-- asked (you, the Blizzard UI, Quartermaster, or FetchDepth below), on the item's price entry:
--   e.depth = { t = time, tiers = { { price, quantity }, ... } } (cheapest first, up to 30)
-- ---------------------------------------------------------------------------

local DEPTH_FRESH = 30 * 60 -- seconds a depth reading stays good
local MAX_TIERS = 30

local function SaveDepth(id, tiers)
    if not id then return end -- (no tiers: nothing listed but yours, which counts too)
    table.sort(tiers, function(a, b) return a[1] < b[1] end)
    local merged = {}
    for _, t in ipairs(tiers) do
        local last = merged[#merged]
        if last and last[1] == t[1] then last[2] = last[2] + t[2]
        elseif #merged < MAX_TIERS then merged[#merged + 1] = { t[1], t[2] } end
    end
    local items = Items()
    local e = items[id]
    if not e then e = { d = {}, s = {} }; items[id] = e end
    e.depth = { t = time(), tiers = merged }
    if not (ns.History and ns.History.current) then ns:Changed() end
end

local function OnCommodityResults(itemID)
    if not (itemID and C_AuctionHouse.GetNumCommoditySearchResults and C_AuctionHouse.GetCommoditySearchResultInfo) then return end
    local tiers = {}
    for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0 do
        local ok, r = pcall(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, i)
        if ok and r and r.unitPrice and r.unitPrice > 0 and (r.quantity or 0) > 0 and not (r.containsOwnerItem or r.containsAccountItem) then
            tiers[#tiers + 1] = { r.unitPrice, r.quantity }
        end
    end
    SaveDepth(itemID, tiers)
end

local function OnItemResults(itemKey)
    if not (itemKey and itemKey.itemID and C_AuctionHouse.GetNumItemSearchResults and C_AuctionHouse.GetItemSearchResultInfo) then return end
    local tiers = {}
    for i = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) or 0 do
        local ok, r = pcall(C_AuctionHouse.GetItemSearchResultInfo, itemKey, i)
        -- Identical listings come grouped in one row: buyoutAmount is the price of each one, and
        -- quantity how many (6 at 1g is { 1g, 6 }, not 1g split six ways).
        if ok and r and r.buyoutAmount and r.buyoutAmount > 0 and not (r.containsOwnerItem or r.containsAccountItem) then
            tiers[#tiers + 1] = { r.buyoutAmount, r.quantity or 1 }
        end
    end
    SaveDepth(itemKey.itemID, tiers)
end

-- Depth from a full scan (History.lua): every auction, so every item's tiers at once.
function Prices:SetDepth(id, tiers) SaveDepth(id, tiers) end

-- The item's depth, if read in the last 30 minutes: { { price, quantity } }, cheapest first.
function Prices:Depth(id)
    local e = self:Entry(id)
    local d = e and e.depth
    if d and time() - d.t <= DEPTH_FRESH then return d.tiers end
    return nil
end

-- Asks the auction house for these items' listings, one at a time (at most `limit` a visit), so
-- Depth knows what's really listed at each price. Only while the auction house is open and no
-- scan is running.
local depthQueue, depthBusy, depthAsked, depthWaiting = {}, false, {}, false
local function NextDepth()
    if depthBusy or not auctionOpen or Prices.scan then return end
    -- A market scan is coming in (Auctionator's, most likely): a search now would wipe a summary
    -- scan's progress, so the listings wait until it's recorded.
    if ns.History and ns.History.current then
        if not depthWaiting then
            depthWaiting = true
            C_Timer.After(2, function() depthWaiting = false; NextDepth() end)
        end
        return
    end
    local id = table.remove(depthQueue, 1)
    if not id then return end
    local ready = C_AuctionHouse.IsThrottledMessageSystemReady
    if ready and not ready() then
        table.insert(depthQueue, 1, id)
        return C_Timer.After(0.5, NextDepth)
    end
    local key = C_AuctionHouse.MakeItemKey and C_AuctionHouse.MakeItemKey(id)
    if not (key and C_AuctionHouse.SendSearchQuery) then return end
    depthBusy = true
    local order = Enum and Enum.AuctionHouseSortOrder
    pcall(C_AuctionHouse.SendSearchQuery, key, { { sortOrder = order and order.Price or 0, reverseSort = false } }, true)
    C_Timer.After(1.5, function() depthBusy = false; NextDepth() end)
end

function Prices:FetchDepth(ids, limit)
    if not (auctionOpen and C_AuctionHouse and C_AuctionHouse.SendSearchQuery) then return end
    local n = 0
    for _, id in ipairs(ids) do
        if n >= (limit or 8) then break end
        if not self:Depth(id) and not depthAsked[id] then
            depthAsked[id] = true
            depthQueue[#depthQueue + 1] = id
            n = n + 1
        end
    end
    NextDepth()
end

ns:OnLoad(function()
    if not C_AuctionHouse then return end
    ns:On("COMMODITY_SEARCH_RESULTS_UPDATED", OnCommodityResults)
    ns:On("ITEM_SEARCH_RESULTS_UPDATED", OnItemResults)
    ns:On("AUCTION_HOUSE_SHOW", function() wipe(depthAsked); wipe(depthQueue); depthBusy = false end)
end)
