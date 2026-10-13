local _, ns = ...

-- A quest window in the style of the game's quest giver frame: parchment,
-- the quest's title and objectives, where its giver stands (continent,
-- zone, subzone, coordinates), the chain it belongs to and its rewards. The
-- Track button marks the giver on the world map and names the quest in the
-- on-screen tracker.
local W = {}
ns.QuestWindow = W

local INK = { 0.18, 0.11, 0.04 }       -- quest text brown
local HEADING = { 0.04, 0.02, 0.0 }    -- quest heading near-black
local TICK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:13|t"
local ARROW = "|TInterface\\Buttons\\UI-SpellbookIcon-NextPage-Up:14|t"
local QUEST_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
local PARCHMENT = { "Interface\\QuestFrame\\QuestBG", "Interface\\QuestFrame\\QuestBackground" }

local f, content
local shown -- { step, reward, item }
local pools = { text = {}, item = {} }
local used = {}

---------------------------------------------------------------------------
-- Text helpers
---------------------------------------------------------------------------

-- The game's quest text placeholders: $N name, $C class, $R race.
local function Fill(text)
    local name = UnitName("player") or ""
    local class = UnitClass("player") or ""
    local race = UnitRace("player") or ""
    return (text:gsub("%$[Nn]", name):gsub("%$[Cc]", class:lower()):gsub("%$[Rr]", race))
end

local function Take(kind, make)
    used[kind] = (used[kind] or 0) + 1
    local item = pools[kind][used[kind]]
    if not item then
        item = make()
        pools[kind][used[kind]] = item
    end
    item:ClearAllPoints()
    item:Show()
    return item
end

local function Text(text, font, color, y, indent)
    local fs = Take("text", function()
        local s = content:CreateFontString(nil, "OVERLAY")
        s:SetJustifyH("LEFT")
        s:SetSpacing(2)
        return s
    end)
    fs:SetFontObject(font)
    fs:SetWidth(content:GetWidth() - 12 - (indent or 0))
    fs:SetPoint("TOPLEFT", 6 + (indent or 0), y)
    fs:SetText(text)
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetShadowOffset(0, 0)
    return y - fs:GetStringHeight() - 6
end

local function Heading(text, y)
    return Text(text, _G.QuestTitleFont and "QuestTitleFont" or "GameFontNormalLarge", HEADING, y - 6)
end

local function Body(text, y, indent)
    return Text(text, _G.QuestFont and "QuestFont" or "GameFontHighlight", INK, y, indent)
end

-- A reward item, like the quest frame's: icon in a slot, name in its rarity colour.
local function RewardItem(itemID, x, y, highlight)
    local b = Take("item", function()
        local button = CreateFrame("Button", nil, content)
        button:SetSize(150, 40)
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetSize(36, 36)
        button.icon:SetPoint("LEFT")
        button.frame = button:CreateTexture(nil, "BACKGROUND")
        button.frame:SetPoint("LEFT", button.icon, "RIGHT", -6, 0)
        button.frame:SetSize(118, 40)
        if not button.frame:SetTexture("Interface\\QuestFrame\\UI-QuestItemNameFrame") then
            button.frame:SetColorTexture(0, 0, 0, 0.15)
        end
        button.glow = button:CreateTexture(nil, "OVERLAY")
        button.glow:SetPoint("TOPLEFT", button.icon, -3, 3)
        button.glow:SetPoint("BOTTOMRIGHT", button.icon, 3, -3)
        button.glow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        button.glow:SetBlendMode("ADD")
        button.name = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        button.name:SetPoint("LEFT", button.icon, "RIGHT", 6, 0)
        button.name:SetWidth(104)
        button.name:SetJustifyH("LEFT")
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.itemID)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        button:SetScript("OnClick", function(self)
            local link = select(2, GetItemInfo(self.itemID))
            if link and IsModifiedClick() then HandleModifiedItemClick(link) end
        end)
        return button
    end)
    b.itemID = itemID
    local info = SpyGlass:ItemInfo(itemID)
    b.icon:SetTexture(info and info.icon or GetItemIcon(itemID) or "Interface\\Icons\\INV_Misc_QuestionMark")
    b.name:SetText(info and info.name or "...")
    b.name:SetTextColor(SpyGlass:QualityColor(info and info.quality or 1))
    b.glow:SetShown(highlight)
    b:SetPoint("TOPLEFT", x, y)
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local function Build()
    f = CreateFrame("Frame", "SpyGlassPluginQuestsFrame", UIParent, "PortraitFrameTemplate")
    f:SetSize(384, 512)
    f:SetPoint("LEFT", 40, 40)
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, "SpyGlassPluginQuestsFrame")
    if f.SetPortraitToAsset then f:SetPortraitToAsset(QUEST_ICON) end

    -- Parchment filling the whole window inside the frame border; the
    -- buttons sit on it at the bottom, like the game's quest frame. It's the
    -- window's own background texture, so the border and portrait (child
    -- frames of the template) stay drawn over it.
    local paper = f:CreateTexture(nil, "BACKGROUND", nil, 7)
    paper:SetPoint("TOPLEFT", 3, -22)
    paper:SetPoint("BOTTOMRIGHT", -3, 3)
    local ok = false
    for _, path in ipairs(PARCHMENT) do
        if paper:SetTexture(path) then ok = true break end
    end
    if ok then
        -- The parchment is only part of the image file (the rest is empty);
        -- show just that part, stretched to the page.
        paper:SetTexCoord(0.01, 0.59, 0.005, 0.655)
    else
        paper:SetColorTexture(0.87, 0.79, 0.62, 1)
    end

    -- Text starts below the portrait in the top-left corner and stops above
    -- the buttons.
    f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT", 22, -46)
    f.scroll:SetPoint("BOTTOMRIGHT", -34, 38)
    content = CreateFrame("Frame", nil, f.scroll)
    content:SetSize(320, 10)
    f.scroll:SetScrollChild(content)

    f.track = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.track:SetSize(110, 22)
    f.track:SetPoint("BOTTOMLEFT", 10, 8)
    f.track:SetScript("OnClick", function() W:ToggleTrack() end)
    -- Undoes "not offered here" marks in this chain, if one was wrong.
    f.resetSkips = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.resetSkips:SetSize(110, 22)
    f.resetSkips:SetPoint("BOTTOM", 0, 8)
    f.resetSkips:SetText("Reset skipped")
    f.resetSkips:SetScript("OnClick", function() W:ResetSkips() end)
    f.resetSkips:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Reset skipped steps")
        GameTooltip:AddLine("Steps marked \"not offered here\" were skipped because their giver didn't offer them "
            .. "when you arrived. Reset if that was wrong.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.resetSkips:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.resetSkips:Hide()
    local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    close:SetSize(90, 22)
    close:SetPoint("BOTTOMRIGHT", -10, 8)
    close:SetText(CLOSE or "Close")
    close:SetScript("OnClick", function() f:Hide() end)
    f:Hide()
end

local function TrackKey(reward)
    return "quest:" .. reward
end

local function IsTracked(reward)
    local wp = SpyGlass:GetWaypoint()
    return wp and wp.key == TrackKey(reward)
end

local SKIPPED = "|cff8a6a40(not offered here)|r"

-- "Pick up from Gryan Stoutmantle" / "Turn in to Gryan Stoutmantle"
local function ActionText(target)
    local who = target.person and target.person.name or "the quest giver"
    if target.action == "turnin" then return "Turn in to " .. who end
    return "Pick up from " .. who
end

local function Draw()
    for kind, pool in pairs(pools) do
        for _, item in ipairs(pool) do item:Hide() end
        used[kind] = 0
    end
    local Q = ns.Quests
    local reward, focusItem = shown.reward, shown.item
    local target = Q:Target(reward)
    local step = target.quest
    shown.step = step
    local person = target.person
    local loc = ns.Location:ForPerson(person, step)

    if f.SetTitle then f:SetTitle(person and person.name or Q:Title(step)) end
    content:SetWidth(f.scroll:GetWidth())
    local y = -4

    y = Text(Q:Title(step), _G.QuestTitleFont and "QuestTitleFont" or "GameFontNormalLarge", HEADING, y)
    local level = Q.Get(step, "questLevel")
    local minLevel = Q.Get(step, "requiredLevel")
    local levelText = (level and level > 0) and ("Level " .. level .. " quest") or "Quest"
    if minLevel and minLevel > 0 then levelText = levelText .. "  (you can take it at level " .. minLevel .. ")" end
    y = Body(levelText, y)
    if step ~= reward then
        y = Body("Leads to |cff7a1a00" .. Q:Title(reward) .. "|r, which rewards the gear below.", y)
    end

    -- What to do now, and where.
    y = Heading(target.action == "turnin" and "Turn in" or "Where to start", y)
    if person then
        local who = person.name or "Unknown"
        if person.subName then who = who .. " <" .. person.subName .. ">" end
        y = Body(ActionText({ person = { name = who }, action = target.action }), y)
    end
    if loc then
        y = Body("Continent: " .. (loc.continent or "Unknown"), y)
        y = Body("Zone: " .. (loc.zone or "Unknown"), y)
        y = Body("Subzone: " .. (loc.subzone or "-"), y)
        y = Body("Coordinates: " .. loc.coords, y)
    else
        y = Body("Where to find them isn't known.", y)
    end

    local objectives = Q.Get(step, "objectivesText")
    if type(objectives) == "table" and #objectives > 0 then
        y = Heading("Quest Objectives", y)
        y = Body(Fill(table.concat(objectives, "\n")), y)
    end

    local chain = Q:Chain(reward)
    local anySkipped = false
    if #chain > 1 then
        y = Heading("Quest chain", y)
        for i, id in ipairs(chain) do
            local mark = Q:Done(id) and TICK or (id == step and ARROW or "   ")
            local title = Q:Title(id)
            if id == step then title = "|cff7a1a00" .. title .. "|r" end
            if Q:Skipped(id) and not Q:Done(id) then
                title = title .. " " .. SKIPPED
                anySkipped = true
            end
            y = Body(mark .. " " .. i .. ". " .. title, y, 4)
        end
    end

    local items = Q.rewardsByQuest[reward] or {}
    if #items > 0 then
        y = Heading("Rewards", y)
        y = Body(#items > 1 and "You will be able to choose one of these rewards:" or "You will receive:", y)
        for i, itemID in ipairs(items) do
            local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
            RewardItem(itemID, 6 + col * 156, y - row * 44, itemID == focusItem)
        end
        y = y - math.ceil(#items / 2) * 44 - 6
    end

    content:SetHeight(-y + 10)
    f.scroll:SetVerticalScroll(0)
    f.track:SetText(IsTracked(reward) and "Stop tracking" or "Track quest")
    f.track:SetEnabled(loc ~= nil and loc.uiMapID ~= nil)
    f.resetSkips:SetShown(anySkipped)
end

-- Shows the quest chain leading to reward (a quest that gives gear), at the
-- step you need next; item is the reward to highlight.
function W:Show(reward, item)
    if not f then Build() end
    shown = { reward = reward, item = item }
    f:Show()
    Draw()
end

-- Marks where to go next on the world map and names the quest in the
-- tracker: the giver of the next step, or whoever takes it back once it's in
-- your quest log.
function W:Track(reward, quiet)
    local target = ns.Quests:Target(reward)
    local loc = ns.Location:ForPerson(target.person, target.quest)
    if not (loc and loc.uiMapID) then
        if not quiet then
            print("|TInterface\\AddOns\\Spyglass\\Media\\Icon:14:14|t |cff66bbffSpyGlass|r: where " .. ns.Quests:Title(target.quest) .. " starts isn't known.")
        end
        return false
    end
    local where = loc.subzone and (loc.subzone .. ", " .. loc.zone) or loc.zone
    SpyGlass:SetWaypoint({
        uiMapID = loc.uiMapID, x = loc.x, y = loc.y,
        title = (target.action == "turnin" and "Turn in: " or "Pick up: ") .. ns.Quests:Title(target.quest),
        subtitle = ActionText(target) .. (where and (", " .. where) or ""),
        key = TrackKey(reward),
        onClick = function() W:Show(reward) end,
        -- For the plugin's arrival check (Plugin.lua).
        quest = target.quest, person = target.person and target.person.id, action = target.action,
    })
    return true
end

function W:ToggleTrack()
    if not shown then return end
    if IsTracked(shown.reward) then
        SpyGlass:ClearWaypoint()
    else
        self:Track(shown.reward)
    end
    Draw()
end

function W:ResetSkips()
    if not shown then return end
    ns.Quests:ResetSkips(shown.reward)
    if IsTracked(shown.reward) then self:Track(shown.reward, true) end
    Draw()
end

-- The tracked chain (reward quest ID), or nil.
function W:TrackedReward()
    local wp = SpyGlass:GetWaypoint()
    return wp and wp.key and tonumber(wp.key:match("^quest:(%d+)$"))
end

-- After quests change (accepted, handed in, skipped): point the tracker at
-- what to do next, or stop once the reward quest is done. Redraws the open
-- window.
function W:QuestProgress()
    local reward = self:TrackedReward()
    if reward then
        if ns.Quests:Done(reward) then
            SpyGlass:ClearWaypoint()
            print("|TInterface\\AddOns\\Spyglass\\Media\\Icon:14:14|t |cff66bbffSpyGlass|r: " .. ns.Quests:Title(reward) .. " is done - stopped tracking.")
        else
            self:Track(reward, true)
        end
    end
    if f and f:IsShown() and shown then Draw() end
end

-- A waypoint saved before a reload gets its click handler back.
function W:RestoreTracking()
    if self:TrackedReward() then self:Track(self:TrackedReward(), true) end
end
