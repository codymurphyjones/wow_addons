local _, ns = ...
local C = ns.Compat

-- Market tab: every item with price history, read like a stock list (price, 7-day change, a
-- 30-day sparkline, signal), and an item page with its chart, numbers and price targets.
local W = ns.Widgets
local UI = ns.UI
local Label, Muted, MakeButton, Hint = W.Label, W.Muted, W.MakeButton, W.Hint
local T = W.Theme

local VIEWS = {
    { "all", "All", "Every item with price history, most recently seen first." },
    { "watch", "Watchlist", "Items you're watching. Add one with the star on any row, or /wp watch <item>." },
    { "movers", "Movers", "Biggest price change over the last 7 days, up or down." },
    { "undervalued", "Undervalued", "Furthest under their 30-day average: candidates to buy and hold." },
    { "flips", "Flips", "Most profit per item if the price returns to normal, after the 5% auction house cut, weighted by how many are listed." },
}
local RANGES = { { 7, "7d" }, { 30, "30d" }, { 90, "90d" }, { 365, "1y" } }
local MAX_ROWS = 200

local function ItemText(id)
    local name, _, quality = C.GetItemInfo(id)
    if not name then C.RequestItem(id); return "item " .. id end
    return W.QualityName(name, quality)
end

-- Daily closes and supply over the last `days` days, oldest first, gaps filled from the day before.
local function Series(id, days)
    local e = ns.Prices:Entry(id)
    local closes, supply, labels = {}, {}, {}
    if not e then return closes, supply, labels end
    local today = ns.Today()
    local prev
    for day = today - days + 1, today do
        local d = e.d[day]
        if d then prev = d.c end
        if prev then
            closes[#closes + 1] = prev
            supply[#supply + 1] = d and d.q or 0
            labels[#labels + 1] = day
        end
    end
    return closes, supply, labels
end

local function MovingAverage(values, n)
    local out, sum = {}, 0
    for i, v in ipairs(values) do
        sum = sum + v
        if i > n then sum = sum - values[i - n] end
        out[i] = sum / math.min(i, n)
    end
    return out
end

UI:RegisterPage("market", function(p)
    p.view, p.range = "all", 30
    p.summary = Muted(Label(p, "", "WealthPlannerGameFontHighlightSmall", 0, 0, 586))

    -- -----------------------------------------------------------------------
    -- List
    -- -----------------------------------------------------------------------
    local listView = CreateFrame("Frame", nil, p)
    listView:SetAllPoints()
    p.viewButtons = {}
    for i, v in ipairs(VIEWS) do
        local b = MakeButton(listView, v[2], 76, 24); b:SetPoint("TOPLEFT", (i - 1) * 79, -22)
        b:SetScript("OnClick", function() p.view = v[1]; p.list:ScrollToTop(); p.Refresh() end)
        Hint(b, v[2], v[3])
        p.viewButtons[v[1]] = b
    end
    p.search = W.MakeEditBox(listView, 90, "Search...")
    p.search:SetPoint("TOPRIGHT", -94, -21)
    p.search:SetScript("OnTextChanged", function() p.Refresh() end)
    W.RegisterLinkBox(p.search)
    p.scan = MakeButton(listView, "Scan market", 90, 24); p.scan:SetPoint("TOPRIGHT", 0, -22)
    p.scan:SetScript("OnClick", function()
        if ns.Prices.scan then ns.Prices:CancelScan() else ns.Prices:ScanMarket() end
    end)
    Hint(p.scan, "Scan market", "At the auction house: starts Auctionator's scan, and records every item's lowest price and how many are listed as it comes in. Auctionator's own scans are picked up too.")
    p.list = W.CreateRowList(listView, -56)

    -- -----------------------------------------------------------------------
    -- Item page
    -- -----------------------------------------------------------------------
    local detail = CreateFrame("Frame", nil, p)
    detail:SetAllPoints(); detail:Hide()
    local back = MakeButton(detail, "< Market", 80, 24); back:SetPoint("TOPLEFT", 0, -22)
    back:SetScript("OnClick", function() p.item = nil; p.Refresh() end)
    detail.icon = detail:CreateTexture(nil, "ARTWORK"); detail.icon:SetSize(36, 36)
    detail.icon:SetPoint("TOPLEFT", 0, -54); detail.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    detail.name = Label(detail, "", "WealthPlannerGameFontNormalLarge", 44, -54, 300)
    detail.price = Label(detail, "", "WealthPlannerGameFontHighlight", 44, -74, 300)
    detail.signal = Label(detail, "", "WealthPlannerGameFontNormalLarge", 346, -54, 240); detail.signal:SetJustifyH("RIGHT")
    detail.reason = Muted(Label(detail, "", "WealthPlannerGameFontHighlightSmall", 286, -74, 300)); detail.reason:SetJustifyH("RIGHT")
    detail.watch = MakeButton(detail, "Watch", 80, 24); detail.watch:SetPoint("LEFT", back, "RIGHT", 8, 0)
    detail.watch:SetScript("OnClick", function() ns.Prices:Watch(p.item, not ns.Prices:IsWatched(p.item)) end)
    detail.ranges = {}
    for i, r in ipairs(RANGES) do
        local b = MakeButton(detail, r[2], 44, 24); b:SetPoint("TOPRIGHT", -(#RANGES - i) * 48, -22)
        b:SetScript("OnClick", function() p.range = r[1]; p.Refresh() end)
        detail.ranges[r[1]] = b
    end
    detail.chart = ns.Chart:New(detail, 586, 150); detail.chart:SetPoint("TOPLEFT", 0, -104)
    detail.supply = ns.Chart:New(detail, 586, 50); detail.supply:SetPoint("TOPLEFT", 0, -258)

    -- Numbers, two columns.
    detail.stats = {}
    for i = 1, 12 do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local k = Muted(Label(detail, "", "WealthPlannerGameFontHighlightSmall", col * 200, -318 - row * 18, 95))
        local v = Label(detail, "", "WealthPlannerGameFontHighlightSmall", col * 200 + 95, -318 - row * 18, 100)
        detail.stats[i] = { k, v }
    end

    -- Price targets: a chat alert when a scan sees the price cross them.
    Muted(Label(detail, "Alert me when the price is", "WealthPlannerGameFontHighlightSmall", 410, -318, 176))
    local function TargetBox(label, which, y)
        Label(detail, label, "WealthPlannerGameFontHighlightSmall", 410, y, 80)
        local box = W.MakeNumberBox(detail, 70, "gold")
        box:SetPoint("TOPLEFT", 500, y + 6)
        box:SetScript("OnEnterPressed", function(self)
            local g = self:GetValue()
            ns.Prices:SetTarget(p.item, which, g and math.floor(g * 10000 + 0.5) or nil)
            self:ClearFocus()
        end)
        Hint(box, "Price alert", "Gold per item. Press Enter to save; clear it and press Enter to remove.")
        return box
    end
    detail.buy = TargetBox("at or under", "buy", -342)
    detail.sell = TargetBox("at or over", "sell", -366)

    local function RefreshDetail()
        local id = p.item
        local s = ns.Analytics:Stats(id)
        local name, link, quality, _, _, _, _, _, _, icon = C.GetItemInfo(id)
        detail.icon:SetTexture(icon or select(5, C.GetItemInfoInstant(id)) or W.UNKNOWN_ICON)
        detail.name:SetText(ItemText(id))
        detail.watch.text:SetText(ns.Prices:IsWatched(id) and "Unwatch" or "Watch")
        for days, b in pairs(detail.ranges) do W.SetActive(b, days == p.range) end
        if not s then
            detail.price:SetText("No price history yet.")
            detail.signal:SetText(""); detail.reason:SetText("")
            detail.chart:Clear(); detail.supply:Clear()
            for _, st in ipairs(detail.stats) do st[1]:SetText(""); st[2]:SetText("") end
            return
        end
        detail.price:SetText(("%s  |cff8fa3b3today|r  %s"):format(C.Money(s.price), ns.Pct(s.chg1)))
        detail.signal:SetText(ns.Analytics.SIGNAL_TEXT[s.signal] .. (" |cff8fa3b3(%d%% sure)|r"):format(s.confidence * 100))
        detail.reason:SetText(s.reason)

        local closes, supply, days = Series(id, p.range)
        local long = p.range > 90
        if long then
            -- A year: one point a week (weekly figures, then the days), with a 4-week average.
            local weeks
            closes, weeks = ns.Trends:Weekly(id)
            days, supply = {}, {}
            for i, wk in ipairs(weeks) do days[i] = wk * 7; supply[i] = 0 end
        end
        if #closes >= 2 and long then
            detail.chart:Render({
                type = "line", legend = true,
                series = {
                    { name = "Weekly price", color = T.accent, values = closes },
                    { name = "4-week avg", color = T.yellow, values = MovingAverage(closes, 4) },
                },
                yFormat = function(v) return ns.Gold(v) end,
                xFormat = function(i) return days[i] and ("week of " .. date("!%m/%d", days[i] * 86400)) or "" end,
                xLabels = { date("!%m/%d", days[1] * 86400), "this week" },
            })
            detail.supply:Clear()
        elseif #closes >= 2 then
            detail.chart:Render({
                type = "line", legend = true,
                series = {
                    { name = "Price", color = T.accent, values = closes },
                    { name = "7-day avg", color = T.yellow, values = MovingAverage(closes, 7) },
                    { name = "30-day avg", color = T.blue, values = MovingAverage(closes, 30) },
                },
                yFormat = function(v) return ns.Gold(v) end,
                xFormat = function(i) return days[i] and date("!%m/%d", days[i] * 86400) or "" end,
                xLabels = { date("!%m/%d", days[1] * 86400), "today" },
            })
            detail.supply:Render({
                type = "bar", min = 0,
                series = { { name = "Listed", color = T.muted, values = supply } },
                yFormat = function(v) return tostring(math.floor(v + 0.5)) end,
                xFormat = function(i) return days[i] and date("!%m/%d", days[i] * 86400) or "" end,
            })
        else
            detail.chart:Clear(); detail.supply:Clear()
        end

        local rows = {
            { "7-day average", ns.Gold(s.ma7) }, { "30-day average", ns.Gold(s.ma30) },
            { "Change 7 days", ns.Pct(s.chg7) }, { "Change 30 days", ns.Pct(s.chg30) },
            { "Volatility", s.vol and ("%.0f%% a day"):format(s.vol * 100) or "-" },
            { "Normal price", ns.Gold(s.normal) },
            { "Listed now", s.supply and (s.supplyAvg and ("%d (normal %d)"):format(s.supply, s.supplyAvg) or tostring(s.supply)) or "-" },
            -- "40 (4 days)": about 40 sell a day, so what's listed lasts 4 days.
            { "Sold a day", s.demand and (tostring(math.floor(s.demand + 0.5))
                .. (s.cover and (" (%d days)"):format(math.floor(s.cover + 0.5)) or "")) or "-" },
            { "Listings, week", s.supplyShift and ("%.1fx before"):format(s.supplyShift) or "-" },
            { "Vendor price", ns.Gold(s.vendor) },
            { "Flip profit", s.flip and s.flip > 0 and (ns.Gold(s.flip) .. " each") or "-" },
            { "History", ("%d day%s"):format(s.days, s.days == 1 and "" or "s") },
        }
        for i, st in ipairs(detail.stats) do st[1]:SetText(rows[i][1]); st[2]:SetText(rows[i][2]) end
        local w = ns.db.watch[id]
        if not detail.buy:HasFocus() then detail.buy:SetValue(w and w.buy and w.buy / 10000) end
        if not detail.sell:HasFocus() then detail.sell:SetValue(w and w.sell and w.sell / 10000) end
    end

    -- -----------------------------------------------------------------------

    p.Open = function(id) if id then p.item = id; p.Refresh() end end

    p.Refresh = function()
        listView:SetShown(not p.item); detail:SetShown(p.item ~= nil)
        if p.item then
            p.summary:SetText("Price history Wealth Planner recorded at the auction house. Signals compare today's price with the last 30 days.")
            return RefreshDetail()
        end
        for key, b in pairs(p.viewButtons) do W.SetActive(b, key == p.view) end
        p.scan.text:SetText(ns.Prices.scan and "Stop scan" or "Scan market")
        p.scan:SetEnabled(ns.Prices:AuctionOpen() or ns.Prices.scan ~= nil)
        local rows = ns.Analytics:List(p.view, p.search:GetText())
        local items = {}
        for i = 1, math.min(#rows, MAX_ROWS) do
            local id, s = rows[i].id, rows[i].s
            local watched = ns.Prices:IsWatched(id)
            local spark = #s.closes >= 2 and { values = s.closes,
                color = (s.chg7 or 0) >= 0 and T.green or T.red } or nil
            items[#items + 1] = {
                icon = select(5, C.GetItemInfoInstant(id)) or W.UNKNOWN_ICON,
                text = ItemText(id), link = select(2, C.GetItemInfo(id)),
                detail = ns.Analytics.SIGNAL_TEXT[s.signal] .. "  " .. s.reason,
                right = ("|cffffffff%s|r\n7d %s"):format(ns.Gold(s.price), ns.Pct(s.chg7)),
                spark = spark,
                actions = { { watched and "*" or "+", function() ns.Prices:Watch(id, not watched) end,
                    watched and "Stop watching" or "Add to watchlist" } },
                onClick = function() p.item = id; p.Refresh() end,
                hint = "Click: open its chart and numbers",
            }
        end
        local realm = ns.db.realms[ns.RealmKey()]
        local total = 0
        if realm then for _ in pairs(realm.items) do total = total + 1 end end
        p.summary:SetText(("%d items with price history on %s. %s"):format(total, ns.RealmKey(),
            realm and realm.lastScan and ("Last full scan " .. date("%m/%d %H:%M", realm.lastScan) .. ".")
            or "Scan the market at the auction house to start the history."))
        p.list:Set(items, p.view == "watch" and "Your watchlist is empty.\n\nClick + on any item to watch it."
            or (total == 0 and "No prices yet.\n\nOpen the auction house and click Scan market,\nor run Auctionator's scan." or "Nothing here yet."))
    end
end)
