local _, ns = ...

-- The buttons the game kept in a column beside the chat (friends, voice and channels, the chat
-- menu) as a quiet row at the right of the tab bar, the suite's ghost icons (secondary text colour,
-- accent under the mouse): Death Roll's Continue and Dice (DeathRoll.lua), Friends (how many are online beside it),
-- Channels, the chat menu, and Full screen (FullScreen.lua). The game's own buttons are kept out of sight. In each chat window, a
-- button to jump back to the newest message shows while you've scrolled up.
local Bar = {}
ns.Toolbar = Bar

local SIZE, GAP = 16, 9
local hidden = setmetatable({}, { __mode = "k" })

local function KeepHidden(frame)
    if not frame then return end
    frame:Hide()
    if not hidden[frame] then
        hidden[frame] = true
        frame:HookScript("OnShow", function(self) self:Hide() end)
    end
end

-- Friends online: characters and Battle.net.
local function OnlineFriends()
    local n = 0
    if C_FriendList and C_FriendList.GetNumOnlineFriends then n = n + (C_FriendList.GetNumOnlineFriends() or 0) end
    if BNGetNumFriends then
        local _, online = BNGetNumFriends()
        if type(online) == "number" then n = n + online end
    end
    return n
end

-- The game's chat menu (languages, emotes, chat settings), opened above our button. On this
-- engine the game's button is a DropdownButton of the Menu system (SetupMenu: its generator is
-- menuGenerator). Its own OpenMenu can't be used: the Menu system closes a menu on the next frame
-- when its owner isn't visible (Blizzard_Menu/Menu.lua, unless ignoreOwner), and that button is
-- kept hidden, so the menu flashed open and shut. So its generator is opened as a context menu
-- owned by our button, which is on screen.
local function MenuOpen(anchor)
    local menu = anchor.chatMenu
    if not menu then return false end
    local ok, shown = pcall(menu.IsShown, menu)
    return ok and shown and true or false
end

local function OpenChatMenu(anchor)
    local original = ChatFrameMenuButton
    if not original then return end
    -- (Read at mouse-down: a click outside an open menu closes it then, so this click is to close
    -- it, even though it's already gone.)
    local wasOpen = anchor.menuWasOpen
    anchor.menuWasOpen = nil
    if wasOpen or MenuOpen(anchor) then
        if MenuOpen(anchor) then pcall(anchor.chatMenu.Close, anchor.chatMenu) end
        anchor.chatMenu = nil
        return
    end
    if original.menuGenerator and MenuUtil and MenuUtil.CreateContextMenu then
        local ok, menu = pcall(MenuUtil.CreateContextMenu, anchor, original.menuGenerator)
        if ok and menu then
            anchor.chatMenu = menu
            if menu.SetClosedCallback then
                pcall(menu.SetClosedCallback, menu, function() if anchor.chatMenu == menu then anchor.chatMenu = nil end end)
            end
            return
        end
    end
    -- An older chat menu (UIDropDownMenu): the game's own click, then moved beside our button.
    local click = original:GetScript("OnClick") or original:GetScript("OnMouseDown")
    if click then
        pcall(click, original, "LeftButton")
    elseif ChatFrame_ToggleMenu then
        pcall(ChatFrame_ToggleMenu)
    end
    local shown = _G.ChatMenu
    if shown and shown:IsShown() then
        shown:ClearAllPoints()
        shown:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 6)
    end
end

local function Channels()
    if ToggleChannelFrame then return pcall(ToggleChannelFrame) end
    local original = ChatFrameChannelButton
    local click = original and original:GetScript("OnClick")
    if click then pcall(click, original, "LeftButton") end
end

function Bar:Build()
    if self.frame then return end
    local T = ns.T()
    local host = GeneralDockManager or ChatFrame1
    if not host then return end
    local row = CreateFrame("Frame", "WallyChatToolbar", host)
    row:SetSize(6 * SIZE + 5 * GAP + 20, SIZE)
    row:SetPoint("BOTTOMRIGHT", ChatFrame1, "TOPRIGHT", 0, 8)
    row:SetFrameLevel(host:GetFrameLevel() + 5)
    self.frame = row

    local full = ns.IconButton(row, "FullScreen", SIZE, "Full screen", "The chat over the whole screen: select any line and copy it (Ctrl+C), click links.")
    full:SetPoint("RIGHT", 0, 0)
    full:SetScript("OnClick", function() ns.FullScreen:Toggle() end)

    local menu = ns.IconButton(row, "Menu", SIZE, "Chat menu", "Emotes, languages, and the chat settings.")
    menu:SetPoint("RIGHT", full, "LEFT", -GAP, 0)
    menu:SetScript("OnClick", function(self) OpenChatMenu(self) end)
    menu:SetScript("OnMouseDown", function(self) self.menuWasOpen = MenuOpen(self) or nil end)
    -- A click on this button isn't a click outside the menu (the Menu system closes menus on any
    -- other mouse-down): it's ours, and OnClick closes the menu itself.
    function menu:HandlesGlobalMouseEvent(button, event) return event == "GLOBAL_MOUSE_DOWN" and button == "LeftButton" end

    local channels = ns.IconButton(row, "Channels", SIZE, "Channels", "Chat channels and voice chat.")
    channels:SetPoint("RIGHT", menu, "LEFT", -GAP, 0)
    channels:SetScript("OnClick", Channels)

    local friends = ns.IconButton(row, "Friends", SIZE, "Friends", nil)
    friends.count = friends:CreateFontString(nil, "OVERLAY")
    friends.count:SetFontObject(GameFontHighlightSmall)
    ns.Skin.Face(friends.count, "medium", 11)
    friends.count:SetTextColor(ns.RGBA(T.text.secondary))
    friends.count:SetPoint("LEFT", friends, "RIGHT", 3, 0)
    friends:SetPoint("RIGHT", channels, "LEFT", -GAP - 12, 0)
    friends:SetScript("OnClick", function()
        if ToggleFriendsFrame then ToggleFriendsFrame(1) end
    end)
    friends:HookScript("OnEnter", function(self)
        GameTooltip:AddLine(("%d online"):format(OnlineFriends()), 0.8, 0.85, 0.9)
        GameTooltip:Show()
    end)
    self.friends = friends
    self:Count()

    local dice = ns.IconButton(row, "Dice", SIZE, "Death Roll",
        "Pick the death roll you're playing when more than one is going, leave it, or start one (rolls 1-10000 for you).")
    dice:SetPoint("RIGHT", friends, "LEFT", -GAP, 0)
    dice:SetScript("OnClick", function() ns.DeathRoll:Click() end)
    self.dice = dice

    -- Shown only while locked onto a game (DeathRoll.lua), lit while it's your turn.
    local continue = ns.IconButton(row, "Continue", SIZE, "Continue death roll", nil)
    continue:SetPoint("RIGHT", dice, "LEFT", -GAP, 0)
    continue:SetScript("OnClick", function() ns.DeathRoll:Continue() end)
    continue:Hide()
    ns.DeathRoll:Attach(continue)
    self.continue = continue

    -- The game's buttons for these: out of sight (their column is gone too, Skin.lua).
    for _, name in ipairs({ "FriendsMicroButton", "QuickJoinToastButton", "ChatFrameChannelButton",
        "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton" }) do
        KeepHidden(_G[name])
    end
    Bar:CoverMenu(menu)
end

-- The game's own chat menu button sits on top of ours, invisible, so a click on our Menu icon is a
-- click on the game's button: the menu is the game's own, and so is the language picked in it.
-- (Built from WallyChat's code, as before, choosing a language ran the game's SetGameLanguage as
-- WallyChat's: the chat box's language was then the addon's, and the choice didn't work. Base chat
-- never had that.) Only frame methods are used on it (parent, place, alpha): nothing of the
-- game's is written. Our icon still shows its hover; OpenChatMenu stays for a game without it.
function Bar:CoverMenu(menu)
    local game = ChatFrameMenuButton
    if not game then return end
    local placing = false
    local function Place()
        if placing then return end
        placing = true
        if game:GetParent() ~= menu then game:SetParent(menu) end
        game:ClearAllPoints()
        game:SetAllPoints(menu)
        game:SetFrameLevel(menu:GetFrameLevel() + 5)
        for _, r in ipairs({ game:GetRegions() }) do r:SetAlpha(0) end
        placing = false
    end
    Place()
    hooksecurefunc(game, "SetPoint", Place)
    hooksecurefunc(game, "SetParent", Place)
    game:Show()
    local function Forward(script)
        return function()
            local f = menu:GetScript(script)
            if f then f(menu) end
        end
    end
    game:HookScript("OnEnter", Forward("OnEnter"))
    game:HookScript("OnLeave", Forward("OnLeave"))
end

function Bar:Count()
    if self.friends then self.friends.count:SetText(OnlineFriends()) end
end

-- ---------------------------------------------------------------------------------------------
-- Back to the newest message, in each window
-- ---------------------------------------------------------------------------------------------

local jumps = setmetatable({}, { __mode = "k" }) -- chat frame -> its button

-- The button sits in the window's bottom right corner all the time: faint while you're reading the
-- newest messages, lit in the accent colour with a slow pulse once you've scrolled up, so you can
-- see at a glance that newer lines are below.
local function PaintJump(b)
    local T = ns.T()
    if b.hover or b.away then
        b.icon:SetVertexColor(ns.RGBA(T.accent))
        b:SetAlpha(1)
    else
        b.icon:SetVertexColor(ns.RGBA(T.text.tertiary))
        b:SetAlpha(0.6)
    end
    b.glow:SetShown(b.away)
    if b.away then
        if not b.pulse:IsPlaying() then b.pulse:Play() end
    elseif b.pulse:IsPlaying() then
        b.pulse:Stop()
    end
end

local function Jump(cf)
    local b = jumps[cf]
    if b then return b end
    b = ns.IconButton(cf, "Bottom", 14, "Newest messages", nil)
    b:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 0, 0)
    b:SetFrameLevel(cf:GetFrameLevel() + 5)
    b:SetScript("OnClick", function() cf:ScrollToBottom() end)
    -- A soft accent disc behind the arrow, breathing while there are newer lines below.
    b.glow = b:CreateTexture(nil, "BACKGROUND")
    b.glow:SetPoint("CENTER")
    b.glow:SetSize(24, 24)
    b.glow:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    local T = ns.T()
    b.glow:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 0.35)
    b.glow:Hide()
    b.pulse = b.glow:CreateAnimationGroup()
    b.pulse:SetLooping("BOUNCE")
    local a = b.pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1); a:SetToAlpha(0.25); a:SetDuration(0.9); a:SetSmoothing("IN_OUT")
    b:HookScript("OnEnter", function(self) self.hover = true; PaintJump(self) end)
    b:HookScript("OnLeave", function(self) self.hover = false; PaintJump(self) end)
    b.away = false
    PaintJump(b)
    b:Show()
    KeepHidden(cf.ScrollToBottomButton or _G[cf:GetName() .. "ButtonFrameBottomButton"])
    jumps[cf] = b
    return b
end

local watch = CreateFrame("Frame")
local acc = 0
watch:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.2 then return end
    acc = 0
    for _, cf in ipairs(ns.Skin.Frames()) do
        if cf:IsVisible() and cf.AtBottom then
            local b = Jump(cf)
            local away = not cf:AtBottom()
            if away ~= b.away then
                b.away = away
                PaintJump(b)
            end
        end
    end
end)

ns:On("PLAYER_LOGIN", function() C_Timer.After(0, function() Bar:Build() end) end)
for _, e in ipairs({ "FRIENDLIST_UPDATE", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE", "BN_FRIEND_LIST_SIZE_CHANGED" }) do
    ns:On(e, function() Bar:Count() end)
end
