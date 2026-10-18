local _, ns = ...
local C = ns.Compat

-- The auction house's "Invest" tab: how much of your wealth is on the market against your target,
-- the target itself (share to keep invested, cash reserve, most per item), the opportunities
-- Wealth Planner found (crafts, conversions from your bags, buys, and buys timed by the price
-- patterns: Invest:Opportunities), and "Go liquid": what to sell, and where, for the most cash now. Added with LibAHTab, the same tab library Wally's and Auctionator's tabs use.
local Tab = {}
ns.InvestTab = Tab

local W = ns.Widgets
local Label, Muted, MakeButton, Hint = W.Label, W.Muted, W.MakeButton, W.Hint
local T = W.Theme
local ACCENT = W.ACCENT

local TAB_ID = "WealthPlannerInvest"
local LEFT_W = 300

local READY = "Interface\\RaidFrame\\ReadyCheck-Ready"
local NOT_READY = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local GAP_READS = 40 -- most-listed items' listings read per auction house visit, looking for gaps

local lib, panel

-- How each kind of idea is labelled.
local KIND = {
    craft = "|cff66ccffCraft|r", convert = "|cff59f28cFrom your bags|r",
    buy = "|cff59f28cBuy|r", timing = "|cffffd24dTiming|r", gap = "|cff59f28cGap|r", recovery = "|cff59f28cRecovery|r",
}
local gapReads = 0

local function ItemName(id)
    local name, _, quality = C.GetItemInfo(id)
    if not name then C.RequestItem(id); return "item " .. id end
    return W.QualityName(name, quality)
end

-- A number box with a label in front and a unit after; saves to options[key] on Enter or focus loss.
local function Setting(parent, y, title, key, unit, hint, min, max)
    Label(parent, title, "GameFontHighlightSmall", 0, y, 130)
    local box = W.MakeNumberBox(parent, 50)
    box:SetPoint("TOPLEFT", 140, y + 6)
    Muted(Label(parent, unit, "GameFontHighlightSmall", 196, y, 100))
    local function Save(self)
        local v = self:GetValue()
        if v then
            ns.db.options[key] = math.max(min, math.min(max, math.floor(v + 0.5)))
            ns.Invest:Record()
            ns:Changed()
        end
        self:SetValue(ns.db.options[key])
    end
    box:SetScript("OnEnterPressed", function(self) Save(self); self:ClearFocus() end)
    box:HookScript("OnEditFocusLost", Save)
    Hint(box, title, hint)
    return box
end

local function Build()
    if panel or not AuctionHouseFrame then return end
    lib = LibStub and LibStub("LibAHTab-1-0", true)
    if not lib then return end

    panel = CreateFrame("Frame", "WealthPlannerInvestPanel", AuctionHouseFrame, "BackdropTemplate")
    panel:SetPoint("TOPLEFT", 8, -64); panel:SetPoint("BOTTOMRIGHT", -8, 30)
    W.SetBackdrop(panel, 0.97)
    panel:SetScript("OnShow", function() Tab:Refresh() end)

    -- Left: where you stand and your target.
    local left = CreateFrame("Frame", nil, panel)
    left:SetPoint("TOPLEFT", 12, -10); left:SetPoint("BOTTOMLEFT", 12, 10); left:SetWidth(LEFT_W)
    Label(left, "Invested", "GameFontNormal", 0, 0):SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    panel.pct = Label(left, "", "GameFontHighlightLarge", 0, -18, LEFT_W)

    local bar = CreateFrame("Frame", nil, left)
    bar:SetSize(LEFT_W, 10); bar:SetPoint("TOPLEFT", 0, -44)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND"); bar.bg:SetAllPoints(); bar.bg:SetColorTexture(T.track[1], T.track[2], T.track[3], 1)
    bar.fill = bar:CreateTexture(nil, "ARTWORK"); bar.fill:SetPoint("TOPLEFT"); bar.fill:SetPoint("BOTTOMLEFT")
    bar.mark = bar:CreateTexture(nil, "OVERLAY"); bar.mark:SetSize(2, 16); bar.mark:SetColorTexture(1, 1, 1, 0.9)
    panel.bar = bar

    panel.lines = {}
    for i = 1, 5 do
        local k = Muted(Label(left, "", "GameFontHighlightSmall", 0, -62 - (i - 1) * 16, 140))
        local v = Label(left, "", "GameFontHighlightSmall", 140, -62 - (i - 1) * 16, 160)
        v:SetJustifyH("RIGHT")
        panel.lines[i] = { k, v }
    end

    Label(left, "Your target", "GameFontNormal", 0, -150):SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    panel.target = Setting(left, -174, "Keep invested", "investTarget", "% of wealth",
        "The share of your wealth (gold + goods + auctions) Wealth Planner keeps invested in goods and auctions.", 0, 100)
    panel.reserve = Setting(left, -200, "Cash reserve", "cashReserve", "gold",
        "The least gold you want to keep on hand, for repairs, training and travel. It's a floor you set, not gold you have: only cash above it is free to invest, and while you're under it the tab says by how much.", 0, 1000000)
    panel.perItem = Setting(left, -226, "Most per item", "maxPerItem", "% of wealth",
        "No single item takes more than this share of your wealth, so one bad call can't sink you.", 1, 100)
    panel.chart = ns.Chart:New(left, LEFT_W, 120); panel.chart:SetPoint("TOPLEFT", 0, -256)

    -- Right: what to do about it.
    local right = CreateFrame("Frame", nil, panel)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 18, 0); right:SetPoint("BOTTOMRIGHT", -12, 10)
    panel.send = MakeButton(right, "Send to Cart", 100, 24); panel.send:SetPoint("TOPRIGHT", 0, 0)
    panel.send:SetScript("OnClick", function()
        local p = panel.planned or {}
        ns.Invest:ToQuartermaster(panel.picks or {}, p.plan, p.spend, p.gain)
    end)
    Hint(panel.send, "Send to Cart", "Makes a new Quartermaster shopping list (\"Wealth Planner\" and the date) with the plan's buys, each capped at the most it still pays to buy at, and opens it on the Cart tab so you can review it before buying. The plan never puts more than 30% of your cash to spend on one idea. Sent plans shows every plan you sent.")
    panel.scan = MakeButton(right, "Scan market", 100, 24); panel.scan:SetPoint("RIGHT", panel.send, "LEFT", -6, 0)
    panel.scan:SetScript("OnClick", function()
        if ns.Prices.scan then ns.Prices:CancelScan() else ns.Prices:ScanMarket() end
    end)
    Hint(panel.scan, "Scan market", "Starts Auctionator's scan (its full or summary scan, as set in its options); Wealth Planner records every item's lowest price and how many are listed as it comes in, so the suggestions use today's prices.")
    panel.liquid = MakeButton(right, "Go liquid", 90, 24); panel.liquid:SetPoint("RIGHT", panel.scan, "LEFT", -6, 0)
    panel.liquid:SetScript("OnClick", function() panel.mode = panel.mode ~= "liquid" and "liquid" or nil; Tab:Refresh() end)
    Hint(panel.liquid, "Go liquid", "What to sell, and where, to turn everything in your bags into the most cash: the vendor now, or the auction house when it pays clearly more.")
    panel.sent = MakeButton(right, "Sent plans", 84, 24); panel.sent:SetPoint("RIGHT", panel.liquid, "LEFT", -6, 0)
    panel.sent:SetScript("OnClick", function() panel.mode = panel.mode ~= "sent" and "sent" or nil; Tab:Refresh() end)
    Hint(panel.sent, "Sent plans", "Every plan you sent to Quartermaster, newest first: each idea, what it's for and what it should earn.")
    -- The buttons have the top line; the heading and its explanation go under them.
    panel.head = Label(right, "", "GameFontNormal", 0, -32)
    panel.head:SetPoint("RIGHT", right, "RIGHT", -4, 0)
    panel.head:SetJustifyH("LEFT"); panel.head:SetWordWrap(false)
    panel.sub = Muted(Label(right, "", "GameFontHighlightSmall", 0, -50))
    panel.sub:SetPoint("RIGHT", right, "RIGHT", -4, 0)
    panel.sub:SetJustifyH("LEFT")
    panel.list = W.CreateRowList(right, -88, { rowHeight = 34 })
    -- "Why?": the charts behind a profit that comes with time (Explain.lua), over the list.
    panel.why = CreateFrame("Frame", nil, right)
    panel.why:SetPoint("TOPLEFT", 0, -82); panel.why:SetPoint("BOTTOMRIGHT", 0, 0); panel.why:Hide()
    local back = MakeButton(panel.why, "< Back", 70, 22); back:SetPoint("TOPLEFT", 0, 0)
    back:SetScript("OnClick", function() panel.why:Hide(); panel.list.scroll:Show(); Tab:Refresh() end)
    panel.explain = ns.Explain:Create(panel.why, 500, 330)
    panel.explain:SetPoint("TOPLEFT", 0, -30)
    panel.explain:SetPoint("BOTTOMRIGHT", 0, 0)

    lib:CreateTab(TAB_ID, panel, "|T" .. ns.INVEST_ICON .. ":16:16:0:0|t Invest", "Wealth Planner: Invest")
end

-- Shows the charts behind one opportunity.
function Tab:Explain(what)
    if not panel then return end
    panel.list.scroll:Hide(); panel.list.empty:Hide()
    panel.why:Show()
    panel.explain:Show(what)
end

function Tab:Refresh()
    if not (panel and panel:IsVisible()) then return end
    if panel.why:IsShown() then return end -- keep the charts up until Back
    local st = ns.Invest:Status()
    local o = ns.db.options

    local reached = st.pct >= st.target - 0.005
    local color = reached and T.green or (st.pct >= st.target * 0.75 and T.yellow or T.red)
    panel.pct:SetText(("%s%.0f%%|r  |cff8fa3b3of %s, target %d%%|r"):format(W.Hex(color), st.pct * 100, ns.Gold(st.worth), o.investTarget))
    local bw = panel.bar:GetWidth()
    panel.bar.fill:SetWidth(math.max(1, bw * math.min(1, st.pct)))
    panel.bar.fill:SetColorTexture(color[1], color[2], color[3], 1)
    panel.bar.mark:ClearAllPoints(); panel.bar.mark:SetPoint("CENTER", panel.bar, "LEFT", bw * st.target, 0)

    local rows = {
        { "Cash", C.Money(st.cash) },
        { "Goods held", C.Money(st.goods) },
        { "On auction (invested)", C.Money(st.auctions) .. (" |cff8fa3b3(%d)|r"):format(st.listed) },
        -- The reserve is a floor you set, not gold you have: under it, say by how much, in red.
        { "Cash reserve", st.short and ("%s %s(%s short)|r"):format(C.Money(st.reserve), W.Hex(T.red), C.Money(st.reserve - st.cash))
            or C.Money(st.reserve) },
        { "Free to invest", C.Money(math.max(0, st.cash - st.reserve)) },
    }
    for i, l in ipairs(panel.lines) do l[1]:SetText(rows[i][1]); l[2]:SetText(rows[i][2]) end
    for _, b in ipairs({ panel.target, panel.reserve, panel.perItem }) do
        if not b:HasFocus() then b:SetValue(o[b == panel.target and "investTarget" or b == panel.reserve and "cashReserve" or "maxPerItem"]) end
    end

    local values, days = ns.Invest:History(60)
    if #values >= 2 then
        panel.chart:Render({
            type = "line", title = "Invested, last 60 days", min = 0, max = 100,
            series = { { name = "Invested", color = T.accent, values = values } },
            thresholds = { { value = o.investTarget, color = T.yellow, label = "target" } },
            yFormat = function(v) return ("%d%%"):format(v) end,
            xFormat = function(i) return days[i] and date("!%m/%d", days[i] * 86400) or "" end,
        })
    else
        panel.chart:Clear()
    end

    panel.scan.text:SetText(ns.Prices.scan and ("Stop (%d)"):format(ns.Prices.scan.groups or 0) or "Scan market")

    local items = {}
    panel.picks = nil
    local empty = ""
    panel.liquid.text:SetText(panel.mode == "liquid" and "Back" or "Go liquid")
    panel.sent.text:SetText(panel.mode == "sent" and "Back" or "Sent plans")
    panel.planned = nil
    local function Icon(id) return select(5, C.GetItemInfoInstant(id)) or W.UNKNOWN_ICON end
    if panel.mode == "liquid" then
        local l = ns.Invest:Liquidate()
        panel.head:SetText(("|cffffd24dGo liquid: %s|r"):format(ns.Gold(l.best + l.soon)))
        panel.sub:SetText(("Best mix: |cffffffff%s now|r from vendors, |cffffffff%s more|r from auctions (within 48 hours, if they sell). Everything to a vendor right now: %s."):format(
            ns.Gold(l.best), ns.Gold(l.soon), ns.Gold(l.now)))
        -- Queue a row in Wally to sell once (never added to its lists): auctions wait for your
        -- approval on Wally's Selling tab, vendor sales go with the junk at the next merchant.
        local sellOnce = WallyAPI and WallyAPI.SellOnce
        for _, r in ipairs(l.rows) do
            local status
            if sellOnce and not r.bank then
                local link = select(2, C.GetItemInfo(r.id))
                local queued = link and WallyAPI.SellingOnce(link)
                local where = r.how == "auction" and "Wally's Selling tab lists it once, for you to approve there"
                    or "Wally sells it with your junk at the next merchant"
                status = queued and {
                    texture = READY, hint = ("Queued in Wally: %s. It's not added to Wally's lists.\nClick to take it off."):format(where),
                    onClick = function() WallyAPI.SellOnce(link, nil); Tab:Refresh() end,
                } or {
                    texture = NOT_READY, hint = ("Click to queue it in Wally: %s. Just this once; it's not added to Wally's lists."):format(where),
                    onClick = function()
                        if not WallyAPI.SellOnce(link or r.id, r.how) then ns:Print("That item isn't loaded yet; click again in a moment.", true) end
                        Tab:Refresh()
                    end,
                }
            end
            items[#items + 1] = {
                status = status,
                icon = Icon(r.id),
                text = ("%s  |cffffffffx%d|r  %s%s"):format(ItemName(r.id), r.qty,
                    r.how == "auction" and "|cff66ccffList it|r" or "|cffffd24dVendor it|r",
                    r.bank and "  |cff8fa3b3(in your bank)|r" or ""),
                link = select(2, C.GetItemInfo(r.id)),
                detail = r.reason,
                right = ("|cffffffff%s|r\n%s"):format(ns.Gold(r.cash), r.how == "auction" and "|cff8fa3b3after the cut|r" or "|cff8fa3b3now|r"),
                onClick = function() ns.Invest:OpenAtAuction(r.id) end,
                hint = "Click: see its listings at the auction house. Shift-click to link. Auction prices are today's lowest from your scans, after the 5% cut.",
            }
        end
        empty = "Nothing in your bags sells for anything."
        panel.send:Hide()
    elseif panel.mode == "sent" then
        -- Every plan sent to Quartermaster: a header per plan (click to open or close it), then its ideas.
        panel.openPlans = panel.openPlans or {}
        local sent = ns.db.sentPlans
        panel.head:SetText(("Sent plans: %d"):format(#sent))
        panel.sub:SetText("Each plan you sent to Quartermaster, newest first. Every idea says what to do and why: buys and gaps are bought to relist higher, timing buys wait for a better hour, crafts sell what you make. Click a plan to open or close it.")
        for i, e in ipairs(sent) do
            local open = panel.openPlans[e.t]
            if open == nil then open = i == 1 end
            items[#items + 1] = {
                noIcon = true,
                text = ("%s  |cffffd24d%s|r  |cff8fa3b3%s|r"):format(open and "-" or "+", date("%m/%d %H:%M", e.t), e.list or ""),
                detail = ("%d idea%s: spend %s for +%s expected, after the cut."):format(#e.ideas, #e.ideas == 1 and "" or "s", ns.Gold(e.spend), ns.Gold(e.gain)),
                right = ("|cff59f28c+%s|r\n|cff8fa3b3spend %s|r"):format(ns.Gold(e.gain), ns.Gold(e.spend)),
                selected = open,
                onClick = function() panel.openPlans[e.t] = not open; Tab:Refresh() end,
                actions = { { "Forget", function() ns.Invest:ForgetSent(e) end, "Remove this plan from the list (the Quartermaster list stays)." } },
                hint = "Click: show or hide its ideas.",
            }
            if open then
                for _, idea in ipairs(e.ideas) do
                    items[#items + 1] = {
                        icon = Icon(idea.id),
                        text = ("%s  %s%s"):format(KIND[idea.kind] or "", idea.title or "",
                            idea.scaled and idea.units and idea.of and ("  |cff8fa3b3(planned %d of %d)|r"):format(idea.units, idea.of) or ""),
                        link = select(2, C.GetItemInfo(idea.id)),
                        detail = idea.detail,
                        right = ("|cff59f28c+%s|r\n|cff8fa3b3spend %s|r"):format(ns.Gold(idea.profit or 0), ns.Gold(idea.cost or 0)),
                        onClick = function() ns.Invest:OpenAtAuction(idea.id) end,
                        hint = "The objective, as planned when you sent it. Click: see it at the auction house.",
                    }
                end
            end
        end
        empty = "No plans sent yet.\n\nSend to Cart makes a Quartermaster shopping list from the plan, and the plan shows up here."
        panel.send:Hide()
    else
        -- Opportunities: crafts, conversions, buys and pattern buys from everything gathered.
        local opps, free = ns.Invest:Opportunities()
        local picks, merged = {}, {}
        -- The plan (Invest:Plan): what to spend on, no idea over 30% of your cash to spend. It's what
        -- Send to Cart sends.
        local plan, spend, gain = ns.Invest:Plan(opps, free)
        panel.planned = { plan = plan, spend = spend, gain = gain }
        local inPlan = {}
        for _, p in ipairs(plan) do
            inPlan[p.op] = p
            for _, b in ipairs(p.buy) do
                local m = merged[b.id]
                if not m then m = { id = b.id, qty = 0 }; merged[b.id] = m; picks[#picks + 1] = m end
                m.qty = m.qty + b.qty
                if b.maxUnit then m.maxUnit = math.max(m.maxUnit or 0, b.maxUnit) end
            end
        end
        for _, op in ipairs(opps) do
            local p = inPlan[op]
            local tag = p and (p.scaled and ("  |cff59f28c[plan: %d of %d]|r"):format(p.units, op.units) or "  |cff59f28c[plan]|r")
                or (op.affordable and "" or "  |cff8fa3b3(needs " .. ns.Gold(op.cost) .. ")|r")
            items[#items + 1] = {
                planned = p ~= nil,
                icon = Icon(op.id),
                text = ("%s  %s%s"):format(KIND[op.kind] or "", op.title, tag),
                link = select(2, C.GetItemInfo(op.id)),
                detail = p and p.scaled and ("Plan: spend %s for +%s (capped at 30%% of your cash to spend). %s"):format(ns.Gold(p.cost), ns.Gold(p.profit), op.detail)
                    or op.detail,
                dim = (not p) and 0.55 or nil,
                actions = op.explain and { { "Why?", function() Tab:Explain(op.explain) end,
                    "The charts and numbers behind this idea, so it isn't a gamble." } } or nil,
                onClick = function()
                    local target = op.id
                    if (op.kind == "craft" or op.kind == "convert") and op.buy and op.buy[1] then target = op.buy[1].id end
                    ns.Invest:OpenAtAuction(target)
                end,
                right = op.unknown and ("|cff8fa3b3+%s each|r\n|cff8fa3b3count unknown|r"):format(ns.Gold(op.each))
                    or ("|cff59f28c+%s|r\n|cff8fa3b3%s|r"):format(ns.Gold(op.profit), op.cost > 0 and ("spend " .. ns.Gold(op.cost)) or "no cost"),
                hint = "Click: open it at the auction house (Quartermaster's Buying tab if installed); a craft opens the first reagent to buy. "
                    .. "Expected profit is after the 5% cut, at today's prices from your scans. Crafts are capped at what the market takes in a day.",
            }
        end
        -- The plan's ideas first, the rest after (each group in its own order).
        local ordered = {}
        for _, it in ipairs(items) do if it.planned then ordered[#ordered + 1] = it end end
        for _, it in ipairs(items) do if not it.planned then ordered[#ordered + 1] = it end end
        items = ordered
        panel.picks = picks
        -- Read the real listings of the buys whose count isn't known yet.
        local need = {}
        for _, op in ipairs(opps) do if op.unknown then need[#need + 1] = op.id end end
        -- Crashed items being watched for a recovery: their listings tell a real bounce from a few cheap ones.
        if ns.Recovery then
            for _, x in ipairs(ns.Recovery:All()) do
                if (x.r.status == "watching" or x.r.status == "recovering") and not ns.Prices:Depth(x.id) then need[#need + 1] = x.id end
            end
        end
        if #need > 0 then ns.Prices:FetchDepth(need, 8) end
        -- And the most-listed items' listings, a few a refresh (GAP_READS a visit), to find gaps
        -- without a full scan.
        if gapReads < GAP_READS then
            local ids = ns.Invest:DepthWanted(8)
            gapReads = gapReads + #ids
            ns.Prices:FetchDepth(ids, 8)
        end
        panel.head:SetText(#plan > 0 and ("Plan: %d of %d ideas, spend %s for |cff59f28c+%s|r"):format(#plan, #opps, ns.Gold(spend), ns.Gold(gain))
            or (#opps > 0 and ("%d opportunit%s, none fit your cash yet"):format(#opps, #opps == 1 and "y" or "ies"))
            or "No opportunities found yet")
        local target = st.over and ("You're over your %d%% target."):format(o.investTarget)
            or (st.shortfall >= 1 and ("Put %s more on the market to reach %d%%."):format(ns.Gold(st.shortfall), o.investTarget))
            or ("On your %d%% target."):format(o.investTarget)
        -- What's holding the list back: days of price history (signals need 3, full confidence 7).
        local days = ns.Invest:HistoryDays()
        local limit = days < 7 and (" |cffffd24dPrice history: %d day%s, so buy signals %s.|r"):format(days, days == 1 and "" or "s",
            days < 3 and "can't show yet (they need 3)" or "are still weak (full at 7)") or ""
        local spend = st.short
            and ("%sYou're %s under your %s cash reserve, so nothing is free to invest.|r"):format(W.Hex(T.red), ns.Gold(st.reserve - st.cash), ns.Gold(st.reserve))
            or ("%s to spend (cash above your %s reserve)."):format(ns.Gold(free), ns.Gold(st.reserve))
        local left = ns.BetaDaysLeft()
        local beta = not left and ""
            or left > 0 and (" |cffffd24dBeta goes offline in %s: only what resells by then is suggested.|r"):format(ns.BetaLeftText())
            or " |cffffd24dThe beta is over.|r"
        panel.sub:SetText(("%s %s%s%s"):format(spend, target, limit, beta))
        empty = "Nothing profitable found yet.\n\nScan the market a few days running (and at different times of day),\nand open your profession windows so Wealth Planner knows your recipes."
            .. "\nGaps in the listings show up as the auction house reads them (a full scan reads them all)."
        panel.send:SetShown(#picks > 0 and QuartermasterAPI ~= nil and QuartermasterAPI.SetShoppingList ~= nil)
    end
    -- Scan sits at the right edge when there's nothing to send.
    panel.scan:ClearAllPoints()
    if panel.send:IsShown() then panel.scan:SetPoint("RIGHT", panel.send, "LEFT", -6, 0) else panel.scan:SetPoint("TOPRIGHT", 0, 0) end
    panel.list:Set(items, empty)
end

function Tab:Select()
    if not (panel and lib and AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return false end
    lib:SetSelected(TAB_ID)
    return true
end

ns:On("ADDON_LOADED", function(name)
    if name == "Blizzard_AuctionHouseUI" and ns.db then Build() end
end)
ns:OnLoad(function() if AuctionHouseFrame then Build() end end)
ns:On("AUCTION_HOUSE_SHOW", function() gapReads = 0; if not panel then Build() end end)
