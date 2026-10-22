local _, ns = ...
local C = ns.Compat

-- The Group History window: Players (everyone you've run with, and each one's page), Runs (each
-- run's bosses, wipes and deaths, and each death's hits and blame), and Settings. Same frame and
-- sidebar as Wally's window.
local UI = {}
ns.UI = UI

local W = ns.Widgets
local Label, Muted, MakeButton, Hint = W.Label, W.Muted, W.MakeButton, W.Hint

local win -- the window (shared\Window.lua), made under "Window" below
local TABS = {
    { "players", "Players", "INV_Misc_GroupNeedMore" },
    { "runs", "Runs", "INV_Misc_Map_01" },
    { "settings", "Settings", "INV_Misc_Gear_01" },
}

local function NewPage(name) return win:NewPage(name) end

local DURATION = { days = false, alwaysHours = true }
local function Duration(run) return ns.Format.Duration((run.stop or time()) - run.start, DURATION) end

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
    Label(p, "Players", "GroupHistoryGameFontNormalLarge", 0, 0)
    p.summary = Muted(Label(p, "", "GroupHistoryGameFontHighlightSmall", 0, -24, 560))
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
    d.name = Label(d, "", "GroupHistoryGameFontNormalLarge", 100, -2, 300)
    d.up = MakeButton(d, "+", 26, 24); d.up:SetPoint("TOPRIGHT", -30, 0)
    d.down = MakeButton(d, "-", 26, 24); d.down:SetPoint("TOPRIGHT", 0, 0)
    d.up:SetScript("OnClick", function() ns.History:SetRating(p.full, 1) end)
    d.down:SetScript("OnClick", function() ns.History:SetRating(p.full, -1) end)
    Hint(d.up, "Thumbs up", "Shown with their history.")
    Hint(d.down, "Thumbs down", "Shown with their history.")
    d.info = Muted(Label(d, "", "GroupHistoryGameFontHighlightSmall", 0, -32, 580))
    d.totals = Label(d, "", "GroupHistoryGameFontHighlightSmall", 0, -50, 580); d.totals:SetWordWrap(true)
    d.note = W.MakeEditBox(d, 420, "Your note about them (Enter to save)")
    d.note:SetPoint("TOPLEFT", 0, -84)
    d.note:SetScript("OnEnterPressed", function(self) ns.History:SetNote(p.full, self:GetText()); self:ClearFocus() end)
    d.list = W.CreateRowList(d, -118, { rowHeight = 34 })
    p.detail = d

    -- The note box and the list sit under the totals (at -84 and -118, or lower when the totals and
    -- a long note wrap onto more lines).
    local function PlaceBelowTotals()
        local noteTop = math.min(-84, -50 - math.ceil(d.totals:GetStringHeight() or 0) - 8)
        d.note:SetPoint("TOPLEFT", 0, noteTop)
        d.list.scroll:SetPoint("TOPLEFT", 0, noteTop - 34)
        d.list.empty:SetPoint("TOPLEFT", 0, noteTop - 94)
    end

    local function RefreshPlayer()
        local full = p.full
        local rec = ns.History:Get(full)
        if not rec then p.full = nil return p.Refresh() end
        d.name:SetText(C.Colored(full, rec.class))
        d.info:SetText(("%s%s%s  -  first grouped %s, last %s"):format(rec.level and ("Level " .. rec.level .. " ") or "",
            rec.race and (rec.race .. " ") or "", rec.class and rec.class:lower():gsub("^%l", string.upper) or "",
            date("%m/%d/%y", rec.first), rec.last and date("%m/%d/%y", rec.last) or "-") .. (rec.guild and ("  <" .. rec.guild .. ">") or ""))
        d.totals:SetText(ns.History:Summary(full, true) or "")
        PlaceBelowTotals()
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
            local share = ns.History.ByName(death.blame, short)
            local text = (death.victim == short or C.SameName(death.victim, short)) and ("|cffd9736bDied|r: " .. DeathLine(death))
                or ("|cffffd24d%d%% of the blame|r for %s"):format((share or 0) * 100, DeathLine(death))
            local reasons = ns.History.ByName(death.reasons, short)
            local why = reasons and reasons[1]
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
    Label(p, "Runs", "GroupHistoryGameFontNormalLarge", 0, 0)
    p.summary = Muted(Label(p, "", "GroupHistoryGameFontHighlightSmall", 0, -24, 560))
    p.list = W.CreateRowList(p, -50)

    local d = CreateFrame("Frame", nil, p); d:SetAllPoints(); d:Hide()
    local back = MakeButton(d, "< Runs", 80, 24); back:SetPoint("TOPLEFT", 0, 0)
    back:SetScript("OnClick", function() p.runID, p.death = nil, nil; p.Refresh() end)
    d.title = Label(d, "", "GroupHistoryGameFontNormalLarge", 90, -2, 480)
    d.text = Label(d, "", "GroupHistoryGameFontHighlightSmall", 0, -32, 580); d.text:SetJustifyH("LEFT"); d.text:SetSpacing(2)
    d.list = W.CreateRowList(d, -200, { rowHeight = 40 })
    p.detail = d

    -- The list starts under the text (at -200, or lower): a run with many bosses, or a death blamed
    -- on several players (full "Given Family" names), runs past 12 lines.
    local function PlaceList()
        local top = math.min(-200, -32 - math.ceil(d.text:GetStringHeight() or 0) - 12)
        d.list.scroll:SetPoint("TOPLEFT", 0, top)
        d.list.empty:SetPoint("TOPLEFT", 0, top - 60)
    end

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
        PlaceList()
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
        PlaceList()
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

-- Through ns:SetOption, so Options > AddOns > Group History (Settings.lua) shows the same values.
local function CreateSettingsPage()
    local p = NewPage("settings")
    local o = ns.db.options
    Label(p, "Settings", "GroupHistoryGameFontNormalLarge", 0, 0)
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
        b:SetScript("OnClick", function(self) ns:SetOption("db.options." .. c[1], self:GetChecked() and true or false) end)
        if c[3] then Hint(b, c[2], c[3]) end
        p.boxes[c[1]] = b
    end
    local function Number(y, title, key, unit, hint)
        Label(p, title, "GroupHistoryGameFontHighlightSmall", 0, y, 220)
        local box = W.MakeEditBox(p, 50, "")
        box:SetPoint("TOPLEFT", 230, y + 6)
        Muted(Label(p, unit, "GroupHistoryGameFontHighlightSmall", 290, y, 260))
        box:SetScript("OnEnterPressed", function(self)
            local v = tonumber(self:GetText())
            if v then ns:SetOption("db.options." .. key, math.max(0, math.floor(v))) end
            self:SetText(tostring(o[key])); self:ClearFocus()
        end)
        Hint(box, title, hint)
        p[key] = box
    end
    Number(-176, "Party popup closes after", "popupSeconds", "seconds (0 = stays open)", "It stays open while your mouse is over it.")
    Number(-202, "Over-pull at", "overpull", "mobs in combat at once", "A pull with this many mobs counts as an over-pull when blaming deaths.")
    Muted(Label(p, "How blame works: every death is checked against what the game lets addons see on this client: the death's last hits (who, what, melee or not), Blizzard's damage meter for the fight (damage, healing, avoidable damage, interrupts), who pulled, how many mobs came, and who died first. Each rule that fits gives someone a share with a reason. It's a best guess; the death page says how sure it is.",
        "GroupHistoryGameFontHighlightSmall", 0, -240, 560)):SetWordWrap(true)
    p.Refresh = function()
        for key, b in pairs(p.boxes) do b:SetChecked(o[key]) end
        for _, key in ipairs({ "popupSeconds", "overpull" }) do if not p[key]:HasFocus() then p[key]:SetText(tostring(o[key])) end end
    end
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------

win = ns.NewWindow({
    name = "GroupHistoryWindow", title = "Group History", subtitle = "Everyone you've run dungeons with, and how it went",
    tabs = TABS, active = "players",
    refresh = function() UI:Refresh() end,
    decorate = function(_, side, count)
        side.current = Muted(Label(side, "", "GroupHistoryGameFontHighlightSmall", 12, -20 - count * 46, 145))
        UI.side = side
    end,
    build = function() CreatePlayersPage(); CreateRunsPage(); CreateSettingsPage() end,
})
UI.window = win

function UI:Refresh()
    if not (ns.db and win:IsShown()) then return end
    local run = ns.Run.current
    UI.side.current:SetText(run and ("In a run:\n|cffffffff%s|r\n%d fights, %d deaths"):format(run.instance, #run.fights, #run.deaths) or "")
    win:Refresh()
end

function UI:Toggle()
    if not ns.db then return end
    win:Toggle()
end

function UI:ShowPlayer(full)
    if not ns.db then return end
    win:Build()
    if full and not ns.History:Get(full) then full = nil end
    win.pages.players.full = full
    win:Show("players")
    if not full then ns:Print("No history with that player.", true) end
end

function UI:ShowRun(id)
    if not ns.db then return end
    win:Build()
    win.pages.runs.runID, win.pages.runs.death = id, nil
    win:Show("runs")
end

function UI:ShowDeath(runID, death)
    if not ns.db then return end
    win:Build()
    win.pages.runs.runID, win.pages.runs.death = runID, death
    win:Show("runs")
end
