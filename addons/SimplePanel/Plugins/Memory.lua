local _, ns = ...

-- Memory: total UI memory on the bar; per-add-on memory (or CPU, with profiling on) in the tooltip.
local T = SimplePanel.Theme
local C = ns.Compat

local function MB(kb) return kb >= 1024 and ("%.1f MB"):format(kb / 1024) or ("%d KB"):format(kb) end

-- Sorted { name, value } for every loaded add-on.
local function Usage(mode)
    local cpu = mode == "cpu" and C.CPUProfiling()
    if cpu then C.UpdateAddOnCPUUsage() else C.UpdateAddOnMemoryUsage() end
    local list, total = {}, 0
    for i = 1, C.GetNumAddOns() do
        local name, title = C.GetAddOnInfo(i)
        if name and C.IsAddOnLoaded(name) then
            local v = cpu and C.GetAddOnCPUUsage(i) or C.GetAddOnMemoryUsage(i)
            list[#list + 1] = { name = name, value = v }
            total = total + v
        end
    end
    table.sort(list, function(a, b) return a.value > b.value end)
    return list, total, cpu
end

-- One add-on's memory, and the whole heap (which includes Blizzard's UI).
local function Color(kb) return kb >= 100 * 1024 and T.red or (kb >= 30 * 1024 and T.yellow or nil) end
local function TotalColor(kb) return kb >= 600 * 1024 and T.red or (kb >= 300 * 1024 and T.yellow or nil) end

SimplePanel.RegisterPlugin({
    id = "Memory",
    name = "Memory",
    category = "Information",
    icon = 136031,
    zone = "right",
    label = "Mem",
    defaults = { mode = "memory", count = 15 },
    interval = 5,
    series = { total = { max = 360, minInterval = 5 } },
    spark = "total",
    chartRanges = { "5m", "15m", "session" },

    onInit = function(p)
        p:Every(5, function() p:Record("total", collectgarbage("count") / 1024) end)
        p:Record("total", collectgarbage("count") / 1024)
    end,

    text = function(p)
        local kb = collectgarbage("count")
        return { { text = MB(kb), color = TotalColor(kb) } }
    end,

    tooltip = function(p, tt)
        local list, total, cpu = Usage(p:Get("mode"))
        tt:AddDouble("All add-ons", cpu and ("%.0f ms"):format(total) or MB(total))
        tt:AddDouble("Lua heap (incl. Blizzard UI)", MB(collectgarbage("count")))
        local items = {}
        for i = 1, math.min(p:Get("count"), #list) do
            local e = list[i]
            items[#items + 1] = { e.name, e.value, cpu and nil or Color(e.value), cpu and ("%.0f ms"):format(e.value) or MB(e.value) }
        end
        tt:AddSpacer(2)
        tt:AddChart({ type = "hbarList", title = cpu and "CPU time by add-on" or "Memory by add-on", items = items,
            labelWidth = 120, valueWidth = 60 }, 300)
        if p:Get("mode") == "cpu" and not cpu then tt:AddLine("CPU profiling is off; showing memory.", T.yellow) end
        tt:AddHint("Click: free unused memory  ·  Right-click: options")
    end,

    chart = function(p, range)
        local secs = SimplePanel.RangeSeconds(range)
        local pts = p:Points("total", secs and (time() - secs) or nil)
        return { type = "area", zero = false, yFormat = function(v) return ("%.0f MB"):format(v) end,
            xFormat = function(x) return date("%H:%M:%S", x) end,
            series = { { name = "Memory", points = pts, color = T.accent } } }
    end,

    menu = function(p, m)
        m:Header("Tooltip shows")
        m:Radio({ text = "Memory", value = "memory", get = function() return p:Get("mode") end, set = function(v) p:Set("mode", v) end })
        m:Radio({ text = "CPU time", value = "cpu", get = function() return p:Get("mode") end, set = function(v) p:Set("mode", v) end,
            disabled = function() return not C.CPUProfiling() end,
            tooltip = "Needs CPU profiling on (below) and a /reload." })
        m:Slider({ text = "Add-ons listed", min = 5, max = 30, step = 1, get = function() return p:Get("count") end, set = function(v) p:Set("count", v) end })
        m:Checkbox({ text = "CPU profiling (after /reload)", get = function() return GetCVarBool("scriptProfile") end,
            set = function(v) SetCVar("scriptProfile", v and "1" or "0"); p:Print("CPU profiling will be " .. (v and "on" or "off") .. " after /reload. It slows the game a little.") end })
        m:Button({ text = "Free unused memory", fn = function() p.def.onClick(p, "LeftButton") end })
    end,

    onClick = function(p, button)
        if button ~= "LeftButton" then return end
        local before = collectgarbage("count")
        collectgarbage("collect")
        local after = collectgarbage("count")
        p:Print(("freed %s."):format(MB(math.max(0, before - after))))
        p:Flash()
        p:Refresh()
    end,
})
