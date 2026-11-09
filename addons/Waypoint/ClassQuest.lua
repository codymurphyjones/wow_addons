local _, ns = ...

-- Class quests first. Guides never suggest class quests (Field Guide leaves them out), but once one
-- is in your log it comes first: the addon that owns the arrow (Field Guide) is paused, as its
-- pause button does, and the arrow follows the class quest (Questie.lua's target for it, required
-- items first). When no class quest is left in your log (handed in, or dropped), the owner resumes.
--
-- A small class icon sits by the arrow while you have a class quest, whatever is leading. Click it
-- to grey it out: the owner resumes and leads as usual, the class quest waits. Click again to put
-- the class quest first again. A class quest you take later puts it first again by itself.
--
-- A class quest: one Questie says a class must take (requiredClasses), or files under a class
-- (zoneOrSort: Druid is -263...), or one in your log under a header named after your class.
-- Forever's own class quests (The Great Windborne Cat Spirit) have no requiredClasses in Questie's
-- data, only the class category: looking at requiredClasses alone missed them.
local CQ = {}
ns.ClassQuest = CQ

local K = ns.QuestieKit
local SIZE = 24 -- the owner's button's size (Arrow.lua's extraIcon): it sits beside it

local holding      -- true while the owner is paused for a class quest
local quests = {}  -- [questID] = name: the class quests in your log
local button

-- Questie's quest categories that are classes (QuestSort): warlock, warrior, shaman, paladin, mage,
-- rogue, hunter, priest, druid. (Other negative ones are professions and holidays.)
local CLASS_SORT = { [-61] = true, [-81] = true, [-82] = true, [-141] = true, [-161] = true, [-162] = true,
    [-261] = true, [-262] = true, [-263] = true }

local function IsClassQuest(id, header)
    if K and K.Query then
        local classes = K.Query(id, "requiredClasses")
        if type(classes) == "number" and classes > 0 then return true end
        local sort = K.Query(id, "zoneOrSort")
        if type(sort) == "number" and CLASS_SORT[sort] then return true end
    end
    local className = UnitClass("player")
    return header ~= nil and className ~= nil and header == className
end
CQ.IsClassQuest = function(_, id) return IsClassQuest(id) end

local function InLog()
    local out = {}
    local under -- the name of the header the rows below sit under
    local num = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries())
        or (GetNumQuestLogEntries and GetNumQuestLogEntries()) or 0
    for i = 1, num do
        local id, title, isHeader
        local info = C_QuestLog and C_QuestLog.GetInfo and C_QuestLog.GetInfo(i)
        if type(info) == "table" then
            id, title, isHeader = info.questID, info.title, info.isHeader
        elseif GetQuestLogTitle then
            local t, _, _, h, _, _, _, qid = GetQuestLogTitle(i)
            id, title, isHeader = qid, t, h
        end
        if isHeader then
            under = title
        elseif id and id > 0 and IsClassQuest(id, under) then
            out[id] = title or ("Quest " .. id)
        end
    end
    -- Quests under a collapsed header aren't listed above: Questie's copy of your log has them all.
    local log = K and K.QuestLog and K.QuestLog()
    if type(log) == "table" then
        for id, q in pairs(log) do
            if type(id) == "number" and not out[id] and IsClassQuest(id) then
                out[id] = type(q) == "table" and q.name or ("Quest " .. id)
            end
        end
    end
    return out
end

-- A class quest of yours, in your log.
function CQ:Is(id) return quests[id] ~= nil end

-- Whether class quests lead now: you have one, and haven't greyed the icon.
function CQ:Active() return next(quests) ~= nil and not (ns.char and ns.char.classQuestOff) end

-- ---------------------------------------------------------------------------------------------
-- The icon
-- ---------------------------------------------------------------------------------------------

local function ClassIcon(tex)
    local _, class = UnitClass("player")
    local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if coords then
        tex:SetTexture("Interface\\WorldStateFrame\\Icons-Classes")
        tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
end

local function Tooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Class quest", 1, 0.82, 0)
    local names = {}
    for _, name in pairs(quests) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do GameTooltip:AddLine(name, 1, 1, 1) end
    if CQ:Active() then
        GameTooltip:AddLine("The arrow leads you through it first; the guide waits and comes back when it's done.", 0.8, 0.85, 0.9, true)
        GameTooltip:AddLine("Click: let the guide lead (the class quest waits).", 0.5, 0.5, 0.5)
    else
        GameTooltip:AddLine("Waiting: the guide leads as usual.", 0.8, 0.85, 0.9, true)
        GameTooltip:AddLine("Click: put the class quest first.", 0.5, 0.5, 0.5)
    end
    GameTooltip:Show()
end

-- Whether the icon shows (a class quest in your log): Arrow.lua makes room for it.
function CQ:Shown() return next(quests) ~= nil end

-- Put beside the owner's button by Arrow.lua: TOPRIGHT x from the arrow's top right.
function CQ:Anchor(f, x)
    if not button then return end
    button:ClearAllPoints()
    button:SetPoint("TOPRIGHT", f, "TOPRIGHT", x, -3)
end

local function Place()
    local f = ns.Arrow and ns.Arrow.GetFrame and ns.Arrow:GetFrame()
    if not f then return end
    if not button then
        button = CreateFrame("Button", nil, f, "BackdropTemplate")
        button:SetSize(SIZE, SIZE)
        button:SetFrameLevel(f:GetFrameLevel() + 5)
        -- A 1px border round the icon, as the arrow's other boxes have.
        if button.SetBackdrop then
            button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            button:SetBackdropColor(0, 0, 0, 0.6)
            button:SetBackdropBorderColor(1, 1, 1, 0.25)
        end
        button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetPoint("TOPLEFT", 2, -2); button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        ClassIcon(button.icon)
        button:SetScript("OnEnter", Tooltip)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        button:SetScript("OnClick", function(self)
            ns.char.classQuestOff = not ns.char.classQuestOff
            CQ:Update()
            if GameTooltip:IsOwned(self) then Tooltip(self) end
        end)
    end
    button:SetShown(next(quests) ~= nil)
    -- (Where it goes is Arrow.lua's layout: left of the owner's button, the title moved over.)
    if ns.Arrow and ns.Arrow.Relayout then ns.Arrow:Relayout() end
    button.icon:SetDesaturated(not CQ:Active())
    button.icon:SetAlpha(CQ:Active() and 1 or 0.6)
end

-- ---------------------------------------------------------------------------------------------
-- The first time: what's happening, once for the account (db.classQuestExplained)
-- ---------------------------------------------------------------------------------------------

-- (Only an entry is added: replacing StaticPopupDialogs itself would taint the game's own popups.)
StaticPopupDialogs["WAYPOINT_CLASS_QUEST"] = {
    text = "|cffffd100Class quest first|r\n\nYou picked up a class quest. Guides like Field Guide never suggest "
        .. "class quests, but once one is in your log it comes first:\n\n"
        .. "- The guide is paused, as its pause button would.\n"
        .. "- The arrow leads you through the class quest, items it needs first (a key, a lockbox, a bauble), "
        .. "then where to use them, then the hand-in.\n"
        .. "- When the class quest is done, the guide comes back by itself.\n\n"
        .. "A small class icon by the arrow shows while you have a class quest. Click it to let the guide lead "
        .. "for now (the icon greys out); click again to put the class quest first.",
    button1 = OKAY or "Okay",
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local function Explain()
    if not ns.db or ns.db.classQuestExplained then return end
    ns.db.classQuestExplained = true
    if StaticPopup_Show then StaticPopup_Show("WAYPOINT_CLASS_QUEST") end
end

-- ---------------------------------------------------------------------------------------------
-- Leading
-- ---------------------------------------------------------------------------------------------

-- Looks at your log again: the icon, and who leads.
function CQ:Update()
    if not ns.char then return end
    local before = next(quests) ~= nil
    quests = InLog()
    if not next(quests) then ns.char.classQuestOff = nil end
    local active = self:Active()
    if active and not holding then
        holding = true
        local m = ns.Targets:GetManager()
        ns.char.classQuestHolding = (m and m.owner) or true
        if m and m.pause then ns.Targets:PauseManager() end
        for id in pairs(quests) do if ns.Questie.Track then pcall(ns.Questie.Track, ns.Questie, "Waypoint", id) end end
        ns:Print("Class quest first: the arrow leads you through it, and the guide comes back when it's done.")
        Explain()
    elseif not active and holding then
        holding = false
        local owner = ns.char.classQuestHolding
        ns.char.classQuestHolding = nil
        if type(owner) == "string" then ns.Targets:Resume(owner) end
        if before then ns:Print(next(quests) and "The class quest waits: back to the guide." or "Class quest done: back to the guide.") end
    end
    Place()
    if ns.Questie and ns.Questie.Select then ns.Questie:Select() end
    ns:Changed()
end

local queued = false
local function Soon()
    if queued then return end
    queued = true
    C_Timer.After(0.5, function() queued = false; CQ:Update() end)
end

ns:On("PLAYER_LOGIN", function()
    -- (Paused for a class quest when you logged out: still holding, so finishing it resumes the guide.)
    holding = ns.char and ns.char.classQuestHolding or false
    C_Timer.After(3, function() CQ:Update() end)
end)
ns:On("QUEST_ACCEPTED", function(a, b)
    local id = b or a
    -- A class quest you take now puts class quests first again.
    if type(id) == "number" and IsClassQuest(id) and ns.char then ns.char.classQuestOff = nil end
    Soon()
end)
ns:On("QUEST_REMOVED", Soon)
-- Questie's data can come later than login (+3 s): look again once it's ready, and when the log
-- changes (Soon is throttled, and Update only acts when something changed).
ns:On("PLAYER_LOGIN", function()
    if K and K.OnReady then K.OnReady(Soon) end
end)
ns:On("QUEST_LOG_UPDATE", Soon)
ns:On("QUEST_TURNED_IN", Soon)
ns:On("QUEST_LOG_UPDATE", Soon)
