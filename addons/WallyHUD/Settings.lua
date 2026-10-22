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
    p:Header("Vitals: your health and power, drawn into the screen")
    p:Check({ id = "vitals", path = "db.vitals", label = "The line (health and power across the screen)",
        tooltip = "One faint line across the screen: its height is your health (it sinks as you're hurt), and how far it's "
            .. "lit is your mana, rage or energy, with a star at the tip. The space above it takes a faint film, the edges "
            .. "redden more and more as you lose health, and it all fades away when you're full and out of combat. Bring the mouse "
            .. "near the line to read the numbers.",
        apply = function() ns.Vitals:Apply(); ns.Orb:Layout() end })
    p:Dropdown({ id = "vitalsPlayerFrame", path = "db.vitalsPlayerFrame", label = "Your unit frame",
        choices = { { "blizzard", "Blizzard's player frame" }, { "orb", "The orb" } },
        tooltip = "Blizzard's player frame, or the orb in its place: an orb cut in half, health on top (green), your "
            .. "resource below. Right-click the orb for your menu (as your portrait), left-click to target yourself, "
            .. "shift-drag to move it (/whud orb reset puts it back). Switches straight away (after the fight, if you're in one).",
        apply = function() ns.Vitals:ApplyPlayerFrame() end })
    p:Slider({ id = "orbSize", path = "db.orbSize", label = "Orb size", min = 32, max = 160, step = 2,
        format = function(v) return ("%d px"):format(v) end,
        tooltip = "The orb's diameter, in and out of combat. With the line on it's a resource tracker, 80% of this. Changes made in a fight apply when it ends.",
        apply = function() ns.Orb:Layout() end })
    p:Dropdown({ id = "vitalsHealthTextSide", path = "db.vitalsHealthTextSide", label = "Health numbers",
        choices = { { "left", "Left" }, { "center", "Center" }, { "right", "Right" } },
        apply = function() ns.Vitals:PlaceHealthText() end,
        tooltip = "Which end of the line the health readout sits at: when you bring the mouse to the line, and below 15% health." })
    p:Dropdown({ id = "vitalsReadouts", path = "db.vitalsReadouts", label = "The numbers",
        choices = { { "learn", "Learn from me" }, { "approach", "When I reach for them" }, { "always", "Always in fights" } },
        tooltip = "Learn from me: they surface when you bring the mouse to the line, and once you often do, they stay out in fights on their own. "
            .. "When I reach for them: only near the mouse. Always in fights: out for the whole fight." })
    p:Check({ id = "vitalsFilm", path = "db.vitalsFilm", label = "A faint film over the health you've lost",
        apply = function() ns.Vitals:UpdateHealth() end })
    p:Check({ id = "vitalsRim", path = "db.vitalsRim", label = "Red edges as you lose health",
        tooltip = "The edges redden from your first point of damage on an exponential curve: barely there for a long while, "
            .. "climbing faster the lower you go, full at about 12%. Lower still they pulse; it learns how low your health "
            .. "usually goes in a fight and only pulses below that (/whud vitals).",
        apply = function() ns.Vitals:UpdateHealth() end })
    p:Check({ id = "vitalsRhythm", path = "db.vitalsRhythm", label = "Rhythm: the five-second rule and regen ticks",
        tooltip = "After a spell costs mana, a sweep round the star counts down the five seconds without regen. Energy and mana ticks ripple off the star." })
    p:Button({ label = "What it has learned", text = "Forget", fn = function() ns.Vitals.Forget(); ns:Print("Vitals forgot what it learned about you.") end })
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
