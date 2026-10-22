local _, ns = ...

-- One place for the game API SmartPlates reads on WoW Forever (Interface 16001, the 12.x engine).
-- Everything checks for the feature, never the version number.
local C = {}
ns.Compat = C

-- Specializations (and so roles from spec), where the game has them.
C.HAS_SPECS = type(GetSpecialization) == "function" and type(GetSpecializationRole) == "function"
-- Secret values: WoW Forever (the 12.x engine) hides some combat numbers from addons. Arithmetic on them errors.
C.HAS_SECRETS = type(issecretvalue) == "function"

local issecret = issecretvalue
function C.IsSecret(v) return issecret ~= nil and issecret(v) or false end

-- true when every value can be read and compared (a boolean; ns.Units.Readable is the value-or-nil guard).
function C.AllReadable(...)
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

-- Returns one aura as a table with the fields C_UnitAuras' AuraData uses, or nil past the last aura.
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
    if not C.AllReadable(tanking, status, scaled) then return nil end
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

C.UnitIsUnit = ns.Units.UnitIsUnit

-- Player names (WoW Forever: realmless "Given Family"). One player's name comes as "Given Family",
-- "GivenFamily" or "Given Family-Server", and some sources (UnitName's first value, a plate that
-- only tells the given name) give the given name alone.
local U = ns.Units

-- One player, whatever the shapes; a given name alone matches a full name that starts with it.
C.SameName = U.SameName

-- A name's given part (or the whole name when it has one word), trimmed; for the NameSet index.
local function GivenOf(name)
    local s = U.Short(U.Str(name))
    s = s and s:match("^%s*(.-)%s*$")
    return (s and s ~= "") and s or nil
end

-- A set of players by name (friends, guild, nemeses) that a plate's unit is looked up in.
-- Kept by the compact key (every shape of a full name gives the same one) and by given name, for
-- the plates and list entries that only tell that. A number value keeps the highest one added.
function C.NameSet() return { keys = {}, givenOnly = {}, given = {} } end

function C.NameSetWipe(set)
    wipe(set.keys); wipe(set.givenOnly); wipe(set.given)
end

local function Put(t, k, v)
    local old = t[k]
    if old == nil or (type(v) == "number" and type(old) == "number" and v > old) then t[k] = v end
end

function C.NameSetAdd(set, name, value)
    if value == nil then value = true end
    local key, given = U.Compact(name), GivenOf(name)
    if not key then return end
    Put(set.keys, key, value)
    if given then
        given = given:lower()
        local first = given:match("^(%S+)")
        Put(set.given, first, value)
        if first == given then Put(set.givenOnly, given, value) end
    end
end

-- The value for a plate's unit (or for a name), or nil.
function C.NameSetFind(set, unit, name)
    local full = unit and U.UnitKey(unit) or name
    local given = GivenOf(name or (unit and U.Call(UnitName, unit)))
    given = given and (given:match("^(%S+)") or given):lower()
    local base = GivenOf(full)
    if base and base:find(" ", 1, true) then
        local v = set.keys[U.Compact(full)]
        if v == nil and given then v = set.givenOnly[given] end
        return v
    end
    -- Only a given name (or a compact one) to go on.
    local key = U.Compact(full)
    if key and set.keys[key] ~= nil then return set.keys[key] end
    return given and set.given[given] or nil
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
local GROUP = { pets = true, raidSelf = true }
function C.GroupUnits(out)
    GROUP.out = out
    local units = ns.Units.GroupUnits(GROUP)
    GROUP.out = nil
    return units
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
    if not C.AllReadable(guid) then guid = nil end
    local isPlayer = Read(UnitIsPlayer, unit)
    if not C.AllReadable(isPlayer) then isPlayer = nil end
    if isPlayer == nil and guid then isPlayer = guid:find("^Player%-") ~= nil end
    local _, class = Read(UnitClass, unit)
    if not C.AllReadable(class) then class = nil end
    if not class and UnitClassBase then
        local c = Read(UnitClassBase, unit)
        if C.AllReadable(c) then class = c end
    end
    local _, race = Read(UnitRace, unit)
    if not C.AllReadable(race) then race = nil end
    if guid and isPlayer and (not class or not race) and GetPlayerInfoByGUID then
        local _, gClass, _, gRace = Read(GetPlayerInfoByGUID, guid)
        if not class and C.AllReadable(gClass) then class = gClass end
        if not race and C.AllReadable(gRace) then race = gRace end
    end
    return isPlayer, class, race, guid
end

-- Class colour for a class token the client hides: true, r, g, b (possibly hidden values), or false.
C.SecretClassColor = ns.Units.SecretClassColor

local GREY = { 0.8, 0.8, 0.8 }
function C.ClassColor(class)
    local _, r, g, b = ns.Units.ClassColor(class, GREY)
    return r, g, b
end

-- The unit tooltip's lines as { text, type, r, g, b }: every line that carries a C_TooltipInfo type,
-- plus lines 2 on (ns.Tooltip.Lines).
function C.GetQuestTooltipLines(unit)
    local lines = {}
    for i, l in ipairs(ns.Tooltip.Lines("unit", unit) or {}) do
        if i >= 2 or l.type then lines[#lines + 1] = { text = l[1], type = l.type, r = l[3], g = l[4], b = l[5] } end
    end
    return lines
end
