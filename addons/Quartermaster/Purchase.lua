local _, ns = ...

-- Places one purchase at a time at the auction house, for the Cart (Buyer) and the Buying tab.
-- Asking a trade good's price (StartCommoditiesPurchase) and every purchase need a hardware event:
-- Quote() and Buy() must run straight from a click or key press, never from a timer or callback
-- (the game blocks those: "Interface action failed because of an AddOn"). Callers make these calls
-- FIRST in their click handler and update their UI afterwards: disabling the clicked button before
-- the call makes the game stop treating the click as yours (that's how Auctionator's Buy Now works).
--
--   Purchase:Quote(itemID, qty, cb)  modern commodities: asks the exact price of qty first.
--       cb.onPrice(unit, total)  cb.onFail(reason)   (no automatic retries: the user clicks again)
--   Purchase:Buy(candidate, cb)      candidate = { count, buyout, unit, link, itemID,
--       commodity = true | auctionID | index (classic "list" row) }
--       cb.onBought(c)  cb.onGone(c) (someone else bought it)  cb.onFail(reason)  cb.onCancel()
--
-- States: idle -> quoting -> idle;  idle -> confirm -> bidding -> idle
local Purchase = { state = "idle" }
ns.Purchase = Purchase

local BID_TIMEOUT = 10
local QUOTE_TIMEOUT = 5

-- Whether the server will take another auction request right now.
function Purchase:CanQuery()
    if ns.Scanner:Modern() then
        local ready = C_AuctionHouse.IsThrottledMessageSystemReady
        return not ready or ready()
    end
    return CanSendAuctionQuery and CanSendAuctionQuery()
end

function Purchase:Busy() return self.state ~= "idle" end

function Purchase:CanBuy(c)
    return self.state == "idle" and c ~= nil and self:CanQuery() and GetMoney() >= c.buyout
end

local function Finish(self)
    local cb = self.cb
    self.state, self.quote, self.candidate, self.cb = "idle", nil, nil, nil
    return cb or {}
end

-- Drops whatever is in progress without telling the owner.
function Purchase:Cancel()
    if self.quote and C_AuctionHouse and C_AuctionHouse.CancelCommoditiesPurchase then
        C_AuctionHouse.CancelCommoditiesPurchase()
    end
    if self.state == "confirm" then StaticPopup_Hide("QUARTERMASTER_CONFIRM_BUY") end
    Finish(self)
end

-- ---------------------------------------------------------------------------
-- Commodity quotes
-- ---------------------------------------------------------------------------

local function QuoteFailed(self, q, reason)
    if self.quote ~= q then return end
    self:Cancel()
    if q.cb.onFail then q.cb.onFail(reason) end
end

-- From a click or key press only. One request; if it gets no answer the user clicks again.
function Purchase:Quote(itemID, qty, cb)
    local q = { itemID = itemID, qty = qty, cb = cb or {} }
    if self.state == "confirm" or self.state == "bidding" or not self:CanQuery() then
        if q.cb.onFail then q.cb.onFail("the auction house is busy") end
        return
    end
    -- No CancelCommoditiesPurchase first: a new request replaces an open one, and this click's one
    -- game call must be the price request.
    self.candidate, self.cb = nil, nil
    self.state, self.quote = "quoting", q
    C_AuctionHouse.StartCommoditiesPurchase(itemID, qty)
    C_Timer.After(QUOTE_TIMEOUT, function()
        if self.state == "quoting" then QuoteFailed(self, q, "no answer") end
    end)
end

-- Diagnostic (/qm testprice [itemID]): asks one trade good's price for 1, straight from the slash
-- command (a key press) with nothing else in between, and says whether a price came back.
function Purchase:TestPrice(itemID)
    if not ns.Scanner:Modern() then return ns:Print("Open the auction house first.", true) end
    if not itemID then return ns:Print("Open a trade good's listings in the Buying tab first, or use /qm testprice <itemID>.", true) end
    self:Cancel()
    ns:Print(("Test: asking the price of 1x item %d..."):format(itemID), true)
    local q = { itemID = itemID, qty = 1, cb = {
        onPrice = function(unit, total)
            ns:Print(("Test: price arrived, %s for 1. Quartermaster can ask prices from a key press."):format(ns.Compat.Money(total)), true)
        end,
        onFail = function(reason) ns:Print("Test: no price (" .. reason .. ").", true) end,
    } }
    self.state, self.quote = "quoting", q
    C_AuctionHouse.StartCommoditiesPurchase(itemID, 1)
    C_Timer.After(QUOTE_TIMEOUT, function()
        if self.state == "quoting" and self.quote == q then QuoteFailed(self, q, "no answer") end
    end)
end

-- The server dropped our request (sent while throttled).
ns:On("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", function()
    local q = Purchase.quote
    if q and Purchase.state == "quoting" then QuoteFailed(Purchase, q, "the auction house is busy") end
end)

ns:On("COMMODITY_PRICE_UPDATED", function(unit, total)
    local q = Purchase.quote
    if not q or Purchase.state ~= "quoting" then return end
    -- The quote stays open on the server: ConfirmCommoditiesPurchase buys at this price.
    Purchase.state = "idle"
    if q.cb.onPrice then q.cb.onPrice(unit, total) end
end)

ns:On("COMMODITY_PRICE_UNAVAILABLE", function()
    local q = Purchase.quote
    if not q or Purchase.state ~= "quoting" then return end
    Purchase:Cancel()
    if q.cb.onFail then q.cb.onFail("price unavailable") end
end)

-- ---------------------------------------------------------------------------
-- Buying
-- ---------------------------------------------------------------------------

local function PlaceBid(self)
    local c = self.candidate
    self.state, self.bidAt = "bidding", GetTime()
    if c.commodity then
        C_AuctionHouse.ConfirmCommoditiesPurchase(c.itemID, c.count)
    elseif c.auctionID then
        C_AuctionHouse.PlaceBid(c.auctionID, c.buyout)
    else
        PlaceAuctionBid("list", c.index, c.buyout)
    end
    C_Timer.After(BID_TIMEOUT, function()
        if self.state == "bidding" and self.candidate == c and GetTime() - self.bidAt >= BID_TIMEOUT - 0.1 then
            local cb = Finish(self)
            if cb.onFail then cb.onFail("timeout") end
        end
    end)
end

function Purchase:Buy(c, cb)
    if not c then return end
    if GetMoney() < c.buyout then
        return ns:Print("Not enough gold for " .. ns.Compat.Money(c.buyout) .. ".", true)
    end
    -- A commodity quote stays open between Quote() and Buy(); anything else is dropped.
    local keepQuote = c.commodity and self.quote and self.quote.itemID == c.itemID and self.quote.qty == c.count
    if self.state ~= "idle" then return end
    if not keepQuote then self:Cancel() end
    self.candidate, self.cb = c, cb or {}
    local threshold = (ns.db.options.confirmOver or 0) * 10000
    -- c.confirmed: the quantity popup already asked.
    if threshold > 0 and c.buyout >= threshold and not c.confirmed then
        self.state = "confirm"
        StaticPopup_Show("QUARTERMASTER_CONFIRM_BUY", ("Buy %dx %s for %s?"):format(c.count, c.link or "?", ns.Compat.Money(c.buyout)), nil,
            { fn = function()
                if self.state ~= "confirm" or self.candidate ~= c then return end
                PlaceBid(self)
            end,
              cancel = function()
                if self.state ~= "confirm" or self.candidate ~= c then return end
                local done = Finish(self)
                if done.onCancel then done.onCancel() end
            end })
        return
    end
    PlaceBid(self)
end

StaticPopupDialogs["QUARTERMASTER_CONFIRM_BUY"] = {
    text = "%s", button1 = YES or "Yes", button2 = NO or "No",
    OnAccept = function(_, data) data.fn() end,
    OnCancel = function(_, data) data.cancel() end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, showAlert = 1, preferredIndex = 3,
}

local function Modern(c) return c and (c.commodity or c.auctionID) end

local function Bought()
    local c = Purchase.candidate
    local cb = Finish(Purchase)
    if cb.onBought then cb.onBought(c) end
end

local function Failed(reason)
    local cb = Finish(Purchase)
    if cb.onFail then cb.onFail(reason) end
end

-- Classic auction house: the server confirms a bid in chat.
ns:On("CHAT_MSG_SYSTEM", function(msg)
    if Purchase.state ~= "bidding" or msg ~= ERR_AUCTION_BID_PLACED or Modern(Purchase.candidate) then return end
    Bought()
end)

-- Modern auction house: commodities by quantity, items by auctionID.
ns:On("COMMODITY_PURCHASE_SUCCEEDED", function()
    local c = Purchase.candidate
    if Purchase.state ~= "bidding" or not (c and c.commodity) then return end
    Purchase.quote = nil
    Bought()
end)

ns:On("COMMODITY_PURCHASE_FAILED", function()
    local c = Purchase.candidate
    if Purchase.state == "bidding" and c and c.commodity then Purchase.quote = nil; Failed("purchase failed") end
end)

ns:On("AUCTION_HOUSE_PURCHASE_COMPLETED", function(auctionID)
    local c = Purchase.candidate
    if Purchase.state ~= "bidding" or not (c and c.auctionID) or c.auctionID ~= auctionID then return end
    Bought()
end)

ns:On("AUCTION_HOUSE_SHOW_ERROR", function()
    if Purchase.state == "bidding" and Modern(Purchase.candidate) then Purchase.quote = nil; Failed("auction house error") end
end)

ns:On("UI_ERROR_MESSAGE", function(_, msg)
    if Purchase.state ~= "bidding" then return end
    if msg == ERR_ITEM_NOT_FOUND or msg == ERR_AUCTION_DATABASE_ERROR then
        -- Someone else bought it first.
        local c = Purchase.candidate
        Purchase.quote = nil
        local cb = Finish(Purchase)
        if cb.onGone then cb.onGone(c) end
    elseif msg == ERR_NOT_ENOUGH_MONEY then
        Failed("not enough gold")
    end
end)

ns:On("AUCTION_HOUSE_CLOSED", function()
    Purchase:Cancel()
    StaticPopup_Hide("QUARTERMASTER_CONFIRM_BUY")
end)
