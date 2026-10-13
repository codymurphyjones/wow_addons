local _, ns = ...

-- Options > AddOns > StatLedger: one list of every stat. Drag rows into
-- order; X moves a stat under "Removed" (still shown, so it can be dragged
-- back), + adds it back at the bottom.
local S = {}
ns.Settings = S

local ROW_H = 22
local DIV_H = 26
local EDGE = 20 -- auto-scroll zone while dragging

-- The spec being edited: one picked on the page, else the player's own.
function S:Editing()
    if self.editing then
        local class, spec = self.editing:match("^(%u+):(%d)$")
        return class, tonumber(spec)
    end
    local class, spec = ns.API:GetActiveSpec()
    return class, spec
end

-- Where a drag lands. rankedMids: distance from the list top to the middle
-- of each ranked row (the dragged one left out), in order. dividerMid: the
-- same for the "Removed" divider. cursor: distance from the list top to the
-- cursor. Returns "insert", index (in the list without the dragged stat) or
-- "remove".
function S.DropTarget(rankedMids, dividerMid, cursor)
    if cursor > dividerMid then return "remove" end
    local index = 1
    for _, mid in ipairs(rankedMids) do
        if mid < cursor then index = index + 1 end
    end
    return "insert", index
end

---------------------------------------------------------------------------
-- Building the page
---------------------------------------------------------------------------

local function Text(parent, template, size)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    if size then
        local font, _, flags = fs:GetFont()
        if font then fs:SetFont(font, size, flags) end
    end
    return fs
end

local function SmallButton(parent, label, r, g, b)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(20, 20)
    button.text = Text(button, "GameFontNormal", 14)
    button.text:SetPoint("CENTER")
    button.text:SetText(label)
    button.text:SetTextColor(r, g, b)
    local hl = button:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)
    return button
end

local function Tooltip(frame, text)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function S:BuildClassRow(page, anchor)
    self.classButtons = {}
    local prev
    for _, class in ipairs(ns.API:GetClasses()) do
        local button = CreateFrame("Button", nil, page)
        button:SetSize(32, 32)
        if prev then
            button:SetPoint("LEFT", prev, "RIGHT", 6, 0)
        else
            button:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
        end
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
        if coords then
            icon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
            icon:SetTexCoord(unpack(coords))
        else
            icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end
        button.icon = icon
        local selected = button:CreateTexture(nil, "OVERLAY")
        selected:SetPoint("TOPLEFT", -4, 4)
        selected:SetPoint("BOTTOMRIGHT", 4, -4)
        selected:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        selected:SetBlendMode("ADD")
        button.selected = selected
        local hl = button:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        hl:SetBlendMode("ADD")
        Tooltip(button, ns.API:GetClassName(class))
        button:SetScript("OnClick", function()
            local current = S:Editing()
            if class == current then return end
            local activeClass, activeSpec = ns.API:GetActiveSpec()
            local spec = class == activeClass and activeSpec or ns.Data.SPECS[class][1]
            S.editing = class .. ":" .. spec
            S:Refresh()
        end)
        self.classButtons[class] = button
        prev = button
    end
    return prev
end

function S:BuildSpecRow(page, anchor)
    self.specButtons = {}
    local prev
    for spec = 1, 3 do
        local button = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
        button:SetSize(150, 24)
        if prev then
            button:SetPoint("LEFT", prev, "RIGHT", 6, 0)
        else
            button:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
        end
        button:SetScript("OnClick", function()
            local class = S:Editing()
            S.editing = class .. ":" .. spec
            S:Refresh()
        end)
        self.specButtons[spec] = button
        prev = button
    end
    return self.specButtons[1]
end

function S:CreateRow(content)
    local row = CreateFrame("Button", nil, content)
    row:SetHeight(ROW_H)
    row:SetPoint("LEFT")
    row:SetPoint("RIGHT")
    row:RegisterForDrag("LeftButton")

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)

    row.rank = Text(row, "GameFontNormal")
    row.rank:SetPoint("LEFT", 8, 0)
    row.rank:SetWidth(24)
    row.rank:SetJustifyH("RIGHT")
    row.grip = Text(row, "GameFontDisable")
    row.grip:SetPoint("LEFT", row.rank, "RIGHT", 8, 0)
    row.grip:SetText("=")
    row.label = Text(row, "GameFontHighlight")
    row.label:SetPoint("LEFT", row.grip, "RIGHT", 8, 0)
    row.tag = Text(row, "GameFontDisableSmall")
    row.tag:SetPoint("LEFT", row.label, "RIGHT", 8, 0)

    row.remove = SmallButton(row, "X", 1, 0.3, 0.3)
    row.remove:SetPoint("RIGHT", -6, 0)
    Tooltip(row.remove, "Remove (it stays listed under Removed)")
    row.remove:SetScript("OnClick", function()
        local class, spec = S:Editing()
        ns.API:RemoveStat(class, spec, row.stat)
    end)

    row.add = SmallButton(row, "+", 0.3, 1, 0.3)
    row.add:SetPoint("RIGHT", -6, 0)
    Tooltip(row.add, "Add back at the bottom of the priority")
    row.add:SetScript("OnClick", function()
        local class, spec = S:Editing()
        ns.API:InsertStat(class, spec, row.stat)
    end)

    row:SetScript("OnDragStart", function(self) S:BeginDrag(self) end)
    row:SetScript("OnDragStop", function() S:EndDrag() end)
    return row
end

function S:Build()
    local page = CreateFrame("Frame")
    page:Hide()
    -- The logo after the name, so the AddOns list still sorts by "StatLedger".
    page.name = "StatLedger " .. ns.IconMarkup(16)
    page.OnCommit = function() end
    page.OnDefault = function() end
    page.OnRefresh = function() S:Refresh() end
    page:SetScript("OnShow", function() S:Refresh() end)
    page:SetScript("OnHide", function() S:CancelDrag() end)
    self.page = page

    local title = Text(page, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(ns.IconMarkup(28) .. "  StatLedger")
    local hint = Text(page, "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    hint:SetText("Pick a class and spec, then drag stats into order (best first). "
        .. "X removes a stat; drag it back up, or press +, to use it again.")

    local classRow = self:BuildClassRow(page, hint)
    local specRow = self:BuildSpecRow(page, self.classButtons[ns.API:GetClasses()[1]])
    self.classLabel = Text(page, "GameFontNormal")
    self.classLabel:SetPoint("LEFT", classRow, "RIGHT", 12, 0)

    local reset = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    reset:SetSize(140, 24)
    reset:SetPoint("TOPLEFT", specRow, "BOTTOMLEFT", 0, -10)
    reset:SetText("Reset to default")
    reset:SetScript("OnClick", function()
        local class, spec = S:Editing()
        ns.API:ResetPriority(class, spec)
    end)
    self.status = Text(page, "GameFontHighlight")
    self.status:SetPoint("LEFT", reset, "RIGHT", 12, 0)

    local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", reset, "BOTTOMLEFT", 0, -12)
    scroll:SetPoint("BOTTOMRIGHT", -32, 12)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(400, 400)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, width) content:SetWidth(width) end)
    self.scroll, self.content = scroll, content

    local frameBg = scroll:CreateTexture(nil, "BACKGROUND")
    frameBg:SetPoint("TOPLEFT", -4, 4)
    frameBg:SetPoint("BOTTOMRIGHT", 4, -4)
    frameBg:SetColorTexture(0, 0, 0, 0.35)

    self.rows = {}
    for _, stat in ipairs(ns.API:GetStats()) do
        local row = self:CreateRow(content)
        row.stat = stat
        row.label:SetText(ns.API:GetStatLabel(stat))
        self.rows[stat] = row
    end

    local divider = CreateFrame("Frame", nil, content)
    divider:SetHeight(DIV_H)
    divider:SetPoint("LEFT")
    divider:SetPoint("RIGHT")
    local divText = Text(divider, "GameFontNormal")
    divText:SetPoint("LEFT", 8, -2)
    divText:SetText("Removed")
    divText:SetTextColor(1, 0.35, 0.35)
    local line = divider:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("LEFT", divText, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", -8, -2)
    line:SetColorTexture(1, 0.35, 0.35, 0.6)
    self.divider = divider
    self.dividerText = divText

    -- While dragging: a copy of the row under the cursor, and a line where it will land.
    local ghost = CreateFrame("Frame", nil, content)
    ghost:SetHeight(ROW_H)
    ghost:SetPoint("LEFT")
    ghost:SetPoint("RIGHT")
    ghost:SetFrameLevel(content:GetFrameLevel() + 20)
    local ghostBg = ghost:CreateTexture(nil, "BACKGROUND")
    ghostBg:SetAllPoints()
    ghostBg:SetColorTexture(0.25, 0.2, 0.05, 0.9)
    ghost.label = Text(ghost, "GameFontNormal")
    ghost.label:SetPoint("LEFT", 56, 0)
    ghost:Hide()
    self.ghost = ghost

    local marker = content:CreateTexture(nil, "OVERLAY")
    marker:SetHeight(2)
    marker:SetPoint("LEFT")
    marker:SetPoint("RIGHT")
    marker:Hide()
    self.marker = marker

    return page
end

---------------------------------------------------------------------------
-- Showing the edited spec
---------------------------------------------------------------------------

-- Pins frame to the list, top pixels down.
local function Place(frame, content, top)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -top)
    frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -top)
end

function S:Refresh()
    if not self.page then return end
    local API = ns.API
    local class, spec = self:Editing()
    local activeClass, activeSpec = API:GetActiveSpec()

    for c, button in pairs(self.classButtons) do
        button.selected:SetShown(c == class)
        button.icon:SetDesaturated(c ~= class)
    end
    self.classLabel:SetText(class and API:GetClassName(class) or "")
    local specs = class and API:GetSpecs(class) or {}
    for s, button in ipairs(self.specButtons) do
        local name = specs[s] or "?"
        if class == activeClass and s == activeSpec then name = name .. " (you)" end
        button:SetText(name)
        if s == spec then button:LockHighlight() else button:UnlockHighlight() end
    end
    if API:IsCustom(class, spec) then
        self.status:SetText("|cff66bbffCustomised|r (saved for all your characters)")
    else
        self.status:SetText("|cff999999Default|r for " .. (API:GetSpecName(class, spec) or "this spec"))
    end

    -- Ranked rows, the divider, then removed rows.
    local content = self.content
    local ranked, removed = API:GetPriority(class, spec), API:GetRemovedStats(class, spec)
    self.ranked = ranked
    local top = 0
    for i, stat in ipairs(ranked) do
        local row = self.rows[stat]
        Place(row, content, top)
        row.mid = top + ROW_H / 2
        row.ranked = true
        row.rank:SetText(i .. ".")
        row.label:SetTextColor(1, 1, 1)
        row.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0)
        row.remove:Show()
        row.add:Hide()
        row.tag:SetText("")
        row:SetAlpha(1)
        top = top + ROW_H
    end
    Place(self.divider, content, top)
    self.dividerMid = top + DIV_H / 2
    self.dividerText:SetText(#removed > 0 and "Removed" or "Removed (drag a stat here to remove it)")
    top = top + DIV_H
    for _, stat in ipairs(removed) do
        local row = self.rows[stat]
        Place(row, content, top)
        row.mid = top + ROW_H / 2
        row.ranked = false
        row.rank:SetText("-")
        row.label:SetTextColor(0.55, 0.55, 0.55)
        row.bg:SetColorTexture(0.6, 0.1, 0.1, 0.25)
        row.remove:Hide()
        row.add:Show()
        row.tag:SetText("removed")
        row:SetAlpha(1)
        top = top + ROW_H
    end
    self.listHeight = top
    content:SetHeight(math.max(top, 1))
end

---------------------------------------------------------------------------
-- Dragging
---------------------------------------------------------------------------

-- Cursor distance from the top of the list.
local function CursorDepth(content)
    local _, y = GetCursorPosition()
    return content:GetTop() - y / content:GetEffectiveScale()
end

function S:BeginDrag(row)
    self.dragging = row
    row:SetAlpha(0.3)
    self.ghost.label:SetText(row.label:GetText())
    self.ghost:Show()
    self.page:SetScript("OnUpdate", function() S:UpdateDrag() end)
    self:UpdateDrag()
end

-- Middles of the ranked rows other than the one being dragged.
function S:RankedMids()
    local mids = {}
    for _, stat in ipairs(self.ranked) do
        local row = self.rows[stat]
        if row ~= self.dragging then mids[#mids + 1] = row.mid end
    end
    return mids
end

function S:UpdateDrag()
    local content, scroll = self.content, self.scroll
    local _, y = GetCursorPosition()
    y = y / scroll:GetEffectiveScale()
    local offset = scroll:GetVerticalScroll()
    if y > scroll:GetTop() - EDGE and offset > 0 then
        scroll:SetVerticalScroll(math.max(0, offset - 6))
    elseif y < scroll:GetBottom() + EDGE then
        local range = scroll:GetVerticalScrollRange() or 0
        if offset < range then scroll:SetVerticalScroll(math.min(range, offset + 6)) end
    end

    local depth = math.max(0, math.min(CursorDepth(content), self.listHeight))
    self.ghost:ClearAllPoints()
    self.ghost:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(depth - ROW_H / 2))
    self.ghost:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(depth - ROW_H / 2))

    local mids = self:RankedMids()
    local action, index = S.DropTarget(mids, self.dividerMid, depth)
    local at
    if action == "remove" then
        at = self.dividerMid + DIV_H / 2
        self.marker:SetColorTexture(1, 0.3, 0.3, 1)
    else
        at = mids[index] and (mids[index] - ROW_H / 2) or (#mids > 0 and mids[#mids] + ROW_H / 2 or 0)
        self.marker:SetColorTexture(1, 0.82, 0, 1)
    end
    self.marker:ClearAllPoints()
    self.marker:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -at + 1)
    self.marker:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -at + 1)
    self.marker:Show()
end

function S:CancelDrag()
    if not self.dragging then return end
    self.dragging:SetAlpha(1)
    self.dragging = nil
    self.page:SetScript("OnUpdate", nil)
    self.ghost:Hide()
    self.marker:Hide()
end

function S:EndDrag()
    local row = self.dragging
    if not row then return end
    local depth = math.max(0, math.min(CursorDepth(self.content), self.listHeight))
    local action, index = S.DropTarget(self:RankedMids(), self.dividerMid, depth)
    self:CancelDrag()
    local class, spec = self:Editing()
    if action == "remove" then
        if row.ranked then ns.API:RemoveStat(class, spec, row.stat) end
    else
        ns.API:InsertStat(class, spec, row.stat, index)
    end
    self:Refresh() -- also redraws a drop that changed nothing
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------

-- Called from Core once SavedVariables are loaded.
function S:Register()
    if self.page then return end
    local page = self:Build()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(page, page.name)
        Settings.RegisterAddOnCategory(category)
        self.category = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(page)
    end
    ns.API:RegisterCallback("StatLedger_Settings", function() S:Refresh() end)
end

-- Opens the page on your own spec.
function S:Open()
    self.editing = nil
    self:Refresh()
    if self.category and Settings.OpenToCategory then
        local ok = pcall(Settings.OpenToCategory, self.category:GetID())
        if ok then return end
    elseif self.page and InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(self.page)
        InterfaceOptionsFrame_OpenToCategory(self.page)
        return
    end
    ns:Print("Open the game menu > Options > AddOns > StatLedger.")
end
