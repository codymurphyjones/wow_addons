local addonName, ns = ...

-- Options > AddOns pages, the same for every addon here (addons/shared), on Blizzard's Settings API:
-- one standard list of headers, checkboxes, sliders, dropdowns and buttons, plus canvas subpages
-- under it for editors a list can't hold. Every control is bound to one saved option, and every UI
-- that changes that option (this page, the addon's own window, a slash command, a menu) goes
-- through ns:SetOption, so they all show the same value: a change anywhere refreshes the open
-- page, runs the option's apply, and calls ns:Changed() so the addon's own windows redraw.
--
-- Options are paths into the addon's saved tables: "db.options.chat" is ns.db.options.chat,
-- "char.minimap.hide" is ns.char.minimap.hide. Their defaults come from ns.DEFAULTS and
-- ns.CHAR_DEFAULTS, so the page's Defaults button restores the addon's real defaults.
--
--   ns.NewOptionsPage({
--       name = "Waypoint",                 -- the page's name under Options > AddOns
--       icon = true,                       -- its icon (ns.IconMarkup) after the name
--       build = function(page)            -- runs at login, once the saved variables are loaded
--           page:Header("The arrow")
--           page:Check({ path = "db.locked", label = "Lock the arrow", tooltip = "..." })
--           page:Check({ path = "char.minimap.hide", invert = true, label = "Show the minimap button",
--               apply = function() ns.MinimapButton:Refresh() end })
--           page:Slider({ path = "db.climb", label = "Cost of climbing", min = 0, max = 3, step = 0.25,
--               format = function(v) return ("%.2g"):format(v) end })
--           page:Dropdown({ path = "db.dockAlign", label = "Windows under the arrow",
--               choices = { { "LEFT", "Left" }, { "CENTER", "Center" }, { "RIGHT", "Right" } } })
--           page:Button({ label = "Stat priority", text = "Edit", fn = function() ... end })
--           page:Subpage({ name = "Bag Sorting", build = function(frame) ... end, refresh = function(frame) ... end })
--       end,
--   })
--
-- A control can use get/set functions instead of a path (for values kept elsewhere); apply runs
-- after every change, from any UI. The page object has Open([subpage name]) and Refresh().
local K = {}
ns.OptionsKit = K

local pages = {}
local applies = {}   -- path -> { fn, ... }: what an option's change does, whichever UI made it
local listeners = {} -- fn(path, value) for each change

-- ---------------------------------------------------------------------------
-- The option store
-- ---------------------------------------------------------------------------

local function Split(path)
    local parts = {}
    for part in tostring(path):gmatch("[^%.]+") do parts[#parts + 1] = tonumber(part) or part end
    return parts
end

-- The table at the root of a path ("db" is ns.db, "char" ns.char) and its own default table.
local ROOT_DEFAULTS = { db = "DEFAULTS", char = "CHAR_DEFAULTS" }
local function Root(name, defaults)
    if defaults then return ns[ROOT_DEFAULTS[name] or ""] end
    return ns[name]
end

local function Walk(t, parts, upto, create)
    for i = 2, upto do
        if type(t) ~= "table" then return nil end
        local nxt = t[parts[i]]
        if nxt == nil and create then nxt = {}; t[parts[i]] = nxt end
        t = nxt
    end
    return t
end

function ns:GetOption(path)
    local parts = Split(path)
    local t = Walk(Root(parts[1]), parts, #parts - 1)
    if type(t) ~= "table" then return nil end
    return t[parts[#parts]]
end

-- The addon's default for an option, or nil.
function ns:DefaultOption(path)
    local parts = Split(path)
    local t = Walk(Root(parts[1], true), parts, #parts - 1)
    if type(t) ~= "table" then return nil end
    return t[parts[#parts]]
end

local function Notify(path, value)
    for _, page in ipairs(pages) do page:Refresh() end
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, path, value)
        if not ok then geterrorhandler()(err) end
    end
    if ns.Changed then ns:Changed() end
end

-- Saves an option and lets every UI know: its applies run, open pages refresh, ns:Changed().
function ns:SetOption(path, value)
    local parts = Split(path)
    local t = Walk(Root(parts[1]), parts, #parts - 1, true)
    if type(t) ~= "table" then return end
    t[parts[#parts]] = value
    for _, fn in ipairs(applies[path] or {}) do
        local ok, err = pcall(fn, value)
        if not ok then geterrorhandler()(err) end
    end
    Notify(path, value)
end

-- Flips a true/false option and returns its new value (for slash command toggles).
function ns:ToggleOption(path)
    local v = not self:GetOption(path)
    self:SetOption(path, v)
    return v
end

-- Code that changed a saved value directly calls this, so the pages and windows show it.
function ns:OptionChanged(path) Notify(path, path and self:GetOption(path)) end

-- fn(path, value) after every change (a window that shows options keeps itself current with it).
function ns:OnOptionChanged(fn) listeners[#listeners + 1] = fn end

-- ---------------------------------------------------------------------------
-- Pages
-- ---------------------------------------------------------------------------

local Page = {}
Page.__index = Page

local function Usable()
    return Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting
        and (Settings.CreateCheckbox or Settings.CreateCheckBox) and Settings.VarType and Settings.VarType.Boolean
        and true or false
end
K.Usable = Usable

-- get/set for a control: its own, or its path's (inverted for "Show ..." of a hide flag).
local function Accessors(def)
    local get, set = def.get, def.set
    if def.path then
        if def.apply then
            applies[def.path] = applies[def.path] or {}
            table.insert(applies[def.path], def.apply)
        end
        get = get or function() return ns:GetOption(def.path) end
        set = set or function(v) ns:SetOption(def.path, v) end
    else
        local rawSet = set
        set = function(v)
            rawSet(v)
            if def.apply then def.apply(v) end
            Notify(nil, v)
        end
    end
    if def.invert then
        local g, s = get, set
        get = function() return not g() end
        set = function(v) s(not v) end
    end
    return get, set
end

function Page:Variable(def)
    self.n = self.n + 1
    return addonName .. "_" .. (def.id or def.path or ("option" .. self.n)):gsub("[^%w]", "_")
end

-- The default the page's Defaults button restores.
local function DefaultFor(def, get, kind)
    local d = def.default
    if d == nil and def.path then
        d = ns:DefaultOption(def.path)
        if def.invert and d ~= nil then d = not d end
    end
    if d == nil then d = get() end
    if kind == "boolean" then return d and true or false end
    return d
end

function Page:Track(setting, get)
    self.entries[#self.entries + 1] = { setting = setting, get = get }
end

function Page:Header(text)
    if self.headless then return end
    if self.layout and self.layout.AddInitializer and CreateSettingsListSectionHeaderInitializer then
        self.layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
    end
end

function Page:Check(def)
    local get, set = Accessors(def)
    if self.headless then return end
    local function Get() return get() and true or false end
    local setting = Settings.RegisterProxySetting(self.category, self:Variable(def), Settings.VarType.Boolean,
        def.label, DefaultFor(def, Get, "boolean"), Get, function(value)
            if self.refreshing then return end
            set(value and true or false)
        end)
    local CreateCheckbox = Settings.CreateCheckbox or Settings.CreateCheckBox
    CreateCheckbox(self.category, setting, def.tooltip)
    self:Track(setting, Get)
    return setting
end

-- A number. scale shows it multiplied (0..1 saved, 0..100 shown: scale = 100); format(shown) labels it.
function Page:Slider(def)
    local get, set = Accessors(def)
    if self.headless or not (Settings.CreateSlider and Settings.CreateSliderOptions and Settings.VarType.Number) then return end
    local scale = def.scale or 1
    local function Get()
        local v = tonumber(get()) or tonumber(DefaultFor(def, function() return def.min end)) or def.min
        return v * scale
    end
    local setting = Settings.RegisterProxySetting(self.category, self:Variable(def), Settings.VarType.Number,
        def.label, (tonumber(DefaultFor(def, function() return def.min end)) or def.min) * scale, Get, function(value)
            if self.refreshing then return end
            set(value / scale)
        end)
    local options = Settings.CreateSliderOptions(def.min * scale, def.max * scale, (def.step or 1) * scale)
    if MinimalSliderWithSteppersMixin and options.SetLabelFormatter then
        local format = def.format or (def.percent and function(v) return ("%d%%"):format(v) end)
            or function(v) return tostring(math.floor(v * 100 + 0.5) / 100) end
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, format)
    end
    Settings.CreateSlider(self.category, setting, options, def.tooltip)
    self:Track(setting, Get)
    return setting
end

-- choices = { { value, label }, ... } or a function returning them (read each time it opens).
function Page:Dropdown(def)
    local get, set = Accessors(def)
    if self.headless then return end
    local CreateDropdown = Settings.CreateDropdown or Settings.CreateDropDown
    if not (CreateDropdown and Settings.CreateControlTextContainer) then return end
    local first = type(def.choices) == "table" and def.choices[1] and def.choices[1][1]
    local numeric = type(first) == "number"
    local varType = numeric and Settings.VarType.Number or Settings.VarType.String
    if not varType then return end
    local function Get()
        local v = get()
        if v == nil then v = DefaultFor(def, function() return first end) end
        return v
    end
    local setting = Settings.RegisterProxySetting(self.category, self:Variable(def), varType,
        def.label, DefaultFor(def, function() return first end) or first, Get, function(value)
            if self.refreshing then return end
            set(value)
        end)
    CreateDropdown(self.category, setting, function()
        local c = Settings.CreateControlTextContainer()
        local list = type(def.choices) == "function" and def.choices() or def.choices
        for _, choice in ipairs(list or {}) do c:Add(choice[1], choice[2]) end
        return c:GetData()
    end, def.tooltip)
    self:Track(setting, Get)
    return setting
end

function Page:Button(def)
    if self.headless then return end
    if self.layout and self.layout.AddInitializer and CreateSettingsButtonInitializer then
        self.layout:AddInitializer(CreateSettingsButtonInitializer(def.label, def.text or def.label, def.fn,
            def.tooltip, true))
    end
end

-- A canvas page under this one: build(frame) the first time it shows, refresh(frame) every time
-- and after every option change.
function Page:Subpage(def)
    if self.headless then return end
    self.subpages[#self.subpages + 1] = def
end

function Page:Refresh()
    if not self.category then return end
    self.refreshing = true
    for _, e in ipairs(self.entries) do pcall(e.setting.SetValue, e.setting, e.get()) end
    self.refreshing = false
    for _, sub in ipairs(self.subpages) do
        if sub.frame and sub.built and sub.frame:IsVisible() and sub.refresh then pcall(sub.refresh, sub.frame) end
    end
end

-- Opens the page (or one of its subpages, by name). Prints where to find it when that can't be done.
function Page:Open(subName)
    local target = self.category
    for _, sub in ipairs(self.subpages) do
        if sub.name == subName and sub.category then target = sub.category end
    end
    if target and Settings and Settings.OpenToCategory then
        self:Refresh()
        if pcall(Settings.OpenToCategory, target:GetID()) then return true end
    end
    local where = "Options > AddOns > " .. self.def.name .. (subName and (" > " .. subName) or "")
    if ns.Print then ns:Print("Open the game menu > " .. where .. ".", true) else print(where) end
    return false
end

function Page:Register()
    if self.category or self.headless then return end
    local def = self.def
    if not Usable() then
        -- The Settings API isn't usable (kept as a guard): the options still apply the same from
        -- every other UI.
        self.headless = true
        local ok, err = pcall(def.build, self)
        if not ok then geterrorhandler()(err) end
        return
    end
    local title = def.name .. ((def.icon and ns.IconMarkup) and (" " .. ns.IconMarkup(16)) or "")
    self.category, self.layout = Settings.RegisterVerticalLayoutCategory(title)
    local ok, err = pcall(def.build, self)
    if not ok then geterrorhandler()(err) end
    for _, sub in ipairs(self.subpages) do
        if Settings.RegisterCanvasLayoutSubcategory then
            local frame = CreateFrame("Frame")
            sub.frame = frame
            frame:SetScript("OnShow", function(f)
                if not sub.built then
                    sub.built = true
                    local okBuild, errBuild = pcall(sub.build, f)
                    if not okBuild then geterrorhandler()(errBuild) end
                end
                if sub.refresh then pcall(sub.refresh, f) end
            end)
            sub.category = Settings.RegisterCanvasLayoutSubcategory(self.category, frame, sub.name)
        end
    end
    Settings.RegisterAddOnCategory(self.category)
end

function ns.NewOptionsPage(def)
    local page = setmetatable({ def = def, entries = {}, subpages = {}, n = 0 }, Page)
    pages[#pages + 1] = page
    if IsLoggedIn and IsLoggedIn() then
        page:Register()
    else
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_LOGIN")
        f:SetScript("OnEvent", function() page:Register() end)
    end
    return page
end
