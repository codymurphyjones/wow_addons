local _, ns = ...

-- The guide list: a small button above the top-left corner of Waypoint's arrow (Waypoint:SetSide's
-- slot 3). It opens a list of guides you could follow from where you are:
--   - the best plan (what the guide picks by itself),
--   - the zones with the most to do for you, each planned as if you followed it (its task areas first),
--   - the dungeons that have quests for you.
-- Each row shows the XP an hour it pays, how long the rest of this level takes at that rate (less the
-- XP of quests you're carrying ready to hand in), and how long one more level takes on top of that.
-- Click a row and the guide follows it from where you stand: the arrow leads to its first step.
-- The rates are the planner's own (Tasks.lua's Options, Engine.lua's DungeonRate): estimates.
local G = {}
ns.GuidePicker = G

local MEDIA = "Interface\\AddOns\\FieldGuide\\Media\\"
local ICON = MEDIA .. "Field\\xp"
local WIDTH, ROW = 340, 38

local frame, owner
local rows = {}
local shownKey

local function L() return ns.Engine and ns.Engine.lib end

local function Number(n)
    n = math.floor((n or 0) + 0.5)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

local function Duration(minutes)
    if not minutes or minutes ~= minutes or minutes == math.huge then return "?" end
    minutes = math.max(1, math.floor(minutes + 0.5))
    if minutes < 60 then return minutes .. " min" end
    local h, m = math.floor(minutes / 60), minutes % 60
    if h >= 48 then return ("%d h"):format(h) end
    return m > 0 and ("%d h %d min"):format(h, m) or ("%d h"):format(h)
end

-- XP to finish this level (less what you carry ready to hand in) and the XP of the level after it.
local function Needs()
    local lib, level = L(), ns.Progress:Level()
    if not lib or level >= 60 then return nil, nil, level end
    local ready = lib.ReadyXP() or 0
    local rest = math.max(0, lib.XPToReach(level + 1) - ready)
    local more = level < 59 and (lib.XPToReach(level + 2) - lib.XPToReach(level + 1)) or nil
    return rest, more, level
end

-- The figures line for a rate in XP a minute.
local function Figures(rate)
    if not rate or rate <= 0 then return "|cff808080nothing to do there yet|r" end
    local rest, more, level = Needs()
    local line = ("~%s XP/h"):format(Number(rate * 60))
    if rest then
        line = line .. ("  ·  %d in %s"):format(level + 1, Duration(rest / rate))
        if more then line = line .. ("  ·  %d in +%s"):format(level + 2, Duration(more / rate)) end
    end
    return line
end

local function Row(i)
    local b = rows[i]
    if b then return b end
    b = CreateFrame("Button", nil, frame)
    b:SetSize(WIDTH - 12, ROW)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.name = b:CreateFontString(nil, "OVERLAY", "FieldGuideGameFontNormal")
    b.name:SetPoint("TOPLEFT", 6, -3)
    b.name:SetPoint("RIGHT", -6, 0)
    b.name:SetJustifyH("LEFT"); b.name:SetWordWrap(false)
    b.line = b:CreateFontString(nil, "OVERLAY", "FieldGuideGameFontHighlightSmall")
    b.line:SetPoint("BOTTOMLEFT", 6, 4)
    b.line:SetPoint("RIGHT", -6, 0)
    b.line:SetJustifyH("LEFT"); b.line:SetWordWrap(false)
    b.line:SetTextColor(0.7, 0.74, 0.78)
    b:SetScript("OnClick", function(self)
        frame:Hide()
        if self.option then G:Follow(self.option) end
    end)
    b:SetScript("OnEnter", function(self)
        local o = self.option
        if not o then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.name:GetText())
        if o.kind == "best" then
            GameTooltip:AddLine("What the guide picks by itself: the task areas that pay the most XP a minute from where you are, travel included.", 1, 1, 1, true)
        elseif o.kind == "zone" then
            GameTooltip:AddLine(("This zone's work first, as long as it has any for you, then the best plan again. Levels %d-%d."):format(o.lo, o.hi), 1, 1, 1, true)
        else
            GameTooltip:AddLine("The dungeon guide: pick up its quests, run it, then turn them in.", 1, 1, 1, true)
        end
        GameTooltip:AddLine("Rates are estimates from the quest data. Click to follow it from here.", 0.7, 0.74, 0.78, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    rows[i] = b
    return b
end

local function Build()
    if frame then return end
    frame = CreateFrame("Frame", "FieldGuideGuidePicker", UIParent, "BackdropTemplate")
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
    frame.title:SetPoint("RIGHT", -9, 0)
    frame.title:SetJustifyH("LEFT")
    frame.title:SetTextColor(0.7, 0.74, 0.78)
    frame.status = frame:CreateFontString(nil, "OVERLAY", "FieldGuideGameFontHighlightSmall")
    frame.status:SetPoint("TOPLEFT", 9, -26)
    frame.status:SetTextColor(0.7, 0.74, 0.78)
    -- Esc, or a click anywhere else, closes it.
    tinsert(UISpecialFrames, "FieldGuideGuidePicker")
    frame:RegisterEvent("GLOBAL_MOUSE_DOWN")
    frame:SetScript("OnEvent", function(self)
        if self:IsShown() and not self:IsMouseOver() and not (owner and owner:IsMouseOver()) then self:Hide() end
    end)
end

local function Title()
    local rest, _, level = Needs()
    if not rest then return "Choose a guide" end
    return ("Choose a guide  ·  %s XP to level %d"):format(Number(rest), level + 1)
end

-- The rows: the planner's options, then the dungeons with quests for you.
local function Fill(options)
    local list = {}
    for _, o in ipairs(options or {}) do
        if o.kind == "best" or (o.rate or 0) > 0 then list[#list + 1] = o end
    end
    for _, entry in ipairs(ns.Instance and ns.Instance:Current() or {}) do
        local rate = ns.Engine:DungeonRate(entry)
        list[#list + 1] = { kind = "dungeon", inst = entry.inst, name = entry.inst.name, rate = rate,
            quests = #entry.open, current = ns.char.instance == entry.inst.id }
    end
    local onRoute = ns.char.instance ~= nil
    for i, o in ipairs(list) do
        local b = Row(i)
        b.option = o
        local name
        if o.kind == "best" then
            name = "Best plan" .. (o.zones and o.zones ~= "" and ("  |cff9d9d9d" .. o.zones .. "|r") or "")
        elseif o.kind == "zone" then
            name = ("%s  |cff9d9d9dlevels %d-%d|r"):format(o.name, o.lo, o.hi)
        else
            name = ("Dungeon: %s  |cff9d9d9d%d quest%s|r"):format(o.name, o.quests, o.quests == 1 and "" or "s")
        end
        local following = o.current and (o.kind == "dungeon" or not onRoute) and not ns.char.paused
        b.name:SetText((following and "|cff66dd66> |r" or "") .. name)
        b.line:SetText(Figures(o.rate))
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 6, -24 - (i - 1) * ROW)
        b:Show()
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    frame.status:SetShown(#list == 0)
    frame.status:SetText("Nothing to choose from here.")
    frame:SetHeight(32 + math.max(1, #list) * ROW)
end

function G:Toggle(button)
    Build()
    if frame:IsShown() then frame:Hide(); return end
    owner = button
    frame.title:SetText(Title())
    for _, r in ipairs(rows) do r:Hide() end
    frame.status:SetText("Working out the rates...")
    frame.status:Show()
    frame:SetHeight(52)
    frame:ClearAllPoints()
    -- Beside the arrow; under the button when the arrow's too near the left of the screen for that.
    if (button:GetLeft() or 0) > WIDTH + 8 then
        frame:SetPoint("TOPRIGHT", button, "TOPLEFT", -4, 0)
    else
        frame:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -4)
    end
    frame:Show()
    ns.Tasks:Options(function(options)
        if frame:IsShown() then Fill(options) end
    end)
end

-- Follow an option from the list.
function G:Follow(o)
    local E = ns.Engine
    if o.kind == "dungeon" then
        ns.Instance:Start(o.inst)
        if ns.char.paused then E:SetPaused(false) end
        return
    end
    -- A leveling guide: off a dungeon's route, a section you picked, a zone you stayed in, and Zone Clear.
    if ns.char.instance then ns.Instance:Stop(true) end
    ns.char.section, ns.char.zoneLock = nil, nil
    if ns.char.preference == "clear" then E:SetPreference("leveling") end
    ns.Tasks:Follow(o.kind == "zone" and o.map or nil)
    E:Invalidate()
    ns:Print(o.kind == "zone" and ("Following %s: the arrow leads you to its first step."):format(o.name)
        or "Following the best plan: the arrow leads you to its first step.")
    E:FollowFromHere()
end

-- The button, after anything that changes which guide you're on (ns:Changed).
function G:Refresh()
    if not (ns.char and Waypoint and Waypoint.SetSide) then return end
    local zone = ns.char.guideZone
    local info = zone and C_Map.GetMapInfo(zone)
    local key = tostring(zone)
    if key == shownKey then return end
    shownKey = key
    Waypoint:SetSide("FieldGuide", { icon = ICON, title = "Choose a guide",
        text = (info and ("Following %s. "):format(info.name) or "")
            .. "Click for the guides you could follow from here: XP an hour, and how long this level and the next take.",
        onClick = function(button) G:Toggle(button) end }, 3)
end
