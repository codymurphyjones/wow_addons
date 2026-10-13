local _, ns = ...

-- Stats, class and spec defaults. Stat keys match Bandolier and GearBot, so
-- other addons can use them without translating.
local D = {}
ns.Data = D

-- Stats, in the order the settings dropdowns list them.
D.STATS = {
    "STR", "AGI", "STA", "INT", "SPI",
    "AP", "RAP", "SP", "HEAL",
    "FIRE", "FROST", "SHADOW", "ARCANE", "NATURE",
    "CRIT", "SPELLCRIT", "HIT", "HASTE", "MP5",
    "ARMOR", "DEF", "DODGE", "PARRY", "BLOCK", "BLOCKVALUE",
    "DPS",
}

-- The ranked list can hold every stat.
D.MAX_SLOTS = #D.STATS

D.LABELS = {
    STR = "Strength", AGI = "Agility", STA = "Stamina", INT = "Intellect", SPI = "Spirit",
    AP = "Attack Power", RAP = "Ranged Attack Power", SP = "Spell Power", HEAL = "Healing",
    FIRE = "Fire Spell Power", FROST = "Frost Spell Power", SHADOW = "Shadow Spell Power",
    ARCANE = "Arcane Spell Power", NATURE = "Nature Spell Power",
    CRIT = "Critical Strike", SPELLCRIT = "Spell Critical Strike", HIT = "Hit", HASTE = "Haste",
    MP5 = "Mana Regeneration",
    ARMOR = "Armor", DEF = "Defense", DODGE = "Dodge", PARRY = "Parry",
    BLOCK = "Block Chance", BLOCKVALUE = "Block Value",
    DPS = "Weapon DPS",
}

D.CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

D.CLASS_NAMES = {
    WARRIOR = "Warrior", ROGUE = "Rogue", HUNTER = "Hunter", MAGE = "Mage", WARLOCK = "Warlock",
    PRIEST = "Priest", PALADIN = "Paladin", DRUID = "Druid", SHAMAN = "Shaman",
}

-- Talent trees in the game's tab order, with each spec's default priority,
-- best first. The first five match Bandolier's built-in presets.
-- [class] = { default tab before talents, { name, { stats } } x3 }
D.SPECS = {
    WARRIOR = { 1,
        { "Arms", { "STR", "AP", "CRIT", "AGI", "STA", "HIT", "DPS", "ARMOR" } },
        { "Fury", { "STR", "AP", "CRIT", "AGI", "HIT", "STA", "DPS", "ARMOR" } },
        { "Protection", { "STA", "ARMOR", "STR", "AGI", "AP", "DEF", "PARRY", "DODGE", "BLOCK", "BLOCKVALUE" } } },
    ROGUE = { 2,
        { "Assassination", { "AGI", "AP", "CRIT", "STR", "HIT", "STA", "DPS", "HASTE" } },
        { "Combat", { "AGI", "AP", "CRIT", "STR", "HIT", "STA", "DPS", "HASTE" } },
        { "Subtlety", { "AGI", "AP", "CRIT", "STR", "STA", "HIT", "DPS", "HASTE" } } },
    HUNTER = { 1,
        { "Beast Mastery", { "AGI", "AP", "CRIT", "HIT", "INT", "RAP", "STA", "MP5" } },
        { "Marksmanship", { "AGI", "AP", "CRIT", "HIT", "INT", "RAP", "STA", "MP5" } },
        { "Survival", { "AGI", "AP", "CRIT", "STA", "INT", "HIT", "RAP", "MP5" } } },
    MAGE = { 3,
        { "Arcane", { "SP", "ARCANE", "INT", "SPI", "MP5", "SPELLCRIT", "HIT", "STA" } },
        { "Fire", { "SP", "FIRE", "SPELLCRIT", "INT", "MP5", "HIT", "SPI", "STA" } },
        { "Frost", { "SP", "FROST", "SPELLCRIT", "INT", "MP5", "HIT", "SPI", "STA" } } },
    WARLOCK = { 1,
        { "Affliction", { "SP", "SHADOW", "STA", "INT", "SPI", "HIT", "SPELLCRIT", "MP5" } },
        { "Demonology", { "SP", "SHADOW", "STA", "INT", "SPI", "HIT", "SPELLCRIT", "MP5" } },
        { "Destruction", { "SP", "SHADOW", "SPELLCRIT", "INT", "STA", "HIT", "FIRE", "SPI" } } },
    PRIEST = { 2,
        { "Discipline", { "HEAL", "INT", "SPI", "MP5", "STA", "SPELLCRIT", "SP" } },
        { "Holy", { "HEAL", "INT", "SPI", "MP5", "STA", "SPELLCRIT", "SP" } },
        { "Shadow", { "SP", "SHADOW", "INT", "SPI", "STA", "HIT", "SPELLCRIT", "MP5" } } },
    PALADIN = { 3,
        { "Holy", { "HEAL", "INT", "MP5", "SPELLCRIT", "STA", "SPI", "SP" } },
        { "Protection", { "STA", "ARMOR", "SP", "STR", "AGI", "DEF", "BLOCK", "BLOCKVALUE", "PARRY", "DODGE" } },
        { "Retribution", { "STR", "AP", "CRIT", "AGI", "INT", "HIT", "STA", "DPS" } } },
    DRUID = { 2,
        { "Balance", { "SP", "ARCANE", "NATURE", "INT", "MP5", "SPELLCRIT", "HIT", "SPI" } },
        { "Feral", { "AGI", "STR", "AP", "STA", "ARMOR", "CRIT", "HIT", "DODGE" } },
        { "Restoration", { "HEAL", "INT", "SPI", "MP5", "STA", "SPELLCRIT", "SP" } } },
    SHAMAN = { 2,
        { "Elemental", { "SP", "NATURE", "SPELLCRIT", "INT", "MP5", "HIT", "STA", "SPI" } },
        { "Enhancement", { "STR", "AP", "AGI", "CRIT", "INT", "HIT", "DPS", "STA" } },
        { "Restoration", { "HEAL", "INT", "MP5", "SPI", "STA", "SPELLCRIT", "SP" } } },
}

-- Used before the class is known or for a class with no specs listed.
D.FALLBACK = { "STA", "STR", "AGI", "INT", "SPI" }
