local _, ns = ...
local D = ns.Data

-- Contributing discoveries (opt in: "Contribute data" in SpyGlass's settings).
-- SpyGlass notes what you see that its data doesn't have yet: loot and who
-- dropped it, what vendors sell and for what, who gives quests and their
-- rewards, rares and bosses. It reports them, as addon messages (never chat
-- text), on a hidden channel to the developer's SpyGlass when it's online
-- (collector mode, /sg collect), which keeps them for the next update.
-- Nothing about you is sent or kept: no names, guilds or chat.
local C = {}
ns.Contribute = C

local CHANNEL = "SpyGlassData"
local PREFIX = "SGD"
local MAX_QUEUE = 1000
local SEND_EVERY = 1.2      -- seconds between messages (addon messages are throttled)
local HELLO_EVERY = 300     -- the collector says it's there this often
local GEAR_OR_RECIPE = { [2] = true, [4] = true, [9] = true }

---------------------------------------------------------------------------
-- Facts: short strings, kind first
--   L:<npc>:<place>:<item>        loot (npc may be o<id> for an object)
--   V:<npc>:<item>:<cost>          a vendor sells it (cost: g<copper> or c<n>x<currency or item>)
--   N:<npc>:<map>:<x>:<y>          where an NPC stands (vendors, quest givers)
--   Q:<quest>:<npc>                who gives a quest
--   R:<quest>:<item>               a quest's reward (a choice, or one you always get)
--   B:<npc>:<class>:<level>:<place> a rare or boss
--   S:<quest>:<spell>              a quest teaches a profession recipe
--   K:<spell>:<how>                you learned a profession recipe: how is
--                                  t<npc> (a trainer), i<item> (a recipe item you
--                                  used), q<quest> (a quest you'd just turned in) or u
-- place: i<instance map ID> inside an instance, else m<uiMapID>.
---------------------------------------------------------------------------

local function DB()
    ns.db.contrib = type(ns.db.contrib) == "table" and ns.db.contrib or {}
    local c = ns.db.contrib
    c.queue = type(c.queue) == "table" and c.queue or {}
    return c
end

local function Enabled()
    return ns.db and ns.db.contribute and true or false
end

local function Hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return string.format("%08x", h)
end

local function NpcID(guid)
    if not guid then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
    if kind == "GameObject" then return "o" .. id end
end

local function Place()
    local _, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
    if instanceType and instanceType ~= "none" and instanceID then return "i" .. instanceID end
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    return map and ("m" .. map) or nil
end

local function ItemID(link) return ns.Items.IDFromLink(link) end

local function Wanted(itemID)
    local _, _, _, classID = ns:Instant(itemID)
    return itemID and GEAR_OR_RECIPE[classID or -1] or false
end

-- What SpyGlass already knows, so only new facts are sent. Plugins add their
-- own checks (the quest plugin knows its quests): C.known[kind] = fn(fact parts).
C.known = {}
local bossItems, bossNpcs

local function AtlasKnown()
    if bossItems then return end
    bossItems, bossNpcs = {}, {}
    for _, inst in ipairs(ns.AtlasData:GetInstances() or {}) do
        for _, boss in ipairs(inst.bosses) do
            for _, npc in ipairs(boss.npcIDs or {}) do
                bossNpcs[npc] = true
                for _, itemID in ipairs(boss.items) do bossItems[npc .. ":" .. itemID] = true end
            end
        end
    end
end

local function Known(kind, a, b)
    if C.known[kind] and C.known[kind](a, b) then return true end
    if kind == "L" then
        AtlasKnown()
        return bossItems[tostring(a) .. ":" .. tostring(b)] or false
    elseif kind == "B" then
        AtlasKnown()
        return bossNpcs[a] or false
    end
    return false
end

-- The professions' recipes by spell ID ({ learn, recipe }) and by name.
local recipeBySpell, recipeByName

local function Recipes()
    if recipeBySpell then return end
    recipeBySpell, recipeByName = {}, {}
    for _, list in pairs(ns.ProfessionData or {}) do
        for _, r in ipairs(list) do
            recipeBySpell[r.id] = r
            if r.name then recipeByName[r.name] = r end
        end
    end
end

-- Does the data already say how this recipe is learned, as the fact does?
local function KnownLearn(spell, how)
    Recipes()
    local r = recipeBySpell[spell]
    if not r then return false end
    local first = r.learn and r.learn[1] or ""
    if first:find("no source", 1, true) then return false end
    if how:sub(1, 1) == "t" then return first:sub(1, 7) == "Trainer" end
    if how:sub(1, 1) == "i" then return r.recipe == tonumber(how:sub(2)) end
    return false
end

-- Does SpyGlass (this version, with its plugins) know the fact already?
function C.KnownFact(fact)
    local kind, a, b = fact:match("^(%a):([^:]+):([^:]+)")
    if kind == "L" then
        local npc, _, item = fact:match("^L:([^:]+):([^:]+):(%d+)$")
        return Known("L", npc, tonumber(item))
    elseif kind == "V" or kind == "R" then
        return Known(kind, tonumber(a) or a, tonumber(b))
    elseif kind == "Q" then
        return Known("Q", tonumber(a), tonumber(b) or b)
    elseif kind == "B" then
        return Known("B", tonumber(a))
    elseif kind == "K" then
        return KnownLearn(tonumber(a), b)
    elseif kind == "S" then
        Recipes()
        local r = recipeBySpell[tonumber(b)]
        return (r and r.learn and (r.learn[1] or ""):find("Quest", 1, true) ~= nil) or false
    end
    return false
end

-- Queues a fact for the developer (a release's leftovers, see Sync.lua).
function C.Queue(fact)
    local db = DB()
    for _, f in ipairs(db.queue) do
        if f == fact then return end
    end
    db.queue[#db.queue + 1] = fact
    while #db.queue > MAX_QUEUE do table.remove(db.queue, 1) end
end

local seenThisSession = {}

local function Note(fact)
    if not Enabled() or seenThisSession[fact] then return end
    seenThisSession[fact] = true
    local db = DB()
    for _, f in ipairs(db.queue) do
        if f == fact then return end
    end
    db.queue[#db.queue + 1] = fact
    while #db.queue > MAX_QUEUE do table.remove(db.queue, 1) end
    if ns.Sync then ns.Sync:Add(fact) end
    C:Flush()
end
C.Note = Note -- Journal/DungeonWatch.lua's pulls and floor sightings go the same way

local function Position(npc)
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, "player")
    if pos then
        local x, y = pos:GetXY()
        Note(string.format("N:%s:%d:%.1f:%.1f", npc, map, x * 100, y * 100))
    end
end

---------------------------------------------------------------------------
-- Watching
---------------------------------------------------------------------------

local function OnLoot()
    local place = Place()
    if not place then return end
    for slot = 1, (GetNumLootItems and GetNumLootItems() or 0) do
        local itemID = ItemID(GetLootSlotLink(slot))
        if itemID and Wanted(itemID) then
            local npc = NpcID(GetLootSourceInfo and (GetLootSourceInfo(slot)))
            if npc and not Known("L", npc, itemID) then
                Note(string.format("L:%s:%s:%d", npc, place, itemID))
            end
        end
    end
end

local function OnMerchant()
    local npc = NpcID(UnitGUID("npc"))
    if not npc then return end
    local any = false
    for i = 1, (GetMerchantNumItems and GetMerchantNumItems() or 0) do
        local itemID = ItemID(GetMerchantItemLink(i))
        if itemID and Wanted(itemID) and not Known("V", npc, itemID) then
            local _, _, price, _, _, _, _, extendedCost = GetMerchantItemInfo(i)
            local cost
            if extendedCost and GetMerchantItemCostInfo then
                local parts = {}
                for j = 1, GetMerchantItemCostInfo(i) do
                    local _, value, link, currency = GetMerchantItemCostItem(i, j)
                    parts[#parts + 1] = "c" .. (value or 0) .. "x" .. (ItemID(link) or (currency or "?"):gsub("[:;]", ""))
                end
                if price and price > 0 then table.insert(parts, 1, "g" .. price) end
                cost = table.concat(parts, "+")
            else
                cost = "g" .. (price or 0)
            end
            Note(string.format("V:%s:%d:%s", npc, itemID, cost))
            any = true
        end
    end
    if any then Position(npc) end
end

local function OnQuestDetail()
    local quest = GetQuestID and GetQuestID()
    local npc = NpcID(UnitGUID("npc"))
    if quest and quest > 0 and npc and not Known("Q", quest, npc) then
        Note(string.format("Q:%d:%s", quest, npc))
        Position(npc)
    end
end

local function OnQuestRewards()
    local quest = GetQuestID and GetQuestID()
    if not (quest and quest > 0) then return end
    for _, kind in ipairs({ "choice", "reward" }) do
        local n = kind == "choice" and (GetNumQuestChoices and GetNumQuestChoices() or 0)
            or (GetNumQuestRewards and GetNumQuestRewards() or 0)
        for i = 1, n do
            local itemID = ItemID(GetQuestItemLink(kind, i))
            if itemID and Wanted(itemID) and not Known("R", quest, itemID) then
                Note(string.format("R:%d:%d", quest, itemID))
            end
        end
    end
    -- A recipe the quest teaches outright (no item).
    Recipes()
    local spells = {}
    if C_QuestInfoSystem and C_QuestInfoSystem.GetQuestRewardSpells then
        for _, id in ipairs(C_QuestInfoSystem.GetQuestRewardSpells(quest) or {}) do spells[#spells + 1] = id end
    elseif GetRewardSpell then
        local id = select(9, GetRewardSpell())
        if id then spells[#spells + 1] = id end
    end
    for _, spell in ipairs(spells) do
        local fact = string.format("S:%d:%d", quest, spell)
        if recipeBySpell[spell] and not C.KnownFact(fact) then Note(fact) end
    end
end

-- How you came to learn a recipe: the trainer you're at, the recipe item you
-- just used, or the quest you just turned in.
local trainer, lastItem, lastQuest

local function OnRecipeItemUsed(bag, slot)
    local ok, link = pcall(ns.Items.GetSlotLink, bag, slot)
    local itemID = ok and ItemID(link) or nil
    local _, _, _, classID = ns:Instant(itemID or 0)
    if itemID and classID == ns.Items.CLASS.RECIPE then lastItem = { id = itemID, t = GetTime() } end
end

local function OnLearned(spell)
    Recipes()
    if not (spell and recipeBySpell[spell]) then return end
    local how = "u"
    if lastItem and GetTime() - lastItem.t < 15 then
        how = "i" .. lastItem.id
    elseif trainer then
        how = "t" .. trainer
    elseif lastQuest and GetTime() - lastQuest.t < 10 then
        how = "q" .. lastQuest.id
    end
    lastItem = nil
    local fact = string.format("K:%d:%s", spell, how)
    if not C.KnownFact(fact) then Note(fact) end
end

-- "You have learned how to create a new item: X" (when NEW_RECIPE_LEARNED doesn't fire).
local function OnSystemMessage(text)
    local pattern = ERR_LEARN_RECIPE_S and ERR_LEARN_RECIPE_S:gsub("%%s", "(.+)")
    local name = pattern and text and text:match("^" .. pattern .. "$")
    if not name then return end
    Recipes()
    local r = recipeByName[name]
    if r then OnLearned(r.id) end
end

local function OnTarget()
    if not UnitExists("target") or UnitIsPlayer("target") then return end
    local class = UnitClassification("target")
    local inInstance = IsInInstance and IsInInstance()
    local boss = class == "worldboss" or class == "rare" or class == "rareelite"
        or (inInstance and class == "elite" and UnitLevel("target") == -1)
    if not boss then return end
    local npc = NpcID(UnitGUID("target"))
    local place = Place()
    if npc and place and type(npc) == "number" and not Known("B", npc) then
        Note(string.format("B:%d:%s:%d:%s", npc, class, UnitLevel("target") or 0, place))
    end
end

---------------------------------------------------------------------------
-- The channel
---------------------------------------------------------------------------

local outbox, sending = {}, false
local channelID

local function Hide()
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local frame = _G["ChatFrame" .. i]
        if frame and ChatFrame_RemoveChannel then pcall(ChatFrame_RemoveChannel, frame, CHANNEL) end
    end
end

-- Your other channels' numbers, lowest first.
local function OtherChannels()
    local list, others = { GetChannelList() }, {}
    for i = 1, #list, 3 do
        local id, name = list[i], list[i + 1]
        if type(id) == "number" and name ~= CHANNEL then others[#others + 1] = id end
    end
    table.sort(others)
    return others
end

-- Your channels in order: General, Trade and LocalDefense are always 1, 2
-- and 3, then the game's other channels, then addons' and your own, with
-- ours last. Within each group they keep the order they had.
local FIRST = { General = 1, Trade = 2, LocalDefense = 3 }

local function Rank(name, server)
    local base = name:match("^(%S+)") or name
    if FIRST[base] then return FIRST[base] end
    if server[base] then return 4 end
    if name == CHANNEL then return 6 end
    return 5
end

local sorting = false
local function SortChannels()
    local swap = (C_ChatInfo and C_ChatInfo.SwapChatChannelsByChannelIndex) or SwapChatChannelByLocalID
    if not swap or sorting then return end
    sorting = true
    local server = {}
    if EnumerateServerChannels then
        for _, name in ipairs({ pcall(EnumerateServerChannels) }) do
            if type(name) == "string" then server[name] = true end
        end
    end
    -- Neighbours swapped when out of order, so each group keeps its order.
    for _ = 1, 100 do
        local list, chans = { GetChannelList() }, {}
        for i = 1, #list, 3 do
            local id, name = list[i], list[i + 1]
            if type(id) == "number" and type(name) == "string" then
                chans[#chans + 1] = { id = id, rank = Rank(name, server) }
            end
        end
        table.sort(chans, function(a, b) return a.id < b.id end)
        local from, to
        for i = 1, #chans - 1 do
            if chans[i].rank > chans[i + 1].rank then
                from, to = chans[i].id, chans[i + 1].id
                break
            end
        end
        if not from or not pcall(swap, from, to) then break end
    end
    sorting = false
end
local MoveLast = SortChannels

-- The game joins General, Trade and the rest a moment after login: ours waits
-- for them (or 20 seconds), so it never takes their numbers.
local ready = false
local function WhenReady(fn)
    if ready then return fn() end
    local tries = 0
    local function check()
        tries = tries + 1
        if #OtherChannels() > 0 or tries >= 20 then
            -- One more second for the rest of them to join.
            C_Timer.After(1, function()
                ready = true
                fn()
            end)
        else
            C_Timer.After(1, check)
        end
    end
    check()
end

local function Channel()
    if not ready then return nil end
    if channelID and GetChannelName(CHANNEL) == channelID then return channelID end
    local id = GetChannelName(CHANNEL)
    if not id or id == 0 then
        JoinTemporaryChannel(CHANNEL)
    end
    MoveLast()
    id = GetChannelName(CHANNEL)
    Hide()
    channelID = (id and id > 0) and id or nil
    return channelID
end

local function Pump()
    if #outbox == 0 then
        sending = false
        return
    end
    local id = Channel()
    if id then
        local msg = table.remove(outbox, 1)
        pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "CHANNEL", id)
    end
    C_Timer.After(SEND_EVERY, Pump)
end

local function Send(msg)
    for _, m in ipairs(outbox) do
        if m == msg then return end
    end
    outbox[#outbox + 1] = msg
    if not sending then
        sending = true
        C_Timer.After(0.1, Pump)
    end
end

C.Send = Send
C.Hash = Hash
C.Enabled = Enabled
C.handlers = {} -- fn(msg, sender) for messages this file doesn't handle (Sync.lua)

-- A collector is listening: send it what's queued (it says OK to each).
local collectorSeen = false
function C:Flush()
    if not (Enabled() and collectorSeen) then return end
    for _, fact in ipairs(DB().queue) do Send("F:" .. fact) end
end

---------------------------------------------------------------------------
-- Collector mode (the developer)
---------------------------------------------------------------------------

local function Collecting()
    return ns.db and ns.db.collector and true or false
end

local salt = tostring(math.random(1, 2 ^ 30))

-- Is the fact well formed, with numbers where numbers belong?
local CHECK = {
    L = "^L:o?%d+:[im]%d+:%d+$",
    V = "^V:o?%d+:%d+:[%w%+x%-' ]+$",
    N = "^N:o?%d+:%d+:%d+%.?%d*:%d+%.?%d*$",
    Q = "^Q:%d+:o?%d+$",
    R = "^R:%d+:%d+$",
    B = "^B:%d+:%a+:%-?%d+:[im]%d+$",
    S = "^S:%d+:%d+$",
    K = "^K:%d+:[tiqu]o?%d*$",
    P = "^P:%d+:%d+:[%d%.%-]+:[%d%.%-]+:[%dx%.]+$", -- a pull (Journal/DungeonWatch.lua)
    W = "^W:%d+:%d+:%d+$",                         -- an NPC seen on a dungeon floor
}

-- Is the fact one of ours, well formed?
function C.Valid(fact)
    local check = type(fact) == "string" and CHECK[fact:sub(1, 1)]
    return check and #fact < 200 and fact:find(check) ~= nil or false
end

local function Store(fact, sender)
    if not C.Valid(fact) then return false end
    ns.db.collected = type(ns.db.collected) == "table" and ns.db.collected or {}
    local entry = ns.db.collected[fact]
    if not entry then
        entry = { n = 0, s = {}, t = time() }
        ns.db.collected[fact] = entry
    end
    -- Senders are only counted (a salted hash of the compact name, so every shape of one name
    -- counts once), never kept by name.
    local who = Hash(salt .. (ns.Units.Compact(sender) or "?"))
    if not entry.s[who] then
        entry.s[who] = true
        entry.n = entry.n + 1
    end
    return true
end

C.Collecting = Collecting

function C:Hello()
    if Collecting() then Send("HI") end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("CHAT_MSG_ADDON")
events:RegisterEvent("LOOT_OPENED")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("QUEST_DETAIL")
events:RegisterEvent("QUEST_COMPLETE")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
for _, event in ipairs({ "NEW_RECIPE_LEARNED", "CHAT_MSG_SYSTEM", "TRAINER_SHOW", "TRAINER_CLOSED", "QUEST_TURNED_IN" }) do
    pcall(events.RegisterEvent, events, event)
end
pcall(events.RegisterEvent, events, "UPDATE_CHAT_WINDOWS")
pcall(events.RegisterEvent, events, "CHANNEL_UI_UPDATE")

local function Safe(fn)
    local ok, err = pcall(fn)
    if not ok and ns.db and ns.db.debugContrib then ns:Print("contribute: " .. tostring(err)) end
end

events:SetScript("OnEvent", function(_, event, prefix, msg, _, sender)
    if event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
        C:Apply()
        C:AskOnce()
        WhenReady(MoveLast)
    elseif event == "CHAT_MSG_ADDON" then
        if prefix ~= PREFIX or not msg then return end
        if msg == "HI" then
            -- A collector is online: send what we have.
            if not Collecting() then
                collectorSeen = true
                C:Flush()
            end
        elseif msg:sub(1, 2) == "F:" and Collecting() then
            local fact = msg:sub(3)
            if Store(fact, sender) then
                Send("OK:" .. Hash(fact))
                if ns.Sync then ns.Sync:Add(fact) end
            end
        elseif msg:sub(1, 3) == "OK:" and Enabled() then
            -- The collector kept it: drop it from the queue.
            local h, queue = msg:sub(4), DB().queue
            for i = #queue, 1, -1 do
                if Hash(queue[i]) == h then table.remove(queue, i) end
            end
        else
            for _, fn in ipairs(C.handlers) do fn(msg, sender) end
        end
    elseif event == "UPDATE_CHAT_WINDOWS" or event == "CHANNEL_UI_UPDATE" then
        if ready then MoveLast() end
        if Enabled() or Collecting() then Hide() end
    elseif Enabled() then
        if event == "LOOT_OPENED" then Safe(OnLoot)
        elseif event == "MERCHANT_SHOW" then Safe(OnMerchant)
        elseif event == "QUEST_DETAIL" then Safe(OnQuestDetail)
        elseif event == "QUEST_COMPLETE" then Safe(OnQuestRewards)
        elseif event == "PLAYER_TARGET_CHANGED" then Safe(OnTarget)
        elseif event == "TRAINER_SHOW" then trainer = NpcID(UnitGUID("npc"))
        elseif event == "TRAINER_CLOSED" then trainer = nil
        elseif event == "QUEST_TURNED_IN" then lastQuest = { id = prefix, t = GetTime() }
        elseif event == "NEW_RECIPE_LEARNED" then Safe(function() OnLearned(prefix) end)
        elseif event == "CHAT_MSG_SYSTEM" then Safe(function() OnSystemMessage(prefix) end)
        end
    end
end)

-- Using a recipe item from your bags (what teaches you the recipe you learn next).
if C_Container and C_Container.UseContainerItem then
    hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot) Safe(function() OnRecipeItemUsed(bag, slot) end) end)
elseif UseContainerItem then
    hooksecurefunc("UseContainerItem", function(bag, slot) Safe(function() OnRecipeItemUsed(bag, slot) end) end)
end

-- The first time SpyGlass loads: ask whether to share. Sharing goes both
-- ways: without it, nothing is sent and nothing from others is received.
-- Only add an entry: assigning StaticPopupDialogs itself would taint
-- Blizzard's own dialogs.
if StaticPopupDialogs then
    StaticPopupDialogs.SPYGLASS_SHARE = {
        text = "SpyGlass: share discoveries to stay up to date?\n\n"
            .. "SpyGlass can trade what players find that its data doesn't have yet (loot and who dropped it, "
            .. "what vendors sell, quest givers and rewards, where recipes are learned, rares and bosses) with other "
            .. "SpyGlass players, "
            .. "so everyone's lists stay current between updates.\n\n"
            .. "No names, guilds or chat are ever shared. Without sharing you also won't receive others' "
            .. "discoveries. You can change this in Options > AddOns > SpyGlass.",
        button1 = YES or "Yes",
        button2 = NO or "No",
        OnAccept = function()
            ns.db.contributeAsked = true
            C:SetEnabled(true)
        end,
        OnCancel = function()
            ns.db.contributeAsked = true
            C:SetEnabled(false)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = false,
    }
end

function C:AskOnce()
    if ns.db.contributeAsked or not StaticPopup_Show then return end
    C_Timer.After(10, function()
        if not ns.db.contributeAsked then StaticPopup_Show("SPYGLASS_SHARE") end
    end)
end

local ticker
-- Joins (or leaves) the channel for the current settings.
function C:Apply()
    if Enabled() or Collecting() then
        WhenReady(function()
            if not (Enabled() or Collecting()) then return end
            Channel()
            if Collecting() then
                C:Hello()
                ticker = ticker or C_Timer.NewTicker(HELLO_EVERY, function() C:Hello() end)
            end
        end)
    else
        if GetChannelName(CHANNEL) and GetChannelName(CHANNEL) > 0 then LeaveChannelByName(CHANNEL) end
        channelID = nil
    end
    if not Collecting() and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

-- Through ns:SetOption, so Options > AddOns > SpyGlass shows it; the option's apply (Settings.lua)
-- starts or stops sharing (C:Apply, Sync:Apply).
function C:SetEnabled(on)
    ns:SetOption("db.contribute", on and true or false)
end

-- /sg collect [on|off|status]
function C:Command(arg)
    if arg == "on" or (arg == "" and not Collecting()) then
        ns.db.collector = true
        self:Apply()
        ns:Print("Collector mode on: discoveries reported by players are kept (/sg collect status).")
    elseif arg == "off" or arg == "" then
        ns.db.collector = nil
        self:Apply()
        ns:Print("Collector mode off.")
    else
        local facts, multi = 0, 0
        for _, e in pairs(ns.db.collected or {}) do
            facts = facts + 1
            if e.n > 1 then multi = multi + 1 end
        end
        ns:Print(string.format("Collector %s. %d facts kept (%d reported by more than one player); "
            .. "your own queue: %d, waiting to send: %d.", Collecting() and "on" or "off", facts, multi,
            #DB().queue, #outbox))
    end
end
