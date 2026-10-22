local _, ns = ...

-- Clock: local and/or server time, 12 or 24 hour, session length.
local T = SimplePanel.Theme
local loginTime = time()

local function Format(h, m, s, p)
    local suffix = ""
    if not p:Get("hour24") then
        suffix = h >= 12 and " pm" or " am"
        h = h % 12
        if h == 0 then h = 12 end
    end
    if p:Get("seconds") and s then return ("%d:%02d:%02d%s"):format(h, m, s, suffix) end
    return ("%d:%02d%s"):format(h, m, suffix)
end

local function Local(p)
    local t = date("*t")
    return Format(t.hour, t.min, t.sec, p)
end

local function Server(p)
    local h, m = ns.Compat.ServerTime()
    return Format(h, m, nil, p)
end

local DURATION = { days = false }
local function Duration(secs) return ns.Format.Duration(secs, DURATION) end

SimplePanel.RegisterPlugin({
    id = "Clock",
    name = "Clock",
    category = "Information",
    icon = 134376,
    zone = "right",
    label = "Time",
    showIcon = false,
    defaults = { mode = "local", hour24 = true, seconds = false },
    interval = 1,

    text = function(p)
        local mode = p:Get("mode")
        if mode == "server" then return Server(p) end
        if mode == "both" then return { { text = Local(p) }, { text = Server(p), color = T.muted } } end
        return Local(p)
    end,

    tooltip = function(p, tt)
        tt:AddDouble("Local time", Local(p))
        tt:AddDouble("Server time", Server(p))
        tt:AddDouble("Date", date("%A %d %B"))
        tt:AddDivider()
        tt:AddDouble("This session", Duration(time() - loginTime))
        tt:AddHint("Click: stopwatch and alarm")
    end,

    menu = function(p, m)
        m:Header("Show")
        for _, o in ipairs({ { "local", "Local time" }, { "server", "Server time" }, { "both", "Both" } }) do
            m:Radio({ text = o[2], value = o[1], get = function() return p:Get("mode") end, set = function(v) p:Set("mode", v) end })
        end
        m:Divider()
        m:Checkbox({ text = "24-hour clock", get = function() return p:Get("hour24") end, set = function(v) p:Set("hour24", v) end })
        m:Checkbox({ text = "Seconds", get = function() return p:Get("seconds") end, set = function(v) p:Set("seconds", v) end })
    end,

    onClick = function(p, button)
        if button ~= "LeftButton" then return end
        if not TimeManagerFrame and UIParentLoadAddOn then pcall(UIParentLoadAddOn, "Blizzard_TimeManager") end
        if TimeManager_Toggle then TimeManager_Toggle() end
    end,
})
