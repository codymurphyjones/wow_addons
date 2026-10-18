local addonName, ns = ...

ns.VERSION = "0.1.0"
ns.PREFIX = "|cff55d6beWealth Planner|r"
-- Built from the folder name so the path survives renaming the folder.
ns.ICON = "Interface\\AddOns\\" .. addonName .. "\\Media\\Icon"
ns.JOBS_ICON = "Interface\\AddOns\\" .. addonName .. "\\Media\\JobsIcon"     -- Jobs Board: minimap button, tracker
ns.INVEST_ICON = "Interface\\AddOns\\" .. addonName .. "\\Media\\InvestIcon" -- the auction house's Invest tab
ns.CALLER = "Wealth Planner" -- callerID for Auctionator.API.v1

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

-- Saved arrays are never merged by index: that would scramble their order.
local function Merge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = {}
                Merge(dst[k], v)
            elseif v[1] == nil then
                Merge(dst[k], v)
            end
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

function ns:Print(msg, force)
    if force or not self.db or self.db.options.chat then
        DEFAULT_CHAT_FRAME:AddMessage(self.PREFIX .. ": " .. tostring(msg))
    end
end

function ns.Trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

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
function ns.RealmKey() return (GetRealmName() or "?") .. "-" .. (UnitFactionGroup("player") or "?") end
function ns.CharKey() return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?") end

-- Short money for tables and charts: 12.4g, 35s, 8c.
-- Compact money with coin icons: at most two coins, zero coins left out ("12[g] 40[s]",
-- "35[s] 2[c]", "7[c]"); from 100 gold up, gold only.
local COIN = "%s|TInterface\\MoneyFrame\\UI-%sIcon:0:0:2:0|t"
function ns.Gold(c)
    if not c then return "-" end
    local neg = c < 0 and "-" or ""
    c = math.floor(math.abs(c) + 0.5)
    local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local parts = {}
    if g > 0 then
        parts[1] = COIN:format(BreakUpLargeNumbers and BreakUpLargeNumbers(g) or g, "Gold")
        if g < 100 and s > 0 then parts[2] = COIN:format(s, "Silver") end
    elseif s > 0 then
        parts[1] = COIN:format(s, "Silver")
        if cp > 0 then parts[2] = COIN:format(cp, "Copper") end
    else
        parts[1] = COIN:format(cp, "Copper")
    end
    return neg .. table.concat(parts, " ")
end

-- Signed percent with a colour: green up, red down.
function ns.Pct(x)
    if not x then return "|cff8fa3b3-|r" end
    local color = x > 0.005 and "|cff59f28c" or x < -0.005 and "|cffd9736b" or "|cffcccccc"
    return ("%s%+.0f%%|r"):format(color, x * 100)
end

-- Coalesce change notifications from many edits into one refresh next frame.
local pending
function ns:Changed()
    if pending then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
        if ns.Tracker and ns.Tracker.Refresh then ns.Tracker:Refresh() end
        if ns.MapPins and ns.MapPins.Refresh then ns.MapPins:Refresh() end
        if ns.InvestTab and ns.InvestTab.Refresh then ns.InvestTab:Refresh() end
    end)
end

local frame = CreateFrame("Frame")
ns.EventFrame = frame
local handlers = {}
function ns:On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        pcall(frame.RegisterEvent, frame, event)
    end
    table.insert(handlers[event], fn)
end
frame:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event] or {}) do fn(...) end
end)

function ns:OnLoad(fn)
    self.onLoad = self.onLoad or {}
    table.insert(self.onLoad, fn)
end

ns:On("ADDON_LOADED", function(name)
    if name ~= addonName then return end
    WealthPlannerDB = Merge(WealthPlannerDB or {}, ns.DEFAULTS)
    WealthPlannerCharDB = Merge(WealthPlannerCharDB or {}, ns.CHAR_DEFAULTS)
    ns.db, ns.char = WealthPlannerDB, WealthPlannerCharDB
    for _, fn in ipairs(ns.onLoad or {}) do fn() end
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
        ns.char.minimap.hide = not ns.char.minimap.hide
        if ns.MinimapButton then ns.MinimapButton:Refresh() end
    elseif cmd == "quit" or cmd == "stop" then
        if ns.Jobs then ns.Jobs:Take(nil) end
    else
        Help()
    end
end

function WealthPlanner_OnCompartmentClick()
    if ns.UI then ns.UI:Show() end
end
