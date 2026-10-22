local _, ns = ...
local C, M = ns.Compat, ns.Media

-- A small marker next to friends (Battle.net or character friends) and guild members.
local Social = { name = "Social" }
-- By name in any of its shapes ("Given Family", "GivenFamily", "Given Family-Server", or the given
-- name alone): C.NameSet.
local friends, guild = C.NameSet(), C.NameSet()

local function Rebuild()
    C.NameSetWipe(friends); C.NameSetWipe(guild)
    if C_FriendList and C_FriendList.GetNumFriends then
        for i = 1, C_FriendList.GetNumFriends() or 0 do
            local info = C_FriendList.GetFriendInfoByIndex(i)
            if info and info.name then C.NameSetAdd(friends, info.name) end
        end
    end
    if BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
        for i = 1, BNGetNumFriends() or 0 do
            local acc = C_BattleNet.GetFriendAccountInfo(i)
            local game = acc and acc.gameAccountInfo
            if game and game.characterName then C.NameSetAdd(friends, game.characterName) end
        end
    end
    if IsInGuild() and GetNumGuildMembers then
        for i = 1, GetNumGuildMembers() or 0 do
            local name = GetGuildRosterInfo(i)
            if name then C.NameSetAdd(guild, name) end
        end
    end
end

function Social:Create(f)
    local t = (f.textLayer or f):CreateTexture(nil, "OVERLAY")
    t:SetSize(12, 12)
    t:Hide()
    f.social = t
end

function Social:Update(f)
    local u, t = f.unit, f.social
    local look = u.isPlayer and u.reaction == "FRIENDLY" and ns.db.widgets.social
    local kind = look and (C.NameSetFind(friends, u.unitid) and "friend" or C.NameSetFind(guild, u.unitid) and "guild")
    if not kind then return t:Hide() end
    if kind == "friend" then
        t:SetTexture("Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon")
        t:SetVertexColor(1, 1, 1, 1)
    else
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        t:SetVertexColor(0.25, 1, 0.25, 1)
        t:SetSize(6, 6)
    end
    if kind == "friend" then t:SetSize(14, 14) end
    t:ClearAllPoints()
    t:SetPoint("LEFT", f.name, "RIGHT", 3, 0)
    t:Show()
end

function Social:Clear(f) f.social:Hide() end

ns.Plates:Register(Social)

local pending
local function Refresh()
    if pending then return end
    pending = true
    C_Timer.After(1, function()
        pending = false
        Rebuild()
        ns.Plates:Each(function(f) Social:Update(f) end)
    end)
end
ns:On("FRIENDLIST_UPDATE", Refresh)
ns:On("BN_FRIEND_INFO_CHANGED", Refresh)
ns:On("GUILD_ROSTER_UPDATE", Refresh)
ns:On("PLAYER_ENTERING_WORLD", Refresh)
