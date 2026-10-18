local _, ns = ...
local C = ns.Compat

-- One pull during a run. While it lasts it watches what can be seen live: who entered combat
-- first (the puller), how many hostile mobs were in combat at once, the encounter, and the order
-- people died in. When combat ends it reads the fight from Blizzard's damage meter (damage, healing,
-- damage taken, avoidable damage, interrupts, deaths with their recaps; Meter.lua) and hands every
-- death to Blame.lua.
local Fight = {}
ns.Fight = Fight

local MERGE = 4            -- seconds out of combat before a fight counts as over
local PULLER_WINDOW = 6    -- someone in combat this long before you counts toward who pulled
local SCAN_EVERY = 0.5

Fight.current = nil
local combatSince = {}     -- short name -> GetTime() they last went into combat
local wasInCombat = {}     -- short name -> true while in combat
local deadNow = {}         -- short name -> true while dead

local function Units()
    local units = C.GroupUnits()
    units[#units + 1] = "player"
    return units
end

local function InCombat(unit) return C.Bool(C.Call(UnitAffectingCombat, unit)) end
local function IsDead(unit) return C.Bool(C.Call(UnitIsDeadOrGhost, unit)) end

-- Watches party units going into combat and dying (both readable on this client out of the
-- combat log; when they're hidden we simply learn less).
local function ScanUnits()
    local now = GetTime()
    for _, unit in ipairs(Units()) do
        local name = C.Short(C.UnitFull(unit))
        if name then
            local inCombat = InCombat(unit)
            if inCombat and not wasInCombat[name] then combatSince[name] = now end
            wasInCombat[name] = inCombat or nil
            local dead = IsDead(unit)
            local f = Fight.current
            if dead and not deadNow[name] and f then
                f.deathOrder[#f.deathOrder + 1] = { name = name, at = now - f.startGT }
                if ns.DeathPopup then ns.DeathPopup:OnLiveDeath(f, name) end
            end
            deadNow[name] = dead or nil
        end
    end
end

-- Hostile mobs in combat, from nameplates.
local function CountMobs()
    local n = 0
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if C.Call(UnitExists, unit) and not C.Bool(C.Call(UnitIsPlayer, unit)) then
            if C.Bool(C.Call(UnitCanAttack, "player", unit)) and InCombat(unit) then n = n + 1 end
        end
    end
    return n
end

local function Start()
    local run = ns.Run:Active()
    if not run then return end
    local f = Fight.current
    if f and f.ending then
        f.ending = nil -- back in combat before it counted as over: the same fight
        return
    end
    local now = GetTime()
    f = { start = time(), startGT = now, mobs = 0, deathOrder = {}, deaths = {} }
    -- Who went into combat first, within a few seconds before you.
    local first, firstAt
    for name, at in pairs(combatSince) do
        if now - at <= PULLER_WINDOW and wasInCombat[name] and (not firstAt or at < firstAt) then first, firstAt = name, at end
    end
    f.puller = first
    Fight.current = f
    table.insert(run.fights, f)
end

local function Finish()
    local f = Fight.current
    local run = ns.Run:Active()
    if not f then return end
    Fight.current = nil
    f.duration = math.floor(GetTime() - f.startGT + 0.5)
    local sessionID = ns.Meter.NewestSessionID()
    -- Everyone dead: a wipe (boss wipes are also counted by ENCOUNTER_END).
    local members, dead = 0, 0
    for _, unit in ipairs(Units()) do
        members = members + 1
        if IsDead(unit) then dead = dead + 1 end
    end
    if members > 1 and dead == members and not f.encounter then
        f.wipe = true
        if run then run.wipes = run.wipes + 1 end
    end
    ns.Meter.ReadAfterCombat(sessionID, function(data, why)
        f.stats = data
        if data then
            f.ledger = ns.Meter.Ledger(sessionID)
            f.received = f.ledger and ns.Meter.Received(f.ledger)
        end
        f.statsMissing = not data and why or nil
        Fight:Analyze(run, f)
    end)
end

-- Reads every death's recap and blames it.
function Fight:Analyze(run, f)
    if not run then return end
    local stats = f.stats or {}
    for name, p in pairs(stats) do
        if p.death and not f.deaths[name] then
            local hits, maxHp = ns.Recap.Read(p.death.recapID)
            f.deaths[name] = { victim = name, hits = hits, maxHp = maxHp, class = p.class }
        end
    end
    -- Deaths seen live but missing from the meter (or with no recap yet): keep them too.
    for _, d in ipairs(f.deathOrder) do
        if not f.deaths[d.name] then f.deaths[d.name] = { victim = d.name } end
        f.deaths[d.name].at = f.deaths[d.name].at or d.at
    end
    if ns.Sync then ns.Sync:FillFromPeers(f) end
    ns.History:InferRoles(run, f)
    -- In the order they died: a later death may be blamed on whoever caused an earlier one.
    local order = {}
    for _, d in pairs(f.deaths) do order[#order + 1] = d end
    table.sort(order, function(a, b) return (a.at or 999) < (b.at or 999) end)
    for i, d in ipairs(order) do
        d.nth = i
        if not d.analyzed then
            d.analyzed = true
            d.t = f.start + math.floor(d.at or f.duration or 0)
            d.fight = #run.fights
            d.encounter = f.encounter
            ns.Blame:Analyze(run, f, d)
            table.insert(run.deaths, d)
            if not run.temp then ns.History:OnDeath(run, d) end
        end
    end
    if ns.db.options.debug then self:Print(f) end
    if ns.DeathPopup then ns.DeathPopup:OnAnalyzed(f, order) end
    if run.temp then ns.Run:UpdateTemp() end
    -- The deaths live on in run.deaths; the fight keeps a count (saved variables would copy them twice).
    local n = 0
    for _ in pairs(f.deaths) do n = n + 1 end
    f.deathCount, f.deaths, f.deathOrder, f.startGT, f.ending = n, nil, nil, nil, nil
    ns:Changed()
end

function Fight:Print(f)
    ns:Debug(("Fight: %ds, %d mobs, puller %s%s%s"):format(f.duration or 0, f.mobs or 0, f.puller or "?",
        f.encounter and (", " .. f.encounter) or "", f.wipe and ", WIPE" or ""))
    if not f.stats then return ns:Debug("  meter data: " .. tostring(f.statsMissing or "none")) end
    for name, p in pairs(f.stats) do
        ns:Debug(("  %s: dmg %d, heal %d, taken %d, avoidable %d, kicks %d%s"):format(name, p.done, p.healed, p.taken,
            p.avoidable, p.interrupts, p.death and (", DIED (recap " .. tostring(p.death.recapID) .. ")") or ""))
    end
    for name, d in pairs(f.deaths) do
        ns:Debug(("  death of %s: %d hits read; most likely %s"):format(name, d.hits and #d.hits or 0, d.top or "?"))
    end
end

function Fight:OnEncounter(name)
    if self.current then self.current.encounter = name end
end

function Fight:MarkWipe()
    if self.current then self.current.wipe = true end
end

-- Your own death: your recap is readable straight away (with or without the meter).
ns:On("PLAYER_DEAD", function()
    local f, run = Fight.current, ns.Run:Active()
    if not (f and run) then return end
    if ns.DeathPopup then ns.DeathPopup:Open(run, f) end
    local me = C.Short(run.me)
    ns.Recap.ReadOwnAfterDeath(function(hits, maxHp)
        if not hits or not f.deaths then return end
        local d = f.deaths[me] or { victim = me }
        d.hits, d.maxHp = d.hits or hits, d.maxHp or maxHp
        d.at = d.at or (GetTime() - f.startGT)
        f.deaths[me] = d
        if ns.DeathPopup then ns.DeathPopup:Refresh() end
        if ns.Sync then ns.Sync:ShareDeath(me, hits, maxHp) end
    end)
end)

ns:On("PLAYER_REGEN_DISABLED", Start)
-- The fight is over once nobody in the group is fighting (you may be dead while they carry on).
local function AnyoneFighting()
    for _, unit in ipairs(Units()) do
        if InCombat(unit) then return true end
    end
    return false
end

ns:On("PLAYER_REGEN_ENABLED", function()
    local f = Fight.current
    if not f then return end
    f.ending = true
    local function Check()
        if Fight.current ~= f or not f.ending or InCombatLockdown() then return end
        if AnyoneFighting() then return C_Timer.After(2, Check) end
        Finish()
    end
    C_Timer.After(MERGE, Check)
end)

local acc = 0
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, elapsed)
    if not ns.Run:Active() then return end
    acc = acc + elapsed
    if acc < SCAN_EVERY then return end
    acc = 0
    ScanUnits()
    local f = Fight.current
    if f and not f.ending then
        local n = CountMobs()
        if n > f.mobs then f.mobs = n end
    end
end)
