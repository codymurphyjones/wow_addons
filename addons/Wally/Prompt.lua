local _, ns = ...

-- One-at-a-time popups: "you keep selling X, is it junk?" and "you bought back junk X, keep it?"
local Prompt = {}
ns.Prompt = Prompt

local queue = {}
local showing = false

-- Asked in Wally's own popup (W.Ask), never the game's StaticPopup frames: an addon's popup there
-- taints them, and the game's next dialog in that frame gets blocked ("The game forbade Wally's
-- call to PurchaseBankTab()" when buying a bank tab).
local BLUE = "|cff55d6beWally|r"
local function Done() showing = false; C_Timer.After(0.2, function() Prompt:Next() end) end

local function AskLearn(key, link, times)
    ns.Widgets.Ask({
        text = ("%s noticed you keep selling %s\n(%s times so far).\n\nTreat it as junk from now on?"):format(BLUE, link, times),
        buttons = {
            { "Yes, it's junk", function() ns.Lists:Add("inclusions", link or key, "learned") end },
            { "Ask later", function() ns.Learning:Snooze(key) end },
            { "Never sell", function() ns.Lists:Add("exclusions", link or key, "manual") end },
        },
        onCancel = function() ns.Learning:Snooze(key) end,
        onHide = Done,
    })
end

local function AskBuyback(key, link)
    ns.Widgets.Ask({
        text = ("You bought back %s, which is on your %s Junk List.\n\nStop selling it?"):format(link, BLUE),
        buttons = {
            { "Never sell", function() ns.Lists:Add("exclusions", link or key, "manual") end },
            { "Keep as junk" },
            { "Remove from list", function()
                ns.Lists:Remove("inclusions", key)
                ns:Print(link .. " removed from the Junk List.", true)
            end },
        },
        onHide = Done,
    })
end

local function AskAuction(key, link, times)
    ns.Widgets.Ask({
        text = ("%s noticed you keep auctioning %s\n(%s times so far).\n\nAdd it to your Auction List so Wally posts it for you?"):format(BLUE, link, times),
        buttons = {
            { "Yes, auction it", function() ns.Lists:Add("auctionList", link or key, "learned") end },
            { "Ask later", function() ns.AuctionLearning:Snooze(key) end },
            { "Never auction", function() ns.Lists:Add("neverAuction", link or key, "manual") end },
        },
        onCancel = function() ns.AuctionLearning:Snooze(key) end,
        onHide = Done,
        wide = true,
    })
end

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
        AskLearn(q.key, h.link or h.name or q.key, tostring(h.sold or 0))
    elseif q.kind == "auction" then
        local h = ns.db.auctionHabits[q.key]
        if not h or ns.db.auctionList[q.key] or ns.db.neverAuction[q.key] then return self:Next() end
        showing = true
        AskAuction(q.key, h.link or h.name or q.key, tostring(h.posted or 0))
    else
        local e = ns.db.inclusions[q.key]
        if not e then return self:Next() end
        showing = true
        AskBuyback(q.key, e.link or e.name or q.key)
    end
end

ns:On("PLAYER_REGEN_ENABLED", function() Prompt:Next() end)
