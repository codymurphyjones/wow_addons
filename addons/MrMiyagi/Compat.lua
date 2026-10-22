local _, ns = ...

-- MrMiyagi's game reads, under the names the addon's files call (ns.Compat.X). On WoW Forever (a
-- 12.x engine) many combat values are "secret": comparing, testing or printing one is an error.
-- The secret-safe guards are shared\Secrets.lua's, names and group units shared\Units.lua's, and
-- the text of spell, talent and item tooltips comes from shared\Tooltip.lua.
local S, U, T = ns.Secrets, ns.Units, ns.Tooltip
local C = {}
ns.Compat = C

-- A value we may read (nil for a secret one), typed reads, and a pcall that returns the results.
C.Readable, C.Num, C.Str, C.Bool, C.Call, C.SpellName = S.Readable, S.Num, S.Str, S.Bool, S.Call, S.SpellName

-- Names: a name's key ("Given Family", the realmless WoW Forever name) and its shown form; a unit's key.
C.Full, C.Short, C.UnitFull, C.UnitIsUnit = U.Full, U.Short, U.UnitFull, U.UnitIsUnit

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

-- You, in the shape C.Canon gives the meter's names (the healing ledger is keyed by it).
C.Me = U.MeCanon

function C.ClassColor(class) return (U.ClassColor(class)) end

-- "Name" coloured by class.
local SHORT = { short = true }
function C.Colored(name, class) return U.Colored(name, class, SHORT) end

-- Group units (party1..4 or raid1..40), not including you.
function C.GroupUnits() return U.GroupUnits() end

-- The text lines of a spell's, talent's or item's tooltip (left then right, empty ones skipped),
-- read without showing anything.
function C.SpellLines(id) return T.Texts(T.Lines("spell", id)) end
function C.TalentLines(tab, index) return T.Texts(T.Lines("talent", tab, index)) end
function C.BagItemLines(bag, slot) return T.Texts(T.Lines("bag", bag, slot)) end
function C.ItemLines(link) return T.Texts(T.Lines("hyperlink", link)) end
