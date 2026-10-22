local _, ns = ...

-- Potions, healthstones, bandages and the like, one list for every addon here (addons/shared):
-- Bandolier sorts its pop-out bar by it, Mr. Miyagi suggests what to bring to a fight that's too hard.
-- { id, name, kind, level, low, high, power, bg }
--   kind   healthstone, heal, emergency (other instant heals), mana, bandage, armor (elixir, armor
--          added), health (elixir, health added), escape, freedom, invulnerable, random (its text
--          mentions health but it isn't a heal)
--   level  the level you can use it at; only entries with one are suggested to buy
--   low, high  health or mana restored, or the armor / health added; power = the average (or given)
--   bg     battleground-only (draughts, combat potions): never suggested to buy
ns.CONSUMABLES = {
    -- Healthstones (base, 1/2 and 2/2 Improved Healthstone)
    { 5512, "Minor Healthstone", "healthstone", power = 100 },
    { 19004, "Minor Healthstone", "healthstone", power = 110 },
    { 19005, "Minor Healthstone", "healthstone", power = 120 },
    { 5511, "Lesser Healthstone", "healthstone", power = 250 },
    { 19006, "Lesser Healthstone", "healthstone", power = 275 },
    { 19007, "Lesser Healthstone", "healthstone", power = 300 },
    { 5509, "Healthstone", "healthstone", power = 500 },
    { 19008, "Healthstone", "healthstone", power = 550 },
    { 19009, "Healthstone", "healthstone", power = 600 },
    { 5510, "Greater Healthstone", "healthstone", power = 800 },
    { 19010, "Greater Healthstone", "healthstone", power = 880 },
    { 19011, "Greater Healthstone", "healthstone", power = 960 },
    { 9421, "Major Healthstone", "healthstone", power = 1200 },
    { 19012, "Major Healthstone", "healthstone", power = 1320 },
    { 19013, "Major Healthstone", "healthstone", power = 1440 },

    -- Healing and rejuvenation potions
    { 118, "Minor Healing Potion", "heal", 1, 70, 90 },
    { 2456, "Minor Rejuvenation Potion", "heal", power = 120 },
    { 858, "Lesser Healing Potion", "heal", 3, 140, 180 },
    { 4596, "Discolored Healing Potion", "heal", power = 160 },
    { 929, "Healing Potion", "heal", 12, 280, 360 },
    { 1710, "Greater Healing Potion", "heal", 21, 455, 585 },
    { 17349, "Superior Healing Draught", "heal", power = 640, bg = true },
    { 3928, "Superior Healing Potion", "heal", 35, 700, 900 },
    { 18839, "Combat Healing Potion", "heal", power = 800, bg = true },
    { 17348, "Major Healing Draught", "heal", power = 1120, bg = true },
    { 13446, "Major Healing Potion", "heal", 45, 1050, 1750 },
    { 18253, "Major Rejuvenation Potion", "heal", power = 1600 },

    -- Other instant heals
    { 11952, "Night Dragon's Breath", "emergency", power = 425 },
    { 11951, "Whipper Root Tuber", "emergency", power = 800 },

    -- Random-effect items: their text mentions health, but they aren't heals.
    { 6522, "Deviate Fish", "random" },
    { 6657, "Savory Deviate Delight", "random" },

    -- Mana
    { 2455, "Minor Mana Potion", "mana", 5, 140, 180 },
    { 3385, "Lesser Mana Potion", "mana", 14, 280, 360 },
    { 5514, "Mana Agate", "mana", power = 400 },
    { 3827, "Mana Potion", "mana", 22, 455, 585 },
    { 5513, "Mana Jade", "mana", power = 600 },
    { 17352, "Superior Mana Draught", "mana", power = 640, bg = true },
    { 6149, "Greater Mana Potion", "mana", 31, 700, 900 },
    { 8007, "Mana Citrine", "mana", power = 850 },
    { 8008, "Mana Ruby", "mana", power = 1100 },
    { 17351, "Major Mana Draught", "mana", power = 1120, bg = true },
    { 13443, "Superior Mana Potion", "mana", 41, 900, 1500 },
    { 18841, "Combat Mana Potion", "mana", power = 1200, bg = true },
    { 12662, "Demonic Rune", "mana", power = 1200 },
    { 20520, "Dark Rune", "mana", power = 1200 },
    { 13444, "Major Mana Potion", "mana", 49, 1350, 2250 },

    -- Bandages
    { 1251, "Linen Bandage", "bandage", power = 66 },
    { 2581, "Heavy Linen Bandage", "bandage", power = 114 },
    { 3530, "Wool Bandage", "bandage", power = 161 },
    { 3531, "Heavy Wool Bandage", "bandage", power = 301 },
    { 6450, "Silk Bandage", "bandage", power = 400 },
    { 6451, "Heavy Silk Bandage", "bandage", power = 640 },
    { 8544, "Mageweave Bandage", "bandage", power = 800 },
    { 8545, "Heavy Mageweave Bandage", "bandage", power = 1104 },
    { 14529, "Runecloth Bandage", "bandage", power = 1360 },
    { 14530, "Heavy Runecloth Bandage", "bandage", power = 2000 },

    -- Elixirs and utility potions
    { 5997, "Elixir of Minor Defense", "armor", 1, 50, 50 },
    { 3389, "Elixir of Defense", "armor", 16, 150, 150 },
    { 8951, "Elixir of Greater Defense", "armor", 29, 250, 250 },
    { 13445, "Elixir of Superior Defense", "armor", 43, 450, 450 },
    { 3825, "Elixir of Fortitude", "health", 25, 120, 120 },
    { 2458, "Elixir of Minor Fortitude", "health", 2, 27, 27 },
    { 2459, "Swiftness Potion", "escape", 1, 0, 0 },
    { 5634, "Free Action Potion", "freedom", 20, 0, 0 },
    { 3387, "Limited Invulnerability Potion", "invulnerable", 45, 0, 0 },
}

-- By item ID, with power filled in.
ns.CONSUMABLE_BY_ID = {}
for _, c in ipairs(ns.CONSUMABLES) do
    if not c.power and c[5] and c[6] then c.power = (c[5] + c[6]) / 2 end
    ns.CONSUMABLE_BY_ID[c[1]] = c
end

-- The best of a kind to buy for your level (battleground-only ones aside).
function ns.BestConsumable(kind, level)
    local best
    for _, c in ipairs(ns.CONSUMABLES) do
        if c[3] == kind and c[4] and not c.bg and c[4] <= level and (not best or c[4] > best[4]) then best = c end
    end
    return best
end
