local _, ns = ...

-- Every assumption about how stats convert, in one place. When one proves wrong, change it here.
--
-- A value is a plain number or an equation: function(v, ...) returning a number. v gives the
-- variables below, read when the equation runs, so an equation can depend on them:
--   v.level, v.class ("MAGE"), v.spec (1-3, Druid 4), v.boss_level, v.max_level
--   v.game_agi_per_crit  Agility per 1% crit by the game's own figures, nil when it won't say
--   any stat by name: v.agility, v.melee_hit, v.crit_chance, v.defense_skill ... (your value now)
-- For example, a rate that shrinks with level:
--   hit_points_per_percent = function(v) return 10 * v.level / 60 end
--
-- Marked UNVERIFIED: no data confirms it yet. Check it against the Forever probe.
--
-- Default stat weights aren't here: they're preferences, in Defaults.lua. Thresholds are read when
-- a profile is created, so changing one here doesn't change profiles that already exist.
local A = {}
ns.Assumptions = A

---------------------------------------------------------------------------
-- Variables
---------------------------------------------------------------------------

local VARIABLES = {
    level = function() return UnitLevel("player") or 60 end,
    class = function() return select(2, UnitClass("player")) end,
    spec = function() return select(2, ns.API:GetActiveSpec()) end,
    boss_level = function() return 63 end, -- raid bosses
    max_level = function() return 60 end,
    game_agi_per_crit = function()
        if not (GetCritChanceFromAgility and UnitStat) then return nil end
        local ok, fromAgi = pcall(GetCritChanceFromAgility, "player")
        local agi = select(2, UnitStat("player", 2))
        if ok and type(fromAgi) == "number" and fromAgi > 0 and agi and agi > 0 then return agi / fromAgi end
    end,
}

local function Variable(_, key)
    local fn = VARIABLES[key]
    if fn then return fn() end
    return ns.Caps and ns.Caps.Read(key) -- a stat's value now
end

local V = setmetatable({}, { __index = Variable })

-- Scales a level 60 figure: at level L about L/60 of it, at least a quarter.
local function ByLevel(v, at60)
    return at60 * math.max(0.25, math.min(1, v.level / v.max_level))
end

---------------------------------------------------------------------------
-- Item points per 1%
---------------------------------------------------------------------------

-- How many points an item shows for 1% of a stat. Hit and crit come from Forever's item data
-- ("chance to hit by 1.0%" is stored as 10, "critical strike by 1.0%" as 14).
A.POINTS_PER_PERCENT = {
    HIT = 10,
    CRIT = 14,
    SPELLCRIT = 14, -- UNVERIFIED: taken from CRIT, no spell crit samples
    HASTE = 10,     -- UNVERIFIED
    DODGE = 12,     -- UNVERIFIED
    PARRY = 20,     -- UNVERIFIED
    BLOCK = 5,      -- UNVERIFIED
}

-- Stats the game gives in percent, so cap thresholds for them are percents too.
A.IN_PERCENT = {
    crit_chance = true, spell_crit = true, melee_hit = true, ranged_hit = true, spell_hit = true,
    haste = true, dodge_rating = true, parry_rating = true, block_chance = true,
}

---------------------------------------------------------------------------
-- Caps
---------------------------------------------------------------------------

A.CAPS = {
    melee_hit = 9,  -- UNVERIFIED on Forever: Classic's cap vs a boss
    ranged_hit = 9, -- UNVERIFIED on Forever
    spell_hit = 16, -- UNVERIFIED on Forever
    -- Crit immunity: 5.6% off a boss's crit, at 0.04% per skill past your own maximum.
    defense_skill = function(v) return (v.boss_level - 3) * 5 + 5.6 / 0.04 end, -- UNVERIFIED on Forever
}

---------------------------------------------------------------------------
-- What stats cost on items
---------------------------------------------------------------------------

-- Roughly what one point of each stat costs an item, with a point of a main stat as 1.
A.BUDGET = {
    STR = 1, AGI = 1, STA = 1, INT = 1, SPI = 1,
    AP = 0.5, RAP = 0.4, SP = 0.86, HEAL = 0.45,
    FIRE = 0.7, FROST = 0.7, SHADOW = 0.7, ARCANE = 0.7, NATURE = 0.7,
    MP5 = 2.5, DEF = 1.2, BLOCKVALUE = 0.15, ARMOR = 0.04, DPS = 3,
}

-- The budget of 1% of a stat.
A.PERCENT_BUDGET = { CRIT = 14, SPELLCRIT = 14, HIT = 14, HASTE = 10, DODGE = 12, PARRY = 20, BLOCK = 5 }

-- An amount at or below this on a percent stat is read as a percent, above it as points worth 1.
-- UNVERIFIED: Forever's data stores 0.3% hit as 3, which this reads as 3%.
A.MAX_PERCENT = 5

-- The share a stat earns of what it produces, so stacking one can't run away.
A.DERIVED_SHARE = 0.5

---------------------------------------------------------------------------
-- What stats produce
---------------------------------------------------------------------------

-- Agility per 1% melee crit at level 60.
local AGI_PER_CRIT_60 = {
    WARRIOR = 20, PALADIN = 20, HUNTER = 53, ROGUE = 29, PRIEST = 20,
    SHAMAN = 20, MAGE = 20, WARLOCK = 20, DRUID = 20,
}
-- Intellect per 1% spell crit at level 60.
local INT_PER_SPELLCRIT_60 = {
    PALADIN = 54, PRIEST = 59, SHAMAN = 59, MAGE = 60, WARLOCK = 61, DRUID = 60,
}

-- Agility per 1% crit: the game's own figure when it gives one, else the table by level.
function A.agi_per_crit(v)
    return v.game_agi_per_crit or ByLevel(v, AGI_PER_CRIT_60[v.class] or 20)
end

function A.int_per_spellcrit(v)
    return ByLevel(v, INT_PER_SPELLCRIT_60[v.class] or 60)
end

-- What one point of a stat also gives, per class: { to stat, amount per point }. "agi" and "int"
-- stand for 1 / agi_per_crit and 1 / int_per_spellcrit, kept by Convert.lua until you level.
local CRIT, SPELL = { "CRIT", "agi" }, { "SPELLCRIT", "int" }
local ARMOR = { "ARMOR", 2 }
A.DERIVED = {
    WARRIOR = { STR = { { "AP", 2 } }, AGI = { CRIT, ARMOR } },
    PALADIN = { STR = { { "AP", 2 } }, AGI = { CRIT, ARMOR }, INT = { SPELL } },
    HUNTER = { STR = { { "AP", 1 } }, AGI = { CRIT, { "RAP", 2 }, { "AP", 1 }, ARMOR } },
    ROGUE = { STR = { { "AP", 1 } }, AGI = { CRIT, { "AP", 1 }, ARMOR } },
    PRIEST = { INT = { SPELL } },
    SHAMAN = { STR = { { "AP", 2 } }, AGI = { CRIT, ARMOR }, INT = { SPELL } },
    MAGE = { INT = { SPELL } },
    WARLOCK = { INT = { SPELL } },
    -- Cat form: 2 AP per Strength, 1 per Agility (Classic's figures; UNVERIFIED on Forever).
    DRUID = { STR = { { "AP", 2 } }, AGI = { CRIT, { "AP", 1 }, ARMOR }, INT = { SPELL } },
}

---------------------------------------------------------------------------
-- Rank lists
---------------------------------------------------------------------------

-- The weight of rank i in a list of n: 1.0 for the first, falling evenly to 0.1 at the last.
function A.rank_weight(_, i, n)
    return n > 1 and (1 - 0.9 * (i - 1) / (n - 1)) or 1
end

---------------------------------------------------------------------------
-- Effects (SpyGlass prices "Equip:" effects with these)
---------------------------------------------------------------------------

-- Stat points per unit of an effect.
A.EFFECT_RATES = {
    SHIFT_COST = { MP5 = 0.05 },   -- per mana off shapeshifting
    SPELL_COST = { MP5 = 0.04 },   -- per mana off one spell
    SPELL_DAMAGE = { SP = 0.4 },   -- per damage on one spell
    SPELL_HEAL = { HEAL = 0.4 },   -- per healing on one spell
    CAST_TIME = { HASTE = 0.5 },   -- per tenth of a second off one spell
    WEAPON_SKILL = { HIT = 0.1 },  -- per point of weapon skill
}

---------------------------------------------------------------------------
-- Reading them
---------------------------------------------------------------------------

-- A number, or an equation run with the variables. overrides (optional, a table) sets variables
-- for this call: A.Solve(value, { level = 30 }).
function A.Solve(value, overrides, ...)
    if type(value) ~= "function" then return value end
    return value(overrides and setmetatable(overrides, { __index = V }) or V, ...)
end

-- One of the equations above by name, with the variables: A.Get("rank_weight", 2, 8).
function A.Get(name, ...)
    return A[name](V, ...)
end

function A.Budget(stat) return A.Solve(A.BUDGET[stat]) or 0 end
function A.PercentBudget(stat) return A.Solve(A.PERCENT_BUDGET[stat]) end
function A.Cap(name, overrides) return A.Solve(A.CAPS[name], overrides) end
function A.PointsPerPercent(stat, overrides) return A.Solve(A.POINTS_PER_PERCENT[stat], overrides) end

-- Item points of a stat as a percent, and back.
function A.ToPercent(stat, points)
    local per = A.PointsPerPercent(stat)
    return per and points / per
end

function A.ToPoints(stat, percent)
    local per = A.PointsPerPercent(stat)
    return per and percent * per
end

-- { stat = rate } for an effect type, solved.
function A.EffectRates(kind)
    local out = {}
    for stat, rate in pairs(A.EFFECT_RATES[kind] or {}) do out[stat] = A.Solve(rate) end
    return out
end
