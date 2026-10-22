local addonName, ns = ...

-- Extras on the shared widget kit (Widgets.lua, which loads first) for the bigger windows:
-- Quartermaster's and Wealth Planner's. Popup menus and dropdowns, sortable column headers,
-- number / range / link boxes, text and three-way prompts, the quantity dialog, the category tree,
-- the item on the cursor, and W.Theme (the colours Chart.lua draws with).
local PAL = ns.Palette
local W = ns.Widgets

local WHITE, ACCENT, MUTED, UNKNOWN_ICON = W.WHITE, W.ACCENT, W.MUTED, W.UNKNOWN_ICON
local SetBackdrop, MakeButton, MakeEditBox, Muted = W.SetBackdrop, W.MakeButton, W.MakeEditBox, W.Muted
local KEY = addonName:upper()

-- Colours Chart.lua draws with (SimplePanel's default theme).
local YELLOW, RED, GREEN, BLUE, ORANGE = { 1, 0.82, 0.30 }, { 0.85, 0.45, 0.42 }, { 0.35, 0.95, 0.55 }, { 0.40, 0.80, 1 }, { 1, 0.60, 0.20 }
W.Theme = {
    white = WHITE, accent = ACCENT, muted = MUTED, border = PAL.border, track = { 0.12, 0.16, 0.19 },
    text = { 0.85, 0.9, 0.95 }, yellow = YELLOW, red = RED, green = GREEN, blue = BLUE, orange = ORANGE,
    series = { ACCENT, YELLOW, BLUE, ORANGE, GREEN, RED, { 0.75, 0.55, 1 }, { 0.9, 0.9, 0.9 } },
}

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
    f.label = f:CreateFontString(nil, "OVERLAY", addonName .. "GameFontHighlightSmall")
    f.label:SetPoint("LEFT"); f.label:SetText(label or ""); Muted(f.label)
    local labelW = label and (f.label:GetStringWidth() + 6) or 0
    f.min = W.MakeNumberBox(f, width, "min"); f.min:SetPoint("LEFT", labelW, 0)
    local dash = f:CreateFontString(nil, "OVERLAY", addonName .. "GameFontHighlightSmall")
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
            item:SetScript("OnLeave", function(self) self:SetBackdropColor(PAL.button[1], PAL.button[2], PAL.button[3], 1) end)
            m.items[i] = item
        end
        item:SetWidth(w - 8)
        item:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 23)
        local label = o[2]
        if multi and not o.header then label = (o.checked and "|cff55d6be[x]|r " or "|cff8fa3b3[  ]|r ") .. label end
        item.text:SetText(label)
        if o.header then
            item.text:SetTextColor(MUTED[1], MUTED[2], MUTED[3]); item:EnableMouse(false)
            item:SetBackdropColor(PAL.bg[1], PAL.bg[2], PAL.bg[3], 1)
        else
            item.text:SetTextColor(1, 1, 1); item:EnableMouse(not o.disabled)
            item:SetBackdropColor(PAL.button[1], PAL.button[2], PAL.button[3], 1)
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
    local arrow = b:CreateFontString(nil, "OVERLAY", addonName .. "GameFontHighlightSmall")
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

-- One-line text prompt, pre-filled. Enter or Accept calls fn(text) with the trimmed text.
local function PopupEditBox(self) return self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox()) end
StaticPopupDialogs[KEY .. "_ASK_TEXT"] = {
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
    local dialog = StaticPopup_Show(KEY .. "_ASK_TEXT", prompt, nil, { default = default, fn = fn })
    -- dialog.data can be set only after OnShow has run; fill the box again to be sure.
    local box = dialog and PopupEditBox(dialog)
    if box then box:SetText(default or ""); box:HighlightText(); box:SetFocus() end
end

-- Three-way prompt used by the Cart when nothing is within tolerance. Escape counts as Cancel.
StaticPopupDialogs[KEY .. "_PROMPT3"] = {
    text = "%s", button1 = "Buy Cheapest", button2 = CANCEL or "Cancel", button3 = "Skip Item",
    OnAccept = function(_, data) data.done = true; data.fns[1]() end,
    OnAlt = function(_, data) data.done = true; data.fns[3]() end,
    OnCancel = function(_, data) if not data.done then data.done = true; data.fns[2]() end end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, showAlert = 1, preferredIndex = 3,
}
-- W.Prompt3(text, buyCheapestFn, cancelFn, skipFn)
function W.Prompt3(text, a, b, c)
    StaticPopup_Show(KEY .. "_PROMPT3", text, nil, { fns = { a, b, c } })
end

-- Quartermaster: adds the item on the cursor to a list or prebuilt list (default: Browse's add target).
function W.AddCursorItem(list)
    local cursorType, id, link = GetCursorInfo()
    if cursorType ~= "item" then return false end
    ClearCursor()
    return ns.Lists:AddItem(link or id, 1, list or ns.Lists:AddTarget())
end

-- The item on the cursor as (itemID, link), clearing the cursor; nil when it holds no item.
function W.TakeCursorItem()
    local cursorType, id, link = GetCursorInfo()
    if cursorType ~= "item" then return nil end
    ClearCursor()
    return id, link
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
    local d = CreateFrame("Frame", addonName .. "QuantityDialog", UIParent, "BackdropTemplate")
    d:SetSize(380, 172); d:SetPoint("CENTER", 0, 120)
    SetBackdrop(d, 0.98); d:SetFrameStrata("DIALOG"); d:SetToplevel(true)
    d:EnableMouse(true); d:SetClampedToScreen(true)
    d:Hide()
    tinsert(UISpecialFrames, addonName .. "QuantityDialog") -- Escape closes it
    d.icon = d:CreateTexture(nil, "ARTWORK"); d.icon:SetSize(32, 32); d.icon:SetPoint("TOPLEFT", 14, -14)
    d.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    d.title = d:CreateFontString(nil, "OVERLAY", addonName .. "GameFontHighlight")
    d.title:SetPoint("LEFT", d.icon, "RIGHT", 10, 0); d.title:SetPoint("RIGHT", d, "RIGHT", -14, 0)
    d.title:SetJustifyH("LEFT"); d.title:SetWordWrap(false)

    local label = Muted(d:CreateFontString(nil, "OVERLAY", addonName .. "GameFontHighlightSmall"))
    label:SetPoint("TOPLEFT", 14, -64); label:SetText("Quantity")
    d.minus = MakeButton(d, "-", 26, 26); d.minus:SetPoint("LEFT", label, "RIGHT", 10, 0)
    d.box = W.MakeNumberBox(d, 64); d.box:SetPoint("LEFT", d.minus, "RIGHT", 4, 0)
    d.plus = MakeButton(d, "+", 26, 26); d.plus:SetPoint("LEFT", d.box, "RIGHT", 4, 0)
    d.max = MakeButton(d, "Max", 46, 26); d.max:SetPoint("LEFT", d.plus, "RIGHT", 6, 0)

    d.line = d:CreateFontString(nil, "OVERLAY", addonName .. "GameFontHighlightSmall")
    d.line:SetPoint("TOPLEFT", 14, -98); d.line:SetPoint("TOPRIGHT", -14, -98)
    d.line:SetJustifyH("LEFT"); d.line:SetWordWrap(true)
    -- Progress of a click session: "Bought 20 / 40 · spent ... · 2 clicks left".
    d.progress = d:CreateFontString(nil, "OVERLAY", addonName .. "GameFontNormal")
    d.progress:SetPoint("TOPLEFT", 14, -122); d.progress:SetPoint("TOPRIGHT", -14, -122)
    d.progress:SetJustifyH("LEFT"); d.progress:SetWordWrap(false)

    d.main = MakeButton(d, "Buy", 200, 28); d.main:SetPoint("BOTTOMRIGHT", -14, 12)
    d.main.text:SetFontObject(addonName .. "GameFontHighlight")
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
    SetBackdrop(tree); tree:SetBackdropColor(PAL.panel[1], PAL.panel[2], PAL.panel[3], 1)
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
                    if btn.active then btn:SetBackdropColor(0.09, 0.15, 0.17, 1) else btn:SetBackdropColor(PAL.button[1], PAL.button[2], PAL.button[3], 1) end
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
                b:SetBackdropColor(PAL.button[1], PAL.button[2], PAL.button[3], 1)
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
