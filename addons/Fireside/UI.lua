local _, ns = ...
local C = ns.Compat

-- The Fireside window: the Campfire (Campfire.lua: the end of a run, where the party thanks
-- each other), People (everyone you've run with: what they're known for, and each one's page),
-- the Mirror (Mirror.lua: what people have told you), Runs (each run's bosses, wipes and deaths,
-- and each death's hits and analysis, for your eyes only) and Settings. Same frame and sidebar as
-- Wally's window.
local UI = {}
ns.UI = UI

local W = ns.Widgets
local Label, Muted, MakeButton, Hint = W.Label, W.Muted, W.MakeButton, W.Hint

local win -- the window (shared\Window.lua), made under "Window" below
local TABS = {
    { "campfire", "Campfire", "Spell_Fire_Fire" },
    { "players", "People", "INV_Misc_GroupNeedMore" },
    { "mirror", "Mirror", "INV_Misc_Note_01" },
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

local SORTS = { { "recent", "Most recent" }, { "praised", "Most praised" }, { "runs", "Most runs" }, { "name", "Name" } }

local function CreatePlayersPage()
    local p = NewPage("players")
    p.sort = "recent"
    Label(p, "People", "FiresideGameFontNormalLarge", 0, 0)
    p.summary = Muted(Label(p, "", "FiresideGameFontHighlightSmall", 0, -24, 560))
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
    d.name = Label(d, "", "FiresideGameFontNormalLarge", 100, -2, 260)
    -- Would you group with them again: your own, private answer (shown only to you, with their history).
    d.again = Muted(Label(d, "Group again?", "FiresideGameFontHighlightSmall", 0, -6, 90))
    d.again:ClearAllPoints(); d.again:SetPoint("TOPRIGHT", -112, -6); d.again:SetJustifyH("RIGHT")
    d.up = MakeButton(d, "Yes", 50, 24); d.up:SetPoint("TOPRIGHT", -56, 0)
    d.down = MakeButton(d, "No", 50, 24); d.down:SetPoint("TOPRIGHT", 0, 0)
    d.up:SetScript("OnClick", function() ns.History:SetRating(p.full, 1) end)
    d.down:SetScript("OnClick", function() ns.History:SetRating(p.full, -1) end)
    Hint(d.up, "Would group again", "Private: only you see it, next to their name. Click again to clear.")
    Hint(d.down, "Wouldn't group again", "Private: only you see it, next to their name. Nothing is sent to anyone.")
    d.info = Muted(Label(d, "", "FiresideGameFontHighlightSmall", 0, -32, 580))
    d.known = Label(d, "", "FiresideGameFontHighlight", 0, -52, 580); d.known:SetWordWrap(true)
    d.sources = Muted(Label(d, "", "FiresideGameFontHighlightSmall", 0, -72, 580)); d.sources:SetWordWrap(true)
    d.totals = Label(d, "", "FiresideGameFontHighlightSmall", 0, -90, 580); d.totals:SetWordWrap(true)
    d.note = W.MakeEditBox(d, 420, "Your private note about them (Enter to save)")
    d.note:SetPoint("TOPLEFT", 0, -112)
    d.note:SetScript("OnEnterPressed", function(self) ns.History:SetNote(p.full, self:GetText()); self:ClearFocus() end)
    d.fire = MakeButton(d, "Your last fire", 110, 26); d.fire:SetPoint("LEFT", d.note, "RIGHT", 8, 0)
    d.fire:SetScript("OnClick", function()
        local runs = ns.History:RunsWith(p.full)
        if runs[1] then ns.Campfire:Open(runs[1].id) end
    end)
    Hint(d.fire, "Your last fire together", "The campfire of your last run with them: kudos and notes still reach them.")
    d.list = W.CreateRowList(d, -146, { rowHeight = 34 })
    p.detail = d

    -- Each line sits under the one above, however many lines the kudos and the private read wrap to.
    local function PlaceBelowTotals()
        local y = -52
        for _, fs in ipairs({ d.known, d.sources, d.totals }) do
            fs:SetPoint("TOPLEFT", 0, y)
            local h = (fs:GetText() or "") ~= "" and math.ceil(fs:GetStringHeight() or 0) + 6 or 0
            y = y - h
        end
        local noteTop = math.min(-112, y - 4)
        d.note:SetPoint("TOPLEFT", 0, noteTop)
        d.list.scroll:SetPoint("TOPLEFT", 0, noteTop - 34)
        d.list.empty:SetPoint("TOPLEFT", 0, noteTop - 94)
    end

    -- Where what they're known for comes from.
    local function Sources(full, rec)
        local mine, heard, givers = 0, 0, {}
        for _, n in pairs(rec.given or {}) do mine = mine + n end
        for giver, h in pairs(rec.heard or {}) do
            for _, n in pairs(type(h) == "table" and h.marks or {}) do
                heard = heard + n
                givers[giver] = true
            end
        end
        local g = 0
        for _ in pairs(givers) do g = g + 1 end
        local parts = {}
        if mine > 0 then parts[#parts + 1] = ("%d kudo%s from you"):format(mine, mine == 1 and "" or "s") end
        if heard > 0 then parts[#parts + 1] = ("%d from %d other player%s (told to your party)"):format(heard, g, g == 1 and "" or "s") end
        local b = rec.banner
        if b and b.marks and next(b.marks) then
            local n = 0
            for _, e in pairs(b.marks) do n = n + (e.n or 0) end
            parts[#parts + 1] = ("their own record says %d in all (as of %s)"):format(n, date("%m/%d", b.t or time()))
        end
        return #parts > 0 and table.concat(parts, ";  ") or nil
    end

    local function RefreshPlayer()
        local full = p.full
        local rec = ns.History:Get(full)
        if not rec then p.full = nil return p.Refresh() end
        d.name:SetText(C.Colored(full, rec.class))
        d.info:SetText(("%s%s%s  -  first grouped %s, last %s"):format(rec.level and ("Level " .. rec.level .. " ") or "",
            rec.race and (rec.race .. " ") or "", rec.class and rec.class:lower():gsub("^%l", string.upper) or "",
            date("%m/%d/%y", rec.first), rec.last and date("%m/%d/%y", rec.last) or "-") .. (rec.guild and ("  <" .. rec.guild .. ">") or ""))
        local known = ns.Marks.KnownLine(full, 6, 16)
        d.known:SetText(known and ("Known for  " .. known) or "|cffaaaaaaNot known for anything yet: kudos given at the campfire show up here.|r")
        local sources = Sources(full, rec)
        d.sources:SetText(sources or "")
        local private = ns.History:Private(full)
        d.totals:SetText(private and ("|cffaaaaaaOnly you see this:|r " .. private) or "")
        PlaceBelowTotals()
        d.fire:SetShown(rec.runs and #rec.runs > 0)
        if not d.note:HasFocus() then d.note:SetText(rec.note or "") end
        W.SetBackdrop(d.up); W.SetBackdrop(d.down)
        local bc = ns.Palette.button
        d.up:SetBackdropColor(bc[1], bc[2], bc[3], 1); d.down:SetBackdropColor(bc[1], bc[2], bc[3], 1)
        if rec.rating == 1 then d.up:SetBackdropBorderColor(0.35, 0.95, 0.55, 1) end
        if rec.rating == -1 then d.down:SetBackdropBorderColor(0.85, 0.45, 0.42, 1) end
        local items = {}
        -- Your jots about them (Hearth.lua), newest first: private.
        for i = #(rec.jots or {}), 1, -1 do
            local j = rec.jots[i]
            local run = j.run and ns.Run:Get(j.run)
            items[#items + 1] = {
                icon = "Interface\\Icons\\INV_Misc_Note_01", text = "|cffffd24d" .. j.text .. "|r",
                detail = ("Your jot, %s%s (only you see it)"):format(date("%m/%d %H:%M", j.t), run and (", " .. run.instance) or ""),
                onClick = run and function() ns.Campfire:Open(run.id) end or nil, hint = run and "Click: that run's campfire" or nil,
            }
        end
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
                or ("|cffffd24d%d%% likely cause|r of %s"):format((share or 0) * 100, DeathLine(death))
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
                rows[#rows + 1] = { full = full, rec = rec, praise = p.sort == "praised" and ns.Marks.Praise(full) or 0 }
            end
        end
        table.sort(rows, function(a, b)
            if p.sort == "runs" and a.rec.t.runs ~= b.rec.t.runs then return a.rec.t.runs > b.rec.t.runs end
            if p.sort == "praised" and a.praise ~= b.praise then return a.praise > b.praise end
            if p.sort == "name" then return a.full < b.full end
            if (a.rec.last or 0) ~= (b.rec.last or 0) then return (a.rec.last or 0) > (b.rec.last or 0) end
            return a.full < b.full
        end)
        local items = {}
        local ran = 0
        for _, r in ipairs(rows) do
            if r.rec.t.runs > 0 then ran = ran + 1 end
            local known = ns.Marks.KnownFor(r.full)[1]
            items[#items + 1] = {
                icon = known and ns.Marks.IconPath(known.id), noIcon = not known,
                text = C.Colored(r.full, r.rec.class) .. (r.rec.level and ("  |cffaaaaaa" .. r.rec.level .. "|r") or ""),
                detail = ns.History:Summary(r.full, false) or "|cffaaaaaaHeard about at a campfire; you haven't run together.|r",
                onClick = function() p.full = r.full; p.Refresh() end,
            }
        end
        p.summary:SetText(("%d people you've run dungeons with%s."):format(ran,
            #rows > ran and (", and %d more you've heard about"):format(#rows - ran) or ""))
        p.list:Set(items, "No dungeon runs recorded yet.\n\nRun a dungeon with a party and everyone in it lands here.")
    end
end

-- ---------------------------------------------------------------------------
-- Runs
-- ---------------------------------------------------------------------------

local function CreateRunsPage()
    local p = NewPage("runs")
    Label(p, "Runs", "FiresideGameFontNormalLarge", 0, 0)
    p.summary = Muted(Label(p, "", "FiresideGameFontHighlightSmall", 0, -24, 560))
    p.list = W.CreateRowList(p, -50)

    local d = CreateFrame("Frame", nil, p); d:SetAllPoints(); d:Hide()
    local back = MakeButton(d, "< Runs", 80, 24); back:SetPoint("TOPLEFT", 0, 0)
    back:SetScript("OnClick", function() p.runID, p.death = nil, nil; p.Refresh() end)
    d.title = Label(d, "", "FiresideGameFontNormalLarge", 90, -2, 480)
    d.text = Label(d, "", "FiresideGameFontHighlightSmall", 0, -32, 580); d.text:SetJustifyH("LEFT"); d.text:SetSpacing(2)
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
        if death.synced then lines[#lines + 1] = "|cffaaaaaaHits sent by their own Fireside.|r" end
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

-- Through ns:SetOption, so Options > AddOns > Fireside (Settings.lua) shows the same values.
local function CreateSettingsPage()
    local p = NewPage("settings")
    local o = ns.db.options
    Label(p, "Settings", "FiresideGameFontNormalLarge", 0, 0)
    local checks = {
        { "popup", "Show the party popup when you join a group", "Who's in your party: what each is known for, and your history with them." },
        { "whisper", "History line in chat when you whisper someone you know" },
        { "tooltip", "History on player tooltips" },
        { "report", "Open the campfire at the end of each run", "At the last boss, while the party is still together (else when the run ends)." },
        { "shareKudos", "Tell my party the kudos I've given", "When someone joins, your party hears the kudos you've given the others: testimony. Only kudos: never notes, ratings or anything negative." },
        { "shareBanner", "Show my party the kudos I've received", "Your own record, so people new to you see what you're known for." },
        { "hearth", "Show the Hearth while in a party", "A slim strip with your party's portraits: left-click someone to send a spark (a small thanks), right-click to jot a note for the campfire." },
        { "prompts", "Offer a spark after a fight", "When the data saw someone do something worth a thank-you, a toast under the Hearth offers the spark in one click." },
        { "acceptTips", "Accept private notes", "Keep / try notes from the people you group with. Off: senders are told you've turned them off." },
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
        Label(p, title, "FiresideGameFontHighlightSmall", 0, y, 220)
        local box = W.MakeEditBox(p, 50, "")
        box:SetPoint("TOPLEFT", 230, y + 6)
        Muted(Label(p, unit, "FiresideGameFontHighlightSmall", 290, y, 260))
        box:SetScript("OnEnterPressed", function(self)
            local v = tonumber(self:GetText())
            if v then ns:SetOption("db.options." .. key, math.max(0, math.floor(v))) end
            self:SetText(tostring(o[key])); self:ClearFocus()
        end)
        Hint(box, title, hint)
        p[key] = box
    end
    Number(-308, "Party popup closes after", "popupSeconds", "seconds (0 = stays open)", "It stays open while your mouse is over it.")
    Number(-334, "Over-pull at", "overpull", "mobs in combat at once", "A pull with this many mobs counts as an over-pull when analysing deaths.")
    Muted(Label(p, "Praise in public, critique in private: kudos are seen by your party and travel with people as testimony; a note's \"try\" half reaches only its player. Who likely caused each death (the death's last hits, Blizzard's damage meter, who pulled, how many mobs came) stays on your own run and death pages, and turns into the campfire's lessons without names.",
        "FiresideGameFontHighlightSmall", 0, -368, 560)):SetWordWrap(true)
    p.Refresh = function()
        for key, b in pairs(p.boxes) do b:SetChecked(o[key]) end
        for _, key in ipairs({ "popupSeconds", "overpull" }) do if not p[key]:HasFocus() then p[key]:SetText(tostring(o[key])) end end
    end
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------

win = ns.NewWindow({
    name = "FiresideWindow", title = "Fireside", subtitle = "Thank the people you run with, and hear what they'd tell you",
    tabs = TABS, active = "campfire",
    refresh = function() UI:Refresh() end,
    decorate = function(_, side, count)
        side.current = Muted(Label(side, "", "FiresideGameFontHighlightSmall", 12, -20 - count * 46, 145))
        UI.side = side
    end,
    build = function()
        ns.Campfire.Build(win); CreatePlayersPage(); ns.Mirror.Build(win); CreateRunsPage(); CreateSettingsPage()
    end,
})
UI.window = win

function UI:Refresh()
    if not (ns.db and win:IsShown()) then return end
    local run = ns.Run.current
    local lines = {}
    if run then lines[#lines + 1] = ("In a run:\n|cffffffff%s|r\n%d fights, %d deaths"):format(run.instance, #run.fights, #run.deaths) end
    local unread = ns.Feedback.Unread()
    if unread > 0 then lines[#lines + 1] = ("|cffffd24d%d new note%s|r in the Mirror"):format(unread, unread == 1 and "" or "s") end
    UI.side.current:SetText(table.concat(lines, "\n\n"))
    win:Refresh()
end

function UI:ShowCampfire()
    if not ns.db then return end
    win:Build()
    win:Show("campfire")
end

function UI:ShowMirror(view)
    if not ns.db then return end
    win:Build()
    ns.Mirror:Show(view)
    win:Show("mirror")
end

function UI:Toggle()
    if not ns.db then return end
    win:Toggle()
end

-- quiet: just the list (no "no history" message when full is nil).
function UI:ShowPlayer(full, quiet)
    if not ns.db then return end
    win:Build()
    if full and not ns.History:Get(full) then full = nil end
    win.pages.players.full = full
    win:Show("players")
    if not full and not quiet then ns:Print("No history with that player.", true) end
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
