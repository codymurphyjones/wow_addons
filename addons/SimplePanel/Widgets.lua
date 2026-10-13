local _, ns = ...

-- Shared widgets and the theme (same look as Wally and Quartermaster).
local W = {}
ns.Widgets = W

local WHITE = "Interface\\Buttons\\WHITE8X8"
local ACCENT = { 0.33, 0.92, 0.78 }
local MUTED = { 0.52, 0.64, 0.70 }
local UNKNOWN_ICON = 134400
W.WHITE, W.ACCENT, W.MUTED, W.UNKNOWN_ICON = WHITE, ACCENT, MUTED, UNKNOWN_ICON

-- One palette for the bar, menus, tooltips and charts. Plugins read it through SimplePanel.Theme.
local T = {
    white = WHITE,
    accent = ACCENT,
    muted = MUTED,
    base = { 0.035, 0.045, 0.060 },
    side = { 0.045, 0.065, 0.085 },
    row = { 0.055, 0.08, 0.10 },
    rowHover = { 0.08, 0.14, 0.16 },
    button = { 0.075, 0.105, 0.13 },
    buttonHover = { 0.10, 0.19, 0.21 },
    active = { 0.09, 0.15, 0.17 },
    well = { 0.02, 0.03, 0.04 },
    border = { 0.16, 0.24, 0.29 },
    track = { 0.12, 0.16, 0.19 },
    text = { 0.85, 0.9, 0.95 },
    version = { 0.38, 0.50, 0.57 },
    yellow = { 1, 0.82, 0.30 },
    red = { 0.85, 0.45, 0.42 },
    green = { 0.35, 0.95, 0.55 },
    orange = { 1, 0.60, 0.20 },
    blue = { 0.40, 0.80, 1 },
    hex = {
        accent = "|cff55d6be", muted = "|cff8fa3b3", yellow = "|cffffd24d",
        red = "|cffd9736b", green = "|cff59f28c", orange = "|cffff9933", white = "|cffffffff",
    },
}
-- Series colors for charts, in order.
T.series = { ACCENT, T.yellow, T.blue, T.orange, T.green, T.red, { 0.75, 0.55, 1 }, { 0.9, 0.9, 0.9 } }
ns.Theme = T
SimplePanel.Theme = T

function W.Hex(c)
    return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end
function W.Color(text, c) return W.Hex(c) .. tostring(text) .. "|r" end

-- ---------------------------------------------------------------------------
-- Color schemes (Appearance tab). "wally" is the look above; the others keep the same flat style
-- and only swap the accent and the tint of the dark neutrals.
-- ---------------------------------------------------------------------------

local NEUTRALS = { "accent", "base", "side", "row", "rowHover", "button", "buttonHover", "active", "well", "border", "track" }
local WALLY = {}
for _, k in ipairs(NEUTRALS) do WALLY[k] = { T[k][1], T[k][2], T[k][3] } end

W.SCHEMES = {
    { id = "wally", name = "Wally" },
    { id = "slate", name = "Slate", accent = { 0.56, 0.72, 1 }, base = { 0.040, 0.045, 0.056 } },
    { id = "jade", name = "Jade", accent = { 0.42, 0.90, 0.48 }, base = { 0.034, 0.050, 0.040 } },
    { id = "violet", name = "Violet", accent = { 0.72, 0.58, 1 }, base = { 0.046, 0.040, 0.062 } },
    { id = "ember", name = "Ember", accent = { 1, 0.58, 0.28 }, base = { 0.056, 0.042, 0.036 } },
    { id = "gold", name = "Gold", accent = { 1, 0.82, 0.36 }, base = { 0.050, 0.046, 0.036 } },
    { id = "crimson", name = "Crimson", accent = { 0.95, 0.40, 0.44 }, base = { 0.056, 0.036, 0.042 } },
    { id = "mono", name = "Mono", accent = { 0.88, 0.90, 0.92 }, base = { 0.040, 0.040, 0.042 } },
}

local function Mix(a, b, t) return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t } end
local function Scale(c, k) return { math.min(1, c[1] * k), math.min(1, c[2] * k), math.min(1, c[3] * k) } end

-- The full palette for a scheme, built from its accent and base the same way Wally's relate.
local function Palette(s)
    if not s.base then return WALLY end
    local b, a = s.base, s.accent
    local pal = { accent = a, base = b, side = Scale(b, 1.35), row = Scale(b, 1.65), button = Scale(b, 2.15),
        well = Scale(b, 0.6), border = Scale(b, 4.6), track = Scale(b, 3.3) }
    pal.rowHover = Mix(pal.row, a, 0.12)
    pal.buttonHover = Mix(pal.button, a, 0.16)
    pal.active = Mix(pal.button, a, 0.08)
    return pal
end

function W.Scheme(id)
    for _, s in ipairs(W.SCHEMES) do if s.id == id then return s end end
    return W.SCHEMES[1]
end
function W.SchemeAccent(s) return s.accent or WALLY.accent end

-- ---------------------------------------------------------------------------
-- Fonts: SimplePanel's own copies of the game fonts, so Appearance > Text size scales them live.
-- ---------------------------------------------------------------------------

local FONTS = {
    SimplePanelFontSmall = "GameFontHighlightSmall",
    SimplePanelFont = "GameFontHighlight",
    SimplePanelFontTitle = "GameFontNormal",
    SimplePanelFontHeader = "GameFontNormalSmall",
    SimplePanelFontLarge = "GameFontNormalLarge",
    SimplePanelFontDisabled = "GameFontDisableSmall",
}
local fontBase = {}
for name, source in pairs(FONTS) do
    local f = CreateFont(name)
    if _G[source] then f:CopyFontObject(_G[source]) end
    fontBase[name] = { f:GetFont() }
end

local function ApplyFontScale(scale)
    for name, base in pairs(fontBase) do
        if base[1] then _G[name]:SetFont(base[1], base[2] * scale, base[3] or "") end
    end
end

-- Puts the saved scheme, class accent and text size into the theme. The theme tables change in
-- place, so anything that reads them when it draws picks the new colors up.
function W.ApplyDesign()
    local o = ns.db.options
    local pal = Palette(W.Scheme(o.scheme))
    for _, k in ipairs(NEUTRALS) do
        local c = pal[k]
        T[k][1], T[k][2], T[k][3] = c[1], c[2], c[3]
    end
    if o.classAccent then
        local _, class = UnitClass("player")
        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then ACCENT[1], ACCENT[2], ACCENT[3] = c.r, c.g, c.b end
    end
    T.hex.accent = W.Hex(ACCENT)
    ns.PREFIX = T.hex.accent .. "SimplePanel|r"
    ApplyFontScale(ns.Clamp(o.textScale, 0.8, 1.4))
    if ns.Bar and ns.Bar.ApplyTheme then ns.Bar:ApplyTheme() end
end
ns:OnLoad(W.ApplyDesign)
ns:On("PLAYER_LOGIN", function() if ns.db.options.classAccent then W.ApplyDesign() end end)

-- Panels (window, menus, tooltips, drawer, charts) share one background opacity.
local function PanelAlpha() return ns.db and ns.Clamp(ns.db.options.panelAlpha, 0.3, 1) or 1 end

-- Frames given an alpha are panels (window, menu levels, tooltip, drawer, chart windows); they are
-- remembered so Appearance can repaint them.
local panels = setmetatable({}, { __mode = "k" })

function W.SetBackdrop(f, alpha)
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(T.base[1], T.base[2], T.base[3], (alpha or 1) * PanelAlpha())
    f:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
    if alpha then panels[f] = alpha end
end

function W.RepaintPanels()
    for f, alpha in pairs(panels) do
        f:SetBackdropColor(T.base[1], T.base[2], T.base[3], alpha * PanelAlpha())
        f:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
    end
end
local SetBackdrop = W.SetBackdrop

function W.Label(parent, text, font, x, y, width)
    local t = parent:CreateFontString(nil, "OVERLAY", font or "SimplePanelFont")
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
    b:SetBackdropColor(T.button[1], T.button[2], T.button[3], 1)
    b.text = b:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall")
    b.text:SetPoint("CENTER"); b.text:SetText(text)
    b:SetScript("OnEnter", function(self) self:SetBackdropColor(T.buttonHover[1], T.buttonHover[2], T.buttonHover[3], 1) end)
    b:SetScript("OnLeave", function(self) self:SetBackdropColor(T.button[1], T.button[2], T.button[3], 1) end)
    return b
end
local MakeButton = W.MakeButton

-- Marks one button of a group as active (accent border).
function W.SetActive(b, active)
    if active then b:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    else b:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1) end
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
    b.label = b:CreateFontString(nil, "OVERLAY", "SimplePanelFontSmall")
    b.label:SetPoint("LEFT", b, "RIGHT", 3, 0); b.label:SetText(text)
    return b
end

function W.MakeEditBox(parent, width, placeholder)
    local b = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    b:SetSize(width or 160, 26)
    SetBackdrop(b); b:SetBackdropColor(T.well[1], T.well[2], T.well[3], 1)
    b:SetFontObject("SimplePanelFontSmall"); b:SetJustifyH("LEFT")
    b:SetAutoFocus(false); b:SetTextInsets(8, 8, 2, 2)
    b.placeholder = b:CreateFontString(nil, "OVERLAY", "SimplePanelFontDisabled")
    b.placeholder:SetPoint("LEFT", 8, 0); b.placeholder:SetText(placeholder or "")
    local function UpdatePlaceholder(self) self.placeholder:SetShown(self:GetText() == "" and not self:HasFocus()) end
    b:SetScript("OnEditFocusGained", UpdatePlaceholder)
    b:SetScript("OnEditFocusLost", UpdatePlaceholder)
    b:HookScript("OnTextChanged", UpdatePlaceholder)
    b:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    b:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return b
end

-- Flat slider: a track, an accent fill and a square thumb. onChange(value) fires while dragging.
function W.MakeSlider(parent, width, minV, maxV, step, onChange)
    local s = CreateFrame("Slider", nil, parent, "BackdropTemplate")
    s:SetSize(width or 160, 12)
    s:SetOrientation("HORIZONTAL"); s:SetMinMaxValues(minV, maxV); s:SetValueStep(step or 1)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    SetBackdrop(s); s:SetBackdropColor(T.track[1], T.track[2], T.track[3], 1)
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1); thumb:SetSize(8, 14)
    s:SetThumbTexture(thumb)
    s.fill = s:CreateTexture(nil, "ARTWORK")
    s.fill:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.35)
    s.fill:SetPoint("TOPLEFT", 1, -1); s.fill:SetPoint("BOTTOMLEFT", 1, 1)
    local function UpdateFill(self, v)
        local lo, hi = self:GetMinMaxValues()
        local pct = hi > lo and (v - lo) / (hi - lo) or 0
        self.fill:SetWidth(math.max(0.01, (self:GetWidth() - 2) * pct))
    end
    s:SetScript("OnValueChanged", function(self, v)
        UpdateFill(self, v)
        if not self.silent and onChange then onChange(v) end
    end)
    function s:SetSilently(v) self.silent = true; self:SetValue(v); UpdateFill(self, v); self.silent = false end
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(self, delta) self:SetValue(self:GetValue() + delta * (step or 1)) end)
    return s
end

-- A section heading with a thin rule under it.
function W.Section(p, text, x, y, width)
    Label(p, text, "SimplePanelFontTitle", x, y)
    local rule = p:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(T.border[1], T.border[2], T.border[3], 1); rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", x, y - 17)
    if width then rule:SetWidth(width) else rule:SetPoint("TOPRIGHT", 0, y - 17) end
    return rule
end

-- Square icon cropped like Wally's tab icons. Accepts a file ID, a path or an atlas ("atlas:name").
function W.SetIcon(tex, icon)
    if type(icon) == "string" and icon:sub(1, 6) == "atlas:" then
        -- SetAtlas sets the atlas's own tex coords; resetting them afterwards would show the whole sheet.
        tex:SetTexCoord(0, 1, 0, 1); tex:SetAtlas(icon:sub(7))
    else
        tex:SetTexture(icon or UNKNOWN_ICON); tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

-- Plain ACCENT-bordered panel used for drawers and windows.
function W.MakePanel(parent, name, alpha)
    local f = CreateFrame("Frame", name, parent or UIParent, "BackdropTemplate")
    SetBackdrop(f, alpha or 0.97)
    return f
end

-- Yes/No question (same dialog Wally uses for anything destructive).
StaticPopupDialogs["SIMPLEPANEL_CONFIRM"] = {
    text = "%s", button1 = YES or "Yes", button2 = NO or "No",
    OnAccept = function(_, data) if data and data.fn then data.fn() end end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, showAlert = 1, preferredIndex = 3,
}
function W.Confirm(text, fn) StaticPopup_Show("SIMPLEPANEL_CONFIRM", text, nil, { fn = fn }) end

-- A scrolling page body. Returns the scroll frame and the child to build into.
function W.ScrollArea(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, 0); scroll:SetPoint("BOTTOMRIGHT", -26, 0)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(500, 10)
    scroll:SetScrollChild(child)
    scroll:SetScript("OnSizeChanged", function(_, w) child:SetWidth(w) end)
    return scroll, child
end

-- Multi-line text box in a well, like Wally's import/export box. Returns the box and its edit box.
function W.MakeTextBox(parent, width, height)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetSize(width, height)
    SetBackdrop(box); box:SetBackdropColor(T.well[1], T.well[2], T.well[3], 1)
    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6); scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetFontObject("SimplePanelFontSmall")
    edit:SetWidth(width - 36); edit:SetHeight(height - 10)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(edit)
    box:EnableMouse(true); box:SetScript("OnMouseDown", function() edit:SetFocus() end)
    return box, edit
end

W.MakeButton, W.Label, W.Muted = MakeButton, Label, Muted
