local _, ns = ...

-- Speed: how fast you're moving, as a percentage of normal run speed, with a sparkline.
local T = SimplePanel.Theme

local BASE = BASE_MOVEMENT_SPEED or 7

local function Speeds()
    if not GetUnitSpeed then return 0, 0, 0, 0 end
    local current, run, flight, swim = GetUnitSpeed("player")
    return current or 0, run or 0, flight or 0, swim or 0
end

local function Pct(v) return math.floor(v / BASE * 100 + 0.5) end

SimplePanel.RegisterPlugin({
    id = "Speed",
    name = "Speed",
    category = "Information",
    icon = "Interface\\Icons\\Ability_Rogue_Sprint",
    zone = "right",
    defaultEnabled = false,
    showIcon = false,
    defaults = { idleRun = true },
    interval = 0.5,
    series = { speed = { max = 120, minInterval = 1 } },
    spark = "speed",

    onInit = function(p) p:Every(1, function() p:Record("speed", Pct((Speeds()))) end) end,

    text = function(p)
        local current, run = Speeds()
        if current == 0 and p:Get("idleRun") then return { { text = Pct(run) .. "%", color = T.muted } } end
        return { { text = Pct(current) .. "%", color = current > BASE * 1.01 and T.green or (current > 0 and current < BASE * 0.99 and T.yellow or nil) } }
    end,

    tooltip = function(_, tt)
        local current, run, flight, swim = Speeds()
        tt:AddDouble("Moving now", Pct(current) .. "%", nil, T.text)
        tt:AddDouble("Running", Pct(run) .. "%", nil, T.muted)
        if swim > 0 then tt:AddDouble("Swimming", Pct(swim) .. "%", nil, T.muted) end
        if flight > 0 and flight ~= run then tt:AddDouble("Flying", Pct(flight) .. "%", nil, T.muted) end
        tt:AddHint("Right-click: options")
    end,

    menu = function(p, m)
        m:Checkbox({ text = "Show run speed while standing", get = function() return p:Get("idleRun") end, set = function(v) p:Set("idleRun", v) end,
            tooltip = "Otherwise it reads 0% when you stand still." })
    end,
})
