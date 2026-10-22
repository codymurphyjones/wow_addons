local _, ns = ...

-- Questie, from the outside (addons/shared, copied into each addon's Shared\ folder by the build).
-- Questie is optional and third party: every touch is guarded, so without it (or with a version
-- that moved something) these answer nil / false and the addon carries on.
--
-- On ns.QuestieKit, not ns.Questie: Waypoint and WallyHUD already have their own ns.Questie
-- modules (built on this kit).
--
-- Names checked against Questie's own code: QuestieLoader:ImportModule(name) (it hands back an
-- empty table for a module it doesn't have: check for the function you need), modules
-- "QuestieDB" (QueryQuestSingle(id, field) and IsDoable(id) are plain functions, GetQuest(id)),
-- "QuestiePlayer" (currentQuestlog), "QuestieTracker" (:Update(), IsTrackedByQuestie(id),
-- :UntrackQuestId(id)), "TrackerUtils" (:FocusQuest(id), :FocusObjective(id, index), :UnFocus()),
-- Questie.db.char.TrackerFocus (a quest ID, or "questId objectiveIndex"), Questie.db.char.complete
-- (questId -> true), Questie.API.RegisterOnReady(fn) / Questie.API.isReady.
local K = {}
ns.QuestieKit = K

local mods = {}

-- pcall that returns the first two results, or nil on an error (or for a non-function).
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end
K.Call = Call

-- Whether Questie's loader is there.
function K.Loaded()
    return type(QuestieLoader) == "table" and type(QuestieLoader.ImportModule) == "function"
end

local function CharDB()
    return type(Questie) == "table" and type(Questie.db) == "table" and type(Questie.db.char) == "table" and Questie.db.char or nil
end
K.CharDB = CharDB

-- Whether Questie is loaded and has its character data (and, on versions that say, is ready).
function K.Ready()
    if not (K.Loaded() and CharDB()) then return false end
    local api = Questie.API
    if type(api) == "table" and api.isReady ~= nil then return api.isReady and true or false end
    return true
end

-- A Questie module, or nil (no Questie). Cached; a module that fails to import stays nil.
function K.Mod(name)
    if not K.Loaded() then return nil end
    if mods[name] == nil then
        local ok, m = pcall(QuestieLoader.ImportModule, QuestieLoader, name)
        mods[name] = ok and type(m) == "table" and m or false
    end
    return mods[name] or nil
end

-- Forget cached modules.
function K.Invalidate() wipe(mods) end

-- Runs fn once Questie is ready (now, if it already is). true when Questie took the callback.
-- Call it at PLAYER_LOGIN or later: Questie defines its API while loading.
function K.OnReady(fn)
    local api = type(Questie) == "table" and Questie.API
    if not (type(api) == "table" and type(api.RegisterOnReady) == "function" and K.Loaded()) then return false end
    return (pcall(api.RegisterOnReady, fn))
end

-- hooksecurefunc on a Questie module's method, guarded. true when hooked.
function K.Hook(modName, method, fn)
    local m = K.Mod(modName)
    if not (m and type(m[method]) == "function" and hooksecurefunc) then return false end
    return (pcall(hooksecurefunc, m, method, fn))
end

-- ---------------------------------------------------------------------------
-- The tracker's focus
-- ---------------------------------------------------------------------------

-- Questie's focus: questId and the objective index (a number; nil for a whole-quest focus), or nil.
-- Questie saves it as a quest ID, or as the text "questId objectiveIndex".
function K.Focus()
    local db = CharDB()
    local f = db and db.TrackerFocus
    if type(f) == "number" then return f end
    if type(f) == "string" then
        local id = tonumber(f:match("^(%d+)"))
        local obj = f:match("^%d+%s+(%S+)")
        return id, obj and (tonumber(obj) or obj) or nil
    end
end

-- Just the quest.
function K.FocusedQuest() return (K.Focus()) end

-- Redraws Questie's tracker.
function K.UpdateTracker()
    local QT = K.Mod("QuestieTracker")
    if QT and type(QT.Update) == "function" then return (pcall(QT.Update, QT)) end
    return false
end

-- Focuses a quest (or one of its objectives) at the top of Questie's tracker. true when the focus
-- changed (false: no Questie, or it's focused already).
--   opts.tracker   ask Questie (TrackerUtils:FocusQuest / FocusObjective, which also fade the other
--                  quests' map icons, and may refuse); falls back to writing the field
--   opts.noUpdate  don't redraw the tracker
-- Without opts.tracker the saved field is written and the tracker redrawn (FieldGuide's way).
function K.SetFocus(id, objective, opts)
    local db = CharDB()
    if not (db and type(id) == "number") then return false end
    opts = opts or {}
    local want = objective and (tostring(id) .. " " .. tostring(objective)) or id
    if db.TrackerFocus == want then return false end
    local done = false
    if opts.tracker then
        local TU = K.Mod("TrackerUtils")
        if objective then
            done = TU and Call(TU.FocusObjective, TU, id, objective) and true or false
        else
            done = TU and Call(TU.FocusQuest, TU, id) and true or false
        end
    end
    if not done then db.TrackerFocus = want end
    if not opts.noUpdate then K.UpdateTracker() end
    return true
end

-- Clears the focus (Questie's UnFocus when it has one, which restores the icons).
function K.ClearFocus(opts)
    local db = CharDB()
    if not (db and db.TrackerFocus) then return false end
    local TU = K.Mod("TrackerUtils")
    if not (TU and type(TU.UnFocus) == "function" and pcall(TU.UnFocus, TU)) then db.TrackerFocus = nil end
    if not (opts and opts.noUpdate) then K.UpdateTracker() end
    return true
end

-- ---------------------------------------------------------------------------
-- Quests
-- ---------------------------------------------------------------------------

-- Questie's record of finished quests (questId -> true), or nil. Live: it updates as you play.
function K.Completed()
    local db = CharDB()
    return db and type(db.complete) == "table" and db.complete or nil
end

-- Questie's record for one quest: true / false, or nil without Questie.
function K.IsComplete(id)
    local c = K.Completed()
    if not c then return nil end
    return c[id] and true or false
end

-- Finished: Questie's record, else the game's (C_QuestLog.IsQuestFlaggedCompleted, else the old
-- IsQuestFlaggedCompleted). gameOnly: the game's alone (SpyglassPluginQuests).
function K.IsDone(id, gameOnly)
    if not gameOnly and K.IsComplete(id) then return true end
    local fn = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted
    return Call(fn, id) and true or false
end

-- Every finished quest, the game's (C_QuestLog.GetAllCompletedQuestIDs) and Questie's, as a set
-- (into `out` when given: it's added to, not wiped).
function K.CompletedIDs(out)
    out = out or {}
    local ids = C_QuestLog and Call(C_QuestLog.GetAllCompletedQuestIDs)
    if type(ids) == "table" then
        for _, id in ipairs(ids) do out[id] = true end
    end
    for id, done in pairs(K.Completed() or {}) do
        if done then out[id] = true end
    end
    return out
end

-- One field of a quest in Questie's database ("name", "exclusiveTo", "breadcrumbForQuestId"...),
-- or nil.
function K.Query(id, field)
    local QDB = K.Mod("QuestieDB")
    if not (QDB and QDB.QueryQuestSingle) then return nil end
    return (Call(QDB.QueryQuestSingle, id, field))
end

-- Questie's verdict on whether you could take a quest at all (class, race, reputation, quests that
-- rule each other out; not level). `unknown` (default nil) when Questie can't tell. FieldGuide
-- treats unknown as doable: K.IsDoable(id, true).
function K.IsDoable(id, unknown)
    local QDB = K.Mod("QuestieDB")
    if not (QDB and QDB.IsDoable) then return unknown end
    local ok, doable = pcall(QDB.IsDoable, id)
    if not ok then return unknown end
    return doable and true or false
end

-- Questie's quest object, or nil.
function K.Quest(id)
    local QDB = K.Mod("QuestieDB")
    return QDB and (Call(QDB.GetQuest, id)) or nil
end

-- The quests in your log as Questie knows them: questId -> quest object (QuestiePlayer.currentQuestlog,
-- Questie's own table: read it, don't change it), or nil.
function K.QuestLog()
    local QP = K.Mod("QuestiePlayer")
    return QP and type(QP.currentQuestlog) == "table" and QP.currentQuestlog or nil
end

-- Whether Questie's tracker shows a quest.
function K.IsTracked(id)
    local QT = K.Mod("QuestieTracker")
    return QT and Call(QT.IsTrackedByQuestie, id) and true or false
end

-- The quests Questie's tracker shows: questId -> quest object.
function K.Tracked()
    local out = {}
    local log, QT = K.QuestLog(), K.Mod("QuestieTracker")
    if not (log and QT and QT.IsTrackedByQuestie) then return out end
    for id, quest in pairs(log) do
        if type(quest) == "table" and Call(QT.IsTrackedByQuestie, id) then out[id] = quest end
    end
    return out
end

-- Takes a quest off Questie's tracker. true when Questie did it.
function K.Untrack(id)
    local QT = K.Mod("QuestieTracker")
    if not (QT and type(QT.UntrackQuestId) == "function") then return false end
    return (pcall(QT.UntrackQuestId, QT, id))
end
