local _, ns = ...

-- Full screen: a chat window over the whole screen below SimplePanel's bar (the whole screen
-- without it), above every other window. Its history is text you can select (drag) and copy
-- (Ctrl+C); typing doesn't change it. Links still work: a click on a web address opens the copy
-- box (Links.lua), on any other link (an item, a player) does what it does in chat. Plain text
-- (the header's switch, remembered) leaves out colours and links, so what you copy is only the
-- words. New messages come in while it's open, except while you're selecting (the text has the
-- focus): the view stays at the bottom if it was there. A tab per chat window, as in chat; Escape
-- or the corner button closes it.
local FS = {}
ns.FullScreen = FS

local frame, box, scroll, tabs, input, measure
local current            -- the chat window shown
local content, spans     -- the text shown, and its links: { { a, b, link, text } } (see Build)
local dirty
local GAP = 12

-- ---------------------------------------------------------------------------------------------
-- The text
-- ---------------------------------------------------------------------------------------------

local function Secret(v) return issecretvalue and issecretvalue(v) or false end

-- One message as it goes in the box: icons and protected names (Battle.net) can't be shown in it.
local function Clean(text)
    text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    text = text:gsub("|K.-|k", "(Battle.net friend)")
    return text
end

local function Plain(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    return text
end

-- How many characters (not bytes) the string has, and how many show (escape codes left out).
local function Chars(s) return #s:gsub("[\128-\191]", "") end
local function Shown(s)
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
    return Chars(s)
end

-- The box's text for a chat window, and where its links are: each { link, display, byte range,
-- character range, shown-character range } (which of the three the box's cursor counts in isn't
-- the same on every client; a click checks all of them).
local function Build(cf)
    local lines, links = {}, {}
    local plain = ns.db.plainCopy
    local n = cf.GetNumMessages and cf:GetNumMessages() or 0
    local text = ""
    for i = 1, n do
        local msg, r, g, b = cf:GetMessageInfo(i)
        if type(msg) == "string" and not Secret(msg) then
            msg = Clean(msg)
            msg = ns.Links.Mark(msg)
            if plain then
                msg = Plain(msg)
            elseif r and g and b and not (Secret(r) or Secret(g) or Secret(b)) then
                msg = ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255) .. msg .. "|r"
            end
            lines[#lines + 1] = msg
        end
    end
    text = table.concat(lines, "\n")
    if not plain then
        local pos = 1
        while true do
            local s, e, link, shown = text:find("|H(.-)|h(.-)|h", pos)
            if not s then break end
            local before = text:sub(1, s - 1)
            local cs, ss = Chars(before), Shown(before)
            links[#links + 1] = { link = link, text = shown, byte = { s - 1, e }, char = { cs, cs + Chars(text:sub(s, e)) },
                shown = { ss, ss + Chars(shown) } }
            pos = e + 1
        end
    else
        -- Plain text: the web addresses are still clickable (by where they are).
        for url_s, url, url_e in text:gmatch("()(https?://%S+)()") do
            local before = text:sub(1, url_s - 1)
            local cs = Chars(before)
            links[#links + 1] = { link = "wallychat:url:" .. url, text = url, byte = { url_s - 1, url_e - 1 },
                char = { cs, cs + Chars(url) }, shown = { cs, cs + Chars(url) } }
        end
    end
    return text, links
end

local function AtBottom()
    local max = scroll:GetVerticalScrollRange()
    return max <= 0 or scroll:GetVerticalScroll() >= max - 4
end

function FS:Fill(toBottom)
    if not (frame and frame:IsShown() and current) then return end
    local bottom = toBottom or AtBottom()
    content, spans = Build(current)
    box:SetText(content)
    if measure then measure:SetText(content) end
    box:SetCursorPosition(0)
    box:ClearFocus()
    if bottom then
        C_Timer.After(0, function() scroll:SetVerticalScroll(scroll:GetVerticalScrollRange()) end)
    end
end

-- New messages: once a moment, unless you're selecting.
local function Changed(cf)
    if not (frame and frame:IsShown()) or cf ~= current or dirty then return end
    dirty = true
    C_Timer.After(0.3, function()
        dirty = false
        if box:HasFocus() then return Changed(cf) end
        FS:Fill(false)
    end)
end

-- ---------------------------------------------------------------------------------------------
-- Tabs: one per chat window that has a tab showing
-- ---------------------------------------------------------------------------------------------

local tabButtons = {}

local function Windows()
    local out = {}
    for _, cf in ipairs(ns.Skin.Frames()) do
        local tab = _G[cf:GetName() .. "Tab"]
        if tab and tab:IsShown() then out[#out + 1] = cf end
    end
    return out
end

local function WindowName(cf)
    local name = FCF_GetChatWindowInfo and FCF_GetChatWindowInfo(cf:GetID())
    if not name or name == "" then
        local tab = _G[cf:GetName() .. "Tab"]
        name = tab and tab:GetText() or cf:GetName()
    end
    return name
end

function FS:Tabs()
    local T = ns.T()
    for _, b in ipairs(tabButtons) do b:Hide() end
    local x = 0
    for i, cf in ipairs(Windows()) do
        local b = tabButtons[i]
        if not b then
            b = CreateFrame("Button", nil, tabs)
            b:SetHeight(26)
            b.text = b:CreateFontString(nil, "OVERLAY")
            b.text:SetFontObject(GameFontHighlightSmall)
            b.text:SetPoint("CENTER", 0, 1)
            b.line = b:CreateTexture(nil, "OVERLAY")
            b.line:SetColorTexture(ns.RGBA(T.accent)); b.line:SetHeight(2)
            b.line:SetPoint("BOTTOMLEFT", 6, 0); b.line:SetPoint("BOTTOMRIGHT", -6, 0)
            tabButtons[i] = b
        end
        ns.Skin.Face(b.text, "medium", 12)
        b.text:SetText(WindowName(cf):upper())
        b:SetWidth(b.text:GetStringWidth() + 24)
        b:ClearAllPoints(); b:SetPoint("LEFT", tabs, "LEFT", x, 0)
        x = x + b:GetWidth()
        local on = cf == current
        b.text:SetTextColor(ns.RGBA(on and T.text.primary or T.text.secondary))
        b.line:SetShown(on)
        b:SetScript("OnClick", function() FS:Show(cf) end)
        b:Show()
    end
end

-- ---------------------------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------------------------

-- The space below SimplePanel's bar when it's showing (the whole screen otherwise), with PAD of it
-- left clear on every side, so it isn't flush with the screen's edges or the bar.
local PAD = 0.05
local function Place()
    frame:ClearAllPoints()
    local bar = SimplePanelFrame
    local top = 0
    if bar and bar:IsShown() and bar:GetBottom() then
        top = math.max(0, UIParent:GetTop() - bar:GetBottom() * bar:GetEffectiveScale() / UIParent:GetEffectiveScale())
    end
    local padX = UIParent:GetWidth() * PAD
    local padY = (UIParent:GetHeight() - top) * PAD
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", padX, -(top + padY))
    frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -padX, padY)
end

-- A click (not a drag) in the text: the link it landed on, if any.
local function LinkAt(pos)
    for _, sp in ipairs(spans or {}) do
        for _, range in ipairs({ sp.byte, sp.char, sp.shown }) do
            if pos >= range[1] and pos <= range[2] then return sp end
        end
    end
end

local function Build_()
    local T = ns.T()
    frame = CreateFrame("Frame", "WallyChatFullScreen", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    ns.Panel(frame, "raised", 0.96)
    frame:Hide()
    tinsert(UISpecialFrames, "WallyChatFullScreen")

    local title = frame:CreateFontString(nil, "OVERLAY")
    title:SetFontObject(GameFontNormal)
    ns.Skin.Face(title, "semibold", 13)
    title:SetTextColor(ns.RGBA(T.text.primary))
    title:SetPoint("TOPLEFT", GAP + 2, -GAP - 6)
    title:SetText("CHAT")

    tabs = CreateFrame("Frame", nil, frame)
    tabs:SetPoint("LEFT", title, "RIGHT", 18, -1)
    tabs:SetSize(600, 26)

    local exit = ns.IconButton(frame, "Exit", 18, "Exit full screen", "Escape closes it too.")
    exit:SetPoint("TOPRIGHT", -GAP, -GAP - 2)
    exit:SetScript("OnClick", function() FS:Hide() end)

    -- Plain text: on or off (remembered).
    local plain = CreateFrame("Button", nil, frame, "BackdropTemplate")
    plain:SetSize(92, 20)
    plain:SetPoint("RIGHT", exit, "LEFT", -12, 0)
    ns.Panel(plain, "sunken")
    plain.text = plain:CreateFontString(nil, "OVERLAY")
    plain.text:SetFontObject(GameFontHighlightSmall)
    ns.Skin.Face(plain.text, "medium", 11)
    plain.text:SetPoint("CENTER")
    local function PaintPlain()
        plain.text:SetText(ns.db.plainCopy and "PLAIN TEXT: ON" or "PLAIN TEXT: OFF")
        plain.text:SetTextColor(ns.RGBA(ns.db.plainCopy and T.accent or T.text.secondary))
        plain:SetWidth(plain.text:GetStringWidth() + 18)
    end
    plain:SetScript("OnClick", function()
        ns.db.plainCopy = not ns.db.plainCopy
        PaintPlain()
        FS:Fill(false)
    end)
    plain:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(ns.RGBA(T.border.strong))
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Plain text", ns.RGBA(T.text.primary))
        GameTooltip:AddLine("Only the words: no colours or links, so what you copy pastes cleanly outside the game. Web addresses stay clickable.", 0.8, 0.85, 0.9, true)
        GameTooltip:Show()
    end)
    plain:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(ns.RGBA(T.border.hairline))
        GameTooltip:Hide()
    end)
    frame.PaintPlain = PaintPlain

    local hint = frame:CreateFontString(nil, "OVERLAY")
    hint:SetFontObject(GameFontDisableSmall)
    ns.Skin.Face(hint, "regular", 11)
    hint:SetTextColor(ns.RGBA(T.text.tertiary))
    hint:SetPoint("RIGHT", plain, "LEFT", -14, 0)
    hint:SetText("Drag to select, Ctrl+C to copy, click a link to open it")

    local line = frame:CreateTexture(nil, "BORDER")
    line:SetColorTexture(ns.RGBA(T.border.hairline)); line:SetHeight(1)
    line:SetPoint("TOPLEFT", GAP, -GAP - 34); line:SetPoint("TOPRIGHT", -GAP, -GAP - 34)

    scroll = CreateFrame("ScrollFrame", "WallyChatFullScreenScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", GAP + 4, -GAP - 44)
    scroll:SetPoint("BOTTOMRIGHT", -GAP - 24, GAP + 42)
    box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal or GameFontHighlight)
    box:SetMaxLetters(0)
    box:EnableMouse(true)
    box:SetTextInsets(0, 0, 0, 0)
    scroll:SetScrollChild(box)
    scroll:SetScript("OnSizeChanged", function(self, w)
        box:SetWidth(w)
        measure:SetWidth(w)
    end)
    -- Hovering a link shows its tooltip, as in chat. The box can't say what's under the mouse, so an
    -- invisible copy of its text, laid out the same (font, width, wrapping) over it, does
    -- (FindCharacterIndexAtCoordinate). Not while the button is down: that's selecting.
    measure = box:CreateFontString(nil, "OVERLAY")
    measure:SetFontObject(ChatFontNormal or GameFontHighlight)
    measure:SetPoint("TOPLEFT")
    measure:SetJustifyH("LEFT"); measure:SetJustifyV("TOP")
    measure:SetWordWrap(true)
    measure:SetAlpha(0)
    local hovered
    local NO_TIP = { wallychat = true, player = true, playerGM = true, BNplayer = true, channel = true, url = true }
    local function Unhover()
        if hovered then
            hovered = nil
            if GameTooltip:IsOwned(box) then GameTooltip:Hide() end
        end
    end
    local hoverAcc = 0
    box:HookScript("OnUpdate", function(self, dt)
        hoverAcc = hoverAcc + dt
        if hoverAcc < 0.05 then return end
        hoverAcc = 0
        if not (self:IsMouseOver() and measure.FindCharacterIndexAtCoordinate) or IsMouseButtonDown("LeftButton") then
            return Unhover()
        end
        local s = measure:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        cx, cy = cx / s, cy / s
        local left, bottom, top = measure:GetLeft(), measure:GetBottom(), measure:GetTop()
        if not (left and bottom and top) then return Unhover() end
        -- (the docs don't say which corner the point is from: the bottom left, else the top left)
        local ok, index, inside = pcall(measure.FindCharacterIndexAtCoordinate, measure, cx - left, cy - bottom)
        if not (ok and inside) then
            ok, index, inside = pcall(measure.FindCharacterIndexAtCoordinate, measure, cx - left, top - cy)
        end
        local sp = ok and inside and index and LinkAt(index) or nil
        if sp == hovered then return end
        Unhover()
        hovered = sp
        local kind = sp and sp.link:match("^([^:]+)")
        if sp and not NO_TIP[kind or ""] then
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT", 16, 0)
            if pcall(GameTooltip.SetHyperlink, GameTooltip, sp.link) then GameTooltip:Show() else GameTooltip:Hide() end
        end
    end)
    box:HookScript("OnLeave", Unhover)
    -- Read-only: typing puts the text back (a copy doesn't change it).
    box:SetScript("OnTextChanged", function(self, user)
        if user and content then
            local at = self:GetCursorPosition()
            self:SetText(content)
            self:SetCursorPosition(at)
        end
    end)
    box:SetScript("OnEscapePressed", function(self)
        if self:HasFocus() then self:ClearFocus() else FS:Hide() end
    end)
    -- A click on a link (the mouse didn't move: not a selection) opens it.
    local downX, downY
    box:SetScript("OnMouseDown", function() downX, downY = GetCursorPosition() end)
    box:SetScript("OnMouseUp", function(self, button)
        local x, y = GetCursorPosition()
        if not downX or math.abs(x - downX) > 3 or math.abs(y - downY) > 3 then return end
        C_Timer.After(0, function()
            local sp = LinkAt(self:GetCursorPosition())
            if not sp then return end
            local url = ns.Links.URL(sp.link)
            if url then
                ns.Links.Open(url)
            elseif SetItemRef then
                pcall(SetItemRef, sp.link, "|H" .. sp.link .. "|h" .. sp.text .. "|h", button or "LeftButton", current)
            end
        end)
    end)

    input = FS:BuildInput()

    frame:SetScript("OnShow", function() Place() end)
    frame:SetScript("OnHide", function() box:ClearFocus(); GameTooltip:Hide(); frame:SetAlpha(1) end)

    -- New messages in any window (the one showing is redrawn).
    for _, cf in ipairs(ns.Skin.Frames()) do
        if cf.AddMessage then hooksecurefunc(cf, "AddMessage", function(self) Changed(self) end) end
    end
end

-- ---------------------------------------------------------------------------------------------
-- Typing here: a line along the bottom, said through the game's own chat box (so /2, /w name, /g,
-- emotes and every other slash command work as in chat), with where it goes beside it as the chat
-- box shows it ("Say:", "[2. Trade]:"). Enter (the game's key for chat) types here while this is
-- open; Escape leaves the line; Up and Down go through what you've said here.
-- ---------------------------------------------------------------------------------------------

local sending = false
local said, back = {}, 0

-- The game's chat box a message goes through (the one it would open now).
local function ChatBox()
    return (ChatEdit_ChooseBoxForSend and ChatEdit_ChooseBoxForSend()) or ChatFrame1EditBox
end

-- Where a message goes now, as the chat box says it.
local function Target()
    local eb = ChatBox()
    if not eb then return "" end
    if ChatEdit_UpdateHeader then pcall(ChatEdit_UpdateHeader, eb) end
    local header = eb.header or _G[eb:GetName() .. "Header"]
    local text = header and header:GetText()
    return (type(text) == "string" and text ~= "") and text or "Say:"
end

local function Say(text)
    local eb = ChatBox()
    if not (eb and ChatEdit_SendText) or text == "" then return end
    sending = true
    local ok, err = pcall(function()
        if ChatEdit_ActivateChat then ChatEdit_ActivateChat(eb) end
        eb:SetText(text)
        ChatEdit_SendText(eb, 1)
        if ChatEdit_DeactivateChat then ChatEdit_DeactivateChat(eb) end
    end)
    sending = false
    if not ok then geterrorhandler()(err) end
end

function FS:BuildInput()
    local T = ns.T()
    local well = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    well:SetPoint("BOTTOMLEFT", GAP, GAP)
    well:SetPoint("BOTTOMRIGHT", -GAP, GAP)
    well:SetHeight(32)
    local to = well:CreateFontString(nil, "OVERLAY")
    to:SetFontObject(GameFontHighlight)
    ns.Skin.Face(to, "semibold", 13)
    to:SetPoint("LEFT", 16, 0)
    local eb = CreateFrame("EditBox", nil, well)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal or GameFontHighlight)
    eb:SetPoint("LEFT", to, "RIGHT", 6, 0)
    eb:SetPoint("RIGHT", -10, 0)
    eb:SetHeight(28)
    eb:SetMaxLetters(255)
    local paint = ns.InputStyle(well, eb, "Type a message (Enter to send)", to)
    local function Refresh()
        to:SetText(Target())
        local face = ns.Face(ns.db.weight)
        if face then
            local _, size = (current or ChatFrame1):GetFont()
            eb:SetFont(face, (size or 13) + 1, "")
            eb:SetShadowColor(ns.RGBA(T.fontShadow)); eb:SetShadowOffset(1, -1)
        end
        paint()
    end
    eb.Refresh = Refresh
    eb:HookScript("OnEditFocusGained", Refresh)
    eb:HookScript("OnEditFocusLost", Refresh)
    eb:SetScript("OnEnterPressed", function(self)
        local text = strtrim(self:GetText() or "")
        if text ~= "" then
            table.insert(said, text)
            if #said > 50 then table.remove(said, 1) end
        end
        back = 0
        self:SetText("")
        Say(text)
        Refresh()
        if text == "" then self:ClearFocus() end
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnArrowPressed", function(self, key)
        if #said == 0 then return end
        if key == "UP" then back = math.min(#said, back + 1)
        elseif key == "DOWN" then back = math.max(0, back - 1)
        else return end
        self:SetText(back > 0 and said[#said - back + 1] or "")
        self:SetCursorPosition(#self:GetText())
    end)
    -- A click anywhere on the line types there.
    well:EnableMouse(true)
    well:SetScript("OnMouseDown", function() eb:SetFocus() end)
    eb:SetAltArrowKeyMode(false)
    return eb
end

-- The game's Enter (or /, or R to reply...): with this open, it types here instead of in the small
-- chat box behind. Whatever opened a chat box, the moment one takes the cursor it hands it over:
-- its text (a "/" already typed) comes along, and where it was going to (a reply's whisper target)
-- stays set on it for the send.
local handed = setmetatable({}, { __mode = "k" })
local function HandOver(eb)
    if sending or not (frame and frame:IsShown() and input) then return end
    C_Timer.After(0, function()
        if sending or not (frame:IsShown() and eb:HasFocus()) then return end
        local text = eb:GetText() or ""
        if ChatEdit_DeactivateChat then pcall(ChatEdit_DeactivateChat, eb) end
        eb:ClearFocus()
        input:SetFocus()
        input:SetText(text)
        input:SetCursorPosition(#text)
        input.Refresh()
    end)
end
local function HookBoxes()
    for _, cf in ipairs(ns.Skin.Frames()) do
        local eb = cf.editBox or _G[cf:GetName() .. "EditBox"]
        if eb and not handed[eb] then
            handed[eb] = true
            eb:HookScript("OnEditFocusGained", HandOver)
        end
    end
end
ns:On("PLAYER_LOGIN", HookBoxes)
ns:On("UPDATE_CHAT_WINDOWS", HookBoxes)

-- Shows chat window cf full screen (the one you're looking at in chat when nil).
function FS:Show(cf)
    if not frame then Build_() end
    HookBoxes()
    current = cf or (SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME)
    Place()
    frame:Show()
    local face = ns.Face(ns.db.weight)
    if face then
        local _, size = current:GetFont()
        box:SetFont(face, (size or 13) + 1, "")
        measure:SetFont(face, (size or 13) + 1, "")
        box:SetShadowColor(ns.RGBA(ns.T().fontShadow)); box:SetShadowOffset(1, -1)
    end
    frame.PaintPlain()
    self:Tabs()
    self:Fill(true)
    input.Refresh()
end

function FS:Hide() if frame then frame:Hide() end end

function FS:IsShown() return frame ~= nil and frame:IsShown() end

function FS:Toggle()
    if self:IsShown() then return self:Hide() end
    if InCombatLockdown() or UnitAffectingCombat("player") then
        return ns:Print("Full screen chat waits until you're out of combat.")
    end
    self:Show()
end

-- Holding Ctrl fades it to almost nothing to see what's behind (as SimplePanel's windows do), and
-- letting go brings it back. Not while you're in the text: Ctrl+C is how you copy.
local PEEK = 0.1
ns:On("MODIFIER_STATE_CHANGED", function()
    if not (frame and frame:IsShown()) then return end
    local peek = IsControlKeyDown() and not box:HasFocus() and not (input and input:HasFocus())
    frame:SetAlpha(peek and PEEK or 1)
end)

-- A click outside it closes it. Not a click in what it opened itself: the link copy box, a link's
-- tooltip, the game's popups, a menu.
local function Ours()
    -- (the icon row too: its Full screen button closes it itself, rather than closing and reopening)
    for _, f in ipairs({ frame, WallyChatToolbar, ItemRefTooltip, DropDownList1, DropDownList2, ChatMenu }) do
        if f and f:IsShown() and f:IsMouseOver() then return true end
    end
    for i = 1, STATICPOPUP_NUMDIALOGS or 4 do
        local p = _G["StaticPopup" .. i]
        if p and p:IsShown() and p:IsMouseOver() then return true end
    end
    if Menu and Menu.GetManager then
        local ok, manager = pcall(Menu.GetManager)
        local open = ok and manager and manager.GetOpenMenu and manager:GetOpenMenu()
        if open and open:IsMouseOver() then return true end
    end
    return false
end
ns:On("GLOBAL_MOUSE_DOWN", function()
    if frame and frame:IsShown() and not Ours() then frame:Hide() end
end)

-- Combat: it closes, so it never covers the fight (open it again afterwards).
ns:On("PLAYER_REGEN_DISABLED", function()
    if frame and frame:IsShown() then frame:Hide() end
end)

-- SimplePanel's bar moving or hiding: the window follows.
ns:On("UI_SCALE_CHANGED", function() if frame and frame:IsShown() then Place() end end)
ns:On("DISPLAY_SIZE_CHANGED", function() if frame and frame:IsShown() then Place() end end)
