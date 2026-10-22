local _, ns = ...
local C = ns.Compat

-- One dungeon run: from entering a 5-man dungeon with a party until you leave it for good (a short
-- time outside covers corpse runs) or the group breaks up. Raids are not tracked. A run keeps its
-- members, the bosses attempted and killed, wipes, every fight (Fight.lua) and every death.
local Run = {}
ns.Run = Run

local GRACE = 10 * 60      -- seconds outside the dungeon before the run ends
local KEEP = 500           -- runs kept

Run.current = nil
-- Outside dungeons a party still gets death recaps: a run kept in memory only, never saved.
Run.temp = nil

function Run:Active() return self.current or self.temp end

local function Me() return C.UnitFull("player") end

local function InDungeonParty()
    if not IsInGroup() or IsInRaid() then return false end
    local inside, kind = IsInInstance()
    return inside and kind == "party"
end

-- Member record for a unit.
local function Member(unit)
    local full = C.UnitFull(unit)
    if not full then return nil end
    local _, class = C.Call(UnitClass, unit)
    local _, race = C.Call(UnitRace, unit)
    local role = C.Str(C.Call(UnitGroupRolesAssigned, unit))
    return full, {
        class = C.Str(class), race = C.Str(race), level = C.Num(C.Call(UnitLevel, unit)),
        guild = C.Str((C.Call(GetGuildInfo, unit))), role = (role and role ~= "NONE") and role:lower() or nil,
    }
end

-- Adds anyone new in the group (people can join mid-run) and notes who left.
function Run:UpdateMembers(run)
    run = run or self.current
    if not run then return end
    local present = {}
    for _, unit in ipairs(C.GroupUnits()) do
        local full, m = Member(unit)
        if full then
            present[full] = true
            local old = run.members[full]
            if old then
                old.level, old.left = m.level or old.level, nil
                old.role = old.role or m.role
            else
                m.joined = time()
                run.members[full] = m
            end
        end
    end
    for full, m in pairs(run.members) do
        if not present[full] and not m.left then m.left = time() end
    end
end

-- Member names by short name, and the full name of a short one.
function Run:FullName(run, short)
    for full in pairs(run.members) do
        if C.Short(full) == short then return full end
    end
    if run.me and C.Short(run.me) == short then return run.me end
    -- Another shape of the name (an older run, a name the meter gave differently).
    for full in pairs(run.members) do
        if C.SameName(full, short) then return full end
    end
    if run.me and C.SameName(run.me, short) then return run.me end
end

function Run:Start()
    local name, _, _, diff, _, _, _, instanceID = GetInstanceInfo()
    local db = ns.db
    local run = {
        id = db.nextRun, instance = C.Str(name) or "Unknown dungeon", instanceID = C.Num(instanceID),
        difficulty = C.Str(diff), start = time(), me = Me(), members = {},
        bosses = {}, bossOrder = {}, wipes = 0, fights = {}, deaths = {},
    }
    db.nextRun = db.nextRun + 1
    table.insert(db.runs, run)
    while #db.runs > KEEP do table.remove(db.runs, 1) end
    self.current = run
    db.currentRun = run.id
    self:UpdateMembers(run)
    ns:Debug(("Run %d started: %s"):format(run.id, run.instance))
    ns:Changed()
end

function Run:Finish()
    local run = self.current
    if not run then return end
    self.current, ns.db.currentRun = nil, nil
    run.stop = run.outsideSince or time()
    run.outsideSince = nil
    -- A run where nothing happened isn't worth keeping.
    if #run.fights == 0 then
        for i = #ns.db.runs, 1, -1 do
            if ns.db.runs[i] == run then table.remove(ns.db.runs, i) end
        end
        return ns:Changed()
    end
    ns.History:AddRun(run)
    if ns.db.options.report and ns.Popup then ns.Popup:ShowReport(run) end
    ns:Changed()
end

function Run:Get(id)
    for _, r in ipairs(ns.db.runs) do if r.id == id then return r end end
end

-- Same instance and at least one of the same people: the run carries on.
local function Continues(run, name)
    if not run or run.instance ~= name then return false end
    if run.outsideSince and time() - run.outsideSince > GRACE then return false end
    for _, unit in ipairs(C.GroupUnits()) do
        local full = C.UnitFull(unit)
        if full and run.members[full] then return true end
    end
    return false
end

local TEMP_FIGHTS = 5

function Run:UpdateTemp()
    if self.current or not IsInGroup() or IsInRaid() then self.temp = nil return end
    local t = self.temp
    if not t then
        t = { temp = true, instance = C.Str(GetRealZoneText and GetRealZoneText()) or "Out in the world", start = time(),
            me = Me(), members = {}, bosses = {}, bossOrder = {}, wipes = 0, fights = {}, deaths = {}, roles = {} }
        self.temp = t
    end
    self:UpdateMembers(t)
    while #t.fights > TEMP_FIGHTS do table.remove(t.fights, 1) end
    while #t.deaths > TEMP_FIGHTS * 5 do table.remove(t.deaths, 1) end
end

local checkToken = 0
function Run:Check()
    local run = self.current
    if InDungeonParty() then
        local name = C.Str((GetInstanceInfo()))
        if run and Continues(run, name) then
            run.outsideSince = nil
            self:UpdateMembers(run)
        else
            if run then self:Finish() end
            self:Start()
        end
    elseif run then
        if not IsInGroup() then return self:Finish() end
        -- Outside the dungeon: give it a while (corpse runs, a quick trip to a vendor).
        if not run.outsideSince then
            run.outsideSince = time()
            checkToken = checkToken + 1
            local token = checkToken
            C_Timer.After(GRACE + 1, function()
                if token == checkToken and self.current == run and run.outsideSince then self:Finish() end
            end)
        end
        self:UpdateMembers(run)
    end
    self:UpdateTemp()
end

-- ---------------------------------------------------------------------------
-- Bosses
-- ---------------------------------------------------------------------------

local function Boss(run, name)
    local b = run.bosses[name]
    if not b then
        b = { attempts = 0, kills = 0, wipes = 0 }
        run.bosses[name] = b
        run.bossOrder[#run.bossOrder + 1] = name
    end
    return b
end

ns:On("ENCOUNTER_START", function(_, name)
    local run = Run.current
    name = C.Str(name)
    if not (run and name) then return end
    local b = Boss(run, name)
    b.attempts = b.attempts + 1
    b.first = b.first or time()
    if ns.Fight then ns.Fight:OnEncounter(name) end
end)

ns:On("ENCOUNTER_END", function(_, name, _, _, status)
    local run = Run.current
    name = C.Str(name)
    if not (run and name) then return end
    local b = Boss(run, name)
    if status == 1 or status == true then
        b.kills = b.kills + 1
        if ns.IsFinalBoss(run.instance, name, run.instanceID) then run.finished = true end
    else
        b.wipes = b.wipes + 1
        run.wipes = run.wipes + 1
        if ns.Fight then ns.Fight:MarkWipe() end
    end
    ns:Changed()
end)

-- ---------------------------------------------------------------------------

ns:OnLoad(function()
    -- A run in progress survives /reload and short disconnects.
    local id = ns.db.currentRun
    local run = id and Run:Get(id)
    if run and not run.stop then Run.current = run else ns.db.currentRun = nil end
end)

local pending
local function Soon()
    if pending then return end
    pending = true
    C_Timer.After(1, function() pending = false; Run:Check() end)
end
ns:On("PLAYER_ENTERING_WORLD", Soon)
ns:On("ZONE_CHANGED_NEW_AREA", Soon)
ns:On("GROUP_ROSTER_UPDATE", Soon)
