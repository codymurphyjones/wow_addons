local _, ns = ...

-- Stat priority: which stats matter to this character, best first. Buffs,
-- enhancement potions and buff food are ranked by the stats on their tooltip.
local T = {}
ns.Stats = T

-- Stats, in the order the settings dropdowns list them.
T.ORDER = {
    "STR", "AGI", "STA", "INT", "SPI", "AP", "SP", "HEAL", "CRIT", "SPELLCRIT", "HIT", "ARMOR", "MP5",
    "FIRE", "FROST", "SHADOW", "ARCANE", "NATURE",
}

T.LABELS = {
    STR = "Strength", AGI = "Agility", STA = "Stamina", INT = "Intellect", SPI = "Spirit",
    AP = "Attack Power", SP = "Spell Power", HEAL = "Healing", CRIT = "Critical Strike",
    SPELLCRIT = "Spell Critical Strike",
    HIT = "Hit", ARMOR = "Armor", MP5 = "Mana Regeneration",
    FIRE = "Fire Spell Power", FROST = "Frost Spell Power", SHADOW = "Shadow Spell Power",
    ARCANE = "Arcane Spell Power", NATURE = "Nature Spell Power",
}

-- How each stat appears in "Use:" text (lower case), checked in this order.
-- Matched phrases are removed before later checks, so "frost spell damage"
-- counts as Frost Spell Power only (not Spell Power too), and "critical
-- strike with spells" as Spell Critical Strike only. Maximum health and mana
-- count as Stamina and Intellect. enUS only.
local PATTERNS = {
    { "FIRE", { "fire spell damage", "spell fire damage", "fire damage" } },
    { "FROST", { "frost spell damage", "spell frost damage", "frost damage" } },
    { "SHADOW", { "shadow spell damage", "spell shadow damage", "shadow damage" } },
    { "ARCANE", { "arcane spell damage", "spell arcane damage", "arcane damage" } },
    { "NATURE", { "nature spell damage", "spell nature damage", "nature damage" } },
    { "SPELLCRIT", { "critical strike with spells", "spell critical", "critical strike with your spells" } },
    { "SP", { "spell damage", "damage done by magical spells", "damage and healing", "spell power" } },
    { "HEAL", { "healing done", "healing spells" } }, -- "damage and healing": see ItemStats
    { "CRIT", { "critical" } },
    { "HIT", { "chance to hit", "hit rating" } },
    { "STR", { "strength" } },
    { "AGI", { "agility" } },
    { "STA", { "stamina", "maximum health" } },
    { "INT", { "intellect", "maximum mana" } },
    { "SPI", { "spirit" } },
    { "AP", { "attack power" } },
    { "ARMOR", { "armor" } },
    { "MP5", { "mana every 5", "mana per 5", "mana every five", "mana regeneration" } },
}

-- Talent trees in the game's tab order, with each spec's default priority.
-- [class] = { default tab before talents, { name, { stats } } x3 }
T.SPECS = {
    WARRIOR = { 1,
        { "Arms", { "STR", "AP", "CRIT", "AGI", "STA" } },
        { "Fury", { "STR", "AP", "CRIT", "AGI", "HIT" } },
        { "Protection", { "STA", "ARMOR", "STR", "AGI", "AP" } } },
    ROGUE = { 2,
        { "Assassination", { "AGI", "AP", "CRIT", "STR", "HIT" } },
        { "Combat", { "AGI", "AP", "CRIT", "STR", "HIT" } },
        { "Subtlety", { "AGI", "AP", "CRIT", "STR", "STA" } } },
    HUNTER = { 1,
        { "Beast Mastery", { "AGI", "AP", "CRIT", "HIT", "INT" } },
        { "Marksmanship", { "AGI", "AP", "CRIT", "HIT", "INT" } },
        { "Survival", { "AGI", "AP", "CRIT", "STA", "INT" } } },
    MAGE = { 3,
        { "Arcane", { "SP", "ARCANE", "INT", "SPI", "MP5" } },
        { "Fire", { "SP", "FIRE", "SPELLCRIT", "INT", "MP5" } },
        { "Frost", { "SP", "FROST", "SPELLCRIT", "INT", "MP5" } } },
    WARLOCK = { 1,
        { "Affliction", { "SP", "SHADOW", "STA", "INT", "SPI" } },
        { "Demonology", { "SP", "SHADOW", "STA", "INT", "SPI" } },
        { "Destruction", { "SP", "SHADOW", "SPELLCRIT", "INT", "STA" } } },
    PRIEST = { 2,
        { "Discipline", { "HEAL", "INT", "SPI", "MP5", "STA" } },
        { "Holy", { "HEAL", "INT", "SPI", "MP5", "STA" } },
        { "Shadow", { "SP", "SHADOW", "INT", "SPI", "STA" } } },
    PALADIN = { 3,
        { "Holy", { "HEAL", "INT", "MP5", "SPELLCRIT", "STA" } },
        { "Protection", { "STA", "ARMOR", "SP", "STR", "AGI" } },
        { "Retribution", { "STR", "AP", "CRIT", "AGI", "INT" } } },
    DRUID = { 2,
        { "Balance", { "SP", "ARCANE", "NATURE", "INT", "MP5" } },
        { "Feral", { "AGI", "STR", "AP", "STA", "ARMOR" } },
        { "Restoration", { "HEAL", "INT", "SPI", "MP5", "STA" } } },
    SHAMAN = { 2,
        { "Elemental", { "SP", "NATURE", "SPELLCRIT", "INT", "MP5" } },
        { "Enhancement", { "STR", "AP", "AGI", "CRIT", "INT" } },
        { "Restoration", { "HEAL", "INT", "MP5", "SPI", "STA" } } },
}

T.CLASS_NAMES = {
    WARRIOR = "Warrior", ROGUE = "Rogue", HUNTER = "Hunter", MAGE = "Mage", WARLOCK = "Warlock",
    PRIEST = "Priest", PALADIN = "Paladin", DRUID = "Druid", SHAMAN = "Shaman",
}
T.CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

T.SLOTS = 5
local WEIGHTS = { 10, 6, 4, 2, 1 } -- 1st stat counts most

---------------------------------------------------------------------------
-- Spec detection
---------------------------------------------------------------------------

-- Points spent in a talent tab. The return values of GetTalentTabInfo
-- differ between clients: (name, icon, points, ...) or (id, name, desc,
-- icon, points, ...).
local function TabPoints(tab)
    if not GetTalentTabInfo then return 0 end
    local a, _, c, _, e = GetTalentTabInfo(tab)
    if type(a) == "string" then return tonumber(c) or 0 end
    return tonumber(e) or 0
end

-- The talent tab with the most points, or the class's default before talents.
function T:DetectedTab()
    local _, class = UnitClass("player")
    local specs = self.SPECS[class]
    if not specs then return end
    local best, bestPoints = specs[1], 0
    for tab = 1, 3 do
        local points = TabPoints(tab)
        if points > bestPoints then best, bestPoints = tab, points end
    end
    return best
end

---------------------------------------------------------------------------
-- Presets and the current priority
---------------------------------------------------------------------------

-- Preset ids are "auto" or "CLASS:tab" (e.g. "PRIEST:2").
function T.PresetLabel(id)
    if id == "auto" then return "Automatic (your class and spec)" end
    local class, tab = id:match("^(%u+):(%d)$")
    local specs = class and T.SPECS[class]
    local spec = specs and specs[tonumber(tab) + 1]
    if not spec then return id end
    return T.CLASS_NAMES[class] .. ": " .. spec[1]
end

-- Every preset id, Automatic first, then class by class.
function T.PresetIds()
    local ids = { "auto" }
    for _, class in ipairs(T.CLASS_ORDER) do
        for tab = 1, 3 do ids[#ids + 1] = class .. ":" .. tab end
    end
    return ids
end

-- The stats StatLedger (a separate, optional addon) has for your spec,
-- trimmed to the stats Bandolier knows and to T.SLOTS. nil without it.
function T:SharedStats()
    if not (StatLedger and StatLedger.GetPriority) then return end
    local list = {}
    for _, stat in ipairs(StatLedger:GetPriority()) do
        if T.LABELS[stat] and #list < self.SLOTS then list[#list + 1] = stat end
    end
    return list
end

-- The stats of a preset ("auto" resolves to the detected class and spec,
-- or to StatLedger when it is installed).
function T:PresetStats(id)
    if id == "auto" then
        local shared = self:SharedStats()
        if shared then return shared end
        local _, class = UnitClass("player")
        local tab = self:DetectedTab()
        if not tab then return { "STA", "STR", "AGI", "INT", "SPI" } end
        id = class .. ":" .. tab
    end
    local class, tab = id:match("^(%u+):(%d)$")
    local spec = class and self.SPECS[class] and self.SPECS[class][tonumber(tab) + 1]
    return spec and spec[2] or {}
end

function T:Preset()
    return ns.db.statPreset or "auto"
end

-- The priority in use: your own five slots if you changed any, else the preset.
function T:Priority()
    return ns.db.statCustom or self:PresetStats(self:Preset())
end

function T:SetPreset(id)
    ns.db.statPreset = id
    ns.db.statCustom = nil
    ns:RequestRefresh()
end

-- Changing one slot turns the current priority into your own custom one.
function T:SetSlot(slot, stat)
    local custom = {}
    for i, s in ipairs(self:Priority()) do custom[i] = s end
    custom[slot] = stat ~= "NONE" and stat or nil
    -- keep it a list: close gaps left by "none"
    local packed = {}
    for i = 1, self.SLOTS do
        if custom[i] then packed[#packed + 1] = custom[i] end
    end
    ns.db.statCustom = packed
    ns:RequestRefresh()
end

function T:Describe()
    local names = {}
    for i, stat in ipairs(self:Priority()) do names[i] = T.LABELS[stat] or stat end
    local source = ns.db.statCustom and "custom" or T.PresetLabel(self:Preset())
    if self:Preset() == "auto" and not ns.db.statCustom then
        local _, class = UnitClass("player")
        local tab = self:DetectedTab()
        if self:SharedStats() then
            source = source .. " -> StatLedger"
        elseif tab then
            source = source .. " -> " .. T.PresetLabel(class .. ":" .. tab)
        end
    end
    return table.concat(names, " > "), source
end

---------------------------------------------------------------------------
-- Scoring items
---------------------------------------------------------------------------

local itemStats = {} -- [itemID] = { stats = { [stat] = true }, amount = n }

-- The stats an item's "Use:" text mentions, and the amount it gives.
local function ItemStats(itemID)
    local cached = itemStats[itemID]
    if cached then return cached end
    local text = (ns.ItemUseText(itemID) or ""):lower():gsub(",", "")
    local stats = {}
    if text:find("damage and healing", 1, true) then stats.HEAL = true end
    local rest = text
    for _, rule in ipairs(PATTERNS) do
        for _, pattern in ipairs(rule[2]) do
            local i, j = rest:find(pattern, 1, true)
            if i then
                stats[rule[1]] = true
                rest = rest:sub(1, i - 1) .. " " .. rest:sub(j + 1)
                break
            end
        end
    end
    -- The stat amount: numbers after "by" ("Strength by 25", "by up to 35"),
    -- not durations ("for 30 min") or other numbers.
    local amount = 0
    for digits in text:gmatch("by up to (%d+)") do
        local n = tonumber(digits)
        if n and n > amount then amount = n end
    end
    for digits in text:gmatch("by (%d+)") do
        local n = tonumber(digits)
        if n and n > amount then amount = n end
    end
    cached = { stats = stats, amount = amount }
    if text ~= "" then itemStats[itemID] = cached end
    return cached
end

-- Does the item give any stat for a stated time ("... for 15 min.")?
function T:IsTimedStatBuff(itemID)
    if not next(ItemStats(itemID).stats) then return false end
    local text = (ns.ItemUseText(itemID) or ""):lower()
    for _, unit in text:gmatch("for ([%d%.]+) (%a+)") do
        if unit:find("^sec") or unit:find("^min") or unit:find("^h") then return true end
    end
    return false
end

-- How well an item's stats match the priority: the 1st stat counts 10, the
-- 2nd 6, then 4, 2, 1, added up. 0 = none of your stats. Also returns the
-- stat amount, to break ties (Juju Power +30 beats Giants +25).
function T:Score(itemID)
    local info = ItemStats(itemID)
    local score = 0
    for i, stat in ipairs(self:Priority()) do
        if info.stats[stat] then score = score + (WEIGHTS[i] or 0) end
    end
    return score, info.amount
end
