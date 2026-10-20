local _, ns = ...
local C = ns.Compat

-- Overview tab: net worth over time, profit this month, today's signals, and the best jobs for you.
local W = ns.Widgets
local UI = ns.UI
local Label, Muted, MakeButton = W.Label, W.Muted, W.MakeButton
local T = W.Theme

local function ItemName(id)
    local name, _, quality = C.GetItemInfo(id)
    if not name then C.RequestItem(id); return "item " .. id end
    return W.QualityName(name, quality)
end

UI:RegisterPage("overview", function(p)
    p.summary = Muted(Label(p, "", "WealthPlannerGameFontHighlightSmall", 0, 0, 586))

    -- Big numbers across the top.
    local tiles = {}
    local TILE_W = 142
    for i, title in ipairs({ "Net worth", "Invested", "Goods held", "Profit, 30 days" }) do
        local t = UI.Panel(p); t:SetSize(TILE_W, 56); t:SetPoint("TOPLEFT", (i - 1) * (TILE_W + 6), -22)
        Muted(Label(t, title, "WealthPlannerGameFontHighlightSmall", 10, -8))
        t.value = Label(t, "", "WealthPlannerGameFontHighlightLarge", 10, -26, TILE_W - 16)
        tiles[i] = t
    end

    local chartPanel = UI.Panel(p); chartPanel:SetPoint("TOPLEFT", 0, -84); chartPanel:SetSize(586, 128)
    p.chart = ns.Chart:New(chartPanel, 570, 112); p.chart:SetPoint("TOPLEFT", 8, -8)

    -- Two columns: signals on the left, jobs on the right.
    UI.Section(p, "Market signals", 0, -222, 286)
    p.signals = {}
    for i = 1, 6 do
        local b = CreateFrame("Button", nil, p)
        b:SetSize(286, 18); b:SetPoint("TOPLEFT", 0, -246 - (i - 1) * 20)
        b.text = Label(b, "", "WealthPlannerGameFontHighlightSmall", 0, -2, 286); b.text:SetWordWrap(false)
        b:SetScript("OnClick", function(self) if self.id then UI:Show("market", self.id) end end)
        p.signals[i] = b
    end
    UI.Section(p, "Best jobs for you", 300, -222, 286)
    p.jobs = {}
    for i = 1, 6 do
        local b = CreateFrame("Button", nil, p)
        b:SetSize(286, 18); b:SetPoint("TOPLEFT", 300, -246 - (i - 1) * 20)
        b.text = Label(b, "", "WealthPlannerGameFontHighlightSmall", 0, -2, 286); b.text:SetWordWrap(false)
        b:SetScript("OnClick", function(self) if self.key then UI:Show("jobs", self.key) end end)
        p.jobs[i] = b
    end
    local market = MakeButton(p, "Open Market", 110, 24); market:SetPoint("TOPLEFT", 0, -374)
    market:SetScript("OnClick", function() UI:Show("market") end)
    local board = MakeButton(p, "Open Jobs Board", 120, 24); board:SetPoint("TOPLEFT", 300, -374)
    board:SetScript("OnClick", function() UI:Show("jobs") end)

    p.Refresh = function()
        local st = ns.Invest:Status()
        local realized = ns.Portfolio:Realized(30)
        tiles[1].value:SetText(ns.Gold(st.worth))
        local good = st.pct >= st.target - 0.005
        tiles[2].value:SetText(("%s%.0f%%|r |cff8fa3b3/ %d%%|r"):format(good and "|cff59f28c" or "|cffffd24d", st.pct * 100, st.target * 100))
        tiles[3].value:SetText(ns.Gold(st.goods))
        tiles[4].value:SetText((realized.profit >= 0 and "|cff59f28c" or "|cffd9736b") .. ns.Gold(realized.profit) .. "|r")

        local values, days = ns.Portfolio:WorthHistory(60)
        if #values >= 2 then
            p.chart:Render({
                type = "area", title = "Net worth, last 60 days",
                series = { { name = "Net worth", color = T.accent, values = values } },
                yFormat = function(v) return ns.Gold(v) end,
                xFormat = function(i) return days[i] and date("!%m/%d", days[i] * 86400) or "" end,
                xLabels = { date("!%m/%d", days[1] * 86400), "today" },
            })
        else
            p.chart:Clear()
        end

        -- Signals: sell suggestions for what you hold, then the strongest buy signals.
        local lines = {}
        for _, r in ipairs(ns.Portfolio:SellNow()) do
            lines[#lines + 1] = { id = r.row.id, text = ("|cffffd24dSell|r %s x%d  |cff8fa3b3%s|r"):format(ItemName(r.row.id), r.row.qty, r.s.reason) }
        end
        for _, r in ipairs(ns.Analytics:List("undervalued")) do
            if #lines >= #p.signals then break end
            if r.s.signal == "buy" and r.s.confidence >= 0.5 then
                lines[#lines + 1] = { id = r.id, text = ("|cff59f28cBuy|r %s at %s  |cff8fa3b3%s|r"):format(ItemName(r.id), ns.Gold(r.s.price), r.s.reason) }
            end
        end
        for i, b in ipairs(p.signals) do
            local l = lines[i]
            b.id = l and l.id
            b.text:SetText(l and l.text or (i == 1 and "|cff8fa3b3No strong signals yet. They need a few days of price history.|r" or ""))
        end

        local jobs = ns.Jobs and ns.Jobs:Board() or {}
        for i, b in ipairs(p.jobs) do
            local j = jobs[i]
            b.key = j and j.key
            b.text:SetText(j and ("|cffffffff%s|r/hr  %s  |cff8fa3b3%s|r"):format(ns.Gold(j.pay), j.title, j.zoneName or "")
                or (i == 1 and "|cff8fa3b3No jobs found for your level yet.|r" or ""))
        end

        local counts = ns.Analytics:SignalCounts()
        local invest = st.budget >= 1 and (" Invest %s to reach your target: see the Invest tab at the auction house."):format(ns.Gold(st.budget))
            or (st.pct >= st.target - 0.005 and " You're at your investment target." or "")
        p.summary:SetText(("%d buy and %d sell signals, %d sales in the last 30 days.%s"):format(
            counts.buy, counts.sell, realized.sales, invest))
    end
end)
