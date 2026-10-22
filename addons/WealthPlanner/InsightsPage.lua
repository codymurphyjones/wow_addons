local _, ns = ...
local C = ns.Compat

-- Insights tab: the pattern watcher and your wealth.
--   Plans        selling plans for what you hold over days and weeks (Trends.lua), with Why? charts
--   Timing       when each item fetches more (hours of the day, days of the week), whether to post
--                now or wait, and when your own auctions sell
--   Conversions  goods you hold that a recipe turns into more cash, and goods a vendor pays more for
--   Deposits     what your auction deposits cost, what they lost, and how to waste less
--   Wealth       every character's cash, goods, auctions and mail, and how it's moving
local W = ns.Widgets
local UI = ns.UI
local Label, Muted, MakeButton, Hint = W.Label, W.Muted, W.MakeButton, W.Hint
local T = W.Theme

local VIEWS = {
    { "plans", "Plans", "Selling plans for what you hold, over days and weeks: how many to post each day, and at what price, from every scan's history (trend, weekday effect, how many sell a day). Why? shows the charts." },
    { "timing", "Timing", "When items sell for more: hours of the day and days of the week, from every price Wealth Planner sees. Post now, or wait?" },
    { "convert", "Conversions", "Goods you hold that a recipe you know turns into more cash, and goods a vendor pays more for than the auction house." },
    { "deposits", "Deposits", "What your auction deposits cost you, how much expired or cancelled auctions lost, and what to change." },
    { "wealth", "Wealth", "Every character's cash, goods, auctions and mail on this realm, and how your wealth is moving." },
}

local function ItemText(id)
    local name, _, quality = C.GetItemInfo(id)
    if not name then C.RequestItem(id); return "item " .. id end
    return W.QualityName(name, quality)
end

local function Icon(id) return id and select(5, C.GetItemInfoInstant(id)) or W.UNKNOWN_ICON end

local DURATION = { style = "coarse", missing = false }
local function Duration(secs) return ns.Format.Duration(secs, DURATION) end

local function Signed(copper)
    if not copper then return "|cff8fa3b3-|r" end
    return (copper >= 0 and "|cff59f28c+" or "|cffd9736b-") .. ns.Gold(math.abs(copper)) .. "|r"
end

-- Four tiles across the page: { title } -> tiles with .value.
local function Tiles(parent, titles, y)
    local tiles, w = {}, 142
    for i, title in ipairs(titles) do
        local t = UI.Panel(parent); t:SetSize(w, 56); t:SetPoint("TOPLEFT", (i - 1) * (w + 6), y)
        Muted(Label(t, title, "WealthPlannerGameFontHighlightSmall", 10, -8))
        t.value = Label(t, "", "WealthPlannerGameFontHighlightLarge", 10, -26, w - 16)
        tiles[i] = t
    end
    return tiles
end

UI:RegisterPage("insights", function(p)
    p.view = "plans"
    p.summary = Muted(Label(p, "", "WealthPlannerGameFontHighlightSmall", 0, 0, 586))
    p.viewButtons = {}
    for i, v in ipairs(VIEWS) do
        local b = MakeButton(p, v[2], 92, 24); b:SetPoint("TOPLEFT", (i - 1) * 95, -22)
        b:SetScript("OnClick", function() p.view = v[1]; if p.why then p.why:Hide() end; p.Refresh() end)
        Hint(b, v[2], v[3])
        p.viewButtons[v[1]] = b
    end
    local views = {}
    for _, v in ipairs(VIEWS) do
        local f = CreateFrame("Frame", nil, p)
        f:SetPoint("TOPLEFT", 0, -56); f:SetPoint("BOTTOMRIGHT", 0, 0)
        f:Hide(); views[v[1]] = f
    end

    -- "Why?": the charts behind a plan or a timing call, over the current view.
    local why = CreateFrame("Frame", nil, p)
    why:SetPoint("TOPLEFT", 0, -56); why:SetPoint("BOTTOMRIGHT", 0, 0); why:Hide()
    local back = MakeButton(why, "< Back", 70, 22); back:SetPoint("TOPLEFT", 0, 0)
    back:SetScript("OnClick", function() why:Hide(); p.Refresh() end)
    local explain = ns.Explain:Create(why, 586, 340)
    explain:SetPoint("TOPLEFT", 0, -30)
    p.why = why
    local function Why(what)
        for _, f in pairs(views) do f:Hide() end
        why:Show()
        explain:Show(what)
    end

    -- -----------------------------------------------------------------------
    -- Plans
    -- -----------------------------------------------------------------------
    local plans = views.plans
    plans.list = W.CreateRowList(plans, 0)

    local function RefreshPlans()
        local items, gain, expected = {}, 0, 0
        for _, plan in ipairs(ns.Trends:Plans()) do
            gain, expected = gain + math.max(0, plan.gain), expected + plan.expected
            local t = plan.stats
            items[#items + 1] = {
                icon = Icon(plan.id), text = ItemText(plan.id) .. ("  |cff8fa3b3x%d over %d day%s|r"):format(plan.qty, #plan.batches, #plan.batches == 1 and "" or "s"),
                link = select(2, C.GetItemInfo(plan.id)),
                detail = ns.Trends:Schedule(plan, 3) .. (plan.hours and ("  |cff8fa3b3(post around " .. plan.hours .. ")|r") or "")
                    .. (plan.leftover > 0 and ("  |cffffd24d%d more than 3 weeks of selling|r"):format(plan.leftover) or ""),
                right = ("|cffffffff%s|r\n%s|cff8fa3b3 vs today|r"):format(ns.Gold(plan.expected), Signed(plan.gain)),
                actions = { { "Why?", function() Why({ kind = "plan", plan = plan }) end, "The charts behind this plan: past prices, the forecast, and the days it sells on." } },
                onClick = function() Why({ kind = "plan", plan = plan }) end,
                hint = (ns.Trends:Describe(t)) .. " Click: the charts behind it.",
            }
        end
        plans.list:Set(items, "No plans yet.\n\nPlans need a few days of scans: run Auctionator's (or Wealth Planner's) scan\n"
            .. "each time you visit the auction house, and hold goods worth selling.")
        local scans = ns.History:Scans()
        local week, last = 0, scans[#scans]
        for i = #scans, 1, -1 do
            if time() - scans[i].t > 7 * 86400 then break end
            week = week + 1
        end
        return ("Selling what you hold over the next 3 weeks: %s after the cut, %s more than all of it at today's prices. %d scans recorded this week%s."):format(
            ns.Gold(expected), ns.Gold(gain), week, last and (", the last " .. date("%m/%d %H:%M", last.t)) or "")
    end

    -- -----------------------------------------------------------------------
    -- Timing
    -- -----------------------------------------------------------------------
    local timing = views.timing
    local salesPanel = UI.Panel(timing); salesPanel:SetPoint("TOPLEFT", 0, 0); salesPanel:SetSize(586, 78)
    timing.sales = ns.Chart:New(salesPanel, 570, 62); timing.sales:SetPoint("TOPLEFT", 8, -8)
    timing.salesNote = Muted(Label(timing, "", "WealthPlannerGameFontHighlightSmall", 0, -84, 586))
    timing.list = W.CreateRowList(timing, -102)

    local function RefreshTiming()
        local sales = ns.Patterns:Sales(60)
        if sales.n > 0 then
            local labels = {}
            for i = 1, 24 do labels[i] = ("%02d:00"):format(i - 1) end
            timing.sales:Render({
                type = "bar", min = 0, title = "Your sales by hour of the day, last 60 days",
                series = { { name = "Sales", color = T.accent, values = sales.hours } },
                yFormat = function(v) return tostring(math.floor(v + 0.5)) end,
                xFormat = function(i) return labels[i] or "" end,
                xLabels = { "00:00", "06:00", "12:00", "18:00", "23:00" },
            })
        else
            timing.sales:Clear()
        end
        timing.salesNote:SetText(sales.bestHours and
            ("Your auctions sell most around %s (%d%% of sales) and on %ss. %d sales in 60 days."):format(
                sales.bestHours, sales.bestShare * 100, sales.bestDay, sales.n)
            or "Your sales' times come from the auction house mail: open your mailbox after selling to fill this in.")

        local items = {}
        for _, r in ipairs(ns.Patterns:Board()) do
            local pat, th = r.pattern, r.through
            local right
            if not pat.ready then
                right = "|cff8fa3b3Learning|r"
            else
                local when = (pat.bestDay and (pat.bestDay.text .. " ") or "") .. (pat.best and pat.best.text or "")
                right = ("%s\n%s"):format(pat.wait and ("|cffffd24dWait|r " .. when) or "|cff59f28cPost now|r",
                    pat.spread and ("|cff8fa3b3best +%d%% over worst|r"):format(pat.spread * 100) or "")
            end
            local extra = {}
            if pat.lowSupply then extra[#extra + 1] = "fewest listed " .. pat.lowSupply.text end
            if th.posted > 0 then
                extra[#extra + 1] = ("sold %d of %d posts%s"):format(th.sold, th.posted,
                    th.median and (", usually within " .. Duration(th.median)) or "")
            end
            items[#items + 1] = {
                icon = Icon(r.id), text = ItemText(r.id) .. (r.qty and ("  |cff8fa3b3x%d|r"):format(r.qty) or ""),
                link = select(2, C.GetItemInfo(r.id)),
                detail = pat.advice .. (#extra > 0 and ("  |cff8fa3b3(" .. table.concat(extra, "; ") .. ")|r") or ""),
                right = right,
                actions = pat.ready and { { "Why?", function() Why({ kind = "timing", id = r.id }) end, "The price by hour of day behind this call." } } or nil,
                onClick = function() UI:Show("market", r.id) end,
                hint = "Click: open its price chart",
            }
        end
        timing.list:Set(items, "No timing data yet.\n\nPrices are sorted into hours and days as you scan the auction house\n"
            .. "(Wealth Planner's or Auctionator's scan). Scan at different times of day to fill it in.")
        return ("Hours and days are when prices were seen, as a ratio to each item's normal price. "
            .. "Items you hold or have posted are listed; ones with enough data first.")
    end

    -- -----------------------------------------------------------------------
    -- Conversions
    -- -----------------------------------------------------------------------
    local convert = views.convert
    convert.list = W.CreateRowList(convert, 0)

    local function RefreshConvert()
        local items = {}
        local crafts = ns.Conversions:Crafts()
        for _, c in ipairs(crafts) do
            local made = math.floor(c.crafts * c.made + 0.5)
            items[#items + 1] = {
                icon = Icon(c.product), text = ("Craft %d %s"):format(made, ItemText(c.product)),
                link = select(2, C.GetItemInfo(c.product)),
                detail = c.text:gsub("^Craft %d+ [^,]- from ", "From ") .. " (what the market takes in a day)",
                right = ("%s\n|cff8fa3b3%s a craft|r"):format(Signed(c.gain), ns.Gold(c.each)),
                onClick = function() UI:Show("market", c.product) end,
                hint = "Click: the product's price chart",
            }
        end
        local vend = ns.Conversions:VendorBetter()
        for _, v in ipairs(vend) do
            items[#items + 1] = {
                icon = Icon(v.id), text = ("Vendor %s  |cff8fa3b3x%d|r"):format(ItemText(v.id), v.qty),
                link = select(2, C.GetItemInfo(v.id)),
                detail = ("A vendor pays %s each; the auction house brings %s after the cut."):format(
                    ns.Gold(v.vendor), ns.Gold(v.auction * 0.95)),
                right = Signed(v.gain),
                onClick = function() UI:Show("market", v.id) end,
            }
        end
        convert.list:Set(items, "Nothing to convert right now.\n\nOpen your profession windows once so Wealth Planner knows your recipes,\n"
            .. "and scan the auction house so it knows prices.")
        local craftGain, vendGain = 0, 0
        for _, c in ipairs(crafts) do craftGain = craftGain + c.gain end
        for _, v in ipairs(vend) do vendGain = vendGain + v.gain end
        return ("Crafting from what you hold: %s more than selling the reagents. Vendoring: %s more than the auction house. Reagents are valued at what selling them would bring."):format(
            ns.Gold(craftGain), ns.Gold(vendGain))
    end

    -- -----------------------------------------------------------------------
    -- Deposits
    -- -----------------------------------------------------------------------
    local deposits = views.deposits
    deposits.tiles = Tiles(deposits, { "Deposits paid", "Refunded (sold)", "Lost", "Still on the market" }, 0)
    deposits.status = Label(deposits, "", "WealthPlannerGameFontHighlightSmall", 0, -64, 586)
    deposits.list = W.CreateRowList(deposits, -100)

    local function RefreshDeposits()
        local t = ns.Deposits:Totals(30)
        local tiles = deposits.tiles
        tiles[1].value:SetText(ns.Gold(t.paid))
        tiles[2].value:SetText("|cff59f28c" .. ns.Gold(t.refunded) .. "|r")
        tiles[3].value:SetText((t.tooHigh and "|cffd9736b" or "|cffffd24d") .. ns.Gold(t.lost) .. "|r")
        tiles[4].value:SetText(ns.Gold(t.live))
        if t.posts == 0 then
            deposits.status:SetText("|cff8fa3b3No posts recorded yet. Every auction you post from now on (any addon, or the Blizzard UI) is tracked.|r")
        elseif t.tooHigh then
            deposits.status:SetText(("|cffd9736bToo much lost:|r %s in deposits on %s of sales (%d%%), and %d%% of finished posts expired or were cancelled. Under %d%% and %d%% is healthy."):format(
                ns.Gold(t.lost), ns.Gold(t.gross), t.ratio * 100, t.failRate * 100, ns.Deposits.WASTE_RATIO * 100, ns.Deposits.FAIL_RATE * 100))
        else
            deposits.status:SetText(("|cff59f28cHealthy:|r %s lost on %s of sales (%d%%); %d%% of finished posts expired or were cancelled."):format(
                ns.Gold(t.lost), ns.Gold(t.gross), t.ratio * 100, t.failRate * 100))
        end
        local items = {}
        for _, a in ipairs(ns.Deposits:Advice()) do
            items[#items + 1] = {
                icon = Icon(a.id), text = a.id and ItemText(a.id) or "?",
                detail = a.text:gsub("^[^:]+: ", ""),
                right = a.lost and a.lost > 0 and ("|cffd9736b" .. ns.Gold(a.lost) .. "|r") or nil,
                onClick = a.id and function() UI:Show("market", a.id) end or nil,
            }
        end
        deposits.list:Set(items, t.posts == 0 and "" or "Nothing wasteful found in the last 30 days.")
        return ("Last 30 days: %d posts. A deposit comes back when the auction sells and is lost when it expires or you cancel it."):format(t.posts)
    end

    -- -----------------------------------------------------------------------
    -- Wealth
    -- -----------------------------------------------------------------------
    local wealth = views.wealth
    wealth.tiles = Tiles(wealth, { "All characters", "Cash", "Goods (bags, bank, mail)", "On the market" }, 0)
    wealth.changes = Label(wealth, "", "WealthPlannerGameFontHighlightSmall", 0, -64, 586)
    local chartPanel = UI.Panel(wealth); chartPanel:SetPoint("TOPLEFT", 0, -84); chartPanel:SetSize(586, 112)
    wealth.chart = ns.Chart:New(chartPanel, 570, 96); wealth.chart:SetPoint("TOPLEFT", 8, -8)
    wealth.list = W.CreateRowList(wealth, -204, { rowHeight = 30 })

    local function RefreshWealth()
        ns.Portfolio:RecordWorth()
        local a = ns.Portfolio:Account()
        local tiles = wealth.tiles
        tiles[1].value:SetText(ns.Gold(a.total))
        tiles[2].value:SetText(ns.Gold(a.cash))
        tiles[3].value:SetText(ns.Gold(a.goods + a.mail))
        tiles[4].value:SetText(ns.Gold(a.auctions))
        local ch = ns.Portfolio:Changes()
        local pnl, free = ns.Portfolio:Unrealized()
        local realized = ns.Portfolio:Realized(30)
        wealth.changes:SetText(("Today %s   7 days %s   30 days %s   |cff8fa3b3Realized (30d)|r %s   |cff8fa3b3Unrealized|r %s"):format(
            Signed(ch.today), Signed(ch.week), Signed(ch.month), Signed(realized.profit), Signed(pnl)))
        local values, days = ns.Portfolio:AccountHistory(60)
        if #values >= 2 then
            wealth.chart:Render({
                type = "area", title = "All characters' net worth, last 60 days",
                series = { { name = "Net worth", color = T.accent, values = values } },
                yFormat = function(v) return ns.Gold(v) end,
                xFormat = function(i) return days[i] and date("!%m/%d", days[i] * 86400) or "" end,
                xLabels = { date("!%m/%d", days[1] * 86400), "today" },
            })
        else
            local today, times = ns.Portfolio:Today()
            if #today >= 2 then
                wealth.chart:Render({
                    type = "area", title = "This character's net worth, last 24 hours",
                    series = { { name = "Net worth", color = T.accent, values = today } },
                    yFormat = function(v) return ns.Gold(v) end,
                    xFormat = function(i) return times[i] and date("%H:%M", times[i]) or "" end,
                })
            else
                wealth.chart:Clear()
            end
        end
        local items = {}
        for _, c in ipairs(ns.Portfolio:Characters()) do
            items[#items + 1] = {
                noIcon = true, text = c.name .. (ns.Units.Same(c.key, ns.CharKey()) and "  |cff8fa3b3(you)|r" or ""),
                detail = ("Cash %s   Goods %s   Auctions %s%s   |cff8fa3b3updated %s|r"):format(ns.Gold(c.cash), ns.Gold(c.goods),
                    ns.Gold(c.auctions), c.mail > 0 and ("   Mail " .. ns.Gold(c.mail)) or "", c.t and date("%m/%d %H:%M", c.t) or "?"),
                right = "|cffffffff" .. ns.Gold(c.total) .. "|r",
            }
        end
        wealth.list:Set(items, "Log in on each character once to add it here.")
        return ("%d character%s on %s. Goods are valued at market (never above what a vendor charges); unrealized is what selling the goods you bought would make, after the cut. Free goods (farmed): %s."):format(
            a.chars, a.chars == 1 and "" or "s", ns.Units.RealmLabel(), ns.Gold(free))
    end

    local REFRESH = { plans = RefreshPlans, timing = RefreshTiming, convert = RefreshConvert, deposits = RefreshDeposits, wealth = RefreshWealth }

    p.Open = function(view) if view and REFRESH[view] then p.view = view; p.Refresh() end end

    p.Refresh = function()
        if why:IsShown() then return end -- keep the charts up until Back
        for key, b in pairs(p.viewButtons) do W.SetActive(b, key == p.view) end
        for key, f in pairs(views) do f:SetShown(key == p.view) end
        local ok, text = pcall(REFRESH[p.view])
        p.summary:SetText(ok and (text or "") or ("|cffd9736bCouldn't build this view:|r " .. tostring(text)))
    end
end)
