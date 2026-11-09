local _, ns = ...

-- Party on quest cards: when Questie shows a quest's card (a quest link clicked or hovered in chat,
-- ItemRefTooltip / GameTooltip, built by Questie's QuestieLink:CreateQuestTooltip), a "Party" part
-- is added under it with each group member's state for that quest:
--
--   On it / Ready to turn in   it's in their log (and every objective is done)
--   Done                       they've handed it in
--   Needs <quest>              a quest it needs first isn't done
--   Can pick it up             they could take it now
--   Level N                    they're below the level it needs
--   Can't take it              class, race, a quest that rules it out...
--
-- Each member running WallyHUD answers for themselves (their log, their finished quests, Questie's
-- verdict on what they could take), over a private addon channel (shared\GroupComm.lua). For one
-- without it, what Questie's own party sharing says (QuestieComms.remoteQuestLogs: only quests in
-- their log), else "no answer". Nothing in Questie's files changes: the part is added from a
-- hooksecurefunc after Questie's lines, and the card is drawn again when answers come in.
-- Off with db.partyQuests.
local PQ = {}
ns.PartyQuests = PQ

local K = ns.QuestieKit
local U = ns.Units

local ASK_AGAIN = 15  -- seconds before the same quest is asked about again
local FRESH = 300     -- seconds an answer is used for
local REDRAW = 0.3    -- answers within this of each other draw the card once

local answers = {}    -- questID -> { [canon name] = { code, extra, at } }
local asked = {}      -- questID -> GetTime() it was last asked about
local open = {}       -- tooltip -> { id, link }: the cards showing a quest now
local drawing = false -- inside our own redraw (the hook runs again: don't ask again)

local comm = ns.NewGroupComm("WallyHUDQ", { pace = 0.2, raids = true, normalize = U.Canon, isMe = U.IsMe })

local function Now() return GetTime and GetTime() or 0 end
local function Enabled() return ns.db and ns.db.partyQuests ~= false end

-- ---------------------------------------------------------------------------
-- Your own state for a quest (what you answer)
-- ---------------------------------------------------------------------------

local function InLog(id)
    local log = K.QuestLog()
    if log and log[id] then return true end
    local fn = C_QuestLog and C_QuestLog.IsOnQuest
    if fn then
        local ok, on = pcall(fn, id)
        if ok and on == true then return true end
    end
    return false
end

local function Ready(id)
    for _, q in ipairs(K.ReadyQuests()) do
        if q == id then return true end
    end
    return false
end

-- The quests it needs first that you haven't done: preQuestSingle (any one of them) is missing only
-- when none is done; preQuestGroup (all of them) lists each one not done.
local function MissingPre(id)
    local out = {}
    local single = K.Query(id, "preQuestSingle")
    if type(single) == "table" and #single > 0 then
        local any = false
        for _, p in ipairs(single) do if K.IsDone(p) then any = true; break end end
        if not any then out[#out + 1] = single[1] end
    end
    local group = K.Query(id, "preQuestGroup")
    if type(group) == "table" then
        for _, p in ipairs(group) do if not K.IsDone(p) then out[#out + 1] = p end end
    end
    return out
end

-- Your state: code, extra. Codes: L on it, R ready to turn in, D done, P needs (extra: quest IDs,
-- comma separated), A can pick it up, V level too low (extra: the level), X can't take it.
local function MyState(id)
    if InLog(id) then return Ready(id) and "R" or "L", "" end
    if K.IsDone(id) then return "D", "" end
    local QDB = K.Mod("QuestieDB")
    local states = QDB and QDB.DoableStates
    if QDB and QDB.IsDoableVerbose and type(states) == "table" then
        local ok, _, _, code = pcall(QDB.IsDoableVerbose, id, false, true, true)
        if ok and code ~= nil then
            if code == states.AVAILABLE then return "A", "" end
            if code == states.NO_PREQUESTSINGLE or code == states.NO_PREQUESTGROUP then
                return "P", table.concat(MissingPre(id), ",")
            end
            if code == states.LEVEL_TOO_LOW then return "V", tostring(K.Query(id, "requiredLevel") or "") end
            return "X", ""
        end
    end
    -- Without the verbose verdict: the prerequisites, then the plain one (no level check there).
    local missing = MissingPre(id)
    if #missing > 0 then return "P", table.concat(missing, ",") end
    local doable = K.IsDoable(id, nil)
    if doable == true then
        local need = tonumber(K.Query(id, "requiredLevel"))
        local level = UnitLevel and UnitLevel("player")
        if need and type(level) == "number" and level < need then return "V", tostring(need) end
        return "A", ""
    end
    if doable == false then return "X", "" end
    return nil
end

-- ---------------------------------------------------------------------------
-- The channel: Q = which state are you in for this quest; S = mine
-- ---------------------------------------------------------------------------

comm:On("Q", function(payload)
    if not Enabled() then return end
    local id = tonumber(payload)
    if not id then return end
    local code, extra = MyState(id)
    if code then comm:Send("S", ("%d|%s|%s"):format(id, code, extra or "")) end
end)

local Redraw -- below
comm:On("S", function(payload, sender)
    if not sender then return end
    local id, code, extra = payload:match("^(%d+)|(%a)|(.*)$")
    id = tonumber(id)
    if not id then return end
    answers[id] = answers[id] or {}
    answers[id][sender] = { code = code, extra = extra, at = Now() }
    Redraw(id)
end)

local function Ask(id)
    if drawing then return end
    local last = asked[id]
    if last and Now() - last < ASK_AGAIN then return end
    if comm:Send("Q", tostring(id)) then asked[id] = Now() end
end

-- ---------------------------------------------------------------------------
-- Questie's party sharing, for members without WallyHUD
-- ---------------------------------------------------------------------------

-- "R" (every objective done), "L" (in their log) or nil, from QuestieComms.remoteQuestLogs.
local function Shared(id, name)
    local QC = K.Mod("QuestieComms")
    local logs = QC and type(QC.remoteQuestLogs) == "table" and QC.remoteQuestLogs[id]
    if type(logs) ~= "table" then return nil end
    for who, objectives in pairs(logs) do
        if U.SameName(who, name) then
            if type(objectives) ~= "table" then return "L" end
            local any, done = false, true
            for _, o in pairs(objectives) do
                if type(o) == "table" then
                    any = true
                    if not (o.finished or (o.fulfilled and o.required and o.fulfilled >= o.required)) then done = false end
                end
            end
            return (any and done) and "R" or "L"
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- The card
-- ---------------------------------------------------------------------------

local function QuestName(id)
    local name = K.Query(id, "name")
    return type(name) == "string" and name or ("quest " .. id)
end

local GREEN, GOLD, GREY, RED, BLUE = "|cff40c040", "|cffffd100", "|cff8a8a8a", "|cffff5050", "|cff6fb7ff"

local function Line(code, extra)
    if code == "L" then return GOLD .. "On it|r" end
    if code == "R" then return GREEN .. "Ready to turn in|r" end
    if code == "D" then return GREY .. "Done|r" end
    if code == "A" then return BLUE .. "Can pick it up|r" end
    if code == "V" then return RED .. ((extra and extra ~= "") and ("Level " .. extra) or "Level too low") .. "|r" end
    if code == "P" then
        local names = {}
        for p in tostring(extra or ""):gmatch("%d+") do names[#names + 1] = QuestName(tonumber(p)) end
        return RED .. (#names > 0 and ("Needs " .. table.concat(names, ", ")) or "Needs an earlier quest") .. "|r"
    end
    if code == "X" then return RED .. "Can't take it|r" end
    return GREY .. "No answer|r"
end

-- The group, not you: { { name = "Given Family", display = "Given" }, ... } (classes coloured).
local function Members()
    local out = {}
    for _, unit in ipairs(U.GroupUnits()) do
        local key = U.UnitFull(unit)
        if key then
            local _, class = UnitClass(unit)
            local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
            local shown = U.Display(key)
            if color and color.colorStr then shown = "|c" .. color.colorStr .. shown .. "|r" end
            out[#out + 1] = { name = key, shown = shown }
        end
    end
    return out
end

local function AddParty(tooltip, id)
    local members = Members()
    if #members == 0 then return end
    tooltip:AddLine(" ")
    tooltip:AddLine("Party", 1, 0.82, 0)
    local mine = answers[id] or {}
    for _, m in ipairs(members) do
        local a
        for who, row in pairs(mine) do
            if U.SameName(who, m.name) and Now() - row.at < FRESH then a = row; break end
        end
        local code, extra = a and a.code, a and a.extra
        if not code then code = Shared(id, m.name) end
        tooltip:AddDoubleLine(m.shown, Line(code, extra))
    end
end

-- Draws an open card for this quest again (answers came in).
local pending = {}
function Redraw(id)
    if pending[id] then return end
    pending[id] = true
    C_Timer.After(REDRAW, function()
        pending[id] = nil
        local QL = K.Mod("QuestieLink")
        if not (QL and QL.CreateQuestTooltip) then return end
        for tooltip, o in pairs(open) do
            if o.id == id and tooltip:IsShown() then
                drawing = true
                local ok = pcall(function()
                    tooltip:ClearLines()
                    QL:CreateQuestTooltip(o.link, tooltip)
                    tooltip:Show()
                end)
                drawing = false
                if not ok then open[tooltip] = nil end
            end
        end
    end)
end

local function OnCard(_, link, tooltip)
    if not (Enabled() and type(link) == "string" and tooltip and tooltip.AddLine) then return end
    local id = tonumber(link:match("questie:(%d+)") or link:match("quest:(%d+)"))
    if not id or #U.GroupUnits() == 0 then
        if tooltip then open[tooltip] = nil end
        return
    end
    open[tooltip] = { id = id, link = link }
    Ask(id)
    AddParty(tooltip, id)
end

function PQ:Setup()
    if self.hooked then return end
    self.hooked = K.Hook("QuestieLink", "CreateQuestTooltip", OnCard)
end

ns:On("PLAYER_LOGIN", function()
    if not K.OnReady(function() PQ:Setup() end) then PQ:Setup() end
end)
ns:On("GROUP_ROSTER_UPDATE", function()
    if #U.GroupUnits() == 0 then wipe(answers); wipe(asked); comm:Reset() end
end)
