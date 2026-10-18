local _, ns = ...
local C, M = ns.Compat, ns.Media

-- Your experience as a thin bar under your target's plate, with rested XP shaded. Off by default.
local XP = { name = "Experience" }

function XP:Create(f)
    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetStatusBarTexture(M.BAR)
    bar:SetStatusBarColor(0.58, 0.30, 0.85, 1)
    bar:SetHeight(4)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints(); bar.bg:SetColorTexture(M.BAR_BG[1], M.BAR_BG[2], M.BAR_BG[3], 0.9)
    bar.rested = bar:CreateTexture(nil, "BORDER")
    bar.rested:SetColorTexture(0.25, 0.45, 0.95, 0.6)
    bar.border = M.Border(bar, "OVERLAY")
    bar:Hide()
    f.xp = bar
end

local function MaxLevel()
    if GetMaxLevelForPlayerExpansion then return GetMaxLevelForPlayerExpansion() end
    if GetMaxPlayerLevel then return GetMaxPlayerLevel() end
    return MAX_PLAYER_LEVEL or 60
end

function XP:Update(f)
    local bar = f.xp
    if not ns.db.widgets.experience or not f.unit.isTarget or f.unit.style ~= "normal" or UnitLevel("player") >= MaxLevel() then
        return bar:Hide()
    end
    bar:SetStatusBarTexture(M.BarTexture())
    local cur, max = UnitXP("player"), UnitXPMax("player")
    if not max or max <= 0 then return bar:Hide() end
    bar:SetMinMaxValues(0, max)
    bar:SetValue(cur)
    local rested = GetXPExhaustion() or 0
    local width = f.barW or ns.db.general.width
    local x = width * cur / max
    local w = math.min(width - x, width * rested / max)
    bar.rested:ClearAllPoints()
    bar.rested:SetPoint("TOPLEFT", bar, "TOPLEFT", x, 0)
    bar.rested:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, 0)
    bar.rested:SetWidth(math.max(0.01, w))
    bar.rested:SetShown(w >= 1)
    bar:ClearAllPoints()
    local below = (ns.db.castbar.enabled and (ns.db.castbar.height + 6) or 3) + (f.combo and f.combo:IsShown() and 8 or 0)
        + ns.Plates:BelowBar(f)
    bar:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -below)
    bar:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -below)
    bar:Show()
end

function XP:Clear(f) f.xp:Hide() end

ns.Plates:Register(XP)

local function Refresh() ns.Plates:Each(function(f) XP:Update(f) end) end
ns:Listen("TargetChanged", Refresh)
ns:On("PLAYER_XP_UPDATE", Refresh)
ns:On("UPDATE_EXHAUSTION", Refresh)
