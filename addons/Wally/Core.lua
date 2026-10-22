local addonName, ns = ...

ns.VERSION = "0.1.6"
ns.PREFIX = "|cff55d6beWally|r"
ns.ICON = "Interface/AddOns/Wally/Media/Wally"
ns.HISTORY_MAX = 200

-- Events, saved variables, Print, Changed and timers: the shared Core.lua (addons/shared).
ns.SAVED = { db = "WallyDB", char = "WallyCharDB" }

ns.DEFAULTS = {
    inclusions = {},
    exclusions = {},
    patterns = { include = {}, exclude = {} },
    habits = {},
    history = {},
    sessions = {},
    -- Auctions: lists keyed like inclusions/exclusions (plus a learned duration), and habits kept
    -- apart from selling habits so the two scores never mix.
    auctionList = {},
    neverAuction = {},
    auctionHabits = {},
    auctionHistory = {},
    -- One-off sales a plugin queued (Wealth Planner's Go liquid): key -> { how = "auction" | "vendor",
    -- name, id, link, t }. Never on the lists: gone once the item has left your bags.
    oneOff = {},
    auctionScans = {}, -- realm -> time() of the last finished full scan
    options = {
        keepSessions = 30,
        autoSell = false,
        safeSell = true,
        sellGreys = true,
        learn = true,
        threshold = 0.5,
        autoAcceptLearned = false,
        protectUpgrades = true,
        sellUnusableBound = true,
        autoRepair = true,
        guildRepair = true,
        tooltip = true,
        chat = true,
        -- Wally's bag window (Bags.lua) in place of the game's bag windows.
        bags = { window = true, columns = 12 },
        -- Lists here are filled and repaired by Sorter:Validate().
        sort = {
            criteria = {},
            categories = {},
            pinned = {},
            junkLast = true,
            fillFromEnd = false,
            bagButton = true,
            buttonSide = "left",
            afterSell = false,
            onMerchantClose = true,   -- auto sort when a merchant closes
            onBagsClose = true,       -- auto sort when the bags close
            onMailClose = true,       -- auto sort when the mailbox closes
            protectTop = 10,
            protectRare = true,
            reagentsByWorth = true,
        },
        auction = {
            learn = true,
            autoAccept = false,
            undercutOn = false,       -- off: post 1c under Auctionator's price (rounds to 1s under)
            undercut = 5,
            undercutMode = "percent", -- "percent" | "copper"
            duration = 2,             -- 1 short, 2 medium, 3 long; used until an item has a learned duration
            staleDays = 3,
            scanFirst = true,         -- full Auctionator scan on the first visit to Wally's tab each session, unless one finished in the last 4 hours
            hideTabs = false,         -- hide Blizzard's Buy/Sell/Auctions and Auctionator's Cancelling/Auctionator tabs
        },
    },
}
ns.CHAR_DEFAULTS = {
    window = { point = "CENTER", x = 0, y = 0 },
    minimap = { angle = 200, hide = false },
    merchantButton = nil,
    sortIgnore = {},
    sortAnchors = {},         -- ["bag:slot"] = itemID: anchored items sorting leaves alone (Sort.lua)
    auctionView = "history",
}

function ns.Key(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil end
    return name:lower()
end

-- What a change refreshes (ns:Changed coalesces many list edits into one refresh next frame).
ns:OnChanged(function()
    if ns.Value then ns.Value:Clear() end
    if ns.JunkFilter then ns.JunkFilter:ClearCache() end
    if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
    if ns.Merchant and ns.Merchant.UpdateState then ns.Merchant:UpdateState() end
    if ns.Auction and ns.Auction.supported then ns.Auction:Build() end
    if ns.AuctionTab and ns.AuctionTab.Refresh then ns.AuctionTab:Refresh() end
    if ns.API then ns.API:FireChanged() end
end)

function ns:AddHistory(kind, link, count, copper, byWally)
    local h = self.db.history
    table.insert(h, 1, { t = time(), kind = kind, link = link, count = count or 1, copper = copper or 0, byWally = byWally or nil })
    for i = #h, self.HISTORY_MAX + 1, -1 do h[i] = nil end
end

-- One auction that was created. unit is the per-item buyout in copper.
function ns:AddAuctionHistory(link, count, unit, duration, byWally)
    local h = self.db.auctionHistory
    table.insert(h, 1, { t = time(), link = link, count = count or 1, unit = unit or 0, duration = duration, byWally = byWally or nil })
    for i = #h, self.HISTORY_MAX + 1, -1 do h[i] = nil end
end

-- One auction that was cancelled, by Wally or by hand.
function ns:AddAuctionCancel(link, count, unit, byWally)
    local h = self.db.auctionHistory
    table.insert(h, 1, { t = time(), link = link, count = count or 1, unit = unit or 0, byWally = byWally or nil, cancelled = true })
    for i = #h, self.HISTORY_MAX + 1, -1 do h[i] = nil end
end

-- Auctions are offered only when the modern auction house is there, and only with Auctionator.
function ns:AuctionsEnabled()
    return ns.Auction and ns.Auction.supported and ns.Value:HasAuctionator() or false
end

ns:On("PLAYER_LOGIN", function()
    ns:Print("v" .. ns.VERSION .. " loaded. Type |cffffffff/wally|r to manage your junk.")
end)

local function Help()
    ns:Print("/wally - open the junk manager", true)
    ns:Print("/wally config - open Options > AddOns > Wally", true)
    ns:Print("/wally history - everything Wally has sold, by session", true)
    ns:Print("/wally add <item link or name> - add to the Junk List", true)
    ns:Print("/wally never <item link or name> - add to Never Sell", true)
    ns:Print("/wally remove <item link or name> - remove from both lists", true)
    ns:Print("/wally rule <text> | /wally keeprule <text> - add a 'name contains' junk / keep rule", true)
    ns:Print("/wally sell - sell junk now (at a merchant)", true)
    ns:Print("/wally sort - sort your bags | /wally sortbank - sort the bank | /wally sort config - sort options", true)
    ns:Print("/wally forget <item link or name> - reset what Wally learned about an item", true)
    ns:Print("/wally list - print the junk list", true)
    ns:Print("/wally minimap - show/hide the minimap button", true)
    ns:Print("/wally resetbutton - put the merchant button back in its default spot", true)
    if ns:AuctionsEnabled() then
        ns:Print("/wally auction - open Wally's auction house tab (or the Auctions page away from it)", true)
        ns:Print("/wally auction add|never|remove|forget <item> - manage the Auction List", true)
        ns:Print("/wally auction undercut <number>[%]|off - e.g. 5% or 100 (copper); off price matches", true)
    end
end

local function AuctionCommand(msg)
    if not ns:AuctionsEnabled() then
        return ns:Print("Auctions need the modern auction house and Auctionator.", true)
    end
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "" then
        if not (ns.AuctionTab and ns.AuctionTab:Select()) and ns.UI then ns.UI:Show("auction") end
    elseif cmd == "add" and rest ~= "" then
        ns.Lists:Add("auctionList", rest, "manual")
    elseif cmd == "never" and rest ~= "" then
        ns.Lists:Add("neverAuction", rest, "manual")
    elseif cmd == "remove" and rest ~= "" then
        local key = ns.Lists:Resolve(rest)
        if key and (ns.Lists:Remove("auctionList", key) or ns.Lists:Remove("neverAuction", key)) then
            ns:Print("Removed " .. rest .. ".", true)
        else
            ns:Print(rest .. " is not on an auction list.", true)
        end
    elseif cmd == "forget" and rest ~= "" then
        local key = ns.Lists:Resolve(rest)
        if key and ns.db.auctionHabits[key] then
            ns.AuctionLearning:Forget(key)
            ns:Print("Forgot auction habits for " .. rest .. ".", true)
        else
            ns:Print("Nothing learned about " .. rest .. ".", true)
        end
    elseif cmd == "undercut" and rest:lower() == "off" then
        ns.Value:SetUndercutOn(false)
        ns:Print("Undercut off: price matching, 1 below Auctionator's price.", true)
    elseif cmd == "undercut" and rest:match("^%d+%.?%d*%s*%%?$") then
        local n, pct = rest:match("^(%d+%.?%d*)%s*(%%?)$")
        ns.Value:SetUndercut(tonumber(n), pct == "%" and "percent" or "copper")
        ns:Print("Undercut set to " .. ns.Value:DescribeUndercut() .. ".", true)
    else
        Help()
    end
end

SLASH_WALLY1 = "/wally"
SLASH_WALLY2 = "/junk"
SlashCmdList.WALLY = function(msg)
    msg = ns.Trim(msg)
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "" then
        if ns.UI then ns.UI:Toggle() end
    elseif cmd == "add" and rest ~= "" then
        ns.Lists:Add("inclusions", rest, "manual")
    elseif cmd == "never" and rest ~= "" then
        ns.Lists:Add("exclusions", rest, "manual")
    elseif cmd == "remove" and rest ~= "" then
        local key = ns.Lists:Resolve(rest)
        if key and (ns.Lists:Remove("inclusions", key) or ns.Lists:Remove("exclusions", key)) then
            ns:Print("Removed " .. rest .. ".", true)
        else
            ns:Print(rest .. " is not on a list.", true)
        end
    elseif cmd == "rule" and rest ~= "" then
        ns.Lists:AddPattern("include", rest)
    elseif cmd == "keeprule" and rest ~= "" then
        ns.Lists:AddPattern("exclude", rest)
    elseif cmd == "config" or cmd == "settings" or cmd == "options" then
        ns.UI:OpenSettings()
    elseif cmd == "history" then
        ns.UI:OpenSettings("history")
    elseif cmd == "sell" then
        ns.Seller:Start(false)
    elseif cmd == "sort" then
        if rest:lower() == "config" or rest:lower() == "options" then ns.UI:OpenSettings("sorting")
        elseif rest:lower() == "bank" then ns.Sorter:Start("bank")
        else ns.Sorter:Start("bags") end
    elseif cmd == "sortbank" then
        ns.Sorter:Start("bank")
    elseif cmd == "sortdebug" then
        ns.Sorter:RefreshButtons()
        ns.Sorter:Debug()
    elseif cmd == "forget" and rest ~= "" then
        local key = ns.Lists:Resolve(rest)
        if key and ns.db.habits[key] then
            ns.db.habits[key] = nil; ns:Changed()
            ns:Print("Forgot selling habits for " .. rest .. ".", true)
        else
            ns:Print("Nothing learned about " .. rest .. ".", true)
        end
    elseif cmd == "list" then
        local n = 0
        for _, e in pairs(ns.db.inclusions) do n = n + 1; ns:Print((e.link or e.name) .. " |cff888888(" .. (e.source or "manual") .. ")|r", true) end
        for _, p in ipairs(ns.db.patterns.include) do n = n + 1; ns:Print("Rule: name contains \"" .. p .. "\"", true) end
        if n == 0 then ns:Print("The junk list is empty.", true) end
    elseif cmd == "auction" or cmd == "auctions" or cmd == "ah" then
        AuctionCommand(rest)
    elseif cmd == "minimap" then
        ns:ToggleOption("char.minimap.hide")
    elseif cmd == "resetbutton" then
        ns.char.merchantButton = nil
        if ns.Merchant then ns.Merchant:UpdatePosition() end
        ns:Print("Merchant button position reset.", true)
    else
        Help()
    end
end

ns:Compartment()
