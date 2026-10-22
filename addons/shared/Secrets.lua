local _, ns = ...

-- Secret-safe reads, shared by the addons that read combat data (addons/shared, copied into each
-- addon's Shared\ folder by the build). On WoW Forever (a 12.x engine) many combat values are
-- "secret": comparing, testing or printing one is an error. These turn a secret (or failing) value
-- into nil. Each addon gets its own copy in its own namespace (ns.Secrets), so they never clash.
local S = {}
ns.Secrets = S

-- A value we may read, or nil for a secret one.
function S.Readable(v)
    if v == nil then return nil end
    if canaccessvalue and not canaccessvalue(v) then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
local Readable = S.Readable

function S.Num(v) v = Readable(v); return type(v) == "number" and v or nil end
function S.Str(v) v = Readable(v); return (type(v) == "string" and v ~= "") and v or nil end
function S.Bool(v) v = Readable(v); return v == true end

-- pcall that returns the results, or nothing when the call errors.
function S.Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local r = { pcall(fn, ...) }
    if r[1] then return unpack(r, 2, table.maxn(r)) end
end

-- "Name-Realm" -> "Name"
function S.Short(name) return name and (name:match("^([^%-]+)") or name) end

function S.SpellName(id)
    if not id or id <= 0 then return nil end
    if C_Spell and C_Spell.GetSpellName then return S.Str(S.Call(C_Spell.GetSpellName, id)) end
    if GetSpellInfo then return S.Str(S.Call(GetSpellInfo, id)) end
end
