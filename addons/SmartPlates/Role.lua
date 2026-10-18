local _, ns = ...
local C = ns.Compat

-- Is the player tanking? From the specialization where specs exist, otherwise from stances, forms,
-- tank auras and Season of Discovery tank runes. /sp role tank|dps overrides it.
local Role = {}
ns.Role = Role

local _, PLAYER_CLASS = UnitClass("player")
local BEAR_FORM, DIRE_BEAR_FORM = DRUID_BEAR_FORM or BEAR_FORM or 5, 8
local DEFENSIVE_STANCE = 18

local TANK_AURAS = {
    PALADIN = { 25780, 20468, 20469, 20470, 407627 }, -- Righteous Fury (407627: Season of Discovery)
    DEATHKNIGHT = { 48263 },                          -- Blood Presence / Frost Presence (Wrath)
    SHAMAN = { 408680 },                              -- Way of Earth (Season of Discovery)
    WARLOCK = { 403789 },                             -- Metamorphosis (Season of Discovery)
}
local ROGUE_TANK_SPELL = 400014 -- Just a Flesh Wound (Season of Discovery); a passive with no aura

local detected = "dps"

local function FormID()
    if GetShapeshiftFormID then return GetShapeshiftFormID() end
end

local function Detect()
    if C.HAS_SPECS then
        local spec = GetSpecialization()
        if spec and spec > 0 then
            return GetSpecializationRole(spec) == "TANK" and "tank" or "dps"
        end
    end
    if UnitHasEffectivelyTankAura then
        local ok, tank = pcall(UnitHasEffectivelyTankAura, "player")
        if ok and C.Readable(tank) and tank == true then return "tank" end
    end
    if PLAYER_CLASS == "WARRIOR" then
        return FormID() == DEFENSIVE_STANCE and "tank" or "dps"
    elseif PLAYER_CLASS == "DRUID" then
        local form = FormID()
        return (form == BEAR_FORM or form == DIRE_BEAR_FORM) and "tank" or "dps"
    elseif PLAYER_CLASS == "ROGUE" then
        return C.IsSpellKnown(ROGUE_TANK_SPELL) and "tank" or "dps"
    end
    for _, id in ipairs(TANK_AURAS[PLAYER_CLASS] or {}) do
        if C.PlayerAura(id) then return "tank" end
    end
    return "dps"
end

function Role:Get()
    local setting = ns.char and ns.char.role or "auto"
    if setting == "tank" or setting == "dps" then return setting end
    return detected
end

function Role:IsTank() return self:Get() == "tank" end

function Role:Update()
    -- In combat on Midnight the aura reads can come back empty; keep what we had then.
    local ok, role = pcall(Detect)
    if ok then detected = role end
    local effective = self:Get()
    if effective ~= self.last then
        self.last = effective
        ns:Fire("RoleChanged", effective)
        if ns.Plates then ns.Plates:UpdateAll() end
    end
end

-- Is another unit (a group member) a tank? Assigned role, main tank assignment, or a pet.
function Role:UnitIsTank(unit)
    -- Both can be hidden on WoW Forever / Midnight; a hidden answer counts as "not a tank".
    if C.Value(UnitGroupRolesAssigned, unit) == "TANK" then return true end
    if C.Value(GetPartyAssignment, "MAINTANK", unit) then return true end
    return false
end

local function Refresh() Role:Update() end
ns:On("PLAYER_ENTERING_WORLD", Refresh)
ns:On("UPDATE_SHAPESHIFT_FORM", Refresh)
ns:On("PLAYER_SPECIALIZATION_CHANGED", Refresh)
ns:On("ACTIVE_TALENT_GROUP_CHANGED", Refresh)
ns:On("PLAYER_EQUIPMENT_CHANGED", Refresh) -- Season of Discovery runes are engraved on gear
ns:On("RUNE_UPDATED", Refresh)
ns:On("UNIT_AURA", function(unit) if unit == "player" and TANK_AURAS[PLAYER_CLASS] then Refresh() end end)
