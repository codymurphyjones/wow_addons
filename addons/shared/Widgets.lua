local addonName, ns = ...

-- The flat widget kit every window here draws with (Wally's look): backdrops, labels, buttons,
-- checkboxes, edit boxes, a yes/no popup, item text helpers and the scrolling row list. Shared by
-- the addons in addons/shared/README.md; each loads its own copy, so fonts come from addonName
-- (<Addon>GameFont...) and colours from ns.Palette. WidgetsPlus.lua adds the menus, dropdowns and
-- dialogs Quartermaster and Wealth Planner use, on the same table.
--
-- Per-addon looks: an addon that wants one changes W.style after this file loads (before it builds
-- any window):
--   dimDisabled  buttons dim their text while disabled and don't light up under the mouse (BattleRecap)
--   checkSize, checkGap  checkbox size and the gap before its label (26 and 3; BattleRecap 24 and 2)
local PAL = ns.Palette
local W = ns.Widgets or {}
ns.Widgets = W

W.style = W.style or { dimDisabled = false, checkSize = 26, checkGap = 3 }

local WHITE = "Interface\\Buttons\\WHITE8X8"
local ROW_H, ROW_GAP = 38, 4
local ACCENT = PAL.accent
local MUTED = PAL.muted
local UNKNOWN_ICON = 134400
W.WHITE, W.ROW_H, W.ROW_GAP, W.ACCENT, W.MUTED, W.UNKNOWN_ICON = WHITE, ROW_H, ROW_GAP, ACCENT, MUTED, UNKNOWN_ICON

-- This addon's copies of the game fonts (shared/Fonts.lua).
local FONT = addonName .. "GameFontHighlight"
local FONT_SMALL = addonName .. "GameFontHighlightSmall"
local FONT_PLACEHOLDER = addonName .. "GameFontDisableSmall"

function W.SetBackdrop(f, alpha)
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(PAL.bg[1], PAL.bg[2], PAL.bg[3], alpha or 1)
    f:SetBackdropBorderColor(PAL.border[1], PAL.border[2], PAL.border[3], 1)
end
local SetBackdrop = W.SetBackdrop

function W.Label(parent, text, font, x, y, width)
    local t = parent:CreateFontString(nil, "OVERLAY", font or FONT)
    t:SetPoint("TOPLEFT", x, y)
    t:SetJustifyH("LEFT")
    if width then t:SetWidth(width) end
    t:SetText(text)
    return t
end
local Label = W.Label

function W.Muted(fs) fs:SetTextColor(MUTED[1], MUTED[2], MUTED[3]); return fs end
local Muted = W.Muted

function W.MakeButton(parent, text, width, height)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width or 110, height or 28)
    SetBackdrop(b)
    b:SetBackdropColor(PAL.button[1], PAL.button[2], PAL.button[3], 1)
    b.text = b:CreateFontString(nil, "OVERLAY", FONT_SMALL)
    b.text:SetPoint("CENTER"); b.text:SetText(text)
    if W.style.dimDisabled then
        b:SetScript("OnEnter", function(self) if self:IsEnabled() then self:SetBackdropColor(PAL.hover[1], PAL.hover[2], PAL.hover[3], 1) end end)
        b:SetScript("OnDisable", function(self) self.text:SetAlpha(0.35) end)
        b:SetScript("OnEnable", function(self) self.text:SetAlpha(1) end)
    else
        b:SetScript("OnEnter", function(self) self:SetBackdropColor(PAL.hover[1], PAL.hover[2], PAL.hover[3], 1) end)
    end
    b:SetScript("OnLeave", function(self) self:SetBackdropColor(PAL.button[1], PAL.button[2], PAL.button[3], 1) end)
    return b
end
local MakeButton = W.MakeButton

-- Marks one button of a group as the active one (accent border).
function W.SetActive(b, active)
    if active then b:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    else b:SetBackdropBorderColor(PAL.border[1], PAL.border[2], PAL.border[3], 1) end
end

function W.Hint(widget, title, body)
    widget:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(title, ACCENT[1], ACCENT[2], ACCENT[3])
        if body then GameTooltip:AddLine(body, 0.8, 0.85, 0.9, true) end
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

function W.MakeCheckbox(parent, text)
    local size, gap = W.style.checkSize or 26, W.style.checkGap or 3
    local b = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    b:SetSize(size, size)
    b.label = b:CreateFontString(nil, "OVERLAY", FONT_SMALL)
    b.label:SetPoint("LEFT", b, "RIGHT", gap, 0); b.label:SetText(text)
    return b
end

function W.MakeEditBox(parent, width, placeholder)
    local b = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    b:SetSize(width or 160, 26)
    SetBackdrop(b); b:SetBackdropColor(PAL.field[1], PAL.field[2], PAL.field[3], 1)
    b:SetFontObject(FONT_SMALL); b:SetJustifyH("LEFT")
    b:SetAutoFocus(false); b:SetTextInsets(8, 8, 2, 2)
    b.placeholder = b:CreateFontString(nil, "OVERLAY", FONT_PLACEHOLDER)
    b.placeholder:SetPoint("LEFT", 8, 0); b.placeholder:SetText(placeholder or "")
    local function UpdatePlaceholder(self) self.placeholder:SetShown(self:GetText() == "" and not self:HasFocus()) end
    b:SetScript("OnEditFocusGained", UpdatePlaceholder)
    b:SetScript("OnEditFocusLost", UpdatePlaceholder)
    b:HookScript("OnTextChanged", UpdatePlaceholder)
    b:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    b:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return b
end

-- "10/21 14:05" (ns.Format.When when the addon loads shared\Format.lua).
function W.When(t, fmt)
    if ns.Format then return ns.Format.When(t, fmt) end
    return t and date(fmt or "%m/%d %H:%M", t) or ""
end

-- "|cffrrggbb" for an {r, g, b} colour.
function W.Hex(c)
    return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

-- Yes/No question; fn runs on Yes. The popup is this addon's own (<ADDON>_CONFIRM).
local CONFIRM = addonName:upper() .. "_CONFIRM"
function W.Confirm(text, fn)
    if not StaticPopupDialogs[CONFIRM] then
        StaticPopupDialogs[CONFIRM] = {
            text = "%s", button1 = YES or "Yes", button2 = NO or "No",
            OnAccept = function(_, data) if data and data.fn then data.fn() end end,
            timeout = 0, whileDead = 1, hideOnEscape = 1, showAlert = 1, preferredIndex = 3,
        }
    end
    StaticPopup_Show(CONFIRM, text, nil, { fn = fn })
end

-- ---------------------------------------------------------------------------
-- Item text
-- ---------------------------------------------------------------------------

function W.QualityName(name, quality)
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color and color.hex then return color.hex .. name .. "|r" end
    return name
end

function W.EntryText(e, key)
    if e.link then return e.link end
    return W.QualityName(e.name or key, e.quality)
end

local function ItemIcon(item)
    local C = ns.Compat
    local get = (C and C.GetItemInfoInstant) or (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not get then return nil end
    return (select(5, get(item)))
end

-- An entry's icon: e.icon, else the icon of e.id / e.itemID / e.link.
function W.IconFor(e)
    if e.icon then return e.icon end
    local id = e.id or e.itemID
    if id then return ItemIcon(id) or UNKNOWN_ICON end
    if e.link then return ItemIcon(e.link) or UNKNOWN_ICON end
    return UNKNOWN_ICON
end

-- Short money text ("1g 20s") through the addon's Compat.Money; nil prints as "n/a".
function W.Money(copper)
    if not copper then return "|cff8fa3b3n/a|r" end
    local C = ns.Compat
    if C and C.Money then return C.Money(copper) end
    return GetMoneyString and GetMoneyString(copper) or tostring(copper)
end

-- ---------------------------------------------------------------------------
-- Scrolling row list
-- ---------------------------------------------------------------------------
-- item = {
--   icon, noIcon,                 -- noIcon: no icon, the text starts at the left edge
--   text, detail, detailColor,    -- a cut-off detail line shows in full in the tooltip
--   right,                        -- a right-hand column; "a\nb" shows as two lines
--   link, plainText, hint,        -- tooltip: the item link, else plainText; hint under it
--   bar, barText, marker,         -- 0..1 bar; marker 0..1 draws a tick and turns the bar orange past it
--   spark = { values, color, min }, -- a small sparkline (needs ns.Chart)
--   status = { texture, desaturate, onClick, hint },  -- small button left of the icon
--   actions = { {label, fn, hint, width = n}, ... },   -- buttons, right to left
--   onClick, onRightClick(shift), selected, dim }      -- dim: 0..1 alpha for rows not yet acted on

function W.NewRow(list)
    local height = list.rowHeight or ROW_H
    local row = CreateFrame("Button", nil, list.content, "BackdropTemplate")
    row.height = height
    row:SetHeight(height); SetBackdrop(row); row:SetBackdropColor(PAL.row[1], PAL.row[2], PAL.row[3], 1)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(height - 10, height - 10)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.text = row:CreateFontString(nil, "OVERLAY", FONT_SMALL)
    row.text:SetJustifyH("LEFT"); row.text:SetWordWrap(false)
    row.detail = row:CreateFontString(nil, "OVERLAY", FONT_SMALL)
    row.detail:SetJustifyH("LEFT"); row.detail:SetWordWrap(false)
    row.right = row:CreateFontString(nil, "OVERLAY", FONT_SMALL)
    row.right:SetJustifyH("RIGHT"); row.right:SetWordWrap(false); row.right:SetWidth(130)
    if row.right.SetMaxLines then row.right:SetMaxLines(2) end
    row.right:Hide()
    row.barBg = row:CreateTexture(nil, "ARTWORK"); row.barBg:SetColorTexture(0.12, 0.16, 0.19, 1); row.barBg:SetSize(110, 6)
    row.barFill = row:CreateTexture(nil, "OVERLAY"); row.barFill:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    row.barFill:SetPoint("LEFT", row.barBg, "LEFT"); row.barFill:SetHeight(6)
    row.marker = row:CreateTexture(nil, "OVERLAY", nil, 2); row.marker:SetColorTexture(1, 0.82, 0.3, 1); row.marker:SetSize(2, 12)
    row.barText = row:CreateFontString(nil, "OVERLAY", FONT_SMALL); row.barText:SetJustifyH("RIGHT")
    row.barText:SetPoint("BOTTOMRIGHT", row.barBg, "TOPRIGHT", 0, 2)
    row.actions = {}
    row:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.08, 0.14, 0.16, 1)
        local d = self.data
        if not d then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if d.link then GameTooltip:SetHyperlink(d.link) else GameTooltip:AddLine(d.plainText or "", 1, 1, 1) end
        -- The detail line doesn't wrap: show it in full here when it's cut off.
        if d.detail and self.detail.IsTruncated and self.detail:IsTruncated() then
            GameTooltip:AddLine(" "); GameTooltip:AddLine(d.detail, 0.85, 0.9, 0.95, true)
        end
        if d.hint then GameTooltip:AddLine(" "); GameTooltip:AddLine(d.hint, MUTED[1], MUTED[2], MUTED[3], true) end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self) self:SetBackdropColor(PAL.row[1], PAL.row[2], PAL.row[3], 1); GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self, button)
        local d = self.data
        if not d then return end
        if GetCursorInfo() and list.onDrop then return list.onDrop() end
        if button == "RightButton" then
            if d.onRightClick then d.onRightClick(IsShiftKeyDown()) end
        elseif d.link and IsModifiedClick() and HandleModifiedItemClick then
            HandleModifiedItemClick(d.link)
        elseif d.onClick then
            d.onClick()
        end
    end)
    row:SetScript("OnReceiveDrag", function() if list.onDrop then list.onDrop() end end)
    return row
end

local function StatusButton(row)
    local b = CreateFrame("Button", nil, row)
    b:SetSize(18, 18); b:SetPoint("LEFT", 5, 0)
    b.tex = b:CreateTexture(nil, "ARTWORK"); b.tex:SetAllPoints()
    b:SetScript("OnClick", function(self) if self.fn then self.fn() end end)
    b:SetScript("OnEnter", function(self)
        if not self.hint then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(self.hint, 0.85, 0.9, 0.95, true); GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.status = b
    return b
end
W.StatusButton = StatusButton

function W.LayoutRow(row, d, index)
    row.data = d
    row:ClearAllPoints()
    local height = row.height or ROW_H
    local compact = height < 34
    local y = -(index - 1) * (height + ROW_GAP)
    row:SetPoint("TOPLEFT", 0, y); row:SetPoint("TOPRIGHT", 0, y)
    if d.selected then row:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    else row:SetBackdropBorderColor(PAL.border[1], PAL.border[2], PAL.border[3], 1) end

    -- Optional status button pushes the icon and text right.
    local left = 5
    if d.status then
        local s = row.status or StatusButton(row)
        local dimmed = d.status.desaturate and 0.6 or 1
        s.tex:SetTexture(d.status.texture)
        s.tex:SetDesaturated(d.status.desaturate and true or false)
        s.tex:SetVertexColor(dimmed, dimmed, dimmed)
        s.fn, s.hint = d.status.onClick, d.status.hint
        s:EnableMouse(d.status.onClick ~= nil or d.status.hint ~= nil)
        s:Show()
        left = 27
    elseif row.status then
        row.status:Hide()
    end
    row.icon:ClearAllPoints(); row.icon:SetPoint("LEFT", left, 0)
    row.icon:SetShown(not d.noIcon)
    local textX = d.noIcon and (left + 4) or (left + height - 3)
    row.text:ClearAllPoints(); row.text:SetPoint("TOPLEFT", textX, compact and -3 or -5)
    row.detail:ClearAllPoints(); row.detail:SetPoint("TOPLEFT", textX, compact and -16 or -21)

    row.icon:SetTexture(d.icon or UNKNOWN_ICON)
    row.icon:SetDesaturated(d.dim ~= nil)
    row.text:SetText(d.text or "")
    row.detail:SetText(d.detail or "")
    local dc = d.detailColor or MUTED
    row.detail:SetTextColor(dc[1], dc[2], dc[3])
    local alpha = d.dim or 1
    row.icon:SetAlpha(d.dim and math.min(1, alpha + 0.2) or 1)
    row.text:SetAlpha(alpha); row.detail:SetAlpha(alpha)

    -- Action buttons, right to left. A one-character label ("+", "X") gets a small square button.
    local right = -6
    local buttonH = compact and 20 or 22
    for i, a in ipairs(d.actions or {}) do
        local b = row.actions[i]
        if not b then
            b = MakeButton(row, "", 64, buttonH)
            b:SetScript("OnClick", function(self) if self.fn then self.fn() end end)
            b:HookScript("OnEnter", function(self)
                if not self.hint then return end
                GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(self.hint, 0.85, 0.9, 0.95, true); GameTooltip:Show()
            end)
            b:HookScript("OnLeave", function() GameTooltip:Hide() end)
            row.actions[i] = b
        end
        local width = a.width or math.max(#a[1] == 1 and 24 or 54, (#a[1]) * 6 + 18)
        b:SetWidth(width); b.text:SetText(a[1]); b.fn, b.hint = a[2], a[3]
        b:ClearAllPoints(); b:SetPoint("RIGHT", right, 0); b:Show()
        right = right - width - 4
    end
    for i = #(d.actions or {}) + 1, #row.actions do row.actions[i]:Hide() end

    -- Right-hand column (prices, states); two lines when the text has a line break.
    if d.right then
        row.right:SetWordWrap(type(d.right) == "string" and d.right:find("\n", 1, true) ~= nil)
        row.right:ClearAllPoints(); row.right:SetPoint("RIGHT", right - 6, 0)
        row.right:SetText(d.right); row.right:SetAlpha(alpha); row.right:Show()
        right = right - 140
    else
        row.right:Hide()
    end

    -- A small sparkline (the addon's Chart.lua) left of the right-hand column.
    if d.spark and #d.spark.values >= 2 and ns.Chart then
        if not row.spark then
            row.spark = ns.Chart:New(row, 90, height - 14)
            row.spark.frame:EnableMouse(false)
        end
        row.spark:ClearAllPoints(); row.spark:SetPoint("RIGHT", row, "RIGHT", right - 8, 0)
        row.spark:Render({ type = "sparkline", hover = false, min = d.spark.min,
            series = { { values = d.spark.values, color = d.spark.color or ACCENT } } })
        row.spark:Show()
        right = right - 104
    elseif row.spark then
        row.spark:Hide()
    end

    local showBar = d.bar ~= nil
    row.barBg:SetShown(showBar); row.barFill:SetShown(showBar); row.barText:SetShown(showBar)
    row.marker:SetShown(showBar and d.marker ~= nil)
    if showBar then
        row.barBg:ClearAllPoints(); row.barBg:SetPoint("RIGHT", right - 8, compact and -4 or -6)
        row.barFill:SetWidth(math.max(1, 110 * math.min(1, d.bar)))
        local color = (d.marker and d.bar >= d.marker) and { 1, 0.55, 0.35 } or ACCENT
        row.barFill:SetColorTexture(color[1], color[2], color[3], 1)
        row.barText:SetText(d.barText or "")
        if d.marker then
            row.marker:ClearAllPoints(); row.marker:SetPoint("CENTER", row.barBg, "LEFT", 110 * d.marker, 0)
        end
        right = right - 126
    end
    row.text:SetPoint("RIGHT", row, "RIGHT", right - 4, 0)
    row.detail:SetPoint("RIGHT", row, "RIGHT", right - 4, 0)
    row:Show()
end

-- opts.rowHeight: row height in pixels (default 38); opts.bottom: gap under the list (default 0).
-- list:Set(items, emptyText)  list:ScrollToTop()  list.onDrop = fn (an item dropped on the list)
function W.CreateRowList(parent, top, opts)
    local list = { rows = {}, rowHeight = opts and opts.rowHeight or ROW_H }
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, top); scroll:SetPoint("BOTTOMRIGHT", -26, opts and opts.bottom or 0)
    local content = CreateFrame("Frame", nil, scroll); content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, w) content:SetWidth(w) end)
    list.scroll, list.content = scroll, content
    list.empty = Label(parent, "", FONT, 0, top - 60)
    list.empty:SetPoint("RIGHT", -26, 0); list.empty:SetJustifyH("CENTER"); Muted(list.empty)
    function list:Set(items, emptyText)
        content:SetWidth(math.max(1, scroll:GetWidth()))
        for i, d in ipairs(items) do
            local row = self.rows[i] or W.NewRow(self)
            self.rows[i] = row
            W.LayoutRow(row, d, i)
        end
        for i = #items + 1, #self.rows do self.rows[i]:Hide(); self.rows[i].data = nil end
        content:SetHeight(math.max(1, #items * (self.rowHeight + ROW_GAP)))
        self.empty:SetText(emptyText or "")
        self.empty:SetShown(#items == 0)
    end
    function list:ScrollToTop() scroll:SetVerticalScroll(0) end
    return list
end
