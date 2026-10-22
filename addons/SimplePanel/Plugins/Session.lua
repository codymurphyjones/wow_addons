local _, ns = ...

-- Session: this login at a glance: time played, gold and XP per hour, kills and deaths, each with a
-- small chart.
local T = SimplePanel.Theme
local C = ns.Compat

local start = time()
local startMoney, lastXP, lastMax
local xpGained, kills, deaths = 0, 0, 0

local function Elapsed() return math.max(1, time() - start) end
local function Hours() return math.max(Elapsed(), 60) / 3600 end
local function Gold() return GetMoney() - (startMoney or GetMoney()) end

local DURATION = { days = false }
local function Duration(secs) return ns.Format.Duration(secs, DURATION) end

local function Short(v) return ns.Format.Short(v) end

local function TrackXP()
    local xp, max = UnitXP("player"), UnitXPMax("player")
    if lastXP then
        if xp >= lastXP and max == lastMax then xpGained = xpGained + (xp - lastXP)
        elseif xp < lastXP then xpGained = xpGained + (lastMax - lastXP) + xp end
    end
    lastXP, lastMax = xp, max
end

-- Kills: WoW Forever gives addons no combat log, so a kill is counted from its experience message
-- ("Kobold Vermin dies, you gain 45 experience.", with or without a group bonus). Kills that give no
-- experience (grey mobs, players) aren't counted.
local KILL_XP = (function()
    local s = COMBATLOG_XPGAIN_FIRSTPERSON or "%s dies, you gain %d experience."
    s = s:gsub("%.$", ""):gsub("([%(%)%.%[%]%*%+%-%?%^%$])", "%%%1")
    return "^" .. s:gsub("%%s", ".+"):gsub("%%d", "%%d+")
end)()

local function MoneyText(copper)
    return (copper < 0 and "-" or "+") .. C.ShortMoney(math.abs(copper)):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

SimplePanel.RegisterPlugin({
    id = "Session",
    name = "Session",
    category = "Information",
    icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    zone = "left",
    defaultEnabled = false,
    showIcon = false,
    defaults = { show = "time" },
    interval = 30,
    series = { gold = { max = 240, minInterval = 60 }, xp = { max = 240, minInterval = 60 } },
    chartRanges = { "session" },

    onInit = function(p)
        startMoney = GetMoney()
        TrackXP()
        p:On("PLAYER_XP_UPDATE", TrackXP)
        p:On("PLAYER_DEAD", function() deaths = deaths + 1; p:Refresh() end)
        p:On("CHAT_MSG_COMBAT_XP_GAIN", function(_, _, msg)
            if type(msg) == "string" and msg:find(KILL_XP) then kills = kills + 1 end
        end)
        p:Every(60, function()
            p:Record("gold", Gold() / 10000)
            p:Record("xp", xpGained)
        end)
    end,

    text = function(p)
        local show = p:Get("show")
        if show == "gold" then
            local g = Gold()
            return { { text = MoneyText(g / Hours()) .. "/h", color = g >= 0 and T.green or T.red } }
        elseif show == "xp" then
            return { { text = Short(xpGained / Hours()) .. " XP/h", color = T.accent } }
        end
        return Duration(Elapsed())
    end,

    tooltip = function(p, tt)
        local g = Gold()
        tt:AddDouble("Playing for", Duration(Elapsed()), nil, T.text)
        tt:AddDouble("Gold", MoneyText(g), nil, g >= 0 and T.green or T.red)
        tt:AddDouble("Gold per hour", MoneyText(g / Hours()), nil, g >= 0 and T.green or T.red)
        tt:AddDouble("XP gained", Short(xpGained), nil, T.text)
        tt:AddDouble("XP per hour", Short(xpGained / Hours()), nil, T.accent)
        tt:AddDouble("Kills", tostring(kills), nil, T.text)
        tt:AddDouble("Deaths", tostring(deaths), nil, deaths > 0 and T.red or T.text)
        local gold = p:Values("gold")
        if #gold > 2 then
            tt:AddSpacer(4)
            tt:AddChart({ type = "area", title = "Gold this session", hover = false, zero = false,
                series = { { name = "Gold", values = gold, color = T.yellow } } }, 220, 60)
        end
        tt:AddHint("Click: chart  ·  Right-click: options")
    end,

    chart = function(p)
        return { type = "line", legend = true, xFormat = function(x) return date("%H:%M", x) end,
            series = { { name = "Gold (g)", points = p:Points("gold"), color = T.yellow },
                { name = "XP", points = p:Points("xp"), color = T.accent } },
            footer = ("Session: %s, %s XP, %d kills, %d deaths"):format(Duration(Elapsed()), Short(xpGained), kills, deaths) }
    end,

    menu = function(p, m)
        m:Header("On the bar")
        for _, v in ipairs({ { "time", "Time played" }, { "gold", "Gold per hour" }, { "xp", "XP per hour" } }) do
            m:Radio({ text = v[2], value = v[1], get = function() return p:Get("show") end, set = function(x) p:Set("show", x) end })
        end
        m:Button({ text = "Start a new session", fn = function()
            start, startMoney, xpGained, kills, deaths = time(), GetMoney(), 0, 0, 0
            wipe(p:Series("gold")); wipe(p:Series("xp")); p:Refresh()
        end })
    end,

    onClick = function(p, button) if button == "LeftButton" then p:ShowChart() end end,
})
