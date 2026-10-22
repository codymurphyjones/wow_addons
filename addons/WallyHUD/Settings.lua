local _, ns = ...

-- Options > AddOns > WallyHUD. The suite's name lives here, not on the HUD. Built with the shared
-- OptionsPage.lua (addons/shared); /whud minimal | standard | expanded changes the same option.
local S = {}
ns.Settings = S

S.page = ns.NewOptionsPage({ name = "WallyHUD", build = function(p)
    p:Header("WallyHUD: one look for the suite")
    -- Density:Set saves it through ns:SetOption (its apply lays the HUD out) and says so in chat.
    p:Dropdown({ id = "Density", path = "db.density", label = "Density",
        choices = { { "minimal", "Minimal" }, { "standard", "Standard" }, { "expanded", "Expanded" } },
        set = function(value) ns.Density:Set(value) end,
        apply = function() ns.Density:Apply() end,
        tooltip = "How much the HUD shows. Minimal: the clock and performance on the status rail, no minimap buttons. "
            .. "Standard: everything you've set up, without memory use. Expanded: everything (/whud minimal | standard | expanded)." })
    p:Check({ id = "suiteLook", path = "db.suiteLook", label = "Shared look for our addons",
        tooltip = "Our addons' windows, popups and bars in one look: see-through surfaces, 1px hairlines, one teal accent, "
            .. "colour only for state, and one font (Roboto Condensed) in its weights. Takes a /reload to switch." })
    p:Check({ id = "minimapButtons", path = "db.minimapButtons", label = "Quiet minimap buttons",
        tooltip = "Minimap buttons without the gold rings: monochrome icons, in colour under the mouse. Takes a /reload to switch off.",
        apply = function(on) if on then ns.MinimapButtons:Apply() end end })
    p:Check({ id = "questieSkin", path = "db.questieSkin", label = "Objectives (Questie's tracker) in the suite's look",
        tooltip = "Questie's quest tracker restyled from here, its files untouched: OBJECTIVES header, zone names in capitals, "
            .. "quest titles in plain text with the level after them, the focused quest marked with an accent bar, thin "
            .. "progress bars under goals with a count, and Ready to turn in for finished quests. A /reload to switch off.",
        apply = function(on) if on and ns.Questie then ns.Questie:Apply() end end })
    p:Header("Issue reporting")
    p:Check({ id = "hideReporter", path = "db.hideReporter", label = "Keep the Issue Reporter out of the way",
        tooltip = "Blizzard's Issue Reporter stays hidden until you want it: Ctrl+Shift+/ (Key Bindings > AddOns > WallyHUD), "
            .. "/whud report, or Report on the error notice.",
        apply = function(on) if on then ns.Reporter:Apply() end end })
    p:Check({ id = "errorToast", path = "db.errorToast", label = "Notice on addon errors",
        tooltip = "A small notice in the bottom right when an addon error happens, with Report and Dismiss. It fades after 10 seconds." })
end })

function S:Open()
    if not self.page.headless then return self.page:Open() end
    ns:Print("/whud minimal | standard | expanded, /whud report.")
end
