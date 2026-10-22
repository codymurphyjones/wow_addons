local _, ns = ...

-- Options > AddOns > Field Guide, built with the shared OptionsPage.lua (addons/shared). /fg
-- (lock, questie, dock, minimap, section) changes the same options, so the page shows them.
local S = {}
ns.Settings = S

local AUTO = "auto"

-- The sections of the guide you follow, for the dropdown: "Ashenvale  15-23".
local function SectionChoices()
    local out = { { AUTO, "Automatic" } }
    local guide = ns.Engine:Guide()
    for _, s in ipairs(guide and guide.sections or {}) do
        out[#out + 1] = { s.id, ("%s  |cff8a948e%d-%d|r"):format(s.title, s.from or 1, s.to or 60) }
    end
    return out
end

-- Built once you're logged in (the guide depends on your faction).
S.page = ns.NewOptionsPage({ name = "Field Guide", icon = true, build = function(p)
    p:Header(ns.IconMarkup(28) .. "  Field Guide: Leveling guide")
    -- "Automatic" is no section of your own (char.section nil).
    p:Dropdown({ id = "Section", label = "Zone guide", default = AUTO, choices = SectionChoices,
        get = function() return ns.char.section or AUTO end,
        set = function(value) ns.Engine:SetSection(value ~= AUTO and value or nil) end,
        tooltip = "Which zone's leveling guide to follow. Automatic: the zone you're in when it has quests worth "
            .. "doing at your level, otherwise the one you were on, or the nearest one for your level. "
            .. "Automatic looks at zones within 4 levels of yours either way, and prefers the ones whose quests "
            .. "are at your level to 2 above. Walking into a zone that doesn't suit you now (under your level, or "
            .. "more than 2 above it) counts as traveling: the zone you were on stays. Nothing changes while you're on a flight. "
            .. "A zone you pick here stays until you pick Automatic again (/fg section auto)." })
    p:Check({ id = "Dock", path = "db.dock", label = "Sit under Waypoint's arrow",
        apply = function() if ns.UI then ns.UI:Dock() end end,
        tooltip = "The guide window sits under Waypoint's arrow and moves with it (the arrow's right-click menu sets left, center or right). "
            .. "Off: drag the guide anywhere on its own (/fg dock)." })
    p:Check({ id = "Tracking", path = "db.manageTracking", label = "Manage quest tracking",
        tooltip = "The guide tracks the quests your next steps are about, and untracks the other quests addons tracked. "
            .. "Quests you track yourself stay tracked until they're done or you untrack them, and come first on the arrow "
            .. "(over the guide's step while the guide window is closed). A quest you untrack yourself isn't tracked again." })

    p:Header("The guide window")
    p:Check({ path = "db.locked", label = "Lock the window", tooltip = "The guide window can't be dragged (/fg lock)." })
    p:Slider({ path = "db.nextSteps", label = "Next steps shown", min = 0, max = 10, step = 1,
        format = function(v) return ("%d"):format(v) end,
        tooltip = "How many of the steps after the current one the guide window lists under it." })
    p:Check({ path = "db.focusQuestie", label = "Focus the current quest in Questie",
        tooltip = "The current step's quest goes to the top of Questie's tracker (/fg questie)." })
    p:Check({ path = "char.minimap.hide", invert = true, label = "Show the minimap button",
        tooltip = "Field Guide's minimap button (/fg minimap).",
        apply = function() if ns.MinimapButton then ns.MinimapButton:Refresh() end end })
end })

function S:Open() return self.page:Open() end
