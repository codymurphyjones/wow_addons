local _, ns = ...

-- Quests: how full the quest log is and how many quests are ready to hand in, every quest with its
-- objectives in the tooltip, and a flash when one is done. Left-click opens the quest log.
local T = SimplePanel.Theme
local C = ns.Compat

local READY_ICON = "Interface\\GossipFrame\\ActiveQuestIcon" -- the yellow "?" over a quest giver
local ZONE_ICON = "Interface\\Icons\\INV_Misc_Map_01"

local wasComplete = {} -- quest key -> complete, as last seen (a quest flashes when it turns true)
local turnedIn = 0

local function Key(q) return q.id or q.title end

local function Ready(list)
    local n = 0
    for _, q in ipairs(list) do if q.complete then n = n + 1 end end
    return n
end

local function Mix(a, b, f) return { a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f } end

-- The count shades from white through yellow to red as the log fills: white up to half full,
-- yellow at three quarters, red when nothing more fits.
local function CountColor(n, max)
    local f = n / math.max(1, max)
    if f <= 0.5 then return T.text end
    if f <= 0.75 then return Mix(T.text, T.yellow, (f - 0.5) / 0.25) end
    return Mix(T.yellow, T.red, math.min(1, (f - 0.75) / 0.25))
end

-- Quests filed under the zone you're in (the quest log groups them by zone).
local function InZone(list)
    local here = GetRealZoneText and GetRealZoneText()
    local n = 0
    for _, q in ipairs(list) do if here and q.zone == here then n = n + 1 end end
    return n
end

local function CheckCompleted(p)
    local done = {}
    for _, q in ipairs(C.Quests().list) do
        local key = Key(q)
        if wasComplete[key] == false and q.complete then done[#done + 1] = q.title end
        wasComplete[key] = q.complete
    end
    if #done > 0 then
        p:Flash()
        if p:Get("announce") then
            for _, title in ipairs(done) do p:Print("|cff59f28c" .. title .. "|r is ready to hand in.") end
        end
    end
    p:Refresh()
end

local function Progress(q)
    if q.failed then return "Failed", T.red end
    if q.complete then return "Ready", T.green end
    local n = #q.objectives
    if n == 0 then return "", T.muted end
    local done = 0
    for _, o in ipairs(q.objectives) do if o.done then done = done + 1 end end
    return done .. "/" .. n, T.text
end

local function AddEntries(p, m)
    m:Checkbox({ text = "Show how many are ready", get = function() return p:Get("showReady") end, set = function(v) p:Set("showReady", v) end })
    m:Checkbox({ text = "Show how many are in this zone", get = function() return p:Get("showZone") end, set = function(v) p:Set("showZone", v) end })
    m:Checkbox({ text = "Show all quests on mouseover", get = function() return p:Get("showAllTooltip") end, set = function(v) p:Set("showAllTooltip", v) end,
        tooltip = "Off: the tooltip lists only the quests in this zone and the ones you track." })
    m:Checkbox({ text = "Objectives in the tooltip", get = function() return p:Get("objectives") end, set = function(v) p:Set("objectives", v) end })
    m:Checkbox({ text = "Say in chat when a quest is done", get = function() return p:Get("announce") end, set = function(v) p:Set("announce", v) end })
end

SimplePanel.RegisterPlugin({
    id = "Quests",
    name = "Quests",
    category = "Character",
    icon = "Interface\\Icons\\INV_Misc_Book_08",
    zone = "left",
    defaults = { showReady = true, showZone = true, showAllTooltip = false, objectives = true, announce = true },
    events = { "QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA" },

    onInit = function(p)
        for _, q in ipairs(C.Quests().list) do wasComplete[Key(q)] = q.complete end
        p:On("QUEST_LOG_UPDATE", function() CheckCompleted(p) end)
        p:On("QUEST_TURNED_IN", function() turnedIn = turnedIn + 1; p:Refresh() end)
    end,

    text = function(p)
        local data = C.Quests()
        local n = #data.list
        -- Quests held, then the game's "?" with how many are ready to hand in, then a map with how
        -- many are in this zone.
        local segs = { { text = tostring(n), color = CountColor(n, data.max) } }
        local ready = Ready(data.list)
        if p:Get("showReady") and ready > 0 then
            segs[#segs + 1] = { icon = READY_ICON, fullIcon = true, text = tostring(ready), color = T.green }
        end
        local here = InZone(data.list)
        if p:Get("showZone") and here > 0 then
            segs[#segs + 1] = { icon = ZONE_ICON, text = tostring(here) }
        end
        return segs
    end,

    tooltip = function(p, tt)
        local data = C.Quests()
        local n = #data.list
        tt:AddDouble("Quest log", n .. "/" .. data.max, nil, CountColor(n, data.max) or T.text)
        local ready = Ready(data.list)
        if ready > 0 then tt:AddDouble("Ready to hand in", tostring(ready), nil, T.green) end
        local here = InZone(data.list)
        if here > 0 then tt:AddDouble("In this zone", tostring(here), nil, T.text) end
        if n == 0 and not data.collapsed then tt:AddLine("No quests.", T.muted) end
        -- Unless every quest is asked for: the ones in this zone and the ones you track.
        local all = p:Get("showAllTooltip")
        local hereName = GetRealZoneText and GetRealZoneText()
        local zone, shown = nil, 0
        for _, q in ipairs(data.list) do
            if all or q.watched or (hereName and q.zone == hereName) then
                shown = shown + 1
                if q.zone ~= zone then zone = q.zone; tt:AddHeader(zone or "Quests") end
                local name = ("[%d%s] %s"):format(q.level, q.group > 1 and "+" or "", q.title)
                local right, rc = Progress(q)
                tt:AddDouble(name, right, C.QuestColor(q.level), rc)
                if p:Get("objectives") and not q.complete then
                    for _, o in ipairs(q.objectives) do
                        tt:AddLine("    " .. o.text, o.done and T.green or T.muted, false)
                    end
                end
            end
        end
        if not all and shown < n then
            tt:AddSpacer(2)
            tt:AddLine(shown == 0 and ("None of your %d quests are in this zone or tracked."):format(n)
                or ("%d more elsewhere: right-click, Show all quests on mouseover."):format(n - shown), T.muted, true)
        end
        if data.collapsed then
            tt:AddLine("Some zones are folded up in your quest log; their quests aren't counted here.", T.yellow, true)
        end
        if turnedIn > 0 then
            tt:AddSpacer(2)
            tt:AddDouble("Handed in this session", tostring(turnedIn), nil, T.text)
        end
        tt:AddHint("Click: quest log  ·  Right-click: options")
    end,

    menu = AddEntries,

    -- The quest log opens through the game's own button: opening it from add-on code taints it.
    secure = function() return ns.SecureClick.Click(QuestLogMicroButton) end,
    secureInCombat = true,

    onClick = function(p, button)
        if button == "LeftButton" and not IsModifierKeyDown() and ToggleQuestLog then
            ns.SecureClick.Open(function() ToggleQuestLog() end, "the quest log")
        end
    end,
})
