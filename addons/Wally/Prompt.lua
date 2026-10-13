local _, ns = ...

-- One-at-a-time popups: "you keep selling X, is it junk?" and "you bought back junk X, keep it?"
local Prompt = {}
ns.Prompt = Prompt

local queue = {}
local showing = false

StaticPopupDialogs["WALLY_LEARN"] = {
    text = "|cff55d6beWally|r noticed you keep selling %s\n(%s times so far).\n\nTreat it as junk from now on?",
    button1 = "Yes, it's junk",
    button2 = "Ask later",
    button3 = "Never sell",
    OnAccept = function(_, data) ns.Lists:Add("inclusions", data.link or data.key, "learned") end,
    OnCancel = function(_, data) ns.Learning:Snooze(data.key) end,
    OnAlt = function(_, data) ns.Lists:Add("exclusions", data.link or data.key, "manual") end,
    OnHide = function() showing = false; C_Timer.After(0.2, function() Prompt:Next() end) end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}

StaticPopupDialogs["WALLY_BUYBACK"] = {
    text = "You bought back %s, which is on your |cff55d6beWally|r Junk List.\n\nStop selling it?",
    button1 = "Never sell",
    button2 = "Keep as junk",
    button3 = "Remove from list",
    OnAccept = function(_, data) ns.Lists:Add("exclusions", data.link or data.key, "manual") end,
    OnAlt = function(_, data)
        ns.Lists:Remove("inclusions", data.key)
        ns:Print((data.link or data.key) .. " removed from the Junk List.", true)
    end,
    OnHide = function() showing = false; C_Timer.After(0.2, function() Prompt:Next() end) end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}

StaticPopupDialogs["WALLY_AUCTION_LEARN"] = {
    text = "|cff55d6beWally|r noticed you keep auctioning %s\n(%s times so far).\n\nAdd it to your Auction List so Wally posts it for you?",
    button1 = "Yes, auction it",
    button2 = "Ask later",
    button3 = "Never auction",
    OnAccept = function(_, data) ns.Lists:Add("auctionList", data.link or data.key, "learned") end,
    OnCancel = function(_, data) ns.AuctionLearning:Snooze(data.key) end,
    OnAlt = function(_, data) ns.Lists:Add("neverAuction", data.link or data.key, "manual") end,
    OnHide = function() showing = false; C_Timer.After(0.2, function() Prompt:Next() end) end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}

local function Enqueue(kind, key)
    for _, q in ipairs(queue) do if q.kind == kind and q.key == key then return end end
    queue[#queue + 1] = { kind = kind, key = key }
    Prompt:Next()
end

function Prompt:Queue(key)
    local h = ns.db.habits[key]
    if not h then return end
    if ns.db.options.autoAcceptLearned then
        ns.Lists:Add("inclusions", h.link or key, "learned", true)
        ns:Print((h.link or h.name or key) .. " learned as junk (sold " .. (h.sold or 0) .. " times).", true)
        return
    end
    h.pending = true
    Enqueue("learn", key)
end

function Prompt:QueueBuyback(key)
    Enqueue("buyback", key)
end

function Prompt:QueueAuction(key)
    local h = ns.db.auctionHabits[key]
    if not h then return end
    if ns.db.options.auction.autoAccept then
        ns.Lists:Add("auctionList", h.link or key, "learned", true)
        ns:Print((h.link or h.name or key) .. " learned for the Auction List (posted " .. (h.posted or 0) .. " times).", true)
        return
    end
    h.pending = true
    Enqueue("auction", key)
end

function Prompt:Next()
    if showing or InCombatLockdown() then return end
    local q = table.remove(queue, 1)
    if not q then return end
    if q.kind == "learn" then
        local h = ns.db.habits[q.key]
        if not h or ns.db.inclusions[q.key] or ns.db.exclusions[q.key] then return self:Next() end
        showing = true
        local dialog = StaticPopup_Show("WALLY_LEARN", h.link or h.name or q.key, tostring(h.sold or 0), { key = q.key, link = h.link })
        if not dialog then showing = false end
    elseif q.kind == "auction" then
        local h = ns.db.auctionHabits[q.key]
        if not h or ns.db.auctionList[q.key] or ns.db.neverAuction[q.key] then return self:Next() end
        showing = true
        local dialog = StaticPopup_Show("WALLY_AUCTION_LEARN", h.link or h.name or q.key, tostring(h.posted or 0), { key = q.key, link = h.link })
        if not dialog then showing = false end
    else
        local e = ns.db.inclusions[q.key]
        if not e then return self:Next() end
        showing = true
        local dialog = StaticPopup_Show("WALLY_BUYBACK", e.link or e.name or q.key, nil, { key = q.key, link = e.link })
        if not dialog then showing = false end
    end
end

ns:On("PLAYER_REGEN_ENABLED", function() Prompt:Next() end)
