local _, ns = ...

-- Quest facts, read from Data\QuestDB.lua (Wowhead's WoW Forever database,
-- baked by tools/Spyglass/build_items.py): titles, chains, who gives each
-- quest, who may take it, and which quests reward gear.
local Q = {}
ns.Quests = Q

-- Events and saved variables: the shared Core.lua (addons/shared). SpyGlassPluginQuestsDB, saved
-- per character, is ns.char.
ns.SAVED = { char = "SpyGlassPluginQuestsDB" }
ns.PREFIX = "|TInterface\\AddOns\\Spyglass\\Media\\Icon:14:14|t |cff66bbffSpyGlassPluginQuests|r"

local DB = ns.QuestDB
local MAX_CHAIN = 25

-- Item classes that are gear: weapons (2) and armor (4).
local GEAR_CLASS = { [2] = true, [4] = true }

-- The field names the rest of the plugin asks for, and where each lives in
-- QuestDB.lua.
local FIELD = { name = "name", questLevel = "level", requiredLevel = "req", requiredRaces = "races",
    requiredClasses = "classes", zoneOrSort = "zone", preQuestSingle = "prev" }

local function Get(id, key)
    local q = DB.quests[id]
    local value
    if q then
        if key == "objectivesText" then
            value = q.text and { q.text }
        else
            value = q[FIELD[key] or key]
        end
    end
    return value
end
Q.Get = Get

function Q:Known(id)
    return DB.quests[id] ~= nil
end

function Q:Exists(id)
    return self:Known(id)
end

function Q:Title(id)
    return Get(id, "name") or ("Quest #" .. id)
end

---------------------------------------------------------------------------
-- Completion and eligibility
---------------------------------------------------------------------------

-- The game's own record only (shared Questie.lua; gameOnly: Questie's isn't counted).
function Q:Done(id)
    return ns.QuestieKit.IsDone(id, true)
end

-- The NPC (or object) in a giver / ender pair { "npc" or "object", id }:
-- { kind, id, name, spawns, friendly, level, subName }.
local function Person(who)
    if type(who) ~= "table" then return nil end
    local kind, id = who[1], who[2]
    local row = (kind == "npc" and DB.npcs[id]) or (kind == "object" and DB.objects[id])
    if not row then return nil end
    return {
        kind = kind, id = id, name = row.name, spawns = row.spawns,
        friendly = row.react, level = row.level, subName = row.sub,
    }
end

-- Who gives the quest, and who takes it back.
function Q:Giver(id)
    local q = DB.quests[id]
    return Person(q and q.giver)
end

function Q:Ender(id)
    local q = DB.quests[id]
    return Person(q and q.ender)
end

-- Is the quest in your quest log right now (accepted, not yet handed in)?
function Q:InLog(id)
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        local index = C_QuestLog.GetLogIndexForQuestID(id)
        return index ~= nil and index > 0
    end
    if GetQuestLogIndexByID then
        local index = GetQuestLogIndexByID(id)
        return index ~= nil and index > 0
    end
    return false
end

---------------------------------------------------------------------------
-- Steps the giver turned out not to offer
---------------------------------------------------------------------------

-- Saved per character: steps we went to whose giver didn't offer them
-- (already done before the game kept track, or not for this character).
ns:OnLoad(function()
    -- Saved under the old name (LootPriorityPlugin): carry it over. (Without a saved
    -- SpyGlassPluginQuestsDB the shared Core.lua has just made an empty one.)
    if next(SpyGlassPluginQuestsDB) == nil and type(LootPriorityPluginDB) == "table" then
        SpyGlassPluginQuestsDB = LootPriorityPluginDB
        ns.char = SpyGlassPluginQuestsDB
    end
    LootPriorityPluginDB = nil
    ns.char.skipped = ns.char.skipped or {}
end)

-- (Before the saved variables are loaded: a throwaway list.)
local function Skips()
    return ns.char and ns.char.skipped or {}
end

function Q:Skipped(id)
    return Skips()[id] and true or false
end

function Q:Skip(id)
    Skips()[id] = true
end

-- Forgets the skips in one chain (the chain leading to reward).
function Q:ResetSkips(reward)
    local skips = Skips()
    for _, id in ipairs(self:Chain(reward)) do skips[id] = nil end
end

-- Race and class masks are tested with plain arithmetic rather than the bit
-- library: the masks carry flag bits above the 32 race/class bits
-- (2^32, 2^33), and a 32-bit bit.band can't be trusted with numbers that size.
local function HasBit(mask, n)
    return math.floor(mask / 2 ^ (n - 1)) % 2 == 1
end

-- A race's bit in requiredRaces: raceID for the old races, but Forever's
-- Skyborne (race IDs 95 and 96) use bits 33 and 34 (mask values 2^32, 2^33).
local RACE_BIT = { [95] = 33, [96] = 34 }
local function RaceBit(race)
    return RACE_BIT[race] or race
end

-- Race IDs on each side (1 Human, 3 Dwarf, 4 Night Elf, 7 Gnome, 95 Skyborne;
-- 2 Orc, 5 Undead, 6 Tauren, 8 Troll, 96 Skyborne).
local SIDE_RACES = { Alliance = { 1, 3, 4, 7, 95 }, Horde = { 2, 5, 6, 8, 96 } }

local function AnyBit(mask, ids)
    for _, n in ipairs(ids) do
        if HasBit(mask, RaceBit(n)) then return true end
    end
    return false
end

local playerRace, playerClass, playerFaction
local function Player()
    if playerFaction == nil then
        playerRace = select(3, UnitRace("player"))
        playerClass = select(3, UnitClass("player"))
        playerFaction = UnitFactionGroup("player") or false
    end
    return playerRace, playerClass, playerFaction
end

-- Is your race in the mask? Without a race ID from the game, any race of
-- your faction counts, so a missing ID never hides everything.
local function RaceAllowed(races)
    local race, _, faction = Player()
    if race then return HasBit(races, RaceBit(race)) end
    local side = faction and SIDE_RACES[faction]
    return not side or AnyBit(races, side)
end

local function Masks(id)
    -- Races use 34 bits (Forever's Skyborne sit at 2^32 and 2^33); classes 32.
    return (Get(id, "requiredRaces") or 0) % 17179869184, (Get(id, "requiredClasses") or 0) % 4294967296
end

-- Can your character take this quest (race, class and, when the quest
-- doesn't say, the giver's faction)?
function Q:Allowed(id)
    local _, class, faction = Player()
    local races, classes = Masks(id)
    if races ~= 0 and not RaceAllowed(races) then return false end
    if classes ~= 0 and class and not HasBit(classes, class) then return false end
    if races == 0 then
        local giver = self:Giver(id)
        local friendly = giver and giver.friendly
        if friendly == "A" and faction == "Horde" then return false end
        if friendly == "H" and faction == "Alliance" then return false end
    end
    return true
end

-- Why your character can't take a quest, in a few words ("Horde only",
-- "Warrior only"), or nil when it can.
function Q:WhyNot(id)
    if self:Allowed(id) then return nil end
    local _, class = Player()
    local races, classes = Masks(id)
    if classes ~= 0 and class and not HasBit(classes, class) then
        local names = {}
        for classID = 1, 11 do
            if HasBit(classes, classID) and GetClassInfo then
                local name = GetClassInfo(classID)
                if name then names[#names + 1] = name end
            end
        end
        return (#names > 0 and table.concat(names, ", ") or "Another class") .. " only"
    end
    if races ~= 0 then
        local horde, alliance = AnyBit(races, SIDE_RACES.Horde), AnyBit(races, SIDE_RACES.Alliance)
        if horde and not alliance then return "Horde only" end
        if alliance and not horde then return "Alliance only" end
        return "Other races only"
    end
    local giver = self:Giver(id)
    if giver and giver.friendly == "H" then return "Horde only" end
    if giver and giver.friendly == "A" then return "Alliance only" end
    return "Not for your character"
end

---------------------------------------------------------------------------
-- Chains
---------------------------------------------------------------------------

-- The quest before this one in its chain, or nil.
function Q:Prev(id)
    local list = Get(id, "preQuestSingle")
    if type(list) ~= "table" then return nil end
    -- Prefer a step your character can take (chains split by faction).
    for _, prev in ipairs(list) do
        if self:Exists(prev) and self:Allowed(prev) then return prev end
    end
    for _, prev in ipairs(list) do
        if self:Exists(prev) then return prev end
    end
    return nil
end

local chains = {}
-- { first, ..., id }: the chain leading to this quest, first step first.
function Q:Chain(id)
    local cached = chains[id]
    if cached then return cached end
    local list, seen, cur = { id }, { [id] = true }, id
    while #list < MAX_CHAIN do
        local prev = self:Prev(cur)
        if not prev or seen[prev] then break end
        seen[prev] = true
        table.insert(list, 1, prev)
        cur = prev
    end
    chains[id] = list
    return list
end

-- The first step of the chain you haven't done (and that wasn't skipped
-- because its giver didn't offer it), its place, and the chain. With no
-- completion data at all, that's the first step.
function Q:NextStep(id)
    local chain = self:Chain(id)
    for i, step in ipairs(chain) do
        if not self:Done(step) and (not self:Skipped(step) or step == id or self:InLog(step)) then
            return step, i, chain
        end
    end
    return id, #chain, chain
end

-- Where to go for the next step: { quest, person, action = "pickup" or
-- "turnin" }. A step in your quest log goes to the NPC who takes it back.
function Q:Target(reward)
    local step = self:NextStep(reward)
    if self:InLog(step) then
        local ender = self:Ender(step)
        if ender then return { quest = step, person = ender, action = "turnin" } end
    end
    return { quest = step, person = self:Giver(step), action = "pickup" }
end

---------------------------------------------------------------------------
-- Quests that reward gear
---------------------------------------------------------------------------

Q.rewardsByQuest = {} -- [questID] = { itemID, ... }

-- The item's expected required level without asking the server: the source
-- index's required level or item level (less 5), else SpyGlass's shipped item
-- data. SpyGlass skips items far from your level before asking about them.
local function LevelHint(itemID)
    local f = ns.Sources and ns.Sources.items[itemID]
    if f and f.req and f.req > 0 then return f.req end
    if f and f.ilvl and f.ilvl > 0 then return math.max(1, f.ilvl - 5) end
    local info = SpyGlass and SpyGlass:PeekItem(itemID)
    return info and info.fitLevel or nil
end

-- Weapon or armor, by what the game or SpyGlass's item data says.
local function IsGear(itemID)
    if not (SpyGlass and SpyGlass.InstantItem) then return false end
    local equipLoc, _, _, classID = SpyGlass:InstantItem(itemID)
    return equipLoc ~= nil and equipLoc ~= "" and GEAR_CLASS[classID or 0] or false
end

-- Goes through the quests' rewards a few hundred quests per frame (so
-- logging in doesn't stall) and calls onDone({ { itemID, quest }, ... }) with
-- every weapon or armor reward. Quality (green or better) is checked later
-- from the game's own item info.
function Q:ScanRewards(onDone)
    local ids = {}
    for id, q in pairs(DB.quests) do
        if q.rewards then ids[#ids + 1] = id end
    end
    local found, seen, index, perFrame = {}, {}, 1, 400
    local function Add(itemID, quest)
        local key = quest .. ":" .. itemID
        if seen[key] then return end
        seen[key] = true
        found[#found + 1] = { itemID = itemID, quest = quest, levelHint = LevelHint(itemID) }
        local list = Q.rewardsByQuest[quest]
        if not list then
            list = {}
            Q.rewardsByQuest[quest] = list
        end
        list[#list + 1] = itemID
    end
    C_Timer.NewTicker(0.01, function(ticker)
        local last = math.min(index + perFrame - 1, #ids)
        for i = index, last do
            local quest = ids[i]
            for _, itemID in ipairs(DB.quests[quest].rewards) do
                if IsGear(itemID) then Add(itemID, quest) end
            end
        end
        index = last + 1
        if index > #ids then
            ticker:Cancel()
            onDone(found)
        end
    end)
end

-- "Contribute data" in SpyGlass skips what this plugin's quest data has: a
-- quest it knows with its giver, and its known rewards.
if SpyGlass and SpyGlass.SetKnownCheck then
    SpyGlass:SetKnownCheck("Q", function(quest, npc)
        local q = DB.quests[quest]
        return q ~= nil and type(q.giver) == "table" and q.giver[2] == npc
    end)
    SpyGlass:SetKnownCheck("R", function(quest, itemID)
        local q = DB.quests[quest]
        return q ~= nil and type(q.rewards) == "table" and tContains(q.rewards, itemID)
    end)
end
