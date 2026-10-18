local _, ns = ...

-- What the cart was expected to cost against what the auction house really asks. "Expected" is
-- Auctionator's market price as it stood when the auction house opened; "live" is this visit's
-- listings, from a quiet check of every cart item and from the Buyer's own searches. Per visit only.
local Compare = { expected = {}, live = {}, paid = {}, failed = {} }
ns.Compare = Compare

local Money = ns.Compat.Money
local UP, DOWN, SAME = "|cffd9736b", "|cff59f28c", "|cffffffff"

local function Refresh() if ns.CartTab then ns.CartTab:Refresh() end end

function Compare:Expected(id)
    if not id then return nil end
    if self.expected[id] == nil then self.expected[id] = ns.Catalog:PriceFor(id) or false end
    return self.expected[id] or nil
end

local function Snapshot(self, entries)
    for _, e in ipairs(entries) do self:Expected(e.itemID) end
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
function Compare:SetLive(id, listings)
    if id then self.live[id] = listings end
end

function Compare:RecordPaid(id, count, copper)
    if not id then return end
    local p = self.paid[id] or { copper = 0, count = 0 }
    p.copper, p.count = p.copper + copper, p.count + count
    self.paid[id] = p
end

-- Average unit price of the cheapest whole stacks covering qty (the way the Buyer picks), and how
-- many of the qty are listed at all. nil while the item hasn't been checked.
function Compare:LiveUnit(id, qty)
    local listings = self.live[id]
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
    local id = entry.itemID
    local parts = {}
    local expected = self:Expected(id)
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
            local expected = self:Expected(entry.itemID)
            if expected then expAll, priced = expAll + expected * remaining, priced + 1 end
            if not self.live[entry.itemID] then
                unchecked = unchecked + 1
            else
                local unit, got = self:LiveUnit(entry.itemID, remaining)
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
    for id, p in pairs(self.paid) do
        local expected = self:Expected(id)
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
        if listings then self.live[item.id] = listings else self.failed[item.id] = true end
        self.checking.done = self.checking.done + 1
        Refresh()
        Next(self)
    end
    if ns.Scanner:Modern() then ns.Scanner:SearchModern(item.id, Done) else ns.Scanner:ScanAll(item.name, Done) end
end

function Compare:Check()
    if self.queue or ns.Buyer.state ~= "idle" or ns.Scanner:Busy() then return end
    -- Low priority: never pause the background full scan for this; it runs once the scan is over.
    if ns.FullScan and ns.FullScan:Busy() then return end
    if not (ns.Scanner:Legacy() or ns.Scanner:Modern()) then return end
    local todo = {}
    for _, entry in ipairs(ns.Buyer:List().entries) do
        local name = entry.itemID and (entry.name or (ns.Catalog:Get(entry.itemID) or {}).name)
        local id = entry.itemID
        if ns.Lists:Remaining(entry) > 0 and name and not self.live[id] and not self.failed[id] then
            todo[#todo + 1] = { id = entry.itemID, name = name }
        end
    end
    if #todo == 0 then return end
    self.queue, self.checking = todo, { done = 0, total = #todo }
    Next(self)
end
