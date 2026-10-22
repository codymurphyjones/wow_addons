local _, ns = ...

-- WallyChat: the game's chat windows in the suite's look (WallyHUD's design tokens and its font,
-- Roboto Condensed). Skin.lua restyles the windows, their tabs and the edit box; Toolbar.lua puts a
-- quiet row of buttons where the game's three sat (friends, channels, the chat menu) with Full
-- screen beside them; Links.lua makes web addresses in chat clickable; FullScreen.lua shows a chat
-- window over the whole screen below SimplePanel's bar, every line selectable and copyable.
-- Without WallyHUD the same colours are used (copied below) and the game's chat font is kept.
WallyChat = WallyChat or {}
ns.VERSION = "0.1.0"

-- Events and saved variables: the shared Core.lua (addons/shared). Print stays here.
ns.SAVED = { db = "WallyChatDB" }

ns.DEFAULTS = {
    weight = "medium",    -- the chat text's weight in Roboto Condensed: regular, medium, semibold, bold
    background = 45,      -- the chat panel's opacity, percent
    plainCopy = false,    -- full screen: plain text (no colours or links) by default
}

-- WallyHUD's tokens (Tokens.lua), for when it isn't loaded: the same values.
local function C(r, g, b, a) return { r / 255, g / 255, b / 255, a or 1 } end
local FALLBACK = {
    surface = { base = C(10, 12, 16, 0.72), raised = C(16, 19, 25, 0.88), sunken = C(6, 7, 10, 0.55) },
    border = { hairline = { 1, 1, 1, 0.08 }, strong = { 1, 1, 1, 0.16 } },
    text = { primary = C(237, 240, 245, 1), secondary = C(237, 240, 245, 0.72), tertiary = C(237, 240, 245, 0.50) },
    accent = C(64, 196, 205, 1),
    accentDim = C(64, 196, 205, 0.18),
    fontShadow = { 0, 0, 0, 0.75 },
}

-- The design tokens in use.
function ns.T() return (WallyHUD and WallyHUD.Tokens) or FALLBACK end

-- r, g, b, a of a colour (a overridable).
function ns.RGBA(c, a) return c[1], c[2], c[3], a or c[4] or 1 end

function ns.Hex(c)
    return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

-- The suite's face at a weight, or nil (no WallyHUD, or its shared look turned off): then the
-- game's font stays.
function ns.Face(weight)
    if WallyHUD and WallyHUD.SuiteFace then return WallyHUD.SuiteFace(weight) end
    return nil
end

ns.WHITE = "Interface\\Buttons\\WHITE8X8"
ns.MEDIA = "Interface\\AddOns\\WallyChat\\Media\\"

-- A hairline panel (see-through surface, 1px edge) on a frame with the BackdropTemplate.
function ns.Panel(frame, kind, alpha)
    if not frame.SetBackdrop then Mixin(frame, BackdropTemplateMixin) end
    local T = ns.T()
    frame:SetBackdrop({ bgFile = ns.WHITE, edgeFile = ns.WHITE, edgeSize = 1 })
    frame:SetBackdropColor(ns.RGBA(T.surface[kind or "base"], alpha))
    frame:SetBackdropBorderColor(ns.RGBA(T.border.hairline))
end

-- A text box's look, on its well (a frame behind the edit box, the BackdropTemplate): a darker
-- sunken well with a faint shadow along its top edge (set into the screen, not floating on it), a
-- caret bar at its left (tertiary at rest, accent while you type), an accent line along its bottom
-- and a brighter edge while you type, and hint (a text, or nil) while it's empty and you aren't.
-- after: where the hint starts (a region to its right; the box's left when nil). Returns a function
-- that repaints it (call it when the box's text changes from outside).
function ns.InputStyle(well, eb, hint, after)
    local T = ns.T()
    ns.Panel(well, "sunken", 0.8)
    local shade = well:CreateTexture(nil, "BORDER")
    shade:SetColorTexture(0, 0, 0, 0.45)
    shade:SetHeight(1)
    shade:SetPoint("TOPLEFT", 1, -1); shade:SetPoint("TOPRIGHT", -1, -1)
    local caret = well:CreateTexture(nil, "ARTWORK")
    caret:SetSize(2, 12)
    caret:SetPoint("LEFT", 6, 0)
    local focus = well:CreateTexture(nil, "ARTWORK")
    focus:SetColorTexture(ns.RGBA(T.accent))
    focus:SetHeight(1)
    focus:SetPoint("BOTTOMLEFT", 1, 1); focus:SetPoint("BOTTOMRIGHT", -1, 1)
    local tip
    if hint then
        tip = well:CreateFontString(nil, "OVERLAY")
        tip:SetFontObject(GameFontDisableSmall)
        local face = ns.Face("regular")
        if face then tip:SetFont(face, 12, "") end
        tip:SetTextColor(ns.RGBA(T.text.tertiary))
        tip:SetText(hint)
        if after then tip:SetPoint("LEFT", after, "RIGHT", 4, 0) else tip:SetPoint("LEFT", 16, 0) end
    end
    local function Paint()
        local on = eb:HasFocus()
        caret:SetColorTexture(ns.RGBA(on and T.accent or T.text.tertiary))
        focus:SetShown(on)
        well:SetBackdropBorderColor(ns.RGBA(on and T.border.strong or T.border.hairline))
        if tip then tip:SetShown(not on and (eb:GetText() or "") == "") end
    end
    eb:HookScript("OnEditFocusGained", Paint)
    eb:HookScript("OnEditFocusLost", Paint)
    eb:HookScript("OnTextChanged", Paint)
    eb:HookScript("OnShow", Paint)
    Paint()
    return Paint
end

-- An icon button in the suite's ghost style: the glyph in secondary text colour at rest, accent
-- under the mouse. tip: its tooltip's title, and a line under it.
function ns.IconButton(parent, file, size, tip, body)
    local T = ns.T()
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexture(ns.MEDIA .. file)
    b.icon:SetVertexColor(ns.RGBA(T.text.secondary))
    b:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(ns.RGBA(T.accent))
        if tip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(tip, ns.RGBA(T.text.primary))
            if body then GameTooltip:AddLine(body, 0.8, 0.85, 0.9, true) end
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        self.icon:SetVertexColor(ns.RGBA(T.text.secondary))
        GameTooltip:Hide()
    end)
    return b
end

function ns:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(ns.Hex(ns.T().accent) .. "WallyChat|r: " .. tostring(msg))
end

-- /wchat (font and bg go through ns:SetOption, so Options > AddOns > WallyChat shows them; their
-- applies there reskin the windows)
SLASH_WALLYCHAT1 = "/wchat"
SlashCmdList.WALLYCHAT = function(msg)
    local cmd, arg = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "full" or cmd == "fullscreen" then
        ns.FullScreen:Toggle()
    elseif cmd == "font" and ({ regular = true, medium = true, semibold = true, bold = true })[arg:lower()] then
        ns:SetOption("db.weight", arg:lower())
        ns:Print("Chat text in " .. arg:lower() .. ".")
    elseif cmd == "bg" and tonumber(arg) then
        ns:SetOption("db.background", math.max(0, math.min(100, tonumber(arg))))
        ns:Print(("Chat panel at %d%% opacity."):format(ns.db.background))
    elseif cmd == "debug" then
        ns.Skin:Debug()
    else
        ns:Print("/wchat full - the chat over the whole screen (select and copy any line)")
        ns:Print("/wchat font regular | medium | semibold | bold - the chat text's weight")
        ns:Print("/wchat bg 0-100 - the chat panel's opacity")
        ns:Print("/wchat debug - which of the game's chat parts were found")
    end
end
