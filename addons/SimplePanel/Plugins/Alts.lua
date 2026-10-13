local _, ns = ...

-- Alts: every character on the account at a glance: level and XP, rested XP (still growing while
-- they're logged out), where they are, when you last played them and their gold.
local T = SimplePanel.Theme
local C = ns.Compat
local Chars = ns.Characters

local SORTS = {
    { "level", "Level", function(a, b) return (a.info.level or 0) > (b.info.level or 0) end },
    { "name", "Name", function(a, b) return Chars.Name(a.key) < Chars.Name(b.key) end },
    { "seen", "Last played", function(a, b) return (a.info.seen or 0) > (b.info.seen or 0) end },
    { "gold", "Gold", function(a, b) return (a.info.copper or 0) > (b.info.copper or 0) end },
}

local function MaxLevel()
    return (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or MAX_PLAYER_LEVEL or 60
end

local function List(p)
    local list = Chars:All(p:Get("scope"))
    local by = SORTS[1][3]
    for _, s in ipairs(SORTS) do if s[1] == p:Get("sort") then by = s[3] end end
    table.sort(list, by)
    return list
end

local function AddEntries(p, m)
    m:Header("Sort by")
    for _, s in ipairs(SORTS) do
        m:Radio({ text = s[2], value = s[1], get = function() return p:Get("sort") end, set = function(v) p:Set("sort", v) end })
    end
    m:Submenu({ text = "Characters", build = function(sub)
        for _, s in ipairs(Chars.SCOPES) do
            sub:Radio({ text = s[2], value = s[1], get = function() return p:Get("scope") end, set = function(v) p:Set("scope", v) end })
        end
    end })
    m:Checkbox({ text = "XP bars", get = function() return p:Get("xpBars") end, set = function(v) p:Set("xpBars", v) end })
    m:Submenu({ text = "Forget a character", build = function(sub)
        local keys = {}
        for key in pairs(ns.db.characters) do if key ~= ns.CharKey() then keys[#keys + 1] = key end end
        table.sort(keys)
        if #keys == 0 then sub:Header("No other characters") end
        for _, key in ipairs(keys) do
            sub:Button({ text = key, fn = function() Chars:Forget(key); p:Print("forgot " .. key .. "."); p:Refresh() end })
        end
    end })
end

SimplePanel.RegisterPlugin({
    id = "Alts",
    name = "Alts",
    category = "Character",
    icon = "Interface\\Icons\\INV_Misc_GroupNeedMore",
    zone = "left",
    label = "Alts",
    showLabel = true,
    defaultEnabled = false,
    defaults = { sort = "level", scope = "realm", xpBars = true },
    events = { "PLAYER_LEVEL_UP", "PLAYER_MONEY" },

    text = function(p)
        return tostring(math.max(0, #Chars:All(p:Get("scope")) - 1))
    end,

    tooltip = function(p, tt)
        local list = List(p)
        local total, max = 0, MaxLevel()
        for i, e in ipairs(list) do
            local info = e.info
            if i > 1 then tt:AddSpacer(3) end
            local name = Chars.ClassName(e.key, info) .. (info.level and (" |cffffffff" .. info.level .. "|r") or "")
            if e.key == ns.CharKey() then name = name .. " |cff8fa3b3(you)|r" end
            tt:AddDouble(name, C.Money(info.copper or 0), nil, T.text)
            local rested = Chars:Rested(e.key, info)
            local where = info.subzone and info.zone and info.subzone ~= info.zone and (info.subzone .. " (" .. info.zone .. ")") or info.zone or "?"
            local right = (e.key == ns.CharKey() and "now" or Chars.Ago(info.seen))
            if info.level and info.level < max and info.xpMax and info.xpMax > 0 and rested > 0 then
                right = ("+%d%% rested  ·  %s"):format(rested / info.xpMax * 100, right)
            end
            local played = Chars:Played(e.key, info)
            if played then right = right .. ("  ·  %dd %dh played"):format(played / 86400, played / 3600 % 24) end
            tt:AddDouble("|cff8fa3b3" .. where .. "|r", right, T.muted, T.muted)
            if p:Get("xpBars") and info.level and info.level < max and info.xpMax and info.xpMax > 0 then
                tt:AddBar(info.xp or 0, info.xpMax, T.accent)
            end
            total = total + (info.copper or 0)
        end
        if #list > 1 then
            tt:AddDivider()
            tt:AddDouble("Total gold", C.Money(total), T.accent, T.accent)
        end
        tt:AddHint("Click: sort and filter  ·  Right-click: options")
    end,

    menu = AddEntries,

    onClick = function(p, button)
        if button ~= "LeftButton" then return end
        local m = ns.Menu:New(p.button)
        m:Title("Alts", p.icon)
        AddEntries(p, m)
        m:Show(p.button)
    end,
})
