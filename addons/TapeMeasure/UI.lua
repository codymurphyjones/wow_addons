local _, ns = ...
local C = ns.Compat

-- The Tape Measure window (Upgrades, Equipped, Stat Priority, Help) and the
-- Options > AddOns > Tape Measure panel. Laid out like Wally's window.
local UI = {}
ns.UI = UI

local frame
local pages, tabs = {}, {}
local activeTab = "upgrades"

local W = ns.Widgets
local ACCENT, UNKNOWN_ICON = W.ACCENT, W.UNKNOWN_ICON
local SetBackdrop, Label, Muted, MakeButton, Hint = W.SetBackdrop, W.Label, W.Muted, W.MakeButton, W.Hint
local MakeCheckbox, MakeEditBox, IconFor, CreateRowList = W.MakeCheckbox, W.MakeEditBox, W.IconFor, W.CreateRowList

local GOOD, BAD = { 0.35, 0.96, 0.55 }, { 1, 0.42, 0.42 }

local STAT_ICONS = {
    STR = "Spell_Nature_Strength", AGI = "Spell_Holy_BlessingOfAgility", STA = "Spell_Holy_WordFortitude",
    INT = "Spell_Holy_MagicalSentry", SPI = "Spell_Holy_DivineSpirit",
    AP = "Ability_Warrior_BattleShout", RAP = "INV_Weapon_Bow_07", SP = "INV_Staff_13", HEAL = "Spell_Holy_Heal",
    FIRE = "Spell_Fire_FireBolt02", FROST = "Spell_Frost_FrostBolt02", SHADOW = "Spell_Shadow_ShadowBolt",
    ARCANE = "Spell_Nature_StarFall", NATURE = "Spell_Nature_Lightning",
    CRIT = "Ability_CriticalStrike", SPELLCRIT = "Spell_Fire_Fireball02", HIT = "Ability_Marksmanship",
    HASTE = "Spell_Nature_Bloodlust", MP5 = "Spell_Nature_ManaRegenTotem",
    ARMOR = "Spell_Holy_DevotionAura", DEF = "Ability_Warrior_DefensiveStance", DODGE = "Spell_Nature_Invisibilty",
    PARRY = "Ability_Parry", BLOCK = "INV_Shield_06", BLOCKVALUE = "Ability_Defend", DPS = "INV_Sword_27",
}
local function StatIcon(stat) return "Interface\\Icons\\" .. (STAT_ICONS[stat] or "INV_Misc_QuestionMark") end

-- ---------------------------------------------------------------------------
-- Pages
-- ---------------------------------------------------------------------------

local function NewPage(name)
    local p = CreateFrame("Frame", nil, frame)
    p:SetPoint("TOPLEFT", 196, -76); p:SetPoint("BOTTOMRIGHT", -18, 18)
    p:Hide(); pages[name] = p
    return p
end

local function CreateUpgradesPage()
    local p = NewPage("upgrades")
    Label(p, "Upgrades in your bags", "GameFontNormalLarge", 0, 0)
    p.summary = Muted(Label(p, "", "GameFontHighlightSmall", 0, -24, 460))
    local rescan = MakeButton(p, "Rescan", 84, 26); rescan:SetPoint("TOPRIGHT", 0, 4)
    rescan:SetScript("OnClick", function() C.ResetRequests(); ns.Stats:ClearCache(); ns:Changed() end)
    Hint(rescan, "Rescan", "Reads every item again, including ones that hadn't loaded.")
    p.list = CreateRowList(p, -50)

    p.Refresh = function()
        local items = {}
        local results = ns.Scoring:ScanBags()
        for _, r in ipairs(results) do
            local cmp = r.cmp
            local replaces = cmp.verdict == "new" and ("Empty " .. cmp.label)
                or ("Replaces " .. table.concat(cmp.replaced, " + "))
            local reasons = ns.Scoring:Reasons(cmp, 3)
            items[#items + 1] = {
                icon = IconFor({ link = r.link }), text = r.link, link = r.link,
                detail = replaces .. (reasons ~= "" and ("  -  " .. reasons) or ""),
                bar = cmp.percent and math.min(1, cmp.percent / 50) or 1,
                barText = ns.Scoring:FormatChange(cmp),
                hint = "Shift-click to link it. The tooltip above explains the verdict.",
            }
        end
        p.summary:SetText(("%d upgrade%s for %s. Ranked with your StatLedger order."):format(
            #results, #results == 1 and "" or "s", ns:ColoredSpecText()))
        p.list:Set(items, "No upgrades in your bags right now.\n\nNew items can take a moment to load.")
    end
end

local function CreateEquippedPage()
    local p = NewPage("equipped")
    Label(p, "What you wear", "GameFontNormalLarge", 0, 0)
    p.summary = Muted(Label(p, "", "GameFontHighlightSmall", 0, -24, 560))
    p.list = CreateRowList(p, -50, { rowHeight = 32 })

    p.Refresh = function()
        local rows, best, total = {}, 0, 0
        for _, slot in ipairs(ns.Scoring.SLOT_ORDER) do
            local link = GetInventoryItemLink("player", slot)
            local s = link and ns.Scoring:Score(link)
            if s then best = math.max(best, s.total); total = total + s.total end
            rows[#rows + 1] = { slot = slot, link = link, s = s }
        end
        local items = {}
        for _, r in ipairs(rows) do
            local name = ns.Scoring.SLOT_NAMES[r.slot]
            if not r.link then
                items[#items + 1] = { icon = UNKNOWN_ICON, text = "|cff7f8c94Empty|r", detail = name, dim = 0.5 }
            elseif not r.s then
                items[#items + 1] = { icon = IconFor({ link = r.link }), text = r.link, link = r.link, detail = name .. "  -  loading" }
            else
                local parts = {}
                for stat, c in pairs(r.s.contrib) do parts[#parts + 1] = { stat = stat, c = c } end
                table.sort(parts, function(a, b) return a.c > b.c end)
                local top = {}
                for i = 1, math.min(3, #parts) do top[i] = ns.Stats:Label(parts[i].stat) end
                items[#items + 1] = {
                    icon = IconFor({ link = r.link }), text = r.link, link = r.link,
                    detail = name .. "  -  " .. (#top > 0 and table.concat(top, ", ") or "nothing on your priority list"),
                    bar = best > 0 and r.s.total / best or 0, barText = ns.Scoring:FormatScore(r.s.total),
                }
            end
        end
        p.summary:SetText(("Total score %s for %s. Short bars are your weakest slots."):format(
            ns.Scoring:FormatScore(total), ns:ColoredSpecText()))
        p.list:Set(items)
    end
end

local function CreatePriorityPage()
    local p = NewPage("priority")
    Label(p, "Stat priority", "GameFontNormalLarge", 0, 0)
    p.summary = Muted(Label(p, "", "GameFontHighlightSmall", 0, -24, 420))
    local edit = MakeButton(p, "Edit in StatLedger", 140, 26); edit:SetPoint("TOPRIGHT", 0, 4)
    edit:SetScript("OnClick", function() ns:OpenStatLedger() end)
    Hint(edit, "StatLedger", "Your stat order lives in the StatLedger addon and is shared with your other addons. Tape Measure updates as soon as you change it.")
    p.list = CreateRowList(p, -50, { rowHeight = 30 })

    p.Refresh = function()
        local items = {}
        for i, stat in ipairs(StatLedger:GetPriority()) do
            local weight = ns.Scoring:Weight(stat)
            -- StatLedger's prices: per percent for crit and the like, for your class and
            -- level; the score per unit also counts what the stat produces (Agility's crit).
            local budget = StatLedger:Budget(stat, 1)
            local unit = StatLedger:IsPercent(stat, 1) and "1%" or "1 point"
            items[#items + 1] = {
                icon = StatIcon(stat), text = ("#%d  %s"):format(i, ns.Stats:Label(stat)),
                detail = ("Weight %.2f  x  %s per %s  =  %s score per %s"):format(weight, ns.Stats:FormatNumber(budget), unit,
                    ns.Scoring:FormatScore(StatLedger:Value(stat, 1)), unit),
                bar = weight, barText = ("%.2f"):format(weight),
            }
        end
        for _, stat in ipairs(StatLedger:GetRemovedStats()) do
            items[#items + 1] = {
                icon = StatIcon(stat), text = "|cff7f8c94Not ranked|r  " .. ns.Stats:Label(stat),
                detail = "Worth nothing to this spec. Add it in StatLedger to count it.", dim = 0.5,
            }
        end
        p.summary:SetText(("%s, %s list. Rank 1 weighs 1.0, falling evenly to 0.1 at the last."):format(
            ns:ColoredSpecText(), StatLedger:IsCustom() and "your own" or "the default"))
        p.list:Set(items)
    end
end

local function CreateHelpPage()
    local p = NewPage("help")
    Label(p, "How Tape Measure decides", "GameFontNormalLarge", 0, 0)
    local text = Label(p,
        "|cff55d6beYour stat priority|r\nTape Measure has no weights of its own. It reads your order from StatLedger (/statledger), the same list your other addons use. Rank 1 weighs 1.0, the last rank 0.1, and stats you haven't ranked count for nothing.\n\n" ..
        "|cff55d6beFair across stats|r\nOne percent of crit is worth far more than one Strength, so each stat is first converted to item budget: main stats 1, attack power 0.5, spell power 0.86, school spell power 0.7, healing 0.45, mp5 2.5, crit / spell crit / hit 14 per %, dodge 12 per %, parry 20 per %, weapon DPS 3, armor 0.04. The conversion is the same for everyone; only the ranks are yours.\n\n" ..
        "|cff55d6beThe tooltip|r\nShows Upgrade, Downgrade or Sidegrade (within " .. "your sidegrade band), the item it was compared with, and each stat that moves the score with its rank. Grey stats change but aren't on your list. Hold Shift for every line.\n\n" ..
        "|cff55d6beWhat it compares|r\nRings and trinkets: the weaker one you wear. Two-handers: main hand plus off hand. One-handers: either hand if you can dual wield, but never against a shield.\n\n" ..
        "|cffffcf73Not counted|r\nUse, Equip and Chance on hit effects, set bonuses and resistances. The tooltip says when an item has an effect Tape Measure can't score.",
        "GameFontHighlightSmall", 0, -34, 560)
    text:SetSpacing(3); text:SetJustifyV("TOP")
end

-- ---------------------------------------------------------------------------
-- Settings panel (Options > AddOns > Tape Measure)
-- ---------------------------------------------------------------------------

local OPTION_DEFS = {
    { "enabled", "Enable Tape Measure", "Tooltips, bag highlights and the Upgrades list." },
    { "tooltip", "Item tooltips", "The verdict and the stats behind it on every gear tooltip." },
    { "tooltipCompact", "Compact tooltips", "Only the verdict and what it was compared with." },
    { "bagGlow", "Highlight upgrades in bags", "A green border on bag slots holding an upgrade." },
    { "bagPulse", "Pulse the border", "Turn off for a steady border." },
    { "bagPercent", "Percent badges", "+12.4%, or NEW for an empty slot, on the bag slot." },
}

local NUMBER_DEFS = {
    { "tooltipLines", "Stat lines in tooltips", "Hold Shift to see them all.", 1, 30 },
    { "sidegrade", "Sidegrade band (%)", "Changes smaller than this are called a sidegrade.", 0, 50 },
    { "minUpgrade", "Minimum upgrade (%)", "Smaller upgrades aren't highlighted or listed.", 0, 1000 },
}

local settingsPanel, settingsCategory

local function BuildSettings(p)
    local logo = p:CreateTexture(nil, "ARTWORK"); logo:SetSize(28, 28)
    logo:SetPoint("TOPLEFT", 0, 6); logo:SetTexture(ns.ICON)
    Label(p, "Tape Measure", "GameFontNormalLarge", 36, 0):SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    local prio = MakeButton(p, "Edit stat priority", 130, 26); prio:SetPoint("TOPRIGHT", 0, 4)
    prio:SetScript("OnClick", function() ns:OpenStatLedger() end)
    Hint(prio, "StatLedger", "Tape Measure's weights come from your stat order in StatLedger.")
    local test = MakeButton(p, "Test bag pulse", 110, 26); test:SetPoint("RIGHT", prio, "LEFT", -8, 0)
    test:SetScript("OnClick", function() ns.Bags:TestPulse() end)
    Hint(test, "Preview", "Open your bags: every item is marked TEST and flashes for six seconds.")

    p.checks = {}
    for i, d in ipairs(OPTION_DEFS) do
        local y = -34 - (i - 1) * 44
        local b = MakeCheckbox(p, d[2]); b:SetPoint("TOPLEFT", -4, y)
        b:SetScript("OnClick", function(self) ns.db[d[1]] = self:GetChecked() and true or false; ns:Changed() end)
        Muted(Label(p, d[3], "GameFontHighlightSmall", 27, y - 25, 270))
        p.checks[d[1]] = b
    end
    local mini = MakeCheckbox(p, "Minimap button"); mini:SetPoint("TOPLEFT", -4, -34 - #OPTION_DEFS * 44)
    mini:SetScript("OnClick", function(self)
        ns.char.minimap.hide = not self:GetChecked()
        ns.MinimapButton:Refresh()
    end)
    p.mini = mini

    local col = 330
    p.numbers = {}
    for i, d in ipairs(NUMBER_DEFS) do
        local y = -38 - (i - 1) * 64
        Label(p, d[2], "GameFontHighlight", col, y)
        local box = MakeEditBox(p, 60); box:SetPoint("TOPLEFT", col + 180, y + 6)
        box:SetJustifyH("CENTER")
        box:SetScript("OnEditFocusLost", function(self)
            local v = tonumber(self:GetText())
            if v then ns.db[d[1]] = math.max(d[4], math.min(d[5], v)) end
            self:SetText(tostring(ns.db[d[1]]))
            ns:Changed()
        end)
        Muted(Label(p, d[3], "GameFontHighlightSmall", col, y - 20, 260))
        p.numbers[d[1]] = box
    end

    p.Refresh = function()
        for key, b in pairs(p.checks) do b:SetChecked(ns.db[key]) end
        p.mini:SetChecked(not ns.char.minimap.hide)
        for key, box in pairs(p.numbers) do
            if not box:HasFocus() then box:SetText(tostring(ns.db[key])) end
        end
    end
end

local function CreateSettingsPanel()
    settingsPanel = CreateFrame("Frame", "TapeMeasureSettingsPanel")
    settingsPanel.name = "Tape Measure"
    local view = CreateFrame("Frame", nil, settingsPanel)
    view:SetPoint("TOPLEFT", 16, -16); view:SetPoint("BOTTOMRIGHT", -16, 16)
    settingsPanel.view = view
    -- A new parentless frame counts as shown, so OnShow would never fire. Start hidden.
    settingsPanel:Hide()
    settingsPanel:SetScript("OnShow", function()
        if not view.Refresh then BuildSettings(view) end
        view.Refresh()
    end)
    if Settings and Settings.RegisterCanvasLayoutCategory then
        settingsCategory = Settings.RegisterCanvasLayoutCategory(settingsPanel, "Tape Measure")
        Settings.RegisterAddOnCategory(settingsCategory)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(settingsPanel)
    end
end
ns:OnLoad(CreateSettingsPanel)

function UI:OpenSettings()
    if frame then frame:Hide() end
    if Settings and Settings.OpenToCategory and settingsCategory then
        Settings.OpenToCategory(settingsCategory:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        -- Called twice: the old options frame ignores the first call when it isn't open yet.
        InterfaceOptionsFrame_OpenToCategory(settingsPanel); InterfaceOptionsFrame_OpenToCategory(settingsPanel)
    end
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------

local TABS = {
    { "upgrades", "Upgrades", "INV_Misc_Bag_08" },
    { "equipped", "Equipped", "INV_Chest_Chain_05" },
    { "priority", "Stat Priority", "INV_Misc_Note_01" },
    { "help", "Help", "INV_Misc_Book_09" },
    { "settings", "Settings", "INV_Misc_Gear_01" },
}

local function ShowTab(name)
    activeTab = name
    for key, p in pairs(pages) do p:SetShown(key == name) end
    for key, b in pairs(tabs) do
        b.selected:SetShown(key == name)
        b:SetBackdropColor(key == name and 0.09 or 0.075, key == name and 0.15 or 0.105, key == name and 0.17 or 0.13, 1)
    end
end

local function CreateMainFrame()
    if frame then return end
    frame = CreateFrame("Frame", "TapeMeasureWindow", UIParent, "BackdropTemplate")
    frame:SetSize(800, 560); frame:SetFrameStrata("DIALOG"); frame:SetToplevel(true)
    frame:SetClampedToScreen(true); frame:SetMovable(true); frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton"); SetBackdrop(frame, 0.985)
    local w = ns.char.window
    frame:SetPoint(w.point or "CENTER", UIParent, w.point or "CENTER", w.x or 0, w.y or 0)
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        ns.char.window = { point = point, x = x, y = y }
    end)
    frame:SetScript("OnShow", function() UI:Refresh() end)
    tinsert(UISpecialFrames, "TapeMeasureWindow")

    local logo = frame:CreateTexture(nil, "ARTWORK"); logo:SetSize(38, 38)
    logo:SetPoint("TOPLEFT", 20, -17); logo:SetTexture(ns.ICON)
    Label(frame, "Tape Measure", "GameFontNormalLarge", 70, -20):SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    Muted(Label(frame, "Measures your gear against what you wear", "GameFontHighlightSmall", 70, -42))
    local close = MakeButton(frame, "X", 28, 26); close:SetPoint("TOPRIGHT", -18, -18)
    close:SetScript("OnClick", function() frame:Hide() end)

    local side = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    side:SetPoint("TOPLEFT", 14, -74); side:SetPoint("BOTTOMLEFT", 14, 14); side:SetWidth(165)
    SetBackdrop(side); side:SetBackdropColor(0.045, 0.065, 0.085, 1)
    for i, d in ipairs(TABS) do
        local b = MakeButton(side, d[2], 147, 40); b:SetPoint("TOPLEFT", 9, -12 - (i - 1) * 46)
        b.text:ClearAllPoints(); b.text:SetPoint("LEFT", 40, 0)
        local icon = b:CreateTexture(nil, "ARTWORK"); icon:SetSize(23, 23); icon:SetPoint("LEFT", 9, 0)
        icon:SetTexture("Interface\\Icons\\" .. d[3]); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.selected = b:CreateTexture(nil, "OVERLAY"); b.selected:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
        b.selected:SetPoint("TOPLEFT"); b.selected:SetPoint("BOTTOMLEFT"); b.selected:SetWidth(3)
        b:SetScript("OnLeave", function(self) if activeTab ~= d[1] then self:SetBackdropColor(0.075, 0.105, 0.13, 1) end end)
        if d[1] == "settings" then
            b:SetScript("OnClick", function() UI:OpenSettings() end)
            Hint(b, "Settings", "Opens Options > AddOns > Tape Measure.")
        else
            b:SetScript("OnClick", function() ShowTab(d[1]); UI:Refresh() end)
        end
        tabs[d[1]] = b
    end
    Muted(Label(side, "Hover any gear to see\nwhy it's better or worse.\n\nHold Shift on a tooltip\nfor every stat line.", "GameFontHighlightSmall", 12, -14 - #TABS * 46, 145))
    Label(side, "v" .. ns.VERSION, "GameFontHighlightSmall", 12, -450, 145):SetTextColor(0.38, 0.50, 0.57)

    CreateUpgradesPage(); CreateEquippedPage(); CreatePriorityPage(); CreateHelpPage()
    ShowTab(activeTab); frame:Hide()
end

function UI:Refresh()
    if not ns.db then return end
    if settingsPanel and settingsPanel.view.Refresh and settingsPanel:IsVisible() then settingsPanel.view.Refresh() end
    if not frame or not frame:IsShown() then return end
    local p = pages[activeTab]
    if p and p.Refresh then p.Refresh() end
end

function UI:Toggle()
    if not ns.db then return end
    CreateMainFrame()
    frame:SetShown(not frame:IsShown())
end

function UI:Show(tab)
    if not ns.db then return end
    CreateMainFrame()
    if tab then ShowTab(tab) end
    frame:Show(); self:Refresh()
end

function UI:Hide()
    if frame then frame:Hide() end
end

ns:On("BAG_UPDATE_DELAYED", function() if activeTab == "upgrades" then UI:Refresh() end end)
ns:On("PLAYER_EQUIPMENT_CHANGED", function() UI:Refresh() end)
