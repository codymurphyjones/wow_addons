local _, ns = ...
local C = ns.Compat

-- The "Ready to Post" queue: Auction List items in your bags, priced from Auctionator, each with
-- a per-visit approval. Posting needs a hardware event, so PostNext() posts exactly one row and is
-- only ever called from the Post button's OnClick.
local Auction = {}
ns.Auction = Auction

Auction.supported = C_AuctionHouse ~= nil and C_AuctionHouse.PostItem ~= nil and C_AuctionHouse.PostCommodity ~= nil
Auction.queue = {}
Auction.posting = false
Auction.posts = 0 -- posts Wally made this visit
Auction.open = false -- at the auction house; the queue is only built while you're there

local BUSY_SECONDS = 5
Auction.COOLDOWN = BUSY_SECONDS
local COMMODITY = Enum and Enum.ItemCommodityStatus and Enum.ItemCommodityStatus.Commodity or 2
local ITEM = Enum and Enum.ItemCommodityStatus and Enum.ItemCommodityStatus.Item or 1

-- Per auction house visit. Nothing posts until you approve it.
local approved = {}   -- key -> true: rows you approved
local done = {}       -- key -> { link, icon, count, unit }: what Wally posted, kept visible after it leaves your bags
local cancelKeys = {} -- key -> true: items whose listed auctions you chose to cancel
local askKeys = {}    -- key -> true: removed from the Auction List; ask about their auctions once we know them
local busy, busyToken = false, 0
Auction.cancels = {}  -- { auctionID, key, link, quantity }: auctions waiting for a Cancel click

local function CommodityStatus(location)
    if not C_AuctionHouse.GetItemCommodityStatus then return ITEM end
    local ok, status = pcall(C_AuctionHouse.GetItemCommodityStatus, location)
    return ok and status or nil
end

function Auction:Build()
    local db = ns.db
    if not self.open then
        self.queue, self.next = {}, nil
        self.approvedCount, self.approvedTotal, self.approvedClicks = 0, 0, 0
        return
    end
    local rows, byKey = {}, {}
    local function Add(bag, slot, info, reagent)
        local key = ns.Key(C.NameFromLink(info.link))
        local entry = key and db.auctionList[key]
        -- A one-off (queued by a plugin) posts this once without joining the Auction List.
        local once = key and not entry and db.oneOff and db.oneOff[key]
        if once and once.how ~= "auction" then once = nil end
        if once then entry = once end
        -- The reagent bag is off limits unless you dropped the item on the Wally tab yourself.
        if entry and (not reagent or entry.fromReagentBag) and (once or not db.neverAuction[key]) and not C.IsSlotBound(bag, slot) then
            local row = byKey[key]
            if not row then
                row = { key = key, link = info.link, icon = info.icon, count = 0, oneOff = once and true or nil }
                byKey[key] = row
                rows[#rows + 1] = row
            end
            row.count = row.count + (info.count or 1)
            if not row.location and ItemLocation then
                if not info.locked then
                    row.location = ItemLocation:CreateFromBagAndSlot(bag, slot)
                    row.link = info.link
                elseif not row.lockedLocation then
                    row.lockedLocation = ItemLocation:CreateFromBagAndSlot(bag, slot)
                end
            end
        end
    end
    for bag, slot, info in C.IterateBags() do Add(bag, slot, info) end
    for bag, slot, info in C.IterateBags(C.BagList("reagent")) do Add(bag, slot, info, true) end
    -- A slot locked by the previous post frees up in a moment: wait for it instead of blocking the row.
    for _, row in ipairs(rows) do
        if not row.location and row.lockedLocation then row.location, row.waiting = row.lockedLocation, true end
    end

    local opt = db.options.auction
    for _, row in ipairs(rows) do
        local entry = db.auctionList[row.key] or db.oneOff[row.key]
        row.duration = entry.duration or opt.duration or 2
        -- What you keep in your bags (set per item on the Next up card) stays out of the post.
        row.have = row.count
        row.keep = math.min(entry.keep or 0, row.have)
        row.count = row.have - row.keep
        local status = row.location and CommodityStatus(row.location)
        row.isCommodity = status == COMMODITY
        -- (Items that aren't commodities only take whole silver: see Value.lua.)
        row.unit, row.details = ns.Value:PostPrice(row.link, status == ITEM)
        if not row.location then
            row.state, row.reason = "blocked", "Locked in your bags."
        elseif status ~= COMMODITY and status ~= ITEM then
            row.state, row.reason = "blocked", "Loading item data..."
        elseif row.count < 1 then
            row.state, row.reason, row.keepingAll = "blocked", ("Keeping all %d in your bags."):format(row.have), true
        elseif not row.unit then
            row.state, row.reason = "blocked", row.details.reason
        elseif approved[row.key] then
            row.state = "approved"
        else
            row.state = "pending"
        end
        -- Clicks it takes: commodities post the whole quantity at once, other items one at a time.
        row.clicks = row.isCommodity and 1 or row.count
    end
    table.sort(rows, function(a, b)
        local va, vb = (a.unit or 0) * a.count, (b.unit or 0) * b.count
        if va ~= vb then return va > vb end
        return a.key < b.key
    end)

    for key, d in pairs(done) do
        if not byKey[key] then
            rows[#rows + 1] = { key = key, link = d.link, icon = d.icon, count = d.count, unit = d.unit, state = "posted" }
        else
            byKey[key].posted = d.count
        end
    end

    self.queue = rows
    self.next = nil
    self.approvedCount, self.approvedTotal, self.approvedClicks = 0, 0, 0
    for _, row in ipairs(rows) do
        if row.state == "approved" then
            self.next = self.next or row
            self.approvedCount = self.approvedCount + 1
            self.approvedTotal = self.approvedTotal + row.unit * row.count
            self.approvedClicks = self.approvedClicks + row.clicks
        end
    end
end

function Auction:SetApproved(key, on)
    approved[key] = on or nil
    ns:Changed()
end

-- How many of an item to keep in your bags when posting it: saved on its Auction List entry,
-- so it holds on later visits too. 0 or nil posts them all.
function Auction:SetKeep(key, keep)
    local entry = ns.db.auctionList[key]
    if not entry then return end
    keep = math.floor(tonumber(keep) or 0)
    entry.keep = keep > 0 and keep or nil
    ns:Changed()
end

-- Approves what's in the queue right now; items that show up later still need approving.
function Auction:ApproveAll()
    for _, row in ipairs(self.queue) do
        if row.state ~= "posted" then approved[row.key] = true end
    end
    ns:Changed()
end

function Auction:RejectAll()
    wipe(approved)
    ns:Changed()
end

function Auction:IsBusy() return busy end

local function ThrottleReady()
    if not C_AuctionHouse.IsThrottledMessageSystemReady then return true end
    local ok, ready = pcall(C_AuctionHouse.IsThrottledMessageSystemReady)
    return not ok or ready
end

-- What the next click of the Post button does: "cancel" (cancels go first), "post", or nil.
function Auction:NextAction()
    if self.cancels[1] then return "cancel" end
    if self.next then return "post" end
end

function Auction:CanPost()
    local action = self:NextAction()
    if not (self.supported and action and not busy and ThrottleReady()) or ns.AuctionScan:Blocking() then return false end
    return action == "cancel" or not self.next.waiting
end

-- Something is ready to go, but the auction house cooldown is holding it back.
function Auction:IsCoolingDown()
    return self.supported and self:NextAction() ~= nil and not self:CanPost() and not ns.AuctionScan:Blocking()
end

local function ClearBusy()
    if not busy then return end
    busy = false
    ns:Changed()
end

-- Whether an item Wally posts is still locked in your bags (the last post's stack on its way out,
-- or the rest of it not yet free to post).
local function PostLocked()
    local db = ns.db
    for _, _, info in C.IterateBags() do
        if info.locked then
            local key = ns.Key(C.NameFromLink(info.link))
            if key and (db.auctionList[key] or (db.oneOff and db.oneOff[key])) then return true end
        end
    end
    return false
end

-- A post or cancel stays "Posting..." until it has settled: the server answered it, the auction
-- house takes another request, and your bags have let go of the items. Each of those used to
-- free the button on its own, so it flicked between Posting... and ready a few times over two
-- seconds before it was really ready. BUSY_SECONDS frees it whatever happens.
-- Settled means settled twice in a row, a tenth of a second apart: the auction house can say it's
-- ready for a moment before a request just sent (the Active view's refresh) makes it busy again.
-- The Active view's refresh (QueryOwnedAuctions) goes out from here too, only once the auction
-- house takes requests again: sent the moment the post was confirmed, the server answered it
-- "Internal auction error". The button stays Posting... until that list has come back.
local answered, steady, queryDue, queryBack = false, 0, false, true
local QueryOwned
local function Settle(token)
    if not busy or token ~= busyToken then return end
    if answered and ThrottleReady() and not PostLocked() then
        if queryDue then
            queryDue, queryBack, steady = false, false, 0
            QueryOwned()
        elseif queryBack then
            steady = steady + 1
            if steady >= 2 then return ClearBusy() end
        end
    else
        steady = 0
    end
    C_Timer.After(0.1, function() Settle(token) end)
end

-- The server answered the post or cancel.
local function Answered()
    if not busy then return end
    answered = true
    Settle(busyToken)
end

local function StartBusy()
    busy, answered, steady, queryDue, queryBack = true, false, 0, false, true
    Auction.lastPost = GetTime()
    busyToken = busyToken + 1
    local token = busyToken
    C_Timer.After(BUSY_SECONDS, function() if token == busyToken then ClearBusy() end end)
    ns:Changed()
end

-- The Post button's click: one cancel or one post. Needs the hardware event.
function Auction:Act()
    if self:NextAction() == "cancel" then self:CancelNext() else self:PostNext() end
end

-- Call only from a button's OnClick: posting needs a hardware event.
function Auction:PostNext()
    if not self:CanPost() or self:NextAction() ~= "post" then return end
    local row = self.next
    -- The bags may have changed since the queue was built.
    local link = C.LinkFromLocation(row.location)
    if not link or ns.Key(C.NameFromLink(link)) ~= row.key then
        ns:Changed()
        return
    end
    self.posting = true
    local ok, err
    if row.isCommodity then
        ok, err = pcall(C_AuctionHouse.PostCommodity, row.location, row.duration, row.count, row.unit)
    else
        ok, err = pcall(C_AuctionHouse.PostItem, row.location, row.duration, 1, nil, row.unit)
    end
    self.posting = false
    if not ok then
        ns:Print("Couldn't post " .. (row.link or row.key) .. ": " .. tostring(err), true)
        return
    end
    StartBusy()
end

-- ---------------------------------------------------------------------------
-- Cancelling auctions of items you took off the Auction List
-- ---------------------------------------------------------------------------

local CANCEL_GRACE = 10 -- seconds a sent cancel hides its auction; a rejected one shows up again
local cancelled = {} -- auctionID -> GetTime() it was sent, so a stale owned list doesn't bring it back
local pendingCancels = {} -- auctionID -> { link, key, quantity, unit, byWally, t }: sent, waiting for AUCTION_CANCELED
local askQueue = {}  -- { key, link, count } waiting for the "also cancel?" popup
Auction.owned = nil  -- your active auctions (see OwnedActive), nil until the server has sent them

local function RecentlyCancelled(id)
    return cancelled[id] and GetTime() - cancelled[id] < CANCEL_GRACE
end

-- Asks only while the auction house takes requests (asked while it's busy, the server answers
-- "Internal auction error"); otherwise waits for it, a few seconds at most. Repeat asks merge.
local queryWaiting = false
function QueryOwned()
    if not C_AuctionHouse.QueryOwnedAuctions or queryWaiting then return end
    local tries = 0
    local function Try()
        if not Auction.open then queryWaiting = false; return end
        tries = tries + 1
        if ThrottleReady() or tries > 50 then
            queryWaiting = false
            pcall(C_AuctionHouse.QueryOwnedAuctions, {})
        else
            queryWaiting = true
            C_Timer.After(0.1, Try)
        end
    end
    Try()
end

function Auction:RefreshOwned()
    if self.open then QueryOwned() end
end

-- key, link, icon for an owned auction. Commodities may come without a link.
local function OwnedKey(info)
    local link = info.itemLink
    if not link and info.itemKey and C_AuctionHouse.GetItemKeyInfo then
        local ok, keyInfo = pcall(C_AuctionHouse.GetItemKeyInfo, info.itemKey)
        if ok and keyInfo then return ns.Key(keyInfo.itemName), nil, keyInfo.iconFileID end
    end
    return ns.Key(C.NameFromLink(link)), link, link and select(5, C.GetItemInfoInstant(link)) or nil
end

-- Active auctions you own: array of { auctionID, key, link, icon, quantity, unit, timeLeft, timeLeftSeconds }.
local function OwnedActive()
    local out = {}
    if not (C_AuctionHouse.GetNumOwnedAuctions and C_AuctionHouse.GetOwnedAuctionInfo) then return out end
    for i = 1, C_AuctionHouse.GetNumOwnedAuctions() or 0 do
        local info = C_AuctionHouse.GetOwnedAuctionInfo(i)
        if info and info.status == 0 and info.auctionID and not RecentlyCancelled(info.auctionID) then
            local key, link, icon = OwnedKey(info)
            if key then
                out[#out + 1] = {
                    auctionID = info.auctionID, key = key, link = link, icon = icon, quantity = info.quantity or 1,
                    unit = info.buyoutAmount or info.bidAmount, timeLeft = info.timeLeft, timeLeftSeconds = info.timeLeftSeconds,
                }
            end
        end
    end
    return out
end

-- Items taken off the Auction List whose auctions are still up, kept across visits so closing
-- the auction house never loses them: key -> "ask" (the "also cancel?" question isn't answered
-- yet) or "cancel" (you said yes; the cancels wait for Post clicks).
local function PendingRemoved()
    if type(ns.db.auctionRemovedPending) ~= "table" then ns.db.auctionRemovedPending = {} end
    return ns.db.auctionRemovedPending
end

local function RebuildCancels()
    local list = {}
    for _, a in ipairs(Auction.owned or {}) do
        -- Put back on the Auction List? Then leave its auctions alone.
        if cancelKeys[a.key] and not ns.db.auctionList[a.key] then list[#list + 1] = a end
    end
    Auction.cancels = list
end

-- Asked in Wally's own popup (W.Ask), never the game's StaticPopup frames: an addon's popup there
-- taints them, and the game's next dialog in that frame (buying a bank tab) gets blocked.
local ShowNextAsk
local asking = false

function ShowNextAsk()
    if not Auction.open or asking then return end
    local a = table.remove(askQueue, 1)
    if not a then return end
    local what = ("%d auction%s of %s"):format(a.count, a.count == 1 and "" or "s", a.link or a.key)
    asking = true
    local function Keep() PendingRemoved()[a.key] = nil end
    ns.Widgets.Ask({
        tag = "cancelAuctions",
        text = ("Also cancel your %s?\n\nDeposits are not refunded."):format(what),
        buttons = {
            { YES or "Yes", function()
                cancelKeys[a.key] = true
                PendingRemoved()[a.key] = "cancel"
                RebuildCancels()
                ns:Changed()
            end },
            { NO or "No", Keep },
        },
        -- No (or Escape): leave its auctions up. Closing the auction house only takes the popup
        -- away (W.CloseAsk), so the question stays saved and comes back next visit.
        onCancel = Keep,
        onHide = function() asking = false; C_Timer.After(0, function() ShowNextAsk() end) end,
    })
end

-- ---------------------------------------------------------------------------
-- Last known auctions: what was up when you last left the auction house, kept per character so
-- the Auctions page can show it anywhere. Auctions drop off when their time runs out, or when the
-- chat says one sold or expired.
-- ns.char.lastAuctions = { t = time(), list = { { key, link, icon, quantity, unit, expires, exact, someSold } } }
-- ---------------------------------------------------------------------------

local BAND_SECONDS = { [0] = 1800, 7200, 43200, 172800 } -- upper end of each time-left band

local function SaveSnapshot()
    if not (ns.char and Auction.owned) then return end
    local now, list = time(), {}
    for _, a in ipairs(Auction.owned) do
        local left = a.timeLeftSeconds or BAND_SECONDS[a.timeLeft]
        list[#list + 1] = {
            key = a.key, link = a.link, icon = a.icon, quantity = a.quantity, unit = a.unit,
            expires = left and now + left or nil, exact = a.timeLeftSeconds ~= nil or nil,
        }
    end
    ns.char.lastAuctions = { t = now, list = list }
end

-- Your auctions still on the market: the live list at the auction house, otherwise the last one
-- seen minus what has run out since. Returns list, time it was seen, live.
function Auction:Market()
    if self.open and self.owned then return self.owned, time(), true end
    local snap = ns.char and ns.char.lastAuctions
    if type(snap) ~= "table" or type(snap.list) ~= "table" then return {}, nil, false end
    local now, out = time(), {}
    for _, a in ipairs(snap.list) do
        if not a.expires or a.expires > now then out[#out + 1] = a end
    end
    return out, snap.t, false
end

-- "A buyer has been found for your auction of %s." and "Your auction of %s has expired."
local function NamePattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local pat = fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%s", "(.+)")
    return "^" .. pat .. "$"
end
local SOLD, EXPIRED = NamePattern(ERR_AUCTION_SOLD_S), NamePattern(ERR_AUCTION_EXPIRED_S)

local function OnSystemMessage(msg)
    -- Secret values (this client hides some chat text from addons) can't be read.
    if (issecretvalue and issecretvalue(msg)) or (canaccessvalue and not canaccessvalue(msg)) then return end
    if type(msg) ~= "string" then return end
    local name, sold = SOLD and msg:match(SOLD), true
    if not name then name, sold = EXPIRED and msg:match(EXPIRED), false end
    if not name then return end
    local key = ns.Key(C.NameFromLink(name) or name)
    local snap = key and ns.char and ns.char.lastAuctions
    if type(snap) ~= "table" or type(snap.list) ~= "table" then return end
    -- The message doesn't say which auction: take the one closest to running out.
    local best
    for i, a in ipairs(snap.list) do
        if a.key == key and (not best or (a.expires or math.huge) < (snap.list[best].expires or math.huge)) then
            best = i
        end
    end
    if not best then return end
    -- A stack of commodities can sell a few at a time; the message doesn't say how many.
    local a = snap.list[best]
    if sold and (a.quantity or 1) > 1 and not a.someSold then
        a.someSold = true
    else
        table.remove(snap.list, best)
    end
    ns:Changed()
end

local function OnOwnedUpdated()
    if not Auction.open then return end
    Auction.owned = OwnedActive()
    SaveSnapshot()
    local counts, links = {}, {}
    for _, a in ipairs(Auction.owned) do
        counts[a.key] = (counts[a.key] or 0) + 1
        links[a.key] = links[a.key] or a.link
    end
    -- Done with a removed item once it's back on the list or none of its auctions are left.
    local pending = PendingRemoved()
    for key in pairs(pending) do
        if ns.db.auctionList[key] or not counts[key] then
            pending[key], cancelKeys[key] = nil, nil
        end
    end
    if next(askKeys) then
        for key in pairs(askKeys) do
            if counts[key] and not ns.db.auctionList[key] then
                askQueue[#askQueue + 1] = { key = key, link = links[key], count = counts[key] }
            end
        end
        wipe(askKeys)
        ShowNextAsk()
    end
    RebuildCancels()
    ns:Changed()
end

-- Lists calls this whenever an item leaves the Auction List.
function Auction:OnListRemoved(key)
    approved[key] = nil
    askKeys[key] = true
    PendingRemoved()[key] = PendingRemoved()[key] or "ask"
    if self.open then QueryOwned() end
end

-- Call only from a button's OnClick: cancelling needs a hardware event.
function Auction:CancelNext()
    if not self:CanPost() or self:NextAction() ~= "cancel" then return end
    local a = self.cancels[1]
    self.cancelling = true
    local ok, err = pcall(C_AuctionHouse.CancelAuction, a.auctionID)
    self.cancelling = false
    if not ok then
        ns:Print("Couldn't cancel " .. (a.link or a.key) .. ": " .. tostring(err), true)
        return
    end
    ns:Print("Cancelled your auction of " .. (a.link or a.key) .. ".")
    StartBusy()
end

-- The Active view's Cancel button. Call only from a button's OnClick: cancelling needs a hardware
-- event. Unlike CancelNext this is your own choice, so AuctionLearning counts it as a cancel.
function Auction:CancelOwned(auctionID)
    if not (self.supported and auctionID) then return end
    if busy or not ThrottleReady() or ns.AuctionScan:Blocking() then
        ns:Print("The auction house is busy, try again in a moment.", true)
        return
    end
    local a
    for _, o in ipairs(self.owned or {}) do if o.auctionID == auctionID then a = o end end
    self.cancellingOwned = true
    local ok, err = pcall(C_AuctionHouse.CancelAuction, auctionID)
    self.cancellingOwned = false
    local what = a and (a.link or a.key) or "item"
    if not ok then
        ns:Print("Couldn't cancel " .. what .. ": " .. tostring(err), true)
        return
    end
    ns:Print("Cancelled your auction of " .. what .. ".")
    StartBusy()
end

-- Every CancelAuction call, from Wally, the Blizzard UI or Auctionator: hide the auction right
-- away and remember it for the history once the server confirms.
local function OnCancelSent(auctionID)
    if not (Auction.open and auctionID) then return end
    local now = GetTime()
    for id, p in pairs(pendingCancels) do
        if now - p.t > CANCEL_GRACE then pendingCancels[id] = nil end
    end
    for _, a in ipairs(Auction.owned or {}) do
        if a.auctionID == auctionID then
            pendingCancels[auctionID] = {
                link = a.link, key = a.key, quantity = a.quantity, unit = a.unit, t = now,
                byWally = (Auction.cancelling or Auction.cancellingOwned) and true or nil,
            }
        end
    end
    cancelled[auctionID] = now
    for _, list in ipairs({ Auction.owned or {}, Auction.cancels }) do
        for i = #list, 1, -1 do
            if list[i].auctionID == auctionID then table.remove(list, i) end
        end
    end
    SaveSnapshot()
    ns:Changed()
end

local function OnCanceled(auctionID)
    local id = auctionID
    if not (id and pendingCancels[id]) then
        -- No ID from the server: confirm the oldest one sent.
        id = nil
        for k, p in pairs(pendingCancels) do
            if not id or p.t < pendingCancels[id].t then id = k end
        end
    end
    local p = id and pendingCancels[id]
    if p then
        pendingCancels[id] = nil
        ns:AddAuctionCancel(p.link or p.key, p.quantity, p.unit, p.byWally)
    end
    -- Wally's cancel: Settle refreshes the Active view once the auction house is ready again.
    if busy then
        queryDue = true
        Answered()
    else
        QueryOwned()
    end
    ns:Changed()
end

-- Called by AuctionLearning once the server confirms an auction.
function Auction:OnCreated(p)
    if not p.byWally then return end
    local key = ns.Key(C.NameFromLink(p.link))
    if not key then return end
    local d = done[key]
    if not d then
        d = { link = p.link, icon = select(5, C.GetItemInfoInstant(p.link)), count = 0, unit = p.unit }
        done[key] = d
    end
    d.count = d.count + (p.quantity or 1)
    d.unit = p.unit
    self.posts = self.posts + 1
    ns:Print(("Posted %dx %s at %s each."):format(p.quantity or 1, p.link, C.Money(p.unit or 0)))
end

-- Deposit estimate for a row, or nil.
function Auction:Deposit(row)
    if not (row and row.location) then return nil end
    local ok, deposit
    if row.isCommodity and C_AuctionHouse.CalculateCommodityDeposit then
        ok, deposit = pcall(C_AuctionHouse.CalculateCommodityDeposit, C.IDFromLink(row.link), row.duration, row.count)
    elseif C_AuctionHouse.CalculateItemDeposit then
        ok, deposit = pcall(C_AuctionHouse.CalculateItemDeposit, row.location, row.duration, 1)
    end
    if ok and type(deposit) == "number" then return deposit end
end

if Auction.supported then
    ns:On("AUCTION_HOUSE_SHOW", function()
        Auction.open = true
        -- Removed items left unfinished last visit: ask again, or carry on cancelling.
        for key, state in pairs(PendingRemoved()) do
            if state == "cancel" then cancelKeys[key] = true else askKeys[key] = true end
        end
        -- Fills the Active view, and finds out whether items removed while you were away still have auctions up.
        QueryOwned()
        ns:Changed()
    end)
    ns:On("AUCTION_HOUSE_CLOSED", function()
        Auction.open = false
        wipe(approved); wipe(done); wipe(cancelKeys); wipe(cancelled); wipe(pendingCancels); wipe(askQueue)
        Auction.cancels, Auction.owned = {}, nil
        ns.Widgets.CloseAsk("cancelAuctions")
        busy, Auction.posts = false, 0
        ns:Changed()
    end)
    ns:On("OWNED_AUCTIONS_UPDATED", function()
        queryBack = true
        OnOwnedUpdated()
    end)
    ns:On("CHAT_MSG_SYSTEM", OnSystemMessage)
    ns:On("AUCTION_CANCELED", OnCanceled)
    if C_AuctionHouse.CancelAuction then hooksecurefunc(C_AuctionHouse, "CancelAuction", OnCancelSent) end
    -- New auctions show up in the Active view; one query covers a burst of confirmations.
    local queryToken = 0
    ns:On("AUCTION_HOUSE_AUCTION_CREATED", function()
        -- Wally's own post: Settle refreshes the Active view as soon as the auction house is ready
        -- again, while the button still says Posting... (A fixed second later, as before, the
        -- request landed after the button was ready and flicked it back to Posting...)
        if busy then
            queryToken = queryToken + 1
            queryDue = true
            Answered()
            return
        end
        queryToken = queryToken + 1
        local token = queryToken
        C_Timer.After(1, function() if token == queryToken and Auction.open then QueryOwned() end end)
    end)
    -- (The auction house ready again isn't the post done: Settle checks it along with the rest.)
    ns:On("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function() if answered then Settle(busyToken) end end)
    ns:On("BAG_UPDATE_DELAYED", function() ns:Changed() end)
    ns:On("ITEM_LOCK_CHANGED", function()
        if Auction.open then ns:Changed() end
    end)
    ns:On("GET_ITEM_INFO_RECEIVED", function()
        if Auction.open then ns:Changed() end
    end)
end
