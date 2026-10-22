local _, ns = ...
local C = ns.Compat

-- Decides whether a grey/white armor or weapon piece in your bags might beat what you wear, with
-- the shared GearEngine.lua (addons/shared): the same verdict Tape Measure and SpyGlass give, by
-- your StatLedger stat priority. An empty slot is always an upgrade. When nothing your priority
-- ranks tells the two apart (plain armor and weapons), the old rules decide: any extra stat beats
-- pure armor, then the higher weapon DPS, then the higher armor. It only ever keeps an item.
local Gear = {}
ns.Gear = Gear

local E = ns.GearEngine
local CLASS_WEAPON, CLASS_ARMOR = ns.Items.CLASS.WEAPON, ns.Items.CLASS.ARMOR
local POOR, COMMON = 0, 1

local ARMOR_KEYS = { RESISTANCE0_NAME = true, ITEM_MOD_ARMOR_SHORT = true, ITEM_MOD_EXTRA_ARMOR_SHORT = true }
local DPS_KEY = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT"
local BLOCK_KEYS = { ITEM_MOD_BLOCK_VALUE_SHORT = true, ITEM_MOD_BLOCK_VALUE = true }

local cache = {}

local function FormatToPattern(fmt)
    if not fmt then return nil end
    fmt = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    return "^" .. fmt:gsub("%%[sd]", "(%%d+)") .. "$"
end
local ARMOR_PATTERN = FormatToPattern(ARMOR_TEMPLATE)

-- Armor from the tooltip, for clients whose GetItemStats leaves it out.
local function ScanArmor(link)
    if not ARMOR_PATTERN then return nil end
    local _, _, a = ns.Tooltip.Find(ns.Tooltip.Lines("hyperlink", link), ARMOR_PATTERN)
    return tonumber(a)
end

-- Summarizes an item: armor, dps, and the list of extra (non-base) stats.
local function Profile(link, equipLoc)
    local stats = C.GetItemStats(link)
    if not stats then return nil end
    local p = { armor = 0, dps = 0, extras = {} }
    for k, v in pairs(stats) do
        if type(v) == "number" then
            if ARMOR_KEYS[k] then
                p.armor = p.armor + v
            elseif k == DPS_KEY then
                p.dps = v
            elseif BLOCK_KEYS[k] and equipLoc == "INVTYPE_SHIELD" then
                -- Block is a shield's base stat, like armor.
            elseif v > 0 then
                local label = _G[k] or k
                p.extras[#p.extras + 1] = ("+%s %s"):format(v, label)
            end
        end
    end
    if p.armor == 0 then p.armor = ScanArmor(link) or 0 end
    p.hasExtras = #p.extras > 0
    return p
end

-- The old rules, against one equipped piece. Returns isBetter, detail.
local function CompareTo(new, equippedLink, equipLoc)
    local old = Profile(equippedLink, equipLoc)
    if not old then return true, "checking equipped item" end
    if new.hasExtras and not old.hasExtras then
        return true, table.concat(new.extras, ", ") .. " vs pure armor"
    end
    if old.hasExtras and not new.hasExtras then return false, "equipped has stats" end
    if new.hasExtras and old.hasExtras then return false, "both have stats" end
    if new.dps > 0 or old.dps > 0 then
        if new.dps > old.dps then return true, ("+%.1f DPS"):format(new.dps - old.dps) end
        return false, ("%.1f DPS lower"):format(old.dps - new.dps)
    end
    if new.armor > old.armor then return true, ("+%d armor"):format(new.armor - old.armor) end
    return false, ("%d armor lower"):format(old.armor - new.armor)
end

local function Label(stat)
    return StatLedger and StatLedger.GetStatLabel and StatLedger:GetStatLabel(stat) or stat
end

-- "+4.2% (+3 Stamina, +2 Strength)"
local function Detail(cmp)
    local parts = {}
    for i = 1, math.min(2, #cmp.deltas) do
        local d = cmp.deltas[i]
        parts[i] = ("%s%s%s %s"):format(d.value < 0 and "-" or "+", math.floor(math.abs(d.value) + 0.5), d.percent and "%" or "", Label(d.stat))
    end
    local head = cmp.percent and ("%+.1f%%"):format(cmp.percent) or ("%+.1f"):format(cmp.diff or 0)
    return #parts > 0 and (head .. " (" .. table.concat(parts, ", ") .. ")") or head
end

local function Evaluate(link)
    local _, _, quality, _, _, _, _, _, equipLoc, _, _, classID = C.GetItemInfo(link)
    if not quality then return nil, "loading" end
    if quality > COMMON or quality < POOR then return false end
    if classID ~= CLASS_ARMOR and classID ~= CLASS_WEAPON then return false end
    if not E.SLOT_MAP[equipLoc or ""] then return false end
    if not C.IsEquippableItem(link) then return false end
    local values, info = E.Read(link)
    if not values then return nil, "loading" end
    if info.unusable then return false, "can't use" end

    local cmp = E.Compare(link)
    if not cmp then return nil, "loading" end
    if cmp.verdict == "none" then return false, cmp.reason end
    if cmp.verdict == "equipped" then return false, "equipped" end
    if cmp.verdict == "new" then return true, "empty slot" end
    if cmp.verdict == "upgrade" then return true, Detail(cmp) end
    -- Your stat priority can't tell them apart: plain armor and weapons go by the old rules.
    if math.abs(cmp.new.total) < 0.05 and math.abs(cmp.base or 0) < 0.05 then
        local new = Profile(link, equipLoc)
        if not new then return nil, "loading" end
        local lastDetail
        for _, worn in ipairs(cmp.replaced) do
            local better, detail = CompareTo(new, worn, equipLoc)
            if better then return true, detail end
            lastDetail = detail
        end
        return false, lastDetail
    end
    return false, cmp.verdict
end

-- Returns isUpgrade, detail. isUpgrade is nil while item data is still loading.
function Gear:IsPossibleUpgrade(link)
    if not link then return false end
    local hit = cache[link]
    if hit then return hit[1], hit[2] end
    local result, detail = Evaluate(link)
    if result ~= nil then cache[link] = { result, detail } end
    return result, detail
end

-- True for armor/weapons this character can never use (wrong class, armor type or weapon
-- skill). Level requirements don't count: you'll grow into those.
local unusableCache = {}
function Gear:IsUnusableGear(link)
    if not link then return false end
    local hit = unusableCache[link]
    if hit ~= nil then return hit end
    local _, _, quality, _, _, _, _, _, equipLoc, _, _, classID = C.GetItemInfo(link)
    if not quality then return false end
    local result = false
    if (classID == CLASS_ARMOR or classID == CLASS_WEAPON) and E.SLOT_MAP[equipLoc or ""] then
        -- Not loaded yet: ask again next time instead of remembering a half-loaded answer.
        local values, info = E.Read(link)
        if not values then return false end
        result = info.unusable
    end
    unusableCache[link] = result
    return result
end

-- Enchanting means unusable greens and better are worth disenchanting.
function Gear:HasEnchanting() return ns.Player.HasEnchanting() end

function Gear:ClearCache() wipe(cache); wipe(unusableCache); ns.Player.Invalidate(); E.Invalidate() end

local function Invalidate() Gear:ClearCache(); if ns.db then ns:Changed() end end
ns:On("PLAYER_EQUIPMENT_CHANGED", Invalidate)
ns:On("SKILL_LINES_CHANGED", Invalidate)
ns:On("PLAYER_LEVEL_UP", Invalidate)
ns:On("SPELLS_CHANGED", Invalidate)
-- A new stat priority changes the verdicts.
ns:On("PLAYER_LOGIN", function()
    if StatLedger and StatLedger.RegisterCallback then StatLedger:RegisterCallback("Wally", Invalidate) end
end)
