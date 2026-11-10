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
-- 2. Strength and Agility are worth what they turn into. When one gives attack power you
--    value (AP or RAP in your list), it's priced as exactly what it produces, at full rate:
--    a cat's Strength is 2 AP, its Agility 1 AP plus its crit and armor. Its own rank and
--    item budget don't count then; budget is what a stat costs an item, not what it's worth.
-- 3. Other stats share in what they produce (Intellect's spell crit, Agility's crit for a
--    class whose Agility gives no attack power): DERIVED_SHARE of its worth on top of their
--    own. Half, not all, so stacking one stat can't run away.
local Cv = {}
ns.Convert = Cv

-- The figures are all in Assumptions.lua.
local A = ns.Assumptions

function Cv:IsPercent(stat, amount)
    return A.PERCENT_BUDGET[stat] ~= nil and math.abs(amount or 0) <= A.MAX_PERCENT
end

-- The flat item budget of one point of stat, for an item that has amount of it.
function Cv:FlatBudget(stat, amount)
    if A.PERCENT_BUDGET[stat] then
        return self:IsPercent(stat, amount) and A.PercentBudget(stat) or 1
    end
    return A.Budget(stat)
end

local class, agiPerCrit, intPerSpellCrit

-- Forgets the class and level figures (on level-up).
function Cv:Reset()
    class, agiPerCrit, intPerSpellCrit = nil, nil, nil
end

local function Who()
    if not class then class = select(2, UnitClass("player")) end
    return class
end

function Cv:AgiPerCrit()
    agiPerCrit = agiPerCrit or A.Get("agi_per_crit")
    return agiPerCrit
end

function Cv:IntPerSpellCrit()
    intPerSpellCrit = intPerSpellCrit or A.Get("int_per_spellcrit")
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

-- Whether stat turns into attack power you value: then it's worth only what it produces.
local POWER = { AP = true, RAP = true }
local function Converts(list, weights)
    for _, d in ipairs(list) do
        if POWER[d[1]] and (weights[d[1]] or 0) > 0 then return true end
    end
    return false
end

-- The worth of amount of stat under weights ({ [stat] = weight }, StatLedger's): what it
-- produces at full rate when it turns into attack power you value, else its own worth plus
-- DERIVED_SHARE of what it produces.
function Cv:Value(stat, amount, weights)
    local list = A.DERIVED[Who()] and A.DERIVED[Who()][stat]
    local full = list and amount > 0 and Converts(list, weights)
    local own = full and 0 or amount * self:Budget(stat, amount) * (weights[stat] or 0)
    local derived = 0
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
    return own + derived * (full and 1 or A.Solve(A.DERIVED_SHARE))
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

-- Assumptions.lua's conversions, for other addons.
function API:ToPercent(stat, points) return A.ToPercent(stat, points) end
function API:ToPoints(stat, percent) return A.ToPoints(stat, percent) end
function API:EffectRates(kind) return A.EffectRates(kind) end

-- Levelling changes the crit ratios: callbacks get "VALUES_CHANGED".
ns:On("PLAYER_LEVEL_UP", function()
    Cv:Reset()
    ns.Fire("VALUES_CHANGED")
end)
