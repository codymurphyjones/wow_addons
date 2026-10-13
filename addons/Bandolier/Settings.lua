local _, ns = ...

-- Options > AddOns > Bandolier, built with Blizzard's Settings API.
local S = {}
ns.Settings = S

-- Bandolier's logo, shipped in the addon (Media\make_icon.py draws it).
S.ICON = "Interface\\AddOns\\Bandolier\\Media\\Icon"

-- The logo as inline text markup, size x size pixels.
function S.IconMarkup(size)
    return ("|T%s:%d:%d|t"):format(S.ICON, size, size)
end

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

-- Called from Core once SavedVariables are loaded.
function S:Register()
    if self.category or not (Settings and Settings.RegisterVerticalLayoutCategory) then return end

    -- The logo after the name (so the AddOns list still sorts by "Bandolier"),
    -- and a larger one heading the page.
    local category, layout = Settings.RegisterVerticalLayoutCategory("Bandolier " .. S.IconMarkup(16))
    if layout and layout.AddInitializer and CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(
            S.IconMarkup(28) .. "  Bandolier: every consumable on one key"))
    end

    local setting = Settings.RegisterProxySetting(category, "Bandolier_PrioritizeMana", Settings.VarType.Boolean,
        "Prioritize Mana", DefaultPrioritizeMana(),
        function() return S:PrioritizeMana() end,
        function(value)
            ns.db.prioritizeMana = value
            ns:RequestRefresh() -- rebuilds after combat if needed
        end)
    local CreateCheckbox = Settings.CreateCheckbox or Settings.CreateCheckBox
    CreateCheckbox(category, setting,
        "On: a plain press restores mana (drink, mana potions) and Shift+press restores health. "
        .. "Off: a plain press restores health (food, healthstones, healing potions) and Shift+press restores mana. "
        .. "Alt+press uses the next buff you don't have yet (flask, elixir, scroll, enhancement potion). With a fishing pole equipped, a press casts Fishing and Shift+press puts your weapons back on. Food that restores both is used first out of combat. "
        .. "On by default for classes that heal themselves with mana.")

    self:RegisterStatLedger(category, layout)

    Settings.RegisterAddOnCategory(category)
    self.category = category
end

-- Stat priority: a preset dropdown and five stat slots.
function S:RegisterStatLedger(category, layout)
    local CreateDropdown = Settings.CreateDropdown or Settings.CreateDropDown
    if not (CreateDropdown and Settings.CreateControlTextContainer and Settings.VarType.String) then
        return -- this client's Settings API has no dropdowns; /bandolier stats still works
    end
    if layout and layout.AddInitializer and CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Stat Priority"))
    end
    local T = ns.Stats

    local preset = Settings.RegisterProxySetting(category, "Bandolier_StatPreset", Settings.VarType.String,
        "Preset", "auto",
        function() return ns.db.statCustom and "custom" or T:Preset() end,
        function(value)
            if S.refreshing then return end
            if value ~= "custom" then T:SetPreset(value) end
            S:RefreshSlots()
        end)
    CreateDropdown(category, preset, function()
        local container = Settings.CreateControlTextContainer()
        if ns.db.statCustom then container:Add("custom", "Custom") end
        for _, id in ipairs(T.PresetIds()) do container:Add(id, T.PresetLabel(id)) end
        return container:GetData()
    end, "Which stats Bandolier favours when choosing buffs, enhancement potions and buff food. "
        .. "Automatic follows your class and the talent tree you've put the most points into. "
        .. "Changing any stat below makes it your own custom priority."
        .. (StatLedger and " Automatic uses the StatLedger addon's priority for your spec." or ""))

    local ordinals = { "1st", "2nd", "3rd", "4th", "5th" }
    self.slotSettings = {}
    for slot = 1, T.SLOTS do
        local setting = Settings.RegisterProxySetting(category, "Bandolier_Stat" .. slot, Settings.VarType.String,
            ordinals[slot] .. " stat", "NONE",
            function() return T:Priority()[slot] or "NONE" end,
            function(value)
                if S.refreshing then return end
                T:SetSlot(slot, value)
                S:RefreshSlots()
            end)
        CreateDropdown(category, setting, function()
            local container = Settings.CreateControlTextContainer()
            container:Add("NONE", "-")
            for _, stat in ipairs(T.ORDER) do container:Add(stat, T.LABELS[stat]) end
            return container:GetData()
        end, slot == 1 and "Counts the most. Each later stat counts less; a buff giving several of your stats adds them up." or nil)
        self.slotSettings[slot] = setting
    end
    self.presetSetting = preset
end

-- Show the current priority in the slot dropdowns (e.g. after picking a preset).
function S:RefreshSlots()
    if not self.slotSettings then return end
    self.refreshing = true
    for slot, setting in ipairs(self.slotSettings) do
        pcall(setting.SetValue, setting, ns.Stats:Priority()[slot] or "NONE")
    end
    if self.presetSetting then
        pcall(self.presetSetting.SetValue, self.presetSetting, ns.db.statCustom and "custom" or ns.Stats:Preset())
    end
    self.refreshing = false
end

function S:Open()
    if self.category and Settings.OpenToCategory then
        local ok = pcall(Settings.OpenToCategory, self.category:GetID())
        if ok then return end
    end
    ns:Print("Open the game menu > Options > AddOns > Bandolier.")
end
