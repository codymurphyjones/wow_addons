local addonName, ns = ...

-- The quest log: a small Field Guide icon left of each quest's title. Hover it: where the quest
-- sits on the guide's route. Click it: a popup with the route for the zone you're on (the steps left,
-- in the order the guide has them: the same order the arrow follows) and this quest's steps in it
-- highlighted. A quest that isn't on the route says why (another section, skipped, too little XP).
--
-- The quest log's rows are the game's own, reused as it scrolls: the icons are found again each
-- time the log changes (and twice a second while it's open), never kept by quest. Rows are found
-- by what they carry: a row with a questID (the quest log beside the world map), or the numbered
-- title buttons of a separate Quest Log window (QuestLogTitle1, ...), whichever this client has.
local QL = {}
ns.QuestLog = QL

local GOLD = { 1, 0.82, 0 }
local GREEN = { 0.56, 0.82, 0.42 }
local DIM = { 0.55, 0.58, 0.6 }
local MAX_LINES = 22 -- lines in the popup's list; a longer route shows its start and around the quest
local AROUND = 4     -- steps shown before and after each of the quest's steps in a long route

local icons = {} -- quest log row -> its icon button
local popup

-- ---------------------------------------------------------------------------------------------
-- The route and the quest's place in it
-- ---------------------------------------------------------------------------------------------

local function Quest(step) return step[1] ~= "G" and step[1] ~= "Z" and step[1] ~= "I" end

-- The steps left on the route, from the step to do now, in order.
local function Left()
    local E = ns.Engine
    local list = {}
    if not (E and E.current and E.steps) then return list end
    for i = E.current, #E.steps do
        local s = E.steps[i]
        if not E:StepDone(s) then list[#list + 1] = s end
    end
    return list
end

-- Where the quest's steps are in list: { index, ... }.
local function Places(list, questID)
    local at = {}
    for i, s in ipairs(list) do
        if Quest(s) and s[2] == questID then at[#at + 1] = i end
    end
    return at
end

-- Why a quest isn't on the route, in a sentence.
local function WhyNot(questID)
    local E = ns.Engine
    if not ns.Quests[questID] then return "None of Field Guide's guides have this quest. It's yours to do whenever you like." end
    if ns.char.ignored[questID] then return "You skipped it, so Field Guide leaves it to you (/fg unskip brings it back)." end
    if ns.char.doneByHand[questID] then return "You marked it done (/fg unskip brings it back)." end
    if not E.section then return "Field Guide has no route for your level right now." end
    for _, s in ipairs(E.guide and E.guide.sections or {}) do
        if s ~= E.section then
            for _, st in ipairs(s.steps or {}) do
                if Quest(st) and st[2] == questID then
                    return ("It's on %s (levels %d-%d), not on the section you're following."):format(s.title, s.from, s.to)
                end
            end
        end
    end
    return "It isn't on this route: it pays too little XP at your level, or it's too far out of the way. It's yours to do whenever you like."
end

-- "#4 of 23" for the quest's next step on the route, or nil.
local function Summary(questID)
    local list = Left()
    local at = Places(list, questID)[1]
    if not at then return nil end
    local verb = ns.Engine:Describe(list[at])
    return ("%s: step %d of %d"):format(verb, at, #list), at == 1
end

-- ---------------------------------------------------------------------------------------------
-- The popup
-- ---------------------------------------------------------------------------------------------

local function Font(fs, r, g, b) fs:SetTextColor(r, g, b) end

local function Line(i)
    popup.lines = popup.lines or {}
    local fs = popup.lines[i]
    if not fs then
        fs = popup:CreateFontString(nil, "OVERLAY", addonName .. "GameFontHighlightSmall")
        fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
        fs:SetPoint("RIGHT", -12, 0)
        popup.lines[i] = fs
    end
    return fs
end

local function Popup()
    if popup then return popup end
    popup = CreateFrame("Frame", "FieldGuideQuestRoute", UIParent, "BackdropTemplate")
    popup:SetSize(360, 100); popup:SetFrameStrata("FULLSCREEN_DIALOG"); popup:SetClampedToScreen(true)
    popup:EnableMouse(true); popup:SetMovable(true); popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", popup.StartMoving)
    popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
    if popup.SetBackdrop then
        popup:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        popup:SetBackdropColor(0.04, 0.05, 0.06, 0.94)
        popup:SetBackdropBorderColor(GREEN[1], GREEN[2], GREEN[3], 0.4)
    end
    if WallyHUD and WallyHUD.Panel then WallyHUD.Panel(popup, "base") end
    popup.title = popup:CreateFontString(nil, "OVERLAY", addonName .. "GameFontNormal")
    popup.title:SetPoint("TOPLEFT", 12, -10); popup.title:SetPoint("RIGHT", -30, 0)
    popup.title:SetJustifyH("LEFT"); popup.title:SetWordWrap(false)
    popup.where = popup:CreateFontString(nil, "OVERLAY", addonName .. "GameFontHighlightSmall")
    popup.where:SetPoint("TOPLEFT", popup.title, "BOTTOMLEFT", 0, -4); popup.where:SetPoint("RIGHT", -12, 0)
    popup.where:SetJustifyH("LEFT")
    local close = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    -- Escape closes it.
    tinsert(UISpecialFrames, "FieldGuideQuestRoute")
    popup:Hide()
    return popup
end

-- Which of list's indexes to show: all of a short route; of a long one, its start and the steps
-- around each of the quest's. A gap between shown steps shows as one "..." line.
local function Shown(n, at)
    local show = {}
    if n <= MAX_LINES then
        for i = 1, n do show[i] = true end
        return show
    end
    for i = 1, 3 do show[i] = true end
    for _, a in ipairs(at) do
        for i = math.max(1, a - AROUND), math.min(n, a + AROUND) do show[i] = true end
    end
    -- Nothing of the quest's on the route: as much of its start as fits.
    if #at == 0 then for i = 1, MAX_LINES do show[i] = true end end
    return show
end

local function Fill()
    local E = ns.Engine
    local questID = popup.questID
    local q = ns.Quests[questID]
    local name = q and E:QuestName(questID) or (C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)) or ("Quest " .. questID)
    popup.title:SetText(ns.IconMarkup(14) .. " " .. (E.section and E.section.title or "Field Guide"))
    local list = Left()
    local at = Places(list, questID)
    local where
    if #at > 0 then
        local parts = {}
        for _, i in ipairs(at) do parts[#parts + 1] = ("%s #%d"):format(strlower((E:Describe(list[i]))), i) end
        where = ("|cffffd100%s|r: %s of %d steps left."):format(name, table.concat(parts, ", "), #list)
        if at[1] == 1 then where = where .. " |cff8fd16aIt's the step to do now.|r" end
    else
        where = ("|cffffd100%s|r: %s"):format(name, WhyNot(questID))
    end
    if ns.char.paused then where = where .. " |cff8a948e(The guide is paused.)|r" end
    popup.where:SetText(where)
    local mine = {}
    for _, i in ipairs(at) do mine[i] = true end
    local show = Shown(#list, at)
    local y = -14 - popup.title:GetStringHeight() - popup.where:GetStringHeight() - 10
    local n, gap = 0, false
    local function Put(text, col)
        n = n + 1
        local fs = Line(n)
        fs:SetPoint("TOPLEFT", 12, y)
        fs:SetText(text); Font(fs, col[1], col[2], col[3])
        fs:Show()
        y = y - 15
    end
    for i, s in ipairs(list) do
        if show[i] then
            if gap then Put("   ...", DIM) end
            gap = false
            local verb, sname = E:Describe(s)
            local text = ("%d.  %s: %s"):format(i, verb, sname)
            if i == 1 then text = text .. "  |cff8fd16a(now)|r" end
            if s.later then text = text .. "  |cff8a948e(later)|r" end
            Put(text, mine[i] and GOLD or (i == 1 and { 1, 1, 1 } or { 0.82, 0.84, 0.86 }))
        else
            gap = true
        end
    end
    if gap then Put("   ...", DIM) end
    if #list == 0 then Put("Nothing left on the route.", DIM) end
    for i = n + 1, #(popup.lines or {}) do popup.lines[i]:Hide() end
    popup:SetHeight(-y + 10)
end

function QL:Open(questID, anchor)
    if not (ns.Engine and ns.db) then return end
    Popup()
    if popup:IsShown() and popup.questID == questID then
        popup:Hide()
        return
    end
    popup.questID = questID
    popup:ClearAllPoints()
    if anchor then
        popup:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 12, 8)
    else
        popup:SetPoint("CENTER")
    end
    Fill()
    popup:Show()
end

-- The route changed while it's open: it follows.
ns:OnChanged(function()
    if popup and popup:IsShown() then Fill() end
end)

-- ---------------------------------------------------------------------------------------------
-- The icons on the quest log's rows
-- ---------------------------------------------------------------------------------------------

local function Icon(row)
    local b = icons[row]
    if b then return b end
    b = CreateFrame("Button", nil, row)
    b:SetSize(14, 14)
    b.tex = b:CreateTexture(nil, "ARTWORK"); b.tex:SetAllPoints()
    b.tex:SetTexture(ns.ICON)
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    b:SetScript("OnClick", function(self) QL:Open(self.questID, self) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ns.IconMarkup(14) .. " Field Guide", GREEN[1], GREEN[2], GREEN[3])
        local summary, now = Summary(self.questID)
        if summary then
            GameTooltip:AddLine(summary .. (now and " (now)" or ""), 1, 1, 1)
        else
            GameTooltip:AddLine("Not on the route you're following.", 0.8, 0.8, 0.8)
        end
        GameTooltip:AddLine("Click: the route for this zone, with this quest in it", 0.75, 0.8, 0.85)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    icons[row] = b
    return b
end

-- Puts the icon on row for questID (nil: hides it). Left of the title's text when the row has
-- one, else just inside the row's left edge.
local function Mark(row, questID)
    if not questID then
        if icons[row] then icons[row]:Hide() end
        return
    end
    local b = Icon(row)
    b.questID = questID
    b:SetFrameLevel(row:GetFrameLevel() + 5)
    if not b.placed then
        b.placed = true
        local text = row.Text or (row.GetFontString and row:GetFontString())
        b:ClearAllPoints()
        if text and text.GetLeft and row.GetLeft and text:GetLeft() and row:GetLeft() and text:GetLeft() - row:GetLeft() >= 16 then
            b:SetPoint("RIGHT", text, "LEFT", -2, 0)
        else
            b:SetPoint("LEFT", row, "LEFT", 1, 0)
        end
    end
    b:Show()
end

local function QuestIDOf(frame)
    local id = frame.questID
    if type(id) == "number" and id > 0 then return id end
end

-- The quest log beside the world map: its rows carry .questID (looked for two levels down). A
-- quest's objective lines can carry it too: the icon goes on the quest's top line, its title.
local function ScanMapLog()
    local scroll = _G.QuestScrollFrame
    if not (scroll and scroll:IsVisible()) then return end
    local root = scroll.Contents or (scroll.ScrollBox and scroll.ScrollBox.ScrollTarget) or scroll
    local title, seen = {}, {} -- questID -> its top row; rows looked at
    local function Walk(frame, depth)
        for _, child in ipairs({ frame:GetChildren() }) do
            seen[child] = true
            local id = child:IsShown() and child.Text and QuestIDOf(child)
            local top = id and child:GetTop()
            if top and (not title[id] or top > title[id]:GetTop()) then title[id] = child end
            if depth < 2 then Walk(child, depth + 1) end
        end
    end
    Walk(root, 1)
    local mine = {}
    for id, row in pairs(title) do mine[row] = id end
    for row in pairs(seen) do
        if mine[row] then Mark(row, mine[row]) elseif icons[row] then Mark(row, nil) end
    end
end

-- A separate Quest Log window: QuestLogTitle1, 2, ... over the log's entries, scrolled.
local function ScanQuestLogWindow()
    local frame = _G.QuestLogFrame
    if not (frame and frame:IsVisible() and GetQuestLogTitle) then return end
    local offset = (_G.QuestLogListScrollFrame and FauxScrollFrame_GetOffset) and FauxScrollFrame_GetOffset(_G.QuestLogListScrollFrame) or 0
    for i = 1, 40 do
        local row = _G["QuestLogTitle" .. i]
        if not row then break end
        local id
        if row:IsShown() then
            local _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle((row.GetID and row:GetID() or i) + offset)
            if not isHeader and type(questID) == "number" and questID > 0 then id = questID end
        end
        Mark(row, id)
    end
end

function QL:Scan()
    if not ns.db then return end
    ScanMapLog()
    ScanQuestLogWindow()
end

local ScanSoon = ns.Soon(function() QL:Scan() end, 0.05)

-- Twice a second while a quest log shows (a driver parented to it ticks only then), and right
-- after the game redraws it.
local hooked = {}
local function Hook()
    for _, name in ipairs({ "QuestScrollFrame", "QuestLogFrame" }) do
        local f = _G[name]
        if f and not hooked[name] then
            hooked[name] = true
            local driver = CreateFrame("Frame", nil, f)
            ns.Every(driver, 0.5, function() QL:Scan() end)
            f:HookScript("OnShow", ScanSoon)
            f:HookScript("OnHide", function() if popup then popup:Hide() end end)
        end
    end
    for _, fn in ipairs({ "QuestLogQuests_Update", "QuestLog_Update" }) do
        if _G[fn] and not hooked[fn] then
            hooked[fn] = true
            hooksecurefunc(fn, ScanSoon)
        end
    end
end

ns:On("PLAYER_LOGIN", Hook)
-- The world map's quest log can load later, with its addon.
ns:On("ADDON_LOADED", function() Hook() end)
ns:On("QUEST_LOG_UPDATE", ScanSoon)
