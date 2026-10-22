local _, Z = ...

-- Ride timing. You stand at a dock (A), the boat or zeppelin carries you off (you move without
-- moving yourself): the ride from A is on and its timer runs. It ends at B, where the ride lands
-- (where you got off last time, else the dock in the destination town), once you stand still or
-- walk on solid ground there, or walk past any other dock's sign. How long it took from boarding
-- is learned for A's dock (ZeppelinSignsDB.rides) and is the countdown next time. A ride never
-- timed counts down from 180 seconds, corrected as you go by how fast you're closing on B when B
-- is known. The countdown shows as a bar under the signs: A on the left, B on the right.
-- Other addons read the ride through ZeppelinSignsAPI (Waypoint's arrow and map icons).
local R = {}
Z.Rides = R

local TICK = 0.5
local DEFAULT = 180        -- seconds: a ride never timed
local MIN_RIDE = 20        -- shorter than this wasn't a ride
local MAX_RIDE = 15 * 60   -- longer than this wasn't one either
local CARRIED_SPEED = 4    -- yards a second you move without moving yourself: carried
local BOARD_CHECKS = 3     -- carried this many checks in a row: on board
local LEAVE_SECS = 120     -- after walking off a dock, boarding still counts for its ride this long...
local LEAVE_RANGE = 200    -- ...and this close (yards)
local ARRIVE = 150         -- yards from where a ride lands that count as there
local STILL_SECS = 2       -- standing still or walking on solid ground this long there: arrived
local ARRIVING = 15        -- seconds left: B shows the ride is ending

local dock      -- { spot, left }: the dock you stand at, or walked off at `left`
local last      -- { c, wx, wy, t }: where you were at the last check
local carriedN = 0
local ride      -- the ride you're on (Begin)
local bar       -- the on-screen timer (Bar)

local function DB() return ZeppelinSignsDB end

local function Dist(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end

-- true only when the game says so and lets us read it.
local function Flag(fn, ...)
    if not fn then return false end
    local ok, v = pcall(fn, ...)
    if not ok or (issecretvalue and issecretvalue(v)) then return false end
    return v and true or false
end

local function OwnSpeed()
    local ok, v = pcall(GetUnitSpeed, "player")
    if not ok or (issecretvalue and issecretvalue(v)) then return 0 end
    return tonumber(v) or 0
end

local CLOCK = { round = "round", hours = false }
local function Clock(secs) return Z.Format.Clock(secs, CLOCK) end

-- The dock sign you stand at (within its radius), or nil.
local function DockAt(c, wx, wy)
    local best, bestD
    for _, spot in ipairs(Z.spots) do
        if spot.continent == c then
            local d = Dist(wx, wy, spot.wx, spot.wy)
            if d <= (Z.RADIUS[spot.sign.kind] or 30) and (not bestD or d < bestD) then best, bestD = spot, d end
        end
    end
    return best
end

-- "zep:orgrimmar:undercity" -> "zep", "orgrimmar", "undercity" (custom signs have no towns).
local function Parts(key)
    local kind, from, to = strsplit(":", key or "")
    if kind == "custom" then return nil end
    return kind, from, to
end

-- The dock in a sign's destination town (the one sailing back, when there is one), or nil.
local function DestDock(sign)
    local kind, from, to = Parts(sign.key)
    if not kind then return nil end
    local back, any
    for _, spot in ipairs(Z.spots) do
        local k, f, t = Parts(spot.sign.key)
        if k == kind and f == to then
            any = any or spot
            if t == from then back = spot end
        end
    end
    return back or any
end

-- Where a sign's ride lands, B: { c, wx, wy, mapID, x, y, spot }. Where you got off last time
-- first, else the dock in the destination town; spot is that dock either way, when there is one.
local function Landing(sign)
    local s = DestDock(sign)
    local rec = DB().rides[sign.key]
    if rec and rec.m then
        local c, wx, wy = Z.WorldPos(rec.m, rec.x, rec.y)
        if c then return { c = c, wx = wx, wy = wy, mapID = rec.m, x = rec.x, y = rec.y, spot = s } end
    end
    if s then return { c = s.continent, wx = s.wx, wy = s.wy, mapID = s.mapID, x = s.x, y = s.y, spot = s } end
end

-- For other addons (Waypoint): events "BOARD" (a ride starts), "ARRIVE" (it lands) and "CANCEL" (it
-- turned out not to be one). Version 2: before it they were lower case.
local API, Fire = Z.NewAPI("ZeppelinSignsAPI", 2)

-- ---------------------------------------------------------------------------------------------
-- A ride
-- ---------------------------------------------------------------------------------------------

local function Begin(spot, boarded)
    local s = spot.sign
    local rec = DB().rides[s.key]
    local now = GetTime()
    ride = {
        sign = s, from = spot, boarded = boarded,
        fromName = s.place or (GetRealZoneText and GetRealZoneText()) or "Here",
        expect = rec and rec.secs or DEFAULT, timed = rec and rec.secs ~= nil,
        to = Landing(s), at = now,
    }
    ride.shown = ride.expect - (now - boarded)
    DB().active = { key = s.key, boarded = time() - math.floor(now - boarded) }
    R:Refresh()
    Fire("BOARD")
end

-- A ride you finished: its time (an average that follows the last few trips) and where it landed.
local function Learn(key, secs)
    if secs < MIN_RIDE or secs > MAX_RIDE then return end
    local rec = DB().rides[key] or {}
    local weight = math.min(rec.n or 0, 4)
    rec.secs = math.floor(((rec.secs or 0) * weight + secs) / (weight + 1) + 0.5)
    rec.n = (rec.n or 0) + 1
    local _, _, _, m, x, y = Z.PlayerWorldPos()
    if m then rec.m, rec.x, rec.y = m, x, y end
    DB().rides[key] = rec
end

local function End(arrived, at)
    if not ride then return end
    if arrived then Learn(ride.sign.key, (at or GetTime()) - ride.boarded) end
    ride = nil
    DB().active = nil
    carriedN = 0
    R:Refresh()
    Fire(arrived and "ARRIVE" or "CANCEL")
end

-- One check while riding: arrived, given up, or a better guess at the time left.
local function OnRide(now, c, wx, wy, speed, moved, dt, carried)
    local r = ride
    local elapsed = now - r.boarded
    if elapsed > MAX_RIDE or Flag(IsSwimming) then return End(false) end
    -- How fast you're carried, smoothed.
    if carried then
        local v = moved / dt
        r.speed = r.speed and (r.speed * 0.8 + v * 0.2) or v
    end
    -- Standing still, or walking where your steps are all of your movement: not on a moving deck.
    local grounded = moved and ((speed == 0 and moved < 0.3) or (speed > 0 and math.abs(moved / dt - speed) < 1.5))
    if grounded then r.stillSince = r.stillSince or now else r.stillSince = nil end
    local still = r.stillSince and now - r.stillSince >= STILL_SECS

    local to = r.to
    local near = to and to.c == c and Dist(wx, wy, to.wx, to.wy) <= ARRIVE
    local fromA = r.from.continent == c and Dist(wx, wy, r.from.wx, r.from.wy) or math.huge
    if elapsed >= MIN_RIDE then
        -- Never left: you stepped off again, or what moved you wasn't the ride.
        if still and fromA < 40 then return End(false) end
        -- Past another town's dock (not a neighbouring pier back in A's town, like Auberdine's three).
        local at = DockAt(c, wx, wy)
        local elsewhere = at and at.sign ~= r.sign and ((at.sign.place and at.sign.place ~= r.sign.place) or fromA > 300)
        if elsewhere then return End(true, r.stillSince or now) end
        if still and (near or (not to and fromA > 300)) then return End(true, r.stillSince) end
    end

    -- Time left: the timed length, or (never timed) 180 seconds corrected by how fast you near B.
    local target = r.expect - elapsed
    if not r.timed and to and to.c == c and r.speed and r.speed > 2 then
        target = Dist(wx, wy, to.wx, to.wy) / r.speed
    end
    -- The count runs down by itself and drifts toward the guess, catching up or slowing down.
    local step = now - r.at
    r.shown = r.shown - step
    r.shown = r.shown + (target - r.shown) * math.min(1, step * 0.25)
    r.at = now
end

local function Tick()
    if not DB() then return end
    local now = GetTime()
    if Flag(UnitOnTaxi, "player") or Flag(UnitIsDeadOrGhost, "player") then
        dock, last, carriedN = nil, nil, 0
        return End(false)
    end
    local c, wx, wy = Z.PlayerWorldPos()
    if not c then return end -- a loading screen (the zeppelin crossing to another continent): keep going
    local speed = OwnSpeed()
    local moved = last and last.c == c and Dist(wx, wy, last.wx, last.wy) or nil
    local dt = last and math.max(0.1, now - last.t) or TICK
    last = { c = c, wx = wx, wy = wy, t = now }
    local carried = moved ~= nil and speed == 0 and moved / dt > CARRIED_SPEED
    carriedN = carried and carriedN + 1 or 0

    if ride then return OnRide(now, c, wx, wy, speed, moved, dt, carried) end

    -- At a dock, or recently walked off one.
    local spot = DockAt(c, wx, wy)
    if spot then
        dock = { spot = spot }
    elseif dock then
        dock.left = dock.left or now
        local s = dock.spot
        if now - dock.left > LEAVE_SECS or s.continent ~= c or Dist(wx, wy, s.wx, s.wy) > LEAVE_RANGE then dock = nil end
    end
    -- Carried off from a dock: on its ride since the first of those checks.
    if dock and carriedN >= BOARD_CHECKS then
        local s = dock.spot
        dock = nil
        Begin(s, now - (BOARD_CHECKS - 1) * TICK)
    end
end

-- ---------------------------------------------------------------------------------------------
-- The on-screen timer: "Zeppelin to Undercity", a bar from A to B and the time left
-- ---------------------------------------------------------------------------------------------

local test -- /zep test ride: { until, total }

local function State()
    if ride then
        local left = math.max(0, ride.shown - (GetTime() - ride.at))
        return Z.KIND_LABEL[ride.sign.kind] .. " to " .. ride.sign.dest, ride.fromName, ride.sign.dest,
            GetTime() - ride.boarded, left
    end
    if test then
        local left = test.ends - GetTime()
        if left > 0 then return "Zeppelin to Undercity", "Orgrimmar", "Undercity", test.total - left, left end
        test = nil
    end
end

local function Face(size)
    local face = WallyHUD and WallyHUD.SuiteFace and WallyHUD.SuiteFace("semibold")
    return face or STANDARD_TEXT_FONT, size, "OUTLINE"
end

local GOLD, GREEN = { 1, 0.82, 0.3 }, { 0.35, 0.95, 0.55 }

-- The timer (shared\Bar.lua): its title 22px above the bar, A left and B right under it, the time
-- left between them.
local function Bar()
    if bar then return bar end
    local f = Z.NewProgressBar(UIParent, 320, 8, { track = { 0, 0, 0, 0.55 }, fillAlpha = 0.9, minFill = 1,
        title = true, titleOffset = 22, below = true })
    f:SetPoint("TOP", UIParent, "TOP", 0, -172)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(false)
    -- A and B stop short of the clock between them (long dock names are cut off, not run into it).
    for _, fs in ipairs({ f.from, f.to }) do fs:SetWidth(125); fs:SetWordWrap(false) end
    f.from:SetJustifyH("LEFT"); f.to:SetJustifyH("RIGHT")
    f:SetScript("OnUpdate", function(self)
        local title, from, to, elapsed, left = State()
        if not title then return R:Refresh() end
        -- A: the timer is running from here. B: where it ends, gold once it's nearly there.
        self:SetTitle(title)
        self:SetLabels("|cff59f28c>|r " .. from, left > 0 and Clock(left) or "Arriving", to)
        local arriving = left <= ARRIVING
        if arriving then self.to:SetTextColor(1, 0.82, 0.3) else self.to:SetTextColor(1, 1, 1) end
        self:SetValue(elapsed / math.max(1, elapsed + left), arriving and GOLD or GREEN)
    end)
    f:Hide()
    bar = f
    return f
end

-- Shows or hides the timer, after a ride starts or ends or the setting changes.
function R:Refresh()
    local shown = DB() and DB().timer and State() ~= nil
    if not shown then
        if bar then bar:Hide() end
        return
    end
    local f = Bar()
    f.title:SetFont(Face(16))
    for _, fs in ipairs({ f.from, f.to, f.mid }) do fs:SetFont(Face(12)) end
    f.title:SetTextColor(1, 1, 1); f.from:SetTextColor(0.8, 0.85, 0.9); f.mid:SetTextColor(1, 1, 1)
    f:Show()
end

function R:Test()
    test = { ends = GetTime() + 20, total = 120 }
    self:Refresh()
end

-- /zep rides: every ride you've timed.
function R:List()
    local byKey = {}
    for _, s in ipairs(Z.SIGNS) do byKey[s.key] = s end
    for _, s in ipairs(DB().custom) do byKey[s.key] = s end
    local n = 0
    for key, rec in pairs(DB().rides) do
        local s = byKey[key]
        if s and rec.secs then
            n = n + 1
            print(("  %s%s: %s (%d ride%s)"):format(s.place and (s.place .. " > ") or "", Z.Label(s), Clock(rec.secs), rec.n or 1, rec.n == 1 and "" or "s"))
        end
    end
    if n == 0 then Z:Print("No rides timed yet. Take one: the timer starts as you're carried off the dock.") end
end

function R:Init()
    -- A ride you were on when the UI reloaded.
    local a = DB().active
    if a and a.key and a.boarded and time() - a.boarded < MAX_RIDE then
        for _, spot in ipairs(Z.spots) do
            if spot.sign.key == a.key then
                Begin(spot, GetTime() - (time() - a.boarded))
                break
            end
        end
    end
    DB().active = ride and DB().active or nil
    C_Timer.NewTicker(TICK, Tick)
end

-- ---------------------------------------------------------------------------------------------
-- For other addons
-- ---------------------------------------------------------------------------------------------

-- The ride you're on, or nil: { key, kind ("zeppelin" or "ship"), from, dest, fromKey (A's sign),
-- toKey (B's sign, when it lands at one), landing = { mapID, x, y } (0-1) or nil, elapsed, left
-- (seconds), timed (the countdown is a learned time, not a guess), arriving (nearly there) }.
function ZeppelinSignsAPI.Ride()
    if not ride then return nil end
    local s, to, now = ride.sign, ride.to, GetTime()
    local left = math.max(0, ride.shown - (now - ride.at))
    return {
        key = s.key, kind = s.kind, from = ride.fromName, dest = s.dest,
        fromKey = s.key, toKey = to and to.spot and to.spot.sign.key or nil,
        landing = to and to.mapID and { mapID = to.mapID, x = to.x, y = to.y } or nil,
        elapsed = now - ride.boarded, left = left, timed = ride.timed, arriving = left <= ARRIVING,
    }
end

-- How long a dock's ride lasts from boarding, and how many times it was timed; nil if never.
function ZeppelinSignsAPI.RideTime(key)
    local rec = DB() and DB().rides and DB().rides[key]
    if rec and rec.secs then return rec.secs, rec.n or 1 end
end

-- The older hook: fn(event) on each of those events.
Z.APIListener(API, "OnChange")
