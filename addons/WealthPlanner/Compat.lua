local _, ns = ...

-- Wealth Planner's game API helpers. Items and bags (C_Item / C_Container)
-- come from the shared Items.lua: every ns.Items function answers as Compat.X too.
local Compat = setmetatable({}, { __index = ns.Items })
ns.Compat = Compat

function Compat.Money(copper) return ns.Format.Money(copper) end
