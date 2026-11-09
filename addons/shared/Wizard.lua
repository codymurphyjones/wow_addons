local addonName, ns = ...

-- ns.NewWizard(def): an addon's setup questions, one a step, asked once a few seconds after login.
--
--   ns.setup = ns.NewWizard({
--       name = "Wally",            -- shown in the title bar and on its section tab
--       icon = "Interface\\...",   -- optional: the title bar's icon (default the TOC's ## IconTexture)
--       store = function() ... end, -- the table that remembers it ran (default ns.db)
--       charStore = function() ... end, -- the same for one character (default ns.char)
--       needed = function() ... end, -- optional: false skips the automatic run; Open() still works
--       own = { is = fn, set = fn(on) }, -- optional: how this character gets its own settings (an
--                                  -- addon with profiles); default ns.SAVED.own (shared Core.lua)
--       delay = 4,                 -- optional: seconds after login before it asks
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
-- There is only ever one setup window. Every addon's wizard is a section in it: the first to ask opens
-- the window, and the rest join its list, one tab each. Next and Back run through the sections in
-- order, and a tab jumps to one. Passing a section's last step (or Skip section) marks that addon done.
-- Later (or Escape) closes the whole window: the addons not done ask again next login, and none of
-- the others still waiting this session interrupt again. Done on the last step closes it too.
--
-- Account or character: an addon whose settings a character can own (own, or ns.SAVED.own) asks a
-- character on its first login, and every character while the account has no answers, one question
-- before its section: "Use account defaults" or "Set character options" (no account answers yet:
-- "Configure account defaults" or "Set character options only"). One answer covers every such addon.
-- Account: with account answers, only the char steps; without, every step, and they become them.
-- Character: every step, kept in this character's own copy; the account's answers stay as they were.
--
-- wizard:Open() (the settings page's button, slash commands) asks every step of that addon: it opens
-- the window with just that section, or, while the window is up, adds the section and jumps to it.
--
-- A choice applies when clicked, so you see it work, and a step you pass keeps the value you have: old
-- saves see what they already use, and nothing changes unless it's clicked.
--
-- One look for every addon, WallyHUD's: its face (Roboto Condensed), tokens and rules (hairline edges,
-- the one accent only for what's selected or active, underline tabs, labels in capitals). Without
-- WallyHUD, or with its shared look off, the same layout in the game's fonts and the suite's default
-- colours. The title bar's icon and name say which addon the current section belongs to.
--
-- Each addon loads its own copy of this file. The newest copy builds the one window (_G.SuiteSetup) and
-- every wizard reaches it through that global when it asks, after login, when all copies have loaded.

local VERSION = 4

local WIDTH, PAD, ROW_H, TICK_H, TAB_H, ICON, BUTTON_H = 520, 18, 46, 28, 22, 28, 24
local BAR_H = 12 + ICON + 10 -- the title bar, down to its rule
local WHITE = "Interface\\Buttons\\WHITE8x8"
local DONE_ICON = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t "

-- The colours without WallyHUD (the suite's default palette, shared\Palette.lua).
local DEFAULT = {
    bg = { 0.035, 0.045, 0.060 }, border = { 0.16, 0.24, 0.29 }, edgeHot = { 0.28, 0.38, 0.44 },
    button = { 0.075, 0.105, 0.13 }, hover = { 0.10, 0.19, 0.21 }, accent = { 0.33, 0.92, 0.78 },
    text = { 0.93, 0.95, 0.96 }, muted = { 0.52, 0.64, 0.70 }, faint = { 0.34, 0.42, 0.46 },
}

-- Each text role: the game font it stands for without WallyHUD, and its size and weight in WallyHUD's face.
local FONTS = {
    name = { "GameFontNormalLarge", 16, "semibold" },  -- the addon, in the title bar
    title = { "GameFontNormalLarge", 14, "semibold" }, -- the step's question
    body = { "GameFontHighlight", 12, "medium" },      -- the step's text, buttons
    choice = { "GameFontHighlight", 13, "medium" },    -- a choice's name
    small = { "GameFontHighlightSmall", 11, "medium" }, -- a choice's line about it
    label = { "GameFontHighlightSmall", 11, "medium" }, -- header and tabs, in capitals
}

local function Same(a, b) return a == b or (not a and not b) end

-- The window ----------------------------------------------------------------------------------------

if not _G.SuiteSetup or (_G.SuiteSetup.version or 0) < VERSION then
    local host = { version = VERSION, sections = {}, index = 0 }
    _G.SuiteSetup = host
    local frame, step, demoing, look, fonts

    -- WallyHUD's colours and face when it's there with its shared look on (read once, at the first
    -- show: WallyHUD loads after every addon), else DEFAULT and the game's fonts.
    local function Look()
        local hud = _G.WallyHUD
        local T, M = hud and hud.Tokens, hud and hud.PaletteColors
        if not (T and M and hud.SuiteFace and hud.SuiteFace("medium")) then return DEFAULT end
        return {
            bg = M.bg, border = T.edge, edgeHot = T.edgeStrong, button = M.button, hover = M.hover,
            accent = T.accent, text = T.text.primary, muted = T.muted, faint = T.faint,
            Face = hud.Face, shadow = T.fontShadow,
        }
    end

    local function MakeFonts()
        fonts = {}
        for role, f in pairs(FONTS) do
            local font = CreateFont("SuiteSetupFont_" .. role)
            if _G[f[1]] then font:CopyFontObject(_G[f[1]]) end
            if look.Face then
                font:SetFont(look.Face(f[3]), f[2], "")
                font:SetShadowColor(look.shadow[1], look.shadow[2], look.shadow[3], look.shadow[4] or 1)
                font:SetShadowOffset(1, -1)
            end
            fonts[role] = font
        end
    end

    local function Text(parent, role, color, layer)
        local fs = parent:CreateFontString(nil, layer or "OVERLAY")
        fs:SetFontObject(fonts[role])
        fs:SetTextColor(color[1], color[2], color[3], 1)
        return fs
    end

    local function Box(parent)
        local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
        b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        return b
    end

    -- { wizard = , scope = "all" or "char" (only this character's steps), done = true once passed,
    --   ask = the opening question decides (hadDefaults: the account's answers existed when it joined) }
    local function Section() return host.sections[host.index] end

    -- An asking section under "account": with account answers, only this character's steps.
    local function Scope(section)
        if section.ask and host.mode == "account" and section.hadDefaults then return "char" end
        return section.scope
    end
    local function Steps(section) return section.wizard:Steps(Scope(section)) end

    local function Position(list, wanted)
        for i, s in ipairs(list) do
            if s == wanted then return i end
        end
    end

    local function Complete(section)
        if section.done then return end
        section.done = true
        section.wizard:MarkDone()
    end

    -- The opening question, as a section of its own, first in the list: does this character use the
    -- account's settings or its own? The answer covers every asking section, those that join later too.
    local function AllHaveDefaults()
        for _, section in ipairs(host.sections) do
            if section.ask and not section.hadDefaults then return false end
        end
        return true
    end

    local intro = { name = "This character", icon = "Interface\\Icons\\INV_Misc_Book_09", intro = true }
    intro.step = {
        title = "Settings for this character",
        required = true,
        text = function()
            if AllHaveDefaults() then
                return "Your other characters already share a set of settings. Use them here too, or give this character its own?"
            end
            return "Answers you give here can become the settings every character shares, or stay with this character only."
        end,
        choices = function()
            if AllHaveDefaults() then
                return {
                    { "account", "Use account defaults", "Only the questions about this character. Change a setting later and every character on the account follows." },
                    { "character", "Set character options", "Every question, answered for this character only. Your other characters keep the account's settings." },
                }
            end
            return {
                { "account", "Configure account defaults", "Your answers become the settings for every character that doesn't have its own." },
                { "character", "Set character options only", "Your answers stay with this character. The next new character is asked again." },
            }
        end,
    }
    function intro:Steps() return { intro.step } end
    function intro:Get() return host.mode end
    function intro:Set(_, value)
        host.mode = value
        for _, section in ipairs(host.sections) do
            if section.ask then section.wizard:SetOwn(value == "character") end
        end
    end
    -- Leaving the question: it leaves the list (it isn't asked twice), and so do the sections it left
    -- with nothing to ask, done.
    function intro:MarkDone()
        for i = #host.sections, 1, -1 do
            local section = host.sections[i]
            if section.wizard == intro then
                table.remove(host.sections, i)
            elseif section.ask and not Steps(section)[1] then
                Complete(section)
                table.remove(host.sections, i)
            end
        end
    end

    local function IntroIndex()
        for i, section in ipairs(host.sections) do
            if section.wizard == intro then return i end
        end
    end

    -- The current step's demo on, any other's off.
    local function Demo(s)
        if demoing == s then return end
        if demoing and demoing.demo then demoing.demo(false) end
        demoing = s
        if s and s.demo then s.demo(true) end
    end

    -- The section and step one place forward (dir 1) or back (-1) from here, across sections; nil at the end.
    local function Neighbour(dir)
        local i = host.index
        local list = Steps(host.sections[i])
        local pos = (Position(list, step) or 0) + dir
        while true do
            if list[pos] then return i, list[pos] end
            i = i + dir
            local section = host.sections[i]
            if not section then return end
            list = Steps(section)
            pos = dir > 0 and 1 or #list
        end
    end

    local Render

    -- Painting: hairline edges at rest, the strong one under the mouse, the accent only when selected.

    local function PaintRow(row)
        local hot = row:IsMouseOver()
        local fill = (row.selected or hot) and look.hover or look.button
        local edge = row.selected and look.accent or hot and look.edgeHot or look.border
        row:SetBackdropColor(fill[1], fill[2], fill[3], 1)
        row:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
        row.mark:SetShown(row.selected)
    end

    local function PaintButton(b)
        local on = b:IsEnabled()
        local hot = on and b:IsMouseOver()
        local fill, edge = hot and look.hover or look.button, hot and look.edgeHot or look.border
        local text = on and look.text or look.faint
        b:SetBackdropColor(fill[1], fill[2], fill[3], 1)
        b:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
        b.label:SetTextColor(text[1], text[2], text[3], 1)
    end

    local function PaintTab(tab)
        local lit = tab.selected or tab:IsMouseOver()
        local text = lit and look.text or look.muted
        tab.label:SetTextColor(text[1], text[2], text[3], 1)
        tab.underline:SetShown(tab.selected)
    end

    local function MakeRow(i)
        local row = Box(frame)
        row:SetSize(WIDTH - PAD * 2, ROW_H)
        row.mark = row:CreateTexture(nil, "OVERLAY")
        row.mark:SetPoint("TOPLEFT", 1, -1)
        row.mark:SetPoint("BOTTOMLEFT", 1, 1)
        row.mark:SetWidth(3)
        row.mark:SetColorTexture(look.accent[1], look.accent[2], look.accent[3], 1)
        row.label = Text(row, "choice", look.text)
        row.label:SetJustifyH("LEFT")
        row.desc = Text(row, "small", look.muted)
        row.desc:SetJustifyH("LEFT")
        row:SetScript("OnEnter", PaintRow)
        row:SetScript("OnLeave", PaintRow)
        row:SetScript("OnClick", function(self)
            if step.multi then
                step.set(self.value, not self.selected)
            else
                Section().wizard:Set(step, self.value)
            end
            Render()
        end)
        frame.rows[i] = row
        return row
    end

    -- Underline tabs: no fill or edge, the name in capitals, the active one with a 2px accent underline.
    local function MakeTab(i)
        local tab = CreateFrame("Button", nil, frame)
        tab:SetHeight(TAB_H)
        tab.label = Text(tab, "label", look.muted)
        tab.label:SetPoint("CENTER", 0, 1)
        tab.underline = tab:CreateTexture(nil, "OVERLAY")
        tab.underline:SetColorTexture(look.accent[1], look.accent[2], look.accent[3], 1)
        tab.underline:SetHeight(2)
        tab.underline:SetPoint("BOTTOMLEFT", 4, 0)
        tab.underline:SetPoint("BOTTOMRIGHT", -4, 0)
        tab:SetScript("OnEnter", PaintTab)
        tab:SetScript("OnLeave", PaintTab)
        tab:SetScript("OnClick", function()
            local to, section = i, host.sections[i]
            if section and section.ask and not host.mode then to = IntroIndex() or i end -- answer that first
            if host.index == to then return end
            host.index, step = to, nil
            Render()
        end)
        frame.tabs[i] = tab
        return tab
    end

    -- Every way the window closes (Later, Escape, Done, Skip on the last section) ends here.
    local function Closed()
        Demo(nil)
        for _, section in ipairs(host.sections) do
            if not section.done then host.later = true end -- the rest wait for the next login
        end
        wipe(host.sections)
        host.index, step, host.mode = 0, nil, nil
    end

    local function Build()
        look = Look()
        MakeFonts()

        frame = CreateFrame("Frame", "SuiteSetupWizard", UIParent, "BackdropTemplate")
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
        frame:SetBackdropColor(look.bg[1], look.bg[2], look.bg[3], 0.97)
        frame:SetBackdropBorderColor(look.border[1], look.border[2], look.border[3], 1)
        frame:Hide()
        tinsert(UISpecialFrames, "SuiteSetupWizard") -- Escape counts as Later
        frame.rows, frame.tabs = {}, {}

        -- Title bar: which addon this is, and how far through it you are.
        frame.icon = frame:CreateTexture(nil, "ARTWORK")
        frame.icon:SetSize(ICON, ICON)
        frame.icon:SetPoint("TOPLEFT", PAD, -12)
        frame.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        frame.name = Text(frame, "name", look.text)
        frame.name:SetPoint("LEFT", frame.icon, "RIGHT", 10, 0)
        frame.header = Text(frame, "label", look.muted)
        frame.header:SetPoint("RIGHT", frame, "TOPRIGHT", -PAD, -12 - ICON / 2)
        local rule = frame:CreateTexture(nil, "ARTWORK")
        rule:SetColorTexture(look.border[1], look.border[2], look.border[3], 1)
        rule:SetHeight(1)
        rule:SetPoint("TOPLEFT", 1, -BAR_H)
        rule:SetPoint("TOPRIGHT", -1, -BAR_H)

        frame.title = Text(frame, "title", look.text)
        frame.title:SetJustifyH("LEFT")
        frame.text = Text(frame, "body", look.muted)
        frame.text:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -8)
        frame.text:SetPoint("RIGHT", -PAD, 0)
        frame.text:SetJustifyH("LEFT")
        frame.text:SetJustifyV("TOP")

        local function Button(text, width, click)
            local b = Box(frame)
            b:SetSize(width, BUTTON_H)
            b.label = Text(b, "body", look.text)
            b.label:SetPoint("CENTER")
            b.label:SetText(text)
            b:SetScript("OnClick", click)
            b:SetScript("OnEnter", PaintButton)
            b:SetScript("OnLeave", PaintButton)
            b:SetScript("OnEnable", PaintButton)
            b:SetScript("OnDisable", PaintButton)
            PaintButton(b)
            return b
        end
        frame.later = Button("Later", 72, function() frame:Hide() end)
        frame.later:SetPoint("BOTTOMLEFT", PAD, 14)
        frame.skip = Button("Skip setup", 104, function()
            Complete(Section())
            for i = host.index + 1, #host.sections do
                local first = Steps(host.sections[i])[1]
                if first then
                    host.index, step = i, first
                    return Render()
                end
            end
            frame:Hide()
        end)
        frame.skip:SetPoint("LEFT", frame.later, "RIGHT", 6, 0)
        frame.next = Button("Next", 84, function()
            local i, nextStep = Neighbour(1)
            local target = host.sections[i]
            if i ~= host.index then Complete(Section()) end -- passed this section's last step
            if not nextStep then return frame:Hide() end
            host.index, step = Position(host.sections, target), nextStep -- (completing may drop sections)
            Render()
        end)
        frame.next:SetPoint("BOTTOMRIGHT", -PAD, 14)
        frame.back = Button("Back", 72, function()
            local i, prevStep = Neighbour(-1)
            if not prevStep then return end
            host.index, step = i, prevStep
            Render()
        end)
        frame.back:SetPoint("RIGHT", frame.next, "LEFT", -6, 0)

        frame:SetScript("OnHide", function(self)
            if self:IsShown() then return end -- only the UI hid (Alt-Z, a cinematic): it comes back as it was
            Closed()
        end)
    end

    -- The section tabs, wrapped to fit; returns how far down the title starts.
    local function LayoutTabs()
        local y = BAR_H + 12
        if #host.sections < 2 then
            for _, tab in ipairs(frame.tabs) do tab:Hide() end
            return y
        end
        local x, rowTop = PAD - 8, y - 4
        for i, section in ipairs(host.sections) do
            local tab = frame.tabs[i] or MakeTab(i)
            tab.label:SetText((section.done and DONE_ICON or "") .. section.wizard.name:upper())
            local width = math.ceil(tab.label:GetStringWidth()) + 16
            if x > PAD - 8 and x + width > WIDTH - PAD + 8 then
                x, rowTop = PAD - 8, rowTop + TAB_H + 2
            end
            tab:ClearAllPoints()
            tab:SetPoint("TOPLEFT", x, -rowTop)
            tab:SetWidth(width)
            tab.selected = i == host.index
            tab:Show()
            PaintTab(tab)
            x = x + width + 4
        end
        for i = #host.sections + 1, #frame.tabs do frame.tabs[i]:Hide() end
        return rowTop + TAB_H + 12
    end

    Render = function()
        local section = Section()
        if not section then return frame:Hide() end
        local list = Steps(section)
        local pos = Position(list, step)
        if not pos then -- just arrived, or an answer took this step out
            step, pos = list[1], 1
        end
        if not step then -- nothing left to ask in this section
            Complete(section)
            table.remove(host.sections, host.index)
            host.index = math.min(host.index, #host.sections)
            return Render()
        end
        Demo(step)
        local wizard = section.wizard

        if frame.low ~= (step.low or false) then
            frame.low = step.low or false
            frame:ClearAllPoints()
            if frame.low then frame:SetPoint("BOTTOM", 0, 40) else frame:SetPoint("CENTER", 0, 80) end
        end

        frame.icon:SetTexture(wizard.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        frame.name:SetText(wizard.name)
        frame.header:SetText(("SETUP  ·  STEP %d OF %d"):format(pos, #list))

        local titleTop = LayoutTabs()
        frame.title:ClearAllPoints()
        frame.title:SetPoint("TOPLEFT", PAD, -titleTop)
        frame.title:SetPoint("RIGHT", -PAD, 0)
        frame.title:SetText(step.title)
        local text = step.text
        frame.text:SetText((type(text) == "function" and text() or text) or "")
        local top = titleTop + frame.title:GetStringHeight() + 8 + frame.text:GetStringHeight() + 14

        local value = not step.multi and wizard:Get(step)
        local height = step.multi and TICK_H or ROW_H
        local gap = step.multi and 3 or 6
        local choices = type(step.choices) == "function" and step.choices() or step.choices
        for i, choice in ipairs(choices) do
            local row = frame.rows[i] or MakeRow(i)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", PAD, -top - (i - 1) * (height + gap))
            row:SetHeight(height)
            row.label:ClearAllPoints()
            row.desc:ClearAllPoints()
            if step.multi then -- one line: the name, then what it's for
                row.label:SetPoint("LEFT", 14, 0)
                row.desc:SetPoint("LEFT", 140, 0)
            else
                row.label:SetPoint("TOPLEFT", 14, -8)
                row.label:SetPoint("RIGHT", -10, 0)
                row.desc:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -3)
            end
            row.desc:SetPoint("RIGHT", -10, 0)
            row.value = choice[1]
            if step.multi then
                row.selected = step.get(choice[1]) and true or false
            else
                row.selected = Same(choice[1], value)
            end
            row.label:SetText(choice[2])
            row.desc:SetText(choice[3] or "")
            row:Show()
            PaintRow(row)
        end
        for i = #choices + 1, #frame.rows do frame.rows[i]:Hide() end
        frame:SetHeight(top + #choices * (height + gap) + 50)

        frame.back:SetEnabled(Neighbour(-1) ~= nil)
        frame.next:SetEnabled(not step.required or value ~= nil)
        frame.next.label:SetText(Neighbour(1) and "Next" or "Done")
        frame.skip.label:SetText(#host.sections > 1 and "Skip section" or "Skip setup")
        frame.skip:SetShown(not wizard.intro) -- the opening question needs an answer
    end

    -- Opens the window, after combat if need be. Already open: just redraws it.
    local waiter = CreateFrame("Frame")
    local function Show()
        if #host.sections == 0 then return end
        if not (frame and frame:IsShown()) and InCombatLockdown() then
            waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
            return
        end
        if not frame then Build() end
        if host.index < 1 then host.index = 1 end
        Render()
        if Section() then frame:Show() end -- Render drops sections with nothing left to ask
    end
    waiter:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        Show()
    end)

    -- A wizard joins the list. auto: the login run, which waits its turn and stays out after Later;
    -- otherwise the player asked for it, so the window jumps to it.
    -- ask: the login run of a character that hasn't said whether it uses the account's settings; the
    -- opening question comes first (or its answer, already given, applies).
    function host:Add(wizard, scope, auto, ask)
        if auto and self.later then return end
        for i, section in ipairs(self.sections) do
            if section.wizard == wizard then
                if scope == "all" then section.scope, section.ask = "all", nil end
                if not auto then self.index, step = i, nil end
                return Show()
            end
        end
        if not wizard:Steps(scope)[1] then return end -- nothing to ask: the next login checks again
        local section = { wizard = wizard, scope = scope }
        if ask then
            section.ask, section.hadDefaults = true, wizard:HasDefaults()
            if self.mode then
                wizard:SetOwn(self.mode == "character")
                if not Steps(section)[1] then return Complete(section) end -- answered already: nothing left
            elseif not IntroIndex() then
                table.insert(self.sections, 1, { wizard = intro, scope = "all" })
                self.index, step = 1, nil -- the question first, even if another section is up
            end
        end
        table.insert(self.sections, section)
        if not auto then self.index, step = #self.sections, nil end
        Show()
    end
end

-- One addon's wizard -------------------------------------------------------------------------------

function ns.NewWizard(def)
    local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local wizard = { name = def.name, icon = def.icon or meta(addonName, "IconTexture") }

    local function Store() return (def.store and def.store()) or ns.db end
    local function CharStore() return (def.charStore and def.charStore()) or ns.char end

    local function HasCharSteps()
        for _, step in ipairs(def.steps) do
            if step.char then return true end
        end
    end

    -- How this character gets its own copy of the settings: def.own = { is = fn, set = fn(on) } (an
    -- addon with profiles), else ns.SAVED.own through the shared Core.lua. nil: it can't.
    local own = def.own
    if not own and ns.CanOwnOptions then
        own = {
            is = function() return ns:OwnsOptions() end,
            set = function(on) ns:SetOwnOptions(on) end,
            can = function() return ns:CanOwnOptions() end,
        }
    end

    function wizard:CanOwn()
        return own ~= nil and CharStore() ~= nil and (not own.can or own.can())
    end
    function wizard:IsOwn() return self:CanOwn() and own.is() and true or false end
    function wizard:SetOwn(on)
        if self:CanOwn() and self:IsOwn() ~= (on and true or false) then own.set(on and true or false) end
    end

    -- The account's answers exist (another character, or this one, went through every step).
    function wizard:HasDefaults()
        local store = Store()
        return store and store.wizardDone and true or false
    end

    -- A character on its first login asks "account defaults or its own options?" until it answers.
    ns:OnLoad(function()
        if not ns.charIsNew then return end
        local charStore = CharStore()
        if charStore and not charStore.wizardDone then charStore.wizardAsk = true end
    end)

    -- scope, ask: scope "all", "char" (only this character's steps: the rest were answered on
    -- another) or nil; ask: put the "account defaults or this character's own" question first.
    function wizard:Pending()
        local store, charStore = Store(), CharStore()
        local canOwn = self:CanOwn()
        if canOwn and charStore.wizardDone and self:IsOwn() then return end -- has its own settings
        if store and not store.wizardDone then return "all", canOwn end
        if charStore and not charStore.wizardDone then
            if canOwn and charStore.wizardAsk then return "all", true end
            if HasCharSteps() then return "char" end
        end
    end

    function wizard:Steps(scope)
        local list = {}
        for _, step in ipairs(def.steps) do
            if (scope == "all" or step.char) and (not step.when or step.when()) then list[#list + 1] = step end
        end
        return list
    end

    function wizard:Get(step)
        if step.get then return step.get() end
        return ns:GetOption(step.path)
    end

    function wizard:Set(step, value)
        if step.set then step.set(value) else ns:SetOption(step.path, value) end
    end

    -- Answers given in this character's own options don't make account defaults.
    function wizard:MarkDone()
        local store, charStore = Store(), CharStore()
        if store and not self:IsOwn() then store.wizardDone = true end
        if charStore then
            charStore.wizardDone = true
            charStore.wizardAsk = nil
        end
    end

    -- Every step, now: its own window, or a new section in the one already up.
    function wizard:Open()
        _G.SuiteSetup:Add(wizard, "all")
    end

    -- The login run. A new character's first login plays its race's intro cinematic over a hidden UI:
    -- the window opened behind it, and the Escape that skips the cinematic closed it as Later (asked
    -- only on the next login: a /reload). So the delay counts from when you're really in the world (no
    -- loading screen, cinematic or movie, the UI showing), and a wizard with nothing to ask yet (its
    -- steps' data still loading) looks again for a while before leaving it to the next login.
    local function InWorld()
        if InCinematic and InCinematic() then return false end
        if IsInCinematicScene and IsInCinematicScene() then return false end
        if CinematicFrame and CinematicFrame:IsShown() then return false end
        if MovieFrame and MovieFrame:IsShown() then return false end
        return UIParent and UIParent:IsShown() and true or false
    end
    local CHECK, TRIES = 1, 30 -- seconds between looks, and how many looks for steps to ask
    local function Ask(tries)
        local mode, ask = wizard:Pending()
        if not mode or (def.needed and not def.needed()) then return end
        if not wizard:Steps(mode)[1] then
            if tries > 0 then C_Timer.After(CHECK, function() Ask(tries - 1) end) end
            return
        end
        _G.SuiteSetup:Add(wizard, mode, true, ask)
    end
    local function WhenInWorld()
        if not InWorld() then return C_Timer.After(CHECK, WhenInWorld) end
        C_Timer.After(def.delay or 4, function()
            if not InWorld() then return WhenInWorld() end -- (a cinematic began meanwhile)
            Ask(TRIES)
        end)
    end
    ns:On("PLAYER_ENTERING_WORLD", function()
        if wizard.started then return end
        wizard.started = true
        WhenInWorld()
    end)

    return wizard
end
