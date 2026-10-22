local _, ns = ...

--[[ Flat context menus with submenus, checkboxes, radios, sliders, color swatches and inputs.

    local m = SimplePanel.Menu:New()              -- or :New(anchorFrame)
    m:Title("Gold")
    m:Checkbox({ text = "Show session", get = function() return x end, set = function(v) x = v end })
    m:Radio({ text = "Left", group = "zone", value = "left", get = ..., set = ... })
    m:Submenu({ text = "More", build = function(sub) sub:Button({ text = "Hi", fn = print }) end })
    m:Slider({ text = "Size", min = 10, max = 40, step = 1, get = ..., set = ..., format = "%d px" })
    m:Color({ text = "Color", get = function() return r, g, b end, set = function(r, g, b) end })
    m:Input({ text = "Name", get = ..., set = ... })
    m:Divider(); m:Header("Section"); m:Button({ text, icon, fn, disabled, tooltip, shortcut, keepOpen })
    m:Slots({ size = 30, slots = { { icon, text, color, fn = function(button) end, tooltip = function(GameTooltip) end,
        disabled, keepOpen, border = { r, g, b }, onEnter, onLeave }, ... } }) -- a row of item-slot buttons (left or right click)
    m:Show()                                    -- at the anchor, or at the cursor

    Any `text` may be a function returning the text. `tooltip` is a string or function(tt).
    Any row may show a color chip at its right with `swatch = { r, g, b }` (or a function returning one).
]]
local Menu = {}
ns.Menu = Menu
SimplePanel.Menu = Menu

local W, T = ns.Widgets, ns.Theme
local WHITE = T.white
local ROW_H, MIN_W, PAD = 20, 160, 4
local HEIGHTS = { title = 22, header = 18, divider = 7, slider = 36, input = 26 }

local Builder = {}
Builder.__index = Builder

function Menu:New(anchor)
    return setmetatable({ items = {}, anchor = anchor }, Builder)
end

local function Add(self, kind, o)
    o = o or {}
    o.kind = kind
    self.items[#self.items + 1] = o
    return self
end
function Builder:Title(text, icon) return Add(self, "title", { text = text, icon = icon }) end
function Builder:Header(text) return Add(self, "header", { text = text }) end
function Builder:Divider() return Add(self, "divider") end
function Builder:Button(o) return Add(self, "button", o) end
function Builder:Checkbox(o) return Add(self, "checkbox", o) end
function Builder:Radio(o) return Add(self, "radio", o) end
function Builder:Submenu(o) return Add(self, "submenu", o) end
function Builder:Slider(o) return Add(self, "slider", o) end
function Builder:Color(o) return Add(self, "color", o) end
function Builder:Input(o) return Add(self, "input", o) end
function Builder:Slots(o) return Add(self, "slots", o) end
function Builder:Count() return #self.items end
-- Drops a trailing divider (handy when sections are optional).
function Builder:Trim()
    while self.items[#self.items] and self.items[#self.items].kind == "divider" do self.items[#self.items] = nil end
    return self
end
function Builder:Show(anchor) Menu:Open(self, anchor or self.anchor) end

-- ---------------------------------------------------------------------------
-- Frames
-- ---------------------------------------------------------------------------

local levels = {}

local function Resolve(v, ...)
    if type(v) == "function" then return v(...) end
    return v
end

local function SafeCall(fn, ...)
    if not fn then return end
    local ok, err = pcall(fn, ...)
    if not ok then ns:Print("|cffd9736bmenu error:|r " .. tostring(err), true) end
    return err
end

local CloseFrom

local function GetLevel(n)
    if levels[n] then return levels[n] end
    local f = CreateFrame("Frame", "SimplePanelMenu" .. n, UIParent, "BackdropTemplate")
    W.SetBackdrop(f, 0.98)
    f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetFrameLevel(10 + n * 10)
    f:SetClampedToScreen(true); f:EnableMouse(true); f:Hide()
    f:SetClipsChildren(true)
    f.level = n
    f.content = CreateFrame("Frame", nil, f)
    f.content:SetPoint("TOPLEFT", 0, 0)
    f.rows = {}
    f.offset = 0
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(self, delta)
        if not self.scrollMax or self.scrollMax <= 0 then return end
        self.offset = math.max(0, math.min(self.scrollMax, self.offset - delta * ROW_H * 2))
        self.content:SetPoint("TOPLEFT", 0, self.offset)
    end)
    f:SetScript("OnHide", function(self)
        CloseFrom(self.level + 1)
        if self.level == 1 then ns.Tooltip:Hide() end
    end)
    -- Escape closes menus like any other window.
    tinsert(UISpecialFrames, f:GetName())
    if n == 1 then
        f:SetScript("OnUpdate", function(self)
            if not (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) then return end
            for _, lv in ipairs(levels) do
                if lv:IsShown() and lv:IsMouseOver() then return end
            end
            if self.anchor and self.anchor.IsMouseOver and self.anchor:IsMouseOver() then return end
            -- color picker opened from a menu keeps it open
            if ColorPickerFrame and ColorPickerFrame:IsShown() then return end
            self:Hide()
        end)
    end
    levels[n] = f
    return f
end

function CloseFrom(n)
    for i = n, #levels do
        if levels[i]:IsShown() then levels[i]:Hide() end
    end
end

function Menu:Close() CloseFrom(1) end
function Menu:IsOpen() return levels[1] and levels[1]:IsShown() end

-- ---------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------

local function NewRow(f)
    local r = CreateFrame("Button", nil, f.content)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.hl = r:CreateTexture(nil, "BACKGROUND"); r.hl:SetAllPoints(); r.hl:SetColorTexture(T.buttonHover[1], T.buttonHover[2], T.buttonHover[3], 1); r.hl:Hide()
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(14, 14); r.icon:SetPoint("LEFT", 8, 0)
    -- check / radio box
    r.box = r:CreateTexture(nil, "ARTWORK"); r.box:SetSize(10, 10); r.box:SetPoint("LEFT", 10, 0); r.box:SetTexture(WHITE)
    r.boxIn = r:CreateTexture(nil, "OVERLAY"); r.boxIn:SetPoint("CENTER", r.box); r.boxIn:SetTexture(WHITE)
    r.boxBg = r:CreateTexture(nil, "OVERLAY", nil, -1); r.boxBg:SetPoint("TOPLEFT", r.box, 1, -1); r.boxBg:SetPoint("BOTTOMRIGHT", r.box, -1, 1)
    r.boxBg:SetColorTexture(T.well[1], T.well[2], T.well[3], 1)
    r.text = r:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall"); r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
    r.right = r:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall"); r.right:SetJustifyH("RIGHT")
    r.right:SetPoint("RIGHT", -10, 0)
    r.arrow = r:CreateTexture(nil, "ARTWORK"); r.arrow:SetSize(10, 10); r.arrow:SetPoint("RIGHT", -6, 0)
    r.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    r.swatch = r:CreateTexture(nil, "ARTWORK"); r.swatch:SetSize(16, 10); r.swatch:SetPoint("RIGHT", -10, 0); r.swatch:SetTexture(WHITE)
    r.swatchBorder = r:CreateTexture(nil, "BORDER"); r.swatchBorder:SetPoint("TOPLEFT", r.swatch, -1, 1); r.swatchBorder:SetPoint("BOTTOMRIGHT", r.swatch, 1, -1)
    r.swatchBorder:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)
    r.rule = r:CreateTexture(nil, "ARTWORK"); r.rule:SetHeight(1)
    r.rule:SetPoint("LEFT", 6, 0); r.rule:SetPoint("RIGHT", -6, 0)
    return r
end

local function HideParts(r)
    for _, k in ipairs({ "icon", "box", "boxIn", "boxBg", "right", "arrow", "swatch", "swatchBorder", "rule" }) do r[k]:Hide() end
    if r.slider then r.slider:Hide() end
    if r.edit then r.edit:Hide() end
    for _, b in ipairs(r.slotButtons or {}) do b:Hide() end
    r.hl:Hide()
    r.text:SetTextColor(1, 1, 1); r.text:SetAlpha(1)
    r.text:SetFontObject("SimplePanelFontSmall")
end

local function ShowItemTooltip(row, item)
    if not item.tooltip then return end
    local tt = ns.Tooltip:Begin(row)
    if type(item.tooltip) == "function" then SafeCall(item.tooltip, tt)
    else tt:SetTitle(Resolve(item.text) or ""); tt:AddLine(item.tooltip, T.text, true) end
    tt:Show()
    tt:ClearAllPoints()
    tt:SetPoint("TOPLEFT", row:GetParent():GetParent(), "TOPRIGHT", 4, 0)
end

local Render

local function OpenSubmenu(level, row, item)
    local sub = Menu:New()
    SafeCall(item.build, sub)
    local f = GetLevel(level + 1)
    Render(f, sub)
    f:ClearAllPoints()
    local right = row:GetRight() or 0
    if right + f:GetWidth() + 4 > UIParent:GetRight() then
        f:SetPoint("TOPRIGHT", row, "TOPLEFT", -PAD - 2, PAD)
    else
        f:SetPoint("TOPLEFT", row, "TOPRIGHT", PAD + 2, PAD)
    end
    f.parentRow = row
    f:Show()
end

local function OnRowEnter(row)
    local item, f = row.item, row.frame
    if not item then return end
    if item.kind == "button" or item.kind == "checkbox" or item.kind == "radio" or item.kind == "submenu" or item.kind == "color" then
        if not row.disabled then row.hl:Show() end
    end
    if item.kind == "submenu" and not row.disabled then
        local child = levels[f.level + 1]
        if not (child and child:IsShown() and child.parentRow == row) then
            CloseFrom(f.level + 1)
            OpenSubmenu(f.level, row, item)
        end
    else
        CloseFrom(f.level + 1)
    end
    ShowItemTooltip(row, item)
end

local function OnRowLeave(row)
    row.hl:Hide()
    ns.Tooltip:Hide()
end

local function OpenColorPicker(item)
    local r, g, b = 1, 1, 1
    if item.get then r, g, b = item.get() end
    local function Apply()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        SafeCall(item.set, nr, ng, nb)
    end
    local function Cancel(prev)
        if type(prev) == "table" then
            SafeCall(item.set, prev.r or prev[1], prev.g or prev[2], prev.b or prev[3])
        else
            SafeCall(item.set, r, g, b)
        end
    end
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({ r = r, g = g, b = b, hasOpacity = false,
            swatchFunc = Apply, cancelFunc = Cancel })
    else
        ColorPickerFrame.func, ColorPickerFrame.cancelFunc = Apply, Cancel
        ColorPickerFrame.hasOpacity, ColorPickerFrame.previousValues = false, { r, g, b }
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame:Hide(); ColorPickerFrame:Show()
    end
end

local function OnRowClick(row, button)
    local item, f = row.item, row.frame
    if not item or row.disabled then return end
    if item.kind == "button" then
        if not item.keepOpen then Menu:Close() end
        SafeCall(item.fn, button)
        if item.keepOpen then Render(f, f.builder) end
    elseif item.kind == "checkbox" then
        SafeCall(item.set, not Resolve(item.get))
        Render(f, f.builder)
        if f.level > 1 and levels[f.level - 1] then Render(levels[f.level - 1], levels[f.level - 1].builder, true) end
    elseif item.kind == "radio" then
        SafeCall(item.set, item.value)
        if item.close then Menu:Close() else Render(f, f.builder) end
    elseif item.kind == "color" then
        OpenColorPicker(item)
    elseif item.kind == "submenu" and item.fn then
        Menu:Close(); SafeCall(item.fn, button)
    end
end

-- A slider's value text: `format` is a format string or a function of the value.
local function FormatValue(item, v)
    if type(item.format) == "function" then return item.format(v) end
    return (item.format or "%s"):format(v)
end

local function SetupSlider(row, item, width)
    if not row.slider then
        row.slider = W.MakeSlider(row, 100, 0, 1, 1, function(v)
            local it = row.item
            if not it or it.kind ~= "slider" then return end
            SafeCall(it.set, v)
            row.right:SetText(FormatValue(it, v))
        end)
    end
    local s = row.slider
    s:SetMinMaxValues(item.min or 0, item.max or 100); s:SetValueStep(item.step or 1)
    s:ClearAllPoints(); s:SetPoint("BOTTOMLEFT", 10, 6); s:SetWidth(width - 20)
    local v = Resolve(item.get) or item.min or 0
    s:SetSilently(v)
    s:Show()
    row.text:ClearAllPoints(); row.text:SetPoint("TOPLEFT", 10, -4)
    row.right:ClearAllPoints(); row.right:SetPoint("TOPRIGHT", -10, -4)
    row.right:SetText(FormatValue(item, v)); row.right:SetTextColor(T.accent[1], T.accent[2], T.accent[3]); row.right:Show()
end

local function SetupInput(row, item, width, labelW)
    if not row.edit then
        row.edit = W.MakeEditBox(row, 100, "")
        row.edit:SetHeight(20)
        row.edit:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
            local it = row.item
            if it and it.set then SafeCall(it.set, self:GetText()) end
            if it and it.closeOnEnter ~= false then Menu:Close() end
        end)
    end
    local e = row.edit
    e:ClearAllPoints(); e:SetPoint("RIGHT", -6, 0); e:SetWidth(math.max(60, width - labelW - 24))
    e.placeholder:SetText(item.placeholder or "")
    e:SetText(tostring(Resolve(item.get) or ""))
    e:Show()
end

-- Slot buttons: the item's tooltip in GameTooltip, either click runs fn(button).
local function SlotBorder(b, hover)
    local c = hover and T.accent or Resolve(b.slot and b.slot.border) or T.border
    b:SetBackdropBorderColor(c[1], c[2], c[3], 1)
end

local function SlotEnter(b)
    local s = b.slot
    SlotBorder(b, true)
    if s and s.onEnter then SafeCall(s.onEnter) end
    if not (s and s.tooltip) then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    SafeCall(s.tooltip, GameTooltip)
    GameTooltip:Show()
end

local function SlotLeave(b)
    SlotBorder(b, false)
    if b.slot and b.slot.onLeave then SafeCall(b.slot.onLeave) end
    if GameTooltip:IsOwned(b) then GameTooltip:Hide() end
end

local function SlotClick(b, button)
    local s = b.slot
    if not s or Resolve(s.disabled) then return end
    SlotLeave(b)
    if not s.keepOpen then Menu:Close() end
    SafeCall(s.fn, button)
end

local function SetupSlots(row, item)
    row.slotButtons = row.slotButtons or {}
    local size = item.size or 30
    for i, s in ipairs(item.slots) do
        local b = row.slotButtons[i]
        if not b then
            b = CreateFrame("Button", nil, row, "BackdropTemplate")
            W.SetBackdrop(b)
            b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetPoint("TOPLEFT", 2, -2); b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
            b.hl = b:CreateTexture(nil, "HIGHLIGHT"); b.hl:SetAllPoints(b.icon); b.hl:SetColorTexture(1, 1, 1, 0.15)
            b.count = b:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall"); b.count:SetPoint("BOTTOMRIGHT", -2, 2)
            b:SetScript("OnEnter", SlotEnter); b:SetScript("OnLeave", SlotLeave); b:SetScript("OnClick", SlotClick)
            row.slotButtons[i] = b
        end
        b.slot = s
        -- Wally's item wells: a dark field, a 1px edge (or the slot's own colour), the accent on hover.
        b:SetBackdropColor(T.well[1], T.well[2], T.well[3], 1)
        SlotBorder(b, false)
        b:SetSize(size, size)
        b:ClearAllPoints(); b:SetPoint("LEFT", 6 + (i - 1) * (size + 4), 0)
        W.SetIcon(b.icon, Resolve(s.icon))
        b.icon:SetDesaturated(Resolve(s.disabled) and true or false)
        b.count:SetText(Resolve(s.text) or "")
        local c = Resolve(s.color) or T.text
        b.count:SetTextColor(c[1], c[2], c[3])
        b:Show()
    end
end

-- ---------------------------------------------------------------------------
-- Render a builder into a level frame
-- ---------------------------------------------------------------------------

function Render(f, builder, keepPosition)
    f.builder = builder
    local items = builder.items
    -- Measure.
    local indent = 0
    local width = builder.minWidth or MIN_W
    local measure = f.measure or f:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall")
    f.measure = measure; measure:Hide()
    for _, it in ipairs(items) do
        if it.kind == "checkbox" or it.kind == "radio" or it.icon then indent = 18 end
    end
    for _, it in ipairs(items) do
        local text = Resolve(it.text) or ""
        measure:SetFontObject(it.kind == "title" and "SimplePanelFontTitle" or "SimplePanelFontSmall")
        measure:SetText(text)
        local w = measure:GetStringWidth() + 20 + indent
        if it.kind == "submenu" then w = w + 16 end
        if it.shortcut then measure:SetText(it.shortcut); w = w + measure:GetStringWidth() + 14 end
        if it.kind == "color" or it.swatch then w = w + 28 end
        if it.kind == "input" then w = w + 110 end
        if it.kind == "slots" then w = #it.slots * ((it.size or 30) + 4) + 16 end
        width = math.max(width, w)
    end
    width = math.min(width, 360)

    local y = -PAD
    local rowW = width - PAD * 2
    for i, it in ipairs(items) do
        local row = f.rows[i] or NewRow(f)
        f.rows[i] = row
        row.item, row.frame = it, f
        HideParts(row)
        local h = it.kind == "slots" and (it.size or 30) + 8 or HEIGHTS[it.kind] or ROW_H
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", PAD, y); row:SetSize(rowW, h)
        row.disabled = Resolve(it.disabled) and true or false
        local text = Resolve(it.text) or ""
        row.text:ClearAllPoints(); row.text:SetPoint("LEFT", 8 + indent, 0); row.text:SetPoint("RIGHT", -24, 0)
        row.text:SetText(text)
        row:EnableMouse(true)
        row:SetScript("OnEnter", OnRowEnter); row:SetScript("OnLeave", OnRowLeave); row:SetScript("OnClick", OnRowClick)

        if it.kind == "title" then
            row.text:SetFontObject("SimplePanelFontTitle"); row.text:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
            row.text:ClearAllPoints(); row.text:SetPoint("LEFT", it.icon and 26 or 8, 1)
            if it.icon then W.SetIcon(row.icon, it.icon); row.icon:Show() end
            row.rule:ClearAllPoints(); row.rule:SetPoint("BOTTOMLEFT", 6, 0); row.rule:SetPoint("BOTTOMRIGHT", -6, 0)
            row.rule:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.5); row.rule:Show()
            row:EnableMouse(false)
        elseif it.kind == "header" then
            row.text:SetTextColor(T.muted[1], T.muted[2], T.muted[3])
            row.text:ClearAllPoints(); row.text:SetPoint("BOTTOMLEFT", 8, 2)
            row:EnableMouse(false)
        elseif it.kind == "divider" then
            row.text:SetText("")
            row.rule:ClearAllPoints(); row.rule:SetPoint("LEFT", 6, 0); row.rule:SetPoint("RIGHT", -6, 0)
            row.rule:SetColorTexture(T.border[1], T.border[2], T.border[3], 1); row.rule:Show()
            row:EnableMouse(false)
        elseif it.kind == "slots" then
            row:EnableMouse(false) -- the slot buttons take the clicks
            SetupSlots(row, it)
        elseif it.kind == "slider" then
            SetupSlider(row, it, rowW)
        elseif it.kind == "input" then
            measure:SetFontObject("SimplePanelFontSmall"); measure:SetText(text)
            row.text:ClearAllPoints(); row.text:SetPoint("LEFT", 8, 0)
            SetupInput(row, it, rowW, measure:GetStringWidth())
        else
            if it.icon then W.SetIcon(row.icon, Resolve(it.icon)); row.icon:Show() end
            if it.kind == "checkbox" or it.kind == "radio" then
                local on
                if it.kind == "radio" then on = Resolve(it.get) == it.value else on = Resolve(it.get) and true or false end
                row.box:SetVertexColor(on and T.accent[1] or T.border[1], on and T.accent[2] or T.border[2], on and T.accent[3] or T.border[3], 1)
                row.box:Show(); row.boxBg:Show()
                if on then
                    local s = it.kind == "radio" and 4 or 6
                    row.boxIn:SetSize(s, s); row.boxIn:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 1); row.boxIn:Show()
                end
                if it.kind == "radio" then row.box:SetSize(10, 10) end
            end
            if it.kind == "submenu" then row.arrow:Show() end
            if it.kind == "color" then
                local r, g, b = 1, 1, 1
                if it.get then r, g, b = it.get() end
                row.swatch:SetVertexColor(r or 1, g or 1, b or 1, 1); row.swatch:Show(); row.swatchBorder:Show()
            elseif it.swatch then
                local c = Resolve(it.swatch)
                row.swatch:SetVertexColor(c[1], c[2], c[3], 1); row.swatch:Show(); row.swatchBorder:Show()
            end
            if it.shortcut then
                row.right:ClearAllPoints(); row.right:SetPoint("RIGHT", it.kind == "submenu" and -20 or -10, 0)
                row.right:SetText(it.shortcut); row.right:SetTextColor(T.muted[1], T.muted[2], T.muted[3]); row.right:Show()
            end
            if row.disabled then row.text:SetAlpha(0.4) end
            if it.color then row.text:SetTextColor(it.color[1], it.color[2], it.color[3]) end
        end
        row:Show()
        y = y - h
    end
    for i = #items + 1, #f.rows do f.rows[i]:Hide(); f.rows[i].item = nil end

    local contentH = -y + PAD
    local maxH = math.floor(UIParent:GetHeight() * 0.75 / f:GetScale())
    f.content:SetSize(width, contentH)
    f:SetSize(width, math.min(contentH, maxH))
    f.scrollMax = contentH - math.min(contentH, maxH)
    if not keepPosition then f.offset = 0 end
    f.offset = math.min(f.offset or 0, math.max(0, f.scrollMax))
    f.content:SetPoint("TOPLEFT", 0, f.offset)
end

-- ---------------------------------------------------------------------------
-- Open
-- ---------------------------------------------------------------------------

function Menu:Open(builder, anchor)
    -- A second click on the same anchor closes its menu.
    if levels[1] and levels[1]:IsShown() and anchor and anchor ~= "cursor" and levels[1].anchor == anchor then
        return CloseFrom(1)
    end
    CloseFrom(1)
    ns.Tooltip:Hide()
    if GameTooltip:IsShown() then GameTooltip:Hide() end
    local f = GetLevel(1)
    Render(f, builder)
    f.anchor = anchor
    f:ClearAllPoints()
    if anchor and anchor ~= "cursor" and anchor.GetCenter then
        local _, cy = anchor:GetCenter()
        local cx = anchor:GetCenter() or 0
        local h = cx > UIParent:GetWidth() / 2 and "RIGHT" or "LEFT"
        if cy and cy > UIParent:GetHeight() / 2 then
            f:SetPoint("TOP" .. h, anchor, "BOTTOM" .. h, 0, -2)
        else
            f:SetPoint("BOTTOM" .. h, anchor, "TOP" .. h, 0, 2)
        end
    else
        local x, y = GetCursorPosition()
        local scale = f:GetEffectiveScale()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale - 4, y / scale + 4)
    end
    f:Show()
end

-- Opens a builder function as a menu: SimplePanel.Menu:Popup(anchor, function(m) ... end)
function Menu:Popup(anchor, build)
    local m = Menu:New(anchor)
    SafeCall(build, m)
    m:Show(anchor)
    return m
end
