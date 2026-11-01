local _, ns = ...
local D = ns.Data
local API = ns.API
local P = ns.Profiles
local C = ns.Caps

-- The Weight Designer (/statledger designer): profiles on the left, stats in the middle, and on the
-- right the chosen stat's base weight, a chart of what it's worth at each value, and its cap tiers
-- with any stats that move them. Every edit saves as you make it.
local Dz = {}
ns.Designer = Dz

local ROW_H = 22
local TEXT = "STATLEDGER_DESIGNER_TEXT"
local UNIT_COLOR = "|cffbbbbbb"

local function Text(parent, template)
    return parent:CreateFontString(nil, "OVERLAY", template or "StatLedgerGameFontHighlight")
end

local function Number(v) return ("%.4g"):format(v or 0) end

local function Tooltip(frame, text)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Button(parent, label, width, fn, tip)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(label)
    b:SetScript("OnClick", fn)
    if tip then Tooltip(b, tip) end
    return b
end

-- A text box that saves on Enter or on leaving it; Escape puts it back.
local function Box(parent, width, onCommit)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, 20)
    box:SetAutoFocus(false)
    box:SetFontObject("StatLedgerGameFontHighlight")
    function box:Show_(text)
        self.shown = text
        if not self:HasFocus() then self:SetText(text) end
    end
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText(self.shown or "")
        self:ClearFocus()
    end)
    box:SetScript("OnEditFocusLost", function(self)
        local text = ns.Trim(self:GetText())
        if text ~= self.shown then onCommit(text, self) end
    end)
    return box
end

-- The same for numbers: anything else goes back to what it was.
local function NumberBox(parent, width, onCommit)
    return Box(parent, width, function(text, box)
        local n = tonumber(text)
        if n then
            box.shown = text
            onCommit(n)
        else
            box:SetText(box.shown or "")
        end
    end)
end

local function Menu(owner, fill)
    if MenuUtil and MenuUtil.CreateContextMenu then MenuUtil.CreateContextMenu(owner, fill) end
end

StaticPopupDialogs[TEXT] = {
    text = "%s", button1 = ACCEPT or "Accept", button2 = CANCEL or "Cancel",
    hasEditBox = 1, maxLetters = 40,
    OnShow = function(self, data)
        local box = self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox())
        if box and data then box:SetText(data.default or ""); box:HighlightText(); box:SetFocus() end
    end,
    OnAccept = function(self, data)
        local box = self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox())
        local text = box and ns.Trim(box:GetText()) or ""
        if text ~= "" then data.fn(text) end
    end,
    EditBoxOnEnterPressed = function(box)
        local dialog = box:GetParent()
        local text = ns.Trim(box:GetText())
        if text ~= "" and dialog.data then dialog.data.fn(text) end
        dialog:Hide()
    end,
    EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}

StaticPopupDialogs.STATLEDGER_DESIGNER_DELETE = {
    text = "Delete the profile \"%s\"?", button1 = YES or "Yes", button2 = NO or "No",
    OnAccept = function(_, data) data.fn() end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, showAlert = 1, preferredIndex = 3,
}

local function Ask(prompt, default, fn)
    StaticPopup_Show(TEXT, prompt, nil, { default = default, fn = fn })
end

---------------------------------------------------------------------------
-- What's selected
---------------------------------------------------------------------------

function Dz:Profile()
    local profile = self.label and P.Get(self.label)
    if profile then return profile end
    local active, label = P.Active()
    self.label = label
    return active
end

function Dz:Entry()
    local profile = self:Profile()
    return profile and profile.stats[self.stat], profile
end

function Dz:Edited()
    P.Changed()
    self:Refresh()
end

---------------------------------------------------------------------------
-- Left: profiles
---------------------------------------------------------------------------

function Dz:NewProfile(owner)
    Menu(owner, function(_, root)
        root:CreateTitle("New profile")
        root:CreateButton("Blank (every stat 0)", function()
            Dz.label = P.Create("New profile")
            Dz:Refresh()
        end)
        root:CreateButton("Copy of this profile", function()
            Dz.label = P.Create(self.label .. " copy", self:Profile())
            Dz:Refresh()
        end)
        local class = API:GetActiveSpec()
        for spec, name in ipairs(API:GetSpecs(class)) do
            root:CreateButton("From " .. name .. " default", function()
                Dz.label = P.Create(name, P.Template(class, spec))
                Dz:Refresh()
            end)
        end
    end)
end

function Dz:BuildProfiles(f)
    local head = Text(f, "StatLedgerGameFontNormal")
    head:SetPoint("TOPLEFT", 14, -44)
    head:SetText("Profiles")
    local note = Text(f, "StatLedgerGameFontDisableSmall")
    note:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -3)
    note:SetWidth(204)
    note:SetJustifyH("LEFT")
    note:SetText("Top one first when no profile matches your talents.")

    self.profileRows = {}
    for i = 1, 12 do
        local row = CreateFrame("Button", nil, f)
        row:SetSize(204, ROW_H)
        row:SetPoint("TOPLEFT", 14, -76 - (i - 1) * ROW_H)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        row.name = Text(row)
        row.name:SetPoint("LEFT", 6, 0)
        row.name:SetWidth(150)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row:SetScript("OnClick", function(self)
            Dz.label = self.label
            Dz:Refresh()
        end)
        row.down = Button(row, "v", 22, function(self)
            P.Move(self:GetParent().label, 1)
            Dz:Refresh()
        end)
        row.down:SetPoint("RIGHT", 0, 0)
        row.up = Button(row, "^", 22, function(self)
            P.Move(self:GetParent().label, -1)
            Dz:Refresh()
        end)
        row.up:SetPoint("RIGHT", row.down, "LEFT", 0, 0)
        self.profileRows[i] = row
    end

    local top = -76 - 12 * ROW_H - 8
    self.useButton = Button(f, "Use this profile", 204, function()
        P.SetActive(Dz.label)
        Dz:Refresh()
    end, "Make this the active profile for this character.")
    self.useButton:SetPoint("TOPLEFT", 14, top)

    local new = Button(f, "New", 66, function(b) Dz:NewProfile(b) end)
    new:SetPoint("TOPLEFT", 14, top - 26)
    local rename = Button(f, "Rename", 70, function()
        Ask("Rename profile:", Dz.label, function(text)
            Dz.label = P.Rename(Dz.label, text)
            Dz:Refresh()
        end)
    end)
    rename:SetPoint("LEFT", new, "RIGHT", 2, 0)
    local delete = Button(f, "Delete", 66, function()
        if #P.List() < 2 then return ns:Print("A character needs at least one profile.") end
        local label = Dz.label
        StaticPopup_Show("STATLEDGER_DESIGNER_DELETE", label, nil, { fn = function()
            P.Delete(label)
            Dz.label = nil
            Dz:Refresh()
        end })
    end)
    delete:SetPoint("LEFT", rename, "RIGHT", 2, 0)

    local aligned = Button(f, "Name after my talents", 204, function()
        Dz.label = P.Rename(Dz.label, P.TalentString())
        Dz:Refresh()
    end, "Renames this profile to your talent points, so it matches when you log in with them.")
    aligned:SetPoint("TOPLEFT", 14, top - 52)
    local reset = Button(f, "Reset whole profile", 204, function()
        P.Reset(Dz:Profile())
        Dz:Refresh()
    end, "Back to the spec default it came from, or all zeros for a blank profile.")
    reset:SetPoint("TOPLEFT", 14, top - 78)

    self.hintLabel = Text(f, "StatLedgerGameFontDisableSmall")
    self.hintLabel:SetPoint("TOPLEFT", 14, top - 108)
    self.hintLabel:SetText("Description")
    self.hintBox = Box(f, 196, function(text)
        Dz:Profile().spec_hint = text
        Dz:Refresh()
    end)
    self.hintBox:SetPoint("TOPLEFT", 20, top - 120)
end

function Dz:RefreshProfiles()
    local _, activeLabel = P.Active()
    local list = P.List()
    for i, row in ipairs(self.profileRows) do
        local label = list[i]
        row:SetShown(label ~= nil)
        if label then
            row.label = label
            local name = label == activeLabel and ("|cff66bbff" .. label .. "|r") or label
            local hint = P.Get(label).spec_hint
            row.name:SetText(hint and hint ~= "" and (name .. " " .. UNIT_COLOR .. hint .. "|r") or name)
            row.bg:SetColorTexture(1, 0.82, 0, label == self.label and 0.18 or 0)
        end
    end
    self.useButton:SetEnabled(self.label ~= activeLabel)
    self.useButton:SetText(self.label == activeLabel and "In use" or "Use this profile")
    self.hintBox:Show_(self:Profile().spec_hint or "")
end

---------------------------------------------------------------------------
-- Middle: stats
---------------------------------------------------------------------------

function Dz:BuildStats(f)
    local head = Text(f, "StatLedgerGameFontNormal")
    head:SetPoint("TOPLEFT", 232, -44)
    head:SetText("Stats")
    local weightHead = Text(f, "StatLedgerGameFontDisableSmall")
    weightHead:SetPoint("TOPRIGHT", f, "TOPLEFT", 478, -46)
    weightHead:SetText("base / now")

    self.search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    self.search:SetSize(238, 20)
    self.search:SetPoint("TOPLEFT", 238, -60)
    self.search:SetAutoFocus(false)
    self.search:SetFontObject("StatLedgerGameFontHighlight")
    self.search:SetScript("OnTextChanged", function() Dz:RefreshStats() end)
    self.search:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    local searchHint = Text(self.search, "StatLedgerGameFontDisableSmall")
    searchHint:SetPoint("LEFT", 2, 0)
    searchHint:SetText("Search stats")
    self.searchHint = searchHint

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 232, -86)
    scroll:SetSize(240, 498)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(240, 400)
    scroll:SetScrollChild(content)
    self.statContent = content

    self.statRows, self.statHeads = {}, {}
    for _, group in ipairs(D.STAT_GROUPS) do
        local groupHead = Text(content, "StatLedgerGameFontNormalSmall")
        self.statHeads[group[1]] = groupHead
        groupHead:SetText(group[1])
        for i = 2, #group do
            local name = group[i]
            local row = CreateFrame("Button", nil, content)
            row:SetHeight(ROW_H)
            row.stat, row.group = name, group[1]
            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()
            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.08)
            row.name = Text(row)
            row.name:SetPoint("LEFT", 6, 0)
            row.value = Text(row)
            row.value:SetPoint("RIGHT", -4, 0)
            row:SetScript("OnClick", function(self)
                Dz.stat = self.stat
                Dz:Refresh()
            end)
            self.statRows[#self.statRows + 1] = row
        end
    end
end

function Dz:RefreshStats()
    local profile = self:Profile()
    local filter = ns.Trim(self.search:GetText()):lower()
    self.searchHint:SetShown(filter == "" and not self.search:HasFocus())
    for _, h in pairs(self.statHeads) do h:Hide() end
    local top, group = 0, nil
    for _, row in ipairs(self.statRows) do
        local label = C.Label(row.stat)
        local entry = profile.stats[row.stat]
        local shown = entry ~= nil and (filter == "" or label:lower():find(filter, 1, true) ~= nil)
        row:SetShown(shown)
        if shown then
            if row.group ~= group then
                group = row.group
                local h = self.statHeads[group]
                h:ClearAllPoints()
                h:SetPoint("TOPLEFT", self.statContent, "TOPLEFT", 6, -top - 5)
                h:Show()
                top = top + 20
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.statContent, "TOPLEFT", 0, -top)
            row:SetPoint("TOPRIGHT", self.statContent, "TOPRIGHT", 0, -top)
            top = top + ROW_H
            local now = C.Weight(row.stat, entry)
            local tiers = #(entry.cap_tiers or {})
            row.name:SetText(label .. (tiers > 0 and (" |cffffd100[" .. tiers .. " cap]|r") or ""))
            local base = entry.base_weight or 0
            local text = Number(base)
            if now ~= base then text = text .. " / |cffffd100" .. Number(now) .. "|r" end
            row.value:SetText(base == 0 and tiers == 0 and "|cff777777-|r" or text)
            row.bg:SetColorTexture(1, 0.82, 0, row.stat == self.stat and 0.18 or 0)
        end
    end
    self.statContent:SetHeight(math.max(top, 1))
end

---------------------------------------------------------------------------
-- Right: the stat
---------------------------------------------------------------------------

local function Unit(name) return C.PERCENT[name] and "%" or "" end

function Dz:BuildDetail(f)
    local x = 492
    self.statTitle = Text(f, "StatLedgerGameFontNormalLarge")
    self.statTitle:SetPoint("TOPLEFT", x, -42)
    self.statNow = Text(f, "StatLedgerGameFontHighlightSmall")
    self.statNow:SetPoint("TOPLEFT", self.statTitle, "BOTTOMLEFT", 0, -4)
    self.statNow:SetWidth(390)
    self.statNow:SetJustifyH("LEFT")

    local label = Text(f, "StatLedgerGameFontNormal")
    label:SetPoint("TOPLEFT", x, -86)
    label:SetText("Base weight")
    self.baseBox = NumberBox(f, 60, function(n)
        Dz:Entry().base_weight = n
        Dz:Edited()
    end)
    self.baseBox:SetPoint("LEFT", label, "RIGHT", 14, 0)
    local function Step(by)
        return function()
            local entry = Dz:Entry()
            entry.base_weight = math.max(0, math.floor(((entry.base_weight or 0) + by) * 100 + 0.5) / 100)
            Dz:Edited()
        end
    end
    local minus = Button(f, "-", 24, Step(-0.1), "0.1 less")
    minus:SetPoint("LEFT", self.baseBox, "RIGHT", 6, 0)
    local plus = Button(f, "+", 24, Step(0.1), "0.1 more")
    plus:SetPoint("LEFT", minus, "RIGHT", 2, 0)
    local reset = Button(f, "Reset stat", 80, function()
        P.ResetStat(Dz:Profile(), Dz.stat)
        Dz:Refresh()
    end, "This stat goes back to the profile's default.")
    reset:SetPoint("LEFT", plus, "RIGHT", 8, 0)

    -- The chart: a bar for each stretch of values, as tall as the weight there.
    local chart = CreateFrame("Frame", nil, f)
    chart:SetPoint("TOPLEFT", x, -112)
    chart:SetSize(380, 84)
    local bg = chart:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.4)
    self.chart, self.bars, self.marks = chart, {}, {}
    self.chartLeft = Text(chart, "StatLedgerGameFontDisableSmall")
    self.chartLeft:SetPoint("TOPLEFT", chart, "BOTTOMLEFT", 0, -2)
    self.chartRight = Text(chart, "StatLedgerGameFontDisableSmall")
    self.chartRight:SetPoint("TOPRIGHT", chart, "BOTTOMRIGHT", 0, -2)
    self.chartKey = Text(chart, "StatLedgerGameFontDisableSmall")
    self.chartKey:SetPoint("TOP", chart, "BOTTOM", 0, -2)
    self.chartKey:SetText("|cff66bbffyou|r   |cffff9933caps|r")

    local tiersHead = Text(f, "StatLedgerGameFontNormal")
    tiersHead:SetPoint("TOPLEFT", x, -218)
    tiersHead:SetText("Cap tiers")
    local add = Button(f, "Add cap tier", 110, function()
        local entry = Dz:Entry()
        local tiers = entry.cap_tiers
        local top = tiers[#tiers] and tiers[#tiers].threshold or 0
        tiers[#tiers + 1] = { threshold = top + 1, label = "", weight = (entry.base_weight or 0) / 2 }
        Dz:Edited()
    end)
    add:SetPoint("LEFT", tiersHead, "RIGHT", 12, 0)

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", x, -242)
    scroll:SetSize(372, 342)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(372, 100)
    scroll:SetScrollChild(content)
    self.cardContent = content
    self.cards = {}
    self.noTiers = Text(content, "StatLedgerGameFontDisableSmall")
    self.noTiers:SetPoint("TOPLEFT", 2, -4)
    self.noTiers:SetWidth(360)
    self.noTiers:SetJustifyH("LEFT")
    self.noTiers:SetText("No caps: this stat keeps its base weight at any value. Add a tier to change "
        .. "its weight past a value, or set it to 0 for a hard cap.")
end

function Dz:RefreshChart(entry, value)
    local tiers = C.Tiers(entry)
    local top = math.max(10, (value or 0) * 1.25)
    for _, t in ipairs(tiers) do top = math.max(top, t.at * 1.25) end
    local tallest = entry.base_weight or 0
    for _, t in ipairs(tiers) do tallest = math.max(tallest, t.tier.weight or 0) end
    if tallest <= 0 then tallest = 1 end

    local width, height = self.chart:GetSize()
    local function X(v) return math.max(0, math.min(1, v / top)) * width end
    local segments, from, weight = {}, 0, entry.base_weight or 0
    for _, t in ipairs(tiers) do
        if t.at > from then
            segments[#segments + 1] = { from, t.at, weight }
            from = t.at
        end
        weight = t.tier.weight or 0
    end
    segments[#segments + 1] = { from, top, weight }

    for i, bar in ipairs(self.bars) do bar:SetShown(segments[i] ~= nil) end
    for i, s in ipairs(segments) do
        local bar = self.bars[i]
        if not bar then
            bar = self.chart:CreateTexture(nil, "ARTWORK")
            bar:SetColorTexture(0.3, 0.75, 0.45, 0.8)
            self.bars[i] = bar
        end
        bar:ClearAllPoints()
        bar:SetPoint("BOTTOMLEFT", X(s[1]), 0)
        bar:SetSize(math.max(1, X(s[2]) - X(s[1]) - 1), math.max(1, s[3] / tallest * (height - 4)))
        bar:Show()
    end

    local marks = {}
    for _, t in ipairs(tiers) do marks[#marks + 1] = { t.at, 1, 0.6, 0.2 } end
    if value then marks[#marks + 1] = { value, 0.4, 0.73, 1 } end
    for i, mark in ipairs(self.marks) do mark:SetShown(marks[i] ~= nil) end
    for i, m in ipairs(marks) do
        local mark = self.marks[i]
        if not mark then
            mark = self.chart:CreateTexture(nil, "OVERLAY")
            self.marks[i] = mark
        end
        mark:SetColorTexture(m[2], m[3], m[4], 1)
        mark:ClearAllPoints()
        mark:SetPoint("BOTTOMLEFT", X(m[1]), 0)
        mark:SetSize(2, height)
        mark:Show()
    end
    self.chartLeft:SetText("0")
    self.chartRight:SetText(Number(top) .. Unit(self.stat))
end

-- One tier's card. Offsets each take a line under it.
function Dz:CreateCard()
    local card = CreateFrame("Frame", nil, self.cardContent)
    card:SetWidth(362)
    local bg = card:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.05)

    local at = Text(card)
    at:SetPoint("TOPLEFT", 8, -11)
    at:SetText("At")
    card.threshold = NumberBox(card, 50, function(n)
        card.tier.threshold = n
        table.sort(Dz:Entry().cap_tiers, function(a, b) return (a.threshold or 0) < (b.threshold or 0) end)
        Dz:Edited()
    end)
    card.threshold:SetPoint("LEFT", at, "RIGHT", 10, 0)
    card.unit = Text(card)
    card.unit:SetPoint("LEFT", card.threshold, "RIGHT", 4, 0)
    local arrow = Text(card)
    arrow:SetPoint("LEFT", card.threshold, "RIGHT", 22, 0)
    arrow:SetText("weight becomes")
    card.weight = NumberBox(card, 50, function(n)
        card.tier.weight = n
        Dz:Edited()
    end)
    card.weight:SetPoint("LEFT", arrow, "RIGHT", 10, 0)
    local remove = Button(card, "X", 24, function()
        local tiers = Dz:Entry().cap_tiers
        for i, tier in ipairs(tiers) do
            if tier == card.tier then
                table.remove(tiers, i)
                break
            end
        end
        Dz:Edited()
    end, "Delete this tier")
    remove:SetPoint("TOPRIGHT", -4, -6)

    local noteLabel = Text(card, "StatLedgerGameFontDisableSmall")
    noteLabel:SetPoint("TOPLEFT", 8, -37)
    noteLabel:SetText("Note")
    card.note = Box(card, 280, function(text)
        card.tier.label = text
        Dz:Refresh()
    end)
    card.note:SetPoint("LEFT", noteLabel, "RIGHT", 12, 0)

    card.lines = {}
    card.addOffset = Button(card, "Move with a stat", 130, function(b) Dz:OffsetMenu(b, card.tier) end,
        "Add another stat to this threshold: a 35% crit cap moved by Hit at 1 sits at 40% with 5% hit.")
    card.result = Text(card, "StatLedgerGameFontHighlightSmall")
    card.result:SetPoint("LEFT", card.addOffset, "RIGHT", 8, 0)
    card.result:SetWidth(220)
    card.result:SetJustifyH("LEFT")
    return card
end

-- Every stat the menu offers: the profile's, then the other hits; not the stat being capped.
function Dz:OffsetMenu(owner, tier, offset)
    Menu(owner, function(_, root)
        root:CreateTitle("Move this threshold with")
        local function Choice(name)
            root:CreateButton(C.Label(name), function()
                if offset then
                    offset.stat = name
                else
                    tier.offsets = tier.offsets or {}
                    tier.offsets[#tier.offsets + 1] = { stat = name, factor = 1 }
                end
                Dz:Edited()
            end)
        end
        for _, group in ipairs(D.STAT_GROUPS) do
            for i = 2, #group do
                if group[i] ~= self.stat then Choice(group[i]) end
            end
        end
        for name in pairs(C.OFFSET_EXTRA) do Choice(name) end
    end)
end

function Dz:CreateOffsetLine(card)
    local line = CreateFrame("Frame", nil, card)
    line:SetSize(346, 50)
    local plus = Text(line)
    plus:SetPoint("TOPLEFT", 0, -5)
    plus:SetText("Add")
    line.factor = NumberBox(line, 40, function(n)
        line.offset.factor = n
        Dz:Edited()
    end)
    line.factor:SetPoint("LEFT", plus, "RIGHT", 10, 0)
    local times = Text(line)
    times:SetPoint("LEFT", line.factor, "RIGHT", 4, 0)
    times:SetText("x")
    line.stat = Button(line, "", 120, function(b) Dz:OffsetMenu(b, card.tier, line.offset) end,
        "Choose the stat")
    line.stat:SetPoint("LEFT", times, "RIGHT", 6, 0)
    line.value = Text(line, "StatLedgerGameFontHighlightSmall")
    line.value:SetPoint("LEFT", line.stat, "RIGHT", 6, 0)
    local remove = Button(line, "X", 24, function()
        for i, offset in ipairs(card.tier.offsets) do
            if offset == line.offset then
                table.remove(card.tier.offsets, i)
                break
            end
        end
        if #card.tier.offsets == 0 then card.tier.offsets = nil end
        Dz:Edited()
    end, "Stop moving with this stat")
    remove:SetPoint("TOPRIGHT", 0, 0)

    -- Its own limit: blank for none.
    local upTo = Text(line, "StatLedgerGameFontHighlightSmall")
    upTo:SetPoint("TOPLEFT", 0, -31)
    upTo:SetText("Up to")
    line.cap = Box(line, 44, function(text, box)
        local n = tonumber(text)
        if text == "" then
            line.offset.cap, line.offset.factor_after = nil, nil
        elseif n then
            line.offset.cap = n
        else
            return box:SetText(box.shown or "")
        end
        Dz:Edited()
    end)
    line.cap:SetPoint("LEFT", upTo, "RIGHT", 10, 0)
    line.capUnit = Text(line, "StatLedgerGameFontHighlightSmall")
    line.capUnit:SetPoint("LEFT", line.cap, "RIGHT", 2, 0)
    Tooltip(line.cap, "Past this value the stat stops moving the threshold, or counts at the rate on the right. Blank: no limit.")
    line.afterLabel = Text(line, "StatLedgerGameFontHighlightSmall")
    line.afterLabel:SetPoint("LEFT", line.cap, "RIGHT", 18, 0)
    line.afterLabel:SetText("then x")
    line.after = NumberBox(line, 40, function(n)
        line.offset.factor_after = n
        Dz:Edited()
    end)
    line.after:SetPoint("LEFT", line.afterLabel, "RIGHT", 10, 0)
    return line
end

function Dz:FillCard(card, tier, unit)
    card.tier = tier
    card.threshold:Show_(Number(tier.threshold))
    card.weight:Show_(Number(tier.weight))
    card.note:Show_(tier.label or "")
    card.unit:SetText(unit)

    local offsets = tier.offsets or {}
    for i, line in ipairs(card.lines) do line:SetShown(offsets[i] ~= nil) end
    local top = 60
    for i, offset in ipairs(offsets) do
        local line = card.lines[i] or self:CreateOffsetLine(card)
        card.lines[i] = line
        line.offset = offset
        line:SetPoint("TOPLEFT", 8, -top)
        line.factor:Show_(Number(offset.factor))
        line.stat:SetText(C.Label(offset.stat))
        line.value:SetText(("%+.1f%s"):format(C.Offset(offset), unit))
        line.cap:Show_(offset.cap and Number(offset.cap) or "")
        line.capUnit:SetText(Unit(offset.stat))
        line.after:Show_(Number(offset.factor_after))
        line.after:SetShown(offset.cap ~= nil)
        line.afterLabel:SetShown(offset.cap ~= nil)
        line:Show()
        top = top + 52
    end
    card.addOffset:ClearAllPoints()
    card.addOffset:SetPoint("TOPLEFT", 8, -top)
    if #offsets > 0 then
        card.result:SetText(("Sits at |cffffd100%s%s|r now"):format(Number(C.Threshold(tier)), unit))
    else
        card.result:SetText("")
    end
    card:SetHeight(top + 30)
end

function Dz:RefreshDetail()
    local entry = self:Entry()
    if not entry then return end
    local name, unit = self.stat, Unit(self.stat)
    self.statTitle:SetText(C.Label(name))
    local value = C.Value(name, entry)
    local weight, active = C.Resolve(entry, value)
    local now = value and (Number(value) .. Unit(entry.reads or name)) or "not readable"
    local reads = entry.reads and (" (" .. C.Label(entry.reads) .. ")") or ""
    self.statNow:SetText(("You have %s%s. Worth %s%s."):format(now, reads, Number(weight),
        active and (" from a cap" .. (active.label ~= "" and active.label and (": " .. active.label) or "")) or ""))
    self.baseBox:Show_(Number(entry.base_weight))
    self:RefreshChart(entry, value)

    local tiers = entry.cap_tiers or {}
    self.noTiers:SetShown(#tiers == 0)
    for i, card in ipairs(self.cards) do card:SetShown(tiers[i] ~= nil) end
    local top = 0
    for i, tier in ipairs(tiers) do
        local card = self.cards[i] or self:CreateCard()
        self.cards[i] = card
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", 0, -top)
        self:FillCard(card, tier, unit)
        card:Show()
        top = top + card:GetHeight() + 6
    end
    self.cardContent:SetHeight(math.max(top, 1))
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

function Dz:Build()
    local f = CreateFrame("Frame", "StatLedgerDesignerFrame", UIParent, "BackdropTemplate")
    f:SetSize(900, 600)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0.05, 0.05, 0.08, 0.98)
    f:Hide()
    tinsert(UISpecialFrames, "StatLedgerDesignerFrame") -- Escape closes it

    local title = Text(f, "StatLedgerGameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText(ns.IconMarkup(20) .. "  Weight Designer")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    self.frame = f
    self:BuildProfiles(f)
    self:BuildStats(f)
    self:BuildDetail(f)
    f:SetScript("OnShow", function() Dz:Refresh() end)
    return f
end

function Dz:Refresh()
    local f = self.frame
    if not (f and f:IsShown()) or not self:Profile() then return end
    self:RefreshProfiles()
    self:RefreshStats()
    self:RefreshDetail()
end

function Dz:Open()
    if not P.Char() then return ns:Print("Your character isn't ready yet. Try again in a moment.") end
    self.label = select(2, P.Active())
    self.stat = self.stat or "agility"
    local f = self.frame or self:Build()
    if f:IsShown() then return self:Refresh() end
    f:Show()
end

for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "COMBAT_RATING_UPDATE" }) do
    ns:On(event, function() Dz:Refresh() end)
end
