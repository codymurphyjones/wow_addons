local addonName, ns = ...

-- ns.NewWizard(def): a short setup window of one-question steps, shown once, a few seconds after login.
--
--   ns.setup = ns.NewWizard({
--       name = "Wally",            -- shown in the header
--       store = function() ... end, -- the table that remembers it ran (default ns.db)
--       charStore = function() ... end, -- the same for one character (default ns.char)
--       needed = function() ... end, -- optional: false skips the automatic run; Open() still works
--       steps = { {
--           title = "...", text = "...",  -- text may be a function, read again after every click
--           path = "db.x.y",       -- an ns:SetOption path, or get = fn() and set = fn(value)
--           choices = { { value, "Label", "One line about it" }, ... }, -- or a function returning them
--           char = true,           -- belongs to one character: asked again on each new character
--           when = function() ... end, -- optional: leaves the step out while false
--           multi = true,          -- tick any number: get(value) says if it's on, set(value, on) changes it
--           demo = function(on) ... end, -- optional: shows the real thing while this step is up
--           low = true,            -- optional: the window moves down, out of the way of the demo
--       } },
--   })
--
-- A choice applies when clicked, so you see it work, and a step you pass keeps the value you have: old
-- saves see what they already use, and nothing changes unless it's clicked. Later (or Escape) asks
-- again next login; Skip setup and Done don't. wizard:Open() runs every step again.
--
-- Each addon has its own copy of this file. They take turns through one global queue, so several
-- addons at login open one after the other rather than on top of each other.

local queue = _G.SuiteSetupQueue or { waiting = {} }
_G.SuiteSetupQueue = queue

local WIDTH, PAD, ROW_H, TICK_H = 520, 18, 46, 28
local WHITE = "Interface\\Buttons\\WHITE8x8"
local FALLBACK = { bg = { 0.035, 0.045, 0.060 }, border = { 0.16, 0.24, 0.29 }, button = { 0.075, 0.105, 0.13 },
    hover = { 0.10, 0.19, 0.21 }, accent = { 0.33, 0.92, 0.78 }, muted = { 0.52, 0.64, 0.70 } }
local function PAL() return ns.Palette or FALLBACK end

local function Font(size)
    local own = addonName .. "GameFont" .. size
    return _G[own] and own or ("GameFont" .. size)
end

local function Pump()
    if queue.open or #queue.waiting == 0 then return end
    if InCombatLockdown() then return ns:AfterCombat("SetupWizard", Pump) end
    table.remove(queue.waiting, 1).Show()
end

local function Same(a, b) return a == b or (not a and not b) end

function ns.NewWizard(def)
    local wizard = {}
    local frame, current, scope, finished, demoing

    local function Store() return (def.store and def.store()) or ns.db end
    local function CharStore() return (def.charStore and def.charStore()) or ns.char end

    local function HasCharSteps()
        for _, step in ipairs(def.steps) do
            if step.char then return true end
        end
    end

    -- "all", "char" (only this character's steps: the rest were answered on another), or nil.
    function wizard:Pending()
        local store, charStore = Store(), CharStore()
        if store and not store.wizardDone then return "all" end
        if charStore and HasCharSteps() and not charStore.wizardDone then return "char" end
    end

    local function Visible()
        local list = {}
        for _, step in ipairs(def.steps) do
            if (scope == "all" or step.char) and (not step.when or step.when()) then list[#list + 1] = step end
        end
        return list
    end

    local function Position(list)
        for i, step in ipairs(list) do
            if step == current then return i end
        end
    end

    local function Get(step)
        if step.get then return step.get() end
        return ns:GetOption(step.path)
    end

    local function Set(step, value)
        if step.set then step.set(value) else ns:SetOption(step.path, value) end
    end

    local Render

    -- The current step's demo on, any other's off.
    local function Demo(step)
        if demoing == step then return end
        if demoing and demoing.demo then demoing.demo(false) end
        demoing = step
        if step and step.demo then step.demo(true) end
    end

    local function Finish()
        local store, charStore = Store(), CharStore()
        if store then store.wizardDone = true end
        if charStore then charStore.wizardDone = true end
        finished = true
        frame:Hide()
    end

    local function Paint(row, selected)
        local P = PAL()
        local fill = (selected or row:IsMouseOver()) and P.hover or P.button
        local edge = selected and P.accent or P.border
        row:SetBackdropColor(fill[1], fill[2], fill[3], 1)
        row:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
        row.mark:SetShown(selected)
        row.mark:SetColorTexture(P.accent[1], P.accent[2], P.accent[3], 1)
    end

    local function MakeRow(i)
        local row = CreateFrame("Button", nil, frame, "BackdropTemplate")
        row:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        row:SetSize(WIDTH - PAD * 2, ROW_H)
        row.mark = row:CreateTexture(nil, "OVERLAY")
        row.mark:SetPoint("TOPLEFT", 1, -1)
        row.mark:SetPoint("BOTTOMLEFT", 1, 1)
        row.mark:SetWidth(4)
        row.label = row:CreateFontString(nil, "OVERLAY", Font("Highlight"))
        row.label:SetJustifyH("LEFT")
        row.desc = row:CreateFontString(nil, "OVERLAY", Font("HighlightSmall"))
        row.desc:SetJustifyH("LEFT")
        row:SetScript("OnEnter", function(self) Paint(self, self.selected) end)
        row:SetScript("OnLeave", function(self) Paint(self, self.selected) end)
        row:SetScript("OnClick", function(self)
            if current.multi then
                current.set(self.value, not self.selected)
            else
                Set(current, self.value)
            end
            Render()
        end)
        frame.rows[i] = row
        return row
    end

    local function Build()
        local P = PAL()
        frame = CreateFrame("Frame", addonName .. "SetupWizard", UIParent, "BackdropTemplate")
        frame:SetWidth(WIDTH)
        frame:SetPoint("CENTER", 0, 80)
        frame:SetFrameStrata("FULLSCREEN_DIALOG")
        frame:SetToplevel(true)
        frame:SetClampedToScreen(true)
        frame:EnableMouse(true)
        frame:SetMovable(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        frame:SetBackdropColor(P.bg[1], P.bg[2], P.bg[3], 0.98)
        frame:SetBackdropBorderColor(P.border[1], P.border[2], P.border[3], 1)
        frame:Hide()
        tinsert(UISpecialFrames, addonName .. "SetupWizard") -- Escape counts as Later
        frame.rows = {}

        frame.header = frame:CreateFontString(nil, "OVERLAY", Font("HighlightSmall"))
        frame.header:SetPoint("TOPLEFT", PAD, -14)
        frame.header:SetTextColor(P.muted[1], P.muted[2], P.muted[3])
        frame.title = frame:CreateFontString(nil, "OVERLAY", Font("NormalLarge"))
        frame.title:SetPoint("TOPLEFT", frame.header, "BOTTOMLEFT", 0, -8)
        frame.title:SetPoint("RIGHT", -PAD, 0)
        frame.title:SetJustifyH("LEFT")
        frame.title:SetTextColor(P.accent[1], P.accent[2], P.accent[3])
        frame.text = frame:CreateFontString(nil, "OVERLAY", Font("Highlight"))
        frame.text:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -8)
        frame.text:SetPoint("RIGHT", -PAD, 0)
        frame.text:SetJustifyH("LEFT")
        frame.text:SetJustifyV("TOP")

        local function Button(text, width, click)
            local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
            b:SetSize(width, 24)
            b:SetText(text)
            b:SetScript("OnClick", click)
            return b
        end
        frame.later = Button("Later", 72, function() frame:Hide() end)
        frame.later:SetPoint("BOTTOMLEFT", PAD, 14)
        frame.skip = Button("Skip setup", 96, Finish)
        frame.skip:SetPoint("LEFT", frame.later, "RIGHT", 6, 0)
        frame.next = Button("Next", 84, function()
            local list = Visible()
            local nextStep = list[(Position(list) or 0) + 1]
            if nextStep then
                current = nextStep
                Render()
            else
                Finish()
            end
        end)
        frame.next:SetPoint("BOTTOMRIGHT", -PAD, 14)
        frame.back = Button("Back", 72, function()
            local list = Visible()
            current = list[(Position(list) or 2) - 1] or list[1]
            Render()
        end)
        frame.back:SetPoint("RIGHT", frame.next, "LEFT", -6, 0)

        frame:SetScript("OnHide", function()
            Demo(nil)
            if queue.open == wizard then queue.open = nil end
            if not finished then wipe(queue.waiting) end -- Later: the rest wait for the next login too
            Pump()
        end)
    end

    Render = function()
        local list = Visible()
        local pos = Position(list)
        if not pos then -- an answer took this step out
            current = list[1]
            pos = 1
        end
        if not current then return Finish() end
        Demo(current)
        if frame.low ~= (current.low or false) then
            frame.low = current.low or false
            frame:ClearAllPoints()
            if frame.low then frame:SetPoint("BOTTOM", 0, 40) else frame:SetPoint("CENTER", 0, 80) end
        end
        frame.header:SetText(("%s setup  ·  step %d of %d"):format(def.name, pos, #list))
        frame.title:SetText(current.title)
        local text = current.text
        frame.text:SetText((type(text) == "function" and text() or text) or "")
        local top = 14 + 12 + 8 + 16 + 8 + frame.text:GetStringHeight() + 12
        local value = not current.multi and Get(current)
        local height = current.multi and TICK_H or ROW_H
        local choices = type(current.choices) == "function" and current.choices() or current.choices
        for i, choice in ipairs(choices) do
            local row = frame.rows[i] or MakeRow(i)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", PAD, -top - (i - 1) * (height + (current.multi and 3 or 6)))
            row:SetHeight(height)
            row.label:ClearAllPoints()
            row.desc:ClearAllPoints()
            if current.multi then -- one line: the name, then what it's for
                row.label:SetPoint("LEFT", 14, 0)
                row.desc:SetPoint("LEFT", 140, 0)
            else
                row.label:SetPoint("TOPLEFT", 14, -8)
                row.label:SetPoint("RIGHT", -10, 0)
                row.desc:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -3)
            end
            row.desc:SetPoint("RIGHT", -10, 0)
            row.value = choice[1]
            if current.multi then
                row.selected = current.get(choice[1]) and true or false
            else
                row.selected = Same(choice[1], value)
            end
            row.label:SetText(choice[2])
            row.desc:SetText(choice[3] or "")
            row:Show()
            Paint(row, row.selected)
        end
        for i = #choices + 1, #frame.rows do frame.rows[i]:Hide() end
        frame:SetHeight(top + #choices * (height + (current.multi and 3 or 6)) + 48)
        frame.back:SetEnabled(pos > 1)
        frame.next:SetText(pos == #list and "Done" or "Next")
    end

    local function Show(mode)
        if not frame then Build() end
        scope, finished = mode, false
        current = Visible()[1]
        if not current then return Pump() end -- nothing to ask: the next login checks again
        queue.open = wizard
        Render()
        frame:Show()
    end

    -- Every step, now (the settings page's button and slash commands).
    function wizard:Open()
        if queue.open then return end
        Show("all")
    end

    ns:On("PLAYER_ENTERING_WORLD", function()
        if wizard.started then return end
        wizard.started = true
        C_Timer.After(def.delay or 4, function()
            local mode = wizard:Pending()
            if not mode or (def.needed and not def.needed()) then return end
            table.insert(queue.waiting, { Show = function() Show(mode) end })
            Pump()
        end)
    end)

    return wizard
end
