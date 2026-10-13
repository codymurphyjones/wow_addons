local _, ns = ...
local C = ns.Compat

-- An item's stats in StatLedger's stat keys, and what one point of each is worth.
local S = {}
ns.Stats = S

-- GetItemStats keys -> StatLedger stat keys. Melee and spell crit stay apart: StatLedger
-- ranks them separately. Spell hit counts as Hit, which StatLedger has only one of.
local ALIASES = {
    ITEM_MOD_STRENGTH_SHORT = "STR", ITEM_MOD_AGILITY_SHORT = "AGI", ITEM_MOD_STAMINA_SHORT = "STA",
    ITEM_MOD_INTELLECT_SHORT = "INT", ITEM_MOD_SPIRIT_SHORT = "SPI",
    ITEM_MOD_ATTACK_POWER_SHORT = "AP", ITEM_MOD_ATTACK_POWER = "AP", ITEM_MOD_MELEE_ATTACK_POWER_SHORT = "AP",
    ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "RAP", ITEM_MOD_RANGED_ATTACK_POWER = "RAP",
    ITEM_MOD_SPELL_POWER_SHORT = "SP", ITEM_MOD_SPELL_POWER = "SP",
    ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "SP", ITEM_MOD_SPELL_DAMAGE_DONE = "SP",
    ITEM_MOD_SPELL_HEALING_DONE_SHORT = "HEAL", ITEM_MOD_SPELL_HEALING_DONE = "HEAL",
    ITEM_MOD_HEALING_DONE_SHORT = "HEAL", ITEM_MOD_HEALING_DONE = "HEAL",
    ITEM_MOD_CRIT_RATING_SHORT = "CRIT", ITEM_MOD_CRIT_MELEE_RATING_SHORT = "CRIT", ITEM_MOD_CRIT_RANGED_RATING_SHORT = "CRIT",
    ITEM_MOD_CRIT_SPELL_RATING_SHORT = "SPELLCRIT", ITEM_MOD_SPELL_CRIT_RATING_SHORT = "SPELLCRIT",
    ITEM_MOD_HIT_RATING_SHORT = "HIT", ITEM_MOD_HIT_MELEE_RATING_SHORT = "HIT", ITEM_MOD_HIT_RANGED_RATING_SHORT = "HIT",
    ITEM_MOD_HIT_SPELL_RATING_SHORT = "HIT", ITEM_MOD_SPELL_HIT_RATING_SHORT = "HIT",
    ITEM_MOD_HASTE_RATING_SHORT = "HASTE", ITEM_MOD_HASTE_MELEE_RATING_SHORT = "HASTE",
    ITEM_MOD_HASTE_RANGED_RATING_SHORT = "HASTE", ITEM_MOD_HASTE_SPELL_RATING_SHORT = "HASTE",
    ITEM_MOD_MANA_REGENERATION_SHORT = "MP5", ITEM_MOD_MANA_REGENERATION = "MP5", ITEM_MOD_POWER_REGEN0_SHORT = "MP5",
    RESISTANCE0_NAME = "ARMOR", ITEM_MOD_ARMOR_SHORT = "ARMOR", ITEM_MOD_EXTRA_ARMOR_SHORT = "ARMOR",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "DEF", ITEM_MOD_DEFENSE_SKILL_RATING = "DEF",
    ITEM_MOD_DODGE_RATING_SHORT = "DODGE", ITEM_MOD_PARRY_RATING_SHORT = "PARRY",
    ITEM_MOD_BLOCK_RATING_SHORT = "BLOCK", ITEM_MOD_BLOCK_VALUE_SHORT = "BLOCKVALUE", ITEM_MOD_BLOCK_VALUE = "BLOCKVALUE",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "DPS",
}

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

-- ---------------------------------------------------------------------------
-- Tooltip scan: what GetItemStats doesn't report
-- ---------------------------------------------------------------------------
-- Classic "Equip:" lines (school spell damage, spell crit, healing...) often aren't in
-- GetItemStats. These patterns are for the English client; text is lowercased first.
local EQUIP_PATTERNS = {
    { "^increases damage and healing done by magical spells and effects by up to (%d+)", { "SP", "HEAL" } },
    { "^increases healing done by spells and effects by up to (%d+)", { "HEAL" } },
    { "^increases damage done by (%a+) spells and effects by up to (%d+)", "school" },
    { "^improves your chance to get a critical strike with spells by (%d+)%%", { "SPELLCRIT" } },
    { "^improves your chance to get a critical strike by (%d+)%%", { "CRIT" } },
    { "^improves your chance to hit with spells by (%d+)%%", { "HIT" } },
    { "^improves your chance to hit by (%d+)%%", { "HIT" } },
    { "^restores (%d+) mana per 5 sec", { "MP5" } },
    { "^%+(%d+) ranged attack power%.?$", { "RAP" } },
    { "^%+(%d+) attack power%.?$", { "AP" } }, -- not "...when fighting Undead"
    { "^increased defense %+(%d+)", { "DEF" } },
    { "^increases your chance to dodge an attack by (%d+)%%", { "DODGE" } },
    { "^increases your chance to parry an attack by (%d+)%%", { "PARRY" } },
    { "^increases your chance to block attacks with a shield by (%d+)%%", { "BLOCK" } },
    { "^increases the block value of your shield by (%d+)", { "BLOCKVALUE" } },
}
local SCHOOLS = { fire = "FIRE", frost = "FROST", shadow = "SHADOW", arcane = "ARCANE", nature = "NATURE" }

local function Prefix(global, fallback)
    return strlower(global or fallback)
end
local EQUIP = Prefix(ITEM_SPELL_TRIGGER_ONEQUIP, "Equip:")
local USE = Prefix(ITEM_SPELL_TRIGGER_ONUSE, "Use:")
local PROC = Prefix(ITEM_SPELL_TRIGGER_ONPROC, "Chance on hit:")
local UNIQUE = ITEM_UNIQUE or "Unique"
local UNIQUE_EQUIPPED = ITEM_UNIQUE_EQUIPPABLE or "Unique-Equipped"

local function FormatToPattern(fmt)
    if not fmt then return nil end
    fmt = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    return "^" .. fmt:gsub("%%[sd]", "%%d+") .. "$"
end
local LEVEL_PATTERN = FormatToPattern(ITEM_MIN_LEVEL)

local function Starts(text, prefix)
    return text:sub(1, #prefix) == prefix
end

-- Equip-line stats, whether the item has effects Tape Measure can't score, whether it is unique,
-- and whether red text says you can't use it (level requirements aside: you grow into those).
local scanner
local function Scan(link)
    if not scanner then
        scanner = CreateFrame("GameTooltip", "TapeMeasureScanTooltip", nil, "GameTooltipTemplate")
    end
    scanner:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanner:ClearLines()
    scanner:SetHyperlink(link)
    local out = { equip = {}, unscored = false, unique = false, unusable = false }
    local lines = scanner:NumLines()
    for i = 2, lines do
        for _, side in ipairs({ "TextLeft", "TextRight" }) do
            local fs = _G["TapeMeasureScanTooltip" .. side .. i]
            local text = fs and fs:GetText()
            if text and text ~= "" then
                local r, g, b = fs:GetTextColor()
                if r > 0.95 and g < 0.2 and b < 0.2 and not (LEVEL_PATTERN and text:match(LEVEL_PATTERN)) then
                    out.unusable = true
                end
                if side == "TextLeft" then
                    if text == UNIQUE or Starts(text, UNIQUE_EQUIPPED) then out.unique = true end
                    local lower = strlower(text)
                    if Starts(lower, USE) or Starts(lower, PROC) then
                        out.unscored = true
                    elseif Starts(lower, EQUIP) then
                        local body = strtrim(lower:sub(#EQUIP + 1))
                        local matched = false
                        for _, p in ipairs(EQUIP_PATTERNS) do
                            local a, b2 = body:match(p[1])
                            if a then
                                matched = true
                                if p[2] == "school" then
                                    local stat = SCHOOLS[a]
                                    if stat then out.equip[stat] = (out.equip[stat] or 0) + tonumber(b2)
                                    else out.unscored = true end -- Holy damage and the like
                                else
                                    for _, stat in ipairs(p[2]) do out.equip[stat] = (out.equip[stat] or 0) + tonumber(a) end
                                end
                                break
                            end
                        end
                        if not matched then out.unscored = true end
                    end
                end
            end
        end
    end
    -- A tooltip with only the name line hasn't loaded yet.
    return out, lines >= 2
end

local cache = {}

-- values { [stat] = amount } and info { unscored, unique, unusable, reqLevel }, or nil while
-- the item is still loading.
function S:Read(link)
    local hit = cache[link]
    if hit then return hit.values, hit.info end
    local raw = C.GetItemStats(link)
    if not raw then
        C.RequestItem(C.IDFromLink(link))
        return nil
    end
    local scanned, complete = Scan(link)
    if not complete then
        C.RequestItem(C.IDFromLink(link))
        return nil
    end
    local values = {}
    for key, v in pairs(raw) do
        local stat = type(v) == "number" and ALIASES[key]
        if stat then values[stat] = (values[stat] or 0) + v end
    end
    -- Equip lines only fill in what GetItemStats left out, so nothing counts twice.
    for stat, v in pairs(scanned.equip) do
        if not values[stat] then values[stat] = v end
    end
    local _, _, _, _, reqLevel = C.GetItemInfo(link)
    local info = { unscored = scanned.unscored, unique = scanned.unique, unusable = scanned.unusable, reqLevel = reqLevel }
    cache[link] = { values = values, info = info }
    return values, info
end

-- Learning a weapon skill or levelling can change what is usable.
function S:ClearCache() wipe(cache) end

local function Reset() S:ClearCache(); ns:Changed() end
ns:On("SKILL_LINES_CHANGED", Reset)
ns:On("PLAYER_LEVEL_UP", Reset)
