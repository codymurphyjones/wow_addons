local _, ns = ...

local D = {}
ns.Data = D

-- Category order is the priority order on the pop-out bar.
D.HEALTHSTONE = 1
D.HEALING     = 2
D.EMERGENCY   = 3 -- other instant heals (tubers, Night Dragon's Breath)
D.MANA        = 4
D.BANDAGE     = 5
D.FLASK       = 6
D.ELIXIR      = 7
D.SCROLL      = 8
D.BUFF        = 8.5 -- any other item that gives stats for a while (juju-likes, rums, firewater)
D.POTION      = 9 -- utility potions (Free Action, protection, rage, ...)
D.REFRESHMENT = 10 -- food that restores health and mana
D.FOOD        = 11
D.DRINK       = 12
D.CAMP        = 13 -- campfire, camp kits and fishing poles
D.WEAPON      = 14 -- sharpening stones, oils, poisons, fishing lures
D.OPEN        = 15 -- lockboxes, clams, bags and crates to open
D.OTHER       = 16 -- any other consumable with a "Use:" effect

D.CATEGORY_NAMES = {
    [D.HEALTHSTONE] = "Healthstone",
    [D.HEALING]     = "Healing",
    [D.EMERGENCY]   = "Emergency heal",
    [D.MANA]        = "Mana",
    [D.BANDAGE]     = "Bandage",
    [D.FLASK]       = "Flask",
    [D.ELIXIR]      = "Elixir",
    [D.SCROLL]      = "Scroll",
    [D.BUFF]        = "Buff",
    [D.POTION]      = "Potion",
    [D.REFRESHMENT] = "Refreshment",
    [D.FOOD]        = "Food",
    [D.DRINK]       = "Drink",
    [D.CAMP]        = "Camp",
    [D.WEAPON]      = "Weapon enhancement",
    [D.OPEN]        = "Open",
    [D.OTHER]       = "Other",
}

-- [itemID] = { category, power }. Power is the average amount restored and
-- decides the order inside a category.
D.ITEMS = {
    -- Healthstones (base, 1/2 and 2/2 Improved Healthstone)
    [5512]  = { D.HEALTHSTONE, 100 },  -- Minor Healthstone
    [19004] = { D.HEALTHSTONE, 110 },
    [19005] = { D.HEALTHSTONE, 120 },
    [5511]  = { D.HEALTHSTONE, 250 },  -- Lesser Healthstone
    [19006] = { D.HEALTHSTONE, 275 },
    [19007] = { D.HEALTHSTONE, 300 },
    [5509]  = { D.HEALTHSTONE, 500 },  -- Healthstone
    [19008] = { D.HEALTHSTONE, 550 },
    [19009] = { D.HEALTHSTONE, 600 },
    [5510]  = { D.HEALTHSTONE, 800 },  -- Greater Healthstone
    [19010] = { D.HEALTHSTONE, 880 },
    [19011] = { D.HEALTHSTONE, 960 },
    [9421]  = { D.HEALTHSTONE, 1200 }, -- Major Healthstone
    [19012] = { D.HEALTHSTONE, 1320 },
    [19013] = { D.HEALTHSTONE, 1440 },

    -- Healing and rejuvenation potions
    [118]   = { D.HEALING, 80 },   -- Minor Healing Potion
    [2456]  = { D.HEALING, 120 },  -- Minor Rejuvenation Potion
    [858]   = { D.HEALING, 160 },  -- Lesser Healing Potion
    [4596]  = { D.HEALING, 160 },  -- Discolored Healing Potion
    [929]   = { D.HEALING, 320 },  -- Healing Potion
    [1710]  = { D.HEALING, 520 },  -- Greater Healing Potion
    [17349] = { D.HEALING, 640 },  -- Superior Healing Draught
    [3928]  = { D.HEALING, 800 },  -- Superior Healing Potion
    [18839] = { D.HEALING, 800 },  -- Combat Healing Potion
    [17348] = { D.HEALING, 1120 }, -- Major Healing Draught
    [13446] = { D.HEALING, 1400 }, -- Major Healing Potion
    [18253] = { D.HEALING, 1600 }, -- Major Rejuvenation Potion

    -- Other instant heals
    [11952] = { D.EMERGENCY, 425 }, -- Night Dragon's Breath
    [11951] = { D.EMERGENCY, 800 }, -- Whipper Root Tuber

    -- Random-effect items: their text mentions health, but they aren't heals.
    [6522]  = { D.OTHER }, -- Deviate Fish
    [6657]  = { D.OTHER }, -- Savory Deviate Delight

    -- Mana
    [2455]  = { D.MANA, 160 },  -- Minor Mana Potion
    [3385]  = { D.MANA, 320 },  -- Lesser Mana Potion
    [5514]  = { D.MANA, 400 },  -- Mana Agate
    [3827]  = { D.MANA, 520 },  -- Mana Potion
    [5513]  = { D.MANA, 600 },  -- Mana Jade
    [17352] = { D.MANA, 640 },  -- Superior Mana Draught
    [6149]  = { D.MANA, 800 },  -- Greater Mana Potion
    [8007]  = { D.MANA, 850 },  -- Mana Citrine
    [8008]  = { D.MANA, 1100 }, -- Mana Ruby
    [17351] = { D.MANA, 1120 }, -- Major Mana Draught
    [13443] = { D.MANA, 1200 }, -- Superior Mana Potion
    [18841] = { D.MANA, 1200 }, -- Combat Mana Potion
    [12662] = { D.MANA, 1200 }, -- Demonic Rune
    [20520] = { D.MANA, 1200 }, -- Dark Rune
    [13444] = { D.MANA, 1800 }, -- Major Mana Potion

    -- Bandages
    [1251]  = { D.BANDAGE, 66 },   -- Linen Bandage
    [2581]  = { D.BANDAGE, 114 },  -- Heavy Linen Bandage
    [3530]  = { D.BANDAGE, 161 },  -- Wool Bandage
    [3531]  = { D.BANDAGE, 301 },  -- Heavy Wool Bandage
    [6450]  = { D.BANDAGE, 400 },  -- Silk Bandage
    [6451]  = { D.BANDAGE, 640 },  -- Heavy Silk Bandage
    [8544]  = { D.BANDAGE, 800 },  -- Mageweave Bandage
    [8545]  = { D.BANDAGE, 1104 }, -- Heavy Mageweave Bandage
    [14529] = { D.BANDAGE, 1360 }, -- Runecloth Bandage
    [14530] = { D.BANDAGE, 2000 }, -- Heavy Runecloth Bandage
}

-- Consumable (class 0) subclasses, when the client provides them.
local SUBCLASS = {
    [1] = D.POTION,
    [2] = D.ELIXIR,
    [3] = D.FLASK,
    [4] = D.SCROLL,
    [5] = D.FOOD,
    [7] = D.BANDAGE,
}

-- The spell an item casts tells food from drink even when the subclass doesn't.
local SPELLS = {
    Food = D.FOOD,
    Refreshment = D.REFRESHMENT, -- food that also restores mana
    Drink = D.DRINK,
}

-- Name patterns for items missing from ITEMS (Classic Era files most
-- consumables under subclass 0). Checked in order; enUS only.
-- Camp items and weapon enhancements, by name (enUS). Checked for every item
-- class, before anything else.
local UTILITY_PATTERNS = {
    { "[Cc]ampfire", D.CAMP },
    { "Camp Kit", D.CAMP },
    { "^Camp ", D.CAMP },
    { "Sharpening Stone", D.WEAPON },
    { "Weightstone", D.WEAPON },
    { "Wizard Oil", D.WEAPON },
    { "Mana Oil", D.WEAPON },
    -- Rogue poisons by name, so "Elixir of Poison Resistance" isn't one.
    { "^Instant Poison", D.WEAPON },
    { "^Deadly Poison", D.WEAPON },
    { "^Crippling Poison", D.WEAPON },
    { "^Mind%-numbing Poison", D.WEAPON },
    { "^Wound Poison", D.WEAPON },
}

local PATTERNS = {
    { "Healthstone", D.HEALTHSTONE },
    { "Healing Potion", D.HEALING },
    { "Healing Draught", D.HEALING },
    { "Rejuvenation Potion", D.HEALING },
    { "Mana Potion", D.MANA },
    { "Mana Draught", D.MANA },
    { "Bandage", D.BANDAGE },
    { "^Flask of", D.FLASK },
    { "Elixir", D.ELIXIR },
    { "^Juju ", D.ELIXIR },
    { "^Scroll of", D.SCROLL },
    { "Potion", D.POTION },
}

-- How much health the use effect restores, read from the item's "Use:" text
-- ("Restores 300 to 500 health", "Instantly restores 15% of your health and
-- mana", "Heals you for 800"). Nil when it doesn't heal; 1 when it heals by an
-- amount we can't read. enUS only.
local function HealAmount(itemID, spellID)
    local text = ns.ItemUseText(itemID)
    if not text or text == "" then text = ns.SpellDescription(spellID) end
    if text == "" then
        ns.Scanner.waitingForInfo = true -- text not loaded yet; rescan later
        return
    end
    text = text:lower():gsub(",", "")
    -- "heals? " skips "healing" ("Increases healing done ..."). "Restores" and
    -- "health" must be in the same sentence.
    if not (text:find("restores?[^%.]-health") or text:find("heals? ")) then return end
    -- A random effect that only might heal isn't a heal.
    if text:find("random") or text:find("chance to") then return end

    local low, high = text:match("([%d%.]+) to ([%d%.]+)")
    if low and tonumber(low) and tonumber(high) then return (tonumber(low) + tonumber(high)) / 2 end
    local percent = tonumber(text:match("([%d%.]+)%%") or "")
    if percent then return percent * UnitHealthMax("player") / 100 end
    local amount = text:match("([%d%.]+) health") or text:match("for ([%d%.]+)")
    return amount and tonumber(amount) or 1
end

-- Never listed: weapons and armor (their use effects only work equipped) and
-- recipes (their tooltip quotes the dish's "Restores ... health" line).
local EXCLUDED_CLASSES = { [2] = true, [4] = true, [9] = true }

-- Food and drink by their "Use:" text ("... Must remain seated while
-- eating."), so buff foods count as food whatever their spell is called.
-- enUS only.
local function FoodOrDrink(itemID)
    local text = (ns.ItemUseText(itemID) or ""):lower()
    if text:find("while eating") then
        -- Restores mana while eating, not just a "Well Fed: ... mana" bonus.
        if text:find("health and [%d%.]+ mana") or text:find("[%d%.]+ mana over") then return D.REFRESHMENT end
        return D.FOOD
    end
    if text:find("while drinking") then return D.DRINK end
end

-- How much a meal restores, from its "Use:" text: health for food, mana for
-- drink, both for refreshment. Decides which food/drink is "better".
-- Only the first amounts count, so a "Well Fed" bonus doesn't. enUS only.
local function MealAmount(itemID, category)
    local text = (ns.ItemUseText(itemID) or ""):lower():gsub(",", "")
    local health = tonumber(text:match("([%d%.]+) health") or "")
    local mana = tonumber(text:match("([%d%.]+) mana over") or text:match("and ([%d%.]+) mana") or "")
    if category == D.FOOD then return health end
    if category == D.DRINK then return mana or tonumber(text:match("([%d%.]+) mana") or "") end
    if health or mana then return (health or 0) + (mana or 0) end
end

local MEALS = { [D.FOOD] = true, [D.DRINK] = true, [D.REFRESHMENT] = true }

local Classify

-- Returns category, power (power is nil when the strength is unknown).
function D.Classify(itemID, name)
    local category, power = Classify(itemID, name)
    if MEALS[category] and not power then power = MealAmount(itemID, category) end
    return category, power
end

-- Fishing poles in the bags sit with the camp items: clicking one equips it.
function D.IsFishingPole(itemID)
    if not itemID then return false end
    local _, _, _, _, _, classID, subClassID = ns.ItemInfoInstant(itemID)
    return classID == 2 and subClassID == 20
end

function Classify(itemID, name)
    local known = D.ITEMS[itemID]
    if known then return known[1], known[2] end
    if D.IsFishingPole(itemID) then return D.CAMP end

    -- Without a use effect there is nothing to click.
    local spellName, spellID = ns.ItemSpell(itemID)
    if not spellName then return end

    local _, _, _, _, _, classID, subClassID = ns.ItemInfoInstant(itemID)
    if EXCLUDED_CLASSES[classID] then return end
    if name then
        for _, rule in ipairs(UTILITY_PATTERNS) do
            if name:find(rule[1]) then return rule[2] end
        end
    end
    -- Fishing lures attach to the pole like a weapon enhancement.
    if (ns.ItemUseText(itemID) or ""):lower():find("fishing") then return D.WEAPON end
    if classID ~= 0 then
        -- Not a consumable, but reusable heals (stones, trinket-like items
        -- carried in bags) still belong on the plain press.
        local heal = HealAmount(itemID, spellID)
        if heal then return D.EMERGENCY, heal end
        return
    end

    if name then
        for _, rule in ipairs(PATTERNS) do
            if name:find(rule[1]) then return rule[2] end
        end
    end
    if SPELLS[spellName] then return SPELLS[spellName] end
    local meal = FoodOrDrink(itemID)
    if meal then return meal end
    -- Anything else that heals is an emergency heal, e.g. a stone that
    -- restores health and mana on a cooldown.
    local heal = HealAmount(itemID, spellID)
    if heal then return D.EMERGENCY, heal end
    -- Gives stats for a while ("Increases Stamina by 15 for 15 min."): a buff,
    -- ranked by your stat priority like flasks and elixirs.
    if ns.Stats:IsTimedStatBuff(itemID) then return D.BUFF end
    return SUBCLASS[subClassID] or D.OTHER
end

-- Items in the same group share a cooldown: using one puts them all on
-- cooldown. In combat Bandolier can't read cooldowns, so it marks the whole
-- group when one is used. "" = no cooldown (food, drink, ...).
-- Flasks, elixirs and scrolls use "a<spellID>": "cooling" then means their
-- buff is still up, so they aren't drunk again.
local RUNES = { [12662] = true, [20520] = true } -- Demonic Rune, Dark Rune

function D.CooldownGroup(entry)
    local category = entry.category
    if category == D.HEALTHSTONE then return "hs" end
    if category == D.HEALING or category == D.POTION then return "pot" end
    if category == D.BANDAGE then return "bandage" end -- Recently Bandaged
    if category == D.MANA then
        if RUNES[entry.id] then return "rune" end
        local name = entry.name or ""
        if name:find("Potion") or name:find("Draught") then return "pot" end
        return "i" .. entry.id
    end
    if category == D.EMERGENCY or category == D.OTHER then return "i" .. entry.id end
    if D.IsBuff(category) and entry.spellID then return "a" .. entry.spellID end
    return ""
end

-- Buff consumables: used first by the plain press during boss fights.
-- Enhancement potions are the POTION category.
function D.IsBuff(category)
    return category == D.FLASK or category == D.ELIXIR or category == D.SCROLL
        or category == D.BUFF or category == D.POTION
end


-- Items that can't be used in combat: the bar's second row, shown only out
-- of combat. (Bandolier also learns more: see Core.lua, PLAYER_REGEN_DISABLED.)
local OUT_OF_COMBAT = {
    [D.REFRESHMENT] = true, [D.FOOD] = true, [D.DRINK] = true,
    [D.CAMP] = true, [D.WEAPON] = true, [D.OPEN] = true,
}

function D.IsOutOfCombat(category)
    return OUT_OF_COMBAT[category] or false
end

-- Food, drink and refreshment.
function D.IsMeal(category)
    return category == D.FOOD or category == D.DRINK or category == D.REFRESHMENT
end
