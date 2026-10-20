local _, ns = ...

-- Options > AddOns > WallyHUD. The suite's name lives here, not on the HUD.
local S = {}
ns.Settings = S

function S:Register()
    if self.category or not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
    local category, layout = Settings.RegisterVerticalLayoutCategory("WallyHUD")
    local CreateCheckbox = Settings.CreateCheckbox or Settings.CreateCheckBox
    local CreateDropdown = Settings.CreateDropdown or Settings.CreateDropDown

    local function Header(text)
        if layout and layout.AddInitializer and CreateSettingsListSectionHeaderInitializer then
            layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
        end
    end
    local function Checkbox(key, label, tooltip, after)
        if not CreateCheckbox then return end
        local setting = Settings.RegisterProxySetting(category, "WallyHUD_" .. key, Settings.VarType.Boolean, label,
            ns.DEFAULTS[key] and true or false,
            function() return ns.db[key] and true or false end,
            function(value)
                ns.db[key] = value and true or false
                if after then after(value) end
            end)
        CreateCheckbox(category, setting, tooltip)
    end

    Header("WallyHUD: one look for the suite")
    if CreateDropdown and Settings.CreateControlTextContainer and Settings.VarType.String then
        local density = Settings.RegisterProxySetting(category, "WallyHUD_Density", Settings.VarType.String,
            "Density", "standard",
            function() return ns.db.density or "standard" end,
            function(value) ns.Density:Set(value) end)
        CreateDropdown(category, density, function()
            local c = Settings.CreateControlTextContainer()
            c:Add("minimal", "Minimal")
            c:Add("standard", "Standard")
            c:Add("expanded", "Expanded")
            return c:GetData()
        end, "How much the HUD shows. Minimal: the clock and performance on the status rail, no minimap buttons. "
            .. "Standard: everything you've set up, without memory use. Expanded: everything (/whud minimal | standard | expanded).")
    end
    Checkbox("suiteLook", "Shared look for our addons",
        "Our addons' windows, popups and bars in one look: see-through surfaces, 1px hairlines, one teal accent, "
        .. "colour only for state, and one font (Roboto Condensed) in its weights. Takes a /reload to switch.")
    Checkbox("minimapButtons", "Quiet minimap buttons",
        "Minimap buttons without the gold rings: monochrome icons, in colour under the mouse. Takes a /reload to switch off.",
        function(on) if on then ns.MinimapButtons:Apply() end end)
    Checkbox("questieSkin", "Objectives (Questie's tracker) in the suite's look",
        "Questie's quest tracker restyled from here, its files untouched: OBJECTIVES header, zone names in capitals, "
        .. "quest titles in plain text with the level after them, the focused quest marked with an accent bar, thin "
        .. "progress bars under goals with a count, and Ready to turn in for finished quests. A /reload to switch off.",
        function(on) if on and ns.Questie then ns.Questie:Apply() end end)
    Header("Issue reporting")
    Checkbox("hideReporter", "Keep the Issue Reporter out of the way",
        "Blizzard's Issue Reporter stays hidden until you want it: Ctrl+Shift+/ (Key Bindings > AddOns > WallyHUD), "
        .. "/whud report, or Report on the error notice.",
        function(on) if on then ns.Reporter:Apply() end end)
    Checkbox("errorToast", "Notice on addon errors",
        "A small notice in the bottom right when an addon error happens, with Report and Dismiss. It fades after 10 seconds.")

    Settings.RegisterAddOnCategory(category)
    self.category = category
end

function S:Open()
    if self.category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(self.category:GetID())
    else
        ns:Print("/whud minimal | standard | expanded, /whud report.")
    end
end

ns:On("PLAYER_LOGIN", function() S:Register() end)
