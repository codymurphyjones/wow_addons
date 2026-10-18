local _, ns = ...
local C, M = ns.Compat, ns.Media

-- Raid target marker, elite/rare icon and the threat glow around the healthbar.
local Icons = { name = "Icons" }

-- The glow warns, so it shows only when the threat state is bad for your role.
local WARN = {
    dps = { MEDIUM = true, HIGH = true },
    tank = { LOW = true, MEDIUM = true },
}

function Icons:Create(f)
    local glow = CreateFrame("Frame", nil, f, "BackdropTemplate")
    glow:SetPoint("TOPLEFT", f, "TOPLEFT", -3, 3)
    glow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 3, -3)
    glow:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))
    glow:SetBackdrop({ edgeFile = M.WHITE, edgeSize = 2 })
    glow:Hide()
    f.glow = glow

    local layer = f.textLayer or f
    f.raidIcon = layer:CreateTexture(nil, "OVERLAY")
    f.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    f.raidIcon:Hide()

    f.eliteIcon = layer:CreateTexture(nil, "OVERLAY")
    f.eliteIcon:SetSize(14, 14)
    f.eliteIcon:Hide()
end

function Icons:UpdateRaid(f)
    local g = ns.db.general
    local ok, index = pcall(GetRaidTargetIndex, f.unit.unitid)
    index = ok and C.Num(index) or nil
    if not g.raidIcon or not index or not SetRaidTargetIconTexture then return f.raidIcon:Hide() end
    SetRaidTargetIconTexture(f.raidIcon, index)
    f.raidIcon:SetSize(g.raidIconSize, g.raidIconSize)
    f.raidIcon:ClearAllPoints()
    if f.unit.style == "name" then
        f.raidIcon:SetPoint("RIGHT", f.name, "LEFT", -3, 0)
    else
        -- Above the aura row (Plugins\Auras.lua), which sits on the name and is 1px tall when empty.
        f.raidIcon:SetPoint("BOTTOM", f.auras or f.name, "TOP", 0, 2)
    end
    f.raidIcon:Show()
end

local ELITE_ATLAS = { elite = "nameplates-icon-elite-gold", worldboss = "nameplates-icon-elite-gold",
    rareelite = "nameplates-icon-elite-silver", rare = "nameplates-icon-elite-silver" }

function Icons:UpdateElite(f)
    local atlas = ELITE_ATLAS[f.unit.classification or ""]
    if not ns.db.general.eliteIcon or not atlas or f.unit.style ~= "normal" then return f.eliteIcon:Hide() end
    local ok = pcall(f.eliteIcon.SetAtlas, f.eliteIcon, atlas)
    if not ok or not f.eliteIcon:GetAtlas() then return f.eliteIcon:Hide() end
    f.eliteIcon:ClearAllPoints()
    f.eliteIcon:SetPoint("CENTER", f, "TOPLEFT", 0, 0) -- on the corner, clear of the cast icon and threat %
    f.eliteIcon:Show()
end

function Icons:UpdateGlow(f)
    local u = f.unit
    local warn = WARN[ns.Role:Get()]
    if not ns.db.threat.glow or u.style ~= "normal" or not u.threatLevel or not (warn and warn[u.threatLevel]) then
        return f.glow:Hide()
    end
    local r, g, b = ns.Threat:Color(u)
    if not r then
        local set = ns.db.threat.colors[ns.Role:Get()]
        local c = set and set[u.threatLevel] or { 1, 1, 1 }
        r, g, b = c[1], c[2], c[3]
    end
    local out = ns.Plates:RingSize(f) + 3
    f.glow:ClearAllPoints()
    f.glow:SetPoint("TOPLEFT", f, "TOPLEFT", -out, out)
    f.glow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", out, -out - ns.Plates:BelowBar(f))
    f.glow:SetBackdropBorderColor(r, g, b, 0.9)
    f.glow:Show()
end

function Icons:Update(f)
    self:UpdateRaid(f)
    self:UpdateElite(f)
    self:UpdateGlow(f)
end

ns.Plates:Register(Icons)

ns:On("RAID_TARGET_UPDATE", function() ns.Plates:Each(function(f) Icons:UpdateRaid(f) end) end)
ns:Listen("ThreatUpdate", function(f) Icons:UpdateGlow(f) end)
