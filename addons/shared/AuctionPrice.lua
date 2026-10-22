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

-- Auctionator's latest price, in copper, by item ID or link; or nil.
function AP.Market(item)
    local api = API()
    if not api or item == nil then return nil end
    if type(item) == "number" then
        return api.GetAuctionPriceByItemID and Positive(pcall(api.GetAuctionPriceByItemID, Caller(), item)) or nil
    end
    return api.GetAuctionPriceByItemLink and Positive(pcall(api.GetAuctionPriceByItemLink, Caller(), item)) or nil
end

-- Days since Auctionator last saw it (0 = today), by item ID or link; or nil.
function AP.Age(item)
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
