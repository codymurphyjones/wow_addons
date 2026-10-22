-----------------------------------------------------------------------
-- AddOn namespace.
-----------------------------------------------------------------------
local ADDON_NAME, private = ...
local AL = LibStub("AceLocale-3.0"):GetLocale("RareScanner", false)
local LB = LibStub("LibBabble-SubZone-3.0")

local RSMapDB = private.NewLib("RareScannerMapDB")

-- RareScanner internal libraries
local RSLogger = private.ImportLib("RareScannerLogger")
local RSUtils = private.ImportLib("RareScannerUtils")
local RSTextTags = private.ImportLib("RareScannerTextTags")
local RSConstants = private.ImportLib("RareScannerConstants")


---============================================================================
-- Auxiliar functions
---============================================================================

local function BelongsToMap(entityID, mapID, mapIDs, infoAlreadyFound, alreadyChecked)
	if (not entityID or not mapID or mapID == 0 or not mapIDs) then
		return false
	end

	-- Check if the zone matches
	local map = mapIDs[mapID]

	-- Search by parent map
	if (not map) then
		local mapInfo = C_Map.GetMapInfo(mapID)
		while (mapInfo and mapInfo.parentMapID > 0 and mapInfo.parentMapID ~= RSConstants.AZEROTH and mapInfo.parentMapID ~= RSConstants.COSMIC) do
			map = mapIDs[mapInfo.parentMapID]
			if (map) then
				break
			else
				mapInfo = C_Map.GetMapInfo(mapInfo.parentMapID)
			end
		end
	end
	
	if (map) then
		if (RSUtils.Contains(map, RSConstants.ALL_ZONES) or RSUtils.Contains(map, C_Map.GetMapArtID(mapID))) then
			return true
		end
	-- Search by the alreadyFound mapID
	elseif (not alreadyChecked) then
		if (infoAlreadyFound) then
			return BelongsToMap(entityID, infoAlreadyFound.mapID, mapIDs, infoAlreadyFound, true)
		end
	end

	return false
end

---============================================================================
-- Subzones resolution
---============================================================================

local MAX_SUBZONES_DEPTH = 5
local zoneMapIDs
local exceptionParents
local cachedAncestors = {}
local cachedChildren

local function IsZone(mapID)
	if (not zoneMapIDs) then
		zoneMapIDs = {}
		for _, continentInfo in pairs(private.CONTINENT_ZONE_IDS) do
			for _, zoneMapID in ipairs(continentInfo.zones) do
				zoneMapIDs[zoneMapID] = true
			end
		end
	end

	return zoneMapIDs[mapID] == true
end

local function GetExceptionParents()
	if (not exceptionParents) then
		exceptionParents = {}
		for parentMapID, childMapIDs in pairs(private.SUBZONES_IDS) do
			for _, childMapID in ipairs(childMapIDs) do
				exceptionParents[childMapID] = exceptionParents[childMapID] or {}
				tinsert(exceptionParents[childMapID], parentMapID)
			end
		end
	end

	return exceptionParents
end

local function GetDirectParents(mapID)
	-- Exceptions that the API doesn't provide
	local parents = GetExceptionParents()[mapID]
	if (parents) then
		return parents
	end

	-- A zone doesn't have parent
	if (IsZone(mapID)) then
		return nil
	end

	-- Maps in a dropdown (dungeon floors) belong to the zone of the group
	local groupID = C_Map.GetMapGroupID(mapID)
	if (groupID) then
		local members = C_Map.GetMapGroupMembersInfo(groupID)
		for _, member in ipairs(members or {}) do
			if (IsZone(member.mapID)) then
				return { member.mapID }
			end
		end
	end

	-- Blizzard hierarchy, ignoring the world and continent maps
	local mapInfo = C_Map.GetMapInfo(mapID)
	if (mapInfo and mapInfo.parentMapID > 0) then
		local parentInfo = C_Map.GetMapInfo(mapInfo.parentMapID)
		if (parentInfo and parentInfo.mapType >= Enum.UIMapType.Zone) then
			return { mapInfo.parentMapID }
		end
	end

	return nil
end

-- Fills ancestors with the maps above mapID, up to a zone. Returns true if it reaches a zone
local function CollectAncestors(mapID, ancestors, depth)
	local reachesZone = false
	local parents = depth < MAX_SUBZONES_DEPTH and GetDirectParents(mapID)
	if (parents) then
		for _, parentMapID in ipairs(parents) do
			if (CollectAncestors(parentMapID, ancestors, depth + 1)) then
				ancestors[parentMapID] = true
				reachesZone = true
			end
		end
	end

	return reachesZone or IsZone(mapID)
end

local function GetAncestors(mapID)
	local ancestors = cachedAncestors[mapID]
	if (not ancestors) then
		ancestors = {}
		CollectAncestors(mapID, ancestors, 0)
		cachedAncestors[mapID] = ancestors
	end

	return ancestors
end

local function IsMapInZones(mapID, zones)
	if (RSUtils.Contains(zones, mapID)) then
		return true
	end

	for ancestorMapID, _ in pairs(GetAncestors(mapID)) do
		if (RSUtils.Contains(zones, ancestorMapID)) then
			return true
		end
	end

	return false
end

-- Only the maps with entities and the exceptions are children
local function GetChildren(mapID)
	if (not cachedChildren) then
		cachedChildren = {}
		local candidates = {}
		for entityMapID, _ in pairs(private.MAP_ENTITIES) do
			candidates[entityMapID] = true
		end
		for childMapID, _ in pairs(GetExceptionParents()) do
			candidates[childMapID] = true
		end

		for childMapID, _ in pairs(candidates) do
			for ancestorMapID, _ in pairs(GetAncestors(childMapID)) do
				cachedChildren[ancestorMapID] = cachedChildren[ancestorMapID] or {}
				tinsert(cachedChildren[ancestorMapID], childMapID)
			end
		end

		for _, childMapIDs in pairs(cachedChildren) do
			sort(childMapIDs)
		end
	end

	return cachedChildren[mapID]
end

---============================================================================
-- Continents database
---============================================================================

function RSMapDB.GetContinents()
	return private.CONTINENT_ZONE_IDS
end

function RSMapDB.GetContinentInfo(mapID)
	if (mapID and RSMapDB.GetContinents()[mapID]) then
		return RSMapDB.GetContinents()[mapID]
	end
	
	return nil
end

function RSMapDB.IsMapInAnyContinent(mapID, continentIDs)
	for _, continentID in ipairs(continentIDs) do
		local continentInfo = RSMapDB.GetContinentInfo(continentID)
		if (continentInfo and IsMapInZones(mapID, continentInfo.zones)) then
			return true
		end
	end

	return false
end

-- Dungeons, raids, delves...: by the lists of zones or by the type of map (unless it is listed as an outdoor zone, like Dalaran)
function RSMapDB.IsInstanceMap(mapID)
	if (RSMapDB.IsMapInAnyContinent(mapID, RSConstants.INSTANCE_CONTINENTS)) then
		return true
	end

	local function IsDungeonType(mapID_)
		local mapInfo = C_Map.GetMapInfo(mapID_)
		return mapInfo and mapInfo.mapType == Enum.UIMapType.Dungeon and not IsZone(mapID_)
	end

	if (IsDungeonType(mapID)) then
		return true
	end

	for ancestorMapID, _ in pairs(GetAncestors(mapID)) do
		if (IsDungeonType(ancestorMapID)) then
			return true
		end
	end

	return false
end

local function IsMapHiddenInNavBar(mapID)
	local mapInfo = C_Map.GetMapInfo(mapID)
	return mapInfo ~= nil and bit.band(mapInfo.flags, Enum.UIMapFlag.DoNotShowOnNavbar) ~= 0
end

-- Zones hidden in the navigation bar: temporary versions of a zone, like the ones of a quest
function RSMapDB.IsHiddenZone(mapID)
	local mapInfo = C_Map.GetMapInfo(mapID)
	return mapInfo ~= nil and mapInfo.mapType == Enum.UIMapType.Zone and IsMapHiddenInNavBar(mapID)
end

-- Maps below mapID (children, children of the children...) by the exceptions and by the API, or only the direct children.
-- Only outdoor maps, the filters don't apply to dungeons, raids, delves...
function RSMapDB.GetSubMapIDs(mapID, onlyDirectChildren)
	local subMapIDs = {}
	local seen = { [mapID] = true }

	local candidateMapIDs = {}
	for _, childMapID in ipairs(GetChildren(mapID) or {}) do
		tinsert(candidateMapIDs, childMapID)
	end
	for _, childMapInfo in ipairs(C_Map.GetMapChildrenInfo(mapID, nil, true) or {}) do
		tinsert(candidateMapIDs, childMapInfo.mapID)
	end

	-- Zones of a continent have no parent in the rule, but they are direct children for the API
	local apiChildMapIDs = {}
	if (onlyDirectChildren) then
		for _, childMapInfo in ipairs(C_Map.GetMapChildrenInfo(mapID, nil, false) or {}) do
			apiChildMapIDs[childMapInfo.mapID] = true
		end
	end

	for _, candidateMapID in ipairs(candidateMapIDs) do
		if (not seen[candidateMapID]) then
			seen[candidateMapID] = true
			if ((not onlyDirectChildren or apiChildMapIDs[candidateMapID] or RSMapDB.GetMapAncestors(candidateMapID)[1] == mapID) and not RSMapDB.IsInstanceMap(candidateMapID)) then
				-- Maps hidden in the navigation bar (like the quest version of Silvermoon) are not listed, but they are still filtered with their parent
				if (not onlyDirectChildren or not IsMapHiddenInNavBar(candidateMapID)) then
					tinsert(subMapIDs, candidateMapID)
				end
			end
		end
	end

	return subMapIDs
end

-- With onlyDirectChildren only the zones of a continent, or the map and its direct children
function RSMapDB.GetActiveMapIDsWithNamesByMapID(mapID, onlyDirectChildren)
	local mapIDs = {}

	-- Ignore world maps
	if (mapID == RSConstants.AZEROTH or mapID == RSConstants.COSMIC) then
		return
	end

	-- If a continent
	local continentInfo = RSMapDB.GetContinents()[mapID]
	if (continentInfo) then
		for _, zoneMapID in ipairs(continentInfo.zones) do
			-- Zones hidden in the navigation bar (temporary quest versions of a zone) are not listed
			if (not onlyDirectChildren or not IsMapHiddenInNavBar(zoneMapID)) then
				tinsert(mapIDs, zoneMapID)
			end
		end

		if (not onlyDirectChildren) then
			local seen = {}
			for _, zoneMapID in ipairs(continentInfo.zones) do
				seen[zoneMapID] = true
			end
			for _, zoneMapID in ipairs(continentInfo.zones) do
				for _, subMapID in ipairs(RSMapDB.GetSubMapIDs(zoneMapID)) do
					if (not seen[subMapID]) then
						seen[subMapID] = true
						tinsert(mapIDs, subMapID)
					end
				end
			end
		end
	-- If not a continent
	else
		tinsert(mapIDs, mapID)
		for _, subMapID in ipairs(RSMapDB.GetSubMapIDs(mapID, onlyDirectChildren)) do
			tinsert(mapIDs, subMapID)
		end
	end

	local mapIDsWithNames = {}
	for _, mapID_ in ipairs (mapIDs) do
		-- Only outdoor zones, the filters don't apply to dungeons, raids, delves...
		if (not RSMapDB.IsInstanceMap(mapID_)) then
			local mapName = RSMapDB.GetMapName(mapID_)
			if (mapName) then
				mapIDsWithNames[mapID_] = string.format("%s (%s)", mapName, mapID_)
			else
				mapIDsWithNames[mapID_] = tostring(mapID_)
			end
		end
	end

	return mapIDsWithNames
end

local cachedContinentMapIDs = {}

local function GetContinentOfMapDB(mapID)
	for continentID, info in pairs(RSMapDB.GetContinents()) do
		if (RSUtils.Contains(info.zones, mapID)) then
			if (info.zonefilter and info.npcfilter) then
				cachedContinentMapIDs[mapID] = continentID
				return continentID
			else
				break
			end
		elseif (IsMapInZones(mapID, info.zones)) then
			cachedContinentMapIDs[mapID] = continentID
			return continentID
		end
	end
end

function RSMapDB.GetContinentOfMap(mapID)
	if (mapID) then
		-- Check first cached list
		if (cachedContinentMapIDs[mapID]) then
			return cachedContinentMapIDs[mapID]
		end
		
		local mapInfo = C_Map.GetMapInfo(mapID)
		if (mapInfo) then
			-- If not dungeon or orphan
			if (mapInfo.mapType ~= Enum.UIMapType.Dungeon and mapInfo.mapType ~= Enum.UIMapType.Orphan) then
				while (mapInfo.parentMapID > 0 and mapInfo.parentMapID ~= RSConstants.AZEROTH and mapInfo.parentMapID ~= RSConstants.COSMIC) do
					mapInfo = C_Map.GetMapInfo(mapInfo.parentMapID)
				end
				cachedContinentMapIDs[mapID] = mapInfo.mapID
				return mapInfo.mapID
			end
		end
		
		-- If not found, or dungeon or orphan, use internal database
		if (not cachedContinentMapIDs[mapID]) then
			return GetContinentOfMapDB(mapID)
		end
	end
	
	return nil
end

function RSMapDB.GetParentMapID(mapID)
	if (mapID) then
		local mapInfo = C_Map.GetMapInfo(mapID)
		if (mapInfo) then
			return mapInfo.parentMapID
		end
	end
	
	return nil
end

function RSMapDB.IsMapInCurrentExpansion(mapID)
	if (not mapID) then
		return false
	end

	-- check if the map is in the continent
	for _, continentInfo in pairs (RSMapDB.GetContinents()) do
		if (IsMapInZones(mapID, continentInfo.zones)) then
			if (not continentInfo.current) then
				return false
			elseif (RSUtils.Contains(continentInfo.current, RSConstants.ALL_ZONES) or RSUtils.Contains(continentInfo.current, mapID)) then
				return true
			end
		end
	end

	return false;
end

---============================================================================
-- Subzones database
---============================================================================

local cachedAncestorsChain = {}

-- Maps that contain mapID, ordered from its parent up to its zone
function RSMapDB.GetMapAncestors(mapID)
	local chain = cachedAncestorsChain[mapID]
	if (not chain) then
		chain = {}
		local currentMapID = mapID
		for _ = 1, MAX_SUBZONES_DEPTH do
			local nextMapID
			local ancestors = GetAncestors(currentMapID)
			for _, parentMapID in ipairs(GetDirectParents(currentMapID) or {}) do
				if (ancestors[parentMapID]) then
					nextMapID = parentMapID
					break
				end
			end

			if (not nextMapID) then
				break
			end

			tinsert(chain, nextMapID)
			currentMapID = nextMapID
		end
		cachedAncestorsChain[mapID] = chain
	end

	return chain
end

function RSMapDB.IsMapInParentMap(parentMapID, subzoneMapID)
	if (parentMapID and subzoneMapID) then
		return GetAncestors(subzoneMapID)[parentMapID] == true
	end

	return false
end

---============================================================================
-- Permanent state areas database
---============================================================================

function RSMapDB.GetPermanentKillZoneIDs()
	return private.PERMANENT_KILLS_ZONE_IDS
end

function RSMapDB.GetPermanentKillZoneArtID(mapID)
	if (mapID) then
		return private.PERMANENT_KILLS_ZONE_IDS[mapID]
	end

	return nil
end

function RSMapDB.IsEntityInPermanentZone(entityID, mapID, infoAlreadyFound, alreadyChecked)
	return BelongsToMap(entityID, mapID, RSMapDB.GetPermanentKillZoneIDs(), infoAlreadyFound, alreadyChecked)
end

---============================================================================
-- Reseteable state areas database
---============================================================================

function RSMapDB.GetReseteableKillZoneIDs()
	return private.RESETABLE_KILLS_ZONE_IDS
end

function RSMapDB.GetReseteableKillZoneArtID(mapID)
	if (mapID) then
		return private.RESETABLE_KILLS_ZONE_IDS[mapID]
	end

	return nil
end

function RSMapDB.IsEntityInReseteableZone(entityID, mapID, infoAlreadyFound, alreadyChecked)
	return BelongsToMap(entityID, mapID, RSMapDB.GetReseteableKillZoneIDs(), infoAlreadyFound, alreadyChecked)
end

function RSMapDB.IsReseteableKillMapID(mapID, artID)
	if (mapID) then
		local reseteableArtIDs = RSMapDB.GetReseteableKillZoneArtID(mapID)
		if (reseteableArtIDs and (RSUtils.Contains(reseteableArtIDs, RSConstants.ALL_ZONES) or RSUtils.Contains(reseteableArtIDs, artID))) then
			return true;
		end
	end

	return false
end

---============================================================================
-- Zones without vignette
---============================================================================
--
function RSMapDB.IsZoneWithoutVignette(mapID)
	if (mapID and private.ZONES_WITHOUT_VIGNETTE[mapID]) then
		return RSUtils.Contains(private.ZONES_WITHOUT_VIGNETTE[mapID], C_Map.GetMapArtID(mapID))
	end

	return false
end

---============================================================================
-- Map names
---============================================================================

function RSMapDB.GetMapName(mapID)
	local mapInfo = C_Map.GetMapInfo(mapID)
	if (mapInfo) then
		-- For those zones with the same name, add a comment
		if (AL["ZONE_"..mapID] ~= "ZONE_"..mapID) then
			return string.format(AL["ZONE_"..mapID], mapInfo.name)
		else
			-- For maps with groups
			local mapGroupID = C_Map.GetMapGroupID(mapID);
			if (not mapGroupID) then
			   	return mapInfo.name
			end

			local mapGroupMembersInfo = C_Map.GetMapGroupMembersInfo(mapGroupID);
			if (not mapGroupMembersInfo) then
			   	return mapInfo.name
			end

			for index, mapGroupMemberInfo in ipairs(mapGroupMembersInfo) do
			   	if (mapGroupMemberInfo.mapID == mapID) then
			   		if (mapInfo.name ~= mapGroupMemberInfo.name) then
			      		return string.format("%s (%s)", mapInfo.name, mapGroupMemberInfo.name)
			      	end
			      	
			      	break;
			   	end
  			end
  			
			return mapInfo.name
		end
	elseif (private.DUNGEONS_IDS[mapID]) then
		local dungeonName = private.DUNGEONS_IDS[mapID]
		local literal = rawget(AL, dungeonName)
		if (literal) then
			literal = string.gsub(RSTextTags.ParseText(literal), "[%[%]]", "")
		end
		return LB:GetAreaInfo(dungeonName) or LB:GetUnstrictLookupTable()[dungeonName] or literal or dungeonName
	end
	
	return AL["ZONES_CONTINENT_LIST"][mapID]
end

---============================================================================
-- Map / entities
---============================================================================

local function GetEntitiesByMapID(mapID, entityType)
	-- The maps that don't exist in the game (dungeons) don't have artID, so they are stored with the artID 0
	local artID = C_Map.GetMapArtID(mapID) or 0
	if (private.MAP_ENTITIES[mapID] and private.MAP_ENTITIES[mapID][artID]) then
		return private.MAP_ENTITIES[mapID][artID][entityType]
	end
	
	return nil
end

function RSMapDB.GetEntitiesByMapID(mapID, entityType, includeChildMaps)
	local entitiesInMap = GetEntitiesByMapID(mapID, entityType) or {}
	
	if (includeChildMaps) then
		for _, submapID in ipairs(GetChildren(mapID) or {}) do
			local entitiesInSubMap = GetEntitiesByMapID(submapID, entityType)
			if (entitiesInSubMap) then
				entitiesInMap = RSUtils.JoinTables(entitiesInMap, entitiesInSubMap)
			end
		end
	end

	if (RSUtils.GetTableLength(entitiesInMap) > 0) then
		return entitiesInMap
	end
	
	return nil
end
