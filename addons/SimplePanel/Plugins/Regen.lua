local _, ns = ...

-- Regen: health and mana regained per second, measured once a second over the last few seconds.
-- For mana users it follows the five-second rule: casting starts a countdown, and the tooltip keeps
-- regen while casting apart from full regen.
local T = SimplePanel.Theme

local WINDOW = 6         -- seconds averaged (Classic regen ticks every 2 s)
local FIVE = 5           -- the five-second rule

local hpSamples, mpSamples = {}, {}
local lastHP, lastMP, lastSpend
local castingRate, fullRate
local inCombat, combatMana, lastCombatMana = false, 0, nil

local function UsesMana() return (UnitPowerType("player")) == 0 end

local function Push(list, v)
    list[#list + 1] = v
    if #list > WINDOW then table.remove(list, 1) end
end

local function Average(list)
    if #list == 0 then return 0 end
    local sum = 0
    for _, v in ipairs(list) do sum = sum + v end
    return sum / #list
end

local function SinceSpend() return lastSpend and (GetTime() - lastSpend) or math.huge end

-- Mana dropping means a spell was cast: the five-second rule starts over.
local function OnPower(_, _, unit, kind)
    if unit ~= "player" or (kind and kind ~= "MANA") then return end
    local mp = UnitPower("player", 0)
    if lastMP and mp < lastMP then lastSpend = GetTime() end
end

local function Sample(p)
    local hp, mp = UnitHealth("player"), UnitPower("player", 0)
    local hpMax, mpMax = UnitHealthMax("player"), UnitPowerMax("player", 0)
    if lastHP then Push(hpSamples, (hp > lastHP and hp < hpMax + 1) and (hp - lastHP) or 0) end
    if lastMP and UsesMana() then
        local gain = mp > lastMP and (mp - lastMP) or 0
        if mp < lastMP then lastSpend = GetTime() end
        Push(mpSamples, gain)
        if inCombat then combatMana = combatMana + gain end
        -- Keep the two kinds of mana regen apart, ignoring seconds spent already full.
        if mp < mpMax then
            local rate = Average(mpSamples)
            if SinceSpend() < FIVE then castingRate = rate else fullRate = rate end
        end
    end
    lastHP, lastMP = hp, mp
    p:Record("hp", Average(hpSamples))
    if UsesMana() then p:Record("mana", Average(mpSamples)) end
end

local function Rate(p, value, max)
    if p:Get("percent") then return ("%.1f%%/s"):format(max > 0 and value / max * 100 or 0) end
    return ("%d/s"):format(math.floor(value + 0.5))
end

local function AddEntries(p, m)
    m:Checkbox({ text = "Show health regen", get = function() return p:Get("showHP") end, set = function(v) p:Set("showHP", v) end })
    m:Checkbox({ text = "Show mana regen", get = function() return p:Get("showMana") end, set = function(v) p:Set("showMana", v) end,
        disabled = function() return not UsesMana() end })
    m:Checkbox({ text = "As a percentage of the maximum", get = function() return p:Get("percent") end, set = function(v) p:Set("percent", v) end })
    m:Checkbox({ text = "Five-second rule countdown", get = function() return p:Get("fiveSecond") end, set = function(v) p:Set("fiveSecond", v) end,
        tooltip = "After you spend mana, regen slows for five seconds. This counts them down on the bar.",
        disabled = function() return not UsesMana() end })
end

SimplePanel.RegisterPlugin({
    id = "Regen",
    name = "Regen",
    category = "Character",
    icon = "Interface\\Icons\\Spell_Nature_Rejuvenation",
    zone = "left",
    defaultEnabled = false,
    defaults = { showHP = true, showMana = true, percent = false, fiveSecond = true },
    interval = 1,
    series = { hp = { max = 300, minInterval = 1 }, mana = { max = 300, minInterval = 1 } },
    spark = "mana",
    chartRanges = { "1m", "5m" },

    onInit = function(p)
        p:Every(1, Sample)
        p:On("UNIT_POWER_UPDATE", OnPower)
        p:On("PLAYER_REGEN_DISABLED", function() inCombat, combatMana = true, 0 end)
        p:On("PLAYER_REGEN_ENABLED", function() inCombat, lastCombatMana = false, combatMana end)
    end,

    text = function(p)
        local segs = {}
        if p:Get("showHP") then
            segs[#segs + 1] = { text = "HP " .. Rate(p, Average(hpSamples), UnitHealthMax("player")), color = T.green }
        end
        if UsesMana() and p:Get("showMana") then
            segs[#segs + 1] = { text = "MP " .. Rate(p, Average(mpSamples), UnitPowerMax("player", 0)), color = T.blue }
            local left = FIVE - SinceSpend()
            if p:Get("fiveSecond") and left > 0 then segs[#segs + 1] = { text = math.ceil(left) .. "s", color = T.muted } end
        end
        if #segs == 0 then segs[1] = { text = "Regen", color = T.muted } end
        return segs
    end,

    tooltip = function(p, tt)
        local hp, hpMax = UnitHealth("player"), UnitHealthMax("player")
        tt:AddDouble("Health", ("%d / %d"):format(hp, hpMax), nil, T.text)
        tt:AddBar(hp, hpMax, T.green)
        tt:AddDouble("Health regen", Rate(p, Average(hpSamples), hpMax), nil, T.green)
        if UsesMana() then
            local mp, mpMax = UnitPower("player", 0), UnitPowerMax("player", 0)
            tt:AddSpacer(4)
            tt:AddDouble("Mana", ("%d / %d"):format(mp, mpMax), nil, T.text)
            tt:AddBar(mp, mpMax, T.blue)
            tt:AddDouble("Mana regen now", Rate(p, Average(mpSamples), mpMax), nil, T.blue)
            tt:AddDouble("While casting", castingRate and Rate(p, castingRate, mpMax) or "?", nil, T.muted)
            tt:AddDouble("Outside the five seconds", fullRate and Rate(p, fullRate, mpMax) or "?", nil, T.muted)
            if inCombat then tt:AddDouble("Mana regained this fight", tostring(combatMana))
            elseif lastCombatMana then tt:AddDouble("Mana regained last fight", tostring(lastCombatMana)) end
            local values = p:Values("mana", 60)
            if #values > 2 then
                tt:AddSpacer(4)
                tt:AddChart({ type = "line", title = "Mana per second", hover = false,
                    series = { { name = "Mana", values = values, color = T.blue } } }, 220, 60)
            end
        else
            tt:AddLine("No mana to track for this class.", T.muted)
        end
        tt:AddHint("Click: settings  ·  Right-click: options")
    end,

    chart = function(p, range)
        local secs = SimplePanel.RangeSeconds(range)
        local since = secs and (time() - secs) or nil
        local series = { { name = "Health", points = p:Points("hp", since), color = T.green } }
        if UsesMana() then series[2] = { name = "Mana", points = p:Points("mana", since), color = T.blue } end
        return { type = "line", series = series, legend = true,
            yFormat = function(v) return ("%d/s"):format(v) end, xFormat = function(x) return date("%H:%M:%S", x) end }
    end,

    menu = AddEntries,

    onClick = function(p, button)
        if button ~= "LeftButton" then return end
        local m = ns.Menu:New(p.button)
        m:Title("Regen", p.icon)
        AddEntries(p, m)
        m:Show(p.button)
    end,
})
