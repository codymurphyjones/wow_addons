local _, ns = ...
local C = ns.Compat

-- Portfolio tab: what you hold (bags and bank), what it cost, what it's worth now, and the sales
-- ledger from your mailbox.
local W = ns.Widgets
local UI = ns.UI
local Label, Muted, MakeButton, Hint = W.Label, W.Muted, W.MakeButton, W.Hint

local function ItemName(id)
    local name, _, quality = C.GetItemInfo(id)
    if not name then C.RequestItem(id); return "item " .. id end
    return W.QualityName(name, quality)
end

UI:RegisterPage("portfolio", function(p)
    p.view = "holdings"
    p.summary = Muted(Label(p, "", "WealthPlannerGameFontHighlightSmall", 0, 0, 586))
    p.viewButtons = {}
    for i, v in ipairs({ { "holdings", "Holdings" }, { "ledger", "Sales" } }) do
        local b = MakeButton(p, v[2], 92, 24); b:SetPoint("TOPLEFT", (i - 1) * 96, -22)
        b:SetScript("OnClick", function() p.view = v[1]; p.list:ScrollToTop(); p.Refresh() end)
        p.viewButtons[v[1]] = b
    end
    Hint(p.viewButtons.holdings, "Holdings", "Everything in your bags and bank with a market price. The bank is counted when you visit it.")
    Hint(p.viewButtons.ledger, "Sales", "Auction sales read from your mailbox, with the cost of what you sold when Wealth Planner knows it.")
    p.list = W.CreateRowList(p, -56)

    p.Refresh = function()
        for key, b in pairs(p.viewButtons) do W.SetActive(b, key == p.view) end
        local items = {}
        if p.view == "holdings" then
            local rows, total = ns.Portfolio:Holdings()
            local pnl, costed = 0, 0
            for _, r in ipairs(rows) do
                local s = ns.Analytics:Stats(r.id)
                local where = r.bank > 0 and (r.bags > 0 and ("%d in bags, %d in bank"):format(r.bags, r.bank) or "in bank") or "in bags"
                local detail = ("%s each  -  %s"):format(ns.Gold(r.unit), where)
                if r.cost then
                    detail = detail .. ("  -  cost %s  -  %s%s|r"):format(ns.Gold(r.cost),
                        r.pnl >= 0 and "|cff59f28c+" or "|cffd9736b", ns.Gold(r.pnl))
                    pnl, costed = pnl + r.pnl, costed + 1
                end
                if s then detail = ns.Analytics.SIGNAL_TEXT[s.signal] .. "  " .. detail end
                items[#items + 1] = {
                    icon = select(5, C.GetItemInfoInstant(r.id)) or W.UNKNOWN_ICON,
                    text = ItemName(r.id) .. "  |cffffffffx" .. r.qty .. "|r", link = select(2, C.GetItemInfo(r.id)),
                    detail = detail,
                    right = ("|cffffffff%s|r\n7d %s"):format(ns.Gold(r.value), ns.Pct(s and s.chg7)),
                    onClick = function() UI:Show("market", r.id) end,
                    hint = s and s.reason or "Click: open its chart",
                }
            end
            local seen = ns.Portfolio.BankSeen()
            p.summary:SetText(("%d kinds of goods worth %s. %s %s"):format(#rows, C.Money(total),
                costed > 0 and ("Profit if sold now, after the 5% cut, on the %d you have costs for: %s."):format(costed, C.Money(pnl))
                or "Buy at the auction house or work a job and Wealth Planner keeps your costs.",
                seen and ("Bank last counted %s."):format(date("%m/%d %H:%M", seen)) or "Bank not counted yet: visit a banker."))
            p.list:Set(items, "Nothing with a market price in your bags yet.\n\nScan the market at the auction house to price your goods.")
        else
            for _, s in ipairs(ns.db.ledger) do
                local net = s.gross - (s.cut or 0)
                local detail = ("%s  -  sold for %s, cut %s"):format(date("%m/%d %H:%M", s.t), ns.Gold(s.gross), ns.Gold(s.cut))
                if s.cost then
                    local profit = net - s.cost
                    detail = detail .. ("  -  cost %s  -  %s%s|r"):format(ns.Gold(s.cost), profit >= 0 and "|cff59f28c+" or "|cffd9736b", ns.Gold(profit))
                end
                items[#items + 1] = {
                    icon = s.id and select(5, C.GetItemInfoInstant(s.id)) or W.UNKNOWN_ICON,
                    text = (s.id and ItemName(s.id) or s.name) .. "  |cffffffffx" .. (s.qty or 1) .. "|r",
                    detail = detail, right = "|cffffffff" .. ns.Gold(net) .. "|r",
                }
            end
            local r = ns.Portfolio:Realized(30)
            p.summary:SetText(("Last 30 days: %d sales, %s in, %s auction house cut, %s profit after costs."):format(
                r.sales, C.Money(r.gross), C.Money(r.cut), C.Money(r.profit)))
            p.list:Set(items, "No sales yet.\n\nSales are read from the mailbox when you open it.")
        end
    end
end)
