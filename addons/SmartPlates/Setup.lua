local _, ns = ...

-- First-run setup (shared\Wizard.lua). ns.db is the active profile, so the "it ran" flag sits in the
-- saved table above the profiles.
--
-- "Set character options" gives this character a profile of its own, named after it and copied from
-- the one it used; going back to the account's switches to that one again and deletes the copy.

local Profiles = ns.Profiles

local own = {
    is = function() return ns.char.ownProfile ~= nil and Profiles:Active() == ns.char.ownProfile end,
    set = function(on)
        if on then
            local base = ns.Units.Me()
            local name, n = base, 1
            while SmartPlatesDB.profiles[name] do
                n = n + 1
                name = ("%s (%d)"):format(base, n)
            end
            ns.char.sharedProfile = Profiles:Active()
            if Profiles:Create(name, true) then ns.char.ownProfile = name end
        else
            local name = ns.char.ownProfile
            Profiles:Switch(ns.char.sharedProfile or "Default")
            if name then Profiles:Delete(name) end
            ns.char.ownProfile, ns.char.sharedProfile = nil, nil
        end
    end,
}

ns.setup = ns.NewWizard({
    name = "SmartPlates",
    store = function() return SmartPlatesDB end,
    own = own,
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
            title = "Health text",
            text = "How should health read on the bar? (Both, Missing and Off are on the settings page.)",
            path = "db.general.healthText",
            choices = {
                { "value", "Number", "Health left, e.g. 1.2K. Units with over 5,000 health show a percent instead." },
                { "percent", "Percent", "Health left as a percent, e.g. 85%." },
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
