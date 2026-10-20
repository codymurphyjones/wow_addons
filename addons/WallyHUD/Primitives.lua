local _, ns = ...
local T = ns.T

-- The shared building blocks: fonts, panels, hairlines, underline tabs, ghost icon buttons. Our
-- addons call these when WallyHUD is there (WallyHUD.Panel(frame) and so on) and keep their own
-- look when it isn't.

-- ---------------------------------------------------------------------------------------------
-- Type: one family, two weights, four roles
-- ---------------------------------------------------------------------------------------------

local function Font(name, size, face)
    local f = CreateFont(name)
    f:SetFont(face or T.font, size, "")
    f:SetShadowColor(WallyHUD.RGBA(T.fontShadow))
    f:SetShadowOffset(1, -1)
    return f
end
-- Labels: 11px, set in capitals by Upper() below. Body: 12px. Numbers: 13px. Titles: 13px in the
-- strong weight.
WallyHUD.FontLabel = Font("WallyHUDFontLabel", 11)
WallyHUD.FontBody = Font("WallyHUDFontBody", 12)
WallyHUD.FontNumber = Font("WallyHUDFontNumber", 13)
WallyHUD.FontTitle = Font("WallyHUDFontTitle", 13, T.fontStrong)
WallyHUD.FontLabel:SetTextColor(WallyHUD.RGBA(T.text.secondary))
WallyHUD.FontTitle:SetTextColor(WallyHUD.RGBA(T.text.primary))
WallyHUD.FontBody:SetTextColor(WallyHUD.RGBA(T.text.primary))
WallyHUD.FontNumber:SetTextColor(WallyHUD.RGBA(T.text.primary))

-- Our addons' windows draw with their own copies of the game fonts (each addon's Fonts.lua puts
-- them in WallyHUD_Fonts as { font = copy, source = "GameFontNormal" }). Here they take the suite's
-- face, keeping the game's size, outline and colour: the gold "Normal" fonts (titles, headings)
-- and the large ones in the strong weight, everything else in the text weight. The game's own
-- windows keep their fonts. The shared look setting turns this off (a /reload).
local function Weight(source)
    if source:find("Large") or source:find("Huge") then return "semibold" end
    if source:find("^GameFontNormal") then return "semibold" end
    return "medium"
end

function WallyHUD.SuiteFont(entry)
    if ns.db and ns.db.suiteLook == false then return end
    local font, source = entry.font, entry.source or ""
    local _, size, flags = font:GetFont()
    if size then font:SetFont(WallyHUD.Face(Weight(source)), size, flags or "") end
end

-- The face for text an addon sets by file (nameplates, bag badges, signs), or nil when the shared
-- look is off: callers keep their own font then. WallyHUD.SuiteFace("bold") or STANDARD_TEXT_FONT.
function WallyHUD.SuiteFace(weight)
    if ns.db and ns.db.suiteLook == false then return nil end
    return WallyHUD.Face(weight)
end

WallyHUD_Fonts = WallyHUD_Fonts or {}
ns:OnLoad(function()
    for _, entry in ipairs(WallyHUD_Fonts) do WallyHUD.SuiteFont(entry) end
end)

-- A label as the design writes it: capitals, a little apart.
function WallyHUD.Upper(text)
    return tostring(text or ""):upper()
end

-- ---------------------------------------------------------------------------------------------
-- Surfaces
-- ---------------------------------------------------------------------------------------------

local WHITE = "Interface\\Buttons\\WHITE8X8"
WallyHUD.WHITE = WHITE

-- A panel: a see-through surface with a 1px hairline. kind: "base" (HUD panels, the default),
-- "raised" (windows, popovers, tooltips) or "sunken" (wells, tracks). The frame needs the
-- BackdropTemplate (or SetBackdrop).
function WallyHUD.Panel(frame, kind)
    if not frame.SetBackdrop then Mixin(frame, BackdropTemplateMixin) end
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    frame:SetBackdropColor(WallyHUD.RGBA(T.surface[kind or "base"] or T.surface.base))
    frame:SetBackdropBorderColor(WallyHUD.RGBA(T.border.hairline))
end

-- The strong hairline while the mouse is over a frame (focus/hover only).
function WallyHUD.HoverEdge(frame)
    frame:HookScript("OnEnter", function(self) self:SetBackdropBorderColor(WallyHUD.RGBA(T.border.strong)) end)
    frame:HookScript("OnLeave", function(self) self:SetBackdropBorderColor(WallyHUD.RGBA(T.border.hairline)) end)
end

-- A 1px hairline texture across the bottom (or top) of a frame.
function WallyHUD.Hairline(frame, where)
    local line = frame:CreateTexture(nil, "BORDER")
    line:SetColorTexture(WallyHUD.RGBA(T.border.hairline))
    line:SetHeight(1)
    line:SetPoint(where == "TOP" and "TOPLEFT" or "BOTTOMLEFT")
    line:SetPoint(where == "TOP" and "TOPRIGHT" or "BOTTOMRIGHT")
    return line
end

-- ---------------------------------------------------------------------------------------------
-- Tabs: one signal for one state
-- ---------------------------------------------------------------------------------------------

-- Makes a tab button an underline tab: no fill, no border; label in capitals; the active tab is
-- primary text with a 2px accent underline, the others secondary text. Call WallyHUD.SetTab(tab,
-- active) whenever it changes. label: the tab's FontString.
function WallyHUD.UnderlineTab(tab, label)
    if tab.SetBackdrop then tab:SetBackdrop(nil) end
    if not tab.wallyUnderline then
        tab.wallyUnderline = tab:CreateTexture(nil, "OVERLAY")
        tab.wallyUnderline:SetColorTexture(WallyHUD.RGBA(T.accent))
        tab.wallyUnderline:SetHeight(2)
        tab.wallyUnderline:SetPoint("BOTTOMLEFT", 4, 0)
        tab.wallyUnderline:SetPoint("BOTTOMRIGHT", -4, 0)
    end
    tab.wallyLabel = label
    if label then label:SetFontObject(WallyHUD.FontLabel) end
end

function WallyHUD.SetTab(tab, active)
    if tab.wallyUnderline then tab.wallyUnderline:SetShown(active and true or false) end
    local label = tab.wallyLabel
    if label then
        label:SetTextColor(WallyHUD.RGBA(active and T.text.primary or T.text.secondary))
        label:SetText(WallyHUD.Upper(label:GetText()))
    end
end

-- ---------------------------------------------------------------------------------------------
-- Ghost icon buttons (the minimap buttons, the HUD's icon row)
-- ---------------------------------------------------------------------------------------------

-- An icon in secondary text colour, desaturated; full colour with an accent tint under the mouse.
function WallyHUD.GhostIcon(button, icon)
    if not icon then return end
    local function Rest()
        if icon.SetDesaturated then icon:SetDesaturated(true) end
        icon:SetVertexColor(WallyHUD.RGBA(T.text.secondary))
    end
    local function Hot()
        if icon.SetDesaturated then icon:SetDesaturated(false) end
        icon:SetVertexColor(1, 1, 1, 1)
    end
    Rest()
    button:HookScript("OnEnter", Hot)
    button:HookScript("OnLeave", Rest)
end
