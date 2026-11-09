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
-- A count, not the clock: a plan's time budget runs out at the same point every run.
CLOCK = 0
function debugprofilestop() CLOCK = CLOCK + 0.004; return CLOCK end
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
function GetAddOnMetadata() return nil end
function PlaySound() end
-- Popups stack, as the game's do (one of each name): a dungeon offer can't hide a move offer.
function StaticPopup_Show(name)
    GAME.popups = GAME.popups or {}
    for _, p in ipairs(GAME.popups) do if p == name then return end end
    GAME.popups[#GAME.popups + 1] = name
    GAME.popup = GAME.popups[1]
end
function NextPopup()
    local q = GAME.popups or {}
    local p = table.remove(q, 1)
    GAME.popup = q[1]
    return p
end
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
WaypointSides = {}
function SideOf() return WaypointSides.FieldGuide end
function FollowAt(key)
    local E = ns.Engine
    local kind, id = key:match("^(%a)(%d+)$")
    id = tonumber(id)
    local q = ns.Quests[id]
    local p = q and ((kind == "A" and q.a) or (kind == "T" and q.t) or (kind == "O" and q.o and q.o[1]))
    local yards = "?"
    if p and E.YardsTo then yards = E.YardsTo(p) or "?" end
    local cur = E.current and E.steps[E.current]
    local plain = cur and (cur.plain or cur)
    return ("sect=%s log=%d current=%s%s yards=%s"):format(tostring(E.section and E.section.id), #ns.Progress:LogQuests(),
        tostring(plain and plain[1]), tostring(plain and plain[2]), tostring(yards))
end
function QuestStateAt(key)
    local kind, id = key:match("^(%a)(%d+)$")
    id = tonumber(id)
    local E, P, q = ns.Engine, ns.Progress, ns.Quests[id]
    if not q then return "no data" end
    local secs = {}
    for _, g in ipairs(E:Guide().sections) do
        for _, s in ipairs(g.steps) do
            if s[2] == id and s[1] == kind then secs[#secs + 1] = g.id; break end
        end
    end
    return ("log=%s ready=%s level=%d l=%s r=%s prereqs=%s open=%s section now %s; in %s"):format(tostring(P:InLog(id)), tostring(P:ReadyToTurnIn(id)),
        GAME.level, tostring(q.l), tostring(q.r), tostring(E:PrereqsDone(id)), tostring(E:QuestOpen(id)), tostring(E.section and E.section.id), table.concat(secs, ","))
end
function StepStates()
    local E, out = ns.Engine, {}
    for i, s in ipairs(E.steps) do
        if s[1] == "A" or s[1] == "O" or s[1] == "T" then
            local key = s[1] .. tostring(s[2])
            local flags = (E:StepDone(s) and "done " or "") .. (E:Waits(s) and "waits " or "") .. (E:MovedOn(s) and "moved " or "")
                .. (s.later and "later " or "") .. (s.early and "early " or "")
            out[#out + 1] = key .. "=" .. (i - (E.current or 1)) .. " " .. flags
        end
    end
    return table.concat(out, ";")
end
function DumpPlan(ids)
    local E, P, out = ns.Engine, ns.Progress, {}
    out[#out + 1] = ("section %s level %d held %s bump %s"):format(tostring(E.section and E.section.id), GAME.level, tostring(E.Held(E)), tostring(E.lastBump))
    for i = E.current or 1, math.min(#E.steps, (E.current or 1) + 11) do
        local s = E.steps[i]
        out[#out + 1] = ("  %d %s:%s part %s"):format(i, s[1], tostring(s[2]), tostring(s.part))
    end
    for id in tostring(ids):gmatch("%d+") do
        id = tonumber(id)
        local where = {}
        for i, s in ipairs(E.steps) do
            if s[2] == id then
                local k = s[1] .. ":" .. tostring(s.part)
                where[#where + 1] = ("#%d %s done=%s waits=%s later=%s moved=%s"):format(i, k, tostring(E:StepDone(s)), tostring(E:Waits(s)), tostring(s.later), tostring(E:MovedOn(s)))
            end
        end
        out[#out + 1] = ("  quest %d inlog=%s ready=%s: %s"):format(id, tostring(P:InLog(id)), tostring(P:ReadyToTurnIn(id)), table.concat(where, "; "))
    end
    return table.concat(out, string.char(10))
end
function EarlySteps()
    local E, out = ns.Engine, {}
    for i, st in ipairs(E.steps) do
        if st.early then out[#out + 1] = ("#%d A:%d l%s r%s %s"):format(i - (E.current or 1) + 1, st[2], tostring(ns.Quests[st[2]].l), tostring(ns.Quests[st[2]].r), tostring(ns.Quests[st[2]].n)) end
    end
    return table.concat(out, "; ")
end
function WhyLines()
    -- /fg why's lines: your state, the leveling plan's areas, and the sections' quest states.
    return ns.Engine:Why()
end
-- What the guide sees when it has nothing to give (with --trace): its section, and the steps left there.
function StallInfo()
    local E, out = ns.Engine, {}
    out[#out + 1] = ("section %s, %d steps, current %s, paused %s, instance %s, map %s, level %d, reach %s"):format(
        tostring(E.section and E.section.id), #E.steps, tostring(E.current), tostring(ns.char.paused),
        tostring(ns.char.instance), tostring(GAME.map), GAME.level, tostring(ns.char.lastPick))
    local shown = 0
    for i, st in ipairs(E.steps) do
        if not E:StepDone(st) and shown < 12 then
            shown = shown + 1
            local q = ns.Quests[st[2]]
            out[#out + 1] = ("  %d %s%s %s waits=%s r=%s l=%s"):format(i, tostring(st[1]), tostring(st[2]),
                q and q.n or "", tostring(E.Waits(E, st)), tostring(q and q.r), tostring(q and q.l))
        end
    end
    for _, line in ipairs(WhyLines()) do out[#out + 1] = "  zone " .. line end
    return table.concat(out, string.char(10))
end
WaypointSides2 = {}
WaypointSides3 = {}
function UseSides() Waypoint = { SetSide = function(_, owner, side, slot)
    if slot == 2 then WaypointSides2[owner] = side elseif slot == 3 then WaypointSides3[owner] = side else WaypointSides[owner] = side end
end } end
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
function DemoSteps()
    local UI = ns.UI
    UI:Demo(true)
    local n = UI.demoRoute and #UI.demoRoute or 0
    UI:Demo(false)
    return n
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
-- The objectives the current step is a task of several with: looked for on the walk there.
function TaskWith()
    local E, out = ns.Engine, {}
    local s = E.current and E.steps[E.current]
    local plain = s and (s.plain or s)
    for _, w in ipairs(s and s.with or {}) do
        if w[1] == "O" and w ~= plain and not w.part then out[#out + 1] = w[2] end
    end
    return out
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

    check("Accept Field Guide Quests: the guide doesn't want Blueleaf Tubers", not ns.Engine.WantsQuest(ns.Engine, 1221))
    picks = [s for s in (ns.Engine.steps[i] for i in range(1, len(ns.Engine.steps) + 1))
             if s[1] == "A" and not ns.Engine.Waits(ns.Engine, s)]
    check("and it does want the next pick-up on its list", not picks or ns.Engine.WantsQuest(ns.Engine, picks[0][2]))
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
    # (The rest of a quest with several objectives is listed: the line on the arrow isn't.)
    texts = [tasks[i].text for i in range(1, len(tasks) + 1)]
    left = ns.Engine.ActionsLeft(ns.Engine, step[2], step.part)
    check("the step itself isn't listed", not left[1] or left[1].text not in texts)
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

    # The setup demo: a character with no route still sees one, and the guide's own stays as it was.
    kept = E.current
    E.current = None
    check("no route: the demo finds one", g.DemoSteps() >= 3)
    E.current = 1
    check("with a route, the demo is your own", g.DemoSteps() == 0)
    E.current = kept

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
    if opts.no_early:
        ns.Engine.EARLY_LOG = 0
    if opts.no_group:
        ns.Engine.GROUP_YARDS = 0
    if opts.at:
        m, x, y = opts.at.split(",")
        game.level = opts.at_level
        ns.char.lastPick = opts.at_pick
        if opts.at_level >= 22:
            # A character who has played the Barrens up to here (as /fg why saved it): low quests done,
            # the rest of the zone open, these in the log.
            for i in range(1, 100000):
                q = ns.Quests[i]
                if q and q.l and q.l <= 16:
                    game.done[i] = True
            for i in (6361, 6362, 1492, 848, 853, 844, 903, 905, 881, 3261, 882):
                game.done[i] = True
            for i in (6541, 1069, 896, 899, 878, 4921):
                game.done[i] = None
                game.log[i] = True
            # Finished dungeon quests, handed in at Ratchet: on no route.
            for i in (959, 1491):
                game.done[i] = None
                game.log[i] = True
                game.ready[i] = True
        # Any state by hand: quests handed in (--done), in the log (--log).
        for i in (int(v) for v in (opts.done or "").split(",") if v):
            game.done[i] = True
        for i in (int(v) for v in (opts.log or "").split(",") if v):
            game.done[i] = None
            game.log[i] = True
        game.map, game.x, game.y = int(m), float(x) / 100, float(y) / 100
        fire("QUEST_LOG_UPDATE")
        g.Settle()
        E = ns.Engine
        keys, i = [], E.current or 1
        while i <= len(E.steps) and len(keys) < opts.at_steps:
            st = E.steps[i]
            keys.append("%s:%s" % (st[1], st[2]))
            i += 1
        print("  at %-14s %-14s %s" % (opts.at, E.section.id if E.section else None, " ".join(keys)), flush=True)
        print("      taken early:", g.EarlySteps(), flush=True)
        chosen = ns.Tasks.Chosen(ns.Tasks)
        print("      plan quests:", " ".join(str(v) for v in chosen.values()) if chosen else None, flush=True)
        for i in (int(v) for v in (opts.log or "").split(",") if v):
            print("      log %d: inLog %s done %s" % (i, ns.Progress.InLog(ns.Progress, i), ns.Progress.Done(ns.Progress, i)), flush=True)
            E_ = ns.Engine
            for j in range(1, len(E_.steps) + 1):
                st = E_.steps[j]
                if st[2] == i:
                    print("        step #%d %s:%s done %s waits %s" % (j, st[1], st[2], E_.StepDone(E_, st), E_.Waits(E_, st)), flush=True)
            sec = E_.section
            n = sum(1 for k in range(1, len(sec.steps) + 1) if sec.steps[k][2] == i) if sec else 0
            print("        in section steps: %d, current #%s of %d" % (n, E_.current, len(E_.steps)), flush=True)
        for line in g.WhyLines().values():
            print("     ", str(line)[:90], flush=True)
        return {"race": name, "trip": True}
    if opts.picker:
        return {"race": name, "trip": picker(ns, g, game, fire)}
    if opts.trip:
        return {"race": name, "trip": trip_replay(ns, g, game, fire)}
    if opts.unlock:
        return {"race": name, "trip": unlock_route(ns, g, game, fire)}
    if opts.wc:
        return {"race": name, "trip": wc_route(ns, g, game, fire)}
    if opts.sunrock:
        return {"race": name, "trip": sunrock(ns, g, game, fire, opts.sunrock)}
    if opts.handins:
        return {"race": name, "trip": handins_route(ns, g, game, fire)}
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
    # Carry: from picking a quest up to first working on it, the yards walked and steps done meanwhile.
    picked, carry, peak_log, level_minutes = {}, [], 0, {}
    # Handed in after it stopped paying (Tasks.lua's LastLevel), and each split quest's parts in the
    # order they were done (independent tasks: any order the route likes).
    expired, parts_seq = [], {}
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
    snaps, quest_states = {}, {}
    follows = {}
    current = g.Current
    place = g.Place
    for n in range(opts.steps):
        if game.level >= opts.levels:
            break
        result = current()
        if opts.trace:
            states = {}
            for row in g.StepStates().split(";"):
                if "=" in row:
                    k, v = row.split("=", 1)
                    states[k] = v
            snaps[len(me.stops)] = states
            for k in opts.watch:
                quest_states[(len(me.stops), k)] = g.QuestStateAt(k)
            for k in opts.follow:
                follows.setdefault(k, []).append((len(me.stops), states.get(k, "-"), g.FollowAt(k)))
        kind, qid = result if result else (None, None)
        if opts.dump and qid and "%s:%d" % (kind, qid) in opts.dump.split(",") and not getattr(opts, "dumped", None):
            opts.dumped = True
            print(g.DumpPlan(opts.dump_ids), flush=True)
        with_part = None
        if kind is not None:
            item = g.WithItem()
            if item and item[0]:
                kind, qid, with_part = "O", item[0], item[1]
        if kind is None or game.popup:
            # The guide's asking: a player says yes to moving on, and carries on.
            popup = g.NextPopup()
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
            if opts.trace:
                print("NOTHING TO DO:", flush=True)
                print(str(g.StallInfo()), flush=True)
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
            along = list(g.TaskWith().values()) if opts.together else []
            me.go(p)
            me.steps_done += 1
            # When this step could first have been done (see backtracks).
            stop = len(me.stops) - 1
            # As a player does: what the arrow lists for the walk gets done on the walk.
            for other in along:
                o = ns.Quests[other]
                if o and game.log[other] and not game.ready[other]:
                    game.ready[other] = True
                    worked[other] = stop
                    game.time = game.time + max(o.m or 1, 2) * 60
            if kind == "A":
                pres = [quest.pre[i] for i in range(1, len(quest.pre) + 1)] if quest.pre else []
                got = [turned.get(x, 0) for x in pres]
                first = (min(got) if quest.preAny else max(got)) if got else 0
                need = max(quest.r or 1, (quest.l or 1) - 3)
                ready[stop] = max(first, level_at.get(need, level_at.get(quest.r or 1, stop)))
            elif kind == "O":
                ready[stop] = taken.get(qid, 0)
            else:
                ready[stop] = worked.get(qid, taken.get(qid, 0))
            trail.append("%3d L%-2d %s%-6d %-34s %5.1f,%5.1f  +%d yd  t=%d" % (
                len(me.stops) - 1, game.level, kind, qid, str(quest.n)[:34], p[2], p[3], me.yards - walked, (game.time - 1000) / 60))
            walked = me.yards
            if kind == "A":
                taken[qid] = stop
                if quest.o:
                    picked[qid] = (me.yards, me.steps_done)
                game.log[qid] = True
                if not quest.o:
                    game.ready[qid] = True
                fire("QUEST_ACCEPTED", qid)
            elif kind == "O":
                if qid in picked:
                    y0, s0 = picked.pop(qid)
                    carry.append((me.yards - y0, me.steps_done - s0 - 1))
                parts_done += 1 if part else 0
                if part:
                    parts_seq.setdefault(qid, []).append(part)
                if not part or g.DonePart(qid, part):
                    game.ready[qid] = True
                worked[qid] = stop
                game.time = game.time + max(quest.m or 1, 2) * 60 / (len(quest.g) if part else 1)
                if opts.together and quest.o:
                    # As a player does: what's at this spot gets done with it, not one quest a visit.
                    here = quest.o[1]
                    for other in list(game.log.keys()):
                        o = ns.Quests[other]
                        at = o.o[1] if o and o.o else None
                        if at and game.log[other] and not game.ready[other] and at[1] == here[1] and at[2] == here[2] and at[3] == here[3]:
                            game.ready[other] = True
                            worked[other] = stop
            else:
                if not game.log[qid]:
                    me.breaks.append(("hand-in without the quest", qid))
                game.log[qid] = None
                game.ready[qid] = None
                game.done[qid] = True
                turned[qid] = stop
                if ns.Tasks and game.level > ns.Tasks.LastLevel(ns.Tasks, qid):
                    expired.append(qid)
                up = me.earn(qid)
                level_at.setdefault(game.level, stop)
                level_minutes.setdefault(game.level, (game.time - 1000) / 60)
                fire("QUEST_TURNED_IN", qid)
                if up:
                    fire("PLAYER_LEVEL_UP", game.level)
            peak_log = max(peak_log, sum(1 for k in list(game.log.keys()) if game.log[k]))
            fire("QUEST_LOG_UPDATE")
        elif kind == "Z":
            trail.append("    L%-2d Z %d from %d  t=%d" % (game.level, qid, game.map, (game.time - 1000) / 60))
            game.map, game.x, game.y = qid, 0.5, 0.5
            fire("ZONE_CHANGED_NEW_AREA")
        elif kind == "G":
            # Grinding takes time: the XP still missing, at the engine's grind pace (ROUTING_RULES.md rule 7).
            lib = ns.Engine.lib
            if getattr(opts, "grind_report", False):
                print(GRIND_REPORT(lua, game.level, qid, game.map, game.x, game.y), flush=True)
            if qid > game.level:
                grind = lib.XPToReach(qid, game.level, game.xp) / lib.GrindRate(game.level)
                me.grind_minutes = getattr(me, "grind_minutes", 0) + grind
                game.time = game.time + grind * 60
            game.level = max(game.level, qid)
            game.xp = 0
            level_minutes.setdefault(game.level, (game.time - 1000) / 60)
            fire("PLAYER_LEVEL_UP", game.level)
        else:
            stalls.append(("can't do", key, game.level))
            ns.Engine.SkipCurrent(ns.Engine)
        seen[kind] += 1
        g.Settle()
    errors = sorted({str(game.errors[i])[:150] for i in range(1, len(game.errors) + 1)})
    return {"race": name, "level": game.level, "minutes": (game.time - 1000) / 60, "grind": getattr(me, "grind_minutes", 0), "popups": dict(popups), "seen": dict(seen), "steps": me.steps_done, "yards": round(me.yards),
            "stalls": stalls, "breaks": me.breaks, "back": backtracks(me.stops, ready), "errors": errors,
            "seconds": round(time.time() - t0), "stops": me.stops, "carry": carry, "peak_log": peak_log,
            "expired": expired, "parts_seq": parts_seq,
            "level_minutes": level_minutes, "trail": trail, "snaps": snaps, "states": quest_states, "follows": follows}


GRIND_LUA = r'''
return function(level)
    local lib, P, T = ns.Engine.lib, ns.Progress, ns.Tasks
    local c = { done = 0, dungeon = 0, race = 0, server = 0, prereq = 0, above = 0, gray = 0, doable = 0, noarea = 0 }
    local xp = { gray = 0, doable = 0, above1 = 0 }
    local list, above = {}, {}
    local here = { ns.WorldMap.Player() }
    for id, q in pairs(ns.Quests) do
        if P:Done(id) or P:InLog(id) then c.done = c.done + 1
        elseif q.dq or q.pvp then c.dungeon = c.dungeon + 1
        elseif not P:RaceAllowed(q.rm) then c.race = c.race + 1
        elseif ns.Exists:Missing(id) then c.server = c.server + 1
        elseif not lib.PrereqsDone(q) then c.prereq = c.prereq + 1
        elseif lib.Practical(q) > level then
            c.above = c.above + 1
            if lib.Practical(q) <= level + 1 then xp.above1 = xp.above1 + lib.QuestXP(q, level + 1) end
        elseif T:LastLevel(id) < level then
            c.gray = c.gray + 1
            xp.gray = xp.gray + lib.QuestXP(q, level)
        else
            c.doable = c.doable + 1
            local x = lib.QuestEarns(q, level)
            xp.doable = xp.doable + x
            local w = q.a and lib.World(q.a)
            local yards = (w and here[1] and w[1] == here[1]) and math.floor(lib.Walked({ here[1], here[2], here[3] }, w) or -1) or -1
            list[#list + 1] = { id = id, n = q.n or "?", l = q.l or 0, xp = x, yards = yards, c = w and w[1] or -1 }
        end
    end
    table.sort(list, function(a, b) return a.xp > b.xp end)
    local out = {}
    for i = 1, math.min(8, #list) do
        local e = list[i]
        out[#out + 1] = ("      %6d xp  L%-2d %-34s %s"):format(e.xp, e.l, tostring(e.n):sub(1, 34),
            e.yards >= 0 and (e.yards .. " yd") or ("continent " .. e.c))
    end
    local need = lib.XP_TO_LEVEL[level] or 0
    return ("  GRIND at L%d (needs %d XP a level): doable %d quests worth %d XP (%.1f levels) | gray %d (%d XP) | above %d (next level opens %d XP) | prereq %d | dungeon %d | race %d | not on server %d | done %d\n%s"):format(
        level, need, c.doable, xp.doable, need > 0 and xp.doable / need or 0, c.gray, xp.gray, c.above, xp.above1,
        c.prereq, c.dungeon, c.race, c.server, c.done, table.concat(out, "\n"))
end
'''


def GRIND_REPORT(lua, level, target, m, x, y):
    fn = getattr(GRIND_REPORT, "fn", None)
    if fn is None:
        fn = GRIND_REPORT.fn = lua.execute(GRIND_LUA)
    return "  [map %d %.2f,%.2f -> L%d] " % (m, x, y, target) + str(fn(level))


STARTS = {"Tauren": (1412, 44.3, 77.0), "Orc": (1411, 43.0, 68.0), "Troll": (1411, 43.0, 68.0), "Undead": (1420, 30.0, 71.0),
          "Human": (1429, 48.0, 42.0), "Dwarf": (1426, 29.0, 72.0), "Gnome": (1426, 29.0, 72.0), "NightElf": (1438, 58.0, 44.0)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--race", default=None)
    ap.add_argument("--levels", type=int, default=60)
    ap.add_argument("--steps", type=int, default=3000)
    ap.add_argument("--debug", action="store_true")
    ap.add_argument("--skip-rules", action="store_true", help="only the rules for skipped quests (with --race)")
    ap.add_argument("--dump", default=None, help="print the plan when this step comes up")
    ap.add_argument("--dump-ids", default="")
    ap.add_argument("--together", action="store_true", help="objectives at one spot are done together, as a player does")
    ap.add_argument("--watch", default="", help="quest steps to record the state of, as A6523,T355")
    ap.add_argument("--follow", default="", help="print a step's place on the list at every stop (with --trace)")
    ap.add_argument("--no-early", action="store_true", help="no quests taken early")
    ap.add_argument("--no-group", action="store_true", help="brackets by level alone")
    ap.add_argument("--at-level", type=int, default=20)
    ap.add_argument("--at-pick", default="horde-1440-19")
    ap.add_argument("--done", default=None, help="with --at: quest IDs handed in, as 363,364")
    ap.add_argument("--log", default=None, help="with --at: quest IDs in the log")
    ap.add_argument("--at-steps", type=int, default=5, help="with --at: how many steps of the plan to print")
    ap.add_argument("--at", default=None, help="only: plan fresh at map,x,y at level 20, and print it")
    ap.add_argument("--picker", action="store_true", help="only the swap to the dungeon guide (with --race Tauren)")
    ap.add_argument("--handins", action="store_true", help="only a dungeon route's hand-ins after the run (--race Undead)")
    ap.add_argument("--unlock", action="store_true", help="only a dungeon route that needs a chain done first (--race Undead)")
    ap.add_argument("--sunrock", default=None, help="only: Arachnophobia ready near Sun Rock, others handed in there to do; x,y in Stonetalon (--race Tauren)")
    ap.add_argument("--wc", action="store_true", help="only Wailing Caverns' route with Altered Beings not done (--race Tauren)")
    ap.add_argument("--trip", action="store_true", help="only a walk into a new zone: the plan must hold (--race Tauren)")
    ap.add_argument("--baseline", action="store_true", help="make this run the one later runs are held to")
    ap.add_argument("--trace", action="store_true", help="every step, and every double-back")
    ap.add_argument("--grind-report", action="store_true", help="at each grind step: what quests there are, and why each isn't doable")
    a = ap.parse_args()
    a.watch = [x for x in a.watch.split(",") if x]
    a.follow = [x for x in a.follow.split(",") if x]
    names = [a.race] if a.race else list(RACES)
    failed = False
    results = {}
    for n in names:
        r = run_race(n, a)
        if "load" in r:
            print(n, "LOAD FAILED:", r["load"])
            failed = True
            continue
        if "trip" in r:
            failed = failed or not r["trip"]
            continue
        if "skip_rules" in r:
            failed = failed or bool(r["skip_rules"])
            continue
        back = sorted(r["back"], reverse=True)
        avoid = [b for b in back if b[3]]
        print("%-9s level %2d  %4d min (%d grinding)  %4d steps  %7d yd  %3d avoidable double-backs of %d returns  %d stalls  %d rule breaks  %d errors  %ds" % (
            n, r["level"], r["minutes"], r["grind"], r["steps"], r["yards"], len(avoid), len(back), len(r["stalls"]),
            len(r["breaks"]), len(r["errors"]), r["seconds"]), flush=True)
        results[n] = {"level": r["level"], "steps": r["steps"], "yards": r["yards"], "avoidable": len(avoid),
                      "returns": len(back), "stalls": len(r["stalls"]), "breaks": len(r["breaks"]), "errors": len(r["errors"])}
        carry = r["carry"]
        if carry:
            mins = r["level_minutes"]
            print("          carry: %d yd and %.1f steps from pick-up to first objective (mean of %d)  log peak %d  minutes to level %s" % (
                sum(c[0] for c in carry) / len(carry), sum(c[1] for c in carry) / len(carry), len(carry), r["peak_log"],
                " ".join("%d:%d" % (lv, mins[lv]) for lv in (10, 20, 30, 40) if lv in mins)), flush=True)
        seqs = [v for v in r.get("parts_seq", {}).values() if len(v) > 1]
        print("          expired: %d handed in after they stopped paying%s  parts: %d split quests, %d done out of the data's order" % (
            len(r.get("expired", [])), (" (" + ", ".join(str(x) for x in r["expired"][:8]) + ")") if r.get("expired") else "",
            len(seqs), sum(1 for v in seqs if v != sorted(v))), flush=True)
        if a.trace:
            for line in r["trail"]:
                print("   ", line)
            def held(b):
                line = next((l for l in r["trail"] if l.lstrip().startswith("%d L" % b[1])), "")
                key = line.split()[2] if line else ""
                return "waits" in r["snaps"].get(b[2] + 1, {}).get(key, "")
            print("    of those, %d were waiting on a level or a quest" % len([b for b in back if b[3] and held(b)]))
            for key, rows in sorted(r.get("follows", {}).items()):
                print("    FOLLOW %s" % key)
                for stop, state, info in rows:
                    print("      stop %d  %-14s %s" % (stop, state, info))
            for yards, i, j, can in back[:12] + [b for b in back[12:] if b[3]]:
                print("    back: stop %d returns to stop %d, %d yd later%s" % (i, j, yards, ", AVOIDABLE" if can else ""))
                if can:
                    line = next((l for l in r["trail"] if l.lstrip().startswith("%d L" % i)), "")
                    key = line.split()[2] if line else ""
                    print("      %s | was: %s" % (line.strip()[:60], next((l.strip()[:60] for l in r["trail"] if l.lstrip().startswith("%d L" % j)), "")))
                    print("      at the earlier visit, %s: %s" % (key, r["snaps"].get(j + 1, {}).get(key, "NOT ON THE LIST")))
                    print("      that quest then: %s" % r["states"].get((j + 1, key), "?"))
        if r.get("popups"):
            print("          popups: %s  steps by kind: %s" % (r["popups"], r.get("seen")), flush=True)
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


def picker(ns, g, game, fire):
    """The button left of the arrow, and the list it opens."""
    ok = []
    def check(name, good):
        ok.append(bool(good))
        print("  %s %s" % ("ok  " if good else "FAIL", name), flush=True)
    g.UseSides()
    side = g.SideOf
    game.map, game.x, game.y = 1412, 0.5, 0.5
    game.level = 1
    fire("QUEST_LOG_UPDATE")
    g.Settle()
    check("no dungeon due: no button", side() is None)
    game.level = 20
    fire("PLAYER_LEVEL_UP")
    ns.Changed(ns)
    g.Settle()
    now = side()
    check("a dungeon due: the button opens the list", now is not None and "Dungeon guide" == now.title)
    print("     ", now.text if now else None)
    list_ = ns.Instance.Current(ns.Instance)
    for i in range(1, len(list_) + 1):
        inst = list_[i].inst
        print("     ", inst.name, "->", ns.DungeonPicker.Picture(inst))
        check("%s has a picture" % inst.name, "Dungeons" in ns.DungeonPicker.Picture(inst))
    ns.DungeonPicker.Toggle(ns.DungeonPicker, g.UIParent)
    check("the list opens with no errors", len(game.errors) == 0)
    todo = g.WaypointSides2.FieldGuide
    check("a dungeon due: the to-do button is there", todo is not None)
    print("     ", todo.text if todo else None)
    ns.DungeonTodo.Toggle(ns.DungeonTodo, g.UIParent)
    check("the to-do list opens with no errors", len(game.errors) == 0)
    picked = list_[1].inst
    ns.Instance.Start(ns.Instance, picked)
    g.Settle()
    now = side()
    check("on a route: the button goes back", now is not None and "leveling" in now.title and ns.char.instance == picked.id)
    now.onClick()
    g.Settle()
    check("back on the leveling guide", ns.char.instance is None and side().title == "Dungeon guide")
    # The guide list (slot 3): its options, and following a zone from it.
    guides = g.WaypointSides3.FieldGuide
    check("the guide list button is there", guides is not None)
    got = {}
    ns.GuidePicker.Toggle(ns.GuidePicker, g.UIParent)
    ns.Tasks.Options(ns.Tasks, lambda opts: got.__setitem__("list", opts))
    for _ in range(40):
        if "list" in got:
            break
        g.Settle()
    opts = got.get("list")
    n = len(opts) if opts is not None else 0
    check("the guide list works out its options", n >= 1 and opts[1].kind == "best")
    check("the guide list opens with no errors", len(game.errors) == 0)
    zone = None
    for i in range(1, n + 1):
        o = opts[i]
        print("      %s %s: %.0f XP/h, %d quests" % (o.kind, o.name, (o.rate or 0) * 60, o.quests or 0))
        if o.kind == "zone" and zone is None:
            zone = o
    if zone is not None:
        ns.GuidePicker.Follow(ns.GuidePicker, zone)
        g.Settle()
        check("following %s pins it" % zone.name, ns.char.guideZone == zone.map and len(game.errors) == 0)
        ns.GuidePicker.Follow(ns.GuidePicker, opts[1])
        g.Settle()
        check("the best plan unpins it", ns.char.guideZone is None)
    # Dungeon paths (DungeonPaths.lua): the chains to dungeon quests, and an accepted one fitted in.
    DP = ns.DungeonPaths
    cands = DP.Candidates(DP)
    nc = len(cands)
    check("dungeon paths: the chains work out with no errors", len(game.errors) == 0)
    print("      %d dungeon quests with a chain to walk first" % nc)
    for i in range(1, min(nc, 6) + 1):
        c = cands[i]
        print("      %s (%s): %s" % (ns.Engine.QuestName(ns.Engine, c.quest), c.inst.name,
                                     " -> ".join(ns.Engine.QuestName(ns.Engine, c.chain[j]) for j in range(1, len(c.chain) + 1))))
    if nc > 0:
        c = cands[1]
        head = DP.NextOf(c.chain)
        head = head[0] if isinstance(head, tuple) else head
        make = (g.loadstring or g.load)("return function(h, c) return { head = h, list = { c } } end")()
        DP.Accept(DP, make(head, c))
        g.Settle()
        active = DP.Active(DP)
        check("an accepted path is followed", len(active) == 1 and active[1].quest == c.quest)
        bonus = DP.Bonus(DP)[0]
        check("its next quest counts extra", (bonus[head] or 0) > 0)
        chosen = ns.Tasks.Chosen(ns.Tasks)
        on = chosen is not None and any(chosen[j] == head for j in range(1, len(chosen) + 1))
        print("      next step %s on the plan: %s" % (ns.Engine.QuestName(ns.Engine, head), on))
        check("the plan works out with the path, no errors", len(game.errors) == 0)
        DP.Command(DP, "stop")
        g.Settle()
        check("paths dropped", len(DP.Active(DP)) == 0)
    # Every dungeon's route: built with no errors, and nothing offered only after the run (inst.after,
    # what an inside quest leads to) picked up before its run step.
    I = ns.Instance
    faction = g.UnitFactionGroup("player")
    bad, built = [], 0
    for i in range(1, len(I.list) + 1):
        inst = I.list[i]
        sec = I.Section(I, inst)
        built += 1
        post = set()
        if inst.after and inst.after[faction]:
            post.update(inst.after[faction][j] for j in range(1, len(inst.after[faction]) + 1))
        for fs in (inst.follow or {}).values():
            post.update(fs[j] for j in range(1, len(fs) + 1))
        seen_run = False
        for j in range(1, len(sec.steps) + 1):
            st = sec.steps[j]
            if st[1] == "I":
                seen_run = True
            elif st[1] == "A" and st[2] in post and not seen_run:
                bad.append("%s: %s" % (inst.name, ns.Engine.QuestName(ns.Engine, st[2])))
    check("every dungeon's route builds (%d) with no errors" % built, len(game.errors) == 0)
    check("no after-the-run quest is picked up before the run", not bad)
    for b in bad[:10]:
        print("      before the run:", b)
    ns.Engine.SetPaused(ns.Engine, True)
    g.Settle()
    check("paused: no button", side() is None)
    return all(ok)


def trip_replay(ns, g, game, fire):
    """Walks from the north of the Barrens into Ashenvale, printing the plan at each point."""
    E = ns.Engine
    def show(label):
        g.Settle()
        keys = []
        i = E.current or 1
        while i <= len(E.steps) and len(keys) < 7:
            st = E.steps[i]
            keys.append("%s:%s" % (st[1], st[2]))
            i += 1
        print("  %-22s zone %s  now %s  trip for %s  held %s  section %s" % (
            label, game.map, " ".join(keys), E.TripTarget(E), E.Held(E), E.section.id if E.section else None), flush=True)
    game.level = 20
    ns.char.lastPick, ns.char.onStep, ns.char.onTrip = "horde-1440-19", None, None
    game.map, game.x, game.y = 1456, 0.47, 0.10
    fire("QUEST_LOG_UPDATE")
    show("in the Barrens")
    game.map, game.x, game.y = 1456, 0.47, 0.03
    fire("QUEST_LOG_UPDATE")
    show("still the Barrens")
    game.map, game.x, game.y = 1440, 0.60, 0.72
    fire("ZONE_CHANGED_NEW_AREA")
    fire("QUEST_LOG_UPDATE")
    show("into Ashenvale")
    E.lastBump = None
    went = E.steps[E.current]
    E.Reorder(E)
    fire("QUEST_LOG_UPDATE")
    show("plan again, same spot")
    print("  bump:", E.lastBump)
    now = E.steps[E.current]
    same = went[1] == now[1] and went[2] == now[2]
    print("  ok   planning again changes nothing" if same else "  FAIL planning again changes the route")
    return same


def handins_route(ns, g, game, fire):
    """Ruins of Lordaeron run, everything finished, standing by Theodore Griffs in Undercity: the
    hand-in beside you (The New Plague) comes first, not the one in the Royal Quarter."""
    E = ns.Engine
    game.level = 22
    for i in range(1, 100000):
        q = ns.Quests[i]
        if q and q.l and q.l <= 18:
            game.done[i] = True
    for i in (356, 99156, 447, 450, 451):
        game.done[i] = True
    inst = ns.Instance.Get(ns.Instance, 16611)
    for i in (97289, 97291, 97292, 92401, 92421, 92422, 95216):
        game.done[i] = None
        game.log[i] = True
        game.ready[i] = True
    game.map, game.x, game.y = 1458, 0.462, 0.715
    fire("QUEST_LOG_UPDATE")
    g.Settle()
    ns.Instance.Start(ns.Instance, inst)
    # (the run's done, every wing of it)
    g.loadstring("local I, inst = ...; ns.char.ran[inst.id .. ':'] = true; for _, w in ipairs(I:RouteWings(inst)) do ns.char.ran[inst.id .. ':' .. w] = true end")(ns.Instance, inst)
    g.Settle()
    fire("QUEST_LOG_UPDATE")
    g.Settle()
    keys = []
    for i in range(1, len(E.steps) + 1):
        st = E.steps[i]
        keys.append("%s%s:%s" % ("*" if i == E.current else "", st[1], st[2]))
    print("  current", E.current, "steps", " ".join(keys), flush=True)
    now = E.steps[E.current] if E.current else None
    good = now is not None and now[1] == "T" and now[2] == 95216
    print("  ok   the hand-in beside you first" if good else "  FAIL not the hand-in beside you", flush=True)
    return good


def lua_list(g, kind, q):
    return g.UnlockStep(kind, q)


def unlock_route(ns, g, game, fire):
    """Ruins of Lordaeron at level 19 with A Recipe For Death part 1 in the log: The New Plague needs
    the whole chain (447, 450, 451) first, so the route starts with part 1's objectives."""
    E = ns.Engine
    g.loadstring("function UnlockStep(k, q) return { k, q } end")()
    game.level = 19
    for i in range(1, 100000):
        q = ns.Quests[i]
        if q and q.l and q.l <= 10:
            game.done[i] = True
    game.log[447] = True
    game.map, game.x, game.y = 1421, 0.43, 0.41
    fire("QUEST_LOG_UPDATE")
    g.Settle()
    inst = ns.Instance.Get(ns.Instance, 16611)
    ns.Instance.Start(ns.Instance, inst)
    g.Settle()
    fire("QUEST_LOG_UPDATE")
    g.Settle()
    keys = []
    for i in range(1, len(E.steps) + 1):
        st = E.steps[i]
        keys.append("%s%s:%s%s" % ("*" if i == E.current else "", st[1], st[2], "u" if st.unlock else ""))
    print("  current", E.current, "steps", " ".join(keys), flush=True)
    for q in (447, 450, 451, 95216):
        print("    %d: open %s, why %s, done %s" % (q, E.QuestOpen(E, q), E.WhyClosed(E, q), E.StepDone(E, lua_list(g, "A", q))), flush=True)
    raw = ns.Instance.Section(ns.Instance, inst)
    print("    section:", " ".join("%s:%s" % (raw.steps[i][1], raw.steps[i][2]) for i in range(1, len(raw.steps) + 1)), flush=True)
    # (A pick-up from a giver beside you may come first: it costs no walk.)
    now, i = None, E.current or 1
    while i <= len(E.steps):
        if E.steps[i][1] != "A" and not E.StepDone(E, E.steps[i]):
            now = E.steps[i]
            break
        i += 1
    good = now is not None and now[2] == 447 and now[1] == "O"
    print("  ok   part 1 first" if good else "  FAIL part 1 isn't first", flush=True)
    return good


def sunrock(ns, g, game, fire, where):
    """Level 22 in Stonetalon near Sun Rock Retreat: Arachnophobia (6284) ready to hand in at Maggran,
    Elemental War (6393) and Boulderslide Ravine (6421) in the log and not done, both handed in at Sun
    Rock too. Handing Arachnophobia in first is a trip the route makes anyway: it shouldn't come first
    unless it's where you are."""
    E = ns.Engine
    parts = where.split(",")
    x, y = float(parts[0]) / 100, float(parts[1]) / 100
    game.level = 22
    for i in range(1, 100000):
        q = ns.Quests[i]
        if q and q.l and q.l <= 16:
            game.done[i] = True
    for q in (6284, 6393, 6421):
        game.done[q] = None
        game.log[q] = True
    game.ready[6284] = True
    # (",taken": the quests to pick up at Sun Rock are in the log already: a visit would be for the hand-in alone.)
    if len(parts) > 2:
        for q in (6282, 86576, 6301, 1087, 6461, 6523, 6542):
            game.done[q] = None
            game.log[q] = True
    ns.char.lastPick = "horde-1442-17"
    game.map, game.x, game.y = 1442, x, y
    fire("QUEST_LOG_UPDATE")
    g.Settle()
    for _ in range(3):
        fire("QUEST_LOG_UPDATE")
        g.Settle()
    keys = []
    for i in range(1, min(len(E.steps), 14) + 1):
        st = E.steps[i]
        keys.append("%s%s:%s" % ("*" if i == E.current else "", st[1], st[2]))
    print("  at %s: %s" % (where, " ".join(keys)), flush=True)
    cur = E.current and E.steps[E.current]
    print("  first:", cur and ("%s:%s" % (cur[1], cur[2])), flush=True)
    return True


def wc_route(ns, g, game, fire):
    """Wailing Caverns at level 18 with Altered Beings (880) not done: Hamuul Runetotem (1489) needs it,
    so the route has to do 880 before it offers 1489, and must never offer 1489 first."""
    E = ns.Engine
    g.loadstring("function UnlockStep(k, q) return { k, q } end")()
    game.level = 18
    for i in range(1, 100000):
        q = ns.Quests[i]
        if q and q.l and q.l <= 10:
            game.done[i] = True
    game.map, game.x, game.y = 1413, 0.52, 0.31
    fire("QUEST_LOG_UPDATE")
    g.Settle()
    inst = ns.Instance.Get(ns.Instance, 718)
    ns.Instance.Start(ns.Instance, inst)
    g.Settle()
    fire("QUEST_LOG_UPDATE")
    g.Settle()
    keys = []
    for i in range(1, len(E.steps) + 1):
        st = E.steps[i]
        keys.append("%s%s:%s%s%s" % ("*" if i == E.current else "", st[1], st[2], "u" if st.unlock else "",
                                     "w" if E.Waits(E, st) else ""))
    print("  current", E.current, "steps", " ".join(keys), flush=True)
    for q in (880, 1489, 1490):
        print("    %d: open %s, why %s, done %s" % (q, E.QuestOpen(E, q), E.WhyClosed(E, q), E.StepDone(E, lua_list(g, "A", q))), flush=True)
    raw = ns.Instance.Section(ns.Instance, inst)
    print("    section:", " ".join("%s:%s%s" % (raw.steps[i][1], raw.steps[i][2], "u" if raw.steps[i].unlock else "") for i in range(1, len(raw.steps) + 1)), flush=True)
    cur = E.current and E.steps[E.current]
    bad = cur is not None and cur[1] == "A" and cur[2] in (1489, 1490)
    good = cur is not None and not bad
    print("  ok   the chain comes first" if good else "  FAIL offers %s:%s before its prerequisite" % (cur[1], cur[2]) if cur else "  FAIL no step", flush=True)
    return good


if __name__ == "__main__":
    main()
