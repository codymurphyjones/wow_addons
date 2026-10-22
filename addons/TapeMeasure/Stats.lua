local _, ns = ...
local C = ns.Compat

-- An item's stats in StatLedger's stat keys, and what one point of each is worth. Reading them
-- (GetItemStats, the "Equip:" lines it misses, unique and unusable) is the shared GearEngine.lua
-- (addons/shared), the same reading SpyGlass and Wally use.
local S = {}
ns.Stats = S

-- What a point of each stat is worth comes from StatLedger (its Convert.lua), the same
-- prices SpyGlass uses: percents ("+1% crit") per percent, crit priced for your class and level.
function S:IsPercent(stat, value)
    return StatLedger:IsPercent(stat, value)
end

function S:Budget(stat, value)
    return StatLedger:Budget(stat, value)
end

function S:Label(stat)
    return StatLedger:GetStatLabel(stat)
end

-- 12 / 3.5, without a sign.
function S:FormatNumber(v)
    v = math.abs(v or 0)
    local rounded = math.floor(v + 0.5)
    if math.abs(v - rounded) < 0.05 then return tostring(rounded) end
    return ("%.1f"):format(v)
end

-- "+12 Fire Spell Power", "-1% Spell Critical Strike"
function S:FormatDelta(stat, value, percent)
    return (value < 0 and "-" or "+") .. self:FormatNumber(value) .. (percent and "%" or "") .. " " .. self:Label(stat)
end

-- values { [stat] = amount } and info { unscored, unique, unusable, reqLevel }, or nil while
-- the item is still loading.
function S:Read(link) return ns.GearEngine.Read(link) end

-- Learning a weapon skill or levelling can change what is usable.
function S:ClearCache() ns.GearEngine.ClearCache() end

local function Reset() S:ClearCache(); ns:Changed() end
ns:On("SKILL_LINES_CHANGED", Reset)
ns:On("PLAYER_LEVEL_UP", Reset)
