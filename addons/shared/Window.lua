local addonName, ns = ...

-- The suite's window shells, on the shared widget kit (ns.Widgets: shared/Widgets.lua, or an addon's
-- own kit with the same names, like SimplePanel's). Each addon loads its own copy, so fonts come from
-- addonName (<Addon>GameFont...) and colours from ns.Palette, unless the addon passes its own.
--
-- ns.NewWindow(def): Wally's sidebar window. A draggable DIALOG frame (800 x 560) with its position
-- saved in ns.char.window, closed by Escape; a 38px logo, the title in the accent colour and a muted
-- subtitle; an "X" button; a 165px sidebar of 147 x 40 icon buttons, the selected one with a 3px
-- accent stripe; the version in the sidebar's corner; one page per tab right of the sidebar.
--   def = {
--     name = "WallyWindow",                  -- global frame name (UISpecialFrames needs one)
--     title, subtitle, icon (default ns.ICON),
--     width, height (800, 560),
--     active = "junk",                       -- the tab shown first
--     tabs = { { key, label, icon,           -- icon: an Interface\Icons name, a texture path or a file ID
--                build = fn(page, win), refresh = fn(page, win),
--                onClick = fn(win),          -- instead of showing a page (a Settings button)
--                hint = { title, body },
--                optional = true,            -- only shown when a page builder is registered for key
--                when = fn() } },            -- only shown when it returns true
--     build = fn(win),                       -- builds the addon's own pages (win:NewPage), before each tab's build
--     refresh = fn(win),                     -- the addon's full refresh: on show, after Show and after a tab click
--                                            --   (default win:Refresh(): the active page's Refresh / tab.refresh)
--     tabClickRefresh = false,               -- a tab click only shows the tab (onTab refreshes instead)
--     onTab = fn(win, key),                  -- runs after every tab change
--     pluginsBefore = "settings",            -- where win:AddTab() tabs go (default: at the end)
--     sideNote = text | fn(win),             -- muted tips under the tab buttons (fn may return nil)
--     decorate = fn(win, side, count),       -- adds the addon's own sidebar text (count = tabs shown)
--     buttons = { { text, width, height, onClick, hint = { title, body } } },     -- header, left of "X"
--     sideButtons = { { text, width, height, y, onClick, hint = { title, body } } }, -- bottom of the sidebar
--     tabHeight, tabGap, tabTop (40, 6, 12),
--     versionY = -450 (height - 110), versionBottom = n,  -- the version label at TOPLEFT 12, versionY,
--                                            --   or at BOTTOMLEFT 12, n when versionBottom is set
--     relPoint = true,                       -- also save the anchor's relative point
--     fonts = { large, small },              -- default <Addon>GameFontNormalLarge / <Addon>GameFontHighlightSmall
--     theme = { panel, button, idle, active, version },  -- {r,g,b} tables, read when drawn
--                                            --   panel: sidebar; button: a tab button at rest (mouse left);
--                                            --   idle / active: a tab's colour when another / it is selected
--   }
-- The window is built on first Show / Toggle / Build. win.frame, win.side, win.pages[key],
-- win.tabs[key] (the buttons), win.headerButtons, win.sideButtons, win.plugins, win.builders.
--   win:Show(tab)  win:Hide()  win:Toggle()  win:IsShown()  win:Active()  win:Build()
--   win:ShowTab(key)  win:Refresh()  win:RefreshPage(key)  win:NewPage(key)
--   win:RegisterPage(key, builder)   -- a page file's builder(page), run when the window is built
--   win:AddTab(tab)                  -- a plugin tab; false once the window is built (shows after /reload)
--
-- W.SubTabs(host, def): a row of sub-tab buttons over a set of pages (Wealth Planner's bar).
-- W.Section(p, text, x, y, width): a heading with a thin rule under it.
-- W.MakeWindow(name, width, height, title, pos): BattleRecap's title-bar window.

local W = ns.Widgets or {}
ns.Widgets = W
W.style = W.style or {}

local ICON_DIR = "Interface\\Icons\\"
local FONT_LARGE = addonName .. "GameFontNormalLarge"
local FONT_NORMAL = addonName .. "GameFontNormal"
local FONT_SMALL = addonName .. "GameFontHighlightSmall"

-- Sets a tab icon: an Interface\Icons name (cropped), a texture path (as is) or a file ID (cropped).
local function SetTabIcon(tex, icon)
    if type(icon) == "string" and icon:find("[\\/]") then
        tex:SetTexture(icon)
    elseif type(icon) == "string" then
        tex:SetTexture(ICON_DIR .. icon); tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        tex:SetTexture(icon); tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

local Window = {}
Window.__index = Window

function ns.NewWindow(def)
    local win = setmetatable({ def = def, pages = {}, tabs = {}, builders = {}, plugins = {},
        headerButtons = {}, sideButtons = {}, active = def.active }, Window)
    local PAL = ns.Palette or {}
    local t = def.theme or {}
    win.theme = {
        panel = t.panel or PAL.panel, button = t.button or PAL.button,
        idle = t.idle or { 0.075, 0.105, 0.13 }, active = t.active or { 0.09, 0.15, 0.17 },
        version = t.version or { 0.38, 0.50, 0.57 },
    }
    win.fonts = { large = def.fonts and def.fonts.large or FONT_LARGE, small = def.fonts and def.fonts.small or FONT_SMALL }
    return win
end

function Window:RegisterPage(key, builder) self.builders[key] = builder end

function Window:AddTab(tab)
    if self.frame then return false end
    tab.plugin = true
    self.plugins[#self.plugins + 1] = tab
    return true
end

function Window:NewPage(key)
    local p = CreateFrame("Frame", nil, self.frame)
    p:SetPoint("TOPLEFT", 196, -76); p:SetPoint("BOTTOMRIGHT", -18, 18)
    p:Hide(); self.pages[key] = p
    return p
end

-- The tabs to show, in order: plugin tabs go before def.pluginsBefore (or last).
function Window:ShownTabs()
    local def, out = self.def, {}
    local function Add(tab)
        if tab.optional and not self.builders[tab[1]] then return end
        if tab.when and not tab.when() then return end
        out[#out + 1] = tab
    end
    local placed = false
    for _, tab in ipairs(def.tabs) do
        if def.pluginsBefore and tab[1] == def.pluginsBefore then
            for _, p in ipairs(self.plugins) do Add(p) end
            placed = true
        end
        Add(tab)
    end
    if not placed then for _, p in ipairs(self.plugins) do Add(p) end end
    return out
end

function Window:ShowTab(key)
    self.active = key
    for k, p in pairs(self.pages) do p:SetShown(k == key) end
    local th = self.theme
    for k, b in pairs(self.tabs) do
        b.selected:SetShown(k == key)
        local c = k == key and th.active or th.idle
        b:SetBackdropColor(c[1], c[2], c[3], 1)
    end
    if self.def.onTab then self.def.onTab(self, key) end
end

-- The addon's full refresh (def.refresh), else the active page's.
function Window:Update()
    if self.def.refresh then self.def.refresh(self) else self:Refresh() end
end

function Window:RefreshPage(key)
    local p = self.pages[key]
    if not (p and self.frame and self.frame:IsShown()) then return end
    if p.Refresh then p.Refresh()
    elseif p.tab and p.tab.refresh then p.tab.refresh(p, self) end
end

function Window:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    self:RefreshPage(self.active)
end

local function AddHint(b, hint)
    if hint and W.Hint then W.Hint(b, hint[1], hint[2]) end
end

function Window:Build()
    if self.frame then return self.frame end
    local def, th, fonts = self.def, self.theme, self.fonts
    local Label, Muted, MakeButton, SetBackdrop = W.Label, W.Muted, W.MakeButton, W.SetBackdrop
    local ACCENT = W.ACCENT
    local width, height = def.width or 800, def.height or 560

    local frame = CreateFrame("Frame", def.name, UIParent, "BackdropTemplate")
    self.frame = frame
    frame:SetSize(width, height); frame:SetFrameStrata("DIALOG"); frame:SetToplevel(true)
    frame:SetClampedToScreen(true); frame:SetMovable(true); frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton"); SetBackdrop(frame, 0.985)
    local w = ns.char.window or {}
    frame:SetPoint(w.point or "CENTER", UIParent, w.relPoint or w.point or "CENTER", w.x or 0, w.y or 0)
    frame:SetScript("OnDragStart", function(f) f:StartMoving() end)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        local point, _, relPoint, x, y = f:GetPoint()
        ns.char.window = def.relPoint and { point = point, relPoint = relPoint, x = x, y = y } or { point = point, x = x, y = y }
    end)
    frame:SetScript("OnShow", function() self:Update() end)
    if def.name then tinsert(UISpecialFrames, def.name) end

    local logo = frame:CreateTexture(nil, "ARTWORK"); logo:SetSize(38, 38)
    logo:SetPoint("TOPLEFT", 20, -17); logo:SetTexture(def.icon or ns.ICON)
    self.title = Label(frame, def.title or addonName, fonts.large, 70, -20)
    self.title:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    self.subtitle = Muted(Label(frame, def.subtitle or "", fonts.small, 70, -42))
    local close = MakeButton(frame, "X", 28, 26); close:SetPoint("TOPRIGHT", -18, -18)
    close:SetScript("OnClick", function() frame:Hide() end)
    self.close = close
    local anchor = close
    for i, d in ipairs(def.buttons or {}) do
        local b = MakeButton(frame, d[1] or d.text, d.width or 80, d.height or 26)
        b:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
        b:SetScript("OnClick", function() d.onClick(self) end)
        AddHint(b, d.hint)
        self.headerButtons[i], anchor = b, b
    end

    local side = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    side:SetPoint("TOPLEFT", 14, -74); side:SetPoint("BOTTOMLEFT", 14, 14); side:SetWidth(165)
    SetBackdrop(side); side:SetBackdropColor(th.panel[1], th.panel[2], th.panel[3], 1)
    self.side = side
    local tabH, gap, top = def.tabHeight or 40, def.tabGap or 6, def.tabTop or 12
    local shown = self:ShownTabs()
    for i, d in ipairs(shown) do
        local key = d[1]
        local b = MakeButton(side, d[2], 147, tabH); b:SetPoint("TOPLEFT", 9, -top - (i - 1) * (tabH + gap))
        b.text:ClearAllPoints(); b.text:SetPoint("LEFT", 40, 0)
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(23, 23); b.icon:SetPoint("LEFT", 9, 0)
        SetTabIcon(b.icon, d[3])
        b.selected = b:CreateTexture(nil, "OVERLAY"); b.selected:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
        b.selected:SetPoint("TOPLEFT"); b.selected:SetPoint("BOTTOMLEFT"); b.selected:SetWidth(3)
        b:SetScript("OnLeave", function(btn)
            if self.active ~= key then btn:SetBackdropColor(th.button[1], th.button[2], th.button[3], 1) end
        end)
        if d.onClick then
            b:SetScript("OnClick", function() d.onClick(self) end)
        else
            b:SetScript("OnClick", function()
                self:ShowTab(key)
                if def.tabClickRefresh ~= false then self:Update() end
            end)
        end
        AddHint(b, d.hint)
        self.tabs[key] = b
    end
    self.tabCount = #shown
    local note = type(def.sideNote) == "function" and def.sideNote(self) or def.sideNote
    if type(note) == "string" then
        self.sideNote = Muted(Label(side, note, fonts.small, 12, -14 - #shown * (tabH + gap), 145))
    end
    if def.decorate then def.decorate(self, side, #shown) end
    for i, d in ipairs(def.sideButtons or {}) do
        local b = MakeButton(side, d[1] or d.text, d.width or 147, d.height or 26)
        b:SetPoint("BOTTOMLEFT", d.x or 9, d.y or 30)
        b:SetScript("OnClick", function() d.onClick(self) end)
        AddHint(b, d.hint)
        self.sideButtons[i] = b
    end
    local version
    if def.versionBottom then
        version = Label(side, "v" .. ns.VERSION, fonts.small, 12, 0, 145)
        version:ClearAllPoints(); version:SetPoint("BOTTOMLEFT", 12, def.versionBottom)
    else
        version = Label(side, "v" .. ns.VERSION, fonts.small, 12, def.versionY or -(height - 110), 145)
    end
    version:SetTextColor(th.version[1], th.version[2], th.version[3])
    self.version = version

    if def.build then def.build(self) end
    for _, d in ipairs(shown) do
        local build = d.build or (not d.onClick and self.builders[d[1]])
        if build then
            local p = self:NewPage(d[1])
            p.tab = d
            if d.plugin then
                local ok, err = pcall(build, p, self)
                if not ok then ns:Print("A plugin's tab failed to build: " .. tostring(err), true) end
            else
                build(p, self)
            end
        end
    end
    self:ShowTab(self.active); frame:Hide()
    return frame
end

function Window:Show(tab)
    self:Build()
    if tab then self:ShowTab(tab) end
    self.frame:Show(); self:Update()
end

function Window:Hide() if self.frame then self.frame:Hide() end end

function Window:Toggle()
    self:Build()
    self.frame:SetShown(not self.frame:IsShown())
end

function Window:IsShown() return self.frame and self.frame:IsShown() or false end
function Window:Active() return self.active end

-- ---------------------------------------------------------------------------
-- Sub-tabs
-- ---------------------------------------------------------------------------
-- W.SubTabs(host, def): buttons across the top of host, one page under them per tab.
--   def = { tabs = { { key, label, hint } }, width = 586, height = 24, gap = 3, top = -34,
--           active = key, builders = { [key] = fn(page) } (run inside pcall),
--           onClick = fn(key) (after the sub-tab is shown) }
-- bar:Show(key) (ignores unknown keys)  bar:Active()  bar:Refresh() (the active page's Refresh)
-- bar.pages[key], bar.buttons[key]
function W.SubTabs(host, def)
    local bar = { pages = {}, buttons = {}, active = def.active }
    function bar:Show(key)
        if not self.pages[key] then return end
        self.active = key
        for k, p in pairs(self.pages) do p:SetShown(k == key) end
        for k, b in pairs(self.buttons) do W.SetActive(b, k == key) end
    end
    function bar:Active() return self.active end
    function bar:Refresh()
        local p = self.pages[self.active]
        if p and p.Refresh then p.Refresh() end
    end
    local n, gap = #def.tabs, def.gap or 3
    local bw = math.floor(((def.width or 586) - (n - 1) * gap) / n)
    for i, d in ipairs(def.tabs) do
        local b = W.MakeButton(host, d[2], bw, def.height or 24); b:SetPoint("TOPLEFT", (i - 1) * (bw + gap), 0)
        b:SetScript("OnClick", function() bar:Show(d[1]); if def.onClick then def.onClick(d[1]) end end)
        if d[3] then W.Hint(b, d[2], d[3]) end
        bar.buttons[d[1]] = b
    end
    local builders = def.builders or {}
    for _, d in ipairs(def.tabs) do
        local p = CreateFrame("Frame", nil, host)
        p:SetPoint("TOPLEFT", 0, def.top or -34); p:SetPoint("BOTTOMRIGHT", 0, 0)
        p:Hide(); bar.pages[d[1]] = p
        if builders[d[1]] then
            local ok, err = pcall(builders[d[1]], p)
            if not ok then ns:Print("The " .. d[2] .. " page failed to build: " .. tostring(err), true) end
        end
    end
    bar:Show(bar.active)
    return bar
end

-- ---------------------------------------------------------------------------
-- Section heading
-- ---------------------------------------------------------------------------
-- A heading with a thin rule under it, across the parent (or width wide). Returns the heading and
-- the rule. W.style.sectionFont / W.style.sectionRule change the font and rule colour.
function W.Section(p, text, x, y, width)
    local fs = W.Label(p, text, W.style.sectionFont or FONT_NORMAL, x, y)
    local c = W.style.sectionRule or (ns.Palette and ns.Palette.border)
    local rule = p:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(c[1], c[2], c[3], 1); rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", x, y - 17)
    if width then rule:SetWidth(width) else rule:SetPoint("TOPRIGHT", 0, y - 17) end
    return fs, rule
end

-- ---------------------------------------------------------------------------
-- Title-bar window (BattleRecap's)
-- ---------------------------------------------------------------------------
-- A movable dark window with a title band, an accent line, an icon, a title and subtitle and a close
-- button. pos is the saved-position table (point, x, y). f:RestorePosition() puts it back there.
function W.MakeWindow(name, width, height, title, pos)
    local PAL, ACCENT = ns.Palette, W.ACCENT
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(width, height)
    W.SetBackdrop(f, 0.96)
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
    f.title = W.Label(f, title, FONT_NORMAL, 28, -7)
    f.subtitle = W.Label(f, "", FONT_SMALL, 0, -8)
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
