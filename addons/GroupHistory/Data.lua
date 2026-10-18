local _, ns = ...

-- The last boss of each classic dungeon (by the instance name GetInstanceInfo gives), so a run can
-- be called a full clear. Dungeons with wings list each wing's last boss: any of them finishes it.
ns.FINAL_BOSSES = {
    ["Ragefire Chasm"] = { "Bazzalan" },
    ["Wailing Caverns"] = { "Mutanus the Devourer" },
    ["The Deadmines"] = { "Edwin VanCleef" },
    ["Shadowfang Keep"] = { "Archmage Arugal" },
    ["Blackfathom Deeps"] = { "Aku'mai" },
    ["The Stockade"] = { "Bazil Thredd" },
    ["Stormwind Stockade"] = { "Bazil Thredd" },
    ["Gnomeregan"] = { "Mekgineer Thermaplugg" },
    ["Razorfen Kraul"] = { "Charlga Razorflank" },
    ["Scarlet Monastery"] = { "Bloodmage Thalnos", "Arcanist Doan", "Herod", "High Inquisitor Whitemane" },
    ["Razorfen Downs"] = { "Amnennar the Coldbringer" },
    ["Uldaman"] = { "Archaedas" },
    ["Zul'Farrak"] = { "Chief Ukorz Sandscalp" },
    ["Maraudon"] = { "Princess Theradras" },
    ["Sunken Temple"] = { "Shade of Eranikus" },
    ["The Temple of Atal'Hakkar"] = { "Shade of Eranikus" },
    ["Blackrock Depths"] = { "Emperor Dagran Thaurissan" },
    ["Blackrock Spire"] = { "Overlord Wyrmthalak", "General Drakkisath" },
    ["Lower Blackrock Spire"] = { "Overlord Wyrmthalak" },
    ["Upper Blackrock Spire"] = { "General Drakkisath" },
    ["Dire Maul"] = { "Alzzin the Wildshaper", "Prince Tortheldrin", "King Gordok" },
    ["Scholomance"] = { "Darkmaster Gandling" },
    ["Stratholme"] = { "Baron Rivendare", "Balnazzar" },
}

-- Classes that can interrupt a spell cast in Classic.
ns.INTERRUPTERS = { ROGUE = true, WARRIOR = true, SHAMAN = true, MAGE = true }
-- Classes that can tank in Classic.
ns.TANK_CLASSES = { WARRIOR = true, DRUID = true, PALADIN = true }

function ns.IsFinalBoss(instance, boss)
    local list = instance and ns.FINAL_BOSSES[instance]
    if not (list and boss) then return false end
    boss = boss:lower()
    for _, name in ipairs(list) do
        if name:lower() == boss then return true end
    end
    return false
end
