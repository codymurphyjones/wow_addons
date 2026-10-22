local _, ns = ...

-- Tape Measure's client differences. Items and bags come from the shared Items.lua: every
-- ns.Items function answers as Compat.X too.
local Compat = setmetatable({}, { __index = ns.Items })
ns.Compat = Compat

function Compat.CanDualWield()
    if IsPlayerSpell then return IsPlayerSpell(674) end
    if IsSpellKnown then return IsSpellKnown(674) end
end

-- Every backpack/bag slot holding an item: for bag, slot, link in Compat.IterateBags() do ... end
function Compat.IterateBags() return ns.Items.IterateBags(nil, "link") end
