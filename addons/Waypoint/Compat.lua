local _, ns = ...

-- Safe calls and names. On WoW Forever (a 12.x engine) some values are "secret": comparing or
-- printing one is an error, so anything read from the game that might be goes through Readable.
-- (From GroupHistory's Compat.lua.)
local C = {}
ns.Compat = C

-- A value we may read, or nil for a secret one.
function C.Readable(v)
    if v == nil then return nil end
    if canaccessvalue and not canaccessvalue(v) then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

function C.Num(v) v = C.Readable(v); return type(v) == "number" and v or nil end

-- pcall that returns the results, or nothing when the call errors.
function C.Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e = pcall(fn, ...)
    if ok then return a, b, c, d, e end
end

-- "Name" -> "Name-Realm" (your realm).
function C.Full(name)
    if type(C.Readable(name)) ~= "string" or name == "" then return nil end
    if name:find("-", 1, true) then return name end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName() or (GetRealmName() or ""):gsub("%s", "")
    return name .. "-" .. realm
end

function C.Short(name) return name and (name:match("^([^%-]+)") or name) end

-- You, as "Name-Realm".
function C.Me() return C.Full(UnitName("player")) or "?" end
