local _, ns = ...
local WM = ns.WorldMap

-- The planned trip (Route.lua's R:Lines) drawn as a dashed line: on the world map the whole way,
-- on the minimap the part around you as a trail of dots. Each kind of travel has a colour family
-- (walking yellow, flights and rides purple, jumps red, swimming green) of 10 shades; each stage
-- of the plan (a task the arrow follows, a waypoint of your path) takes its own shade, so the legs
-- of a path you dropped stand apart. Walks, swims and jumps follow the land map; flights and
-- rides are drawn straight from stop to stop.
-- Seeing it shows straight away when the land map has the ground wrong: walk the pass it missed
-- once and it learns it (Route.lua), or mark it in RoadLog.
local Way = {}
ns.WayLine = Way

-- Hue (degrees), saturation and brightness range of each family.
local FAMILIES = {
    yellow = { 38, 64, 0.65, 1.0 },
    purple = { 252, 302, 0.45, 0.85 },
    red = { -12, 18, 0.65, 0.95 },
    green = { 82, 150, 0.55, 0.9 },
}
local FAMILY = { walk = "yellow", fly = "purple", ride = "purple", drop = "red", swim = "green" }
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
        local value = (i % 2 == 0) and 1.0 or 0.72
        local r, g, b = HSV(hue, f[3] + (f[4] - f[3]) * (1 - t), value)
        shades[k] = { r, g, b }
    end
    PALETTE[name] = shades
end
Way.PALETTE = PALETTE

-- A line's colour: its kind's family, at its stage's shade.
local function Color(seg)
    local shades = PALETTE[FAMILY[seg.kind] or "yellow"]
    return shades[seg.shade or 1] or shades[1]
end
local LINE = 2.25       -- world map: on-screen thickness
local DASH, GAP = 4, 2  -- world map: on-screen dash and gap lengths (fine, so the route's bends show)
local REFRESH = 1      -- world map: seconds between redraws while it's open
local DOT = 5          -- minimap: dot size
local DOTS = 120       -- minimap: dots at most
local MINI_UPDATE = 0.1

local function Lines()
    return ns.Route and ns.Route:Lines()
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
local function Refresh(l, mapID)
    local trip = ns.db and ns.db.showWay and Lines()
    if not (trip and l:CanDrawLines()) then return end
    for _, seg in ipairs(trip) do
        local run
        local function Flush()
            if run and #run >= 4 then l:Dashed(run, Color(seg), LINE, DASH, GAP, 0.9) end
            run = nil
        end
        for i = 1, #seg.pts - 1, 2 do
            local x, y = Project(seg.continent, seg.pts[i], seg.pts[i + 1], mapID)
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

-- Redrawn when the map, its zoom or its visibility changes, every REFRESH seconds while it's open,
-- and when OpenMap switches between its stitched map and Blizzard's (the line, the pins and the
-- town badges go somewhere else, at other levels).
layer = WM.NewLayer({
    lines = true, level = 2050, refresh = Refresh, interval = REFRESH,
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

local function UpdateMinimap()
    if not Minimap then return end
    local count = 0
    local trip = ns.db and ns.db.showWayMinimap and not ns:InBattleground() and Lines()
    -- What the minimap shows (shared WorldMap.lua): its zoom, indoors or out, turning with you or
    -- not, round or square, and where you are.
    local v = trip and WM.MinimapView()
    local c = v and v.continent
    if trip and c then
        local spacing = v.radius / 10
        local edge = v.radius * 0.95
        local function Place(pn, pw, col)
            local px, py, inside = v:PlaceWorld(c, pn, pw, nil, edge)
            if not inside or count >= DOTS then return end
            count = count + 1
            local dot = GetDot(count)
            dot:SetVertexColor(col[1], col[2], col[3], 0.95)
            dot:ClearAllPoints()
            dot:SetPoint("CENTER", Minimap, "CENTER", px, py)
            dot:Show()
        end
        for _, seg in ipairs(trip) do
            if seg.continent == c then
                local col = Color(seg)
                local carry = 0
                for i = 3, #seg.pts - 1, 2 do
                    local n0, w0, n1, w1 = seg.pts[i - 2], seg.pts[i - 1], seg.pts[i], seg.pts[i + 1]
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

-- The minimap's dots follow you; the world map's line has its own layer (above).
ns:On("PLAYER_LOGIN", function()
    local miniAcc = 0
    CreateFrame("Frame"):SetScript("OnUpdate", function(_, elapsed)
        miniAcc = miniAcc + elapsed
        if miniAcc >= MINI_UPDATE then
            miniAcc = 0
            UpdateMinimap()
        end
    end)
end)
