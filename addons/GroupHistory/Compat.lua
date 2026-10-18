local _, ns = ...

-- Secret-safe reads. On WoW Forever (a 12.x engine) many combat values are "secret": comparing,
-- testing or printing one is an error. Everything read from the game goes through these, which turn
-- a secret (or failing) value into nil. (From SmartPlates' Compat.lua and BattleRecap's Log.lua.)
local C = {}
ns.Compat = C

-- A value we may read, or nil for a secret one.
function C.Readable(v)
    if v == nil then return nil end
    if canaccessvalue and not canaccessvalue(v) then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
local Readable = C.Readable

function C.Num(v) v = Readable(v); return type(v) == "number" and v or nil end
function C.Str(v) v = Readable(v); return (type(v) == "string" and v ~= "") and v or nil end
function C.Bool(v) v = Readable(v); return v == true end

-- pcall that returns the results, or nothing when the call errors.
function C.Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e = pcall(fn, ...)
    if ok then return a, b, c, d, e end
end

-- "Name" -> "Name-Realm" (your realm), and back.
function C.Full(name)
    name = C.Str(name)
    if not name then return nil end
    if name:find("-", 1, true) then return name end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName() or (GetRealmName() or ""):gsub("%s", "")
    return name .. "-" .. realm
end

function C.Short(name) return name and (name:match("^([^%-]+)") or name) end

-- A unit's full name, or nil.
function C.UnitFull(unit)
    local name, realm = C.Call(UnitName, unit)
    name, realm = C.Str(name), C.Str(realm)
    if not name then return nil end
    return realm and (name .. "-" .. realm) or C.Full(name)
end

function C.UnitIsUnit(a, b)
    local v = C.Call(UnitIsUnit, a, b)
    return C.Bool(v)
end

function C.ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return c and (c.colorStr or "ffffffff") or "ffffffff"
end

-- "Name" coloured by class.
function C.Colored(name, class)
    return ("|c%s%s|r"):format(C.ClassColor(class), C.Short(name) or "?")
end

function C.SpellName(id)
    if not id or id <= 0 then return nil end
    if C_Spell and C_Spell.GetSpellName then return C.Str(C.Call(C_Spell.GetSpellName, id)) end
    if GetSpellInfo then return C.Str(C.Call(GetSpellInfo, id)) end
end

-- Group units (party1..4 or raid1..40), not including you.
function C.GroupUnits()
    local out = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            if not C.UnitIsUnit("raid" .. i, "player") then out[#out + 1] = "raid" .. i end
        end
    else
        for i = 1, GetNumSubgroupMembers() do out[#out + 1] = "party" .. i end
    end
    return out
end
