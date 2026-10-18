local _, ns = ...

-- Consumables anyone can use (bought, crafted or found), for when a fight is too hard for what you
-- carry. This is about items, not classes; the ones already in your bags are always suggested
-- first. { itemID, name, kind, minLevel, low, high }: low-high health or mana restored, or the
-- armor / health added for buffs.
ns.CONSUMABLES = {
    { 118, "Minor Healing Potion", "heal", 1, 70, 90 },
    { 858, "Lesser Healing Potion", "heal", 3, 140, 180 },
    { 929, "Healing Potion", "heal", 12, 280, 360 },
    { 1710, "Greater Healing Potion", "heal", 21, 455, 585 },
    { 3928, "Superior Healing Potion", "heal", 35, 700, 900 },
    { 13446, "Major Healing Potion", "heal", 45, 1050, 1750 },
    { 2455, "Minor Mana Potion", "mana", 5, 140, 180 },
    { 3385, "Lesser Mana Potion", "mana", 14, 280, 360 },
    { 3827, "Mana Potion", "mana", 22, 455, 585 },
    { 6149, "Greater Mana Potion", "mana", 31, 700, 900 },
    { 13443, "Superior Mana Potion", "mana", 41, 900, 1500 },
    { 13444, "Major Mana Potion", "mana", 49, 1350, 2250 },
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

-- The best of a kind for your level.
function ns.BestConsumable(kind, level)
    local best
    for _, c in ipairs(ns.CONSUMABLES) do
        if c[3] == kind and c[4] <= level and (not best or c[4] > best[4]) then best = c end
    end
    return best
end
