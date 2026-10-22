local _, ns = ...

-- Constants: the level window, equip slots and how item stats map to
-- StatLedger's stat keys.
local D = {}
ns.Data = D

-- Items are shown when their required level is within this window around
-- the player's level. Class-specific items (class restricted, relics, or
-- effects that name one of your class's spells) reach further down.
D.LEVELS_ABOVE = 4
D.LEVELS_BELOW = 12
D.CLASS_LEVELS_BELOW = 20

-- The AtlasLoot module the dungeon and raid loot comes from.
D.ATLAS_MODULE = "AtlasLootClassic_DungeonsAndRaids"

-- Slot groups, in the order the slot dropdown lists them.
D.SLOT_GROUPS = {
    { "ALL", ALL or "All slots" },
    { "HEAD", INVTYPE_HEAD or "Head" },
    { "NECK", INVTYPE_NECK or "Neck" },
    { "SHOULDER", INVTYPE_SHOULDER or "Shoulder" },
    { "BACK", INVTYPE_CLOAK or "Back" },
    { "CHEST", INVTYPE_CHEST or "Chest" },
    { "WRIST", INVTYPE_WRIST or "Wrist" },
    { "HANDS", INVTYPE_HAND or "Hands" },
    { "WAIST", INVTYPE_WAIST or "Waist" },
    { "LEGS", INVTYPE_LEGS or "Legs" },
    { "FEET", INVTYPE_FEET or "Feet" },
    { "FINGER", INVTYPE_FINGER or "Finger" },
    { "TRINKET", INVTYPE_TRINKET or "Trinket" },
    { "MAINHAND", "Weapons" },
    { "OFFHAND", INVTYPE_WEAPONOFFHAND or "Off Hand" },
    { "RANGED", (INVTYPE_RANGED or "Ranged") .. " / " .. (INVTYPE_RELIC or "Relic") },
}

-- Equip location -> slot group. Equip locations not listed (shirts, tabards,
-- bags, ammo) are not gear and are left out of the list.
D.EQUIP_GROUP = {
    INVTYPE_HEAD = "HEAD",
    INVTYPE_NECK = "NECK",
    INVTYPE_SHOULDER = "SHOULDER",
    INVTYPE_CLOAK = "BACK",
    INVTYPE_CHEST = "CHEST",
    INVTYPE_ROBE = "CHEST",
    INVTYPE_WRIST = "WRIST",
    INVTYPE_HAND = "HANDS",
    INVTYPE_WAIST = "WAIST",
    INVTYPE_LEGS = "LEGS",
    INVTYPE_FEET = "FEET",
    INVTYPE_FINGER = "FINGER",
    INVTYPE_TRINKET = "TRINKET",
    INVTYPE_WEAPON = "MAINHAND",
    INVTYPE_2HWEAPON = "MAINHAND",
    INVTYPE_WEAPONMAINHAND = "MAINHAND",
    INVTYPE_WEAPONOFFHAND = "OFFHAND",
    INVTYPE_SHIELD = "OFFHAND",
    INVTYPE_HOLDABLE = "OFFHAND",
    INVTYPE_RANGED = "RANGED",
    INVTYPE_RANGEDRIGHT = "RANGED",
    INVTYPE_THROWN = "RANGED",
    INVTYPE_RELIC = "RANGED",
}

-- GetItemStats keys -> StatLedger stat keys: the shared GearEngine.lua's (addons/shared).
D.STAT_ALIASES = ns.GearEngine.STAT_ALIASES

-- "Equip:" effects that GetItemStats may not report: the shared GearEngine.lua's.
D.EQUIP_PATTERNS = ns.GearEngine.EQUIP_PATTERNS

D.SCHOOLS = ns.GearEngine.SCHOOLS

-- Effects that aren't stats but stand in for one (Effects.lua): matched
-- against the lower-cased "Equip:" line, first match wins. The captures are
-- (amount) or (spell names, amount); convert is stat points per unit of the
-- amount, rough item-budget numbers (an effect on one spell
-- is worth part of the same amount on every spell). needs: "form" (a
-- shapeshift spell), "spell" (one of the named spells in your spellbook) or
-- "weapon" (a weapon type your class can use). An amount followed by "%" is
-- a percentage, which these rates don't fit, so it's skipped.
D.EFFECT_TYPES = {
    { "mana cost of shapeshifting spells by (%d+)", "SHIFT_COST", { MP5 = 0.05 }, "form" },
    { "mana cost of your (.-) spells? by (%d+)", "SPELL_COST", { MP5 = 0.04 }, "spell" },
    { "damage done by your (.-) spells? by up to (%d+)", "SPELL_DAMAGE", { SP = 0.4 }, "spell" },
    { "damage of your (.-) spells? by up to (%d+)", "SPELL_DAMAGE", { SP = 0.4 }, "spell" },
    { "damage of your (.-) spells? by (%d+)", "SPELL_DAMAGE", { SP = 0.4 }, "spell" },
    { "healing done by your (.-) spells? by up to (%d+)", "SPELL_HEAL", { HEAL = 0.4 }, "spell" },
    { "healing of your (.-) spells? by up to (%d+)", "SPELL_HEAL", { HEAL = 0.4 }, "spell" },
    { "healing of your (.-) spells? by (%d+)", "SPELL_HEAL", { HEAL = 0.4 }, "spell" },
    { "casting time of your (.-) spells? by 0?%.(%d) sec", "CAST_TIME", { HASTE = 0.5 }, "spell" },
    { "^equip: increased (.-) %+(%d+)", "WEAPON_SKILL", { HIT = 0.1 }, "weapon" },
}

-- Weapon skill names on items -> weapon subclasses (see CLASS_PROFICIENCY).
D.WEAPON_SKILLS = {
    ["axes"] = { 0 }, ["two-handed axes"] = { 1 }, ["bows"] = { 2 }, ["guns"] = { 3 },
    ["maces"] = { 4 }, ["two-handed maces"] = { 5 }, ["polearms"] = { 6 }, ["swords"] = { 7 },
    ["two-handed swords"] = { 8 }, ["staves"] = { 10 }, ["fist weapons"] = { 13 }, ["daggers"] = { 15 },
    ["thrown"] = { 16 }, ["crossbows"] = { 18 }, ["wands"] = { 19 },
}

-- Paper doll grades (green / yellow / red) while the list is open: your worn
-- item against the best you can wear now (required level at most yours).
-- Near (yellow) is within NEAR_BIS of the best's score, or no more than
-- NEAR_BIS_GAP score points behind it (low-level scores are small, so a
-- trivial gap shouldn't turn a slot red).
D.NEAR_BIS = 0.85
D.NEAR_BIS_GAP = 1.0

-- Each talent point in a talent whose text mentions an effect (its spell,
-- shapeshifting, its weapon) makes the effect worth this much more, up to
-- TALENT_BOOST_MAX times its base worth.
D.TALENT_BOOST = 0.1
D.TALENT_BOOST_MAX = 2
D.FORM_SPELLS = { "bear form", "dire bear form", "cat form", "travel form", "aquatic form", "moonkin form", "ghost wolf" }

-- Used when StatLedger is not installed.
D.FALLBACK_WEIGHTS = ns.GearEngine.FALLBACK_WEIGHTS

-- What each class can learn to wear and wield in Classic, by item subclass:
-- armor (class 4): 1 cloth, 2 leather, 3 mail, 4 plate, 6 shield, 7 libram,
-- 8 idol, 9 totem; weapons (class 2): 0/1 axe, 2 bow, 3 gun, 4/5 mace,
-- 6 polearm, 7/8 sword, 10 staff, 13 fist, 15 dagger, 16 thrown,
-- 18 crossbow, 19 wand. Miscellaneous armor (rings, necks, trinkets, cloaks)
-- and miscellaneous weapons fit everyone. Used for items not loaded yet,
-- since it needs nothing from the server.
local function Set(...)
    local s = {}
    for i = 1, select("#", ...) do s[select(i, ...)] = true end
    return s
end
D.CLASS_PROFICIENCY = {
    WARRIOR = { armor = Set(1, 2, 3, 4, 6), weapon = Set(0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18) },
    PALADIN = { armor = Set(1, 2, 3, 4, 6, 7), weapon = Set(0, 1, 4, 5, 6, 7, 8) },
    HUNTER = { armor = Set(1, 2, 3), weapon = Set(0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18) },
    ROGUE = { armor = Set(1, 2), weapon = Set(2, 3, 4, 7, 13, 15, 16, 18) },
    PRIEST = { armor = Set(1), weapon = Set(4, 10, 15, 19) },
    SHAMAN = { armor = Set(1, 2, 3, 6, 9), weapon = Set(0, 1, 4, 5, 10, 13, 15) },
    MAGE = { armor = Set(1), weapon = Set(7, 10, 15, 19) },
    WARLOCK = { armor = Set(1), weapon = Set(7, 10, 15, 19) },
    DRUID = { armor = Set(1, 2, 8), weapon = Set(4, 5, 10, 13, 15) },
}

-- Class spells too generic to mark an item as class-specific.
D.SPELL_STOPLIST = {
    ["Attack"] = true, ["Auto Shot"] = true, ["Shoot"] = true, ["Throw"] = true,
    ["Parry"] = true, ["Dodge"] = true, ["Block"] = true,
}
