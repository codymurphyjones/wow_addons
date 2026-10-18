local _, ns = ...

-- How the game words what a spell, talent or item does. Your own spells' tooltips are read
-- against these to learn what each one is for: this is a table of wording, not of classes, so
-- it follows every rank, talent and Forever change automatically. Patterns are matched against
-- lower-cased tooltip text.
ns.WORDS = {
    tags = {
        interrupt = { "interrupt", "silence", "counterspell", "spell lock" },
        stun = { "stuns? th", "stunn", "knocks? .- out" },
        root = { "root", "immobiliz", "freezes? .- in place", "unable to move" },
        slow = { "movement speed .- reduced", "reduc%a* .- movement speed", "slows?", "dazed", "movement slowed" },
        fear = { "flee in terror", "fear", "horrif", "run in fear" },
        cc = { "sleep", "incapacitat", "transforms? the enemy", "polymorph", "sap", "banish", "shackle", "disorient", "cannot attack or cast", "blind" },
        heal = { "heals? .- for", "restores? %d+ to %d+ health", "restores? %d+ health", "heal[%s%a]-%d+ to %d+" },
        defensive = { "absorbs? %d+", "reduc%a* .- damage taken", "damage taken .- reduced", "immune to", "dodge chance", "parry chance", "increases? .- armor", "block chance" },
        cleanse = { "removes? .- poison", "removes? .- disease", "removes? .- curse", "removes? .- magic", "dispels?", "cures?" },
        taunt = { "taunt", "forces? the target to attack", "forces? .- to attack you" },
        escape = { "teleport", "increases? .- movement speed", "run speed", "feign death", "vanish", "escape", "breaks? .- free", "removes? all movement" },
        aoe = { "all enemies within", "nearby enemies", "enemies in a", "all targets within", "enemies within %d+ yards" },
        mana = { "restores? %d+ to %d+ mana", "restores? %d+ mana", "regain.- mana", "mana regeneration" },
        threatdrop = { "feign death", "vanish", "fade", "reduces? .- threat", "less threat" },
        pet = { "summons? .- pet", "your pet", "call pet", "revive pet" },
        ranged = { "%d+ yd range", "%d+%-%d+ yd range" },
        damage = { "causes? %d+", "deals? %d+", "inflicts? %d+", "%d+ to %d+ %a+ damage", "%d+ %a+ damage" },
        rest = { "must remain seated", "while eating", "while drinking" },
    },
    -- What a cleanse removes.
    cleanseKinds = { poison = "poison", disease = "disease", curse = "curse", magic = "magic" },
    -- Creature types a spell is limited to: the tooltip says "Only works on Beasts, Humanoids and
    -- Critters" or "the target undead".
    typeLimits = {
        { "only works on (.-)%.", true }, { "only usable on (.-)%.", true }, { "target ([%a]+) enemy", false },
        { "the target (undead)", false }, { "against (undead)", false }, { "(demon) or (elemental)", false },
    },
    types = { beast = "Beast", beasts = "Beast", humanoid = "Humanoid", humanoids = "Humanoid", undead = "Undead",
        demon = "Demon", demons = "Demon", elemental = "Elemental", elementals = "Elemental", dragonkin = "Dragonkin",
        giant = "Giant", giants = "Giant", mechanical = "Mechanical", mechanicals = "Mechanical", critter = "Critter", critters = "Critter" },
    -- Numbers worth knowing, as Lua patterns with captures.
    amounts = {
        heal = { "restores? (%d+) to (%d+) health", "heals? .- for (%d+) to (%d+)", "heals? .- for (%d+)", "restores? (%d+) health" },
        mana = { "restores? (%d+) to (%d+) mana", "restores? (%d+) mana" },
        absorb = { "absorbs? (%d+) to (%d+) damage", "absorbs? (%d+) damage" },
        reduce = { "damage taken .- by (%d+)%%", "reduc%a* .- damage taken by (%d+)%%", "reduc%a* .- damage .- by (%d+)%%" },
        duration = { "for (%d+%.?%d*) sec", "lasts (%d+%.?%d*) sec", "over (%d+%.?%d*) sec" },
        armor = { "increases? .- armor by (%d+)", "%+(%d+) armor", "armor by (%d+)" },
    },
}
