local _, ns = ...

-- Gold: money on this character, the change this session, every character's gold, and history charts.
local T = SimplePanel.Theme
local C = ns.Compat
local Chars = ns.Characters
local sessionStart

local function Save() Chars:Refresh() end
local function ClassName(key, class) return Chars.ClassName(key, { class = class }) end

local function GoldFormat(v) return ("%sg"):format(SimplePanel.Chart.Format(v)) end

local SCOPES = Chars.SCOPES
local SCOPE_TITLE = { char = "This character", faction = "Characters on %s (%s)", realm = "Characters on %s", all = "All characters" }

-- The characters the plugin counts, richest first, and their total.
local function Characters(p)
    local list, total = Chars:All(p:Get("scope")), 0
    for _, e in ipairs(list) do total = total + (e.info.copper or 0) end
    table.sort(list, function(a, b) return (a.info.copper or 0) > (b.info.copper or 0) end)
    return list, total
end

SimplePanel.RegisterPlugin({
    id = "Gold",
    name = "Gold",
    category = "Character",
    icon = 133784,
    zone = "right",
    label = "Gold",
    defaults = { showSession = true, scope = "realm", barTotal = false },
    events = { "PLAYER_MONEY", "PLAYER_TRADE_MONEY", "TRADE_MONEY_CHANGED", "SEND_MAIL_MONEY_CHANGED" },
    series = {
        gold = { max = 2000, persist = "char", minInterval = 1800 }, -- one sample per half hour, ~6 weeks
        session = { max = 600, minInterval = 10 },
    },
    chartRanges = { "session", "24h", "7d", "30d" },

    onInit = function(p)
        -- allRealms (a checkbox) became the scope choice.
        local s = p:Settings()
        if s.allRealms ~= nil then
            if s.allRealms then s.scope = "all" end
            s.allRealms = nil
        end
        sessionStart = GetMoney()
        Save()
        p:Record("gold", GetMoney() / 10000)
        p:Record("session", GetMoney() / 10000)
        p:On("PLAYER_MONEY", function()
            Save()
            p:Record("gold", GetMoney() / 10000)
            p:Record("session", GetMoney() / 10000)
        end)
    end,

    text = function(p)
        local money = GetMoney()
        local shown = money
        if p:Get("barTotal") then
            Save()
            local _, total = Characters(p)
            shown = total
        end
        local segs = { { text = C.ShortMoney(shown) } }
        local delta = money - (sessionStart or money)
        if p:Get("showSession") and delta ~= 0 then
            segs[2] = { text = (delta > 0 and "+" or "-") .. C.ShortMoney(delta):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""),
                color = delta > 0 and T.green or T.red }
        end
        return segs
    end,

    tooltip = function(p, tt)
        local money = GetMoney()
        local delta = money - (sessionStart or money)
        tt:AddDouble("This character", C.Money(money), nil, T.text)
        tt:AddDouble("This session", (delta >= 0 and "+" or "-") .. C.Money(math.abs(delta)), nil, delta >= 0 and T.green or T.red)
        local list, total = Characters(p)
        if #list > 1 then
            local scope = p:Get("scope")
            tt:AddHeader(SCOPE_TITLE[scope]:format(GetRealmName(), UnitFactionGroup("player") or ""))
            for i, e in ipairs(list) do
                if i > 12 then break end
                local name = ClassName(e.key, e.info.class)
                if scope == "all" then name = name .. " |cff8fa3b3" .. (e.key:match("^(.-) %- ") or "") .. "|r" end
                tt:AddDouble(name, C.Money(e.info.copper or 0), T.text, T.text)
            end
            tt:AddDivider()
            tt:AddDouble("Total", C.Money(total), T.accent, T.accent)
        end
        local pts = p:Points("gold", time() - 7 * 86400)
        if #pts > 1 then
            tt:AddSpacer(4)
            tt:AddChart({ type = "area", title = "Last 7 days", yFormat = GoldFormat, hover = false,
                series = { { name = "Gold", points = pts, color = T.yellow } } }, 260, 80)
        end
        tt:AddHint("Click: gold chart  ·  Right-click: options")
    end,

    chart = function(p, range)
        local secs = SimplePanel.RangeSeconds(range)
        local name = range == "session" and "session" or "gold"
        local pts = p:Points(name, secs and (time() - secs) or nil)
        local first, last = pts[1], pts[#pts]
        local footer
        if first and last then
            local d = (last[2] - first[2]) * 10000
            footer = ("Change: %s%s"):format(d >= 0 and "|cff59f28c+" or "|cffd9736b-", C.Money(math.abs(d))) .. "|r"
        end
        return {
            type = "area", yFormat = GoldFormat, zero = false,
            xFormat = function(x) return date(range == "session" and "%H:%M:%S" or "%a %d %b %H:%M", x) end,
            xLabels = first and { date("%d %b %H:%M", first[1]), date("%d %b %H:%M", last[1]) } or nil,
            series = { { name = "Gold", points = pts, color = T.yellow } },
            footer = footer,
        }
    end,

    menu = function(p, m)
        m:Checkbox({ text = "Show this session's change", get = function() return p:Get("showSession") end, set = function(v) p:Set("showSession", v) end })
        m:Submenu({ text = "Characters", build = function(sub)
            for _, s in ipairs(SCOPES) do
                sub:Radio({ text = s[2], value = s[1], get = function() return p:Get("scope") end, set = function(v) p:Set("scope", v) end })
            end
        end })
        m:Checkbox({ text = "Bar shows their total", get = function() return p:Get("barTotal") end, set = function(v) p:Set("barTotal", v) end,
            tooltip = "Adds up the characters chosen above instead of showing this character's gold.",
            disabled = function() return p:Get("scope") == "char" end })
        m:Button({ text = "Reset session", fn = function() sessionStart = GetMoney(); wipe(p:Series("session")); p:Refresh() end })
        m:Submenu({ text = "Forget a character", build = function(sub)
            local keys = {}
            for key in pairs(ns.db.characters) do if key ~= ns.CharKey() then keys[#keys + 1] = key end end
            table.sort(keys)
            if #keys == 0 then sub:Header("No other characters") end
            for _, key in ipairs(keys) do
                sub:Button({ text = key, fn = function() Chars:Forget(key); p:Print("forgot " .. key .. ".") end })
            end
        end })
    end,

    -- The gold chart, like XP's (the Bags plugin opens the bags).
    onClick = function(p, button) if button == "LeftButton" and not IsModifierKeyDown() then p:ShowChart() end end,
})
