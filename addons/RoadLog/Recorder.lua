local _, ns = ...
local C = ns.Compat

-- Records where you walk while the toggle is on. Every tick it checks whether you can be on a road
-- at all (not dead, swimming, flying, on a flight path, indoors or in an instance); if not, the
-- current stretch ends. Standing still keeps the stretch open. Points go down every STEP yards,
-- and on straight stretches the middle of three nearly collinear points is dropped.
-- What you walk is logged as the current mode (ns.db.mode): a road, a blocker (you walked
-- along a wall, fence or cliff edge you can't cross), or a cave. Narrow passes (MarkPass) and zone
-- transitions (MarkTransition) are single spots.
-- Caves: the game doesn't tell addons your height (UnitPosition's height is always 0 on this
-- client), so a cave is logged as your path, every CAVE_STEP yards and kept whole (no straight
-- stretches thinned out: a straight passage can still go up or down), with the falls you took on
-- it (how long you were in the air, and where you landed) and whether the game had you indoors at
-- each point (inside the cave, not on the ground above it). Recording doesn't pause indoors or
-- while swimming then. tools/RoadLog/build_caves.py works out the height at every point from the
-- cave's floors in the game files and writes it to Data/Caves.lua (Caves.lua reads it).
local R = {}
ns.Recorder = R

local TICK = 0.25     -- seconds between position checks
local STEP = 4        -- yards between points
local JUMP = 60       -- yards moved in one tick that can't be walking (hearth, portal, loading screen)
local STRAIGHT = 0.75 -- a middle point this close (yards) to the line through its neighbours is dropped
local MIN_LENGTH = 10 -- shorter stretches aren't kept
local CAVE_STEP = 2   -- yards between points in a cave
local FALL = 0.5      -- seconds in the air that count as a fall (a jump on the spot is about 0.7)

R.state = "off"   -- "off", "recording", "still" or "paused"
R.reason = nil    -- why it's paused: "dead", "swimming", "flight path", "flying", "indoors", "instance"
R.current = nil   -- the open stretch: { continent, zone, at, pts, kind = "road" | "blocker" | "cave",
                  -- and for caves: name (the cave's), falls = { [point] = seconds in the air } }
R.dead = false

local ticker
local lastN, lastW, lastContinent -- your position at the last tick, recording or not
local airborne                    -- when you left the ground (GetTime), while you're falling

local function Round(v) return math.floor(v * 10 + 0.5) / 10 end

-- Length in yards of a flat { n1, w1, n2, w2, ... } list.
function R.Length(pts)
    local yd = 0
    for i = 3, #pts - 1, 2 do
        local dn, dw = pts[i] - pts[i - 2], pts[i + 1] - pts[i - 1]
        yd = yd + math.sqrt(dn * dn + dw * dw)
    end
    return yd
end

-- Distance from (pn, pw) to the line through (an, aw) and (bn, bw).
local function OffLine(an, aw, bn, bw, pn, pw)
    local dn, dw = bn - an, bw - aw
    local len = math.sqrt(dn * dn + dw * dw)
    if len < 0.01 then return math.sqrt((pn - an) ^ 2 + (pw - aw) ^ 2) end
    return math.abs(dn * (pw - aw) - dw * (pn - an)) / len
end

-- Why you can't be on a road right now, or nil when you can.
local function PauseReason()
    if R.dead or C.Flag(UnitIsDeadOrGhost, "player") then return "dead" end
    if C.Flag(UnitOnTaxi, "player") then return "flight path" end
    local cave = ns.db.mode == "cave"
    if not cave and C.Flag(IsSwimming) then return "swimming" end
    if C.Flag(IsFlying) then return "flying" end
    if not cave and C.Flag(IsIndoors) then return "indoors" end
    if C.Flag(IsInInstance) then return "instance" end
end

-- Close the open stretch, keeping it if it's long enough.
function R:Finish()
    local cur = self.current
    self.current = nil
    if not cur or #cur.pts < 4 or R.Length(cur.pts) < MIN_LENGTH then return end
    local roads = cur.kind == "blocker" and ns.db.blockers or cur.kind == "cave" and ns.db.caves or ns.db.roads
    roads[cur.continent] = roads[cur.continent] or {}
    local seg = { zone = cur.zone, at = cur.at, pts = cur.pts }
    if cur.kind == "cave" then seg.name, seg.falls, seg.inside = cur.name, cur.falls, table.concat(cur.inside) end
    table.insert(roads[cur.continent], seg)
    self.lastSaved = cur.continent
end

-- The last point of a stretch floats: while you keep going straight it moves up with you. cur.raw
-- holds every spot it sat on since the last fixed point; once one of them is more than STRAIGHT off
-- the line from that fixed point to where you are, the floating point is fixed and a new one starts.
local function AddPoint(cur, n, w, force)
    local pts = cur.pts
    local k = #pts
    if cur.kind == "cave" then
        -- every point kept: heights are worked out later, and a straight passage can still climb
        if k > 0 and not force then
            local dn, dw = n - pts[k - 1], w - pts[k]
            if dn * dn + dw * dw < CAVE_STEP * CAVE_STEP then return end
        end
        pts[k + 1], pts[k + 2] = Round(n), Round(w)
        cur.inside[#cur.inside + 1] = C.Flag(IsIndoors) and "1" or "0"
        return
    end
    if k == 0 then
        pts[1], pts[2] = Round(n), Round(w)
        cur.raw = {}
        return
    end
    local dn, dw = n - pts[k - 1], w - pts[k]
    if dn * dn + dw * dw < STEP * STEP then return end
    n, w = Round(n), Round(w)
    if k >= 4 then
        local an, aw = pts[k - 3], pts[k - 2]
        local straight = true
        for i = 1, #cur.raw - 1, 2 do
            if OffLine(an, aw, n, w, cur.raw[i], cur.raw[i + 1]) > STRAIGHT then
                straight = false
                break
            end
        end
        if straight then
            pts[k - 1], pts[k] = n, w
            cur.raw[#cur.raw + 1], cur.raw[#cur.raw + 2] = n, w
            return
        end
    end
    pts[k + 1], pts[k + 2] = n, w
    cur.raw = { n, w }
end

function R:Tick()
    if not ns.db.enabled then return end
    local reason = PauseReason()
    local continent, n, w, zone
    if not reason then
        continent, n, w, zone = ns.Nav:Player()
        if not continent then reason = "instance" end
    end
    if reason then
        self:Finish()
        lastN, lastW, lastContinent, airborne = nil, nil, nil, nil
        if self.state ~= "paused" or self.reason ~= reason then
            self.state, self.reason = "paused", reason
            ns:Changed()
        end
        return
    end

    -- A jump no one can walk: the old stretch ends where it was.
    if lastContinent and (continent ~= lastContinent or (n - lastN) ^ 2 + (w - lastW) ^ 2 > JUMP * JUMP) then
        self:Finish()
    end
    lastN, lastW, lastContinent = n, w, continent

    local speed = C.Num(GetUnitSpeed and C.Call(GetUnitSpeed, "player")) or 0
    local falling = C.Flag(IsFalling)
    local state = (speed > 0 or falling) and "recording" or "still"
    if state == "recording" then
        if not self.current then
            self.current = { continent = continent, zone = zone, at = time(), pts = {}, kind = ns.db.mode }
            if ns.db.mode == "cave" then
                self.current.falls, self.current.inside = {}, {}
                self.current.name = C.Readable(GetMinimapZoneText and C.Call(GetMinimapZoneText))
                    or C.Readable(GetSubZoneText and C.Call(GetSubZoneText)) or nil
                if self.current.name == "" then self.current.name = nil end
            end
        end
        AddPoint(self.current, n, w)
    end
    -- Falls (caves): time in the air, kept on the point where you landed.
    if falling then
        airborne = airborne or GetTime()
    elseif airborne then
        local air = GetTime() - airborne
        airborne = nil
        local cur = self.current
        if cur and cur.kind == "cave" and air >= FALL then
            AddPoint(cur, n, w, true)
            cur.falls[#cur.pts / 2] = math.floor(air * 100 + 0.5) / 100
        end
    end
    if state ~= self.state or self.reason then
        self.state, self.reason = state, nil
        ns:Changed()
    end
end

-- Start or stop the ticker to match the toggle.
function R:Update()
    if ns.db.enabled then
        if not ticker then ticker = C_Timer.NewTicker(TICK, function() R:Tick() end) end
        self:Tick()
    else
        if ticker then ticker:Cancel(); ticker = nil end
        self:Finish()
        self.state, self.reason = "off", nil
        lastN, lastW, lastContinent = nil, nil, nil
    end
end

-- The open stretch (only while it has points), for the map.
function R:Current()
    local cur = self.current
    if cur and #cur.pts >= 4 then return cur end
end

-- Log roads, blockers or caves from now on. A stretch you're walking ends, kept as what it was.
function R:SetMode(mode)
    if mode ~= "road" and mode ~= "blocker" and mode ~= "cave" then return end
    if self.current and self.current.kind ~= mode then self:Finish() end
    ns.db.mode = mode
    ns:Changed()
end

-- A narrow pass where you stand: a spot you can get through (a gap, a ramp, a gate).
function R:MarkPass()
    local continent, n, w, zone = ns.Nav:Player()
    if not continent then
        ns:Print("Can't tell where you are here.")
        return
    end
    ns.db.passes[continent] = ns.db.passes[continent] or {}
    table.insert(ns.db.passes[continent], { zone = zone, at = time(), n = Round(n), w = Round(w) })
    ns:Print(("Narrow pass marked in %s."):format(ns.Nav:ZoneName(zone)))
    ns:Changed()
end

-- A zone transition where you stand, labelled with the zone you're in and the nearest other zone:
-- "Durotar-The Barrens Transition".
function R:MarkTransition()
    local continent, n, w, map = ns.Nav:Player()
    if not continent then
        ns:Print("Can't tell where you are here.")
        return
    end
    local here = ns.Nav:Zone(map) or map
    local other = ns.Nav:NearestOtherZone(continent, n, w, here)
    local label = other and ("%s-%s Transition"):format(ns.Nav:ZoneName(here), ns.Nav:ZoneName(other))
        or ("%s Transition"):format(ns.Nav:ZoneName(here))
    ns.db.transitions[continent] = ns.db.transitions[continent] or {}
    table.insert(ns.db.transitions[continent], { zone = here, other = other, label = label, at = time(),
        n = Round(n), w = Round(w) })
    ns:Print(("Marked the |cffffffff%s|r."):format(label))
    if not other then ns:Print("No other zone within 500 yards, so it's labelled with this zone only.") end
    ns:Changed()
end

-- Delete the newest thing logged: the stretch you're walking if there is one, else the last
-- road, blocker, narrow pass or zone transition saved.
local KIND_NAME = { roads = "road", blockers = "blocker", caves = "cave", passes = "narrow pass", transitions = "zone transition" }
function R:Undo()
    if self:Current() then
        self.current = nil
        ns:Print("Dropped the stretch you were recording.")
        ns:Changed()
        return
    end
    local newest, list, index, kind
    for key in pairs(KIND_NAME) do
        for _, items in pairs(ns.db[key]) do
            local item = items[#items]
            if item and (not newest or (item.at or 0) > (newest.at or 0)) then
                newest, list, index, kind = item, items, #items, key
            end
        end
    end
    if not newest then
        ns:Print("Nothing to undo.")
        return
    end
    table.remove(list, index)
    local size = newest.pts and (" (" .. ns.Yards(R.Length(newest.pts)) .. ")") or ""
    ns:Print(("Deleted the last %s%s in %s."):format(KIND_NAME[kind], size, ns.Nav:ZoneName(newest.zone)))
    ns:Changed()
end

-- Delete one narrow pass or zone transition (from its spot on the map). kind: "passes" or
-- "transitions".
function R:RemoveMark(continent, pin, kind)
    local pins = ns.db[kind] and ns.db[kind][continent]
    if pins and tDeleteItem then
        tDeleteItem(pins, pin)
        ns:Print(kind == "transitions" and ((pin.label or "Zone transition") .. " removed.") or "Narrow pass removed.")
        ns:Changed()
    end
end

function R:Clear()
    self.current = nil
    wipe(ns.db.roads)
    wipe(ns.db.blockers)
    wipe(ns.db.caves)
    wipe(ns.db.passes)
    wipe(ns.db.transitions)
    ns:Print("Every road, blocker, cave, narrow pass and zone transition deleted.")
    ns:Changed()
end

-- How many blockers, narrow passes, zone transitions and caves are logged.
function R:Marks()
    local blockers, passes, transitions, caves = 0, 0, 0, 0
    for _, segs in pairs(ns.db.blockers) do blockers = blockers + #segs end
    for _, segs in pairs(ns.db.caves) do caves = caves + #segs end
    for _, pins in pairs(ns.db.passes) do passes = passes + #pins end
    for _, pins in pairs(ns.db.transitions) do transitions = transitions + #pins end
    return blockers, passes, transitions, caves
end

-- "2 blockers, 1 narrow pass, 3 zone transitions" (only the kinds there are), or nil.
function R:MarksText()
    local blockers, passes, transitions, caves = self:Marks()
    local parts = {}
    if caves > 0 then parts[#parts + 1] = ("%d cave stretch%s"):format(caves, caves == 1 and "" or "es") end
    if blockers > 0 then parts[#parts + 1] = ("%d blocker%s"):format(blockers, blockers == 1 and "" or "s") end
    if passes > 0 then parts[#parts + 1] = ("%d narrow pass%s"):format(passes, passes == 1 and "" or "es") end
    if transitions > 0 then parts[#parts + 1] = ("%d zone transition%s"):format(transitions, transitions == 1 and "" or "s") end
    return #parts > 0 and table.concat(parts, ", ") or nil
end

-- Totals over every continent: yards, stretches.
function R:Totals()
    local yd, count = 0, 0
    for _, segs in pairs(ns.db.roads) do
        for _, seg in ipairs(segs) do
            yd = yd + R.Length(seg.pts)
            count = count + 1
        end
    end
    local cur = self:Current()
    if cur and cur.kind == "road" then yd = yd + R.Length(cur.pts) end
    return yd, count
end

-- Status for the tooltip: text and color.
function R:Status()
    if not ns.db.enabled then return "Off", 0.6, 0.6, 0.6 end
    if self.state == "paused" then return "Paused (" .. (self.reason or "?") .. ")", 1, 0.5, 0.3 end
    local what = ns.db.mode == "blocker" and "blockers" or ns.db.mode == "cave" and "a cave" or "roads"
    if self.state == "still" then return "Logging " .. what .. ": standing still", 1, 0.82, 0.3 end
    return "Logging " .. what, 0.5, 0.9, 0.5
end

-- Dying ends the stretch at once; coming back lets the next tick pick up again.
ns:On("PLAYER_DEAD", function()
    R.dead = true
    if ns.db and ns.db.enabled then R:Tick() end
end)
local function Alive()
    R.dead = C.Flag(UnitIsDeadOrGhost, "player")
    if ns.db and ns.db.enabled then R:Tick() end
end
ns:On("PLAYER_ALIVE", Alive)
ns:On("PLAYER_UNGHOST", Alive)

ns:On("PLAYER_ENTERING_WORLD", function()
    -- A loading screen: whatever you walked before it is done.
    R:Finish()
    lastN, lastW, lastContinent, airborne = nil, nil, nil, nil
    R.dead = C.Flag(UnitIsDeadOrGhost, "player")
    R:Update()
end)

-- Logging out or /reload: keep the stretch you were on.
ns:On("PLAYER_LOGOUT", function() R:Finish() end)
