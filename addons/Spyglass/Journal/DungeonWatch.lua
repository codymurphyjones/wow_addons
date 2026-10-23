local ADDON, ns = ...

-- The dungeon watch: what really happens in dungeons, kept so the pull maps can be checked and
-- improved (tools/Spyglass/ingest_contrib.py extracts it; fetch_pulls.py folds it in).
--
-- Inside a dungeon or raid it notes:
--   * each pull: the hostile NPCs that are in combat in the first few seconds of a fight (from the
--     nameplates and your group's targets), the floor you're on (its uiMapID), and where you stand
--     when the game says (it often doesn't inside instances);
--   * the NPCs a floor has (nameplates as they come into view).
-- Facts, as Contribute.lua's (kind first):
--   P:<instance>:<uiMap>:<x>:<y>:<npc>[x<count>].<npc>...   a pull (x, y: 0-100, or "-" unknown)
--   W:<instance>:<uiMap>:<npc>                               an NPC seen on a floor
-- They're pooled in your own saved variables (SpyGlassDB.observed: fact -> times seen), always,
-- so your runs can be extracted later; and, with "Share discoveries" on, sent to the collector
-- like every other discovery. Nothing about you is kept: no names, no times, no group.
--
-- In combat the game may hide some values (secret values): a unit whose ID or combat state is
-- hidden is left out, and counted (/sgj watch shows how many), so we learn what this client allows.
local W = {}
ns.DungeonWatch = W

local WINDOW = { 0.3, 1.2, 2.5 }   -- seconds into a fight the units are looked at (a pull's mobs arrive)
local MAX_NPCS = 12                 -- different NPCs kept in one pull
local MAX_FACTS = 4000              -- facts kept in the pool (the least seen go first)

local session = { pulls = 0, empty = 0, hidden = 0, seen = 0 }
local seenThisSession = {}

local function Secret(v) return ns.IsSecret and ns.IsSecret(v) or (issecretvalue and issecretvalue(v)) or false end

local function On()
    return ns.J and ns.J.db and ns.J.db.watch ~= false
end

-- The instance (map ID) you're in, when it's a dungeon or raid; else nil.
local function Instance()
    local _, kind, _, _, _, _, _, instanceID = GetInstanceInfo()
    if (kind == "party" or kind == "raid") and type(instanceID) == "number" and not Secret(instanceID) then return instanceID end
end

-- Your floor (uiMapID) and where you stand on it (0-100), each nil when the game won't say.
local function Where()
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if Secret(map) or type(map) ~= "number" then return nil end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if ok and pos and pos.GetXY then
        local x, y = pos:GetXY()
        if not Secret(x) and not Secret(y) and type(x) == "number" and (x > 0 or y > 0) then
            return map, x * 100, y * 100
        end
    end
    return map
end

local function NpcOf(unit)
    local guid = UnitGUID(unit)
    if guid == nil then return nil end
    if Secret(guid) then return nil, true end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id), false, guid end
end

-- A hostile unit in combat: its NPC ID and GUID; hidden = the game kept something secret.
local function Fighting(unit)
    if not UnitExists(unit) or UnitIsPlayer(unit) then return nil end
    local enemy = UnitCanAttack("player", unit)
    if Secret(enemy) then return nil, true end
    if not enemy then return nil end
    local combat = UnitAffectingCombat(unit)
    if Secret(combat) then return nil, true end
    if not combat then return nil end
    local npc, hidden, guid = NpcOf(unit)
    return npc, hidden, guid
end

local function Units()
    local list = { "target", "focus", "mouseover" }
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
            local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
            if unit then list[#list + 1] = unit end
        end
    end
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    local prefix = IsInRaid and IsInRaid() and "raid" or "party"
    for i = 1, n do list[#list + 1] = prefix .. i .. "target" end
    return list
end

-- The pool: fact -> times seen (and the least seen dropped when it's full).
local function Pool()
    ns.db.observed = type(ns.db.observed) == "table" and ns.db.observed or {}
    local o = ns.db.observed
    o.facts = type(o.facts) == "table" and o.facts or {}
    return o
end

local function Keep(fact)
    local o = Pool()
    o.facts[fact] = (o.facts[fact] or 0) + 1
    o.count = (o.count or 0) + (o.facts[fact] == 1 and 1 or 0)
    if (o.count or 0) > MAX_FACTS then
        local list = {}
        for f, n in pairs(o.facts) do list[#list + 1] = { f, n } end
        table.sort(list, function(a, b) return a[2] > b[2] end)
        for i = MAX_FACTS + 1, #list do o.facts[list[i][1]] = nil end
        o.count = MAX_FACTS
    end
    -- And to the collector, with "Share discoveries" on (Contribute.lua checks that).
    if ns.Contribute and ns.Contribute.Note then ns.Contribute.Note(fact) end
end

local function Num(v) return v and ("%.1f"):format(v) or "-" end

-- ---------------------------------------------------------------------------------------------
-- Pulls
-- ---------------------------------------------------------------------------------------------

local pull -- the fight under way: { instance, map, x, y, guids = { guid -> npc } }

local function Look()
    if not pull then return end
    for _, unit in ipairs(Units()) do
        local npc, hidden, guid = Fighting(unit)
        if hidden then
            session.hidden = session.hidden + 1
        elseif npc and guid and not pull.guids[guid] then
            pull.guids[guid] = npc
        end
    end
end

local function Finish()
    local p = pull
    pull = nil
    if not p then return end
    local counts, order = {}, {}
    for _, npc in pairs(p.guids) do
        if not counts[npc] then order[#order + 1] = npc end
        counts[npc] = (counts[npc] or 0) + 1
    end
    if #order == 0 then
        session.empty = session.empty + 1
        return
    end
    table.sort(order)
    local parts = {}
    for i = 1, math.min(#order, MAX_NPCS) do
        local npc = order[i]
        parts[i] = counts[npc] > 1 and (npc .. "x" .. counts[npc]) or tostring(npc)
    end
    Keep(("P:%d:%d:%s:%s:%s"):format(p.instance, p.map or 0, Num(p.x), Num(p.y), table.concat(parts, ".")))
    session.pulls = session.pulls + 1
end

local function StartPull()
    if not On() then return end
    local instance = Instance()
    if not instance then return end
    local map, x, y = Where()
    pull = { instance = instance, map = map, x = x, y = y, guids = {} }
    for i, t in ipairs(WINDOW) do
        C_Timer.After(t, function()
            Look()
            if i == #WINDOW then Finish() end
        end)
    end
end

-- ---------------------------------------------------------------------------------------------
-- NPCs seen on a floor
-- ---------------------------------------------------------------------------------------------

local function OnPlate(unit)
    if not On() or InCombatLockdown() then return end
    local instance = Instance()
    if not instance or not UnitCanAttack("player", unit) then return end
    local npc = NpcOf(unit)
    if not npc then return end
    local map = Where()
    local fact = ("W:%d:%d:%d"):format(instance, map or 0, npc)
    if seenThisSession[fact] then return end
    seenThisSession[fact] = true
    session.seen = session.seen + 1
    Keep(fact)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
pcall(frame.RegisterEvent, frame, "NAME_PLATE_UNIT_ADDED")
frame:SetScript("OnEvent", function(_, event, unit)
    local ok, err = pcall(function()
        if event == "PLAYER_REGEN_DISABLED" then
            StartPull()
        elseif event == "NAME_PLATE_UNIT_ADDED" and unit then
            OnPlate(unit)
        end
    end)
    if not ok and ns.db and ns.db.debugContrib then ns:Print("dungeon watch: " .. tostring(err)) end
end)

-- /sgj watch [on | off]
function W:Command(arg)
    arg = strlower(strtrim(arg or ""))
    if arg == "on" or arg == "off" then
        ns.J.db.watch = arg == "on"
        ns:Print(ns.J.db.watch and "Dungeon watch on: pulls and NPCs in dungeons are noted." or "Dungeon watch off.")
        return
    end
    local o = Pool()
    ns:Print(("Dungeon watch is %s. This session: %d pulls noted, %d fights with no mob it could read, %d unit reads the game kept secret, %d NPCs seen. In the pool: %d facts (tools/Spyglass/ingest_contrib.py extracts them)."):format(
        On() and "on" or "off", session.pulls, session.empty, session.hidden, session.seen, o.count or 0))
end
