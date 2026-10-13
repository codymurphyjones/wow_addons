local _, ns = ...

-- Which quests belong to which dungeon or raid. Worked out ahead of time by
-- Spyglass\Tools\build_items.py (Data\QuestDB.lua): a quest belongs to an
-- instance when its zone is the instance, its giver stands inside, or
-- something it asks for is only found there: a creature to kill or talk to,
-- an object, or an item that drops from one of them.
local D = {}
ns.Dungeons = D

local DB = ns.QuestDB

-- The index is shipped, so it's always ready.
function D:Build() end

function D:Ready()
    return true
end

-- The instance's area: AtlasLoot's area ID, else the dungeon whose area
-- name the game gives as the instance's name.
local byName
local function AreaOf(inst)
    if inst.areaID then return inst.areaID end
    if not byName then
        byName = {}
        for area in pairs(DB.dungeons) do
            local name = C_Map.GetAreaInfo and C_Map.GetAreaInfo(area)
            if name then byName[name] = area end
        end
    end
    return byName[inst.name]
end

-- Every quest for the instance (including ones for the other faction or
-- another class, which the Quests tab marks), and, with a boss, only those
-- involving that boss.
function D:QuestsFor(inst, boss)
    local area = AreaOf(inst)
    local list = area and DB.dungeons[area] or {}
    local out = {}
    for _, questID in ipairs(list) do
        local keep = true
        if boss then
            keep = false
            local npcs = DB.dungeonNpcs[questID]
            for _, npc in ipairs(boss.npcIDs or {}) do
                if npcs and tContains(npcs, npc) then keep = true break end
            end
        end
        if keep then out[#out + 1] = questID end
    end
    return out
end
