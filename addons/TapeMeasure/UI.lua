local _, ns = ...
local C = ns.Compat

-- The Tape Measure window (Upgrades, Equipped, Stat Priority, Help) and the
-- Options > AddOns > Tape Measure panel. Laid out like Wally's window.
local UI = {}
ns.UI = UI

local win -- the window (shared\Window.lua), made under "Window" below

local W = ns.Widgets
local UNKNOWN_ICON = W.UNKNOWN_ICON
local Label, Muted, MakeButton, Hint = W.Label, W.Muted, W.MakeButton, W.Hint
local IconFor, CreateRowList = W.IconFor, W.CreateRowList

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

local function NewPage(name) return win:NewPage(name) end

local function CreateUpgradesPage()
    local p = NewPage("upgrades")
    Label(p, "Upgrades in your bags", "TapeMeasureGameFontNormalLarge", 0, 0)
    p.summary = Muted(Label(p, "", "TapeMeasureGameFontHighlightSmall", 0, -24, 460))
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
    Label(p, "What you wear", "TapeMeasureGameFontNormalLarge", 0, 0)
    p.summary = Muted(Label(p, "", "TapeMeasureGameFontHighlightSmall", 0, -24, 560))
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
    Label(p, "Stat priority", "TapeMeasureGameFontNormalLarge", 0, 0)
    p.summary = Muted(Label(p, "", "TapeMeasureGameFontHighlightSmall", 0, -24, 420))
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
    Label(p, "How Tape Measure decides", "TapeMeasureGameFontNormalLarge", 0, 0)
    local text = Label(p,
        "|cff55d6beYour stat priority|r\nTape Measure has no weights of its own. It reads your order from StatLedger (/statledger), the same list your other addons use. Rank 1 weighs 1.0, the last rank 0.1, and stats you haven't ranked count for nothing.\n\n" ..
        "|cff55d6beFair across stats|r\nOne percent of crit is worth far more than one Strength, so each stat is first converted to item budget: main stats 1, attack power 0.5, spell power 0.86, school spell power 0.7, healing 0.45, mp5 2.5, crit / spell crit / hit 14 per %, dodge 12 per %, parry 20 per %, weapon DPS 3, armor 0.04. The conversion is the same for everyone; only the ranks are yours.\n\n" ..
        "|cff55d6beThe tooltip|r\nShows Upgrade, Downgrade or Sidegrade (within " .. "your sidegrade band), the item it was compared with, and each stat that moves the score with its rank. Grey stats change but aren't on your list. Hold Shift for every line.\n\n" ..
        "|cff55d6beWhat it compares|r\nRings and trinkets: the weaker one you wear. Two-handers: main hand plus off hand. One-handers: either hand if you can dual wield, but never against a shield.\n\n" ..
        "|cffffcf73Not counted|r\nUse, Equip and Chance on hit effects, set bonuses and resistances. The tooltip says when an item has an effect Tape Measure can't score.",
        "TapeMeasureGameFontHighlightSmall", 0, -34, 560)
    text:SetSpacing(3); text:SetJustifyV("TOP")
end

-- ---------------------------------------------------------------------------
-- Settings page (Options > AddOns > Tape Measure)
-- Built with the shared OptionsPage.lua (addons/shared): /tape on|off, /tape minimap and the
-- window's Settings tab change the same options, so every UI shows the same value.
-- ---------------------------------------------------------------------------

local OPTION_DEFS = {
    { "enabled", "Enable Tape Measure", "Tooltips, bag highlights and the Upgrades list." },
    { "tooltip", "Item tooltips", "The verdict and the stats behind it on every gear tooltip." },
    { "tooltipCompact", "Compact tooltips", "Only the verdict and what it was compared with." },
    { "bagGlow", "Highlight upgrades in bags", "A green border on bag slots holding an upgrade." },
    { "bagPulse", "Pulse the border", "Turn off for a steady border." },
    { "bagPercent", "Percent badges", "+12.4%, or NEW for an empty slot, on the bag slot." },
}

local function Percent(v) return ("%.3g%%"):format(v) end

UI.page = ns.NewOptionsPage({ name = "Tape Measure", icon = true, build = function(p)
    p:Header(ns.IconMarkup(28) .. "  Tape Measure")
    for _, d in ipairs(OPTION_DEFS) do
        p:Check({ path = "db." .. d[1], label = d[2], tooltip = d[3] })
    end
    p:Check({ path = "char.minimap.hide", invert = true, label = "Minimap button", tooltip = "Tape Measure's minimap button (/tape minimap).",
        apply = function() if ns.MinimapButton then ns.MinimapButton:Refresh() end end })

    p:Header("Numbers")
    p:Slider({ path = "db.tooltipLines", label = "Stat lines in tooltips", min = 1, max = 30, step = 1,
        tooltip = "Hold Shift to see them all." })
    p:Slider({ path = "db.sidegrade", label = "Sidegrade band (%)", min = 0, max = 50, step = 0.5, format = Percent,
        tooltip = "Changes smaller than this are called a sidegrade." })
    p:Slider({ path = "db.minUpgrade", label = "Minimum upgrade (%)", min = 0, max = 50, step = 0.5, format = Percent,
        tooltip = "Smaller upgrades aren't highlighted or listed." })

    p:Header("Stat priority and preview")
    p:Button({ label = "Stat priority", text = "Edit stat priority", fn = function() ns:OpenStatLedger() end,
        tooltip = "Tape Measure's weights come from your stat order in StatLedger." })
    p:Button({ label = "Preview", text = "Test bag pulse", fn = function() ns.Bags:TestPulse() end,
        tooltip = "Open your bags: every item is marked TEST and flashes for six seconds." })
end })

function UI:OpenSettings()
    win:Hide()
    return self.page:Open()
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------

local TABS = {
    { "upgrades", "Upgrades", "INV_Misc_Bag_08" },
    { "equipped", "Equipped", "INV_Chest_Chain_05" },
    { "priority", "Stat Priority", "INV_Misc_Note_01" },
    { "help", "Help", "INV_Misc_Book_09" },
    { "settings", "Settings", "INV_Misc_Gear_01", onClick = function() UI:OpenSettings() end,
        hint = { "Settings", "Opens Options > AddOns > Tape Measure." } },
}

win = ns.NewWindow({
    name = "TapeMeasureWindow", title = "Tape Measure", subtitle = "Measures your gear against what you wear",
    tabs = TABS, active = "upgrades",
    refresh = function() UI:Refresh() end,
    sideNote = "Hover any gear to see\nwhy it's better or worse.\n\nHold Shift on a tooltip\nfor every stat line.",
    build = function() CreateUpgradesPage(); CreateEquippedPage(); CreatePriorityPage(); CreateHelpPage() end,
})
UI.window = win

function UI:Refresh()
    if not ns.db then return end
    win:Refresh()
end

function UI:Toggle()
    if not ns.db then return end
    win:Toggle()
end

function UI:Show(tab)
    if not ns.db then return end
    win:Show(tab)
end

function UI:Hide() win:Hide() end

ns:On("BAG_UPDATE_DELAYED", function() if win.active == "upgrades" then UI:Refresh() end end)
ns:On("PLAYER_EQUIPMENT_CHANGED", function() UI:Refresh() end)
