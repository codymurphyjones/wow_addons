local _, ns = ...

-- Options > AddOns > Bandolier, built with the shared OptionsPage.lua (addons/shared): Prioritize
-- Mana and the stat priority. /bandolier stats reset changes the same options, so the page shows it.
local S = {}
ns.Settings = S

-- Bandolier's logo (ns.ICON, Core.lua) and its inline text markup (the shared Core.lua).
S.ICON = ns.ICON
S.IconMarkup = ns.IconMarkup

-- Classes that heal themselves with mana start with Prioritize Mana on.
local MANA_HEALERS = { PRIEST = true, PALADIN = true, DRUID = true, SHAMAN = true }

local function DefaultPrioritizeMana()
    local _, class = UnitClass("player")
    return MANA_HEALERS[class] or false
end

-- Is mana the primary resource (plain press), with health on Shift?
function S:PrioritizeMana()
    local value = ns.db and ns.db.prioritizeMana
    if value == nil then return DefaultPrioritizeMana() end
    return value
end

-- The page refreshes every control after any change, so picking a preset shows its five stats
-- and changing a stat shows "Custom".
local function PresetChoices()
    local T = ns.Stats
    local out = {}
    if ns.db.statCustom then out[#out + 1] = { "custom", "Custom" } end
    for _, id in ipairs(T.PresetIds()) do out[#out + 1] = { id, T.PresetLabel(id) } end
    return out
end

local function StatChoices()
    local out = { { "NONE", "-" } }
    for _, stat in ipairs(ns.Stats.ORDER) do out[#out + 1] = { stat, ns.Stats.LABELS[stat] } end
    return out
end

S.page = ns.NewOptionsPage({ name = "Bandolier", icon = true, build = function(p)
    p:Header(S.IconMarkup(28) .. "  Bandolier: every consumable on one key")
    p:Check({ id = "PrioritizeMana", path = "db.prioritizeMana", label = "Prioritize Mana", default = DefaultPrioritizeMana(),
        get = function() return S:PrioritizeMana() end,
        apply = function() ns:RequestRefresh() end, -- rebuilds after combat if needed
        tooltip = "On: a plain press restores mana (drink, mana potions) and Shift+press restores health. "
            .. "Off: a plain press restores health (food, healthstones, healing potions) and Shift+press restores mana. "
            .. "Alt+press uses the next buff you don't have yet (flask, elixir, scroll, enhancement potion). With a fishing pole equipped, a press casts Fishing and Shift+press puts your weapons back on. Food that restores both is used first out of combat. "
            .. "On by default for classes that heal themselves with mana." })

    local T = ns.Stats
    p:Header("Stat Priority")
    p:Dropdown({ id = "StatPreset", label = "Preset", default = "auto", choices = PresetChoices,
        get = function() return ns.db.statCustom and "custom" or T:Preset() end,
        set = function(value) if value ~= "custom" then T:SetPreset(value) end end,
        tooltip = "Which stats Bandolier favours when choosing buffs, enhancement potions and buff food. "
            .. "Automatic follows your class and the talent tree you've put the most points into. "
            .. "Changing any stat below makes it your own custom priority."
            .. (StatLedger and " Automatic uses the StatLedger addon's priority for your spec." or "") })
    local ordinals = { "1st", "2nd", "3rd", "4th", "5th" }
    for slot = 1, T.SLOTS do
        p:Dropdown({ id = "Stat" .. slot, label = ordinals[slot] .. " stat", default = "NONE", choices = StatChoices,
            get = function() return T:Priority()[slot] or "NONE" end,
            set = function(value) T:SetSlot(slot, value) end,
            tooltip = slot == 1 and "Counts the most. Each later stat counts less; a buff giving several of your stats adds them up." or nil })
    end
end })

function S:Open() return self.page:Open() end
