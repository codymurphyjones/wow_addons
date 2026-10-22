local _, ns = ...
local C = ns.Compat

-- Keeps a share of your wealth invested. Your wealth is everything you own:
--   cash         gold on hand
--   goods        what's in your bags and bank, at market price (vendor goods at no more than a
--                vendor charges)
--   on auction   your auctions on the market right now (Wally's On Market list), after the 5% cut
-- "Invested" is only what's on the market: auctions run 48 hours at most, so it's money at work
-- for the next two days. Under your target share, Wealth Planner suggests goods you hold to
-- list, then what to buy and list with spare cash (never touching a cash reserve you set,
-- spreading the money over several items and never buying up more than a share of what's
-- listed). "Go liquid" lists what to sell, and where, to turn your goods into the most cash now.
local Invest = {}
ns.Invest = Invest

local AH_CUT = 0.05
local MAX_PICKS = 8
local MAX_SHARE_OF_LISTED = 0.3 -- never buy more than this share of what's on the market
local OVER_BY = 0.15            -- over the target by this much counts as over
local AUCTION_PREMIUM = 1.25    -- go liquid: list it rather than vendor it when the auction pays this much more
local SHARE_OF_VOLUME = 0.3     -- your share of what sells in a day (as in Trends.lua)
local SELL_DAYS = 7             -- never buy more than you could resell in this many days

local function Opt() return ns.db.options end

-- The most worth buying to resell: about SELL_DAYS of your share of what sells a day (or only the
-- days left before the beta goes offline, with Beta Crash Monitoring on: none in its last half day),
-- or nil when sales aren't known yet.
local function DemandCap(s)
    if not s.demand then return nil end
    local left = ns.BetaDaysLeft()
    if left then return math.floor(s.demand * SHARE_OF_VOLUME * math.min(SELL_DAYS, left)) end
    return math.max(1, math.floor(s.demand * SHARE_OF_VOLUME * SELL_DAYS))
end

-- Your auctions on the market, valued at their buyout after the cut.
function Invest:Auctions()
    if not (WallyAPI and WallyAPI.AuctionsOnMarket) then return 0, 0 end
    local list = WallyAPI.AuctionsOnMarket()
    local value, n = 0, 0
    for _, a in ipairs(list) do
        if a.unit then value = value + a.unit * (a.quantity or 1) * (1 - AH_CUT) end
        n = n + 1
    end
    return value, n
end

-- Where your wealth stands: { cash, goods, auctions, listed, invested, worth, pct, target, reserve,
-- shortfall (to put on the market to reach the target), budget (cash that can go to it now),
-- over (well over the target), short (cash under the reserve) }.
function Invest:Status()
    local cash = GetMoney() or 0
    local _, goods = ns.Portfolio:Holdings()
    local auctions, listed = self:Auctions()
    local invested = auctions
    local worth = cash + goods + auctions
    local target = (Opt().investTarget or 50) / 100
    local reserve = (Opt().cashReserve or 0) * 10000
    local shortfall = math.max(0, target * worth - invested)
    local budget = math.min(shortfall, math.max(0, cash - reserve))
    local pct = worth > 0 and invested / worth or 0
    return {
        cash = cash, goods = goods, auctions = auctions, listed = listed, invested = invested, worth = worth,
        pct = pct, target = target, reserve = reserve, shortfall = shortfall, budget = budget,
        over = pct > target + OVER_BY, short = cash < reserve,
    }
end

-- Candidates to buy: strong buy signals first, then steady "stores of value" (low volatility,
-- plenty listed, priced at or under normal) to park money in when nothing is on sale.
local function Candidates()
    local out = {}
    for _, r in ipairs(ns.Analytics:All()) do
        local s = r.s
        -- Vendor goods: buy them from a vendor when you need them, never as an investment.
        if s.ma30 and s.price > 0 and not ns.Prices:VendorSold(r.id) then
            local ret = ((s.target or s.ma30) * (1 - AH_CUT) - s.price) / s.price
            if s.signal == "buy" and s.confidence >= 0.5 then
                out[#out + 1] = { id = r.id, s = s, ret = ret, score = ret * s.confidence + 1, kind = "signal" }
            elseif s.days >= 7 and (s.vol or 1) <= 0.1 and (s.supplyAvg or 0) >= 20 and (s.z or 1) <= 0.3 and ret >= -0.05
                and not s.falling and (s.supplyShift or 1) < 1.25 then -- not while listings pile up
                out[#out + 1] = { id = r.id, s = s, ret = ret, score = ret, kind = "store" }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.id < b.id
    end)
    return out
end

-- What to buy with `budget` copper: { { id, qty, price, cost, profit, reason, kind } }, and what's
-- left over.
function Invest:Suggestions(budget)
    local status = self:Status()
    budget = budget or status.budget
    local perItem = math.max(1, (Opt().maxPerItem or 20) / 100 * status.worth)
    local held = {}
    for _, r in ipairs(ns.Portfolio:Holdings()) do held[r.id] = r.value end
    local picks, left = {}, budget
    for _, c in ipairs(Candidates()) do
        if #picks >= MAX_PICKS or left < 1 then break end
        local price = c.s.price
        local name = C.GetItemInfo(c.id)
        -- Wally posts Auction List items at the going price: buying them back would just churn.
        local selling = name and WallyAPI and WallyAPI.OnAuctionList and WallyAPI.OnAuctionList(name)
        local cap = selling and 0 or math.min(perItem - (held[c.id] or 0), left)
        local qty = math.floor(cap / price)
        local listed = c.s.supply or c.s.supplyAvg
        if listed then qty = math.min(qty, math.floor(listed * MAX_SHARE_OF_LISTED)) end
        if not (c.s.vendor and price < c.s.vendor * 0.95) then qty = math.min(qty, DemandCap(c.s) or qty) end
        if qty >= 1 then
            local cost = qty * price
            picks[#picks + 1] = {
                id = c.id, qty = qty, price = price, cost = cost, kind = c.kind,
                profit = math.floor(qty * ((c.s.target or c.s.ma30) * (1 - AH_CUT) - price)),
                reason = c.kind == "signal" and c.s.reason
                    or ("Steady price (%.0f%% a day), %d usually listed: a safe place to park gold."):format((c.s.vol or 0) * 100, c.s.supplyAvg or 0),
            }
            left = left - cost
        end
    end
    return picks, left
end

-- Goods you hold worth listing, to put `need` copper on the market: sell signals first, then goods
-- trading at or above their 30-day average (most valuable first). Goods with a buy signal are
-- kept (they're cheap right now), and so are vendor goods (no one should pay over the vendor).
-- Returns { { row, s, qty, value, kind = "signal" | "normal", reason } } and what's still needed.
function Invest:ListSuggestions(need)
    local signal, normal = {}, {}
    for _, r in ipairs(ns.Portfolio:Holdings()) do
        local s = ns.Analytics:Stats(r.id)
        if ns.Prices:VendorSold(r.id) then
            -- vendor goods: not something to list
        elseif s and s.signal == "sell" and s.confidence >= 0.5 then
            signal[#signal + 1] = { row = r, s = s, kind = "signal" }
        elseif not (s and s.signal == "buy") and (not (s and s.ma30) or r.unit >= s.ma30 * 0.97) then
            normal[#normal + 1] = { row = r, s = s, kind = "normal" }
        end
    end
    local out = {}
    for _, list in ipairs({ signal, normal }) do
        for _, c in ipairs(list) do
            if need <= 0 or #out >= MAX_PICKS then break end
            local each = c.row.unit * (1 - AH_CUT)
            local qty = each > 0 and math.min(c.row.qty, math.ceil(need / each)) or 0
            if qty >= 1 then
                c.qty, c.value = qty, math.floor(qty * each)
                c.reason = c.kind == "signal" and c.s.reason
                    or (c.s and c.s.ma30 and ("At or above its 30-day average (%s): a fair time to list."):format(ns.Gold(c.s.ma30))
                    or "No price history yet; priced at your latest scan.")
                out[#out + 1] = c
                need = need - c.value
            end
        end
    end
    return out, math.max(0, need)
end

-- Go liquid: everything in your bags you could turn into cash, and the best way for each.
--   vendor   what a vendor pays for the stack, right now
--   auction  what listing it at today's price brings after the 5% cut (it sells within 48 hours,
--            if it sells): only for goods that aren't bound, have a market price, and aren't
--            vendor goods
-- An item goes to the auction house when that pays AUCTION_PREMIUM times the vendor or more,
-- else to the vendor. Bank goods are listed apart (take them out first).
-- Returns { rows = { { id, qty, bound, bank, vendor, auction, how, cash, reason } },
-- now (cash from vendoring everything), best (the recommended mix), soon (what the mix's
-- auctions should bring) }.
function Invest:Liquidate()
    local stacks = {}
    local function Add(info, bank)
        local id = info.id or C.IDFromLink(info.link)
        if not id or info.noValue then return end
        local key = id .. (info.bound and ":b" or "") .. (bank and ":k" or "")
        local st = stacks[key]
        if not st then
            st = { id = id, qty = 0, bound = info.bound and true or false, bank = bank }
            stacks[key] = st
        end
        st.qty = st.qty + (info.count or 1)
    end
    for _, _, info in C.IterateBags(C.BagList("bags")) do Add(info, false) end
    -- The bank as last seen (no bound flags: counts only).
    local h = ns.db.holdings[ns.CharKey()]
    for id, n in pairs(h and h.bank or {}) do
        local key = id .. ":k"
        stacks[key] = { id = id, qty = n, bound = false, bank = true }
    end

    local rows, now, best, soon = {}, 0, 0, 0
    for _, st in pairs(stacks) do
        local sell = ns.Prices:Vendor(st.id) or 0
        local vendor = sell * st.qty
        local auction
        if not st.bound and not ns.Prices:VendorSold(st.id) then
            local price = ns.Prices:Price(st.id)
            if price and price > 0 then auction = math.floor(price * st.qty * (1 - AH_CUT)) end
        end
        if vendor > 0 or auction then
            local how, cash, reason
            if auction and auction >= vendor * AUCTION_PREMIUM and auction > vendor then
                how, cash = "auction", auction
                reason = vendor > 0 and ("%.1fx the vendor's %s."):format(auction / vendor, ns.Gold(vendor))
                    or "Vendors won't buy it."
            else
                how, cash = "vendor", vendor
                reason = st.bound and "Bound: vendor only."
                    or ns.Prices:VendorSold(st.id) and "Vendor goods: vendor it."
                    or auction and ("Listing brings only %s."):format(ns.Gold(auction))
                    or "No auction price."
            end
            st.vendor, st.auction, st.how, st.cash, st.reason = vendor, auction, how, cash, reason
            rows[#rows + 1] = st
            if not st.bank then
                now = now + vendor
                best = best + (how == "vendor" and vendor or 0)
                soon = soon + (how == "auction" and auction or 0)
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.bank ~= b.bank then return not a.bank end
        if a.cash ~= b.cash then return a.cash > b.cash end
        return a.id < b.id
    end)
    return { rows = rows, now = now, best = best, soon = soon }
end

-- Invested share per day, for the chart.
function Invest:Record()
    local st = self:Status()
    if st.worth <= 0 then return end
    local key = ns.CharKey()
    local t = ns.db.invested[key]
    if not t then t = {}; ns.db.invested[key] = t end
    t[ns.Today()] = math.floor(st.pct * 1000 + 0.5) / 10
end

function Invest:History(days)
    local t = ns.db.invested[ns.CharKey()] or {}
    local values, labels, prev = {}, {}, nil
    local today = ns.Today()
    for day = today - (days or 60) + 1, today do
        if t[day] then prev = t[day] end
        if prev then values[#values + 1] = prev; labels[#labels + 1] = day end
    end
    return values, labels
end

-- ---------------------------------------------------------------------------
-- Opportunities: ways to turn gold (or goods) into more gold, from everything Wealth Planner
-- has gathered. Each is { kind, id, title, detail, cost (copper to spend), profit (expected,
-- after the cut), affordable, buy = { { id, qty, maxUnit } } (auction purchases, for Quartermaster's Cart) }.
--   craft    a recipe you know whose product sells for more than its reagents cost (bought at
--            the cheaper of the auction house and a vendor), as many as the market takes a day
--   convert  goods you already hold that a recipe turns into more than they'd sell for
--   buy      listed under a vendor's price, or well under its 30-day normal (buy signals)
--   timing   at its daily low now, and it reliably sells higher at another hour or day
--   gap      the cheapest listings sit well under the next price with stock behind it: buy, relist
-- Sorted by expected profit; ones you can afford from your free cash first.
-- ---------------------------------------------------------------------------

local TIMING_EDGE = 0.15 -- a pattern buy needs its best window this much (15%) over now
local MIN_PROFIT = 200   -- opportunities earning less than this (2 silver) aren't shown
local MIN_RETURN = 0.05  -- nor ones earning less than this (5%) on what they cost
local GAP_EDGE = 0.2     -- a listing gap: the cheap ones at least this much (20%) under the next price
local GAP_BEHIND = 3     -- ... with at least this many listed at that price and the two after it
local GAP_TIERS = 6      -- ... buying through at most this many price levels
local GAP_CAP = 1.2      -- ... and never relisting over this times the 30-day average
local PLAN_SHARE = 0.3   -- the plan never puts more than this (30%) of your cash to spend on one idea

-- What buying from the real listings comes to: units bought cheapest first while each one still
-- pays (worth(price) > price), up to `budget` copper and `maxQty` units (when given). Returns qty,
-- cost, profit, the tiers used ({ { price, qty } }), or nil when the listings haven't been read lately.
local function FromDepth(id, budget, worth, maxQty)
    local tiers = ns.Prices:Depth(id)
    if not tiers then return nil end
    local qty, cost, profit, used = 0, 0, 0, {}
    for _, t in ipairs(tiers) do
        local price, n = t[1], t[2]
        local gain = worth(price) - price
        if gain <= 0 then break end
        local afford = math.floor((budget - cost) / price)
        local take = math.min(n, afford, (maxQty or math.huge) - qty)
        if take < 1 then break end
        qty, cost, profit = qty + take, cost + take * price, profit + take * gain
        used[#used + 1] = { price, take }
        if take < n then break end
    end
    return qty, cost, profit, used
end

local function Tiers(used)
    local parts = {}
    for i, u in ipairs(used) do
        if i > 3 then parts[#parts + 1] = "..."; break end
        parts[#parts + 1] = ("%d at %s"):format(u[2], ns.Gold(u[1]))
    end
    return table.concat(parts, ", ")
end

function Invest:Opportunities()
    local st = self:Status()
    local free = math.max(0, st.cash - st.reserve)
    local perItem = math.max(1, (Opt().maxPerItem or 20) / 100 * math.max(st.worth, 1))
    local out, seen = {}, {}
    local function Name(id) return C.GetItemInfo(id) or ("item " .. id) end

    -- Crafts from scratch (recipes you know).
    if ns.Crafting then
        for _, j in ipairs(ns.Crafting:Jobs()) do
            if j.reqMet and not j.learnable and j.costEach > 0 then
                local crafts = math.max(1, math.min(j.crafts, math.floor(perItem / j.costEach)))
                local parts, buy = {}, {}
                for _, r in ipairs(j.reagents) do
                    parts[#parts + 1] = ("%d %s (%s)"):format(r.count * crafts, Name(r.item), r.from == "vendor" and "vendor" or "auction")
                    if r.from ~= "vendor" then buy[#buy + 1] = { id = r.item, qty = r.count * crafts } end
                end
                local made = math.floor(crafts * (j.made or 1) + 0.5)
                out[#out + 1] = {
                    kind = "craft", id = j.product, cost = j.costEach * crafts, profit = j.profitEach * crafts,
                    title = ("Craft %d %s"):format(made, Name(j.product)),
                    detail = ("Buy %s; sells at %s each."):format(table.concat(parts, ", "), ns.Gold(j.priceEach)),
                    each = j.profitEach, buy = buy, units = crafts,
                }
                seen["craft:" .. j.product] = true
            end
        end
    end

    -- Conversions from what you hold.
    if ns.Conversions then
        for _, c in ipairs(ns.Conversions:Crafts()) do
            local bought = 0
            for _, u in ipairs(c.uses) do bought = bought + (u.bought or 0) * (u.buy or 0) end
            out[#out + 1] = {
                kind = "convert", id = c.product, cost = bought, profit = c.gain,
                title = c.text:match("^(Craft %d+ .-) from ") or c.text,
                detail = (c.text:gsub("^Craft %d+ .- from ", "From your bags: ")) .. ".",
                each = c.each, buy = {},
            }
        end
    end

    -- Recoveries: crashed on a flood of listings, and now climbing back as the flood sells
    -- (Recovery.lua). Bought as the bounce starts, sold at half the climb still to go; capped at
    -- what the market takes, like the buys below.
    -- Beta Crash Monitoring: in the beta's last day nothing is bought to resell (it may not sell in
    -- time); only buys under a vendor's price, which sell to any vendor at once.
    local closing = (ns.BetaDaysLeft() or math.huge) < 1
    local recovering = {}
    if ns.Recovery and not closing then
        for _, x in ipairs(ns.Recovery:All()) do
            local rec, s = x.r, ns.Analytics:Stats(x.id)
            if rec.status == "recovering" and s and not ns.Prices:VendorSold(x.id) then
                recovering[x.id] = true
                local sellAt = rec.target
                local detail = rec.why .. (" Sell near %s."):format(ns.Gold(sellAt))
                local qty, cost, profit, used = FromDepth(x.id, perItem, function() return sellAt * (1 - AH_CUT) end, DemandCap(s))
                if qty and qty >= 1 then
                    out[#out + 1] = {
                        kind = "recovery", id = x.id, cost = cost, profit = profit, known = true,
                        explain = { kind = "recovery", id = x.id },
                        title = ("Buy %d %s at %s (recovering)"):format(qty, Name(x.id), ns.Gold(used[#used][1])),
                        detail = Tiers(used) .. ". " .. detail,
                        each = profit / qty, buy = { { id = x.id, qty = qty, maxUnit = used[#used][1] } }, units = qty,
                    }
                elseif not qty and sellAt * (1 - AH_CUT) > rec.now then
                    out[#out + 1] = {
                        kind = "recovery", id = x.id, cost = rec.now, profit = sellAt * (1 - AH_CUT) - rec.now, unknown = true,
                        explain = { kind = "recovery", id = x.id },
                        title = ("Buy %s from %s (recovering)"):format(Name(x.id), ns.Gold(rec.now)),
                        detail = "How many at this price isn't known yet (checking its listings). " .. detail,
                        each = sellAt * (1 - AH_CUT) - rec.now, buy = {},
                    }
                end
            end
        end
    end

    -- Buys: under a vendor's price, or a buy signal. How many comes from the item's real listings
    -- (Prices:Depth): only the units still worth buying at their own price. Without a recent
    -- reading of them, the count is unknown and says so (the Invest tab asks for them).
    for _, r in ipairs(ns.Analytics:All()) do
        local s = r.s
        local asRecovery = recovering[r.id] and not (s.vendor and s.price < s.vendor * 0.95) -- bought above instead
        if s.signal == "buy" and s.confidence >= 0.5 and s.flip and s.flip > 0 and not ns.Prices:VendorSold(r.id) and not asRecovery then
            local underVendor = s.vendor and s.price < s.vendor * 0.95
            local worth = underVendor and function() return s.vendor end
                or function() return s.target * (1 - AH_CUT) end
            local why = underVendor and ("Under its vendor price: sell them to a vendor for %s each."):format(ns.Gold(s.vendor))
                or (s.reason .. (" Relist near %s."):format(ns.Gold(s.target)))
            -- Under a vendor's price sells to any vendor, whatever the market takes.
            local qty, cost, profit, used = FromDepth(r.id, perItem, worth, not underVendor and DemandCap(s) or nil)
            if qty and qty >= 1 then
                out[#out + 1] = {
                    kind = "buy", id = r.id, cost = cost, profit = profit, known = true,
                    explain = not underVendor and { kind = "revert", id = r.id } or nil,
                    title = #used == 1 and ("Buy %d %s at %s"):format(qty, Name(r.id), ns.Gold(used[1][1]))
                        or ("Buy %d %s at %s-%s"):format(qty, Name(r.id), ns.Gold(used[1][1]), ns.Gold(used[#used][1])),
                    detail = ("%s listed at a price worth buying. %s"):format(Tiers(used), why),
                    each = profit / qty, buy = { { id = r.id, qty = qty, maxUnit = used[#used][1] } }, units = qty,
                }
            elseif not qty then
                out[#out + 1] = {
                    kind = "buy", id = r.id, cost = s.price, profit = s.flip, unknown = true,
                    explain = not underVendor and { kind = "revert", id = r.id } or nil,
                    title = ("Buy %s from %s"):format(Name(r.id), ns.Gold(s.price)),
                    detail = ("How many at that price isn't known yet (checking its listings). %s"):format(why),
                    each = s.flip, buy = {},
                }
            end
        end
    end

    -- Timing: cheap at this hour, reliably dearer at another.
    if ns.Patterns and not closing then
        for _, r in ipairs(ns.Analytics:All()) do
            local pat = not ns.Prices:VendorSold(r.id) and ns.Patterns:Item(r.id)
            local s = r.s
            if pat and pat.ready and pat.best and pat.nowRatio and pat.worst
                and pat.nowRatio <= pat.worst.ratio * 1.03 and pat.best.ratio / pat.nowRatio - 1 >= TIMING_EDGE then
                local sellAt = s.price * pat.best.ratio / pat.nowRatio
                local when = (pat.bestDay and (pat.bestDay.text .. " ") or "") .. pat.best.text
                local why = ("It's at its daily low now; %s it usually sells about %d%% higher (%s each)."):format(
                    when, (pat.best.ratio / pat.nowRatio - 1) * 100, ns.Gold(sellAt))
                local qty, cost, profit, used = FromDepth(r.id, perItem, function() return sellAt * (1 - AH_CUT) end, DemandCap(s))
                if qty and qty >= 1 then
                    out[#out + 1] = {
                        kind = "timing", id = r.id, cost = cost, profit = profit, known = true,
                        explain = { kind = "timing", id = r.id, sellAt = sellAt },
                        title = ("Buy %d %s now, sell %s"):format(qty, Name(r.id), when),
                        detail = Tiers(used) .. ". " .. why,
                        each = profit / qty, buy = { { id = r.id, qty = qty, maxUnit = used[#used][1] } }, units = qty,
                    }
                elseif not qty and sellAt * (1 - AH_CUT) > s.price then
                    out[#out + 1] = {
                        kind = "timing", id = r.id, cost = s.price, profit = sellAt * (1 - AH_CUT) - s.price, unknown = true,
                        explain = { kind = "timing", id = r.id, sellAt = sellAt },
                        title = ("Buy %s now, sell %s"):format(Name(r.id), when),
                        detail = "How many at this price isn't known yet (checking its listings). " .. why,
                        each = sellAt * (1 - AH_CUT) - s.price, buy = {},
                    }
                end
            end
        end
    end

    -- Gaps: the cheapest listings sit well under the next price that has real stock behind it, so
    -- buying them and relisting just under that price pays now, with no history needed. Read from
    -- the item's listings (Prices:Depth). Never over GAP_CAP times its 30-day average, when known.
    local suggested = {}
    for _, o in ipairs(out) do if o.kind == "buy" or o.kind == "timing" or o.kind == "recovery" then suggested[o.id] = true end end
    for id in pairs(ns.Prices.Items()) do
        -- Not while it's crashed and not recovering: the stock "behind" gets undercut in a crash.
        local rec = ns.Recovery and ns.Recovery:Check(id)
        local crashed = rec and (rec.status == "watching" or rec.status == "held")
        local tiers = not closing and not suggested[id] and not crashed and not ns.Prices:VendorSold(id) and ns.Prices:Depth(id)
        if tiers and #tiers >= 2 then
            local s = ns.Analytics:Stats(id)
            local listed = 0
            for _, t in ipairs(tiers) do listed = listed + t[2] end
            local best
            for j = 1, math.min(#tiers - 1, GAP_TIERS) do
                local behind = 0
                for k = j + 1, math.min(#tiers, j + 3) do behind = behind + tiers[k][2] end
                local relist = tiers[j + 1][1] - 1
                if s and s.ma30 then relist = math.min(relist, math.floor(s.ma30 * GAP_CAP)) end
                if behind >= GAP_BEHIND and tiers[j][1] <= tiers[j + 1][1] * (1 - GAP_EDGE) then
                    local qty, cost, profit = 0, 0, 0
                    local maxQty = math.max(1, math.floor(listed * MAX_SHARE_OF_LISTED))
                    for k = 1, j do
                        local price = tiers[k][1]
                        local gain = relist * (1 - AH_CUT) - price
                        if gain <= 0 then break end
                        local take = math.min(tiers[k][2], maxQty - qty, math.floor((perItem - cost) / price))
                        if take < 1 then break end
                        qty, cost, profit = qty + take, cost + take * price, profit + take * gain
                    end
                    if qty >= 1 and (not best or profit > best.profit) then
                        best = { qty = qty, cost = cost, profit = profit, relist = relist, low = tiers[1][1], high = tiers[j][1],
                            next = tiers[j + 1][1], behind = behind }
                    end
                end
            end
            if best then
                local at = best.low == best.high and ns.Gold(best.low) or (ns.Gold(best.low) .. "-" .. ns.Gold(best.high))
                out[#out + 1] = {
                    kind = "gap", id = id, cost = best.cost, profit = math.floor(best.profit), known = true,
                    explain = { kind = "gap", id = id, qty = best.qty, low = best.low, high = best.high, relist = best.relist,
                        next = best.next, behind = best.behind },
                    title = ("Buy %d %s at %s, relist at %s"):format(best.qty, Name(id), at, ns.Gold(best.relist)),
                    detail = ("%d listed under %s, the next price with stock behind it."):format(best.qty, ns.Gold(best.relist + 1)),
                    each = best.profit / best.qty, buy = { { id = id, qty = best.qty, maxUnit = best.high } }, units = best.qty,
                }
            end
        end
    end

    -- Too small to bother with: it must earn 2 silver or 5% of what it costs, whichever is more. A count not known yet
    -- has per-unit figures, so only the 5% test applies to it until its listings are read.
    local kept = {}
    for _, o in ipairs(out) do
        local tiny = (not o.unknown and o.profit < MIN_PROFIT) or (o.cost > 0 and o.profit / o.cost < MIN_RETURN)
        if not tiny then kept[#kept + 1] = o end
    end
    out = kept
    for _, o in ipairs(out) do o.affordable = o.cost <= free end
    table.sort(out, function(a, b)
        if (a.unknown or false) ~= (b.unknown or false) then return not a.unknown end
        if a.affordable ~= b.affordable then return a.affordable end
        if a.profit ~= b.profit then return a.profit > b.profit end
        return (a.id or 0) < (b.id or 0)
    end)
    return out, free
end


-- The plan: how to spread your cash to spend over the opportunities, so no one idea risks more
-- than PLAN_SHARE of it. Best return on what it costs first; an idea that costs more than its
-- share is scaled down (fewer crafts or units, cheapest listings first) rather than dropped, and
-- dropped when what's left earns under 2 silver or 5% of its cost, whichever is more. Counts not known yet stay out until
-- their listings are read. Returns { { op, units, cost, profit, buy = { { id, qty, maxUnit } } } },
-- what it spends and its expected profit.
function Invest:Plan(opps, free)
    local cap = free * PLAN_SHARE
    local ideas = {}
    for _, op in ipairs(opps) do
        if not op.unknown and op.profit > 0 then ideas[#ideas + 1] = op end
    end
    table.sort(ideas, function(a, b)
        local ra = a.cost > 0 and a.profit / a.cost or math.huge
        local rb = b.cost > 0 and b.profit / b.cost or math.huge
        if ra ~= rb then return ra > rb end
        return a.profit > b.profit
    end)
    local plan, left, spend, gain = {}, free, 0, 0
    for _, op in ipairs(ideas) do
        local room = math.min(cap, left)
        local units, cost, profit = op.units, op.cost, op.profit
        if cost > room then
            -- Too big for its share: scale it down if it comes in units, else leave it out.
            local n = op.units and op.units > 0 and math.floor(op.units * room / cost) or 0
            if n >= 1 then
                units, cost, profit = n, cost * n / op.units, profit * n / op.units
            else
                units = nil
            end
        end
        -- Worth it only when it earns 2 silver or 5% of what it costs, whichever is more.
        if (units or op.cost <= room) and profit >= math.max(MIN_PROFIT, cost * MIN_RETURN) then
            local buy = {}
            for _, b in ipairs(op.buy or {}) do
                local qty = units and op.units and op.units > 0 and math.ceil(b.qty * units / op.units) or b.qty
                if qty >= 1 then buy[#buy + 1] = { id = b.id, qty = qty, maxUnit = b.maxUnit } end
            end
            plan[#plan + 1] = { op = op, units = units, cost = math.floor(cost), profit = math.floor(profit), buy = buy,
                scaled = units ~= op.units }
            left, spend, gain = left - cost, spend + cost, gain + profit
        end
    end
    return plan, math.floor(spend), math.floor(gain)
end

-- The most days of price history any item has (signals need 3, full confidence takes 7).
function Invest:HistoryDays()
    local most = 0
    for _, e in pairs(ns.Prices.Items()) do
        local n = 0
        for _ in pairs(e.d) do n = n + 1 end
        if n > most then most = n end
    end
    return most
end

-- Items worth reading the listings of for gaps: the most listed ones, vendor goods left out.
function Invest:DepthWanted(n)
    local rows = {}
    for _, r in ipairs(ns.Analytics:All()) do
        if (r.s.supply or 0) >= GAP_BEHIND + 1 and not ns.Prices:VendorSold(r.id) and not ns.Prices:Depth(r.id) then
            rows[#rows + 1] = r
        end
    end
    table.sort(rows, function(a, b)
        if a.s.supply ~= b.s.supply then return a.s.supply > b.s.supply end
        return a.id < b.id
    end)
    local ids = {}
    for i = 1, math.min(n, #rows) do ids[i] = rows[i].id end
    return ids
end

-- Opens an item at the auction house to buy it: in Quartermaster's Buying tab when Quartermaster is
-- installed, else in the auction house's own Buy tab (straight to the item's listings when the
-- client allows, else a search for its name). Returns true when it opened.
function Invest:OpenAtAuction(id)
    if not id then return false end
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
        ns:Print("Open the auction house first.", true)
        return false
    end
    local name = C.GetItemInfo(id)
    if not name then C.RequestItem(id, true); ns:Print("That item isn't loaded yet; click again in a moment.", true); return false end
    if QuartermasterAPI and QuartermasterAPI.SearchAuction and QuartermasterAPI.SearchAuction(name) then return true end
    -- The auction house's own Buy tab.
    if AuctionHouseFrameBuyTab and AuctionHouseFrameBuyTab.Click then AuctionHouseFrameBuyTab:Click() end
    local key = C_AuctionHouse and C_AuctionHouse.MakeItemKey and C_AuctionHouse.MakeItemKey(id)
    if key and AuctionHouseFrame.SelectBrowseResult and pcall(AuctionHouseFrame.SelectBrowseResult, AuctionHouseFrame, { itemKey = key }) then
        return true
    end
    local bar = AuctionHouseFrame.SearchBar
    if bar and bar.SetSearchText and bar.StartSearch then
        pcall(bar.SetSearchText, bar, name)
        pcall(bar.StartSearch, bar)
        return true
    end
    ns:Print("Couldn't open " .. name .. " at the auction house.", true)
    return false
end

-- Sends the plan's buys to Quartermaster as a new shopping list ("Wealth Planner 10/17 14:05"),
-- each capped at the most it still pays to buy at, and opens it on the Cart tab to review before
-- buying. The plan itself is kept (ns.db.sentPlans, the last SENT_KEPT) so its ideas and what each
-- is for can be looked at later. picks = { { id, qty, maxUnit } }; plan from Invest:Plan.
local SENT_KEPT = 30
function Invest:ToQuartermaster(picks, plan, spend, gain)
    if not (QuartermasterAPI and QuartermasterAPI.NewShoppingList) then
        return ns:Print("Quartermaster isn't loaded, so there's no Cart to send to.", true)
    end
    if #picks == 0 then return ns:Print("Nothing to send yet.", true) end
    local ok, n, name = pcall(QuartermasterAPI.NewShoppingList, "Wealth Planner " .. date("%m/%d %H:%M"), picks)
    if not ok then return ns:Print("Quartermaster didn't take the list: " .. tostring(n), true) end
    local ideas = {}
    for _, p in ipairs(plan or {}) do
        local op = p.op
        ideas[#ideas + 1] = {
            kind = op.kind, id = op.id, title = op.title, detail = op.detail,
            cost = p.cost, profit = p.profit, units = p.units, of = op.units, scaled = p.scaled,
            buy = p.buy,
        }
    end
    table.insert(ns.db.sentPlans, 1, { t = time(), list = name, spend = spend or 0, gain = gain or 0, ideas = ideas })
    while #ns.db.sentPlans > SENT_KEPT do table.remove(ns.db.sentPlans) end
    ns:Print(("Sent %d item%s to Quartermaster as \"%s\": review it on the Cart tab before buying."):format(n or 0, n == 1 and "" or "s", name or "?"))
    ns:Changed()
end

function Invest:ForgetSent(entry)
    for i, e in ipairs(ns.db.sentPlans) do
        if e == entry then table.remove(ns.db.sentPlans, i) break end
    end
    ns:Changed()
end

ns:On("PLAYER_MONEY", function() if ns.db then Invest:Record() end end)
ns:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(5, function() if ns.db then Invest:Record() end end) end)
