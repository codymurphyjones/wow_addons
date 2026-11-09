local _, ns = ...

-- The quest item macro: one account-wide macro ("FG Quest Item", General macros, shared by all your
-- characters) that uses the quest item you need now. Field Guide rewrites it as your bags, quest log
-- and current step change (never in combat: macros can't be changed then, so it waits).
--   click        the first item: the current step's, else a quest you're on, else any usable quest item
--   shift-click  the second, ctrl-click the third
-- Nothing to use: the macro says so in chat.
-- Made only when you say yes (the prompt the first time you carry a usable quest item, the button in
-- Options > AddOns > Field Guide, or /fg macro). Delete it in /macro and it stays gone until you
-- make it again.
local M = {}
ns.QuestMacro = M

M.NAME = "FG Quest Item"
local ICON = "INV_Misc_QuestionMark" -- with #showtooltip, the game shows the item's own icon
local CLASS_QUEST = 12
local MODS = { "", "[mod:shift] ", "[mod:ctrl] " }
local EMPTY = '#showtooltip\n/run print("Field Guide: no quest item to use right now.")'

local pending = false -- a rewrite waiting for combat to end

local function MaxAccount() return MAX_ACCOUNT_MACROS or 120 end

local function Index()
    local i = GetMacroIndexByName and GetMacroIndexByName(M.NAME) or 0
    return i and i > 0 and i <= MaxAccount() and i or nil
end

local function ItemSpell(id)
    local fn = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if not fn then return nil end
    local ok, spell = pcall(fn, id)
    return ok and spell or nil
end

local function ItemInfo(id)
    local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not fn then return nil end
    local name, _, _, _, _, _, _, _, _, _, _, classID = fn(id)
    return name, classID
end

-- Quests in your log: questID -> true.
local function LogQuests()
    local out = {}
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID and info.questID > 0 then out[info.questID] = true end
        end
    elseif GetNumQuestLogEntries and GetQuestLogTitle then
        for i = 1, GetNumQuestLogEntries() or 0 do
            local _, _, _, isHeader, _, _, _, id = GetQuestLogTitle(i)
            if not isHeader and id and id > 0 then out[id] = true end
        end
    end
    return out
end

-- The items a quest has you use: by name from the guide's objectives (k = "use"), and by ID from
-- Questie (the item it starts with and the items it needs to carry). names[name], ids[id] = rank.
local function NoteQuest(qid, rank, names, ids)
    local q = ns.Quests[qid]
    for _, g in ipairs(q and q.g or {}) do
        if g.k == "use" and g.n and not names[g.n] then names[g.n] = rank end
    end
    local K = ns.QuestieKit
    local QDB = K and K.Mod and K.Mod("QuestieDB")
    if QDB and QDB.QueryQuestSingle then
        local ok, src = pcall(QDB.QueryQuestSingle, qid, "sourceItemId")
        if ok and type(src) == "number" and src > 0 and not ids[src] then ids[src] = rank end
        local ok2, req = pcall(QDB.QueryQuestSingle, qid, "requiredSourceItems")
        if ok2 and type(req) == "table" then
            for _, id in pairs(req) do
                if type(id) == "number" and not ids[id] then ids[id] = rank end
            end
        end
    end
end

-- The usable quest items in your bags, best first: { itemID, ... }.
function M:Items()
    local names, ids = {}, {}
    -- 1: the current step's quest; 2: the quests of the steps after it; 3: the rest of your log.
    local E = ns.Engine
    local steps, cur = E and E.steps, E and E.current
    local log = LogQuests()
    if steps and cur and not ns.char.paused then
        for i = cur, #steps do
            local id = type(steps[i]) == "table" and steps[i][2]
            if type(id) == "number" and log[id] then NoteQuest(id, i == cur and 1 or 2, names, ids) end
        end
    end
    for id in pairs(log) do NoteQuest(id, 3, names, ids) end

    local found, seen = {}, {}
    local getID = C_Container and C_Container.GetContainerItemID or GetContainerItemID
    local numSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, (numSlots and numSlots(bag)) or 0 do
            local id = getID and getID(bag, slot)
            if id and not seen[id] then
                seen[id] = true
                local name, classID = ItemInfo(id)
                local rank = ids[id] or (name and names[name])
                if not rank and classID == CLASS_QUEST then rank = 4 end
                if rank and ItemSpell(id) then found[#found + 1] = { id = id, rank = rank, order = #found } end
            end
        end
    end
    table.sort(found, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.order < b.order
    end)
    local out = {}
    for i = 1, math.min(#found, #MODS) do out[i] = found[i].id end
    return out
end

function M:Body()
    local items = self:Items()
    if #items == 0 then return EMPTY end
    if #items == 1 then return "#showtooltip\n/use item:" .. items[1] end
    -- Modifiers first, the plain click last: "/use [mod:shift] item:B; [mod:ctrl] item:C; item:A".
    local parts = {}
    for i = 2, #items do parts[#parts + 1] = MODS[i] .. "item:" .. items[i] end
    parts[#parts + 1] = "item:" .. items[1]
    return "#showtooltip\n/use " .. table.concat(parts, "; ")
end

-- Rewrites the macro if it's there (and you made it). Out of combat; in combat, after it.
function M:Refresh()
    if not (ns.db and ns.db.questMacro) then return end
    if InCombatLockdown() then pending = true; return end
    local i = Index()
    if not i then
        -- Deleted in /macro: stay gone until it's made again.
        ns.db.questMacro = false
        return
    end
    local body = self:Body()
    local _, _, old = GetMacroInfo(i)
    if old ~= body then EditMacro(i, M.NAME, ICON, body) end
end

-- Makes the macro (or rewrites it) and puts it on your cursor, to drop on an action bar.
function M:Create()
    if InCombatLockdown() then return ns:Print("Macros can't be made in combat. Try again after the fight.") end
    if not (CreateMacro and EditMacro and GetNumMacros) then return ns:Print("This client can't make macros from addons.") end
    local i = Index()
    local body = self:Body()
    if i then
        EditMacro(i, M.NAME, ICON, body)
    else
        if (GetNumMacros() or 0) >= MaxAccount() then
            return ns:Print(("Your general macros are full (%d). Free one in /macro, then try again."):format(MaxAccount()))
        end
        local ok, idx = pcall(CreateMacro, M.NAME, ICON, body, nil)
        if not (ok and idx) then return ns:Print("The game didn't make the macro.") end
        i = idx
        ns:Print("Made the |cffffd100" .. M.NAME .. "|r macro (General macros, shared by all your characters). "
            .. "Drop it on an action bar: click uses the quest item you need now, shift-click the next, ctrl-click the third.")
    end
    ns.db.questMacro, ns.db.questMacroAsked = true, true
    if PickupMacro then PickupMacro(i) end
end

function M:State()
    local i = Index()
    if not i then return "Not made yet." end
    return ns.db.questMacro and ("Made (General macros, slot " .. i .. "), kept up to date.") or "Made, not kept up to date: Make it again."
end

-- ---------------------------------------------------------------------------
-- The prompt: once, the first time you carry a usable quest item
-- ---------------------------------------------------------------------------

StaticPopupDialogs["FIELDGUIDE_QUEST_MACRO"] = {
    text = "Field Guide can make a |cffffd100Quest Item|r macro for your action bar. Click it and it uses the quest item "
        .. "you need right now (shift-click: the next one, ctrl-click: the third), kept up to date as your quests change. "
        .. "It goes in your General macros, shared by all your characters.\n\nMake it?",
    button1 = "Make it",
    button2 = "No thanks",
    OnAccept = function() M:Create() end,
    OnCancel = function(_, _, reason)
        if reason == "clicked" then
            ns.db.questMacroAsked = true
            ns:Print("No quest item macro. You can make it any time: Options > AddOns > Field Guide, or /fg macro.")
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function MaybeAsk()
    if not ns.db or ns.db.questMacroAsked or ns.db.questMacro or Index() then return end
    if InCombatLockdown() or (IsInInstance and IsInInstance()) then return end
    if StaticPopup_Visible and StaticPopup_Visible("FIELDGUIDE_QUEST_MACRO") then return end
    if #M:Items() == 0 then return end
    StaticPopup_Show("FIELDGUIDE_QUEST_MACRO")
end

-- ---------------------------------------------------------------------------
-- Keeping it up to date (a burst of changes: once, a moment later)
-- ---------------------------------------------------------------------------

local queued = false
local function Queue()
    if queued then return end
    queued = true
    C_Timer.After(0.5, function()
        queued = false
        M:Refresh()
        MaybeAsk()
    end)
end
M.Queue = Queue

ns:On("BAG_UPDATE_DELAYED", Queue)
ns:On("QUEST_LOG_UPDATE", Queue)
ns:On("GET_ITEM_INFO_RECEIVED", function() if ns.db and ns.db.questMacro then Queue() end end)
ns:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(3, Queue) end)
ns:On("PLAYER_REGEN_ENABLED", function()
    if pending then pending = false; Queue() end
end)
ns:OnChanged(Queue) -- the current step moved on

function M:Command()
    self:Create()
end
