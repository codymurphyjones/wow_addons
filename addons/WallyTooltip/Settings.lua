local _, ns = ...

-- Options > AddOns > WallyTooltip (or /wtip options).
local S = {}
ns.Settings = S

function S:Register()
    if self.category or not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
    local category, layout = Settings.RegisterVerticalLayoutCategory("WallyTooltip")
    local CreateCheckbox = Settings.CreateCheckbox or Settings.CreateCheckBox
    local function Header(text)
        if layout and layout.AddInitializer and CreateSettingsListSectionHeaderInitializer then
            layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
        end
    end
    local function Checkbox(key, label, tooltip)
        if not CreateCheckbox then return end
        local setting = Settings.RegisterProxySetting(category, "WallyTooltip_" .. key, Settings.VarType.Boolean, label,
            ns.DEFAULTS[key] and true or false,
            function() return ns.db[key] and true or false end,
            function(value) ns.db[key] = value and true or false end)
        CreateCheckbox(category, setting, tooltip)
    end

    Header("WallyTooltip: tooltips that place themselves")
    Checkbox("enabled", "Smart placement",
        "Each tooltip goes where you can read it and where it covers nothing vital: your unit frames, action bars, "
        .. "the thing under your cursor, what the tooltip is about. Near what it's about when that's clear; along "
        .. "the screen's edges when it isn't; Edit Mode's tooltip spot only when everywhere would cover something "
        .. "vital. Off: Edit Mode's spot, as always (/wtip on | off).")
    Checkbox("glide", "Glide to a new spot",
        "A tooltip that's showing slides to a new spot instead of jumping: when it grows, when your cursor moves onto "
        .. "it, or when you point at something else while it's still fading.")
    Checkbox("combatAware", "Keep the fight clear",
        "In combat, and while you're moving, the middle of the screen (your character and the way ahead) is kept "
        .. "clearer, and tooltips go further out of the way rather than right beside the cursor.")
    Header("Troubleshooting")
    Checkbox("debug", "Say where each tooltip goes",
        "A line in chat for each tooltip: the spot it took and what it touched, or why it went to Edit Mode's spot "
        .. "(/wtip debug). /wtip status counts what it has done since you logged in.")

    Settings.RegisterAddOnCategory(category)
    self.category = category
end

function S:Open()
    if self.category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(self.category:GetID())
    else
        ns:Print("/wtip on | off, /wtip status, /wtip debug.")
    end
end

ns:On("PLAYER_LOGIN", function() S:Register() end)
