local _, ns = ...

--[[ PluginKit: how anything gets onto the bar.

    SimplePanel.RegisterPlugin({
        id = "MyThing",                -- unique; also the saved-settings key
        name = "My Thing",             -- shown in menus and settings
        title = "Thing",               -- optional heading for its tooltip and menu (defaults to name)
        category = "Character",        -- groups plugins in the "Add plugin" menu
        icon = 134400,                 -- file ID, path or "atlas:name"
        label = "Thing",               -- optional label shown before the value ("Thing: 12")
        zone = "left",                 -- default zone: left | center | right
        defaultEnabled = true,         -- or function() return isHunter end, asked once on first load
        scope = "account",             -- where p:Get/p:Set live: "account" or "char"
        defaults = { mode = "a" },     -- default settings
        events = { "BAG_UPDATE" },     -- refresh on these events
        interval = 1,                  -- and/or every N seconds
        series = { fps = { max = 300, persist = nil, minInterval = 1 } }, -- chart buffers ("char" / "account" persist)
        spark = "fps",                 -- series drawn as an inline sparkline when the user turns it on
        progress = function(p) return value, max, color, extra, extraColor end, -- draws the button as a
                                       -- progress bar; extra is a second segment after the fill; nil hides it
        progressWidth = 140,           -- the bar's default width
        progressTicks = false,         -- no tenths marks (they suit XP, not every bar)
        text = function(p) return "12", "optional label override" end, -- string or { {text=, color=, icon=}, ... }
                                       -- ({ sep = true } is a spaced, muted dot between groups;
                                       --  fullIcon = true shows an icon uncropped; iconColor = {r,g,b}
                                       --  tints one, for SimplePanel's own white icons in Media\)
        tooltip = function(p, tt) end, -- SimplePanel tooltip (see Tooltip.lua)
        menu = function(p, m) end,     -- right-click entries (see Menu.lua); standard controls are added after
        chart = function(p, range) return spec end, -- spec for the chart window (see Chart.lua)
        chartRanges = { "15m", "1h", "session" },
        onClick = function(p, button) end,
        onWheel = function(p, delta) end, -- mouse wheel over the button (+1 up, -1 down)
        secure = function(p) return attrs end, -- left-click as the game's own code (SecureClick.lua)
        indicators = function(p) return { { icon = 132147, on = true }, ... } end, -- icons after the text;
                                       -- an "off" one is drawn grey
        onEnable = function(p) end, onDisable = function(p) end,
    })

    Plugin object: p:Refresh(), p:Get(k), p:Set(k, v), p:On(event, fn), p:Every(sec, fn),
    p:Record(series, value[, time]), p:Series(name), p:Points(name[, since]), p:ShowChart(),
    p:Flash(), p:SetBadge(n), p:IsEnabled(), p:SetEnabled(bool), p:Print(msg)
]]
local PK = {}
ns.PluginKit = PK

local T = ns.Theme
local plugins, list, queue = {}, {}, {}
local ready = false
PK.plugins = plugins

local Plugin = {}
Plugin.__index = Plugin
PK.Plugin = Plugin

-- ---------------------------------------------------------------------------
-- Safe calls
-- ---------------------------------------------------------------------------

function Plugin:Error(err)
    err = tostring(err)
    self.lastError = err
    if ns.db and ns.db.errors[self.id] ~= err then
        ns.db.errors[self.id] = err
        ns:Print(("|cffd9736b%s|r plugin error: %s"):format(self.id, err), true)
    end
end

-- Calls def[name](self, ...) under pcall. Returns ok, results...
function Plugin:Call(name, ...)
    local fn = self.def[name]
    if not fn then return false end
    local res = { n = 0 }
    local function Pack(...) res.n = select("#", ...); for i = 1, res.n do res[i] = select(i, ...) end end
    Pack(pcall(fn, self, ...))
    if not res[1] then self:Error(res[2]); return false end
    return unpack(res, 1, res.n)
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

local function Layout(id) return ns.db.plugins[id] end

function Plugin:Settings()
    if self.def.scope == "char" then
        ns.char.plugins[self.id] = ns.char.plugins[self.id] or {}
        return ns.char.plugins[self.id]
    end
    return Layout(self.id).settings
end
function Plugin:Get(key) return self:Settings()[key] end
function Plugin:Set(key, value) self:Settings()[key] = value; self:Refresh() end
function Plugin:Layout() return Layout(self.id) end
function Plugin:IsEnabled() return Layout(self.id).enabled and true or false end

function Plugin:SetEnabled(on)
    Layout(self.id).enabled = on and true or false
    if on then self:Enable() else self:Disable() end
    ns:Changed()
end

function Plugin:SetZone(zone)
    local l = Layout(self.id)
    if l.zone == zone then return end
    l.zone, l.order = zone, PK:NextOrder(zone)
    ns:Changed()
end

function Plugin:Print(msg) ns:Print("|cff8fa3b3" .. self.name .. ":|r " .. tostring(msg), true) end

-- ---------------------------------------------------------------------------
-- Events and timers (cleaned up on disable)
-- ---------------------------------------------------------------------------

function Plugin:On(event, fn)
    if not self.events then
        self.events = CreateFrame("Frame")
        self.handlers = {}
        self.events:SetScript("OnEvent", function(_, ev, ...)
            for _, h in ipairs(self.handlers[ev] or {}) do
                local ok, err = pcall(h, self, ev, ...)
                if not ok then self:Error(err) end
            end
        end)
    end
    if not self.handlers[event] then
        self.handlers[event] = {}
        if self.enabled then pcall(self.events.RegisterEvent, self.events, event) end
    end
    table.insert(self.handlers[event], fn)
end

function Plugin:Every(seconds, fn)
    self.timers = self.timers or {}
    local entry = { seconds = seconds, fn = fn }
    table.insert(self.timers, entry)
    if self.enabled then
        entry.ticker = C_Timer.NewTicker(seconds, function()
            local ok, err = pcall(fn, self)
            if not ok then self:Error(err) end
        end)
    end
    return entry
end

local function StartTimers(self)
    for event in pairs(self.handlers or {}) do pcall(self.events.RegisterEvent, self.events, event) end
    for _, entry in ipairs(self.timers or {}) do
        if not entry.ticker then
            entry.ticker = C_Timer.NewTicker(entry.seconds, function()
                local ok, err = pcall(entry.fn, self)
                if not ok then self:Error(err) end
            end)
        end
    end
end

local function StopTimers(self)
    if self.events then self.events:UnregisterAllEvents() end
    for _, entry in ipairs(self.timers or {}) do
        if entry.ticker then entry.ticker:Cancel(); entry.ticker = nil end
    end
end

-- ---------------------------------------------------------------------------
-- Series (chart data)
-- ---------------------------------------------------------------------------

function Plugin:Series(name)
    self.series = self.series or {}
    if self.series[name] then return self.series[name] end
    local cfg = (self.def.series or {})[name] or {}
    local buf
    if cfg.persist == "char" then
        ns.char.series[self.id] = ns.char.series[self.id] or {}
        ns.char.series[self.id][name] = ns.char.series[self.id][name] or {}
        buf = ns.char.series[self.id][name]
    elseif cfg.persist == "account" then
        ns.db.series[self.id] = ns.db.series[self.id] or {}
        ns.db.series[self.id][name] = ns.db.series[self.id][name] or {}
        buf = ns.db.series[self.id][name]
    else
        buf = {}
    end
    self.series[name] = buf
    return buf
end

-- Appends {time, value}. With minInterval, samples closer than that replace the last one.
function Plugin:Record(name, value, t)
    if type(value) ~= "number" then return end
    t = t or time()
    local cfg = (self.def.series or {})[name] or {}
    local buf = self:Series(name)
    local last = buf[#buf]
    if last and cfg.minInterval and t - last[1] < cfg.minInterval then
        last[2] = value
    else
        buf[#buf + 1] = { t, value }
    end
    local cap = cfg.max or 300
    while #buf > cap do table.remove(buf, 1) end
    if ns.ChartWindow then ns.ChartWindow:Notify(self) end
    if self.button and Layout(self.id).spark then ns.Bar:UpdateSpark(self) end
end

-- Points {x = time, y = value} newer than `since` (a time()), ready for a chart spec.
function Plugin:Points(name, since)
    local out = {}
    for _, s in ipairs(self:Series(name)) do
        if not since or s[1] >= since then out[#out + 1] = { s[1], s[2] } end
    end
    return out
end

-- Values only (for sparklines), the last n samples.
function Plugin:Values(name, n)
    local buf, out = self:Series(name), {}
    local start = n and math.max(1, #buf - n + 1) or 1
    for i = start, #buf do out[#out + 1] = buf[i][2] end
    return out
end

function Plugin:ShowChart(range)
    if not self.def.chart then return self:Print("this plugin has no chart.") end
    ns.ChartWindow:Open(self, range)
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

-- Batched: many Refresh calls in one frame make one update.
local dirty, scheduled = {}, false
local function Flush()
    scheduled = false
    local batch = dirty
    dirty = {}
    for p in pairs(batch) do p:Update() end
end

function Plugin:Refresh()
    if not self.enabled then return end
    dirty[self] = true
    if not scheduled then
        scheduled = true
        C_Timer.After(0, Flush)
    end
end

-- Normalizes what text() returns into segments.
local function Segments(self)
    if not self.def.text then return {} end
    local ok, value, label = self:Call("text")
    if not ok then return { { text = "<?>", color = T.red } }, nil end
    if value == nil then return {}, label end
    if type(value) ~= "table" then value = { { text = tostring(value) } } end
    return value, label
end

function Plugin:Update()
    if not self.enabled or not self.button then return end
    local segs, label = Segments(self)
    self.segments, self.labelText = segs, label or self.def.label
    ns.Bar:UpdateButton(self)
    if ns.Tooltip:IsOwned(self.button) and self.button:IsMouseOver() then PK:ShowTooltip(self) end
end

function Plugin:Flash() if self.button then ns.Bar:Flash(self) end end
function Plugin:SetBadge(n) self.badge = n; if self.button then ns.Bar:UpdateButton(self) end end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function Plugin:Enable()
    if self.enabled or not ready then return end
    self.enabled = true
    self.button = self.button or ns.Bar:CreateButton(self)
    self.button:Show()
    StartTimers(self)
    if not self.started then
        self.started = true
        for _, ev in ipairs(self.def.events or {}) do self:On(ev, function(p) p:Refresh() end) end
        if self.def.interval then self:Every(self.def.interval, function(p) p:Refresh() end) end
        self:Call("onInit")
    end
    self:Call("onEnable")
    self:Refresh()
    ns:Changed()
end

function Plugin:Disable()
    if not self.enabled then return end
    self.enabled = false
    StopTimers(self)
    if self.button then self.button:Hide() end
    self:Call("onDisable")
    ns:Changed()
end

function PK:NextOrder(zone)
    local n = 0
    for id, l in pairs(ns.db.plugins) do
        if l.zone == zone and (l.order or 0) > n then n = l.order end
    end
    return n + 1
end

local function Init(p)
    local def = p.def
    local l = ns.db.plugins[p.id] or {}
    ns.db.plugins[p.id] = l
    -- The out-of-the-box layout (Defaults.lua) first: it only fills what isn't saved yet, so a
    -- layout someone already has stays exactly as it is.
    local preset = ns.DEFAULT_LAYOUT and ns.DEFAULT_LAYOUT[p.id]
    if preset then ns.Merge(l, preset) end
    local default = def.defaultEnabled
    if type(default) == "function" then
        local ok, v = pcall(default, p)
        default = ok and v and true or false
    end
    ns.Merge(l, {
        enabled = default ~= false,
        zone = def.zone or "left",
        showIcon = def.showIcon ~= false,
        showLabel = def.showLabel and true or false,
        colored = true,
        spark = false,
        progress = true,
        progressStyle = "fill",
        progressWidth = def.progressWidth or 140,
        settings = {},
    })
    if not l.order then l.order = PK:NextOrder(l.zone) end
    if def.defaults then ns.Merge(p:Settings(), def.defaults) end
    -- An error from an old session is forgotten once the plugin loads again.
    ns.db.errors[p.id] = nil
    if l.enabled then p:Enable() end
end

function PK:Register(def)
    assert(type(def) == "table" and type(def.id) == "string" and def.id ~= "", "SimplePanel.RegisterPlugin: def.id is required")
    if plugins[def.id] then
        ns:Print("A plugin with id '" .. def.id .. "' is already registered.", true)
        return plugins[def.id]
    end
    local p = setmetatable({
        def = def, id = def.id, name = def.name or def.id, category = def.category or "Other",
        icon = def.icon, kind = def.kind or "data", hidden = def.hidden,
    }, Plugin)
    plugins[p.id] = p
    list[#list + 1] = p
    if ready then Init(p) else queue[#queue + 1] = p end
    if ns.Config and ns.Config.Refresh then ns.Config:Refresh() end
    return p
end

-- Removes a plugin entirely (LDB objects and unpinned launchers use this). Saved layout stays.
function PK:Unregister(id)
    local p = plugins[id]
    if not p then return end
    p:Disable()
    plugins[id] = nil
    for i, q in ipairs(list) do if q == p then table.remove(list, i) break end end
    ns:Changed()
end

function PK:Find(id)
    if not id or id == "" then return nil end
    if plugins[id] then return plugins[id] end
    id = id:lower()
    for _, p in ipairs(list) do
        if p.id:lower() == id or p.name:lower() == id then return p end
    end
end

-- All plugins sorted by name; hidden (internal) ones only when asked.
function PK:List(includeHidden)
    local out = {}
    for _, p in ipairs(list) do
        if includeHidden or not p.hidden then out[#out + 1] = p end
    end
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    return out
end

function PK:ResetLayout()
    -- Back to the out-of-the-box sections and order (Defaults.lua); plugins it doesn't list go to
    -- their own default section, after the others.
    for _, p in ipairs(list) do
        local l = ns.db.plugins[p.id]
        local preset = ns.DEFAULT_LAYOUT and ns.DEFAULT_LAYOUT[p.id]
        l.zone = (preset and preset.zone) or p.def.zone or "left"
        l.order = preset and preset.order or nil
    end
    for _, p in ipairs(list) do
        local l = ns.db.plugins[p.id]
        if not l.order then l.order = PK:NextOrder(l.zone) end
    end
    ns:Print("Plugin layout reset.", true)
    ns:Changed()
end

-- Runs once the bar exists (Bar.lua calls this at login).
function PK:Start()
    ready = true
    local q = queue
    queue = {}
    for _, p in ipairs(q) do Init(p) end
end

-- ---------------------------------------------------------------------------
-- Tooltip and menu
-- ---------------------------------------------------------------------------

function PK:ShowTooltip(p)
    if ns.Menu:IsOpen() then return end
    if p.def.tooltipGame then
        -- LDB-style: the plugin fills GameTooltip itself.
        local ok, err = pcall(p.def.tooltipGame, p, ns.Tooltip.GameTooltipFor(p.button))
        if not ok then p:Error(err) end
        GameTooltip:Show()
        return
    end
    if not p.def.tooltip then return end
    local tt = ns.Tooltip:Begin(p.button)
    tt:SetTitle(p.def.title or p.name, p.icon)
    p:Call("tooltip", tt)
    if p.lastError and ns.db.errors[p.id] then tt:AddDivider(); tt:AddLine("Error: " .. p.lastError, T.red, true) end
    tt:Show()
end

function PK:HideTooltip(p)
    ns.Tooltip:Hide()
    if p and p.def.tooltipGame and GameTooltip:IsOwned(p.button) then GameTooltip:Hide() end
end

-- The standard right-click menu: plugin entries, then display controls.
function PK:BuildMenu(p, m)
    local l = p:Layout()
    m:Title(p.def.title or p.name, p.icon)
    if p.def.menu then
        local before = m:Count()
        local ok, err = pcall(p.def.menu, p, m)
        if not ok then p:Error(err) end
        if m:Count() > before then m:Divider() end
    end
    if p.def.chart then
        m:Button({ text = "Open chart", icon = "Interface\\Icons\\INV_Misc_Note_01", fn = function() p:ShowChart() end })
    end
    m:Submenu({ text = "Display", build = function(sub)
        sub:Checkbox({ text = "Show icon", get = function() return l.showIcon end, set = function(v) l.showIcon = v; p:Refresh(); ns:Changed() end })
        if p.def.label or p.def.labelOptional then
            sub:Checkbox({ text = "Show label", get = function() return l.showLabel end, set = function(v) l.showLabel = v; p:Refresh(); ns:Changed() end })
        end
        if p.def.text then
            sub:Checkbox({ text = "Colored values", get = function() return l.colored end, set = function(v) l.colored = v; p:Refresh() end })
        end
        if p.def.spark then
            sub:Checkbox({ text = "Inline sparkline", get = function() return l.spark end, set = function(v) l.spark = v; p:Refresh(); ns:Changed() end })
        end
        if p.def.progress then
            sub:Header("Progress bar")
            sub:Checkbox({ text = "Show progress bar", get = function() return l.progress end, set = function(v) l.progress = v; p:Refresh() end })
            for _, s in ipairs({ { "fill", "Fill" }, { "underline", "Underline" } }) do
                sub:Radio({ text = s[2], value = s[1], get = function() return l.progressStyle end, set = function(v) l.progressStyle = v; p:Refresh() end,
                    disabled = function() return not l.progress end })
            end
            sub:Slider({ text = "Bar width", min = 80, max = 300, step = 10, get = function() return l.progressWidth end,
                set = function(v) l.progressWidth = v; p:Refresh() end })
        end
        sub:Header("Position")
        for _, z in ipairs({ { "left", "Left" }, { "center", "Center" }, { "right", "Right" } }) do
            sub:Radio({ text = z[2], value = z[1], get = function() return l.zone end, set = function(v) p:SetZone(v) end })
        end
    end })
    m:Divider()
    m:Button({ text = "Hide " .. p.name, fn = function() p:SetEnabled(false) end })
    m:Button({ text = "SimplePanel settings", fn = function() ns.Config:Show("plugins") end })
end

function PK:OpenMenu(p)
    local m = ns.Menu:New(p.button)
    self:BuildMenu(p, m)
    m:Show(p.button)
end

-- Public API
SimplePanel.RegisterPlugin = function(def) return PK:Register(def) end
SimplePanel.GetPlugin = function(id) return PK:Find(id) end
SimplePanel.UnregisterPlugin = function(id) return PK:Unregister(id) end
