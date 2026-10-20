local _, ns = ...

-- The game's chat windows in the suite's look:
--   * each window: the game's gold-edged background and its button column (scroll arrows, the
--     friends, channel and menu buttons) gone; one see-through hairline panel behind the tabs and
--     the messages instead (its opacity: /wchat bg). The buttons come back as Toolbar.lua's row.
--   * the text: Roboto Condensed at the weight you pick (/wchat font), the size you set in the
--     game's chat settings, with the suite's soft shadow
--   * tabs: underline tabs, as WallyHUD draws them: no art, the name in capitals, the window you're
--     looking at in primary text over a 2px accent line, the others in secondary text. A tab with
--     something new still flashes, as an accent line.
--   * the edit box: a sunken hairline well whose edge brightens while you type
-- Windows opened later (whispers in their own window, new windows) get the same look, and a
-- change in the game's chat settings (font size, renaming, docking) is followed.
local Skin = {}
ns.Skin = Skin

local styled = setmetatable({}, { __mode = "k" }) -- chat frame -> { bg, eb }
local hidden = setmetatable({}, { __mode = "k" })  -- frames kept out of sight

-- The game's art on a chat window, its tabs and its edit box (by the part's key, or the frame's
-- name plus it).
local FRAME_ART = { "Background", "TopLeftTexture", "BottomLeftTexture", "TopRightTexture", "BottomRightTexture",
    "LeftTexture", "RightTexture", "BottomTexture", "TopTexture" }
local TAB_ART = { "Left", "Middle", "Right", "SelectedLeft", "SelectedMiddle", "SelectedRight",
    "HighlightLeft", "HighlightMiddle", "HighlightRight", "ActiveLeft", "ActiveMiddle", "ActiveRight" }
local EDIT_ART = { "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }

local function Part(frame, key)
    local name = frame:GetName()
    return frame[key] or (name and _G[name .. key])
end

-- A texture emptied: the game still sets its alpha as windows fade, but there's nothing to draw.
local function Blank(tex)
    if tex and tex.GetObjectType and tex:GetObjectType() == "Texture" then
        tex:SetTexture(nil)
        tex:SetAlpha(0)
    end
end

local function KeepHidden(frame)
    if not frame then return end
    frame:Hide()
    if not hidden[frame] then
        hidden[frame] = true
        frame:HookScript("OnShow", function(self) self:Hide() end)
    end
end

-- The suite's face at the chat weight (or weight), keeping the size and outline the game set.
local function Face(obj, weight, size)
    local face = ns.Face(weight or ns.db.weight)
    if not (face and obj and obj.GetFont) then return end
    local _, s, flags = obj:GetFont()
    obj:SetFont(face, size or s or 12, flags or "")
    if obj.SetShadowColor then
        obj:SetShadowColor(ns.RGBA(ns.T().fontShadow))
        obj:SetShadowOffset(1, -1)
    end
end
Skin.Face = Face

-- Whether a window is the one you're looking at: the selected one of the dock, or a window of its own.
local function Active(cf)
    if cf.isDocked and FCFDock_GetSelectedWindow and GENERAL_CHAT_DOCK then
        return FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK) == cf
    end
    return true
end

-- ---------------------------------------------------------------------------------------------
-- Tabs
-- ---------------------------------------------------------------------------------------------

local function TabText(tab)
    return tab.Text or Part(tab, "Text") or (tab.GetFontString and tab:GetFontString())
end

-- The tabs' text: the window you're looking at in full primary text, the others a step down
-- (INACTIVE of it): clearly readable over the panel, with the game's tab fading off (below).
local INACTIVE = 0.78
local function PaintTab(tab, cf)
    local T, text = ns.T(), TabText(tab)
    local on = cf and Active(cf)
    if text then text:SetTextColor(ns.RGBA(T.text.primary, on and 1 or INACTIVE)) end
    if tab.wallyLine then tab.wallyLine:SetShown(on and true or false) end
end

-- The game fades the tabs while the mouse isn't over the chat (the one you're on to 40%, the others
-- to 20%), dimming the text past readable: they stay at full instead, the text colours (PaintTab)
-- telling them apart. A tab with something new still flashes (its Glow, not the tab's alpha).
-- Done by putting the tab back to full as the game fades it, never by changing the game's
-- CHAT_FRAME_TAB_*_ALPHA globals: values we write there are tainted, and the game reads them while
-- Edit Mode opens, which got the rest of Edit Mode's work blocked (and blamed on WallyChat).
local unfaded = setmetatable({}, { __mode = "k" })
local function NoTabFade(tab)
    if not unfaded[tab] then
        unfaded[tab] = true
        hooksecurefunc(tab, "SetAlpha", function(self, a)
            if a ~= 1 then self:SetAlpha(1) end
        end)
    end
    tab:SetAlpha(1)
end

function Skin:Tab(cf)
    local tab = cf and _G[cf:GetName() .. "Tab"]
    if not tab then return end
    local T = ns.T()
    for _, key in ipairs(TAB_ART) do Blank(Part(tab, key)) end
    NoTabFade(tab)
    local text = TabText(tab)
    local glow = Part(tab, "Glow")
    if not tab.wallyLine and text then
        tab.wallyLine = tab:CreateTexture(nil, "OVERLAY")
        tab.wallyLine:SetColorTexture(ns.RGBA(T.accent))
        tab.wallyLine:SetHeight(2)
        tab.wallyLine:SetPoint("TOPLEFT", text, "BOTTOMLEFT", -2, -3)
        tab.wallyLine:SetPoint("TOPRIGHT", text, "BOTTOMRIGHT", 2, -3)
    end
    -- Something new in a window you aren't looking at: its tab flashes an accent line (the game
    -- flashes this texture).
    if glow and text and not tab.wallyGlow then
        tab.wallyGlow = true
        glow:SetTexture(ns.WHITE)
        glow:SetVertexColor(ns.RGBA(T.accent, 0.7))
        glow:ClearAllPoints()
        glow:SetHeight(2)
        glow:SetPoint("TOPLEFT", text, "BOTTOMLEFT", -2, -3)
        glow:SetPoint("TOPRIGHT", text, "BOTTOMRIGHT", 2, -3)
    end
    if text then
        Face(text, "medium", 11)
        local name = text:GetText()
        if name and name ~= name:upper() then
            text:SetText(name:upper())
            if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tab, tab.sizePadding or 0) end
        end
    end
    PaintTab(tab, cf)
end

-- ---------------------------------------------------------------------------------------------
-- Windows and the edit box
-- ---------------------------------------------------------------------------------------------

function Skin:Frame(cf)
    if not cf then return end
    local s = styled[cf] or {}
    styled[cf] = s
    for _, key in ipairs(FRAME_ART) do Blank(Part(cf, key)) end
    for _, region in ipairs({ cf:GetRegions() }) do Blank(region) end
    KeepHidden(Part(cf, "ButtonFrame"))

    -- One panel behind the tab row and the messages.
    if not s.bg then
        s.bg = CreateFrame("Frame", nil, cf, "BackdropTemplate")
        s.bg:SetPoint("TOPLEFT", cf, "TOPLEFT", -6, 30)
        s.bg:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 6, -6)
        s.bg:SetFrameLevel(math.max(0, cf:GetFrameLevel() - 1))
    end
    ns.Panel(s.bg, "base", (ns.db.background or 45) / 100)
    Face(cf)

    local eb = Part(cf, "EditBox")
    if eb then
        for _, key in ipairs(EDIT_ART) do Blank(Part(eb, key)) end
        if not s.eb then
            -- The well fills the box, and the box sits right under the window's panel, as wide
            -- as it (the game anchors it to the text area: wider and off to one side). Put back
            -- there whenever the game moves it.
            s.eb = CreateFrame("Frame", nil, eb, "BackdropTemplate")
            s.eb:SetAllPoints(eb)
            s.eb:SetFrameLevel(math.max(0, eb:GetFrameLevel() - 1))
            local aligning = false
            local function Align()
                if aligning or not s.bg then return end
                aligning = true
                eb:ClearAllPoints()
                eb:SetPoint("TOPLEFT", s.bg, "BOTTOMLEFT", 0, -4)
                eb:SetPoint("TOPRIGHT", s.bg, "BOTTOMRIGHT", 0, -4)
                eb:SetHeight(28)
                aligning = false
            end
            hooksecurefunc(eb, "SetPoint", Align)
            Align()
            s.paintEB = ns.InputStyle(s.eb, eb, "Press Enter to chat", nil)
        end
        if s.paintEB then s.paintEB() end
        Face(eb)
        Face(Part(eb, "Header"))
        Face(Part(eb, "HeaderSuffix"))
    end
    self:Tab(cf)
end

-- Every chat window there is now (the numbered ones and those opened since: whisper windows).
local function Frames()
    local out, seen = {}, {}
    local function Add(cf) if cf and not seen[cf] then seen[cf] = true; out[#out + 1] = cf end end
    for i = 1, NUM_CHAT_WINDOWS or 10 do Add(_G["ChatFrame" .. i]) end
    for _, name in ipairs(CHAT_FRAMES or {}) do Add(_G[name]) end
    return out
end
Skin.Frames = Frames

function Skin:All()
    if not ns.db then return end
    for _, cf in ipairs(Frames()) do self:Frame(cf) end
end

-- Once, after whatever the game is doing settles (a window opening, docking, a setting changing).
local pending
function Skin:Later()
    if pending then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        Skin:All()
    end)
end

function Skin:Debug()
    local function Has(name) return _G[name] and "|cff59f28cyes|r" or "|cffd9736bno|r" end
    for _, name in ipairs({ "ChatFrame1", "ChatFrame1Tab", "ChatFrame1EditBox", "ChatFrame1ButtonFrame",
        "GeneralDockManager", "FriendsMicroButton", "QuickJoinToastButton", "ChatFrameChannelButton",
        "ChatFrameMenuButton", "SimplePanelFrame" }) do
        ns:Print(("%s: %s"):format(name, Has(name)))
    end
    ns:Print(("Font: %s (%s)"):format(tostring(ns.Face(ns.db.weight)), ns.db.weight))
end

ns:On("PLAYER_LOGIN", function()
    Skin:All()
    for _, fn in ipairs({ "FCF_OpenTemporaryWindow", "FCF_OpenNewWindow", "FCF_SetChatWindowFontSize", "FCF_DockFrame",
        "FCF_UnDockFrame", "FCFDock_SelectWindow", "FCF_Tab_OnClick", "FCF_Close", "FCF_SetWindowName",
        "FCF_RestorePositionAndDimensions" }) do
        if type(_G[fn]) == "function" then hooksecurefunc(fn, function() Skin:Later() end) end
    end
    -- The game paints a tab's text in its window's colour as it selects one: ours again.
    if type(FCFTab_UpdateColors) == "function" then
        hooksecurefunc("FCFTab_UpdateColors", function(tab)
            local cf = tab and tab.GetID and _G["ChatFrame" .. tab:GetID()]
            if cf and tab.wallyLine then PaintTab(tab, cf) end
        end)
    end
end)
ns:On("UPDATE_CHAT_WINDOWS", function() Skin:Later() end)
ns:On("UPDATE_FLOATING_CHAT_WINDOWS", function() Skin:Later() end)
