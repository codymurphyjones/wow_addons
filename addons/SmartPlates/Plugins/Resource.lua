local _, ns = ...
local C, M = ns.Compat, ns.Media

-- Power (mana, rage, energy...) as a thin bar under every healthbar, a quarter of the healthbar's
-- height. Elements below the healthbar (castbar, combo pips, XP) leave room for it via
-- ns.Plates:BelowBar(f). Hidden values (WoW Forever, Midnight) go straight to the bar.
local Resource = { name = "Resource" }
ns.Resource = Resource

local MANA = { r = 0.30, g = 0.50, b = 1.00 }

-- Height of the power bar for this plate, or 0 when it has none. Called by Plate.lua before the
-- elements update, so everything below the healthbar is laid out with it.
function Resource:Height(f)
    local u = f.unit
    if not ns.db.widgets.resource or u.style ~= "normal" or not u.unitid then return 0 end
    local ok, max = pcall(UnitPowerMax, u.unitid)
    if not ok then return 0 end
    -- A hidden maximum still has a bar worth showing; a readable 0 means the unit has no power.
    if not C.IsSecret(max) and (not max or max <= 0) then return 0 end
    return math.max(1, math.floor((f.barH or ns.db.general.height) / 4 + 0.5))
end

function Resource:Create(f)
    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetStatusBarTexture(M.BAR)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints(); bar.bg:SetColorTexture(M.BAR_BG[1], M.BAR_BG[2], M.BAR_BG[3], 0.9)
    bar.border = M.Border(bar, "OVERLAY")
    bar:Hide()
    f.power = bar
end

function Resource:UpdateValue(f)
    local bar, unit = f.power, f.unit.unitid
    pcall(bar.SetMinMaxValues, bar, 0, UnitPowerMax(unit))
    pcall(bar.SetValue, bar, UnitPower(unit))
    local ok, _, token = pcall(UnitPowerType, unit)
    if not ok or not C.Readable(token) then token = nil end
    local c = token and PowerBarColor and PowerBarColor[token] or MANA
    bar:SetStatusBarColor(c.r, c.g, c.b, 1)
end

function Resource:Update(f)
    local bar, h = f.power, f.powerH or 0
    if h <= 0 then return bar:Hide() end
    bar:SetStatusBarTexture(M.BarTexture())
    bar:ClearAllPoints()
    -- 1px gap, so the two borders sit side by side.
    bar:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -1)
    bar:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -1)
    bar:SetHeight(h)
    self:UpdateValue(f)
    bar:Show()
end

function Resource:Clear(f) f.power:Hide() end

ns.Plates:Register(Resource)

local function OnPower(unit)
    local f = ns.Plates:ForUnit(unit)
    if f and f.active and f.power:IsShown() then Resource:UpdateValue(f) end
end
ns:On("UNIT_POWER_UPDATE", OnPower)
ns:On("UNIT_POWER_FREQUENT", OnPower)
ns:On("UNIT_DISPLAYPOWER", OnPower)
ns:On("UNIT_MAXPOWER", function(unit)
    local f = ns.Plates:ForUnit(unit)
    if f and f.active then ns.Plates:Refresh(f) end -- the unit may gain or lose its bar
end)
