local _, ns = ...
local C = ns.Compat

-- Records every PvE fight lightly while it happens: which mobs joined and when (nameplates and
-- target), your own casts, the casts the mobs started, and how you came into it (health, mana,
-- pet). When it ends (won, or you died) the damage meter is read for it; a won fight is kept as a
-- compact record, a death goes to the coach (Coach.lua).
local Watch = {}
ns.Watch = Watch

local SCAN_EVERY = 0.4
local KEEP_FIGHTS = 300

Watch.fight = nil
local pre = {}           -- how you are right now, out of combat
local maxHp = {}         -- npcID or "name:level" -> max health seen out of combat

local function NpcID(unit)
    local guid = C.Str(C.Call(UnitGUID, unit))
    return guid and tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)")), guid
end

local function Pct(cur, max)
    cur, max = C.Num(cur), C.Num(max)
    return cur and max and max > 0 and cur / max or nil
end

-- Out of combat: remember health and mana, and mobs' max health while it's readable.
local function NoteUnit(unit)
    if not C.Call(UnitExists, unit) or C.Bool(C.Call(UnitIsPlayer, unit)) then return end
    local id = NpcID(unit)
    local name, level = C.Str(C.Call(UnitName, unit)), C.Num(C.Call(UnitLevel, unit))
    local hp = C.Num(C.Call(UnitHealthMax, unit))
    if hp and hp > 0 then
        maxHp[id or ((name or "?") .. ":" .. (level or 0))] = hp
    end
end

local function Snapshot()
    if InCombatLockdown() then return end
    pre.hp = Pct(UnitHealth("player"), UnitHealthMax("player"))
    pre.power = Pct(UnitPower("player"), UnitPowerMax("player"))
    pre.powerType = select(2, UnitPowerType("player"))
    pre.pet = UnitExists("pet") and not UnitIsDeadOrGhost("pet") or false
    pre.petHp = UnitExists("pet") and Pct(UnitHealth("pet"), UnitHealthMax("pet")) or nil
    pre.maxHp = C.Num(UnitHealthMax("player"))
    pre.t = GetTime()
end

-- A mob in the fight (added once, with when it joined).
local function AddMob(f, unit)
    if not C.Call(UnitExists, unit) then return end
    if C.Bool(C.Call(UnitIsPlayer, unit)) then
        if C.Bool(C.Call(UnitCanAttack, "player", unit)) then f.pvp = true end
        return
    end
    if not C.Bool(C.Call(UnitCanAttack, "player", unit)) then return end
    if not C.Bool(C.Call(UnitAffectingCombat, unit)) then return end
    local id, guid = NpcID(unit)
    local name = C.Str(C.Call(UnitName, unit))
    local key = guid or (name and (name .. ":" .. tostring(unit)))
    if not key or f.mobs[key] then return end
    local level = C.Num(C.Call(UnitLevel, unit))
    local m = {
        name = name or "?", level = level, npcID = id, kind = C.Str(C.Call(UnitCreatureType, unit)),
        rank = C.Str(C.Call(UnitClassification, unit)), at = GetTime() - f.startGT,
        maxHp = maxHp[id or ((name or "?") .. ":" .. (level or 0))],
    }
    local data = id and ns.Mobs and ns.Mobs.npcs[id]
    if data then
        m.kind = m.kind or (ns.Mobs.types and ns.Mobs.types[data[4]])
        m.mech, m.school, m.flee, m.spells = data.mech, data.school, data.flee, data.spells
        m.dbRank = data[5]
    end
    f.mobs[key] = m
    table.insert(f.order, key)
    local n = 0
    for _ in pairs(f.mobs) do n = n + 1 end
    if n > f.peak then f.peak = n end
end

local function Start()
    if Watch.fight then return end
    local f = {
        start = time(), startGT = GetTime(), mobs = {}, order = {}, peak = 0, casts = {}, enemyCasts = {},
        pre = { hp = pre.hp, power = pre.power, powerType = pre.powerType, pet = pre.pet, petHp = pre.petHp, maxHp = pre.maxHp },
        level = UnitLevel("player"), zone = C.Str(GetRealZoneText and GetRealZoneText()), group = IsInGroup() or nil,
    }
    Watch.fight = f
    AddMob(f, "target")
end

local function Scan()
    local f = Watch.fight
    if not f then return end
    AddMob(f, "target")
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if C.Call(UnitExists, unit) then AddMob(f, unit) end
    end
end

-- The fight is over: read the meter, then hand it on.
function Watch:Finish()
    local f = self.fight
    if not f then return end
    self.fight = nil
    f.duration = GetTime() - f.startGT
    f.died = UnitIsDeadOrGhost("player") or f.died
    f.startGT = nil
    if f.pvp or #f.order == 0 and not f.died then return end
    local session = ns.Meter.NewestSessionID()
    ns.Meter.ReadAfterCombat(session, function(data, why)
        f.meter, f.meterMissing = data, (not data) and why or nil
        if f.died then
            ns.Coach:OnFightOver(f)
        else
            Watch:Keep(f)
        end
    end)
end

-- A compact record of a fight, for comparing your deaths against your wins.
function Watch:Keep(f)
    local mobs, kinds, casters = 0, {}, 0
    for _, key in ipairs(f.order) do
        local m = f.mobs[key]
        mobs = mobs + 1
        if m.kind then kinds[m.kind] = true end
        local n = f.enemyCasts[key]
        if n and n > 0 then casters = casters + 1 end
    end
    local defensive, heals, interrupts = 0, 0, 0
    local kit = ns.Kit.data
    for _, c in ipairs(f.casts) do
        local s = kit and (kit.spells[c.name or ""] or kit.pet[c.name or ""])
        if s then
            if s.tags.defensive then defensive = defensive + 1 end
            if s.tags.heal then heals = heals + 1 end
            if s.tags.interrupt then interrupts = interrupts + 1 end
        end
    end
    local rec = {
        t = f.start, won = not f.died, duration = math.floor(f.duration), mobs = mobs, casters = casters,
        defensive = defensive, heals = heals, interrupts = interrupts, level = f.level,
        maxDiff = (function()
            local d = 0
            for _, key in ipairs(f.order) do d = math.max(d, (f.mobs[key].level or f.level) - f.level) end
            return d
        end)(),
        dps = f.meter and f.meter.duration and f.meter.duration > 0 and math.floor(f.meter.done.total / f.meter.duration) or nil,
        taken = f.meter and f.meter.taken.total or nil,
    }
    local list = {}
    for k in pairs(kinds) do list[#list + 1] = k end
    rec.kinds = table.concat(list, ",")
    table.insert(ns.db.fights, rec)
    while #ns.db.fights > KEEP_FIGHTS do table.remove(ns.db.fights, 1) end
    ns:Changed()
end

-- ---------------------------------------------------------------------------

ns:On("PLAYER_REGEN_DISABLED", Start)
ns:On("PLAYER_REGEN_ENABLED", function() C_Timer.After(0.2, function() Watch:Finish() end) end)
ns:On("PLAYER_DEAD", function()
    if Watch.fight then Watch.fight.died = true end
end)

ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    local f = Watch.fight
    if not f or unit ~= "player" then return end
    local id = C.Num(spellID)
    if not id then return end
    table.insert(f.casts, { at = GetTime() - (f.startGT or GetTime()), id = id, name = C.SpellName(id) })
end)

local function EnemyCast(unit)
    local f = Watch.fight
    if not (f and unit and (unit == "target" or unit:find("^nameplate"))) then return end
    if C.Bool(C.Call(UnitIsPlayer, unit)) or not C.Bool(C.Call(UnitCanAttack, "player", unit)) then return end
    local _, guid = NpcID(unit)
    local key = guid
    if not key then return end
    f.enemyCasts[key] = (f.enemyCasts[key] or 0) + 1
    local name = C.Str((C.Call(UnitCastingInfo, unit))) or C.Str((C.Call(UnitChannelInfo, unit)))
    if name then
        f.castNames = f.castNames or {}
        f.castNames[name] = (f.castNames[name] or 0) + 1
    end
end
ns:On("UNIT_SPELLCAST_START", EnemyCast)
ns:On("UNIT_SPELLCAST_CHANNEL_START", EnemyCast)

ns:On("PLAYER_TARGET_CHANGED", function()
    if not InCombatLockdown() then NoteUnit("target") end
end)
ns:On("NAME_PLATE_UNIT_ADDED", function(unit)
    if not InCombatLockdown() then NoteUnit(unit) end
end)

local acc = 0
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < SCAN_EVERY then return end
    acc = 0
    if Watch.fight then Scan() else Snapshot() end
end)
