local _, ns = ...

-- Auction pools: prices kept apart by which auction house they were seen at. Auctionator keeps one
-- price per item for your realm and faction ("<realm> <faction>"), so a scan at Booty Bay, or at
-- Forever's new auctioneer at the Crossroads, overwrites what your own faction's auction house
-- costs. Every price Auctionator saves goes through its Database:SetPrice (full scans, searches,
-- selling): that's hooked (Auctionator itself is untouched), and each price is also stored here
-- under the pool of the auction house it came from.
--
-- A pool is the set of auction houses that share their listings (see the Forever Auction House
-- Pools page): the Alliance cities, the Horde cities, Steamwheedle (Booty Bay, Gadgetzan,
-- Everlook), and Forever's new auctioneers, each its own pool until it's known whom they share
-- with: Quickcoin (the Crossroads and Redridge: one NPC, so one pool), Zephras Isle, Captain
-- Bloodcoin. Which pool you're at comes from the auctioneer you opened (its NPC ID); one not on the
-- list gets a pool of its own ("npc<id>", named after it and its zone), so nothing gets mixed.
-- A scan Auctionator finishes after you walk away still counts for the house you scanned.
--
-- Read: Pools:Prices(link) (every pool's price, yours first), Pools:Price(link, pool),
-- Pools:Home() (your faction's pool), Pools:Current() (the house open now, else nil). Item
-- tooltips list each pool's price (db.options.poolTooltip); WealthPlannerAPI has PoolPrice and
-- PoolPrices for the other addons (shared AuctionPrice.lua prefers them to Auctionator's).
local Pools = {}
ns.Pools = Pools

local A, H, N = "alliance", "horde", "steamwheedle"
-- Auctioneer NPC ID -> pool (Wowhead's Forever NPC data: every "Auctioneer").
local NPC_POOL = {
    -- Stormwind, Ironforge, Darnassus
    [15659] = A, [8670] = A, [8719] = A, [8671] = A, [8720] = A, [9859] = A, [8669] = A, [8723] = A, [15678] = A, [15679] = A,
    -- Orgrimmar, Thunder Bluff, Undercity
    [8673] = H, [8724] = H, [9856] = H, [8674] = H, [8722] = H, [8672] = H, [8721] = H,
    [15675] = H, [15676] = H, [15682] = H, [15683] = H, [15684] = H, [15686] = H,
    -- Booty Bay, Gadgetzan, Everlook
    [9858] = N, [15677] = N, [15681] = N, [8661] = N, [9857] = N,
    -- New in Forever: their own pools until we know better
    [258878] = "quickcoin", [257037] = "zephras", [242827] = "bloodcoin",
}
-- Where the auctioneer's GUID can't be read: the neutral towns by subzone.
local NEUTRAL_TOWNS = { ["Booty Bay"] = true, ["Gadgetzan"] = true, ["Everlook"] = true }
-- The logistics camps (the "quickcoin" pool, shown as Logistics for both factions): Durotar Supply
-- and Logistics by the Crossroads, the Azeroth Commerce Authority at Three Corners. An auctioneer
-- there not in NPC_POOL still counts as Logistics.
local LOGISTICS_CAMPS = { ["Durotar Supply and Logistics"] = true, ["Azeroth Commerce Authority"] = true }

local NAMES = {
    alliance = "Alliance", horde = "Horde", steamwheedle = "Steamwheedle",
    quickcoin = "Logistics", zephras = "Zephras Isle", bloodcoin = "Bloodcoin",
}
local ORDER = { alliance = 1, horde = 2, steamwheedle = 3, quickcoin = 4, zephras = 5, bloodcoin = 6 }

local current   -- the pool of the auction house open now
local last      -- the pool of the last one opened (Auctionator's scan may finish after it closes)

local function Realm() return GetRealmName and GetRealmName() or "?" end

local function Store()
    local db = ns.db
    if not db then return nil end
    db.pools = type(db.pools) == "table" and db.pools or {}
    local realm = Realm()
    db.pools[realm] = db.pools[realm] or {}
    return db.pools[realm]
end

local function Seen()
    local db = ns.db
    db.poolsSeen = type(db.poolsSeen) == "table" and db.poolsSeen or {}
    return db.poolsSeen
end

-- Your faction's pool.
function Pools:Home()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    return f == "Alliance" and A or f == "Horde" and H or nil
end

function Pools:Current() return current end

function Pools:Name(pool)
    if NAMES[pool] then return NAMES[pool] end
    local seen = ns.db and Seen()[pool]
    return seen and seen.name or pool
end

-- The pool of the auction house just opened: by its auctioneer, else by where you are.
local function PoolHere()
    local guid = UnitGUID and UnitGUID("npc")
    local id = type(guid) == "string" and not (issecretvalue and issecretvalue(guid)) and tonumber(guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
    if id then
        local pool = NPC_POOL[id]
        if pool then return pool end
        if GetSubZoneText and LOGISTICS_CAMPS[GetSubZoneText()] then return "quickcoin" end
        pool = "npc" .. id
        local name = UnitName and UnitName("npc")
        local zone = (GetSubZoneText and GetSubZoneText() ~= "" and GetSubZoneText()) or (GetZoneText and GetZoneText()) or "?"
        if ns.db then
            Seen()[pool] = { name = ((type(name) == "string" and name) or "Auctioneer") .. " (" .. zone .. ")", npc = id, zone = zone }
        end
        return pool
    end
    if GetSubZoneText and NEUTRAL_TOWNS[GetSubZoneText()] then return N end
    if GetSubZoneText and LOGISTICS_CAMPS[GetSubZoneText()] then return "quickcoin" end
    return Pools:Home()
end

ns:On("AUCTION_HOUSE_SHOW", function()
    current = PoolHere()
    last = current
end)
ns:On("AUCTION_HOUSE_CLOSED", function() current = nil end)

-- Days since a time.
local function Age(t) return t and math.max(0, math.floor((time() - t) / 86400)) or nil end

-- Auctionator's key for an item link (its own helper, else the item ID).
local function Key(item)
    if type(item) == "number" then return tostring(item) end
    if type(item) ~= "string" then return nil end
    local U = type(Auctionator) == "table" and Auctionator.Utilities
    if U and U.BasicDBKeyFromLink then
        local ok, key = pcall(U.BasicDBKeyFromLink, item)
        if ok and key then return key end
    end
    return item:match("item:(%d+)")
end

-- e[4]: day (ns.Today) -> the lowest price seen that day at this pool, for HISTORY_DAYS days (the
-- monthly trend in Wally's tooltips reaches back 30 days, give or take a week).
local HISTORY_DAYS = 40
-- e[5]: the scans of the last RECENT_KEEP seconds, flat { time, copper, time, copper, ... } (oldest
-- first): Wally's daily trend compares now against 24 hours ago, not against a calendar day. Scans
-- less than MERGE seconds apart are one point (the lower price).
local RECENT_KEEP, MERGE = 30 * 3600, 600

local function Record(dbKey, price, available)
    local pool = last
    if not (pool and type(dbKey) == "string" and type(price) == "number" and price > 0) then return end
    local store = Store()
    if not store then return end
    store[pool] = store[pool] or {}
    local e = store[pool][dbKey]
    if not e then e = {}; store[pool][dbKey] = e end
    e[1], e[2], e[3] = price, time(), tonumber(available)
    local today = ns.Today()
    local days = type(e[4]) == "table" and e[4] or {}
    e[4] = days
    if days[today] == nil then
        for d in pairs(days) do
            if d <= today - HISTORY_DAYS then days[d] = nil end
        end
    end
    if not days[today] or price < days[today] then days[today] = price end
    local now = e[2]
    local recent = type(e[5]) == "table" and e[5] or {}
    e[5] = recent
    local n = #recent
    if n >= 2 and now - recent[n - 1] < MERGE then
        if price < recent[n] then recent[n] = price end
    else
        recent[n + 1], recent[n + 2] = now, price
    end
    local drop = 0
    while drop + 2 <= #recent and recent[drop + 1] < now - RECENT_KEEP do drop = drop + 2 end
    if drop > 0 then
        for i = 1, #recent - drop do recent[i] = recent[i + drop] end
        for i = #recent, #recent - drop + 1, -1 do recent[i] = nil end
    end
end

-- One pool's price: copper, days since seen, how many were up; or nil.
function Pools:Price(item, pool)
    local key, store = Key(item), Store()
    local e = key and store and pool and store[pool] and store[pool][key]
    if not e then return nil end
    return e[1], Age(e[2]), e[3]
end

-- One pool's daily lows: { [day] = copper } (day = ns.Today()), the latest price, today; or nil.
function Pools:History(item, pool)
    local key, store = Key(item), Store()
    local e = key and store and pool and store[pool] and store[pool][key]
    if not (e and type(e[4]) == "table") then return nil end
    return e[4], e[1], ns.Today()
end

-- One pool's recent scans: { time, copper, time, copper, ... }, oldest first (the last 30 hours);
-- or nil.
function Pools:Recent(item, pool)
    local key, store = Key(item), Store()
    local e = key and store and pool and store[pool] and store[pool][key]
    return e and type(e[5]) == "table" and #e[5] >= 2 and e[5] or nil
end

-- Every pool's price for an item: { { pool, name, price, age, available, home, here } }, the pool
-- you're at first, then your faction's, then the rest.
function Pools:Prices(item)
    local key, store = Key(item), Store()
    local out = {}
    if not (key and store) then return out end
    local home = self:Home()
    for pool, prices in pairs(store) do
        local e = prices[key]
        if e then
            out[#out + 1] = { pool = pool, name = self:Name(pool), price = e[1], age = Age(e[2]), available = e[3],
                home = pool == home, here = pool == current }
        end
    end
    table.sort(out, function(a, b)
        if a.here ~= b.here then return a.here end
        if a.home ~= b.home then return a.home end
        local oa, ob = ORDER[a.pool] or 99, ORDER[b.pool] or 99
        if oa ~= ob then return oa < ob end
        return a.pool < b.pool
    end)
    return out
end

-- The price to go by: the auction house open now, else your faction's. Copper, age; or nil.
function Pools:Market(item)
    local pool = current or self:Home()
    if not pool then return nil end
    local price, age = self:Price(item, pool)
    return price, age
end

-- ---------------------------------------------------------------------------
-- Hooking Auctionator's saves
-- ---------------------------------------------------------------------------

local hooked = false
local function Hook()
    local db = type(Auctionator) == "table" and Auctionator.Database
    if hooked or type(db) ~= "table" or type(db.SetPrice) ~= "function" then return end
    hooked = true
    hooksecurefunc(db, "SetPrice", function(_, dbKey, price, available) Record(dbKey, price, available) end)
end
ns:On("PLAYER_LOGIN", Hook)
ns:On("AUCTION_HOUSE_SHOW", Hook) -- (in case Auctionator built its database late)

-- ---------------------------------------------------------------------------
-- Item tooltips: one line a pool
-- ---------------------------------------------------------------------------

local function AgeText(age)
    if not age then return "" end
    if age == 0 then return "today" end
    return age == 1 and "1 day ago" or (age .. " days ago")
end

local function AddLines(tooltip, link)
    if not (ns.db and ns.db.options) then return false end
    if ns.db.options.poolTooltip == false then return end
    local list = Pools:Prices(link)
    if #list == 0 then return end
    tooltip:AddLine("Auction prices", 0.95, 0.82, 0.4)
    for _, e in ipairs(list) do
        local label = e.name .. (e.here and " (here)" or e.home and " (yours)" or "")
        local right = ns.Compat.Money(e.price) .. "  |cff8a8f99" .. AgeText(e.age) .. "|r"
        local r, g, b = 0.82, 0.86, 0.9
        if e.home or e.here then r, g, b = 1, 1, 1 end
        tooltip:AddDoubleLine("  " .. label, right, r, g, b, 1, 1, 1)
    end
    tooltip:Show()
end

if ns.Tooltip and ns.Tooltip.HookItem then ns.Tooltip.HookItem(AddLines) end
