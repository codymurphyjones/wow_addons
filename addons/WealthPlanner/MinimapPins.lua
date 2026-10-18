local _, ns = ...

-- The tracked job's spots on the minimap, coloured like the world map dots. Spots off the edge of
-- the minimap are left out (the Waypoint addon's dot shows the way to the next one).
local MP = {}
ns.MinimapPins = MP

local SIZE = 8
local MAX_PINS = 60
local UPDATE = 0.1
local T = ns.Widgets.Theme

-- Minimap diameter in yards at each zoom level (HereBeDragons' table).
local OUTDOOR = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }
local INDOOR = { [0] = 300, 240, 180, 120, 80, 50 }

local pool = {}

local function Pin(i)
    local p = pool[i]
    if not p then
        p = CreateFrame("Frame", nil, Minimap)
        p:SetSize(SIZE, SIZE); p:SetFrameStrata("MEDIUM"); p:SetFrameLevel(Minimap:GetFrameLevel() + 5)
        p.border = p:CreateTexture(nil, "BACKGROUND"); p.border:SetPoint("TOPLEFT", -1, 1); p.border:SetPoint("BOTTOMRIGHT", 1, -1)
        p.border:SetColorTexture(0, 0, 0, 0.9)
        p.dot = p:CreateTexture(nil, "ARTWORK"); p.dot:SetAllPoints()
        pool[i] = p
    end
    return p
end

local function HideFrom(i)
    for k = i, #pool do pool[k]:Hide() end
end

local function Radius()
    local zoom = Minimap:GetZoom() or 0
    local t = (IsIndoors and IsIndoors()) and INDOOR or OUTDOOR
    return (t[zoom] or t[0]) / 2
end

local function Update()
    if not (ns.db and ns.db.options.minimapPins and ns.Nav:Job()) then return HideFrom(1) end
    local radius = Radius()
    local half = Minimap:GetWidth() / 2
    local rotate = GetCVar and GetCVar("rotateMinimap") == "1"
    local facing = rotate and GetPlayerFacing and GetPlayerFacing() or 0
    local sin, cos = math.sin(facing), math.cos(facing)
    local n = 0
    for _, a in ipairs(ns.Nav:Around(radius * 1.05)) do
        if n >= MAX_PINS then break end
        local s, x, y = a[1], a[2], a[3]
        if rotate then x, y = x * cos - y * sin, x * sin + y * cos end
        n = n + 1
        local p = Pin(n)
        local col = T.series[((s.index or 1) - 1) % #T.series + 1]
        p.dot:SetColorTexture(col[1], col[2], col[3], 1)
        p:SetAlpha(1)
        p:ClearAllPoints(); p:SetPoint("CENTER", Minimap, "CENTER", x / radius * half, -y / radius * half)
        p:Show()
    end
    HideFrom(n + 1)
end

local ticker = CreateFrame("Frame")
local acc = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < UPDATE then return end
    acc = 0
    Update()
end)
