local ADDON, ns = ...

-- Registers with SpyGlass: the "Quests" category, an entry for every
-- quest that rewards a weapon or armor, and the "quest" origin, which names
-- the next step of the chain you still have to do. Then the World, Vendors
-- and Crafted categories from the source index (Sources.lua).
local Q, Location, Window = ns.Quests, ns.Location, ns.QuestWindow

if not (SpyGlass and SpyGlass.RegisterPlugin and ns.QuestDB) then return end

local TICK = "|cff40ff40done|r"

-- The row text: the quest and, for a chain, the next step you still have
-- to do. Cheap (no map or giver lookups): it runs for every listed item.
local function Text(reward)
    local step, index, chain = Q:NextStep(reward)
    local title = Q:Title(reward)
    if #chain > 1 then
        return "Quest: " .. title .. " - next: " .. Q:Title(step) .. " (step " .. index .. " of " .. #chain .. ")"
    end
    return "Quest: " .. title
end

-- What the list shows for a quest reward. SpyGlass keeps the answer until
-- your quests change, so it follows your progress through the chain. When
-- the item is hidden, reason says why (for /sg debug).
local function Resolve(origin)
    local reward = origin.quest
    if not Q:Exists(reward) then return { available = false, reason = "unknown quest" } end
    if not Q:Allowed(reward) then return { available = false, reason = "not for your character" } end
    -- Green or better only (the quest data has no quality; the game's item info does).
    -- Peek: only what the game has; the list asks for items as it draws them.
    -- Until it has the item, ask again next time (cache = false).
    local info = SpyGlass:PeekItem(origin.item)
    if info and (info.quality or 0) < 2 then return { available = false, reason = "below green" } end

    local ok, text = pcall(Text, reward)
    if not ok then text = "Quest: " .. Q:Title(reward) end
    -- Done: still listed, since you may have the item (or wear it).
    if Q:Done(reward) then text = "Quest (done): " .. Q:Title(reward) end
    return { available = true, text = text, cache = info ~= nil }
end

-- Tooltip lines, worked out on hover: where the next step starts and the
-- whole chain, with finished steps marked.
local function Lines(origin)
    local step, _, chain = Q:NextStep(origin.quest)
    local lines = {}
    local ok, loc = pcall(Location.ForQuest, Location, step)
    if ok and loc then
        local where = loc.zone or "?"
        if loc.subzone then where = loc.subzone .. ", " .. where end
        lines[#lines + 1] = "Start: " .. (loc.giver and loc.giver.name or "?") .. " - " .. where
            .. " (" .. (loc.coords or "?") .. ")"
    end
    if #chain > 1 then
        for i, id in ipairs(chain) do
            if i > 8 and i < #chain then
                if i == 9 then lines[#lines + 1] = "  ..." end
            else
                local state = Q:Done(id) and TICK or (id == step and "|cffffd100next|r" or "")
                lines[#lines + 1] = "  " .. i .. ". " .. Q:Title(id) .. (state ~= "" and ("  " .. state) or "")
            end
        end
    end
    return lines
end

local function OnClick(origin, row)
    Window:Show(origin.quest, row and row.itemID)
end

---------------------------------------------------------------------------
-- The journal's Quests tab: quests that belong to the dungeon or raid
---------------------------------------------------------------------------

local QUEST_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
local DONE_ICON = "Interface\\RaidFrame\\ReadyCheck-Ready"
local STATE_ORDER = { log = 1, open = 2, high = 3, done = 4, other = 5 }

local function QuestRow(questID, inst)
    local level = Q.Get(questID, "questLevel") or 0
    local need = Q.Get(questID, "requiredLevel") or 0
    local state, color, right
    local whyNot = Q:WhyNot(questID)
    if whyNot then
        state, color, right = "other", { 0.6, 0.45, 0.45 }, "|cffcc6666" .. whyNot .. "|r"
    elseif Q:Done(questID) then
        state, color, right = "done", { 0.55, 0.55, 0.55 }, "|cff40ff40Done|r"
    elseif Q:InLog(questID) then
        state, color, right = "log", { 1, 1, 0.3 }, "|cffffff4dIn your log|r"
    elseif UnitLevel("player") < need then
        state, color, right = "high", { 1, 0.5, 0.25 }, "|cffff8040Needs " .. need .. "|r"
    else
        -- Done or not is this character's own record (IsQuestFlaggedCompleted).
        state, color, right = "open", { 1, 0.82, 0 }, "|cffbbbbbbNot done|r"
    end
    right = ((level > 0) and ("Level " .. level) or "") .. (right and ("  " .. right) or "")

    local loc = Location:ForQuest(questID)
    local giver = loc and loc.giver or Q:Giver(questID)
    local sub
    if loc and loc.inside and loc.areaID == inst.areaID then
        sub = "Starts inside, from " .. (giver and giver.name or "?")
    elseif loc then
        sub = "Starts: " .. (giver and giver.name or "?") .. " - " .. (loc.subzone and (loc.subzone .. ", ") or "") .. (loc.zone or "?")
    else
        sub = giver and ("Starts: " .. giver.name) or "Start not known"
    end

    local rewards = Q.rewardsByQuest[questID]
    local icon = (state == "done" and DONE_ICON) or (rewards and GetItemIcon and GetItemIcon(rewards[1])) or QUEST_ICON
    local tooltip = {}
    local objectives = Q.Get(questID, "objectivesText")
    if type(objectives) == "table" and #objectives > 0 then
        tooltip[#tooltip + 1] = table.concat(objectives, " ")
    end
    local chain = Q:Chain(questID)
    if #chain > 1 then tooltip[#tooltip + 1] = "Part " .. #chain .. " of a quest chain." end
    if rewards then
        local names = {}
        for _, itemID in ipairs(rewards) do
            local info = SpyGlass:PeekItem(itemID)
            names[#names + 1] = info and info.name or ("item " .. itemID)
        end
        tooltip[#tooltip + 1] = "|cff40ff40Rewards: " .. table.concat(names, ", ") .. "|r"
    end
    tooltip[#tooltip + 1] = "|cff66bbffClick to open the quest (and track it).|r"

    return {
        text = Q:Title(questID), subtext = sub, right = right, icon = icon, color = color,
        dim = state == "done" or state == "other", tooltip = tooltip, state = state, level = level,
        onClick = function() Window:Show(questID) end,
    }
end

local function QuestTabRows(inst, boss)
    local quests = ns.Dungeons:QuestsFor(inst, boss)
    local rows = {}
    for _, questID in ipairs(quests) do rows[#rows + 1] = QuestRow(questID, inst) end
    table.sort(rows, function(a, b)
        if a.state ~= b.state then return STATE_ORDER[a.state] < STATE_ORDER[b.state] end
        if a.level ~= b.level then return a.level < b.level end
        return a.text < b.text
    end)
    local empty = boss and ("No known quests involve " .. boss.name .. ".")
        or ("No known quests for " .. inst.name .. ".")
    return rows, empty
end

---------------------------------------------------------------------------
-- Following the tracked chain
---------------------------------------------------------------------------

-- The creature ID of the NPC you're talking to.
local function TalkingTo()
    local guid = UnitGUID("npc")
    if not guid then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind ~= "Creature" and kind ~= "GameObject" then return nil end
    return tonumber(id)
end

-- The quests the NPC offers right now: { [questID] = true, [title] = true }.
local function Offered(event)
    local offered = {}
    if event == "GOSSIP_SHOW" and C_GossipInfo and C_GossipInfo.GetAvailableQuests then
        for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
            if q.questID then offered[q.questID] = true end
            if q.title then offered[q.title] = true end
        end
    elseif event == "QUEST_GREETING" and GetNumAvailableQuests then
        for i = 1, GetNumAvailableQuests() do
            local title = GetAvailableTitle(i)
            if title then offered[title] = true end
        end
    elseif event == "QUEST_DETAIL" and GetQuestID then
        local id = GetQuestID()
        if id then offered[id] = true end
        if GetTitleText then offered[GetTitleText() or ""] = true end
    end
    return offered
end

-- You reached the giver of the tracked step: if they don't offer it (you
-- did it before the game kept track, or it isn't for you), move on to the
-- next step of the chain.
local function CheckArrival(event)
    local wp = SpyGlass:GetWaypoint()
    if not (wp and wp.action == "pickup" and wp.quest and wp.person) then return end
    if TalkingTo() ~= wp.person then return end
    local step = wp.quest
    if Q:InLog(step) or Q:Done(step) then return end
    local offered = Offered(event)
    if offered[step] or offered[Q:Title(step)] then return end
    local need = Q.Get(step, "requiredLevel") or 0
    if UnitLevel("player") < need then
        print("|TInterface\\AddOns\\Spyglass\\Media\\Icon:14:14|t |cff66bbffSpyGlass|r: " .. Q:Title(step) .. " needs level " .. need .. ".")
        return
    end
    Q:Skip(step)
    print("|TInterface\\AddOns\\Spyglass\\Media\\Icon:14:14|t |cff66bbffSpyGlass|r: " .. Q:Title(step) .. " isn't offered here - moving to the next step.")
    Window:QuestProgress()
end

for _, event in ipairs({ "QUEST_TURNED_IN", "QUEST_ACCEPTED" }) do
    ns:On(event, function()
        -- The quest log updates a moment after.
        C_Timer.After(0.5, function() Window:QuestProgress() end)
    end)
end
for _, event in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL" }) do
    ns:On(event, function() CheckArrival(event) end)
end

-- Find every gear reward, then every other known item (both spread over
-- frames; see Quests.lua and Sources.lua), then register.
Q:ScanRewards(function(found)
    local rewarded = {}
    for _, r in ipairs(found) do rewarded[r.itemID] = true end
    ns.SourceIndex:Build(rewarded, function(categories, more)
        local entries = {}
        for _, r in ipairs(found) do
            entries[#entries + 1] = {
                itemID = r.itemID, levelHint = r.levelHint,
                origin = { kind = "quest", quest = r.quest, item = r.itemID },
            }
        end
        -- Quest rewards only the source index knew about.
        for _, r in ipairs(more) do
            if r.quest then
                local list = Q.rewardsByQuest[r.quest] or {}
                Q.rewardsByQuest[r.quest] = list
                list[#list + 1] = r.itemID
            end
            entries[#entries + 1] = {
                itemID = r.itemID, levelHint = r.levelHint,
                origin = r.origin or { kind = "quest", quest = r.quest, item = r.itemID },
            }
        end
        table.insert(categories, 1, { key = "quests", label = "Quests", entries = entries })
        local origins = { quest = { Resolve = Resolve, Lines = Lines, OnClick = OnClick } }
        for kind, handler in pairs(ns.SourceIndex.origins) do origins[kind] = handler end
        local ok, why = SpyGlass:RegisterPlugin({
            addon = ADDON,
            name = "Quest Rewards",
            apiVersion = 1,
            categories = categories,
            origins = origins,
        })
        if not ok then
            print("|TInterface\\AddOns\\Spyglass\\Media\\Icon:14:14|t |cff66bbffSpyGlassPluginQuests|r: couldn't register: " .. tostring(why))
            return
        end
        -- Ask for a Quests tab in the loot journal (dungeon and raid quests).
        local granted, refused = SpyGlass:RequestJournalTab(ADDON, {
            key = "quests", label = "Quests", icon = "Interface\\Icons\\INV_Misc_Book_08", Rows = QuestTabRows,
        })
        if not granted then
            print("|TInterface\\AddOns\\Spyglass\\Media\\Icon:14:14|t |cff66bbffSpyGlassPluginQuests|r: no Quests tab in the journal: " .. tostring(refused))
        end
        Window:RestoreTracking()
        ns.SourceIndex:RestoreTracking()
    end)
end)
