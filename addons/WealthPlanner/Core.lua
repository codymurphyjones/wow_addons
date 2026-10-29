local addonName, ns = ...

ns.VERSION = "0.1.2"
ns.PREFIX = "|cff55d6beWealth Planner|r"
-- Built from the folder name so the path survives renaming the folder.
ns.ICON = "Interface\\AddOns\\" .. addonName .. "\\Media\\Icon"
ns.JOBS_ICON = "Interface\\AddOns\\" .. addonName .. "\\Media\\JobsIcon"     -- Jobs Board: minimap button, tracker
ns.INVEST_ICON = "Interface\\AddOns\\" .. addonName .. "\\Media\\InvestIcon" -- the auction house's Invest tab
ns.CALLER = "Wealth Planner" -- callerID for Auctionator.API.v1

-- Events, saved variables, Print, Changed and timers: the shared Core.lua (addons/shared).
ns.SAVED = { db = "WealthPlannerDB", char = "WealthPlannerCharDB" }

ns.DEFAULTS = {
    options = {
        chat = true,
        historyDays = 120,   -- days of price history kept per item
        investTarget = 50,   -- % of your wealth to keep invested (goods and auctions)
        cashReserve = 5,     -- gold that's never counted as available to invest
        maxPerItem = 20,     -- % of your wealth any one item may take
        killRate = 90,       -- kills an hour on mobs of your own level
        levelAbove = 2,      -- jobs: mobs up to this many levels over you
        mapPins = true,
        minimapPins = true,
        tracker = true,
        alerts = true,       -- chat alert when a watched item crosses its target price
        betaCrash = false,   -- the beta goes offline at BETA_END: plan around it (ns.BetaDaysLeft)
    },
    realms = {},     -- "Realm-Faction" -> { items = { [itemID] = { d = { [day] = {lo, hi, c, q, n} }, s = { {t, p, q} }, t } } }
    watch = {},      -- itemID -> { added = time(), buy = copper|nil, sell = copper|nil }
    holdings = {},   -- "Name-Realm" -> { bags = { [itemID] = count }, bank = { ... }, bankSeen = time() }
    lots = {},       -- itemID -> { { qty, cost (per item), t, src = "ah"|"farm" } }, oldest first
    vendorBuy = {},  -- itemID -> what a vendor charges for one (copper), from merchant windows you opened
    ledger = {},     -- realized sales, newest first: { t, id, name, qty, gross, deposit, cut, cost }
    worth = {},      -- "Name-Realm" -> { [day] = copper (gold + holdings) }
    invested = {},   -- "Name-Realm" -> { [day] = % of wealth invested }
    sessions = {},   -- farming sessions, newest first (Session.lua)
    jobStats = {},   -- job key -> { secs, value, runs } measured on that job
    recipes = {},    -- "Name-Realm" -> { [profession] = { rank, max, list = { [productID] = { name, made, reagents, diff } } } }
    wealth = {},     -- "Name-Realm" -> { t, cash, goods, auctions, mail, total }: the latest breakdown
    worthLog = {},   -- "Name-Realm" -> { { time, total } }: intraday snapshots, the last day's
    deposits = {},   -- your auction posts and what became of their deposits, newest first (Deposits.lua)
    sentPlans = {},  -- plans sent to Quartermaster, newest first: { t, list, spend, gain, ideas = { ... } } (Invest.lua)
    recoveryAlerted = {}, -- itemID -> crash day already alerted as recovering (Recovery.lua)
}
ns.CHAR_DEFAULTS = {
    tracker = { point = "RIGHT", x = -60, y = 120 },
    minimap = { angle = 250, hide = false },
    trackedJob = nil, -- job Waypoint's arrow leads to (Nav.lua); nil follows the job you took
    activeJob = nil, -- key of the job you took (Jobs.lua)
    jobFilter = { kinds = { mob = true, herb = true, mine = true, skin = true, fish = true } },
}

-- Today as a whole number of UTC days; price history is kept per day.
function ns.Today() return math.floor(time() / 86400) end

-- The beta goes offline at the start of Wed 10/21/2026 (local time). With "Use Beta Crash
-- Monitoring" on, the Invest tool plans around it: prices are expected to slide as players cash
-- out, crashes to hold, and nothing is bought that can't be resold before then.
ns.BETA_END = time({ year = 2026, month = 10, day = 21, hour = 0, min = 0, sec = 0 })

-- Days (fractional) until the beta goes offline, or nil when the setting is off.
function ns.BetaDaysLeft()
    if not (ns.db and ns.db.options.betaCrash) then return nil end
    return math.max(0, (ns.BETA_END - time()) / 86400)
end

-- "3d 14h" left.
function ns.BetaLeftText()
    local d = ns.BetaDaysLeft()
    if not d then return nil end
    if d <= 0 then return "the beta is over" end
    local h = math.floor(d * 24)
    return h >= 24 and ("%dd %dh"):format(math.floor(h / 24), h % 24) or ("%dh"):format(h)
end

-- "Realm-Faction": auction houses are per realm and faction.
ns.RealmKey = ns.Units.ServerKey
-- This character: "Given Family" (shared Units.lua).
function ns.CharKey() return ns.Units.Me() end
-- This character's name as shown in lists: the full "Given Family" (UnitName alone gives only the
-- given name, which can't tell two characters apart).
function ns.CharName() return ns.Units.Short(ns.Units.CharKey()) or (UnitName("player")) end

-- Stores kept per character, under ns.CharKey(). Entries saved under an older key for this
-- character ("Name-Realm" with the realm's display name) move to the current one; run at load
-- and again at login (only the logged-in character can be mapped, so it runs every login).
local CHAR_STORES = { "holdings", "recipes", "invested", "worth", "worthLog", "wealth" }
local function MigrateCharKeys()
    if not ns.db then return end
    for _, k in ipairs(CHAR_STORES) do ns.Units.MigrateKeys(ns.db[k]) end
    -- The wealth entry says whose and which realm's it is (Portfolio's per-realm lists).
    local key = ns.Units.CharKey()
    local w = key and ns.db.wealth[key]
    if w and not w.realm then w.realm = ns.Units.RealmLabel() end
    if w then w.name = ns.CharName() end
    -- Entries saved before family names were shown kept only the given name: take the full name
    -- from the "Given Family" key.
    for k, e in pairs(ns.db.wealth or {}) do
        local full = type(k) == "string" and type(e) == "table" and ns.Units.KeyOf(k)
        if full and type(e.name) == "string" and full:find(" ", 1, true) and not e.name:find(" ", 1, true)
            and ns.Units.Same(full:match("^(%S+)"), e.name) then
            e.name = full
        end
    end
end
ns:OnLoad(MigrateCharKeys)
ns:On("PLAYER_LOGIN", MigrateCharKeys)

-- Compact money with coin icons: at most two coins, zero coins left out ("12[g] 40[s]",
-- "35[s] 2[c]", "7[c]"); from 100 gold up, gold only.
function ns.Gold(c) return ns.Format.Money(c, ns.Format.MONEY_GOLD) end

-- Signed percent with a colour: green up, red down.
local PCT = { decimals = 0, signed = true, colored = true, missing = "|cff8fa3b3-|r" }
function ns.Pct(x) return ns.Format.Pct(x, PCT) end

-- What a change refreshes (ns:Changed coalesces many edits into one refresh next frame).
ns:OnChanged(function()
    if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
    if ns.Tracker and ns.Tracker.Refresh then ns.Tracker:Refresh() end
    if ns.MapPins and ns.MapPins.Refresh then ns.MapPins:Refresh() end
    if ns.InvestTab and ns.InvestTab.Refresh then ns.InvestTab:Refresh() end
end)

ns:On("PLAYER_LOGIN", function()
    ns:Print("v" .. ns.VERSION .. " loaded. It's the Wealth tab in Wally's window, or type |cffffffff/wp|r.")
end)

local function Help()
    ns:Print("/wp - open the Wealth tab in Wally's window", true)
    ns:Print("/wp market | portfolio | insights | jobs | worklog - open that page", true)
    ns:Print("/wp invest - the Invest tab (at the auction house)", true)
    ns:Print("/wp scan - scan the whole auction house (at the auction house)", true)
    ns:Print("/wp watch <item> - add an item to your watchlist", true)
    ns:Print("/wp quit - quit the job you took", true)
    ns:Print("/wp minimap - show/hide the Jobs Board minimap button", true)
    ns:Print("/wp item <item> - print an item's price history", true)
end

local function ItemID(text)
    return tonumber(text) or ns.Compat.IDFromLink(text) or (text ~= "" and select(1, ns.Compat.GetItemInfoInstant(text))) or nil
end

SLASH_WEALTHPLANNER1 = "/wp"
SLASH_WEALTHPLANNER2 = "/wealth"
SlashCmdList.WEALTHPLANNER = function(msg)
    msg = ns.Trim(msg)
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "" then
        ns.UI:Toggle()
    elseif cmd == "invest" then
        if not (ns.InvestTab and ns.InvestTab:Select()) then ns:Print("The Invest tab is at the auction house.", true) end
    elseif cmd == "overview" or cmd == "market" or cmd == "portfolio" or cmd == "insights" or cmd == "jobs" or cmd == "worklog" then
        ns.UI:Show(cmd)
    elseif cmd == "farm" or cmd == "board" then
        ns.UI:Show("jobs")
    elseif cmd == "scan" then
        ns.Prices:ScanMarket()
    elseif cmd == "watch" then
        local id = ItemID(rest)
        if id then ns.Prices:Watch(id, true) else ns:Print("Usage: /wp watch <item link, name or ID>", true) end
    elseif cmd == "item" then
        local id = ItemID(rest)
        if id then ns.Prices:Debug(id) else ns:Print("Usage: /wp item <item link, name or ID>", true) end
    elseif cmd == "minimap" then
        ns:ToggleOption("char.minimap.hide")
    elseif cmd == "quit" or cmd == "stop" then
        if ns.Jobs then ns.Jobs:Take(nil) end
    else
        Help()
    end
end

ns:Compartment(function()
    if ns.UI then ns.UI:Show() end
end)
