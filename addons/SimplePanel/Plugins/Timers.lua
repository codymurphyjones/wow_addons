local _, ns = ...

-- Timers: quick alarms from the drop-down ("in 10 minutes", or your own). The button counts down to
-- the next one; when one is up it flashes, rings and puts the reminder on screen. Timers survive a
-- reload.
local T = SimplePanel.Theme

local QUICK = { 1, 5, 10, 15, 30, 60 }

local function Clock(secs)
    secs = math.max(0, math.floor(secs))
    if secs >= 3600 then return ("%d:%02d:%02d"):format(secs / 3600, secs / 60 % 60, secs % 60) end
    return ("%d:%02d"):format(secs / 60, secs % 60)
end

local function List(p)
    local list = p:Get("timers")
    table.sort(list, function(a, b) return a.at < b.at end)
    return list
end

local function Add(p, minutes, label)
    local list = p:Get("timers")
    list[#list + 1] = { at = time() + math.floor(minutes * 60), label = label or (minutes .. " min timer") }
    p:Refresh()
end

local function Ring(p, t)
    p:Flash()
    if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
    if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
        RaidNotice_AddMessage(RaidWarningFrame, t.label, ChatTypeInfo["RAID_WARNING"])
    end
    p:Print("time's up: " .. t.label)
end

local function Check(p)
    local list, now, changed = p:Get("timers"), time(), false
    for i = #list, 1, -1 do
        if list[i].at <= now then
            Ring(p, list[i])
            table.remove(list, i)
            changed = true
        end
    end
    if changed then p:Refresh() end
end

local function AddEntries(p, m)
    m:Header("New timer")
    for _, minutes in ipairs(QUICK) do
        m:Button({ text = minutes == 60 and "In 1 hour" or ("In %d minutes"):format(minutes):gsub("In 1 minutes", "In 1 minute"),
            keepOpen = true, fn = function() Add(p, minutes) end })
    end
    m:Input({ text = "Minutes", get = function() return "" end, set = function(v)
        local minutes, label = tostring(v):match("^%s*(%d+%.?%d*)%s*(.-)%s*$")
        minutes = tonumber(minutes)
        if not minutes or minutes <= 0 then return p:Print("type a number of minutes, optionally followed by a note: 25 pizza") end
        Add(p, minutes, label ~= "" and label or nil)
    end, tooltip = "A number of minutes, and a note if you like: \"25 raid starts\"." })
    local list = List(p)
    if #list > 0 then
        m:Header("Running")
        for _, t in ipairs(list) do
            m:Button({ text = t.label, shortcut = Clock(t.at - time()), keepOpen = true,
                tooltip = "Click to cancel it.", fn = function()
                    for i, x in ipairs(p:Get("timers")) do if x == t then table.remove(p:Get("timers"), i) break end end
                    p:Refresh()
                end })
        end
    end
end

SimplePanel.RegisterPlugin({
    id = "Timers",
    name = "Timers",
    category = "Information",
    icon = "Interface\\Icons\\INV_Misc_PocketWatch_03",
    zone = "right",
    defaultEnabled = false,
    defaults = { timers = {} },
    interval = 1,

    onInit = function(p) p:Every(1, Check) end,

    text = function(p)
        local list = List(p)
        if #list == 0 then return { { text = "Timers", color = T.muted } } end
        local t = list[1]
        local left = t.at - time()
        local segs = { { text = Clock(left), color = left < 60 and T.yellow or T.accent } }
        if #list > 1 then segs[2] = { text = "+" .. (#list - 1), color = T.muted } end
        return segs
    end,

    tooltip = function(p, tt)
        local list = List(p)
        if #list == 0 then tt:AddLine("No timers running.", T.muted) end
        for _, t in ipairs(list) do tt:AddDouble(t.label, Clock(t.at - time()), T.text, T.accent) end
        tt:AddHint("Click: new timer or cancel one")
    end,

    menu = AddEntries,

    onClick = function(p, button)
        if button ~= "LeftButton" then return end
        local m = ns.Menu:New(p.button)
        m:Title("Timers", p.icon)
        AddEntries(p, m)
        m:Show(p.button)
    end,
})
