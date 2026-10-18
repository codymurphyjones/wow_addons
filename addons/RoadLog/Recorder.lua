local _, ns = ...
local C = ns.Compat

-- Records where you walk while the toggle is on. Every tick it checks whether you can be on a road
-- at all (not dead, swimming, flying, on a flight path, indoors or in an instance); if not, the
-- current stretch ends. Standing still keeps the stretch open. Points go down every STEP yards,
-- and on straight stretches the middle of three nearly collinear points is dropped.
local R = {}
ns.Recorder = R

local TICK = 0.25     -- seconds between position checks
local STEP = 4        -- yards between points
local JUMP = 60       -- yards moved in one tick that can't be walking (hearth, portal, loading screen)
local STRAIGHT = 0.75 -- a middle point this close (yards) to the line through its neighbours is dropped
local MIN_LENGTH = 10 -- shorter stretches aren't kept

R.state = "off"   -- "off", "recording", "still" or "paused"
R.reason = nil    -- why it's paused: "dead", "swimming", "flight path", "flying", "indoors", "instance"
R.current = nil   -- the open stretch: { continent, zone, at, pts }
R.dead = false

local ticker
local lastN, lastW, lastContinent -- your position at the last tick, recording or not

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
    if C.Flag(IsSwimming) then return "swimming" end
    if C.Flag(IsFlying) then return "flying" end
    if C.Flag(IsIndoors) then return "indoors" end
    if C.Flag(IsInInstance) then return "instance" end
end

-- Close the open stretch, keeping it if it's long enough.
function R:Finish()
    local cur = self.current
    self.current = nil
    if not cur or #cur.pts < 4 or R.Length(cur.pts) < MIN_LENGTH then return end
    local roads = ns.db.roads
    roads[cur.continent] = roads[cur.continent] or {}
    table.insert(roads[cur.continent], { zone = cur.zone, at = cur.at, pts = cur.pts })
    self.lastSaved = cur.continent
end

-- The last point of a stretch floats: while you keep going straight it moves up with you. cur.raw
-- holds every spot it sat on since the last fixed point; once one of them is more than STRAIGHT off
-- the line from that fixed point to where you are, the floating point is fixed and a new one starts.
local function AddPoint(cur, n, w)
    local pts = cur.pts
    local k = #pts
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
        lastN, lastW, lastContinent = nil, nil, nil
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
    local state = speed > 0 and "recording" or "still"
    if state == "recording" then
        if not self.current then
            self.current = { continent = continent, zone = zone, at = time(), pts = {} }
        end
        AddPoint(self.current, n, w)
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

-- Delete the newest stretch: the open one if there is one, else the last one saved.
function R:Undo()
    if self:Current() then
        self.current = nil
        ns:Print("Dropped the stretch you were recording.")
        ns:Changed()
        return
    end
    local newest, newestC, newestI
    for continent, segs in pairs(ns.db.roads) do
        local seg = segs[#segs]
        if seg and (not newest or (seg.at or 0) > (newest.at or 0)) then
            newest, newestC, newestI = seg, continent, #segs
        end
    end
    if not newest then
        ns:Print("Nothing to undo.")
        return
    end
    table.remove(ns.db.roads[newestC], newestI)
    ns:Print(("Deleted the last stretch (%s in %s)."):format(ns.Yards(R.Length(newest.pts)), ns.Nav:ZoneName(newest.zone)))
    ns:Changed()
end

function R:Clear()
    self.current = nil
    wipe(ns.db.roads)
    ns:Print("Every road deleted.")
    ns:Changed()
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
    if cur then yd = yd + R.Length(cur.pts) end
    return yd, count
end

-- Status for the tooltip: text and color.
function R:Status()
    if not ns.db.enabled then return "Off", 0.6, 0.6, 0.6 end
    if self.state == "paused" then return "Paused (" .. (self.reason or "?") .. ")", 1, 0.5, 0.3 end
    if self.state == "still" then return "On: standing still", 1, 0.82, 0.3 end
    return "Recording", 0.5, 0.9, 0.5
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
    lastN, lastW, lastContinent = nil, nil, nil
    R.dead = C.Flag(UnitIsDeadOrGhost, "player")
    R:Update()
end)

-- Logging out or /reload: keep the stretch you were on.
ns:On("PLAYER_LOGOUT", function() R:Finish() end)
