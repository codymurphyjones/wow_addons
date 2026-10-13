local _, ns = ...

-- XP: progress to the next level, rested, XP per hour, time and kills to level, and a rate chart.
local T = SimplePanel.Theme

local sessionStart, gained, lastXP, lastMax, lastKill = time(), 0, nil, nil, nil

local function Short(v)
    if v >= 1e6 then return ("%.1fm"):format(v / 1e6) end
    if v >= 1e4 then return ("%.1fk"):format(v / 1e3) end
    return tostring(math.floor(v))
end

local function Duration(secs)
    if not secs or secs == math.huge or secs <= 0 then return "?" end
    local h, m = math.floor(secs / 3600), math.floor(secs / 60) % 60
    if h > 0 then return ("%dh %02dm"):format(h, m) end
    return ("%dm"):format(m)
end

local function MaxLevel()
    local maxLevel = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or MAX_PLAYER_LEVEL or 60
    return UnitLevel("player") >= maxLevel
end

local function Rate()
    local elapsed = time() - sessionStart
    if elapsed < 30 or gained == 0 then return 0 end
    return gained / elapsed * 3600
end

local function Track()
    local xp, max = UnitXP("player"), UnitXPMax("player")
    if lastXP then
        if xp >= lastXP and max == lastMax then gained = gained + (xp - lastXP)
        elseif xp < lastXP then gained = gained + (lastMax - lastXP) + xp end -- levelled up
    end
    lastXP, lastMax = xp, max
end

SimplePanel.RegisterPlugin({
    id = "XP",
    name = "Experience",
    category = "Character",
    icon = 132281,
    zone = "left",
    label = "XP",
    defaults = { showRate = true, showRested = true },
    events = { "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION" },
    series = { rate = { max = 360, minInterval = 60 }, pct = { max = 360, minInterval = 60 } },
    chartRanges = { "session" },

    onInit = function(p)
        Track()
        p:On("PLAYER_XP_UPDATE", function() Track() end)
        p:On("PLAYER_LEVEL_UP", function() C_Timer.After(0.5, Track); p:Flash() end)
        p:On("CHAT_MSG_COMBAT_XP_GAIN", function(_, _, msg)
            local n = msg and tonumber(msg:match("(%d+)"))
            if n then lastKill = n end
        end)
        p:Every(60, function()
            p:Record("rate", Rate())
            p:Record("pct", UnitXP("player") / math.max(1, UnitXPMax("player")) * 100)
            p:Refresh()
        end)
    end,

    text = function(p)
        if MaxLevel() then return { { text = "Max level", color = T.muted } } end
        local xp, max = UnitXP("player"), math.max(1, UnitXPMax("player"))
        local segs = { { text = ("%d%%"):format(xp / max * 100) } }
        local rested = GetXPExhaustion and GetXPExhaustion()
        if p:Get("showRested") and rested and rested > 0 then
            segs[#segs + 1] = { text = ("+%d%%"):format(rested / max * 100), color = T.blue }
        end
        local rate = Rate()
        if p:Get("showRate") and rate > 0 then segs[#segs + 1] = { text = Short(rate) .. "/h", color = T.muted } end
        return segs
    end,

    -- The button doubles as an XP bar: fill to the current level, rested after it.
    progress = function(p)
        if MaxLevel() then return nil end
        local xp, max = UnitXP("player"), math.max(1, UnitXPMax("player"))
        local rested = p:Get("showRested") and GetXPExhaustion and GetXPExhaustion() or 0
        return xp, max, T.accent, rested, T.blue
    end,

    tooltip = function(p, tt)
        local level = UnitLevel("player")
        if MaxLevel() then tt:AddLine("Level " .. level .. " (max)"); return end
        local xp, max = UnitXP("player"), math.max(1, UnitXPMax("player"))
        local rested = GetXPExhaustion and GetXPExhaustion() or 0
        tt:AddDouble("Level", tostring(level))
        tt:AddBar(xp, max, T.accent, ("%s / %s"):format(Short(xp), Short(max)), ("%d%%"):format(xp / max * 100))
        if rested > 0 then tt:AddDouble("Rested", ("%s (%d%%)"):format(Short(rested), rested / max * 100), nil, T.blue) end
        tt:AddDouble("To level", Short(max - xp))
        local rate = Rate()
        tt:AddDivider()
        tt:AddDouble("Gained this session", Short(gained))
        tt:AddDouble("XP per hour", rate > 0 and Short(rate) or "?")
        tt:AddDouble("Time to level", rate > 0 and Duration((max - xp) / rate * 3600) or "?")
        if lastKill and lastKill > 0 then tt:AddDouble("Kills to level", ("~%d"):format(math.ceil((max - xp) / lastKill))) end
        local rates = p:Values("rate")
        if #rates > 2 then
            tt:AddSpacer(4)
            tt:AddChart({ type = "area", title = "XP per hour", hover = false, yFormat = Short,
                series = { { name = "XP/h", values = rates, color = T.accent } } }, 240, 70)
        end
        tt:AddHint("Click: chart  ·  Right-click: options")
    end,

    chart = function(p)
        local pts = p:Points("rate")
        return { type = "area", yFormat = Short, xFormat = function(x) return date("%H:%M", x) end,
            xLabels = pts[1] and { date("%H:%M", pts[1][1]), date("%H:%M", pts[#pts][1]) } or nil,
            series = { { name = "XP/h", points = pts, color = T.accent } },
            footer = ("Session: %s XP in %s"):format(Short(gained), Duration(time() - sessionStart)) }
    end,

    menu = function(p, m)
        m:Checkbox({ text = "Show XP per hour", get = function() return p:Get("showRate") end, set = function(v) p:Set("showRate", v) end })
        m:Checkbox({ text = "Show rested XP", get = function() return p:Get("showRested") end, set = function(v) p:Set("showRested", v) end })
        m:Button({ text = "Reset session", fn = function()
            sessionStart, gained = time(), 0
            wipe(p:Series("rate")); wipe(p:Series("pct"))
            p:Refresh()
        end })
    end,

    onClick = function(p, button) if button == "LeftButton" then p:ShowChart() end end,
})
