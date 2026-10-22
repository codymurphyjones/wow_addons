local ADDON, ns = ...

local UI = {}
ns.UI = UI

local SIZE, GAP = 32, 4
local ROW_HEIGHT = 58
local LIST_WIDTH = 440
local FRAME_WIDTH, FRAME_HEIGHT = 1010, 640

local function SavePosition(frame)
    local point, _, relPoint, x, y = frame:GetPoint(1)
    ns.db.point = { point, relPoint, x, y }
end

local function CreateSlotButton(row, index)
    local btn = CreateFrame("Button", nil, row)
    btn:SetSize(SIZE, SIZE)
    btn:SetPoint("TOPLEFT", 2 + (index - 1) * (SIZE + GAP), -20)

    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetColorTexture(0, 0, 0, 0.6)

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    btn.border = btn:CreateTexture(nil, "OVERLAY")
    btn.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    btn.border:SetBlendMode("ADD")
    btn.border:SetSize(SIZE * 1.8, SIZE * 1.8)
    btn.border:SetPoint("CENTER")

    btn.selected = btn:CreateTexture(nil, "OVERLAY")
    btn.selected:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    btn.selected:SetBlendMode("ADD")
    btn.selected:SetAllPoints()

    btn.badge = btn:CreateFontString(nil, "OVERLAY", "ModifiedNumberFontNormalSmall")
    btn.badge:SetPoint("TOPRIGHT", -1, -2)
    btn.badge:SetText("|cffffd100M|r")

    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    btn:SetScript("OnClick", function(self) UI:SelectSlot(self.slot) end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if HasAction(self.slot) then
            GameTooltip:SetAction(self.slot)
        else
            GameTooltip:SetText("Empty")
        end
        GameTooltip:AddLine(ns.Bars:Describe(self.slot), 0.6, 0.6, 0.6)
        local design = ns.db.designs[self.slot]
        if design then
            if design.detached then
                GameTooltip:AddLine("Design saved, but its macro is no longer on this button.", 1, 0.3, 0.3, true)
            else
                GameTooltip:AddLine("Managed by Modified (" .. design.macroName .. ")", 0.2, 1, 0.6)
            end
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return btn
end

function UI:GetRow(i)
    local row = self.rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, self.content)
    row:SetSize(LIST_WIDTH, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
    row.label = row:CreateFontString(nil, "OVERLAY", "ModifiedGameFontNormal")
    row.label:SetPoint("TOPLEFT", 2, -2)
    row.buttons = {}
    for b = 1, ns.Bars.BUTTONS_PER_BAR do
        row.buttons[b] = CreateSlotButton(row, b)
    end
    self.rows[i] = row
    return row
end

function UI:Create()
    if self.frame then return self.frame end

    local f = CreateFrame("Frame", "ModifiedMainFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    local p = ns.db.point
    if p then
        f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        f:SetPoint("CENTER", 120, 0)
    end
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
    end)
    f:SetScript("OnShow", function() UI:Refresh() end)
    f:Hide()
    tinsert(UISpecialFrames, f:GetName())
    self.frame = f

    local title = f:CreateFontString(nil, "OVERLAY", "ModifiedGameFontHighlight")
    title:SetPoint("TOP", 0, -5)
    title:SetText("Modified - Modifier Macro Designer")
    local titleIcon = f:CreateTexture(nil, "OVERLAY")
    titleIcon:SetSize(18, 18)
    titleIcon:SetPoint("RIGHT", title, "LEFT", -5, 0)
    titleIcon:SetTexture(ns.ICON)

    local showEmpty = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    showEmpty:SetSize(24, 24)
    showEmpty:SetPoint("TOPLEFT", 12, -28)
    -- The same option as Options > AddOns > Modified; its apply redraws this list.
    showEmpty:SetScript("OnClick", function(self)
        ns:SetOption("db.showEmpty", self:GetChecked() and true or false)
    end)
    local showEmptyLabel = showEmpty:CreateFontString(nil, "OVERLAY", "ModifiedGameFontNormalSmall")
    showEmptyLabel:SetPoint("LEFT", showEmpty, "RIGHT", 2, 0)
    showEmptyLabel:SetText("Show empty bars")
    self.showEmpty = showEmpty

    self.counter = f:CreateFontString(nil, "OVERLAY", "ModifiedGameFontHighlightSmall")
    self.counter:SetPoint("TOPLEFT", 150, -34)

    local settings = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    settings:SetSize(76, 22)
    settings:SetPoint("TOPLEFT", 386, -29)
    settings:SetText("Settings")
    settings:SetScript("OnClick", function() ns.Settings:Open() end)

    local scroll = CreateFrame("ScrollFrame", "ModifiedBarScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -58)
    scroll:SetPoint("BOTTOMLEFT", 12, 12)
    scroll:SetWidth(LIST_WIDTH)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(LIST_WIDTH, 10)
    scroll:SetScrollChild(content)
    self.content = content
    self.rows = {}

    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.15)
    divider:SetPoint("TOPLEFT", 478, -28)
    divider:SetPoint("BOTTOMLEFT", 478, 12)
    divider:SetWidth(1)

    ns.Editor:Create(f)
    return f
end

function UI:Toggle()
    local f = self:Create()
    f:SetShown(not f:IsShown())
end

function UI:SelectSlot(slot)
    self.selectedSlot = slot
    ns.Editor:Load(slot)
    self:Refresh()
end

function UI:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    ns.Manager:UpdateDetached()

    self.showEmpty:SetChecked(ns.db.showEmpty)
    local managed, limit = ns.Manager:ManagedCount(), ns.Manager:GetLimit()
    local used, max = ns.Manager:CharacterMacroUsage()
    self.counter:SetText(("Modified: %s%d/%d|r   Slots: %s%d/%d|r"):format(
        managed >= limit and "|cffff5555" or "|cffffffff", managed, limit,
        used >= max and "|cffff5555" or "|cffffffff", used, max))

    local bars = ns.Bars:GetDisplayBars(ns.db.showEmpty)
    for i, bar in ipairs(bars) do
        local row = self:GetRow(i)
        row:Show()
        row.label:SetText(bar.name)
        for b, btn in ipairs(row.buttons) do
            local slot = bar.start + b - 1
            btn.slot = slot
            local texture = GetActionTexture(slot)
            btn.icon:SetTexture(texture)
            btn.icon:SetShown(texture ~= nil)
            local design = ns.db.designs[slot]
            btn.border:SetShown(design ~= nil)
            if design and design.detached then
                btn.border:SetVertexColor(1, 0.2, 0.2)
            else
                btn.border:SetVertexColor(1, 0.82, 0)
            end
            btn.badge:SetShown(design ~= nil and not design.detached)
            btn.selected:SetShown(slot == self.selectedSlot)
        end
    end
    for i = #bars + 1, #self.rows do self.rows[i]:Hide() end
    self.content:SetHeight(math.max(#bars * ROW_HEIGHT, 10))

    ns.Editor:Refresh()
end
