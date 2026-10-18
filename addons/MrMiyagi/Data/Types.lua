local _, ns = ...

-- What's worth knowing about each kind of creature when you fight it. Mobs.lua's own immunities
-- (when known) take precedence over these general notes.
ns.TYPES = {
    Humanoid = {
        flees = true,
        notes = {
            "Humanoids often run at low health and bring friends back: keep a stun, root or slow for that moment.",
            "Casters among them can be pulled around a corner so they come to you instead of casting.",
        },
    },
    Beast = {
        notes = { "Beasts are quick: running rarely works unless you slow or root them first." },
    },
    Undead = {
        notes = { "Many undead shrug off fear and sleep effects, and some resist shadow." },
    },
    Elemental = {
        bleedImmune = true,
        notes = { "Elementals don't bleed, and many resist or ignore the school they're made of (fire elementals and fire, water elementals and frost)." },
    },
    Mechanical = {
        bleedImmune = true, poisonImmune = true,
        notes = { "Mechanical foes don't bleed or take poison, and many ignore fear and mind effects." },
    },
    Demon = {
        notes = { "Demons often drain mana or hit with shadow; Banish and similar spells work on them." },
    },
    Dragonkin = {
        notes = { "Dragonkin hit hard and breathe in a cone: fight them from the side when you can." },
    },
    Giant = {
        notes = { "Giants hit very hard in melee: keep your distance or let a pet take the hits." },
    },
}

-- CMaNGOS creature type ids (Data\Mobs.lua) to names.
ns.TYPE_IDS = { "Beast", "Dragonkin", "Demon", "Elemental", "Giant", "Undead", "Humanoid", "Critter", "Mechanical" }
