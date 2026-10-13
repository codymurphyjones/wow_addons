local _, ns = ...
local C = ns.Compat

-- Decides whether a grey/white armor or weapon piece in your bags might beat what you wear.
-- Rules: an empty slot is always an upgrade; any non-armor stat beats a pure-armor piece;
-- between two pure-armor pieces the higher armor (or weapon DPS) wins; when both carry
-- extra stats it isn't judged here.
local Gear = {}
ns.Gear = Gear

local CLASS_WEAPON, CLASS_ARMOR = 2, 4
local POOR, COMMON = 0, 1

local SLOT_MAP = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
}

local ARMOR_KEYS = { RESISTANCE0_NAME = true, ITEM_MOD_ARMOR_SHORT = true, ITEM_MOD_EXTRA_ARMOR_SHORT = true }
local DPS_KEY = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT"
local BLOCK_KEYS = { ITEM_MOD_BLOCK_VALUE_SHORT = true, ITEM_MOD_BLOCK_VALUE = true }

local cache = {}

local function FormatToPattern(fmt, capture)
    if not fmt then return nil end
    fmt = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    return "^" .. fmt:gsub("%%[sd]", capture and "(%%d+)" or "%%d+") .. "$"
end
local LEVEL_PATTERN = FormatToPattern(ITEM_MIN_LEVEL)
local ARMOR_PATTERN = FormatToPattern(ARMOR_TEMPLATE, true)

local scanner
local function Scan(link)
    if not scanner then
        scanner = CreateFrame("GameTooltip", "WallyScanTooltip", nil, "GameTooltipTemplate")
        scanner:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    scanner:ClearLines()
    scanner:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanner:SetHyperlink(link)
    local usable, armor = true, nil
    for i = 2, scanner:NumLines() do
        for _, side in ipairs({ "TextLeft", "TextRight" }) do
            local fs = _G["WallyScanTooltip" .. side .. i]
            local text = fs and fs:GetText()
            if text and text ~= "" then
                local r, g, b = fs:GetTextColor()
                -- Red text = a requirement you don't meet. Level requirements are ignored:
                -- you'll grow into the item.
                if r > 0.95 and g < 0.2 and b < 0.2 and not (LEVEL_PATTERN and text:match(LEVEL_PATTERN)) then
                    usable = false
                end
                if not armor and ARMOR_PATTERN then
                    local a = text:match(ARMOR_PATTERN)
                    if a then armor = tonumber(a) end
                end
            end
        end
    end
    -- A tooltip with only the name line hasn't loaded yet; its "usable" answer means nothing.
    return usable, armor, scanner:NumLines() >= 2
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
    if p.armor == 0 then
        local _, scanned = Scan(link)
        p.armor = scanned or 0
    end
    p.hasExtras = #p.extras > 0
    return p
end

local function CanDualWield()
    if IsPlayerSpell then return IsPlayerSpell(674) end
    if IsSpellKnown then return IsSpellKnown(674) end
end

-- Compares a candidate with one equipped slot. Returns isBetter, detail; nil detail means "not judged".
local function CompareTo(new, slotID, equipLoc)
    local equippedLink = GetInventoryItemLink("player", slotID)
    if not equippedLink then return true, "empty slot" end
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

local function Evaluate(link)
    local _, _, quality, _, _, _, _, _, equipLoc, _, _, classID = C.GetItemInfo(link)
    if not quality then return nil, "loading" end
    if quality > COMMON or quality < POOR then return false end
    if classID ~= CLASS_ARMOR and classID ~= CLASS_WEAPON then return false end
    local slots = SLOT_MAP[equipLoc or ""]
    if not slots then return false end
    if not C.IsEquippableItem(link) then return false end
    local usable = Scan(link)
    if not usable then return false, "can't use" end

    local mainLink = GetInventoryItemLink("player", 16)
    local mainLoc = mainLink and select(9, C.GetItemInfo(mainLink))
    if slots[1] == 17 and mainLoc == "INVTYPE_2HWEAPON" then return false, "two-hander equipped" end
    if equipLoc == "INVTYPE_WEAPON" and CanDualWield() then slots = { 16, 17 } end

    local new = Profile(link, equipLoc)
    if not new then return nil, "loading" end
    -- Two-slot items are upgrades if they beat the weaker of the two equipped pieces.
    local lastDetail
    for _, slotID in ipairs(slots) do
        local better, detail = CompareTo(new, slotID, equipLoc)
        if better then return true, detail end
        lastDetail = detail
    end
    return false, lastDetail
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
    if (classID == CLASS_ARMOR or classID == CLASS_WEAPON) and SLOT_MAP[equipLoc or ""] then
        local usable, _, complete = Scan(link)
        if not complete then
            -- Ask again next time instead of remembering a half-loaded answer.
            C.RequestItem(C.IDFromLink(link))
            return false
        end
        result = not usable
    end
    unusableCache[link] = result
    return result
end

-- Enchanting (skill line 333) means unusable greens and better are worth disenchanting.
local ENCHANTING_SKILL = 333
local hasEnchanting
function Gear:HasEnchanting()
    if hasEnchanting ~= nil then return hasEnchanting end
    hasEnchanting = false
    if GetProfessions and GetProfessionInfo then
        for _, index in pairs({ GetProfessions() }) do
            if index and select(7, GetProfessionInfo(index)) == ENCHANTING_SKILL then hasEnchanting = true end
        end
    elseif GetNumSkillLines and GetSkillLineInfo then
        local spellName = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(7411))
            or (GetSpellInfo and GetSpellInfo(7411)) or "Enchanting"
        for i = 1, GetNumSkillLines() do
            local name, isHeader = GetSkillLineInfo(i)
            if not isHeader and name == spellName then hasEnchanting = true end
        end
    end
    return hasEnchanting
end

function Gear:ClearCache() wipe(cache); wipe(unusableCache); hasEnchanting = nil end

local function Invalidate() Gear:ClearCache(); if ns.db then ns:Changed() end end
ns:On("PLAYER_EQUIPMENT_CHANGED", Invalidate)
ns:On("SKILL_LINES_CHANGED", Invalidate)
ns:On("PLAYER_LEVEL_UP", Invalidate)
ns:On("SPELLS_CHANGED", Invalidate)
