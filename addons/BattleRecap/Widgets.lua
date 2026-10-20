local _, ns = ...
local PAL = ns.Palette

-- Shared widgets for the recap windows. Same look as Wally and Tape Measure (the basics are copied
-- from TapeMeasure/Widgets.lua so the addons match).
local W = {}
ns.Widgets = W

local WHITE = "Interface\\Buttons\\WHITE8X8"
local ACCENT = PAL.accent
local MUTED = PAL.muted
W.WHITE, W.ACCENT, W.MUTED = WHITE, ACCENT, MUTED

function W.SetBackdrop(f, alpha)
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(PAL.bg[1], PAL.bg[2], PAL.bg[3], alpha or 1)
    f:SetBackdropBorderColor(PAL.border[1], PAL.border[2], PAL.border[3], 1)
end
local SetBackdrop = W.SetBackdrop

function W.Label(parent, text, font, x, y, width)
    local t = parent:CreateFontString(nil, "OVERLAY", font or "BattleRecapGameFontHighlight")
    t:SetPoint("TOPLEFT", x, y)
    t:SetJustifyH("LEFT")
    if width then t:SetWidth(width) end
    t:SetText(text)
    return t
end
local Label = W.Label

function W.Muted(fs) fs:SetTextColor(MUTED[1], MUTED[2], MUTED[3]); return fs end

function W.MakeButton(parent, text, width, height)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width or 110, height or 28)
    SetBackdrop(b)
    b:SetBackdropColor(PAL.button[1], PAL.button[2], PAL.button[3], 1)
    b.text = b:CreateFontString(nil, "OVERLAY", "BattleRecapGameFontHighlightSmall")
    b.text:SetPoint("CENTER"); b.text:SetText(text)
    b:SetScript("OnEnter", function(self) if self:IsEnabled() then self:SetBackdropColor(PAL.hover[1], PAL.hover[2], PAL.hover[3], 1) end end)
    b:SetScript("OnLeave", function(self) self:SetBackdropColor(PAL.button[1], PAL.button[2], PAL.button[3], 1) end)
    b:SetScript("OnDisable", function(self) self.text:SetAlpha(0.35) end)
    b:SetScript("OnEnable", function(self) self.text:SetAlpha(1) end)
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
    b:SetSize(24, 24)
    b.label = b:CreateFontString(nil, "OVERLAY", "BattleRecapGameFontHighlightSmall")
    b.label:SetPoint("LEFT", b, "RIGHT", 2, 0); b.label:SetText(text)
    return b
end

-- A flat bar: bg + fill, value 0..1.
function W.MakeBar(parent, width, height)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(width, height)
    bar.bg = bar:CreateTexture(nil, "ARTWORK"); bar.bg:SetAllPoints(); bar.bg:SetColorTexture(0.12, 0.16, 0.19, 1)
    bar.fill = bar:CreateTexture(nil, "OVERLAY"); bar.fill:SetPoint("TOPLEFT"); bar.fill:SetPoint("BOTTOMLEFT")
    function bar:SetValue(v, r, g, b)
        self.fill:SetWidth(math.max(0.5, self:GetWidth() * math.max(0, math.min(1, v or 0))))
        self.fill:SetColorTexture(r or ACCENT[1], g or ACCENT[2], b or ACCENT[3], 1)
    end
    return bar
end

-- Health % colour: green at full, yellow at half, red near death.
function W.HealthColor(pct)
    pct = math.max(0, math.min(1, pct or 0))
    if pct > 0.5 then return (1 - pct) * 2, 1, 0.1 end
    return 1, pct * 2, 0.1
end

---------------------------------------------------------------------------
-- Windows
---------------------------------------------------------------------------

-- A movable dark window with a title, an icon and a close button. pos is the saved-position table.
function W.MakeWindow(name, width, height, title, pos)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(width, height)
    SetBackdrop(f, 0.96)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        pos.point, pos.x, pos.y = point, x, y
    end)
    function f:RestorePosition()
        self:ClearAllPoints()
        self:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or 0)
    end
    f:RestorePosition()

    local band = f:CreateTexture(nil, "BORDER")
    band:SetPoint("TOPLEFT", 1, -1); band:SetPoint("TOPRIGHT", -1, -1); band:SetHeight(26)
    band:SetColorTexture(0.06, 0.08, 0.10, 1)
    local accent = f:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", band, "BOTTOMLEFT"); accent:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT"); accent:SetHeight(1)
    accent:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.6)

    local icon = f:CreateTexture(nil, "OVERLAY")
    icon:SetSize(18, 18); icon:SetPoint("TOPLEFT", 6, -5); icon:SetTexture(ns.ICON)
    f.title = Label(f, title, "BattleRecapGameFontNormal", 28, -7)
    f.subtitle = Label(f, "", "BattleRecapGameFontHighlightSmall", 0, -8)
    f.subtitle:ClearAllPoints(); f.subtitle:SetPoint("LEFT", f.title, "RIGHT", 8, 0)
    W.Muted(f.subtitle)
    if WallyHUD and WallyHUD.Tokens then
        -- the suite's look (WallyHUD): the header in the panel colour, the title in primary text
        band:SetColorTexture(PAL.panel[1], PAL.panel[2], PAL.panel[3], 1)
        f.title:SetTextColor(WallyHUD.RGBA(WallyHUD.Tokens.text.primary))
    end

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(24, 24); close:SetPoint("TOPRIGHT", -1, -1)
    close:SetScript("OnClick", function() f:Hide() end)
    f.close = close

    tinsert(UISpecialFrames, name) -- Escape closes it
    f:Hide()
    return f
end

---------------------------------------------------------------------------
-- Scrolling table
---------------------------------------------------------------------------
-- columns = { { title, width, justify }, ... }
-- row = { cells = { ... }, icon, iconCol = n (default 1), colors = { [col] = {r,g,b} }, indent (first column),
--         header, section, bg = {r,g,b,a}, bar = 0..1, barColor = {r,g,b}, barCol = n, onClick, onEnter }

local ROW_H = 20

function W.CreateTable(parent, columns, opts)
    opts = opts or {}
    local t = { rows = {}, columns = columns, rowHeight = opts.rowHeight or ROW_H }
    local headerH = opts.noHeader and 0 or 18

    local header = CreateFrame("Frame", nil, parent)
    header:SetPoint("TOPLEFT"); header:SetPoint("TOPRIGHT", -26, 0); header:SetHeight(math.max(1, headerH))
    t.header, t.headerCells = header, {}
    local x = 4
    for i, col in ipairs(columns) do
        local b = CreateFrame("Button", nil, header)
        b:SetPoint("TOPLEFT", x, 0); b:SetSize(col[2], 18)
        b.text = b:CreateFontString(nil, "OVERLAY", "BattleRecapGameFontNormalSmall")
        b.text:SetAllPoints(); b.text:SetJustifyH(col[3] or "LEFT"); b.text:SetText(col[1])
        b:SetScript("OnClick", function() if t.onSort then t.onSort(i) end end)
        b:SetShown(not opts.noHeader)
        t.headerCells[i] = b
        x = x + col[2] + 6
    end

    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -headerH); scroll:SetPoint("BOTTOMRIGHT", -26, 0)
    local content = CreateFrame("Frame", nil, scroll); content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, w) content:SetWidth(w) end)
    t.scroll, t.content = scroll, content

    local function NewRow()
        local r = CreateFrame("Button", nil, content)
        r:SetHeight(t.rowHeight)
        r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
        r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 1, 1, 0.06)
        r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(t.rowHeight - 4, t.rowHeight - 4)
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        r.barBg = r:CreateTexture(nil, "ARTWORK"); r.barBg:SetColorTexture(0.12, 0.16, 0.19, 1)
        r.barFill = r:CreateTexture(nil, "ARTWORK", nil, 1)
        r.cells = {}
        for i = 1, #columns do
            local fs = r:CreateFontString(nil, "OVERLAY", "BattleRecapGameFontHighlightSmall")
            fs:SetWordWrap(false)
            r.cells[i] = fs
        end
        r:SetScript("OnClick", function(self) if self.data and self.data.onClick then self.data.onClick() end end)
        r:SetScript("OnEnter", function(self) if self.data and self.data.onEnter then self.data.onEnter(self) end end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return r
    end

    local function Layout(r, d, index)
        r.data = d
        r:ClearAllPoints()
        local y = -(index - 1) * t.rowHeight
        r:SetPoint("TOPLEFT", 0, y); r:SetPoint("TOPRIGHT", 0, y)
        local bg = d.bg or ((d.header or d.section) and { 0.08, 0.11, 0.14, 1 })
            or (index % 2 == 0 and { 1, 1, 1, 0.025 }) or { 0, 0, 0, 0 }
        r.bg:SetColorTexture(bg[1], bg[2], bg[3], bg[4] or 1)

        local iconCol = d.iconCol or 1
        r.icon:SetShown(d.icon ~= nil)
        local barCol = d.bar and (d.barCol or 1)
        r.barBg:Hide(); r.barFill:Hide()
        local cx = 4
        for i, col in ipairs(columns) do
            local fs = r.cells[i]
            local text = d.cells and d.cells[i]
            fs:ClearAllPoints()
            local left = cx + (i == 1 and (d.indent or 0) or 0)
            if d.icon and i == iconCol then
                r.icon:ClearAllPoints(); r.icon:SetPoint("LEFT", left, 0); r.icon:SetTexture(d.icon)
                left = left + t.rowHeight
            end
            local width = col[2] - (left - cx)
            fs:SetPoint("LEFT", r, "LEFT", left, 0)
            if d.section and i == 1 then
                fs:SetPoint("RIGHT", r, "RIGHT", -4, 0) -- a section title spans the row
            else
                fs:SetWidth(math.max(1, width))
            end
            fs:SetJustifyH(d.section and "LEFT" or col[3] or "LEFT")
            fs:SetFontObject((d.header or d.section) and "BattleRecapGameFontNormalSmall" or "BattleRecapGameFontHighlightSmall")
            fs:SetText(text or "")
            local c = d.colors and d.colors[i]
            if c then fs:SetTextColor(c[1], c[2], c[3])
            elseif d.header or d.section then fs:SetTextColor(1, 0.82, 0)
            else fs:SetTextColor(0.92, 0.92, 0.92) end
            fs:SetShown(not d.section or i == 1)
            if barCol == i then
                -- A thin bar along the bottom of the cell, under its text.
                r.barBg:ClearAllPoints(); r.barBg:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", cx, 2)
                r.barBg:SetSize(col[2], 3); r.barBg:Show()
                r.barFill:ClearAllPoints(); r.barFill:SetPoint("LEFT", r.barBg, "LEFT")
                r.barFill:SetSize(math.max(0.5, col[2] * math.max(0, math.min(1, d.bar))), 3)
                local bc = d.barColor or ACCENT
                r.barFill:SetColorTexture(bc[1], bc[2], bc[3], 0.9); r.barFill:Show()
            end
            cx = cx + col[2] + 6
        end
        r:Show()
    end

    function t:Set(items, emptyText)
        content:SetWidth(math.max(1, scroll:GetWidth()))
        for i, d in ipairs(items) do
            local r = self.rows[i] or NewRow()
            self.rows[i] = r
            Layout(r, d, i)
        end
        for i = #items + 1, #self.rows do self.rows[i]:Hide(); self.rows[i].data = nil end
        content:SetHeight(math.max(1, #items * self.rowHeight))
        if not self.empty then
            self.empty = Label(parent, "", "BattleRecapGameFontHighlight", 0, -60)
            self.empty:SetPoint("RIGHT", -26, 0); self.empty:SetJustifyH("CENTER"); W.Muted(self.empty)
        end
        self.empty:SetText(emptyText or "")
        self.empty:SetShown(#items == 0)
    end

    function t:SetHeaders(titles)
        for i, b in ipairs(self.headerCells) do b.text:SetText(titles[i] or "") end
    end

    function t:ScrollToEnd()
        C_Timer.After(0, function() scroll:SetVerticalScroll(scroll:GetVerticalScrollRange()) end)
    end

    function t:ScrollToTop() scroll:SetVerticalScroll(0) end

    return t
end
