local _, ns = ...

-- Auto Accept and Auto Turn-in (Options > AddOns > Field Guide; both on until you turn them off). Hold
-- Shift when you talk to an NPC to do it by hand. It stops, for you to decide, at anything that's
-- yours to choose: a reward to pick, or gold a quest wants. Quests you skipped aren't taken, repeatable
-- quests are left alone, and gray ones are only taken in Zone Clear.
local A = {}
ns.AutoQuest = A

local Call = ns.QuestieKit.Call

-- Exists.lua reads the NPC's dialog 0.2 seconds after it opens to see what's offered: we leave it open
-- until then, or a quest you've just taken would look like one the NPC doesn't have.
local DIALOG_DELAY = 0.3
local RETRY_SECONDS = 30 -- a quest that didn't go through (full log, say) isn't tried again for this long

local tried = {} -- [questID] = when we last chose it from a list

local function Paused() return IsShiftKeyDown and IsShiftKeyDown() end

local function Fresh(id)
    return not id or not tried[id] or GetTime() - tried[id] >= RETRY_SECONDS
end

local function Mark(id)
    if id then tried[id] = GetTime() end
end

-- Worth taking from an NPC's list.
local function Takes(id, trivial, repeatable)
    if repeatable or (id and ns.char.ignored[id]) or not Fresh(id) then return false end
    return not trivial or ns.char.preference == "clear"
end

-- A gossip window: quests to hand in first, then quests to take.
local function FromGossip()
    if ns.db.autoTurnIn then
        for _, q in ipairs(Call(C_GossipInfo.GetActiveQuests) or {}) do
            if q.isComplete and not q.repeatable and Fresh(q.questID) then
                Mark(q.questID)
                return C_GossipInfo.SelectActiveQuest(q.questID)
            end
        end
    end
    if ns.db.autoAccept then
        for _, q in ipairs(Call(C_GossipInfo.GetAvailableQuests) or {}) do
            if Takes(q.questID, q.isTrivial, q.repeatable) then
                Mark(q.questID)
                return C_GossipInfo.SelectAvailableQuest(q.questID)
            end
        end
    end
end

-- The plainer list some NPCs show instead.
local function FromGreeting()
    if ns.db.autoTurnIn then
        for i = 1, Call(GetNumActiveQuests) or 0 do
            local _, complete = Call(GetActiveTitle, i)
            local id = Call(GetActiveQuestID, i)
            if complete and Fresh(id) then
                Mark(id)
                return SelectActiveQuest(i)
            end
        end
    end
    if ns.db.autoAccept then
        for i = 1, Call(GetNumAvailableQuests) or 0 do
            local trivial, _, repeatable, _, id = Call(GetAvailableQuestInfo, i)
            if Takes(id, trivial, repeatable) then
                Mark(id)
                return SelectAvailableQuest(i)
            end
        end
    end
end

local function Later(fn)
    if Paused() then return end
    C_Timer.After(DIALOG_DELAY, function()
        if not Paused() then fn() end
    end)
end

ns:On("GOSSIP_SHOW", function()
    if ns.db.autoAccept or ns.db.autoTurnIn then Later(FromGossip) end
end)

ns:On("QUEST_GREETING", function()
    if ns.db.autoAccept or ns.db.autoTurnIn then Later(FromGreeting) end
end)

-- A quest's description, with Accept on it.
ns:On("QUEST_DETAIL", function()
    if not ns.db.autoAccept then return end
    local id = Call(GetQuestID)
    if id and ns.char.ignored[id] then return end
    Later(function()
        -- (Still this quest's dialog: you may have closed it, or moved on.)
        if ns.db.autoAccept and Call(GetQuestID) == id then AcceptQuest() end
    end)
end)

-- "Have you got them?": Continue is on if you have.
ns:On("QUEST_PROGRESS", function()
    if not ns.db.autoTurnIn or Paused() then return end
    if Call(IsQuestCompletable) and (Call(GetQuestMoneyToGet) or 0) == 0 then CompleteQuest() end
end)

-- The rewards. One you're given isn't a choice; two or more are yours to pick from.
ns:On("QUEST_COMPLETE", function()
    if not ns.db.autoTurnIn or Paused() then return end
    local choices = Call(GetNumQuestChoices) or 0
    if choices <= 1 then GetQuestReward(choices) end
end)
