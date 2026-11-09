local _, ns = ...

-- First-run setup (shared\Wizard.lua): only with OneForAll installed, the one question of whether to
-- put SpyGlass's mob packs on its dungeon maps (Journal\MobPins.lua). Asked once; the answer is
-- Options > AddOns > SpyGlass > Mob packs on OneForAll's dungeon maps.

ns.setup = ns.NewWizard({
    name = "SpyGlass",
    needed = function() return ns.MobPins and ns.MobPins:OneForAll() ~= nil end,
    steps = {
        {
            title = "OneForAll's dungeon maps",
            text = "OneForAll is installed, with maps of every dungeon. SpyGlass knows where the mob packs stand in each one. "
                .. "Show them on OneForAll's dungeon maps?",
            path = "db.ofaPins",
            choices = {
                { true, "Show the mob packs", "A small circle for each pack with how many mobs, amber when there are elites. Hover one for the mobs, what aggros with it and its patrol." },
                { false, "No, leave the maps as they are", "OneForAll's maps show only its own boss and entrance markers." },
            },
        },
    },
})
