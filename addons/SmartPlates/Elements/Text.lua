local _, ns = ...
local C, M = ns.Compat, ns.Media

-- Name, level, health text and the threat percentage.
local Text = { name = "Text" }

local function Short(n)
    if n >= 1e6 then return ("%.1fm"):format(n / 1e6) end
    if n >= 1e4 then return ("%.0fk"):format(n / 1e3) end
    if n >= 1e3 then return ("%.1fk"):format(n / 1e3) end
    return tostring(math.floor(n))
end

function Text:Create(f)
    local layer = CreateFrame("Frame", nil, f)
    layer:SetAllPoints(f)
    layer:SetFrameLevel(f:GetFrameLevel() + 5)
    f.textLayer = layer
    f.name = layer:CreateFontString(nil, "OVERLAY")
    f.level = layer:CreateFontString(nil, "OVERLAY")
    f.healthText = layer:CreateFontString(nil, "OVERLAY")
    f.threatText = layer:CreateFontString(nil, "OVERLAY")
    f.mobTarget = layer:CreateFontString(nil, "OVERLAY")
    -- A small sword left of hostile names (the game's attack cursor).
    f.sword = layer:CreateTexture(nil, "OVERLAY")
    f.sword:SetTexture("Interface\\Cursor\\Attack")
    f.sword:Hide()
    for _, fs in ipairs({ f.name, f.level, f.healthText, f.threatText, f.mobTarget }) do M.SetFont(fs, 10) end
    f.mobTarget:SetJustifyH("LEFT"); f.mobTarget:SetWordWrap(false)
    f.name:SetWordWrap(false)
end

function Text:Layout(f)
    local g = ns.db.general
    local nameOnly = f.unit.style == "name"
    if f.unit.reaction == "FRIENDLY" then
        -- Friendly names: bigger, outlined, plus a drop shadow so they stand off busy backgrounds.
        M.SetFont(f.name, g.friendlyNameSize, "OUTLINE")
        f.name:SetShadowOffset(1, -1)
        f.name:SetShadowColor(0, 0, 0, 1)
    else
        M.SetFont(f.name, nameOnly and g.nameSize + 2 or g.nameSize)
    end
    M.SetFont(f.level, g.healthTextSize)
    M.SetFont(f.healthText, g.healthTextSize)
    M.SetFont(f.threatText, ns.db.threat.percent.size)

    f.name:ClearAllPoints()
    if nameOnly then
        f.name:SetPoint("CENTER", f, "CENTER", 0, 0)
        f.name:SetWidth(0)
    else
        f.name:SetPoint("BOTTOM", f, "TOP", 0, 3)
        f.name:SetWidth((f.barW or g.width) + 30)
    end
    f.level:ClearAllPoints(); f.level:SetPoint("RIGHT", f, "RIGHT", -2, 0)
    f.healthText:ClearAllPoints(); f.healthText:SetPoint("CENTER", f, "CENTER", 0, 0)
    M.SetFont(f.mobTarget, math.max(7, g.healthTextSize - 1))
    f.mobTarget:SetJustifyH("LEFT"); f.mobTarget:SetWordWrap(false)

    local anchor = ns.db.threat.percent.anchor
    f.threatText:ClearAllPoints()
    if anchor == "LEFT" then
        f.threatText:SetPoint("RIGHT", f, "LEFT", -4, 0)
    elseif anchor == "TOP" then
        f.threatText:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 3)
    else
        f.threatText:SetPoint("LEFT", f, "RIGHT", 4, 0)
    end
end

function Text:UpdateName(f)
    local u = f.unit
    if u.name then f.name:SetText(u.name) else pcall(f.name.SetText, f.name, UnitName(u.unitid)) end
    local r, g, b, hidden = ns.Style:NameColor(u)
    ns.Style:Apply(f.name.SetTextColor, f.name, u, r, g, b, hidden)
    self:UpdateSword(f)
end

local ELITE = { elite = true, worldboss = true, rareelite = true, rare = true } -- as Icons.lua marks them

-- The sword sits just left of the healthbar, outside the friend/foe ring. The cast icon takes
-- that spot while the unit casts, so the sword fades out meanwhile (see Castbar.lua).
function Text:UpdateSword(f)
    local u, sword, mode = f.unit, f.sword, ns.db.general.enemySword
    local show = mode ~= "off" and u.reaction == "HOSTILE" and (mode == "all" or u.isPlayer) and u.style == "normal"
    -- The elite / rare icon already marks the mob as a threat.
    if ns.db.general.eliteIcon and ELITE[u.classification or ""] then show = false end
    if not show then return sword:Hide() end
    local size = math.floor(math.max(10, (f.barH or 12) + 4) * 0.9 + 0.5)
    sword:SetSize(size, size)
    sword:ClearAllPoints()
    sword:SetPoint("RIGHT", f, "LEFT", -(ns.Plates:RingSize(f) + 2), 0)
    sword:SetAlpha(f.castbar and f.castbar:IsShown() and f.castbar.icon:IsShown() and 0 or 1)
    sword:Show()
end

-- The mob's target runs from the bar's left end up to the health text (or the level when there's
-- no health text), and is cut short with "..." rather than running under it.
function Text:LayoutMobTarget(f)
    local fs = f.mobTarget
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", f, "LEFT", 3, 0)
    if f.healthText:IsShown() then
        fs:SetPoint("RIGHT", f.healthText, "LEFT", -4, 0)
    elseif f.level:IsShown() then
        fs:SetPoint("RIGHT", f.level, "LEFT", -4, 0)
    else
        fs:SetPoint("RIGHT", f, "RIGHT", -3, 0)
    end
end

function Text:UpdateLevel(f)
    local u = f.unit
    if u.style == "name" or not ns.db.general.showLevel or not u.level or (f.barH or 12) < 8 then return f.level:Hide() end
    local text = u.level < 0 and "??" or tostring(u.level)
    local c = u.classification
    if c == "elite" or c == "worldboss" or c == "rareelite" then text = text .. "+" end
    f.level:SetText(text)
    local color = u.level > 0 and GetCreatureDifficultyColor and GetCreatureDifficultyColor(u.level)
        or (GetQuestDifficultyColor and GetQuestDifficultyColor(u.level > 0 and u.level or 999))
    if color then f.level:SetTextColor(color.r, color.g, color.b) else f.level:SetTextColor(1, 1, 1) end
    f.level:Show()
end

-- Readable health as text for a mode (none | value | percent | both | deficit).
function Text.Format(mode, cur, max)
    if mode == "none" or not max or max <= 0 then return "" end
    local pct = cur / max * 100
    if mode == "percent" then return ("%d%%"):format(pct + 0.5) end
    if mode == "value" then return Short(cur) end
    if mode == "both" then return ("%s  %d%%"):format(Short(cur), pct + 0.5) end
    if mode == "deficit" then return cur < max and ("-" .. Short(max - cur)) or "" end
    return ""
end

-- Health text when the client hides the unit's health (WoW Forever and Midnight, in combat): the
-- hidden numbers go through the game's own helpers and string formatting, which accept them, and
-- straight into the text unread. nil when the client has none of those helpers.
local function HiddenHealthText(unit, mode)
    local function Value() return AbbreviateNumbers(UnitHealth(unit)) end
    local function Percent()
        return ("%.f%%"):format(UnitHealthPercent(unit, true, CurveConstants.ScaleTo100))
    end
    local ok, text = pcall(function()
        if mode == "percent" then return Percent() end
        if mode == "value" then return Value() end
        if mode == "both" then return Value() .. "  " .. Percent() end
        if mode == "deficit" then return "-" .. AbbreviateNumbers(UnitHealthMissing(unit)) end
    end)
    if ok then return text end
end

-- Above this much maximum health, the value and deficit modes show a percentage instead.
local BIG_HEALTH = 5000

function Text:UpdateHealth(f)
    self:UpdateHealthText(f)
    self:LayoutMobTarget(f)
end

function Text:UpdateHealthText(f)
    local mode = ns.db.general.healthText
    -- Bars under 8px (friendly players) are too thin for text.
    if f.unit.style == "name" or mode == "none" or (f.barH or 12) < 8 then return f.healthText:Hide() end
    local unit = f.unit.unitid
    local rawCur, rawMax = UnitHealth(unit), UnitHealthMax(unit)
    local cur, max = C.Num(rawCur), C.Num(rawMax)
    -- The maximum is often readable out of combat even when hidden in it: remember it.
    if max then f.unit.knownMaxHealth = max end
    local bigMax = max or f.unit.knownMaxHealth
    if bigMax and bigMax > BIG_HEALTH and (mode == "value" or mode == "deficit") then mode = "percent" end
    local text
    if cur and max then
        if max <= 0 then return f.healthText:Hide() end
        text = Text.Format(mode, cur, max)
    elseif C.IsSecret(rawCur) or C.IsSecret(rawMax) then
        text = HiddenHealthText(unit, mode)
        if text == nil or not pcall(f.healthText.SetText, f.healthText, text) then return f.healthText:Hide() end
        f.healthText:SetTextColor(1, 1, 1)
        return f.healthText:Show()
    else
        return f.healthText:Hide()
    end
    f.healthText:SetText(text or "")
    f.healthText:SetTextColor(1, 1, 1)
    f.healthText:Show()
end

function Text:UpdateThreat(f)
    local u = f.unit
    if not ns.Threat:ShowPercent(u) then return f.threatText:Hide() end
    if u.threatPct == nil then
        -- Hidden by the client: formatted by the widget, never read here.
        if not pcall(f.threatText.SetFormattedText, f.threatText, "%.0f%%", u.threatHidden) then
            return f.threatText:Hide()
        end
    else
        f.threatText:SetText(ns.Threat.Format(u.threatPct))
    end
    local r, g, b
    if ns.db.threat.percent.colored then r, g, b = ns.Threat:Color(u) end
    f.threatText:SetTextColor(r or 1, g or 1, b or 1)
    f.threatText:Show()
end

-- Who the mob is attacking, inside its healthbar on the left: "YOU" in red, otherwise their name
-- (class-coloured when readable). Names the client hides are passed through to the text unread.
function Text:UpdateMobTarget(f)
    local u, fs = f.unit, f.mobTarget
    if not ns.db.general.mobTarget or u.style ~= "normal" or u.isPlayer or u.reaction == "FRIENDLY" then return fs:Hide() end
    local target = u.unitid .. "target"
    local okE, exists = pcall(UnitExists, target)
    if not okE or not C.Readable(exists) or not exists then return fs:Hide() end
    local okG, tGuid = pcall(UnitGUID, target)
    local isMe = C.UnitIsUnit(target, "player")
        or (okG and C.Readable(tGuid) and tGuid ~= nil and tGuid == UnitGUID("player"))
    if isMe then
        fs:SetText("YOU")
        fs:SetTextColor(1, 0.35, 0.3)
        return fs:Show()
    end
    local okN, name = pcall(UnitName, target)
    if not okN or not pcall(fs.SetText, fs, name) then return fs:Hide() end
    local _, class = C.Identity(target)
    if class then fs:SetTextColor(C.ClassColor(class)) else fs:SetTextColor(0.85, 0.9, 0.95) end
    fs:Show()
end

function Text:Update(f)
    self:Layout(f)
    self:UpdateMobTarget(f)
    self:UpdateName(f)
    self:UpdateLevel(f)
    self:UpdateHealth(f)
    self:UpdateThreat(f)
end

ns.Plates:Register(Text)
ns.Text = Text

ns:Listen("HealthChanged", function(f) Text:UpdateHealth(f) end)
ns:On("UNIT_TARGET", function(unit)
    local f = ns.Plates:ForUnit(unit)
    if f and f.active then Text:UpdateMobTarget(f) end
end)
ns:Listen("ThreatUpdate", function(f) Text:UpdateThreat(f) end)
