local _, ns = ...

-- WallyAPI: the small public surface plugins use (Wealth Planner). Everything else in Wally stays
-- private. Plugins require Wally in their TOC (## Dependencies: Wally), so this exists when they load.
local API = { version = 1 }
ns.API = API
WallyAPI = API

local listeners = {}

-- Adds a tab to Wally's window, just above Settings. icon is an icon name ("INV_Misc_Coin_01") or a
-- full texture path. builder(page) fills the page (586 x 466);
-- page.Refresh(), if set, runs whenever Wally refreshes while the tab is showing.
-- Register while loading: once the window has been built, new tabs wait for a /reload.
function API.RegisterTab(key, label, icon, builder)
    return ns.UI:AddPluginTab(key, label, icon, builder)
end

function API.Show(key) if ns.UI then ns.UI:Show(key) end end
function API.Toggle() if ns.UI then ns.UI:Toggle() end end
function API.ActiveTab() return ns.UI and ns.UI:ActiveTab() end
function API.Refresh() if ns.UI then ns.UI:Refresh() end end

-- fn() runs after Wally's data changes (lists, auctions, sales), at most once a frame.
function API.OnChanged(fn) listeners[#listeners + 1] = fn end
function API:FireChanged()
    for _, fn in ipairs(listeners) do pcall(fn) end
end

-- Whether Wally's auction features are on (modern auction house and Auctionator).
function API.AuctionsEnabled() return ns:AuctionsEnabled() end

-- Your auctions still on the market (see Wally's On Market view): a copy of
-- { { key, link, icon, quantity, unit, expires, exact, someSold } }, the time they were seen, and
-- whether the list is live from the auction house.
function API.AuctionsOnMarket()
    if not (ns.Auction and ns.Auction.Market) then return {}, nil, false end
    local list, seen, live = ns.Auction:Market()
    local out = {}
    for i, a in ipairs(list) do
        out[i] = { key = a.key, link = a.link, icon = a.icon, quantity = a.quantity, unit = a.unit,
            expires = a.expires, exact = a.exact, someSold = a.someSold }
    end
    return out, seen, live
end

-- Auctions you posted and cancelled, newest first (read only):
-- { t, link, count, unit, duration, byWally, cancelled }.
function API.AuctionHistory() return ns.db and ns.db.auctionHistory or {} end

-- Whether an item (by name) is on Wally's Auction List.
function API.OnAuctionList(name) return ns.Lists:Contains("auctionList", ns.Key(name)) end

-- One-off sales: queue an item (link or item ID) to sell once, how = "auction" (it shows in the
-- Selling tab's Ready to Post list, for you to approve there) or "vendor" (sold with the junk at
-- the next merchant), or how = nil to take it off the queue. It never joins the Auction or Junk
-- List; Wally's learning sees the sale like one made by hand. It's dropped once the item has left
-- your bags. Returns true when queued or cleared, false when the item isn't loaded yet.
function API.SellOnce(item, how)
    local link = type(item) == "string" and item or select(2, ns.Compat.GetItemInfo(item))
    local name = link and ns.Compat.NameFromLink(link)
    if not name then
        if type(item) == "number" then ns.Compat.RequestItem(item) end
        return false
    end
    local key = ns.Key(name)
    if how == "auction" or how == "vendor" then
        ns.db.oneOff[key] = { how = how, name = name, id = ns.Compat.IDFromLink(link), link = link, t = time() }
    else
        ns.db.oneOff[key] = nil
        if ns.Auction and ns.Auction.SetApproved then ns.Auction:SetApproved(key, false) end
    end
    ns:Changed()
    return true
end

-- How an item is queued to sell once ("auction" or "vendor"), or nil.
function API.SellingOnce(item)
    local link = type(item) == "string" and item or select(2, ns.Compat.GetItemInfo(item))
    local key = link and ns.Key(ns.Compat.NameFromLink(link))
    local once = key and ns.db.oneOff[key]
    return once and once.how or nil
end

-- Drops one-offs whose item is no longer in your bags (sold, posted or moved). Run after the
-- merchant or auction house closes, so learning has already seen the sale.
local function PruneOneOffs()
    local db = ns.db
    if not (db and next(db.oneOff)) then return end
    local have = {}
    for _, _, info in ns.Compat.IterateBags() do
        local key = ns.Key(ns.Compat.NameFromLink(info.link))
        if key then have[key] = true end
    end
    for _, _, info in ns.Compat.IterateBags(ns.Compat.BagList("reagent")) do
        local key = ns.Key(ns.Compat.NameFromLink(info.link))
        if key then have[key] = true end
    end
    for key in pairs(db.oneOff) do
        if not have[key] then db.oneOff[key] = nil end
    end
    ns:Changed()
end
ns:On("MERCHANT_CLOSED", PruneOneOffs)
ns:On("AUCTION_HOUSE_CLOSED", PruneOneOffs)
ns:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(5, PruneOneOffs) end)
