local _, ns = ...
local C = ns.Compat

-- What an item is worth: Auctionator's auction price when it has one, otherwise an estimate from
-- rarity, tier (item level) and kind of item. Vendor price is only a floor, because valuable
-- reagents such as enchanting materials often can't be sold to a vendor at all.
local Value = {}
ns.Value = Value

local CACHE_SECONDS = 300
local RARE = 3
-- Copper per item at item level 10, by quality.
local QUALITY_BASE = { [0] = 5, [1] = 25, [2] = 250, [3] = 2000, [4] = 15000, [5] = 100000 }
local CLASS_GEM, CLASS_REAGENT, CLASS_TRADE, CLASS_QUEST, CLASS_KEY = 3, 5, 7, 12, 13
-- Trade goods subclasses worth more than their tier suggests: jewelcrafting, elemental, enchanting.
local PRECIOUS_TRADE = { [4] = true, [10] = true, [12] = true }
local WORTHLESS = { [6948] = true } -- Hearthstone

local cache = {}
local protectedSet

function Value:HasAuctionator()
    return type(Auctionator) == "table" and Auctionator.API and Auctionator.API.v1
        and Auctionator.API.v1.GetAuctionPriceByItemLink and true or false
end

local function AuctionPrice(link)
    if not Value:HasAuctionator() then return nil end
    local ok, price = pcall(Auctionator.API.v1.GetAuctionPriceByItemLink, "Wally", link)
    if ok and type(price) == "number" and price > 0 then return price end
end
function Value:AuctionPrice(link) return AuctionPrice(link) end

-- Days since Auctionator last saw the item on the auction house, or nil (never, or over 21 days).
function Value:AuctionAge(link)
    local api = self:HasAuctionator() and Auctionator.API.v1.GetAuctionAgeByItemLink
    if not api then return nil end
    local ok, age = pcall(api, "Wally", link)
    if ok and type(age) == "number" then return age end
end

-- ---------------------------------------------------------------------------
-- Posting prices: Auctionator's price minus your undercut. The modern auction house only takes
-- buyouts in whole silver, and an item is never listed for less than a vendor would pay.
-- ---------------------------------------------------------------------------

local SILVER = 100

function Value:Undercut(market)
    local o = ns.db.options.auction
    local price
    if not o.undercutOn then
        price = market - 1
    elseif o.undercutMode == "copper" then
        price = market - (o.undercut or 0)
    else
        price = market * (1 - (o.undercut or 0) / 100)
    end
    price = math.floor(price / SILVER) * SILVER
    return math.max(SILVER, price)
end

function Value:DescribeUndercut()
    local o = ns.db.options.auction
    if not o.undercutOn then return C.Money(1) .. " (match)" end
    if o.undercutMode == "copper" then return C.Money(o.undercut or 0) end
    return (o.undercut or 0) .. "%"
end

-- Off: price match, 1 below Auctionator's price. On: your own undercut amount.
function Value:SetUndercutOn(on)
    ns.db.options.auction.undercutOn = on and true or false
    ns:Changed()
end

function Value:SetUndercut(value, mode)
    local o = ns.db.options.auction
    o.undercutOn = true
    o.undercutMode = mode == "copper" and "copper" or "percent"
    value = math.max(0, tonumber(value) or 0)
    if o.undercutMode == "percent" then value = math.min(value, 90) end
    o.undercut = value
    ns:Changed()
end

-- Returns (unit, details). unit is nil when the item shouldn't be posted; details.reason says why.
-- details = { market, age, stale, vendor, reason }
function Value:PostPrice(link)
    local d = {}
    local name, _, _, _, _, _, _, _, _, _, vendor = C.GetItemInfo(link)
    if not name then
        C.RequestItem(C.IDFromLink(link))
        d.reason = "Loading item data..."
        return nil, d
    end
    d.vendor = vendor or 0
    d.market = AuctionPrice(link)
    d.age = self:AuctionAge(link)
    d.stale = d.age ~= nil and d.age > (ns.db.options.auction.staleDays or 3)
    if not d.market then
        d.reason = "No Auctionator price yet. Search for it first."
        return nil, d
    end
    local unit = self:Undercut(d.market)
    if d.vendor > 0 and unit <= d.vendor then
        d.reason = "Worth more at a vendor (" .. C.Money(d.vendor) .. ")."
        return nil, d
    end
    return unit, d
end

-- Trade goods, reagents and gems: the items "reagents by worth" applies to.
function Value:IsReagent(link)
    local classID = link and select(6, C.GetItemInfoInstant(link))
    return classID == CLASS_TRADE or classID == CLASS_REAGENT or classID == CLASS_GEM
end

-- Copper per item and where it came from ("auction", "estimate" or "none").
-- Returns nil while the item's data is still loading.
function Value:UnitWorth(link)
    if not link then return 0, "none" end
    local c = cache[link]
    if c and GetTime() - c.t < CACHE_SECONDS then return c.worth, c.source end
    local name, _, quality, ilvl, _, _, _, _, _, _, price, classID, subclassID = C.GetItemInfo(link)
    if not name then return nil end
    local worth, source
    if WORTHLESS[C.IDFromLink(link)] or classID == CLASS_QUEST or classID == CLASS_KEY then
        worth, source = 0, "none"
    else
        worth = AuctionPrice(link)
        if worth then
            source = "auction"
        else
            local kind = 1
            if classID == CLASS_GEM or (classID == CLASS_TRADE and PRECIOUS_TRADE[subclassID]) then kind = 4
            elseif classID == CLASS_TRADE or classID == CLASS_REAGENT then kind = 2 end
            local tier = (math.max(ilvl or 1, 1) / 10) ^ 1.5
            worth = math.floor((QUALITY_BASE[quality or 1] or 25) * tier * kind + 0.5)
            worth = math.max(worth, price or 0)
            source = "estimate"
        end
    end
    cache[link] = { worth = worth, source = source, t = GetTime() }
    return worth, source
end

-- Greys and soulbound gear you can't use are never "valuables": their only worth is the vendor price,
-- and protecting them would stop the grey and unusable-gear rules from selling them.
-- Unusable gear that isn't bound can still go to the auction house, so it still counts.
function Value:IsJunkByNature(info)
    if (info.quality or 1) == 0 then return true end
    if not ns.Gear:IsUnusableGear(info.link) then return false end
    if info.bound ~= nil then return info.bound end
    return info.bag ~= nil and C.IsSlotBound(info.bag, info.slot)
end

-- Ranks slot infos by stack worth. Returns link -> { rank, worth, unit, source, rare } for the
-- top N stacks (Bag Sorting setting) plus, optionally, everything rare or better.
function Value:RankSlots(infos)
    local opt = ns.db.options.sort
    local rows = {}
    for _, info in ipairs(infos) do
        local unit, source = self:UnitWorth(info.link)
        if unit and unit > 0 and not self:IsJunkByNature(info) then
            rows[#rows + 1] = { link = info.link, unit = unit, source = source, quality = info.quality or 0,
                worth = unit * (info.count or 1) }
        end
    end
    table.sort(rows, function(a, b)
        if a.worth ~= b.worth then return a.worth > b.worth end
        return a.link < b.link
    end)
    local set = {}
    for i, r in ipairs(rows) do
        local top = i <= (opt.protectTop or 0)
        local rare = opt.protectRare and r.quality >= RARE
        if (top or rare) and not set[r.link] then
            set[r.link] = { rank = i, worth = r.worth, unit = r.unit, source = r.source, rare = not top }
        end
    end
    return set
end

-- The protected valuables in your bags, worked out once per bag change.
function Value:Protected()
    if not protectedSet then
        local infos = {}
        for _, _, info in C.IterateBags() do infos[#infos + 1] = info end
        protectedSet = self:RankSlots(infos)
    end
    return protectedSet
end

function Value:IsProtected(link)
    return link and self:Protected()[link] or nil
end

-- Text for the junk filter and tooltips.
function Value:Describe(p)
    local from = p.source == "auction" and "auction price" or "estimate"
    if p.rare then return ("Valuable: rare or better, ~%s (%s)"):format(C.Money(p.worth), from) end
    return ("Valuable: #%d in your bags, ~%s (%s)"):format(p.rank, C.Money(p.worth), from)
end

function Value:SetProtectTop(n)
    ns.db.options.sort.protectTop = math.max(0, math.min(40, math.floor(tonumber(n) or 0)))
    ns:Changed()
end

function Value:Invalidate() protectedSet = nil end

function Value:Clear()
    wipe(cache)
    protectedSet = nil
end

ns:On("BAG_UPDATE_DELAYED", function() Value:Invalidate() end)
ns:On("GET_ITEM_INFO_RECEIVED", function() Value:Invalidate() end)
