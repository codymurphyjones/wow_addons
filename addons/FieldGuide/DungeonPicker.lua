local _, ns = ...

-- The swap between the leveling guide and the dungeon guide: a button on the left of Waypoint's arrow,
-- there while you have dungeon quests to do or are on a dungeon's route. From the leveling guide it opens
-- a small list of those dungeons, a picture and a name each, to choose which to focus on; on a dungeon's
-- route it goes back. ("Guide me" on the popup that offers a dungeon needs no list: it's chosen.)
local P = {}
ns.DungeonPicker = P

local MEDIA = "Interface\\AddOns\\FieldGuide\\Media\\"
local DUNGEON, LEVELING = MEDIA .. "Field\\dungeon", MEDIA .. "Field\\leveling"
local WIDTH, ROW = 270, 42
local PICTURE_W, PICTURE_H = 72, 36

local frame, owner
local rows = {}
local shownKey

-- The dungeon's picture, or the guide's dungeon icon for one without.
local function Picture(inst)
    local name = ns.DungeonArt and ns.DungeonArt[inst.key]
    return name and (MEDIA .. "Dungeons\\" .. name) or DUNGEON
end
P.Picture = Picture

local function Row(i)
    local b = rows[i]
    if b then return b end
    b = CreateFrame("Button", nil, frame)
    b:SetSize(WIDTH - 12, ROW)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.picture = b:CreateTexture(nil, "ARTWORK")
    b.picture:SetSize(PICTURE_W, PICTURE_H)
    b.picture:SetPoint("LEFT", 3, 0)
    b.name = b:CreateFontString(nil, "OVERLAY", "FieldGuideGameFontNormal")
    b.name:SetPoint("TOPLEFT", b.picture, "TOPRIGHT", 8, -2)
    b.name:SetPoint("RIGHT", -4, 0)
    b.name:SetJustifyH("LEFT"); b.name:SetWordWrap(false)
    b.line = b:CreateFontString(nil, "OVERLAY", "FieldGuideGameFontHighlightSmall")
    b.line:SetPoint("BOTTOMLEFT", b.picture, "BOTTOMRIGHT", 8, 3)
    b.line:SetPoint("RIGHT", -4, 0)
    b.line:SetJustifyH("LEFT"); b.line:SetWordWrap(false)
    b.line:SetTextColor(0.7, 0.74, 0.78)
    b:SetScript("OnClick", function(self)
        frame:Hide()
        if self.inst then ns.Instance:Start(self.inst) end
    end)
    rows[i] = b
    return b
end

local function Build()
    if frame then return end
    frame = CreateFrame("Frame", "FieldGuideDungeonPicker", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetWidth(WIDTH)
    frame:Hide()
    if frame.SetBackdrop then
        frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        frame:SetBackdropColor(0.04, 0.05, 0.06, 0.92)
        frame:SetBackdropBorderColor(1, 1, 1, 0.14)
        if WallyHUD and WallyHUD.Panel then WallyHUD.Panel(frame, "base") end
    end
    frame.title = frame:CreateFontString(nil, "OVERLAY", "FieldGuideGameFontHighlightSmall")
    frame.title:SetPoint("TOPLEFT", 9, -7)
    frame.title:SetTextColor(0.7, 0.74, 0.78)
    frame.title:SetText("Choose a dungeon to focus on")
    -- Esc, or a click anywhere else, closes it.
    tinsert(UISpecialFrames, "FieldGuideDungeonPicker")
    frame:RegisterEvent("GLOBAL_MOUSE_DOWN")
    frame:SetScript("OnEvent", function(self)
        -- (Region:IsMouseOver: this client has no global MouseIsOver.)
        if self:IsShown() and not self:IsMouseOver() and not (owner and owner:IsMouseOver()) then self:Hide() end
    end)
end

-- Fills the list; false when there's nothing to choose.
local function Fill()
    local list = ns.Instance:Current()
    for i, entry in ipairs(list) do
        local b, inst = Row(i), entry.inst
        b.inst = inst
        b.picture:SetTexture(Picture(inst))
        b.name:SetText(inst.name)
        b.line:SetText(("Levels %d-%d, %d quest%s"):format(inst.from, inst.to, #entry.open, #entry.open == 1 and "" or "s"))
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 6, -22 - (i - 1) * ROW)
        b:Show()
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    frame:SetHeight(28 + #list * ROW)
    return #list > 0
end

function P:Toggle(button)
    Build()
    if frame:IsShown() then frame:Hide(); return end
    if not Fill() then return end
    owner = button
    frame:ClearAllPoints()
    -- Beside the arrow; under the button when the arrow's too near the left of the screen for that.
    if (button:GetLeft() or 0) > WIDTH + 8 then
        frame:SetPoint("TOPRIGHT", button, "TOPLEFT", -4, 0)
    else
        frame:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -4)
    end
    frame:Show()
end

-- The button, after anything that changes which guide you're on or what's due (ns:Changed).
function P:Refresh()
    if not (ns.char and Waypoint and Waypoint.SetSide) then return end
    local inst = ns.char.instance and ns.Instance:Get(ns.char.instance)
    local list = ns.Instance:Current()
    local key
    if ns.char.paused or (not inst and #list == 0) then
        key = "none"
    elseif inst then
        key = "route:" .. inst.id
    else
        local ids = {}
        for i, entry in ipairs(list) do ids[i] = entry.inst.id .. "=" .. #entry.open end
        key = "pick:" .. table.concat(ids, ",")
    end
    if key == shownKey then return end
    shownKey = key
    if frame then
        if key:sub(1, 5) == "pick:" then
            if frame:IsShown() then Fill() end
        else
            frame:Hide()
        end
    end
    if key == "none" then
        Waypoint:SetSide("FieldGuide", nil)
    elseif inst then
        Waypoint:SetSide("FieldGuide", { icon = LEVELING, title = "Back to the leveling guide",
            text = ("You're on the route for %s. Click to go back to questing."):format(inst.name),
            onClick = function() ns.Instance:Stop() end })
    else
        Waypoint:SetSide("FieldGuide", { icon = DUNGEON, title = "Dungeon guide",
            text = ("%d dungeon%s with quests for you. Click to choose one."):format(#list, #list == 1 and "" or "s"),
            onClick = function(button) P:Toggle(button) end })
    end
end
