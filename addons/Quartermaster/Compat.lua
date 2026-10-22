local _, ns = ...

-- Quartermaster's game API helpers. Items come from the shared Items.lua: every ns.Items
-- function answers as Compat.X too.
local Compat = setmetatable({}, { __index = ns.Items })
ns.Compat = Compat

function Compat.Money(copper) return ns.Format.Money(copper) end

-- Whether an auction owner name is you. WoW Forever names are "Given Family"; the auction house may
-- give the owner as "Given Family", "GivenFamily", "Given Family-Server" or only the given name, so a
-- one-word owner matches your given name (the auction house can't tell more apart then).
local ownerCache, cacheFor = {}, nil
function Compat.OwnerIsMe(owner)
    if owner == nil then return false end
    local me = ns.Units.CharKey()
    if me ~= cacheFor then ownerCache, cacheFor = {}, me end
    local hit = ownerCache[owner]
    if hit ~= nil then return hit end
    local mine = ns.Units.IsMeLoose(owner)
    if type(owner) == "string" then ownerCache[owner] = mine end
    return mine
end
