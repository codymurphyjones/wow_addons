local _, ns = ...

-- Settings pages from a list of rows, in Wally's layout: a checkbox with a muted line under it, a
-- section heading with a rule, flat sliders and button choices.
--
--   { type = "group", id = "behavior", label = "Behavior" }            -- click to fold
--   { type = "check", key = "autoHide", label = "...", desc = "..." }  -- ns.db.options[key]
--   { type = "slider", key = "height", label = "Height", min = 16, max = 36, step = 1, format = "%d px" }
--   { type = "choice", key = "font", label = "Font", values = { { "small", "Small" }, ... } }
--   { type = "buttons", buttons = { { text, width, fn, hint, confirm = "Are you sure?" } } }
--   { type = "note", text = "..." }
--   { type = "custom", height = 40, build = function(row, width) end, refresh = function(row) end }
--
-- A key row saves through ns:SetOption("db.options.<key>") (addons/shared/OptionsPage.lua), so
-- Options > AddOns > SimplePanel shows the change and runs that option's apply there; give such a
-- row no apply of its own for the same side effect. Any row may use get/set instead of key, and
-- `apply` runs after a change. A row with
-- `disabled = function() return true end` fades and says why (`why`); hovering it lights up the
-- rows named in `causes` (by id or key), which are what turn it back on.
local Options = {}
ns.Options = Options

local W, T = ns.Widgets, ns.Theme
local Label, Muted, MakeButton, Hint = W.Label, W.Muted, W.MakeButton, W.Hint

local function Resolve(v, ...) if type(v) == "function" then return v(...) end return v end

local function Get(def)
    if def.get then return def.get() end
    return ns.db.options[def.key]
end

local function Set(def, value)
    if def.set then def.set(value) else ns:SetOption("db.options." .. def.key, value) end
    if def.apply then def.apply(value) end
end

local function Disabled(def)
    if not def.disabled then return false end
    local ok, v = pcall(def.disabled)
    return ok and v and true or false
end

local function FormatValue(def, v)
    if type(def.format) == "function" then return def.format(v) end
    return (def.format or "%s"):format(v)
end

-- Text a search matches against.
local function SearchText(def, group)
    return table.concat({ def.label or "", def.desc or "", def.text or "", def.keywords or "", group and group.label or "" }, " "):lower()
end

-- ---------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------

local function Highlight(row, on)
    if not row.hl then
        row.hl = row:CreateTexture(nil, "BACKGROUND")
        row.hl:SetPoint("TOPLEFT", -6, 2); row.hl:SetPoint("BOTTOMRIGHT", 6, -2)
    end
    row.hl:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.16)
    row.hl:SetShown(on)
end

-- Hover on a faded row: say why, and light up whatever is holding it off.
local function HookCause(r, view, widget)
    widget:HookScript("OnEnter", function(self)
        if not r.off then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(r.def.label or "", T.muted[1], T.muted[2], T.muted[3])
        GameTooltip:AddLine(Resolve(r.def.why) or "Not available right now.", T.yellow[1], T.yellow[2], T.yellow[3], true)
        GameTooltip:Show()
        for _, id in ipairs(r.def.causes or {}) do
            local other = view.byId[id]
            if other then Highlight(other, true) end
        end
    end)
    widget:HookScript("OnLeave", function()
        if not r.off then return end
        GameTooltip:Hide()
        for _, id in ipairs(r.def.causes or {}) do
            local other = view.byId[id]
            if other then Highlight(other, false) end
        end
    end)
end

local BUILD = {}

BUILD.check = function(r, view)
    local def = r.def
    r.box = W.MakeCheckbox(r, def.label)
    r.box:SetPoint("TOPLEFT", -4, 0)
    r.box:SetScript("OnClick", function(self)
        if r.off then self:SetChecked(Get(def) and true or false); return end
        Set(def, self:GetChecked() and true or false)
        view:Refresh()
    end)
    if def.desc then r.desc = Muted(Label(r, def.desc, "SimplePanelFontSmall", 27, -25, 480)) end
    r.height, r.descTop = 28, 25
    r.Refresh = function()
        r.box:SetChecked(Get(def) and true or false)
        if r.desc then
            if r.off then r.desc:SetText(T.hex.yellow .. (Resolve(def.why) or "Not available right now.") .. "|r")
            else r.desc:SetText(def.desc) end
        end
    end
    HookCause(r, view, r.box)
end

BUILD.slider = function(r, view)
    local def = r.def
    Label(r, def.label, "SimplePanelFontSmall", 0, 0)
    r.value = Label(r, "", "SimplePanelFontSmall", 330, 0)
    r.value:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
    r.slider = W.MakeSlider(r, 300, def.min, def.max, def.step, function(v)
        if r.off then return end
        Set(def, v)
        r.value:SetText(FormatValue(def, v))
    end)
    r.slider:SetPoint("TOPLEFT", 0, -18)
    if def.desc then r.desc = Muted(Label(r, def.desc, "SimplePanelFontSmall", 0, -36, 480)) end
    r.height, r.descTop = 44, 36
    r.Refresh = function()
        local v = Get(def) or def.min
        r.slider:SetSilently(v)
        r.value:SetText(FormatValue(def, v))
        r.slider:EnableMouse(not r.off)
    end
    HookCause(r, view, r.slider)
end

BUILD.choice = function(r, view)
    local def = r.def
    Label(r, def.label, "SimplePanelFontSmall", 0, -6)
    r.buttons = {}
    local x = def.labelWidth or 110
    for _, v in ipairs(def.values) do
        local b = MakeButton(r, v[2], v[3] or 80, 24)
        b:SetPoint("TOPLEFT", x, 0)
        b:SetScript("OnClick", function()
            if r.off then return end
            Set(def, v[1]); view:Refresh()
        end)
        HookCause(r, view, b)
        r.buttons[#r.buttons + 1] = { b = b, value = v[1] }
        x = x + (v[3] or 80) + 6
    end
    if def.desc then r.desc = Muted(Label(r, def.desc, "SimplePanelFontSmall", 0, -30, 480)) end
    r.height, r.descTop = 32, 30
    r.Refresh = function()
        local cur = Get(def)
        for _, e in ipairs(r.buttons) do W.SetActive(e.b, e.value == cur) end
    end
end

BUILD.buttons = function(r, view)
    local x = 0
    for _, d in ipairs(r.def.buttons) do
        local b = MakeButton(r, d.text, d.width or 140, 26)
        b:SetPoint("TOPLEFT", x, 0)
        b:SetScript("OnClick", function()
            if r.off then return end
            if d.confirm then W.Confirm(d.confirm, function() d.fn(); view:Refresh() end)
            else d.fn(); view:Refresh() end
        end)
        if d.hint then Hint(b, d.text, d.hint) end
        HookCause(r, view, b)
        x = x + (d.width or 140) + 8
    end
    r.height = 34
end

BUILD.note = function(r)
    r.text = Muted(Label(r, "", "SimplePanelFontSmall", 0, 0, 520))
    r.Refresh = function() r.text:SetText(Resolve(r.def.text) or "") end
    r.Refresh()
    r.height = math.ceil(r.text:GetStringHeight()) + 10
end

BUILD.custom = function(r, view)
    r.height = r.def.height or 30
    r.def.build(r, view)
    r.Refresh = r.def.refresh and function() r.def.refresh(r) end or nil
end

local function BuildGroup(r, view)
    local def = r.def
    r:EnableMouse(true)
    r.arrow = Label(r, "-", "SimplePanelFontTitle", 0, 0)
    r.arrow:SetTextColor(T.muted[1], T.muted[2], T.muted[3])
    r.title = Label(r, def.label, "SimplePanelFontTitle", 14, 0)
    r.rule = r:CreateTexture(nil, "ARTWORK")
    r.rule:SetColorTexture(T.border[1], T.border[2], T.border[3], 1); r.rule:SetHeight(1)
    r.rule:SetPoint("TOPLEFT", 0, -17); r.rule:SetPoint("TOPRIGHT", 0, -17)
    r.height = 30
    r:SetScript("OnMouseUp", function()
        if view.filter then return end
        view.collapsed[def.id] = not view.collapsed[def.id]
        view:Layout()
    end)
    r:SetScript("OnEnter", function() r.title:SetTextColor(T.accent[1], T.accent[2], T.accent[3]) end)
    r:SetScript("OnLeave", function() r.title:SetTextColor(1, 0.82, 0) end)
end

-- ---------------------------------------------------------------------------
-- View
-- ---------------------------------------------------------------------------

local View = {}
View.__index = View

-- Builds `defs` into a scrolling area filling `parent`. Returns the view.
function Options:Build(parent, defs)
    local view = setmetatable({ rows = {}, byId = {}, collapsed = {}, filter = nil }, View)
    view.scroll, view.child = W.ScrollArea(parent)
    local group
    for _, def in ipairs(defs) do
        local r = CreateFrame("Frame", nil, view.child)
        r.def = def
        if def.type == "group" then
            group = def
            BuildGroup(r, view)
            if def.collapsed then view.collapsed[def.id] = true end
        else
            r.group = group
            BUILD[def.type](r, view)
            r.search = SearchText(def, group)
        end
        r:SetHeight(r.height)
        local id = def.id or def.key
        if id then view.byId[id] = r end
        view.rows[#view.rows + 1] = r
    end
    view:Refresh()
    return view
end

-- Does a row match the search?
local function Matches(r, filter)
    return not filter or (r.search and r.search:find(filter, 1, true) ~= nil)
end

-- How many rows match a search, without changing what is shown.
function View:Count(filter)
    filter = filter and filter ~= "" and filter:lower() or nil
    local n = 0
    for _, r in ipairs(self.rows) do
        if r.def.type ~= "group" and filter and Matches(r, filter) then n = n + 1 end
    end
    return n
end

function View:SetFilter(filter)
    self.filter = filter and filter ~= "" and filter:lower() or nil
    self:Layout()
    return self:Count(self.filter)
end

-- Places the rows: folded groups hide theirs; a search shows only matching rows and their headings.
function View:Layout()
    local y, filter = 0, self.filter
    local groupHasMatch = {}
    if filter then
        for _, r in ipairs(self.rows) do
            if r.group and Matches(r, filter) then groupHasMatch[r.group] = true end
        end
    end
    for _, r in ipairs(self.rows) do
        local def, show = r.def, true
        if def.type == "group" then
            show = not filter or groupHasMatch[def] or false
            r.arrow:SetText((not filter and self.collapsed[def.id]) and "+" or "-")
        elseif filter then
            show = Matches(r, filter)
        elseif r.group and self.collapsed[r.group.id] then
            show = false
        end
        if show and def.hidden and Resolve(def.hidden) then show = false end
        r:SetShown(show)
        if show then
            if r.desc then -- as tall as its text, which can wrap to several lines or change (why)
                r:SetHeight(math.max(r.height, r.descTop + math.ceil(r.desc:GetStringHeight()) + 6))
            end
            if def.type == "group" and y < 0 then y = y - 6 end
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 4, y); r:SetPoint("RIGHT", self.child, "RIGHT", -4, 0)
            y = y - r:GetHeight()
        end
    end
    self.child:SetHeight(-y + 10)
    if self.empty == nil then
        self.empty = Muted(Label(self.child, "Nothing here matches your search.", "SimplePanelFontSmall", 4, -4))
    end
    self.empty:SetShown(filter ~= nil and y == 0)
end

function View:Refresh()
    for _, r in ipairs(self.rows) do
        if r.def.type ~= "group" then
            r.off = Disabled(r.def)
            r:SetAlpha(r.off and 0.45 or 1)
            if r.Refresh then r.Refresh() end
        end
    end
    self:Layout()
end
