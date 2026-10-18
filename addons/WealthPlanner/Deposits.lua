local _, ns = ...
local C = ns.Compat

-- Auction deposits: what each post cost, and what became of it. A deposit comes back when the
-- auction sells; it's lost when the auction expires or you cancel it. Every post you make (through
-- any addon or the Blizzard UI) is recorded in ns.db.deposits, newest first:
--   { t, id, name, qty, unit, duration, deposit, market (its price when posted),
--     state = "live" | "sold" | "expired" | "cancelled" | "unknown", resolved (time) }
-- Outcomes come from the chat ("A buyer has been found for your auction of ...", "... has
-- expired"), the auction house mail when you were away, and cancelling. When the deposits you lose
-- grow too large next to what your sales bring in, Advice() says what's wasting them.
local D = {}
ns.Deposits = D

local KEEP = 600            -- posts remembered
local MATCH_DAYS = 3        -- an outcome matches a post made at most this long before it
local GIVE_UP_DAYS = 7      -- a post nobody heard back about by then is "unknown"
local WASTE_RATIO = 0.05    -- lost deposits over 5% of sales: too much
local FAIL_RATE = 0.4       -- 40% of posts expiring or cancelled: too much
local DURATION_HOURS = { 12, 24, 48 }

local function List()
    ns.db.deposits = ns.db.deposits or {}
    return ns.db.deposits
end

local function Key(name) return name and name:lower() or nil end

-- ---------------------------------------------------------------------------
-- Posting
-- ---------------------------------------------------------------------------

local pendingMoney -- { post, money } waiting for PLAYER_MONEY to tell the deposit

local function Deposit(kind, location, duration, quantity)
    if not C_AuctionHouse then return nil end
    local ok, v
    if kind == "commodity" and C_AuctionHouse.CalculateCommodityDeposit then
        local id = C_Item and C_Item.GetItemID and select(2, pcall(C_Item.GetItemID, location))
        if id then ok, v = pcall(C_AuctionHouse.CalculateCommodityDeposit, id, duration, quantity) end
    elseif C_AuctionHouse.CalculateItemDeposit then
        ok, v = pcall(C_AuctionHouse.CalculateItemDeposit, location, duration, quantity)
    end
    return ok and type(v) == "number" and v or nil
end

local function LinkOf(location)
    if not (C_Item and C_Item.GetItemLink) then return nil end
    local ok, link = pcall(C_Item.GetItemLink, location)
    return ok and link or nil
end

local function OnPost(kind, location, duration, quantity, unit)
    local link = LinkOf(location)
    if not link then return end
    local id = C.IDFromLink(link)
    local p = {
        t = time(), id = id, name = C.NameFromLink(link), qty = quantity or 1, unit = unit,
        duration = duration, deposit = Deposit(kind, location, duration, quantity or 1),
        market = id and ns.Prices:Price(id) or nil, state = "live",
    }
    local list = List()
    table.insert(list, 1, p)
    for i = #list, KEEP + 1, -1 do list[i] = nil end
    -- No estimate from the API: the money that leaves right after posting is the deposit.
    if not p.deposit then pendingMoney = { post = p, money = GetMoney(), t = GetTime() } end
    ns:Changed()
end

ns:On("PLAYER_MONEY", function()
    local pm = pendingMoney
    if not pm then return end
    pendingMoney = nil
    if GetTime() - pm.t > 5 then return end
    local spent = pm.money - GetMoney()
    if spent > 0 then pm.post.deposit = spent end
end)

-- ---------------------------------------------------------------------------
-- Outcomes
-- ---------------------------------------------------------------------------

-- The oldest live post of an item made before `at` (within MATCH_DAYS of it).
local function OldestLive(name, at)
    local key = Key(name)
    if not key then return nil end
    local list, found = List(), nil
    for _, p in ipairs(list) do
        if p.state == "live" and Key(p.name) == key and p.t <= at + 60 and at - p.t <= MATCH_DAYS * 86400 then
            found = p -- newest first: keep going for the oldest
        end
    end
    return found
end

function D:Resolve(name, state, at)
    at = at or time()
    local p = OldestLive(name, at)
    if not p then return end
    p.state, p.resolved = state, at
    ns:Changed()
end

-- Sold (an invoice in the mail, at the time it was sent).
function D:OnSoldMail(name, at) self:Resolve(name, "sold", at) end
-- Expired (the item came back in the mail).
function D:OnExpiredMail(name, at) self:Resolve(name, "expired", at) end

-- Chat: "A buyer has been found for your auction of %s." / "Your auction of %s has expired."
local function Pattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local pat = fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%s", "(.+)")
    return "^" .. pat .. "$"
end
local SOLD, EXPIRED = Pattern(ERR_AUCTION_SOLD_S), Pattern(ERR_AUCTION_EXPIRED_S)

ns:On("CHAT_MSG_SYSTEM", function(msg)
    -- Secret values (this client hides some chat text from addons) can't be read.
    if (issecretvalue and issecretvalue(msg)) or (canaccessvalue and not canaccessvalue(msg)) then return end
    if type(msg) ~= "string" then return end
    local name = SOLD and msg:match(SOLD)
    if name then return D:Resolve(C.NameFromLink(name) or name, "sold") end
    name = EXPIRED and msg:match(EXPIRED)
    if name then return D:Resolve(C.NameFromLink(name) or name, "expired") end
end)

local function OnCancel(auctionID)
    if not (C_AuctionHouse.GetNumOwnedAuctions and C_AuctionHouse.GetOwnedAuctionInfo) then return end
    for i = 1, C_AuctionHouse.GetNumOwnedAuctions() or 0 do
        local ok, info = pcall(C_AuctionHouse.GetOwnedAuctionInfo, i)
        if ok and info and info.auctionID == auctionID and info.itemLink then
            D:Resolve(C.NameFromLink(info.itemLink), "cancelled")
            return
        end
    end
end

-- Posts nobody heard back about.
local function Expire()
    local cutoff = time() - GIVE_UP_DAYS * 86400
    for _, p in ipairs(List()) do
        if p.state == "live" and p.t < cutoff then p.state = "unknown" end
    end
end

ns:OnLoad(function()
    Expire()
    if not (C_AuctionHouse and C_AuctionHouse.PostItem) then return end
    hooksecurefunc(C_AuctionHouse, "PostItem", function(location, duration, quantity, _, buyout)
        OnPost("item", location, duration, quantity, buyout)
    end)
    if C_AuctionHouse.PostCommodity then
        hooksecurefunc(C_AuctionHouse, "PostCommodity", function(location, duration, quantity, unitPrice)
            OnPost("commodity", location, duration, quantity, unitPrice)
        end)
    end
    if C_AuctionHouse.CancelAuction then
        hooksecurefunc(C_AuctionHouse, "CancelAuction", function(auctionID) pcall(OnCancel, auctionID) end)
    end
end)

-- ---------------------------------------------------------------------------
-- Totals and advice
-- ---------------------------------------------------------------------------

-- The last `days` days: { posts, paid, refunded, lost, live, sold, expired, cancelled, gross (sales),
-- ratio (lost / gross), failRate (expired + cancelled over finished posts), tooHigh }.
function D:Totals(days)
    local since = time() - (days or 30) * 86400
    local t = { posts = 0, paid = 0, refunded = 0, lost = 0, live = 0, sold = 0, expired = 0, cancelled = 0, gross = 0 }
    for _, p in ipairs(List()) do
        if p.t < since then break end
        local dep = p.deposit or 0
        t.posts, t.paid = t.posts + 1, t.paid + dep
        if p.state == "sold" then t.sold, t.refunded = t.sold + 1, t.refunded + dep
        elseif p.state == "expired" then t.expired, t.lost = t.expired + 1, t.lost + dep
        elseif p.state == "cancelled" then t.cancelled, t.lost = t.cancelled + 1, t.lost + dep
        elseif p.state == "live" then t.live = t.live + dep end
    end
    t.gross = ns.Portfolio:Realized(days or 30).gross
    t.ratio = t.gross > 0 and t.lost / t.gross or (t.lost > 0 and 1 or 0)
    local done = t.sold + t.expired + t.cancelled
    t.failRate = done > 0 and (t.expired + t.cancelled) / done or 0
    t.tooHigh = (t.lost > 0 and t.ratio > WASTE_RATIO) or (done >= 5 and t.failRate > FAIL_RATE)
    return t
end

local function ItemName(id, name)
    return (id and C.GetItemInfo(id)) or name or ("item " .. tostring(id))
end

-- What's wasting deposits, worst first: { { id, text, lost } }. Looks at the last 30 days.
function D:Advice()
    local since = time() - 30 * 86400
    local by = {}
    for _, p in ipairs(List()) do
        if p.t < since then break end
        local k = p.id or Key(p.name)
        if k then
            local s = by[k]
            if not s then s = { id = p.id, name = p.name, posts = 0, sold = 0, failed = 0, cancelled = 0, lost = 0,
                over = 0, overN = 0, long = 0, fast = 0, soldTimed = 0, deposit = 0 }; by[k] = s end
            s.posts = s.posts + 1
            s.deposit = s.deposit + (p.deposit or 0)
            if p.state == "sold" then
                s.sold = s.sold + 1
                if p.resolved then
                    s.soldTimed = s.soldTimed + 1
                    if p.resolved - p.t <= 12 * 3600 then s.fast = s.fast + 1 end
                end
            elseif p.state == "expired" or p.state == "cancelled" then
                s.failed, s.lost = s.failed + 1, s.lost + (p.deposit or 0)
                if p.state == "cancelled" then s.cancelled = s.cancelled + 1 end
            end
            if p.unit and p.market and p.market > 0 then
                s.over, s.overN = s.over + p.unit / p.market, s.overN + 1
            end
            if (p.duration or 1) > 1 then s.long = s.long + 1 end
        end
    end
    local out = {}
    for _, s in pairs(by) do
        local name = ItemName(s.id, s.name)
        local overBy = s.overN > 0 and s.over / s.overN - 1 or nil
        -- Doesn't sell: priced over the market, or just not wanted.
        if s.failed >= 2 and s.failed >= s.sold then
            local why
            if overBy and overBy > 0.1 then
                why = ("you list it about %d%% over the market price; price it nearer the market"):format(overBy * 100)
            elseif s.id and ns.Prices:Vendor(s.id) then
                why = "it isn't selling at this price: list it nearer the market, post it in its best window (Timing), or sell it to a vendor"
            else
                why = "it isn't selling at this price: list it nearer the market, or post it in its best window (Timing)"
            end
            out[#out + 1] = { id = s.id, lost = s.lost, text = ("%s: %d of %d posts didn't sell (%s in deposits lost): %s."):format(
                name, s.failed, s.posts, ns.Gold(s.lost), why) }
        end
        -- Cancel and repost: every repost pays a new deposit.
        if s.cancelled >= 3 then
            out[#out + 1] = { id = s.id, lost = s.lost, text = ("%s: cancelled %d times. Each repost pays a new deposit: post once, in its best window, instead of chasing undercuts."):format(
                name, s.cancelled) }
        end
        -- Sells fast on long auctions: a shorter one costs a fraction of the deposit.
        if s.long >= 2 and s.soldTimed >= 2 and s.fast / s.soldTimed >= 0.75 then
            out[#out + 1] = { id = s.id, lost = s.deposit / 2, text = ("%s: %d of %d sales came within 12 hours, but you post it for longer. A 12-hour auction's deposit is a quarter of a 48-hour one's."):format(
                name, s.fast, s.soldTimed) }
        end
    end
    table.sort(out, function(a, b) return (a.lost or 0) > (b.lost or 0) end)
    return out
end

D.DURATION_HOURS = DURATION_HOURS
D.WASTE_RATIO, D.FAIL_RATE = WASTE_RATIO, FAIL_RATE
