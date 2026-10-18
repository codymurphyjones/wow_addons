local _, ns = ...
local C = ns.Compat

-- "Why?": the charts behind a profit that comes with time rather than right away, so the reasoning
-- can be seen, not just trusted.
--   plan     a multi-day selling plan: the price over the last four weeks, the forecast for the
--            next three (trend and weekday effect), and the days and prices the plan sells at;
--            then each weekday's price against the week around it
--   timing   buy now, sell at a better hour: the price through the day (by hour, against now) with
--            the buy and the sell marked; then the last two weeks' closes
--   revert   a buy signal (under its normal price): the last 30 days against the 30-day average,
--            with the buy and relist prices; then how many were listed each day
--   recovery a crash recovery (Recovery.lua): every scan since the crash with the count listed,
--            the pre-crash price, the low and where to sell; then the last 30 days
--   gap      a listing gap: the listings as a ladder with the cheap ones to buy and the next price
--            marked; then the last 30 days with the buy and relist prices
--
-- Ex:Create(parent, width, height) makes a view; view:Show(what) draws it, where what is
-- { kind, id, plan | price, sellAt, ... }.
local Ex = {}
ns.Explain = Ex

local W = ns.Widgets
local T = W.Theme
local Label, Muted = W.Label, W.Muted

local function Name(id)
    local name, _, quality = C.GetItemInfo(id)
    if not name then C.RequestItem(id); return "item " .. id end
    return W.QualityName(name, quality)
end

local function DateText(day) return date("%m/%d", day * 86400 + 43200) end
local function Gold(v) return ns.Gold(v) end

local View = {}
View.__index = View

function Ex:Create(parent, width, height)
    local v = setmetatable({}, View)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, height)
    v.frame = f
    v.title = Label(f, "", "GameFontNormal", 0, 0, width)
    v.title:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    v.text = Muted(Label(f, "", "GameFontHighlightSmall", 0, -18, width))
    v.text:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    v.chart1 = ns.Chart:New(f, width, 100)
    v.chart2 = ns.Chart:New(f, width, 100)
    -- The charts take the frame's width and split the height left under the text, so the view fits
    -- whatever it's anchored to.
    f:SetScript("OnSizeChanged", function() v:Layout() end)
    f:Hide()
    return v
end

function View:Layout()
    local f = self.frame
    local w, h = f:GetWidth(), f:GetHeight()
    if not (w and h and w > 0 and h > 0) then return end
    local top = 18 + math.max(14, math.ceil(self.text:GetStringHeight() or 0)) + 8
    local room = math.max(80, h - top - 6)
    local h1 = math.floor(room * 0.6)
    self.chart1.frame:SetSize(w, h1); self.chart1:SetPoint("TOPLEFT", 0, -top)
    self.chart2.frame:SetSize(w, room - h1); self.chart2:SetPoint("TOPLEFT", 0, -top - h1 - 6)
end

function View:Hide() self.frame:Hide() end
function View:IsShown() return self.frame:IsShown() end
function View:SetPoint(...) self.frame:SetPoint(...) end

local function PlanCharts(v, what)
    local plan = what.plan
    local id, t = plan.id, plan.stats
    local hist, days = ns.Trends:Daily(id, 28)
    local today = ns.Today()
    local past = {}
    for i, d in ipairs(days) do past[i] = { d - today, hist[i] } end
    local fc = {}
    for off = 0, 20 do fc[#fc + 1] = { off, t.Forecast(off) } end
    local sells = {}
    for _, b in ipairs(plan.batches) do sells[#sells + 1] = { b.offset, b.price } end
    local now = plan.analytics.price
    v.chart1:Render({
        type = "line", legend = true, zero = false,
        title = "Price: last 4 weeks, forecast for the next 3",
        series = {
            { name = "Price", color = T.accent, points = past },
            { name = "Forecast", color = T.blue, points = fc },
            { name = "Plan sells", color = T.green, points = sells },
        },
        thresholds = { { value = now, color = T.yellow, label = "today " .. Gold(now) } },
        yFormat = Gold,
        xFormat = function(x) return x == 0 and "today" or DateText(today + math.floor(x + 0.5)) end,
        xLabels = { DateText(today - #past + 1), "today", DateText(today + 20) },
    })
    if t.weekday then
        local values, colors = {}, {}
        for wd = 1, 7 do
            values[wd] = ((t.weekday[wd] or 1) - 1) * 100
            colors[wd] = wd == t.bestWeekday and T.green or (wd == t.worstWeekday and T.red or T.muted)
        end
        v.chart2:Render({
            type = "bar", title = "Each weekday's price against the week around it (%)",
            series = { { name = "vs week", values = values, colors = colors } },
            yFormat = function(x) return ("%+.0f%%"):format(x) end,
            xFormat = function(i) return ns.Patterns.DAYS[i] or "" end,
            xLabels = ns.Patterns.DAYS,
        })
    else
        v.chart2:Clear()
    end
    v.title:SetText(("Selling plan: %s x%d"):format(Name(id), plan.qty))
    v.text:SetText(("%s The plan sells about %d a day (a share of what the market takes) on the days the forecast pays most, never under a vendor's price: %s after the cut, against %s for all of it at today's %s. %s"):format(
        ns.Trends:Describe(t), plan.perDay, Gold(plan.expected), Gold(plan.flat), Gold(now),
        plan.hours and ("Post around " .. plan.hours .. ".") or ""))
end

local function TimingCharts(v, what)
    local id = what.id
    local e = ns.Prices:Entry(id)
    local s = ns.Analytics:Stats(id)
    local pat = ns.Patterns:Item(id)
    if not (e and e.ph and s and pat) then return false end
    local values, colors = {}, {}
    local hourNow = date("*t").hour + 1
    local nowRatio = pat.nowRatio or 1
    for i = 1, 24 do
        local r = e.pn[i] > 0 and e.ph[i] / e.pn[i] or nil
        values[i] = r and s.price * r / nowRatio or 0
        local inBest = pat.best and math.abs(((i - pat.best.i + 12) % 24) - 12) <= 1
        colors[i] = i == hourNow and T.yellow or (inBest and T.green or T.muted)
    end
    v.chart1:Render({
        type = "bar", title = "Price by hour of day (from every scan), scaled to today's price",
        series = { { name = "Price", values = values, colors = colors } },
        thresholds = { { value = s.price, color = T.yellow, label = "buy now " .. Gold(s.price) },
            what.sellAt and { value = what.sellAt, color = T.green, label = "sell " .. Gold(what.sellAt) } or nil },
        yFormat = Gold,
        xFormat = function(i) return ("%02d:00"):format(i - 1) end,
        xLabels = { "00:00", "06:00", "12:00", "18:00", "23:00" },
    })
    local hist, days = ns.Trends:Daily(id, 14)
    if #hist >= 2 then
        v.chart2:Render({
            type = "line", zero = false, title = "Daily price, last 2 weeks",
            series = { { name = "Price", color = T.accent, values = hist } },
            yFormat = Gold,
            xFormat = function(i) return days[i] and DateText(days[i]) or "" end,
            xLabels = { DateText(days[1]), "today" },
        })
    else
        v.chart2:Clear()
    end
    v.title:SetText("Timing: " .. Name(id))
    local atLow = pat.worst and nowRatio <= pat.worst.ratio * 1.03
    v.text:SetText(("Yellow is now, green is its best hours. %s; %s it usually sells about %d%% higher than now. %d price checks so far."):format(
        atLow and "It's at its daily low now" or ("Now it's %+d%% against its normal price"):format((nowRatio - 1) * 100),
        (pat.bestDay and (pat.bestDay.text .. " ") or "") .. (pat.best and pat.best.text or ""),
        pat.best and (pat.best.ratio / nowRatio - 1) * 100 or 0, pat.samples))
    return true
end

local function RevertCharts(v, what)
    local id = what.id
    local s = ns.Analytics:Stats(id)
    if not (s and s.ma30) then return false end
    local hist, days = ns.Trends:Daily(id, 30)
    if #hist < 2 then return false end
    local avg = {}
    for i = 1, #hist do avg[i] = s.ma30 end
    local e = ns.Prices:Entry(id)
    local supply = {}
    for i, d in ipairs(days) do supply[i] = e.d[d] and e.d[d].q or 0 end
    local Count = function(x) return tostring(math.floor(x + 0.5)) end
    v.chart1:Render({
        type = "line", legend = true, zero = false, title = "Price and listings, 30 days",
        series = { { name = "Price", color = T.accent, values = hist }, { name = "30-day average", color = T.blue, values = avg } },
        bars = { name = "Listed", color = T.muted, values = supply, format = Count },
        thresholds = { { value = s.price, color = T.yellow, label = "buy " .. Gold(s.price) },
            { value = (s.target or s.ma30) * 0.95, color = T.green, label = "relist (after cut) " .. Gold((s.target or s.ma30) * 0.95) } },
        yFormat = Gold,
        xFormat = function(i) return days[i] and DateText(days[i]) or "" end,
        xLabels = { DateText(days[1]), "today" },
    })
    v.chart2:Render({
        type = "bar", min = 0, title = "Listed each day",
        series = { { name = "Listed", color = T.muted, values = supply } },
        yFormat = Count,
        xFormat = function(i) return days[i] and DateText(days[i]) or "" end,
    })
    local t = ns.Trends:Stats(id)
    -- Supply and demand: what's listed against normal, and how long it lasts at the sell rate.
    local market = ""
    if s.supply then
        market = ("Listed: %d%s"):format(s.supply, s.supplyAvg and (" (normal %d)"):format(math.floor(s.supplyAvg + 0.5)) or "")
        if s.demand then
            -- Listings that leave between scans: sales, but cancels and reposts too, so during a
            -- flood of listings it says nothing about how fast they'd clear.
            market = market .. ("; about %d listings leave a day (sales, cancels and reposts)"):format(math.floor(s.demand + 0.5))
            if (s.supplyRatio or 0) < 2 and s.cover then
                market = market .. (", so about %d days to clear"):format(math.floor(s.cover + 0.5))
            end
        end
        market = market .. ". "
    end
    v.title:SetText((s.falling and "Losing value: " or "Under its normal price: ") .. Name(id))
    local normal = s.normal or s.ma30
    local head = s.falling and (s.reason .. " ")
        or ("Today's %s is %d%% under its normal price of %s (the 30-day median). The profit assumes it returns there (after the 5%% cut), which can take days. "):format(
            Gold(s.price), math.floor((1 - s.price / normal) * 100), Gold(normal))
    v.text:SetText(head .. market .. ns.Trends:Describe(t))
    return true
end

local function Count(x) return tostring(math.floor(x + 0.5)) end

-- A crash recovery: every scan since the day before the crash (price, with the count listed as
-- bars), against the pre-crash price, the low and where to sell; then the last 30 days.
local function RecoveryCharts(v, what)
    local id = what.id
    local r = ns.Recovery and ns.Recovery:Check(id)
    if not r then return false end
    local lows, listed, times = {}, {}, {}
    for _, sc in ipairs(ns.History:Raw(id)) do
        if sc.t >= (r.crashDay - 1) * 86400 then
            lows[#lows + 1], listed[#listed + 1], times[#times + 1] = sc.low, sc.listed or 0, sc.t
        end
    end
    if #lows < 2 then return false end
    local function When(t) return date("%m/%d %H:%M", t) end
    v.chart1:Render({
        type = "line", legend = true, zero = false, title = "Since the crash, every scan",
        series = { { name = "Price", color = T.accent, values = lows } },
        bars = { name = "Listed", color = T.muted, values = listed, format = Count },
        thresholds = { { value = r.pre, color = T.blue, label = "before the crash " .. Gold(r.pre) },
            { value = r.target, color = T.green, label = "sell near " .. Gold(r.target) },
            { value = r.trough, color = T.yellow, label = "low " .. Gold(r.trough) } },
        yFormat = Gold,
        xFormat = function(i) return times[i] and When(times[i]) or "" end,
        xLabels = { date("%m/%d", times[1]), "now" },
    })
    local hist, days = ns.Trends:Daily(id, 30)
    if #hist >= 2 then
        local e = ns.Prices:Entry(id)
        local supply = {}
        for i, d in ipairs(days) do supply[i] = e.d[d] and e.d[d].q or 0 end
        v.chart2:Render({
            type = "line", legend = true, zero = false, title = "Price and listings, 30 days",
            series = { { name = "Price", color = T.accent, values = hist } },
            bars = { name = "Listed", color = T.muted, values = supply, format = Count },
            yFormat = Gold,
            xFormat = function(i) return days[i] and DateText(days[i]) or "" end,
            xLabels = { DateText(days[1]), "today" },
        })
    end
    local titles = { recovering = "Recovering: ", watching = "Crashed, watching: ", held = "Holding its drop: ", recovered = "Recovered: " }
    v.title:SetText((titles[r.status] or "") .. Name(id))
    v.text:SetText(r.why)
    return true
end

-- A listing gap: the item's listings as a ladder (price, how many), the cheap ones to buy marked,
-- the price they're relisted under; then the last 30 days with the buy and relist prices.
local function GapCharts(v, what)
    local id = what.id
    local e = ns.Prices:Entry(id)
    local depth = e and e.depth
    if not (depth and depth.tiers and #depth.tiers >= 2) then return false end
    local items = {}
    for _, t in ipairs(depth.tiers) do
        local buy, next = t[1] <= what.high, t[1] == what.next
        items[#items + 1] = { Gold(t[1]) .. (buy and "  |cff59f28cbuy|r" or next and "  |cffffd24dnext price|r" or ""),
            t[2], buy and T.green or next and T.yellow or T.muted, Count(t[2]) }
    end
    v.chart1:Render({ type = "hbarList", title = "Listed now, cheapest first", items = items, labelWidth = 150, valueWidth = 40 })
    local s = ns.Analytics:Stats(id)
    local hist, days = ns.Trends:Daily(id, 30)
    if #hist >= 2 then
        local supply = {}
        for i, d in ipairs(days) do supply[i] = e.d[d] and e.d[d].q or 0 end
        v.chart2:Render({
            type = "line", legend = true, zero = false, title = "Price and listings, 30 days",
            series = { { name = "Price", color = T.accent, values = hist } },
            bars = { name = "Listed", color = T.muted, values = supply, format = Count },
            thresholds = { { value = what.high, color = T.yellow, label = "buy up to " .. Gold(what.high) },
                { value = what.relist, color = T.green, label = "relist " .. Gold(what.relist) } },
            yFormat = Gold,
            xFormat = function(i) return days[i] and DateText(days[i]) or "" end,
            xLabels = { DateText(days[1]), "today" },
        })
    end
    local parts = {
        ("The cheapest %d listed sit at %s, well under the next price with stock behind it: %s, with %d listed there and at the two prices after it."):format(
            what.qty, what.low == what.high and Gold(what.low) or (Gold(what.low) .. "-" .. Gold(what.high)), Gold(what.next), what.behind),
        ("Buy them and relist at %s, just under it. It pays as long as those sellers don't drop their price first."):format(Gold(what.relist)),
    }
    if s and s.normal then
        parts[#parts + 1] = what.relist > s.normal * 1.05
            and ("That's over its normal price of %s, so it may sit a while."):format(Gold(s.normal))
            or ("Its normal price is %s, so the relist is no stretch."):format(Gold(s.normal))
    end
    if s and s.demand then parts[#parts + 1] = ("About %d listings leave a day."):format(math.floor(s.demand + 0.5)) end
    parts[#parts + 1] = ("Listings read %d min ago."):format(math.floor((time() - depth.t) / 60))
    v.title:SetText("Listing gap: " .. Name(id))
    v.text:SetText(table.concat(parts, " "))
    return true
end

function View:Show(what)
    self.chart1:Clear(); self.chart2:Clear()
    local ok
    if what.kind == "plan" then PlanCharts(self, what); ok = true
    elseif what.kind == "timing" then ok = TimingCharts(self, what)
    elseif what.kind == "revert" then ok = RevertCharts(self, what)
    elseif what.kind == "recovery" then ok = RecoveryCharts(self, what)
    elseif what.kind == "gap" then ok = GapCharts(self, what) end
    if not ok then
        self.title:SetText(Name(what.id))
        self.text:SetText("Not enough history to chart yet: it fills in with every auction house scan.")
    end
    self.frame:Show()
    self:Layout()
end


