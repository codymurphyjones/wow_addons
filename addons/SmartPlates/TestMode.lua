local _, ns = ...
local M = ns.Media

-- /sp test: sample plates in the middle of the screen, drawn with your current settings, with the
-- aggro percentage sweeping from 0% up past 100% so colours and text can be tuned out of combat.
local Test = {}
ns.TestMode = Test

local SAMPLE_MAX_HP = 1450 -- what a level 18 mob has, for the health text

local SAMPLES = {
    { name = "Defias Pillager", level = 18, phase = 0.0, health = 0.85 },
    { name = "Kobold Geomancer", level = 17, phase = 0.25, health = 0.52, cast = "Fireball" },
    { name = "Murloc Tidehunter", level = 16, phase = 0.5, health = 1.0 },
    { name = "Gnoll Brute", level = 19, phase = 0.75, health = 0.30, elite = true },
}
local holder, plates
local CYCLE = 12 -- seconds for one sweep 0% -> 300%

-- Threat level from the percentage: over 100% you hold aggro, from 80% you're close to the flip.
local function LevelFor(pct, role)
    if pct >= 100 then return "HIGH" end
    if pct >= 80 then return "MEDIUM" end
    return "LOW"
end

local function Build()
    holder = CreateFrame("Frame", "SmartPlatesTestFrame", UIParent, "BackdropTemplate")
    holder:SetSize(320, 300)
    holder:SetPoint("CENTER", 0, 80)
    holder:SetFrameStrata("HIGH")
    M.Backdrop(holder, 0.85)
    holder:EnableMouse(true); holder:SetMovable(true); holder:RegisterForDrag("LeftButton")
    holder:SetScript("OnDragStart", holder.StartMoving)
    holder:SetScript("OnDragStop", holder.StopMovingOrSizing)
    local title = holder:CreateFontString(nil, "OVERLAY", "SmartPlatesGameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetTextColor(M.ACCENT[1], M.ACCENT[2], M.ACCENT[3])
    title:SetText("SmartPlates preview")
    holder.role = holder:CreateFontString(nil, "OVERLAY", "SmartPlatesGameFontHighlightSmall")
    holder.role:SetPoint("TOPRIGHT", -34, -12)
    local close = ns.Widgets.MakeButton(holder, "X", 22, 20)
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() Test:Toggle() end)

    plates = {}
    for i, s in ipairs(SAMPLES) do
        local f = CreateFrame("Frame", nil, holder)
        f:SetPoint("TOP", 0, -50 - (i - 1) * 62)
        f.health = CreateFrame("StatusBar", nil, f)
        f.health:SetAllPoints(); f.health:SetStatusBarTexture(M.BAR)
        f.health:SetMinMaxValues(0, 1); f.health:SetValue(s.health)
        local bg = f.health:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(M.BAR_BG[1], M.BAR_BG[2], M.BAR_BG[3], 0.9)
        f.border = M.Border(f.health, "OVERLAY")
        f.glow = CreateFrame("Frame", nil, f, "BackdropTemplate")
        f.glow:SetPoint("TOPLEFT", -3, 3); f.glow:SetPoint("BOTTOMRIGHT", 3, -3)
        f.glow:SetBackdrop({ edgeFile = M.WHITE, edgeSize = 2 })
        f.name = f.health:CreateFontString(nil, "OVERLAY")
        f.level = f.health:CreateFontString(nil, "OVERLAY")
        f.hp = f.health:CreateFontString(nil, "OVERLAY")
        f.pct = f.health:CreateFontString(nil, "OVERLAY")
        if s.cast then
            f.cast = CreateFrame("StatusBar", nil, f)
            f.cast:SetStatusBarTexture(M.BAR)
            f.cast:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -3); f.cast:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -3)
            f.cast:SetMinMaxValues(0, 1)
            M.Border(f.cast, "OVERLAY")
            f.castText = f.cast:CreateFontString(nil, "OVERLAY")
        end
        f.sample = s
        plates[i] = f
    end
end

local function Layout(f)
    local g, p = ns.db.general, ns.db.threat.percent
    f:SetSize(g.width, g.height)
    M.SetFont(f.name, g.nameSize); M.SetFont(f.level, g.healthTextSize)
    M.SetFont(f.hp, g.healthTextSize); M.SetFont(f.pct, p.size)
    f.name:ClearAllPoints(); f.name:SetPoint("BOTTOM", f, "TOP", 0, 3)
    f.name:SetText(f.sample.name)
    f.level:ClearAllPoints(); f.level:SetPoint("RIGHT", -2, 0)
    f.level:SetText(f.sample.level .. (f.sample.elite and "+" or ""))
    f.level:SetShown(g.showLevel)
    f.hp:ClearAllPoints(); f.hp:SetPoint("CENTER")
    f.hp:SetText(ns.Text.Format(g.healthText, f.sample.health * SAMPLE_MAX_HP, SAMPLE_MAX_HP))
    f.pct:ClearAllPoints()
    if p.anchor == "LEFT" then f.pct:SetPoint("RIGHT", f, "LEFT", -4, 0)
    elseif p.anchor == "TOP" then f.pct:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 3)
    else f.pct:SetPoint("LEFT", f, "RIGHT", 4, 0) end
    if f.cast then
        local c = ns.db.colors.cast
        f.cast:SetHeight(ns.db.castbar.height)
        f.cast:SetStatusBarColor(c[1], c[2], c[3])
        f.cast:SetShown(ns.db.castbar.enabled)
        M.SetFont(f.castText, math.max(7, ns.db.castbar.height + 1))
        f.castText:SetPoint("LEFT", 2, 0)
        f.castText:SetText(ns.db.castbar.text and f.sample.cast or "")
    end
end

local WARN = { dps = { MEDIUM = true, HIGH = true }, tank = { LOW = true, MEDIUM = true } }

local function Animate()
    local role = ns.Role:Get()
    holder.role:SetText("Role: |cffffffff" .. (role == "tank" and "Tank" or "DPS / Healer") .. "|r")
    local now = GetTime()
    for _, f in ipairs(plates) do
        Layout(f)
        local t = ((now / CYCLE) + f.sample.phase) % 1
        local pct = t * 300
        local text = pct > 290 and "MAX" or ns.Threat.Format(pct)
        local level = LevelFor(pct, role)
        local c = ns.db.threat.colors[role][level]
        if ns.db.threat.useColor then f.health:SetStatusBarColor(c[1], c[2], c[3]) else f.health:SetStatusBarColor(unpack(ns.db.colors.hostile)) end
        f.pct:SetText(ns.db.threat.percent.show ~= "never" and text or "")
        if ns.db.threat.percent.colored then f.pct:SetTextColor(c[1], c[2], c[3]) else f.pct:SetTextColor(1, 1, 1) end
        f.glow:SetBackdropBorderColor(c[1], c[2], c[3], 0.9)
        f.glow:SetShown(ns.db.threat.glow and WARN[role][level] or false)
        if f.cast then f.cast:SetValue((now % 2.5) / 2.5) end
        local scale = ns.db.threat.useScale and (ns.db.threat.scale[role][level] or 1) or 1
        f:SetScale(ns.db.general.scale * scale)
    end
end

function Test:Toggle()
    if not ns.db then return end
    if not holder then Build() end
    if holder:IsShown() then
        holder:Hide()
        holder:SetScript("OnUpdate", nil)
    else
        holder:Show()
        local acc = 0
        holder:SetScript("OnUpdate", function(_, elapsed)
            acc = acc + elapsed
            if acc < 0.05 then return end
            acc = 0
            Animate()
        end)
        Animate()
    end
end
