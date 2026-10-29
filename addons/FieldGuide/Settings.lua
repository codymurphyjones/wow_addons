local _, ns = ...

-- Options > AddOns > Field Guide, built with the shared OptionsPage.lua (addons/shared). /fg
-- (questie, minimap, section) changes the same options, so the page shows them.
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
    p:Dropdown({ path = "char.preference", label = "Preference",
        choices = { { "leveling", "Leveling" }, { "clear", "Zone Clear" } },
        apply = function() ns.Engine:Invalidate(); ns:Changed() end,
        tooltip = "Leveling: experience and convenience first. Quests worth too little XP for your level are left out, "
            .. "and a quick quest a little off the route (one with nothing to do but hand it in) is picked up on the way "
            .. "when it's within the detour budget below.\n\nZone Clear: every quest of the zone you're on that you "
            .. "haven't done, gray ones too, and the quests they need first even when those are in another zone (the "
            .. "zone you're on stays meanwhile). Quests above your level wait at the end as \"Needs level N\"; once "
            .. "only those are left the zone counts as cleared and the guide moves on. (/fg mode)" })
    p:Slider({ path = "db.detourMinutes", label = "Detour budget", min = 0, max = 5, step = 0.5,
        format = function(v) return v == 0 and "Off" or ("%.1f min"):format(v) end,
        apply = function() ns.Engine:Invalidate(); ns:Changed() end,
        tooltip = "Leveling only: how many minutes of extra walking a quick quest off the route may cost "
            .. "(and it has to pay at least the route's usual XP per minute). 0 turns detours off." })
    p:Check({ id = "Tracking", path = "db.manageTracking", label = "Manage quest tracking",
        tooltip = "The guide tracks the quests your next steps are about, and untracks the other quests addons tracked. "
            .. "Quests you track yourself stay tracked until they're done or you untrack them, and come first on the arrow "
            .. "(over the guide's step while the guide window is closed). A quest you untrack yourself isn't tracked again." })

    p:Header("The field")
    p:Slider({ path = "db.nextSteps", label = "Steps ahead", min = 0, max = 10, step = 1,
        format = function(v) return ("%d"):format(v) end,
        tooltip = "How many of the steps after the current one come up around you once you've stood still a while "
            .. "(two more when you often look ahead)." })
    p:Check({ path = "db.field.learn", label = "Learn how I read",
        tooltip = "The field paces itself to how long you usually stay still to read: the longer you stay, the sooner the "
            .. "next steps and the trail come up. /fg relearn forgets it." })
    p:Check({ path = "db.focusQuestie", label = "Focus the current quest in Questie",
        tooltip = "The current step's quest goes to the top of Questie's tracker (/fg questie)." })
    p:Check({ path = "char.minimap.hide", invert = true, label = "Show the minimap button",
        tooltip = "Field Guide's minimap button (/fg minimap).",
        apply = function() if ns.MinimapButton then ns.MinimapButton:Refresh() end end })
end })

function S:Open() return self.page:Open() end
