local _, ns = ...

-- WealthPlannerAPI: the price history Wealth Planner keeps, for other addons. Wally and
-- Quartermaster read it through the shared AuctionPrice.lua (addons/shared): a 30-day normal to
-- check Auctionator's latest price against before selling or buying.
--   WealthPlannerAPI.Price(itemID)  -> copper, time seen (or nil): today's close, else the newest
--                                      sample, else Auctionator's price
--   WealthPlannerAPI.Stats(itemID)  -> { price, normal (30-day median), ma7, ma30, chg7, chg30,
--                                      days (of history), signal = "buy"|"sell"|"hold", reason }, or nil
--   WealthPlannerAPI.Normal(itemID) -> the 30-day normal, or nil
--   WealthPlannerAPI.PoolPrice(item, pool) -> copper, days old (or nil): the price at one auction
--                                      pool (Pools.lua); pool nil: the house open now, else yours
--   WealthPlannerAPI.PoolPrices(item) -> { { pool, name, price, age, available, home, here } }
--   WealthPlannerAPI.PoolHistory(item, pool) -> { [day] = lowest copper that day }, latest copper,
--                                      today (days are whole days since 1970); or nil. pool nil: yours
--   WealthPlannerAPI.PoolRecent(item, pool) -> { time, copper, time, copper, ... }: the scans of the
--                                      last 30 hours, oldest first; or nil. pool nil: yours
--   WealthPlannerAPI.HomePool() -> your faction's pool ("alliance" or "horde")
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

function API.PoolPrice(item, pool)
    if not (ns.db and ns.Pools and item) then return nil end
    if pool then return ns.Pools:Price(item, pool) end
    return ns.Pools:Market(item)
end

function API.PoolHistory(item, pool)
    if not (ns.db and ns.Pools and item) then return nil end
    return ns.Pools:History(item, pool or ns.Pools:Home())
end

function API.PoolRecent(item, pool)
    if not (ns.db and ns.Pools and item) then return nil end
    return ns.Pools:Recent(item, pool or ns.Pools:Home())
end

function API.HomePool()
    return ns.Pools and ns.Pools:Home() or nil
end

function API.PoolPrices(item)
    if not (ns.db and ns.Pools and item) then return {} end
    return ns.Pools:Prices(item)
end
