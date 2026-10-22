local _, ns = ...
local C = ns.Compat

-- The party popup: when you join a party or someone new joins it, who's in it: what each member is
-- known for (the kudos that reached you, Marks.lua) and your history with them. Also the run summary
-- lines the Runs page shows. (The end of a run is the Campfire now: Campfire.lua.)
local Popup = {}
ns.Popup = Popup

local W = ns.Widgets
local Label, Muted, MakeButton = W.Label, W.Muted, W.MakeButton
local ACCENT = W.ACCENT

local function Window(name, w, h)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(w, h); f:SetPoint("TOP", 0, -140); f:SetFrameStrata("DIALOG"); f:SetClampedToScreen(true)
    W.SetBackdrop(f, 0.97)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local icon = f:CreateTexture(nil, "ARTWORK"); icon:SetSize(22, 22); icon:SetPoint("TOPLEFT", 10, -8)
    icon:SetTexture(ns.ICON)
    f.title = Label(f, "", "FiresideGameFontNormal", 38, -12, w - 90); f.title:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    local close = MakeButton(f, "X", 22, 20); close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() f:Hide() end)
    f.lines = {}
    tinsert(UISpecialFrames, name)
    f:Hide()
    return f
end

-- ---------------------------------------------------------------------------
-- Party popup
-- ---------------------------------------------------------------------------

local party, known = nil, {} -- known: members in the last popup, to spot newcomers
local ROW = 46

local function PartyRow(i)
    local r = party.lines[i]
    if not r then
        r = CreateFrame("Button", nil, party)
        r:SetSize(500, ROW - 4)
        -- One line across the row: a long "Given Family  level 60, Healer" is cut short instead of
        -- wrapping down into the summary under it.
        r.name = Label(r, "", "FiresideGameFontHighlight", 0, 0, 500); r.name:SetWordWrap(false)
        r.text = Muted(Label(r, "", "FiresideGameFontHighlightSmall", 0, -16, 500))
        r.text:SetWordWrap(true); r.text:SetHeight(28)
        r:SetScript("OnClick", function(self) if self.full then ns.UI:ShowPlayer(self.full) end end)
        party.lines[i] = r
    end
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 12, -36 - (i - 1) * ROW)
    return r
end

function Popup:ShowParty(force)
    if not (force or ns.db.options.popup) then return end
    if not IsInGroup() or IsInRaid() then
        if force then ns:Print("You're not in a party.", true) end
        return
    end
    if not party then
        party = Window("FiresidePartyPopup", 524, 100)
        party:SetScript("OnUpdate", function(self, elapsed)
            if not self.closeAt or self:IsMouseOver() then return end
            if GetTime() >= self.closeAt then self:Hide() end
        end)
    end
    local units = C.GroupUnits()
    local n, anyKnown = 0, false
    for _, unit in ipairs(units) do
        local full = C.UnitFull(unit)
        if full then
            n = n + 1
            local r = PartyRow(n)
            local _, class = C.Call(UnitClass, unit)
            local p = ns.History:Get(full)
            local summary = ns.History:Summary(full)
            if summary then anyKnown = true end
            r.full = full
            r.name:SetText(("%s  |cffaaaaaalevel %s%s|r"):format(C.Colored(full, C.Str(class)), C.Num(C.Call(UnitLevel, unit)) or "?",
                p and p.lastRole and (", " .. p.lastRole) or ""))
            r.text:SetText(summary or "|cffaaaaaaNew to you, and nobody has told your party about them yet.|r")
            r:Show()
        end
    end
    for i = n + 1, #party.lines do party.lines[i]:Hide() end
    if n == 0 then return party:Hide() end
    party.title:SetText(anyKnown and "Who's in your party, and what they're known for" or "Your party: new faces all round")
    party:SetHeight(46 + n * ROW)
    local secs = ns.db.options.popupSeconds or 20
    party.closeAt = (secs > 0 and not force) and (GetTime() + secs) or nil
    party:Show()
end

-- On joining a party, or when someone new joins it.
local pending
ns:On("GROUP_ROSTER_UPDATE", function()
    if pending then return end
    pending = true
    C_Timer.After(1.5, function()
        pending = false
        if not IsInGroup() or IsInRaid() then wipe(known) return end
        local newcomer = false
        local now = {}
        for _, unit in ipairs(C.GroupUnits()) do
            local full = C.UnitFull(unit)
            if full then
                now[full] = true
                if not known[full] then newcomer = true end
            end
        end
        known = now
        if newcomer then Popup:ShowParty(false) end
    end)
end)

-- ---------------------------------------------------------------------------
-- Run summary (the Runs page)
-- ---------------------------------------------------------------------------

local DURATION = { days = false, alwaysHours = true }
local function Duration(run) return ns.Format.Duration((run.stop or time()) - run.start, DURATION) end

-- Lines describing a run: bosses, wipes, deaths by person, who caused the most.
function Popup.RunLines(run)
    local lines = {}
    lines[#lines + 1] = ("%s, %s. %d boss%s killed, %d wipe%s, %d death%s."):format(date("%m/%d %H:%M", run.start), Duration(run),
        run.bossKills or 0, (run.bossKills or 0) == 1 and "" or "es", run.wipes or 0, (run.wipes or 0) == 1 and "" or "s",
        #run.deaths, #run.deaths == 1 and "" or "s")
    for _, name in ipairs(run.bossOrder or {}) do
        local b = run.bosses[name]
        lines[#lines + 1] = ("  %s: %d attempt%s, %s"):format(name, b.attempts, b.attempts == 1 and "" or "s",
            b.kills > 0 and "|cff59f28ckilled|r" or "|cffd9736bnot killed|r")
    end
    local died, caused = {}, {}
    for _, d in ipairs(run.deaths) do
        died[d.victim] = (died[d.victim] or 0) + 1
        for who, share in pairs(d.blame or {}) do caused[who] = (caused[who] or 0) + share * (d.weight or 1) end
    end
    local list = {}
    for who, n in pairs(caused) do list[#list + 1] = { who, n } end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    if #list > 0 then
        local parts = {}
        for i = 1, math.min(5, #list) do
            parts[#parts + 1] = ("%s %.1f (died %d)"):format(list[i][1], list[i][2], died[list[i][1]] or 0)
        end
        lines[#lines + 1] = "Deaths caused, most likely: " .. table.concat(parts, ", ")
    end
    -- Damage and healing over the whole run.
    local done, healed = {}, {}
    for _, f in ipairs(run.fights) do
        for name, p in pairs(f.stats or {}) do
            done[name] = (done[name] or 0) + (p.done or 0)
            healed[name] = (healed[name] or 0) + (p.healed or 0)
        end
    end
    local function Top(t)
        local best, n = nil, 0
        for name, v in pairs(t) do if v > n then best, n = name, v end end
        return best, n
    end
    local dps, dn = Top(done)
    local heal, hn = Top(healed)
    if dps then lines[#lines + 1] = ("Most damage: %s (%s)"):format(dps, AbbreviateNumbers and AbbreviateNumbers(dn) or dn) end
    if heal and hn > 0 then lines[#lines + 1] = ("Most healing: %s (%s)"):format(heal, AbbreviateNumbers and AbbreviateNumbers(hn) or hn) end
    -- What was said at the campfire.
    local kudos = {}
    for _, e in ipairs(run.kudos or {}) do
        kudos[#kudos + 1] = ("%s to %s: %s %s"):format(C.IsMe(e.from) and "you" or C.Short(e.from), C.IsMe(e.to) and "you" or C.Short(e.to),
            ns.Marks.Icon(e.k), ns.Marks.Label(e.k))
    end
    if #kudos > 0 then lines[#lines + 1] = "At the campfire: " .. table.concat(kudos, ";  ") end
    return lines
end
