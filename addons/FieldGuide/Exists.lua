local _, ns = ...

-- Whether a quest is really there before the guide sends you to it. The guides come from
-- QuestieDB, which knows quests Forever doesn't have (or a giver won't offer you), so:
--   * the server is asked about each quest (C_QuestLog.RequestLoadQuestByID; it answers with
--     QUEST_DATA_LOAD_RESULT), and a quest only goes on the route once it says the quest exists.
--     The answers are kept per game build (ns.db.questCheck), so the scan runs once a patch: at
--     login the guide's quests are asked about a few at a time, and a quest the guide wants that
--     isn't known yet goes to the front. No answer in TIMEOUT seconds: it counts as there.
--   * at the giver: talking to the quest giver of the step to pick up, when they don't offer it
--     (and nothing you need for it is missing), it's dropped from the route (ns.char.notOffered;
--     /fg unskip brings it back).
local X = {}
ns.Exists = X

local PER_TICK = 20  -- questions sent every TICK seconds
local TICK = 0.1
local TIMEOUT = 10
-- The server saying no to more than this share of the first answers (at least TRUST_AFTER of them)
-- means the lookup doesn't work here, not that the quests are gone: every quest counts as there.
-- (Judged once a session, on its first TRUST_AFTER answers.)
local TRUST_AFTER, TRUST_SHARE = 60, 0.5

local cache                  -- ns.db.questCheck: [questID] = true (there) / false (the server has no such quest)
local asked = {}             -- questID -> GetTime() it was asked
local timedOut = {}          -- questID -> true: no answer in time (counts as there, asked again next session)
local queue, queued = {}, {} -- questIDs to ask, front first
local urgent = {}            -- questID -> true: the route is waiting on it (see Busy)
local answers, nos = 0, 0
local broken = false         -- the lookup can't be trusted (see TRUST_SHARE)
local flush                  -- a redraw is coming for answers that came in

local function Api()
    return not broken and C_QuestLog and C_QuestLog.RequestLoadQuestByID and ns.db and true or false
end

local function BuildKey()
    local _, build = GetBuildInfo()
    return tostring(build or "?")
end

local function Cache()
    if not cache then
        local c = ns.db.questCheck
        if type(c) ~= "table" or c.build ~= BuildKey() then
            c = { build = BuildKey() }
            ns.db.questCheck = c
        end
        cache = c
    end
    return cache
end

-- The client already has the quest's title: it exists.
local function Known(id)
    local fn = C_QuestLog and C_QuestLog.GetTitleForQuestID
    local title = fn and ns.QuestieKit.Call(fn, id)
    return type(title) == "string" and title ~= ""
end

local function Enqueue(id, front)
    if queued[id] then
        if not front or urgent[id] then return end
        for i, q in ipairs(queue) do
            if q == id then table.remove(queue, i); break end
        end
    end
    queued[id] = true
    if front then
        urgent[id] = true
        table.insert(queue, 1, id)
    else
        queue[#queue + 1] = id
    end
end

local function Changed()
    if flush then return end
    flush = true
    C_Timer.After(0.5, function()
        flush = nil
        if ns.Engine then ns.Engine:Invalidate() end
        ns:Changed()
    end)
end

-- The server has no such quest.
function X:Missing(id)
    if not Api() then return false end
    return Cache()[id] == false
end

-- Not known yet whether the quest is there: asked (or about to be). Asks for it first if not.
function X:Pending(id)
    if not Api() then return false end
    local c = Cache()
    if c[id] ~= nil or timedOut[id] then return false end
    if Known(id) then
        c[id] = true
        return false
    end
    if asked[id] then
        if GetTime() - asked[id] < TIMEOUT then return true end
        timedOut[id], urgent[id] = true, nil
        return false
    end
    Enqueue(id, true)
    return true
end

-- Still asking about quests the route is waiting on.
function X:Busy()
    if not Api() then return false end
    local now = GetTime()
    for id in pairs(urgent) do
        if Cache()[id] ~= nil or (asked[id] and now - asked[id] >= TIMEOUT) then
            urgent[id] = nil
        else
            return true
        end
    end
    return false
end

-- The quests the server said aren't there, by ID.
function X:MissingList()
    local out = {}
    if not Api() then return out end
    for id, there in pairs(Cache()) do
        if there == false then out[#out + 1] = id end
    end
    table.sort(out)
    return out
end

-- Forget the answers and ask again.
function X:Recheck()
    if not ns.db then return end
    ns.db.questCheck, cache = nil, nil
    wipe(asked); wipe(timedOut); wipe(queue); wipe(queued); wipe(urgent)
    answers, nos, broken = 0, 0, false
    X:ScanGuide()
    Changed()
end

-- Every quest your race could take in the guides (in the background, after what the route wants).
function X:ScanGuide()
    if not Api() then return end
    local c = Cache()
    for id, q in pairs(ns.Quests) do
        if c[id] == nil and not queued[id] and ns.Progress:RaceAllowed(q.rm) then Enqueue(id) end
    end
end

local function Ask()
    if not Api() then return end
    local n = 0
    while n < PER_TICK and #queue > 0 do
        local id = table.remove(queue, 1)
        queued[id] = nil
        local c = Cache()
        if c[id] == nil and not asked[id] then
            if Known(id) then
                c[id], urgent[id] = true, nil
            else
                asked[id] = GetTime()
                ns.QuestieKit.Call(C_QuestLog.RequestLoadQuestByID, id)
                n = n + 1
            end
        end
    end
end

ns:On("QUEST_DATA_LOAD_RESULT", function(id, success)
    if not (id and asked[id] and ns.db) or broken then return end
    local there = success and true or false
    Cache()[id] = there
    timedOut[id], urgent[id] = nil, nil
    answers = answers + 1
    if not there then nos = nos + 1 end
    if answers == TRUST_AFTER and nos > answers * TRUST_SHARE then
        -- Most answers are "no": the lookup isn't telling the truth here. Leave it off.
        broken = true
        ns.db.questCheck, cache = nil, nil
        ns:Print("The server's quest lookup doesn't answer reliably here: every quest counts as there.")
    end
    Changed()
end)

ns:On("PLAYER_LOGIN", function()
    C_Timer.After(2, function() X:ScanGuide() end)
    C_Timer.NewTicker(TICK, Ask)
end)

-- ---------------------------------------------------------------------------------------------
-- At the giver
-- ---------------------------------------------------------------------------------------------

-- The quests the NPC offers right now: { [questID] = true, [title] = true }.
local function Offered(event)
    local offered = {}
    local Call = ns.QuestieKit.Call
    if event == "GOSSIP_SHOW" and C_GossipInfo and C_GossipInfo.GetAvailableQuests then
        for _, q in ipairs(Call(C_GossipInfo.GetAvailableQuests) or {}) do
            if q.questID then offered[q.questID] = true end
            if q.title then offered[q.title] = true end
        end
    elseif event == "QUEST_GREETING" and GetNumAvailableQuests then
        for i = 1, Call(GetNumAvailableQuests) or 0 do
            local title = Call(GetAvailableTitle, i)
            if title then offered[title] = true end
        end
    elseif event == "QUEST_DETAIL" then
        local id = Call(GetQuestID)
        if id then offered[id] = true end
        local title = Call(GetTitleText)
        if title then offered[title] = true end
    end
    return offered
end

local listedAt = 0 -- when the NPC last showed a list of quests (gossip or greeting)

local function CheckGiver(event)
    local E, P = ns.Engine, ns.Progress
    if event ~= "QUEST_DETAIL" then
        listedAt = GetTime()
    elseif GetTime() - listedAt < 30 then
        return -- a quest you picked from the list: it says nothing about the others offered
    end
    if not (E and ns.char) then return end
    local step = E.current and E.steps[E.current]
    if not step or step[1] ~= "A" then return end
    local id = step[2]
    local q = ns.Quests[id]
    if not (q and q.a and q.a[4]) or P:InLog(id) or P:Done(id) then return end
    local npc = ns.QuestieKit.Call(UnitName, "npc")
    if type(npc) ~= "string" or npc ~= q.a[4] then return end
    if (q.r or 1) > P:Level() or not E:PrereqsDone(id) then return end
    local offered = Offered(event)
    if offered[id] or (q.n and offered[q.n]) then return end
    ns.char.notOffered[id] = true
    E:Invalidate()
    ns:Print(("%s isn't offered here: dropped from the route (/fg unskip brings it back)."):format(E:QuestName(id)))
    ns:Changed()
end

for _, event in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL" }) do
    -- (The NPC's dialog fills in a moment after the event.)
    ns:On(event, function() C_Timer.After(0.2, function() CheckGiver(event) end) end)
end
