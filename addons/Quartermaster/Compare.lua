local _, ns = ...

-- What the cart was expected to cost against what the auction house really asks. "Expected" is
-- Auctionator's market price as it stood when the auction house opened; "live" is this visit's
-- listings, from a quiet check of every cart item and from the Buyer's own searches. Per visit only.
-- Everything is keyed by Lists:Key: an enchanted copy is a different item from the plain one.
local Compare = { expected = {}, live = {}, paid = {}, failed = {} }
ns.Compare = Compare

local Money = ns.Compat.Money
local UP, DOWN, SAME = "|cffd9736b", "|cff59f28c", "|cffffffff"

local function Refresh() if ns.CartTab then ns.CartTab:Refresh() end end

-- An exact entry's expected unit price (Lists:Price: its variant's market price, or the price seen).
function Compare:Expected(entry)
    local key = entry and not entry.filter and ns.Lists:Key(entry)
    if not key then return nil end
    if self.expected[key] == nil then self.expected[key] = ns.Lists:Price(entry) or false end
    return self.expected[key] or nil
end

-- By key alone (purchases): what Expected stored, else a plain item's market price.
local function ExpectedByKey(self, key)
    if self.expected[key] == nil then
        local id = tonumber(key)
        self.expected[key] = id and ns.Catalog:PriceFor(id) or false
    end
    return self.expected[key] or nil
end

local function Snapshot(self, entries)
    for _, e in ipairs(entries) do self:Expected(e) end
end

ns:On("AUCTION_HOUSE_SHOW", function()
    Compare:StopCheck()
    wipe(Compare.expected); wipe(Compare.live); wipe(Compare.paid); wipe(Compare.failed)
    for _, list in ipairs(ns.char.lists) do Snapshot(Compare, list.entries) end
    for _, scope in pairs(ns.Prebuilt:All()) do
        for _, t in ipairs(scope) do Snapshot(Compare, t.entries) end
    end
end)
ns:On("AUCTION_HOUSE_CLOSED", function() Compare:StopCheck() end)

-- The Buyer's listings table is stored as is, so auctions it buys drop out of the live data too.
function Compare:SetLive(key, listings)
    if key then self.live[key] = listings end
end

function Compare:RecordPaid(key, count, copper)
    if not key then return end
    local p = self.paid[key] or { copper = 0, count = 0 }
    p.copper, p.count = p.copper + copper, p.count + count
    self.paid[key] = p
end

-- Average unit price of the cheapest whole stacks covering qty (the way the Buyer picks), and how
-- many of the qty are listed at all. nil while the item hasn't been checked.
function Compare:LiveUnit(key, qty)
    local listings = self.live[key]
    if not listings then return nil end
    local cost, got = 0, 0
    for _, l in ipairs(listings) do
        if got >= qty then break end
        local n = l.available or l.count -- grouped modern rows: one bid each, `available` of them
        cost, got = cost + l.unit * n, got + n
    end
    return got > 0 and cost / got or nil, math.min(got, qty)
end

-- Colour and "+12g 30s, +8%" for actual against expected.
function Compare:Diff(expected, actual)
    local d = actual - expected
    local pct = expected > 0 and d / expected * 100 or 0
    local color = pct > 2 and UP or pct < -2 and DOWN or SAME
    pct = math.floor(pct + 0.5)
    return color, ("%s%s, %s%d%%"):format(d < 0 and "-" or "+", Money(math.abs(d)), pct < 0 and "" or "+", pct)
end

-- ---------------------------------------------------------------------------
-- Text for the Cart tab
-- ---------------------------------------------------------------------------

function Compare:RowText(entry, remaining)
    if entry.filter then return nil end -- search entries have no single expected price
    local id = ns.Lists:Key(entry)
    local parts = {}
    local expected = self:Expected(entry)
    if remaining > 0 and not self.live[id] then
        parts[#parts + 1] = "expected " .. ns.Widgets.Money(expected)
            .. (self.failed[id] and " |cff8fa3b3(couldn't check)|r" or " |cff8fa3b3(checking...)|r")
    elseif remaining > 0 then
        local unit, got = self:LiveUnit(id, remaining)
        if not unit then
            parts[#parts + 1] = UP .. "none listed now|r"
        else
            if expected then
                local color, diff = self:Diff(expected, unit)
                parts[#parts + 1] = ("expected %s → now %s%s (%s)|r"):format(Money(expected), color, Money(unit), diff:match(", (.+)$"))
            else
                parts[#parts + 1] = "now " .. Money(unit)
            end
            if got < remaining then parts[#parts + 1] = UP .. ("only %d listed|r"):format(got) end
        end
    end
    local p = self.paid[id]
    if p and p.count > 0 then
        local avg = p.copper / p.count
        local color = expected and self:Diff(expected, avg) or SAME
        parts[#parts + 1] = ("paid %s%s|r each"):format(color, Money(avg))
    end
    return #parts > 0 and table.concat(parts, "  ·  ") or nil
end

function Compare:Summary(list)
    local expSum, liveSum, unchecked, none, compared = 0, 0, 0, 0, 0
    local expAll, priced = 0, 0
    for _, entry in ipairs(list.entries) do
        local remaining = ns.Lists:Remaining(entry)
        if remaining > 0 and not entry.filter then
            local key = ns.Lists:Key(entry)
            local expected = self:Expected(entry)
            if expected then expAll, priced = expAll + expected * remaining, priced + 1 end
            if not self.live[key] then
                unchecked = unchecked + 1
            else
                local unit, got = self:LiveUnit(key, remaining)
                if not unit then none = none + 1
                elseif expected then
                    expSum, liveSum, compared = expSum + expected * got, liveSum + unit * got, compared + 1
                end
            end
        end
    end
    local parts = {}
    if compared > 0 and compared == priced and expSum == expAll then
        local color, diff = self:Diff(expSum, liveSum)
        parts[#parts + 1] = ("Expected %s → now %s%s|r  (%s%s|r)"):format(Money(expSum), color, Money(liveSum), color, diff)
    else
        parts[#parts + 1] = "Expected " .. Money(expAll)
        if compared > 0 then
            local color, diff = self:Diff(expSum, liveSum)
            parts[#parts + 1] = ("checked so far: %s vs %s expected (%s%s|r)"):format(Money(liveSum), Money(expSum), color, diff)
        end
    end
    local spent, spentExp, spentAll = 0, 0, true
    for key, p in pairs(self.paid) do
        local expected = ExpectedByKey(self, key)
        spent = spent + p.copper
        if expected then spentExp = spentExp + expected * p.count else spentAll = false end
    end
    if spent > 0 then
        if spentExp > 0 then
            local color, diff = self:Diff(spentExp, spent)
            parts[#parts + 1] = ("spent %s%s|r vs %s expected (%s%s|r)%s"):format(color, Money(spent), Money(spentExp),
                color, diff, spentAll and "" or " +unpriced")
        else
            parts[#parts + 1] = "spent " .. Money(spent)
        end
    end
    if self.checking then
        parts[#parts + 1] = ("|cffffd24dchecking prices %d/%d|r"):format(math.min(self.checking.done + 1, self.checking.total), self.checking.total)
    elseif unchecked > 0 then
        parts[#parts + 1] = ("|cff8fa3b3%d not checked|r"):format(unchecked)
    end
    if none > 0 then parts[#parts + 1] = UP .. none .. " none listed|r" end
    return table.concat(parts, "  ·  ")
end

-- ---------------------------------------------------------------------------
-- Price check: one auction house search per Cart item still to buy, in the background, so the Cart
-- knows this visit's prices before it buys (it waits for them: Buyer:ButtonState) and both tabs show
-- them up to date. Only what the list needs: never the whole auction house. Your own searches come
-- first: one pauses it (Pause, from the Buying tab's Claim and the Buyer), and the item it was on is
-- searched again later; it carries on once the auction house has been quiet RESUME_IDLE seconds.
-- Never while the Cart is buying, or while a Buying view shows an item's listings (a classic auction
-- house's bid needs that page). Driven once a second while the auction house is open, with the Cart
-- or Buying tab showing. Progress: Compare:Progress(), the bars (Compare:MakeBar).
-- ---------------------------------------------------------------------------

local token = 0
local RESUME_IDLE = 1.5 -- seconds of quiet after your own search before the check carries on
local quietSince = 0
local driver

-- The Cart's items still to buy that can be searched: { id, key, name }.
function Compare:Items()
    local out = {}
    for _, entry in ipairs(ns.Buyer:List().entries) do
        local name = entry.itemID and (entry.name or (ns.Catalog:Get(entry.itemID) or {}).name)
        if name and ns.Lists:Remaining(entry) > 0 and not ns.Buyer:IsSetAside(entry) then
            out[#out + 1] = { id = entry.itemID, key = ns.Lists:Key(entry), name = name }
        end
    end
    return out
end

-- How many of them have this visit's price (or were searched and found nothing to read), of how many.
function Compare:Progress()
    local items, done = self:Items(), 0
    for _, it in ipairs(items) do
        if self.live[it.key] or self.failed[it.key] then done = done + 1 end
    end
    return done, #items
end

function Compare:Pending()
    local done, total = self:Progress()
    return done < total
end

-- Your own search (or the Cart buying) takes the auction house: the check steps aside.
function Compare:Pause()
    token = token + 1
    self.running = nil
    quietSince = GetTime()
end
Compare.StopCheck = Compare.Pause -- (the old name: the Buyer's)

local function TabShown()
    local cart = ns.CartTab and ns.CartTab.Shown and ns.CartTab:Shown()
    local buying = ns.AuctionTab and ns.AuctionTab.Shown and ns.AuctionTab:Shown()
    return cart or buying
end

local function CanRun()
    if not (ns.Scanner:Legacy() or ns.Scanner:Modern()) then return false end
    if ns.Buyer.state ~= "idle" or ns.Scanner:Busy() or ns.Purchase.state ~= "idle" then return false end
    if ns.AuctionSearch and ns.AuctionSearch.Holding and ns.AuctionSearch:Holding() then return false end
    return GetTime() - quietSince >= RESUME_IDLE and TabShown()
end

-- One search at a time, and never from inside another's answer: the next starts a frame later. (An
-- answer can come back at once, from what the auction house has cached; each answer starting the next
-- straight away, and the Cart's redraw starting one too, doubled the searches with every answer and
-- froze the game for 8 seconds.) Next never redraws the Cart either: the Cart's redraw calls Check.
local function Next(self)
    if self.running or not CanRun() then return end
    local item
    for _, it in ipairs(self:Items()) do
        if not (self.live[it.key] or self.failed[it.key]) then item = it; break end
    end
    if not item then return end
    self.running = item
    local mine, answered = token, false
    local function Done(listings)
        if token ~= mine or answered then return end
        answered = true
        if listings then self.live[item.key] = listings else self.failed[item.key] = true end
        C_Timer.After(0, function()
            if token ~= mine or self.running ~= item then return end
            self.running = nil
            Next(self)
            Refresh()
            if ns.AuctionTab and ns.AuctionTab.Refresh then ns.AuctionTab:Refresh() end
        end)
    end
    -- Only copies of the entry's own variant: an enchanted one isn't the item on the list.
    if ns.Scanner:Modern() then ns.Scanner:SearchModern(item.id, Done, item.key)
    else ns.Scanner:ScanAll(item.name, Done, nil, item.key) end
end

function Compare:Check()
    Next(self)
end

ns:On("AUCTION_HOUSE_SHOW", function()
    if driver then driver:Cancel() end
    driver = C_Timer.NewTicker(1, function() Compare:Check() end)
end)
ns:On("AUCTION_HOUSE_CLOSED", function()
    if driver then driver:Cancel(); driver = nil end
end)

-- A progress bar for the check: "Checking prices 5/12", then "Prices checked" once all are in.
-- bar:Update() reads Progress; hidden when the Cart has nothing to price.
function Compare:MakeBar(parent, width)
    local W = ns.Widgets
    local bar = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    bar:SetSize(width or 200, 14)
    W.SetBackdrop(bar, 0.9)
    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetPoint("TOPLEFT", 1, -1); bar.fill:SetPoint("BOTTOMLEFT", 1, 1)
    bar.fill:SetColorTexture(1, 1, 1, 1)
    bar.text = bar:CreateFontString(nil, "OVERLAY", "QuartermasterGameFontHighlightSmall")
    bar.text:SetPoint("CENTER")
    function bar:Update()
        local done, total = Compare:Progress()
        if total == 0 then return self:Hide() end
        self:Show()
        local share = done / total
        self.fill:SetWidth(math.max(1, (self:GetWidth() - 2) * share))
        if done >= total then
            self.fill:SetVertexColor(0.35, 0.95, 0.55, 0.45)
            self.text:SetText(("Prices checked (%d)"):format(total))
        else
            self.fill:SetVertexColor(1, 0.82, 0.3, 0.45)
            self.text:SetText(("Checking prices %d/%d%s"):format(done, total,
                Compare.running and "" or (CanRun() and "" or " (paused)")))
        end
    end
    bar:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Today's prices", 1, 0.82, 0)
        GameTooltip:AddLine("Quartermaster searches the auction house for each item on the Cart's list, one at a time, "
            .. "so you buy at what's listed now. Your own searches go first; it carries on when they're done. "
            .. "The Cart waits until every item has been checked.", 0.8, 0.85, 0.9, true)
        GameTooltip:Show()
    end)
    bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bar:Hide()
    return bar
end

