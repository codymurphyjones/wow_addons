local _, ns = ...

-- Where a quest giver stands: continent, zone, subzone and map position.
-- Data\QuestDB.lua gives spawns as { [areaID] = { { x, y }, ... } } in
-- percent of that zone's map, and the map ID for each area.
local L = {}
ns.Location = L

local function AreaName(areaID)
    return areaID and C_Map.GetAreaInfo and C_Map.GetAreaInfo(areaID) or nil
end

-- Map IDs by name, for areas the shipped data has no map ID for.
local byName
local function MapByName(name)
    if not name then return nil end
    if not byName then
        byName = {}
        local ok, children = pcall(C_Map.GetMapChildrenInfo, 946, nil, true) -- the whole world
        if not ok or not children then ok, children = pcall(C_Map.GetMapChildrenInfo, 947, nil, true) end
        for _, info in ipairs(ok and children or {}) do
            if info.name and not byName[info.name] then byName[info.name] = info.mapID end
        end
    end
    return byName[name]
end

local function UiMapID(areaID)
    return ns.QuestDB.areaMap[areaID] or MapByName(AreaName(areaID))
end

local CONTINENT = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2

local function Continent(uiMapID)
    local id, guard = uiMapID, 0
    while id and guard < 10 do
        local info = C_Map.GetMapInfo(id)
        if not info then return nil end
        if info.mapType == CONTINENT then return info.name end
        id, guard = info.parentMapID, guard + 1
    end
    return nil
end

-- { uiMapID, x, y (0-1), continent, zone, subzone, coords = "45.2, 61.8", giver }
-- for a quest's giver, or nil when the shipped data has no spawn for it.
function L:ForQuest(questID)
    return self:ForPerson(ns.Quests:Giver(questID), questID)
end

-- The same for any NPC or object (from Quests:Giver / Quests:Ender);
-- questID, when given, can name the subzone.
function L:ForPerson(giver, questID)
    local spawns = giver and giver.spawns
    if type(spawns) ~= "table" then return nil end
    -- Several areas: the quest's own, else any.
    local questArea = questID and ns.Quests.Get(questID, "zoneOrSort") or 0
    local areaID = spawns[questArea] and questArea
    if not areaID then
        for id in pairs(spawns) do areaID = id break end
    end
    local point = areaID and spawns[areaID] and spawns[areaID][1]
    if not point then return nil end
    -- Inside a dungeon or raid: no map position (-1, -1).
    if (point[1] or 0) < 0 then
        return { inside = true, zone = AreaName(areaID), coords = "inside the instance", giver = giver, areaID = areaID }
    end

    -- Spawns are listed under the zone; the quest's own area may name the
    -- subzone (Goldshire in Elwynn): an area with no map of its own.
    local subzoneArea
    if questArea > 0 and questArea ~= areaID and not ns.QuestDB.dungeons[questArea]
        and not UiMapID(questArea) then
        subzoneArea = questArea
    end

    local uiMapID = UiMapID(areaID)
    local x, y = (point[1] or 0) / 100, (point[2] or 0) / 100
    return {
        uiMapID = uiMapID, x = x, y = y,
        continent = uiMapID and Continent(uiMapID),
        zone = AreaName(areaID) or (uiMapID and C_Map.GetMapInfo(uiMapID) and C_Map.GetMapInfo(uiMapID).name),
        subzone = subzoneArea and AreaName(subzoneArea) or nil,
        coords = string.format("%.1f, %.1f", point[1] or 0, point[2] or 0),
        giver = giver,
    }
end
