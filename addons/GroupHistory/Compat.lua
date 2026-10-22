local _, ns = ...

-- The game reads the rest of Group History uses, under one name (C): the secret-safe reads from
-- the shared Secrets.lua (on WoW Forever, a 12.x engine, many combat values are "secret": comparing,
-- testing or printing one is an error, so they become nil) and names, class colours and group units
-- from the shared Units.lua (character keys: realmless "Given Family" on WoW Forever).
local C = {}
ns.Compat = C

local S, U = ns.Secrets, ns.Units

C.Readable, C.Num, C.Str, C.Bool, C.Call, C.SpellName = S.Readable, S.Num, S.Str, S.Bool, S.Call, S.SpellName

-- A unit's key ("Given Family"), or its plain name when that's all the client tells; nil.
C.UnitFull = U.UnitFull
C.UnitIsUnit = U.UnitIsUnit

-- Player names (WoW Forever: realmless "Given Family"). The game hands one player's name over as
-- "Given Family", "GivenFamily" or "Given Family-Server", and some sources (UnitName's first value,
-- a unit that only tells its given name) as the given name alone.
--   SameName(a, b): one player, whatever the shapes; a given name alone matches a full name that
--                   starts with it (ns.Units.SameName).
--   IsMe(name):     you, by any of those shapes (ns.Units.IsMeLoose).
--   Canon(name):    the one shape to key a table by: your key or a group member's when the name is
--                   you or someone in your group, else ns.Units.KeyOf(name). nil for nil or secret.
--   InGroup(name):  someone in your group (not you), by any shape of the name.
C.SameName, C.IsMe, C.Canon, C.InGroup = U.SameName, U.IsMeLoose, U.Canon, U.InGroup

-- The name deaths, fights, the meter and the healing ledger are keyed by: one shape per player
-- whatever the source gave (C.Canon), the group member's key for anyone in your group. Shows as
-- the full "Given Family".
C.Short = C.Canon

function C.ClassColor(class) return (U.ClassColor(class)) end

-- "Name" coloured by class.
local SHORT = { short = true }
function C.Colored(name, class) return U.Colored(name, class, SHORT) end

-- Group units (party1..4 or raid1..40), not including you.
function C.GroupUnits() return U.GroupUnits() end
