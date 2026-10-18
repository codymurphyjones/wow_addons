local _, ns = ...
local C = ns.Compat

-- Shared widgets for the Wealth Planner window (copied from Quartermaster's Widgets.lua)
local W = {}
ns.Widgets = W

local WHITE = "Interface\\Buttons\\WHITE8X8"
local ROW_H, ROW_GAP = 38, 4
local ACCENT = { 0.33, 0.92, 0.78 }
local MUTED = { 0.52, 0.64, 0.70 }
local UNKNOWN_ICON = 134400
W.WHITE, W.ROW_H, W.ROW_GAP, W.ACCENT, W.MUTED, W.UNKNOWN_ICON = WHITE, ROW_H, ROW_GAP, ACCENT, MUTED, UNKNOWN_ICON

-- Colours Chart.lua draws with (SimplePanel's default theme).
local YELLOW, RED, GREEN, BLUE, ORANGE = { 1, 0.82, 0.30 }, { 0.85, 0.45, 0.42 }, { 0.35, 0.95, 0.55 }, { 0.40, 0.80, 1 }, { 1, 0.60, 0.20 }
W.Theme = {
    white = WHITE, accent = ACCENT, muted = MUTED, border = { 0.16, 0.24, 0.29 }, track = { 0.12, 0.16, 0.19 },
    text = { 0.85, 0.9, 0.95 }, yellow = YELLOW, red = RED, green = GREEN, blue = BLUE, orange = ORANGE,
    series = { ACCENT, YELLOW, BLUE, ORANGE, GREEN, RED, { 0.75, 0.55, 1 }, { 0.9, 0.9, 0.9 } },
}

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

-- Marks one button of a group as active (accent border), like Wally's sub-view buttons.
function W.SetActive(b, active)
    if active then b:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    else b:SetBackdropBorderColor(0.16, 0.24, 0.29, 1) end
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
local MakeEditBox = W.MakeEditBox

-- Edit boxes that take a shift-clicked item link as an exact name search (see UI.lua).
W.linkBoxes = {}
function W.RegisterLinkBox(box, onInsert) W.linkBoxes[box] = onInsert or false end

-- Puts an item's name in a search box as an exact search, without the quotes. The box remembers it
-- (box.exactName) until the text is edited; filter bars read that as exact.
function W.SetExactName(box, name)
    box:SetText(name)
    box.exactName = name:lower()
end

-- Number box; GetNumber-style reads return nil when empty.
function W.MakeNumberBox(parent, width, placeholder)
    local b = MakeEditBox(parent, width or 44, placeholder)
    b:SetJustifyH("CENTER"); b:SetTextInsets(4, 4, 2, 2)
    b.placeholder:ClearAllPoints(); b.placeholder:SetPoint("CENTER")
    function b:GetValue() return tonumber(self:GetText()) end
    function b:SetValue(v) self:SetText(v and tostring(v) or "") end
    return b
end

-- Two number boxes with a dash between: "[min] - [max]".
function W.MakeRangeBox(parent, label, width)
    local f = CreateFrame("Frame", nil, parent)
    width = width or 40
    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.label:SetPoint("LEFT"); f.label:SetText(label or ""); Muted(f.label)
    local labelW = label and (f.label:GetStringWidth() + 6) or 0
    f.min = W.MakeNumberBox(f, width, "min"); f.min:SetPoint("LEFT", labelW, 0)
    local dash = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dash:SetPoint("LEFT", f.min, "RIGHT", 3, 0); dash:SetText("-")
    f.max = W.MakeNumberBox(f, width, "max"); f.max:SetPoint("LEFT", dash, "RIGHT", 3, 0)
    f:SetSize(labelW + width * 2 + 16, 26)
    function f:Get() return self.min:GetValue(), self.max:GetValue() end
    function f:Clear() self.min:SetText(""); self.max:SetText("") end
    function f:OnChanged(fn) self.min:HookScript("OnTextChanged", fn); self.max:HookScript("OnTextChanged", fn) end
    return f
end

-- Flat-style popup menu shared by dropdowns and right-click menus.
-- opts = { {value, label, checked=bool, disabled=bool, header=bool}, ... }
-- onSelect(value, label, option). With multi = true the menu stays open and shows ticks.
local menu
local function GetMenu()
    if menu then return menu end
    menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    SetBackdrop(menu); menu:SetFrameStrata("FULLSCREEN_DIALOG"); menu:SetClampedToScreen(true)
    menu:Hide()
    menu.items = {}
    menu:SetScript("OnUpdate", function(self)
        if (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
            and not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then self:Hide() end
    end)
    menu:SetScript("OnHide", function(self) self.owner = nil end)
    return menu
end

function W.ShowMenu(owner, opts, onSelect, multi, minWidth)
    local m = GetMenu()
    if m:IsShown() and m.owner == owner and not m.keepOpen then m:Hide() return end
    m.keepOpen = nil
    m:Hide()
    m.owner = owner
    local w = math.max(owner:GetWidth(), minWidth or 140)
    for i, o in ipairs(opts) do
        local item = m.items[i]
        if not item then
            item = MakeButton(m, "", w - 8, 22)
            item.text:ClearAllPoints(); item.text:SetPoint("LEFT", 8, 0); item.text:SetPoint("RIGHT", -6, 0)
            item.text:SetJustifyH("LEFT"); item.text:SetWordWrap(false)
            item:SetBackdropBorderColor(0, 0, 0, 0)
            item:SetScript("OnLeave", function(self) self:SetBackdropColor(0.075, 0.105, 0.13, 1) end)
            m.items[i] = item
        end
        item:SetWidth(w - 8)
        item:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 23)
        local label = o[2]
        if multi and not o.header then label = (o.checked and "|cff55d6be[x]|r " or "|cff8fa3b3[  ]|r ") .. label end
        item.text:SetText(label)
        if o.header then
            item.text:SetTextColor(MUTED[1], MUTED[2], MUTED[3]); item:EnableMouse(false)
            item:SetBackdropColor(0.035, 0.045, 0.060, 1)
        else
            item.text:SetTextColor(1, 1, 1); item:EnableMouse(not o.disabled)
            item:SetBackdropColor(0.075, 0.105, 0.13, 1)
            item.text:SetAlpha(o.disabled and 0.4 or 1)
        end
        item:SetScript("OnClick", function()
            if multi then
                o.checked = not o.checked
                onSelect(o[1], o[2], o)
                m.keepOpen = true
                W.ShowMenu(owner, opts, onSelect, multi, minWidth)
            else
                m:Hide(); onSelect(o[1], o[2], o)
            end
        end)
        item:Show()
    end
    for i = #opts + 1, #m.items do m.items[i]:Hide() end
    m:SetSize(w, math.max(1, #opts) * 23 + 7)
    m:ClearAllPoints()
    if owner.menuAtCursor then
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        m:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    else
        m:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    end
    m:Show()
end

function W.HideMenu() if menu then menu:Hide() end end

-- Right-click menu at the cursor: opts = { {label, fn, disabled = bool, header = bool}, ... }.
local cursorAnchor
function W.ContextMenu(opts)
    if not cursorAnchor then
        cursorAnchor = CreateFrame("Frame", nil, UIParent)
        cursorAnchor:SetSize(1, 1)
        cursorAnchor.menuAtCursor = true
    end
    local list = {}
    for i, o in ipairs(opts) do list[i] = { i, o[1], disabled = o.disabled, header = o.header } end
    if menu and menu:IsShown() then menu:Hide() end
    W.ShowMenu(cursorAnchor, list, function(i) if opts[i][2] then opts[i][2]() end end, false, 170)
end

local function DropdownButton(parent, width)
    local b = MakeButton(parent, "", width or 120, 26)
    b.text:ClearAllPoints(); b.text:SetPoint("LEFT", 8, 0); b.text:SetPoint("RIGHT", -18, 0)
    b.text:SetJustifyH("LEFT"); b.text:SetWordWrap(false)
    local arrow = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    arrow:SetPoint("RIGHT", -7, 0); arrow:SetText("v"); Muted(arrow)
    b:HookScript("OnHide", function(self) if menu and menu.owner == self then menu:Hide() end end)
    return b
end

-- Dropdown in the flat style: a button that opens a menu of rows.
-- getOptions() returns { {value, label}, ... }; onSelect(value, label).
function W.MakeDropdown(parent, width, getOptions, onSelect)
    local b = DropdownButton(parent, width)
    function b:SetValue(value, label) self.value = value; self.text:SetText(label or tostring(value or "")) end
    b:SetScript("OnClick", function(self)
        W.ShowMenu(self, getOptions() or {}, function(value, label)
            self:SetValue(value, label); onSelect(value, label)
        end)
    end)
    return b
end

-- Dropdown with ticks. getOptions() returns { {value, label, checked=bool, header=bool}, ... };
-- onChange(value, checked) runs for every tick; the caller sets the button text with :SetLabel.
function W.MakeMultiDropdown(parent, width, getOptions, onChange)
    local b = DropdownButton(parent, width)
    function b:SetLabel(text) self.text:SetText(text) end
    b:SetScript("OnClick", function(self)
        W.ShowMenu(self, getOptions() or {}, function(value, _, o) onChange(value, o.checked) end, true, 200)
    end)
    return b
end

-- Row of clickable column headers. cols = { {key, label, width}, ... }; onSort(key, desc).
function W.MakeColumnHeaders(parent, cols, onSort)
    local h = CreateFrame("Frame", nil, parent)
    h:SetHeight(20)
    h.buttons, h.sortKey, h.desc = {}, cols[1][1], false
    local function Update()
        for _, b in ipairs(h.buttons) do
            local arrow = b.key == h.sortKey and (h.desc and "  v" or "  ^") or ""
            b.text:SetText(b.label .. arrow)
            W.SetActive(b, b.key == h.sortKey)
        end
    end
    local x = 0
    for i, c in ipairs(cols) do
        local b = MakeButton(h, c[2], c[3], 20)
        b.key, b.label = c[1], c[2]
        b.text:ClearAllPoints(); b.text:SetPoint("LEFT", 8, 0)
        if c[3] then b:SetPoint("LEFT", x, 0); x = x + c[3] + 2
        else b:SetPoint("LEFT", x, 0); b:SetPoint("RIGHT", h, "RIGHT", 0, 0) end
        b:SetScript("OnClick", function()
            if h.sortKey == b.key then h.desc = not h.desc else h.sortKey, h.desc = b.key, false end
            Update(); onSort(h.sortKey, h.desc)
        end)
        h.buttons[i] = b
    end
    function h:Set(key, desc) self.sortKey, self.desc = key, desc; Update() end
    Update()
    return h
end

function W.QualityName(name, quality)
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color and color.hex then return color.hex .. name .. "|r" end
    return name
end

function W.IconFor(e)
    if e.icon then return e.icon end
    local id = e.id or e.itemID
    if id then return select(5, C.GetItemInfoInstant(id)) or UNKNOWN_ICON end
    if e.link then return select(5, C.GetItemInfoInstant(e.link)) or UNKNOWN_ICON end
    return UNKNOWN_ICON
end

-- Short money text: "1g 20s", "45s 10c". nil prints as "n/a".
function W.Money(copper)
    if not copper then return "|cff8fa3b3n/a|r" end
    return C.Money(copper)
end

StaticPopupDialogs["WEALTHPLANNER_CONFIRM"] = {
    text = "%s", button1 = YES or "Yes", button2 = NO or "No",
    OnAccept = function(_, data) if data and data.fn then data.fn() end end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, showAlert = 1, preferredIndex = 3,
}
function W.Confirm(text, fn) StaticPopup_Show("WEALTHPLANNER_CONFIRM", text, nil, { fn = fn }) end

-- One-line text prompt, pre-filled. Enter or Accept calls fn(text) with the trimmed text.
local function PopupEditBox(self) return self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox()) end
StaticPopupDialogs["WEALTHPLANNER_ASK_TEXT"] = {
    text = "%s", button1 = ACCEPT or "Accept", button2 = CANCEL or "Cancel",
    hasEditBox = 1, maxLetters = 60,
    OnShow = function(self, data)
        data = data or self.data
        local box = PopupEditBox(self)
        if box and data then box:SetText(data.default or ""); box:HighlightText(); box:SetFocus() end
    end,
    OnAccept = function(self, data)
        local box = PopupEditBox(self)
        local text = box and ns.Trim(box:GetText()) or ""
        if text ~= "" then data.fn(text) end
    end,
    EditBoxOnEnterPressed = function(box)
        local dialog = box:GetParent()
        local data = dialog.data
        local text = ns.Trim(box:GetText())
        if text ~= "" and data then data.fn(text) end
        dialog:Hide()
    end,
    EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}
function W.AskText(prompt, default, fn)
    local dialog = StaticPopup_Show("WEALTHPLANNER_ASK_TEXT", prompt, nil, { default = default, fn = fn })
    -- Some clients set dialog.data only after OnShow has run; fill the box again to be sure.
    local box = dialog and PopupEditBox(dialog)
    if box then box:SetText(default or ""); box:HighlightText(); box:SetFocus() end
end

-- Three-way prompt used by the Cart when nothing is within tolerance. Escape counts as Cancel.
StaticPopupDialogs["WEALTHPLANNER_PROMPT3"] = {
    text = "%s", button1 = "Buy Cheapest", button2 = CANCEL or "Cancel", button3 = "Skip Item",
    OnAccept = function(_, data) data.done = true; data.fns[1]() end,
    OnAlt = function(_, data) data.done = true; data.fns[3]() end,
    OnCancel = function(_, data) if not data.done then data.done = true; data.fns[2]() end end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, showAlert = 1, preferredIndex = 3,
}
-- W.Prompt3(text, buyCheapestFn, cancelFn, skipFn)
function W.Prompt3(text, a, b, c)
    StaticPopup_Show("WEALTHPLANNER_PROMPT3", text, nil, { fns = { a, b, c } })
end

-- The item on the cursor as (itemID, link), clearing the cursor; nil when it holds no item.
function W.TakeCursorItem()
    local cursorType, id, link = GetCursorInfo()
    if cursorType ~= "item" then return nil end
    ClearCursor()
    return id, link
end

function W.Hex(c)
    return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

-- ---------------------------------------------------------------------------
-- Quantity popup: how many to buy or add, then one main button (Buy / Confirm / Add) and Cancel.
-- W.QuantityDialog({ title, icon, qty = default, max, mainLabel, describe(qty) -> text,
--                    onMain(qty, dialog), onQtyChanged(qty, dialog), onCancel() })
-- dialog:Qty()  :SetMainLabel(text)  :SetBusy(on)  :SetLine(text)  :SetProgress(text)  :LockQty(on)
--        :Refresh()  :Close(silent)
-- onMain runs from the button click (or Enter), so it may do things that need a hardware event.
-- ---------------------------------------------------------------------------

local qdialog
local function GetQuantityDialog()
    if qdialog then return qdialog end
    local d = CreateFrame("Frame", "WealthPlannerQuantityDialog", UIParent, "BackdropTemplate")
    d:SetSize(380, 172); d:SetPoint("CENTER", 0, 120)
    SetBackdrop(d, 0.98); d:SetFrameStrata("DIALOG"); d:SetToplevel(true)
    d:EnableMouse(true); d:SetClampedToScreen(true)
    d:Hide()
    tinsert(UISpecialFrames, "WealthPlannerQuantityDialog") -- Escape closes it
    d.icon = d:CreateTexture(nil, "ARTWORK"); d.icon:SetSize(32, 32); d.icon:SetPoint("TOPLEFT", 14, -14)
    d.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    d.title = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    d.title:SetPoint("LEFT", d.icon, "RIGHT", 10, 0); d.title:SetPoint("RIGHT", d, "RIGHT", -14, 0)
    d.title:SetJustifyH("LEFT"); d.title:SetWordWrap(false)

    local label = Muted(d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
    label:SetPoint("TOPLEFT", 14, -64); label:SetText("Quantity")
    d.minus = MakeButton(d, "-", 26, 26); d.minus:SetPoint("LEFT", label, "RIGHT", 10, 0)
    d.box = W.MakeNumberBox(d, 64); d.box:SetPoint("LEFT", d.minus, "RIGHT", 4, 0)
    d.plus = MakeButton(d, "+", 26, 26); d.plus:SetPoint("LEFT", d.box, "RIGHT", 4, 0)
    d.max = MakeButton(d, "Max", 46, 26); d.max:SetPoint("LEFT", d.plus, "RIGHT", 6, 0)

    d.line = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d.line:SetPoint("TOPLEFT", 14, -98); d.line:SetPoint("TOPRIGHT", -14, -98)
    d.line:SetJustifyH("LEFT"); d.line:SetWordWrap(true)
    -- Progress of a click session: "Bought 20 / 40 · spent ... · 2 clicks left".
    d.progress = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    d.progress:SetPoint("TOPLEFT", 14, -122); d.progress:SetPoint("TOPRIGHT", -14, -122)
    d.progress:SetJustifyH("LEFT"); d.progress:SetWordWrap(false)

    d.main = MakeButton(d, "Buy", 200, 28); d.main:SetPoint("BOTTOMRIGHT", -14, 12)
    d.main.text:SetFontObject("GameFontHighlight")
    d.cancel = MakeButton(d, "Cancel", 80, 28); d.cancel:SetPoint("RIGHT", d.main, "LEFT", -6, 0)

    function d:Qty()
        local q = math.floor(self.box:GetValue() or 1)
        q = math.max(1, q)
        if self.opts and self.opts.max then q = math.min(q, self.opts.max) end
        return q
    end
    function d:SetMainLabel(text) self.main.text:SetText(text) end
    function d:SetBusy(on)
        self.busy = on
        self.main:SetEnabled(not on); self.main.text:SetAlpha(on and 0.5 or 1)
    end
    function d:SetLine(text) self.line:SetText(text or "") end
    function d:SetProgress(text) self.progress:SetText(text or "") end
    function d:LockQty(on)
        self.locked = on
        for _, w in ipairs({ self.box, self.minus, self.plus, self.max }) do
            w:SetEnabled(not on); w:SetAlpha(on and 0.45 or 1)
        end
    end
    function d:Refresh()
        if self.opts and self.opts.describe then self:SetLine(self.opts.describe(self:Qty())) end
    end
    function d:Close(silent)
        self.silent = silent
        self:Hide()
        self.silent = nil
    end
    local function SetQty(q)
        d.box:SetValue(q)
        if d.opts.onQtyChanged then d.opts.onQtyChanged(d:Qty(), d) end
        d:Refresh()
    end
    d.minus:SetScript("OnClick", function() SetQty(math.max(1, d:Qty() - 1)) end)
    d.plus:SetScript("OnClick", function() SetQty(d:Qty() + 1) end)
    d.max:SetScript("OnClick", function() if d.opts.max then SetQty(d.opts.max) end end)
    d.box:HookScript("OnTextChanged", function(_, user)
        if not user then return end
        if d.opts.onQtyChanged then d.opts.onQtyChanged(d:Qty(), d) end
        d:Refresh()
    end)
    local function Main()
        if d.busy or not d.opts then return end
        d.opts.onMain(d:Qty(), d)
    end
    d.main:SetScript("OnClick", Main)
    d.box:SetScript("OnEnterPressed", function(self) self:ClearFocus(); Main() end)
    d.cancel:SetScript("OnClick", function() d:Hide() end)
    d:SetScript("OnHide", function(self)
        local opts = self.opts
        self.opts = nil
        if opts and opts.onCancel and not self.silent then opts.onCancel() end
    end)
    qdialog = d
    return d
end

function W.QuantityDialog(opts)
    local d = GetQuantityDialog()
    if d:IsShown() then d:Hide() end -- closes (and cancels) any other one first
    d.opts = opts
    d.icon:SetTexture(opts.icon or UNKNOWN_ICON)
    d.title:SetText(opts.title or "")
    d.box:SetValue(math.max(1, math.floor(opts.qty or 1)))
    d.max:SetShown(opts.max ~= nil)
    d:SetMainLabel(opts.mainLabel or "OK")
    d:SetBusy(false)
    d:LockQty(false)
    d:SetProgress("")
    d:Show()
    d:Refresh()
    d.box:SetFocus(); d.box:HighlightText()
    return d
end

-- ---------------------------------------------------------------------------
-- Category tree (the Browse tab's category list): "All categories", then classes that open to
-- show their subclasses. getTree() returns { {classID, name, subs = { {subClassID, name}, ... }}, ... };
-- onSelect(classID, subClassID) runs when a row is clicked. The caller positions the frame.
-- tree:Refresh()  tree:Set(classID, subClassID)  tree:Get()
-- ---------------------------------------------------------------------------

function W.MakeCategoryTree(parent, width, getTree, onSelect)
    local tree = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    tree:SetWidth(width)
    SetBackdrop(tree); tree:SetBackdropColor(0.045, 0.065, 0.085, 1)
    local scroll = CreateFrame("ScrollFrame", nil, tree, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4); scroll:SetPoint("BOTTOMRIGHT", -4, 4)
    local content = CreateFrame("Frame", nil, scroll); content:SetSize(width - 8, 1)
    scroll:SetScrollChild(content)
    -- The scroll bar would cover the buttons; hide it and rely on the mouse wheel.
    if scroll.ScrollBar then scroll.ScrollBar:SetAlpha(0); scroll.ScrollBar:EnableMouse(false) end
    local buttons = {}
    tree.expanded = {}

    function tree:Get() return self.classID, self.subClassID end

    function tree:Set(classID, subClassID)
        self.classID, self.subClassID = classID, subClassID
        if classID then self.expanded[classID] = true end
        self:Refresh()
    end

    function tree:Refresh()
        local rows = { { label = "All categories", indent = 0, active = not self.classID,
            fn = function() self.classID, self.subClassID = nil, nil end } }
        for _, c in ipairs(getTree() or {}) do
            local open = self.expanded[c[1]]
            rows[#rows + 1] = { label = (#c.subs > 0 and (open and "- " or "+ ") or "  ") .. c[2], indent = 0,
                active = self.classID == c[1] and not self.subClassID,
                fn = function()
                    if self.classID == c[1] and not self.subClassID then self.expanded[c[1]] = not open
                    else self.expanded[c[1]] = true end
                    self.classID, self.subClassID = c[1], nil
                end }
            if open then
                for _, s in ipairs(c.subs) do
                    rows[#rows + 1] = { label = s[2], indent = 12, active = self.classID == c[1] and self.subClassID == s[1],
                        fn = function() self.classID, self.subClassID = c[1], s[1] end }
                end
            end
        end
        for i, r in ipairs(rows) do
            local b = buttons[i]
            if not b then
                b = MakeButton(content, "", width - 8, 20)
                b.text:ClearAllPoints(); b.text:SetJustifyH("LEFT"); b.text:SetWordWrap(false)
                b:SetBackdropBorderColor(0, 0, 0, 0)
                b:SetScript("OnLeave", function(btn)
                    if btn.active then btn:SetBackdropColor(0.09, 0.15, 0.17, 1) else btn:SetBackdropColor(0.075, 0.105, 0.13, 1) end
                end)
                buttons[i] = b
            end
            b:SetPoint("TOPLEFT", 0, -(i - 1) * 21)
            b.text:SetPoint("LEFT", 6 + r.indent, 0); b.text:SetPoint("RIGHT", -4, 0)
            b.text:SetText(r.label)
            b.active = r.active
            if r.active then
                b:SetBackdropColor(0.09, 0.15, 0.17, 1); b.text:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
            else
                b:SetBackdropColor(0.075, 0.105, 0.13, 1)
                if r.indent > 0 then b.text:SetTextColor(0.8, 0.85, 0.9) else b.text:SetTextColor(1, 1, 1) end
            end
            b:SetScript("OnClick", function()
                r.fn(); tree:Refresh()
                if onSelect then onSelect(tree.classID, tree.subClassID) end
            end)
            b:Show()
        end
        for i = #rows + 1, #buttons do buttons[i]:Hide() end
        content:SetHeight(#rows * 21)
    end

    return tree
end

-- ---------------------------------------------------------------------------
-- Scrolling row list
-- ---------------------------------------------------------------------------
-- item = { icon, text, detail, detailColor, right, link, bar, barText, actions = {{label, fn, hint}},
--          onClick, onRightClick, hint, selected, dim, spark = { values, color },
--          status = { texture, desaturate, onClick, hint } }

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
    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.right:SetJustifyH("RIGHT"); row.right:SetWordWrap(true); row.right:SetWidth(130)
    if row.right.SetMaxLines then row.right:SetMaxLines(2) end
    row.barBg = row:CreateTexture(nil, "ARTWORK"); row.barBg:SetColorTexture(0.12, 0.16, 0.19, 1); row.barBg:SetSize(110, 6)
    row.barFill = row:CreateTexture(nil, "OVERLAY"); row.barFill:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    row.barFill:SetPoint("LEFT", row.barBg, "LEFT"); row.barFill:SetHeight(6)
    row.barText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); row.barText:SetJustifyH("RIGHT")
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

function W.LayoutRow(row, d, index)
    row.data = d
    row:ClearAllPoints()
    local height = row.height or ROW_H
    local compact = height < 34
    local y = -(index - 1) * (height + ROW_GAP)
    row:SetPoint("TOPLEFT", 0, y); row:SetPoint("TOPRIGHT", 0, y)
    if d.selected then row:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    else row:SetBackdropBorderColor(0.16, 0.24, 0.29, 1) end

    local left = 5
    -- Optional status toggle (Wally's ready check / red circle) left of the icon.
    if d.status then
        local s = row.status
        if not s then
            s = CreateFrame("Button", nil, row)
            s:SetSize(16, 16)
            s.tex = s:CreateTexture(nil, "ARTWORK"); s.tex:SetAllPoints()
            s:SetScript("OnClick", function(self) if self.fn then self.fn() end end)
            s:SetScript("OnEnter", function(self)
                if not self.hint then return end
                GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(self.hint, 0.85, 0.9, 0.95, true); GameTooltip:Show()
            end)
            s:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.status = s
        end
        s.tex:SetTexture(d.status.texture)
        s.tex:SetDesaturated(d.status.desaturate and true or false)
        s.fn, s.hint = d.status.onClick, d.status.hint
        s:ClearAllPoints(); s:SetPoint("LEFT", 6, 0); s:Show()
        left = 26
    elseif row.status then
        row.status:Hide()
    end
    row.icon:ClearAllPoints(); row.icon:SetPoint("LEFT", left, 0)
    row.icon:SetShown(not d.noIcon)
    local textX = d.noIcon and 9 or (left + height - 3)
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
        local width = a.width or math.max(a[1]:len() <= 2 and 24 or 54, (#a[1]) * 6 + 18)
        b:SetWidth(width); b.text:SetText(a[1]); b.fn, b.hint = a[2], a[3]
        b:ClearAllPoints(); b:SetPoint("RIGHT", right, 0); b:Show()
        right = right - width - 4
    end
    for i = #(d.actions or {}) + 1, #row.actions do row.actions[i]:Hide() end

    if d.right then
        row.right:ClearAllPoints(); row.right:SetPoint("RIGHT", right - 6, 0)
        row.right:SetText(d.right); row.right:SetAlpha(alpha); row.right:Show()
        right = right - 140
    else
        row.right:Hide()
    end

    -- A small sparkline (Chart.lua) left of the price column.
    if d.spark and #d.spark.values >= 2 then
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
    if showBar then
        row.barBg:ClearAllPoints(); row.barBg:SetPoint("RIGHT", right - 8, compact and -4 or -6)
        row.barFill:SetWidth(math.max(1, 110 * math.min(1, d.bar)))
        row.barText:SetText(d.barText or "")
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
    scroll:SetPoint("TOPLEFT", 0, top); scroll:SetPoint("BOTTOMRIGHT", -26, opts and opts.bottom or 0)
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
    function list:ScrollToTop() scroll:SetVerticalScroll(0) end
    return list
end
