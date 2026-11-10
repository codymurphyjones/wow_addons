local addonName, ns = ...

-- Auction prices, the same for every addon here (addons/shared): Auctionator's latest price and its
-- age (public v1 API only), and, when Wealth Planner is loaded, the item's 30-day normal price from
-- the history it keeps (WealthPlannerAPI). Auctionator's price is the last scan's lowest listing,
-- so one empty or flooded market can make it swing; the normal is the steadier figure to check it
-- against. The caller ID Auctionator sees is ns.CALLER, else the addon's name.
local AP = {}
ns.AuctionPrice = AP

-- Days of history before the normal price counts.
local MIN_DAYS = 5
-- The market this far under normal is a crash (selling into it gives the item away).
AP.CRASH = 0.7

local function API() return type(Auctionator) == "table" and Auctionator.API and Auctionator.API.v1 end
local function Caller() return ns.CALLER or addonName end

local function Positive(ok, v) return ok and type(v) == "number" and v > 0 and v or nil end

function AP.HasAuctionator()
    local api = API()
    return api and (api.GetAuctionPriceByItemID or api.GetAuctionPriceByItemLink) and true or false
end

-- Wealth Planner's price for the auction pool you're at (else your faction's): Auctionator keeps
-- one price for every auction house you visit, so Booty Bay's would stand in for your own city's.
local function PoolPrice(item)
    local wp = WealthPlannerAPI
    if not (wp and wp.PoolPrice) or item == nil then return nil end
    local ok, price, age = pcall(wp.PoolPrice, item)
    if ok and type(price) == "number" and price > 0 then return price, age end
end

-- The latest price, in copper, by item ID or link; or nil: the auction pool's (above), else
-- Auctionator's.
function AP.Market(item)
    local pool = PoolPrice(item)
    if pool then return pool end
    local api = API()
    if not api or item == nil then return nil end
    if type(item) == "number" then
        return api.GetAuctionPriceByItemID and Positive(pcall(api.GetAuctionPriceByItemID, Caller(), item)) or nil
    end
    return api.GetAuctionPriceByItemLink and Positive(pcall(api.GetAuctionPriceByItemLink, Caller(), item)) or nil
end

-- Days since it was last seen (0 = today), by item ID or link; or nil.
function AP.Age(item)
    local price, age = PoolPrice(item)
    if price then return age end
    local api = API()
    if not api or item == nil then return nil end
    local fn = type(item) == "number" and api.GetAuctionAgeByItemID or api.GetAuctionAgeByItemLink
    if not fn then return nil end
    local ok, age = pcall(fn, Caller(), item)
    return ok and type(age) == "number" and age or nil
end

local function ItemID(item)
    if type(item) == "number" then return item end
    if type(item) == "string" then return tonumber(item:match("item:(%d+)")) end
end

-- ---------------------------------------------------------------------------
-- Trend at your faction's auction houses only: Wealth Planner's daily lows per auction pool
-- (WealthPlannerAPI.PoolHistory). Auctionator's own history can't be used: it keeps one price for
-- every house you visit, so a Booty Bay scan would read as a jump or a crash. Without Wealth
-- Planner there's no trend (nil).
-- ---------------------------------------------------------------------------

AP.STEAMWHEEDLE = "steamwheedle"
AP.LOGISTICS = "quickcoin" -- the logistics camps' auction house (Crossroads, Three Corners), both factions

local function HomeHistory(item)
    local wp = WealthPlannerAPI
    if not (wp and wp.PoolHistory) or item == nil then return nil end
    local ok, days, now, today = pcall(wp.PoolHistory, item)
    if ok and type(days) == "table" and type(now) == "number" and now > 0 and type(today) == "number" then
        return days, now, today
    end
end

-- The latest price at your faction's houses minus the price there at the start of the last `days`
-- days, in copper; or nil when the history doesn't reach back that far. The start is the day
-- `days` ago, else the scanned day nearest it within a quarter of the window (at least a day):
-- scans are rarely daily.
--
-- The daily trend (days 1) is measured in hours instead: the latest scan against the oldest scan of
-- the last 24 hours, once those are at least DAY_MIN_SPAN apart (two scans, 12 hours of data).
local DAY, DAY_MIN_SPAN = 24 * 3600, 12 * 3600

local function DailyTrend(item)
    local wp = WealthPlannerAPI
    if not (wp and wp.PoolRecent) or item == nil then return nil end
    local ok, recent = pcall(wp.PoolRecent, item)
    if not (ok and type(recent) == "table" and #recent >= 4) then return nil end
    local n = #recent
    local lastT, lastP = recent[n - 1], recent[n]
    local since = time() - DAY
    for i = 1, n - 3, 2 do -- (never the latest itself)
        local t, p = recent[i], recent[i + 1]
        if t >= since then
            if lastT - t >= DAY_MIN_SPAN and type(p) == "number" and p > 0 then return lastP - p end
            return nil -- the oldest scan in the window is too recent: under 12 hours of data
        end
    end
end

function AP.Trend(item, days)
    if days == 1 then return DailyTrend(item) end
    local prices, now, today = HomeHistory(item)
    if not prices then return nil end
    local start = today - days
    local slack = math.max(1, math.floor(days / 4))
    for off = 0, slack do
        -- Nearest first; on a tie the older day, so the window is never shorter than asked.
        local p = prices[start - off] or (start + off < today and prices[start + off]) or nil
        if type(p) == "number" and p > 0 then return now - p end
    end
    return nil
end

-- Whether your faction's houses have a price for the item (the trend lines then show N/A rather
-- than nothing).
function AP.HasHistory(item)
    return HomeHistory(item) ~= nil
end

-- The latest price at one auction pool (AP.STEAMWHEEDLE, "alliance", "horde", ...): copper, days
-- old; or nil (not seen there, or no Wealth Planner).
function AP.PoolPrice(item, pool)
    local wp = WealthPlannerAPI
    if not (wp and wp.PoolPrice and pool) or item == nil then return nil end
    local ok, price, age = pcall(wp.PoolPrice, item, pool)
    if ok and type(price) == "number" and price > 0 then return price, age end
end

-- Wealth Planner's view of an item: { normal, ma7, ma30, chg7, days, signal }, or nil without it
-- or without enough history.
function AP.History(item)
    local api = WealthPlannerAPI
    local id = ItemID(item)
    if not (id and api and api.Stats) then return nil end
    local ok, s = pcall(api.Stats, id)
    if not (ok and type(s) == "table" and s.normal and (s.days or 0) >= MIN_DAYS) then return nil end
    return s
end

-- The 30-day normal price (median), or nil.
function AP.Normal(item)
    local s = AP.History(item)
    return s and s.normal or nil
end

-- What to judge a purchase by: the market, but never above its normal (no buying into a spike).
-- Returns price, normal.
function AP.BuyReference(market, item)
    local normal = AP.Normal(item)
    if market and normal then return math.min(market, normal), normal end
    return market or normal, normal
end

-- Whether the market has crashed under its normal: crashed, normal.
function AP.Crashed(market, item)
    local normal = AP.Normal(item)
    return (market and normal and market < normal * AP.CRASH) and true or false, normal
end
