local _, ns = ...
local C, M = ns.Compat, ns.Media

-- Combo points (and Holy Power, Chi, Soul Shards, Arcane Charges, Essence where they exist) as
-- flat pips under your target's plate.
local Combo = { name = "ComboPoints" }

local _, CLASS = UnitClass("player")
local PT = Enum and Enum.PowerType or {}
local POWER_BY_CLASS = {
    ROGUE = PT.ComboPoints or 4,
    DRUID = PT.ComboPoints or 4,
    PALADIN = PT.HolyPower,
    MONK = PT.Chi,
    WARLOCK = PT.SoulShards,
    MAGE = PT.ArcaneCharges,
    EVOKER = PT.Essence,
}
local COLORS = {
    [PT.ComboPoints or 4] = { 1.00, 0.82, 0.20 },
    [PT.HolyPower or -1] = { 0.95, 0.90, 0.60 },
    [PT.Chi or -2] = { 0.40, 0.95, 0.75 },
    [PT.SoulShards or -3] = { 0.70, 0.45, 0.95 },
    [PT.ArcaneCharges or -4] = { 0.40, 0.60, 1.00 },
    [PT.Essence or -5] = { 0.30, 0.85, 0.85 },
}
local powerType = POWER_BY_CLASS[CLASS]
local current -- plate showing the pips

local function Points()
    -- Classic keeps combo points on the target; Retail keeps them on the player.
    if powerType == (PT.ComboPoints or 4) and GetComboPoints and not C.IS_MAINLINE then
        local max = C.Num(UnitPowerMax("player", powerType)) or 0
        return GetComboPoints("player", "target") or 0, max > 0 and max or 5
    end
    local cur, max = C.Num(UnitPower("player", powerType)), C.Num(UnitPowerMax("player", powerType))
    return cur or 0, max or 0
end

function Combo:Create(f)
    local box = CreateFrame("Frame", nil, f)
    box:SetSize(1, 6)
    box.pips = {}
    box:Hide()
    f.combo = box
end

local function Show(f)
    local box = f.combo
    if not powerType then return box:Hide() end
    local cur, max = Points()
    local ok = powerType and ns.db.widgets.comboPoints and max > 0 and f.unit.style == "normal" and f.unit.canAttack
    -- Combo points show whenever you have some; other resources only in combat.
    if ok and powerType ~= (PT.ComboPoints or 4) and not InCombatLockdown() then ok = false end
    if ok and powerType == (PT.ComboPoints or 4) and cur == 0 then ok = false end
    if not ok then return box:Hide() end
    local width = f.barW or ns.db.general.width
    local gap = 2
    local size = math.floor((width - gap * (max - 1)) / max)
    local c = COLORS[powerType] or M.ACCENT
    for i = 1, max do
        local pip = box.pips[i]
        if not pip then
            pip = CreateFrame("Frame", nil, box, "BackdropTemplate")
            M.Backdrop(pip)
            pip.fill = pip:CreateTexture(nil, "ARTWORK")
            pip.fill:SetPoint("TOPLEFT", 1, -1); pip.fill:SetPoint("BOTTOMRIGHT", -1, 1)
            box.pips[i] = pip
        end
        pip:SetSize(size, 5)
        pip:ClearAllPoints()
        pip:SetPoint("LEFT", box, "LEFT", (i - 1) * (size + gap), 0)
        pip.fill:SetColorTexture(c[1], c[2], c[3], 1)
        pip.fill:SetShown(i <= cur)
        pip:Show()
    end
    for i = max + 1, #box.pips do box.pips[i]:Hide() end
    box:ClearAllPoints()
    local below = (ns.db.castbar.enabled and (ns.db.castbar.height + 6) or 3) + ns.Plates:BelowBar(f)
    box:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -below)
    box:SetSize(width, 5)
    box:Show()
end

function Combo:Refresh()
    if current then current.combo:Hide(); current = nil end
    if not powerType then return end
    local f
    ns.Plates:Each(function(p) if p.unit.isTarget then f = p end end)
    if f and f.active then
        current = f
        Show(f)
    end
end

function Combo:Update(f)
    if f.unit.isTarget then current = f; Show(f) else f.combo:Hide() end
end

function Combo:Clear(f)
    f.combo:Hide()
    if current == f then current = nil end
end

ns.Plates:Register(Combo)

local function Refresh() Combo:Refresh() end
ns:Listen("TargetChanged", Refresh)
ns:On("UNIT_POWER_UPDATE", function(unit) if unit == "player" then Refresh() end end)
ns:On("UNIT_POWER_FREQUENT", function(unit) if unit == "player" then Refresh() end end)
ns:On("UNIT_MAXPOWER", function(unit) if unit == "player" then Refresh() end end)
ns:On("PLAYER_TARGET_CHANGED", Refresh)
ns:On("PLAYER_REGEN_ENABLED", Refresh)
ns:On("PLAYER_REGEN_DISABLED", Refresh)
