local _, ns = ...

-- Social: one drop-down of on/off switches for the things other players can push at you.
--
-- Where the game already has a setting (trades, channel invites, the language filter, guild
-- invites on clients that have it, away and busy) the switch is a view of that setting rather
-- than a copy, so the game's options and this menu can never disagree. The rest SimplePanel does
-- itself, and keeps doing while the plugin is hidden from the bar.
local T = SimplePanel.Theme

local p -- the plugin, set below

local function Settings()
    local l = ns.db and ns.db.plugins.Social
    return l and l.settings
end

local function Say(msg)
    local s = Settings()
    if s and s.announce then ns:Print(msg, true) end
end

local function Short(name) return name and name:match("^[^%-]+") end

-- ---------------------------------------------------------------------------
-- Who counts as someone you know: friends, Battle.net friends, guild, group
-- ---------------------------------------------------------------------------

local function IsFriend(name, guid)
    local FL = C_FriendList
    if guid and FL and FL.IsFriend then
        local ok, yes = pcall(FL.IsFriend, guid)
        if ok and yes then return true end
    end
    local n = (FL and FL.GetNumFriends and FL.GetNumFriends()) or (GetNumFriends and GetNumFriends()) or 0
    for i = 1, n do
        local friend
        if FL and FL.GetFriendInfoByIndex then
            local info = FL.GetFriendInfoByIndex(i)
            friend = info and info.name
        elseif GetFriendInfo then
            friend = GetFriendInfo(i)
        end
        if friend and Short(friend) == Short(name) then return true end
    end
    if guid and C_BattleNet and C_BattleNet.GetGameAccountInfoByGUID then
        local ok, info = pcall(C_BattleNet.GetGameAccountInfoByGUID, guid)
        if ok and info then return true end
    end
    return false
end

local function IsGuildmate(name, guid)
    if guid and IsGuildMember then
        local ok, yes = pcall(IsGuildMember, guid)
        if ok and yes then return true end
    end
    if not (IsInGuild and IsInGuild() and GetNumGuildMembers) then return false end
    for i = 1, GetNumGuildMembers() or 0 do
        local member = GetGuildRosterInfo(i)
        if member and Short(member) == Short(name) then return true end
    end
    return false
end

local function IsKnown(name, guid)
    if not name then return false end
    if UnitInParty and (UnitInParty(Short(name)) or UnitInRaid(Short(name))) then return true end
    return IsFriend(name, guid) or IsGuildmate(name, guid)
end

-- ---------------------------------------------------------------------------
-- The switches
-- ---------------------------------------------------------------------------

local function HasCVar(name)
    if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) ~= nil end
    return GetCVar and GetCVar(name) ~= nil
end

local function CVarSwitch(cvar, text, tooltip, block, short)
    return {
        text = text, tooltip = tooltip, block = block, short = short,
        available = function() return HasCVar(cvar) end,
        get = function() return GetCVarBool(cvar) and true or false end,
        set = function(v) SetCVar(cvar, v and "1" or "0") end,
    }
end

local function OwnSwitch(key, text, tooltip, block, short)
    return {
        text = text, tooltip = tooltip, block = block, short = short,
        get = function() return Settings()[key] and true or false end,
        set = function(v) Settings()[key] = v and true or false end,
    }
end

local function SendFlag(flag)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    send("", flag)
end

-- `block = true` marks the switches the bar counts ("3 blocks"); `short` names a switch that's on
-- ("No duels"); `topic` is the kind of request it blocks ("Duels"), for the Full Social Plugin's
-- row of interaction rules: open or blocked, one per kind.

-- Guild invites: the client's own switch where there is one, ours otherwise.
local function ClientGuildSwitch() return GetAutoDeclineGuildInvites ~= nil and SetAutoDeclineGuildInvites ~= nil end

local SWITCHES = {
    { header = "Requests" },
    OwnSwitch("declineDuels", "Decline duels", "Turns every duel request down as it arrives.", true, "No duels"),

    OwnSwitch("declineStrangerInvites", "Decline group invites from strangers",
        "Group invites from anyone who isn't a friend, a Battle.net friend or in your guild are turned down.", true, "No stranger invites"),
    OwnSwitch("acceptKnownInvites", "Accept group invites from friends and guild",
        "Joins straight away when a friend, Battle.net friend or guildmate invites you.", false, "Auto-join"),
    {
        text = "Decline guild invites", tooltip = "Turns down invitations to join a guild.", block = true, short = "No guild invites",
        get = function()
            if ClientGuildSwitch() then local v = GetAutoDeclineGuildInvites(); return v == true or v == 1 end
            return Settings().declineGuild and true or false
        end,
        set = function(v)
            if ClientGuildSwitch() then
                if not pcall(SetAutoDeclineGuildInvites, v) then SetAutoDeclineGuildInvites(v and 1 or 0) end
            else
                Settings().declineGuild = v and true or false
            end
        end,
    },
    CVarSwitch("blockTrades", "Block trades", "Nobody can open a trade window with you.", true, "No trades"),
    CVarSwitch("blockChannelInvites", "Block channel invites", "Invitations to custom chat channels are ignored.", true, "No channel invites"),

    { header = "Chat" },
    OwnSwitch("hideStrangerWhispers", "Hide whispers from strangers",
        "Whispers from anyone who isn't a friend, a Battle.net friend, in your guild or in your group are hidden. Game Masters always get through.", true, "Stranger whispers hidden"),
    CVarSwitch("profanityFilter", "Mature language filter", "The game's own filter for strong language in chat."),

    { header = "Status" },
    {
        text = "Away (AFK)", tooltip = "Marks you as away, the same as /afk.",
        get = function() return UnitIsAFK("player") and true or false end,
        set = function() SendFlag("AFK") end,
    },
    {
        text = "Busy (Do Not Disturb)", tooltip = "Marks you as busy, the same as /dnd. Whispers get an automatic reply.",
        get = function() return UnitIsDND("player") and true or false end,
        set = function() SendFlag("DND") end,
    },

    { header = "SimplePanel" },
    OwnSwitch("announce", "Say in chat when something is declined", "A line in chat for each duel, invite or trade turned down."),
}

-- The kind of request each blocking switch is about.
local TOPICS = {
    ["Decline duels"] = "Duels",
    ["Decline group invites from strangers"] = "Invites",
    ["Decline guild invites"] = "Guild",
    ["Block trades"] = "Trades",
    ["Block channel invites"] = "Channels",
    ["Hide whispers from strangers"] = "Whispers",
}
for _, sw in ipairs(SWITCHES) do sw.topic = sw.text and TOPICS[sw.text] end

local function Available(sw) return not sw.available or sw.available() end

-- How many of the blocking switches are on.
local function ActiveCount()
    local n = 0
    for _, sw in ipairs(SWITCHES) do
        if sw.block and Available(sw) and sw.get() then n = n + 1 end
    end
    return n
end

-- Adds the switches under the given headings (all of them without a list).
local function AddSwitches(m, groups)
    local include = true
    for _, sw in ipairs(SWITCHES) do
        if sw.header then
            include = not groups or groups[sw.header]
            if include then m:Header(sw.header) end
        elseif include then
            local ok = Available(sw)
            m:Checkbox({
                text = sw.text,
                tooltip = ok and sw.tooltip or "This client doesn't have this setting.",
                disabled = not ok,
                get = function() return ok and sw.get() end,
                set = function(v) ns.SocialShared.SetSwitch(sw, v) end,
            })
        end
    end
end

-- ---------------------------------------------------------------------------
-- Doing the declining. Registered here rather than on the plugin, so a block keeps working even
-- while the Social button is hidden from the bar.
-- ---------------------------------------------------------------------------

local function HidePopup(which) if StaticPopup_Hide then StaticPopup_Hide(which) end end

ns:On("DUEL_REQUESTED", function(name)
    local s = Settings()
    if not (s and s.declineDuels) then return end
    CancelDuel()
    HidePopup("DUEL_REQUESTED")
    Say("declined a duel from " .. tostring(name) .. ".")
end)

ns:On("PARTY_INVITE_REQUEST", function(name, ...)
    local s = Settings()
    if not s then return end
    local guid = select(6, ...)
    local known = IsKnown(name, guid)
    if known and s.acceptKnownInvites then
        AcceptGroup()
        HidePopup("PARTY_INVITE")
        Say("joined " .. tostring(name) .. "'s group.")
    elseif not known and s.declineStrangerInvites then
        DeclineGroup()
        HidePopup("PARTY_INVITE")
        Say("declined a group invite from " .. tostring(name) .. ".")
    end
end)

ns:On("GUILD_INVITE_REQUEST", function(inviter, guild)
    local s = Settings()
    if ClientGuildSwitch() or not (s and s.declineGuild) then return end
    DeclineGuild()
    HidePopup("GUILD_INVITE")
    Say("declined an invite to " .. tostring(guild or "a guild") .. " from " .. tostring(inviter) .. ".")
end)

local function WhisperFilter(_, _, _, author, _, _, _, flags, _, _, _, _, _, guid)
    local s = Settings()
    if not (s and s.hideStrangerWhispers) or flags == "GM" or flags == "DEV" then return false end
    return not IsKnown(author, guid)
end
if ChatFrame_AddMessageEventFilter then ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", WhisperFilter) end

-- The switches are shared with the Full Social Plugin, which shows them next to who's online. There
-- is only one set of them, and one set of the handlers above, so the two never decline anything twice.
-- The game's own friend-list status dots: available, Away, Busy.
local DOTS = {
    online = "Interface\\FriendsFrame\\StatusIcon-Online",
    away = "Interface\\FriendsFrame\\StatusIcon-Away",
    busy = "Interface\\FriendsFrame\\StatusIcon-DnD",
}
local SHIELD = "Interface\\Icons\\Spell_Holy_PowerWordShield"

-- What the bar shows, as segments: a status dot (green available, yellow Away, red Busy), then a
-- shield with the number of blocks that are on, if any.
local function Status()
    local dot = UnitIsDND("player") and DOTS.busy or (UnitIsAFK("player") and DOTS.away or DOTS.online)
    local segs = { { icon = dot, fullIcon = true, text = "" } }
    local n = ActiveCount()
    if n > 0 then segs[2] = { icon = SHIELD, text = tostring(n), color = T.accent } end
    return segs
end

-- Words for the same thing, for tooltips.
local function StatusWords()
    local n = ActiveCount()
    local state = UnitIsDND("player") and "Busy" or (UnitIsAFK("player") and "Away" or "Available")
    return state, n
end

-- Your interaction rules, one per kind of request: { topic, open, switch }.
local function Rules()
    local out = {}
    for _, sw in ipairs(SWITCHES) do
        if sw.topic and Available(sw) then out[#out + 1] = { topic = sw.topic, open = not sw.get(), switch = sw } end
    end
    return out
end

-- The switches with a bar label that are on right now.
local function ActiveLabels()
    local out = {}
    for _, sw in ipairs(SWITCHES) do
        if sw.short and Available(sw) and sw.get() then out[#out + 1] = sw end
    end
    return out
end

ns.SocialShared = {
    SWITCHES = SWITCHES, Available = Available, ActiveCount = ActiveCount, AddSwitches = AddSwitches,
    Settings = Settings, Status = Status, StatusWords = StatusWords, ActiveLabels = ActiveLabels, Rules = Rules,
    AutoJoin = function() return Settings() and Settings().acceptKnownInvites and true or false end,
    OPEN_ICON = "Interface\\RaidFrame\\ReadyCheck-Ready", BLOCKED_ICON = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    listeners = {},
}

-- Flips a switch and tells every plugin that shows them.
function ns.SocialShared.SetSwitch(sw, v)
    sw.set(v)
    if p then p:Refresh() end
    for _, fn in ipairs(ns.SocialShared.listeners) do fn() end
end

-- ---------------------------------------------------------------------------
-- The plugin
-- ---------------------------------------------------------------------------

p = SimplePanel.RegisterPlugin({
    id = "Social",
    name = "Social",
    category = "Social",
    icon = 132311,
    zone = "right",
    label = "Social",
    defaults = {
        declineDuels = false, declineStrangerInvites = false, acceptKnownInvites = false,
        declineGuild = false, hideStrangerWhispers = false, announce = true,
    },
    events = { "PLAYER_FLAGS_CHANGED", "CVAR_UPDATE" },

    text = function() return Status() end,

    tooltip = function(_, tt)
        local state, n = StatusWords()
        tt:AddDouble("You are", state, nil, state == "Busy" and T.red or (state == "Away" and T.yellow or T.green))
        tt:AddDouble("Blocks on", tostring(n), nil, n > 0 and T.accent or T.muted)
        for _, sw in ipairs(SWITCHES) do
            if sw.header then
                tt:AddHeader(sw.header)
            elseif Available(sw) then
                local on = sw.get()
                tt:AddDouble(sw.text, on and "On" or "Off", T.text, on and T.green or T.muted)
            end
        end
        tt:AddHint("Click: switches  ·  Right-click: options")
    end,

    menu = function(_, m) AddSwitches(m) end,

    onClick = function(plugin, button)
        if button ~= "LeftButton" then return end
        local m = ns.Menu:New(plugin.button)
        m:Title("Social", plugin.icon)
        AddSwitches(m)
        m:Show(plugin.button)
    end,
})
