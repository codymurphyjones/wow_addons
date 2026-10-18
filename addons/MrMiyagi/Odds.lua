local _, ns = ...

-- A simple duel model of the fight you lost, built from what actually happened: how fast you were
-- killing the mobs (your damage per second, from the meter) against how fast they were killing you
-- (their damage per second), your health against theirs. The odds compare time-to-kill with
-- time-to-die, with room for luck. Each lesson says how it changes the fight in this model, so
-- the window can show your odds today and with the advice applied. Every number is an estimate.
local Odds = {}
ns.Odds = Odds

-- A mob's health when it couldn't be read: by level, tripled for elites.
function Odds.MobHealth(level, elite)
    level = math.max(1, level or 1)
    local hp = 42 + level * 15 + level * level * 0.82
    return math.floor(hp * (elite and 3 or 1))
end

local function Logistic(r)
    -- r = time to die / time to kill: 1 is a coin flip, 2 is comfortable, 0.5 is a loss.
    if r <= 0 then return 0 end
    -- About 90% when you'd last twice as long as they would, 10% at half as long.
    return 1 / (1 + math.exp(-2.2 * (math.log(r) / math.log(2))))
end

-- The fight as numbers: { myDps, inDps, myHp, startFrac, mobHp, sources = { [mob] = dps } }.
function Odds.Model(f)
    local m = f.meter
    local dur = math.max(3, (m and m.duration) or f.duration or 10)
    local model = {
        dur = dur,
        myDps = m and m.done.total / dur or 0,
        inDps = m and m.taken.total / dur or 0,
        myHp = f.pre.maxHp or (UnitHealthMax("player")) or 100,
        startFrac = f.pre.hp or 1,
        sources = {}, kinds = { melee = 0, cast = 0, periodic = 0 },
    }
    for _, r in ipairs(m and m.taken.rows or {}) do
        local who = r.other or "?"
        model.sources[who] = (model.sources[who] or 0) + r.amount / dur
        local kind = r.melee and "melee" or "cast"
        model.kinds[kind] = model.kinds[kind] + r.amount / dur
    end
    local hp = 0
    for _, key in ipairs(f.order) do
        local mob = f.mobs[key]
        local elite = mob.rank == "elite" or mob.rank == "rareelite" or mob.rank == "worldboss" or (mob.dbRank or 0) == 1
        mob.estHp = mob.maxHp or Odds.MobHealth(mob.level, elite)
        hp = hp + mob.estHp
    end
    model.mobHp = math.max(1, hp)
    return model
end

-- Chance of winning a fight like this one: 0..1.
function Odds.Chance(model)
    local ttk = model.mobHp / math.max(1, model.myDps)
    local ttd = (model.myHp * model.startFrac + (model.extraHp or 0)) / math.max(1, model.inDps)
    return Logistic(ttd / ttk), ttd, ttk
end

-- A copy of the model with lesson effects applied. Effects:
--   extraHp (health from potions, heals, shields), inDpsMul (damage taken multiplier), startFull,
--   dropSources (mobs taken out of this fight: their damage and health), myDpsMul, castMul (cast damage
--   multiplier), meleeMul.
function Odds.Apply(model, effects)
    local m = {}
    for k, v in pairs(model) do m[k] = v end
    m.sources = {}
    for k, v in pairs(model.sources) do m.sources[k] = v end
    m.extraHp = 0
    for _, e in ipairs(effects) do
        if e.extraHp then m.extraHp = m.extraHp + e.extraHp end
        if e.startFull then m.startFrac = 1 end
        if e.myDpsMul then m.myDps = m.myDps * e.myDpsMul end
        if e.inDpsMul then m.inDps = m.inDps * e.inDpsMul end
        if e.castMul then m.inDps = m.inDps - model.kinds.cast * (1 - e.castMul) end
        if e.meleeMul then m.inDps = m.inDps - model.kinds.melee * (1 - e.meleeMul) end
        for name, hp in pairs(e.dropSources or {}) do
            if m.sources[name] then
                m.inDps = m.inDps - m.sources[name]
                m.sources[name] = nil
            end
            m.mobHp = math.max(1, m.mobHp - hp)
        end
    end
    m.inDps = math.max(1, m.inDps)
    return m
end

-- The level at which a fight like this becomes an even match, roughly: each level you gain makes
-- your hits land more and theirs less (about 6% each way) and adds health.
function Odds.EvenLevel(model, level)
    for gain = 0, 15 do
        local m = {}
        for k, v in pairs(model) do m[k] = v end
        m.myDps = model.myDps * (1 + 0.06 * gain)
        m.inDps = model.inDps * (1 - 0.05 * gain)
        m.myHp = model.myHp * (1 + 0.05 * gain)
        if Odds.Chance(m) >= 0.5 then return level + gain end
    end
end

function Odds.Percent(p)
    if p >= 0.99 then return "99%+" end
    if p < 0.01 then return "under 1%" end
    return ("%d%%"):format(math.floor(p * 100 + 0.5))
end
