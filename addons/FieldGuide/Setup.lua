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
            title = "The field",
            text = "This is how it looks. When you stand still, your next steps rise up around your character, each one placed in the direction it really lies, and more come up the longer you wait. Move or start a fight and it all fades away.",
            demo = function(on) ns.UI:Demo(on) end,
            low = true,
            path = "db.shown",
            choices = {
                { true, "Show it when I stand still", "Rest the cursor on a step for its details." },
                { false, "Keep it off", "The arrow still guides you. /fg brings it back." },
            },
        },
        {
            title = "Talking to quest givers",
            text = "Accepting for you skips the quest text. You can have it take only the guide's quests, or everything a giver offers.",
            get = function()
                if ns.db.autoAccept then return ns.db.autoAcceptGuide and "guide" or "both" end
                return ns.db.autoTurnIn and "turnin" or "off"
            end,
            set = function(value)
                ns:SetOption("db.autoAccept", value == "both" or value == "guide")
                ns:SetOption("db.autoAcceptGuide", value == "guide")
                ns:SetOption("db.autoTurnIn", value ~= "off")
            end,
            choices = {
                { "guide", "Accept the guide's quests and hand in for me", "The fastest way through a route, with nothing extra in your log." },
                { "both", "Accept everything and hand in for me", "Takes every quest a giver offers, on the guide or not." },
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
