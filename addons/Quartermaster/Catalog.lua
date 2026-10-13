local _, ns = ...
local C = ns.Compat

-- Every item Auctionator has a price for, with enough item info to search and filter it.
-- Entry = { id, name, link, icon, quality, reqLevel, ilvl, classID, subClassID, equipLoc, maxStack, price, ageDays, loaded }
local Catalog = { entries = {}, byID = {}, built = false, waiting = {}, queue = {} }
ns.Catalog = Catalog

local LOAD_PER_TICK = 150

local function API() return Auctionator and Auctionator.API and Auctionator.API.v1 end

function Catalog:HasData()
    return Auctionator and Auctionator.Database and Auctionator.Database.db ~= nil
end

-- Auctionator keys plain items by their itemID ("2589"); gear can be "g:<id>:<ilvl>"; pets "p:<id>".
local function IDFromKey(key)
    if type(key) == "number" then return key end
    if type(key) ~= "string" then return nil end
    return tonumber(key) or tonumber(key:match("^g:(%d+)"))
end

function Catalog:PriceFor(id)
    local api = API()
    if not api or not id then return nil end
    local ok, price = pcall(api.GetAuctionPriceByItemID, ns.CALLER, id)
    if ok and price and price > 0 then return price end
end

function Catalog:AgeFor(id)
    local api = API()
    if not api or not api.GetAuctionAgeByItemID or not id then return nil end
    local ok, age = pcall(api.GetAuctionAgeByItemID, ns.CALLER, id)
    if ok then return age end
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
            else Catalog.waiting[e.id] = e; C.RequestItem(e.id) end
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
