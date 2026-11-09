local _, ns = ...

-- Questie Auto Track: Questie's quest icons on the world map and minimap only for the quests you're
-- tracking. It drives Questie's own option for that ("Hide icons of untracked quests",
-- Questie.db.profile.hideUntrackedQuestsMapIcons) and redraws its icons, the same as switching it
-- in Questie's settings; nothing in Questie's files changes.
--
-- db.questieAutoTrack: nil until you choose (the setup wizard asks, Setup.lua), and while it's nil
-- Questie's own setting is left as it is. true: only tracked quests' icons. false: every quest's.
local QI = {}
ns.QuestieIcons = QI

local K = ns.QuestieKit

local function Profile()
    return type(Questie) == "table" and type(Questie.db) == "table" and type(Questie.db.profile) == "table" and Questie.db.profile or nil
end

-- Whether Questie is loaded (the wizard asks only then).
function QI:Available() return Profile() ~= nil end

-- Questie's icon redraw (QuestieQuest:HideQuestIcons / ShowQuestIcons) only runs inside a coroutine
-- (it asserts one, and yields every few quests): run it in one to the end. Called outside one, as
-- it was, it failed straight away and the icons stayed as they were.
local function Redraw(hide)
    local quest = K and K.Mod and K.Mod("QuestieQuest")
    local fn = quest and (hide and quest.HideQuestIcons or quest.ShowQuestIcons)
    if type(fn) ~= "function" then return false end
    local co = coroutine.create(function() fn(quest) end)
    for _ = 1, 10000 do
        local ok, err = coroutine.resume(co)
        if not ok then
            if ns.db and ns.db.debug then ns:Print("Questie icon redraw: " .. tostring(err)) end
            return false
        end
        if coroutine.status(co) == "dead" then return true end
    end
    return false
end

-- Sets Questie's option to ours and redraws its icons (nothing while ours isn't chosen).
function QI:Apply()
    local want = ns.db and ns.db.questieAutoTrack
    local p = Profile()
    if want == nil or not p then return end
    want = want and true or false
    if (p.hideUntrackedQuestsMapIcons and true or false) ~= want then p.hideUntrackedQuestsMapIcons = want end
    Redraw(want)
end

-- /whud questie: what Questie counts as tracked (only those keep their icons while the option is on),
-- and its other settings that decide which icons show.
function QI:Report()
    local p = Profile()
    if not p then return ns:Print("Questie isn't loaded.") end
    local quest = K.Mod and K.Mod("QuestieQuest")
    local log = K.QuestLog and K.QuestLog() or {}
    local tracked, untracked = {}, {}
    for id, q in pairs(log) do
        local name = type(q) == "table" and q.name or tostring(id)
        local ok, on = pcall(quest and quest.IsQuestTracked or function() return nil end, quest, id)
        if ok and on then tracked[#tracked + 1] = name else untracked[#untracked + 1] = name end
    end
    table.sort(tracked); table.sort(untracked)
    local function YN(v) return v and "on" or "off" end
    local char = Questie.db.char or {}
    ns:Print(("Questie: hide untracked quests' icons %s (ours: %s), auto-track new quests %s, Questie tracker %s, faded icon alpha %s, focus %s")
        :format(YN(p.hideUntrackedQuestsMapIcons), tostring(ns.db.questieAutoTrack), YN(p.autoTrackQuests),
            YN(p.trackerEnabled), tostring(p.iconFadeLevel), tostring(char.TrackerFocus)))
    ns:Print(("Tracked (%d): %s"):format(#tracked, table.concat(tracked, ", ")))
    ns:Print(("Not tracked (%d): %s"):format(#untracked, table.concat(untracked, ", ")))
end

-- At login, once Questie is up (it loads its settings and icons a little after).
ns:On("PLAYER_LOGIN", function()
    if K and K.OnReady then K.OnReady(function() QI:Apply() end) else C_Timer.After(5, function() QI:Apply() end) end
end)
