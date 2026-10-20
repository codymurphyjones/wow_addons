local _, ns = ...

-- Travel over the land and water map (Data\Water.lua, built from the game's map tiles by
-- tools\Waypoint\build_water.py): how long it takes to get from a point to every square of its
-- continent, on foot and swimming, around lakes, cliffs, lava and the edge of the world.
--
-- A "field" holds the seconds from one source (you, or the target) to every square you can reach,
-- found by Dijkstra over the 66-yard squares, 8 ways each. Land costs your travel speed, steep
-- squares three times that, water your swimming speed; lava and off-map squares can't be crossed.
-- Climbing costs extra (the field's climb: each yard up counts as that many yards more on the flat).
--
-- Which steps exist comes from the map's links (build_water.py): from each square to each of its 8
-- neighbours, a walk (there's a slope you can walk up or down), a drop (only down: a cliff), or
-- nothing. A drop you'd take no damage from (HARMLESS yards) you slide down, a little slower; a
-- bigger one up to the field's maxDrop (your setting for how much fall damage you'll take) you
-- jump; past that only with a safe fall ready (Slow Fall, Levitate). Nothing climbs a cliff. A field to the target is worked out from the target outward, so it's "reverse": each
-- step is costed in the direction you'd really walk it.
-- A walk link only says two squares join; where the way between them zigzags up a hillside or goes
-- round the end of a ridge, the map keeps its turns (bends), and G:Detail puts them into a path so
-- the arrow and the route lines follow them instead of pointing straight up the slope.
-- Fields are worked out in the background, a few milliseconds a frame (BUDGET), and Route.lua
-- uses the last one that still fits. The path to any square follows the field downhill.
local G = {}
ns.Grid = G

local BUDGET = 4         -- milliseconds of work per frame
local RUSH = 12          -- ...while you're waiting for a route (G.rush: nothing to follow yet)
local STEEP_COST = 3     -- steep squares take this many times longer to cross
local MOVE = 3           -- squares you can move before your field is worked out again
local SLIDE = 1.5        -- sliding down a small drop is this much slower than walking
-- A jump you'd take damage from (or need a safe fall for) counts this many seconds extra: finding
-- the edge, casting, landing. A walk round that's about as quick beats it.
local JUMP_COST = 30

-- Fall damage, as the servers work it out (TrinityCore, CMaNGOS): a share of your maximum health,
-- 1.8% per yard fallen less 24.26%, from about 14.6 yards (nothing below). 69 yards kills you from
-- full health.
local HARMLESS = 14.57
function G.FallDamage(yards)
    if yards < HARMLESS then return 0 end
    return math.max(0, math.min(1, 0.018 * yards - 0.2426))
end
-- The highest fall that costs at most share (0-1) of your health.
function G.FallHeight(share)
    if share <= 0 then return HARMLESS end
    return (share + 0.2426) / 0.018
end
local DIAG = math.sqrt(2)
local B_L, B_S, B_W, B_H, B_V = ("lswhv"):byte(1, 5)
local STEPS = { { -1, 0, 1 }, { 1, 0, 1 }, { 0, -1, 1 }, { 0, 1, 1 },
    { -1, -1, DIAG }, { -1, 1, DIAG }, { 1, -1, DIAG }, { 1, 1, DIAG } }

-- Direction index (from 0, as in STEPS) of a step (dr, dc), keyed dr * 3 + dc.
local DIRECTION = {}
for k, s in ipairs(STEPS) do DIRECTION[s[1] * 3 + s[2]] = k - 1 end

local W = ns.Water
local maps = {} -- continent -> { r0, c0, nr, nc, rows = { "llww..." } }

-- The map tiles are Forever's (classic) continents; later expansions reshaped them.
local function Usable()
    if not W then return false end
    local _, _, _, interface = GetBuildInfo()
    return (tonumber(interface) or 0) < 40000
end

local function Map(continent)
    local m = maps[continent]
    if m ~= nil then return m or nil end
    local src = Usable() and W.maps[continent]
    if not src then
        maps[continent] = false
        return nil
    end
    m = { r0 = src.r0, c0 = src.c0, rows = {}, heights = src.heights or {}, links = src.links, linkRows = {}, fallOn = {},
        bends = src.bends, bendRows = {} }
    for i, row in ipairs(src.rows) do
        m.rows[i] = row:gsub("(%d*)(%a)", function(n, ch) return ch:rep(n == "" and 1 or tonumber(n)) end)
    end
    m.nr, m.nc = #m.rows, #m.rows[1]
    maps[continent] = m
    return m
end

function G:Has(continent) return Map(continent) ~= nil end

-- The square at a world position: its index (1-based), row and column (0-based), or nil off the map.
local function Square(m, n, w)
    local r = math.floor((W.max - n) / W.cell) - m.r0
    local c = math.floor((W.max - w) / W.cell) - m.c0
    if r < 0 or c < 0 or r >= m.nr or c >= m.nc then return nil end
    return r * m.nc + c + 1, r, c
end

local function Kind(m, r, c) return m.rows[r + 1]:byte(c + 1) end

-- Tunnels and caves the land map can't see (they run under it): W.passages[continent], each
-- { an, aw, bn, bw, yards, name } from one mouth to the other. Walked either way, as an extra step
-- between the two mouths' squares: { [square index] = { { to = square index, yards, name } } }.
local NONE = {}
local function Passages(m, continent)
    if m.passages then return m.passages end
    m.passages = {}
    for _, p in ipairs(W.passages and W.passages[continent] or {}) do
        local a = Square(m, p[1], p[2])
        local b = Square(m, p[3], p[4])
        if a and b and a ~= b then
            m.passages[a] = m.passages[a] or {}
            m.passages[b] = m.passages[b] or {}
            table.insert(m.passages[a], { to = b, yards = p[5], name = p[6] })
            table.insert(m.passages[b], { to = a, yards = p[5], name = p[6] })
        end
    end
    return m.passages
end

-- A square's height in yards (two characters each, base 64, yards + 1024); 0 when unknown.
local DIGIT = {}
for i, ch in ipairs({ ("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"):byte(1, -1) }) do DIGIT[ch] = i - 1 end
local Height -- below

-- A square's links: walk | drop << 8, bit k for the step in direction k (STEPS, from 0); nil when
-- the map has none (then every step to a square you can use is a walk).
local LDIGIT = {}
for i, ch in ipairs({ ("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$%&()*+,-."):byte(1, -1) }) do LDIGIT[ch] = i - 1 end
local function Links(m, r, c)
    if not m.links then return nil end
    local row = m.linkRows[r + 1]
    if not row then
        local src = m.links[r + 1]
        if not src then return nil end
        row = src:gsub("(%d*)([^%d][^%d][^%d])", function(n, tok) return n == "" and tok or tok:rep(tonumber(n)) end)
        m.linkRows[r + 1] = row
    end
    local a, b, c3 = row:byte(c * 3 + 1, c * 3 + 3)
    if not c3 then return 0 end
    return LDIGIT[a] * 4096 + LDIGIT[b] * 64 + LDIGIT[c3]
end

-- A walk link's bend: the turns of the real way from square (r, c) to its neighbour in direction k,
-- where it zigzags up a hillside or goes round the end of a ridge (the map's bends, build_water.py
-- bend_row), as { dr, dc, dr, dc, ... } cells from the square's top left corner; nil when the
-- straight line does. A row is decoded the first time it's asked for.
local BEND_OFFSET = 24
local function Bend(m, r, c, k)
    if not m.bends then return nil end
    local row = m.bendRows[r + 1]
    if row == nil then
        row = false
        local s = m.bends[r + 1]
        if s and s ~= "" then
            row = {}
            local i = 1
            while i + 3 <= #s do
                local col = DIGIT[s:byte(i)] * 64 + DIGIT[s:byte(i + 1)]
                local dir, count = DIGIT[s:byte(i + 2)], DIGIT[s:byte(i + 3)]
                local turns = {}
                for t = 0, count - 1 do
                    local a, b = s:byte(i + 4 + t * 2, i + 5 + t * 2)
                    turns[#turns + 1] = DIGIT[a] - BEND_OFFSET
                    turns[#turns + 1] = DIGIT[b] - BEND_OFFSET
                end
                row[col * 8 + dir] = turns
                i = i + 4 + count * 2
            end
        end
        m.bendRows[r + 1] = row
    end
    return row and row[c * 8 + k] or nil
end

local POW = {}
for k = 0, 15 do POW[k] = 2 ^ k end
local function Bit(v, k) return math.floor(v / POW[k]) % 2 == 1 end
local OPPOSITE = { [0] = 1, 0, 3, 2, 7, 6, 5, 4 } -- direction k's way back

-- Overrides on top of the map's links, per continent (G:SetOverrides): steps you've walked
-- yourself and RoadLog's narrow passes and roads open a link; RoadLog's blockers close one. Keyed
-- by Key(), from the whole map's square numbers, so they survive a rebuilt map.
local function Key(m, r, c, k)
    return ((r + m.r0) * 1024 + (c + m.c0)) * 8 + k
end
local LinkKey = Key

-- How a step from (r, c) in direction k (from 0) goes: "walk", "drop" with how far down, or nil.
local function Step(m, r, c, k, rr, cc)
    local ov = m.ov
    if ov then
        local key = Key(m, r, c, k)
        if ov.block[key] then return nil end
        if ov.open[key] then return "walk", 0 end
    end
    local v = Links(m, r, c)
    if not v then return "walk", 0 end
    if Bit(v, k) then return "walk", 0 end
    if Bit(v, k + 8) then return "drop", Height(m, r, c) - Height(m, rr, cc) end
    return nil
end

-- How much further you have to fall after landing on (r, c): nothing on ground you can stand on;
-- on a cliff face (no ground in the square) you keep sliding, by the shortest way down, to the
-- next ground. A cliff spread over several squares of face is one fall. It only depends on the
-- map, so it's kept per square. Drops always go down, so it ends.
local function FallOn(m, r, c)
    if Kind(m, r, c) ~= B_S then return 0 end
    local idx = r * m.nc + c + 1
    local v = m.fallOn[idx]
    if v then return v end
    m.fallOn[idx] = 0
    local best
    for k, s in ipairs(STEPS) do
        local rr, cc = r + s[1], c + s[2]
        if rr >= 0 and cc >= 0 and rr < m.nr and cc < m.nc then
            local how, down = Step(m, r, c, k - 1, rr, cc)
            if how == "drop" and down > 0 then
                local t = down + FallOn(m, rr, cc)
                if not best or t < best then best = t end
            end
        end
    end
    m.fallOn[idx] = best or 0
    return best or 0
end

Height = function(m, r, c)
    local row = m.heights[r + 1]
    if not row then return 0 end
    local a, b = row:byte(c * 2 + 1, c * 2 + 2)
    if not (a and b) then return 0 end
    return DIGIT[a] * 64 + DIGIT[b] - 1024
end

local function Center(m, idx)
    local r, c = math.floor((idx - 1) / m.nc), (idx - 1) % m.nc
    return W.max - (r + m.r0 + 0.5) * W.cell, W.max - (c + m.c0 + 0.5) * W.cell
end

-- Seconds per yard on a square, or nil where you can't go. Cliff faces (s) are crossed only by
-- their links (drops); without links they're slow ground.
local function Pace(kind, speed, swim, linked)
    if kind == B_L then return 1 / speed end
    if kind == B_S then return (linked and 1 or STEEP_COST) / speed end
    if kind == B_W and swim > 0 then return 1 / swim end -- swim 0: no swimming
end

-- ---------------------------------------------------------------------------------------------
-- Fields, worked out in the background
-- ---------------------------------------------------------------------------------------------

local fields = {} -- key -> the newest finished field
local jobs = {}   -- key -> the field being worked out: { co, field }
local queue = {}  -- keys waiting their turn, oldest first

-- The search runs over nodes: each square twice, with your safe fall still ready (state 0) or
-- already used (state 1): node = square * 2 + state. A safe fall you can only cast once on the way
-- (Walk on Air: its cooldown outlasts a walk) moves you from ready to used, and a cliff that needs
-- it can't be jumped once it's used. One you can cast every time (Slow Fall, Levitate: a feather a
-- cast) leaves the state alone.
local function Work(f)
    local m, dist, from, secs = f.m, f.dist, f.from, f.secs
    local speed, swim, safe, reverse = f.speed, f.swim, f.safe, f.reverse
    local maxDrop, climb, once = f.maxDrop, f.climb, f.once
    -- Off the roads every step weighs offroad times its seconds (your road preference); the search
    -- goes by weight, and secs keeps the real seconds along the way it chose. In a major city at
    -- least the city's weight, whatever your preference (G:SetCities).
    local offroad, roads = f.offroad, m.roads
    local cities, cityOff = m.cities, m.cityOffroad or 1
    local hk, hv, size = {}, {}, 0
    local function Push(d, idx)
        size = size + 1
        local i = size
        while i > 1 do
            local p = math.floor(i / 2)
            if hk[p] <= d then break end
            hk[i], hv[i] = hk[p], hv[p]
            i = p
        end
        hk[i], hv[i] = d, idx
    end
    local function Pop()
        local d, idx = hk[1], hv[1]
        local lastK, lastV = hk[size], hv[size]
        hk[size], hv[size] = nil, nil
        size = size - 1
        if size > 0 then
            local i = 1
            while true do
                local l = i * 2
                if l > size then break end
                local r = l + 1
                local child = (r <= size and hk[r] < hk[l]) and r or l
                if hk[child] >= lastK then break end
                hk[i], hv[i] = hk[child], hv[child]
                i = child
            end
            hk[i], hv[i] = lastK, lastV
        end
        return d, idx
    end
    local cell, nc, nr, count = W.cell, m.nc, m.nr, 0
    -- Toward a point (the target's field, toward you): A*. Each square's key is its weight so far
    -- plus the straight line to that point at your fastest pace, which no step beats, so every
    -- square still gets its exact weight; the squares toward you just come first, and the way from
    -- where you stand is there (f.done) long before the whole field is.
    local done = f.done
    local H
    if f.toward then
        local tn, tw = f.toward[1], f.toward[2]
        local per = 1 / math.max(speed, swim or 0)
        local mx, r0, c0 = W.max, m.r0, m.c0
        H = function(idx)
            local r, c = math.floor((idx - 1) / nc), (idx - 1) % nc
            local dn, dw = mx - (r + r0 + 0.5) * cell - tn, mx - (c + c0 + 0.5) * cell - tw
            return math.sqrt(dn * dn + dw * dw) * per
        end
    end
    local function Key(j, g) return H and g + H(math.floor(j / 2)) or g end
    -- From you: the spell is ready. To the target (reverse): either state can finish there. Without
    -- a once-only safe fall the state never changes, so one is enough.
    dist[f.src * 2] = 0
    secs[f.src * 2] = 0
    Push(Key(f.src * 2, 0), f.src * 2)
    if reverse and once then
        dist[f.src * 2 + 1] = 0
        secs[f.src * 2 + 1] = 0
        Push(Key(f.src * 2 + 1, 0), f.src * 2 + 1)
    end
    local passages = Passages(m, f.continent)
    local start = debugprofilestop()
    while size > 0 do
        local _, node = Pop()
        if not done[node] then
            -- the first time a square comes out its weight is final (later copies are stale)
            done[node] = true
            local d = dist[node]
            local idx, state = math.floor(node / 2), node % 2
            local r, c = math.floor((idx - 1) / nc), (idx - 1) % nc
            local kind, height = Kind(m, r, c), Height(m, r, c)
            local linked = m.links ~= nil
            local here = Pace(kind, speed, swim, linked) or (1 / speed)
            for k, s in ipairs(STEPS) do
                local rr, cc = r + s[1], c + s[2]
                if rr >= 0 and cc >= 0 and rr < nr and cc < nc then
                    local k2 = Kind(m, rr, cc)
                    local pace = Pace(k2, speed, swim, linked)
                    -- The step the way you'd really walk it: out from here, or (reverse) in to here.
                    local how, fall
                    local nextState = state
                    if pace then
                        local dir = reverse and OPPOSITE[k - 1] or k - 1
                        if reverse then
                            how, fall = Step(m, rr, cc, dir, r, c)
                        else
                            how, fall = Step(m, r, c, dir, rr, cc)
                        end
                        -- The whole cliff counts: this drop and the ones after it. Past what you'll
                        -- fall, only with the safe fall; a once-only one has to be still ready.
                        if how == "drop" then
                            local whole = fall + (reverse and FallOn(m, r, c) or FallOn(m, rr, cc))
                            if whole > maxDrop then
                                if not safe then
                                    how = nil
                                elseif once then
                                    -- forward: ready here, used after; reverse (walking in to here):
                                    -- used here, so ready just before
                                    if reverse then
                                        if state == 1 then nextState = 0 else how = nil end
                                    else
                                        if state == 0 then nextState = 1 else how = nil end
                                    end
                                end
                            end
                        end
                    end
                    if how then
                        local j = (rr * nc + cc + 1) * 2 + nextState
                        local rise = Height(m, rr, cc) - height
                        if reverse then rise = -rise end
                        local nd
                        if how == "drop" then
                            -- Down a cliff: slide down a small one, jump a big one (safe fall).
                            nd = s[3] * cell / speed * (fall > HARMLESS and 1 or SLIDE)
                            -- Leaving the ground for a big one is a jump of its own (on cliff face
                            -- you're already falling).
                            local start = reverse and k2 or kind
                            if start ~= B_S and fall + (reverse and FallOn(m, r, c) or FallOn(m, rr, cc)) > HARMLESS then
                                nd = nd + JUMP_COST
                            end
                        else
                            nd = s[3] * cell * (here + pace) / 2
                            if rise > 0 and kind ~= B_W and k2 ~= B_W then nd = nd + rise * climb / speed end
                        end
                        local t = secs[node] + nd
                        if not (roads and roads[LinkKey(m, r, c, k - 1)]) then
                            local weight = (cities and cities[idx]) and math.max(offroad, cityOff) or offroad
                            if weight ~= 1 then nd = nd * weight end
                        end
                        nd = d + nd
                        local old = dist[j]
                        if not done[j] and (not old or nd < old) then
                            dist[j] = nd
                            secs[j] = t
                            from[j] = node
                            Push(Key(j, nd), j)
                        end
                    end
                end
            end
            -- Through a tunnel or a cave to its other mouth: its length at your speed.
            for _, p in ipairs(passages[idx] or NONE) do
                local j = p.to * 2 + state
                local nd = d + p.yards / speed
                local old = dist[j]
                if not done[j] and (not old or nd < old) then
                    dist[j] = nd
                    secs[j] = secs[node] + p.yards / speed
                    from[j] = node
                    Push(Key(j, nd), j)
                end
            end
        end
        count = count + 1
        if count % 200 == 0 and debugprofilestop() - start > (G.rush and RUSH or BUDGET) then
            coroutine.yield()
            start = debugprofilestop()
        end
    end
end

local listeners = {} -- G:OnReady's
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self)
    local key = queue[1]
    local job = key and jobs[key]
    if not job then
        if key then table.remove(queue, 1) else self:Hide() end
        return
    end
    local ok, err = coroutine.resume(job.co)
    if not ok then
        jobs[key] = nil
        table.remove(queue, 1)
        geterrorhandler()("Waypoint grid: " .. tostring(err))
    elseif coroutine.status(job.co) == "dead" then
        job.field.ready = true
        fields[key] = job.field
        jobs[key] = nil
        table.remove(queue, 1)
        for _, fn in ipairs(listeners) do
            local ok2, err2 = pcall(fn, key)
            if not ok2 then geterrorhandler()(err2) end
        end
    end
end)

local function Fits(f, continent, idx, r, c, o, slack)
    if not f or f.version ~= G.version or f.continent ~= continent or f.speed ~= o.speed or f.swim ~= o.swim or f.safe ~= o.safe
        or f.maxDrop ~= o.maxDrop or f.climb ~= o.climb or f.once ~= o.once or f.offroad ~= o.offroad then return false end
    return math.abs(f.r - r) <= slack and math.abs(f.c - c) <= slack
end

-- The field from the point (continent, north, west) under key ("here", "target"), when one that
-- fits is finished (its source within slack squares, the same settings). Otherwise it's started in
-- the background and this returns nil for now. opts:
--   speed, swim  yards per second on land and in water (swim 0: never swim)
--   slack        squares the source may be off by
--   safe         you can jump down any cliff (Slow Fall, Levitate)
--   maxDrop      the highest drop you'll jump without one (yards)
--   climb        each yard up counts as this many yards more on the flat
--   once         the safe fall can be cast only once on the way (a cooldown, not a reagent)
--   offroad      how much more a step off the roads weighs (1: roads don't matter; G:SetRoads)
--   reverse      the walk ends at the point (a field to the target)
--   toward       { north, west }: where the walk starts (you), for a reverse field: worked out
--                toward it first (A*), so the way from there is ready early (G:Partial)
--   later        don't go ahead of the fields already waiting (one worked out ahead of time)
function G:Field(key, continent, n, w, opts)
    local m = Map(continent)
    if not m then return nil end
    local idx, r, c = Square(m, n, w)
    if not idx then return nil end
    local o = {
        speed = math.floor(opts.speed * 10 + 0.5) / 10,
        swim = math.floor((opts.swim or 0) * 10 + 0.5) / 10,
        safe = opts.safe and true or false,
        maxDrop = math.floor(opts.maxDrop or HARMLESS),
        climb = opts.climb or 1,
        once = opts.once and true or false,
        offroad = math.floor((opts.offroad or 1) * 100 + 0.5) / 100,
    }
    local slack = opts.slack or 0
    -- A field worked out ahead under "next" (Route.lua: where the arrow goes after this) for the
    -- point you've now switched to: taken over, finished or still being worked out.
    if key ~= "next" and opts.reverse then
        local spare = fields.next
        if spare and spare.reverse and Fits(spare, continent, idx, r, c, o, slack) then
            fields[key], fields.next = spare, nil
        end
        local sj = jobs.next
        if sj and sj.field.reverse and Fits(sj.field, continent, idx, r, c, o, slack)
            and not Fits(fields[key], continent, idx, r, c, o, slack) then
            for i, q in ipairs(queue) do
                if q == "next" then table.remove(queue, i) break end
            end
            if not jobs[key] then table.insert(queue, 1, key) end
            jobs[key], jobs.next = sj, nil
        end
    end
    local f = fields[key]
    if Fits(f, continent, idx, r, c, o, slack) then return f end
    local job = jobs[key]
    if job and Fits(job.field, continent, idx, r, c, o, slack) then return nil end
    -- Standing in the sea or on lava by the map's reckoning: start from the nearest square you can use.
    local src = idx
    if not Pace(Kind(m, r, c), 1, 1) then
        src = nil
        for ring = 1, 2 do
            for dr = -ring, ring do
                for dc = -ring, ring do
                    local rr, cc = r + dr, c + dc
                    if not src and rr >= 0 and cc >= 0 and rr < m.nr and cc < m.nc and Pace(Kind(m, rr, cc), 1, 1) then
                        src = rr * m.nc + cc + 1
                    end
                end
            end
        end
        if not src then return nil end
    end
    local field = { continent = continent, m = m, src = src, r = r, c = c, speed = o.speed, swim = o.swim,
        safe = o.safe, maxDrop = o.maxDrop, climb = o.climb, once = o.once, reverse = opts.reverse and true or false,
        offroad = o.offroad, dist = {}, secs = {}, from = {}, done = {},
        toward = opts.toward and { opts.toward[1], opts.toward[2] } or nil,
        version = G.version }
    -- The target's field first: the way to it is what the arrow needs soonest. One worked out
    -- ahead (later) waits its turn.
    if not jobs[key] then
        if opts.reverse and not opts.later then table.insert(queue, 1, key) else queue[#queue + 1] = key end
    end
    jobs[key] = { field = field, co = coroutine.create(function() Work(field) end) }
    driver:Show()
    return nil
end

-- The field under key while it's still being worked out (or the finished one): the squares it
-- has settled (f.done) are exact already. With G:Settled, the way from where you stand can be used
-- before the rest of the field is there.
function G:Partial(key)
    local job = jobs[key]
    return job and job.field or fields[key]
end

-- Whether the field has settled the square at a world point: its way from there is final.
function G:Settled(f, n, w)
    local idx = f and Square(f.m, n, w)
    return idx and (f.done[idx * 2] or f.done[idx * 2 + 1]) and true or false
end

-- Whether any field is being worked out or waiting.
function G:Busy() return queue[1] ~= nil end

-- Whether a field under key is being worked out now (G:Field returned nil for it: it's coming).
function G:Working(key)
    return jobs[key] ~= nil
end

-- fn(key) is called each time a field is finished (worked out in the background, then reported):
-- what was planned without it can be planned again.
function G:OnReady(fn)
    listeners[#listeners + 1] = fn
end

-- Seconds from a field's source to a world point (same continent), or nil when it can't be reached.
-- Seconds from a field's source to a world point (same continent), or nil when it can't be reached:
-- the quicker of its two states.
local function Best(f, idx)
    local a, b = f.dist[idx * 2], f.dist[idx * 2 + 1]
    if a and (not b or a <= b) then return f.secs[idx * 2], idx * 2 end
    return b and f.secs[idx * 2 + 1], b and idx * 2 + 1
end

function G:Cost(f, n, w)
    local idx = Square(f.m, n, w)
    return idx and (Best(f, idx))
end

-- The squares from a world point back to the field's source, the way the field reached it:
-- { { n, w, water = true|false, face = a cliff face (no ground), h = height in yards,
-- t = seconds from the source } } in that order.
function G:Path(f, n, w)
    local m, dist, secs = f.m, f.dist, f.secs
    local idx = Square(m, n, w)
    if not idx then return nil end
    local _, node = Best(f, idx)
    if not node then return nil end
    local out = {}
    for _ = 1, 5000 do
        idx = math.floor(node / 2)
        local r, c = math.floor((idx - 1) / m.nc), (idx - 1) % m.nc
        local cn, cw = Center(m, idx)
        local kind = Kind(m, r, c)
        out[#out + 1] = { n = cn, w = cw, water = kind == B_W, face = kind == B_S, h = Height(m, r, c), t = secs[node] }
        if idx == f.src and dist[node] == 0 then return out end
        node = f.from[node]
        if not node then return out end
    end
    return out
end

-- Whether a straight line between two world points stays on squares like where it starts: land
-- (not water, cliffs, lava or off the map), or water when it starts in water.
function G:Clear(continent, n1, w1, n2, w2)
    local m = Map(continent)
    if not m then return true end
    local a, r1, c1 = Square(m, n1, w1)
    local b, r2, c2 = Square(m, n2, w2)
    if not (a and b) then return false end
    local swimming = Kind(m, r1, c1) == B_W
    local steps = math.max(math.abs(r2 - r1), math.abs(c2 - c1))
    local pr, pc = r1, c1
    for i = 1, steps do
        local r = math.floor(r1 + (r2 - r1) * i / steps + 0.5)
        local c = math.floor(c1 + (c2 - c1) * i / steps + 0.5)
        local k = Kind(m, r, c)
        if k == B_V or k == B_H or k == B_S or (k == B_W) ~= swimming then return false end
        local dir = DIRECTION[(r - pr) * 3 + (c - pc)]
        if dir and Step(m, pr, pc, dir, r, c) ~= "walk" then return false end
        -- a step whose way zigzags or goes round: not in a straight line
        if dir and Bend(m, pr, pc, dir) then return false end
        pr, pc = r, c
    end
    return true
end

-- A walking path (points in the order you'd walk them: { n, w, ... }) with the turns of each step
-- that zigzags or goes round put in (the map's bends): { n, w, via = true } between the two
-- squares. The squares' own entries are kept as they are. Only for steering and drawing: a turn
-- can stand in a third square, so it isn't a step of the map's own.
function G:Detail(continent, path)
    local m = path and Map(continent)
    if not (m and m.bends and path[2]) then return path end
    local sub = W.cell / 16
    local out = { path[1] }
    for i = 2, #path do
        local a, b = path[i - 1], path[i]
        local ia, r1, c1 = Square(m, a.n, a.w)
        local ib, r2, c2 = Square(m, b.n, b.w)
        local dir = ia and ib and DIRECTION[(r2 - r1) * 3 + (c2 - c1)]
        local turns = dir and Bend(m, r1, c1, dir)
        if turns then
            local top, left = (r1 + m.r0) * 16, (c1 + m.c0) * 16
            for t = 1, #turns, 2 do
                out[#out + 1] = { n = W.max - (top + turns[t] + 0.5) * sub, w = W.max - (left + turns[t + 1] + 0.5) * sub,
                    via = true, water = false, face = false, h = a.h }
            end
        end
        out[#out + 1] = b
    end
    return out
end

-- The ground's height (yards) at a world point, by the map: its square's average; nil off the map.
function G:Height(continent, n, w)
    local m = Map(continent)
    if not m then return nil end
    local idx, r, c = Square(m, n, w)
    if idx and Kind(m, r, c) ~= B_V then return Height(m, r, c) end
end

-- How a step between two neighbouring squares (world points) goes, the way you'd walk it:
-- "walk", "drop" (and how many yards down), or nil when you can't take it.
function G:Step(continent, n1, w1, n2, w2)
    local m = Map(continent)
    if not m then return "walk", 0 end
    local a, r1, c1 = Square(m, n1, w1)
    local b, r2, c2 = Square(m, n2, w2)
    if not (a and b) then return nil end
    local dir = DIRECTION[(r2 - r1) * 3 + (c2 - c1)]
    if not dir then return a == b and "walk" or nil, 0 end
    return Step(m, r1, c1, dir, r2, c2)
end

-- Overrides for a continent: open = { [key] = true } links to walk, block = { [key] = true } links
-- closed (keys from G:LinkKey). Fields worked out before are dropped.
G.version = 0
function G:SetOverrides(continent, open, block)
    local m = Map(continent)
    if not m then return end
    m.ov = { open = open or {}, block = block or {} }
    m.fallOn = {}
    G.version = G.version + 1
end

-- The roads for a continent: { [key] = true } for each step along one, both ways (keys from
-- G:LinkKey). Steps off them weigh more by a field's offroad (your road preference). Fields worked
-- out before are dropped.
function G:SetRoads(continent, keys)
    local m = Map(continent)
    if not m then return end
    m.roads = keys
    G.version = G.version + 1
end

-- The major cities on a continent, as world rectangles { { n1, w1, n2, w2 } }: in their squares a
-- step off the roads weighs at least weight, whatever a field's own preference (in a city the
-- roads are the way through; the land map doesn't see its buildings). Fields worked out before
-- are dropped.
function G:SetCities(continent, rects, weight)
    local m = Map(continent)
    if not m then return end
    local squares = {}
    for _, rc in ipairs(rects) do
        local n1, n2 = math.max(rc[1], rc[3]), math.min(rc[1], rc[3])
        local w1, w2 = math.max(rc[2], rc[4]), math.min(rc[2], rc[4])
        local r1 = math.max(0, math.floor((W.max - n1) / W.cell) - m.r0)
        local r2 = math.min(m.nr - 1, math.floor((W.max - n2) / W.cell) - m.r0)
        local c1 = math.max(0, math.floor((W.max - w1) / W.cell) - m.c0)
        local c2 = math.min(m.nc - 1, math.floor((W.max - w2) / W.cell) - m.c0)
        for r = r1, r2 do
            for c = c1, c2 do squares[r * m.nc + c + 1] = true end
        end
    end
    m.cities, m.cityOffroad = next(squares) and squares or nil, weight
    G.version = G.version + 1
end

-- The override key for the step between two neighbouring world points (from the first toward the
-- second), and the way back; nil when they aren't neighbouring squares.
function G:LinkKey(continent, n1, w1, n2, w2)
    local m = Map(continent)
    if not m then return nil end
    local a, r1, c1 = Square(m, n1, w1)
    local b, r2, c2 = Square(m, n2, w2)
    if not (a and b) or a == b then return nil end
    local dir = DIRECTION[(r2 - r1) * 3 + (c2 - c1)]
    if not dir then return nil end
    return Key(m, r1, c1, dir), Key(m, r2, c2, OPPOSITE[dir])
end

-- Every override key for the links out of the square at a world point, and into it from its
-- neighbours (a narrow pass opens them all).
function G:SquareKeys(continent, n, w)
    local m = Map(continent)
    if not m then return {} end
    local idx, r, c = Square(m, n, w)
    if not idx then return {} end
    local out = {}
    for k, s in ipairs(STEPS) do
        local rr, cc = r + s[1], c + s[2]
        if rr >= 0 and cc >= 0 and rr < m.nr and cc < m.nc then
            out[#out + 1] = Key(m, r, c, k - 1)
            out[#out + 1] = Key(m, rr, cc, OPPOSITE[k - 1])
        end
    end
    return out
end

-- The override keys of every link between two squares whose centres a wall from (n1, w1) to
-- (n2, w2) runs between (RoadLog's blockers).
function G:CrossingKeys(continent, n1, w1, n2, w2)
    local m = Map(continent)
    if not m then return {} end
    local out = {}
    local function Crosses(an, aw, bn, bw)
        local function Side(pn, pw, qn, qw, xn, xw) return (qn - pn) * (xw - pw) - (qw - pw) * (xn - pn) end
        local d1, d2 = Side(n1, w1, n2, w2, an, aw), Side(n1, w1, n2, w2, bn, bw)
        local d3, d4 = Side(an, aw, bn, bw, n1, w1), Side(an, aw, bn, bw, n2, w2)
        return d1 * d2 < 0 and d3 * d4 < 0
    end
    local _, ra, ca = Square(m, math.max(n1, n2), math.max(w1, w2))
    local _, rb, cb = Square(m, math.min(n1, n2), math.min(w1, w2))
    if not (ra and rb) then return out end
    for r = math.max(0, ra - 1), math.min(m.nr - 1, rb + 1) do
        for c = math.max(0, ca - 1), math.min(m.nc - 1, cb + 1) do
            local an, aw = Center(m, r * m.nc + c + 1)
            for k, s in ipairs(STEPS) do
                local rr, cc = r + s[1], c + s[2]
                if rr >= 0 and cc >= 0 and rr < m.nr and cc < m.nc then
                    local bn, bw = Center(m, rr * m.nc + cc + 1)
                    if Crosses(an, aw, bn, bw) then out[#out + 1] = Key(m, r, c, k - 1) end
                end
            end
        end
    end
    return out
end

G.MOVE = MOVE
G.HARMLESS = HARMLESS

