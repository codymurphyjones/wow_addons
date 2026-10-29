local _, ns = ...
local C = ns.Compat

-- The default target: your Questie quests. Quests you tracked yourself come first, the most
-- recently tracked first; then Questie's focused quest; then the other tracked quests, the most
-- recently tracked first, nearest as the tie-break. The pick holds until you track or untrack
-- something, change the focus, or the quest moves on (an objective done, ready to turn in);
-- walking never re-picks.
--
-- Tracking history (ns.char.tracking): every quest that becomes tracked is recorded with when,
-- and by whom. "user" only when you did it by hand: a click (or shift-click) in a quest window,
-- the quest log, the map's quest list, or Questie's tracker and its menu. Everything else (Questie
-- tracking quests as you accept them, any addon) counts as an addon's. Addons track and
-- untrack through TrackQuest/UntrackQuest: never a quest you tracked, and never again one you
-- untracked yourself while it's still in your log.
-- Questie is optional. Its modules are used through QuestieLoader, every touch guarded: without
-- Questie (or with a version that moved something), the quest target is simply off, tracking
-- requests from addons are refused, and everything else in Waypoint works as usual.
local Q = {}
ns.Questie = Q

local MAX_POINTS = 150
local ARRIVE = 30

local K = ns.QuestieKit -- Questie from the outside (shared Questie.lua)
local ready = false
local skipped = {}       -- questId -> true: skipped from the arrow this session
local current            -- { id, obj } of the pick
local signature

-- Tracking history -------------------------------------------------------------------------------

local known              -- the tracked set at the last look (nil before the first)
local pendingTrack = {}  -- questID -> { owner, t }: an addon asked to track it (through Waypoint)
local pendingUntrack = {} -- questID -> GetTime(): an addon asked to untrack it (through Waypoint)
local manualTrack = {}   -- questID -> GetTime(): you tracked it by hand
local manualUntrack = {} -- questID -> GetTime(): you untracked it by hand
local accepted = {}      -- questID -> GetTime() you accepted it (tracking it then is Questie's doing, not yours)
local SETTLE = 5         -- seconds a request explains a tracking change

-- Whether a tracking call comes from your hand: the mouse is over a quest window, the quest log,
-- the world map's quest list, Questie's tracker, or a menu (Questie's right-click menu).
local HAND = { "Quest", "Questie", "WorldMap", "Objective", "Watch", "DropDown", "Menu" }
local function ByHand()
    local focus
    if GetMouseFoci then
        local list = GetMouseFoci()
        focus = type(list) == "table" and list[1] or nil
    elseif GetMouseFocus then
        focus = GetMouseFocus()
    end
    for _ = 1, 12 do
        if not (focus and focus.GetName) then return false end
        local name = focus:GetName()
        if type(name) == "string" then
            for _, word in ipairs(HAND) do
                if name:find(word, 1, true) then return true end
            end
        end
        focus = focus.GetParent and focus:GetParent() or nil
    end
    return false
end

local function NoteTrack(id)
    local asked = pendingTrack[id]
    if type(id) ~= "number" or (asked and GetTime() - asked.t < SETTLE) then return end
    if accepted[id] and GetTime() - accepted[id] < 3 then return end -- the Accept button, not a track click
    if ByHand() then manualTrack[id] = GetTime() end
end

local function NoteUntrack(id)
    if type(id) == "number" and not (pendingUntrack[id] and GetTime() - pendingUntrack[id] < SETTLE) and ByHand() then
        manualUntrack[id] = GetTime()
    end
end

local function InLog(id)
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        local i = C.Call(C_QuestLog.GetLogIndexForQuestID, id)
        return i ~= nil and i > 0
    end
    return GetQuestLogIndexByID and (GetQuestLogIndexByID(id) or 0) > 0
end

local function Recent(t) return t ~= nil and GetTime() - t < SETTLE end

-- Compares the tracked set with the last look and records what changed, and who did it.
local function Reconcile(tracked)
    local hist, untracked = ns.char.tracking, ns.char.untracked
    if known then
        for id in pairs(tracked) do
            if not known[id] then
                local asked = pendingTrack[id]
                local by = (asked and Recent(asked.t) and asked.owner)
                    or (Recent(manualTrack[id]) and not (accepted[id] and math.abs(accepted[id] - manualTrack[id]) < 3)
                        and "user")
                    or "addon"
                hist[id] = { by = by, at = ns:NextSeq() }
                if by == "user" then untracked[id] = nil end
            end
        end
        for id in pairs(known) do
            if not tracked[id] then
                if Recent(manualUntrack[id]) and InLog(id) then untracked[id] = true end
                hist[id] = nil
            end
        end
    else
        -- First look: what was tracked before keeps its record; anything else is an addon's.
        for id in pairs(tracked) do
            if not hist[id] then hist[id] = { by = "addon", at = 0 } end
        end
    end
    for id in pairs(hist) do
        if not tracked[id] then hist[id] = nil end
    end
    for id in pairs(untracked) do
        if not InLog(id) then untracked[id] = nil end
    end
    known = {}
    for id in pairs(tracked) do known[id] = true end
end

local function ByUser(id)
    local h = ns.char.tracking[id]
    return h and h.by == "user" or false
end

local function TrackedAt(id)
    local h = ns.char.tracking[id]
    return h and h.at or 0
end

-- A Questie module (cached). No Questie (it's optional): no modules, and everything built on
-- them stays off.
local Mod = K.Mod

local function Available()
    return ready and K.Loaded() and K.CharDB() ~= nil
end

-- Tracked quests: questId -> Questie's quest object.
local Tracked = K.Tracked

-- Questie's focus: questId, objective index (or nil).
local Focus = K.Focus

-- Whether Questie is loaded and ready (the quest target and quest tracking need it).
function Q:Available() return Available() end

-- Tracked quests: questId -> Questie's quest object (exposed for TrackQuest and friends).
function Q:Tracked() return Tracked() end

local function Signature(tracked)
    local ids = {}
    for id in pairs(tracked) do ids[#ids + 1] = id end
    table.sort(ids)
    local fid, fobj = Focus()
    return tostring(fid) .. ":" .. tostring(fobj) .. "|" .. table.concat(ids, ",")
end

-- Every spawn in Questie's { [areaId] = { { x, y } } } as points (0-1 on a uiMapID).
local function AddSpawns(points, spawns, label)
    local ZoneDB = Mod("ZoneDB")
    if not (ZoneDB and type(spawns) == "table") then return end
    local function Push(areaId, x, y)
        if #points >= MAX_POINTS then return end
        local mapID = C.Call(ZoneDB.GetUiMapIdByAreaId, ZoneDB, areaId)
        if mapID and x and y then points[#points + 1] = { mapID = mapID, x = x / 100, y = y / 100, label = label } end
    end
    for areaId, list in pairs(spawns) do
        for _, s in pairs(list) do
            if s[1] == -1 or s[2] == -1 then
                for _, loc in pairs(C.Call(ZoneDB.GetDungeonLocation, ZoneDB, areaId) or {}) do Push(loc[1], loc[2], loc[3]) end
            else
                Push(areaId, s[1], s[2])
            end
        end
    end
end

local function IsComplete(quest)
    local complete = C.Call(quest.IsComplete, quest)
    return complete == 1 or (complete ~= -1 and quest.isComplete)
end

local function Unfinished(o) return o and ((not o.Needed) or o.Needed ~= o.Collected) and o.spawnList end

-- The target for one quest: its turn-in when complete, else an unfinished objective (prefer is
-- the objective to keep if it's still unfinished). nil when Questie knows no place for it.
local function Build(id, quest, prefer)
    local name = quest.name or ("Quest " .. id)
    local points = {}
    if IsComplete(quest) then
        local QDB = Mod("QuestieDB")
        local finisher, who = quest.Finisher or {}, nil
        for _, npcId in pairs(finisher.NPC or {}) do
            local npc = QDB and C.Call(QDB.GetNPC, QDB, npcId)
            if npc and npc.spawns then AddSpawns(points, npc.spawns, npc.name); who = who or npc.name end
        end
        for _, objId in pairs(finisher.GameObject or {}) do
            local obj = QDB and C.Call(QDB.GetObject, QDB, objId)
            if obj and obj.spawns then AddSpawns(points, obj.spawns, obj.name); who = who or obj.name end
        end
        if #points == 0 then return nil end
        return { key = id .. ":done", questID = id, obj = "done", title = "Turn in: " .. name,
            subtitle = who and ("to " .. who) or nil, targetName = who, points = points, arrive = ARRIVE, byUser = ByUser(id) }
    end

    -- Unfinished objectives, numbered like Questie's focus ("s1".. for special ones).
    local objectives = {}
    for i, o in pairs(quest.Objectives or {}) do
        if Unfinished(o) then objectives[#objectives + 1] = { idx = i, o = o } end
    end
    for i, o in pairs(quest.SpecialObjectives or {}) do
        if Unfinished(o) then objectives[#objectives + 1] = { idx = "s" .. i, o = o } end
    end
    local chosen
    for _, ob in ipairs(objectives) do
        if ob.idx == prefer then chosen = ob end
    end
    if not chosen then
        local DU, bestD = Mod("DistanceUtils"), nil
        for _, ob in ipairs(objectives) do
            local d
            if DU then d = select(4, C.Call(DU.GetNearestObjective, ob.o.spawnList)) end
            if d and (not bestD or d < bestD) then chosen, bestD = ob, d end
        end
        chosen = chosen or objectives[1]
    end
    if not chosen then return nil end
    for _, spawn in pairs(chosen.o.spawnList) do
        if type(spawn) == "table" then AddSpawns(points, spawn.Spawns, spawn.Name) end
    end
    if #points == 0 then return nil end
    local o = chosen.o
    local what = o.Description or (points[1] and points[1].label) or "Objective"
    if o.Needed and o.Collected then what = ("%s %d/%d"):format(what, o.Collected, o.Needed) end
    return { key = id .. ":" .. tostring(chosen.idx), questID = id, obj = chosen.idx, title = name,
        subtitle = what, points = points, arrive = ARRIVE, byUser = ByUser(id) }
end

-- Picks the quest to point at, from scratch.
function Q:Select()
    if not (ns.db and ns.db.quests and Available()) then
        current = nil
        ns.Targets:SetQuestie(nil)
        return
    end
    local tracked = Tracked()
    Reconcile(tracked)
    signature = Signature(tracked)
    local DU = Mod("DistanceUtils")
    local order = {}
    for id, quest in pairs(tracked) do
        if not skipped[id] then
            local d
            if DU then d = select(4, C.Call(DU.GetNearestSpawnForQuest, quest)) end
            order[#order + 1] = { id = id, quest = quest, d = d or math.huge, user = ByUser(id), at = TrackedAt(id) }
        end
    end
    table.sort(order, function(a, b)
        if a.user ~= b.user then return a.user end
        if a.at ~= b.at then return a.at > b.at end
        return a.d < b.d
    end)
    local e
    -- Yours first (the most recently tracked); then Questie's focus; then the rest.
    for _, c in ipairs(order) do
        if not c.user then break end
        e = Build(c.id, c.quest)
        if e then break end
    end
    local fid, fobj = Focus()
    if not e and fid and tracked[fid] and not skipped[fid] then e = Build(fid, tracked[fid], fobj) end
    if not e then
        for _, c in ipairs(order) do
            e = Build(c.id, c.quest)
            if e then break end
        end
        -- Skipped everything: start over.
        if not e and next(skipped) then
            wipe(skipped)
            return self:Select()
        end
    end
    current = e and { id = e.questID, obj = e.obj } or nil
    ns.Targets:SetQuestie(e)
end

-- The picked quest changed (an objective done, ready to turn in): rebuild it, keeping its objective.
function Q:Rebuild()
    if not current then return self:Select() end
    local quest = Tracked()[current.id]
    local e = quest and Build(current.id, quest, current.obj)
    if not e then return self:Select() end
    current.obj = e.obj
    ns.Targets:SetQuestie(e)
end

-- An addon tracks a quest (it's recorded as that addon's). Not one you untracked yourself.
function Q:Track(owner, id)
    if not (Available() and InLog(id)) or ns.char.untracked[id] then return false end
    local tracked = Tracked()
    if tracked[id] then
        local h = ns.char.tracking[id]
        if not h then ns.char.tracking[id] = { by = owner, at = ns:NextSeq() } end
        return true
    end
    pendingTrack[id] = { owner = owner, t = GetTime() }
    if C_QuestLog and C_QuestLog.AddQuestWatch then
        C.Call(C_QuestLog.AddQuestWatch, id)
    elseif AddQuestWatch and GetQuestLogIndexByID then
        C.Call(AddQuestWatch, GetQuestLogIndexByID(id))
    end
    return true
end

-- An addon untracks a quest. Never one you tracked yourself.
function Q:Untrack(owner, id)
    if not Available() or ByUser(id) then return false end
    if not Tracked()[id] then return true end
    pendingUntrack[id] = GetTime()
    local QT = Mod("QuestieTracker")
    if QT and QT.UntrackQuestId then
        K.Untrack(id)
    elseif C_QuestLog and C_QuestLog.RemoveQuestWatch then
        C.Call(C_QuestLog.RemoveQuestWatch, id)
    end
    return true
end

-- Who tracked a quest: "user", an addon's name, or nil (not tracked).
function Q:TrackedBy(id)
    local h = ns.char.tracking[id]
    return h and h.by or nil
end

-- Arrow right-click on a quest: point at another one.
function Q:Skip()
    if not current then return end
    skipped[current.id] = true
    ns:Print("Skipping that quest for now.")
    self:Select()
end

local pendingCheck
local function CheckTracking()
    if pendingCheck or not Available() then return end
    pendingCheck = true
    C_Timer.After(0.3, function()
        pendingCheck = false
        local tracked = Tracked()
        Reconcile(tracked)
        if Signature(tracked) ~= signature then Q:Select() end
    end)
end

local function OnQuestUpdate(questId, _, reason)
    local REASON = Questie and Questie.API and Questie.API.Enums and Questie.API.Enums.QuestUpdateTriggerReason or {}
    if not current then return CheckTracking() end
    if questId == current.id then
        if reason == (REASON.QUEST_TURNED_IN or 3) or reason == (REASON.QUEST_ABANDONED or 4) then
            C_Timer.After(0.3, function() Q:Select() end)
        else
            C_Timer.After(0.1, function() Q:Rebuild() end)
        end
    else
        CheckTracking()
    end
end

local function Start()
    ready = true
    K.Hook("QuestieTracker", "Update", CheckTracking)
    K.Hook("QuestieTracker", "UntrackQuestId", function(_, id) NoteUntrack(id) end)
    if Questie and Questie.API and Questie.API.RegisterForQuestUpdates then pcall(Questie.API.RegisterForQuestUpdates, OnQuestUpdate) end
    Q:Select()
end

ns:On("PLAYER_LOGIN", function() K.OnReady(Start) end)
ns:On("QUEST_WATCH_LIST_CHANGED", CheckTracking)
ns:On("QUEST_ACCEPTED", function(a, b)
    local id = b or a -- (questLogIndex, questID) or (questID): the quest ID is the last value
    if type(id) == "number" then accepted[id] = GetTime() end
end)

-- Watch the tracking calls themselves, to tell your clicks from addons'.
ns:On("PLAYER_LOGIN", function()
    if C_QuestLog and C_QuestLog.AddQuestWatch then pcall(hooksecurefunc, C_QuestLog, "AddQuestWatch", NoteTrack) end
    if C_QuestLog and C_QuestLog.RemoveQuestWatch then pcall(hooksecurefunc, C_QuestLog, "RemoveQuestWatch", NoteUntrack) end
end)
-- Positions are known once you're in the world: the nearest quest may be a different one.
ns:On("PLAYER_ENTERING_WORLD", function()
    if ready then C_Timer.After(1, function() Q:Select() end) end
end)
