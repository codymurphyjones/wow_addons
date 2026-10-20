local ADDON, ns = ...

-- The journal's Scrapbook tab: your character's story as a timeline. It records level-ups, first
-- boss kills, epic loot, your first ride, every new zone, close escapes, deaths, and world PvP
-- (kills, killing sprees, who killed you, duels, battlegrounds, rank-ups and kill milestones), and
-- takes a screenshot of each big moment (saved in the game's Screenshots folder; the entry names the file).
-- Kept per character, so you can leaf through your alts' scrapbooks too.
local S = {}
ns.Scrapbook = S

local KEEP = 3000
local LOW_HEALTH = 0.1
local KINDS = {
    { "all", "Everything" },
    { "level", "Levels", "Interface\\Icons\\Spell_Holy_SurgeOfLight" },
    { "boss", "First kills", "Interface\\Icons\\Ability_Warrior_Rampage" },
    { "loot", "Epic loot", "Interface\\Icons\\INV_Misc_Bag_10_Blue" },
    { "zone", "Places", "Interface\\Icons\\INV_Misc_Map_01" },
    { "mount", "Mounts", "Interface\\Icons\\Ability_Mount_RidingHorse" },
    { "escape", "Close escapes", "Interface\\Icons\\Spell_Holy_SealOfProtection" },
    { "death", "Deaths", "Interface\\Icons\\Ability_Rogue_FeignDeath" },
    { "pvp", "PvP", "Interface\\Icons\\Ability_Warrior_Challange" },
}
local ICON = {}
for _, k in ipairs(KINDS) do ICON[k[1]] = k[3] end

local function CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

local function Book(key)
    local db = ns.J.db
    db.scrapbook = type(db.scrapbook) == "table" and db.scrapbook or {}
    key = key or CharKey()
    local b = db.scrapbook[key]
    if not b then
        b = { entries = {}, zones = {}, bosses = {}, class = select(2, UnitClass("player")) }
        db.scrapbook[key] = b
    end
    return b
end

-- A value we can't read (Forever's "secret" values, e.g. your health in some fights): comparing
-- or doing arithmetic on one is an error.
local function Secret(v)
    if v == nil then return false end
    if canaccessvalue and not canaccessvalue(v) then return true end
    return issecretvalue and issecretvalue(v) or false
end

-- ---------------------------------------------------------------------------
-- Recording
-- ---------------------------------------------------------------------------

local pendingShot

-- ---------------------------------------------------------------------------
-- The moment itself: everything worth remembering about it, so the entry tells the story even
-- without its screenshot.
-- ---------------------------------------------------------------------------

local played = { total = nil, level = nil, at = nil } -- from TIME_PLAYED_MSG, counted on from `at`
local healthLog = {}                                   -- { GetTime(), % } over the last few seconds
local HEALTH_SECONDS = 10

local function Num(v) return (not Secret(v)) and type(v) == "number" and v or nil end
local function Str(v) return (not Secret(v)) and type(v) == "string" and v ~= "" and v or nil end
local function Pct(cur, max)
    cur, max = Num(cur), Num(max)
    return cur and max and max > 0 and math.floor(cur / max * 100 + 0.5) or nil
end

local function PlayedNow()
    if not played.at then return nil end
    local extra = GetTime() - played.at
    return math.floor(played.total + extra), math.floor(played.level + extra)
end

-- "item:1234:0:..." without trailing zero fields; a link is rebuilt from it when shown.
local function ItemString(link)
    local str = link and link:match("|H(item:[^|]+)|h")
    return str and (str:gsub("[:0]+$", "")) or nil
end

local function Talents()
    if not (GetNumTalentTabs and GetTalentTabInfo) then return nil end
    local out = {}
    for i = 1, GetNumTalentTabs() or 0 do
        local r = { GetTalentTabInfo(i) }
        -- Older clients: name, icon, points; newer: id, name, description, icon, points.
        local name, points
        if type(r[1]) == "number" then name, points = r[2], r[5] else name, points = r[1], r[3] end
        out[#out + 1] = { Str(name) or ("Tree " .. i), Num(points) or 0 }
    end
    return out
end

local function Unit(unit)
    if not UnitExists(unit) then return nil end
    local name = Str(GetUnitName and GetUnitName(unit, true) or UnitName(unit))
    if not name then return nil end
    local u = { name = name, level = Num(UnitLevel(unit)), hp = Pct(UnitHealth(unit), UnitHealthMax(unit)) }
    if UnitIsPlayer(unit) then
        u.player = true
        u.class = select(2, UnitClass(unit))
        u.race = Str(UnitRace(unit))
        u.guild = Str(GetGuildInfo(unit))
    else
        u.kind = Str(UnitCreatureType(unit))
        u.rank = Str(UnitClassification(unit))
    end
    local ok, enemy = pcall(UnitCanAttack, "player", unit)
    if ok and not Secret(enemy) then u.enemy = enemy and true or nil end
    return u
end

local function Group()
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    if n == 0 then return nil end
    local units = {}
    if IsInRaid() then for i = 1, n do units[#units + 1] = "raid" .. i end
    else for i = 1, n - 1 do units[#units + 1] = "party" .. i end end
    local out = {}
    for _, unit in ipairs(units) do
        local name = Str(UnitName(unit))
        if name then
            out[#out + 1] = { name, select(2, UnitClass(unit)), Num(UnitLevel(unit)), UnitIsGroupLeader(unit) and 1 or nil }
        end
    end
    return out
end

local function Buffs()
    local out = {}
    for i = 1, 24 do
        local name
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok or not a then break end
            name = a.name
        elseif UnitBuff then
            name = UnitBuff("player", i)
            if not name then break end
        end
        name = Str(name)
        if name then out[#out + 1] = name end
    end
    return #out > 0 and out or nil
end

-- What's around you, from the nameplates the game shows.
local function Nearby()
    local hostilePlayers, friendlyPlayers, hostileNpcs = 0, 0, 0
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) then
            local ok, enemy = pcall(UnitCanAttack, "player", unit)
            enemy = ok and not Secret(enemy) and enemy
            if UnitIsPlayer(unit) then
                if enemy then hostilePlayers = hostilePlayers + 1 else friendlyPlayers = friendlyPlayers + 1 end
            elseif enemy then
                hostileNpcs = hostileNpcs + 1
            end
        end
    end
    return { hostilePlayers, friendlyPlayers, hostileNpcs }
end

local function Snapshot()
    local c = {}
    c.played, c.levelPlayed = PlayedNow()
    c.xp, c.xpMax, c.rested = Num(UnitXP("player")), Num(UnitXPMax("player")), Num(GetXPExhaustion and GetXPExhaustion())
    c.money = Num(GetMoney())
    c.hp = Pct(UnitHealth("player"), UnitHealthMax("player"))
    c.power = Pct(UnitPower("player"), UnitPowerMax("player"))
    c.powerType = select(2, UnitPowerType("player"))
    c.map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    c.facing = Num(GetPlayerFacing and GetPlayerFacing())
    local iname, itype, _, diff, maxPlayers = GetInstanceInfo()
    if itype and itype ~= "none" then c.instance = { Str(iname), itype, Str(diff), Num(maxPlayers) } end
    local h, m = GetGameTime()
    c.server = h and ("%02d:%02d"):format(h, m) or nil
    c.flags = {
        combat = InCombatLockdown() or nil, mounted = IsMounted and IsMounted() or nil, resting = IsResting() or nil,
        pvp = UnitIsPVP("player") or nil, swimming = IsSwimming and IsSwimming() or nil, dead = UnitIsDeadOrGhost("player") or nil,
    }
    local guild, rank = GetGuildInfo("player")
    if Str(guild) then c.guild = { guild, Str(rank) } end
    c.talents = Talents()
    c.gear = {}
    for slot = 1, 19 do c.gear[slot] = ItemString(GetInventoryItemLink("player", slot)) end
    c.target = Unit("target")
    c.group = Group()
    c.buffs = Buffs()
    c.nearby = Nearby()
    local low
    for _, s2 in ipairs(healthLog) do
        if GetTime() - s2[1] <= HEALTH_SECONDS and (not low or s2[2] < low) then low = s2[2] end
    end
    c.lowHealth = low
    if GetPVPLifetimeStats then c.hk = Num(GetPVPLifetimeStats()) end
    return c
end

-- Adds a moment; shot = take a screenshot of it.
function S:Add(kind, title, text, shot)
    if not ns.J.db then return end
    local b = Book()
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local x, y
    if map then
        local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
        if ok and pos then x, y = pos:GetXY() end
    end
    local e = {
        t = time(), kind = kind, title = title, text = text, level = UnitLevel("player"),
        zone = GetRealZoneText and GetRealZoneText() or nil, sub = GetSubZoneText and GetSubZoneText() or nil,
        x = x and math.floor(x * 1000) / 10, y = y and math.floor(y * 1000) / 10,
    }
    local ok, ctx = pcall(Snapshot)
    if ok then e.ctx = ctx end
    table.insert(b.entries, e)
    while #b.entries > KEEP do table.remove(b.entries, 1) end
    if shot and ns.J.db.scrapShots ~= false and Screenshot then
        -- A moment later, so the screen shows the moment (the level-up glow, the loot).
        C_Timer.After(0.6, function()
            pendingShot = e
            pcall(Screenshot)
        end)
    end
    self:Refresh()
end

local frame = CreateFrame("Frame")
local low, mounted = nil, nil

-- ---------------------------------------------------------------------------
-- PvP memories
-- ---------------------------------------------------------------------------

local MILESTONES = { 1, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000, 25000 }
local STREAK_WINDOW, STREAK_MIN = 60, 3 -- this many honorable kills inside the window: a spree
local ATTACKER_WINDOW = 15              -- an enemy player on you this recently counts as your killer
local OUTLEVEL = 3                      -- kills this many levels above you get a screenshot

local seen = {}       -- enemy player name -> { level, class, guild }
local lastAttacker    -- { name, t }
local streak = {}     -- GetTime() of recent honorable kills
local bgDone = false  -- this battleground's result is recorded

local function PvPBook()
    local b = Book()
    b.pvp = type(b.pvp) == "table" and b.pvp or { milestones = {}, duelWins = 0 }
    return b.pvp
end

-- A chat format ("%s dies, honorable kill Rank: %s (Estimated Honor Points: %d)",
-- "%1$s has defeated %2$s in a duel") as a Lua pattern with captures.
local function Pattern(fmt)
    if type(fmt) ~= "string" then return nil end
    fmt = fmt:gsub("%%%d%$s", "\1"):gsub("%%s", "\1"):gsub("%%d", "\2")
    fmt = fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%0")
    return "^" .. fmt:gsub("\1", "(.+)"):gsub("\2", "(%%d+)") .. "$"
end
local HONOR = { Pattern(COMBATLOG_HONORGAIN), Pattern(COMBATLOG_HONORGAIN_NO_RANK) }
local DUEL_WON, DUEL_FLED = Pattern(DUEL_WINNER_KNOCKOUT), Pattern(DUEL_WINNER_RETREAT)

local function InBattleground()
    local _, kind = IsInInstance()
    return kind == "pvp" or kind == "arena"
end

-- Remembers enemy players you see, and notices the ones attacking you.
local function Watch(unit)
    if not (UnitExists(unit) and UnitIsPlayer(unit)) then return end
    local ok, enemy = pcall(UnitCanAttack, "player", unit)
    if not ok or Secret(enemy) or not enemy then return end
    local name = GetUnitName and GetUnitName(unit, true) or UnitName(unit)
    if not name or Secret(name) then return end
    local level, class = UnitLevel(unit), UnitClass(unit)
    local guild = GetGuildInfo(unit)
    seen[name] = {
        level = not Secret(level) and level or nil, class = not Secret(class) and class or nil,
        guild = not Secret(guild) and guild or nil,
    }
    local ok2, onMe = pcall(UnitIsUnit, unit .. "target", "player")
    if ok2 and not Secret(onMe) and onMe then lastAttacker = { name = name, t = GetTime() } end
end

local function Describe(name)
    local p = seen[name]
    if not p then return nil end
    local parts = {}
    if p.level then parts[#parts + 1] = p.level > 0 and ("Level " .. p.level) or "Level ??" end
    if p.class then parts[#parts + 1] = p.class end
    local text = table.concat(parts, " ")
    if p.guild then text = text .. " <" .. p.guild .. ">" end
    return text ~= "" and text or nil
end

local function CheckMilestones()
    if not GetPVPLifetimeStats then return end
    local hk = GetPVPLifetimeStats()
    if Secret(hk) or type(hk) ~= "number" then return end
    local pvp = PvPBook()
    local reached
    for _, m in ipairs(MILESTONES) do
        if hk >= m and not pvp.milestones[m] then pvp.milestones[m] = time(); reached = m end
    end
    -- One entry for the biggest one reached (a first login may pass several at once).
    if reached and reached > 1 then S:Add("pvp", ("%d honorable kills"):format(reached), "A milestone.", true) end
end

local function CheckRank()
    if not UnitPVPRank then return end
    local rank = UnitPVPRank("player")
    if Secret(rank) or type(rank) ~= "number" then return end
    local pvp = PvPBook()
    if pvp.rank and rank > pvp.rank and rank > 0 then
        local name = GetPVPRankInfo and GetPVPRankInfo(rank) or ("rank " .. rank)
        S:Add("pvp", "New rank: " .. tostring(name), nil, true)
    end
    pvp.rank = rank
end

local function OnHonorKill(msg)
    local name
    for _, pat in ipairs(HONOR) do
        name = pat and msg:match(pat)
        if name then break end
    end
    if not name then return end
    local honor = msg:match("(%d+)%)?%.?$")
    local now = GetTime()
    table.insert(streak, now)
    while streak[1] and now - streak[1] > STREAK_WINDOW do table.remove(streak, 1) end
    C_Timer.After(1, CheckMilestones)
    if #streak == STREAK_MIN or (#streak > STREAK_MIN and #streak % 5 == 0) then
        S:Add("pvp", ("Killing spree: %d kills in a minute"):format(#streak), nil, true)
    end
    if InBattleground() then return end -- battleground kills count toward milestones only
    local pvp = PvPBook()
    local who = Describe(name)
    local p = seen[name]
    local outlevel = p and p.level and (p.level < 0 or p.level >= (UnitLevel("player") or 0) + OUTLEVEL)
    local first = not pvp.firstWorldKill
    if first then pvp.firstWorldKill = time() end
    pvp.worldKills = (pvp.worldKills or 0) + 1
    S:Add("pvp", (first and "First world PvP kill: " or "Honorable kill: ") .. name,
        (who and (who .. "   ") or "") .. (honor and ("+" .. honor .. " honor") or ""), first or outlevel or false)
end

local function OnSystem(msg)
    local me = UnitName("player")
    local winner, loser = DUEL_WON and msg:match(DUEL_WON)
    local fled = false
    if not winner and DUEL_FLED then
        loser, winner = msg:match(DUEL_FLED) -- "%2$s has fled from %1$s": the one who fled comes first
        fled = winner ~= nil
    end
    if not winner then return end
    local pvp = PvPBook()
    if winner == me then
        pvp.duelWins = (pvp.duelWins or 0) + 1
        local first = pvp.duelWins == 1
        S:Add("pvp", (first and "First duel won: " or "Won a duel against ") .. loser,
            fled and "They ran." or Describe(loser), first)
    elseif loser == me then
        S:Add("pvp", "Lost a duel to " .. winner, fled and "You ran." or Describe(winner), false)
    end
end

local function OnScore()
    if bgDone or not GetBattlefieldWinner then return end
    local winner = GetBattlefieldWinner()
    if winner == nil or Secret(winner) then return end
    bgDone = true
    local mine = UnitFactionGroup("player") == "Alliance" and 1 or 0
    local zone = GetRealZoneText and GetRealZoneText() or "the battleground"
    if winner == mine then S:Add("pvp", "Victory in " .. zone, nil, true)
    elseif winner == 255 then S:Add("pvp", "Draw in " .. zone, nil, false)
    else S:Add("pvp", "Defeat in " .. zone, nil, false) end
end

local function PvPHandlers()
    return {
        CHAT_MSG_COMBAT_HONOR_GAIN = function(msg)
            if not Secret(msg) and type(msg) == "string" then OnHonorKill(msg) end
        end,
        CHAT_MSG_SYSTEM = function(msg)
            if not Secret(msg) and type(msg) == "string" then OnSystem(msg) end
        end,
        UPDATE_BATTLEFIELD_SCORE = OnScore,
        PLAYER_ENTERING_WORLD = function() bgDone = false; C_Timer.After(5, function() CheckRank(); CheckMilestones() end) end,
        PLAYER_PVP_KILLS_CHANGED = CheckRank,
        PLAYER_PVP_RANK_CHANGED = CheckRank,
        PLAYER_TARGET_CHANGED = function() Watch("target") end,
        UPDATE_MOUSEOVER_UNIT = function() Watch("mouseover") end,
        NAME_PLATE_UNIT_ADDED = function(unit) Watch(unit) end,
        UNIT_TARGET = function(unit) if unit and unit:find("^nameplate") then Watch(unit) end end,
    }
end

-- Who killed you, when an enemy player was on you (or your target) moments before.
local function Killer()
    local a = lastAttacker
    if a and GetTime() - a.t <= ATTACKER_WINDOW then return a.name end
    if UnitExists("target") and UnitIsPlayer("target") then
        local ok, enemy = pcall(UnitCanAttack, "player", "target")
        if ok and not Secret(enemy) and enemy and InCombatLockdown() then
            local name = UnitName("target")
            if name and not Secret(name) then return name end
        end
    end
end

local function Handlers()
    local h = PvPHandlers()
    for event, fn in pairs({
        PLAYER_LEVEL_UP = function(level)
            S:Add("level", ("Reached level %d"):format(level), nil, true)
        end,
        ENCOUNTER_END = function(_, name, _, _, success)
            if success ~= 1 and success ~= true then return end
            local b = Book()
            if Secret(name) or not name or b.bosses[name] then return end
            b.bosses[name] = time()
            S:Add("boss", "First kill: " .. name, GetRealZoneText and GetRealZoneText() or nil, true)
        end,
        BOSS_KILL = function(_, name)
            local b = Book()
            if Secret(name) or not name or b.bosses[name] then return end
            b.bosses[name] = time()
            S:Add("boss", "First kill: " .. name, GetRealZoneText and GetRealZoneText() or nil, true)
        end,
        CHAT_MSG_LOOT = function(msg, _, _, _, _, _, _, _, _, _, _, guid)
            if Secret(msg) or type(msg) ~= "string" then return end
            if guid and not Secret(guid) then
                if guid ~= UnitGUID("player") then return end
            else
                -- No looter given: only "You receive loot..." lines are yours.
                local mine = (LOOT_ITEM_SELF or "You receive loot: %s."):match("^(.-)%%s")
                if not (mine and msg:sub(1, #mine) == mine) then return end
            end
            local link = msg:match("(|c%x+|Hitem:.-|h.-|h|r)")
            if not link then return end
            local quality = select(3, (C_Item and C_Item.GetItemInfo or GetItemInfo)(link))
            if quality == nil then
                local id = tonumber(link:match("item:(%d+)"))
                quality = id and C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
            end
            if quality and quality >= 4 then S:Add("loot", "Epic loot", link, true) end
        end,
        ZONE_CHANGED_NEW_AREA = function()
            local zone = GetRealZoneText and GetRealZoneText()
            if not zone or zone == "" or Secret(zone) then return end
            local b = Book()
            if b.zones[zone] then return end
            b.zones[zone] = time()
            local _, kind = IsInInstance()
            S:Add("zone", (kind == "party" or kind == "raid") and ("First time in " .. zone) or ("Discovered " .. zone), nil, true)
        end,
        PLAYER_MOUNT_DISPLAY_CHANGED = function()
            local now = IsMounted and IsMounted()
            if now and not mounted then
                local b = Book()
                if not b.firstRide then
                    b.firstRide = time()
                    S:Add("mount", "First ride", nil, true)
                end
            end
            mounted = now
        end,
        UNIT_HEALTH = function(unit)
            if unit ~= "player" then return end
            local hp, max = UnitHealth("player"), UnitHealthMax("player")
            if Secret(hp) or Secret(max) or not max or max <= 0 then return end
            local pct = hp / max
            table.insert(healthLog, { GetTime(), math.floor(pct * 100 + 0.5) })
            while healthLog[1] and GetTime() - healthLog[1][1] > HEALTH_SECONDS do table.remove(healthLog, 1) end
            if not InCombatLockdown() then return end
            if hp > 0 and pct < LOW_HEALTH and (not low or pct < low) then low = pct end
        end,
        PLAYER_REGEN_ENABLED = function()
            if low and not UnitIsDeadOrGhost("player") then
                S:Add("escape", "Close escape", ("Survived a fight on %.0f%% health."):format(low * 100), true)
            end
            low = nil
        end,
        PLAYER_DEAD = function()
            low = nil
            local killer = Killer()
            lastAttacker = nil
            if killer then
                S:Add("pvp", "Killed by " .. killer, Describe(killer), false)
            else
                S:Add("death", "Died", nil, false)
            end
        end,
        SCREENSHOT_SUCCEEDED = function()
            if pendingShot then
                -- The game names screenshots by date and time.
                pendingShot.shot = date("WoWScrnShot_%m%d%y_%H%M%S")
                pendingShot = nil
                S:Refresh()
            end
        end,
        SCREENSHOT_FAILED = function() pendingShot = nil end,
        TIME_PLAYED_MSG = function(total, level)
            played.total, played.level, played.at = Num(total) or 0, Num(level) or 0, GetTime()
        end,
    }) do h[event] = fn end
    return h
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        self.handlers = Handlers()
        for name in pairs(self.handlers) do pcall(self.RegisterEvent, self, name) end
        mounted = IsMounted and IsMounted()
        -- Time played for the snapshots, asked for once without printing it in chat.
        C_Timer.After(4, function()
            if not RequestTimePlayed then return end
            local show = ChatFrame_DisplayTimePlayed
            local util = ChatFrameUtil and ChatFrameUtil.DisplayTimePlayed
            if show then ChatFrame_DisplayTimePlayed = function() end end
            if util then ChatFrameUtil.DisplayTimePlayed = function() end end
            RequestTimePlayed()
            C_Timer.After(3, function()
                if show then ChatFrame_DisplayTimePlayed = show end
                if util then ChatFrameUtil.DisplayTimePlayed = util end
            end)
        end)
        -- Where you start counts as visited, quietly.
        C_Timer.After(2, function()
            local zone = GetRealZoneText and GetRealZoneText()
            if ns.J.db and zone and zone ~= "" then
                local b = Book()
                if not next(b.entries) then
                    S:Add("level", ("Scrapbook started at level %d"):format(UnitLevel("player") or 1), "Every moment from here on is kept.", false)
                end
                b.zones[zone] = b.zones[zone] or time()
            end
        end)
        return
    end
    local fn = self.handlers and self.handlers[event]
    if fn then fn(...) end
end)

-- ---------------------------------------------------------------------------
-- Page
-- ---------------------------------------------------------------------------

local page

local function Visible()
    local db = ns.J.db
    local book = Book(page.char)
    local kind, search = page.kind or "all", ns.J.state.search or ""
    local out = {}
    for i = #book.entries, 1, -1 do
        local e = book.entries[i]
        if (kind == "all" or e.kind == kind) and (search == "" or ((e.title or "") .. " " .. (e.text or "") .. " " .. (e.zone or "")):lower():find(search, 1, true)) then
            out[#out + 1] = e
        end
    end
    return out, book
end

local SLOT_NAMES = {
    "Head", "Neck", "Shoulder", "Shirt", "Chest", "Waist", "Legs", "Feet", "Wrist", "Hands",
    "Ring", "Ring", "Trinket", "Trinket", "Back", "Main hand", "Off hand", "Ranged", "Tabard",
}

local function Played(secs)
    if not secs then return nil end
    local d, h, m = math.floor(secs / 86400), math.floor(secs % 86400 / 3600), math.floor(secs % 3600 / 60)
    return d > 0 and ("%dd %dh %dm"):format(d, h, m) or ("%dh %dm"):format(h, m)
end

local function ClassName(file, name)
    local c = file and RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]
    return c and ("|c%s%s|r"):format(c.colorStr or "ffffffff", name) or name
end

local function Money(c)
    if not c then return "?" end
    return GetCoinTextureString and GetCoinTextureString(c) or GetMoneyString(c)
end

-- The memory card's text, section by section.
local function CardText(e)
    local c = e.ctx or {}
    local L = {}
    local function Add(line) L[#L + 1] = line end
    local function Head(text) Add(" "); Add("|cffffd100" .. text .. "|r") end

    Add(("|cffffffff%s|r"):format(date("%A, %B %d %Y at %H:%M:%S", e.t)) .. (c.server and ("  |cffaaaaaa(server time %s)|r"):format(c.server) or ""))
    if c.played then Add(("Time played: %s total, %s at this level"):format(Played(c.played), Played(c.levelPlayed))) end

    Head("Where")
    local where = e.zone or "?"
    if e.sub and e.sub ~= "" and e.sub ~= e.zone then where = e.sub .. ", " .. where end
    if e.x then where = where .. (" (%.1f, %.1f)"):format(e.x, e.y) end
    Add(where)
    if c.instance then
        Add(("Inside %s%s%s"):format(c.instance[1] or "an instance", c.instance[3] and (", " .. c.instance[3]) or "",
            c.instance[4] and c.instance[4] > 0 and (" (" .. c.instance[4] .. " players)") or ""))
    end
    if c.facing then
        local dirs = { "north", "north-west", "west", "south-west", "south", "south-east", "east", "north-east" }
        Add("Facing " .. dirs[math.floor((c.facing / (2 * math.pi)) * 8 + 0.5) % 8 + 1])
    end

    Head("You")
    local you = ("Level %d"):format(e.level or 0)
    if c.xp and c.xpMax and c.xpMax > 0 then you = you .. (", %d%% of the way to the next level"):format(c.xp / c.xpMax * 100) end
    if c.rested and c.rested > 0 and c.xpMax then you = you .. (", %d%% rested"):format(c.rested / c.xpMax * 100) end
    Add(you)
    Add(("Health %s%%, %s %s%%"):format(c.hp or "?", (c.powerType or "power"):lower(), c.power or "?")
        .. (c.lowHealth and c.lowHealth < (c.hp or 100) and (", down to %d%% moments before"):format(c.lowHealth) or ""))
    Add("Carrying " .. Money(c.money))
    local flags = {}
    for k, label in pairs({ combat = "in combat", mounted = "mounted", resting = "resting", pvp = "flagged for PvP", swimming = "swimming", dead = "dead" }) do
        if c.flags and c.flags[k] then flags[#flags + 1] = label end
    end
    if #flags > 0 then table.sort(flags); Add("Was " .. table.concat(flags, ", ")) end
    if c.guild then Add(("<%s>%s"):format(c.guild[1], c.guild[2] and (", " .. c.guild[2]) or "")) end
    if c.talents then
        local parts = {}
        for _, t in ipairs(c.talents) do parts[#parts + 1] = t[2] end
        local names = {}
        for _, t in ipairs(c.talents) do names[#names + 1] = t[1] end
        Add(("Talents %s  |cffaaaaaa(%s)|r"):format(table.concat(parts, "/"), table.concat(names, " / ")))
    end
    if c.buffs then Add("Buffs: " .. table.concat(c.buffs, ", ")) end
    if c.hk then Add(("%d honorable kills so far"):format(c.hk)) end

    if c.target then
        local t = c.target
        Head("Your target")
        local desc = t.player and ClassName(t.class, t.name) or t.name
        local bits = {}
        if t.level then bits[#bits + 1] = t.level > 0 and ("level " .. t.level) or "level ??" end
        if t.race then bits[#bits + 1] = t.race end
        if t.kind then bits[#bits + 1] = t.kind end
        if t.rank and t.rank ~= "normal" then bits[#bits + 1] = t.rank end
        if t.hp then bits[#bits + 1] = t.hp .. "% health" end
        Add(desc .. (#bits > 0 and (", " .. table.concat(bits, ", ")) or "") .. (t.guild and (" <" .. t.guild .. ">") or "")
            .. (t.enemy and "  |cffff6060enemy|r" or ""))
    end

    if c.group then
        Head(("Your group (%d)"):format(#c.group + 1))
        local names = {}
        for _, m in ipairs(c.group) do
            names[#names + 1] = ClassName(m[2], m[1]) .. (m[3] and (" " .. m[3]) or "") .. (m[4] and " (leader)" or "")
        end
        Add(table.concat(names, ", "))
    end

    if c.nearby and (c.nearby[1] + c.nearby[2] + c.nearby[3]) > 0 then
        Head("Around you")
        Add(("%d enemy players, %d friendly players, %d hostile creatures in sight"):format(c.nearby[1], c.nearby[2], c.nearby[3]))
    end
    if e.shot then
        Head("Screenshot")
        Add("Screenshots\\" .. e.shot .. " (.jpg or .tga, as your game saves them)")
    end
    return table.concat(L, "\n")
end

local function InitRow(row, e)
    if not row.icon then
        row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(34, 34); row.icon:SetPoint("LEFT", 6, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.title = row:CreateFontString(nil, "OVERLAY", "SpyglassGameFontNormal"); row.title:SetPoint("TOPLEFT", 48, -5)
        row.title:SetPoint("RIGHT", -170, 0); row.title:SetJustifyH("LEFT"); row.title:SetWordWrap(false)
        row.text = row:CreateFontString(nil, "OVERLAY", "SpyglassGameFontHighlightSmall"); row.text:SetPoint("TOPLEFT", 48, -22)
        row.text:SetPoint("RIGHT", -170, 0); row.text:SetJustifyH("LEFT"); row.text:SetWordWrap(false)
        row.when = row:CreateFontString(nil, "OVERLAY", "SpyglassGameFontHighlightSmall"); row.when:SetPoint("TOPRIGHT", -8, -5)
        row.when:SetJustifyH("RIGHT")
        row.shot = row:CreateFontString(nil, "OVERLAY", "SpyglassGameFontDisableSmall"); row.shot:SetPoint("TOPRIGHT", -8, -22)
        row.shot:SetJustifyH("RIGHT")
        row.line = row:CreateTexture(nil, "BACKGROUND"); row.line:SetPoint("BOTTOMLEFT", 6, 0); row.line:SetPoint("BOTTOMRIGHT", -6, 0)
        row.line:SetHeight(1); row.line:SetColorTexture(1, 0.78, 0.25, 0.15)
        row:SetScript("OnEnter", function(self)
            local d = self.data
            if not d then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local link = d.text and d.text:match("|Hitem:")
            if link then GameTooltip:SetHyperlink(d.text:match("|H(item:.-)|h")) else GameTooltip:AddLine(d.title, 1, 0.82, 0) end
            if d.zone then GameTooltip:AddLine(("%s%s%s"):format(d.zone, d.sub and d.sub ~= "" and d.sub ~= d.zone and (", " .. d.sub) or "",
                d.x and (" (%.1f, %.1f)"):format(d.x, d.y) or ""), 0.8, 0.8, 0.8) end
            if d.shot then GameTooltip:AddLine("Screenshots\\" .. d.shot .. ".*", 0.6, 0.6, 0.6) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
        row:SetScript("OnClick", function(self) if self.data then S:ShowCard(self.data) end end)
    end
    row.data = e
    row.icon:SetTexture(ICON[e.kind] or ns.ICON)
    row.title:SetText(e.title or "")
    local where = e.zone and (e.sub and e.sub ~= "" and e.sub ~= e.zone and (e.sub .. ", " .. e.zone) or e.zone) or ""
    row.text:SetText((e.text and (e.text .. "   ") or "") .. "|cffaaaaaa" .. where .. "|r")
    row.when:SetText(("%s  |cffaaaaaalevel %d|r"):format(date("%b %d %Y, %H:%M", e.t), e.level or 0))
    row.shot:SetText(e.shot and "screenshot taken" or "")
end

function S:Build(parent)
    page = CreateFrame("Frame", nil, parent)
    page:SetPoint("TOPLEFT", 6, -6); page:SetPoint("BOTTOMRIGHT", -6, 6)
    page:Hide()
    page.kind = "all"

    page.heading = ns.J.TitleText(page, 26)
    page.heading:SetPoint("TOPLEFT", 8, -4)
    page.sub = page:CreateFontString(nil, "OVERLAY", "SpyglassGameFontHighlightSmall")
    page.sub:SetPoint("TOPLEFT", 10, -36); page.sub:SetWidth(560); page.sub:SetJustifyH("LEFT")

    page.kindDrop = ns.J.MakeDropdown(page, 150, KINDS, function() return page.kind end, function(k) page.kind = k; S:Refresh(true) end)
    page.kindDrop:SetPoint("TOPRIGHT", -8, -6)
    page.chars = {}
    page.charDrop = ns.J.MakeDropdown(page, 180, page.chars, function() return page.char or CharKey() end, function(k)
        page.char = k; S:Refresh(true)
    end)
    page.charDrop:SetPoint("RIGHT", page.kindDrop, "LEFT", -8, 0)
    page.shots = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    page.shots:SetSize(24, 24); page.shots:SetPoint("TOPRIGHT", -150, -34)
    page.shots.label = page.shots:CreateFontString(nil, "OVERLAY", "SpyglassGameFontHighlightSmall")
    page.shots.label:SetPoint("LEFT", page.shots, "RIGHT", 2, 0); page.shots.label:SetText("Take screenshots")
    page.shots:SetScript("OnClick", function(self) ns.J.db.scrapShots = self:GetChecked() and true or false end)

    page.list = ns.J.MakeList(page, 44, InitRow)
    page.list:SetPoint("TOPLEFT", 4, -64); page.list:SetPoint("BOTTOMRIGHT", -24, 4)

    -- The memory card: one moment in full.
    local card = CreateFrame("Frame", nil, page)
    card:SetPoint("TOPLEFT", 4, -64); card:SetPoint("BOTTOMRIGHT", -4, 4); card:Hide()
    card.bg = card:CreateTexture(nil, "BACKGROUND"); card.bg:SetAllPoints(); card.bg:SetColorTexture(0.07, 0.09, 0.14, 1)
    card.back = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    card.back:SetSize(90, 22); card.back:SetPoint("TOPLEFT", 8, -8); card.back:SetText("< Back")
    card.back:SetScript("OnClick", function() card:Hide(); page.list:Show() end)
    card.map = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    card.map:SetSize(110, 22); card.map:SetPoint("LEFT", card.back, "RIGHT", 6, 0); card.map:SetText("Show on map")
    card.map:SetScript("OnClick", function()
        local e = card.entry
        local map = e and e.ctx and e.ctx.map
        if not (map and e.x) then return end
        if not WorldMapFrame:IsShown() then ToggleWorldMap() end
        WorldMapFrame:SetMapID(map)
        if C_Map.SetUserWaypoint and UiMapPoint then
            pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(map, e.x / 100, e.y / 100))
        end
    end)
    card.icon = card:CreateTexture(nil, "ARTWORK"); card.icon:SetSize(44, 44); card.icon:SetPoint("TOPLEFT", 10, -40)
    card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    card.title = ns.J.TitleText(card, 22); card.title:SetPoint("TOPLEFT", 62, -42); card.title:SetPoint("RIGHT", -10, 0)
    card.title:SetJustifyH("LEFT")
    card.sub = card:CreateFontString(nil, "OVERLAY", "SpyglassGameFontHighlight"); card.sub:SetPoint("TOPLEFT", 62, -68)
    card.sub:SetPoint("RIGHT", -10, 0); card.sub:SetJustifyH("LEFT"); card.sub:SetWordWrap(false)
    local scroll = CreateFrame("ScrollFrame", nil, card, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -92); scroll:SetPoint("BOTTOMRIGHT", -250, 8)
    card.body = CreateFrame("Frame", nil, scroll); card.body:SetSize(560, 10)
    scroll:SetScrollChild(card.body)
    card.text = card.body:CreateFontString(nil, "OVERLAY", "SpyglassGameFontHighlightSmall")
    card.text:SetPoint("TOPLEFT"); card.text:SetWidth(540); card.text:SetJustifyH("LEFT"); card.text:SetSpacing(2)
    -- Gear, as it was: item buttons with tooltips.
    card.gearTitle = card:CreateFontString(nil, "OVERLAY", "SpyglassGameFontNormal")
    card.gearTitle:SetPoint("TOPRIGHT", -150, -92); card.gearTitle:SetText("Equipped")
    card.gear = {}
    for slot = 1, 19 do
        local b = CreateFrame("Button", nil, card)
        b:SetSize(26, 26)
        local col, row = (slot - 1) % 2, math.floor((slot - 1) / 2)
        b:SetPoint("TOPRIGHT", -(10 + (1 - col) * 116), -112 - row * 30)
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints()
        b.label = b:CreateFontString(nil, "OVERLAY", "SpyglassGameFontHighlightSmall"); b.label:SetPoint("LEFT", b, "RIGHT", 4, 0)
        b.label:SetWidth(82); b.label:SetJustifyH("LEFT"); b.label:SetWordWrap(false)
        b:SetScript("OnEnter", function(self)
            if not self.item then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetHyperlink(self.item); GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        card.gear[slot] = b
    end
    page.card = card
    page.empty = page:CreateFontString(nil, "OVERLAY", "SpyglassGameFontDisable")
    page.empty:SetPoint("CENTER", page.list, "CENTER")
    return page
end

function S:Refresh(toTop)
    if not (page and page:IsVisible()) then return end
    local db = ns.J.db
    wipe(page.chars)
    for key in pairs(db.scrapbook or {}) do page.chars[#page.chars + 1] = { key, Ambiguate(key, "short") } end
    table.sort(page.chars, function(a, b) return a[2] < b[2] end)
    if page.charDrop.GenerateMenu then pcall(page.charDrop.GenerateMenu, page.charDrop) end
    if page.charDrop.Update then page.charDrop:Update() end
    if page.kindDrop.Update then page.kindDrop:Update() end
    page.shots:SetChecked(db.scrapShots ~= false)

    if toTop and page.card then page.card:Hide(); page.list:Show() end
    local list, book = Visible()
    local who = page.char or CharKey()
    page.heading:SetText(Ambiguate(who, "short") .. "'s Scrapbook")
    local zones, bosses = 0, 0
    for _ in pairs(book.zones or {}) do zones = zones + 1 end
    for _ in pairs(book.bosses or {}) do bosses = bosses + 1 end
    local pvp = book.pvp or {}
    page.sub:SetText(("%d moments, %d places discovered, %d bosses defeated, %d world PvP kills, %d duels won. Screenshots are in your game's Screenshots folder."):format(
        #book.entries, zones, bosses, pvp.worldKills or 0, pvp.duelWins or 0))
    ns.J.SetList(page.list, list, toTop)
    page.empty:SetText(#list == 0 and "Nothing here yet: go make some memories." or "")
end

function S:ShowCard(e)
    local card = page and page.card
    if not card then return end
    card.entry = e
    page.list:Hide(); card:Show()
    card.icon:SetTexture(ICON[e.kind] or ns.ICON)
    card.title:SetText(e.title or "")
    card.sub:SetText(e.text or "")
    card.text:SetText(CardText(e))
    card.body:SetHeight(card.text:GetStringHeight() + 10)
    card.map:SetEnabled(e.ctx and e.ctx.map and e.x and true or false)
    local gear = e.ctx and e.ctx.gear or {}
    for slot, b in ipairs(card.gear) do
        local item = gear[slot]
        b.item = item
        if item then
            local _, link, _, _, _, _, _, _, _, tex = (C_Item and C_Item.GetItemInfo or GetItemInfo)(item)
            b.icon:SetTexture(tex or (GetItemIcon and GetItemIcon(item)) or 134400)
            b.label:SetText(link or SLOT_NAMES[slot])
            b:Show()
        else
            b:Hide()
        end
    end
    card.gearTitle:SetShown(next(gear) ~= nil)
end

function S:Crumbs() return "Scrapbook" end
