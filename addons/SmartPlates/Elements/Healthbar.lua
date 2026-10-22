local _, ns = ...
local C, M = ns.Compat, ns.Media

-- Healthbar with a 1px border, a light wash on mouseover, absorbs where the client has them, an
-- execute-range marker, an orange border on your focus, and your target marked by a teal border,
-- arrows or a glow. The fill colour comes from Style:HealthColor (execute, then threat, then class).
local Health = { name = "Healthbar" }

local ARROW = "Interface\\ChatFrame\\ChatFrameExpandArrow"

function Health:Create(f)
    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetAllPoints(f)
    bar:SetStatusBarTexture(M.BAR)
    bar:SetMinMaxValues(0, 1); bar:SetValue(1)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints(); bar.bg:SetColorTexture(M.BAR_BG[1], M.BAR_BG[2], M.BAR_BG[3], 0.9)
    bar.border = M.Border(bar, "OVERLAY")

    bar.absorb = bar:CreateTexture(nil, "ARTWORK", nil, 1)
    bar.absorb:SetTexture(M.BAR)
    bar.absorb:SetVertexColor(1, 1, 1, 0.35)
    bar.absorb:Hide()

    bar.highlight = bar:CreateTexture(nil, "OVERLAY", nil, -1)
    bar.highlight:SetAllPoints(); bar.highlight:SetColorTexture(1, 1, 1, 0.15)
    bar.highlight:Hide()

    -- Execute threshold: a thin line across the bar.
    bar.execute = bar:CreateTexture(nil, "OVERLAY", nil, 1)
    bar.execute:SetColorTexture(1, 1, 1, 0.55)
    bar.execute:SetWidth(1)
    bar.execute:Hide()

    -- Target markers: arrows either side, or a soft teal glow.
    bar.arrowL = f:CreateTexture(nil, "OVERLAY")
    bar.arrowL:SetTexture(ARROW)
    bar.arrowR = f:CreateTexture(nil, "OVERLAY")
    bar.arrowR:SetTexture(ARROW)
    bar.arrowR:SetTexCoord(1, 0, 0, 1) -- mirrored: points left, at the bar (the texture points right)
    for _, a in ipairs({ bar.arrowL, bar.arrowR }) do
        a:SetVertexColor(M.ACCENT[1], M.ACCENT[2], M.ACCENT[3], 1)
        a:Hide()
    end
    -- Reaction ring: a few pixels of green (friendly), red (enemy) or yellow (neutral) right round the
    -- healthbar and power bar, so friend and foe are obvious at a glance.
    bar.ring = CreateFrame("Frame", nil, f, "BackdropTemplate")
    bar.ring:SetFrameLevel(math.max(0, f:GetFrameLevel()))
    bar.ring:Hide()

    bar.targetGlow = CreateFrame("Frame", nil, f, "BackdropTemplate")
    bar.targetGlow:SetBackdrop({ edgeFile = M.WHITE, edgeSize = 3 })
    bar.targetGlow:SetBackdropBorderColor(M.ACCENT[1], M.ACCENT[2], M.ACCENT[3], 0.45)
    bar.targetGlow:Hide()

    f.health = bar
end

-- Is the unit in execute range? Needs readable health, so it stays off where health is hidden.
local function ExecuteState(f, cur, max)
    local g, u = ns.db.general, f.unit
    if not g.execute or u.reaction == "FRIENDLY" or not cur or not max or max <= 0 then return false end
    return cur / max * 100 <= g.executePercent and cur > 0
end

function Health:UpdateValues(f)
    local bar, unit = f.health, f.unit.unitid
    if not unit then return end
    local cur, max = UnitHealth(unit), UnitHealthMax(unit)
    -- Secret values can still be handed to the bar; only arithmetic on them is blocked.
    pcall(bar.SetMinMaxValues, bar, 0, max)
    pcall(bar.SetValue, bar, cur)
    local nCur, nMax = C.Num(cur), C.Num(max)
    local readable = nCur ~= nil and nMax ~= nil
    if readable ~= f.unit.healthReadable then
        f.unit.healthReadable = readable
        self:UpdateExecuteMarker(f)
    end
    self:UpdateAbsorb(f, nCur, nMax)
    local inExecute = ExecuteState(f, nCur, nMax)
    if inExecute ~= (f.unit.inExecute or false) then
        f.unit.inExecute = inExecute
        self:UpdateColor(f)
    end
    ns:Fire("HealthChanged", f)
end

function Health:UpdateAbsorb(f, cur, max)
    local bar = f.health
    if not ns.db.general.absorbs or not UnitGetTotalAbsorbs or not cur or not max or max <= 0 then
        return bar.absorb:Hide()
    end
    local ok, absorb = pcall(UnitGetTotalAbsorbs, f.unit.unitid)
    absorb = ok and C.Num(absorb) or 0
    if absorb <= 0 then return bar.absorb:Hide() end
    local width = bar:GetWidth()
    local x = width * cur / max
    local w = math.min(width - x, width * absorb / max)
    if w < 1 then return bar.absorb:Hide() end
    bar.absorb:ClearAllPoints()
    bar.absorb:SetPoint("TOPLEFT", bar, "TOPLEFT", x, 0)
    bar.absorb:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, 0)
    bar.absorb:SetWidth(w)
    bar.absorb:Show()
end

function Health:UpdateExecuteMarker(f)
    local g, bar = ns.db.general, f.health
    -- Hidden health (WoW Forever, Midnight) can't be compared to the threshold, so no marker there.
    if not g.execute or f.unit.reaction == "FRIENDLY" or f.unit.healthReadable == false then return bar.execute:Hide() end
    local x = (f.barW or g.width) * g.executePercent / 100
    bar.execute:ClearAllPoints()
    bar.execute:SetPoint("TOPLEFT", bar, "TOPLEFT", x, 0)
    bar.execute:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, 0)
    bar.execute:Show()
end

function Health:UpdateColor(f)
    local r, g, b, hidden = ns.Style:HealthColor(f.unit)
    ns.Style:Apply(f.health.SetStatusBarColor, f.health, f.unit, r, g, b, hidden)
end

function Health:UpdateRing(f)
    local u, ring, g = f.unit, f.health.ring, ns.db.general
    local size = ns.Plates:RingSize(f)
    if size <= 0 then return ring:Hide() end
    local below = ns.Plates:BelowBar(f)
    ring:ClearAllPoints()
    ring:SetPoint("TOPLEFT", f, "TOPLEFT", -size, size)
    ring:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", size, -size - below)
    ring:SetBackdrop({ edgeFile = M.WHITE, edgeSize = size })
    local c = ns.db.colors
    c = (u.reaction == "FRIENDLY" and c.borderFriendly) or (u.reaction == "NEUTRAL" and c.borderNeutral) or c.borderEnemy
    ring:SetBackdropBorderColor(c[1], c[2], c[3], 1)
    ring:Show()
end

function Health:UpdateBorder(f)
    local u, bar, g = f.unit, f.health, ns.db.general
    -- The target glow sits just outside the reaction ring.
    local out = ns.Plates:RingSize(f) + 4
    bar.targetGlow:ClearAllPoints()
    bar.targetGlow:SetPoint("TOPLEFT", f, "TOPLEFT", -out, out)
    bar.targetGlow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", out, -out - ns.Plates:BelowBar(f))
    -- (SmartPlates' target frame is the target; it doesn't mark itself.)
    local target = u.isTarget and g.targetHighlight
    local style = g.targetStyle
    if target then
        bar.border:SetColor(M.ACCENT[1], M.ACCENT[2], M.ACCENT[3], 1)
    elseif u.isFocus and g.focusHighlight then
        local c = ns.db.colors.focus
        bar.border:SetColor(c[1], c[2], c[3], 1)
    else
        bar.border:SetColor(M.BORDER[1], M.BORDER[2], M.BORDER[3], 1)
    end
    local arrows = target and style == "arrows" and u.style == "normal"
    if arrows then
        local size = math.max(10, (f.barH or g.height) + 6)
        bar.arrowL:SetSize(size, size); bar.arrowR:SetSize(size, size)
        bar.arrowL:ClearAllPoints(); bar.arrowR:ClearAllPoints()
        -- Outside the cast icon on the left and the threat % / class icon on the right.
        -- The right arrow also clears the threat % (about "100%" wide) when it sits on that side.
        local pct = ns.db.threat.percent
        local right = size + 8
        if pct.show ~= "never" and pct.anchor == "RIGHT" then right = math.max(right, math.floor(pct.size * 2.6) + 10) end
        bar.arrowL:SetPoint("RIGHT", f, "LEFT", -(size + 8), 0)
        bar.arrowR:SetPoint("LEFT", f, "RIGHT", right, 0)
    end
    bar.arrowL:SetShown(arrows); bar.arrowR:SetShown(arrows)
    bar.targetGlow:SetShown(target and style == "glow" and u.style == "normal" or false)
    bar.highlight:SetShown(u.isMouseover and g.mouseoverHighlight and not u.isTarget or false)
end

function Health:Update(f)
    local bar = f.health
    if f.unit.style == "name" then
        bar:Hide()
        bar.arrowL:Hide(); bar.arrowR:Hide(); bar.targetGlow:Hide(); bar.ring:Hide()
        return
    end
    bar:Show()
    local tex = M.BarTexture()
    bar:SetStatusBarTexture(tex)
    bar.absorb:SetTexture(tex)
    self:UpdateValues(f)
    self:UpdateColor(f)
    self:UpdateBorder(f)
    self:UpdateRing(f)
    self:UpdateExecuteMarker(f)
end

function Health:Clear(f)
    local bar = f.health
    bar.arrowL:Hide(); bar.arrowR:Hide(); bar.targetGlow:Hide(); bar.ring:Hide()
end

ns.Plates:Register(Health)
ns.Healthbar = Health

local function OnHealth(unit)
    local f = ns.Plates:ForUnit(unit)
    if f and f.active and f.unit.style ~= "name" then Health:UpdateValues(f) end
end
ns:On("UNIT_HEALTH", OnHealth)
ns:On("UNIT_HEALTH_FREQUENT", OnHealth)
ns:On("UNIT_MAXHEALTH", OnHealth)
ns:On("UNIT_ABSORB_AMOUNT_CHANGED", OnHealth)

ns:On("UNIT_FLAGS", function(unit)
    local f = ns.Plates:ForUnit(unit)
    if not f or not f.active then return end
    if UnitIsTapDenied then
        local ok, tapped = pcall(UnitIsTapDenied, unit)
        if ok and C.AllReadable(tapped) then f.unit.tapped = tapped end
    end
    Health:UpdateColor(f)
    Health:UpdateRing(f)
end)

ns:Listen("ThreatUpdate", function(f) Health:UpdateColor(f) end)
ns:Listen("TargetChanged", function() ns.Plates:Each(function(f) Health:UpdateBorder(f) end) end)
ns:Listen("FocusChanged", function() ns.Plates:Each(function(f) Health:UpdateBorder(f) end) end)
ns:Listen("MouseoverChanged", function(f) if f.active then Health:UpdateBorder(f) end end)
