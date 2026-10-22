local _, ns = ...

-- World positions for navigation: where you are, where the tracked job's spots are, which is
-- nearest, and which way to turn. World coordinates come from C_Map.GetWorldPosFromMapPos, whose
-- vector is (north, west) in yards on a continent.
local Nav = {}
ns.Nav = Nav

local spots, spotsKey -- cached world positions of the tracked job's spots
local dismissed       -- job you stopped from Waypoint's arrow: not pointed at again until you track it

-- The job being navigated to: the one you're tracking, else the one you took.
function Nav:Job()
    local key = ns.char.trackedJob or ns.char.activeJob
    return key and ns.Jobs:Get(key) or nil
end

function Nav:Track(key)
    ns.char.trackedJob = key
    spots, spotsKey = nil, nil
    if key then
        dismissed = nil
        local j = ns.Jobs:Get(key)
        ns:Print(("Tracking %s in %s."):format(j and j.title or key, j and j.zoneName or "?"))
    end
    self:SyncWaypoint()
    ns:Changed()
end

function Nav:IsTracking(key) return ns.char.trackedJob == key end

-- The arrow is the Waypoint addon's. Without it, jobs can't be tracked.
function Nav:HasArrow()
    return type(Waypoint) == "table" and Waypoint.Set ~= nil
end

-- Points Waypoint's arrow at the job's spots (nearest first, then on to the next), or takes it
-- away when there's no job. Only sets it when the job changes, so a newer target (a group's
-- waypoint path) keeps the arrow.
function Nav:SyncWaypoint()
    if not (self:HasArrow() and ns.char) then return end
    local job = self:Job()
    if job and (job.kind == "craft" or job.key == dismissed) then job = nil end
    local cur = Waypoint:Get("WealthPlanner")
    if not job then
        if cur then Waypoint:Clear("WealthPlanner") end
        return
    end
    -- After a reload the saved target has no onClick: set it up again. A spot you clicked on the
    -- world map (MapPins) stays until you track something else.
    if cur and (cur.key == job.key or cur.key == "spot") and cur.onClick then return end
    local points = {}
    for _, s in ipairs(self:Spots()) do
        points[#points + 1] = { mapID = job.zone, x = s.mapX / 100, y = s.mapY / 100 }
    end
    if #points == 0 then return end
    Waypoint:Set("WealthPlanner", {
        key = job.key, title = job.title, subtitle = job.zoneName, points = points, arrive = 25,
        onClick = function() ns.UI:Show("jobs") end,
    })
end

-- You: continent, north, west; nil inside instances or when the map can't place you.
function Nav:Player()
    local c, n, w = ns.WorldMap.Player()
    return c, n, w
end

-- The tracked job's spots as { { continent, north, west, kind, id, index, mapX, mapY } }.
function Nav:Spots()
    local job = self:Job()
    if not job then return {} end
    if spotsKey == job.key and spots then return spots end
    spots, spotsKey = {}, job.key
    local WM = ns.WorldMap
    for _, pt in ipairs(ns.Jobs:Pins(job, job.zone)) do
        local continent, n, w = WM.World(job.zone, pt[1] / 100, pt[2] / 100)
        if continent then
            spots[#spots + 1] = { continent, n, w, kind = pt.kind, id = pt.id, index = pt.index, mapX = pt[1], mapY = pt[2] }
        end
    end
    -- Fishing jobs have no spots: aim for the middle of the zone.
    if #spots == 0 then
        local continent, n, w = WM.World(job.zone, 0.5, 0.5)
        if continent then spots[1] = { continent, n, w, mapX = 50, mapY = 50 } end
    end
    return spots
end

function Nav:Invalidate() spots, spotsKey = nil, nil end

-- Every spot within `radius` yards: { { spot, dEast, dSouth } } (yards, relative to you).
function Nav:Around(radius)
    local continent, n, w = self:Player()
    local out = {}
    if not continent then return out end
    for _, s in ipairs(self:Spots()) do
        if s[1] == continent then
            local dEast, dSouth = w - s[3], n - s[2]
            if dEast * dEast + dSouth * dSouth <= radius * radius then out[#out + 1] = { s, dEast, dSouth } end
        end
    end
    return out
end

ns:On("ZONE_CHANGED_NEW_AREA", function() Nav:Invalidate() end)

-- Stopping the job from Waypoint's arrow stops tracking it here too.
ns:On("PLAYER_LOGIN", function()
    if not Nav:HasArrow() then return end
    Waypoint:RegisterCallback("WealthPlanner", function(event, e)
        if type(event) ~= "string" or event:upper() ~= "CLEARED" or not (e and e.owner == "WealthPlanner") then return end
        dismissed = e.key
        if ns.char.trackedJob == e.key then ns.char.trackedJob = nil end
        ns:Changed()
    end)
end)
