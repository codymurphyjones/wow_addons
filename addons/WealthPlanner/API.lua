local _, ns = ...

-- WealthPlannerAPI: the price history Wealth Planner keeps, for other addons. Wally and
-- Quartermaster read it through the shared AuctionPrice.lua (addons/shared): a 30-day normal to
-- check Auctionator's latest price against before selling or buying.
--   WealthPlannerAPI.Price(itemID)  -> copper, time seen (or nil): today's close, else the newest
--                                      sample, else Auctionator's price
--   WealthPlannerAPI.Stats(itemID)  -> { price, normal (30-day median), ma7, ma30, chg7, chg30,
--                                      days (of history), signal = "buy"|"sell"|"hold", reason }, or nil
--   WealthPlannerAPI.Normal(itemID) -> the 30-day normal, or nil
-- Version 2: the shared registry (RegisterCallback); no events yet.
local API = ns.NewAPI("WealthPlannerAPI", 2)

local function Ready() return ns.db and ns.Prices and ns.Analytics end

function API.Price(itemID)
    if not (Ready() and tonumber(itemID)) then return nil end
    return ns.Prices:Price(tonumber(itemID))
end

function API.Stats(itemID)
    if not (Ready() and tonumber(itemID)) then return nil end
    local s = ns.Analytics:Stats(tonumber(itemID))
    if not s then return nil end
    -- A copy, so callers can't change Wealth Planner's cache.
    return {
        price = s.price, normal = s.normal, ma7 = s.ma7, ma30 = s.ma30, chg7 = s.chg7, chg30 = s.chg30,
        days = s.days, signal = s.signal, reason = s.reason,
    }
end

function API.Normal(itemID)
    local s = API.Stats(itemID)
    return s and s.normal or nil
end
