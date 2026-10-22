local _, ns = ...

-- Trends over days and weeks, from every scan's history (History.lua, Prices.lua), and selling
-- plans built on them.
--   Stats(id)  the price's direction over 7 and 28 days (% a day, from a least-squares fit of the
--              daily closes), the day-of-week effect (each weekday's close against the week around
--              it, from the last 8 weeks), how many sell a day (listings that disappear between
--              scans, from the per-scan history; an estimate), and a forecast for the coming days
--   Plan(row)  how to sell what you hold over the next three weeks: each day's share of what the
--              market takes, on the days the forecast pays most (never under a vendor's price),
--              against selling it all at today's price
local Tr = {}
ns.Trends = Tr

local AH_CUT = 0.05
local HORIZON = 21          -- days a plan looks ahead
local SHARE_OF_VOLUME = 0.3 -- your share of what sells in a day
local MAX_DRIFT = 0.3       -- forecasts never move more than 30% from today's normal

local function Close(e, day)
    local d = e.d[day]
    return d and (d.sc and d.sc > 0 and d.ms / d.sc or d.c) or nil
end

-- Daily closes for the last `days` days, oldest first, gaps carried forward: values, days.
function Tr:Daily(id, days)
    local e = ns.Prices:Entry(id)
    local values, labels = {}, {}
    if not e then return values, labels end
    local today, prev = ns.Today(), nil
    for day = today - days + 1, today do
        local c = Close(e, day)
        if c then prev = c end
        if prev then values[#values + 1] = prev; labels[#labels + 1] = day end
    end
    return values, labels
end

-- Weekly closes (from the weekly figures, then the days), oldest first: values, week numbers.
function Tr:Weekly(id)
    local e = ns.Prices:Entry(id)
    local byWeek = {}
    if not e then return {}, {} end
    for wk, w in pairs(e.w or {}) do
        if w.cn > 0 then byWeek[wk] = { w.cs, w.cn } end
    end
    for day in pairs(e.d) do
        local c = Close(e, day)
        if c then
            local wk = math.floor(day / 7)
            local b = byWeek[wk] or { 0, 0 }
            b[1], b[2] = b[1] + c, b[2] + 1
            byWeek[wk] = b
        end
    end
    local weeks = {}
    for wk in pairs(byWeek) do weeks[#weeks + 1] = wk end
    table.sort(weeks)
    local values = {}
    for i, wk in ipairs(weeks) do values[i] = byWeek[wk][1] / byWeek[wk][2] end
    return values, weeks
end

-- Least-squares slope of log(values) against their index: the change a step, as a fraction.
local function Slope(values, from)
    local xs, ys = {}, {}
    for i = math.max(1, from or 1), #values do
        if values[i] and values[i] > 0 then xs[#xs + 1] = i; ys[#ys + 1] = math.log(values[i]) end
    end
    local n = #xs
    if n < 4 then return nil end
    local sx, sy, sxx, sxy = 0, 0, 0, 0
    for i = 1, n do sx, sy, sxx, sxy = sx + xs[i], sy + ys[i], sxx + xs[i] * xs[i], sxy + xs[i] * ys[i] end
    local den = n * sxx - sx * sx
    if den == 0 then return nil end
    return math.exp((n * sxy - sx * sy) / den) - 1
end
Tr.Slope = Slope

-- How many sell a day: listings that disappear between consecutive scans less than a day apart,
-- scaled to a day. Only scan pairs ending between `fromHours` and `toHours` ago when given (e.g.
-- 0, 96: the last four days). nil without enough scans. Reads History only, so Analytics can use it.
function Tr:Volume(id, fromHours, toHours)
    local raw = ns.History and ns.History:Raw(id) or {}
    local now = time()
    local newest = now - (fromHours or 0) * 3600
    local oldest = toHours and now - toHours * 3600 or 0
    local gone, hours, pairsSeen = 0, 0, 0
    for i = 2, #raw do
        local a, b = raw[i - 1], raw[i]
        local gap = (b.t - a.t) / 3600
        if a.listed and b.listed and gap > 0 and gap <= 26 and b.t <= newest and b.t > oldest then
            gone = gone + math.max(0, a.listed - b.listed)
            hours = hours + gap
            pairsSeen = pairsSeen + 1
        end
    end
    if pairsSeen < 2 or hours <= 0 then return nil end
    return gone / hours * 24
end

local cache, cacheAt = {}, 0

-- { slope7, slope28 (fraction a day), weekday = { [1..7] = ratio } or nil, bestWeekday, worstWeekday,
--   volume (a day), volumeEstimated, base (today's normal price), scans (in the per-scan history),
--   Forecast(dayOffset) }, or nil without history.
function Tr:Stats(id)
    local now = GetTime()
    if now - cacheAt > 5 then wipe(cache); cacheAt = now end
    if cache[id] ~= nil then return cache[id] or nil end
    local s = ns.Analytics:Stats(id)
    if not s then cache[id] = false return nil end
    local closes = self:Daily(id, 56)
    local t = { slope7 = Slope(closes, #closes - 6), slope28 = Slope(closes, #closes - 27) }

    -- Day of the week: each day's close against the 7 days around it.
    local e = ns.Prices:Entry(id)
    local sums, counts = {}, {}
    local today = ns.Today()
    for day = today - 55, today - 3 do
        local c = Close(e, day)
        if c then
            local s7, n7 = 0, 0
            for k = day - 3, day + 3 do
                local v = Close(e, k)
                if v then s7, n7 = s7 + v, n7 + 1 end
            end
            if n7 >= 4 then
                local wd = date("*t", day * 86400 + 43200).wday
                sums[wd], counts[wd] = (sums[wd] or 0) + c / (s7 / n7), (counts[wd] or 0) + 1
            end
        end
    end
    local wdays, ratios = 0, {}
    for wd = 1, 7 do
        if (counts[wd] or 0) >= 2 then wdays = wdays + 1; ratios[wd] = sums[wd] / counts[wd] end
    end
    if wdays >= 4 then
        t.weekday = ratios
        for wd, r in pairs(ratios) do
            if not t.bestWeekday or r > ratios[t.bestWeekday] then t.bestWeekday = wd end
            if not t.worstWeekday or r < ratios[t.worstWeekday] then t.worstWeekday = wd end
        end
    end

    t.volume = self:Volume(id)
    if not t.volume then
        t.volume, t.volumeEstimated = s.supplyAvg and s.supplyAvg * 0.25 or nil, true
    end
    t.scans = #(ns.History and ns.History:Raw(id) or {})
    t.base = s.ma7 or s.price
    local slope = t.slope28 or t.slope7 or 0
    function t.Forecast(offset)
        local drift = math.max(-MAX_DRIFT, math.min(MAX_DRIFT, (1 + slope) ^ offset - 1))
        local wd = date("*t", (today + offset) * 86400 + 43200).wday
        return t.base * (1 + drift) * (t.weekday and t.weekday[wd] or 1)
    end
    cache[id] = t
    return t
end

local PCT = { decimals = 1, signed = true }
local function Pct(x) return ns.Format.Pct(x, PCT) end

-- How the trend reads in words.
function Tr:Describe(t)
    if not t then return "No history yet." end
    local slope = t.slope28 or t.slope7
    local dir = not slope and "no clear direction yet"
        or (slope > 0.004 and ("rising %s a day"):format(Pct(slope)))
        or (slope < -0.004 and ("falling %s a day"):format(Pct(slope)))
        or "flat"
    local parts = { (dir:gsub("^%l", string.upper)) }
    if t.bestWeekday then
        parts[#parts + 1] = ("best on %ss (%s), weakest on %ss (%s)"):format(ns.Patterns.DAYS[t.bestWeekday],
            Pct(t.weekday[t.bestWeekday] - 1), ns.Patterns.DAYS[t.worstWeekday], Pct(t.weekday[t.worstWeekday] - 1))
    end
    if t.volume then
        parts[#parts + 1] = ("about %d sell a day%s"):format(math.floor(t.volume + 0.5), t.volumeEstimated and " (rough)" or "")
    end
    return table.concat(parts, "; ") .. "."
end

-- A selling plan for one holding: { id, qty, batches = { { offset, day, qty, price } }, leftover,
-- expected (after the cut), flat (all of it at today's price), gain, perDay, stats, hours }, or nil.
function Tr:Plan(row)
    local id = row.id
    if ns.Prices:VendorSold(id) then return nil end
    local s = ns.Analytics:Stats(id)
    local t = self:Stats(id)
    if not (s and t and t.volume and t.volume > 0) then return nil end
    local perDay = math.max(1, math.floor(t.volume * SHARE_OF_VOLUME))
    local floor = ns.Prices:Vendor(id) or 0
    local today = ns.Today()
    local days = {}
    -- Beta Crash Monitoring: plan only up to the day the beta goes offline.
    local left = ns.BetaDaysLeft()
    local horizon = left and math.max(1, math.min(HORIZON, math.floor(left))) or HORIZON
    for offset = 0, horizon - 1 do
        local price = t.Forecast(offset)
        if price * (1 - AH_CUT) > floor then days[#days + 1] = { offset = offset, price = price } end
    end
    table.sort(days, function(a, b)
        if math.abs(a.price - b.price) > a.price * 0.005 then return a.price > b.price end
        return a.offset < b.offset
    end)
    local left, batches = row.qty, {}
    for _, d in ipairs(days) do
        if left <= 0 then break end
        local q = math.min(left, perDay)
        batches[#batches + 1] = { offset = d.offset, day = today + d.offset, qty = q, price = d.price }
        left = left - q
    end
    if #batches == 0 then return nil end
    table.sort(batches, function(a, b) return a.offset < b.offset end)
    local expected, sold = 0, 0
    for _, b in ipairs(batches) do expected, sold = expected + b.qty * b.price * (1 - AH_CUT), sold + b.qty end
    local flat = sold * s.price * (1 - AH_CUT)
    local pat = ns.Patterns:Item(id)
    return {
        id = id, qty = row.qty, batches = batches, leftover = left, expected = expected, flat = flat,
        gain = expected - flat, perDay = perDay, stats = t, analytics = s,
        hours = pat and pat.ready and pat.best and pat.best.text or nil,
    }
end

-- Plans for what you hold, the most to gain first.
function Tr:Plans()
    local out = {}
    for _, r in ipairs(ns.Portfolio:Holdings()) do
        if r.value >= 100 then
            local p = self:Plan(r)
            if p then out[#out + 1] = p end
        end
    end
    table.sort(out, function(a, b) return a.gain > b.gain end)
    return out
end

-- "Tue 14th: 20 at 1.2g, Thu 16th: 20 at 1.3g, ..."
function Tr:Schedule(plan, max)
    local parts = {}
    for i, b in ipairs(plan.batches) do
        if i > (max or 4) then parts[#parts + 1] = ("+%d more days"):format(#plan.batches - (max or 4)); break end
        parts[#parts + 1] = ("%s: %d at %s"):format(b.offset == 0 and "today" or date("%a %d", b.day * 86400 + 43200), b.qty, ns.Gold(b.price))
    end
    return table.concat(parts, ", ")
end

