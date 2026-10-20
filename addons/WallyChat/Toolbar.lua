local _, ns = ...

-- The buttons the game kept in a column beside the chat (friends, voice and channels, the chat
-- menu) as a quiet row at the right of the tab bar, the suite's ghost icons (secondary text colour,
-- accent under the mouse): Friends (how many are online beside it), Channels, the chat menu, and
-- Full screen (FullScreen.lua). The game's own buttons are kept out of sight. In each chat window, a
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

-- The game's chat menu, opened beside our button (its own anchor is the hidden game button).
local function OpenChatMenu(anchor)
    local original = ChatFrameMenuButton
    local click = original and original:GetScript("OnClick")
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
    row:SetSize(4 * SIZE + 3 * GAP + 20, SIZE)
    row:SetPoint("BOTTOMRIGHT", ChatFrame1, "TOPRIGHT", 0, 8)
    row:SetFrameLevel(host:GetFrameLevel() + 5)
    self.frame = row

    local full = ns.IconButton(row, "FullScreen", SIZE, "Full screen", "The chat over the whole screen: select any line and copy it (Ctrl+C), click links.")
    full:SetPoint("RIGHT", 0, 0)
    full:SetScript("OnClick", function() ns.FullScreen:Toggle() end)

    local menu = ns.IconButton(row, "Menu", SIZE, "Chat menu", "Emotes, languages, and the chat settings.")
    menu:SetPoint("RIGHT", full, "LEFT", -GAP, 0)
    menu:SetScript("OnClick", function(self) OpenChatMenu(self) end)

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

    -- The game's buttons for these: out of sight (their column is gone too, Skin.lua).
    for _, name in ipairs({ "FriendsMicroButton", "QuickJoinToastButton", "ChatFrameChannelButton", "ChatFrameMenuButton",
        "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton" }) do
        KeepHidden(_G[name])
    end
end

function Bar:Count()
    if self.friends then self.friends.count:SetText(OnlineFriends()) end
end

-- ---------------------------------------------------------------------------------------------
-- Back to the newest message, in each window
-- ---------------------------------------------------------------------------------------------

local jumps = setmetatable({}, { __mode = "k" }) -- chat frame -> its button

local function Jump(cf)
    local b = jumps[cf]
    if b then return b end
    b = ns.IconButton(cf, "Bottom", 14, "Newest messages", nil)
    b:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 0, 0)
    b:SetFrameLevel(cf:GetFrameLevel() + 5)
    b:SetScript("OnClick", function() cf:ScrollToBottom() end)
    b:Hide()
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
            b:SetShown(not cf:AtBottom())
        end
    end
end)

ns:On("PLAYER_LOGIN", function() C_Timer.After(0, function() Bar:Build() end) end)
for _, e in ipairs({ "FRIENDLIST_UPDATE", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE", "BN_FRIEND_LIST_SIZE_CHANGED" }) do
    ns:On(e, function() Bar:Count() end)
end
