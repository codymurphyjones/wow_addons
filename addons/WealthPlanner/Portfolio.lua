local _, ns = ...
local C = ns.Compat

-- Your holdings, treated like a portfolio:
-- * Holdings: what's in each character's bags and bank, valued at market price.
-- * Cost basis: "lots" of what you paid, oldest first. Auction house purchases add a lot at their
--   price; goods looted on a job add a lot at zero cost (Session.lua).
-- * Realized profit: auction sales read from the mailbox invoices, matched against the oldest lots.
-- * Net worth: gold plus holdings value, recorded once a day per character.
local P = {}
ns.Portfolio = P

local AH_CUT = 0.05
local PENDING_SECONDS = 30
local MAIL_DAYS = 30

-- ---------------------------------------------------------------------------
-- Holdings
-- ---------------------------------------------------------------------------

local function Mine()
    local key = ns.CharKey()
    local h = ns.db.holdings[key]
    if not h then h = { bags = {}, bank = {} }; ns.db.holdings[key] = h end
    return h
end

-- Counts by item ID, and how many slots could be read (0: the containers aren't readable now).
local function Count(which)
    local out, slots = {}, 0
    for _, bag in ipairs(C.BagList(which)) do slots = slots + C.GetNumSlots(bag) end
    for _, _, info in C.IterateBags(C.BagList(which)) do
        local id = info.id or C.IDFromLink(info.link)
        if id then out[id] = (out[id] or 0) + (info.count or 1) end
    end
    return out, slots
end

local bagsPending
local function ScanBags()
    bagsPending = false
    Mine().bags = Count("bags")
    P:RecordWorth()
    ns:Changed()
end

-- The bank is counted whenever it's open and something moves (its own slots, its bags, or items
-- going between it and your bags), so what you take out stops counting as in the bank. A reading
-- with no slots (the bank already closed) is ignored rather than wiping what was counted.
local bankOpen, bankError = false, false
local function ScanBank()
    if not bankOpen then return end
    local ok, counts, slots = pcall(Count, "bank")
    if not ok then
        if not bankError then bankError = true; ns:Print("Couldn't read your bank: " .. tostring(counts), true) end
        return
    end
    if slots == 0 then return end
    local h = Mine()
    h.bank, h.bankSeen = counts, time()
    ns:Changed()
end
P.BankSeen = function() local h = ns.db.holdings[ns.CharKey()]; return h and h.bankSeen end
local function BankOpened() bankOpen = true; ScanBank(); C_Timer.After(1, ScanBank) end
local function BankClosed() bankOpen = false; P:TrimLots() end

-- What one of an item is worth: its auction price, but never more than a vendor charges for it
-- (an auction price over that is a markup few pay), else what a vendor pays you.
local function Worth(id, unit)
    local buy = ns.Prices:VendorBuy(id)
    if unit and buy and buy < unit then return buy end
    return unit
end
P.Worth = function(_, id, unit) return Worth(id, unit) end

function P:Value(id)
    return Worth(id, ns.Prices:Price(id)) or ns.Prices:Vendor(id)
end

-- This character's holdings: { { id, qty, unit, value, cost, pnl, bags, bank } }, most valuable first.
function P:Holdings(charKey)
    local h = ns.db.holdings[charKey or ns.CharKey()]
    if not h then return {}, 0 end
    local qty = {}
    for id, n in pairs(h.bags or {}) do qty[id] = (qty[id] or 0) + n end
    for id, n in pairs(h.bank or {}) do qty[id] = (qty[id] or 0) + n end
    local rows, total = {}, 0
    for id, n in pairs(qty) do
        local unit = Worth(id, ns.Prices:Price(id))
        if unit then
            local cost, covered = self:CostOf(id, n)
            local value = unit * n
            rows[#rows + 1] = {
                id = id, qty = n, unit = unit, value = value, bags = h.bags[id] or 0, bank = h.bank[id] or 0,
                cost = covered > 0 and cost or nil,
                pnl = covered > 0 and (unit * covered * (1 - AH_CUT) - cost) or nil,
            }
            total = total + value
        end
    end
    table.sort(rows, function(a, b) return a.value > b.value end)
    return rows, total
end

-- Everything you own: cash, goods (bags and bank) and your auctions on the market.
function P:NetWorth()
    local _, holdings = self:Holdings()
    local auctions = ns.Invest and ns.Invest:Auctions() or 0
    return (GetMoney() or 0) + holdings + auctions
end

-- Goods bought at the auction house still waiting in the mail, valued at market.
local function MailGoods()
    local total = 0
    for id, n in pairs(ns.char.inMail or {}) do
        total = total + (Worth(id, ns.Prices:Price(id)) or ns.Prices:Vendor(id) or 0) * n
    end
    return total
end

local LOG_GAP = 15 * 60  -- intraday snapshots at most every 15 minutes
local LOG_KEEP = 96      -- a day's worth of them

-- Records this character's net worth: one figure a day (worth), the breakdown (wealth), and
-- intraday snapshots (worthLog) for the day's ups and downs.
function P:RecordWorth()
    local key = ns.CharKey()
    local t = ns.db.worth[key]
    if not t then t = {}; ns.db.worth[key] = t end
    local cash = GetMoney() or 0
    local _, goods = self:Holdings()
    local auctions = ns.Invest and ns.Invest:Auctions() or 0
    local mail = MailGoods()
    local total = cash + goods + auctions + mail
    t[ns.Today()] = total
    ns.db.wealth[key] = { t = time(), cash = cash, goods = goods, auctions = auctions, mail = mail, total = total }
    local log = ns.db.worthLog[key]
    if not log then log = {}; ns.db.worthLog[key] = log end
    local last = log[#log]
    if last and time() - last[1] < LOG_GAP then
        last[2] = total
    else
        log[#log + 1] = { time(), total }
        while #log > LOG_KEEP do table.remove(log, 1) end
    end
end

-- Your characters on this realm: { { key, name, cash, goods, auctions, mail, total, t } }, richest first.
function P:Characters()
    local realm = "-" .. (GetRealmName() or "?")
    local out = {}
    for key, w in pairs(ns.db.wealth) do
        if key:sub(-#realm) == realm then
            out[#out + 1] = { key = key, name = key:sub(1, -#realm - 1), cash = w.cash or 0, goods = w.goods or 0,
                auctions = w.auctions or 0, mail = w.mail or 0, total = w.total or 0, t = w.t }
        end
    end
    table.sort(out, function(a, b) return a.total > b.total end)
    return out
end

-- Everything your characters on this realm own: { cash, goods, auctions, mail, total, chars }.
function P:Account()
    local a = { cash = 0, goods = 0, auctions = 0, mail = 0, total = 0, chars = 0 }
    for _, c in ipairs(self:Characters()) do
        a.cash, a.goods, a.auctions = a.cash + c.cash, a.goods + c.goods, a.auctions + c.auctions
        a.mail, a.total, a.chars = a.mail + c.mail, a.total + c.total, a.chars + 1
    end
    return a
end

-- The account's net worth by day (each character's last known figure carried forward), oldest
-- first: values, days.
function P:AccountHistory(days)
    local realm = "-" .. (GetRealmName() or "?")
    local today = ns.Today()
    local values, labels, carry = {}, {}, {}
    for day = today - (days or 30) + 1, today do
        local sum, any = 0, false
        for key, t in pairs(ns.db.worth) do
            if key:sub(-#realm) == realm then
                if t[day] then carry[key] = t[day] end
                if carry[key] then sum, any = sum + carry[key], true end
            end
        end
        if any then values[#values + 1] = sum; labels[#labels + 1] = day end
    end
    return values, labels
end

-- How the account's worth moved: { today, week, month } in copper (nil when there's no history that far back).
function P:Changes()
    local values = self:AccountHistory(31)
    local n = #values
    local function Back(k) return n > k and values[n] - values[n - k] or nil end
    return { today = Back(1), week = Back(7), month = Back(30) }
end

-- This character's intraday snapshots: values, times.
function P:Today()
    local log = ns.db.worthLog[ns.CharKey()] or {}
    local values, times = {}, {}
    local since = time() - 86400
    for _, s in ipairs(log) do
        if s[1] >= since then values[#values + 1] = s[2]; times[#times + 1] = s[1] end
    end
    return values, times
end

-- Profit you'd lock in selling what you hold now (market value after the cut, less what it cost),
-- for goods whose cost is known; and the market value of goods that cost you nothing (farmed).
function P:Unrealized()
    local pnl, free = 0, 0
    for _, r in ipairs(self:Holdings()) do
        if r.pnl then pnl = pnl + r.pnl else free = free + r.value end
    end
    return pnl, free
end

-- Net worth by day for this character, oldest first: values, days.
function P:WorthHistory(days)
    local t = ns.db.worth[ns.CharKey()] or {}
    local values, labels, prev = {}, {}, nil
    local today = ns.Today()
    for day = today - (days or 30) + 1, today do
        if t[day] then prev = t[day] end
        if prev then values[#values + 1] = prev; labels[#labels + 1] = day end
    end
    return values, labels
end

-- ---------------------------------------------------------------------------
-- Cost basis (lots, oldest first)
-- ---------------------------------------------------------------------------

function P:AddLot(id, qty, unitCost, src)
    if not (id and qty and qty > 0) then return end
    local lots = ns.db.lots[id]
    if not lots then lots = {}; ns.db.lots[id] = lots end
    local last = lots[#lots]
    if src == "farm" and last and last.src == "farm" and time() - last.t < 86400 then
        last.qty = last.qty + qty
        return
    end
    lots[#lots + 1] = { qty = qty, cost = unitCost or 0, t = time(), src = src or "ah" }
end

-- An item ID from its name: the game's cache, else any item Wealth Planner already knows.
function P:IDByName(name)
    if not name then return nil end
    local id = C.GetItemInfoInstant(name)
    if id then return id end
    local key = name:lower()
    local function Match(i) local n = C.GetItemInfo(i); return n and n:lower() == key end
    for i in pairs(ns.db.lots) do if Match(i) then return i end end
    for i in pairs(ns.db.watch) do if Match(i) then return i end end
    for _, h in pairs(ns.db.holdings) do
        for i in pairs(h.bags or {}) do if Match(i) then return i end end
        for i in pairs(h.bank or {}) do if Match(i) then return i end end
    end
end

-- What the oldest `qty` items cost you, and how many of them have a known cost.
function P:CostOf(id, qty)
    local cost, covered = 0, 0
    for _, lot in ipairs(ns.db.lots[id] or {}) do
        local n = math.min(lot.qty, qty - covered)
        cost, covered = cost + n * lot.cost, covered + n
        if covered >= qty then break end
    end
    return cost, covered
end

-- Takes `qty` items off the oldest lots; returns their total cost and how many had a lot.
local function Consume(id, qty)
    local lots = ns.db.lots[id]
    local cost, covered = 0, 0
    while lots and lots[1] and covered < qty do
        local lot = lots[1]
        local n = math.min(lot.qty, qty - covered)
        cost, covered = cost + n * lot.cost, covered + n
        lot.qty = lot.qty - n
        if lot.qty <= 0 then table.remove(lots, 1) end
    end
    if lots and not lots[1] then ns.db.lots[id] = nil end
    return cost, covered
end

-- Lots for items you no longer have anywhere (used, vendored, mailed away) are dropped, so the cost
-- basis follows what you hold.
function P:TrimLots()
    local have = {}
    for _, h in pairs(ns.db.holdings) do
        for id, n in pairs(h.bags or {}) do have[id] = (have[id] or 0) + n end
        for id, n in pairs(h.bank or {}) do have[id] = (have[id] or 0) + n end
    end
    -- Items on the auction house are still yours until the sale comes in by mail.
    if WallyAPI and WallyAPI.AuctionsOnMarket then
        for _, a in ipairs((WallyAPI.AuctionsOnMarket())) do
            local id = (a.link and C.IDFromLink(a.link)) or P:IDByName(a.key)
            if id then have[id] = (have[id] or 0) + (a.quantity or 1) end
        end
    end
    -- Purchases arrive by mail: until the mailbox has been read since, they count as on their way.
    local inMail, readAt = ns.char.inMail or {}, ns.char.mailReadAt or 0
    for id, lots in pairs(ns.db.lots) do
        local total, onTheWay = 0, 0
        for _, lot in ipairs(lots) do
            total = total + lot.qty
            if lot.src == "ah" and lot.t > readAt then onTheWay = onTheWay + lot.qty end
        end
        local extra = total - (have[id] or 0) - (inMail[id] or 0) - onTheWay
        if extra > 0 then Consume(id, extra) end
    end
end

-- ---------------------------------------------------------------------------
-- Auction house purchases
-- ---------------------------------------------------------------------------

local pending = {} -- { id, qty, total, t, auctionID }
local lastItemKey

local function PendingAdd(p)
    p.t = GetTime()
    pending[#pending + 1] = p
end

local function Confirm(match)
    local now = GetTime()
    for i = #pending, 1, -1 do
        if now - pending[i].t > PENDING_SECONDS then table.remove(pending, i) end
    end
    for i, p in ipairs(pending) do
        if match(p) then
            table.remove(pending, i)
            if p.qty and p.qty > 0 and p.total then
                P:AddLot(p.id, p.qty, p.total / p.qty, "ah")
                ns:Changed()
            end
            return
        end
    end
end

-- The auction behind an auction ID, from the item search being looked at.
local function ItemAuction(auctionID)
    if not (lastItemKey and C_AuctionHouse.GetNumItemSearchResults) then return nil end
    for i = 1, C_AuctionHouse.GetNumItemSearchResults(lastItemKey) or 0 do
        local r = C_AuctionHouse.GetItemSearchResultInfo(lastItemKey, i)
        if r and r.auctionID == auctionID then return r end
    end
end

local function HookPurchases()
    local AH = C_AuctionHouse
    if not AH then return end
    if AH.SendSearchQuery then
        hooksecurefunc(AH, "SendSearchQuery", function(itemKey) lastItemKey = itemKey end)
    end
    if AH.PlaceBid then
        hooksecurefunc(AH, "PlaceBid", function(auctionID, bidAmount)
            local ok, r = pcall(ItemAuction, auctionID)
            local id = ok and r and r.itemKey and r.itemKey.itemID or (lastItemKey and lastItemKey.itemID)
            if not id then return end
            -- Only buyouts become yours right away; a plain bid may still be outbid.
            if ok and r and r.buyoutAmount and bidAmount < r.buyoutAmount then return end
            -- A row's quantity is how many identical auctions it groups; a bid buys one of them.
            PendingAdd({ id = id, qty = 1, total = bidAmount, auctionID = auctionID })
        end)
    end
    if AH.StartCommoditiesPurchase then
        hooksecurefunc(AH, "StartCommoditiesPurchase", function(itemID, quantity)
            PendingAdd({ id = itemID, qty = quantity, commodity = true })
        end)
    end
    ns:On("COMMODITY_PRICE_UPDATED", function(_, totalPrice)
        local p = pending[#pending]
        if p and p.commodity then p.total = totalPrice end
    end)
    ns:On("COMMODITY_PURCHASE_SUCCEEDED", function() Confirm(function(p) return p.commodity end) end)
    ns:On("AUCTION_HOUSE_PURCHASE_COMPLETED", function(auctionID)
        Confirm(function(p) return p.auctionID == auctionID end)
    end)
end

-- ---------------------------------------------------------------------------
-- Sales, from the mailbox
-- ---------------------------------------------------------------------------

-- "Auction expired: %s"
local EXPIRED_SUBJECT = type(AUCTION_EXPIRED_MAIL_SUBJECT) == "string"
    and ("^" .. AUCTION_EXPIRED_MAIL_SUBJECT:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%s", "(.+)") .. "$") or nil

local function SeenMail()
    if type(ns.char.seenMail) ~= "table" then ns.char.seenMail = {} end
    return ns.char.seenMail
end

local function ReadInvoices()
    if not (GetInboxNumItems and GetInboxInvoiceInfo and GetInboxHeaderInfo) then return end
    local seen = SeenMail()
    local now = time()
    for k, t in pairs(seen) do
        if now - t > (MAIL_DAYS + 2) * 86400 then seen[k] = nil end
    end
    local inMail = {}
    for i = 1, GetInboxNumItems() or 0 do
        local _, _, _, subject, money, _, daysLeft = GetInboxHeaderInfo(i)
        local invoiceType, itemName, _, bid, _, deposit, consignment = GetInboxInvoiceInfo(i)
        -- When the mail was sent (auction house mail lasts MAIL_DAYS): the sale (or expiry) time.
        local sentAt = math.floor(now - (MAIL_DAYS - (daysLeft or MAIL_DAYS)) * 86400)
        local expiredName = EXPIRED_SUBJECT and type(subject) == "string" and subject:match(EXPIRED_SUBJECT)
        if expiredName then
            local key = "expired:" .. expiredName .. ":" .. math.floor(sentAt / 7200)
            if not seen[key] then
                seen[key] = now
                if ns.Deposits then ns.Deposits:OnExpiredMail(expiredName, sentAt) end
            end
        end
        if invoiceType == "seller" and itemName and bid then
            -- Sent time, to the nearest two hours: mails can't be told apart otherwise.
            local sent = math.floor((now - (MAIL_DAYS - (daysLeft or MAIL_DAYS)) * 86400) / 7200)
            local key = table.concat({ itemName, bid, deposit or 0, consignment or 0, sent }, ":")
            if not seen[key] then
                seen[key] = now
                local qty = tonumber(subject and subject:match("%((%d+)%)%s*$")) or 1
                local id = P:IDByName(itemName)
                local cost, covered = 0, 0
                if id then cost, covered = Consume(id, qty) end
                table.insert(ns.db.ledger, 1, {
                    t = now, sold = sentAt, id = id, name = itemName, qty = qty, gross = bid, deposit = deposit or 0,
                    cut = consignment or 0, cost = covered > 0 and cost or nil, covered = covered,
                })
                if ns.Deposits then ns.Deposits:OnSoldMail(itemName, sentAt) end
                for j = #ns.db.ledger, 501, -1 do ns.db.ledger[j] = nil end
            end
        elseif invoiceType == "buyer" and itemName then
            local id = P:IDByName(itemName)
            local qty = tonumber(subject and subject:match("%((%d+)%)%s*$")) or 1
            if id then inMail[id] = (inMail[id] or 0) + qty end
        end
        local _ = money
    end
    ns.char.inMail, ns.char.mailReadAt = inMail, now
    ns:Changed()
end

-- Realized profit over the last `days` days: sales, auction house cut, cost of what was sold.
function P:Realized(days)
    local since = time() - (days or 30) * 86400
    local gross, cut, cost, n = 0, 0, 0, 0
    for _, s in ipairs(ns.db.ledger) do
        if s.t < since then break end
        gross, cut, cost, n = gross + s.gross, cut + (s.cut or 0), cost + (s.cost or 0), n + 1
    end
    return { gross = gross, cut = cut, cost = cost, profit = gross - cut - cost, sales = n }
end

-- Sell suggestions: holdings whose market signal says sell.
function P:SellNow()
    local out = {}
    for _, r in ipairs(self:Holdings()) do
        local s = ns.Analytics:Stats(r.id)
        if s and s.signal == "sell" and s.confidence >= 0.5 then out[#out + 1] = { row = r, s = s } end
    end
    return out
end

-- ---------------------------------------------------------------------------

ns:OnLoad(function()
    HookPurchases()
    ns:On("BAG_UPDATE_DELAYED", function()
        if bagsPending then return end
        bagsPending = true
        C_Timer.After(1, function() ScanBags(); ScanBank() end)
    end)
    ns:On("BANKFRAME_OPENED", BankOpened)
    ns:On("BANKFRAME_CLOSED", BankClosed)
    -- Newer clients open the bank through the interaction manager (the banker's type).
    local banker = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Banker
    if banker then
        ns:On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(kind) if kind == banker then BankOpened() end end)
        ns:On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(kind) if kind == banker then BankClosed() end end)
    end
    ns:On("PLAYERBANKSLOTS_CHANGED", ScanBank)
    ns:On("MAIL_INBOX_UPDATE", ReadInvoices)
    ns:On("PLAYER_MONEY", function() P:RecordWorth() end)
end)

ns:On("PLAYER_ENTERING_WORLD", function()
    C_Timer.After(3, function() ScanBags(); P:TrimLots() end)
end)
