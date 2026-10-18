local _, ns = ...
local C = ns.Compat

-- The Group History window: Players (everyone you've run with, and each one's page), Runs (each
-- run's bosses, wipes and deaths, and each death's hits and blame), and Settings. Same frame and
-- sidebar as Wally's window.
local UI = {}
ns.UI = UI

local W = ns.Widgets
local ACCENT = W.ACCENT
local SetBackdrop, Label, Muted, MakeButton, Hint = W.SetBackdrop, W.Label, W.Muted, W.MakeButton, W.Hint

local frame
local pages, tabs = {}, {}
local activeTab = "players"
local TABS = {
    { "players", "Players", "INV_Misc_GroupNeedMore" },
    { "runs", "Runs", "INV_Misc_Map_01" },
    { "settings", "Settings", "INV_Misc_Gear_01" },
}

local function NewPage(name)
    local p = CreateFrame("Frame", nil, frame)
    p:SetPoint("TOPLEFT", 196, -76); p:SetPoint("BOTTOMRIGHT", -18, 18)
    p:Hide(); pages[name] = p
    return p
end

local function Duration(run)
    local secs = (run.stop or time()) - run.start
    return ("%dh %02dm"):format(secs / 3600, secs % 3600 / 60)
end

local function RunLine(run)
    return ("%s  -  %s, %s%s, %d wipe%s, %d death%s"):format(date("%m/%d/%y %H:%M", run.start), Duration(run),
        run.finished and "|cff59f28cfull clear|r" or ("%d boss%s"):format(run.bossKills or 0, (run.bossKills or 0) == 1 and "" or "es"),
        run.stop and "" or " (in progress)", run.wipes or 0, (run.wipes or 0) == 1 and "" or "s", #run.deaths, #run.deaths == 1 and "" or "s")
end

local function Members(run)
    local parts = {}
    for full, m in pairs(run.members) do
        local role = m.role or (run.roles and (run.roles.tank == C.Short(full) and "tank" or run.roles.healer == C.Short(full) and "healer"))
        parts[#parts + 1] = C.Colored(full, m.class) .. (role and ("|cffaaaaaa " .. role .. "|r") or "")
    end
    table.sort(parts)
    return table.concat(parts, ", ")
end

local function DeathLine(d)
    local how = d.spell and ("%s%s"):format(d.spell, d.killer and (" from " .. d.killer) or "") or "unknown cause"
    return ("%s died to %s"):format(d.victim, how)
end

-- ---------------------------------------------------------------------------
-- Players
-- ---------------------------------------------------------------------------

local SORTS = { { "recent", "Most recent" }, { "runs", "Most runs" }, { "fault", "Most at fault" }, { "name", "Name" } }

local function CreatePlayersPage()
    local p = NewPage("players")
    p.sort = "recent"
    Label(p, "Players", "GameFontNormalLarge", 0, 0)
    p.summary = Muted(Label(p, "", "GameFontHighlightSmall", 0, -24, 560))
    p.search = W.MakeEditBox(p, 200, "Search...")
    p.search:SetPoint("TOPLEFT", 0, -46)
    p.search:SetScript("OnTextChanged", function() p.Refresh() end)
    p.sortBtn = MakeButton(p, "Most recent", 120, 26); p.sortBtn:SetPoint("LEFT", p.search, "RIGHT", 8, 0)
    p.sortBtn:SetScript("OnClick", function(self)
        for i, s in ipairs(SORTS) do
            if s[1] == p.sort then p.sort = SORTS[i % #SORTS + 1][1]; break end
        end
        p.Refresh()
    end)
    p.list = W.CreateRowList(p, -82)

    -- A player's page.
    local d = CreateFrame("Frame", nil, p); d:SetAllPoints(); d:Hide()
    local back = MakeButton(d, "< Players", 90, 24); back:SetPoint("TOPLEFT", 0, 0)
    back:SetScript("OnClick", function() p.full = nil; p.Refresh() end)
    d.name = Label(d, "", "GameFontNormalLarge", 100, -2, 300)
    d.up = MakeButton(d, "+", 26, 24); d.up:SetPoint("TOPRIGHT", -30, 0)
    d.down = MakeButton(d, "-", 26, 24); d.down:SetPoint("TOPRIGHT", 0, 0)
    d.up:SetScript("OnClick", function() ns.History:SetRating(p.full, 1) end)
    d.down:SetScript("OnClick", function() ns.History:SetRating(p.full, -1) end)
    Hint(d.up, "Thumbs up", "Shown with their history.")
    Hint(d.down, "Thumbs down", "Shown with their history.")
    d.info = Muted(Label(d, "", "GameFontHighlightSmall", 0, -32, 580))
    d.totals = Label(d, "", "GameFontHighlightSmall", 0, -50, 580); d.totals:SetWordWrap(true)
    d.note = W.MakeEditBox(d, 420, "Your note about them (Enter to save)")
    d.note:SetPoint("TOPLEFT", 0, -84)
    d.note:SetScript("OnEnterPressed", function(self) ns.History:SetNote(p.full, self:GetText()); self:ClearFocus() end)
    d.list = W.CreateRowList(d, -118, { rowHeight = 34 })
    p.detail = d

    local function RefreshPlayer()
        local full = p.full
        local rec = ns.History:Get(full)
        if not rec then p.full = nil return p.Refresh() end
        d.name:SetText(C.Colored(full, rec.class))
        d.info:SetText(("%s%s%s  -  first grouped %s, last %s"):format(rec.level and ("Level " .. rec.level .. " ") or "",
            rec.race and (rec.race .. " ") or "", rec.class and rec.class:lower():gsub("^%l", string.upper) or "",
            date("%m/%d/%y", rec.first), rec.last and date("%m/%d/%y", rec.last) or "-") .. (rec.guild and ("  <" .. rec.guild .. ">") or ""))
        d.totals:SetText(ns.History:Summary(full, true) or "")
        if not d.note:HasFocus() then d.note:SetText(rec.note or "") end
        W.SetBackdrop(d.up); W.SetBackdrop(d.down)
        if rec.rating == 1 then d.up:SetBackdropBorderColor(0.35, 0.95, 0.55, 1) end
        if rec.rating == -1 then d.down:SetBackdropBorderColor(0.85, 0.45, 0.42, 1) end
        local items = {}
        for _, run in ipairs(ns.History:RunsWith(full)) do
            items[#items + 1] = {
                noIcon = true, text = "|cffffd24d" .. run.instance .. "|r  " .. RunLine(run),
                detail = Members(run), onClick = function() UI:ShowRun(run.id) end, hint = "Click: open this run",
            }
        end
        local short = C.Short(full)
        for _, e in ipairs(ns.History:DeathsOf(full)) do
            local death = e.death
            local share = death.blame and death.blame[short]
            local text = death.victim == short and ("|cffd9736bDied|r: " .. DeathLine(death))
                or ("|cffffd24d%d%% of the blame|r for %s"):format((share or 0) * 100, DeathLine(death))
            local why = death.reasons and death.reasons[short] and death.reasons[short][1]
            items[#items + 1] = {
                noIcon = true, text = text,
                detail = ("%s, %s  -  %s"):format(e.run.instance, date("%m/%d", death.t or e.run.start),
                    why and ("%s: %s"):format(short, why) or ns.Blame.Summary(death)),
                onClick = function() UI:ShowDeath(e.run.id, death) end, hint = "Click: the hits and the analysis",
            }
        end
        d.list:Set(items, "Nothing recorded yet.")
    end

    p.Refresh = function()
        d:SetShown(p.full ~= nil)
        p.list.scroll:SetShown(not p.full); p.search:SetShown(not p.full); p.sortBtn:SetShown(not p.full)
        p.summary:SetShown(not p.full)
        if p.full then p.list.empty:Hide(); return RefreshPlayer() end
        for _, s in ipairs(SORTS) do if s[1] == p.sort then p.sortBtn.text:SetText(s[2]) end end
        local search = ns.Trim(p.search:GetText()):lower()
        local rows = {}
        for full, rec in pairs(ns.db.players) do
            if search == "" or full:lower():find(search, 1, true) or (rec.note or ""):lower():find(search, 1, true) then
                rows[#rows + 1] = { full = full, rec = rec }
            end
        end
        table.sort(rows, function(a, b)
            if p.sort == "runs" and a.rec.t.runs ~= b.rec.t.runs then return a.rec.t.runs > b.rec.t.runs end
            if p.sort == "fault" then
                local fa, fb = a.rec.t.fault / math.max(1, a.rec.t.runs), b.rec.t.fault / math.max(1, b.rec.t.runs)
                if fa ~= fb then return fa > fb end
            end
            if p.sort == "name" then return a.full < b.full end
            if (a.rec.last or 0) ~= (b.rec.last or 0) then return (a.rec.last or 0) > (b.rec.last or 0) end
            return a.full < b.full
        end)
        local items = {}
        for _, r in ipairs(rows) do
            items[#items + 1] = {
                noIcon = true, text = C.Colored(r.full, r.rec.class) .. (r.rec.level and ("  |cffaaaaaa" .. r.rec.level .. "|r") or ""),
                detail = ns.History:Summary(r.full, false), onClick = function() p.full = r.full; p.Refresh() end,
            }
        end
        p.summary:SetText(("%d players you've run dungeons with."):format(#rows))
        p.list:Set(items, "No dungeon runs recorded yet.\n\nRun a dungeon with a party and everyone in it lands here.")
    end
end

-- ---------------------------------------------------------------------------
-- Runs
-- ---------------------------------------------------------------------------

local function CreateRunsPage()
    local p = NewPage("runs")
    Label(p, "Runs", "GameFontNormalLarge", 0, 0)
    p.summary = Muted(Label(p, "", "GameFontHighlightSmall", 0, -24, 560))
    p.list = W.CreateRowList(p, -50)

    local d = CreateFrame("Frame", nil, p); d:SetAllPoints(); d:Hide()
    local back = MakeButton(d, "< Runs", 80, 24); back:SetPoint("TOPLEFT", 0, 0)
    back:SetScript("OnClick", function() p.runID, p.death = nil, nil; p.Refresh() end)
    d.title = Label(d, "", "GameFontNormalLarge", 90, -2, 480)
    d.text = Label(d, "", "GameFontHighlightSmall", 0, -32, 580); d.text:SetJustifyH("LEFT"); d.text:SetSpacing(2)
    d.list = W.CreateRowList(d, -200, { rowHeight = 40 })
    p.detail = d

    local function RefreshDeath(run, death)
        d.title:SetText(DeathLine(death))
        local lines = { ("%s, %s%s. %s's role: %s."):format(run.instance, date("%m/%d %H:%M:%S", death.t or run.start),
            death.encounter and (", fighting " .. death.encounter) or "", death.victim, death.role or "?") }
        lines[#lines + 1] = ("Analysis (%s): %s"):format(death.confidence and ("%d%% sure"):format(death.confidence * 100) or "?",
            ns.Blame.Summary(death))
        local shares = {}
        for who, share in pairs(death.blame or {}) do shares[#shares + 1] = { who, share } end
        table.sort(shares, function(a, b) return a[2] > b[2] end)
        for _, s in ipairs(shares) do
            lines[#lines + 1] = ("  %s %d%%: %s"):format(s[1], s[2] * 100, table.concat(death.reasons and death.reasons[s[1]] or {}, "; "))
        end
        if death.synced then lines[#lines + 1] = "|cffaaaaaaHits sent by their own Group History.|r" end
        d.text:SetText(table.concat(lines, "\n"))
        local items = {}
        for i = #(death.hits or {}), 1, -1 do
            local h = death.hits[i]
            local hp = h.hp and death.maxHp and death.maxHp > 0 and ("%d%% health"):format(h.hp / death.maxHp * 100) or ""
            items[#items + 1] = {
                noIcon = true, text = (i == #death.hits and "|cffd9736bKilling blow|r  " or "") .. ns.Recap.Describe(h),
                detail = ("%s%s%s"):format(h.rel and ("%.1fs before death  "):format(-h.rel) or "", hp,
                    h.melee and "  melee" or h.periodic and "  over time" or h.env and "  environment" or ""),
            }
        end
        d.list:Set(items, "No hits were readable for this death.")
    end

    local function RefreshRun(run)
        d.title:SetText(run.instance .. (run.finished and "  |cff59f28cfull clear|r" or ""))
        local lines = ns.Popup.RunLines(run)
        table.insert(lines, 2, "With " .. Members(run))
        d.text:SetText(table.concat(lines, "\n"))
        local items = {}
        for _, death in ipairs(run.deaths) do
            items[#items + 1] = {
                noIcon = true, text = ("%s  %s"):format(date("%H:%M", death.t or run.start), DeathLine(death)),
                detail = ns.Blame.Summary(death), onClick = function() p.death = death; p.Refresh() end,
                hint = "Click: the hits and the analysis",
            }
        end
        d.list:Set(items, "Nobody died. Nice.")
    end

    p.Refresh = function()
        local run = p.runID and ns.Run:Get(p.runID)
        d:SetShown(run ~= nil)
        p.list.scroll:SetShown(run == nil); p.summary:SetShown(run == nil)
        if run then
            p.list.empty:Hide()
            if p.death then return RefreshDeath(run, p.death) end
            return RefreshRun(run)
        end
        local items = {}
        for i = #ns.db.runs, 1, -1 do
            local r = ns.db.runs[i]
            items[#items + 1] = {
                noIcon = true, text = "|cffffd24d" .. r.instance .. "|r  " .. RunLine(r), detail = Members(r),
                onClick = function() p.runID, p.death = r.id, nil; p.Refresh() end,
            }
        end
        p.summary:SetText(("%d runs recorded."):format(#ns.db.runs))
        p.list:Set(items, "No dungeon runs recorded yet.")
    end
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

local function CreateSettingsPage()
    local p = NewPage("settings")
    local o = ns.db.options
    Label(p, "Settings", "GameFontNormalLarge", 0, 0)
    local checks = {
        { "popup", "Show the party popup when you join a group", "Your history with each member, as soon as you join." },
        { "whisper", "History line in chat when you whisper someone you know" },
        { "tooltip", "History on player tooltips" },
        { "report", "Report at the end of each run" },
        { "chat", "Print messages in chat" },
    }
    p.boxes = {}
    for i, c in ipairs(checks) do
        local b = W.MakeCheckbox(p, c[2]); b:SetPoint("TOPLEFT", -4, -30 - (i - 1) * 26)
        b:SetScript("OnClick", function(self) o[c[1]] = self:GetChecked() and true or false end)
        if c[3] then Hint(b, c[2], c[3]) end
        p.boxes[c[1]] = b
    end
    local function Number(y, title, key, unit, hint)
        Label(p, title, "GameFontHighlightSmall", 0, y, 220)
        local box = W.MakeEditBox(p, 50, "")
        box:SetPoint("TOPLEFT", 230, y + 6)
        Muted(Label(p, unit, "GameFontHighlightSmall", 290, y, 260))
        box:SetScript("OnEnterPressed", function(self)
            local v = tonumber(self:GetText())
            if v then o[key] = math.max(0, math.floor(v)) end
            self:SetText(tostring(o[key])); self:ClearFocus()
        end)
        Hint(box, title, hint)
        p[key] = box
    end
    Number(-176, "Party popup closes after", "popupSeconds", "seconds (0 = stays open)", "It stays open while your mouse is over it.")
    Number(-202, "Over-pull at", "overpull", "mobs in combat at once", "A pull with this many mobs counts as an over-pull when blaming deaths.")
    Muted(Label(p, "How blame works: every death is checked against what the game lets addons see on this client: the death's last hits (who, what, melee or not), Blizzard's damage meter for the fight (damage, healing, avoidable damage, interrupts), who pulled, how many mobs came, and who died first. Each rule that fits gives someone a share with a reason. It's a best guess; the death page says how sure it is.",
        "GameFontHighlightSmall", 0, -240, 560)):SetWordWrap(true)
    p.Refresh = function()
        for key, b in pairs(p.boxes) do b:SetChecked(o[key]) end
        for _, key in ipairs({ "popupSeconds", "overpull" }) do if not p[key]:HasFocus() then p[key]:SetText(tostring(o[key])) end end
    end
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------

local function ShowTab(name)
    activeTab = name
    for key, pg in pairs(pages) do pg:SetShown(key == name) end
    for key, b in pairs(tabs) do
        b.selected:SetShown(key == name)
        b:SetBackdropColor(key == name and 0.09 or 0.075, key == name and 0.15 or 0.105, key == name and 0.17 or 0.13, 1)
    end
end

local function CreateMainFrame()
    if frame then return end
    frame = CreateFrame("Frame", "GroupHistoryWindow", UIParent, "BackdropTemplate")
    frame:SetSize(800, 560); frame:SetFrameStrata("DIALOG"); frame:SetToplevel(true)
    frame:SetClampedToScreen(true); frame:SetMovable(true); frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton"); SetBackdrop(frame, 0.985)
    local w = ns.char.window
    frame:SetPoint(w.point or "CENTER", UIParent, w.point or "CENTER", w.x or 0, w.y or 0)
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        ns.char.window = { point = point, x = x, y = y }
    end)
    frame:SetScript("OnShow", function() UI:Refresh() end)
    tinsert(UISpecialFrames, "GroupHistoryWindow")

    local logo = frame:CreateTexture(nil, "ARTWORK"); logo:SetSize(38, 38)
    logo:SetPoint("TOPLEFT", 20, -17); logo:SetTexture(ns.ICON)
    Label(frame, "Group History", "GameFontNormalLarge", 70, -20):SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    Muted(Label(frame, "Everyone you've run dungeons with, and how it went", "GameFontHighlightSmall", 70, -42))
    local close = MakeButton(frame, "X", 28, 26); close:SetPoint("TOPRIGHT", -18, -18)
    close:SetScript("OnClick", function() frame:Hide() end)

    local side = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    side:SetPoint("TOPLEFT", 14, -74); side:SetPoint("BOTTOMLEFT", 14, 14); side:SetWidth(165)
    SetBackdrop(side); side:SetBackdropColor(0.045, 0.065, 0.085, 1)
    for i, d in ipairs(TABS) do
        local b = MakeButton(side, d[2], 147, 40); b:SetPoint("TOPLEFT", 9, -12 - (i - 1) * 46)
        b.text:ClearAllPoints(); b.text:SetPoint("LEFT", 40, 0)
        local icon = b:CreateTexture(nil, "ARTWORK"); icon:SetSize(23, 23); icon:SetPoint("LEFT", 9, 0)
        icon:SetTexture("Interface\\Icons\\" .. d[3]); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.selected = b:CreateTexture(nil, "OVERLAY"); b.selected:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
        b.selected:SetPoint("TOPLEFT"); b.selected:SetPoint("BOTTOMLEFT"); b.selected:SetWidth(3)
        b:SetScript("OnLeave", function(self) if activeTab ~= d[1] then self:SetBackdropColor(0.075, 0.105, 0.13, 1) end end)
        b:SetScript("OnClick", function() ShowTab(d[1]); UI:Refresh() end)
        tabs[d[1]] = b
    end
    side.current = Muted(Label(side, "", "GameFontHighlightSmall", 12, -20 - #TABS * 46, 145))
    Label(side, "v" .. ns.VERSION, "GameFontHighlightSmall", 12, -450, 145):SetTextColor(0.38, 0.50, 0.57)
    UI.side = side

    CreatePlayersPage(); CreateRunsPage(); CreateSettingsPage()
    ShowTab(activeTab); frame:Hide()
end

function UI:Refresh()
    if not (ns.db and frame and frame:IsShown()) then return end
    local run = ns.Run.current
    UI.side.current:SetText(run and ("In a run:\n|cffffffff%s|r\n%d fights, %d deaths"):format(run.instance, #run.fights, #run.deaths) or "")
    local p = pages[activeTab]
    if p and p.Refresh then p.Refresh() end
end

function UI:Toggle()
    if not ns.db then return end
    CreateMainFrame()
    frame:SetShown(not frame:IsShown())
end

function UI:ShowPlayer(full)
    if not ns.db then return end
    CreateMainFrame()
    if full and not ns.History:Get(full) then full = nil end
    pages.players.full = full
    ShowTab("players"); frame:Show(); self:Refresh()
    if not full then ns:Print("No history with that player.", true) end
end

function UI:ShowRun(id)
    if not ns.db then return end
    CreateMainFrame()
    pages.runs.runID, pages.runs.death = id, nil
    ShowTab("runs"); frame:Show(); self:Refresh()
end

function UI:ShowDeath(runID, death)
    if not ns.db then return end
    CreateMainFrame()
    pages.runs.runID, pages.runs.death = runID, death
    ShowTab("runs"); frame:Show(); self:Refresh()
end
