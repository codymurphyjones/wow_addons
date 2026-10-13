local _, ns = ...
local C = ns.Compat

-- Watches every auction you create, whether through Auctionator, the Blizzard UI or Wally's own tab.
-- Each item name carries a 0..1 auction habit score (the same moving average as selling): a post
-- moves it toward 1 by 0.382 * quantity/maxStack, adding it to the Auction List yourself moves it
-- by 0.764, and cancelling an auction shrinks it twice as hard. Wally's own posts never count.
-- Crossing the threshold asks whether the item belongs on the Auction List.
local Learn = {}
ns.AuctionLearning = Learn

local RATE = 0.382
local HAND_ADD_RATE = 2 * RATE
local FLOOR = 0.1
local SNOOZE_SECONDS = 24 * 60 * 60
local PENDING_SECONDS = 30 -- a post the server hasn't confirmed by now has failed
local EXTRA_SECONDS = 3    -- multi-quantity item posts can confirm once per copy

-- Posts sent to the server, oldest first, waiting for AUCTION_HOUSE_AUCTION_CREATED.
local pending = {}

local function Supported()
    return C_AuctionHouse ~= nil and C_AuctionHouse.PostItem ~= nil and C_AuctionHouse.PostCommodity ~= nil
end

local function Decay(link, count)
    local maxStack = select(8, C.GetItemInfo(link)) or 1
    if maxStack < 1 then maxStack = 1 end
    return math.min(1, RATE * (count or 1) / maxStack)
end

local function OnPost(kind, location, duration, quantity, unit)
    local link = C.LinkFromLocation(location)
    if not link then return end
    pending[#pending + 1] = {
        kind = kind, link = link, duration = duration, quantity = quantity or 1, unit = unit or 0,
        byWally = ns.Auction and ns.Auction.posting or false, t = GetTime(),
    }
end

local function Habit(key)
    local h = ns.db.auctionHabits[key]
    if not h then h = { score = 0, posted = 0, cancelled = 0 }; ns.db.auctionHabits[key] = h end
    return h
end

function Learn:Train(link, count, duration)
    local name, _, quality, _, _, _, _, _, _, icon = C.GetItemInfo(link)
    name = name or C.NameFromLink(link)
    local key = ns.Key(name)
    if not key then return end

    -- Whatever you chose by hand becomes the duration Wally uses for this item.
    local entry = ns.db.auctionList[key]
    if entry and duration then entry.duration = duration end

    if not ns.db.options.auction.learn or ns.db.neverAuction[key] then return end
    local h = Habit(key)
    h.name, h.id, h.link, h.icon, h.quality = name, C.IDFromLink(link), link, icon or h.icon, quality or h.quality
    h.duration = duration or h.duration
    local old = h.score or 0
    h.score = old + (1 - old) * Decay(link, count)
    h.posted = (h.posted or 0) + 1
    h.lastPosted = time()

    -- Already on the list: keep learning, but there's nothing to suggest.
    local snoozed = h.snoozedUntil and h.snoozedUntil > time()
    if not entry and h.score >= ns.db.options.threshold and not snoozed and not h.pending then
        ns.Prompt:QueueAuction(key)
    end
end

-- Putting an item on the Auction List yourself is the strongest signal there is: it moves the score
-- twice as far as a full-stack post, whatever the quantity. Wally's own suggestions never come here.
function Learn:OnHandAdded(key, meta)
    if not key or not ns.db.options.auction.learn then return end
    local h = Habit(key)
    meta = meta or {}
    h.name, h.id = meta.name or h.name, meta.id or h.id
    h.link, h.icon, h.quality = meta.link or h.link, meta.icon or h.icon, meta.quality or h.quality
    local old = h.score or 0
    h.score = old + (1 - old) * HAND_ADD_RATE
    h.added = (h.added or 0) + 1
    h.lastAdded = time()
    h.snoozedUntil, h.pending = nil, nil
end

local function Commit(p)
    ns:AddAuctionHistory(p.link, p.quantity, p.unit, p.duration, p.byWally)
    -- Only habits you form by hand count.
    if not p.byWally then Learn:Train(p.link, p.quantity, p.duration) end
    if ns.Auction then ns.Auction:OnCreated(p) end
    ns:Changed()
end

local function OnCreated()
    local now = GetTime()
    -- Drop confirmed posts that are done confirming, and posts that never got confirmed.
    while pending[1] and ((pending[1].committed and (pending[1].left <= 0 or now - pending[1].t > EXTRA_SECONDS))
            or (not pending[1].committed and now - pending[1].t > PENDING_SECONDS)) do
        table.remove(pending, 1)
    end
    local p = pending[1]
    if not p then return end
    if p.committed then
        p.left = p.left - 1
        return
    end
    p.committed, p.t = true, now
    p.left = (p.kind == "item" and p.quantity or 1) - 1
    Commit(p)
end

-- The auction's item is still in your owned list when CancelAuction is called.
local function OwnedAuction(auctionID)
    if not (C_AuctionHouse.GetNumOwnedAuctions and C_AuctionHouse.GetOwnedAuctionInfo) then return nil end
    for i = 1, C_AuctionHouse.GetNumOwnedAuctions() or 0 do
        local info = C_AuctionHouse.GetOwnedAuctionInfo(i)
        if info and info.auctionID == auctionID then return info end
    end
end

function Learn:OnCancel(auctionID)
    -- Wally cancelling for a removed item: OnListRemoved already counted it.
    if ns.Auction and ns.Auction.cancelling then return end
    local ok, info = pcall(OwnedAuction, auctionID)
    if not ok or not info or not info.itemLink then return end
    local key = ns.Key(C.NameFromLink(info.itemLink))
    local h = key and ns.db.auctionHabits[key]
    if not h then return end
    local old = h.score or 0
    h.score = (1 - 2 * Decay(info.itemLink, info.quantity)) * old
    h.cancelled = (h.cancelled or 0) + 1
    if h.score < FLOOR then h.score = 0 end
    if h.score < ns.db.options.threshold then h.pending = nil end
    ns:Changed()
end

-- Taking an item off the Auction List counts like a cancel, and Wally stops suggesting it for a day.
function Learn:OnListRemoved(key)
    local h = ns.db.auctionHabits[key]
    if not h then return end
    h.score = (1 - 2 * RATE) * (h.score or 0)
    if h.score < FLOOR then h.score = 0 end
    h.cancelled = (h.cancelled or 0) + 1
    h.snoozedUntil = time() + SNOOZE_SECONDS
    h.pending = nil
end

function Learn:Snooze(key)
    local h = ns.db.auctionHabits[key]
    if h then
        h.score = math.min(h.score or 0, 0.3)
        h.snoozedUntil = time() + SNOOZE_SECONDS
        h.pending = nil
    end
    ns:Changed()
end

function Learn:Forget(key)
    ns.db.auctionHabits[key] = nil
    ns:Changed()
end

function Learn:ResetAll()
    wipe(ns.db.auctionHabits)
    ns:Changed()
end

-- Every habit not on Never Auction, highest score first; listed = already on the Auction List.
function Learn:List(text)
    local out = {}
    text = ns.Key(text)
    for key, h in pairs(ns.db.auctionHabits) do
        if not ns.db.neverAuction[key] and (not text or key:find(text, 1, true)) then
            out[#out + 1] = { key = key, habit = h, listed = ns.db.auctionList[key] ~= nil }
        end
    end
    table.sort(out, function(a, b)
        if (a.habit.score or 0) == (b.habit.score or 0) then return a.key < b.key end
        return (a.habit.score or 0) > (b.habit.score or 0)
    end)
    return out
end

ns:OnLoad(function()
    if not Supported() then return end
    hooksecurefunc(C_AuctionHouse, "PostItem", function(location, duration, quantity, _, buyout)
        OnPost("item", location, duration, quantity, buyout)
    end)
    hooksecurefunc(C_AuctionHouse, "PostCommodity", function(location, duration, quantity, unitPrice)
        OnPost("commodity", location, duration, quantity, unitPrice)
    end)
    if C_AuctionHouse.CancelAuction then
        hooksecurefunc(C_AuctionHouse, "CancelAuction", function(auctionID) Learn:OnCancel(auctionID) end)
    end
    ns:On("AUCTION_HOUSE_AUCTION_CREATED", OnCreated)
end)
