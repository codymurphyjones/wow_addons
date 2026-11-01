local _, ns = ...
local D = ns.Data
local API = ns.API
local P = ns.Profiles
local Read = ns.Player.Read

-- Reads your stats and works out which cap tier applies. Tiers replace a stat's base weight once
-- it reaches their threshold; the last one reached wins, weight 0 being a hard cap.
-- A tier can move with other stats: offsets = { { stat = "melee_hit", factor = 1 } }. The threshold
-- it's held to is threshold + each offset stat's value x factor, so a 35% crit soft cap with 5% hit
-- sits at 40%. An offset can have its own limit: cap = 8 stops it there, or with factor_after the
-- rest counts for less. Offsets read stats, never weights, so two stats can't chase each other.
local C = {}
ns.Caps = C

-- What these read in percent; everything else is plain points.
C.PERCENT = ns.Assumptions.IN_PERCENT

local function Rating(id) return id and Read(GetCombatRatingBonus, id) or 0 end
local function Hit(id, modifier)
    local bonus = Read(modifier)
    if bonus == nil then return nil end
    return Rating(id) + bonus
end
local function School(index) return function() return (Read(GetSpellBonusDamage, index)) end end
local function Attribute(index) return function() return (select(2, Read(UnitStat, "player", index))) end end
local function Plus(fn)
    return function()
        local base, pos, neg = Read(fn, "player")
        return base and base + (pos or 0) + (neg or 0)
    end
end

-- Stat name -> its value now, nil when the client hides it. The same calls as the character sheet.
local READERS = {
    strength = Attribute(1), agility = Attribute(2), stamina = Attribute(3),
    intellect = Attribute(4), spirit = Attribute(5),
    attack_power = Plus(UnitAttackPower), ranged_attack_power = Plus(UnitRangedAttackPower),
    fire_power = School(3), nature_power = School(4), frost_power = School(5),
    shadow_power = School(6), arcane_power = School(7),
    spell_power = function()
        local best
        for school = 2, 7 do
            local v = Read(GetSpellBonusDamage, school)
            if v and (not best or v > best) then best = v end
        end
        return best
    end,
    healing = function() return (Read(GetSpellBonusHealing)) end,
    crit_chance = function() return (Read(GetCritChance)) end,
    spell_crit = function() return (Read(GetSpellCritChance, 3)) end,
    melee_hit = function() return Hit(CR_HIT_MELEE, GetHitModifier) end,
    ranged_hit = function() return Hit(CR_HIT_RANGED, GetRangedHitModifier) end,
    spell_hit = function() return Hit(CR_HIT_SPELL, GetSpellHitModifier) end,
    haste = function() return (Read(GetMeleeHaste)) end,
    mana_regen = function()
        local v = Read(GetManaRegen)
        return v and v * 5
    end,
    armor = function() return (select(2, Read(UnitArmor, "player"))) end,
    defense_skill = function()
        local base, mod = Read(UnitDefenseSkill, "player")
        return base and base + (mod or 0)
    end,
    dodge_rating = function() return (Read(GetDodgeChance)) end,
    parry_rating = function() return (Read(GetParryChance)) end,
    block_chance = function() return (Read(GetBlockChance)) end,
    block_value = function() return (Read(GetShieldBlock)) end,
}

-- Stats an offset can use, beyond a profile's: the other two kinds of hit.
C.OFFSET_EXTRA = { ranged_hit = "Ranged Hit", spell_hit = "Spell Hit" }

local last = {} -- what each stat last read as, for while it's hidden

-- A stat's value now: the last readable one while it's hidden, nil when it never was.
function C.Read(name)
    local reader = READERS[name]
    local ok, value = false, nil
    if reader then ok, value = pcall(reader) end
    if ok and type(value) == "number" then last[name] = value end
    return last[name]
end

function C.Label(name)
    return C.OFFSET_EXTRA[name] or API:GetStatLabel(D.STAT_KEYS[name] or name)
end

-- What a stat's own caps are measured on (Hit reads spell or ranged hit for some specs).
function C.Value(name, entry) return C.Read(entry and entry.reads or name) end

-- How far one offset moves its tier now. Up to offset.cap the stat counts at factor; past it, at
-- factor_after (default 0: it stops moving the tier). No cap: factor all the way.
function C.Offset(offset)
    local value = C.Read(offset.stat) or 0
    local factor, cap = offset.factor or 0, offset.cap
    if not cap or value <= cap then return value * factor end
    return cap * factor + (value - cap) * (offset.factor_after or 0)
end

-- A tier's threshold after its offsets.
function C.Threshold(tier)
    local at = tier.threshold or 0
    for _, offset in ipairs(tier.offsets or {}) do at = at + C.Offset(offset) end
    return at
end

-- { { tier, at } } by where the tiers sit now: offsets can move one past another.
function C.Tiers(entry)
    local out = {}
    for i, tier in ipairs(entry.cap_tiers or {}) do out[i] = { tier = tier, at = C.Threshold(tier), order = i } end
    table.sort(out, function(a, b)
        if a.at ~= b.at then return a.at < b.at end
        return a.order < b.order
    end)
    return out
end

-- weight, the tier in force (nil: the base weight) at value.
function C.Resolve(entry, value)
    local weight, active = entry.base_weight or 0, nil
    for _, t in ipairs(C.Tiers(entry)) do
        if (value or 0) >= t.at then weight, active = t.tier.weight or 0, t.tier end
    end
    return weight, active
end

function C.Weight(name, entry)
    if not entry then return 0 end
    return (C.Resolve(entry, C.Value(name, entry)))
end

---------------------------------------------------------------------------
-- Public API (see README.md). stat takes either name: "melee_hit" or "HIT".
---------------------------------------------------------------------------

local function Entry(stat)
    local profile = P.Active()
    local name = P.StatName(stat)
    return profile and name and profile.stats[name], name
end

function API:GetActiveProfile() return P.Copy((P.Active())) end

function API:GetWeight(stat)
    local entry, name = Entry(stat)
    return C.Weight(name, entry)
end

-- base_weight, cap_tiers (a copy), for addons doing their own cap logic.
function API:GetWeightRaw(stat)
    local entry = Entry(stat)
    if not entry then return 0, {} end
    return entry.base_weight or 0, P.Copy(entry.cap_tiers or {})
end

-- { [stat key] = weight } with the caps worked out; stats worth nothing are left out.
function API:GetAllWeights()
    local out = {}
    local profile = P.Active()
    for name, entry in pairs(profile and profile.stats or {}) do
        local weight = C.Weight(name, entry)
        if weight ~= 0 then out[D.STAT_KEYS[name]] = weight end
    end
    return out
end

-- { { threshold, label, weight, at, offsets, reached } } in the order they apply now. at is the
-- threshold after offsets; reached says whether your stat is there.
function API:GetCapInfo(stat)
    local entry, name = Entry(stat)
    local out = {}
    if not entry then return out end
    local value = C.Value(name, entry) or 0
    for i, t in ipairs(C.Tiers(entry)) do
        local tier = P.Copy(t.tier)
        tier.at, tier.reached = t.at, value >= t.at
        out[i] = tier
    end
    return out
end

-- fn(label) when your active profile changes. Same as the PROFILE_CHANGED event.
ns.APIListener(API, "OnProfileChanged", "PROFILE_CHANGED")
