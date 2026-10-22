local _, ns = ...
local C = ns.Compat

-- Every item Auctionator has a price for, with enough item info to search and filter it.
-- Entry = { id, name, link, icon, quality, reqLevel, ilvl, classID, subClassID, equipLoc, maxStack, price, ageDays, loaded }
local Catalog = { entries = {}, byID = {}, built = false, waiting = {}, queue = {} }
ns.Catalog = Catalog

local LOAD_PER_TICK = 150


function Catalog:HasData()
    return Auctionator and Auctionator.Database and Auctionator.Database.db ~= nil
end

-- Auctionator keys plain items by their itemID ("2589"); gear can be "g:<id>:<ilvl>"; pets "p:<id>".
local function IDFromKey(key)
    if type(key) == "number" then return key end
    if type(key) ~= "string" then return nil end
    return tonumber(key) or tonumber(key:match("^g:(%d+)"))
end

-- Auctionator's price and age, through the shared AuctionPrice.lua (addons/shared).
function Catalog:PriceFor(id) return id and ns.AuctionPrice.Market(id) or nil end

function Catalog:AgeFor(id) return id and ns.AuctionPrice.Age(id) or nil end

-- ---------------------------------------------------------------------------
-- Variants: copies of one item that differ in enchant, random suffix ("of the Monkey") or gems.
-- An enchant can change what an item is worth a lot, so each variant is its own item to buy.
-- ---------------------------------------------------------------------------

-- The numbers after "item:" (id, enchant, gem1-4, suffix, uniqueID, ...); empty fields are 0.
local function LinkFields(link)
    local s = type(link) == "string" and link:match("item:([%-%d:]*)")
    if not s then return nil end
    local f = {}
    for v in (s .. ":"):gmatch("([^:]*):") do f[#f + 1] = tonumber(v) or 0 end
    return f
end

-- key, enchantID, suffixID for a link. key is "<itemID>" for a plain copy, otherwise
-- "<itemID>:e<enchant>:s<suffix>:g<g1>.<g2>.<g3>.<g4>". The uniqueID and later fields differ
-- between two identical copies, so they're left out.
function Catalog:Variant(link)
    local f = LinkFields(link)
    if not f or (f[1] or 0) == 0 then return nil end
    local id, enchant, suffix = f[1], f[2] or 0, f[7] or 0
    local g1, g2, g3, g4 = f[3] or 0, f[4] or 0, f[5] or 0, f[6] or 0
    if enchant == 0 and suffix == 0 and g1 == 0 and g2 == 0 and g3 == 0 and g4 == 0 then
        return tostring(id), 0, 0
    end
    return ("%d:e%d:s%d:g%d.%d.%d.%d"):format(id, enchant, suffix, g1, g2, g3, g4), enchant, suffix
end

-- A variant key with no enchant, suffix or gems (nil counts as plain: entries saved before variants).
function Catalog:IsPlain(variant)
    return variant == nil or not variant:find(":", 1, true)
end

function Catalog:Enchanted(variant)
    local e = variant and tonumber(variant:match(":e(%-?%d+)"))
    return e ~= nil and e ~= 0
end

local enchantNames = {}
local SCAN_ONLY = { info = false }

-- The link's lines from the scan tooltip (after the name), and whether each is green.
local function TipLines(link)
    local lines = {}
    for i, l in ipairs((ns.Tooltip.Scan(SCAN_ONLY, "hyperlink", link)) or {}) do
        if i >= 2 and l[1] ~= "" then
            lines[#lines + 1] = { text = l[1], green = l[4] > 0.9 and l[3] < 0.2 and l[5] < 0.2 }
        end
    end
    return lines
end

-- "Enchanted: %s" in the client's language, as a pattern that captures the name.
local function EnchantedPattern()
    local fmt = ENCHANTED_TOOLTIP_LINE
    if type(fmt) ~= "string" or not fmt:find("%s", 1, true) then return nil end
    return "^" .. fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%s", "(.+)", 1) .. "$"
end

-- The enchant's name ("Crusader"), from the link's tooltip: the enchantment line the modern
-- tooltip data marks as such, or else the green line that the same link without its enchant lacks.
function Catalog:EnchantText(link)
    local _, enchant = self:Variant(link)
    if not enchant or enchant == 0 then return nil end
    if enchantNames[enchant] then return enchantNames[enchant] end
    local name
    local lineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.ItemEnchantmentPermanent
    if lineType and C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        for _, l in ipairs(ns.Tooltip.Lines("hyperlink", link) or {}) do
            if l.type == lineType and l[1] ~= "" then name = l[1] break end
        end
    end
    if not name then
        local base = {}
        local plain = link:gsub("(item:%-?%d+):%-?%d*", "%1:0", 1)
        for _, l in ipairs(TipLines(plain)) do base[l.text] = true end
        for _, l in ipairs(TipLines(link)) do
            if l.green and not base[l.text] then name = l.text break end
        end
    end
    if not name then return "enchant #" .. enchant end -- item data not cached yet: try again later
    local pattern = EnchantedPattern()
    name = pattern and name:match(pattern) or name
    enchantNames[enchant] = name
    return name
end

-- What sets a variant apart, for after its name: " [Crusader]", " [socketed]", or "".
function Catalog:VariantTag(link)
    local variant, enchant = self:Variant(link)
    if self:IsPlain(variant) then return "" end
    local parts = {}
    if enchant ~= 0 then parts[#parts + 1] = self:EnchantText(link) end
    if variant:match(":g(.+)$") ~= "0.0.0.0" then parts[#parts + 1] = "socketed" end
    if #parts == 0 then return "" end -- a random suffix is already in the name
    return " |cff1eff00[" .. table.concat(parts, ", ") .. "]|r"
end

-- Auctionator's market price for a variant. Plain: by itemID. A random suffix: Auctionator's price
-- for that suffix, if it has one. Enchanted or socketed: none, since Auctionator ignores enchants
-- and gems and its price is for a bare copy.
function Catalog:MarketFor(itemID, variant, link)
    if self:IsPlain(variant) then return self:PriceFor(itemID) end
    if variant:match(":g(.+)$") ~= "0.0.0.0" or self:Enchanted(variant) then return nil end
    return link and ns.AuctionPrice.Market(link) or nil
end

local function FillInfo(e)
    local name, link, quality, ilvl, reqLevel, _, _, maxStack, equipLoc, icon, _, classID, subClassID = C.GetItemInfo(e.id)
    if not name then return false end
    e.name, e.lname, e.link, e.quality = name, name:lower(), link, quality
    e.ilvl, e.reqLevel, e.maxStack = ilvl or 0, reqLevel or 0, maxStack or 1
    e.icon = icon or e.icon
    e.equipLoc = equipLoc ~= "" and equipLoc or e.equipLoc
    e.classID, e.subClassID = classID or e.classID, subClassID or e.subClassID
    e.loaded = true
    return true
end

-- Adds an entry for an item (used for list items that Auctionator has no price for yet).
function Catalog:Ensure(id)
    if not id then return nil end
    local e = self.byID[id]
    if e then return e end
    local _, _, _, equipLoc, icon, classID, subClassID = C.GetItemInfoInstant(id)
    e = { id = id, icon = icon, classID = classID, subClassID = subClassID, equipLoc = equipLoc,
        price = self:PriceFor(id), ageDays = self:AgeFor(id) }
    self.byID[id] = e
    self.entries[#self.entries + 1] = e
    if not FillInfo(e) then table.insert(self.queue, e) self:StartLoading() end
    return e
end

function Catalog:Build()
    if not self:HasData() then return false end
    wipe(self.entries); wipe(self.byID); wipe(self.waiting); wipe(self.queue)
    for key in pairs(Auctionator.Database.db) do
        local id = IDFromKey(key)
        if id and not self.byID[id] then self:Ensure(id) end
    end
    self.built = true
    self.version = (self.version or 0) + 1
    return true
end

function Catalog:EnsureBuilt()
    if not self.built then self:Build() end
    return self.built
end

-- Prices change after every Auctionator search; refreshing them is cheap compared to a rebuild.
function Catalog:RefreshPrices()
    for _, e in ipairs(self.entries) do
        e.price, e.ageDays = self:PriceFor(e.id), self:AgeFor(e.id)
    end
    self.version = (self.version or 0) + 1
end

function Catalog:Get(id)
    if not id then return nil end
    return self.byID[id] or self:Ensure(id)
end

function Catalog:Pending()
    local n = #self.queue
    for _ in pairs(self.waiting) do n = n + 1 end
    return n
end

-- Item data loads in batches: GetItemInfo returns nil for uncached items and requests them;
-- GET_ITEM_INFO_RECEIVED tells us when each arrives.
local ticker, dirty
local function Notify()
    if dirty then return end
    dirty = true
    C_Timer.After(0.5, function()
        dirty = false
        Catalog.version = (Catalog.version or 0) + 1
        if ns.UI and ns.UI.OnCatalogChanged then ns.UI:OnCatalogChanged() end
    end)
end

function Catalog:StartLoading()
    if ticker then return end
    ticker = C_Timer.NewTicker(0.05, function()
        local q = Catalog.queue
        for _ = 1, LOAD_PER_TICK do
            local e = table.remove(q)
            if not e then break end
            if FillInfo(e) then Notify()
            else Catalog.waiting[e.id] = e; C.RequestItem(e.id, true) end
        end
        if #q == 0 then ticker:Cancel(); ticker = nil end
    end)
end

ns:On("GET_ITEM_INFO_RECEIVED", function(id, success)
    local e = id and Catalog.waiting[id]
    if not e then return end
    Catalog.waiting[id] = nil
    if success ~= false then FillInfo(e) end
    Notify()
end)

-- Auctionator's full scan replaces most prices and adds new items: rebuild.
local listener = {}
function listener:ReceiveEvent()
    Catalog.built = false
    Catalog:Build()
    Notify()
end

local function RegisterWithAuctionator()
    if listener.registered then return end
    local events = Auctionator and Auctionator.FullScan and Auctionator.FullScan.Events
    if not (Auctionator and Auctionator.EventBus and events and events.ScanComplete) then return end
    -- Replicate scans and summary (browse) scans both replace most prices.
    local names = { events.ScanComplete }
    local inc = Auctionator.IncrementalScan and Auctionator.IncrementalScan.Events
    if inc and inc.ScanComplete then names[2] = inc.ScanComplete end
    local ok = pcall(Auctionator.EventBus.Register, Auctionator.EventBus, listener, names)
    listener.registered = ok
end

ns:On("PLAYER_LOGIN", RegisterWithAuctionator)
ns:On("AUCTION_HOUSE_SHOW", RegisterWithAuctionator)
ns:On("AUCTION_HOUSE_CLOSED", function()
    if not Catalog.built then return end
    -- Searches at the AH add items too; pick those up and refresh every price.
    if Catalog:HasData() then
        for key in pairs(Auctionator.Database.db) do
            local id = IDFromKey(key)
            if id and not Catalog.byID[id] then Catalog:Ensure(id) end
        end
    end
    Catalog:RefreshPrices()
    Notify()
end)
