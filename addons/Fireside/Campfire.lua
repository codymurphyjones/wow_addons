local _, ns = ...
local C = ns.Compat

-- The Campfire: where a run comes together at the end. Everyone who was part of it sits in a ring
-- around a fire: the party as it is now, and everyone who left on the way (kicked or gone, and those
-- who left while the group formed, Run.lua's session), however many that is. Each seat shows what the
-- data saw them do well, the kudos and sparks (Hearth.lua) they collected, and your jots about them.
-- You thank people by dragging a kudo from the tray onto their seat (or picking one and clicking
-- them); everyone in the party with Fireside sees it fly across the fire, and theirs fly to you. A
-- seat's glowing badge is the kudo the data (and the sparks you sent) suggest.
-- "Go round the fire" (or right-click a seat) takes you through everyone, one at a time: their
-- moments, sparks and your jots, kudos in one click, and a private note: a kudo to keep with one
-- thing to try and/or your own words (only they ever see it). In the middle, the fire tells the
-- run's lessons for everyone, with no names. Opens itself at the last boss, while the party is still
-- together; /fire opens it any time, and kudos and notes for people who left still reach them.
local CF = {}
ns.Campfire = CF

local W = ns.Widgets
local Label, Muted, MakeButton, Hint = W.Label, W.Muted, W.MakeButton, W.Hint
local ACCENT = W.ACCENT
local M, Mo, F = ns.Marks, ns.Moments, ns.Feedback

local SMALL, NORMAL, LARGE = "FiresideGameFontHighlightSmall", "FiresideGameFontNormal", "FiresideGameFontNormalLarge"
local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local FIRE = "Interface\\Icons\\Spell_Fire_Fire"
local NOTE = "Interface\\Icons\\INV_Misc_Note_01"
local CX, CY, RX, RY = 293, -186, 210, 102 -- the ring: centre and radii, from the page's top left
local TOKEN, TOKEN_GAP = 32, 6
local FLIGHT = 0.9
-- Seat sizes as the ring fills: { up to n seats, width, portrait, show the moment line }.
local SIZES = { { 6, 150, 46, true }, { 9, 112, 40, true }, { 99, 88, 32, false } }

local page
local state = { runID = nil, picked = nil, status = nil }

-- ---------------------------------------------------------------------------
-- Which run, who sits where
-- ---------------------------------------------------------------------------

local function CurrentRun()
    return (state.runID and ns.Run:Get(state.runID)) or F.LiveRun() or ns.db.runs[#ns.db.runs]
end
CF.CurrentRun = CurrentRun

local function RoleIn(run, full, m)
    local short = C.Short(full)
    local tank, healer = ns.Blame.Roles(run)
    if m and m.role then return m.role end
    if short == tank then return "tank" end
    if short == healer then return "healer" end
    return "damage"
end

-- Everyone at the fire: who's still with you, then who left (in the order they left), then you
-- (seated at the bottom). { full, short, class, role, left, before, me }.
local function Seats(run)
    local here, gone = {}, {}
    for full, m in pairs(run.members or {}) do
        local seat = { full = full, short = C.Short(full), class = m.class, role = RoleIn(run, full, m), left = m.left, before = m.before }
        if m.left then gone[#gone + 1] = seat else here[#here + 1] = seat end
    end
    table.sort(here, function(a, b) return (a.short or "") < (b.short or "") end)
    table.sort(gone, function(a, b) return (a.left or 0) < (b.left or 0) end)
    for _, s in ipairs(gone) do here[#here + 1] = s end
    local myClass = run.me and C.IsMe(run.me) and select(2, UnitClass("player")) or nil
    here[#here + 1] = { full = run.me, short = C.Short(run.me), class = myClass, role = RoleIn(run, run.me or ""), me = true }
    return here
end
CF.Seats = Seats

-- "left 12:40", "left before the run"
local function LeftText(seat)
    if seat.before then return "left before the run" end
    if seat.left then return "left " .. date("%H:%M", seat.left) end
end

-- The unit token of someone in your group now (for a live portrait).
local function UnitOf(full)
    if not full then return nil end
    if C.IsMe(full) then return "player" end
    for _, unit in ipairs(C.GroupUnits()) do
        if C.SameName(C.UnitFull(unit), full) then return unit end
    end
end

-- ---------------------------------------------------------------------------
-- Drawing helpers
-- ---------------------------------------------------------------------------

local function Round(tex, parent)
    if not (parent.CreateMaskTexture and tex.AddMaskTexture) then return end
    local mask = parent:CreateMaskTexture()
    mask:SetTexture(ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(tex)
    tex:AddMaskTexture(mask)
end

local function SetPortrait(tex, seat)
    tex:SetTexCoord(0, 1, 0, 1)
    local unit = UnitOf(seat.full)
    if unit and SetPortraitTexture and C.Bool(C.Call(UnitIsVisible, unit)) then
        SetPortraitTexture(tex, unit)
        return
    end
    local coords = CLASS_ICON_TCOORDS and seat.class and CLASS_ICON_TCOORDS[seat.class]
    if coords then
        tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
end

local function Status(text)
    state.status = text
    if page and page.status then page.status:SetText(text or "") end
end

local function Count(t)
    local n = 0
    for _, list in pairs(t) do n = n + #list end
    return n
end

-- "Nice pull x3 (you 2, Carol)" for a seat's sparks.
local function SparkLines(sparks)
    local lines = {}
    for s, from in pairs(sparks) do
        local by = {}
        for _, n in ipairs(from) do
            local who = C.IsMe(n) and "you" or C.Short(n)
            by[who] = (by[who] or 0) + 1
        end
        local parts = {}
        for who, n in pairs(by) do parts[#parts + 1] = n > 1 and (who .. " " .. n) or who end
        table.sort(parts)
        lines[#lines + 1] = ("%s %s%s  |cffaaaaaa(%s)|r"):format(M.SparkIcon(s), M.SparkLabel(s), #from > 1 and (" x" .. #from) or "",
            table.concat(parts, ", "))
    end
    table.sort(lines)
    return lines
end

-- ---------------------------------------------------------------------------
-- Giving
-- ---------------------------------------------------------------------------

local WHY = {
    self = "Kudos are for the others: yours land on your seat.",
    given = "You've already given them that one this run.",
    unknown = "That kudo isn't known.",
}

local function GiveTo(seat, k)
    if not (seat and k) then return end
    local run = CurrentRun()
    if seat.me then return Status(WHY.self) end
    local ok, why = F:Give(run, seat.full, k)
    if ok then
        local live = C.InGroup(seat.full)
        Status(("%s %s to %s%s"):format(M.Icon(k), M.Label(k), seat.short,
            live and "" or "  |cffaaaaaa(they've left the group: it goes to them directly)|r"))
    else
        Status(WHY[why] or "Couldn't give that.")
    end
    state.picked = nil
end

-- ---------------------------------------------------------------------------
-- Flights: a kudo (or spark) crossing the fire
-- ---------------------------------------------------------------------------

local flights = {}

local function SeatFor(name)
    for _, s in ipairs(page and page.seats or {}) do
        if s:IsShown() and s.seat and name and C.SameName(s.seat.full, name) then return s end
    end
end

local function SeatCentre(s)
    if not s then return CX, CY + 10 end
    return s.cx, s.cy
end

local function NewFlight()
    for _, f in ipairs(flights) do if not f:IsShown() then return f end end
    local f = CreateFrame("Frame", nil, page)
    f:SetSize(28, 28); f:SetFrameLevel(page:GetFrameLevel() + 15)
    f.icon = f:CreateTexture(nil, "OVERLAY"); f.icon:SetAllPoints()
    Round(f.icon, f)
    f.glow = f:CreateTexture(nil, "BACKGROUND"); f.glow:SetPoint("CENTER"); f.glow:SetSize(52, 52)
    f.glow:SetTexture(FIRE); f.glow:SetBlendMode("ADD"); f.glow:SetAlpha(0.5)
    Round(f.glow, f)
    f:SetScript("OnUpdate", function(self, elapsed)
        self.t = self.t + elapsed / FLIGHT
        local t = math.min(1, self.t)
        local e = t * t * (3 - 2 * t)
        local x = self.x0 + (self.x1 - self.x0) * e
        local y = self.y0 + (self.y1 - self.y0) * e + math.sin(t * math.pi) * 60
        self:ClearAllPoints(); self:SetPoint("CENTER", page, "TOPLEFT", x, y)
        local s = t < 0.85 and 1 or 1 + (t - 0.85) * 6
        self:SetScale(s * self.size)
        self:SetAlpha(t < 0.85 and 1 or 1 - (t - 0.85) / 0.15)
        if t >= 1 then self:Hide() end
    end)
    flights[#flights + 1] = f
    return f
end

-- A kudo (or a spark: smaller) was given by anyone: fly it, if this run's fire is on screen.
function CF:Fly(run, from, to, k, spark)
    if not (page and page:IsVisible() and run and run == CurrentRun()) then return end
    local target = SeatFor(to)
    if not target then return end
    local f = NewFlight()
    f.x0, f.y0 = SeatCentre(SeatFor(from))
    f.x1, f.y1 = SeatCentre(target)
    f.t, f.size = 0, spark and 0.7 or 1
    f.icon:SetTexture(spark and M.SparkIconPath(k) or M.IconPath(k)); f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f:SetScale(f.size); f:SetAlpha(1); f:Show()
end

-- ---------------------------------------------------------------------------
-- Dragging a kudo from the tray
-- ---------------------------------------------------------------------------

local drag -- { k, x, y, moved }
local ghost

local function Cursor()
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    return x / s, y / s
end

local function SeatUnderMouse()
    for _, s in ipairs(page.seats) do
        if s:IsShown() and s:IsMouseOver() then return s end
    end
end

local function Ghost()
    if ghost then return ghost end
    ghost = CreateFrame("Frame", nil, UIParent)
    ghost:SetSize(34, 34); ghost:SetFrameStrata("TOOLTIP")
    ghost.icon = ghost:CreateTexture(nil, "OVERLAY"); ghost.icon:SetAllPoints()
    Round(ghost.icon, ghost)
    ghost:Hide()
    return ghost
end

local function DragUpdate()
    if not drag then return end
    local x, y = Cursor()
    if not drag.moved and (math.abs(x - drag.x) > 4 or math.abs(y - drag.y) > 4) then
        drag.moved = true
        local g = Ghost()
        g.icon:SetTexture(M.IconPath(drag.k)); g.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        g:Show()
    end
    if drag.moved then
        ghost:ClearAllPoints(); ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
        local over = SeatUnderMouse()
        for _, s in ipairs(page.seats) do s.hover:SetShown(s == over and not s.seat.me) end
    end
end

local function EndDrag()
    if not drag then return end
    local d = drag
    drag = nil
    if ghost then ghost:Hide() end
    for _, s in ipairs(page.seats) do s.hover:Hide() end
    if d.moved then
        local s = SeatUnderMouse()
        if s then GiveTo(s.seat, d.k) end
    else
        state.picked = (state.picked ~= d.k) and d.k or nil
        Status(state.picked and ("%s %s picked: click someone to give it."):format(M.Icon(state.picked), M.Label(state.picked)) or nil)
    end
    CF:Refresh()
end

-- ---------------------------------------------------------------------------
-- Going round the fire: one person at a time
-- ---------------------------------------------------------------------------

local remarks -- the panel
local TIP_COLS, TIP_W = 3, 182

-- The others at the fire, in seat order (the ones still with you first).
local function Round_(run)
    local list = {}
    for _, seat in ipairs(Seats(run)) do
        if not seat.me then list[#list + 1] = seat end
    end
    return list
end

local function BuildRemarks()
    local o = CreateFrame("Frame", nil, page, "BackdropTemplate")
    o:SetPoint("TOPLEFT", 0, -46); o:SetPoint("BOTTOMRIGHT", 0, 0)
    W.SetBackdrop(o, 0.98); o:SetFrameLevel(page:GetFrameLevel() + 30); o:EnableMouse(true)

    o.portrait = o:CreateTexture(nil, "ARTWORK"); o.portrait:SetSize(36, 36); o.portrait:SetPoint("TOPLEFT", 12, -8)
    Round(o.portrait, o)
    o.title = Label(o, "", LARGE, 56, -10, 330)
    o.where = Muted(Label(o, "", SMALL, 56, -32, 330))
    o.pos = Muted(Label(o, "", SMALL, 0, -14, 60)); o.pos:ClearAllPoints(); o.pos:SetPoint("TOPRIGHT", -78, -14); o.pos:SetJustifyH("RIGHT")
    o.prev = MakeButton(o, "<", 26, 24); o.prev:SetPoint("TOPRIGHT", -44, -10)
    o.next = MakeButton(o, ">", 26, 24); o.next:SetPoint("TOPRIGHT", -12, -10)
    o.prev:SetScript("OnClick", function() CF:GoRound(o.index - 1) end)
    o.next:SetScript("OnClick", function() CF:GoRound(o.index + 1) end)

    o.story = Label(o, "", SMALL, 12, -54, 562); o.story:SetSpacing(2); o.story:SetWordWrap(true)

    o.kudoHead = Label(o, "Kudos  |cffaaaaaapublic: the party sees it land. Click to give.|r", NORMAL, 12, -124, 562)
    o.kudos = {}
    for i, k in ipairs(M.KUDOS) do
        local b = MakeButton(o, "", 32, 32)
        b:SetPoint("TOPLEFT", 12 + (i - 1) * 38, -142)
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetPoint("TOPLEFT", 3, -3); b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
        b.icon:SetTexture(M.IconPath(k.id)); b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.check = b:CreateFontString(nil, "OVERLAY", SMALL); b.check:SetPoint("BOTTOMRIGHT", 2, -2)
        b.k = k.id
        b:SetScript("OnClick", function(self)
            GiveTo(o.seat, self.k)
            CF:Refresh()
        end)
        Hint(b, k.label, k.says)
        o.kudos[i] = b
    end

    o.noteHead = Label(o, "A private note  |cffaaaaaaonly they will ever see it. Pick one thing to try, write your own words, or both.|r",
        NORMAL, 12, -186, 562)
    o.tips = {}
    for i, tip in ipairs(M.TIPS) do
        local b = MakeButton(o, "", TIP_W - 4, 22)
        b.text:SetWidth(TIP_W - 14); b.text:SetWordWrap(false)
        b.id = tip.id
        b:SetScript("OnClick", function(self)
            o.try = (o.try ~= self.id) and self.id or nil
            CF:RefreshRemarks()
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Try: " .. tip.label, 1, 1, 1, true)
            if self.hint then GameTooltip:AddLine(self.hint .. " (only you see this)", 1, 0.82, 0.3, true) end
            GameTooltip:Show()
        end)
        b:HookScript("OnLeave", function() GameTooltip:Hide() end)
        o.tips[i] = b
    end
    o.note = W.MakeEditBox(o, 562, ("In your own words (up to %d characters)"):format(M.MAX_NOTE))
    o.note:SetPoint("TOPLEFT", 12, -318); o.note:SetMaxLetters(M.MAX_NOTE)
    o.note:HookScript("OnTextChanged", function() CF:RefreshRemarks(true) end)
    o.keepText = Muted(Label(o, "", SMALL, 12, -350, 400))
    o.state = Label(o, "", SMALL, 12, -368, 560)

    o.back = MakeButton(o, "Back to the fire", 120, 26); o.back:SetPoint("BOTTOMLEFT", 12, 10)
    o.back:SetScript("OnClick", function() o:Hide(); CF:Refresh() end)
    o.send = MakeButton(o, "Send note privately", 140, 26); o.send:SetPoint("BOTTOMRIGHT", -194, 10)
    o.after = MakeButton(o, "Next", 174, 26); o.after:SetPoint("BOTTOMRIGHT", -12, 10)
    o.after:SetScript("OnClick", function()
        if o.index < #o.list then CF:GoRound(o.index + 1) else o:Hide(); CF:Refresh(); Status("You've been round the whole fire.") end
    end)
    o.send:SetScript("OnClick", function()
        local seat = o.seat
        local keep = o.keep
        if not (seat and keep) then return end
        local note = o.note:GetText()
        if F:SendTip(CurrentRun(), seat.full, keep, o.try, note) then
            Status(("Note sent privately to %s, with %s %s as a public kudo."):format(seat.short, M.Icon(keep), M.Label(keep)))
        else
            Status("Couldn't send it: pick a tip or write something (one note per person per run).")
        end
        CF:RefreshRemarks()
    end)
    o:Hide()
    return o
end

-- The kudo a note goes with: the first you've given them at this fire, else the data's suggestion.
local function KeepFor(run, seat)
    local given = F.GivenIn(run, seat.full)
    for _, k in ipairs(M.KUDOS) do
        if given[k.id] then return k.id, true end
    end
    local s = Mo.Suggest(run, seat.short)
    return s and s.kudo, false
end

function CF:RefreshRemarks(typing)
    local o = remarks
    if not (o and o:IsShown() and o.seat) then return end
    local run, seat = CurrentRun(), o.seat
    local sent = F.TipIn(run, seat.full)
    if not typing then
        o.title:SetText(C.Colored(seat.short, seat.class))
        local where = { seat.role }
        local left = LeftText(seat)
        if left then where[#where + 1] = "|cffd9a066" .. left .. ": kudos and notes go to them directly|r" end
        o.where:SetText(table.concat(where, "  -  "))
        o.pos:SetText(("%d of %d"):format(o.index, #o.list))
        o.prev:SetEnabled(o.index > 1); o.next:SetEnabled(o.index < #o.list)
        SetPortrait(o.portrait, seat)

        -- Their story: moments, sparks, your jots.
        local L = {}
        local moments = Mo.For(run)[seat.short] or {}
        if #moments > 0 then
            local parts = {}
            for i = 1, math.min(3, #moments) do parts[#parts + 1] = M.Icon(moments[i].kudo) .. " " .. moments[i].text end
            L[#L + 1] = table.concat(parts, "   ")
        else
            L[#L + 1] = "|cffaaaaaaThe data didn't single anything out for them.|r"
        end
        local sparks = SparkLines(F.SparksIn(run, seat.full))
        if #sparks > 0 then L[#L + 1] = "Sparks: " .. table.concat(sparks, "   ") end
        local jots = F.JotsIn(run, seat.full)
        for i = math.max(1, #jots - 1), #jots do
            L[#L + 1] = ("|TInterface\\Icons\\INV_Misc_Note_01:12:12|t |cffffd24d%s|r  |cffaaaaaa%s, your jot|r"):format(jots[i].text, date("%H:%M", jots[i].t))
        end
        o.story:SetText(table.concat(L, "\n"))

        local hints = Mo.TipHints(run, seat.short)
        local i = 0
        for _, b in ipairs(o.tips) do
            local tip = M.tip[b.id]
            if M.Suits(tip, seat.role) or hints[b.id] then
                i = i + 1
                b.hint = hints[b.id]
                b.text:SetText((b.hint and "|cffffd24d* |r" or "") .. tip.label)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", 12 + ((i - 1) % TIP_COLS) * TIP_W, -206 - math.floor((i - 1) / TIP_COLS) * 26)
                b:Show()
            else
                b:Hide()
            end
        end
        if sent then
            o.note:SetText(sent.note or ""); o.note:Disable()
        else
            o.note:Enable()
        end
    end

    local given = F.GivenIn(run, seat.full)
    for _, b in ipairs(o.kudos) do
        W.SetActive(b, given[b.k] or false)
        b.check:SetText(given[b.k] and "|cff59f28cv|r" or "")
        b:SetEnabled(not seat.me and not given[b.k])
    end
    for _, b in ipairs(o.tips) do
        W.SetActive(b, (sent and sent.try or o.try) == b.id)
        b:SetEnabled(not sent)
    end
    o.keep = KeepFor(run, seat)
    if sent then
        local where = sent.acked == "closed" and "|cffd9736bthey've turned notes off|r"
            or sent.acked and "|cff59f28cdelivered|r" or "waiting: it goes again the next time you group"
        local extra = sent.progress and (" - it stuck: %d clean runs since"):format(sent.progress.clean)
            or sent.thanked and " - they thanked you" or ""
        o.keepText:SetText(("Your note went with %s %s."):format(M.Icon(sent.keep), M.Label(sent.keep)))
        o.state:SetText(("Sent %s, %s%s."):format(date("%H:%M", sent.t), where, extra))
        o.send:Disable(); o.send:SetAlpha(0.4)
    else
        local words = ns.Trim(o.note:GetText() or "") ~= ""
        local ready = o.keep and (o.try or words)
        o.keepText:SetText(o.keep and ("Goes with %s %s as a public kudo."):format(M.Icon(o.keep), M.Label(o.keep))
            or "Give them a kudo first: a note always goes with something to keep.")
        o.state:SetText("")
        o.send:SetEnabled(ready and true or false); o.send:SetAlpha(ready and 1 or 0.4)
    end
    local nextSeat = o.list[o.index + 1]
    o.after.text:SetText(nextSeat and ("Next: " .. nextSeat.short) or "Done")
end

-- Opens the round on the index-th person (1 = the first), pre-filling the note with your jots.
function CF:GoRound(index)
    local run = CurrentRun()
    if not run then return end
    remarks = remarks or BuildRemarks()
    local list = Round_(run)
    if #list == 0 then return Status("Nobody else was at this fire.") end
    index = math.max(1, math.min(index or 1, #list))
    remarks.list, remarks.index, remarks.seat = list, index, list[index]
    remarks.try = nil
    for id in pairs(Mo.TipHints(run, remarks.seat.short)) do remarks.try = remarks.try or id end
    local jots = F.JotsIn(run, remarks.seat.full)
    local text = {}
    for _, j in ipairs(jots) do text[#text + 1] = j.text end
    remarks:Show()
    remarks.note:SetText(table.concat(text, " "):sub(1, M.MAX_NOTE))
    self:RefreshRemarks()
end

local function OpenRemarks(seat)
    if seat.me then return Status("That's your own seat.") end
    local run = CurrentRun()
    for i, s in ipairs(Round_(run)) do
        if C.SameName(s.full, seat.full) then return CF:GoRound(i) end
    end
end

-- ---------------------------------------------------------------------------
-- Seats
-- ---------------------------------------------------------------------------

local function SeatTooltip(s)
    local seat, run = s.seat, CurrentRun()
    GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
    GameTooltip:AddLine(C.Colored(seat.me and (seat.short .. " (you)") or seat.short, seat.class))
    GameTooltip:AddLine(seat.role .. (LeftText(seat) and ("  -  " .. LeftText(seat)) or ""), 0.6, 0.65, 0.7)
    local moments = s.moments or {}
    if #moments > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("This run", ACCENT[1], ACCENT[2], ACCENT[3])
        for _, m in ipairs(moments) do GameTooltip:AddLine(M.Icon(m.kudo) .. " " .. m.text, 0.9, 0.92, 0.95, true) end
    end
    local got = F.KudosIn(run, seat.full)
    if next(got) then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Kudos at this fire", ACCENT[1], ACCENT[2], ACCENT[3])
        for k, from in pairs(got) do
            local names = {}
            for _, n in ipairs(from) do names[#names + 1] = C.IsMe(n) and "you" or C.Short(n) end
            GameTooltip:AddLine(("%s %s  |cffaaaaaafrom %s|r"):format(M.Icon(k), M.Label(k), table.concat(names, ", ")), 1, 1, 1, true)
        end
    end
    local sparks = SparkLines(F.SparksIn(run, seat.full))
    if #sparks > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Sparks during the run", ACCENT[1], ACCENT[2], ACCENT[3])
        for _, l in ipairs(sparks) do GameTooltip:AddLine(l, 1, 1, 1, true) end
    end
    local jots = not seat.me and F.JotsIn(run, seat.full) or {}
    if #jots > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Your jots (only you see them)", ACCENT[1], ACCENT[2], ACCENT[3])
        for _, j in ipairs(jots) do GameTooltip:AddLine(("%s  |cffaaaaaa%s|r"):format(j.text, date("%H:%M", j.t)), 1, 0.82, 0.3, true) end
    end
    local known = not seat.me and M.KnownLine(seat.full, 4)
    if known then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Known for", ACCENT[1], ACCENT[2], ACCENT[3])
        GameTooltip:AddLine(known, 1, 1, 1, true)
    end
    GameTooltip:AddLine(" ")
    if seat.me then
        GameTooltip:AddLine("Your seat: kudos the party gives you land here.", 0.75, 0.8, 0.85, true)
    else
        GameTooltip:AddLine("Drag a kudo here, or pick one and click.", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("Right-click: your remarks for them (kudos, a private note).", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("Shift-click: everything about them.", 0.75, 0.8, 0.85)
    end
    GameTooltip:Show()
end

local function NewSeat(i)
    local s = CreateFrame("Button", nil, page)
    s:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    s.hover = s:CreateTexture(nil, "BACKGROUND"); s.hover:SetTexture(FIRE); s.hover:SetBlendMode("ADD"); s.hover:SetAlpha(0.7)
    Round(s.hover, s); s.hover:Hide()
    s.ring = s:CreateTexture(nil, "BORDER"); s.ring:SetColorTexture(1, 1, 1, 1); Round(s.ring, s)
    s.portrait = s:CreateTexture(nil, "ARTWORK"); s.portrait:SetPoint("CENTER", s.ring)
    Round(s.portrait, s)
    s.name = s:CreateFontString(nil, "OVERLAY", NORMAL); s.name:SetPoint("TOP", s.ring, "BOTTOM", 0, -3); s.name:SetWordWrap(false)
    s.moment = Muted(s:CreateFontString(nil, "OVERLAY", SMALL)); s.moment:SetPoint("TOP", s.name, "BOTTOM", 0, -1)
    s.moment:SetHeight(26); s.moment:SetJustifyV("TOP")
    s.embers = {}
    for j = 1, 6 do
        local e = s:CreateTexture(nil, "OVERLAY"); e:SetSize(16, 16)
        e:SetTexCoord(0.08, 0.92, 0.08, 0.92); Round(e, s)
        s.embers[j] = e
    end
    s.more = s:CreateFontString(nil, "OVERLAY", SMALL)
    s.sparks = s:CreateFontString(nil, "OVERLAY", SMALL); s.sparks:SetPoint("TOPLEFT", s.ring, "BOTTOMRIGHT", -6, 10)
    s.jot = s:CreateFontString(nil, "OVERLAY", SMALL); s.jot:SetPoint("TOPRIGHT", s.ring, "BOTTOMLEFT", 6, 10)
    -- The suggested kudo.
    local badge = CreateFrame("Button", nil, s)
    badge:SetSize(22, 22); badge:SetPoint("CENTER", s.ring, "TOPRIGHT", -2, -2)
    badge.glow = badge:CreateTexture(nil, "BACKGROUND"); badge.glow:SetSize(40, 40); badge.glow:SetPoint("CENTER")
    badge.glow:SetTexture(FIRE); badge.glow:SetBlendMode("ADD"); Round(badge.glow, badge)
    badge.icon = badge:CreateTexture(nil, "ARTWORK"); badge.icon:SetAllPoints(); badge.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    Round(badge.icon, badge)
    badge:SetScript("OnClick", function(self) GiveTo(s.seat, self.k); CF:Refresh() end)
    badge:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Suggested: " .. M.Label(self.k), ACCENT[1], ACCENT[2], ACCENT[3])
        GameTooltip:AddLine(self.why or "", 1, 1, 1, true)
        GameTooltip:AddLine("Click to give it.", 0.75, 0.8, 0.85)
        GameTooltip:Show()
    end)
    badge:SetScript("OnLeave", function() GameTooltip:Hide() end)
    badge.pulse = 0
    badge:SetScript("OnUpdate", function(self, elapsed)
        self.pulse = self.pulse + elapsed
        self.glow:SetAlpha(0.35 + 0.3 * math.sin(self.pulse * 3))
    end)
    s.badge = badge

    s:SetScript("OnClick", function(self, button)
        if button == "RightButton" then return OpenRemarks(self.seat) end
        if IsShiftKeyDown() then return ns.UI:ShowPlayer(self.seat.full) end
        if state.picked then GiveTo(self.seat, state.picked); return CF:Refresh() end
        if not self.seat.me then Status("Drag a kudo from the tray onto them, or right-click for your remarks.") end
    end)
    s:SetScript("OnEnter", function(self) SeatTooltip(self) end)
    s:SetScript("OnLeave", function() GameTooltip:Hide() end)
    page.seats[i] = s
    return s
end

local function Size(n)
    for _, sz in ipairs(SIZES) do
        if n <= sz[1] then return sz end
    end
    return SIZES[#SIZES]
end

local function LayoutSeat(s, seat, x, y, run, moments, size)
    local width, portrait, showMoment = size[2], size[3], size[4]
    local top = 18 + portrait / 2 -- from the seat's top to the portrait's centre (embers above)
    s.seat, s.cx, s.cy = seat, x, y
    s:SetSize(width, top + portrait / 2 + (showMoment and 46 or 20))
    s:ClearAllPoints(); s:SetPoint("TOP", page, "TOPLEFT", x, y + top)
    s.ring:SetSize(portrait + 8, portrait + 8); s.ring:ClearAllPoints(); s.ring:SetPoint("CENTER", s, "TOP", 0, -top)
    s.hover:SetSize(portrait * 1.5, portrait * 1.5); s.hover:ClearAllPoints(); s.hover:SetPoint("CENTER", s.ring)
    s.portrait:SetSize(portrait, portrait)
    s.name:SetWidth(width); s.moment:SetWidth(width + 10)
    local _, r, g, b = ns.Units.ClassColor(seat.class, { 0.5, 0.55, 0.6 })
    s.ring:SetVertexColor(r, g, b, 1)
    SetPortrait(s.portrait, seat)
    s.name:SetText(C.Colored(seat.me and "You" or seat.short, seat.class))
    s.moments = moments[seat.short] or {}
    local best = s.moments[1]
    local left = LeftText(seat)
    s.moment:SetShown(showMoment)
    s.moment:SetText(left and ("|cffd9a066" .. left .. "|r" .. (best and ("\n" .. best.text) or ""))
        or (best and best.text) or seat.role)
    s:SetAlpha(seat.left and 0.7 or 1)

    -- Embers: the kudos at this fire, one per kudo.
    local got = F.KudosIn(run, seat.full)
    local ks = {}
    for k, from in pairs(got) do ks[#ks + 1] = { k = k, n = #from } end
    table.sort(ks, function(a, b2) return a.k < b2.k end)
    local shown = math.min(#ks, #s.embers, math.floor(width / 18))
    local w = shown * 18 - 2
    for j, e in ipairs(s.embers) do
        local entry = ks[j]
        if entry and j <= shown then
            e:SetTexture(M.IconPath(entry.k))
            e:ClearAllPoints(); e:SetPoint("BOTTOMLEFT", s.ring, "TOP", -w / 2 + (j - 1) * 18, 2)
            e:Show()
        else
            e:Hide()
        end
    end
    local total = 0
    for _, entry in ipairs(ks) do total = total + entry.n end
    s.more:ClearAllPoints(); s.more:SetPoint("BOTTOMLEFT", s.ring, "TOP", w / 2 + 3, 4)
    s.more:SetText(total > shown and ("|cffffd24d%d|r"):format(total) or "")
    -- Sparks and your jots, small at the portrait's feet.
    local sparks = Count(F.SparksIn(run, seat.full))
    s.sparks:SetText(sparks > 0 and ("|cffffd24d%d|r|T%s:11:11|t"):format(sparks, FIRE) or "")
    local jots = not seat.me and #F.JotsIn(run, seat.full) or 0
    s.jot:SetText(jots > 0 and ("|T%s:11:11|t|cffaaaaaa%d|r"):format(NOTE, jots) or "")

    -- The suggested kudo, for the others.
    local sug = not seat.me and Mo.Suggest(run, seat.short, moments, F.GivenIn(run, seat.full))
    s.badge:SetShown(sug and true or false)
    if sug then
        s.badge.k, s.badge.why = sug.kudo, sug.text
        s.badge.icon:SetTexture(M.IconPath(sug.kudo))
    end
    s:Show()
end

-- ---------------------------------------------------------------------------
-- The page
-- ---------------------------------------------------------------------------

local function Runs()
    local list = {}
    for _, r in ipairs(ns.db.runs) do list[#list + 1] = r end
    return list
end

local function Step(dir)
    local runs = Runs()
    local run = CurrentRun()
    for i, r in ipairs(runs) do
        if r == run then
            local to = runs[i + dir]
            if to then state.runID = to.id; state.picked = nil; Status(nil) end
            break
        end
    end
    if remarks then remarks:Hide() end
    CF:Refresh()
end

function CF.Build(win)
    page = win:NewPage("campfire")
    page.seats = {}
    page.title = Label(page, "", LARGE, 0, 0, 420)
    page.sub = Muted(Label(page, "", SMALL, 0, -24, 586))
    page.older = MakeButton(page, "<", 26, 24); page.older:SetPoint("TOPRIGHT", -128, 0)
    page.newer = MakeButton(page, ">", 26, 24); page.newer:SetPoint("TOPRIGHT", -98, 0)
    page.details = MakeButton(page, "Run details", 90, 24); page.details:SetPoint("TOPRIGHT", 0, 0)
    page.older:SetScript("OnClick", function() Step(-1) end)
    page.newer:SetScript("OnClick", function() Step(1) end)
    page.details:SetScript("OnClick", function() local r = CurrentRun(); if r then ns.UI:ShowRun(r.id) end end)
    Hint(page.older, "An earlier fire", "Kudos and notes for an earlier run still reach people.")
    Hint(page.newer, "A later fire")
    Hint(page.details, "Run details", "Bosses, every death, its hits and the analysis (only you see those).")

    -- The fire, and what it teaches.
    page.glow = page:CreateTexture(nil, "BACKGROUND"); page.glow:SetSize(120, 120)
    page.glow:SetPoint("CENTER", page, "TOPLEFT", CX, CY + 22); page.glow:SetTexture(FIRE); page.glow:SetBlendMode("ADD")
    Round(page.glow, page)
    page.fire = page:CreateTexture(nil, "ARTWORK"); page.fire:SetSize(54, 54)
    page.fire:SetPoint("CENTER", page, "TOPLEFT", CX, CY + 22); page.fire:SetTexture(FIRE); page.fire:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    Round(page.fire, page)
    page.lessons = page:CreateFontString(nil, "OVERLAY", SMALL)
    page.lessons:SetPoint("TOP", page, "TOPLEFT", CX, CY - 10); page.lessons:SetWidth(230); page.lessons:SetSpacing(2)
    local flicker = 0
    page:SetScript("OnUpdate", function(_, elapsed)
        flicker = flicker + elapsed
        page.glow:SetAlpha(0.45 + 0.15 * math.sin(flicker * 2.3) + 0.08 * math.sin(flicker * 7.1))
        DragUpdate()
    end)
    page:SetScript("OnHide", function() if drag then EndDrag() end end)

    -- The tray.
    page.trayLabel = Muted(Label(page, "Kudos: drag one onto someone, or pick one and click them. Your party sees it land.", SMALL, 0, -352, 586))
    page.tokens = {}
    local x0 = (586 - (#M.KUDOS * (TOKEN + TOKEN_GAP) - TOKEN_GAP)) / 2
    for i, k in ipairs(M.KUDOS) do
        local t = MakeButton(page, "", TOKEN + 4, TOKEN + 4)
        t:SetPoint("TOPLEFT", x0 + (i - 1) * (TOKEN + TOKEN_GAP) - 2, -370)
        t.icon = t:CreateTexture(nil, "ARTWORK"); t.icon:SetPoint("TOPLEFT", 3, -3); t.icon:SetPoint("BOTTOMRIGHT", -3, 3)
        t.icon:SetTexture(M.IconPath(k.id)); t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        t.k = k.id
        t:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" then return end
            local x, y = Cursor()
            drag = { k = self.k, x = x, y = y, moved = false }
        end)
        t:SetScript("OnMouseUp", function() EndDrag() end)
        Hint(t, k.label, k.says .. "\n\nDrag onto someone at the fire, or click to pick it.")
        page.tokens[i] = t
    end
    page.status = Label(page, "", SMALL, 0, -416, 420)
    page.hint = Muted(Label(page, "Right-click someone for your remarks.  Shift-click: their page.", SMALL, 0, -436, 420))
    page.round = MakeButton(page, "Go round the fire", 150, 26); page.round:SetPoint("TOPRIGHT", 0, -418)
    page.round:SetScript("OnClick", function() CF:GoRound(1) end)
    Hint(page.round, "Go round the fire", "Everyone who was part of this run, one at a time: what they did, your jots, kudos and a private note.")
    page.empty = Muted(Label(page, "No runs yet.\n\nAfter your next dungeon, your party gathers here around the fire: thank each other with kudos, leave private notes, and see what the run taught.",
        SMALL, 0, -60, 520))
    page.empty:SetWordWrap(true)
    page.Refresh = function() CF:Refresh() end
end

function CF:Refresh()
    if not (page and page:IsVisible()) then return end
    local run = CurrentRun()
    local has = run ~= nil
    for _, key in ipairs({ "fire", "glow", "lessons", "trayLabel", "status", "hint", "older", "newer", "details", "sub", "round" }) do page[key]:SetShown(has) end
    for _, t in ipairs(page.tokens) do t:SetShown(has) end
    page.empty:SetShown(not has)
    if not has then
        page.title:SetText("The Campfire")
        for _, s in ipairs(page.seats) do s:Hide() end
        return
    end
    local live = run == ns.Run.current
    page.title:SetText(run.instance .. (run.finished and "  |cff59f28cfull clear|r" or ""))
    local bits = { date("%m/%d %H:%M", run.start) }
    if live then table.insert(bits, 1, "|cff59f28cin progress|r") end
    if run.stop then bits[#bits + 1] = ns.Format.Duration(run.stop - run.start, { days = false, alwaysHours = true }) end
    bits[#bits + 1] = ("%d boss%s"):format(run.bossKills or 0, (run.bossKills or 0) == 1 and "" or "es")
    bits[#bits + 1] = ("%d wipe%s"):format(run.wipes or 0, (run.wipes or 0) == 1 and "" or "s")
    bits[#bits + 1] = ("%d death%s"):format(#run.deaths, #run.deaths == 1 and "" or "s")
    page.sub:SetText(table.concat(bits, "  -  "))
    local runs = Runs()
    page.older:SetEnabled(runs[1] ~= run); page.newer:SetEnabled(runs[#runs] ~= run)

    local lessons = Mo.Lessons(run)
    local L = {}
    for i = 1, math.min(2, #lessons) do
        L[#L + 1] = ("|cffffd24d%s.|r %s"):format(lessons[i].title, lessons[i].text)
    end
    page.lessons:SetText(table.concat(L, "\n"))

    local seats = Seats(run)
    local moments = Mo.For(run)
    local n = #seats
    local size = Size(n)
    for i, seat in ipairs(seats) do
        local s = page.seats[i] or NewSeat(i)
        -- You at the bottom (270 degrees), the others round the ring from there.
        local a = math.rad(270 + (i == n and 0 or i * 360 / n))
        LayoutSeat(s, seat, CX + RX * math.cos(a), CY + RY * math.sin(a), run, moments, size)
    end
    for i = n + 1, #page.seats do page.seats[i]:Hide() end

    for _, t in ipairs(page.tokens) do W.SetActive(t, state.picked == t.k) end

    if not state.status then
        local given, notes, waiting = 0, 0, 0
        for _, e in ipairs(run.kudos or {}) do if C.IsMe(e.from) then given = given + 1 end end
        for _, id in pairs(run.tips or {}) do
            local s = F.DB().sent[id]
            notes = notes + 1
            if s and not s.acked then waiting = waiting + 1 end
        end
        local text = ("%d at the fire. You've given %d kudo%s"):format(n, given, given == 1 and "" or "s")
        if notes > 0 then text = text .. (", %d private note%s%s"):format(notes, notes == 1 and "" or "s", waiting > 0 and (" (" .. waiting .. " waiting)") or "") end
        page.status:SetText("|cffaaaaaa" .. text .. ".|r")
    else
        page.status:SetText(state.status)
    end
    if remarks and remarks:IsShown() then self:RefreshRemarks() end
end

-- ---------------------------------------------------------------------------
-- Opening
-- ---------------------------------------------------------------------------

local waiting
function CF:Open(runID)
    state.runID, state.picked, state.status = runID, nil, nil
    if remarks then remarks:Hide() end
    if InCombatLockdown() then
        waiting = true
        return
    end
    ns.UI:ShowCampfire()
end

ns:On("PLAYER_REGEN_ENABLED", function()
    if waiting then
        waiting = nil
        ns.UI:ShowCampfire()
    end
end)

-- The last boss is down and the party is still together: gather round.
function CF:OnFinalBoss(run)
    if run.campfireShown then return end
    run.campfireShown = true
    C_Timer.After(4, function() CF:Open(run.id) end)
end

function CF:OnRunEnd(run)
    if run.campfireShown then return end
    run.campfireShown = true
    CF:Open(run.id)
end

-- /fire: the live run's fire (or the newest).
function CF:OpenLatest() self:Open(nil) end
