local _, ns = ...

-- The guide window: the section you're on and how far along, the step to do now (Waypoint's arrow
-- points at it), and the next few steps. Drag to move (/fg lock); Skip passes the current step.
local UI = {}
ns.UI = UI

local GREEN = { 0.56, 0.82, 0.42 }
local VERB_COLOR = {
    ["Pick up"] = "|cffffd100", ["Do"] = "|cffffffff", ["Turn in"] = "|cff8fd16a",
    ["Grind"] = "|cffd9a066", ["Travel"] = "|cff66bbff", ["Run"] = "|cffff8040", ["Loot"] = "|cffd9a066",
}
local PURPLE = { 0.78, 0.55, 1 }
local WIDTH = 300

local f

local function Text(parent, font, x, y, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", font)
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetWidth(width)
    fs:SetJustifyH("LEFT")
    return fs
end

-- Where the window sits: under Waypoint's arrow (ns.db.dock, /fg dock), or where you dragged it.
function UI:Dock()
    if not f then return end
    local canDock = ns.db.dock and Waypoint and Waypoint.Dock
    if canDock and f.dockedTo then return end
    if not canDock and not f.dockedTo and f:GetNumPoints() > 0 then return end
    if f.dockedTo and Waypoint and Waypoint.Undock then Waypoint:Undock(f) end
    -- Waypoint places it (left, center or right: the arrow's right-click menu, "Anchor").
    local arrow = canDock and Waypoint:Dock(f)
    f.dockedTo = arrow or nil
    if not arrow then
        f:ClearAllPoints()
        local pos = ns.db.window
        f:SetPoint(pos.point or "RIGHT", UIParent, pos.point or "RIGHT", pos.x or -40, pos.y or 60)
    end
end

local function Build()
    if f then return end
    f = CreateFrame("Frame", "FieldGuideFrame", UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, 120); f:SetFrameStrata("MEDIUM"); f:SetClampedToScreen(true)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    f:SetBackdropColor(0.03, 0.05, 0.04, 0.82)
    f:SetBackdropBorderColor(GREEN[1], GREEN[2], GREEN[3], 0.35)
    UI:Dock()
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    -- Docked under Waypoint's arrow: dragging the guide moves the arrow, and the guide follows.
    f:SetScript("OnDragStart", function(self)
        if f.dockedTo then
            local start = f.dockedTo:GetScript("OnDragStart")
            if start then start(f.dockedTo) end
        elseif not ns.db.locked then
            self:StartMoving()
        end
    end)
    f:SetScript("OnDragStop", function(self)
        if f.dockedTo then
            local stop = f.dockedTo:GetScript("OnDragStop")
            if stop then stop(f.dockedTo) end
            return
        end
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        ns.db.window = { point = point, x = x, y = y }
    end)

    local icon = f:CreateTexture(nil, "ARTWORK"); icon:SetSize(16, 16); icon:SetPoint("TOPLEFT", 6, -5)
    icon:SetTexture(ns.ICON)
    f.title = Text(f, "GameFontNormal", 26, -6, WIDTH - 90)
    f.title:SetTextColor(GREEN[1], GREEN[2], GREEN[3]); f.title:SetWordWrap(false)
    f.count = Text(f, "GameFontHighlightSmall", WIDTH - 90, -7, 60)
    f.count:SetJustifyH("RIGHT"); f.count:SetTextColor(0.65, 0.7, 0.68)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(20, 20); close:SetPoint("TOPRIGHT", 1, 1)
    close:SetScript("OnClick", function() ns.db.shown = false; ns:Changed() end)

    f.barBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.barBg:SetPoint("TOPLEFT", 6, -24); f.barBg:SetSize(WIDTH - 12, 3)
    f.barBg:SetColorTexture(1, 1, 1, 0.08)
    f.bar = f:CreateTexture(nil, "ARTWORK")
    f.bar:SetPoint("TOPLEFT", f.barBg); f.bar:SetHeight(3)
    f.bar:SetColorTexture(GREEN[1], GREEN[2], GREEN[3], 0.9)

    -- The step count (and the bar under it): click for the whole plan.
    local planButton = CreateFrame("Button", nil, f)
    planButton:SetPoint("TOPLEFT", f.count, "TOPLEFT", -4, 3); planButton:SetSize(66, 18)
    planButton:SetScript("OnClick", function() UI:TogglePlan() end)
    planButton:SetScript("OnEnter", function(self)
        f.count:SetTextColor(1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("The whole plan")
        GameTooltip:AddLine("Every step of this section, done and still to do.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    planButton:SetScript("OnLeave", function() f.count:SetTextColor(0.65, 0.7, 0.68); GameTooltip:Hide() end)

    f.step = Text(f, "GameFontHighlight", 8, -32, WIDTH - 16)
    -- Each line sits under the one above it, however many lines that one wraps to.
    f.detail = Text(f, "GameFontHighlightSmall", 8, -50, WIDTH - 16)
    f.detail:ClearAllPoints(); f.detail:SetPoint("TOPLEFT", f.step, "BOTTOMLEFT", 0, -4)
    f.detail:SetTextColor(0.78, 0.8, 0.78)
    f.next = Text(f, "GameFontHighlightSmall", 8, -80, WIDTH - 16)
    f.next:ClearAllPoints(); f.next:SetPoint("TOPLEFT", f.detail, "BOTTOMLEFT", 0, -8)
    f.next:SetTextColor(0.55, 0.58, 0.56); f.next:SetSpacing(2)

    f.skip = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.skip:SetSize(52, 18); f.skip:SetPoint("BOTTOMRIGHT", -6, 6); f.skip:SetText("Skip")
    f.skip:SetScript("OnClick", function() ns.Engine:SkipCurrent() end)
    f.skip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Skip this step")
        GameTooltip:AddLine("/fg unskip brings skipped steps back.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    f.skip:SetScript("OnLeave", GameTooltip_Hide)

    -- Bottom left: pause the arrow, and leave a dungeon's route for the leveling guide.
    f.pause = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.pause:SetSize(58, 18); f.pause:SetPoint("BOTTOMLEFT", 6, 6)
    f.pause:SetScript("OnClick", function() ns.Engine:SetPaused() end)
    f.pause:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(ns.char.paused and "Resume the arrow" or "Pause the arrow")
        GameTooltip:AddLine(ns.char.paused and "The guide points Waypoint's arrow at your current step again."
            or "The guide stops moving Waypoint's arrow (it goes back to Questie, your path or other addons). It still tracks your progress.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    f.pause:SetScript("OnLeave", GameTooltip_Hide)
    -- On a dungeon's route: "To Leveling" (purple, it leaves the dungeon plan). On the leveling
    -- guide: "To Dungeons", clickable when a dungeon in your range still has quests for you.
    f.questing = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.questing:SetSize(96, 18); f.questing:SetPoint("LEFT", f.pause, "RIGHT", 4, 0)
    f.questing:SetScript("OnClick", function()
        if ns.char.instance then
            ns.Instance:Stop()
        else
            ns.Instance:Resume()
        end
    end)
    f.questing:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if ns.char.instance then
            GameTooltip:AddLine("To the leveling guide")
            GameTooltip:AddLine("Leaves this dungeon's route. \"To Dungeons\" or the minimap button picks it up again.", 0.8, 0.8, 0.8, true)
        else
            local next = ns.Instance:Next()
            GameTooltip:AddLine("To a dungeon")
            GameTooltip:AddLine(next and ("Guides you to " .. next.name .. ": its quests, the run, the turn-ins.")
                or "No dungeon in your level range has quests left for you.", 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end)
    f.questing:SetScript("OnLeave", GameTooltip_Hide)

    f.done = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.done:SetSize(64, 18); f.done:SetPoint("RIGHT", f.skip, "LEFT", -4, 0); f.done:SetText("Done it")
    f.done:SetScript("OnClick", function() ns.Engine:MarkDone() end)
    f.done:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("I've already done this quest")
        GameTooltip:AddLine("Drops every step of it, here and in every guide, for when the game's record doesn't show it. /fg unskip brings it back.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    f.done:SetScript("OnLeave", GameTooltip_Hide)
end

local function Line(step)
    local verb, name = ns.Engine:Describe(step)
    return (VERB_COLOR[verb] or "") .. verb .. ":|r " .. name .. (step.catchup and "  |cffd9a066(missed earlier)|r" or "")
        .. (step.exit and "  |cff7fb8d9(next zone)|r" or "")
end

-- What's coming: the next unfinished steps (up to max), one a line, each with who it's with
-- ("Je'neu Sancrea: turn in Allegiance to the Old Gods (part 1)").
function UI:NextLines(from, max)
    local E = ns.Engine
    local lines = {}
    for i = (from or 0) + 1, #E.steps do
        if #lines >= max then break end
        local s = E.steps[i]
        if not E:StepDone(s) then
            local who = E:Who(s)
            if who then
                local verb, name = E:Describe(s)
                lines[#lines + 1] = ("|cffd9d9d9%s:|r %s%s|r %s"):format(who, VERB_COLOR[verb] or "", strlower(verb), name)
                    .. (s.catchup and "  |cffd9a066(missed earlier)|r" or "") .. (s.exit and "  |cff7fb8d9(next zone)|r" or "")
            else
                lines[#lines + 1] = Line(s)
            end
        end
    end
    return lines
end

local plan -- the whole-plan window (see below)

-- The window's color: purple on a dungeon's route, green on the leveling guide (the same as
-- Waypoint's arrow for its steps).
function UI:Theme()
    local col = ns.char.instance and PURPLE or GREEN
    if f.themed == col then return end
    f.themed = col
    f:SetBackdropBorderColor(col[1], col[2], col[3], 0.35)
    f.title:SetTextColor(col[1], col[2], col[3])
    f.bar:SetColorTexture(col[1], col[2], col[3], 0.9)
    if plan then
        plan:SetBackdropBorderColor(col[1], col[2], col[3], 0.45)
        plan.title:SetTextColor(col[1], col[2], col[3])
    end
end

function UI:SetQuestingButton()
    UI:Theme()
    local fs = f.questing:GetFontString()
    if ns.char.instance then
        f.questing:SetText("To Leveling")
        f.questing:Enable()
        if fs then fs:SetTextColor(GREEN[1], GREEN[2], GREEN[3]) end -- the color of where it leads
    else
        f.questing:SetText("To Dungeons")
        local next = ns.Instance:Next()
        f.questing:SetEnabled(next ~= nil)
        if fs then
            if next then fs:SetTextColor(PURPLE[1], PURPLE[2], PURPLE[3]) else fs:SetTextColor(0.5, 0.5, 0.5) end
        end
    end
    f.questing:Show()
end

-- ---------------------------------------------------------------------------------------------
-- The whole plan: every step of the section, ticked off as you go
-- ---------------------------------------------------------------------------------------------


local function BuildPlan()
    if plan then return end
    plan = CreateFrame("Frame", "FieldGuidePlanFrame", UIParent, "BackdropTemplate")
    plan:SetSize(360, 420); plan:SetFrameStrata("HIGH"); plan:SetClampedToScreen(true)
    plan:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    plan:SetBackdropColor(0.03, 0.05, 0.04, 0.94)
    plan:SetBackdropBorderColor(GREEN[1], GREEN[2], GREEN[3], 0.45)
    plan:SetPoint("TOPRIGHT", f, "TOPLEFT", -6, 0)
    plan:SetMovable(true); plan:EnableMouse(true); plan:RegisterForDrag("LeftButton")
    plan:SetScript("OnDragStart", plan.StartMoving); plan:SetScript("OnDragStop", plan.StopMovingOrSizing)
    plan.title = Text(plan, "GameFontNormal", 10, -8, 300)
    plan.title:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
    if f then f.themed = nil end -- recolor both on the next refresh
    local close = CreateFrame("Button", nil, plan, "UIPanelCloseButton")
    close:SetSize(20, 20); close:SetPoint("TOPRIGHT", 1, 1)
    close:SetScript("OnClick", function() plan:Hide() end)
    local scroll = CreateFrame("ScrollFrame", nil, plan, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -30); scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    local content = CreateFrame("Frame", nil, scroll); content:SetSize(320, 10)
    scroll:SetScrollChild(content)
    plan.text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    plan.text:SetPoint("TOPLEFT"); plan.text:SetWidth(318); plan.text:SetJustifyH("LEFT"); plan.text:SetSpacing(3)
    plan.content, plan.scroll = content, scroll
end

function UI:RefreshPlan()
    if not (plan and plan:IsShown()) then return end
    local E = ns.Engine
    local section = E.section
    if not section then
        plan.title:SetText("No section right now")
        plan.text:SetText("")
        return
    end
    local done, total = E:Progress()
    plan.title:SetText(("%s: %d of %d done"):format(section.title, done, total))
    local lines, n = {}, 0
    for i, s in ipairs(E.steps) do
        if E:Counts(s) or i == E.current or s[1] == "Z" then
        if s[1] ~= "Z" then n = n + 1 end
        local verb, name, detail = E:Describe(s)
        local mark
        if i == E.current then
            mark = "|cffffd100>|r "
        elseif s[1] ~= "Z" and E:StepDone(s) then
            mark = "|cff59f28cv|r "
        else
            mark = "   "
        end
        local text = ("%s%s%s"):format(mark, s[1] == "Z" and "" or (n .. ". "), Line(s))
        if s[1] ~= "Z" and E:StepDone(s) and i ~= E.current then
            text = ("%s|cff6b736e%d. %s: %s|r"):format(mark, n, verb, name)
        end
        lines[#lines + 1] = text
        if i == E.current and detail and detail ~= "" then
            lines[#lines + 1] = "      |cffa8b0a8" .. detail .. "|r"
        end
        end
    end
    plan.text:SetText(table.concat(lines, "\n"))
    plan.content:SetHeight(plan.text:GetStringHeight() + 8)
end

function UI:TogglePlan()
    Build()
    BuildPlan()
    UI:Theme()
    plan:SetShown(not plan:IsShown())
    self:RefreshPlan()
end

function UI:Refresh()
    if not ns.db then return end
    local E = ns.Engine
    if not ns.db.shown or not E.guide or E:HidesWhilePaused() then
        if f then f:Hide() end
        if plan then plan:Hide() end
        return
    end
    Build()
    UI:Dock()
    f:Show()
    local section = E.section
    if not section then
        f.title:SetText(E.guide.name .. " guide")
        f.count:SetText("")
        f.bar:SetWidth(0.001)
        f.step:SetText("No quests worth doing here at your level.")
        f.detail:SetText("Head to a zone for your level and its guide takes over. /fg list shows every section.")
        f.next:SetText("")
        f.skip:Hide(); f.done:Hide()
        f.pause:SetText(ns.char.paused and "Resume" or "Pause")
        UI:SetQuestingButton()
        f:SetHeight(84)
        UI:RefreshPlan()
        return
    end
    f.pause:SetText(ns.char.paused and "Resume" or "Pause")
    UI:SetQuestingButton()
    f.skip:Show()
    local cur = E.current and E.steps[E.current]
    f.done:SetShown(cur ~= nil and cur[1] ~= "G" and cur[1] ~= "Z" and cur[1] ~= "I")
    local done, total = E:Progress()
    f.title:SetText(("%s  |cff8a948e%d-%d|r"):format(section.title, section.from, section.to))
    f.count:SetText(("%d / %d"):format(done, total))
    f.bar:SetWidth(math.max(0.001, (WIDTH - 12) * (total > 0 and done / total or 0)))

    local step = E.current and E.steps[E.current]
    if not step then
        f.step:SetText("|cff8fd16aSection done.|r")
        f.detail:SetText("")
        f.next:SetText("")
        f:SetHeight(84)
        UI:RefreshPlan()
        return
    end
    local _, _, detail = E:Describe(step)
    f.step:SetText(Line(step))
    f.detail:SetText(detail or "")
    f.next:SetText(table.concat(UI:NextLines(E.current, ns.db.nextSteps), "\n"))
    local height = 32 + f.step:GetStringHeight() + 4 + f.detail:GetStringHeight() + 8 + f.next:GetStringHeight() + 30
    f:SetHeight(math.max(84, height))
    UI:RefreshPlan()
end
