local _, ns = ...

-- First-run setup (shared\Wizard.lua).

ns.setup = ns.NewWizard({
    name = "Field Guide",
    steps = {
        {
            title = "What's your goal on this character?",
            text = "Reaching max level, or finishing zones for their achievements? You can switch any time.",
            char = true,
            path = "char.preference",
            choices = {
                { "leveling", "Leveling", "The fastest way up. Quests worth too little XP are left out." },
                { "clear", "Zone Clear", "Every quest in each zone, gray ones too, for the achievements." },
            },
        },
        {
            title = "Talking to quest givers",
            text = "Auto takes any quest a giver offers, not only the guide's, and you skip the quest text.",
            get = function()
                if ns.db.autoAccept then return "both" end
                return ns.db.autoTurnIn and "turnin" or "off"
            end,
            set = function(value)
                ns:SetOption("db.autoAccept", value == "both")
                ns:SetOption("db.autoTurnIn", value ~= "off")
            end,
            choices = {
                { "both", "Accept and hand in for me", "The fastest way through a route." },
                { "turnin", "Only hand in", "You read and accept quests yourself." },
                { "off", "Neither", "You do both by hand. Best for enjoying the story." },
            },
        },
        {
            title = "Quest tracker",
            text = "The guide can track the quests your next steps are about, and untrack the ones other addons tracked. Quests you track yourself stay.",
            path = "db.manageTracking",
            choices = {
                { true, "Manage it for me", "Your tracker follows the guide." },
                { false, "Leave my tracker alone", "" },
            },
        },
    },
})
