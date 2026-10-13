local _, ns = ...
local D = ns.Data

-- Whether an item belongs in the list by default: your class can equip it,
-- and its required level is within the window around your level (wider
-- for class-specific items).
local U = {}
ns.Usability = U

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local CLASSES_PREFIX = ITEM_CLASSES_ALLOWED and ITEM_CLASSES_ALLOWED:gsub("%%s.*$", "") or "Classes: "
local EFFECT_PREFIXES = {
    ITEM_SPELL_TRIGGER_ONEQUIP or "Equip:",
    ITEM_SPELL_TRIGGER_ONUSE or "Use:",
    ITEM_SPELL_TRIGGER_ONPROC or "Chance on hit:",
}

local playerClass, playerLevel
local canEquip = {}      -- [itemID] = bool (depends on class only)
local canEquipInstant = {} -- [itemID] = bool, for items not loaded yet
local classSpecific = {} -- [itemID] = bool
local facts = {}         -- [itemID] = parsed tooltip
local spellNames         -- { escaped pattern, ... } for your class's spells

function U:Init()
    playerClass = select(2, UnitClass("player"))
    playerLevel = UnitLevel("player")
end

function U:Reset(level)
    playerLevel = level or UnitLevel("player")
    wipe(canEquip)
    wipe(canEquipInstant)
    ns.Upgrades:Invalidate()
end

function U:SpellsChanged()
    spellNames = nil
    wipe(classSpecific)
    ns.Upgrades:Invalidate()
end

-- Your level; up to date during PLAYER_LEVEL_UP, before UnitLevel is.
function U:Level()
    return playerLevel or UnitLevel("player")
end

-- lo, hi, classLo: required levels shown by default.
function U:Window()
    local level = playerLevel or UnitLevel("player")
    return math.max(1, level - D.LEVELS_BELOW), level + D.LEVELS_ABOVE, math.max(1, level - D.CLASS_LEVELS_BELOW)
end

---------------------------------------------------------------------------
-- Tooltip facts
---------------------------------------------------------------------------

local function StartsWith(text, prefix)
    return prefix ~= "" and text:sub(1, #prefix) == prefix
end

-- What the tooltip says about classes and effects:
-- { classes = "Mage, Priest" or nil, classesRed = bool, effects = { line, ... } }
-- Effects are Equip:, Use:, Chance on hit: and set bonus lines.
function U:Facts(itemID)
    local cached = facts[itemID]
    if cached then return cached end
    -- Not loaded yet: what the shipped item data has (not cached, so
    -- the real tooltip counts once the item arrives).
    local info = ns:Peek(itemID)
    if info and info.baked then
        local s = ns:Shipped(itemID)
        return {
            classes = s.classes, effects = s.effects or {},
            classesRed = s.classes ~= nil and not s.classes:find((UnitClass("player")), 1, true),
        }
    end
    local lines = ns:TooltipLines(itemID)
    if not lines then return nil end
    local result = { effects = {} }
    for _, line in ipairs(lines) do
        local text = line[1]
        if StartsWith(text, CLASSES_PREFIX) then
            result.classes = text:sub(#CLASSES_PREFIX + 1)
            result.classesRed = ns.IsRed(line[3], line[4], line[5])
        elseif text:find("^%(%d+%)") then
            result.effects[#result.effects + 1] = text
        else
            for _, prefix in ipairs(EFFECT_PREFIXES) do
                if StartsWith(text, prefix) then
                    result.effects[#result.effects + 1] = text
                    break
                end
            end
        end
    end
    facts[itemID] = result
    return result
end

---------------------------------------------------------------------------
-- Class checks
---------------------------------------------------------------------------

local function Requirements()
    return AtlasLoot and AtlasLoot.Data and AtlasLoot.Data.Requirements
end

-- AtlasLoot's class data restricts the item to some classes, yours among them.
local function RestrictedToYourClass(itemID)
    local req = Requirements()
    if not (req and req.HasRequirements and req.ClassCanUseItem) then return false end
    if not req.HasRequirements(itemID) or not req.ClassCanUseItem(playerClass, itemID) then return false end
    for _, class in ipairs(CLASSES) do
        if not req.ClassCanUseItem(class, itemID) then return true end
    end
    return false
end

-- Armor and weapon type (SpyGlass's proficiency table) and AtlasLoot's
-- class restrictions: only what the game knows without asking the server.
local function Proficient(itemID)
    playerClass = playerClass or select(2, UnitClass("player"))
    local req = Requirements()
    if req and req.ClassCanUseItem and not req.ClassCanUseItem(playerClass, itemID) then return false end
    local _, _, _, classID, subClassID = ns:Instant(itemID)
    local known = D.CLASS_PROFICIENCY[playerClass]
    if known and subClassID then
        if classID == 4 and subClassID ~= 0 then return known.armor[subClassID] or false end
        if classID == 2 and subClassID ~= 14 and subClassID ~= 20 then return known.weapon[subClassID] or false end
    end
    return true
end

-- Can your class wear or wield it (now or once trained)? Only what the
-- class can equip counts, never what suits it: which stats matter is your
-- StatLedger priority's call, so a hunter still sees leather and a warrior
-- cloth (AtlasLoot's ClassFilter, a "suits the class" filter that drops
-- leather for hunters and whole stats per class, isn't used). A red
-- "Classes:" line means another class's item.
function U:CanEquip(itemID)
    local cached = canEquip[itemID]
    if cached ~= nil then return cached end
    local result = Proficient(itemID)
    if result then
        local f = self:Facts(itemID)
        if f and f.classes and f.classesRed then result = false end
    end
    canEquip[itemID] = result
    return result
end

-- The same check for items not loaded yet: leaves out the tooltip's
-- "Classes:" line (CanEquip checks it once the item has loaded). Lists run
-- it on every candidate at every redraw, so it never asks the server.
function U:CanEquipInstant(itemID)
    if canEquip[itemID] ~= nil then return canEquip[itemID] end
    local cached = canEquipInstant[itemID]
    if cached ~= nil then return cached end
    local result = Proficient(itemID)
    canEquipInstant[itemID] = result
    return result
end

-- Escaped patterns for the spells in your class's spellbook tabs.
local function SpellPatterns()
    if spellNames then return spellNames end
    spellNames = {}
    local seen = {}
    local bank = BOOKTYPE_SPELL or "spell"
    local numTabs = GetNumSpellTabs and GetNumSpellTabs() or 0
    for tab = 2, numTabs do -- tab 1 is General
        local _, _, offset, count = GetSpellTabInfo(tab)
        for i = (offset or 0) + 1, (offset or 0) + (count or 0) do
            local name
            if GetSpellBookItemName then
                name = GetSpellBookItemName(i, bank)
            elseif C_SpellBook and C_SpellBook.GetSpellBookItemName then
                name = C_SpellBook.GetSpellBookItemName(i, Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0)
            elseif GetSpellName then
                name = GetSpellName(i, bank)
            end
            if name and #name > 3 and not seen[name] and not D.SPELL_STOPLIST[name] then
                seen[name] = true
                spellNames[#spellNames + 1] = "%f[%a]" .. name:gsub("%p", "%%%0") .. "%f[%A]"
            end
        end
    end
    return spellNames
end

-- Items made for your class: restricted to it, a libram/totem/idol, or an
-- effect that names one of your class's spells.
function U:IsClassSpecific(itemID)
    local cached = classSpecific[itemID]
    if cached ~= nil then return cached end
    local f = self:Facts(itemID)
    if not f then return false end
    local result = (f.classes and not f.classesRed) or RestrictedToYourClass(itemID)
        or ns:Instant(itemID) == "INVTYPE_RELIC"
    if not result then
        local patterns = SpellPatterns()
        for _, text in ipairs(f.effects) do
            for _, pattern in ipairs(patterns) do
                if text:find(pattern) then result = true break end
            end
            if result then break end
        end
    end
    classSpecific[itemID] = result and true or false
    return classSpecific[itemID]
end

---------------------------------------------------------------------------
-- The default filter
---------------------------------------------------------------------------

-- true, false, or "pending" while the item's info is still on its way.
-- With showAll every equippable item counts.
-- Only looks at what the game already has: never asks the server (lists
-- ask for the rows they draw).
function U:Status(itemID, showAll)
    local info = ns:Peek(itemID)
    if not info then return ns:IsUnavailable(itemID) and false or "pending" end
    if showAll then return true end
    if not self:CanEquip(itemID) then return false end
    local lo, hi, classLo = self:Window()
    local level = info.fitLevel or info.reqLevel
    if level > hi then return false end
    if level >= lo then return true end
    return level >= classLo and self:IsClassSpecific(itemID)
end

-- Why Status says no, in a few words (for /sg debug).
function U:Reason(itemID)
    local info = ns:Peek(itemID)
    if not info then
        if ns:IsEncrypted(itemID) then return "encrypted by the client (hidden)" end
        return ns:IsUnavailable(itemID) and "the server never sent its details" or "item info loading"
    end
    if not self:CanEquip(itemID) then return "your class can't use it" end
    local lo, hi = self:Window()
    local level, what = info.fitLevel or info.reqLevel, info.noReq and "for level ~" or "req "
    if level > hi then return "level too high (" .. what .. level .. ")" end
    if level < lo then return "level too low (" .. what .. level .. ")" end
    return "ok"
end
