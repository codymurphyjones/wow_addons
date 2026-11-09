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
    p:Button({ label = "Setup wizard", text = "Run setup", fn = function() ns.setup:Open() end })
    -- "Automatic" is no section of your own (char.section nil).
    p:Dropdown({ id = "Section", label = "Zone guide", default = AUTO, choices = SectionChoices,
        get = function() return ns.char.section or AUTO end,
        set = function(value) ns.Engine:SetSection(value ~= AUTO and value or nil) end,
        tooltip = "Automatic: Leveling plans tasks wherever the best XP a minute is, across zone borders, and Zone Clear "
            .. "clears the zone you're on, then the nearest zone with something left. A zone you pick here is followed zone "
            .. "by zone instead, until you pick Automatic again (/fg section auto). Nothing changes while you're on a flight." })
    p:Dropdown({ path = "char.preference", label = "Preference",
        choices = { { "leveling", "Leveling" }, { "clear", "Zone Clear" } },
        apply = function() ns.Engine:Invalidate(); ns:Changed() end,
        tooltip = "Leveling: XP a minute first. Every pick-up, objective and hand-in is a task of its own, done in the "
            .. "quickest order wherever it is, and quests worth too little XP for your level are left out. A quest that "
            .. "takes you to the next area of work is picked up on the way there.\n\nZone Clear: every quest of the zone you're on that you "
            .. "haven't done, gray ones too, and the quests they need first even when those are in another zone (the "
            .. "zone you're on stays meanwhile). Quests above your level wait at the end as \"Needs level N\"; once "
            .. "only those are left the zone counts as cleared and the guide moves on. (/fg mode)" })
    p:Check({ id = "Tracking", path = "db.manageTracking", label = "Manage quest tracking",
        tooltip = "The guide tracks the quests your next steps are about, and untracks the other quests addons tracked. "
            .. "Quests you track yourself stay tracked until they're done or you untrack them, and come first on the arrow "
            .. "(over the guide's step while the guide window is closed). A quest you untrack yourself isn't tracked again." })

    p:Check({ path = "db.autoAccept", label = "Auto Accept",
        tooltip = "Takes quests when you talk to their giver. Quests you skipped and repeatable quests are left alone, and "
            .. "gray quests are only taken in Zone Clear. Hold Shift while you talk to the NPC to do it by hand." })
    p:Check({ path = "db.autoAcceptGuide", label = "Accept Field Guide Quests",
        tooltip = "With Auto Accept on, only takes the quests the guide is telling you to pick up. Anything else a giver "
            .. "offers is left for you to take or leave. Turn it off to take every quest." })
    p:Check({ path = "db.autoTurnIn", label = "Auto Turn-in",
        tooltip = "Hands in a finished quest when you talk to the NPC. It stops if there's a reward to choose or the quest "
            .. "wants gold, so that's yours to decide. Hold Shift while you talk to the NPC to do it by hand." })

    p:Header("The field")
    p:Slider({ path = "db.nextSteps", label = "Steps ahead", min = 0, max = 5, step = 1,
        format = function(v) return ("%d"):format(v) end,
        tooltip = "How many of the steps after the current one come up around you once you've stood still a while "
            .. "(two more when you often look ahead)." })
    p:Check({ path = "db.field.learn", label = "Learn how I read",
        tooltip = "The field paces itself to how long you usually stay still to read: the longer you stay, the sooner the "
            .. "next steps and the trail come up. /fg relearn forgets it." })
    p:Check({ path = "db.focusQuestie", label = "Focus the current quest in Questie",
        tooltip = "The current step's quest goes to the top of Questie's tracker (/fg questie)." })
    p:Button({ label = "Quest item macro", text = "Make macro", fn = function() ns.QuestMacro:Create() end,
        tooltip = "Makes the \"FG Quest Item\" macro (General macros, shared by all your characters) and puts it on "
            .. "your cursor: drop it on an action bar. Click uses the quest item you need now (the current step's first), "
            .. "shift-click the next, ctrl-click the third. Field Guide keeps it up to date (/fg macro)." })
    p:Check({ path = "char.minimap.hide", invert = true, label = "Show the minimap button",
        tooltip = "Field Guide's minimap button (/fg minimap).",
        apply = function() if ns.MinimapButton then ns.MinimapButton:Refresh() end end })
end })

function S:Open() return self.page:Open() end
