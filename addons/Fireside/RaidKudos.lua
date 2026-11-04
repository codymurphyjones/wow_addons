local _, ns = ...
local C = ns.Compat

-- The raid kudos window: what the Hearth is in a raid (and in a party shown with raid-style frames),
-- opened from its one button (Hearth.lua) or /fire raid. A list of the people you fought beside on
-- the left; pick one and thank them on the right, the way the campfire's round does:
--   sparks         small thanks, sent now; the group sees them light up
--   kudos          public: the group sees them land (one of each per person per raid)
--   a private note a tip to try and/or your own words, sent with a kudo to keep; only they see it
-- In a raid the list is everyone who was in the raid and in combat while in it with you
-- (Feedback.RaidList): someone kicked after the fighting started is still there, and kudos and notes
-- reach them directly; someone removed before it never shows. The raid's list stays for a while
-- after you leave it (Feedback.LastRaid). In a party it's the party, and anyone who left the run.
local R = {}
ns.RaidKudos = R

local W = ns.Widgets
local Label, Muted, MakeButton, Hint = W.Label, W.Muted, W.MakeButton, W.Hint
local M, F = ns.Marks, ns.Feedback

local SMALL, NORMAL, LARGE = "FiresideGameFontHighlightSmall", "FiresideGameFontNormal", "FiresideGameFontNormalLarge"
local WIDTH, HEIGHT = 650, 560
local LIST_W, ROW_H = 184, 22
local X0, PANEL_W = 214, 420
local TIP_W = 210

local frame
local state = { sel = nil, try = nil } -- the picked person's full name, the picked tip

-- ---------------------------------------------------------------------------
-- Who's on the list, and what they've been given here
-- ---------------------------------------------------------------------------

-- The run kudos and notes land on, the list, and whether it's a raid.
local function Source()
    local raid = F.LastRaid()
    if raid and (IsInRaid() or not IsInGroup()) then return raid, F.RaidList(raid), true end
    local run = F.LiveRun()
    local list, seen = {}, {}
    local function Add(full, class, here)
        if not full or C.IsMe(full) then return end
        for _, e in ipairs(seen) do if C.SameName(e, full) then return end end
        seen[#seen + 1] = full
        list[#list + 1] = { full = full, class = class, here = here }
    end
    for _, unit in ipairs(C.GroupUnits()) do
        local _, class = C.Call(UnitClass, unit)
        Add(C.UnitFull(unit), C.Str(class), true)
    end
    for full, m in pairs(run and run.members or {}) do
        Add(full, type(m) == "table" and m.class or nil, false)
    end
    return run, list, false
end

-- The kudo a note goes with: the last one you gave them here.
local function KeepFor(run, full)
    local keep
    for _, e in ipairs(run and run.kudos or {}) do
        if C.IsMe(e.from) and C.SameName(e.to, full) then keep = e.k end
    end
    return keep
end

local function Status(text) if frame then frame.status:SetText(text or "") end end

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------

local function Build()
    local f = CreateFrame("Frame", "FiresideRaidKudos", UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, HEIGHT); f:SetPoint("CENTER", 0, 40)
    W.SetBackdrop(f, 0.97)
    f:SetFrameStrata("HIGH"); f:SetToplevel(true); f:SetClampedToScreen(true)
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, "FiresideRaidKudos")
    f:Hide()

    f.title = Label(f, "Kudos", LARGE, 14, -12, 400)
    f.sub = Muted(Label(f, "", SMALL, 14, -34, 600))
    f.close = MakeButton(f, "X", 22, 22); f.close:SetPoint("TOPRIGHT", -10, -10)
    f.close:SetScript("OnClick", function() f:Hide() end)

    -- The list.
    f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT", 12, -58); f.scroll:SetPoint("BOTTOMLEFT", 12, 72)
    f.scroll:SetWidth(LIST_W - 22)
    f.list = CreateFrame("Frame", nil, f.scroll)
    f.list:SetSize(LIST_W - 22, 10)
    f.scroll:SetScrollChild(f.list)
    f.rows = {}
    f.empty = Muted(Label(f, "", SMALL, 14, -62, LIST_W - 10)); f.empty:SetWordWrap(true)

    -- The panel.
    f.name = Label(f, "", LARGE, X0, -58, PANEL_W)
    f.where = Muted(Label(f, "", SMALL, X0, -80, PANEL_W))
    f.known = Label(f, "", SMALL, X0, -96, PANEL_W); f.known:SetWordWrap(true)

    f.sparkHead = Label(f, "Sparks  |cffaaaaaaa quick thanks: the group sees it light up on them|r", NORMAL, X0, -124, PANEL_W)
    f.sparks = {}
    for i, sp in ipairs(M.SPARKS) do
        local b = MakeButton(f, "", 28, 28)
        b:SetPoint("TOPLEFT", X0 + (i - 1) * 32, -142)
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetPoint("TOPLEFT", 3, -3); b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
        b.icon:SetTexture(M.SparkIconPath(sp.id)); b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.s = sp.id
        b:SetScript("OnClick", function(self) R:Spark(self.s) end)
        Hint(b, sp.label, "Sends it now.")
        f.sparks[i] = b
    end

    f.kudoHead = Label(f, "Kudos  |cffaaaaaapublic: the group sees it land. One of each per person.|r", NORMAL, X0, -180, PANEL_W)
    f.kudos = {}
    local perRow = math.ceil(#M.KUDOS / 2)
    local step = math.min(36, math.floor(PANEL_W / perRow))
    for i, k in ipairs(M.KUDOS) do
        local b = MakeButton(f, "", step - 4, step - 4)
        b:SetPoint("TOPLEFT", X0 + ((i - 1) % perRow) * step, -198 - math.floor((i - 1) / perRow) * step)
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetPoint("TOPLEFT", 3, -3); b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
        b.icon:SetTexture(M.IconPath(k.id)); b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.check = b:CreateFontString(nil, "OVERLAY", SMALL); b.check:SetPoint("BOTTOMRIGHT", 2, -2)
        b.k = k.id
        b:SetScript("OnClick", function(self) R:Give(self.k) end)
        Hint(b, k.label, k.says)
        f.kudos[i] = b
    end

    local noteTop = -198 - 2 * step - 10
    f.noteHead = Label(f, "A private note  |cffaaaaaaonly they see it: a tip to try, your own words, or both|r", NORMAL, X0, noteTop, PANEL_W)
    f.tips = {}
    for i, tip in ipairs(M.TIPS) do
        local b = MakeButton(f, tip.label, TIP_W - 4, 22)
        b.text:SetWidth(TIP_W - 14); b.text:SetWordWrap(false)
        b:SetPoint("TOPLEFT", X0 + ((i - 1) % 2) * TIP_W, noteTop - 18 - math.floor((i - 1) / 2) * 25)
        b.id = tip.id
        b:SetScript("OnClick", function(self)
            state.try = (state.try ~= self.id) and self.id or nil
            R:Refresh()
        end)
        Hint(b, "Try: " .. tip.label)
        f.tips[i] = b
    end
    local noteY = noteTop - 18 - math.ceil(#M.TIPS / 2) * 25 - 4
    f.note = W.MakeEditBox(f, PANEL_W, ("In your own words (up to %d characters)"):format(M.MAX_NOTE))
    f.note:SetPoint("TOPLEFT", X0, noteY); f.note:SetMaxLetters(M.MAX_NOTE)
    f.note:HookScript("OnTextChanged", function() R:RefreshSend() end)
    f.keepText = Muted(Label(f, "", SMALL, X0, noteY - 32, PANEL_W))

    f.status = Label(f, "", SMALL, 14, 0, WIDTH - 28)
    f.status:ClearAllPoints(); f.status:SetPoint("BOTTOMLEFT", 14, 50)
    f.page = MakeButton(f, "Their page", 96, 26); f.page:SetPoint("BOTTOMLEFT", X0, 12)
    f.page:SetScript("OnClick", function() if state.sel then ns.UI:ShowPlayer(state.sel) end end)
    f.send = MakeButton(f, "Send note privately", 140, 26); f.send:SetPoint("LEFT", f.page, "RIGHT", 8, 0)
    f.send:SetScript("OnClick", function() R:SendNote() end)
    f.after = MakeButton(f, "Next", 160, 26); f.after:SetPoint("BOTTOMRIGHT", -12, 12)
    f.after:SetScript("OnClick", function() R:Step(1) end)

    f:SetScript("OnShow", function() R:Refresh() end)
    return f
end

local function Row(i)
    local row = frame.rows[i]
    if row then return row end
    row = MakeButton(frame.list, "", LIST_W - 26, ROW_H - 2)
    row.text:ClearAllPoints(); row.text:SetPoint("LEFT", 8, 0); row.text:SetJustifyH("LEFT"); row.text:SetWidth(LIST_W - 64)
    row.text:SetWordWrap(false)
    row.mark = row:CreateFontString(nil, "OVERLAY", SMALL); row.mark:SetPoint("RIGHT", -6, 0)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetScript("OnClick", function(self)
        state.sel, state.try = self.full, nil
        frame.note:SetText("")
        Status("")
        R:Refresh()
    end)
    frame.rows[i] = row
    return row
end

-- ---------------------------------------------------------------------------
-- Giving
-- ---------------------------------------------------------------------------

function R:Spark(s)
    if not state.sel then return end
    local ok, why = F:Spark(state.sel, s)
    if ok then
        Status(("%s %s to %s."):format(M.SparkIcon(s), M.SparkLabel(s), C.Short(state.sel)))
    else
        Status(why == "soon" and "You just sent them that one." or "Couldn't send that.")
    end
end

function R:Give(k)
    if not state.sel then return end
    local run = Source()
    local ok, why = F:Give(run, state.sel, k)
    if ok then
        local here = C.InGroup(state.sel)
        Status(("%s %s to %s%s"):format(M.Icon(k), M.Label(k), C.Short(state.sel),
            here and "" or "  |cffaaaaaa(they've left the group: it goes to them directly)|r"))
    else
        Status(why == "given" and "You've given them that one already." or "Couldn't give that.")
    end
    self:Refresh()
end

function R:SendNote()
    if not state.sel then return end
    local run = Source()
    local keep = KeepFor(run, state.sel)
    if not keep then return end
    if F:SendTip(run, state.sel, keep, state.try, frame.note:GetText()) then
        Status(("Note sent privately to %s, with %s %s as a public kudo."):format(C.Short(state.sel), M.Icon(keep), M.Label(keep)))
        state.try = nil
    else
        Status("Couldn't send it: pick a tip or write something (one note per person).")
    end
    self:Refresh()
end

function R:Step(d)
    local _, list = Source()
    local at = 0
    for i, e in ipairs(list) do if state.sel and C.SameName(e.full, state.sel) then at = i end end
    local nextOne = list[at + d]
    if not nextOne then frame:Hide() return end
    state.sel, state.try = nextOne.full, nil
    frame.note:SetText("")
    Status("")
    self:Refresh()
end

-- ---------------------------------------------------------------------------
-- Refresh
-- ---------------------------------------------------------------------------

function R:RefreshSend()
    if not (frame and frame:IsShown()) then return end
    local run = Source()
    local sel = state.sel
    local sent = sel and F.TipIn(run, sel)
    if not sel then
        frame.keepText:SetText(""); frame.send:Disable(); frame.send:SetAlpha(0.4)
        return
    end
    if sent then
        local where = sent.acked == "closed" and "|cffd9736bthey've turned notes off|r"
            or sent.acked and "|cff59f28cdelivered|r" or "waiting: it goes again the next time you group"
        frame.keepText:SetText(("Your note went with %s %s, %s, %s."):format(M.Icon(sent.keep), M.Label(sent.keep), date("%H:%M", sent.t), where))
        frame.send:Disable(); frame.send:SetAlpha(0.4)
        return
    end
    local keep = KeepFor(run, sel)
    local words = ns.Trim(frame.note:GetText() or "") ~= ""
    local ready = keep and (state.try or words)
    frame.keepText:SetText(keep and ("Goes with %s %s as a public kudo."):format(M.Icon(keep), M.Label(keep))
        or "Give them a kudo first: a note always goes with something to keep.")
    frame.send:SetEnabled(ready and true or false); frame.send:SetAlpha(ready and 1 or 0.4)
end

function R:Refresh()
    if not (frame and frame:IsShown()) then return end
    local run, list, raid = Source()
    frame.title:SetText(raid and "Raid kudos" or "Kudos")
    frame.sub:SetText(raid
        and ((IsInRaid() and "" or "|cffd9a066You've left the raid.|r ") .. "Everyone who fought beside you in this raid, even if they've left it since.")
        or "Your party, and anyone who left the run.")

    -- Keep the pick if they're still listed, else the first.
    local found
    for _, e in ipairs(list) do if state.sel and C.SameName(e.full, state.sel) then found = e end end
    if not found then
        found = list[1]
        state.sel, state.try = found and found.full or nil, nil
    end

    for i, e in ipairs(list) do
        local row = Row(i)
        row.full = e.full
        local given = 0
        for _ in pairs(F.GivenIn(run, e.full)) do given = given + 1 end
        row.text:SetText(C.Colored(C.Short(e.full), e.class) .. (e.here and "" or "  |cff888888left|r"))
        row.mark:SetText(given > 0 and ("|cff59f28c%d|r"):format(given) or "")
        W.SetActive(row, e == found)
        row:Show()
    end
    for i = #list + 1, #frame.rows do frame.rows[i]:Hide() end
    frame.list:SetHeight(math.max(10, #list * ROW_H))
    frame.empty:SetText(#list == 0 and (raid and "Nobody yet: people show up here once they've been in combat with the raid." or "Nobody to thank yet.") or "")

    local sel = found
    local on = sel ~= nil
    for _, b in ipairs(frame.sparks) do b:SetEnabled(on and sel.here); b:SetAlpha(on and sel.here and 1 or 0.4) end
    frame.page:SetEnabled(on)
    if not on then
        frame.name:SetText(""); frame.where:SetText(""); frame.known:SetText("")
        for _, b in ipairs(frame.kudos) do b:Disable(); b.check:SetText("") end
        for _, b in ipairs(frame.tips) do b:Disable() end
        frame.note:Disable()
        frame.after.text:SetText("Close")
        return self:RefreshSend()
    end
    frame.name:SetText(C.Colored(C.Short(sel.full), sel.class))
    frame.where:SetText(sel.here and (raid and "In the raid" or "In your party")
        or "|cffd9a066Left the group: kudos and notes go to them directly. Sparks are for the moment, so they're off.|r")
    frame.known:SetText(M.KnownLine(sel.full, 4) or "")

    local given = F.GivenIn(run, sel.full)
    for _, b in ipairs(frame.kudos) do
        W.SetActive(b, given[b.k] or false)
        b.check:SetText(given[b.k] and "|cff59f28cv|r" or "")
        b:SetEnabled(not given[b.k])
    end
    local sent = F.TipIn(run, sel.full)
    for _, b in ipairs(frame.tips) do
        W.SetActive(b, (sent and sent.try or state.try) == b.id)
        b:SetEnabled(not sent)
    end
    if sent then frame.note:SetText(sent.note or ""); frame.note:Disable() else frame.note:Enable() end

    local at = 0
    for i, e in ipairs(list) do if e == sel then at = i end end
    local nextOne = list[at + 1]
    frame.after.text:SetText(nextOne and ("Next: " .. C.Short(nextOne.full)) or "Done")
    self:RefreshSend()
end

function R:Open()
    local _, list, raid = Source()
    if not IsInGroup() and not raid then
        ns:Print("No group, and no raid in the last 45 minutes, to thank.", true)
        return
    end
    frame = frame or Build()
    frame:Show()
    self:Refresh()
    return list
end

function R:Toggle()
    if frame and frame:IsShown() then frame:Hide() else self:Open() end
end

ns:OnChanged(function() R:Refresh() end)
