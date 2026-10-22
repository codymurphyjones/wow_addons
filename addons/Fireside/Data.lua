local _, ns = ...

-- Classes that can interrupt a spell cast in Classic.
ns.INTERRUPTERS = { ROGUE = true, WARRIOR = true, SHAMAN = true, MAGE = true }
-- Classes that can tank in Classic.
ns.TANK_CLASSES = { WARRIOR = true, DRUID = true, PALADIN = true }

-- Whether boss is the last boss of the dungeon a run is in (instance: the name GetInstanceInfo gave,
-- instanceID: its map ID), so a run can be called a full clear. Dungeons with wings list each wing's
-- last boss (ns.Instances, shared\Instances.lua): any of them finishes it; a wing's own name
-- ("Lower Blackrock Spire") only its own.
function ns.IsFinalBoss(instance, boss, instanceID)
    local inst, wing = ns.Instances:Find(instance, instanceID)
    return inst ~= nil and ns.Instances:IsFinalBoss(inst, boss, wing)
end
