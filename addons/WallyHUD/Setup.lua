local _, ns = ...

-- First-run setup (shared\Wizard.lua): with Questie installed, whether its map icons show only for
-- the quests you're tracking (Questie Auto Track, QuestieIcons.lua). Asked once while the setting
-- isn't chosen; Options > AddOns > WallyHUD changes it later.

ns.setup = ns.NewWizard({
    name = "WallyHUD",
    needed = function() return ns.QuestieIcons and ns.QuestieIcons:Available() and ns.db and ns.db.questieAutoTrack == nil end,
    steps = {
        {
            title = "Questie Auto Track",
            text = "Questie marks every quest in your log on the world map and the minimap. Show those icons only "
                .. "for the quests you're tracking?",
            get = function() return ns.db.questieAutoTrack end,
            set = function(value)
                ns.db.questieAutoTrack = value
                ns.QuestieIcons:Apply()
            end,
            choices = {
                { true, "Only tracked quests", "The map shows what you're working on. Track a quest (Shift+click it in the log) to see its icons." },
                { false, "Every quest", "Questie's icons for every quest in your log, as Questie shows them." },
            },
        },
    },
})
