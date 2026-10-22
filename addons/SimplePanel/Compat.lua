local _, ns = ...

-- Normalizes APIs that moved between clients (C_AddOns, currencies, quests, loot...). Money, bags,
-- items, map coordinates, skills and player names come from the shared files (addons/shared):
-- Format.lua, Items.lua, WorldMap.lua, Player.lua and Units.lua.
local Compat = {}
ns.Compat = Compat

local CA = C_AddOns
local F, I = ns.Format, ns.Items

-- ---------------------------------------------------------------------------
-- Add-ons, memory and CPU
-- ---------------------------------------------------------------------------

function Compat.GetNumAddOns()
    if CA and CA.GetNumAddOns then return CA.GetNumAddOns() end
    return GetNumAddOns()
end

-- name, title
function Compat.GetAddOnInfo(i)
    if CA and CA.GetAddOnInfo then
        local name, title = CA.GetAddOnInfo(i)
        return name, title
    end
    local name, title = GetAddOnInfo(i)
    return name, title
end

function Compat.IsAddOnLoaded(name)
    if CA and CA.IsAddOnLoaded then return CA.IsAddOnLoaded(name) end
    return IsAddOnLoaded(name)
end

function Compat.UpdateAddOnMemoryUsage() if UpdateAddOnMemoryUsage then UpdateAddOnMemoryUsage() end end
function Compat.GetAddOnMemoryUsage(i) return GetAddOnMemoryUsage and GetAddOnMemoryUsage(i) or 0 end

-- CPU numbers only mean something while the scriptProfile CVar is on.
function Compat.CPUProfiling()
    return GetCVarBool and GetCVarBool("scriptProfile") and GetAddOnCPUUsage ~= nil
end
function Compat.UpdateAddOnCPUUsage() if UpdateAddOnCPUUsage then UpdateAddOnCPUUsage() end end
function Compat.GetAddOnCPUUsage(i) return GetAddOnCPUUsage and GetAddOnCPUUsage(i) or 0 end

-- ---------------------------------------------------------------------------
-- Money
-- ---------------------------------------------------------------------------

function Compat.Money(copper) return F.Money(copper) end

-- Short money with coin icons, for the bar's gold: "123[g] 45[s]" / "45[s] 12[c]".
function Compat.CoinMoney(copper) return F.Money(copper, F.MONEY_COIN) end

-- Short money text with letters: "123g 45s" / "45s 12c" (compact: the session change).
function Compat.ShortMoney(copper) return F.Money(copper, F.MONEY_LETTERS) end

-- ---------------------------------------------------------------------------
-- Bags
-- ---------------------------------------------------------------------------

Compat.NUM_BAGS = I.NUM_BAGS
Compat.GetNumSlots = I.GetNumSlots
Compat.GetFreeSlots = I.GetFreeSlots -- free, family (0 = normal bag)
Compat.GetBagName = I.GetBagName

-- ---------------------------------------------------------------------------
-- Map
-- ---------------------------------------------------------------------------

-- x, y in 0..100, or nil inside instances.
function Compat.PlayerCoords()
    local x, y = ns.WorldMap.PlayerPos()
    if x then return x * 100, y * 100 end
end

-- ---------------------------------------------------------------------------
-- Items and currencies
-- ---------------------------------------------------------------------------

function Compat.ItemCount(itemID) return I.ItemCount(itemID) end

-- start, duration (0, 0 when ready), enable
function Compat.ItemCooldown(itemID) return I.ItemCooldown(itemID) end

-- name, quantity, maxQuantity (0 = no cap), icon; nil for an unknown currency.
function Compat.CurrencyInfo(id)
    local CI = C_CurrencyInfo
    if CI and CI.GetCurrencyInfo then
        local info = CI.GetCurrencyInfo(id)
        if not info or not info.name or info.name == "" then return nil end
        return info.name, info.quantity or 0, info.maxQuantity or 0, info.iconFileID
    end
    if GetCurrencyInfo then
        local name, amount, icon, _, _, max = GetCurrencyInfo(id)
        if not name or name == "" then return nil end
        return name, amount or 0, max or 0, icon
    end
end

-- The currencies on this character's currency tab: { id, name } (headers left out).
function Compat.CurrencyList()
    local out = {}
    local CI = C_CurrencyInfo
    local size = (CI and CI.GetCurrencyListSize and CI.GetCurrencyListSize()) or (GetCurrencyListSize and GetCurrencyListSize()) or 0
    for i = 1, size do
        local name, header, id
        if CI and CI.GetCurrencyListInfo then
            local info = CI.GetCurrencyListInfo(i)
            if info then name, header = info.name, info.isHeader end
        elseif GetCurrencyListInfo then
            name, header = GetCurrencyListInfo(i)
        end
        local link = (CI and CI.GetCurrencyListLink and CI.GetCurrencyListLink(i)) or (GetCurrencyListLink and GetCurrencyListLink(i))
        id = link and tonumber(link:match("currency:(%d+)"))
        if name and not header and id then out[#out + 1] = { id = id, name = name } end
    end
    return out
end

-- name, link, quality, ..., icon (the classic GetItemInfo returns)
Compat.ItemInfo = I.GetItemInfo
Compat.ItemIcon = I.ItemIcon

function Compat.IsSpellKnown(id)
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    return IsSpellKnown and IsSpellKnown(id) and true or false
end

function Compat.SpellName(id)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        return info and info.name
    end
    return GetSpellInfo and (GetSpellInfo(id))
end

function Compat.SpellIcon(id)
    local fn = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture
    return fn and fn(id) or nil
end

-- ---------------------------------------------------------------------------
-- Skills: primary professions and the secondary ones (Cooking, First Aid, Fishing)
-- ---------------------------------------------------------------------------

-- { { name, rank, max, primary } ... }: primaries first, then by name (shared Player.lua).
function Compat.Skills() return ns.Player.Skills() end

-- What the game hands back, line by line, for when Skills() finds nothing it recognises.
function Compat.SkillsReport()
    local lines = {}
    lines[#lines + 1] = ("GetProfessions: %s, GetNumSkillLines: %s"):format(GetProfessions and "yes" or "no",
        GetNumSkillLines and tostring(GetNumSkillLines()) or "no")
    if GetProfessions then
        local slots = { GetProfessions() }
        for i = 1, 6 do
            local index = slots[i]
            if index and GetProfessionInfo then
                local ok, name, _, rank, max = pcall(GetProfessionInfo, index)
                lines[#lines + 1] = ("  profession %d: %s %s/%s"):format(i, ok and tostring(name) or "error", tostring(rank), tostring(max))
            end
        end
    end
    if GetNumSkillLines and GetSkillLineInfo then
        for i = 1, GetNumSkillLines() or 0 do
            local name, header, expanded, rank, _, _, max, abandonable = GetSkillLineInfo(i)
            lines[#lines + 1] = header and ("  [%s]%s"):format(tostring(name), expanded and "" or " (collapsed)")
                or ("    %s %s/%s%s"):format(tostring(name), tostring(rank), tostring(max), abandonable and " (profession)" or "")
        end
    end
    return lines
end

-- ---------------------------------------------------------------------------
-- Group loot
-- ---------------------------------------------------------------------------

-- Loot methods by name; C_PartyInfo numbers them (LOOT_BY_NUMBER).
Compat.LOOT_METHODS = { "freeforall", "roundrobin", "master", "group", "needbeforegreed" }
local LOOT_BY_NUMBER = { [0] = "freeforall", [1] = "roundrobin", [2] = "master", [3] = "group", [4] = "needbeforegreed", [5] = "personalloot" }

-- method name, master looter party index (or nil)
function Compat.LootMethod()
    local fn = (C_PartyInfo and C_PartyInfo.GetLootMethod) or GetLootMethod
    if not fn then return nil end
    local method, partyMaster = fn()
    if type(method) == "number" then method = LOOT_BY_NUMBER[method] end
    return method, partyMaster
end

function Compat.SetLootMethod(method, who)
    local fn = (C_PartyInfo and C_PartyInfo.SetLootMethod) or SetLootMethod
    if not fn then return end
    if C_PartyInfo and fn == C_PartyInfo.SetLootMethod and Enum and Enum.LootMethod then
        for n, name in pairs(LOOT_BY_NUMBER) do if name == method then return fn(n, who) end end
    end
    fn(method, who)
end

-- ---------------------------------------------------------------------------
-- Auras
-- ---------------------------------------------------------------------------

-- Every helpful aura on a unit as { name, icon, spellId, expires, duration }.
function Compat.Buffs(unit)
    local out = {}
    for i = 1, 40 do
        local name, icon, duration, expires, spellId
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local a = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
            if not a then break end
            name, icon, duration, expires, spellId = a.name, a.icon, a.duration, a.expirationTime, a.spellId
        elseif UnitBuff then
            local _
            name, icon, _, _, duration, expires, _, _, _, spellId = UnitBuff(unit, i)
            if not name then break end
        else
            break
        end
        out[#out + 1] = { name = name, icon = icon, spellId = spellId, expires = expires, duration = duration }
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Friends and guild
-- ---------------------------------------------------------------------------

-- A player name as you'd type it, show it and send it (whisper, invite, guild and friend calls):
-- WoW Forever's realmless "Given Family". Names come from the game as "Given Family",
-- "Given Family-Server" or (older saves) "Given-Family"; all give "Given Family". A name with one
-- word ("Aranalia", UnitName's first value) stays as it is. A hidden or empty name comes back as
-- it was given.
function Compat.PlayerName(name)
    return ns.Units.KeyOf(name) or ns.Units.Display(name)
end

-- The shared Units.lua's name helpers, under the names SimplePanel's files call:
--   SamePlayer(a, b): one player, any of the shapes above ("GivenFamily" too; ns.Units.Same).
--   IsMe(name):       you (ns.Units.IsMe).
--   NameByGUID(guid): a player's name from their GUID ("Given Family"), or nil.
--   FullName(name, guid): name when it has the family name, else what the GUID gives, else name's key.
Compat.SamePlayer, Compat.IsMe = ns.Units.Same, ns.Units.IsMe
Compat.NameByGUID, Compat.FullName = ns.Units.NameByGUID, ns.Units.FullName

-- A unit's name to show and send: "Given Family" (UnitName's two values joined), or its one name.
function Compat.UnitPlayer(unit)
    return ns.Units.UnitFull(unit)
end

-- Online friends (in-game and Battle.net friends playing WoW) as { name, level, class, zone, bnet }.
function Compat.OnlineFriends()
    local out, FL = {}, C_FriendList
    local n = (FL and FL.GetNumFriends and FL.GetNumFriends()) or (GetNumFriends and GetNumFriends()) or 0
    for i = 1, n do
        if FL and FL.GetFriendInfoByIndex then
            local f = FL.GetFriendInfoByIndex(i)
            if f and f.connected then out[#out + 1] = { name = Compat.PlayerName(f.name), level = f.level, class = f.className, zone = f.area } end
        elseif GetFriendInfo then
            local name, level, class, area, connected = GetFriendInfo(i)
            if connected then out[#out + 1] = { name = Compat.PlayerName(name), level = level, class = class, zone = area } end
        end
    end
    if BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
        for i = 1, (BNGetNumFriends()) or 0 do
            local acc = C_BattleNet.GetFriendAccountInfo(i)
            local g = acc and acc.gameAccountInfo
            if g and g.isOnline and g.clientProgram == (BNET_CLIENT_WOW or "WoW") and g.characterName then
                out[#out + 1] = { name = Compat.PlayerName(g.characterName),
                    level = g.characterLevel, class = g.className, zone = g.areaName, bnet = acc.accountName }
            end
        end
    end
    table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
    return out
end

-- Online guild members as { name, level, class, classFile, zone, rank }, and the guild's size.
-- You aren't in the list: you know you're online.
function Compat.OnlineGuild()
    local out = {}
    if not (IsInGuild and IsInGuild() and GetNumGuildMembers) then return out, 0 end
    local total = GetNumGuildMembers() or 0
    for i = 1, total do
        local name, rank, _, level, class, zone, _, _, online, _, classFile = GetGuildRosterInfo(i)
        if name and online and not Compat.IsMe(name) then
            out[#out + 1] = { name = Compat.PlayerName(name), level = level,
                class = class, classFile = classFile, zone = zone, rank = rank }
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out, total
end

function Compat.RequestRosters()
    if C_FriendList and C_FriendList.ShowFriends then C_FriendList.ShowFriends() elseif ShowFriends then ShowFriends() end
    if IsInGuild and IsInGuild() then
        if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() elseif GuildRoster then GuildRoster() end
    end
end

-- Both take any spelling of the name and send the full "Given Family" (a "-Server" ending is dropped).
function Compat.Whisper(name)
    name = Compat.PlayerName(name)
    if ChatFrame_SendTell then ChatFrame_SendTell(name) elseif ChatFrame_OpenChat then ChatFrame_OpenChat("/w " .. name .. " ") end
end

function Compat.Invite(name)
    local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    if fn then fn(Compat.PlayerName(name)) end
end

-- ---------------------------------------------------------------------------
-- Reputation
-- ---------------------------------------------------------------------------

-- The watched faction: name, standing (1-8), min, max, value, factionID; nil when none is watched.
function Compat.WatchedFaction()
    if C_Reputation and C_Reputation.GetWatchedFactionData then
        local d = C_Reputation.GetWatchedFactionData()
        if not d or not d.name or d.name == "" then return nil end
        return d.name, d.reaction, d.currentReactionThreshold, d.nextReactionThreshold, d.currentStanding, d.factionID
    end
    if GetWatchedFactionInfo then
        local name, standing, min, max, value, id = GetWatchedFactionInfo()
        if not name then return nil end
        return name, standing, min, max, value, id
    end
end

-- Every faction you have reputation with: { index, name, standing, min, max, value, watched }.
function Compat.Factions()
    local out = {}
    if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
        for i = 1, C_Reputation.GetNumFactions() do
            local d = C_Reputation.GetFactionDataByIndex(i)
            if d and not d.isHeader or (d and d.isHeaderWithRep) then
                out[#out + 1] = { index = i, name = d.name, standing = d.reaction, min = d.currentReactionThreshold,
                    max = d.nextReactionThreshold, value = d.currentStanding, watched = d.isWatched }
            end
        end
    elseif GetNumFactions and GetFactionInfo then
        for i = 1, GetNumFactions() do
            local name, _, standing, min, max, value, _, _, header, _, hasRep, watched = GetFactionInfo(i)
            if name and (not header or hasRep) then
                out[#out + 1] = { index = i, name = name, standing = standing, min = min, max = max, value = value, watched = watched }
            end
        end
    end
    return out
end

function Compat.WatchFaction(index)
    if C_Reputation and C_Reputation.SetWatchedFactionByIndex then C_Reputation.SetWatchedFactionByIndex(index)
    elseif SetWatchedFactionIndex then SetWatchedFactionIndex(index) end
end

function Compat.StandingName(s) return _G["FACTION_STANDING_LABEL" .. tostring(s)] or ("Standing " .. tostring(s)) end
function Compat.StandingColor(s)
    local c = FACTION_BAR_COLORS and FACTION_BAR_COLORS[s]
    return c and { c.r, c.g, c.b } or { 0.6, 0.6, 0.6 }
end

-- pvpType, isFFA, faction (C_PvP's, else the global).
function Compat.ZonePVPInfo()
    local fn = (C_PvP and C_PvP.GetZonePVPInfo) or GetZonePVPInfo
    if fn then return fn() end
end

-- ---------------------------------------------------------------------------
-- Quests
-- ---------------------------------------------------------------------------

-- One row of the quest log: title, level, suggested group, header, collapsed, complete, questID.
-- Complete is 1 when done and -1 when failed (GetQuestLogTitle, else C_QuestLog).
local function QuestRow(i)
    if GetQuestLogTitle then
        local title, level, group, header, collapsed, complete, _, id = GetQuestLogTitle(i)
        return title, level, group, header, collapsed, complete, id
    end
    local info = C_QuestLog and C_QuestLog.GetInfo and C_QuestLog.GetInfo(i)
    if not info or info.isHidden then return nil end
    local id = info.questID
    local complete = id and C_QuestLog.IsComplete and C_QuestLog.IsComplete(id) and 1 or nil
    if id and C_QuestLog.IsFailed and C_QuestLog.IsFailed(id) then complete = -1 end
    return info.title, info.level, info.suggestedGroup, info.isHeader, info.isCollapsed, complete, id
end

local function QuestObjectives(i, id)
    local out = {}
    if id and C_QuestLog and C_QuestLog.GetQuestObjectives then
        for _, o in ipairs(C_QuestLog.GetQuestObjectives(id) or {}) do
            if o.text and o.text ~= "" then out[#out + 1] = { text = o.text, done = o.finished and true or false } end
        end
        if #out > 0 then return out end
    end
    if GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
        for j = 1, GetNumQuestLeaderBoards(i) or 0 do
            local text, _, done = GetQuestLogLeaderBoard(j, i)
            if text and text ~= "" then out[#out + 1] = { text = text, done = done and true or false } end
        end
    end
    return out
end

-- Whether a quest is tracked (shown in the objectives list on screen).
local function QuestWatched(i, id)
    if IsQuestWatched then return IsQuestWatched(i) and true or false end
    if id and C_QuestLog and C_QuestLog.GetQuestWatchType then return C_QuestLog.GetQuestWatchType(id) ~= nil end
    return false
end

-- { list = { { id, title, level, zone, complete, failed, group, watched, objectives = { { text, done } } } },
--   max, collapsed } where collapsed means a zone heading is folded and hides its quests.
function Compat.Quests()
    local maxFn = C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept
    local out = { list = {}, max = (maxFn and maxFn()) or MAX_QUESTS or 20, collapsed = false }
    local numFn = GetNumQuestLogEntries or (C_QuestLog and C_QuestLog.GetNumQuestLogEntries)
    if not numFn then return out end
    local zone
    for i = 1, (numFn()) or 0 do
        local title, level, group, header, collapsed, complete, id = QuestRow(i)
        if title and header then
            zone = title
            if collapsed then out.collapsed = true end
        elseif title then
            out.list[#out.list + 1] = {
                id = id, title = title, level = tonumber(level) or 0, zone = zone,
                complete = complete == 1 or complete == true, failed = complete == -1,
                group = tonumber(group) or 0, objectives = QuestObjectives(i, id),
                watched = QuestWatched(i, id),
            }
        end
    end
    return out
end

-- The game's quest colors: red far above you, orange, yellow around your level, green, grey.
function Compat.QuestColor(level)
    if GetQuestDifficultyColor then
        local c = GetQuestDifficultyColor(level)
        if c and c.r then return { c.r, c.g, c.b } end
    end
    local diff = (level or 0) - (UnitLevel("player") or 1)
    if diff >= 5 then return { 1, 0.1, 0.1 } end
    if diff >= 3 then return { 1, 0.5, 0.25 } end
    if diff >= -2 then return { 1, 0.82, 0 } end
    if -diff <= ((GetQuestGreenRange and GetQuestGreenRange()) or 8) then return { 0.25, 0.75, 0.25 } end
    return { 0.5, 0.5, 0.5 }
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

-- Line regions (Frame:CreateLine) exist on every modern client; the chart falls back to dots without them.
Compat.HasLines = UIParent.CreateLine ~= nil

function Compat.ServerTime()
    if GetGameTime then return GetGameTime() end
    return tonumber(date("%H")), tonumber(date("%M"))
end
