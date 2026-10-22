local _, ns = ...

-- Safe calls and names. On WoW Forever (a 12.x engine) some values are "secret": comparing or
-- printing one is an error, so anything read from the game that might be goes through Readable.
-- (From Fireside's Compat.lua; names from the shared Units.lua.)
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

-- A name from any game source as a key: "Given Family" ("Given Family-Server" and the old saved
-- "Given-Family" shapes fold into it).
C.Full = ns.Units.KeyOf

-- A name to show: the full "Given Family" (given names repeat; the family name tells players
-- apart), without any "-Server".
C.Short = ns.Units.Display

-- You, as a key: "Given Family" ("?" before the game says).
C.Me = ns.Units.Me
