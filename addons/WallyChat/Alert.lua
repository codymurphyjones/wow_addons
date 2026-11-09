local _, ns = ...

-- The game's layer-refresh notice, kept with the chat. When the game is about to move you to
-- another layer (you joined a group whose leader is on another one, or the server rebalances it),
-- the game shows a toast with the time left (ShardTransferImminentFrame, Blizzard_SocialToast; a click
-- brings up Refresh Now / Okay) and a small expand arrow beside it that toggles the toast
-- (ShardTransferImminentMinimizeButton). The game hangs both off ChatAlertFrame, which sits on
-- top of the chat's button column: a column Skin.lua hides, and a spot WallyChat's tab bar covers.
-- Here they sit just above WallyChat's panel on the main chat window instead (the arrow at the
-- panel's left edge, the toast beside it, growing upward), so they follow the chat when it moves.
--
-- While the main chat window can be moved (the game's Edit Mode, or dragging it by its tab) or
-- after /wchat alert, an outline shows the space the notice takes there.
local A = {}
ns.Alert = A

local TOAST_W, TOAST_H = 250, 50 -- the game's sizes (SocialToast.xml)
local ARROW = 24
local GAP = 5                     -- the game's gap between the arrow and the toast
local LIFT = 6                    -- above the panel's top edge
-- The panel's top-left corner, from the chat window's (Skin.lua: s.bg at -6, 30).
local PANEL_X, PANEL_Y = -6, 30

local function Chat() return DEFAULT_CHAT_FRAME or ChatFrame1 end

-- The arrow at the panel's left edge, the toast to its right: bottoms aligned, so the toast
-- grows upward as its text wraps (it sets its own height every frame) and never over the chat.
local function Place(toast, arrow, cf)
    toast:ClearAllPoints()
    toast:SetPoint("BOTTOMLEFT", cf, "TOPLEFT", PANEL_X + ARROW + GAP, PANEL_Y + LIFT)
    if arrow then
        arrow:ClearAllPoints()
        arrow:SetPoint("BOTTOMRIGHT", toast, "BOTTOMLEFT", -GAP, 0)
    end
end

function A:Anchor()
    local cf, toast = Chat(), _G.ShardTransferImminentFrame
    if not (cf and toast) then return end
    Place(toast, _G.ShardTransferImminentMinimizeButton, cf)
end

-- ---------------------------------------------------------------------------------------------
-- The outline of where it shows
-- ---------------------------------------------------------------------------------------------

local preview
local reasons = {} -- why the outline is up: editMode, drag, command

local function Outline(parent, w, h)
    local T = ns.T()
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(w, h)
    ns.Panel(f, "raised", 0.55)
    f:SetBackdropBorderColor(ns.RGBA(T.accent))
    return f
end

local function BuildPreview()
    local T = ns.T()
    local box = CreateFrame("Frame", "WallyChatAlertPreview", UIParent)
    box:SetFrameStrata("DIALOG")
    box:SetSize(TOAST_W, TOAST_H)
    box:EnableMouse(false)
    box.arrow = Outline(box, ARROW, ARROW)
    box.arrow:SetPoint("BOTTOMRIGHT", box, "BOTTOMLEFT", -GAP, 0)
    local glyph = box.arrow:CreateTexture(nil, "ARTWORK")
    glyph:SetSize(ARROW - 6, ARROW - 6)
    glyph:SetPoint("CENTER")
    glyph:SetAtlas("RedButton-Expand")
    glyph:SetDesaturated(true)
    glyph:SetVertexColor(ns.RGBA(T.accent))
    box.toast = Outline(box, TOAST_W, TOAST_H)
    box.toast:SetAllPoints()
    local title = box.toast:CreateFontString(nil, "OVERLAY")
    title:SetFontObject(GameFontHighlight)
    title:SetPoint("TOPLEFT", 10, -9)
    title:SetPoint("RIGHT", -10, 0)
    title:SetJustifyH("LEFT")
    title:SetTextColor(ns.RGBA(T.text.primary))
    title:SetText("Layer refresh notice")
    local body = box.toast:CreateFontString(nil, "OVERLAY")
    body:SetFontObject(GameFontHighlightSmall)
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    body:SetPoint("RIGHT", -10, 0)
    body:SetJustifyH("LEFT")
    body:SetTextColor(ns.RGBA(T.text.secondary))
    body:SetText("Shows here when the game will move you to another layer.")
    local face = ns.Face("semibold")
    if face then title:SetFont(face, 13, "") end
    face = ns.Face("regular")
    if face then body:SetFont(face, 11, "") end
    return box
end

function A:Preview(reason, on)
    reasons[reason] = on or nil
    local want = next(reasons) ~= nil
    local real = _G.ShardTransferImminentFrame
    if real and real:IsShown() then want = false end -- the notice itself is showing
    if not want then
        if preview then preview:Hide() end
        return
    end
    local cf = Chat()
    if not cf then return end
    preview = preview or BuildPreview()
    Place(preview, nil, cf)
    preview:Show()
end

function A:TogglePreview()
    self:Preview("command", not reasons.command)
    return reasons.command ~= nil
end

-- ---------------------------------------------------------------------------------------------
-- Hooks
-- ---------------------------------------------------------------------------------------------

local hooked
local function Hook()
    if hooked or not _G.ShardTransferImminentFrame then return end
    hooked = true
    A:Anchor()
    -- The real notice: anchored again whenever it comes up (nothing in the game moves it after
    -- it loads, but another addon might), and the outline out of its way meanwhile.
    _G.ShardTransferImminentFrame:HookScript("OnShow", function()
        A:Anchor()
        if preview then preview:Hide() end
    end)
    _G.ShardTransferImminentFrame:HookScript("OnHide", function() A:Preview("refresh", false) end) -- (the outline back, if wanted)
end

ns:On("PLAYER_LOGIN", function()
    Hook()
    -- Moving the main chat window: the game's Edit Mode...
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("EditMode.Enter", function() A:Preview("editMode", true) end, A)
        EventRegistry:RegisterCallback("EditMode.Exit", function() A:Preview("editMode", false) end, A)
    end
    -- ...or dragging it by its tab (the outline follows: it's anchored to the window).
    local tab = _G[(Chat():GetName() or "ChatFrame1") .. "Tab"]
    if tab then tab:HookScript("OnDragStart", function() A:Preview("drag", true) end) end
    if type(FCF_StopDragging) == "function" then
        hooksecurefunc("FCF_StopDragging", function() A:Preview("drag", false) end)
    end
end)

-- Blizzard_SocialToast loads with the game's other UI, before us; in case it ever loads later:
ns:On("ADDON_LOADED", function(name)
    if name == "Blizzard_SocialToast" then Hook() end
end)

ns:On("SHARD_TRANSFER_IMMINENT", function() Hook(); A:Anchor() end)
