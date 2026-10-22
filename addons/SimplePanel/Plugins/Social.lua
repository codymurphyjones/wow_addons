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

-- Your Away and Busy flags. WoW Forever (the 12.x engine's restrictions) can hand these back as
-- hidden "secret" values, and any test on one is an error. Then we keep showing the last value we
-- could read and say it may be out of date.
local away = { afk = false, dnd = false, stale = false }
local STALE_REASON = "The game is hiding your Away/Busy status from addons right now (it does this in combat and in some instances), so this is the last status SimplePanel could read."

local function ReadFlag(fn)
    local ok, v = pcall(fn, "player")
    if not ok or (issecretvalue and issecretvalue(v)) then return nil end
    return v and true or false
end

-- afk, dnd, stale
local function AwayFlags()
    local afk, dnd = ReadFlag(UnitIsAFK), ReadFlag(UnitIsDND)
    if afk == nil or dnd == nil then
        away.stale = true
    else
        away.afk, away.dnd, away.stale = afk, dnd, false
    end
    return away.afk, away.dnd, away.stale
end

local function Say(msg)
    local s = Settings()
    if s and s.announce then ns:Print(msg, true) end
end

-- Names are WoW Forever's realmless "Given Family", and arrive as "Given Family", "GivenFamily"
-- or "Given Family-Server": every comparison goes through Compat.SamePlayer, which takes them all.
local C = ns.Compat
local Same = C.SamePlayer

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
        if friend and Same(friend, name) then return true end
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
        if member and Same(member, name) then return true end
    end
    return false
end

-- What the Fireside addon knows of a player (FiresideAPI.Get), or nil.
local function History(name, guid)
    if not (name and FiresideAPI and FiresideAPI.Get) then return nil end
    local ok, info = pcall(FiresideAPI.Get, C.FullName(name, guid), guid)
    return ok and info or nil
end

local function HasHistory() return FiresideAPI ~= nil and FiresideAPI.Get ~= nil end

-- Whether name is in your group: each member's "Given Family" against it.
local function InMyGroup(name)
    for _, unit in ipairs(ns.Units.GroupUnits()) do
        if Same(ns.Units.UnitFull(unit), name) then return true end
    end
    return false
end

-- Past groupmates you'd group with again (Fireside) count too, while that switch is on.
local function IsKnown(name, guid)
    if not name then return false end
    if InMyGroup(name) then return true end
    if IsFriend(name, guid) or IsGuildmate(name, guid) then return true end
    local s = Settings()
    local h = s and s.knownFromHistory and History(name, guid)
    return h and (h.rating or 0) > 0 or false
end

-- ---------------------------------------------------------------------------
-- Looking for Group: while you're listed, strangers inviting you is the point
-- ---------------------------------------------------------------------------

local LFG = C_LFGList

local function Readable(v) return not (issecretvalue and issecretvalue(v)) end

-- Every value fn returns, or nothing when it errors.
local function Call(fn, ...)
    if not fn then return end
    local r = { pcall(fn, ...) }
    if not r[1] then return end
    return unpack(r, 2, table.maxn(r))
end

local function SameName(a, b) return type(a) == "string" and Readable(a) and Same(a, b) end

-- Whether you're listed in the Looking for Group tool yourself.
local function IsListed()
    if not LFG then return false end
    local v = Call(LFG.HasActiveEntryInfo)
    return Readable(v) and v == true
end

-- Whether name leads or is in a listing from the last Looking for Group search. A leader who
-- browses without listing their group can't be seen.
local function InviterListed(name)
    if not (LFG and name) then return false end
    local a, b = Call(LFG.GetSearchResults)
    local ids = type(a) == "table" and a or b
    if type(ids) ~= "table" then return false end
    for _, id in ipairs(ids) do
        local info = Call(LFG.GetSearchResultInfo, id)
        if type(info) == "table" and not info.isDelisted then
            if SameName(info.leaderName, name) then return true end
            for i = 1, tonumber(info.numMembers) or 0 do
                -- Clients differ on where the member's name sits, so test every string returned.
                local r = { Call(LFG.GetSearchResultMemberInfo, id, i) }
                for j = 1, table.maxn(r) do
                    if SameName(r[j], name) then return true end
                end
            end
        end
    end
    return false
end

local LFG_PAUSED = "Paused while you're listed in Looking for Group. Invites from players who are also listed get through; others are declined."

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

local function OwnSwitch(key, text, tooltip, block, short, paused)
    return {
        text = text, tooltip = tooltip, block = block, short = short, paused = paused,
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
-- row of interaction rules: open or blocked, one per kind. `paused` returns why a switch is set
-- aside for now, if it is; a paused switch neither blocks nor counts, whatever its value.

-- Switches that only exist with the Fireside addon.
local function HistorySwitch(sw)
    sw.available, sw.hideUnavailable = HasHistory, true
    return sw
end

-- Guild invites: the client's own switch where there is one, ours otherwise.
local function ClientGuildSwitch() return GetAutoDeclineGuildInvites ~= nil and SetAutoDeclineGuildInvites ~= nil end

local SWITCHES = {
    { header = "Requests" },
    OwnSwitch("declineDuels", "Decline duels", "Turns every duel request down as it arrives.", true, "No duels"),

    OwnSwitch("declineStrangerInvites", "Decline group invites from strangers",
        "Group invites from anyone who isn't a friend, a Battle.net friend or in your guild are turned down. While you're listed in Looking for Group this is set aside: invites from players who are also listed get through, others are declined.",
        true, "No stranger invites", function() return IsListed() and LFG_PAUSED or nil end),
    OwnSwitch("acceptKnownInvites", "Accept group invites from friends and guild",
        "Joins straight away when a friend, Battle.net friend or guildmate invites you.", false, "Auto-join"),
    -- With the Fireside addon: whether you'd group with past groupmates again.
    HistorySwitch(OwnSwitch("knownFromHistory", "Treat players you'd group with again as known",
        "Past groupmates you marked \"would group again\" in Fireside count like friends: their invites aren't declined as a stranger's, their whispers aren't hidden, and Accept group invites joins them too.")),
    HistorySwitch(OwnSwitch("declineRatedDown", "Decline group invites from players you wouldn't group with again",
        "Group invites from anyone you marked \"wouldn't group again\" in Fireside are turned down, even while you're listed in Looking for Group.", true, "No invites from players you'd avoid")),
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
        get = function() return (AwayFlags()) end,
        set = function() SendFlag("AFK") end,
    },
    {
        text = "Busy (Do Not Disturb)", tooltip = "Marks you as busy, the same as /dnd. Whispers get an automatic reply.",
        get = function() local _, dnd = AwayFlags(); return dnd end,
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
local function Paused(sw) return sw.paused and sw.paused() end
local PAUSED_TAG = T.hex.yellow .. "Paused (LFG)|r"

-- How many of the blocking switches are on.
local function ActiveCount()
    local n = 0
    for _, sw in ipairs(SWITCHES) do
        if sw.block and Available(sw) and not Paused(sw) and sw.get() then n = n + 1 end
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
        elseif include and (Available(sw) or not sw.hideUnavailable) then
            local ok = Available(sw)
            m:Checkbox({
                -- A paused switch stays clickable, with the reason after its name.
                text = function() return Paused(sw) and (sw.text .. "  " .. PAUSED_TAG) or sw.text end,
                tooltip = ok and (Paused(sw) or sw.tooltip) or "This client doesn't have this setting.",
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
    Say("declined a duel from " .. tostring(C.PlayerName(name)) .. ".")
end)

-- A stranger's invite while you're listed: it gets through if they're listed too. When the last
-- search doesn't show them, the search is run again and the popup waits up to 3 seconds for it.
local pending -- { name, token }: the invite waiting on that search
local token = 0

local function SettleLFG(t, listed)
    if not pending or pending.token ~= t then return end
    local name = pending.name
    pending = nil
    if listed then
        Say("let a group invite from " .. tostring(name) .. " through: you're both listed in Looking for Group.")
    elseif not IsInGroup() then
        DeclineGroup()
        HidePopup("PARTY_INVITE")
        Say("declined a group invite from " .. tostring(name) .. ": you're listed in Looking for Group, but they aren't.")
    end
end

local function CheckLFGInvite(name)
    token = token + 1
    local t = token
    pending = { name = name, token = t }
    if InviterListed(name) then return SettleLFG(t, true) end
    if not (LFG.RefreshResults and pcall(LFG.RefreshResults)) then return SettleLFG(t, false) end
    C_Timer.After(3, function() SettleLFG(t, InviterListed(name)) end)
end

ns:On("LFG_LIST_SEARCH_RESULTS_RECEIVED", function()
    if pending and InviterListed(pending.name) then SettleLFG(pending.token, true) end
end)
ns:On("PARTY_INVITE_CANCEL", function() pending = nil end)
ns:On("GROUP_ROSTER_UPDATE", function() pending = nil end)

ns:On("PARTY_INVITE_REQUEST", function(name, ...)
    local s = Settings()
    if not s then return end
    local guid = select(6, ...)
    -- The inviter's "Given Family" (from the GUID when the event gives only the given name).
    name = C.FullName(name, guid) or name
    if s.declineRatedDown then
        local h = History(name, guid)
        if h and (h.rating or 0) < 0 then
            DeclineGroup()
            HidePopup("PARTY_INVITE")
            Say("declined a group invite from " .. tostring(name) .. ": you marked them 'wouldn't group again' in Fireside.")
            return
        end
    end
    local known = IsKnown(name, guid)
    if known and s.acceptKnownInvites then
        AcceptGroup()
        HidePopup("PARTY_INVITE")
        Say("joined " .. tostring(name) .. "'s group.")
    elseif not known and IsListed() then
        CheckLFGInvite(name)
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
    Say("declined an invite to " .. tostring(guild or "a guild") .. " from " .. tostring(C.PlayerName(inviter)) .. ".")
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
    local afk, dnd, stale = AwayFlags()
    local dot = dnd and DOTS.busy or (afk and DOTS.away or DOTS.online)
    local segs = { { icon = dot, fullIcon = true, text = "" } }
    -- A small "?" after the dot while the status shown is only the last one we could read.
    if stale then segs[#segs + 1] = { text = "?", color = T.muted } end
    local n = ActiveCount()
    if n > 0 then segs[2] = { icon = SHIELD, text = tostring(n), color = T.accent } end
    return segs
end

-- Words for the same thing, for tooltips.
-- state, number of blocks, stale (the state is the last one we could read), and why.
local function StatusWords()
    local n = ActiveCount()
    local afk, dnd, stale = AwayFlags()
    local state = dnd and "Busy" or (afk and "Away" or "Available")
    return state, n, stale, stale and STALE_REASON or nil
end

-- Your interaction rules, one per kind of request: { topic, open, switch }.
local function Rules()
    local out = {}
    for _, sw in ipairs(SWITCHES) do
        if sw.topic and Available(sw) then out[#out + 1] = { topic = sw.topic, open = Paused(sw) ~= nil or not sw.get(), switch = sw } end
    end
    return out
end

-- The switches with a bar label that are on right now.
local function ActiveLabels()
    local out = {}
    for _, sw in ipairs(SWITCHES) do
        if sw.short and Available(sw) and not Paused(sw) and sw.get() then out[#out + 1] = sw end
    end
    return out
end

ns.SocialShared = {
    SWITCHES = SWITCHES, Available = Available, Paused = Paused, ActiveCount = ActiveCount, AddSwitches = AddSwitches,
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

-- Listing or delisting pauses the stranger-invite switch; tell the plugins that show it.
ns:On("LFG_LIST_ACTIVE_ENTRY_UPDATE", function()
    for _, fn in ipairs(ns.SocialShared.listeners) do fn() end
end)

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
        knownFromHistory = true, declineRatedDown = false,
    },
    events = { "PLAYER_FLAGS_CHANGED", "CVAR_UPDATE", "LFG_LIST_ACTIVE_ENTRY_UPDATE" },

    text = function() return Status() end,

    tooltip = function(_, tt)
        local state, n, stale, why = StatusWords()
        tt:AddDouble("You are", state .. (stale and " (?)" or ""), nil, state == "Busy" and T.red or (state == "Away" and T.yellow or T.green))
        if stale then tt:AddLine("May be out of date: " .. why, T.muted, true) end
        tt:AddDouble("Blocks on", tostring(n), nil, n > 0 and T.accent or T.muted)
        for _, sw in ipairs(SWITCHES) do
            if sw.header then
                tt:AddHeader(sw.header)
            elseif Available(sw) then
                local on, paused = sw.get(), Paused(sw)
                tt:AddDouble(sw.text, paused and "Paused (LFG)" or (on and "On" or "Off"), T.text, paused and T.yellow or (on and T.green or T.muted))
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
