local _, ns = ...

-- Long trips, chained from walks that never change on foot (Data\ZoneWays.lua, baked by
-- tools\Waypoint\nav_zones.py): every zone entrance, dock, flight master and town, and the walk between
-- those on one zone, by road mode. A trip of LONG yards or more goes through them: out of your zone by
-- its own exit, zone to zone, and in to the target from the last stop. Nothing of the world is searched
-- for that, so only the ground around you has to be in memory; the land map takes over near the end.
--
-- What's in memory: the costs of the road mode in use (a route chooses with those), and the walks of
-- the last few stops a route went through (KEEP_WALKS). Everything else stays packed.
local Z = {}
ns.ZoneWays = Z

local LONG = 1200       -- yards in a straight line that make a trip a long one
local REACH = 1800      -- yards from you or the target a stop may be, with no zone known
local DETOUR = 1.3      -- how much longer than a straight line the first and last stretch are taken to be
local RUN = 7
local MESA = 700        -- yards from a lift's top that its mesa may reach
local LEVEL = 20        -- yards under the top of a lift that still count as up there
local MIN_RISE = 40     -- yards a lift has to climb to reach somewhere only it goes (not a step or a dock)
local KEEP_WALKS = 12   -- stops whose walks stay unpacked
-- The first and last stretch (you to the first stop, the last stop to the target) are guessed: a
-- straight line DETOUR longer. A far stop's guess can look cheaper than the stored walks, and the way
-- then ends in a long straight line (over a ridge, in Stonetalon). So stops within END_YARDS of you
-- and of the target go first; farther ones only when none is that near.
local END_YARDS = 600
local END_DETOUR = 2.5  -- ...and, choosing the last stop, its straight stretch counts this much longer: the
                        -- stop right by the target wins over one a little cheaper with more guessed
Z.LONG = LONG

local costs = {}        -- ["continent:mode"] = { [from] = { to, secs, to, secs, ... } }
local unpacked, order = {}, {} -- ["continent:mode:from"] = { [to] = "n,w,n,w,..." }, oldest first

local function Unpack(text)
    local raw = C_EncodingUtil.DecodeBase64(text)
    return raw and C_EncodingUtil.DecompressString(raw, Enum.CompressionMethod.Zlib)
end

-- What a route chooses with, for a map and mode: only one mode is ever read.
local function Costs(continent, mode)
    local data = ns.ZoneWayData and ns.ZoneWayData[continent]
    local packed = data and data[mode]
    if not packed then return nil end
    local key = continent .. ":" .. mode
    local list = costs[key]
    if list then return list, data.exits end
    local ok, text = pcall(Unpack, packed.costs)
    if not ok or not text then return nil end
    -- Another road mode's are done with.
    for k in pairs(costs) do
        if k:match("^%d+:(.*)$") ~= mode then costs[k] = nil end
    end
    list = {}
    local from = 0
    for line in (text .. ";"):gmatch("([^;]*);") do
        from = from + 1
        local row, i = {}, 0
        for v in line:gmatch("%d+") do
            i = i + 1
            row[i] = tonumber(v)
        end
        list[from] = row
    end
    costs[key] = list
    return list, data.exits
end

-- The walk from one stop to another: a string of "n,w,n,w,...", or nil.
local function WalkOf(continent, mode, from, to)
    local key = continent .. ":" .. mode .. ":" .. from
    local walks = unpacked[key]
    if not walks then
        local packed = ns.ZoneWayData[continent][mode].ways[from]
        local ok, text = pcall(Unpack, packed)
        if not ok or not text then return nil end
        walks = {}
        for row in text:gmatch("[^;]+") do
            local t, rest = row:match("^(%d+),(.*)$")
            if t then walks[tonumber(t)] = rest end
        end
        unpacked[key] = walks
        order[#order + 1] = key
        if #order > KEEP_WALKS then unpacked[table.remove(order, 1)] = nil end
    end
    return walks[to]
end

-- The zone at a point, from the land map (0: none known).
function Z.ZoneAt(c, n, w)
    local G = ns.Grid
    return G and G.ZoneAt and G:ZoneAt(c, n, w) or 0
end

-- The height of the ground at a point, from the land map, or nil.
-- (Second: true when the land map there isn't unpacked yet; it is being, in the background.)
function Z.HeightAt(c, n, w)
    local G = ns.Grid
    if G and G.HeightSoon then return G:HeightSoon(c, n, w) end
    return G and G.Height and G:Height(c, n, w) or nil
end

local function Yards(an, aw, bn, bw)
    local dn, dw = an - bn, aw - bw
    return math.sqrt(dn * dn + dw * dw)
end

-- A small heap of { secs, stop }.
local function Push(h, secs, stop)
    local i = #h + 1
    h[i] = { secs, stop }
    while i > 1 do
        local p = math.floor(i / 2)
        if h[p][1] <= h[i][1] then break end
        h[p], h[i] = h[i], h[p]
        i = p
    end
end

local function Pop(h)
    local top, last = h[1], h[#h]
    h[#h] = nil
    local n = #h
    if n > 0 then
        h[1] = last
        local i = 1
        while true do
            local c = i * 2
            if c > n then break end
            if c < n and h[c + 1][1] < h[c][1] then c = c + 1 end
            if h[i][1] <= h[c][1] then break end
            h[i], h[c] = h[c], h[i]
            i = c
        end
    end
    return top
end

-- The quickest walk from (n, w) to every stop. Kept for the last few places asked about: a plan asks
-- about every dock and flight master from one spot.
local function From(c, n, w, mode)
    local list, exits = Costs(c, mode)
    if not list then return nil end
    local key = ("%d:%s:%d:%d"):format(c, mode, n / 25, w / 25)
    if Z.cache and Z.cache[key] then return Z.cache[key] end
    local dist, prev, heap = {}, {}, {}
    -- Out of your zone by its own exits: the stop nearest on the map may be down a cliff from you.
    local zone = Z.ZoneAt(c, n, w)
    for pass = 1, 2 do
        for i, e in ipairs(exits) do
            local d = Yards(n, w, e[3], e[4])
            if ((e[1] == zone or e[2] == zone) or (zone == 0 and d <= REACH)) and (pass == 2 or d <= END_YARDS) then
                dist[i] = d * DETOUR / RUN
                Push(heap, dist[i], i)
            end
        end
        if #heap > 0 then break end
    end
    while #heap > 0 do
        local top = Pop(heap)
        local du, u = top[1], top[2]
        if du == dist[u] then
            local row = list[u]
            for k = 1, #row, 2 do
                local to, nd = row[k], du + row[k + 1]
                if not dist[to] or nd < dist[to] then
                    dist[to], prev[to] = nd, u
                    Push(heap, nd, to)
                end
            end
        end
    end
    local out = { dist = dist, prev = prev, exits = exits }
    Z.cache = Z.cache or {}
    Z.keys = Z.keys or {}
    Z.cache[key] = out
    Z.keys[#Z.keys + 1] = key
    if #Z.keys > 4 then Z.cache[table.remove(Z.keys, 1)] = nil end
    return out
end

local function Last(from, c, tn, tw)
    local best, last, secs
    local zone = Z.ZoneAt(c, tn, tw)
    for pass = 1, 2 do
        for i, d in pairs(from.dist) do
            local e = from.exits[i]
            local out = Yards(tn, tw, e[3], e[4])
            if (e[1] == zone or e[2] == zone or (zone == 0 and out <= REACH)) and (pass == 2 or out <= END_YARDS) then
                local total = d + out * END_DETOUR / RUN
                if not best or total < best then best, last, secs = total, i, d + out * DETOUR / RUN end
            end
        end
        if last then break end
    end
    -- (The time: the usual guess for the last stretch. END_DETOUR only chooses the stop.)
    return last, secs
end

-- The lift to a point that's up where only lifts go (a mesa: Thunder Bluff, Freewind Post), the
-- nearest of them; nil when the point isn't up there. A place a lift's top is level with, within
-- MESA yards, and well above its bottom.
-- (Remembered by place: the ground's height comes off the land map, and unpacking a far place's
-- tile for it took 50-100 ms each time a plan asked.)
local liftMemo, liftCount = {}, 0
function Z:LiftFor(c, n, w)
    local lifts = ns.ZoneLifts and ns.ZoneLifts[c]
    if not lifts then return nil end
    -- Only a place near a lift can be up on its mesa: no height needed for the rest.
    local near
    for _, lift in ipairs(lifts) do
        if Yards(n, w, lift[1], lift[2]) <= MESA and lift[4] - lift[3] >= MIN_RISE then near = true break end
    end
    if not near then return nil end
    local key = ("%d:%d:%d"):format(c, n, w)
    local known = liftMemo[key]
    if known ~= nil then return known or nil end
    local best, bd
    local h, pending = self.HeightAt(c, n, w)
    if pending then return nil end -- asked again once the ground's unpacked (not remembered)
    if h then
        for _, lift in ipairs(lifts) do
            local d = Yards(n, w, lift[1], lift[2])
            if d <= MESA and h >= lift[4] - LEVEL and lift[4] - lift[3] >= MIN_RISE and (not bd or d < bd) then
                best, bd = lift, d
            end
        end
    end
    if liftCount > 1000 then wipe(liftMemo); liftCount = 0 end
    liftMemo[key], liftCount = best or false, liftCount + 1
    return best
end

-- Seconds on foot at run speed from (n, w) to (tn, tw) through the stops, or nil. The lifts on the way
-- count: from down at the first one, and on to the last one.
-- (Remembered: a plan asks this every second for each flight master and dock to the target, the
-- same places each time, and each answer is a search over the stops.)
local secsMemo, secsCount = {}, 0
local SecsUncached
function Z:Secs(c, n, w, tn, tw, mode)
    if Yards(n, w, tn, tw) < LONG then return nil end
    local key = ("%d:%s:%d:%d:%d:%d"):format(c, mode, n, w, tn, tw)
    local known = secsMemo[key]
    if known ~= nil then return known or nil end
    local secs = SecsUncached(self, c, n, w, tn, tw, mode)
    if secsCount > 2000 then wipe(secsMemo); secsCount = 0 end
    secsMemo[key], secsCount = secs or false, secsCount + 1
    return secs
end

function SecsUncached(self, c, n, w, tn, tw, mode)
    local up, down = self:LiftFor(c, n, w), self:LiftFor(c, tn, tw)
    local extra = 0
    if up and up ~= down then
        extra = extra + Yards(n, w, up[1], up[2]) * DETOUR / RUN + up[5]
        n, w = up[1], up[2]
    end
    if down and down ~= up then
        extra = extra + Yards(tn, tw, down[1], down[2]) * DETOUR / RUN + down[5]
        tn, tw = down[1], down[2]
    end
    local from = From(c, n, w, mode)
    if not from then return nil end
    local _, secs = Last(from, c, tn, tw)
    return secs and secs + extra
end

-- Under the loading screen (Flight.lua's warm-up): the stops' costs unpacked and the walks from where
-- you stand worked out, not in the first plan after a reload (ZoneWays:Secs, ~80 ms).
function Z:Warm(c, n, w, mode)
    if not (c and Costs(c, mode)) then return end
    self:LiftFor(c, n, w)
    From(c, n, w, mode)
end

-- Whether this continent has stored walks.
function Z:Has(c) return ns.ZoneWayData ~= nil and ns.ZoneWayData[c] ~= nil end

-- The way from you to the target through the stops: squares { n, w }, or nil when the trip isn't a
-- long one or no chain of stops joins them. mode: Route.lua's road mode.
function Z:Way(c, n, w, tc, tn, tw, mode)
    if c ~= tc or Yards(n, w, tn, tw) < LONG then return nil end
    -- Up on a mesa, you or the target: the lift is part of the way, and goes first.
    local up, down = self:LiftFor(c, n, w), self:LiftFor(c, tn, tw)
    if up == down then up, down = nil, nil end
    local endN, endW = tn, tw
    if up then n, w = up[1], up[2] end
    if down then tn, tw = down[1], down[2] end
    local from = From(c, n, w, mode)
    if not from then return nil end
    local last = Last(from, c, tn, tw)
    if not last then return nil end
    local chain, at = {}, last
    while at do
        table.insert(chain, 1, at)
        at = from.prev[at]
    end
    local exits = from.exits
    local squares = {}
    local function Add(sn, sw, lift)
        squares[#squares + 1] = { n = sn, w = sw, water = false, face = false, via = lift, lift = lift }
    end
    if up then Add(up[1], up[2], true) end
    Add(exits[chain[1]][3], exits[chain[1]][4])
    for k = 2, #chain do
        local points = WalkOf(c, mode, chain[k - 1], chain[k])
        if points then
            local coords, skip = {}, true
            for v in points:gmatch("-?%d+") do coords[#coords + 1] = tonumber(v) end
            for i = 1, #coords - 1, 2 do
                if skip then skip = false else Add(coords[i], coords[i + 1]) end
            end
        else
            Add(exits[chain[k]][3], exits[chain[k]][4])
        end
    end
    if down then Add(down[1], down[2], true) end
    Add(endN, endW)
    return squares
end
