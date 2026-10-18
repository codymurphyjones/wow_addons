local _, ns = ...

-- Reads an item's daily price history the way a stock chart would: moving averages, change over
-- 1, 7 and 30 days, volatility, how far today's price sits from its 30-day normal (z-score), and
-- supply against its normal. From those, a Buy / Sell / Hold signal with a confidence and a reason
-- in plain words.
local A = {}
ns.Analytics = A

local cache = {} -- itemID -> stats, until new prices arrive

-- Under normal counts as losing value (no buy) when the price falls faster than FALL_SLOPE a day
-- over the week and listings grew FALL_SUPPLY times, sales slowed to FALL_DEMAND of before, or
-- FALL_COVER days of sales are listed.
local FALL_SLOPE, FALL_SUPPLY, FALL_DEMAND, FALL_COVER = -0.02, 1.25, 0.7, 14
-- A crash today counts too: the price at SHOCK_DEPTH of normal or under while SHOCK_SUPPLY times the
-- usual number is listed, unless only a thin layer (under THIN_SHARE of what's listed, within 10%
-- of the lowest price) is that cheap: then it's a lone undercut worth snapping up.
local SHOCK_DEPTH, SHOCK_SUPPLY, THIN_SHARE = 0.5, 2, 0.25
-- Beta Crash Monitoring (ns.BetaDaysLeft): no "back to normal" buys with less than this many days left.
local BETA_MIN_DAYS = 2
-- ... and the price it's expected back at is cut to this share of the climb per day left (all of it at 4+).
local BETA_FULL_DAYS = 4

function A:Invalidate(id)
    if id then cache[id] = nil else wipe(cache) end
    if ns.Recovery then ns.Recovery:Invalidate(id) end
end

local function Mean(t)
    if #t == 0 then return nil end
    local s = 0
    for _, v in ipairs(t) do s = s + v end
    return s / #t
end

local function StdDev(t, mean)
    if #t < 2 then return nil end
    local s = 0
    for _, v in ipairs(t) do s = s + (v - mean) ^ 2 end
    return math.sqrt(s / (#t - 1))
end

local function Median(t)
    if #t == 0 then return nil end
    local c = {}
    for i, v in ipairs(t) do c[i] = v end
    table.sort(c)
    local m = (#c + 1) / 2
    return (c[math.floor(m)] + c[math.ceil(m)]) / 2
end

-- The close on the newest recorded day at or before `day`.
local function CloseAtOrBefore(days, d, day)
    for i = #days, 1, -1 do
        if days[i] <= day then return d[days[i]].c end
    end
end

-- Stats for one item, or nil without history:
-- { price, days, ma7, ma30, chg1, chg7, chg30, vol, z, supply, supplyAvg, supplyRatio, vendor,
--   slope7 (price change a day this week), supply7, supplyBefore, supplyShift (listings this week
--   against the 3 weeks before), demand (sold a day), demandShift (last 4 days against the 10
--   before), cover (days of sales listed), falling (under normal because it's losing value),
--   slope28, normal (the price to expect it back at: the 30-day median, at most the week before
--   today's), cheapShare (share of what's listed within 10% of the lowest price, when known),
--   closes (last 30 days, oldest first), signal = "buy"|"sell"|"hold", confidence (0..1), reason }
function A:Stats(id)
    if cache[id] ~= nil then return cache[id] or nil end
    local e = ns.Prices:Entry(id)
    if not (e and next(e.d)) then cache[id] = false return nil end
    local d = e.d
    local days = {}
    for day in pairs(d) do days[#days + 1] = day end
    table.sort(days)
    local today = ns.Today()
    local last = days[#days]
    local price = d[last].c

    local c7, c30, q30 = {}, {}, {}
    for _, day in ipairs(days) do
        if day > today - 7 then c7[#c7 + 1] = d[day].c end
        if day > today - 30 then
            c30[#c30 + 1] = d[day].c
            if d[day].q then q30[#q30 + 1] = d[day].q end
        end
    end
    local ma7, ma30 = Mean(c7), Mean(c30)
    local function Change(back)
        local old = CloseAtOrBefore(days, d, last - back)
        return old and old > 0 and (price - old) / old or nil
    end

    -- Day-to-day returns for volatility.
    local returns = {}
    for i = 2, #days do
        local a, b = d[days[i - 1]].c, d[days[i]].c
        if a > 0 and days[i] > today - 30 then returns[#returns + 1] = (b - a) / a end
    end
    local vol = #returns >= 2 and StdDev(returns, Mean(returns)) or nil

    local z
    if ma30 and #c30 >= 3 then
        local sd = math.max(StdDev(c30, ma30) or 0, ma30 * 0.01)
        z = (price - ma30) / sd
    end

    local supply = d[last].q
    local supplyAvg = Mean(q30)

    -- Supply and demand: listings this week against the three weeks before (a build-up, not a
    -- one-day spike), and how many sell a day (Trends:Volume, from listings that disappear between
    -- scans), lately against the days before.
    local q7, qBefore = {}, {}
    for _, day in ipairs(days) do
        local q = d[day].q
        if q and day > today - 30 then
            if day > today - 7 then q7[#q7 + 1] = q else qBefore[#qBefore + 1] = q end
        end
    end
    local supply7, supplyBefore = Mean(q7), #qBefore >= 3 and Mean(qBefore) or nil
    local Tr = ns.Trends
    -- The week's direction before today, so one cheap day doesn't read as a slide.
    local week = Tr and Tr:Daily(id, 8) or {}
    week[#week] = nil
    local slope7 = Tr and Tr.Slope(week)
    -- Today is judged by the crash rule in Signal, not by the trends.
    local month = Tr and Tr:Daily(id, 29) or {}
    month[#month] = nil
    local slope28 = Tr and Tr.Slope(month)
    -- The price to expect it back at: the median (spikes don't pull it up), and never above the
    -- week before today, so an item already lower all week isn't expected back at last month's.
    local normal = Median(c30)
    local weekMedian = #week >= 3 and Median(week)
    if normal and weekMedian then normal = math.min(normal, weekMedian) end
    -- How much is listed as cheap as today's price: from the listings when read lately, else the
    -- last full scan's count at the lowest price.
    local cheapShare
    local tiers = ns.Prices.Depth and ns.Prices:Depth(id)
    if tiers and tiers[1] then
        local cheap, all = 0, 0
        for _, t in ipairs(tiers) do
            all = all + t[2]
            if t[1] <= tiers[1][1] * 1.1 then cheap = cheap + t[2] end
        end
        cheapShare = all > 0 and cheap / all or nil
    elseif d[last].qm and supply and supply > 0 then
        cheapShare = d[last].qm / supply
    end
    local demand = Tr and Tr:Volume(id)
    local demandNow, demandBefore = Tr and Tr:Volume(id, 0, 96), Tr and Tr:Volume(id, 96, 336)

    local s = {
        id = id, price = price, days = #days, ma7 = ma7, ma30 = ma30,
        chg1 = Change(1), chg7 = Change(7), chg30 = Change(30),
        vol = vol, z = z, supply = supply, supplyAvg = supplyAvg,
        supplyRatio = supply and supplyAvg and supplyAvg > 0 and supply / supplyAvg or nil,
        slope7 = slope7, slope28 = slope28, normal = normal, cheapShare = cheapShare, supply7 = supply7, supplyBefore = supplyBefore,
        supplyShift = supply7 and supplyBefore and supplyBefore > 0 and supply7 / supplyBefore or nil,
        demand = demand, demandNow = demandNow,
        demandShift = demandNow and demandBefore and demandBefore > 0 and demandNow / demandBefore or nil,
        cover = supply and demand and demand > 0 and supply / demand or nil,
        vendor = ns.Prices:Vendor(id), closes = c30, lastSeen = e.t,
        vendorBuy = ns.Prices:VendorBuy(id), vendorExact = select(2, ns.Prices:VendorBuy(id)),
    }
    self:Signal(s)
    cache[id] = s
    return s
end

-- Buy when the price is well under its 30-day normal, sell when well over (or when supply is
-- drying up while the price climbs). Confidence grows with days of history and shrinks with
-- volatility.
function A:Signal(s)
    local reasons = {}
    local signal = "hold"
    -- Listed for less than a vendor pays: buying it is a sure profit, whatever the trend.
    if s.vendor and s.price < s.vendor * 0.95 then
        s.signal, s.confidence = "buy", 1
        s.reason = ("Listed under its vendor price (%s): sell it to any vendor for a profit."):format(ns.Gold(s.vendor))
        s.flip = s.vendor - s.price
        return
    end
    -- Vendors sell it: the auction price is only worth paying up to what they charge.
    if s.vendorBuy then
        s.flip = nil
        if s.price > s.vendorBuy * 1.05 then
            s.signal, s.confidence = "hold", 1
            s.reason = ("Vendors sell it for %s%s: the auction price is %.1fx that. Buy it from a vendor, not here."):format(
                ns.Gold(s.vendorBuy), s.vendorExact and "" or " (about)", s.price / s.vendorBuy)
        else
            s.signal, s.confidence = "hold", 1
            s.reason = ("Vendors sell it for %s%s: no room to make money on it."):format(ns.Gold(s.vendorBuy), s.vendorExact and "" or " (about)")
        end
        return
    end
    local confScale = 1
    if s.z and s.ma30 then
        local off = (s.price - s.ma30) / s.ma30
        if s.z <= -1 then
            -- Under normal, but is it a dip or a decline? The price falling all week while listings
            -- pile up, sales slow or there's weeks of stock listed: the 30-day average is just lagging.
            local thin = s.cheapShare and s.cheapShare < THIN_SHARE
            local why = {}
            if (s.supplyShift or 0) >= FALL_SUPPLY then why[#why + 1] = ("listings grew %.1fx"):format(s.supplyShift) end
            -- (a jump that's mostly priced above today's lowest isn't a flood at that price)
            if (s.supplyRatio or 0) >= SHOCK_SUPPLY and not thin then why[#why + 1] = ("listings jumped %.1fx today"):format(s.supplyRatio) end
            if s.demandShift and s.demandShift <= FALL_DEMAND then
                why[#why + 1] = ("sales slowed to about %d a day"):format(math.floor(s.demandNow + 0.5))
            end
            if (s.cover or 0) >= FALL_COVER then why[#why + 1] = ("%d days of stock listed"):format(math.floor(s.cover)) end
            local slope = math.min(s.slope7 or 0, s.slope28 or 0)
            local shock = s.normal and s.price <= s.normal * SHOCK_DEPTH and (s.supplyRatio or 0) >= SHOCK_SUPPLY
            if shock and not thin then
                -- A crash on a flood of listings: the market repriced, it didn't dip.
                s.falling = true
                -- Once it climbs back as the flood sells, Recovery.lua says so (the Invest tab buys
                -- it as a recovery, not here).
                local rec = ns.Recovery and ns.Recovery:Check(s.id)
                if rec and rec.status == "recovering" then
                    reasons[#reasons + 1] = (rec.why:gsub("%.$", ""))
                else
                    reasons[#reasons + 1] = ("crashed today: %.0f%% under normal as listings jumped %.1fx (%d, normally %d); wait to see whether the price holds before buying"):format(
                        (1 - s.price / s.normal) * 100, s.supplyRatio, s.supply, math.floor(s.supplyAvg + 0.5))
                end
            elseif slope < FALL_SLOPE and #why > 0 then
                s.falling = true
                reasons[#reasons + 1] = ("losing value, not dipping: down %.0f%% a day while %s"):format(
                    -slope * 100, table.concat(why, " and "))
                reasons[#reasons + 1] = ("%.0f%% under a 30-day average it's leaving behind"):format(-off * 100)
            elseif (ns.BetaDaysLeft() or math.huge) < BETA_MIN_DAYS then
                -- The beta goes offline soon: no time for it to come back, and prices slide as players cash out.
                reasons[#reasons + 1] = ("%.0f%% under its 30-day average, but the beta goes offline in %s: no time for it to come back"):format(
                    -off * 100, ns.BetaLeftText())
            else
                signal = "buy"
                reasons[#reasons + 1] = ("%.0f%% under its 30-day average"):format(-off * 100)
                if ns.BetaDaysLeft() then
                    reasons[#reasons + 1] = ("the beta goes offline in %s, so the expected price is cut to what it can climb back by then"):format(ns.BetaLeftText())
                end
                if shock then
                    reasons[#reasons + 1] = "only a few listed this cheap"
                elseif slope < FALL_SLOPE then
                    reasons[#reasons + 1] = ("still sliding %.0f%% a day, though listings and sales look normal"):format(-slope * 100)
                end
                if not s.supplyAvg then
                    confScale = 0.6
                    reasons[#reasons + 1] = "no listing counts yet"
                elseif not s.demand then
                    confScale = 0.8
                elseif (s.supplyRatio or 0) > 1.3 and (s.supplyRatio or 0) < SHOCK_SUPPLY and (s.supplyShift or 1) < FALL_SUPPLY and (s.demandShift or 1) > FALL_DEMAND then
                    reasons[#reasons + 1] = "a one-off dump: sales are holding"
                end
            end
        elseif s.z >= 1 then
            signal = "sell"
            reasons[#reasons + 1] = ("%.0f%% over its 30-day average"):format(off * 100)
        end
    end
    if signal == "hold" and s.chg7 and s.chg7 > 0.1 and s.supplyRatio and s.supplyRatio < 0.8 then
        signal = "sell"
        reasons[#reasons + 1] = ("up %.0f%% this week while supply dries up"):format(s.chg7 * 100)
    end
    if s.supplyRatio and (s.supplyRatio > 1.3 or s.supplyRatio < 0.7) and not s.falling then
        reasons[#reasons + 1] = ("supply %.1fx normal"):format(s.supplyRatio)
    end
    if s.vendor and s.price <= s.vendor * 1.2 then
        reasons[#reasons + 1] = "near its vendor price, so it can't fall much further"
    end
    if #reasons == 0 then
        reasons[1] = s.days < 3 and "not enough history yet" or "trading near its normal price"
    end
    local conf = math.min(1, s.days / 7) * confScale
    if s.vol and s.vol > 0.3 then conf = conf * 0.6 end
    s.signal, s.confidence = signal, conf
    s.reason = reasons[1]:gsub("^%l", string.upper) .. (#reasons > 1 and ("; " .. table.concat(reasons, "; ", 2)) or "") .. "."
    -- Expected profit per item if the price returns to normal, after the 5% auction house cut.
    -- Nothing to flip on goods losing value: the average they'd "return" to is the old price.
    -- The price to expect it back at: its normal price, or with the beta ending soon, only as much of
    -- the climb as the days left allow.
    local target, left = s.normal, ns.BetaDaysLeft()
    if target and left then target = s.price + (target - s.price) * math.min(1, left / BETA_FULL_DAYS) end
    s.target = target
    s.flip = target and not s.falling and (target * 0.95 - s.price) or nil
end

A.SIGNAL_TEXT = {
    buy = "|cff59f28cBuy|r", sell = "|cffffd24dSell|r", hold = "|cff8fa3b3Hold|r",
}

-- Every item with history on this realm, as { id, stats }.
function A:All()
    local out = {}
    for id in pairs(ns.Prices.Items()) do
        local s = self:Stats(id)
        if s then out[#out + 1] = { id = id, s = s } end
    end
    return out
end

-- Market lists for the Market and Overview pages. kind:
--   "movers"      biggest 7-day change either way
--   "undervalued" furthest under normal (buy signals first)
--   "flips"       most profit if the price returns to normal, weighted by how many are listed
--   "watch"       your watchlist
--   "all"         everything, newest first
function A:List(kind, search)
    local rows = {}
    search = search and search ~= "" and search:lower() or nil
    local watch = ns.db.watch
    for _, r in ipairs(self:All()) do
        local keep = true
        if kind == "watch" then keep = watch[r.id] ~= nil
        elseif kind == "movers" then keep = r.s.chg7 ~= nil
        elseif kind == "undervalued" then keep = r.s.z ~= nil and r.s.z < 0
        elseif kind == "flips" then keep = (r.s.flip or 0) > 0 and (r.s.supply or 0) > 0 end
        if keep and search then
            local name = ns.Compat.GetItemInfo(r.id)
            keep = name and name:lower():find(search, 1, true) ~= nil
        end
        if keep then rows[#rows + 1] = r end
    end
    local function Score(r)
        local s = r.s
        if kind == "movers" then return math.abs(s.chg7 or 0) end
        if kind == "undervalued" then return -(s.z or 0) * (s.confidence or 0) end
        if kind == "flips" then return (s.flip or 0) * math.min(s.supply or 0, 20) end
        return s.lastSeen or 0
    end
    table.sort(rows, function(a, b)
        local x, y = Score(a), Score(b)
        if x ~= y then return x > y end
        return a.id < b.id
    end)
    return rows
end

-- Counts of today's signals across the watchlist and your holdings.
function A:SignalCounts()
    local counts = { buy = 0, sell = 0, hold = 0 }
    for id in pairs(ns.Prices:Tracked()) do
        local s = self:Stats(id)
        if s and s.confidence >= 0.5 then counts[s.signal] = counts[s.signal] + 1 end
    end
    return counts
end

ns:On("GET_ITEM_INFO_RECEIVED", function() ns:Changed() end)
