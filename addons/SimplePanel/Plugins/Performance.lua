local _, ns = ...

-- Performance: frame rate and latency, with a live sparkline and five minutes of history.
local T = SimplePanel.Theme

local function FpsColor(v) return v >= 50 and T.green or (v >= 25 and T.yellow or T.red) end
local function MsColor(v) return v <= 120 and T.green or (v <= 300 and T.yellow or T.red) end

local function Stats(values)
    local n, sum, lo, hi = #values, 0, math.huge, 0
    for _, v in ipairs(values) do sum = sum + v; lo = math.min(lo, v); hi = math.max(hi, v) end
    if n == 0 then return 0, 0, 0 end
    return math.floor(sum / n + 0.5), lo, hi
end

SimplePanel.RegisterPlugin({
    id = "Performance",
    name = "Performance",
    category = "Information",
    icon = 132150,
    zone = "right",
    defaults = { show = "both" },
    series = { fps = { max = 300 }, home = { max = 300 }, world = { max = 300 } },
    spark = "fps",
    chartRanges = { "FPS", "Latency" },

    onInit = function(p)
        p:Every(1, function()
            local _, _, home, world = GetNetStats()
            p:Record("fps", math.floor(GetFramerate() + 0.5))
            p:Record("home", home or 0)
            p:Record("world", world or 0)
            p:Refresh()
        end)
    end,

    text = function(p)
        local fps = math.floor(GetFramerate() + 0.5)
        local _, _, home, world = GetNetStats()
        local ms = math.max(home or 0, world or 0)
        local show = p:Get("show")
        local segs = {}
        if show ~= "ms" then segs[#segs + 1] = { text = fps .. " fps", color = FpsColor(fps) } end
        if show ~= "fps" then segs[#segs + 1] = { text = ms .. " ms", color = MsColor(ms) } end
        return segs
    end,

    tooltip = function(p, tt)
        local fps = p:Values("fps")
        local avg, lo, hi = Stats(fps)
        local _, _, home, world = GetNetStats()
        local bwIn, bwOut = GetNetStats()
        tt:AddDouble("Frame rate", ("%d fps"):format(math.floor(GetFramerate() + 0.5)), nil, FpsColor(GetFramerate()))
        tt:AddDouble("Average · low · high", ("%d · %d · %d"):format(avg, lo == math.huge and 0 or lo, hi))
        tt:AddDouble("Home latency", (home or 0) .. " ms", nil, MsColor(home or 0))
        tt:AddDouble("World latency", (world or 0) .. " ms", nil, MsColor(world or 0))
        tt:AddDouble("Bandwidth in · out", ("%.1f · %.1f KB/s"):format(bwIn or 0, bwOut or 0))
        if #fps > 2 then
            tt:AddSpacer(4)
            tt:AddChart({ type = "area", title = "FPS, last " .. math.ceil(#fps / 60) .. " min", hover = false,
                thresholds = { { value = 30, color = T.red, label = "30" } },
                series = { { name = "FPS", values = fps, color = T.accent } } }, 260, 80)
            tt:AddChart({ type = "line", title = "Latency (ms)", hover = false,
                series = { { name = "Home", values = p:Values("home"), color = T.yellow },
                    { name = "World", values = p:Values("world"), color = T.blue } } }, 260, 70)
        end
        tt:AddHint("Click: open the chart window")
    end,

    chart = function(p, view)
        local now = time()
        local function Ago(x) local s = now - x; return s < 60 and (s .. "s ago") or (("%dm %02ds ago"):format(math.floor(s / 60), s % 60)) end
        if view == "Latency" then
            return { type = "line", xFormat = Ago, yFormat = function(v) return ("%d ms"):format(v) end,
                thresholds = { { value = 300, color = T.red, label = "300 ms" } },
                xLabels = { "5 min ago", "now" },
                series = { { name = "Home", points = p:Points("home"), color = T.yellow },
                    { name = "World", points = p:Points("world"), color = T.blue } } }
        end
        local avg, lo, hi = Stats(p:Values("fps"))
        return { type = "area", xFormat = Ago, yFormat = function(v) return ("%d"):format(v) end,
            thresholds = { { value = 30, color = T.red, label = "30 fps" } },
            xLabels = { "5 min ago", "now" },
            series = { { name = "FPS", points = p:Points("fps"), color = T.accent } },
            footer = ("Average %d  ·  low %d  ·  high %d"):format(avg, lo == math.huge and 0 or lo, hi) }
    end,

    menu = function(p, m)
        m:Header("Show")
        for _, o in ipairs({ { "both", "FPS and latency" }, { "fps", "FPS only" }, { "ms", "Latency only" } }) do
            m:Radio({ text = o[2], value = o[1], get = function() return p:Get("show") end, set = function(v) p:Set("show", v) end })
        end
    end,

    onClick = function(p, button) if button == "LeftButton" then p:ShowChart() end end,
})
