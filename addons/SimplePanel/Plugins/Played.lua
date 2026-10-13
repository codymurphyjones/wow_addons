local _, ns = ...

-- Played: /played for this character, counting up live, and for every other character as of the
-- last time you played them. Asked quietly, so nothing is printed to chat.
local T = SimplePanel.Theme
local Chars = ns.Characters

local function Duration(secs)
    if not secs then return "?" end
    local d, h, m = math.floor(secs / 86400), math.floor(secs / 3600) % 24, math.floor(secs / 60) % 60
    if d > 0 then return ("%dd %dh"):format(d, h) end
    if h > 0 then return ("%dh %02dm"):format(h, m) end
    return ("%dm"):format(m)
end

SimplePanel.RegisterPlugin({
    id = "Played",
    name = "Played",
    category = "Information",
    icon = "Interface\\Icons\\INV_Misc_PocketWatch_02",
    zone = "left",
    defaultEnabled = false,
    showIcon = false,
    defaults = { show = "total", scope = "all" },
    events = { "TIME_PLAYED_MSG" },
    interval = 60,

    text = function(p)
        local me = Chars:Me()
        local total, level = me and Chars:Played(ns.CharKey(), me)
        if not total then return { { text = "Played ?", color = T.muted } } end
        return Duration(p:Get("show") == "level" and level or total)
    end,

    tooltip = function(p, tt)
        local list, sum = Chars:All(p:Get("scope")), 0
        table.sort(list, function(a, b) return (a.info.played or 0) > (b.info.played or 0) end)
        for _, e in ipairs(list) do
            local total, level = Chars:Played(e.key, e.info)
            if total then
                sum = sum + total
                local right = Duration(total)
                if e.key == ns.CharKey() then right = right .. " |cff8fa3b3(this level " .. Duration(level) .. ")|r" end
                tt:AddDouble(Chars.ClassName(e.key, e.info) .. (e.info.level and (" |cffffffff" .. e.info.level .. "|r") or ""), right, nil, T.text)
            else
                tt:AddDouble(Chars.ClassName(e.key, e.info), "log in to count", nil, T.muted)
            end
        end
        if #list > 1 then tt:AddDivider(); tt:AddDouble("All together", Duration(sum), T.accent, T.accent) end
        tt:AddHint("Click: ask again  ·  Right-click: options")
    end,

    menu = function(p, m)
        m:Header("On the bar")
        m:Radio({ text = "Total", value = "total", get = function() return p:Get("show") end, set = function(v) p:Set("show", v) end })
        m:Radio({ text = "This level", value = "level", get = function() return p:Get("show") end, set = function(v) p:Set("show", v) end })
        m:Submenu({ text = "Characters", build = function(sub)
            for _, s in ipairs(Chars.SCOPES) do
                sub:Radio({ text = s[2], value = s[1], get = function() return p:Get("scope") end, set = function(v) p:Set("scope", v) end })
            end
        end })
    end,

    onClick = function(_, button) if button == "LeftButton" then Chars:RequestPlayed() end end,
})
