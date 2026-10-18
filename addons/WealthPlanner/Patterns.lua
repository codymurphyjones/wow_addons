local _, ns = ...
local C = ns.Compat

-- The pattern watcher: when in the day and the week an item sells for more, and when your own
-- auctions actually sell.
--
-- Prices: every price Wealth Planner sees (your scans, Auctionator's, browsing) for an item you
-- care about (watchlist, holdings, what you've posted or sold, farmable goods) goes into its hour
-- of day and day of week, as a ratio to the item's running normal price, at most once every 30
-- minutes per item. Supply (how many are listed) is kept the same way. Stored on the item's price
-- entry: ph/pn (24 hours: summed ratio, count), wh/wn (7 days), qh/qn (24 hours of supply ratio),
-- ref/qref (the running normal price and supply), pt (the last time it counted).
--
-- Your sales: the auction house mail says when each sale happened (Portfolio.lua stores it as
-- `sold` on the ledger), so the hours and days your auctions sell are counted from that.
local Pat = {}
ns.Patterns = Pat

local GAP = 30 * 60      -- seconds between two counted observations of one item
local EMA = 0.08         -- how fast the running normal follows the price
local MIN_SAMPLES = 10   -- observations before an item's hours mean anything
local MIN_HOURS = 5      -- ... spread over at least this many hours of the day
local MIN_DAYS = 4       -- days of the week with data before the weekday pattern counts
local WORTH_WAITING = 0.05 -- a better window this much (5%) over now is worth waiting for

local DAYS = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
Pat.DAYS = DAYS

-- Items worth watching for patterns, refreshed once a minute.
local interest, interestAt = {}, 0
local function Interesting(id)
    local now = time()
    if now - interestAt > 60 then
        interestAt = now
        interest = ns.Prices:Tracked()
        for _, s in ipairs(ns.db.ledger) do if s.id then interest[s.id] = true end end
        for _, d in ipairs(ns.db.deposits or {}) do if d.id then interest[d.id] = true end end
    end
    return interest[id]
end

local function Arr(n)
    local t = {}
    for i = 1, n do t[i] = 0 end
    return t
end

-- One price seen (Prices:Record calls this).
function Pat:Observe(id, price, qty)
    if not (id and price and price > 0) or not Interesting(id) then return end
    local e = ns.Prices:Entry(id)
    if not e then return end
    local now = time()
    if e.pt and now - e.pt < GAP then return end
    e.pt = now
    if not e.ref then
        e.ref, e.qref = price, qty
        return
    end
    local t = date("*t", now)
    local h, w = t.hour + 1, t.wday
    local ratio = math.max(0.2, math.min(5, price / e.ref))
    e.ph, e.pn = e.ph or Arr(24), e.pn or Arr(24)
    e.wh, e.wn = e.wh or Arr(7), e.wn or Arr(7)
    e.ph[h], e.pn[h] = e.ph[h] + ratio, e.pn[h] + 1
    e.wh[w], e.wn[w] = e.wh[w] + ratio, e.wn[w] + 1
    if qty and qty > 0 then
        if e.qref and e.qref > 0 then
            e.qh, e.qn = e.qh or Arr(24), e.qn or Arr(24)
            local q = math.max(0.1, math.min(10, qty / e.qref))
            e.qh[h], e.qn[h] = e.qh[h] + q, e.qn[h] + 1
            e.qref = e.qref + (qty - e.qref) * EMA
        else
            e.qref = qty
        end
    end
    e.ref = e.ref + (price - e.ref) * EMA
end

-- ---------------------------------------------------------------------------
-- Reading the pattern
-- ---------------------------------------------------------------------------

-- "18-21h" for a 3-hour window centred on hour index i (1 = midnight).
local function Hours(i)
    local from = (i - 2) % 24
    return ("%02d-%02dh"):format(from, (from + 3) % 24)
end
Pat.Hours = Hours

-- Mean ratio over the 3-hour window centred on i, or nil without data.
local function Window(sum, count, i)
    local s, n = 0, 0
    for d = -1, 1 do
        local j = (i - 1 + d) % 24 + 1
        s, n = s + sum[j], n + count[j]
    end
    if n == 0 then return nil end
    return s / n, n
end

-- An item's pattern: { ready, samples, best = { i, ratio, text }, worst, now, nowRatio,
-- bestDay, worstDay, lowSupply = { i, text }, spread (best over worst), advice, wait (bool) },
-- or nil without any data.
function Pat:Item(id)
    local e = ns.Prices:Entry(id)
    if not (e and e.ph) then return nil end
    local samples, hours = 0, 0
    for i = 1, 24 do
        samples = samples + e.pn[i]
        if e.pn[i] > 0 then hours = hours + 1 end
    end
    local out = { samples = samples, hours = hours, ready = samples >= MIN_SAMPLES and hours >= MIN_HOURS }
    local best, worst
    for i = 1, 24 do
        local r, n = Window(e.ph, e.pn, i)
        if r and n >= 2 then
            if not best or r > best.ratio then best = { i = i, ratio = r } end
            if not worst or r < worst.ratio then worst = { i = i, ratio = r } end
        end
    end
    if best then best.text = Hours(best.i) end
    if worst then worst.text = Hours(worst.i) end
    out.best, out.worst = best, worst
    out.spread = best and worst and worst.ratio > 0 and best.ratio / worst.ratio - 1 or nil
    local hourNow = date("*t").hour + 1
    out.nowRatio = Window(e.ph, e.pn, hourNow)

    -- Days of the week.
    local days, bestDay, worstDay = 0, nil, nil
    for w = 1, 7 do
        if (e.wn[w] or 0) >= 2 then
            days = days + 1
            local r = e.wh[w] / e.wn[w]
            if not bestDay or r > bestDay.ratio then bestDay = { w = w, ratio = r, text = DAYS[w] } end
            if not worstDay or r < worstDay.ratio then worstDay = { w = w, ratio = r, text = DAYS[w] } end
        end
    end
    if days >= MIN_DAYS then out.bestDay, out.worstDay = bestDay, worstDay end

    -- Fewest listed: least competition for your auction.
    if e.qh then
        local low
        for i = 1, 24 do
            local r, n = Window(e.qh, e.qn, i)
            if r and n >= 2 and (not low or r < low.ratio) then low = { i = i, ratio = r } end
        end
        if low then low.text = Hours(low.i) end
        out.lowSupply = low
    end

    -- Post now, or wait?
    if not out.ready then
        out.advice = ("Learning: %d of %d price checks, at %d of %d different hours. Scan at different times of day."):format(
            samples, MIN_SAMPLES, hours, MIN_HOURS)
    elseif best and out.nowRatio and best.ratio - out.nowRatio > WORTH_WAITING then
        out.wait = true
        out.advice = ("Wait for %s%s: prices run about %d%% higher than now."):format(
            out.bestDay and (out.bestDay.text .. " ") or "", best.text, (best.ratio / out.nowRatio - 1) * 100)
    elseif out.nowRatio then
        out.advice = ("Good time to post: prices now are %s."):format(out.nowRatio >= 1.02 and
            ("%d%% over normal"):format((out.nowRatio - 1) * 100) or "near their best for the day")
    else
        out.advice = ("No prices seen at this hour yet. Best so far: %s%s."):format(
            out.bestDay and (out.bestDay.text .. " ") or "", best and best.text or "?")
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Your own sales: when they sell, how fast, how often
-- ---------------------------------------------------------------------------

-- Sales over the last `days` days by hour of day and day of week:
-- { hours = { [1..24] = count }, days = { [1..7] = count }, gold = { [1..24] = copper }, n,
--   bestHours = text, bestDay = text }.
function Pat:Sales(days)
    local since = time() - (days or 60) * 86400
    local hours, wdays, gold, n = Arr(24), Arr(7), Arr(24), 0
    for _, s in ipairs(ns.db.ledger) do
        local t = s.sold or s.t
        if s.t < since then break end
        local d = date("*t", t)
        hours[d.hour + 1] = hours[d.hour + 1] + 1
        gold[d.hour + 1] = gold[d.hour + 1] + (s.gross or 0)
        wdays[d.wday] = wdays[d.wday] + 1
        n = n + 1
    end
    local out = { hours = hours, days = wdays, gold = gold, n = n }
    if n >= 5 then
        local best, bestN = 1, -1
        for i = 1, 24 do
            local c = 0
            for d = -1, 1 do c = c + hours[(i - 1 + d) % 24 + 1] end
            if c > bestN then best, bestN = i, c end
        end
        out.bestHours, out.bestShare = Hours(best), bestN / n
        local bd, bdn = 1, -1
        for w = 1, 7 do if wdays[w] > bdn then bd, bdn = w, wdays[w] end end
        out.bestDay = DAYS[bd]
    end
    return out
end

-- How an item has done when you post it (last 30 days): { posted, sold, expired, cancelled,
-- sellRate, fastest (median seconds from post to sale, if known) }.
function Pat:SellThrough(id)
    local out = { posted = 0, sold = 0, expired = 0, cancelled = 0 }
    local since = time() - 30 * 86400
    local times = {}
    for _, d in ipairs(ns.db.deposits or {}) do
        if d.t < since then break end
        if d.id == id then
            out.posted = out.posted + 1
            if d.state == "sold" then
                out.sold = out.sold + 1
                if d.resolved then times[#times + 1] = d.resolved - d.t end
            elseif d.state == "expired" then out.expired = out.expired + 1
            elseif d.state == "cancelled" then out.cancelled = out.cancelled + 1 end
        end
    end
    local done = out.sold + out.expired + out.cancelled
    out.sellRate = done > 0 and out.sold / done or nil
    if #times > 0 then
        table.sort(times)
        out.median = times[math.floor((#times + 1) / 2)]
    end
    return out
end

-- Items to time: what you hold and what you've been posting, with their pattern.
-- { { id, pattern, through, qty } }, the ones worth waiting for (and ready) first.
function Pat:Board()
    local ids, qty = {}, {}
    for _, r in ipairs(ns.Portfolio:Holdings()) do ids[r.id] = true; qty[r.id] = r.qty end
    for _, d in ipairs(ns.db.deposits or {}) do if d.id then ids[d.id] = true end end
    local out = {}
    for id in pairs(ids) do
        local p = self:Item(id)
        if p then out[#out + 1] = { id = id, pattern = p, through = self:SellThrough(id), qty = qty[id] } end
    end
    table.sort(out, function(a, b)
        local ra, rb = a.pattern.ready and 1 or 0, b.pattern.ready and 1 or 0
        if ra ~= rb then return ra > rb end
        local sa, sb = a.pattern.spread or 0, b.pattern.spread or 0
        if sa ~= sb then return sa > sb end
        return a.id < b.id
    end)
    return out
end
