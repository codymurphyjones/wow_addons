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
-- Quiet price check: one search per unchecked cart item, while nothing is being bought
-- ---------------------------------------------------------------------------

local token = 0

function Compare:StopCheck()
    token = token + 1
    self.queue, self.checking = nil, nil
end

local function Next(self)
    local item = table.remove(self.queue, 1)
    if not item then
        self.queue, self.checking = nil, nil
        return Refresh()
    end
    local mine = token
    local function Done(listings)
        if token ~= mine then return end
        if listings then self.live[item.key] = listings else self.failed[item.key] = true end
        self.checking.done = self.checking.done + 1
        Refresh()
        Next(self)
    end
    -- Only copies of the entry's own variant: an enchanted one isn't the item on the list.
    if ns.Scanner:Modern() then ns.Scanner:SearchModern(item.id, Done, item.key)
    else ns.Scanner:ScanAll(item.name, Done, nil, item.key) end
end

function Compare:Check()
    if self.queue or ns.Buyer.state ~= "idle" or ns.Scanner:Busy() then return end
    -- Low priority: never pause the background full scan for this; it runs once the scan is over.
    if ns.FullScan and ns.FullScan:Busy() then return end
    if not (ns.Scanner:Legacy() or ns.Scanner:Modern()) then return end
    local todo = {}
    for _, entry in ipairs(ns.Buyer:List().entries) do
        local name = entry.itemID and (entry.name or (ns.Catalog:Get(entry.itemID) or {}).name)
        local key = entry.itemID and ns.Lists:Key(entry)
        if ns.Lists:Remaining(entry) > 0 and name and not self.live[key] and not self.failed[key] then
            todo[#todo + 1] = { id = entry.itemID, key = key, name = name }
        end
    end
    if #todo == 0 then return end
    self.queue, self.checking = todo, { done = 0, total = #todo }
    Next(self)
end
