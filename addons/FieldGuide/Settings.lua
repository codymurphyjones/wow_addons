local _, ns = ...

-- Options > AddOns > Field Guide, built with Blizzard's Settings API.
local S = {}
ns.Settings = S

local AUTO = "auto"

-- The sections of the guide you follow, for the dropdown: "Ashenvale  15-23".
local function SectionOptions()
    local container = Settings.CreateControlTextContainer()
    container:Add(AUTO, "Automatic")
    local guide = ns.Engine:Guide()
    for _, s in ipairs(guide and guide.sections or {}) do
        container:Add(s.id, ("%s  |cff8a948e%d-%d|r"):format(s.title, s.from or 1, s.to or 60))
    end
    return container:GetData()
end

-- Called once you're logged in (the guide depends on your faction).
function S:Register()
    if self.category or not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
    local category, layout = Settings.RegisterVerticalLayoutCategory("Field Guide " .. ns.IconMarkup(16))
    if layout and layout.AddInitializer and CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(ns.IconMarkup(28) .. "  Field Guide: Leveling guide"))
    end

    local CreateDropdown = Settings.CreateDropdown or Settings.CreateDropDown
    if CreateDropdown and Settings.CreateControlTextContainer and Settings.VarType.String then
        local zone = Settings.RegisterProxySetting(category, "FieldGuide_Section", Settings.VarType.String,
            "Zone guide", AUTO,
            function() return ns.char.section or AUTO end,
            function(value) ns.Engine:SetSection(value ~= AUTO and value or nil) end)
        CreateDropdown(category, zone, SectionOptions,
            "Which zone's leveling guide to follow. Automatic: the zone you're in when it has quests worth "
            .. "doing at your level, otherwise the one you were on, or the nearest one for your level. "
            .. "Automatic looks at zones within 4 levels of yours either way, and prefers the ones whose quests "
            .. "are at your level to 2 above. Walking into a zone that doesn't suit you now (under your level, or "
            .. "more than 2 above it) counts as traveling: the zone you were on stays. Nothing changes while you're on a flight. "
            .. "A zone you pick here stays until you pick Automatic again (/fg section auto).")
    end

    local CreateCheckbox = Settings.CreateCheckbox or Settings.CreateCheckBox
    if CreateCheckbox then
        local dock = Settings.RegisterProxySetting(category, "FieldGuide_Dock", Settings.VarType.Boolean,
            "Sit under Waypoint's arrow", true,
            function() return ns.db.dock and true or false end,
            function(value)
                ns.db.dock = value and true or false
                if ns.UI then ns.UI:Dock() end
            end)
        CreateCheckbox(category, dock,
            "The guide window sits under Waypoint's arrow and moves with it (the arrow's right-click menu sets left, center or right). "
            .. "Off: drag the guide anywhere on its own (/fg dock).")
    end

    if CreateCheckbox then
        local tracking = Settings.RegisterProxySetting(category, "FieldGuide_Tracking", Settings.VarType.Boolean,
            "Manage quest tracking", true,
            function() return ns.db.manageTracking and true or false end,
            function(value)
                ns.db.manageTracking = value and true or false
                ns:Changed()
            end)
        CreateCheckbox(category, tracking,
            "The guide tracks the quests your next steps are about, and untracks the other quests addons tracked. "
            .. "Quests you track yourself stay tracked until they're done or you untrack them, and come first on the arrow "
            .. "(over the guide's step while the guide window is closed). A quest you untrack yourself isn't tracked again.")
    end

    Settings.RegisterAddOnCategory(category)
    self.category = category
end

function S:Open()
    if self.category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(self.category:GetID())
    end
end

ns:On("PLAYER_LOGIN", function() S:Register() end)
