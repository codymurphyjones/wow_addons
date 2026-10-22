local _, ns = ...
local WM = ns.WorldMap

-- One dot on the minimap for the point the arrow aims at, on the rim when it's out of range.
-- Distance in yards is turned into minimap pixels with HereBeDragons' zoom tables (the shared
-- WorldMap.lua's minimap view).
local MP = {}
ns.MinimapPin = MP

local SIZE = 14
local UPDATE = 0.1
local VIEW = { square = false }

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

local function Update()
    if not Minimap then return end
    if not pin then Build() end
    if ns:InBattleground() then pin:Hide() return end
    local p = ns.Targets.point
    if p and ns.Flight then p = ns.Flight:Aim(p) end
    -- The minimap now; round, as the pin always was (a square minimap still clamps to a circle).
    local v = WM.MinimapView(VIEW)
    local continent = v.continent
    local pc, pn, pw
    if p and continent then pc, pn, pw = ns.Nav:World(p) end
    if not (pc and pc == continent) then
        pin:Hide()
        return
    end
    if v.rotate and not v.known then pin:Hide() return end -- it turns with you, but which way you face is hidden
    local px, py, inside = v:PlaceWorld(pc, pn, pw, 4) -- out of range: on the rim, 4 pixels in
    local onRim = not inside
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
