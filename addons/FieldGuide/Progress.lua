local _, ns = ...

-- Where you stand: your race, your level, which quests you've finished, which are in your log and
-- whether their objectives are done. Finished quests come from the game, and from Questie's
-- record of them; Questie also says whether you can take a quest at all (class, reputation,
-- quests that rule each other out).
local P = {}
ns.Progress = P

-- Race ID -> name and QuestieDB race bit: only to skip the quests your race can't take.
P.RACES = {
    [1] = { "Human", 1 }, [2] = { "Orc", 2 }, [3] = { "Dwarf", 4 }, [4] = { "NightElf", 8 },
    [5] = { "Undead", 16 }, [6] = { "Tauren", 32 }, [7] = { "Gnome", 64 }, [8] = { "Troll", 128 },
    [95] = { "SkyborneA", 2 ^ 32 }, [96] = { "SkyborneH", 2 ^ 33 },
}

local completed = {} -- questId -> true, refreshed on quest events
local doable = {}    -- questId -> Questie's verdict, until quests change

-- Questie from the outside: shared Questie.lua (guarded; answers nil / false without Questie).
local K = ns.QuestieKit
local Call = K.Call

function P:Race()
    local _, _, id = UnitRace("player")
    local r = id and self.RACES[id]
    return r and r[1], r and r[2] or 0, id
end

function P:Level() return UnitLevel("player") or 1 end

-- Can your race take a quest? (QuestieDB masks go past 2^32: plain arithmetic, not bit.band.)
function P:RaceAllowed(mask)
    local _, bit = self:Race()
    if not mask or mask == 0 or bit == 0 then return true end
    return (mask % (2 * bit)) >= bit
end

function P:Refresh()
    wipe(completed)
    wipe(doable)
    K.CompletedIDs(completed)
end

-- Finished for sure: the game's record, or Questie's (read live: it updates as you play).
local function Flagged(id)
    if completed[id] or (ns.char and ns.char.doneByHand and ns.char.doneByHand[id]) then return true end
    local flagged = K.IsDone(id) -- Questie's record, else the game's
    if flagged then completed[id] = true end
    return flagged
end

local Questie_ = K.Query

-- Later quests that need each quest first (from the guides' data), built once.
local needs
local function Dependents(id)
    if not needs then
        needs = {}
        for qid, q in pairs(ns.Quests or {}) do
            for _, p in ipairs(q.pre or {}) do
                needs[p] = needs[p] or {}
                table.insert(needs[p], qid)
            end
        end
    end
    return needs[id]
end

-- Done, or as good as done, so no guide sends you to pick it up:
--   * the game or Questie has it finished;
--   * you did a version of it that rules it out (Questie's exclusiveTo), or it's a breadcrumb
--     and you've done or taken the quest it leads to;
--   * a later quest that needs it is done or in your log (so you must have done it, whatever
--     the record says).
function P:Done(id)
    if Flagged(id) then return true end
    if self:InLog(id) then return false end
    local inferred = false
    for _, other in ipairs(Questie_(id, "exclusiveTo") or {}) do
        if Flagged(other) or self:InLog(other) then inferred = true; break end
    end
    local leadsTo = not inferred and Questie_(id, "breadcrumbForQuestId")
    if type(leadsTo) == "number" and (Flagged(leadsTo) or self:InLog(leadsTo)) then inferred = true end
    if not inferred then
        for _, later in ipairs(Dependents(id) or {}) do
            if Flagged(later) or self:InLog(later) then inferred = true; break end
        end
    end
    if inferred then completed[id] = true end
    return inferred
end

-- In your quest log (the modern lookup, else the older one, else a walk through the log).
function P:InLog(id)
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        local index = Call(C_QuestLog.GetLogIndexForQuestID, id)
        return index ~= nil and index > 0
    end
    if GetQuestLogIndexByID then
        local index = Call(GetQuestLogIndexByID, id)
        return index ~= nil and index > 0
    end
    for _, q in ipairs(self:LogQuests()) do
        if q == id then return true end
    end
    return false
end

-- The quest IDs in your log.
function P:LogQuests()
    local out = {}
    local n = C_QuestLog and Call(C_QuestLog.GetNumQuestLogEntries) or (GetNumQuestLogEntries and GetNumQuestLogEntries()) or 0
    for i = 1, n do
        local id
        local info = C_QuestLog and C_QuestLog.GetInfo and Call(C_QuestLog.GetInfo, i)
        if type(info) == "table" then
            if not info.isHeader then id = info.questID end
        elseif GetQuestLogTitle then
            local _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(i)
            if not isHeader then id = questID end
        end
        if id and id > 0 then out[#out + 1] = id end
    end
    return out
end

-- In your log with every objective done.
-- Whether a quest in your log has no objectives at all (talk to someone and hand it in), from the
-- game; nil when the game can't say.
function P:NoObjectives(id)
    if not (self:InLog(id) and C_QuestLog and C_QuestLog.GetQuestObjectives) then return nil end
    local objectives = Call(C_QuestLog.GetQuestObjectives, id)
    if type(objectives) ~= "table" then return nil end
    return #objectives == 0
end

function P:ReadyToTurnIn(id)
    if not self:InLog(id) then return false end
    return Call(C_QuestLog.IsComplete, id) and true or false
end

-- Questie's verdict on whether you could take the quest at all (ignores level). True when
-- Questie can't tell.
function P:Doable(id)
    if doable[id] ~= nil then return doable[id] end
    doable[id] = self:AskQuestie(id)
    return doable[id]
end

function P:AskQuestie(id)
    return K.IsDoable(id, true) -- true when Questie can't tell
end

-- Puts the quest you're on at the top of Questie's tracker (its "focus").
function P:FocusQuestie(id)
    if not (ns.db.focusQuestie and K.CharDB()) then return end
    if not self:InLog(id) then return end
    K.SetFocus(id) -- writes the focus (unless it's already this quest) and redraws the tracker
end

ns:On("PLAYER_LOGIN", function() P:Refresh(); ns:Changed() end)
for _, event in ipairs({ "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_LOG_UPDATE", "PLAYER_LEVEL_UP",
    "ZONE_CHANGED_NEW_AREA" }) do
    ns:On(event, function()
        if event ~= "QUEST_LOG_UPDATE" and event ~= "ZONE_CHANGED_NEW_AREA" then wipe(doable) end
        -- Zone, level and quests taken or handed in can change which section fits.
        if event ~= "QUEST_LOG_UPDATE" and ns.Engine then ns.Engine:Invalidate() end
        ns:Changed()
    end)
end
-- The game marks a turn-in done a moment after the event.
ns:On("QUEST_TURNED_IN", function(id)
    if id then completed[id] = true end
    C_Timer.After(1, function() P:Refresh(); ns:Changed() end)
end)
