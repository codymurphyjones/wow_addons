local _, ns = ...
local API = ns.API

-- What stats are worth, for your class and level: the one conversion every addon scores
-- through (Tape Measure, SpyGlass), so they always agree. Your priority (GetWeights) says
-- which stats you prefer; this says what a point of each is worth next to the others.
--
-- On top of flat item budgets:
-- 1. Crit is priced in the stat that buys it. 1% crit costs as much as the Agility that
--    gives 1% crit to your class at your level (a level 30 druid: about 10), never more
--    than its item budget. A flat 14 made one 1% crit item outrank 10 Agility.
-- 2. Stats share in what they produce. A point of Agility also gives crit (and, for some
--    classes, attack power and armor); it earns DERIVED_SHARE of their worth by your
--    weights. Half, not all, so stacking one stat can't run away.
local Cv = {}
ns.Convert = Cv

-- Roughly what one point of each stat costs an item, with a point of a main stat as 1.
Cv.BUDGET = {
    STR = 1, AGI = 1, STA = 1, INT = 1, SPI = 1,
    AP = 0.5, RAP = 0.4, SP = 0.86, HEAL = 0.45,
    FIRE = 0.7, FROST = 0.7, SHADOW = 0.7, ARCANE = 0.7, NATURE = 0.7,
    MP5 = 2.5, DEF = 1.2, BLOCKVALUE = 0.15, ARMOR = 0.04, DPS = 3,
}

-- Stats items give as a percent in classic ("+1% crit"). Their budget is per percent. Values
-- above 5 are taken to be ratings instead (about 14 rating per percent), worth 1 each.
Cv.PERCENT_BUDGET = { CRIT = 14, SPELLCRIT = 14, HIT = 14, HASTE = 10, DODGE = 12, PARRY = 20, BLOCK = 5 }
local MAX_PERCENT = 5

function Cv:IsPercent(stat, amount)
    return self.PERCENT_BUDGET[stat] ~= nil and math.abs(amount or 0) <= MAX_PERCENT
end

-- The flat item budget of one point of stat, for an item that has amount of it.
function Cv:FlatBudget(stat, amount)
    if self.PERCENT_BUDGET[stat] then
        return self:IsPercent(stat, amount) and self.PERCENT_BUDGET[stat] or 1
    end
    return self.BUDGET[stat] or 0
end

Cv.DERIVED_SHARE = 0.5

-- Agility per 1% melee crit at level 60 (classic). Lower levels need less (see AgiPerCrit).
local AGI_PER_CRIT_60 = {
    WARRIOR = 20, PALADIN = 20, HUNTER = 53, ROGUE = 29, PRIEST = 20,
    SHAMAN = 20, MAGE = 20, WARLOCK = 20, DRUID = 20,
}
-- Intellect per 1% spell crit at level 60.
local INT_PER_SPELLCRIT_60 = {
    PALADIN = 54, PRIEST = 59, SHAMAN = 59, MAGE = 60, WARLOCK = 61, DRUID = 60,
}

-- What one point of a stat also gives, per class: { to stat, amount per point }.
-- Agility: crit (from the class's ratio), attack power, 2 armor. Strength: attack power.
-- Intellect: spell crit for casters.
local DERIVED = {
    WARRIOR = { STR = { { "AP", 2 } }, AGI = { { "CRIT", "agi" }, { "ARMOR", 2 } } },
    PALADIN = { STR = { { "AP", 2 } }, AGI = { { "CRIT", "agi" }, { "ARMOR", 2 } }, INT = { { "SPELLCRIT", "int" } } },
    HUNTER = { STR = { { "AP", 1 } }, AGI = { { "CRIT", "agi" }, { "RAP", 2 }, { "AP", 1 }, { "ARMOR", 2 } } },
    ROGUE = { STR = { { "AP", 1 } }, AGI = { { "CRIT", "agi" }, { "AP", 1 }, { "ARMOR", 2 } } },
    PRIEST = { INT = { { "SPELLCRIT", "int" } } },
    SHAMAN = { STR = { { "AP", 2 } }, AGI = { { "CRIT", "agi" }, { "ARMOR", 2 } }, INT = { { "SPELLCRIT", "int" } } },
    MAGE = { INT = { { "SPELLCRIT", "int" } } },
    WARLOCK = { INT = { { "SPELLCRIT", "int" } } },
    DRUID = { STR = { { "AP", 2 } }, AGI = { { "CRIT", "agi" }, { "AP", 2 }, { "ARMOR", 2 } }, INT = { { "SPELLCRIT", "int" } } },
}

local class, level, agiPerCrit, intPerSpellCrit

-- Forgets the class and level figures (on level-up).
function Cv:Reset()
    class, level, agiPerCrit, intPerSpellCrit = nil, nil, nil, nil
end

local function Who()
    if not class then
        class = select(2, UnitClass("player"))
        level = UnitLevel("player") or 60
    end
    return class, level
end

-- Ratios grow with level; at level L about L/60 of the level 60 figure, at least a quarter.
local function Scaled(at60)
    local _, lvl = Who()
    return at60 * math.max(0.25, math.min(1, lvl / 60))
end

-- Agility per 1% crit for you: the game's own figure when it gives one, else the table.
function Cv:AgiPerCrit()
    if agiPerCrit then return agiPerCrit end
    local cls = Who()
    if GetCritChanceFromAgility and UnitStat then
        local ok, fromAgi = pcall(GetCritChanceFromAgility, "player")
        local agi = select(2, UnitStat("player", 2))
        if ok and type(fromAgi) == "number" and fromAgi > 0 and agi and agi > 0 then
            agiPerCrit = agi / fromAgi
        end
    end
    agiPerCrit = agiPerCrit or Scaled(AGI_PER_CRIT_60[cls] or 20)
    return agiPerCrit
end

function Cv:IntPerSpellCrit()
    if intPerSpellCrit then return intPerSpellCrit end
    local cls = Who()
    intPerSpellCrit = Scaled(INT_PER_SPELLCRIT_60[cls] or 60)
    return intPerSpellCrit
end

-- What one point (or one percent) of stat is worth before your weights, for an item that has
-- amount of it. Crit percents cost the stat that buys them, capped at their item budget.
function Cv:Budget(stat, amount)
    local budget = self:FlatBudget(stat, amount)
    if self:IsPercent(stat, amount) then
        if stat == "CRIT" then return math.min(budget, self:AgiPerCrit()) end
        if stat == "SPELLCRIT" then return math.min(budget, self:IntPerSpellCrit()) end
    end
    return budget
end

-- The worth of amount of stat under weights ({ [stat] = weight }, StatLedger's): its own
-- worth plus DERIVED_SHARE of what it produces.
function Cv:Value(stat, amount, weights)
    local own = amount * self:Budget(stat, amount) * (weights[stat] or 0)
    local derived = 0
    local list = DERIVED[(Who())] and DERIVED[(Who())][stat]
    if list and amount > 0 then
        for _, d in ipairs(list) do
            local to, per = d[1], d[2]
            local w = weights[to]
            if w and w > 0 then
                if per == "agi" then per = 1 / self:AgiPerCrit() end
                if per == "int" then per = 1 / self:IntPerSpellCrit() end
                -- Derived crit is a percent: priced like the crit an item would give.
                local unit = (to == "CRIT" or to == "SPELLCRIT") and self:Budget(to, 1) or self:FlatBudget(to, per)
                derived = derived + amount * per * unit * w
            end
        end
    end
    return own + derived * self.DERIVED_SHARE
end

-- total, contrib { [stat] = worth } for an item's values { [stat] = amount }. Each stat's
-- contribution includes its share of what it produces.
function Cv:Score(values, weights)
    local total, contrib = 0, {}
    for stat, amount in pairs(values) do
        if type(amount) == "number" and amount ~= 0 then
            local c = self:Value(stat, amount, weights)
            if c ~= 0 then
                contrib[stat] = c
                total = total + c
            end
        end
    end
    return total, contrib
end

---------------------------------------------------------------------------
-- Public API (see README.md)
---------------------------------------------------------------------------

-- weights default to your priority's (GetWeights).
function API:Score(values, weights) return Cv:Score(values, weights or self:GetWeights()) end
function API:Value(stat, amount, weights) return Cv:Value(stat, amount, weights or self:GetWeights()) end
function API:Budget(stat, amount) return Cv:Budget(stat, amount) end
function API:IsPercent(stat, amount) return Cv:IsPercent(stat, amount) end

-- Levelling changes the crit ratios: callbacks get "VALUES_CHANGED".
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:SetScript("OnEvent", function()
    Cv:Reset()
    ns.Fire("VALUES_CHANGED")
end)
