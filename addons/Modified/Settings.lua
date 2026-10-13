local ADDON, ns = ...

-- Options > AddOns > Modified, built with Blizzard's Settings API.
local S = {}
ns.Settings = S

-- Called from Core once SavedVariables are loaded.
function S:Register()
    if self.category or not (Settings and Settings.RegisterVerticalLayoutCategory) then return end

    local category = Settings.RegisterVerticalLayoutCategory("Modified")
    local _, max = ns.Manager:CharacterMacroUsage()

    local limit = Settings.RegisterProxySetting(category, "Modified_MacroLimit", Settings.VarType.Number,
        "Character macro limit", math.min(ns.Manager.DEFAULT_LIMIT, max),
        function() return (ns.Manager:GetLimit()) end,
        function(value) ns.Manager:SetLimit(value) end)
    local options = Settings.CreateSliderOptions(1, max, 1)
    if MinimalSliderWithSteppersMixin then
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
    end
    Settings.CreateSlider(category, limit, options,
        ("How many of your %d character macros Modified may use, so the rest stay free for your own macros. "
        .. "Buttons that are already managed keep working if you lower this; new ones can't be added "
        .. "until Modified is back under the limit."):format(max))

    local reload = Settings.RegisterProxySetting(category, "Modified_AutoReload", Settings.VarType.Boolean,
        "Reload UI after Apply/Revert", true,
        function() return ns.db.autoReload end,
        function(value) ns.db.autoReload = value end)
    local CreateCheckbox = Settings.CreateCheckbox or Settings.CreateCheckBox
    CreateCheckbox(category, reload,
        "Changing macros and action buttons from an addon makes Blizzard's action bars throw cooldown errors "
        .. "until the UI is reloaded. With this on, Modified reloads right after you apply or revert a button. "
        .. "With it off, click Reload UI in /mod (or type /reload) before your next fight.")

    Settings.RegisterAddOnCategory(category)
    self.category = category
end

function S:Open()
    if self.category and Settings.OpenToCategory then
        local ok = pcall(Settings.OpenToCategory, self.category:GetID())
        if ok then return end
    end
    ns:Print("Open the game menu > Options > AddOns > Modified.")
end
