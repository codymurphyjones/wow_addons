local ADDON, ns = ...

local E = {}
ns.Editor = E

local B = ns.Builder

local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"
local RULE_HEIGHT, VISIBLE_RULES = 32, 9
local SEQ_VISIBLE_RULES = 5 -- fewer rows in cast sequence mode, to fit the sequence panel
local LIST_WIDTH = 478
local LIST_TOP = -64
local COL = {
    num = 0, mod = 14, well = 88, name = 120, unit = 190, reaction = 258, state = 310, combat = 358,
    up = 408, down = 424, dup = 442, del = 458,
}

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------

local function ShowTooltip(owner, title, text)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title)
    if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
    GameTooltip:Show()
end

local function AddTooltip(widget, title, text)
    widget:SetScript("OnEnter", function(self) ShowTooltip(self, title, text) end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A button that steps through `options` (left-click next, right-click previous).
-- Options for which `isAllowed(key)` returns false are skipped.
local function CreateCycleButton(parent, width, options, title, onChange, isAllowed)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetNormalFontObject("ModifiedGameFontNormalSmall")
    b:SetHighlightFontObject("ModifiedGameFontHighlightSmall")
    b:SetDisabledFontObject("ModifiedGameFontDisableSmall")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    function b:SetValue(key)
        for _, o in ipairs(options) do
            if o.key == key then
                self.value, self.option = o.key, o
                self:SetText(o.label)
                return
            end
        end
        self:SetValue(options[1].key)
    end

    b:SetScript("OnClick", function(self, button)
        local index = 1
        for i, o in ipairs(options) do
            if o.key == self.value then index = i end
        end
        local step = button == "RightButton" and -1 or 1
        for _ = 1, #options - 1 do
            index = index + step
            if index > #options then index = 1 elseif index < 1 then index = #options end
            if not isAllowed or isAllowed(options[index].key) then
                self:SetValue(options[index].key)
                onChange(self.value)
                break
            end
        end
        if GameTooltip:IsOwned(self) then self:GetScript("OnEnter")(self) end
    end)
    b:SetScript("OnEnter", function(self)
        local hint = "Left-click: next   Right-click: previous"
        if isAllowed then hint = hint .. "\nChoices that would clash with another row are skipped." end
        ShowTooltip(self, title .. ": " .. self.option.label,
            self.option.tip .. "\n\n|cff808080" .. hint .. "|r")
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function CreateButton(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

-- Small texture button. `base` is a texture path prefix with -Up/-Down variants.
local function CreateIconButton(parent, base, highlight, size, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b:SetNormalTexture(base .. "-Up")
    b:SetPushedTexture(base .. "-Down")
    b:SetHighlightTexture(highlight, "ADD")
    b:SetScript("OnClick", onClick)
    return b
end

local function CreateCheck(parent, label, tipTitle, tipText, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    AddTooltip(cb, tipTitle, tipText)
    if label then
        cb.label = cb:CreateFontString(nil, "OVERLAY", "ModifiedGameFontNormalSmall")
        cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        cb.label:SetText(label)
    end
    return cb
end

local function CreateBackdropFrame(parent, alpha)
    local f = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        f:SetBackdropColor(0, 0, 0, alpha)
        f:SetBackdropBorderColor(0.6, 0.6, 0.6)
    end
    return f
end

local function RuleIcon(rule)
    if rule.kind == "spell" then
        local _, icon = ns.SpellInfo(rule.id or rule.name)
        return icon or QUESTION_MARK
    elseif rule.kind == "item" then
        return ns.ItemIcon(rule.id) or QUESTION_MARK
    end
end

-- Reads a spell or item from the cursor. Returns fields for a rule, or nil.
local function ReadCursor()
    local kind, a, b, c = GetCursorInfo()
    if kind == "spell" then
        -- Spellbook drags: kind, slotIndex, bookType, spellID
        local spellID = c
        local name = spellID and ns.SpellInfo(spellID)
        local getBookName = (C_SpellBook and C_SpellBook.GetSpellBookItemName) or GetSpellBookItemName
        if not name and getBookName then
            local ok, bookName = pcall(getBookName, a, b)
            name = ok and bookName or nil
        end
        if not name then
            ns:Print("Could not read that spell.")
            return
        end
        -- Keep the dragged rank only when ranks are shown; otherwise use the highest.
        local rank = ns.db.showAllRanks and ns.SpellRank(spellID) or nil
        return { kind = "spell", id = spellID, name = name, rank = rank }
    elseif kind == "item" then
        return { kind = "item", id = a, name = ns.ItemName(a) or ("item:" .. a) }
    elseif kind == "macro" then
        ns:Print("Macros can't be placed inside a macro. Drag a spell or item instead.")
    elseif kind then
        ns:Print("Only spells and items can be used here.")
    end
end

---------------------------------------------------------------------------
-- Rule rows (pooled)
---------------------------------------------------------------------------

local function CreateRuleRow(parent, i)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(LIST_WIDTH, RULE_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * RULE_HEIGHT)

    local function Rule() return E.draft.rules[row.index] end

    -- Highlight for the row whose sequence is being edited.
    row.sel = row:CreateTexture(nil, "BACKGROUND")
    row.sel:SetAllPoints()
    row.sel:SetColorTexture(1, 0.82, 0, 0.12)
    row.sel:Hide()

    row.num = row:CreateFontString(nil, "OVERLAY", "ModifiedGameFontDisableSmall")
    row.num:SetPoint("LEFT", COL.num, 0)

    -- Cycle button for one rule field; values that would clash are skipped.
    local function FieldButton(width, options, title, field)
        return CreateCycleButton(row, width, options, title,
            function(value)
                Rule()[field] = value
                E:Refresh()
            end,
            function(value) return E:CanSet(Rule(), field, value) end)
    end

    row.mod = FieldButton(72, B.MODIFIERS, "Modifier", "mod")
    row.mod:SetPoint("LEFT", COL.mod, 0)

    local well = CreateFrame("Button", nil, row)
    well:SetSize(28, 28)
    well:SetPoint("LEFT", COL.well, 0)
    well.edge = well:CreateTexture(nil, "BACKGROUND")
    well.edge:SetPoint("TOPLEFT", -1, 1)
    well.edge:SetPoint("BOTTOMRIGHT", 1, -1)
    well.edge:SetColorTexture(1, 0.82, 0, 0.35)
    well.bg = well:CreateTexture(nil, "BORDER")
    well.bg:SetAllPoints()
    well.bg:SetColorTexture(0, 0, 0, 0.7)
    well.icon = well:CreateTexture(nil, "ARTWORK")
    well.icon:SetAllPoints()
    well.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    well.role = well:CreateFontString(nil, "OVERLAY", "ModifiedGameFontNormalLarge")
    well.role:SetPoint("CENTER")
    well.count = well:CreateFontString(nil, "OVERLAY", "ModifiedNumberFontNormal")
    well.count:SetPoint("BOTTOMRIGHT", -1, 1)
    well:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    well:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    well:SetScript("OnReceiveDrag", function()
        if E.draft.sequence then
            E:SelectSequence(Rule())
            E:DropStep(nil)
        else
            E:DropOnRule(Rule())
        end
    end)
    well:SetScript("OnClick", function(self, button)
        if E.draft.sequence then
            -- In sequence mode the square selects the row; steps are edited below the list.
            E:SelectSequence(Rule())
            if GetCursorInfo() then E:DropStep(nil) end
        elseif button == "RightButton" then
            E:ClearRule(Rule())
        elseif GetCursorInfo() then
            E:DropOnRule(Rule())
        else
            E:PickSpellForRule(Rule(), self)
        end
    end)
    well:SetScript("OnEnter", function(self)
        local rule = Rule()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if E.draft.sequence then
            GameTooltip:SetText("Cast sequence")
            for i, step in ipairs(rule.steps or {}) do
                GameTooltip:AddLine(("%d. %s"):format(i, B:ActionToken(step)), 1, 1, 1)
            end
            local reset = B:ResetString(rule.reset)
            if reset then GameTooltip:AddLine(reset, 0.6, 0.8, 1) end
            GameTooltip:AddLine("Click to edit this row's sequence below the list.", 0.5, 0.5, 0.5, true)
            GameTooltip:Show()
            return
        end
        if rule and rule.kind == "spell" and rule.id then
            GameTooltip:SetSpellByID(rule.id)
        elseif rule and rule.kind == "item" then
            GameTooltip:SetItemByID(rule.id)
        else
            GameTooltip:SetText("No spell yet")
            if rule and rule.role then
                GameTooltip:AddLine(("Spell %s: also fills every other empty %s row."):format(rule.role, rule.role), 1, 0.82, 0, true)
            end
        end
        GameTooltip:AddLine("Click to choose a spell. You can also drag in a spell or an item from your bags.", 0.5, 0.5, 0.5, true)
        GameTooltip:AddLine("Right-click to clear.", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    well:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.well = well

    row.name = row:CreateFontString(nil, "OVERLAY", "ModifiedGameFontHighlightSmall")
    row.name:SetPoint("LEFT", COL.name, 0)
    row.name:SetWidth(68)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.unit = FieldButton(66, B.UNITS, "Target", "unit")
    row.unit:SetPoint("LEFT", COL.unit, 0)
    row.reaction = FieldButton(50, B.REACTIONS, "Reaction", "reaction")
    row.reaction:SetPoint("LEFT", COL.reaction, 0)
    row.state = FieldButton(46, B.STATES, "State", "state")
    row.state:SetPoint("LEFT", COL.state, 0)
    row.combat = FieldButton(48, B.COMBAT, "Combat", "combat")
    row.combat:SetPoint("LEFT", COL.combat, 0)

    row.up = CreateIconButton(row, "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton",
        "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Highlight", 18, function() E:MoveRule(row.index, -1) end)
    row.up:SetDisabledTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Disabled")
    row.up:SetPoint("LEFT", COL.up, 0)
    AddTooltip(row.up, "Move up", "Rows with the same modifier are checked top to bottom; the first match is cast. "
        .. "A broader row can't move above a narrower one it would block.")

    row.down = CreateIconButton(row, "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton",
        "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Highlight", 18, function() E:MoveRule(row.index, 1) end)
    row.down:SetDisabledTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Disabled")
    row.down:SetPoint("LEFT", COL.down, 0)
    AddTooltip(row.down, "Move down", "Rows with the same modifier are checked top to bottom; the first match is cast. "
        .. "A broader row can't move above a narrower one it would block.")

    row.dup = CreateIconButton(row, "Interface\\Buttons\\UI-PlusButton",
        "Interface\\Buttons\\UI-PlusButton-Hilight", 16, function() E:DuplicateRule(row.index) end)
    row.dup:SetPoint("LEFT", COL.dup, 0)
    AddTooltip(row.dup, "Duplicate", "Copy this row below itself, then change its spell or conditions.")

    row.del = CreateIconButton(row, "Interface\\Buttons\\UI-GroupLoot-Pass",
        "Interface\\Buttons\\UI-GroupLoot-Pass-Highlight", 18, function() E:DeleteRule(row.index) end)
    row.del:SetPoint("LEFT", COL.del, 0)
    AddTooltip(row.del, "Delete row")

    return row
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------

function E:Create(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", 490, -28)
    panel:SetPoint("BOTTOMRIGHT", -12, 12)
    self.panel = panel

    -- Empty state: the logo with a hint underneath.
    panel.logo = panel:CreateTexture(nil, "ARTWORK")
    panel.logo:SetSize(128, 128)
    panel.logo:SetPoint("CENTER", 0, 50)
    panel.logo:SetTexture(ns.LOGO)
    panel.logo:SetAlpha(0.85)

    panel.placeholder = panel:CreateFontString(nil, "OVERLAY", "ModifiedGameFontDisable")
    panel.placeholder:SetPoint("TOP", panel.logo, "BOTTOM", 0, -14)
    panel.placeholder:SetWidth(340)
    panel.placeholder:SetText("Click a button on the left to design what it does with modifiers and different targets.")

    local c = CreateFrame("Frame", nil, panel)
    c:SetAllPoints()
    self.content = c

    -- Header
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetSize(36, 36)
    c.icon:SetPoint("TOPLEFT", 0, 0)
    c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    c.title = c:CreateFontString(nil, "OVERLAY", "ModifiedGameFontNormalLarge")
    c.title:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 8, -1)
    c.title:SetWidth(280)
    c.title:SetJustifyH("LEFT")
    c.title:SetWordWrap(false)
    c.sub = c:CreateFontString(nil, "OVERLAY", "ModifiedGameFontHighlightSmall")
    c.sub:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -3)
    c.status = c:CreateFontString(nil, "OVERLAY", "ModifiedGameFontNormalSmall")
    c.status:SetPoint("TOPRIGHT", 0, -22)
    c.status:SetJustifyH("RIGHT")

    -- Column headers
    local headers = {
        { COL.mod, "Modifier" }, { COL.well, "Spell" }, { COL.unit, "Target" },
        { COL.reaction, "Reaction" }, { COL.state, "State" }, { COL.combat, "Combat" },
    }
    for _, h in ipairs(headers) do
        local fs = c:CreateFontString(nil, "OVERLAY", "ModifiedGameFontDisableSmall")
        fs:SetPoint("TOPLEFT", h[1] + 2, -48)
        fs:SetText(h[2])
    end

    -- Rule list
    local scroll = CreateFrame("ScrollFrame", "ModifiedRuleScroll", c, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, LIST_TOP)
    scroll:SetSize(LIST_WIDTH, RULE_HEIGHT * VISIBLE_RULES)
    local list = CreateFrame("Frame", nil, scroll)
    list:SetSize(LIST_WIDTH, 10)
    scroll:SetScrollChild(list)
    self.scroll, self.list, self.ruleRows = scroll, list, {}

    c.emptyList = list:CreateFontString(nil, "OVERLAY", "ModifiedGameFontDisable")
    c.emptyList:SetPoint("TOPLEFT", 4, -8)
    c.emptyList:SetWidth(LIST_WIDTH - 8)
    c.emptyList:SetJustifyH("LEFT")
    c.emptyList:SetText("No rows yet. Click 'Add modifier' or pick a pattern.")

    local belowList = LIST_TOP - RULE_HEIGHT * VISIBLE_RULES - 8
    self:CreateSequencePanel(c)

    c.add = CreateButton(c, "Add modifier", 120, function(self)
        local fields = GetCursorInfo() and ReadCursor()
        if fields then
            ClearCursor()
            E:AddRule(fields)
        else
            -- Add an empty row and offer the spell list for it right away.
            local rule = E:AddRule()
            if rule then E:PickSpellForRule(rule, self) end
        end
    end)
    c.add:SetPoint("TOPLEFT", 0, belowList)
    c.add:SetScript("OnReceiveDrag", function()
        local fields = ReadCursor()
        if fields then
            ClearCursor()
            E:AddRule(fields)
        end
    end)
    AddTooltip(c.add, "Add modifier",
        "Adds a row and opens the spell list. Set its modifier, target and reaction with the buttons on the row. "
        .. "Rows may share a modifier as long as their conditions differ.")

    c.patterns = CreateButton(c, "Patterns...", 110, function() E:TogglePatterns() end)
    c.patterns:SetPoint("LEFT", c.add, "RIGHT", 8, 0)
    AddTooltip(c.patterns, "Patterns", "Add a ready-made set of rows (mouseover then target, heal friend / hurt enemy, ...). Change their modifier afterwards if you like.")
    self:CreatePatternMenu(c)

    c.showtooltip = CreateCheck(c, "#showtooltip", "#showtooltip",
        "The button's icon and tooltip follow the spell the macro would cast right now.",
        function(checked)
            E.draft.showtooltip = checked
            E:Refresh()
        end)
    c.showtooltip:SetPoint("LEFT", c.patterns, "RIGHT", 12, 0)

    -- Preview
    local previewLabel = c:CreateFontString(nil, "OVERLAY", "ModifiedGameFontNormal")
    previewLabel:SetPoint("TOPLEFT", 0, belowList - 32)
    previewLabel:SetText("Macro preview")
    c.counter = c:CreateFontString(nil, "OVERLAY", "ModifiedGameFontHighlightSmall")
    c.counter:SetPoint("TOPRIGHT", 0, belowList - 34)

    local box = CreateBackdropFrame(c, 0.8)
    box:SetPoint("TOPLEFT", 0, belowList - 50)
    box:SetPoint("TOPRIGHT", 0, belowList - 50)
    box:SetHeight(84)
    c.preview = box:CreateFontString(nil, "OVERLAY", "ModifiedGameFontHighlightSmall")
    c.preview:SetPoint("TOPLEFT", 8, -8)
    c.preview:SetPoint("BOTTOMRIGHT", -8, 8)
    c.preview:SetJustifyH("LEFT")
    c.preview:SetJustifyV("TOP")

    c.warning = c:CreateFontString(nil, "OVERLAY", "ModifiedGameFontNormalSmall")
    c.warning:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 2, -6)
    c.warning:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", -2, -6)
    c.warning:SetJustifyH("LEFT")
    c.warning:SetJustifyV("TOP")

    -- Actions
    c.apply = CreateButton(c, "Apply", 110, function() E:Apply() end)
    c.apply:SetPoint("BOTTOMLEFT", 0, 0)
    c.revert = CreateButton(c, "Revert to original", 140, function() E:Revert() end)
    c.revert:SetPoint("LEFT", c.apply, "RIGHT", 8, 0)
    c.reset = CreateButton(c, "Reset all", 110, function() E:ResetAll() end)
    c.reset:SetPoint("LEFT", c.revert, "RIGHT", 8, 0)
    AddTooltip(c.reset, "Reset all", "Clears every row and puts the button's original spell back as a single 'None' row. Nothing changes in game until you click Apply.")
    c.reload = CreateButton(c, "Reload UI", 90, function() ReloadUI() end)
    c.reload:SetPoint("LEFT", c.reset, "RIGHT", 8, 0)
    AddTooltip(c.reload, "Reload UI", "Modified changed your action bars this session. Reload before your next fight, or Blizzard's action buttons will throw cooldown errors.")

    c.showRanks = CreateCheck(c, "Show all spell ranks", "Show all spell ranks",
        "Lists every rank you know in the spell picker, so a row can cast a specific rank, e.g. Rejuvenation(Rank 3). "
        .. "Dragging a spell from the spellbook also keeps its rank while this is on. "
        .. "Rows without a fixed rank always cast your highest rank.",
        function(checked)
            -- The same option as Options > AddOns > Modified; its apply resets the spell picker.
            ns:SetOption("db.showAllRanks", checked)
        end)
    c.showRanks:SetPoint("BOTTOMLEFT", -4, 26)

    c.sequenceMode = CreateCheck(c, "Cast sequence", "Cast sequence",
        "Writes a /castsequence macro: each row casts its own list of spells in turn, one per press. "
        .. "Rows keep their modifier and target, so you can have a mouseover sequence, a target sequence "
        .. "and a self-cast sequence on one button. Pick a row, then edit its steps and reset options below the list.",
        function(checked) E:SetSequenceMode(checked) end)
    c.sequenceMode:SetPoint("LEFT", c.showRanks.label, "RIGHT", 16, 0)

    self:Refresh()
end

---------------------------------------------------------------------------
-- Sequence panel (cast sequence mode): steps and reset options of one row
---------------------------------------------------------------------------

local STEP_SIZE, STEP_GAP = 28, 4

local function CreateStepWell(parent, i)
    local well = CreateFrame("Button", nil, parent)
    well:SetSize(STEP_SIZE, STEP_SIZE)
    well:SetPoint("TOPLEFT", (i - 1) * (STEP_SIZE + STEP_GAP), -18)
    well.edge = well:CreateTexture(nil, "BACKGROUND")
    well.edge:SetPoint("TOPLEFT", -1, 1)
    well.edge:SetPoint("BOTTOMRIGHT", 1, -1)
    well.edge:SetColorTexture(1, 0.82, 0, 0.35)
    well.bg = well:CreateTexture(nil, "BORDER")
    well.bg:SetAllPoints()
    well.bg:SetColorTexture(0, 0, 0, 0.7)
    well.icon = well:CreateTexture(nil, "ARTWORK")
    well.icon:SetAllPoints()
    well.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    well.num = well:CreateFontString(nil, "OVERLAY", "ModifiedNumberFontNormalSmall")
    well.num:SetPoint("TOPLEFT", 2, -2)
    well:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    well:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    well:SetScript("OnReceiveDrag", function(self) E:DropStep(self.index) end)
    well:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            E:RemoveStep(self.index)
        elseif GetCursorInfo() then
            E:DropStep(self.index)
        else
            E:PickStep(self.index, self)
        end
    end)
    well:SetScript("OnEnter", function(self)
        local step = E.seqRule and E.seqRule.steps[self.index]
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if step and step.kind == "spell" and step.id then
            GameTooltip:SetSpellByID(step.id)
        elseif step and step.kind == "item" then
            GameTooltip:SetItemByID(step.id)
        end
        GameTooltip:AddLine(("Step %d"):format(self.index), 1, 0.82, 0)
        GameTooltip:AddLine("Click: change   Right-click: remove", 0.5, 0.5, 0.5, true)
        GameTooltip:AddLine("Use the arrows below to change the cast order.", 0.5, 0.5, 0.5, true)
        GameTooltip:Show()
    end)
    well:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Reorder buttons under the square: cast order is the whole point of a sequence.
    local function Arrow(dir, delta, tip)
        local b = CreateIconButton(well, "Interface\\Buttons\\UI-SpellbookIcon-" .. dir .. "Page",
            "Interface\\Buttons\\ButtonHilight-Square", 14, function() E:MoveStep(well.index, delta) end)
        b:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. dir .. "Page-Disabled")
        AddTooltip(b, tip)
        return b
    end
    well.left = Arrow("Prev", -1, "Cast earlier")
    well.left:SetPoint("TOPLEFT", well, "BOTTOMLEFT", 0, -2)
    well.right = Arrow("Next", 1, "Cast later")
    well.right:SetPoint("TOPRIGHT", well, "BOTTOMRIGHT", 0, -2)
    return well
end

function E:CreateSequencePanel(c)
    local p = CreateFrame("Frame", nil, c)
    p:SetPoint("TOPLEFT", 0, LIST_TOP - RULE_HEIGHT * SEQ_VISIBLE_RULES - 6)
    p:SetSize(LIST_WIDTH, RULE_HEIGHT * (VISIBLE_RULES - SEQ_VISIBLE_RULES))
    p:Hide()
    c.seq = p

    p.title = p:CreateFontString(nil, "OVERLAY", "ModifiedGameFontNormalSmall")
    p.title:SetPoint("TOPLEFT", 0, 0)
    p.title:SetWidth(LIST_WIDTH)
    p.title:SetJustifyH("LEFT")
    p.title:SetWordWrap(false)

    p.steps = {}
    for i = 1, B.MAX_STEPS do p.steps[i] = CreateStepWell(p, i) end

    local add = CreateFrame("Button", nil, p)
    add:SetSize(STEP_SIZE, STEP_SIZE)
    add:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
    add:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
    add:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    add:SetScript("OnClick", function(self)
        if GetCursorInfo() then E:DropStep(nil) else E:PickStep(nil, self) end
    end)
    add:SetScript("OnReceiveDrag", function() E:DropStep(nil) end)
    AddTooltip(add, "Add step", "Adds a spell to the end of this row's sequence. You can also drag a spell or item here.")
    p.add = add

    -- Reset options
    local resetLabel = p:CreateFontString(nil, "OVERLAY", "ModifiedGameFontNormalSmall")
    resetLabel:SetPoint("TOPLEFT", 0, -72)
    resetLabel:SetText("Reset:")

    local function StepSeconds(delta)
        if IsShiftKeyDown() then delta = delta * 5 end
        local reset = E:SequenceReset()
        reset.seconds = math.max(0, math.min((reset.seconds or 0) + delta, B.MAX_RESET_SECONDS))
        E:Refresh()
    end
    p.minus = CreateButton(p, "-", 20, function() StepSeconds(-1) end)
    p.minus:SetPoint("TOPLEFT", 40, -68)
    p.seconds = p:CreateFontString(nil, "OVERLAY", "ModifiedGameFontHighlightSmall")
    p.seconds:SetPoint("LEFT", p.minus, "RIGHT", 2, 0)
    p.seconds:SetWidth(34)
    p.plus = CreateButton(p, "+", 20, function() StepSeconds(1) end)
    p.plus:SetPoint("LEFT", p.seconds, "RIGHT", 2, 0)
    AddTooltip(p.minus, "Reset timer", "Start the sequence over after this many seconds without pressing the button. Shift-click: 5 seconds at a time.")
    AddTooltip(p.plus, "Reset timer", "Start the sequence over after this many seconds without pressing the button. Shift-click: 5 seconds at a time.")

    p.flags = {}
    local x = 132
    for _, flag in ipairs(B.RESET_FLAGS) do
        local cb = CreateCheck(p, flag.label, "Reset: " .. flag.label, flag.tip, function(checked)
            E:SequenceReset()[flag.key] = checked or nil
            E:Refresh()
        end)
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", x, -67)
        p.flags[flag.key] = cb
        x = x + 24 + cb.label:GetStringWidth() + 10
    end

    p.help = p:CreateFontString(nil, "OVERLAY", "ModifiedGameFontDisableSmall")
    p.help:SetPoint("TOPLEFT", 0, -94)
    p.help:SetWidth(LIST_WIDTH)
    p.help:SetJustifyH("LEFT")
    p.help:SetText("Each press casts the next step. Every row keeps its own place, so mouseover, target and self rows each run their own sequence.")
end

-- Rows sharing the selected row's context (modifier + conditions), in list
-- order, with their list positions. They run as one sequence.
function E:SequenceGroup()
    local group, positions = {}, {}
    for i, r in ipairs(self.draft.rules) do
        if B:SameConditions(r, self.seqRule) then
            group[#group + 1] = r
            positions[#positions + 1] = i
        end
    end
    return group, positions
end

-- Reset options live on the first row of a context; they cover the whole sequence.
function E:SequenceReset()
    if not self.seqRule then return {} end -- no row selected: edits go nowhere
    local rule = self:SequenceGroup()[1]
    rule.reset = rule.reset or {}
    return rule.reset
end

function E:RefreshSequencePanel()
    local p = self.content.seq
    local rule = self.seqRule
    if not rule then
        p.title:SetText("Add a row to build a sequence.")
        p.help:SetText("")
        for _, w in ipairs(p.steps) do w:Hide() end
        p.add:Hide()
        return
    end

    local index
    for i, r in ipairs(self.draft.rules) do
        if r == rule then index = i end
    end
    local unit = B.UNITS[1].label
    for _, o in ipairs(B.UNITS) do
        if o.key == rule.unit then unit = o.label end
    end
    p.title:SetText(("Steps of row %d  |cffb0b0b0(%s, %s)|r"):format(index or 0, B:ModLabel(rule.mod), unit))

    -- Rows that share this context chain into one sequence; say so.
    local group, positions = self:SequenceGroup()
    if #group > 1 then
        local names = {}
        for _, r in ipairs(group) do
            for _, step in ipairs(r.steps or {}) do names[#names + 1] = step.name or B:ActionToken(step) end
        end
        p.help:SetText(("|cffffd100Rows %s share these conditions and run as one sequence:|r %s. "
            .. "Reorder with the row arrows. The reset options apply to the whole sequence.")
            :format(table.concat(positions, ", "), table.concat(names, " > ")))
    else
        p.help:SetText("Each press casts the next step. Add more rows with the same modifier and target "
            .. "to extend this sequence, or rows with other targets for separate sequences.")
    end

    local steps = rule.steps
    for i, w in ipairs(p.steps) do
        local step = steps[i]
        w.index = i
        if step then
            w.icon:SetTexture(RuleIcon(step))
            w.num:SetText(i)
            w.left:SetEnabled(i > 1)
            w.right:SetEnabled(i < #steps)
            w:Show()
        else
            w:Hide()
        end
    end
    p.add:ClearAllPoints()
    p.add:SetPoint("TOPLEFT", #steps * (STEP_SIZE + STEP_GAP), -18)
    p.add:SetShown(#steps < B.MAX_STEPS)

    local reset = group[1].reset or {}
    local seconds = reset.seconds or 0
    p.seconds:SetText(seconds > 0 and (seconds .. "s") or "off")
    p.minus:SetEnabled(seconds > 0)
    p.plus:SetEnabled(seconds < B.MAX_RESET_SECONDS)
    for key, cb in pairs(p.flags) do cb:SetChecked(reset[key] and true or false) end
end

function E:CreatePatternMenu(c)
    local menu = CreateBackdropFrame(c, 0.95)
    menu:SetFrameLevel(c:GetFrameLevel() + 30)
    menu:SetPoint("BOTTOMLEFT", c.patterns, "TOPLEFT", 0, 2)
    menu:SetSize(216, 12 + #B.PATTERNS * 24)
    menu:EnableMouse(true)
    for i, pattern in ipairs(B.PATTERNS) do
        local b = CreateButton(menu, pattern.label, 200, function()
            menu:Hide()
            E:InsertPattern(pattern)
        end)
        b:SetNormalFontObject("ModifiedGameFontNormalSmall")
        b:SetHighlightFontObject("ModifiedGameFontHighlightSmall")
        b:SetPoint("TOPLEFT", 8, -6 - (i - 1) * 24)
        AddTooltip(b, pattern.label, pattern.tip)
    end
    menu:Hide()
    self.patternMenu = menu
end

function E:TogglePatterns()
    self.patternMenu:SetShown(not self.patternMenu:IsShown())
end

---------------------------------------------------------------------------
-- Draft editing
---------------------------------------------------------------------------

local function FillFromOriginal(design)
    local original = design.original
    design.rules = {}
    if original and (original.type == "spell" or original.type == "item") then
        design.rules[1] = B:NewRule({ kind = original.type, id = original.id, name = original.name })
    end
end

function E:NewDesignFromSlot(slot)
    local info = ns.Bars:GetSlotInfo(slot)
    local design = { version = B.VERSION, macroName = "Mod_" .. slot, showtooltip = true }
    if info.type then
        design.original = { type = info.type, id = info.id, name = info.name }
    end
    FillFromOriginal(design)
    return design
end

function E:Load(slot)
    self.slot = slot
    local saved = ns.db.designs[slot]
    if saved then
        self.draft = B:Sanitize(B:Migrate(ns.DeepCopy(saved)))
    else
        self.draft = self:NewDesignFromSlot(slot)
    end
    if self.patternMenu then self.patternMenu:Hide() end
    ns.SpellPicker:Hide()
    if self.scroll then self.scroll:SetVerticalScroll(0) end
    self:Refresh()
end

-- Would setting rule[field] = value clash with another row?
function E:CanSet(rule, field, value)
    local test = ns.DeepCopy(rule)
    test[field] = value
    return not B:HasConflict(self.draft.rules, test, rule, self.draft.sequence)
end

-- Adds a row: the nearest free combination to the last row's modifier, or in
-- cast sequence mode the selected row's context, which extends its sequence.
function E:AddRule(fields)
    local rules = self.draft.rules
    local sequence = self.draft.sequence
    local base = B:NewRule(fields)
    local template = sequence and self.seqRule or rules[#rules]
    if template then
        base.mod = template.mod
        if sequence then
            base.unit, base.reaction = template.unit, template.reaction
            base.state, base.combat = template.state, template.combat
        end
    end
    local rule = B:FindFree(rules, base, nil, sequence)
    if not rule then
        ns:Print("Every modifier and condition combination is already in use.")
        return
    end
    table.insert(rules, rule)
    if self.draft.sequence then self.seqRule = rule end
    self:Refresh()
    return rule
end

local function SetAction(rule, fields)
    rule.kind, rule.id, rule.name, rule.rank = fields.kind, fields.id, fields.name, fields.rank
end

-- Sets a rule's spell; pattern placeholders with the same role fill too.
function E:SetRuleAction(rule, fields)
    SetAction(rule, fields)
    if rule.role then
        for _, other in ipairs(self.draft.rules) do
            if other.role == rule.role and not B:RuleHasAction(other) then
                SetAction(other, fields)
            end
        end
    end
    self:Refresh()
end

function E:DropOnRule(rule)
    local fields = ReadCursor()
    if not fields then return end
    ClearCursor()
    self:SetRuleAction(rule, fields)
end

function E:PickSpellForRule(rule, anchor)
    local draft = self.draft
    ns.SpellPicker:Open(anchor, function(fields)
        -- Ignore the pick if another button was opened meanwhile.
        if self.draft == draft then self:SetRuleAction(rule, fields) end
    end, ns.db.showAllRanks)
end

---------------------------------------------------------------------------
-- Cast sequence editing
---------------------------------------------------------------------------

function E:SetSequenceMode(on)
    self.draft.sequence = on or nil
    if on then
        for _, rule in ipairs(self.draft.rules) do B:EnsureSteps(rule) end
        self.seqRule = self.draft.rules[1]
    else
        -- The standard designer doesn't allow rows that share a context.
        local _, changed = B:Sanitize(self.draft)
        if changed > 0 then
            ns:Print(("%d row(s) shared a target/reaction with another row and were changed so they don't clash. "
                .. "Tick Cast sequence again before applying to get the sequence back."):format(changed))
        end
    end
    ns.SpellPicker:Hide()
    self:Refresh()
end

function E:SelectSequence(rule)
    self.seqRule = rule
    self:Refresh()
end

-- Puts `fields` at step `index` of the selected row, or appends when index is nil.
function E:SetStep(index, fields)
    local rule = self.seqRule
    if not rule then return end
    local step = { kind = fields.kind, id = fields.id, name = fields.name, rank = fields.rank }
    if index and rule.steps[index] then
        rule.steps[index] = step
    elseif #rule.steps < B.MAX_STEPS then
        table.insert(rule.steps, step)
    end
    B:SyncFromSteps(rule)
    self:Refresh()
end

function E:DropStep(index)
    local fields = ReadCursor()
    if not fields then return end
    ClearCursor()
    self:SetStep(index, fields)
end

function E:PickStep(index, anchor)
    local rule = self.seqRule
    ns.SpellPicker:Open(anchor, function(fields)
        if self.seqRule == rule then self:SetStep(index, fields) end
    end, ns.db.showAllRanks)
end

function E:RemoveStep(index)
    local rule = self.seqRule
    table.remove(rule.steps, index)
    B:SyncFromSteps(rule)
    self:Refresh()
end

function E:MoveStep(index, delta)
    local steps = self.seqRule.steps
    local target = index + delta
    if target < 1 or target > #steps then return end
    steps[index], steps[target] = steps[target], steps[index]
    B:SyncFromSteps(self.seqRule)
    self:Refresh()
end

function E:ClearRule(rule)
    rule.kind, rule.id, rule.name, rule.rank = nil, nil, nil, nil
    self:Refresh()
end

function E:MoveRule(index, delta)
    local rules = self.draft.rules
    if not B:CanMove(rules, index, delta) then return end
    local a, b = rules[index], rules[index + delta]
    -- Rows of one sequence: the reset options belong to the sequence, so they
    -- stay with whichever row comes first.
    if B:SameConditions(a, b) then a.reset, b.reset = b.reset, a.reset end
    rules[index], rules[index + delta] = b, a
    self:Refresh()
end

-- Copies a row, adjusted to the nearest combination that doesn't clash.
function E:DuplicateRule(index)
    local rules = self.draft.rules
    local copy = B:FindFree(rules, rules[index], nil, self.draft.sequence)
    if not copy then
        ns:Print("Every modifier and condition combination is already in use.")
        return
    end
    table.insert(rules, index + 1, copy)
    self:Refresh()
end

function E:DeleteRule(index)
    local rules = self.draft.rules
    local removed = table.remove(rules, index)
    -- Hand a sequence's reset options to the next row of that sequence.
    if removed.reset then
        for _, r in ipairs(rules) do
            if B:SameConditions(r, removed) then
                r.reset = r.reset or removed.reset
                break
            end
        end
    end
    self:Refresh()
end

function E:InsertPattern(pattern)
    local rules = self.draft.rules
    -- Spell A comes from the first row's spell, so a fresh button keeps its spell.
    local seed
    for _, rule in ipairs(rules) do
        if B:RuleHasAction(rule) then
            seed = { kind = rule.kind, id = rule.id, name = rule.name, rank = rule.rank }
            break
        end
    end
    -- A lone catch-all row (like the button's original spell) is replaced.
    if #rules == 1 and (B:IsUnconditional(rules[1]) or not B:RuleHasAction(rules[1])) then
        wipe(rules)
    end

    local new = {}
    for _, skeleton in ipairs(pattern.rules) do
        local rule = B:NewRule(skeleton)
        if rule.role == "A" and seed then SetAction(rule, seed) end
        new[#new + 1] = rule
    end

    -- Put the whole pattern on the first modifier where none of its rows clash.
    local chosen
    for _, mod in ipairs(B.MODIFIERS) do
        local fits = true
        for _, rule in ipairs(new) do
            rule.mod = mod.key
            if B:HasConflict(rules, rule, nil, self.draft.sequence) then fits = false end
        end
        if fits then
            chosen = mod
            break
        end
    end
    if not chosen then
        ns:Print("That pattern doesn't fit: every modifier already uses those conditions.")
        return
    end
    for _, rule in ipairs(new) do rules[#rules + 1] = rule end
    if chosen.key ~= "none" then
        ns:Print(("Pattern added on %s (the earlier modifiers already use those conditions)."):format(chosen.label))
    end
    self:Refresh()
end

function E:ResetAll()
    FillFromOriginal(self.draft)
    self.draft.showtooltip = true
    self:Refresh()
end

local function StripRoles(design)
    for _, rule in ipairs(design.rules) do rule.role = nil end
    return design
end

-- Our macro/action bar writes leave Blizzard's buttons tainted until a reload.
-- ReloadUI needs a hardware event, so it can only run from the Apply/Revert click.
local function ReloadIfNeeded()
    if ns.needsReload and ns.db.autoReload then
        ns:Print("Reloading the UI so your action bars stay error-free...")
        ReloadUI()
    end
end

function E:Apply()
    local slot = self.slot
    local ok, err = ns.Manager:Apply(slot, StripRoles(ns.DeepCopy(self.draft)))
    if ok == "queued" then
        ns:Print("In combat. The macro will be applied when combat ends.")
    elseif ok then
        ns:Print(("Updated %s (%s)."):format(ns.Bars:Describe(slot), self.draft.macroName))
        ReloadIfNeeded()
    elseif err then
        ns:Print("|cffff5555" .. err .. "|r")
    end
    self:Refresh()
end

function E:Revert()
    local slot = self.slot
    local result = ns.Manager:Revert(slot)
    if result == "queued" then
        ns:Print("In combat. The button will be reverted when combat ends.")
        self:Refresh()
    elseif result then
        ns:Print(("Restored %s."):format(ns.Bars:Describe(slot)))
        self:Load(slot)
        ReloadIfNeeded()
    end
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------

function E:RefreshRules()
    local rules = self.draft.rules
    for i, rule in ipairs(rules) do
        local row = self.ruleRows[i]
        if not row then
            row = CreateRuleRow(self.list, i)
            self.ruleRows[i] = row
        end
        row.index = i
        row:Show()
        row.num:SetText(i)

        local has = B:RuleHasAction(rule)
        local sequence = self.draft.sequence
        row.well.icon:SetTexture(has and RuleIcon(rule) or nil)
        row.well.role:SetText(not has and rule.role or "")
        row.well.count:SetText(sequence and #rule.steps > 1 and #rule.steps or "")
        row.sel:SetShown(sequence and rule == self.seqRule)
        if sequence then
            local names = {}
            for _, step in ipairs(rule.steps) do names[#names + 1] = step.name or B:ActionToken(step) end
            row.name:SetText(#names > 0 and table.concat(names, " > ") or "|cff606060(no steps)|r")
        elseif has then
            local label = rule.name or B:ActionToken(rule)
            if rule.rank then
                local num = rule.rank:match("(%d+)%s*$")
                label = label .. (num and (" |cffb0b0b0(R" .. num .. ")|r") or (" (" .. rule.rank .. ")"))
            end
            row.name:SetText(label)
        elseif rule.role then
            row.name:SetText(("|cffffd100(spell %s)|r"):format(rule.role))
        else
            row.name:SetText("|cff606060(click)|r")
        end

        row.mod:SetValue(rule.mod)
        row.unit:SetValue(rule.unit)
        row.reaction:SetValue(rule.reaction)
        row.state:SetValue(rule.state)
        row.combat:SetValue(rule.combat)
        local alpha = has and 1 or 0.5
        row.unit:SetAlpha(alpha)
        row.reaction:SetAlpha(alpha)
        row.state:SetAlpha(alpha)
        row.combat:SetAlpha(alpha)
        row.up:SetEnabled(B:CanMove(rules, i, -1))
        row.down:SetEnabled(B:CanMove(rules, i, 1))
    end
    for i = #rules + 1, #self.ruleRows do self.ruleRows[i]:Hide() end
    self.list:SetHeight(math.max(#rules * RULE_HEIGHT, 10))
    self.content.emptyList:SetShown(#rules == 0)
end

function E:Refresh()
    if not self.panel then return end
    local c, slot, draft = self.content, self.slot, self.draft
    if not slot or not draft then
        c:Hide()
        self.panel.placeholder:Show()
        self.panel.logo:Show()
        return
    end
    self.panel.placeholder:Hide()
    self.panel.logo:Hide()
    c:Show()

    -- Every edit ends here: regroup by modifier and keep broad rows below narrow ones.
    B:Normalize(draft.rules)

    -- Cast sequence mode: every row has steps, one row is selected, and the
    -- list shrinks to make room for the sequence panel.
    local sequence = draft.sequence and true or false
    if sequence then
        local selectedExists = false
        for _, rule in ipairs(draft.rules) do
            B:EnsureSteps(rule)
            if rule == self.seqRule then selectedExists = true end
        end
        if not selectedExists then self.seqRule = draft.rules[1] end
    end
    self.scroll:SetHeight(RULE_HEIGHT * (sequence and SEQ_VISIBLE_RULES or VISIBLE_RULES))
    c.seq:SetShown(sequence)
    c.sequenceMode:SetChecked(sequence)
    if sequence then self:RefreshSequencePanel() end

    -- Header
    local info = ns.Bars:GetSlotInfo(slot)
    c.icon:SetTexture(info.icon or QUESTION_MARK)
    c.title:SetText(info.name or (info.type and "Unknown action" or "Empty button"))
    c.sub:SetText(ns.Bars:Describe(slot))

    local saved = ns.db.designs[slot]
    if ns:IsPending("apply" .. slot) then
        c.status:SetText("|cffffff00Queued until combat ends|r")
    elseif saved and saved.detached then
        c.status:SetText("|cffff5555Detached: macro moved off this button|r")
    elseif saved then
        c.status:SetText("|cff33ff99Managed (" .. saved.macroName .. ")|r")
    else
        c.status:SetText("|cff808080Not managed yet|r")
    end

    self:RefreshRules()
    c.showtooltip:SetChecked(draft.showtooltip)
    c.showRanks:SetChecked(ns.db.showAllRanks)

    -- Preview and validation
    local text, length = B:Build(draft)
    c.preview:SetText(length > 0 and text or "|cff808080Add a row and choose a spell to start.|r")
    local tooLong = length > B.MAX_LENGTH
    c.counter:SetText(("%s%d/%d|r"):format(tooLong and "|cffff5555" or "|cffffffff", length, B.MAX_LENGTH))

    -- Only a button that isn't managed yet needs a new macro slot.
    local slotsFull, fullReason = false, nil
    if not saved then
        local ok, reason = ns.Manager:CanManageNew()
        slotsFull, fullReason = not ok, reason
    end

    local warnings = {}
    if tooLong then
        warnings[#warnings + 1] = "|cffff5555Too long. Remove a row or a condition.|r"
    end
    if slotsFull then
        warnings[#warnings + 1] = "|cffff5555" .. fullReason .. "|r"
    end
    for _, w in ipairs(B:Analyze(draft)) do
        warnings[#warnings + 1] = "|cffffff00" .. w .. "|r"
    end
    if InCombatLockdown() then
        warnings[#warnings + 1] = "|cffffff00In combat: Apply will wait until combat ends.|r"
    end
    c.warning:SetText(table.concat(warnings, "\n"))

    c.apply:SetEnabled(length > 0 and not tooLong and not slotsFull)
    c.revert:SetEnabled(saved ~= nil)
    c.reload:SetShown(ns.needsReload and true or false)
end
