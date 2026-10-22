local _, ns = ...

-- Options > AddOns > Wealth Planner: job estimates, map pins, the tracker, price history, the
-- investment target and the minimap button. Built with the shared OptionsPage.lua (addons/shared):
-- the window's Settings page, the auction house's Invest tab and /wp change the same options
-- (ns:SetOption), so every UI shows the same value.
local S = {}
ns.Settings = S

local function Jobs() if ns.Jobs then ns.Jobs:Invalidate() end end
local function Record() if ns.Invest then ns.Invest:Record() end end

S.page = ns.NewOptionsPage({ name = "Wealth Planner", build = function(p)
    p:Header("Jobs")
    p:Slider({ path = "db.options.killRate", label = "Kills an hour at your level", min = 10, max = 400, step = 5, apply = Jobs,
        format = function(v) return ("%d kills"):format(v) end,
        tooltip = "How fast you kill mobs of your own level (lower it if you play slowly). Job pay is estimated from it until you've worked the job yourself." })
    p:Slider({ path = "db.options.levelAbove", label = "Show mobs up to", min = 0, max = 10, step = 1, apply = Jobs,
        format = function(v) return ("%d levels over you"):format(v) end,
        tooltip = "Jobs with mobs higher than this aren't posted on the board." })

    p:Header("On the job")
    p:Check({ path = "db.options.mapPins", label = "Mark the job's spots on the world map" })
    p:Check({ path = "db.options.minimapPins", label = "Mark the job's spots on the minimap" })
    p:Check({ path = "db.options.tracker", label = "Show the job tracker",
        tooltip = "A small window with the shift's time, loot and pay per hour. The way to the spots is the Waypoint addon's arrow." })
    p:Check({ path = "char.minimap.hide", invert = true, label = "Show the minimap button",
        tooltip = "The Jobs Board minimap button (/wp minimap).",
        apply = function() if ns.MinimapButton then ns.MinimapButton:Refresh() end end })

    p:Header("Market")
    p:Slider({ path = "db.options.historyDays", label = "Keep price history for", min = 30, max = 365, step = 5, apply = Jobs,
        format = function(v) return ("%d days"):format(v) end,
        tooltip = "Older days are dropped at login." })
    p:Check({ path = "db.options.alerts", label = "Chat alerts for watched prices",
        tooltip = "When a scan sees a watched item cross the buy or sell price you set on its chart." })
    p:Check({ path = "db.options.chat", label = "Print messages in chat" })
    p:Check({ path = "db.options.betaCrash", label = "Use Beta Crash Monitoring",
        apply = function() if ns.Analytics then ns.Analytics:Invalidate() end end,
        tooltip = ("The beta goes offline at the start of %s. The Invest tool plans around it: prices are expected to slide as players cash out, "
            .. "crashes to hold rather than recover, selling plans end by then, and nothing is suggested that can't be resold in time."):format(
            date("%a %m/%d", ns.BETA_END)) })

    p:Header("Investing")
    p:Slider({ path = "db.options.investTarget", label = "Keep invested", min = 0, max = 100, step = 1, apply = Record,
        format = function(v) return ("%d%% of wealth"):format(v) end,
        tooltip = "The share of your wealth (gold + goods + auctions) Wealth Planner keeps invested in goods and auctions." })
    p:Slider({ path = "db.options.cashReserve", label = "Cash reserve", min = 0, max = 1000, step = 1, apply = Record,
        format = function(v) return ("%d gold"):format(v) end,
        tooltip = "The least gold you want to keep on hand, for repairs, training and travel. It's a floor you set, not gold you have: only cash above it is free to invest, and while you're under it the Invest tab says by how much." })
    p:Slider({ path = "db.options.maxPerItem", label = "Most per item", min = 1, max = 100, step = 1, apply = Record,
        format = function(v) return ("%d%% of wealth"):format(v) end,
        tooltip = "No single item takes more than this share of your wealth, so one bad call can't sink you." })
end })

function S:Open() return self.page:Open() end
