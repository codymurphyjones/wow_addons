local _, ns = ...
local W = ns.Widgets

-- Works through a shopping list at the auction house. Every purchase needs a hardware event, so
-- Step() (the Buy Next button or key binding) places at most one bid (through Purchase.lua);
-- searching between bids runs on its own.
--
-- Exact entries search for their item. Search entries (entry.filter) browse the auction house with
-- their filters and work through the matching items cheapest first, within the entry's max price
-- (or each item's market price plus tolerance).
--
-- States: idle -> scanning -> focusing -> ready -> buying -> (focusing | next item) ... -> idle
local Buyer = { state = "idle", status = {}, override = {}, skipped = {}, requotes = {}, spent = 0, bought = 0 }
ns.Buyer = Buyer

local MAX_REQUOTES = 3

-- Classic AuctionFrame, or the modern AuctionHouseFrame (C_AuctionHouse).
local function AHOpen() return ns.Scanner:Legacy() or ns.Scanner:Modern() end

local function Changed() if ns.CartTab then ns.CartTab:Refresh() end end

-- What the Cart is buying: the active list, or a restock run built from ticked prebuilt lists.
-- Switching to something else stops a run in progress.
function Buyer:List()
    local active = ns.CartTab and ns.CartTab:Source() or ns.Lists:Active()
    if self.list ~= active then
        self.list = active
        if self.state ~= "idle" then self:Stop(true) end
    end
    return active
end

function Buyer:SetList(list)
    if list ~= self.list and self.state ~= "idle" then self:Stop(true) end
    self.list = list
    Changed()
end

function Buyer:Running() return self.state ~= "idle" end

local function Clear(self)
    self.state, self.entry, self.listings, self.candidate = "idle", nil, nil, nil
    self.groups, self.group, self.cheapestOver, self.quoting = nil, nil, nil, nil
    wipe(self.override); wipe(self.skipped); wipe(self.requotes)
end

function Buyer:Stop(quiet)
    ns.Scanner:Abort()
    ns.Purchase:Cancel()
    if ns.Compare then ns.Compare:StopCheck() end
    local wasRunning = self.state ~= "idle"
    Clear(self)
    wipe(self.status)
    if wasRunning and not quiet and (self.spent > 0) then
        ns:Print(("Stopped. Spent %s on %d items."):format(ns.Compat.Money(self.spent), self.bought), true)
    end
    self.spent, self.bought = 0, 0
    Changed()
end

local function NextEntry(self)
    for _, entry in ipairs(self:List().entries) do
        if ns.Lists:Remaining(entry) > 0 and not self.skipped[entry] then return entry end
    end
end

local function Finish(self)
    local short = {}
    for _, entry in ipairs(self:List().entries) do
        if ns.Lists:Remaining(entry) > 0 then
            short[#short + 1] = ("%s (%d short)"):format(ns.Lists:Describe(entry), ns.Lists:Remaining(entry))
        end
    end
    ns:Print(("Cart finished. Spent %s on %d items."):format(ns.Compat.Money(self.spent), self.bought), true)
    if #short > 0 then ns:Print("Still needed: " .. table.concat(short, ", "), true) end
    Clear(self)
    self.spent, self.bought = 0, 0
    Changed()
end

-- The item being bought right now: the entry's own, or the matching item a search entry is on.
local function CurrentItem(self, entry)
    if entry.filter then return self.group and self.group.itemID end
    return entry.itemID
end

local function ItemText(self, entry, itemID)
    if entry.filter then
        local g = self.group
        local e = ns.Catalog:Get(itemID)
        return (g and g.link) or (e and (e.link or e.name)) or ("item:" .. tostring(itemID))
    end
    return ns.Lists:Describe(entry)
end

-- Price cap for one item: a search entry's max price, else market price plus tolerance.
local function MaxUnit(entry, itemID)
    if entry.filter and entry.filter.maxPrice then return entry.filter.maxPrice, nil end
    local market = ns.Catalog:PriceFor(itemID)
    if not market then return nil, nil end
    return market * (1 + ns.Lists:Tolerance(entry) / 100), market
end

-- Moves to the next unfinished entry and searches for it.
function Buyer:Advance()
    self.entry, self.listings, self.candidate = NextEntry(self), nil, nil
    self.groups, self.group, self.cheapestOver = nil, nil, nil
    if not self.entry then return Finish(self) end
    local entry = self.entry
    if not entry.filter then
        local name = entry.name or (ns.Catalog:Get(entry.itemID) or {}).name
        -- The classic auction house searches by name; the modern one by itemID.
        if not name and not ns.Scanner:Modern() then
            self.status[entry] = "no item data"
            self.skipped[entry] = true
            return self:Advance()
        end
    end
    self:Search(entry)
end

-- Searches for the current entry (again) and chooses what to buy from the results. A search entry
-- first browses for matching items, then searches the current one's listings.
function Buyer:Search(entry)
    ns.Purchase:Cancel()
    self.quoting = nil
    self.listings, self.candidate = nil, nil
    if entry.filter and not self.group then return self:Browse(entry) end
    self.state = "scanning"
    self.status[entry] = "scanning"
    Changed()
    local itemID = CurrentItem(self, entry)
    local function Done(listings)
        if self.entry ~= entry then return end
        if not listings then
            self.status[entry] = "no answer from the auction house"
            self.skipped[entry] = true
            return self:Advance()
        end
        self.listings = listings
        ns.Compare:SetLive(itemID, listings)
        if #listings == 0 then
            if entry.filter then return self:NextGroup(entry) end
            self.status[entry] = "none listed"
            self.skipped[entry] = true
            return self:Advance()
        end
        if not entry.filter then
            self.status[entry] = #listings .. " listing" .. (#listings == 1 and "" or "s")
        end
        self:Choose()
    end
    local function Progress(page)
        self.status[entry] = "scanning page " .. (page + 1)
        Changed()
    end
    if self.group then
        ns.Scanner:Listings(self.group, Done, Progress)
    elseif ns.Scanner:Modern() then
        ns.Scanner:SearchModern(entry.itemID, Done)
    else
        local name = entry.name or (ns.Catalog:Get(entry.itemID) or {}).name
        ns.Scanner:ScanAll(name, Done, Progress)
    end
end

-- Search entries: every matching item at the auction house, cheapest first.
function Buyer:Browse(entry)
    self.state = "scanning"
    self.status[entry] = "scanning"
    Changed()
    ns.Scanner:Browse(entry.filter, function(groups)
        if self.entry ~= entry then return end
        if not groups then
            self.status[entry] = "no answer from the auction house"
            self.skipped[entry] = true
            return self:Advance()
        end
        if #groups == 0 then
            self.status[entry] = "nothing matches"
            self.skipped[entry] = true
            return self:Advance()
        end
        self.groups, self.cheapestOver = groups, nil
        self:NextGroup(entry)
    end, function(n)
        self.status[entry] = ("scanning (%d found)"):format(n)
        Changed()
    end)
end

-- Search entries: the next matching item still within the price cap. When none is left, asks
-- (if nothing was within the cap at all) or moves on.
function Buyer:NextGroup(entry)
    self.group, self.listings = nil, nil
    while self.groups and #self.groups > 0 do
        local g = table.remove(self.groups, 1)
        local cap = MaxUnit(entry, g.itemID)
        if self.override[entry] or (cap and g.minUnit <= cap) then
            self.group = g
            self.status[entry] = ("buying %s"):format(g.link or g.name or "?")
            return self:Search(entry)
        end
        self.cheapestOver = self.cheapestOver or g
    end
    local remaining = ns.Lists:Remaining(entry)
    if remaining <= 0 then
        self.status[entry] = "done"
        return self:Advance()
    end
    local over = self.cheapestOver
    if over and not self.override[entry] and (entry.bought or 0) == 0 then
        self.state = "prompt"
        Changed()
        local cap = MaxUnit(entry, over.itemID)
        local text = ("Nothing matching %s is within your price.\n\n%sCheapest: %s at %s each"):format(
            ns.Lists:Describe(entry), cap and ("Your limit: " .. ns.Compat.Money(cap) .. " each\n") or "No max price and no market price.\n",
            over.link or over.name or "?", ns.Compat.Money(over.minUnit))
        W.Prompt3(text,
            function()
                if self.state ~= "prompt" or self.entry ~= entry then return end
                self.override[entry] = true
                self.groups = nil
                self:Search(entry)
            end,
            function() if self.state == "prompt" then self:Stop() end end,
            function()
                if self.state ~= "prompt" or self.entry ~= entry then return end
                self.status[entry] = "skipped (over price)"
                self.skipped[entry] = true
                self:Advance()
            end)
        return
    end
    self.status[entry] = ("%d short, nothing else within price"):format(remaining)
    self.skipped[entry] = true
    self:Advance()
end

-- Picks the listing to buy next, or asks what to do when nothing is within tolerance.
function Buyer:Choose()
    local entry, listings = self.entry, self.listings
    local remaining = ns.Lists:Remaining(entry)
    if remaining <= 0 then
        self.status[entry] = "done"
        return self:Advance()
    end
    if #listings == 0 then
        if entry.filter then return self:NextGroup(entry) end
        self.status[entry] = ("%d short, none left"):format(remaining)
        self.skipped[entry] = true
        return self:Advance()
    end

    local itemID = CurrentItem(self, entry)
    local maxUnit, market = MaxUnit(entry, itemID)
    local allowed = {}
    for _, l in ipairs(listings) do
        if self.override[entry] or (maxUnit and l.unit <= maxUnit) then allowed[#allowed + 1] = l end
    end

    if #allowed == 0 then
        if entry.filter then return self:NextGroup(entry) end
        self.state = "prompt"
        Changed()
        local cheapest = listings[1]
        local text
        if market then
            text = ("No %s within %d%% of market.\n\nMarket: %s each\nCheapest: %s each (%dx for %s)"):format(
                ns.Lists:Describe(entry), ns.Lists:Tolerance(entry), ns.Compat.Money(market),
                ns.Compat.Money(cheapest.unit), cheapest.count, ns.Compat.Money(cheapest.buyout))
        else
            text = ("Auctionator has no market price for %s.\n\nCheapest: %s each (%dx for %s)"):format(
                ns.Lists:Describe(entry), ns.Compat.Money(cheapest.unit), cheapest.count, ns.Compat.Money(cheapest.buyout))
        end
        W.Prompt3(text,
            function()
                if self.state ~= "prompt" or self.entry ~= entry then return end
                self.override[entry] = true; self:Choose()
            end,
            function() if self.state == "prompt" then self:Stop() end end,
            function()
                if self.state ~= "prompt" or self.entry ~= entry then return end
                self.status[entry] = "skipped (over market)"
                self.skipped[entry] = true
                self:Advance()
            end)
        return
    end

    -- Commodities (modern auction house) are bought by quantity: everything allowed, up to what's needed.
    if allowed[1].commodity then
        local want = remaining
        local qty, cost = 0, 0
        for _, l in ipairs(allowed) do
            local take = math.min(l.count, want - qty)
            if take <= 0 then break end
            qty, cost = qty + take, cost + take * l.unit
        end
        -- Asking the exact price needs a click (Step), so this is an estimate until then.
        self.candidate = { commodity = true, estimated = true, itemID = itemID, count = qty,
            buyout = math.ceil(cost), unit = cost / qty, link = ItemText(self, entry, itemID) }
        self.state = "ready"
        return Changed()
    end

    -- Cheapest stack that doesn't overshoot by too much; failing that, the smallest stack.
    local limit = remaining + remaining * ns.db.options.overshoot / 100
    local pick
    for _, l in ipairs(allowed) do
        if l.count <= limit then pick = l break end
    end
    if not pick then
        for _, l in ipairs(allowed) do
            if not pick or l.count < pick.count or (l.count == pick.count and l.unit < pick.unit) then pick = l end
        end
    end
    pick.link = pick.link or ItemText(self, entry, itemID)
    if pick.auctionID then
        -- Modern auction house: the auctionID is good to bid on as it is.
        self.candidate, self.state = pick, "ready"
        return Changed()
    end
    self:Focus(pick)
end

-- Modern commodity, from a click or key press (Step): asks the server for the exact price of the
-- estimated candidate's quantity. The next click buys at that price.
function Buyer:Quote(est)
    local entry, itemID, qty = self.entry, est.itemID, est.count
    self.state, self.quoting = "focusing", true
    -- The game call first, then the button refresh (Purchase.lua explains why).
    C_Timer.After(0, Changed)
    ns.Purchase:Quote(itemID, qty, {
        onPrice = function(unit, total)
            if self.entry ~= entry or self.state ~= "focusing" then return end
            self.quoting = nil
            -- The server rounds the unit price up to the silver, so allow that much over the search's promise.
            local promised = math.ceil((est.unit or 0) / 100) * 100
            if not self.override[entry] and unit > promised then
                -- Someone bought the cheap ones meanwhile: look again, but not forever.
                self.requotes[entry] = (self.requotes[entry] or 0) + 1
                if self.requotes[entry] > MAX_REQUOTES then
                    ns.Purchase:Cancel()
                    self.status[entry] = "skipped (price kept changing)"
                    self.skipped[entry] = true
                    return self:Advance()
                end
                ns:Print("The price went up since the search; looking again.")
                return self:Search(entry)
            end
            self.candidate = { commodity = true, itemID = itemID, count = qty, buyout = total, unit = unit,
                link = est.link }
            self.state = "ready"
            Changed()
        end,
        onFail = function(reason)
            if self.entry ~= entry or self.state ~= "focusing" then return end
            self.quoting = nil
            if reason == "price unavailable" then return self:Search(entry) end
            -- Nothing came back: still ready, the next click asks again.
            self.candidate, self.state = est, "ready"
            self.status[entry] = "no price yet (" .. reason .. "), click again"
            Changed()
        end,
    })
end

-- Reloads the candidate's page so it can be bid on, and refreshes that page's listings.
function Buyer:Focus(listing)
    local entry = self.entry
    local itemID = CurrentItem(self, entry)
    self.candidate, self.state = listing, "focusing"
    Changed()
    ns.Scanner:FocusPage(listing.name, listing.page, function(rows)
        if self.entry ~= entry or self.candidate ~= listing then return end
        local me = UnitName("player")
        -- Replace this page's listings with what's there now.
        local fresh = {}
        for _, l in ipairs(self.listings) do if l.page ~= listing.page then fresh[#fresh + 1] = l end end
        local found
        for _, r in ipairs(rows) do
            if r.buyout > 0 and not r.sold and r.owner ~= me then
                r.unit = r.buyout / r.count
                fresh[#fresh + 1] = r
                if not found and r.link == listing.link and r.count == listing.count
                    and r.buyout == listing.buyout and r.bidAmount ~= r.buyout then
                    found = r
                end
            end
        end
        table.sort(fresh, function(a, b)
            if a.unit ~= b.unit then return a.unit < b.unit end
            return a.count < b.count
        end)
        self.listings = fresh
        ns.Compare:SetLive(itemID, fresh)
        if not found then return self:Choose() end
        self.candidate, self.state = found, "ready"
        Changed()
    end)
end

local function RemoveListing(self, listing)
    for i, l in ipairs(self.listings or {}) do
        if l == listing then table.remove(self.listings, i) break end
    end
end

local function Modern(c) return c and (c.commodity or c.auctionID) end

-- Bookkeeping for a purchase that went through.
local function Bought(entry, c)
    local itemID = c.itemID or entry.itemID
    entry.bought = (entry.bought or 0) + c.count
    ns.Stock:RecordPurchase(itemID, c.count)
    ns.Compare:RecordPaid(itemID, c.count, c.buyout)
    Buyer.spent, Buyer.bought = Buyer.spent + c.buyout, Buyer.bought + c.count
    Buyer.candidate = nil
    local remaining = ns.Lists:Remaining(entry)
    Buyer.status[entry] = remaining <= 0 and "done" or ("%d/%d bought"):format(entry.bought, entry.qty)
    ns:Changed()
end

function Buyer:PlaceBid()
    local c = self.candidate
    if self.state ~= "ready" or not c then return end
    local entry = self.entry
    local function Mine() return self.entry == entry and self.state == "buying" end
    self.state = "buying"
    C_Timer.After(0, Changed) -- after the game call below
    ns.Purchase:Buy(c, {
        onBought = function()
            if not Mine() then return end
            Bought(entry, c)
            if c.commodity then
                -- Quantities on the market changed; search again before the next purchase.
                if ns.Lists:Remaining(entry) > 0 then return self:Search(entry) end
                return self:Advance()
            end
            RemoveListing(self, c)
            if not Modern(c) then
                -- Rows after the bought one move up one place on that page.
                for _, l in ipairs(self.listings) do
                    if l.page == c.page and l.index > c.index then l.index = l.index - 1 end
                end
            end
            self:Choose()
        end,
        onGone = function()
            if not Mine() then return end
            -- Someone else bought it first.
            if Modern(c) then return self:Search(entry) end
            RemoveListing(self, c)
            self.candidate = nil
            self:Choose()
        end,
        onFail = function(reason)
            if not Mine() then return end
            if reason == "not enough gold" then self.state = "ready"; return Changed() end
            if reason == "timeout" and not Modern(c) then return self:Focus(c) end
            self:Search(entry)
        end,
        onCancel = function()
            if Mine() then self.state = "ready"; Changed() end
        end,
    })
    -- Purchase refused without starting (not enough gold): still ready.
    if self.state == "buying" and not ns.Purchase:Busy() then self.state = "ready"; Changed() end
end

-- The Buy Next button and key binding.
function Buyer:Step()
    if not AHOpen() then return ns:Print("Open the auction house first.", true) end
    if self.state == "idle" then
        -- Restock runs count your stock again right before starting.
        if ns.CartTab and ns.CartTab.Recount then ns.CartTab:Recount() end
        if not NextEntry(self) then return ns:Print("Nothing left to buy on " .. self:List().name .. ".", true) end
        -- The Scanner runs one search at a time and Purchase one purchase; a run takes both over.
        ns.Compare:StopCheck()
        if ns.AuctionSearch then ns.AuctionSearch:StopAll() end
        ns.Scanner:Abort()
        ns.Purchase:Cancel()
        self.spent, self.bought = 0, 0
        wipe(self.status)
        return self:Advance()
    end
    if not self:CanBid() then return end
    if self.candidate.estimated then return self:Quote(self.candidate) end
    self:PlaceBid()
end

function Buyer:CanBid()
    return self.state == "ready" and self.candidate ~= nil and ns.Purchase:CanQuery()
        and GetMoney() >= self.candidate.buyout
end

-- Clicks still needed for the current entry's trade good: get price, then buy.
local function ClicksLeft(self, c)
    if not (self.entry and c and c.commodity) then return nil end
    return c.estimated and 2 or 1
end

-- Text and enabled state for the Buy Next button.
function Buyer:ButtonState()
    local s = self.state
    if s == "idle" then
        if NextEntry(self) then return "Start buying", true end
        return "Nothing to buy", false
    end
    local name = self.entry and ns.Lists:Describe(self.entry) or ""
    if s == "scanning" then return "Searching " .. name .. "...", false end
    if s == "focusing" then return self.quoting and "Getting price..." or "Finding auction...", false end
    if s == "prompt" then return "Waiting for you...", false end
    if s == "buying" then return ns.Purchase.state == "confirm" and "Waiting for you..." or "Buying...", false end
    local c = self.candidate
    if s == "ready" and c then
        local text = c.estimated and ("Get price: %dx %s ~%s"):format(c.count, c.link or name, ns.Compat.Money(c.buyout))
            or ("Buy %dx %s - %s"):format(c.count, c.link or name, ns.Compat.Money(c.buyout))
        if GetMoney() < c.buyout then return "Not enough gold - " .. ns.Compat.Money(c.buyout), false end
        local clicks = ClicksLeft(self, c)
        if clicks then text = text .. ("  ·  %d click%s left"):format(clicks, clicks == 1 and "" or "s") end
        return text, ns.Purchase:CanQuery()
    end
    return "Buy Next", false
end

ns:On("AUCTION_HOUSE_CLOSED", function()
    Buyer:Stop(true)
    StaticPopup_Hide("QUARTERMASTER_PROMPT3")
end)
ns:On("PLAYER_MONEY", function() if Buyer.state ~= "idle" then Changed() end end)
