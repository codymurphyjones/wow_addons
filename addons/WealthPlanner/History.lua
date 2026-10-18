local _, ns = ...

-- Every scan, kept. Wealth Planner reads each auction house scan whoever runs it:
--   * a full scan (Auctionator's "Full Scan", or any addon's C_AuctionHouse.ReplicateItems): every
--     auction on the market at once. Read here in chunks: per item, the lowest buyout per unit, how
--     many are listed, how many auctions, how many at (or within 5% of) the lowest price, and the
--     price tiers (Prices:SetDepth, so buys know what's really listed at each price);
--   * a summary scan (Auctionator's, or Wealth Planner's own "Scan market"): every item's lowest
--     price and how many are listed (Prices.lua reads the browse results).
-- Each item seen in a scan is recorded through Prices:Record (the daily figures and the hourly
-- patterns), and appended to its per-scan history: e.x, a compact string of "time:low:listed:atLow;"
-- records, kept RAW_DAYS days. Days older than the history setting are rolled into weekly figures
-- (Prices.lua), kept two years. Each scan is logged in realm.scans { t, kind, items, auctions }.
local H = {}
ns.History = H

local RAW_DAYS = 14
local KEEP_SCANS = 1000
local CHUNK = 2000        -- full-scan auctions read per frame
local NEAR_LOW = 1.05     -- "at the lowest price": within 5% of it
local SUMMARY_IDLE = 10   -- seconds without browse results before a summary scan counts as over

H.current = nil -- the scan being recorded: { t, kind, items, auctions, seen = { [id] = true } }

local function Realm()
    local key = ns.RealmKey()
    local realm = ns.db.realms[key]
    if not realm then realm = { items = {} }; ns.db.realms[key] = realm end
    realm.scans = realm.scans or {}
    return realm
end

function H:Begin(kind)
    if self.current then self:Finish() end
    self.current = { t = time(), kind = kind, items = 0, auctions = 0, seen = {}, last = GetTime() }
end

-- One item's figures from the scan in progress (or a single sighting when no scan is running).
function H:Item(id, low, listed, atLow, auctions)
    if not (id and low and low > 0) then return end
    local cur = self.current
    ns.Prices:Record(id, low, listed, { qm = atLow, a = auctions, scan = cur ~= nil })
    if not cur or cur.seen[id] then return end
    cur.seen[id] = true
    cur.items, cur.auctions, cur.last = cur.items + 1, cur.auctions + (auctions or 0), GetTime()
    local e = ns.Prices:Entry(id)
    if e then
        e.x = (e.x or "") .. ("%d:%d:%d:%d;"):format(cur.t, low, listed or -1, atLow or -1)
    end
end

function H:Finish()
    local cur = self.current
    if not cur then return end
    self.current = nil
    if cur.items == 0 then return end
    local scans = Realm().scans
    scans[#scans + 1] = { t = cur.t, kind = cur.kind, items = cur.items, auctions = cur.auctions }
    while #scans > KEEP_SCANS do table.remove(scans, 1) end
    Realm().lastScan = time()
    if ns.Analytics then ns.Analytics:Invalidate() end
    if ns.Recovery then ns.Recovery:Scan() end
    ns:Print(("Recorded the %s scan: %d items%s."):format(cur.kind, cur.items,
        cur.auctions > 0 and (", %d auctions"):format(cur.auctions) or ""))
    ns:Changed()
end

-- Scans recorded on this realm, newest last.
function H:Scans() return Realm().scans end

-- An item's per-scan history, oldest first: { { t, low, listed, atLow } } (nil fields when unknown).
function H:Raw(id)
    local e = ns.Prices:Entry(id)
    local out = {}
    if not (e and e.x) then return out end
    for t, low, listed, atLow in e.x:gmatch("(%d+):(%d+):(%-?%d+):(%-?%d+);") do
        listed, atLow = tonumber(listed), tonumber(atLow)
        out[#out + 1] = { t = tonumber(t), low = tonumber(low), listed = listed >= 0 and listed or nil,
            atLow = atLow >= 0 and atLow or nil }
    end
    return out
end

-- Drops per-scan records older than RAW_DAYS.
local function PruneRaw()
    local cutoff = time() - RAW_DAYS * 86400
    for _, realm in pairs(ns.db.realms) do
        for _, e in pairs(realm.items or {}) do
            if e.x then
                local keepFrom
                local pos = 1
                for t, stop in e.x:gmatch("(%d+):[^;]*;()") do
                    if tonumber(t) >= cutoff then keepFrom = pos; break end
                    pos = stop
                end
                e.x = keepFrom and e.x:sub(keepFrom) or nil
                if e.x == "" then e.x = nil end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Full scans (C_AuctionHouse.ReplicateItems), whoever started them
-- ---------------------------------------------------------------------------

local reading -- { i, n, agg, me }

local function FinishReplicate()
    local r = reading
    reading = nil
    for id, a in pairs(r.agg) do
        table.sort(a.units, function(x, y) return x[1] < y[1] end)
        local low = a.units[1][1]
        local atLow, tiers = 0, {}
        for _, u in ipairs(a.units) do
            if u[1] <= low * NEAR_LOW then atLow = atLow + u[2] end
            local last = tiers[#tiers]
            if last and last[1] == u[1] then last[2] = last[2] + u[2]
            elseif #tiers < 30 then tiers[#tiers + 1] = { u[1], u[2] } end
        end
        H:Item(id, low, a.qty, atLow, a.auctions)
        ns.Prices:SetDepth(id, tiers)
    end
    H:Finish()
end

local function ReadChunk()
    local r = reading
    if not r then return end
    local stop = math.min(r.n, r.i + CHUNK)
    for i = r.i, stop - 1 do
        local _, _, count, _, _, _, _, _, _, buyout, _, _, _, owner, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(i)
        if itemID and buyout and buyout > 0 and (count or 0) > 0 and owner ~= r.me then
            local a = r.agg[itemID]
            if not a then a = { qty = 0, auctions = 0, units = {} }; r.agg[itemID] = a end
            a.qty, a.auctions = a.qty + count, a.auctions + 1
            a.units[#a.units + 1] = { math.floor(buyout / count), count }
        end
    end
    r.i = stop
    if r.i >= r.n then return FinishReplicate() end
    C_Timer.After(0, ReadChunk)
end

local function OnReplicate()
    if reading or not (C_AuctionHouse.GetNumReplicateItems and C_AuctionHouse.GetReplicateItemInfo) then return end
    local n = C_AuctionHouse.GetNumReplicateItems() or 0
    if n == 0 then return end
    H:Begin("full")
    reading = { i = 0, n = n, agg = {}, me = UnitName("player") }
    C_Timer.After(0, ReadChunk)
end

-- ---------------------------------------------------------------------------
-- Summary scans: a blank browse query (Auctionator's summary scan, or anyone's)
-- ---------------------------------------------------------------------------

local function IsBlank(query)
    if type(query) ~= "table" or (query.searchString or "") ~= "" then return false end
    local function Empty(t) return t == nil or (type(t) == "table" and next(t) == nil) end
    return Empty(query.filters) and Empty(query.itemClassFilters)
end

function H:OnBrowseResults()
    local cur = self.current
    if not (cur and (cur.kind == "summary" or cur.kind == "market")) then return end
    cur.last = GetTime()
    if C_AuctionHouse.HasFullBrowseResults and C_AuctionHouse.HasFullBrowseResults() then self:Finish() end
end

local function WatchSummary()
    local cur = H.current
    if not (cur and cur.kind == "summary") then return end
    if GetTime() - cur.last > SUMMARY_IDLE then return H:Finish() end
    C_Timer.After(1, WatchSummary)
end

ns:OnLoad(function()
    PruneRaw()
    if not C_AuctionHouse then return end
    ns:On("REPLICATE_ITEM_LIST_UPDATE", OnReplicate)
    if C_AuctionHouse.SendBrowseQuery then
        hooksecurefunc(C_AuctionHouse, "SendBrowseQuery", function(query)
            if ns.Prices.scan or not IsBlank(query) then return end -- Wealth Planner's own scan logs itself
            H:Begin("summary")
            C_Timer.After(1, WatchSummary)
        end)
    end
    ns:On("AUCTION_HOUSE_CLOSED", function() if H.current then H:Finish() end end)
end)
