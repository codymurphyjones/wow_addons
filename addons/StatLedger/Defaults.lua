local _, ns = ...
local D = ns.Data

-- The starting weights of every class and spec, in the profile shape:
--   { label, spec_hint, stats = { agility = { base_weight = 2.1, cap_tiers = {} }, ... } }
-- D.DEFAULT_PROFILES[class][spec] uses the same spec numbers as D.SPECS (Druid has a fourth, Feral
-- Tank, on the Feral tree). Below, each spec lists only the stats it values and the rest come out
-- at 0, so every entry holds every stat.
--
-- A weight is what one point of a stat is worth, as items show it: one Agility, or one point of
-- crit (14 points = 1%) or hit (10 points = 1%). 1.0 is one Attack Power; for casters and healers
-- it is one Spell Power or one point of Healing.
-- cap_tiers: thresholds are what the character sheet shows, percent for hit and crit, skill points
-- for defense, and come from Assumptions.lua (assumed names the cap, read again whenever a profile
-- is made). Ordered by threshold; the last one reached wins. reads says which hit a stat's caps
-- are measured on: melee unless it's "ranged_hit" or "spell_hit".

-- Item stat names in profiles -> StatLedger's stat keys.
D.STAT_KEYS = {
    strength = "STR", agility = "AGI", stamina = "STA", intellect = "INT", spirit = "SPI",
    attack_power = "AP", ranged_attack_power = "RAP", spell_power = "SP", healing = "HEAL",
    fire_power = "FIRE", frost_power = "FROST", shadow_power = "SHADOW", arcane_power = "ARCANE",
    nature_power = "NATURE", crit_chance = "CRIT", spell_crit = "SPELLCRIT", melee_hit = "HIT",
    haste = "HASTE", mana_regen = "MP5", armor = "ARMOR", defense_skill = "DEF", dodge_rating = "DODGE",
    parry_rating = "PARRY", block_chance = "BLOCK", block_value = "BLOCKVALUE", weapon_dps = "DPS",
    resilience = "RESILIENCE",
}

D.LABELS.RESILIENCE = "Resilience"

-- The Weight Designer's stat list.
D.STAT_GROUPS = {
    { "Attributes", "strength", "agility", "stamina", "intellect", "spirit" },
    { "Physical", "attack_power", "ranged_attack_power", "crit_chance", "melee_hit", "haste", "weapon_dps" },
    { "Spells", "spell_power", "healing", "spell_crit", "mana_regen", "fire_power", "frost_power", "shadow_power",
        "arcane_power", "nature_power" },
    { "Defense", "armor", "defense_skill", "dodge_rating", "parry_rating", "block_chance", "block_value", "resilience" },
}

local A = ns.Assumptions
local HIT_MELEE = { assumed = "melee_hit", label = "Hit cap vs level 63 (raid boss)", weight = 0 }
local HIT_RANGED = { assumed = "ranged_hit", label = "Hit cap vs level 63 (raid boss)", weight = 0 }
local HIT_SPELL = { assumed = "spell_hit", label = "Spell hit cap vs level 63 (raid boss)", weight = 0 }
local DEFENSE = { assumed = "defense_skill", label = "Crit immunity vs level 63 (5.6% crit reduction)", weight = 0.1 }

-- The same tier for each spec that has it, as its own copy.
local function Tiers(...)
    local out = {}
    for i, tier in ipairs({ ... }) do
        out[i] = { threshold = A.Cap(tier.assumed), assumed = tier.assumed, label = tier.label, weight = tier.weight }
    end
    return out
end

-- weights { stat = base weight }; caps { stat = { tiers } }; reads { stat = what its caps read }.
local function Entry(hint, weights, caps, reads, label)
    local stats = {}
    for name in pairs(D.STAT_KEYS) do
        stats[name] = { base_weight = weights[name] or 0, cap_tiers = caps and caps[name] or {} }
        if reads and reads[name] then stats[name].reads = reads[name] end
    end
    return { label = label, spec_hint = hint, stats = stats }
end

local function MeleeHit() return { melee_hit = Tiers(HIT_MELEE) } end
local function RangedHit() return { melee_hit = Tiers(HIT_RANGED) }, { melee_hit = "ranged_hit" } end
local function SpellHit() return { melee_hit = Tiers(HIT_SPELL) }, { melee_hit = "spell_hit" } end
local function Tank() return { melee_hit = Tiers(HIT_MELEE), defense_skill = Tiers(DEFENSE) } end

D.DEFAULT_PROFILES = {
    WARRIOR = {
        Entry("Arms", { strength = 2.2, agility = 1.5, stamina = 0.4, attack_power = 1, crit_chance = 1.7,
            melee_hit = 2.6, haste = 0.9, armor = 0.03, weapon_dps = 14, dodge_rating = 0.1 }, MeleeHit()),
        Entry("Fury", { strength = 2.2, agility = 1.6, stamina = 0.4, attack_power = 1, crit_chance = 1.9,
            melee_hit = 3, haste = 1.1, armor = 0.03, weapon_dps = 12, dodge_rating = 0.1 }, MeleeHit()),
        Entry("Protection", { stamina = 3, armor = 0.8, strength = 1, agility = 1.6, attack_power = 0.4,
            defense_skill = 3, dodge_rating = 2.2, parry_rating = 2.2, block_chance = 1.6, block_value = 0.6,
            melee_hit = 1.5, crit_chance = 0.6, weapon_dps = 3 }, Tank()),
    },
    PALADIN = {
        Entry("Holy", { healing = 1, intellect = 1.4, spirit = 0.4, mana_regen = 2.4, spell_crit = 1.1,
            stamina = 0.3, spell_power = 0.4, armor = 0.01 }),
        Entry("Protection", { stamina = 3, armor = 0.7, spell_power = 0.9, strength = 0.8, agility = 1.2,
            defense_skill = 3, block_chance = 1.8, block_value = 0.8, parry_rating = 2, dodge_rating = 2,
            intellect = 0.5, melee_hit = 1.2, weapon_dps = 2 }, Tank()),
        Entry("Retribution", { strength = 2.3, agility = 1.4, stamina = 0.4, intellect = 0.3, attack_power = 1,
            crit_chance = 1.6, melee_hit = 2.5, haste = 0.8, spell_power = 0.3, armor = 0.03, weapon_dps = 14 }, MeleeHit()),
    },
    HUNTER = {
        Entry("Beast Mastery", { agility = 2.2, intellect = 0.5, stamina = 0.4, attack_power = 0.6, ranged_attack_power = 1,
            crit_chance = 1.5, melee_hit = 2.4, haste = 0.9, mana_regen = 0.8, armor = 0.02, weapon_dps = 8 }, RangedHit()),
        Entry("Marksmanship", { agility = 2.3, intellect = 0.5, stamina = 0.4, attack_power = 0.6, ranged_attack_power = 1,
            crit_chance = 1.7, melee_hit = 2.6, haste = 0.9, mana_regen = 0.8, armor = 0.02, weapon_dps = 10 }, RangedHit()),
        Entry("Survival", { agility = 2.5, intellect = 0.5, stamina = 0.5, attack_power = 0.6, ranged_attack_power = 1,
            crit_chance = 1.8, melee_hit = 2.5, haste = 0.8, mana_regen = 0.8, armor = 0.02, weapon_dps = 8 }, RangedHit()),
    },
    ROGUE = {
        Entry("Assassination", { agility = 2.2, strength = 1.1, stamina = 0.4, attack_power = 1, crit_chance = 2,
            melee_hit = 2.8, haste = 1, armor = 0.02, weapon_dps = 12 }, MeleeHit()),
        Entry("Combat", { agility = 2.1, strength = 1.1, stamina = 0.4, attack_power = 1, crit_chance = 1.7,
            melee_hit = 3, haste = 1.2, armor = 0.02, weapon_dps = 14 }, MeleeHit()),
        Entry("Subtlety", { agility = 2.3, strength = 1.1, stamina = 0.5, attack_power = 1, crit_chance = 1.8,
            melee_hit = 2.5, haste = 0.9, armor = 0.02, dodge_rating = 0.3, weapon_dps = 12 }, MeleeHit()),
    },
    PRIEST = {
        Entry("Discipline", { healing = 1, intellect = 1.2, spirit = 1, mana_regen = 2.2, spell_crit = 0.9,
            stamina = 0.3, spell_power = 0.4 }),
        Entry("Holy", { healing = 1, intellect = 1, spirit = 1.3, mana_regen = 2, spell_crit = 1,
            stamina = 0.3, spell_power = 0.3 }),
        Entry("Shadow", { spell_power = 1, shadow_power = 1, intellect = 0.5, spirit = 0.5, stamina = 0.6,
            spell_crit = 0.2, melee_hit = 1.6, mana_regen = 1.4, haste = 0.8 }, SpellHit()),
    },
    SHAMAN = {
        Entry("Elemental", { spell_power = 1, nature_power = 1, intellect = 0.6, mana_regen = 2, spell_crit = 1.1,
            melee_hit = 1.6, stamina = 0.3, spirit = 0.2, haste = 0.8 }, SpellHit()),
        Entry("Enhancement", { strength = 2.2, agility = 1.5, intellect = 0.4, stamina = 0.4, attack_power = 1,
            crit_chance = 1.6, melee_hit = 2.4, haste = 1, mana_regen = 0.5, spell_power = 0.2, armor = 0.03, weapon_dps = 14 }, MeleeHit()),
        Entry("Restoration", { healing = 1, intellect = 0.9, mana_regen = 2.6, spirit = 0.5, spell_crit = 1,
            stamina = 0.3, spell_power = 0.3 }),
    },
    MAGE = {
        Entry("Arcane", { spell_power = 1, arcane_power = 1, intellect = 0.9, spirit = 0.7, mana_regen = 1.8,
            spell_crit = 0.8, melee_hit = 1.5, stamina = 0.2, haste = 0.8 }, SpellHit()),
        Entry("Fire", { spell_power = 1, fire_power = 1, spell_crit = 1.2, intellect = 0.5, mana_regen = 1.5,
            melee_hit = 1.7, spirit = 0.2, stamina = 0.2, haste = 0.8 }, SpellHit()),
        Entry("Frost", { spell_power = 1, frost_power = 1, spell_crit = 0.9, intellect = 0.5, mana_regen = 1.5,
            melee_hit = 1.7, spirit = 0.2, stamina = 0.2, haste = 0.7 }, SpellHit()),
    },
    WARLOCK = {
        Entry("Affliction", { spell_power = 1, shadow_power = 1, stamina = 0.5, intellect = 0.4, spirit = 0.3,
            melee_hit = 1.7, spell_crit = 0.3, mana_regen = 1.2, haste = 0.7 }, SpellHit()),
        Entry("Demonology", { spell_power = 1, shadow_power = 1, stamina = 0.7, intellect = 0.4, spirit = 0.3,
            melee_hit = 1.5, spell_crit = 0.4, mana_regen = 1.2, haste = 0.6 }, SpellHit()),
        Entry("Destruction", { spell_power = 1, shadow_power = 0.9, fire_power = 0.5, spell_crit = 0.9, stamina = 0.4,
            intellect = 0.4, melee_hit = 1.6, spirit = 0.2, mana_regen = 1, haste = 0.7 }, SpellHit()),
    },
    DRUID = {
        Entry("Balance", { spell_power = 1, arcane_power = 0.7, nature_power = 0.7, intellect = 0.6, mana_regen = 1.8,
            spell_crit = 1, melee_hit = 1.6, spirit = 0.4, stamina = 0.3, haste = 0.7 }, SpellHit()),

        -- Hand-tuned: the 7/36/8 Cat build.
        Entry("Cat DPS", { agility = 2.1, strength = 1.9, attack_power = 1, crit_chance = 1.8, melee_hit = 3, haste = 0.7,
            stamina = 0.4, intellect = 0.15, spirit = 0.05, armor = 0.1, spell_power = 0.05, spell_crit = 0.05,
            dodge_rating = 0.2 }, {
                crit_chance = { { threshold = 0, label = "Soft crit cap (diminishing combo point value)", weight = 0.9 } },
                melee_hit = Tiers(HIT_MELEE),
            }, nil, "7/36/8"),

        Entry("Restoration", { healing = 1, intellect = 0.9, spirit = 1.2, mana_regen = 2.2, spell_crit = 0.8,
            stamina = 0.3, spell_power = 0.3 }),

        -- Hand-tuned: the 0/45/7 Bear build.
        Entry("Bear Tank", { stamina = 3.5, armor = 3, agility = 2.4, defense_skill = 3.2, melee_hit = 2.5, strength = 1.8,
            crit_chance = 1.5, attack_power = 1, dodge_rating = 1.2, intellect = 0.2, haste = 0.3, spirit = 0.05 }, {
                defense_skill = Tiers(DEFENSE),
                melee_hit = Tiers(HIT_MELEE),
            }, nil, "0/45/7"),
    },
}
