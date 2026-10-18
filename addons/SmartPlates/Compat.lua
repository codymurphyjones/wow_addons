local _, ns = ...

-- One place for API differences between Classic Era, the Classic progression clients and Retail.
-- Everything checks for the feature, never the version number, except the few flags below.
local C = {}
ns.Compat = C

local project = WOW_PROJECT_ID
C.IS_MAINLINE = project == WOW_PROJECT_MAINLINE
C.IS_CLASSIC_ERA = WOW_PROJECT_CLASSIC ~= nil and project == WOW_PROJECT_CLASSIC
-- Specializations (and so roles from spec) exist from Mists on, on Retail and Classic alike.
C.HAS_SPECS = type(GetSpecialization) == "function" and type(GetSpecializationRole) == "function"
-- Secret values: Midnight hides some combat numbers from addons. Arithmetic on them errors.
C.HAS_SECRETS = type(issecretvalue) == "function"

local issecret = issecretvalue
function C.IsSecret(v) return issecret ~= nil and issecret(v) or false end

-- true when every value can be read and compared.
function C.Readable(...)
    if not issecret then return true end
    for i = 1, select("#", ...) do
        if issecret((select(i, ...))) then return false end
    end
    return true
end

-- Calls a unit query and returns its first result only when it can be read; nil when it errors or
-- the client hides it. Use this before testing any unit value ("if x", "x == y" error on hidden ones).
function C.Value(fn, ...)
    if not fn then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or (issecret and issecret(v)) then return nil end
    return v
end

-- A number that may be secret, or nil when it can't be read.
function C.Num(v)
    if (issecret and issecret(v)) or v == nil then return nil end -- test secrecy first: comparing a hidden value errors
    return tonumber(v)
end

function C.GetSpellTexture(id)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
    if GetSpellTexture then return GetSpellTexture(id) end
end

function C.GetSpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end

function C.IsSpellKnown(id)
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok, known = pcall(C_SpellBook.IsSpellKnown, id)
        if ok then return known end
    end
    if IsSpellKnown then return IsSpellKnown(id) end
    return false
end

function C.PlayerAura(spellId)
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        return C_UnitAuras.GetPlayerAuraBySpellID(spellId) ~= nil
    end
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, id = UnitBuff("player", i)
        if not name then return false end
        if id == spellId then return true end
    end
    return false
end

-- Returns one aura as a table with the fields Retail's AuraData uses, or nil past the last aura.
function C.GetAura(unit, index, filter)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
        if ok then return a end
        return nil
    end
    if not UnitAura then return nil end
    local name, icon, count, dispel, duration, expires, source, stealable, _, spellId = UnitAura(unit, index, filter)
    if not name then return nil end
    return {
        name = name, icon = icon, applications = count, dispelName = dispel, duration = duration,
        expirationTime = expires, sourceUnit = source, isStealable = stealable, spellId = spellId,
        isHarmful = filter and filter:find("HARMFUL") ~= nil,
    }
end

function C.UnitCastingInfo(unit)
    if UnitCastingInfo then return UnitCastingInfo(unit) end
    if CastingInfo and UnitIsUnit(unit, "player") then return CastingInfo() end
end

function C.UnitChannelInfo(unit)
    if UnitChannelInfo then return UnitChannelInfo(unit) end
    if ChannelInfo and UnitIsUnit(unit, "player") then return ChannelInfo() end
end

-- UnitThreatSituation / UnitDetailedThreatSituation, with secret values turned into nil.
function C.ThreatSituation(unit, mob)
    if not UnitThreatSituation then return nil end
    local ok, status = pcall(UnitThreatSituation, unit, mob)
    if not ok then return nil end
    return C.Num(status)
end

function C.DetailedThreat(unit, mob)
    if not UnitDetailedThreatSituation then return nil end
    local ok, tanking, status, scaled, raw, value = pcall(UnitDetailedThreatSituation, unit, mob)
    if not ok then return nil end
    if not C.Readable(tanking, status, scaled) then return nil end
    return tanking, status, scaled, raw, value
end

-- Blizzard's scaled threat (0-100) for unit on mob, even when the client hides it: a hidden value
-- comes back as is, for passing straight to a font string. nil when not on the threat table.
function C.ScaledThreatAny(unit, mob)
    if not UnitDetailedThreatSituation then return nil end
    local ok, _, _, scaled = pcall(UnitDetailedThreatSituation, unit, mob)
    if not ok then return nil end
    if issecret and issecret(scaled) then return scaled end
    return tonumber(scaled)
end

function C.UnitIsUnit(a, b)
    local ok, same = pcall(UnitIsUnit, a, b)
    if not ok or (issecret and issecret(same)) then return false end
    return same
end

-- Only nameplate tokens: the API errors on raid/party tokens.
function C.PlateForUnit(unit)
    if type(unit) ~= "string" or not unit:find("^nameplate%d+$") then return nil end
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    return ok and plate or nil
end

function C.AllPlates()
    if C_NamePlate and C_NamePlate.GetNamePlates then return C_NamePlate.GetNamePlates() end
    return {}
end

function C.WidgetsOnly(unit)
    return UnitNameplateShowsWidgetsOnly and UnitNameplateShowsWidgetsOnly(unit) or false
end

-- Group members that can hold threat, as unit tokens: party or raid members and their pets, plus your pet.
function C.GroupUnits(out)
    out = out or {}
    wipe(out)
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            out[#out + 1] = "raid" .. i
            out[#out + 1] = "raidpet" .. i
        end
    else
        for i = 1, GetNumSubgroupMembers() do
            out[#out + 1] = "party" .. i
            out[#out + 1] = "partypet" .. i
        end
        out[#out + 1] = "pet"
    end
    return out
end

-- Who is this unit? Each value may be hidden (secret) on Forever/Midnight, so every read has a fallback:
-- the GUID's "Player-" prefix for isPlayer, UnitClassBase / GetPlayerInfoByGUID for class and race.
-- Returns isPlayer, class token, race token, guid (each nil when it can't be read).
local function Read(fn, ...)
    if not fn then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c, d
end

function C.Identity(unit)
    local guid = Read(UnitGUID, unit)
    if not C.Readable(guid) then guid = nil end
    local isPlayer = Read(UnitIsPlayer, unit)
    if not C.Readable(isPlayer) then isPlayer = nil end
    if isPlayer == nil and guid then isPlayer = guid:find("^Player%-") ~= nil end
    local _, class = Read(UnitClass, unit)
    if not C.Readable(class) then class = nil end
    if not class and UnitClassBase then
        local c = Read(UnitClassBase, unit)
        if C.Readable(c) then class = c end
    end
    local _, race = Read(UnitRace, unit)
    if not C.Readable(race) then race = nil end
    if guid and isPlayer and (not class or not race) and GetPlayerInfoByGUID then
        local _, gClass, _, gRace = Read(GetPlayerInfoByGUID, guid)
        if not class and C.Readable(gClass) then class = gClass end
        if not race and C.Readable(gRace) then race = gRace end
    end
    return isPlayer, class, race, guid
end

-- Class colour for a class token the client hides. Addons can't look a hidden value up themselves,
-- but some game functions may accept one and return a (hidden) colour we can pass on to a bar.
-- Returns true, r, g, b (possibly hidden values), or false when every route is refused. The results
-- are never tested here: a test on a hidden value is itself an error.
function C.SecretClassColor(class)
    if C_ClassColor and C_ClassColor.GetClassColor then
        local ok, r, g, b = pcall(function()
            local color = C_ClassColor.GetClassColor(class)
            return color:GetRGB()
        end)
        if ok then return true, r, g, b end
    end
    if GetClassColor then
        local ok, r, g, b = pcall(GetClassColor, class)
        if ok then return true, r, g, b end
    end
    return false
end

function C.ClassColor(class)
    if (issecret and issecret(class)) or class == nil then return 0.8, 0.8, 0.8 end
    local c = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
    if c then return c.r, c.g, c.b end
    return 0.8, 0.8, 0.8
end

function C.GetQuestTooltipLines(unit)
    -- Off Retail, quest addons add the objective lines to the real tooltip only.
    if C.IS_MAINLINE and C_TooltipInfo and C_TooltipInfo.GetUnit then
        local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
        if ok and data and data.lines then
            local lines = {}
            for _, line in ipairs(data.lines) do
                lines[#lines + 1] = { text = line.leftText, type = line.type, r = line.leftColor and line.leftColor.r, g = line.leftColor and line.leftColor.g, b = line.leftColor and line.leftColor.b }
            end
            return lines
        end
    end
    local tip = C.scanTip
    if not tip then
        tip = CreateFrame("GameTooltip", "SmartPlatesScanTooltip", nil, "GameTooltipTemplate")
        C.scanTip = tip
    end
    tip:SetOwner(WorldFrame, "ANCHOR_NONE") -- a hidden tooltip loses its owner, so set it every scan
    tip:ClearLines()
    tip:SetUnit(unit)
    local lines = {}
    for i = 2, tip:NumLines() do
        local fs = _G["SmartPlatesScanTooltipTextLeft" .. i]
        if fs then
            local r, g, b = fs:GetTextColor()
            lines[#lines + 1] = { text = fs:GetText(), r = r, g = g, b = b }
        end
    end
    return lines
end
