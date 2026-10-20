local _, ns = ...

-- What you use up, for other addons: Quartermaster's Consumables page keeps these stocked.
--
-- Usage is read from your bags: after each rescan (Core.lua, ns:Refresh), any consumable whose count
-- went down counts as used. Counts that drop while a window that moves items is open (vendor, bank,
-- mail, trade, auction house, guild bank), or while an item is on the cursor, are moving items, not
-- using them, so they're skipped. Saved per character: BandolierDB.usage[itemID] = { last = time(),
-- days = { [day] = count } }, kept for KEEP_DAYS.
local U = {}
ns.Usage = U

local KEEP_DAYS = 30
local DAY = 86400

local function Today() return math.floor(time() / DAY) end

-- Windows that move items in and out of your bags.
local moving = {}
local OPENS = {
    MERCHANT_SHOW = "merchant", MERCHANT_CLOSED = "merchant",
    BANKFRAME_OPENED = "bank", BANKFRAME_CLOSED = "bank",
    MAIL_SHOW = "mail", MAIL_CLOSED = "mail",
    TRADE_SHOW = "trade", TRADE_CLOSED = "trade",
    AUCTION_HOUSE_SHOW = "ah", AUCTION_HOUSE_CLOSED = "ah",
    GUILDBANKFRAME_OPENED = "guildbank", GUILDBANKFRAME_CLOSED = "guildbank",
}
local CLOSES = {
    MERCHANT_CLOSED = true, BANKFRAME_CLOSED = true, MAIL_CLOSED = true,
    TRADE_CLOSED = true, AUCTION_HOUSE_CLOSED = true, GUILDBANKFRAME_CLOSED = true,
}

local last = nil -- [itemID] = count at the last rescan; nil until the first one
local listeners = {}

local function Store()
    if not ns.db then return nil end
    ns.db.usage = ns.db.usage or {}
    return ns.db.usage
end

local function Prune(store)
    local oldest = Today() - KEEP_DAYS
    for id, rec in pairs(store) do
        for day in pairs(rec.days or {}) do
            if day < oldest then rec.days[day] = nil end
        end
        if not next(rec.days or {}) then store[id] = nil end
    end
end

local function Notify()
    for _, fn in ipairs(listeners) do pcall(fn) end
end

-- Lockboxes and clams are opened, not used up, and a fishing pole leaves the bags when equipped.
local function Tracked(entry)
    return entry.category ~= ns.Data.OPEN and not ns.Data.IsFishingPole(entry.id)
end

-- Called after every bag rescan with the scanned list (Scanner:Scan).
function U:Update(list)
    local store = Store()
    if not store then return end
    local now = {}
    for _, entry in ipairs(list or {}) do
        if Tracked(entry) then now[entry.id] = ns.ItemCount(entry.id) end
    end
    -- Items that were in the bags last time and are gone now: count them too.
    if last then
        for id in pairs(last) do
            if now[id] == nil then now[id] = ns.ItemCount(id) end
        end
    end

    local skip = next(moving) ~= nil or GetCursorInfo() == "item"
    if last and not skip then
        local day, changed = Today(), false
        for id, count in pairs(now) do
            local before = last[id]
            if before and count < before then
                local rec = store[id] or { days = {} }
                rec.days[day] = (rec.days[day] or 0) + (before - count)
                rec.last = time()
                store[id] = rec
                changed = true
            end
        end
        if changed then Notify() end
    end
    -- Keep only what's still in the bags for next time.
    for id, count in pairs(now) do
        if count == 0 then now[id] = nil end
    end
    last = now
end

-- How many of an item you used in the last `days` days (default 7).
function U:Used(itemID, days)
    local store = Store()
    local rec = store and store[itemID]
    if not rec then return 0 end
    local since, n = Today() - (days or 7) + 1, 0
    for day, count in pairs(rec.days) do
        if day >= since then n = n + count end
    end
    return n
end

local events = CreateFrame("Frame")
for event in pairs(OPENS) do pcall(events.RegisterEvent, events, event) end
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        local store = Store()
        if store then Prune(store) end
        return
    end
    local key = OPENS[event]
    if CLOSES[event] then
        -- Bag counts settle a moment after the window closes; keep skipping until the next rescan,
        -- unless the window opened again meanwhile.
        local token = {}
        moving[key] = token
        C_Timer.After(0.5, function() if moving[key] == token then moving[key] = nil end end)
    else
        moving[key] = true
    end
end)

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

BandolierAPI = BandolierAPI or {}

-- Bandolier's kind of consumable for an item ("Healing", "Food", "Elixir", ...), or nil when
-- Bandolier wouldn't use it. Needs the item's data to be loaded for anything not in its own tables.
function BandolierAPI.Category(itemID, name)
    if not itemID then return nil end
    if not name then name = ns.ItemInfo(itemID) end
    local ok, category = pcall(ns.Data.Classify, itemID, name)
    if not ok or not category or category == ns.Data.OPEN then return nil end
    return ns.Data.CATEGORY_NAMES[category]
end

-- Consumables you've used lately, most used first:
-- { { id, used = count in the last `days` days, last = time() of the latest use } }.
function BandolierAPI.RecentlyUsed(days)
    local store = Store()
    local out = {}
    for id, rec in pairs(store or {}) do
        local used = U:Used(id, days or 7)
        if used > 0 then out[#out + 1] = { id = id, used = used, last = rec.last } end
    end
    table.sort(out, function(a, b)
        if a.used ~= b.used then return a.used > b.used end
        return (a.last or 0) > (b.last or 0)
    end)
    return out
end

-- How many of an item you used in the last `days` days (default 7).
function BandolierAPI.Used(itemID, days) return U:Used(itemID, days) end

-- fn() runs whenever a new use is recorded.
function BandolierAPI.OnUsage(fn)
    if type(fn) == "function" then listeners[#listeners + 1] = fn end
end
