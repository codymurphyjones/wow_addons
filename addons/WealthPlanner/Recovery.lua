local _, ns = ...
local C = ns.Compat

-- Crash recoveries. A crash is a day the price fell to half its normal or less on a flood of
-- listings (twice the usual count or more). Most crashes either hold (the flood was a new source,
-- and the lower price is the new normal) or recover (one seller dumped, the cheap ones sell off,
-- and the price climbs back). This tells them apart from every scan since the crash
-- (History:Raw), so the Invest tab can buy into a recovery as it starts, not at the bottom:
--   watching    crashed in the last WINDOW days, no verdict yet
--   recovering  bounced BOUNCE off its low with higher lows each scan, the flood selling down
--               toward the usual count, and still well under its pre-crash price
--   held        days later, still near its low with the flood still listed: a new normal
--   recovered   back near its pre-crash price: the chance has passed
-- A recovery is sold at half the climb still to go (TARGET_SHARE), never the full old price.
-- Recovery:Scan() runs after each recorded scan and posts a chat alert for new recoveries.
local R = {}
ns.Recovery = R

local WINDOW = 14         -- days a crash is watched
local CRASH_DEPTH = 0.5   -- a crash: the day's low at this share of normal or under
local CRASH_SUPPLY = 2    -- ... with this many times the usual count listed or more
local BOUNCE = 1.25       -- recovering: at least this many times its low
local HIGHER_LOWS = 3     -- ... over this many scans since the low, each at least
local LOW_SLIP = 0.97     -- ... this share of the one before
local SOLD_DOWN = 0.7     -- ... the flood down to this share of its peak or under
local NEAR_USUAL = 1.5    -- ... and to this many times the usual count or under
local ROOM = 0.8          -- ... and still at this share of its pre-crash price or under
local HELD_DAYS = 2       -- held: crashed this many days ago or more
local HELD_NEAR = 1.15    -- ... still within this of its low
local HELD_SUPPLY = 1.5   -- ... with this many times the usual count still listed
local TARGET_SHARE = 0.5  -- sell at the price now plus this share of the climb still to go

local cache = {} -- itemID -> result (false: no crash), until new prices arrive

function R:Invalidate(id)
    if id then cache[id] = nil else wipe(cache) end
end

local function Median(t)
    if #t == 0 then return nil end
    local c = {}
    for i, v in ipairs(t) do c[i] = v end
    table.sort(c)
    local m = (#c + 1) / 2
    return (c[math.floor(m)] + c[math.ceil(m)]) / 2
end

-- The normal price and count before `day`: medians of the 14 days before it.
local function Before(d, day)
    local closes, counts = {}, {}
    for k = day - 14, day - 1 do
        local x = d[k]
        if x then
            closes[#closes + 1] = x.c
            if x.q then counts[#counts + 1] = x.q end
        end
    end
    if #closes < 5 or #counts < 3 then return nil end
    return Median(closes), Median(counts)
end

local function Crashed(d, day)
    local x = d[day]
    if not (x and x.q) then return false end
    local pre, preListed = Before(d, day)
    return pre and x.lo <= pre * CRASH_DEPTH and x.q >= preListed * CRASH_SUPPLY and preListed > 0, pre, preListed
end

local function Pct(x) return math.floor(x * 100 + 0.5) end

-- { status, crashDay, pre, preListed, trough, troughT, now, listed, peakListed, target, why },
-- or nil without a crash in the last WINDOW days.
function R:Check(id)
    if cache[id] ~= nil then return cache[id] or nil end
    local e = ns.Prices:Entry(id)
    local d = e and e.d
    if not d then cache[id] = false return nil end
    local today = ns.Today()
    -- The latest crash, back to the day it started (the days after it look like crashes too).
    local day
    for k = today, today - WINDOW, -1 do
        if Crashed(d, k) then day = k break end
    end
    if not day then cache[id] = false return nil end
    while Crashed(d, day - 1) do day = day - 1 end
    local _, pre, preListed = Crashed(d, day)

    -- Every scan since the crash.
    local start = day * 86400
    local scans = {}
    for _, r in ipairs(ns.History and ns.History:Raw(id) or {}) do
        if r.t >= start then scans[#scans + 1] = r end
    end
    local r = { crashDay = day, pre = pre, preListed = preListed, peakListed = d[day].q, trough = d[day].lo }
    local troughAt = 0
    for i, sc in ipairs(scans) do
        if sc.low <= r.trough then r.trough, r.troughT, troughAt = sc.low, sc.t, i end
        if sc.listed and sc.listed > r.peakListed then r.peakListed = sc.listed end
    end
    local last = scans[#scans]
    local lastDay = d[today] or d[today - 1]
    r.now = last and last.low or (lastDay and lastDay.c) or r.trough
    r.listed = last and last.listed or (lastDay and lastDay.q)
    -- Beta Crash Monitoring: with the beta going offline soon, crashes are mostly players cashing out
    -- (they hold sooner), and only as much of the climb is expected as the days left allow.
    local left = ns.BetaDaysLeft()
    local heldDays = left and left < 2 and 0 or HELD_DAYS
    r.target = math.floor(r.now + TARGET_SHARE * (left and math.min(1, left / 4) or 1) * (pre - r.now))

    -- Higher lows since the trough: the last HIGHER_LOWS scans, each holding the one before.
    local rising = #scans - troughAt >= HIGHER_LOWS
    if rising then
        for i = #scans - HIGHER_LOWS + 2, #scans do
            if scans[i].low < scans[i - 1].low * LOW_SLIP then rising = false break end
        end
    end
    local bounced = r.now >= r.trough * BOUNCE
    local soldDown = r.listed and r.listed <= r.peakListed * SOLD_DOWN and r.listed <= preListed * NEAR_USUAL
    local listedText = r.listed and ("listings %d (peak %d, normally %d)"):format(r.listed, r.peakListed, preListed) or "listings unknown"
    if r.now > pre * ROOM then
        r.status = "recovered"
        r.why = ("Back to %s, near its pre-crash %s."):format(ns.Gold(r.now), ns.Gold(pre))
    elseif left and left < 1 then
        r.status = "held"
        r.why = ("Crashed from %s to %s, and the beta goes offline in %s: no time to recover."):format(
            ns.Gold(pre), ns.Gold(r.trough), ns.BetaLeftText())
    elseif bounced and rising and soldDown then
        r.status = "recovering"
        r.why = ("Recovering from a crash: bounced %d%% off its %s low with higher lows each scan, and the flood sold down: %s. Still %d%% under its pre-crash %s."):format(
            Pct(r.now / r.trough - 1), ns.Gold(r.trough), listedText, Pct(1 - r.now / pre), ns.Gold(pre))
    elseif time() - start >= heldDays * 86400 and r.now <= r.trough * HELD_NEAR and (r.listed or 0) >= preListed * HELD_SUPPLY then
        r.status = "held"
        r.why = ("Holding its drop: still near its %s low %d days on, with %s. Likely its new normal%s."):format(
            ns.Gold(r.trough), math.floor((time() - start) / 86400), listedText,
            left and (" (the beta goes offline in %s, so sellers are cashing out)"):format(ns.BetaLeftText()) or "")
    else
        r.status = "watching"
        local wants = {}
        if not bounced then wants[#wants + 1] = ("a bounce to %s"):format(ns.Gold(r.trough * BOUNCE)) end
        if not rising then wants[#wants + 1] = ("%d scans of higher lows (%d since its low)"):format(HIGHER_LOWS, #scans - troughAt) end
        if not soldDown then wants[#wants + 1] = "the flood of listings selling down" end
        r.why = ("Crashed %s from %s to %s; %s. Watching for %s."):format(date("%m/%d", start + 43200), ns.Gold(pre), ns.Gold(r.trough),
            listedText, table.concat(wants, ", "))
    end
    cache[id] = r
    return r
end

-- Every item with a crash being watched, as { id, r }.
function R:All()
    local out = {}
    for id in pairs(ns.Prices.Items()) do
        local r = self:Check(id)
        if r then out[#out + 1] = { id = id, r = r } end
    end
    return out
end

-- After each recorded scan: a chat alert for each recovery not alerted yet (once per crash).
function R:Scan()
    local alerted = ns.db.recoveryAlerted
    for _, x in ipairs(self:All()) do
        local r = x.r
        if r.status == "recovering" and alerted[x.id] ~= r.crashDay and not ns.Prices:VendorSold(x.id) then
            alerted[x.id] = r.crashDay
            if ns.db.options.alerts then
                local name = select(2, C.GetItemInfo(x.id)) or ("item " .. x.id)
                ns:Print(("|cff59f28cRecovery|r: %s bounced %d%% off its %s low as listings sold down (%d to %d). See Invest."):format(
                    name, Pct(r.now / r.trough - 1), ns.Gold(r.trough), r.peakListed, r.listed or 0), true)
            end
        end
    end
end
