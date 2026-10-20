local _, ns = ...

-- Caves: the heights along the caves you logged. The game doesn't tell addons your height, so
-- they're worked out after the fact: tools/RoadLog/build_caves.py (yarn build --dev) reads your
-- logged cave stretches, finds the cave's floors in the game files and follows the one you were on
-- from point to point (levels over each other stay apart, falls you took allow the drops), and
-- writes Data/Caves.lua:
--   ns.CaveMap = { [continent] = { [at] = { z = { height per point, yards }, lo = lowest, hi = highest } } }
-- keyed by each logged stretch's time (at). A stretch logged since the last build has no heights
-- yet.
local Caves = {}
ns.Caves = Caves

local NEAR = 4      -- yards: a logged point this close counts as where you are
local APART = 3     -- yards: heights further apart than this at one spot are different levels

-- The built heights for a logged cave stretch, or nil.
function Caves:Heights(continent, seg)
    local byAt = ns.CaveMap and ns.CaveMap[continent]
    local built = byAt and seg.at and byAt[seg.at]
    if built and built.z and #built.z * 2 == #seg.pts then return built.z end
end

-- Your height from the cave map where you are: yards, or nil when no built cave stretch passes
-- within NEAR yards. Where levels cross, the one nearest the height you were last seen at wins.
function Caves:HeightAt(continent, n, w)
    local best, bestD
    for _, seg in ipairs(ns.db.caves[continent] or {}) do
        local z = self:Heights(continent, seg)
        if z then
            local pts = seg.pts
            for i = 1, #pts - 1, 2 do
                local dn, dw = pts[i] - n, pts[i + 1] - w
                local d = dn * dn + dw * dw
                if d <= NEAR * NEAR then
                    local h = z[(i + 1) / 2]
                    -- distance, plus the jump from the last height when it's another level
                    local cost = d + ((self.last and math.abs(h - self.last) > APART) and 10000 or 0)
                    if not bestD or cost < bestD then best, bestD = h, cost end
                end
            end
        end
    end
    if best then self.last = best end
    return best
end

-- Cave stretches logged, and how many of them have heights.
function Caves:Counts()
    local all, built = 0, 0
    for continent, segs in pairs(ns.db.caves) do
        for _, seg in ipairs(segs) do
            all = all + 1
            if self:Heights(continent, seg) then built = built + 1 end
        end
    end
    return all, built
end

-- The minimap button's tooltip: your height in a mapped cave, and what's waiting for a build.
function Caves:AddTooltip(tt)
    local all, built = self:Counts()
    local continent, n, w = ns.Nav:Player()
    local h = continent and self:HeightAt(continent, n, w)
    if h then
        tt:AddLine(("Height here: %d yd (cave map)"):format(math.floor(h + 0.5)), 0.45, 0.85, 0.9)
    elseif ns.db.mode == "cave" then
        tt:AddLine("Height here: worked out after the next build", 0.6, 0.6, 0.6)
    end
    if all > built then
        tt:AddLine(("%d cave stretch%s waiting for heights (yarn build --dev)"):format(all - built, all - built == 1 and "" or "es"),
            0.6, 0.6, 0.6)
    end
end
