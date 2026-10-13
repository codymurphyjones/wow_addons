local _, ns = ...
local C = ns.Compat

-- Shared widgets for the Wally manager, the settings panel and the auction house tab
-- (same look as GearBot's dashboard).
local W = {}
ns.Widgets = W

local WHITE = "Interface\\Buttons\\WHITE8X8"
local ROW_H, ROW_GAP = 38, 4
local ACCENT = { 0.33, 0.92, 0.78 }
local MUTED = { 0.52, 0.64, 0.70 }
local UNKNOWN_ICON = 134400
W.WHITE, W.ROW_H, W.ROW_GAP, W.ACCENT, W.MUTED, W.UNKNOWN_ICON = WHITE, ROW_H, ROW_GAP, ACCENT, MUTED, UNKNOWN_ICON

function W.SetBackdrop(f, alpha)
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(0.035, 0.045, 0.060, alpha or 1)
    f:SetBackdropBorderColor(0.16, 0.24, 0.29, 1)
end
local SetBackdrop = W.SetBackdrop

function W.Label(parent, text, font, x, y, width)
    local t = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
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
    b:SetBackdropColor(0.075, 0.105, 0.13, 1)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("CENTER"); b.text:SetText(text)
    b:SetScript("OnEnter", function(self) self:SetBackdropColor(0.10, 0.19, 0.21, 1) end)
    b:SetScript("OnLeave", function(self) self:SetBackdropColor(0.075, 0.105, 0.13, 1) end)
    return b
end
local MakeButton = W.MakeButton

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
    local b = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    b:SetSize(26, 26)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("LEFT", b, "RIGHT", 3, 0); b.label:SetText(text)
    return b
end

function W.MakeEditBox(parent, width, placeholder)
    local b = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    b:SetSize(width or 160, 26)
    SetBackdrop(b); b:SetBackdropColor(0.02, 0.03, 0.04, 1)
    b:SetFontObject("GameFontHighlightSmall"); b:SetJustifyH("LEFT")
    b:SetAutoFocus(false); b:SetTextInsets(8, 8, 2, 2)
    b.placeholder = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.placeholder:SetPoint("LEFT", 8, 0); b.placeholder:SetText(placeholder or "")
    local function UpdatePlaceholder(self) self.placeholder:SetShown(self:GetText() == "" and not self:HasFocus()) end
    b:SetScript("OnEditFocusGained", UpdatePlaceholder)
    b:SetScript("OnEditFocusLost", UpdatePlaceholder)
    b:HookScript("OnTextChanged", UpdatePlaceholder)
    b:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    b:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return b
end

function W.QualityName(name, quality)
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color and color.hex then return color.hex .. name .. "|r" end
    return name
end

function W.EntryText(e, key)
    if e.link then return e.link end
    return W.QualityName(e.name or key, e.quality)
end

function W.IconFor(e)
    if e.icon then return e.icon end
    if e.id then return select(5, C.GetItemInfoInstant(e.id)) or UNKNOWN_ICON end
    if e.link then return select(5, C.GetItemInfoInstant(e.link)) or UNKNOWN_ICON end
    return UNKNOWN_ICON
end

function W.When(t) return t and date("%m/%d %H:%M", t) or "" end

StaticPopupDialogs["WALLY_CONFIRM"] = {
    text = "%s", button1 = YES or "Yes", button2 = NO or "No",
    OnAccept = function(_, data) if data and data.fn then data.fn() end end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, showAlert = 1, preferredIndex = 3,
}
function W.Confirm(text, fn) StaticPopup_Show("WALLY_CONFIRM", text, nil, { fn = fn }) end

-- Adds whatever item is on the cursor. Used by every drop target. Returns the list key, or true
-- while the item's data is still loading.
function W.AddCursorItem(kind)
    local cursorType, id, link = GetCursorInfo()
    if cursorType ~= "item" then return false end
    ClearCursor()
    return ns.Lists:Add(kind, link or id, "manual") or true
end

-- ---------------------------------------------------------------------------
-- Scrolling row list
-- ---------------------------------------------------------------------------
-- item = { icon, text, detail, detailColor, link, bar, marker, barText, actions = {{label, fn, hint}},
--          onRightClick, hint, selected,
--          status = { texture, desaturate, onClick, hint },  -- small button left of the icon
--          dim }                                             -- 0..1 alpha for rows not yet acted on

function W.NewRow(list)
    local height = list.rowHeight or ROW_H
    local row = CreateFrame("Button", nil, list.content, "BackdropTemplate")
    row.height = height
    row:SetHeight(height); SetBackdrop(row); row:SetBackdropColor(0.055, 0.08, 0.10, 1)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(height - 10, height - 10)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetJustifyH("LEFT"); row.text:SetWordWrap(false)
    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.detail:SetJustifyH("LEFT"); row.detail:SetWordWrap(false)
    row.barBg = row:CreateTexture(nil, "ARTWORK"); row.barBg:SetColorTexture(0.12, 0.16, 0.19, 1); row.barBg:SetSize(110, 6)
    row.barFill = row:CreateTexture(nil, "OVERLAY"); row.barFill:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    row.barFill:SetPoint("LEFT", row.barBg, "LEFT"); row.barFill:SetHeight(6)
    row.marker = row:CreateTexture(nil, "OVERLAY", nil, 2); row.marker:SetColorTexture(1, 0.82, 0.3, 1); row.marker:SetSize(2, 12)
    row.barText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); row.barText:SetJustifyH("RIGHT")
    row.barText:SetPoint("BOTTOMRIGHT", row.barBg, "TOPRIGHT", 0, 2)
    row.actions = {}
    row:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.08, 0.14, 0.16, 1)
        local d = self.data
        if not d then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if d.link then GameTooltip:SetHyperlink(d.link) else GameTooltip:AddLine(d.plainText or "", 1, 1, 1) end
        if d.hint then GameTooltip:AddLine(" "); GameTooltip:AddLine(d.hint, MUTED[1], MUTED[2], MUTED[3], true) end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self) self:SetBackdropColor(0.055, 0.08, 0.10, 1); GameTooltip:Hide() end)
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

function W.LayoutRow(row, d, index)
    row.data = d
    row:ClearAllPoints()
    local height = row.height or ROW_H
    local compact = height < 34
    local y = -(index - 1) * (height + ROW_GAP)
    row:SetPoint("TOPLEFT", 0, y); row:SetPoint("TOPRIGHT", 0, y)
    if d.selected then row:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    else row:SetBackdropBorderColor(0.16, 0.24, 0.29, 1) end

    -- Optional status button pushes the icon and text right.
    local left = 5
    if d.status then
        local s = row.status or StatusButton(row)
        s.tex:SetTexture(d.status.texture)
        s.tex:SetDesaturated(d.status.desaturate and true or false)
        s.tex:SetVertexColor(d.status.desaturate and 0.6 or 1, d.status.desaturate and 0.6 or 1, d.status.desaturate and 0.6 or 1)
        s.fn, s.hint = d.status.onClick, d.status.hint
        s:EnableMouse(d.status.onClick ~= nil or d.status.hint ~= nil)
        s:Show()
        left = 27
    elseif row.status then
        row.status:Hide()
    end
    row.icon:ClearAllPoints(); row.icon:SetPoint("LEFT", left, 0)
    local textX = left + height - 3
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

    -- Action buttons, right to left.
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
        local width = math.max(54, (#a[1]) * 6 + 18)
        b:SetWidth(width); b.text:SetText(a[1]); b.fn, b.hint = a[2], a[3]
        b:ClearAllPoints(); b:SetPoint("RIGHT", right, 0); b:Show()
        right = right - width - 4
    end
    for i = #(d.actions or {}) + 1, #row.actions do row.actions[i]:Hide() end

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

-- opts.rowHeight: row height in pixels (default 38).
function W.CreateRowList(parent, top, opts)
    local list = { rows = {}, rowHeight = opts and opts.rowHeight or ROW_H }
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, top); scroll:SetPoint("BOTTOMRIGHT", -26, 0)
    local content = CreateFrame("Frame", nil, scroll); content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, w) content:SetWidth(w) end)
    list.scroll, list.content = scroll, content
    list.empty = Label(parent, "", "GameFontHighlight", 0, top - 60)
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
    return list
end
