local _, ns = ...
local WM = ns.WorldMap

-- The planned trip (Route.lua's R:Lines) drawn as a dashed line: on the world map the whole way,
-- on the minimap the part around you as a trail of dots. Each kind of travel has a colour family
-- (walking cyan, flights and rides purple, jumps red, swimming green) of 10 shades; each stage
-- of the plan (a task the arrow follows, a waypoint of your path) takes its own shade, so the legs
-- of a path you dropped stand apart. Walks, swims and jumps follow the land map; flights and
-- rides are drawn straight from stop to stop.
-- Every line sits on a dark casing, so it stands out on the map's tan, green and snow alike; the
-- colours keep clear of the ground's (no yellows or browns).
-- Seeing it shows straight away when the land map has the ground wrong: walk the pass it missed
-- once and it learns it (Route.lua), or mark it in RoadLog.
local Way = {}
ns.WayLine = Way

-- Hue (degrees), saturation and brightness range of each family.
local FAMILIES = {
    cyan = { 175, 215, 0.55, 1.0 },  -- (yellow sank into the map's tan and olive ground)
    purple = { 270, 315, 0.5, 0.9 },
    red = { -12, 18, 0.65, 0.95 },
    green = { 82, 150, 0.55, 0.9 },
}
local FAMILY = { walk = "cyan", fly = "purple", ride = "purple", drop = "red", swim = "green" }
-- The shades in the order stages take them: each is several steps from the one before.
local ORDER = { 0, 5, 2, 7, 4, 9, 1, 6, 3, 8 }

local function HSV(h, s, v)
    h = (h % 360) / 60
    local i, f = math.floor(h), h - math.floor(h)
    local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    if i == 0 then return v, t, p elseif i == 1 then return q, v, p elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v elseif i == 4 then return t, p, v end
    return v, p, q
end

-- PALETTE[family][1..10]: shades running across the family's hues, light and dark alternating.
local PALETTE = {}
for name, f in pairs(FAMILIES) do
    local shades = {}
    for k = 1, 10 do
        local i = ORDER[k]
        local t = i / 9
        local hue = f[1] + (f[2] - f[1]) * t
        local value = (i % 2 == 0) and 1.0 or 0.8
        local r, g, b = HSV(hue, f[3] + (f[4] - f[3]) * (1 - t), value)
        shades[k] = { r, g, b }
    end
    PALETTE[name] = shades
end
Way.PALETTE = PALETTE

-- A line's colour: its kind's family, at its stage's shade.
local function Color(seg)
    if seg.color then return seg.color end -- (a leg after the target: Route.lua's AHEAD_COLORS)
    local shades = PALETTE[FAMILY[seg.kind] or "cyan"]
    return shades[seg.shade or 1] or shades[1]
end
local LINE = 1.5        -- world map: on-screen thickness
local DASH, GAP = 6, 3  -- world map: on-screen dash and gap lengths (fine, so the route's bends show)
local CASING = { 0.04, 0.07, 0.16 } -- the thin dark edge under the dashes (a deep navy, not black)
local CASING_WIDTH = 1.8            -- times LINE
local CASING_ALPHA = 0.55
local CHECK = 0.2      -- seconds between looks at whether to redraw (only when something changed)
local DOT = 5          -- minimap: dot size
local DOTS = 120       -- minimap: dots at most
local MINI_UPDATE = 0.1

local function Lines()
    if ns.Targets and ns.Targets.inArea then return nil end -- in the quest's area: nothing to follow
    return ns.Route and ns.Route:Lines()
end

-- A leg's points, starting on you this moment for the leg you're on: the plan's start is where you
-- stood when it was made, up to a second ago, and its next point the middle of a map cell a few
-- yards to one side of you.
local ON_LEG = 60       -- yards from a leg's start you can be for it to be the one you're on
local NEAR_START = 12   -- points this close to you are left out
local function FromYou(trip, seg)
    local pts = seg.pts
    if seg ~= trip[1] or (seg.kind ~= "walk" and seg.kind ~= "swim") or #pts < 4 then return pts end
    local c, n, w = ns.Nav:Player()
    if c ~= seg.continent or (pts[1] - n) ^ 2 + (pts[2] - w) ^ 2 > ON_LEG * ON_LEG then return pts end
    local first = 3
    while first + 2 < #pts and (pts[first] - n) ^ 2 + (pts[first + 1] - w) ^ 2 < NEAR_START * NEAR_START do
        first = first + 2
    end
    local out = { n, w }
    for i = first, #pts do out[#out + 1] = pts[i] end
    return out
end

-- What a trip looks like, as a short string: its legs' kinds and shades, their points to the yard.
-- Route.lua makes a new trip each time it plans (about once a second), most often the same as the
-- one before: the maps are redrawn only when this changes.
local function Signature(trip)
    if not trip then return "" end
    local parts = {}
    for _, seg in ipairs(trip) do
        local pts, sum = seg.pts, 0
        for i = 1, #pts do sum = (sum * 31 + math.floor(pts[i])) % 1000000007 end
        parts[#parts + 1] = (seg.kind or "") .. (seg.shade or 0) .. ":" .. seg.continent .. ":" .. #pts .. ":" .. sum
    end
    return table.concat(parts, "|")
end

-- ---------------------------------------------------------------------------------------------
-- World map
-- ---------------------------------------------------------------------------------------------

local layer -- the shared WorldMap.lua layer (below)

-- A world point on mapID, as 0-1 fractions (nil off it, with a little slack). On OpenMap's
-- stitched map the view runs past mapID's own rectangle: there OpenMap says where the point is on
-- the canvas, past 0-1 too.
local function Project(continent, n, w, mapID) return WM.WorldOnCanvas(continent, n, w, mapID, 0.05) end

-- The trip as dashes (fine, so the route's bends show), on the layer's line frame at +2050.
-- Hovering the line: what that stretch is for. An addon's entry says, in info (its target's) and in
-- each `ahead` stop's: { { title, detail, why }, ... }. Without them, the target's own title.
local HOVER_MAP = 7      -- pixels from the line on the world map
local HOVER_MINI = 8     -- pixels from a dot on the minimap
local HOVER_EVERY = 0.1  -- seconds between looks, while the cursor is over a map
local tipOwner, tipSeg

local function Length(pts)
    local yards = 0
    for i = 3, #pts - 1, 2 do
        yards = yards + math.sqrt((pts[i] - pts[i - 2]) ^ 2 + (pts[i + 1] - pts[i - 1]) ^ 2)
    end
    return yards
end

local function ShowTip(owner, seg)
    if tipOwner == owner and tipSeg == seg then return end
    -- (Someone else's tooltip, a quest pin's say, comes first.)
    if GameTooltip:IsShown() and not GameTooltip:IsOwned(owner) then return end
    local e = ns.Targets and ns.Targets.current
    local info = seg.stop and seg.stop.info or (e and e.info)
    local col = seg.color or { 0.4, 0.9, 0.9 }
    GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(seg.number and ("Then, stop " .. seg.number) or "On your way now", col[1], col[2], col[3])
    if type(info) == "table" and info[1] then
        for _, line in ipairs(info) do
            GameTooltip:AddLine(line.title, 1, 1, 1, true)
            if line.detail and line.detail ~= "" then GameTooltip:AddLine(line.detail, 0.75, 0.8, 0.85, true) end
            if line.why then GameTooltip:AddLine(line.why, 0.6, 0.85, 0.6, true) end
        end
    elseif e and e.title then
        GameTooltip:AddLine(e.title, 1, 1, 1, true)
        if e.subtitle then GameTooltip:AddLine(e.subtitle, 0.75, 0.8, 0.85, true) end
    end
    local yards = Length(seg.pts)
    GameTooltip:AddLine(("%s, about %s on foot"):format(ns.Nav.Distance(yards), ns.Nav.ETA(yards)), 0.75, 0.8, 0.85)
    GameTooltip:Show()
    tipOwner, tipSeg = owner, seg
end

local function HideTip()
    if tipOwner and GameTooltip:IsOwned(tipOwner) then GameTooltip:Hide() end
    tipOwner, tipSeg = nil, nil
end

-- The stretch of line nearest x, y (runs: { { seg, { x, y, ... } }, ... }, in the same units) within
-- reach, or nil.
local function NearestLine(runs, x, y, reach)
    local best, bestD = nil, reach * reach
    for _, run in ipairs(runs) do
        local xy = run[2]
        for i = 3, #xy - 1, 2 do
            local x0, y0, x1, y1 = xy[i - 2], xy[i - 1], xy[i], xy[i + 1]
            local dx, dy = x1 - x0, y1 - y0
            local len = dx * dx + dy * dy
            local t = len > 0 and math.max(0, math.min(1, ((x - x0) * dx + (y - y0) * dy) / len)) or 0
            local px, py = x0 + t * dx - x, y0 + t * dy - y
            local d = px * px + py * py
            if d < bestD then best, bestD = run[1], d end
        end
    end
    return best
end
Way.NearestLine = NearestLine -- (for tests)

local mapRuns = {} -- what's drawn on the world map: { { seg, { x, y, ... } in canvas fractions }, ... }

local AHEAD_ALPHA = 0.85 -- the legs after the target: a little fainter, what's expected, not what's on

local function Refresh(l, mapID, ahead)
    wipe(mapRuns)
    if not (ns.db and ns.db.showWay and l:CanDrawLines()) then return end
    local trip, faint = {}, {}
    for _, seg in ipairs(Lines() or {}) do trip[#trip + 1] = seg end
    for _, seg in ipairs(ahead or {}) do
        faint[seg] = true
        trip[#trip + 1] = seg
    end
    for _, seg in ipairs(trip) do
        local run
        local function Flush()
            if run and #run >= 4 then
                -- The edge at ARTWORK sublevel 0, the dashes at 1: always under them.
                for i = 3, #run - 1, 2 do
                    l:Line(run[i - 2], run[i - 1], run[i], run[i + 1], CASING, LINE * CASING_WIDTH,
                        CASING_ALPHA * (faint[seg] and AHEAD_ALPHA or 1), 0)
                end
                l:Dashed(run, Color(seg), LINE, DASH, GAP, faint[seg] and AHEAD_ALPHA or 1, 1)
                mapRuns[#mapRuns + 1] = { seg, run }
            end
            run = nil
        end
        local pts = FromYou(trip, seg)
        for i = 1, #pts - 1, 2 do
            local x, y = Project(seg.continent, pts[i], pts[i + 1], mapID)
            if x then
                run = run or {}
                run[#run + 1], run[#run + 2] = x, y
            else
                Flush() -- off this map: the line breaks there
            end
        end
        Flush()
    end
end

-- Redrawn when the map, its zoom or its visibility changes, when the trip changes or you've moved
-- MOVED yards (looked at every CHECK seconds while the map is open: Signature), and when OpenMap
-- switches between its stitched map and Blizzard's (the line, the pins and the town badges go
-- somewhere else, at other levels).
local MOVED = 2
local drawnSig, drawnAhead, drawnN, drawnW
local function Ahead() return ns.Route and ns.db and ns.db.showWay and ns.Route:AheadLines() or nil end
local function Moved()
    local _, n, w = ns.Nav:Player()
    if not (n and drawnN) then return n ~= nil end
    return (n - drawnN) ^ 2 + (w - drawnW) ^ 2 >= MOVED * MOVED
end
layer = WM.NewLayer({
    lines = true, level = 2050,
    refresh = function(l, mapID)
        drawnSig = Signature(Lines())
        local ahead = Ahead()
        drawnAhead = Signature(ahead)
        drawnN, drawnW = select(2, ns.Nav:Player())
        Refresh(l, mapID, ahead)
    end,
    interval = CHECK,
    every = function(l)
        if Signature(Lines()) ~= drawnSig or Signature(Ahead()) ~= drawnAhead or Moved() then l:Refresh() end
    end,
    onStitched = function(l) l:Refresh(); ns:Changed() end,
})
Way.layer = layer

function Way:Refresh()
    if ns.db then layer:Refresh() end
end

-- ---------------------------------------------------------------------------------------------
-- Minimap: the part of the trip around you, as dots
-- ---------------------------------------------------------------------------------------------

local dots, shownDots = {}, 0

local function GetDot(i)
    local dot = dots[i]
    if not dot then
        dot = Minimap:CreateTexture(nil, "OVERLAY")
        dot:SetTexture("Interface\\COMMON\\Indicator-Gray")
        dot:SetSize(DOT, DOT)
        dots[i] = dot
    end
    return dot
end

-- The dots are placed again only when something they depend on changed: where you are (to a
-- quarter yard), which way the minimap faces, its zoom, size and shape, or the trip.
local placedKey

local function UpdateMinimap()
    if not Minimap then return end
    local count = 0
    local trip = ns.db and ns.db.showWayMinimap and not ns:InBattleground() and Lines()
    -- What the minimap shows (shared WorldMap.lua): its zoom, indoors or out, turning with you or
    -- not, round or square, and where you are.
    local v = trip and WM.MinimapView()
    local c = v and v.continent
    local key = v and c and table.concat({ c, math.floor(v.n * 4), math.floor(v.w * 4), v.radius, v.half,
        v.rotate and math.floor((v.sin or 0) * 500) or 0, v.rotate and math.floor((v.cos or 0) * 500) or 0,
        v.square and 1 or 0, Signature(trip) }, ",") or ""
    if key == placedKey then return end
    placedKey = key
    if trip and c then
        local spacing = v.radius / 10
        local placing
        local edge = v.radius * 0.95
        local function Place(pn, pw, col)
            local px, py, inside = v:PlaceWorld(c, pn, pw, nil, edge)
            if not inside or count >= DOTS then return end
            count = count + 1
            local dot = GetDot(count)
            dot.at = { seg = placing, x = px, y = py }
            dot:SetVertexColor(col[1], col[2], col[3], 0.95)
            dot:ClearAllPoints()
            dot:SetPoint("CENTER", Minimap, "CENTER", px, py)
            dot:Show()
        end
        for _, seg in ipairs(trip) do
            if seg.continent == c then
                local col = Color(seg)
                placing = seg
                local carry = 0
                local pts = FromYou(trip, seg)
                for i = 3, #pts - 1, 2 do
                    local n0, w0, n1, w1 = pts[i - 2], pts[i - 1], pts[i], pts[i + 1]
                    local len = math.sqrt((n1 - n0) ^ 2 + (w1 - w0) ^ 2)
                    local at = carry
                    while at < len do
                        local f = at / len
                        Place(n0 + (n1 - n0) * f, w0 + (w1 - w0) * f, col)
                        at = at + spacing
                    end
                    carry = at - len
                end
            end
        end
    end
    for i = count + 1, shownDots do dots[i]:Hide() end
    shownDots = count
end

-- Hovering: the nearest stretch of line under the cursor, on either map.
local function HoverMinimap()
    local mx, my = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = Minimap:GetCenter()
    if not (cx and scale and scale > 0) then return nil end
    local x, y = mx / scale - cx, my / scale - cy
    local best, bestD = nil, HOVER_MINI * HOVER_MINI
    for i = 1, shownDots do
        local at = dots[i].at
        local d = at and (at.x - x) ^ 2 + (at.y - y) ^ 2
        if d and d < bestD then best, bestD = at.seg, d end
    end
    return best
end

local function HoverMap()
    local l = layer
    local x, y = WorldMapFrame:GetNormalizedCursorPosition()
    if not (x and l.w and l.w > 0 and mapRuns[1]) then return nil end
    -- (In pixels of the map, so a tall map reaches as far up as across.)
    local runs = {}
    for k, run in ipairs(mapRuns) do
        local xy, out = run[2], {}
        for i = 1, #xy - 1, 2 do out[i], out[i + 1] = xy[i] * l.w, xy[i + 1] * l.h end
        runs[k] = { run[1], out }
    end
    return NearestLine(runs, x * l.w, y * l.h, HOVER_MAP * (l.scale or 1))
end

local function UpdateHover()
    if Minimap and Minimap:IsShown() and Minimap:IsMouseOver() then
        local seg = HoverMinimap()
        if seg then return ShowTip(Minimap, seg) end
    elseif WorldMapFrame and WorldMapFrame:IsShown() and layer.frame and WorldMapFrame:IsMouseOver() then
        local seg = HoverMap()
        if seg then return ShowTip(layer.frame, seg) end
    end
    if tipOwner then HideTip() end
end

-- The minimap's dots follow you; the world map's line has its own layer (above).
ns:On("PLAYER_LOGIN", function()
    local miniAcc, hoverAcc = 0, 0
    CreateFrame("Frame"):SetScript("OnUpdate", function(_, elapsed)
        hoverAcc = hoverAcc + elapsed
        if hoverAcc >= HOVER_EVERY then
            hoverAcc = 0
            UpdateHover()
        end
        miniAcc = miniAcc + elapsed
        if miniAcc >= MINI_UPDATE then
            miniAcc = 0
            UpdateMinimap()
        end
    end)
end)
