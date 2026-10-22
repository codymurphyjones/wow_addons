local _, ns = ...

-- BattleRecap's own widgets: bars and the scrolling table. The basics (buttons, labels, checkboxes,
-- ...) are the shared kit (addons/shared/Widgets.lua, loaded first); the recap windows' title-bar
-- frame is W.MakeWindow(name, width, height, title, pos) from shared/Window.lua.
local W = ns.Widgets

-- BattleRecap's look on the shared basics: disabled buttons dim their text, and checkboxes are
-- a little smaller.
W.style.dimDisabled = true
W.style.checkSize, W.style.checkGap = 24, 2

local ACCENT = W.ACCENT
local Label = W.Label

W.MakeBar = ns.NewProgressBar -- shared\Bar.lua: (parent, width, height), bar:SetValue(v, r, g, b)

-- Health % colour: green at full, yellow at half, red near death.
function W.HealthColor(pct)
    pct = math.max(0, math.min(1, pct or 0))
    if pct > 0.5 then return (1 - pct) * 2, 1, 0.1 end
    return 1, pct * 2, 0.1
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
