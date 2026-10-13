local _, ns = ...

-- Reputation: the watched faction as a bar like the XP bar, in its standing's color, with reputation
-- per hour and time to the next standing. The drop-down picks the faction to watch.
local T = SimplePanel.Theme
local C = ns.Compat

local session = {} -- factionID or name -> { start, gained, since }

local function Key(name, id) return id or name end

local function Track()
    local name, _, _, _, value, id = C.WatchedFaction()
    if not name then return end
    local s = session[Key(name, id)]
    if not s then session[Key(name, id)] = { last = value, gained = 0, since = time() }; return end
    if value > s.last then s.gained = s.gained + (value - s.last) end
    s.last = value
end

local function PerHour(name, id)
    local s = session[Key(name, id)]
    if not s or s.gained == 0 then return 0 end
    local hours = math.max(time() - s.since, 60) / 3600
    return s.gained / hours
end

local function Short(n)
    n = math.floor(n + 0.5)
    if n >= 10000 then return ("%.1fk"):format(n / 1000) end
    return tostring(n)
end

SimplePanel.RegisterPlugin({
    id = "Reputation",
    name = "Reputation",
    category = "Character",
    icon = "Interface\\Icons\\INV_Misc_Note_02",
    zone = "left",
    showIcon = false,
    defaults = { showName = true, showPct = true },
    events = { "UPDATE_FACTION", "PLAYER_ENTERING_WORLD" },

    onInit = function(p)
        Track()
        p:On("UPDATE_FACTION", function() Track() end)
    end,

    text = function(p)
        local name, standing, min, max, value = C.WatchedFaction()
        if not name then return { { text = "No faction watched", color = T.muted } } end
        local segs = {}
        if p:Get("showName") then segs[#segs + 1] = { text = name } end
        local span = math.max(1, max - min)
        local done = value - min
        segs[#segs + 1] = { text = p:Get("showPct") and ("%d%%"):format(done / span * 100) or (Short(done) .. "/" .. Short(span)),
            color = C.StandingColor(standing) }
        return segs
    end,

    progress = function()
        local name, standing, min, max, value = C.WatchedFaction()
        if not name then return nil end
        return value - min, math.max(1, max - min), C.StandingColor(standing)
    end,

    tooltip = function(_, tt)
        local name, standing, min, max, value, id = C.WatchedFaction()
        if not name then tt:AddLine("Pick a faction to watch from the drop-down.", T.muted); return end
        local span, done = math.max(1, max - min), value - min
        tt:AddDouble(name, C.StandingName(standing), T.text, C.StandingColor(standing))
        tt:AddBar(done, span, C.StandingColor(standing), ("%s / %s"):format(Short(done), Short(span)), ("%d%%"):format(done / span * 100))
        tt:AddDouble("To the next standing", Short(span - done))
        local rate = PerHour(name, id)
        tt:AddDouble("Per hour", rate > 0 and Short(rate) or "?")
        if rate > 0 then
            local secs = (span - done) / rate * 3600
            tt:AddDouble("Time to next standing", ("%dh %02dm"):format(secs / 3600, secs / 60 % 60))
        end
        tt:AddHint("Click: pick a faction  ·  Right-click: options")
    end,

    menu = function(p, m)
        m:Checkbox({ text = "Show the faction name", get = function() return p:Get("showName") end, set = function(v) p:Set("showName", v) end })
        m:Checkbox({ text = "As a percentage", get = function() return p:Get("showPct") end, set = function(v) p:Set("showPct", v) end })
        m:Checkbox({ text = "Watch buttons on the Reputation tab", get = function() return ns.db.options.repWatchButtons end,
            set = function(v) ns.db.options.repWatchButtons = v; ns.ReputationWatch:Update() end,
            tooltip = "A small eye on every faction in the game's Reputation tab: click it to watch that faction." })
    end,

    onClick = function(p, button)
        if button ~= "LeftButton" then return end
        local m = ns.Menu:New(p.button)
        m:Title("Watch a faction", p.icon)
        local list = C.Factions()
        if #list == 0 then m:Header("No reputations yet") end
        for _, f in ipairs(list) do
            m:Radio({ text = f.name, value = f.index, swatch = C.StandingColor(f.standing), close = true,
                get = function() for _, g in ipairs(C.Factions()) do if g.watched then return g.index end end end,
                set = function(v) C.WatchFaction(v); C_Timer.After(0.2, function() Track(); p:Refresh() end) end,
                tooltip = C.StandingName(f.standing) })
        end
        m:Show(p.button)
    end,
})
