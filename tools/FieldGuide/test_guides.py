"""Plays characters through Field Guide's real code, with the game stubbed, and reports what happens.

    python tools/FieldGuide/test_guides.py [--race Tauren] [--levels 12] [--steps 400]        (yarn test:guides)

The addon's own files load unchanged (the order in its TOC). A simulated character does what the guide
says: walks to the step, picks the quest up, does it, hands it in, earns the XP and levels. Plans run
on their real time limit. What's reported for each race:

    reached      the level it got to, and the steps and yards it took
    stalls       the guide had nothing to do, or the same step wouldn't go away
    rule breaks  a step the game wouldn't allow: a quest above your level or before what it needs
    double-backs a return to a place it had left, with the walk that wasted when the stop before it
                 could have been done on the way (see Backtracks)
    errors       any Lua error at all

Exit code 1 when anything fails. --report writes tools/FieldGuide/test_report.txt.
"""
import argparse
import collections
import json
import math
import os
import site
import sys
import time

sys.path.append(site.getusersitepackages())

import lupa.lua51 as L  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import zone_walks as Z  # noqa: E402
import optimize_guides as O  # noqa: E402

ROOT = Z.ROOT
ADDON = os.path.join(ROOT, "addons", "FieldGuide")
SHARED = os.path.join(ROOT, "addons", "shared")
RACES = {"Human": (1, "Alliance"), "Orc": (2, "Horde"), "Dwarf": (3, "Alliance"), "NightElf": (4, "Alliance"),
         "Undead": (5, "Horde"), "Tauren": (6, "Horde"), "Gnome": (7, "Alliance"), "Troll": (8, "Horde")}
BACKTRACK_YARDS = 300   # a return to within this of somewhere counts as coming back
BACKTRACK_LEFT = 700    # after walking at least this far away

STUBS = r'''
-- The game, as far as the addon asks. Anything else on a frame is a do-nothing.
GAME = { parts = {}, time = 1000, level = 1, xp = 0, race = 1, faction = "Horde", name = "Test", map = 1412, x = 0.5, y = 0.5,
         log = {}, done = {}, ready = {}, timers = {}, errors = {} }
function GetTime() return GAME.time end
function debugprofilestop() return py_clock() end
function issecretvalue() return false end
function canaccessvalue() return true end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
strlower, strupper, strfind, strsub, format = string.lower, string.upper, string.find, string.sub, string.format
tinsert, tremove = table.insert, table.remove
function geterrorhandler() return function(e) GAME.errors[#GAME.errors + 1] = tostring(e) end end
function seterrorhandler() end
function hooksecurefunc() end
function IsLoggedIn() return true end
function InCombatLockdown() return false end
function UnitAffectingCombat() return false end
function UnitOnTaxi() return false end
function UnitIsDeadOrGhost() return false end
function UnitLevel() return GAME.level end
function UnitXP() return GAME.xp end
function UnitXPMax() return 1000 end
function UnitName() return GAME.name end
function UnitRace() return "Race", "Race", GAME.race end
function UnitClass() return "Warrior", "WARRIOR", 1 end
function UnitFactionGroup() return GAME.faction end
function UnitGUID() return "Player-1-1" end
function GetUnitSpeed() return 7, 7 end
function GetPlayerFacing() return 0 end
function IsPlayerMoving() return false end
function IsIndoors() return false end
function IsInInstance() return false, "none" end
function GetInstanceInfo() return "World", "none", 0, "", 5, 0, false, GAME.map end
function GetCVar() return "0" end
function GetItemCount() return 0 end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
function GetLocale() return "enUS" end
function GetBuildInfo() return "1.60.1", "70707", "", 16001 end
function PlaySound() end
function StaticPopup_Show(name) GAME.popup = name end
function StaticPopup_Visible() return false end
function StaticPopup_Hide() end
StaticPopupDialogs = {}
UISpecialFrames = {}
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function print() end

local FRAME = {}
FRAME.__index = function(t, k)
    local v = rawget(FRAME, k)
    if v ~= nil then return v end
    return function() end
end
function FRAME:SetScript(k, fn)
    if not rawget(self, "scripts") then rawset(self, "scripts", {}) end
    rawget(self, "scripts")[k] = fn
end
function FRAME:GetScript(k)
    local scripts = rawget(self, "scripts")
    return scripts and scripts[k]
end
function FRAME:RegisterEvent() end
function FRAME:IsShown() return false end
function FRAME:IsVisible() return false end
function FRAME:GetWidth() return 100 end
function FRAME:GetHeight() return 100 end
function FRAME:GetSize() return 100, 100 end
function FRAME:GetAlpha() return 1 end
function FRAME:GetEffectiveScale() return 1 end
function FRAME:GetFrameLevel() return 1 end
function FRAME:GetCenter() return 0, 0 end
function FRAME:GetStringWidth() return 10 end
function FRAME:GetStringHeight() return 10 end
function FRAME:GetUnboundedStringWidth() return 10 end
function FRAME:GetNumPoints() return 0 end
function FRAME:GetChildren() end
local function New() return setmetatable({}, FRAME) end
for _, name in ipairs({ "CreateTexture", "CreateFontString", "CreateLine", "CreateAnimationGroup", "CreateAnimation", "CreateMaskTexture" }) do
    FRAME[name] = function() return New() end
end
function CreateFrame() return New() end
function CreateFont() return New() end
UIParent, WorldMapFrame, Minimap, GameTooltip, QuestFrame, GossipFrame = New(), New(), New(), New(), New(), New()
function GameTooltip:IsOwned() return false end

C_Timer = {
    After = function(secs, fn) table.insert(GAME.timers, { at = GAME.time + secs, fn = fn }) end,
    NewTicker = function(secs, fn) table.insert(GAME.timers, { at = GAME.time + secs, fn = fn, every = secs }); return { Cancel = function() end } end,
}
function RunTimers()
    local due = {}
    for i = #GAME.timers, 1, -1 do
        local t = GAME.timers[i]
        if t.at <= GAME.time then
            table.remove(GAME.timers, i)
            due[#due + 1] = t
        end
    end
    for _, t in ipairs(due) do
        local ok, err = pcall(t.fn)
        if not ok then GAME.errors[#GAME.errors + 1] = tostring(err) end
        if t.every then t.at = GAME.time + t.every; table.insert(GAME.timers, t) end
    end
end

Enum = { UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 } }
function CreateVector2D(x, y) return { x = x, y = y, GetXY = function(s) return s.x, s.y end } end
C_Map = {
    GetBestMapForUnit = function() return GAME.map end,
    GetPlayerMapPosition = function() return CreateVector2D(GAME.x, GAME.y) end,
    GetMapInfo = function(id) return { mapID = id, name = "Map " .. tostring(id), parentMapID = 0, mapType = 3 } end,
    GetWorldPosFromMapPos = function(map, v)
        local c, n, w = py_world(map, v.x * 100, v.y * 100)
        if not c then return nil end
        return c, CreateVector2D(n, w)
    end,
    GetMapPosFromWorldPos = function() return nil end,
}
local function LogList()
    local ids = {}
    for id in pairs(GAME.log) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end
C_QuestLog = {
    GetNumQuestLogEntries = function() local n = #LogList(); return n, n end,
    GetInfo = function(i) local id = LogList()[i]; return id and { questID = id, title = "Quest", isHeader = false } or nil end,
    GetLogIndexForQuestID = function(id)
        for i, x in ipairs(LogList()) do if x == id then return i end end
    end,
    IsOnQuest = function(id) return GAME.log[id] == true end,
    IsComplete = function(id) return GAME.ready[id] == true end,
    GetQuestObjectives = function(id)
        local q = ns.Quests[id]
        if not (q and q.o) then return {} end
        local out = {}
        for i, a in ipairs(q.g or {}) do
            if a.n then
                out[#out + 1] = { finished = GAME.ready[id] == true or (GAME.parts[id] and GAME.parts[id][i]) == true,
                    text = a.n .. ": 0/1", numFulfilled = 0, numRequired = 1 }
            end
        end
        if #out == 0 then out[1] = { finished = GAME.ready[id] == true, text = "x" } end
        return out
    end,
    IsQuestFlaggedCompleted = function(id) return GAME.done[id] == true end,
    GetAllCompletedQuestIDs = function()
        local out = {}
        for id in pairs(GAME.done) do out[#out + 1] = id end
        return out
    end,
    GetTitleForQuestID = function(id) local q = ns.Quests[id]; return q and q.n or nil end,
    RequestLoadQuestByID = function() end,
}
function GetNumQuestLogEntries() local n = #LogList(); return n, n end
C_GossipInfo = { GetAvailableQuests = function() return {} end }
function GetNumAvailableQuests() return 0 end
function GetNumActiveQuests() return 0 end
'''

DRIVE = r'''
function Fire(event, ...)
    local fn = ns.EventFrame and ns.EventFrame:GetScript("OnEvent")
    if fn then
        local ok, err = pcall(fn, ns.EventFrame, event, ...)
        if not ok then GAME.errors[#GAME.errors + 1] = tostring(err) end
    end
end
-- The guide's part of a moment: timers, background plans, then its view of what to do.
function Tick(seconds)
    GAME.time = GAME.time + (seconds or 1)
    RunTimers()
    local ok, err = pcall(function() ns.Engine:Update() end)
    if not ok then GAME.errors[#GAME.errors + 1] = tostring(err) end
end
-- A background plan's frames, then one look: as long as a plan can take at 50 frames a second.
function Settle()
    for _ = 1, 300 do
        GAME.time = GAME.time + 0.02
        RunTimers()
    end
    Tick(0)
end
-- A task of several ("hunt these on the way there"): a player does them as they go, so the
-- objectives come first, nearest first, and the place last.
function WithItem()
    local E = ns.Engine
    local s = E.current and E.steps[E.current]
    if not (s and s.with) then return nil end
    local plain = s.plain or s
    local c, n, w = ns.WorldMap.Player()
    local best, bestYards
    for _, o in ipairs(s.with) do
        if o[1] == "O" and o ~= plain and not E:StepDone(o) then
            local p = o.part and ns.Quests[o[2]].g[o.part].p[1] or ns.Quests[o[2]].o[1]
            local oc, on, ow = ns.WorldMap.World(p[1], p[2] / 100, p[3] / 100)
            local yards = oc == c and ns.WorldMap.Distance(c, n, w, oc, on, ow) or 1e9
            if not best or yards < bestYards then best, bestYards = o, yards end
        end
    end
    if best then return best[2], best.part or false end
end
function CurrentPart()
    local E = ns.Engine
    local s = E.current and E.steps[E.current]
    local plain = s and (s.plain or s)
    return plain and plain.part
end
function GatherOrder(case)
    local a, b = { 1, 0, 0 }, { 1, 5000, 0 }
    local near = { 1, 200, 0 }
    local list, spots
    if case == 1 then
        list, spots = { { "O", 747 }, { "O", 780 }, { "O", 750 } }, { a, b, a }
    elseif case == 2 then
        list, spots = { { "T", 747 }, { "O", 780 }, { "T", 750 } }, { a, b, near }
    else
        list, spots = { { "A", 747 }, { "O", 780 }, { "T", 747 } }, { b, a, a }
        return table.concat(ns.Engine.Gather(list, spots, { 2, 1, 3 }), ",")
    end
    return table.concat(ns.Engine.Gather(list, spots, { 1, 2, 3 }), ",")
end
function Split(id) return ns.Engine.SplitParts({ { "O", id } }) end
function PartsFree(id)
    local steps = Split(id)
    return not ns.Engine.After(steps[1], steps[2])
end
function Step(kind, id)
    for _, s in ipairs(ns.Engine.steps) do
        if s[1] == kind and s[2] == id then return s end
    end
end
-- Puts you on the quest's "Do" step, as the route would.
function ForceStep(id)
    local E = ns.Engine
    for i, s in ipairs(E.steps) do
        if s[1] == "O" and s[2] == id then
            E.current = i
            E:CheckHunt()
            Tick(3)
            E.current = i
            E:CheckHunt()
            return true
        end
    end
    return false
end
function Moved(id)
    local E = ns.Engine
    E.current = nil
    for i, s in ipairs(E.steps) do
        if s[1] == "O" and s[2] == id then E.current = i end
    end
    GAME.time = GAME.time + 6
    E:CheckHunt()
    return E.hunting[id] ~= nil
end
function TaskMoves(id)
    local E = ns.Engine
    local stepOf = Step("A", 95805) or E.steps[1]
    local items = {}
    for _, s in ipairs(E.steps) do
        if s[1] == "O" and s[2] == id then items[#items + 1] = s end
    end
    E.steps[#E.steps + 1] = { stepOf[1], stepOf[2], plain = stepOf, with = items, going = true }
    E.current = #E.steps
    E:CheckHunt()
    GAME.time = GAME.time + 6
    E:CheckHunt()
    E.steps[#E.steps] = nil
    return E.hunting[id] ~= nil
end
function NearTexts()
    local out = {}
    for i, t in ipairs(ns.Engine:NearbyActions()) do out[i] = t.text end
    return table.concat(out, " | ")
end
function Tasks()
    local E = ns.Engine
    E.current = 1
    local out, list = {}, E:SecondaryTasks()
    for i, t in ipairs(list) do out[i] = t.title end
    return out
end
function PointsOf(step)
    local _, _, _, points = ns.Engine:Describe(step)
    return points or {}
end
function PartPlace(id, part) return ns.Quests[id].g[part].p[1] end
function DonePart(id, part)
    GAME.parts[id] = GAME.parts[id] or {}
    GAME.parts[id][part] = true
    for i, a in ipairs(ns.Quests[id].g) do
        if a.p and not GAME.parts[id][i] then return false end
    end
    return true
end
function Current()
    local E = ns.Engine
    local s = E.current and E.steps[E.current]
    if not s then return nil end
    local plain = s.plain or s
    return plain[1], plain[2]
end
function Place(kind, id)
    local q = ns.Quests[id]
    if not q then return nil end
    local p = (kind == "A" and q.a) or (kind == "T" and q.t) or (kind == "O" and q.o and q.o[1]) or (kind == "L" and q.d and q.d[1])
    return p
end
'''


class Character:
    def __init__(self, lua, world, race, faction, walk):
        self.lua, self.world, self.walk = lua, world, walk
        self.game = lua.globals().GAME
        self.game.race, self.game.faction = race, faction
        self.ns = lua.globals().ns
        self.yards, self.stops, self.report = 0.0, [], []
        self.breaks, self.steps_done = [], 0

    def go(self, p):
        here = (self.game.map, self.game.x, self.game.y)
        a, b = self.world(here[0], here[1] * 100, here[2] * 100), self.world(p[1], p[2], p[3])
        if a and b:
            yards = self.walk(a, b)
            self.yards += yards
            self.game.time = self.game.time + yards / 7
        self.game.map, self.game.x, self.game.y = p[1], p[2] / 100, p[3] / 100
        if b:
            self.stops.append((b, self.yards))

    def earn(self, q):
        level = self.game.level
        xp = self.ns.Engine.QuestEarns(self.ns.Engine, q) or 0
        self.game.xp = self.game.xp + xp
        need = XP_TO_LEVEL[level - 1] if level <= 60 else 0
        while level < 60 and self.game.xp >= need:
            self.game.xp = self.game.xp - need
            level += 1
            need = XP_TO_LEVEL[level - 1]
        changed = level != self.game.level
        self.game.level = level
        return changed


XP_TO_LEVEL = [400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400, 16000,
               17700, 19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400, 50800,
               54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700, 95800, 101000, 106300, 111800, 117500,
               123200, 129100, 135100, 141200, 147500, 153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300,
               209800, 217400]


def backtracks(stops, ready):
    """Each return to a place left a long way behind: (yards walked since, stop number, the stop it
    came back to, avoidable). Avoidable: the step here could already be done on that earlier visit, so
    the trip out and back wasn't needed for it. A hand-in after the fighting isn't that. ready[stop]:
    the first stop the step could be done after. Each return counts once."""
    found = []
    for i, (spot, at) in enumerate(stops):
        for j in range(i - 2, -1, -1):
            old, then = stops[j]
            if old[0] != spot[0] or math.hypot(old[1] - spot[1], old[2] - spot[2]) > BACKTRACK_YARDS:
                continue
            between = [s[0] for s in stops[j + 1:i] if s[0][0] == spot[0]]
            away = max((math.hypot(x[1] - spot[1], x[2] - spot[2]) for x in between), default=0)
            if away >= BACKTRACK_LEFT:
                found.append((round(at - then), i, j, ready.get(i, 0) <= j))
            break
    return found


def skip_rules(ns, g, game, fire, lua_table):
    """Skipping in Zone Clear, and taking a skipped quest back. Returns the failures."""
    bad = []

    def check(what, ok):
        print(("  ok   " if ok else "  FAIL ") + what)
        if not ok:
            bad.append(what)

    ns.char.preference = "clear"
    ns.Engine.Invalidate(ns.Engine)
    g.Settle()
    kind, qid = g.Current()
    ns.Engine.SkipCurrent(ns.Engine)
    g.Settle()
    check("Zone Clear: a skip keeps the quest", ns.char.deferred[qid] and not ns.char.ignored[qid])
    check("the next step is another quest", g.Current()[1] != qid)
    steps = ns.Engine.steps
    last = [i for i in range(1, len(steps) + 1) if steps[i][2] == qid]
    others = [i for i in range(1, len(steps) + 1) if steps[i][2] != qid and steps[i][1] in ("A", "O", "T") and not steps[i].later
              and not ns.Engine.StepDone(ns.Engine, steps[i])]
    check("it's after the rest of the zone", last and others and min(last) > max(others))
    fire("QUEST_ACCEPTED", qid)
    g.Settle()
    check("taking it ends the wait", not ns.char.deferred[qid])

    ns.char.preference = "leveling"
    level = game.level
    near = far = None
    for q, data in ns.Quests.items():
        if data.l and data.l == level + 1 and not near:
            near = q
        if data.l and data.l >= level + 10 and not far:
            far = q
    ns.char.ignored[near] = True
    ns.char.ignored[far] = True
    fire("QUEST_ACCEPTED", near)
    fire("QUEST_ACCEPTED", far)
    check("a skipped quest near your level comes back", not ns.char.ignored[near])
    check("one far above your level doesn't", ns.char.ignored[far])
    ns.char.ignored[near] = True
    fire("QUEST_ACCEPTED", 0, near)
    check("the client's two-value form of the event too", not ns.char.ignored[near])
    # On the way: two hunts in the same fields, so the walk to one crosses the other's.
    ns.char.preference = "leveling"
    ns.char.ignored[near] = None
    game.log[qid] = None
    game.log[747] = True
    game.log[780] = True
    game.map, game.x, game.y = 1412, 0.56, 0.90
    fire("QUEST_LOG_UPDATE")
    ns.Engine.Invalidate(ns.Engine)
    g.Settle()
    step = ns.Engine.steps[ns.Engine.current]
    side = 780 if step[2] == 747 else 747
    want = ns.Quests[side].n
    tasks = ns.Engine.SecondaryTasks(ns.Engine)
    names = [tasks[i].title for i in range(1, len(tasks) + 1)]
    print("     now:", step[1], step[2], "on the way:", names)
    check("a quest along the walk is listed", want in names)
    check("the step itself isn't listed", ns.Quests[step[2]].n not in names)
    check("at most six", len(names) <= 6)
    check("its line is the short objective", names and len(tasks[1].text) < 120)
    lines = [tasks[i].text for i in range(1, len(tasks) + 1)]
    check("no line says the whole quest again", not any(t == ns.Quests[side].ot for t in lines))
    game.ready[side] = True
    fire("QUEST_LOG_UPDATE")
    g.Settle()
    tasks = ns.Engine.SecondaryTasks(ns.Engine)
    names = [tasks[i].title for i in range(1, len(tasks) + 1)]
    check("finished, it drops off", want not in names)

    # What a quest asks, one action at a time.
    E = ns.Engine
    game.log[747] = True
    game.ready[747] = None
    fire("QUEST_LOG_UPDATE")
    left = E.ActionsLeft(E, 747)
    check("two objectives are two lines", len(left) == 2)
    game.parts[747] = lua_table({1: True})
    left = E.ActionsLeft(E, 747)
    check("a finished one drops off", len(left) == 1)
    game.parts[747] = None
    game.log[8992] = True
    left = E.ActionsLeft(E, 8992)
    check("an item to use stands out", "|cff" in left[1].text)
    game.log[8992] = None
    # A quest split into stops: one step each, in the order that walks best, and all needed.
    split = [q for q, d in ns.Quests.items() if d.sp and d.g][:40]
    check("some quests are split", len(split) > 0)
    steps = g.Split(split[0])
    check("a stop for each objective", len(steps) >= 2)
    check("their parts have no fixed order", g.PartsFree(split[0]))

    # What's at one place is done on one visit, and what's close by before a long walk away.
    check("one place, one visit", g.GatherOrder(1) == "1,3,2")
    check("close by comes before a long walk", g.GatherOrder(2) == "1,3,2")
    check("what a step needs still comes first", g.GatherOrder(3) == "2,1,3")

    # What's near you, whatever the arrow is pointing at.
    game.log[748] = True
    game.map, game.x, game.y = 1412, 0.47, 0.73
    fire("QUEST_LOG_UPDATE")
    E.Invalidate(E)
    g.Settle()
    near = g.NearTexts()
    print("     near:", near)
    check("the objectives near you are named", "Plainstrider Talon" in near or "Prairie Wolf Paw" in near)
    game.log[748] = None

    # A task of several: the same, for each hunt you're standing in, and the task goes on to its place.
    game.log[745] = True
    game.map, game.x, game.y = 1412, 0.474, 0.733
    fire("QUEST_LOG_UPDATE")
    E.Invalidate(E)
    g.Settle()
    check("a task's hunt moves on too", g.TaskMoves(745))
    E.hunting[745] = None
    game.log[745] = None

    # A hunting area: the arrow moves on a little after you walk in, and the hand-in waits.
    for q in (747, 780, 750, 752, 753):
        game.log[q] = None
        game.ready[q] = None
    game.log[780] = True
    game.map, game.x, game.y = 1412, 0.563, 0.717
    fire("QUEST_LOG_UPDATE")
    E.Invalidate(E)
    g.Settle()
    hunt = g.ForceStep(780)
    check("the hunt is the step", hunt)
    g.Settle()
    check("after a few seconds the arrow moves on", g.Moved(780))
    names = g.Tasks()
    check("what's left stays listed", ns.Quests[780].n in [names[i] for i in range(1, len(names) + 1)])
    check("its hand-in waits", E.Waits(E, g.Step("T", 780)))
    spots = E.FarmSpots(E)
    check("a farm route goes through several spots", len(spots) >= 3)
    farm = E.FarmFirst(E, None)
    step = E.steps[farm] if farm else None
    check("with nothing close by, the farm is next", step is not None and step.farm is True)
    verb = E.Describe(E, step)
    check("the farm walks all its spots", len(g.PointsOf(step)) == len(spots))
    game.ready[780] = True
    fire("QUEST_LOG_UPDATE")
    g.Settle()
    check("finished, the hunt is over", not ns.Engine.hunting[780])
    g.Settle()
    check("and its hand-in is back", not E.Waits(E, g.Step("T", 780)))
    return bad


def run_race(name, opts):
    race, faction = RACES[name]
    lua = L.LuaRuntime(encoding="utf8", unpack_returned_tuples=True)
    g = lua.globals()
    assign = Z.assignments()
    memo = {}

    def world(ui, x, y):
        key = (int(ui), round(x, 3), round(y, 3))
        if key not in memo:
            memo[key] = Z.C.world(assign, int(ui), x / 100, y / 100)
        return memo[key]

    def py_world(ui, x, y):
        w = world(ui, x, y)
        return (w[0], w[1], w[2]) if w else (None, None, None)

    g.py_world = py_world
    g.py_clock = lambda: time.perf_counter() * 1000
    lua.execute(STUBS)
    lua.execute('ns = { }')
    loader = lua.eval("""function(src, name)
        local f, e = loadstring(src, name)
        if not f then error(name .. ': ' .. tostring(e)) end
        f('FieldGuide', ns)
    end""")
    toc = open(os.path.join(ADDON, "FieldGuide.toc"), encoding="utf8").read()
    errors = []
    for line in toc.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        line = line.replace("\\", "/")
        path = os.path.join(SHARED, line[len("../shared/"):]) if line.startswith("../shared/") else os.path.join(ADDON, line)
        if not path.endswith(".lua") or not os.path.exists(path):
            continue
        try:
            loader(open(path, encoding="utf8").read(), os.path.basename(path))
        except Exception as e:  # noqa: BLE001
            errors.append("load %s: %s" % (line, str(e)[:160]))
    if errors:
        return {"race": name, "load": errors}
    lua.execute(DRIVE)
    game = g.GAME
    game.race, game.faction = race, faction
    ns = g.ns
    # Where the race starts: the first step of its starting section tells us.
    places = O.Places(ns, assign)
    me = Character(lua, world, race, faction, places.walk)
    fire = g.Fire
    fire("ADDON_LOADED", "FieldGuide")
    fire("PLAYER_LOGIN")
    fire("PLAYER_ENTERING_WORLD", True, False)
    fire("QUEST_LOG_UPDATE")
    first = STARTS.get(name)
    game.map, game.x, game.y = first[0], first[1] / 100, first[2] / 100
    g.Settle()
    if opts.skip_rules:
        return {"race": name, "skip_rules": skip_rules(ns, g, game, fire, lua.table_from)}
    stalls, seen, same, last = [], collections.Counter(), 0, None
    trail, walked, moves, idle = [], 0.0, 0, 0
    parts_done = 0
    popups = collections.Counter()
    ready, taken, worked, turned, level_at = {}, {}, {}, {}, {}
    if opts.debug:
        print(lua.execute("""
            local E = ns.Engine
            local d = {}
            d[#d+1] = "db " .. tostring(ns.db) .. " char " .. tostring(ns.char)
            d[#d+1] = "guide " .. tostring(E:Guide() and E:Guide().key) .. " guides " .. #ns.Guides
            d[#d+1] = "steps " .. tostring(E.steps and #E.steps) .. " current " .. tostring(E.current) .. " section " .. tostring(E.section and E.section.id)
            d[#d+1] = "faction " .. tostring(GAME.faction) .. " paused " .. tostring(ns.char and ns.char.paused)
            d[#d+1] = "errors " .. #GAME.errors .. ": " .. tostring(GAME.errors[1])
            return table.concat(d, " | ")
        """))
    t0 = time.time()
    current = g.Current
    place = g.Place
    for n in range(opts.steps):
        if game.level >= opts.levels:
            break
        result = current()
        kind, qid = result if result else (None, None)
        with_part = None
        if kind is not None:
            item = g.WithItem()
            if item and item[0]:
                kind, qid, with_part = "O", item[0], item[1]
        if kind is None or game.popup:
            # The guide's asking: a player says yes to moving on, and carries on.
            popup, game.popup = game.popup, None
            if popup == "FIELDGUIDE_MOVE":
                ns.Engine.AcceptMove(ns.Engine)
                moves += 1
                g.Settle()
                continue
            if popup == "FIELDGUIDE_STAY":
                ns.Engine.BackToRoute(ns.Engine)
                g.Settle()
                continue
            if popup:
                popups[popup] += 1  # (a dungeon offered: "Later", on with the route)
                g.Settle()
                continue
        if kind is None:
            idle += 1
            if idle < 3:
                g.Settle()
                continue
            stalls.append(("nothing to do", game.level, game.map))
            break
        idle = 0
        key = (kind, qid)
        same = same + 1 if key == last else 0
        last = key
        if same >= 3:
            stalls.append(("stuck on", key, game.level))
            ns.Engine.SkipCurrent(ns.Engine)
            g.Settle()
            continue
        quest = ns.Quests[qid] if kind in ("A", "O", "T", "L") else None
        if kind == "L":
            # A quest started from an item: found where it drops, and taken.
            p = place(kind, qid)
            if p:
                me.go(p)
            game.log[qid] = True
            if quest and not quest.o:
                game.ready[qid] = True
            fire("QUEST_ACCEPTED", qid)
            fire("QUEST_LOG_UPDATE")
        elif kind in ("A", "O", "T"):
            part = (with_part or None) if with_part is not None else (g.CurrentPart() if kind == "O" else None)
            p = g.PartPlace(qid, part) if part else place(kind, qid)
            if quest is None or p is None:
                stalls.append(("no place", key, game.level))
                ns.Engine.SkipCurrent(ns.Engine)
                g.Settle()
                continue
            if kind == "A":
                if (quest.r or 1) > game.level:
                    me.breaks.append(("below required level", qid, game.level, quest.r))
                pres = [quest.pre[i] for i in range(1, len(quest.pre) + 1)] if quest.pre else []
                missing = [x for x in pres if not game.done[x]]
                if pres and (len(missing) == len(pres) if quest.preAny else missing):
                    me.breaks.append(("before what it needs", qid, missing[:3]))
            me.go(p)
            me.steps_done += 1
            # When this step could first have been done (see backtracks).
            stop = len(me.stops) - 1
            if kind == "A":
                pres = [quest.pre[i] for i in range(1, len(quest.pre) + 1)] if quest.pre else []
                got = [turned.get(x, 0) for x in pres]
                first = (min(got) if quest.preAny else max(got)) if got else 0
                ready[stop] = max(first, level_at.get(max(quest.r or 1, (quest.l or 1) - 3), 0))
            elif kind == "O":
                ready[stop] = taken.get(qid, 0)
            else:
                ready[stop] = worked.get(qid, taken.get(qid, 0))
            trail.append("%3d L%-2d %s%-6d %-34s %5.1f,%5.1f  +%d yd" % (
                len(me.stops) - 1, game.level, kind, qid, str(quest.n)[:34], p[2], p[3], me.yards - walked))
            walked = me.yards
            if kind == "A":
                taken[qid] = stop
                game.log[qid] = True
                if not quest.o:
                    game.ready[qid] = True
                fire("QUEST_ACCEPTED", qid)
            elif kind == "O":
                parts_done += 1 if part else 0
                if not part or g.DonePart(qid, part):
                    game.ready[qid] = True
                worked[qid] = stop
                game.time = game.time + (quest.m or 1) * 60 / (len(quest.g) if part else 1)
            else:
                if not game.log[qid]:
                    me.breaks.append(("hand-in without the quest", qid))
                game.log[qid] = None
                game.ready[qid] = None
                game.done[qid] = True
                turned[qid] = stop
                up = me.earn(qid)
                level_at.setdefault(game.level, stop)
                fire("QUEST_TURNED_IN", qid)
                if up:
                    fire("PLAYER_LEVEL_UP", game.level)
            fire("QUEST_LOG_UPDATE")
        elif kind == "Z":
            game.map, game.x, game.y = qid, 0.5, 0.5
            fire("ZONE_CHANGED_NEW_AREA")
        elif kind == "G":
            game.level = max(game.level, qid)
            game.xp = 0
            fire("PLAYER_LEVEL_UP", game.level)
        else:
            stalls.append(("can't do", key, game.level))
            ns.Engine.SkipCurrent(ns.Engine)
        seen[kind] += 1
        g.Settle()
    errors = sorted({str(game.errors[i])[:150] for i in range(1, len(game.errors) + 1)})
    return {"race": name, "level": game.level, "steps": me.steps_done, "yards": round(me.yards),
            "stalls": stalls, "breaks": me.breaks, "back": backtracks(me.stops, ready), "errors": errors,
            "seconds": round(time.time() - t0), "stops": me.stops, "trail": trail}


STARTS = {"Tauren": (1412, 44.3, 77.0), "Orc": (1411, 43.0, 68.0), "Troll": (1411, 43.0, 68.0), "Undead": (1420, 30.0, 71.0),
          "Human": (1429, 48.0, 42.0), "Dwarf": (1426, 29.0, 72.0), "Gnome": (1426, 29.0, 72.0), "NightElf": (1438, 58.0, 44.0)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--race", default=None)
    ap.add_argument("--levels", type=int, default=60)
    ap.add_argument("--steps", type=int, default=3000)
    ap.add_argument("--debug", action="store_true")
    ap.add_argument("--skip-rules", action="store_true", help="only the rules for skipped quests (with --race)")
    ap.add_argument("--baseline", action="store_true", help="make this run the one later runs are held to")
    ap.add_argument("--trace", action="store_true", help="every step, and every double-back")
    a = ap.parse_args()
    names = [a.race] if a.race else list(RACES)
    failed = False
    results = {}
    for n in names:
        r = run_race(n, a)
        if "load" in r:
            print(n, "LOAD FAILED:", r["load"])
            failed = True
            continue
        if "skip_rules" in r:
            failed = failed or bool(r["skip_rules"])
            continue
        back = sorted(r["back"], reverse=True)
        avoid = [b for b in back if b[3]]
        print("%-9s level %2d  %4d steps  %7d yd  %3d avoidable double-backs of %d returns  %d stalls  %d rule breaks  %d errors  %ds" % (
            n, r["level"], r["steps"], r["yards"], len(avoid), len(back), len(r["stalls"]),
            len(r["breaks"]), len(r["errors"]), r["seconds"]), flush=True)
        results[n] = {"level": r["level"], "steps": r["steps"], "yards": r["yards"], "avoidable": len(avoid),
                      "returns": len(back), "stalls": len(r["stalls"]), "breaks": len(r["breaks"]), "errors": len(r["errors"])}
        if a.trace:
            for line in r["trail"]:
                print("   ", line)
            for yards, i, j, can in back[:12]:
                print("    back: stop %d returns to stop %d, %d yd later%s" % (i, j, yards, ", AVOIDABLE" if can else ""))
        for label, rows in (("stall", r["stalls"][:4]), ("break", r["breaks"][:4]), ("error", r["errors"][:4])):
            for row in rows:
                print("    %s: %s" % (label, str(row)[:150]))
        failed = failed or bool(r["errors"] or r["breaks"])
    # Against the last run: nothing may get worse without showing.
    if len(results) > 1:
        path = os.path.join(HERE, "test_baseline.json")
        old = json.load(open(path, encoding="utf-8")) if os.path.exists(path) else {}
        for n, now in results.items():
            for key in ("avoidable", "stalls", "breaks", "errors"):
                was = old.get(n, {}).get(key)
                if was is not None and now[key] > was:
                    print("WORSE: %s %s %d -> %d" % (n, key, was, now[key]))
                    failed = True
        if not old or a.baseline:
            with open(path, "w", encoding="utf-8", newline="\n") as f:
                json.dump(results, f, indent=1, sort_keys=True)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
