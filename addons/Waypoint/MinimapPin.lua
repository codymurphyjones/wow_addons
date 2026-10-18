local _, ns = ...
local C = ns.Compat

-- One dot on the minimap for the point the arrow aims at, on the rim when it's out of range.
-- Distance in yards is turned into minimap pixels with HereBeDragons' zoom tables (from
-- WealthPlanner's MinimapPins.lua).
local MP = {}
ns.MinimapPin = MP

local SIZE = 14
local UPDATE = 0.1

-- Minimap diameter in yards at each zoom level.
local OUTDOOR = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }
local INDOOR = { [0] = 300, 240, 180, 120, 80, 50 }

local pin

local function Build()
    pin = CreateFrame("Frame", nil, Minimap)
    pin:SetSize(SIZE, SIZE)
    pin:SetFrameStrata("MEDIUM"); pin:SetFrameLevel(Minimap:GetFrameLevel() + 6)
    pin.glow = pin:CreateTexture(nil, "BACKGROUND")
    pin.glow:SetPoint("CENTER"); pin.glow:SetSize(SIZE * 2, SIZE * 2)
    pin.glow:SetTexture("Interface\\Cooldown\\star4"); pin.glow:SetBlendMode("ADD")
    pin.glow:SetVertexColor(1, 0.79, 0.3, 0.7)
    pin.dot = pin:CreateTexture(nil, "ARTWORK"); pin.dot:SetAllPoints()
    pin.dot:SetTexture("Interface\\COMMON\\Indicator-Gray"); pin.dot:SetVertexColor(1, 0.79, 0.3)
    pin:Hide()
end

local function Radius()
    local zoom = Minimap:GetZoom() or 0
    local t = (IsIndoors and IsIndoors()) and INDOOR or OUTDOOR
    return (t[zoom] or t[0]) / 2
end

local function Update()
    if not Minimap then return end
    if not pin then Build() end
    if ns:InBattleground() then pin:Hide() return end
    local p = ns.Targets.point
    if p and ns.Flight then p = ns.Flight:Aim(p) end
    local continent, n, w = ns.Nav:Player()
    local pc, pn, pw
    if p and continent then pc, pn, pw = ns.Nav:World(p) end
    if not (pc and pc == continent) then
        pin:Hide()
        return
    end
    local x, y = w - pw, n - pn -- yards east, yards south
    local rotate = GetCVar and GetCVar("rotateMinimap") == "1"
    if rotate then
        local facing = GetPlayerFacing and C.Num(GetPlayerFacing())
        if not facing then pin:Hide() return end
        local sin, cos = math.sin(facing), math.cos(facing)
        x, y = x * cos - y * sin, x * sin + y * cos
    end
    local radius, half = Radius(), Minimap:GetWidth() / 2
    local len = math.sqrt(x * x + y * y)
    local px, py = x / radius * half, -y / radius * half
    local onRim = len > radius
    if onRim and len > 0 then
        px, py = x / len * (half - 4), -y / len * (half - 4)
    end
    local col = ns:ColorOf(ns.Targets.current)
    pin.glow:SetVertexColor(col[1], col[2], col[3], 0.7); pin.dot:SetVertexColor(col[1], col[2], col[3])
    pin.glow:SetShown(not onRim)
    pin:SetAlpha(onRim and 0.8 or 1)
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", Minimap, "CENTER", px, py)
    pin:Show()
end

local acc = 0
CreateFrame("Frame"):SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < UPDATE then return end
    acc = 0
    if ns.db then Update() end
end)
