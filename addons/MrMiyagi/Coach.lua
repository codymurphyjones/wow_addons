local _, ns = ...
local C = ns.Compat

-- After a death to mobs: puts the death recap and the fight record together, leaves deaths to
-- players alone (those are BattleRecap's), builds the lessons, keeps them in the dojo and opens
-- the coach window.
local Coach = {}
ns.Coach = Coach

local W = ns.Widgets
local Label, Muted, MakeButton = W.Label, W.Muted, W.MakeButton
local ACCENT = W.ACCENT
local KEEP = 200
local WAIT = 6 -- seconds to wait for the other half (recap or fight) before going ahead

local pendingHits, pendingFight, token = nil, nil, 0

-- Any hit from a player or a player's pet: a PvP death.
local function IsPvP(hits)
    for _, h in ipairs(hits or {}) do
        if h.player or h.playerPet then return true end
    end
    return false
end

local function Story(f, hits, maxHp)
    local lines = {}
    local first = f.mobs[f.order[1]]
    if first then
        lines[#lines + 1] = ("You fought %s (%s%s%s) for %ds%s."):format(first.name,
            first.level and ("level " .. first.level) or "level ??", first.kind and (" " .. first.kind:lower()) or "",
            (first.rank == "elite" or (first.dbRank or 0) == 1) and ", elite" or "", f.duration or 0,
            f.pre.hp and f.pre.hp < 0.95 and (", starting at %d%% health"):format(f.pre.hp * 100) or "")
    end
    for i = 2, #f.order do
        local m = f.mobs[f.order[i]]
        lines[#lines + 1] = ("%s (level %s) joined at %ds."):format(m.name, m.level or "??", m.at)
    end
    local m = f.meter
    if m then
        lines[#lines + 1] = ("You dealt %d damage (%d a second) and took %d."):format(m.done.total,
            m.duration and m.duration > 0 and m.done.total / m.duration or 0, m.taken.total)
        if m.received then
            local me = C.Me()
            local got = m.received[me]
            if got and got > 0 then
                local by = {}
                for name, h in pairs(m.ledger or {}) do
                    if h.targets[me] and h.targets[me] > 0 then by[#by + 1] = ("%s %d"):format(name, h.targets[me]) end
                end
                lines[#lines + 1] = ("Healing you received: %d (%s)."):format(got, table.concat(by, ", "))
            end
        end
    end
    local kb
    for _, h in ipairs(hits or {}) do if not h.heal then kb = h end end
    if kb then
        lines[#lines + 1] = ("The killing blow: %s %s%s%s."):format(kb.spell or "?", kb.amount or "?", kb.crit and " (crit)" or "",
            kb.src and (" from " .. kb.src) or "")
    end
    return table.concat(lines, "\n")
end

local function Process()
    local f, hits = pendingFight, pendingHits
    pendingFight, pendingHits = nil, nil
    if not f then return end
    if f.pvp or IsPvP(hits and hits.list) then
        ns:Debug("Death to a player: that's BattleRecap's.")
        return
    end
    local result = ns.Lessons:Build(f, hits and hits.list, hits and hits.maxHp)
    if not result then return end
    local mobs = {}
    for _, key in ipairs(f.order) do
        local m = f.mobs[key]
        mobs[#mobs + 1] = { name = m.name, level = m.level, kind = m.kind, rank = m.rank }
    end
    -- Saved without functions or the model: text and numbers only.
    local lessons = {}
    for _, l in ipairs(result.lessons) do
        lessons[#lessons + 1] = { key = l.key, title = l.title, what = l.what, todo = l.todo, gain = l.gain }
    end
    local d = {
        t = f.start, zone = f.zone, level = f.level, mobs = mobs, duration = math.floor(f.duration or 0),
        story = Story(f, hits and hits.list, hits and hits.maxHp), lessons = lessons,
        odds = result.odds, oddsAfter = result.oddsAfter, tooHard = result.tooHard, evenLevel = result.evenLevel,
        maxDiff = result.maxDiff, group = f.group,
    }
    table.insert(ns.db.deaths, d)
    while #ns.db.deaths > KEEP do table.remove(ns.db.deaths, 1) end
    ns.Watch:Keep(f) -- the loss counts in your record too
    if ns.db.options.debug then
        ns:Debug(("Death: %d mobs, meter %s, %d hits; odds %s -> %s"):format(#f.order, f.meter and "read" or tostring(f.meterMissing),
            hits and hits.list and #hits.list or 0, ns.Odds.Percent(result.odds), ns.Odds.Percent(result.oddsAfter)))
        for _, l in ipairs(result.lessons) do ns:Debug(("  %s (+%s): %s"):format(l.title, ns.Odds.Percent(l.gain or 0), l.what)) end
    end
    if ns.db.options.autoOpen then
        -- Fireside's death popup is already explaining this death: don't open on top of it.
        local gh = FiresideAPI and FiresideAPI.DeathPopupShown
        local ok, shown = pcall(gh or function() return false end)
        if ok and shown then
            ns:Print("A lesson from this death is waiting: |cffffffff/miyagi last|r.")
        else
            Coach:Show(d)
        end
    end
    ns:Changed()
end

local function Soon()
    token = token + 1
    local mine = token
    if pendingFight and pendingHits then return Process() end
    C_Timer.After(WAIT, function() if mine == token then Process() end end)
end

ns:On("PLAYER_DEAD", function()
    ns.Recap.ReadOwnAfterDeath(function(list, maxHp)
        pendingHits = { list = list, maxHp = maxHp }
        Soon()
    end)
end)

function Coach:OnFightOver(f)
    pendingFight = f
    Soon()
end

-- ---------------------------------------------------------------------------
-- The coach window
-- ---------------------------------------------------------------------------

local win

local function Build()
    win = CreateFrame("Frame", "MrMiyagiCoach", UIParent, "BackdropTemplate")
    win:SetSize(560, 520); win:SetFrameStrata("DIALOG"); win:SetClampedToScreen(true)
    W.SetBackdrop(win, 0.97)
    local pos = ns.char.coach
    win:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or 80)
    win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        ns.char.coach = { point = point, x = x, y = y }
    end)
    tinsert(UISpecialFrames, "MrMiyagiCoach")
    local icon = win:CreateTexture(nil, "ARTWORK"); icon:SetSize(30, 30); icon:SetPoint("TOPLEFT", 12, -10)
    icon:SetTexture(ns.ICON)
    win.title = Label(win, "", "MrMiyagiGameFontNormalLarge", 50, -12, 440); win.title:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    win.sub = Muted(Label(win, "", "MrMiyagiGameFontHighlightSmall", 50, -32, 480))
    local close = MakeButton(win, "X", 24, 22); close:SetPoint("TOPRIGHT", -10, -10)
    close:SetScript("OnClick", function() win:Hide() end)

    local scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -56); scroll:SetPoint("BOTTOMRIGHT", -32, 46)
    win.body = CreateFrame("Frame", nil, scroll); win.body:SetSize(510, 10)
    scroll:SetScrollChild(win.body)
    win.text = win.body:CreateFontString(nil, "OVERLAY", "MrMiyagiGameFontHighlight")
    win.text:SetPoint("TOPLEFT"); win.text:SetWidth(500); win.text:SetJustifyH("LEFT"); win.text:SetSpacing(3)

    local ok = MakeButton(win, "Got it", 90, 24); ok:SetPoint("BOTTOMRIGHT", -12, 12)
    ok:SetScript("OnClick", function() win:Hide() end)
    local dojo = MakeButton(win, "Dojo", 80, 24); dojo:SetPoint("RIGHT", ok, "LEFT", -6, 0)
    dojo:SetScript("OnClick", function() win:Hide(); ns.UI:Show() end)
    win.more = MakeButton(win, "All lessons", 100, 24); win.more:SetPoint("BOTTOMLEFT", 12, 12)
    win.more:SetScript("OnClick", function() win.all = not win.all; Coach:Show(win.death) end)
    win:Hide()
end

local function Text(d, all)
    local L = {}
    local function Add(s) L[#L + 1] = s end
    Add("|cffffd100What happened|r")
    Add(d.story or "")
    Add(" ")
    -- The odds, and the honest answer when it's too hard.
    Add("|cffffd100Your odds|r")
    Add(("A fight like this one: about %s. With the lessons below: about %s."):format(ns.Odds.Percent(d.odds or 0),
        ns.Odds.Percent(d.oddsAfter or 0)))
    if d.tooHard then
        Add(("|cffd9736bThis fight is too much for you right now%s. Leave it for later%s.|r"):format(
            d.maxDiff and d.maxDiff >= 3 and (" (%d levels above you)"):format(d.maxDiff) or "",
            d.evenLevel and (": at about level %d it becomes an even match"):format(d.evenLevel) or ""))
        Add("If you take it on anyway, this is how to give yourself the best chance:")
    end
    Add("|cffaaaaaaEstimates from this fight's numbers (your damage and theirs, your health and theirs).|r")
    -- Recurring patterns from the dojo.
    local pattern = ns.Dojo and ns.Dojo:PatternLine(d)
    if pattern then
        Add(" ")
        Add("|cffffd24d" .. pattern .. "|r")
    end
    Add(" ")
    Add("|cffffd100Lessons|r")
    local shown = all and #d.lessons or math.min(#d.lessons, ns.db.options.lessons or 4)
    if #d.lessons == 0 then Add("Nothing stands out: this one may simply have been bad luck.") end
    for i = 1, shown do
        local l = d.lessons[i]
        Add(("|cffffffff%d. %s|r%s"):format(i, l.title, l.gain and l.gain >= 0.01 and ("  |cff59f28c+%s|r"):format(ns.Odds.Percent(l.gain)) or ""))
        Add("|cffaaaaaa" .. (l.what or "") .. "|r")
        for _, line in ipairs(l.todo or {}) do Add(line) end
        Add(" ")
    end
    return table.concat(L, "\n"), shown < #d.lessons
end

function Coach:Show(d)
    if not d then return end
    if not win then Build() end
    if win.death ~= d then win.all = false end
    win.death = d
    local killers = {}
    for _, m in ipairs(d.mobs or {}) do killers[#killers + 1] = m.name end
    win.title:SetText("Mr. Miyagi: " .. (killers[1] or "a lesson"))
    win.sub:SetText(("%s  -  %s, level %d%s"):format(date("%m/%d %H:%M", d.t), d.zone or "?", d.level or 0,
        #killers > 1 and ("  -  with " .. table.concat(killers, ", ", 2)) or ""))
    local text, more = Text(d, win.all)
    win.text:SetText(text)
    win.body:SetHeight(win.text:GetStringHeight() + 20)
    win.more:SetShown(more or win.all)
    win.more.text:SetText(win.all and "Top lessons" or "All lessons")
    win:Show()
end
