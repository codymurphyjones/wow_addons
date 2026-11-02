local _, ns = ...

-- First-run setup (shared\Wizard.lua). ns.db is the active profile, so the "it ran" flag sits in the
-- saved table above the profiles.

ns.setup = ns.NewWizard({
    name = "SmartPlates",
    store = function() return SmartPlatesDB end,
    steps = {
        {
            title = "Your role",
            text = "Threat colours flip with your role: a mob on you is good for a tank and bad for everyone else.",
            char = true,
            path = "char.role",
            choices = {
                { "auto", "Automatic", "Reads your stance, form or tank aura. A tank outside that stance counts as DPS." },
                { "tank", "Tank", "Always tank colours, whatever your stance." },
                { "dps", "DPS / Healer", "Always DPS colours, whatever your stance." },
            },
        },
        {
            title = "Threat colours",
            text = "Where should plates change colour, size and opacity with threat?",
            path = "db.threat.instancesOnly",
            choices = {
                { false, "Everywhere", "Also while questing and in the open world." },
                { true, "Dungeons and raids only", "Plain plates out in the world." },
            },
        },
        {
            title = "Game nameplate settings",
            text = "SmartPlates can set the game's nameplate options for you at every login: stacking, distance and which plates show.",
            path = "db.cvars.manage",
            choices = {
                { true, "Let SmartPlates manage them", "The look it was designed around." },
                { false, "Keep my own", "Your previous game settings are put back." },
            },
        },
        {
            title = "Plates out of combat",
            text = "Show plates for units you aren't fighting?",
            when = function() return ns.db.cvars.manage end,
            path = "db.cvars.alwaysShow",
            choices = {
                { true, "Always show", "See what's around you before you pull." },
                { false, "Only in combat", "A cleaner screen while you travel." },
            },
        },
        {
            title = "Enemy buffs",
            text = "A small line of buffs on enemy plates, most important first. Handy for purging and PvP, busy in big pulls.",
            path = "db.auras.buffs",
            choices = {
                { true, "Show them", "" },
                { false, "Hide them", "Only your debuffs and crowd control stay on the plate." },
            },
        },
        {
            title = "Friendly plates",
            text = "Who draws the plates of friendly units?",
            path = "db.general.blizzardFriendly",
            choices = {
                { false, "SmartPlates", "Names for NPCs, small health bars for players." },
                { true, "The game", "Leaves friendly plates to Blizzard, or to another addon." },
            },
        },
    },
})
