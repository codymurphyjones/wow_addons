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

-- Classes, specs and their default priorities are StatLedger's (Bandolier needs it): a preset is a
-- spec's default list, cut to the stats Bandolier knows and to T.SLOTS.
local function Ledger() return StatLedger and StatLedger.GetDefaultPriority and StatLedger or nil end

T.SLOTS = 5
local WEIGHTS = { 10, 6, 4, 2, 1 } -- 1st stat counts most

---------------------------------------------------------------------------
-- Presets and the current priority
---------------------------------------------------------------------------

-- Preset ids are "auto" or "CLASS:tab" (e.g. "PRIEST:2").
function T.PresetLabel(id)
    if id == "auto" then return "Automatic (your class and spec)" end
    local class, tab = id:match("^(%u+):(%d)$")
    local L = Ledger()
    local spec = L and class and L:GetSpecName(class, tonumber(tab))
    if not spec then return id end
    return L:GetClassName(class) .. ": " .. spec
end

-- Every preset id, Automatic first, then class by class.
function T.PresetIds()
    local ids = { "auto" }
    local L = Ledger()
    for _, class in ipairs(L and L:GetClasses() or {}) do
        for tab = 1, 3 do ids[#ids + 1] = class .. ":" .. tab end
    end
    return ids
end

-- A StatLedger list trimmed to the stats Bandolier knows and to T.SLOTS.
local function Trim(list)
    local out = {}
    for _, stat in ipairs(list or {}) do
        if T.LABELS[stat] and #out < T.SLOTS then out[#out + 1] = stat end
    end
    return out
end

-- The stats StatLedger has for your spec (your own order if you changed it there), trimmed.
-- nil without it.
function T:SharedStats()
    if not (StatLedger and StatLedger.GetPriority) then return end
    return Trim(StatLedger:GetPriority())
end

-- The stats of a preset: "auto" is StatLedger's list for your class and spec; "CLASS:tab" that
-- spec's default list.
function T:PresetStats(id)
    if id == "auto" then
        return self:SharedStats() or { "STA", "STR", "AGI", "INT", "SPI" }
    end
    local class, tab = id:match("^(%u+):(%d)$")
    local L = Ledger()
    if not (L and class) then return {} end
    return Trim(L:GetDefaultPriority(class, tonumber(tab)))
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
    -- /bandolier stats reset too: Options > AddOns > Bandolier shows the new priority.
    if ns.OptionChanged then ns:OptionChanged("db.statPreset") end
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
        if self:SharedStats() then source = source .. " -> StatLedger" end
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
