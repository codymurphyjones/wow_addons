local _, ns = ...

-- Takes the wobble out of a recorded road for drawing (what's recorded is never changed). Walking
-- a road you weave: sidestep a mob, overshoot a corner, correct your heading. Those zig-zags don't
-- lead into a turn, so they're navigation, not road:
--   0. averaging: each point moves to the average of the road within WINDOW yards either side of
--      it (along the road), which pulls a weave onto its middle line. The ends stay put; a real
--      corner is only rounded by a few yards.
--   1. spikes: a point where the path doubles back sharply (its two legs meet at under
--      SPIKE_ANGLE) and both legs are short (under SPIKE_LEN) is a step out and back: dropped,
--      again and again until none are left. A real dead end is longer and stays.
--   2. wobble: of the points between two that stay, only one further than TOLERANCE from the
--      straight line between them is kept (Douglas-Peucker). Real turns stray far further than a
--      weave does, so they're kept; the weaving in between goes.
local Smooth = {}
ns.Smooth = Smooth

local SPIKE_LEN = 20   -- yards
local SPIKE_ANGLE = 60 -- degrees
local TOLERANCE = 3    -- yards
local WINDOW = 10      -- yards either side a point is averaged over

local COS_SPIKE = math.cos(math.rad(SPIKE_ANGLE))

local function Dist(a, b)
    local dn, dw = a[1] - b[1], a[2] - b[2]
    return math.sqrt(dn * dn + dw * dw)
end

-- Distance from p to the segment a-b.
local function OffSegment(a, b, p)
    local dn, dw = b[1] - a[1], b[2] - a[2]
    local len2 = dn * dn + dw * dw
    if len2 < 1e-6 then return Dist(a, p) end
    local t = ((p[1] - a[1]) * dn + (p[2] - a[2]) * dw) / len2
    t = math.max(0, math.min(1, t))
    local qn, qw = a[1] + t * dn - p[1], a[2] + t * dw - p[2]
    return math.sqrt(qn * qn + qw * qw)
end

-- Whether the path doubles back at b (the angle between b->a and b->c is sharp).
local function Sharp(a, b, c)
    local un, uw = a[1] - b[1], a[2] - b[2]
    local vn, vw = c[1] - b[1], c[2] - b[2]
    local lu, lv = math.sqrt(un * un + uw * uw), math.sqrt(vn * vn + vw * vw)
    if lu < 1e-6 or lv < 1e-6 then return true end
    return (un * vn + uw * vw) / (lu * lv) > COS_SPIKE
end

-- Douglas-Peucker (with a stack rather than recursion): of the points between two that stay, only
-- one further than tol from the straight line between them is kept. P = { { n, w } }; returns flat.
local function Simplify(P, tol)
    local keep = { [1] = true, [#P] = true }
    local stack = { { 1, #P } }
    while #stack > 0 do
        local span = table.remove(stack)
        local first, last = span[1], span[2]
        local far, farD = nil, tol
        for i = first + 1, last - 1 do
            local d = OffSegment(P[first], P[last], P[i])
            if d > farD then far, farD = i, d end
        end
        if far then
            keep[far] = true
            stack[#stack + 1] = { first, far }
            stack[#stack + 1] = { far, last }
        end
    end
    local out = {}
    for i = 1, #P do
        if keep[i] then
            out[#out + 1] = P[i][1]
            out[#out + 1] = P[i][2]
        end
    end
    return out
end

-- A flat { n1, w1, n2, w2, ... } road, cleaned: the same shape, fewer points.
function Smooth.Clean(pts)
    local P = {}
    for i = 1, #pts - 1, 2 do P[#P + 1] = { pts[i], pts[i + 1] } end
    if #P < 3 then return pts end

    -- 0. Averaging over WINDOW yards of road either side (by distance along it).
    local along = { 0 }
    for i = 2, #P do along[i] = along[i - 1] + Dist(P[i - 1], P[i]) end
    local avg = { P[1] }
    local lo = 1
    for i = 2, #P - 1 do
        while along[lo] < along[i] - WINDOW do lo = lo + 1 end
        local sn, sw, k = 0, 0, 0
        local j = lo
        while j <= #P and along[j] <= along[i] + WINDOW do
            sn, sw, k = sn + P[j][1], sw + P[j][2], k + 1
            j = j + 1
        end
        avg[i] = { sn / k, sw / k }
    end
    avg[#P] = P[#P]
    P = avg

    -- 1. Spikes, until none are left.
    local changed = true
    while changed and #P > 2 do
        changed = false
        local i = 2
        while i < #P do
            local a, b, c = P[i - 1], P[i], P[i + 1]
            if Dist(a, b) < SPIKE_LEN and Dist(b, c) < SPIKE_LEN and Sharp(a, b, c) then
                table.remove(P, i)
                changed = true
            else
                i = i + 1
            end
        end
    end

    -- 2. Wobble.
    return Simplify(P, TOLERANCE)
end

-- ---------------------------------------------------------------------------------------------
-- The network: every stretch together. Walking the same road again you're never exactly on your
-- old line, so repeated passes draw as strands side by side, and loops around a hub (a mesa, the
-- lifts) tangle it. Built fresh whenever the roads change, so a new tangle is ironed out the same
-- way, with nothing to do by hand:
--   merge    stretches are taken in the order you walked them; a point within MERGE of a road
--            already in the network is that road (it isn't drawn again), so each road is one line
--   detours  what's left that is new: a short piece (under DETOUR_LEN) that leaves the network
--            and rejoins it, ending less than LOOPY of its length from where it started, is a
--            loop or a side trip: drawn faint. Real connections and long new roads stay full.
-- ---------------------------------------------------------------------------------------------

local RESAMPLE = 5      -- yards between points while merging
local MERGE = 8         -- yards: a pass this close to a road already drawn is that road
local CELL = 16         -- yards: the spatial index's cell
local RECENT = 4        -- a stretch's own last few pieces don't count as "already drawn"
local DETOUR_LEN = 120  -- yards
local LOOPY = 0.5
local NET_TOLERANCE = 2 -- yards: the merged pieces are simplified again before drawing

-- Points every RESAMPLE yards along a flat road: { { n, w } }.
local function Resample(flat)
    local P = {}
    for i = 1, #flat - 1, 2 do P[#P + 1] = { flat[i], flat[i + 1] } end
    if #P < 2 then return P end
    local out = { P[1] }
    local carry = 0
    for i = 2, #P do
        local a, b = P[i - 1], P[i]
        local len = Dist(a, b)
        local t = RESAMPLE - carry
        while t <= len do
            out[#out + 1] = { a[1] + (b[1] - a[1]) * t / len, a[2] + (b[2] - a[2]) * t / len }
            t = t + RESAMPLE
        end
        carry = len - (t - RESAMPLE)
    end
    local last = P[#P]
    if Dist(out[#out], last) > 0.5 then out[#out + 1] = last end
    return out
end

-- stretches: flat point lists (cleaned), oldest first. Returns { { pts = flat, faint = bool } }.
function Smooth.Network(stretches)
    local edges, grid = {}, {}
    local function Key(n, w) return math.floor(n / CELL) .. ":" .. math.floor(w / CELL) end
    local function Index(id)
        local e = edges[id]
        local seen = {}
        for _, p in ipairs({ e.a, e.b }) do
            local k = Key(p[1], p[2])
            if not seen[k] then
                seen[k] = true
                grid[k] = grid[k] or {}
                table.insert(grid[k], id)
            end
        end
    end
    -- The nearest edge to p within MERGE (not one of the run's last RECENT): id, distance, snapped point.
    local function Nearest(p, run)
        local cn, cw = math.floor(p[1] / CELL), math.floor(p[2] / CELL)
        local best, bestD, sp
        for dn = -1, 1 do
            for dw = -1, 1 do
                for _, id in ipairs(grid[(cn + dn) .. ":" .. (cw + dw)] or {}) do
                    local e = edges[id]
                    if not (run and e.run == run and e.seq > run.count - RECENT) then
                        local d = OffSegment(e.a, e.b, p)
                        if d <= MERGE and (not bestD or d < bestD) then
                            -- the closest point on the edge: where the pass joins it
                            local an, aw = e.a[1], e.a[2]
                            local vn, vw = e.b[1] - an, e.b[2] - aw
                            local len2 = vn * vn + vw * vw
                            local t = len2 > 0 and math.max(0, math.min(1, ((p[1] - an) * vn + (p[2] - aw) * vw) / len2)) or 0
                            best, bestD, sp = id, d, { an + t * vn, aw + t * vw }
                        end
                    end
                end
            end
        end
        return best, bestD, sp
    end

    local runs = {}
    for _, flat in ipairs(stretches) do
        local run, last = nil, nil
        for _, p in ipairs(Resample(flat)) do
            local id, _, sp = Nearest(p, run)
            if id then
                -- On a road already drawn: the new piece (if any) ends where it joins.
                if run then
                    table.insert(run.pts, sp)
                    run.joinsEnd = true
                    run = nil
                end
                last = sp
            else
                if not run then
                    run = { pts = {}, count = 0, joinsStart = last ~= nil }
                    runs[#runs + 1] = run
                    if last then table.insert(run.pts, last) end
                end
                local prev = run.pts[#run.pts]
                table.insert(run.pts, p)
                if prev then
                    run.count = run.count + 1
                    edges[#edges + 1] = { a = prev, b = p, run = run, seq = run.count }
                    Index(#edges)
                end
                last = p
            end
        end
    end

    local out = {}
    for _, run in ipairs(runs) do
        if #run.pts >= 2 then
            local len = 0
            for i = 2, #run.pts do len = len + Dist(run.pts[i - 1], run.pts[i]) end
            local chord = Dist(run.pts[1], run.pts[#run.pts])
            local faint = run.joinsStart and run.joinsEnd and len < DETOUR_LEN and chord < LOOPY * len
            out[#out + 1] = { pts = Simplify(run.pts, NET_TOLERANCE), faint = faint or false }
        end
    end
    return out
end
