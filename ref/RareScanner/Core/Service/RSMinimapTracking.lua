-----------------------------------------------------------------------
-- AddOn namespace.
-----------------------------------------------------------------------
local ADDON_NAME, private = ...

local RSMinimapTracking = private.NewLib("RareScannerMinimapTracking")

-- RareScanner database libraries
local RSNpcDB = private.ImportLib("RareScannerNpcDB")
local RSContainerDB = private.ImportLib("RareScannerContainerDB")
local RSConfigDB = private.ImportLib("RareScannerConfigDB")

-- RareScanner internal libraries
local RSConstants = private.ImportLib("RareScannerConstants")
local RSUtils = private.ImportLib("RareScannerUtils")
local RSLogger = private.ImportLib("RareScannerLogger")
local RSRoutines = private.ImportLib("RareScannerRoutines")

---============================================================================
-- Minimap tracking by class/racial skills
---============================================================================

local STEP = 8
local SCAN_INTERVAL = 1.0
local IDLE_INTERVAL = 4.0
local ERROR_INTERVAL = 30.0
local NAME_MAP_TTL = 60

local FIND_TREASURE = 2481
local NOT_RELEVANT_TRACKING = { [2383] = true, [2580] = true } -- Find Herbs, Find Minerals

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

---============================================================================
-- Names -> NPC / container IDs of the zone
---============================================================================

local nameMaps = {}

local function AddName(map, name, id)
	if (name and id) then
		local key = strupper(name)
		if (not map[key]) then
			map[key] = {}
		end
		table.insert(map[key], id)
	end
end

local function MapAndParents(mapID)
	local maps = { mapID }
	local current = mapID
	for _ = 1, 3 do
		local info = C_Map.GetMapInfo(current)
		if (not info or not info.parentMapID or info.parentMapID == 0) then
			break
		end
		current = info.parentMapID
		maps[#maps + 1] = current
	end
	return maps
end

local function GetNameMaps(mapID)
	local now = GetTime()
	local cached = nameMaps[mapID]
	if (cached and now - cached.time < NAME_MAP_TTL) then
		return cached
	end

	local result = { time = now, npcs = {}, containers = {}, matches = { npcs = {}, containers = {} } }

	for _, id in ipairs(MapAndParents(mapID)) do
		for _, npcID in ipairs(RSNpcDB.GetNpcIDsByMapID(id) or {}) do
			AddName(result.npcs, RSNpcDB.GetNpcName(npcID), npcID)
		end

		for _, containerID in ipairs(RSContainerDB.GetContainerIDsByMapID(id) or {}) do
			AddName(result.containers, RSContainerDB.GetContainerName(containerID), containerID)
		end
	end

	-- Check custom NPCs that might not have a zone associated or are global
	local customNpcs = RSNpcDB.GetAllCustomNpcInfo()
	if (customNpcs) then
		for customNpcID, _ in pairs(customNpcs) do
			AddName(result.npcs, RSNpcDB.GetNpcName(customNpcID), customNpcID)
		end
	end

	nameMaps[mapID] = result
	return result
end

---============================================================================
-- Geometry
---============================================================================

local function PointToMapCoords(x, y, width, radius, facing, px, py, mapWidth, mapHeight)
	local dx, dy = x - width / 2, y - width / 2
	local distance = math.sqrt(dx * dx + dy * dy)
	local yards = distance / (width / 2) * radius
	local bearing = atan2(dx, dy)
	local world = facing and (bearing - facing) or bearing
	local mx = px + yards * math.sin(world) / mapWidth
	local my = py - yards * math.cos(world) / mapHeight
	return mx, my, yards
end

local function Cluster(points)
	local clusters = {}
	local visited = {}

	for key, _ in pairs(points) do
		if (not visited[key]) then
			visited[key] = true
			local queue, head = { key }, 1
			local sumx, sumy, count = 0, 0, 0

			while (queue[head]) do
				local current = queue[head]
				head = head + 1
				local gx, gy = math.floor(current / 1000), current % 1000
				sumx, sumy, count = sumx + gx, sumy + gy, count + 1
				for ox = -1, 1 do
					for oy = -1, 1 do
						if (ox ~= 0 or oy ~= 0) then
							local neighbour = (gx + ox) * 1000 + (gy + oy)
							if (points[neighbour] and not visited[neighbour]) then
								visited[neighbour] = true
								queue[#queue + 1] = neighbour
							end
						end
					end
				end
			end

			clusters[#clusters + 1] = { x = sumx / count * STEP, y = sumy / count * STEP, points = count }
		end
	end

	return clusters
end

local function DistanceToContainer(containerID, mapID, mx, my)
	local info = RSContainerDB.GetInternalContainerInfoByMapID(containerID, mapID)
	if (not info) then
		return nil
	end

	local spots = {}
	if (info.x and info.y) then
		spots[#spots + 1] = { RSUtils.FixCoord(info.x), RSUtils.FixCoord(info.y) }
	end

	if (type(info.overlay) == "table") then
		for _, coordinates in ipairs(info.overlay) do
			local x, y = strsplit("-", coordinates)
			if (x and y) then
				spots[#spots + 1] = { RSUtils.FixCoord(x), RSUtils.FixCoord(y) }
			end
		end
	end

	local best
	for _, spot in ipairs(spots) do
		if (spot[1] and spot[2]) then
			local distance = RSUtils.GetDistanceInYards(mapID, mx, my, spot[1], spot[2])
			if (not best or distance < best) then
				best = distance
			end
		end
	end

	return best
end

local function ChooseContainer(candidates, mapID, mx, my)
	if (#candidates == 1) then
		return candidates[1]
	end

	local best, bestDistance
	for _, containerID in ipairs(candidates) do
		local distance = DistanceToContainer(containerID, mapID, mx, my)
		if (distance and (not bestDistance or distance < bestDistance)) then
			best, bestDistance = containerID, distance
		end
	end

	return best or candidates[1]
end

---============================================================================
-- Scan
---============================================================================

local scan

local function ActiveTracking()
	if (not (C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo)) then
		return true, true
	end

	local creatures, treasures = false, false
	for index = 1, C_Minimap.GetNumTrackingTypes() do
		local info = C_Minimap.GetTrackingInfo(index)
		if (info and info.active and info.spellID) then
			if (info.spellID == FIND_TREASURE) then
				treasures = true
			elseif (not NOT_RELEVANT_TRACKING[info.spellID]) then
				creatures = true
			end
		end
	end

	return creatures, treasures
end

local function BuildGrid(width)
	local grid = {}
	for gx = 0, math.floor(width / STEP) do
		for gy = 0, math.floor(width / STEP) do
			local dx, dy = gx * STEP - width / 2, gy * STEP - width / 2
			if (dx * dx + dy * dy <= width * width / 4) then
				grid[#grid + 1] = gx * 1000 + gy
			end
		end
	end

	return grid
end

local function StartScan()
	if (InCombatLockdown() or not Minimap:IsVisible() or not Minimap:GetLeft() or IsInInstance()) then
		return false
	end

	local creatures, treasures = ActiveTracking()
	if (not creatures and not treasures) then
		return false
	end

	local width = Minimap:GetWidth()
	if (not width or width <= 0) then
		return false
	end

	scan = { grid = BuildGrid(width), next = 1, width = width, names = {}, creatures = creatures, treasures = treasures }
	return true
end

local function CleanTooltipText(text)
	text = text:gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")

	-- Strip leading symbols (e.g. ▼)
	local previous
	repeat
		previous = text
		text = text:gsub("^[%s%p%c]+", ""):gsub("^\226[\128-\191][\128-\191]", "")
	until (text == previous)

	return (text:match("^(.-)%s*$"))
end

local function Probe(left, bottom, scale, key)
	local gx, gy = math.floor(key / 1000), key % 1000
	Minimap:UpdateMouseoverAtPoint((left + gx * STEP) * scale, (bottom + gy * STEP) * scale)
	local data = C_TooltipInfo.GetMinimapMouseover()

	if (not data or issecretvalue(data) or not data.lines) then
		return
	end

	for _, line in ipairs(data.lines) do
		local text = line.leftText
		if (text and text ~= "" and not issecretvalue(text)) then
			for subline in text:gmatch("([^\r\n]+)") do
				-- Ignore quest objectives (e.g. "0/1 ...", "50%")
				if (not subline:find("%d+/%d+") and not subline:find("%d+%%")) then
					local cleanedText = CleanTooltipText(subline)
					if (cleanedText ~= "") then
						local upper = strupper(cleanedText)
						if (not scan.names[upper]) then
							scan.names[upper] = {}
						end
						scan.names[upper][key] = true
					end
				end
			end
		end
	end
end

-- Word boundary check to prevent partial substring matches
local function ContainsName(text, name)
	local first, last = text:find(name, 1, true)
	if (not first) then
		return false
	end

	local before = first == 1 or text:sub(first - 1, first - 1):find("[%s%p]")
	local after = last == #text or text:sub(last + 1, last + 1):find("[%s%p]")
	return (before and after) and true or false
end

local function FindNames(maps, kind, upperText)
	local memory = maps.matches[kind]
	if (memory[upperText]) then
		return memory[upperText]
	end

	-- Direct match
	if (maps[kind][upperText]) then
		local result = { upperText }
		memory[upperText] = result
		return result
	end

	local found = {}
	for entityName, _ in pairs(maps[kind]) do
		if (ContainsName(upperText, entityName)) then
			found[#found + 1] = entityName
		end
	end

	local result = {}
	for _, name in ipairs(found) do
		local contained = false
		for _, other in ipairs(found) do
			if (#other > #name and other:find(name, 1, true)) then
				contained = true
				break
			end
		end
		if (not contained) then
			result[#result + 1] = name
		end
	end

	memory[upperText] = result
	return result
end

local function FinishScan(finished)
	local mapID = C_Map.GetBestMapForUnit("player")
	if (not mapID) then
		return
	end

	local position = C_Map.GetPlayerMapPosition(mapID, "player")
	if (not position) then
		return
	end

	local px, py = position:GetXY()
	local mapWidth, mapHeight = C_Map.GetMapWorldSize(mapID)
	local radius = C_Minimap.GetViewRadius()
	if (not px or not py or not mapWidth or not mapHeight or mapWidth <= 0 or mapHeight <= 0 or not radius) then
		return
	end

	local facing
	if (C_CVar.GetCVar("rotateMinimap") == "1") then
		facing = GetPlayerFacing()
		if (not facing) then
			return
		end
	end

	local maps = GetNameMaps(mapID)
	local scannerButton = _G[RSConstants.RS_BUTTON_NAME]
	if (not scannerButton) then
		return
	end

	-- Aggregate detected points by entity
	local entities = { npcs = {}, containers = {} }
	for upper, points in pairs(finished.names) do
		for kind, enabled in pairs({ npcs = finished.creatures, containers = finished.treasures }) do
			if (enabled) then
				for _, entityName in ipairs(FindNames(maps, kind, upper)) do
					if (not entities[kind][entityName]) then
						entities[kind][entityName] = {}
					end
					for key, _ in pairs(points) do
						entities[kind][entityName][key] = true
					end
				end
			end
		end
	end

	for kind, byName in pairs(entities) do
		for entityName, points in pairs(byName) do
			local best
			for _, cluster in ipairs(Cluster(points)) do
				local mx, my, yards = PointToMapCoords(cluster.x, cluster.y, finished.width, radius, facing, px, py, mapWidth, mapHeight)
				cluster.mx, cluster.my, cluster.yards = mx, my, yards
				if (not best or yards < best.yards) then
					best = cluster
				end
			end

			if (best) then
				local ids = maps[kind][entityName]
				if (kind == "npcs") then
					local npcID = ids[1]
					scannerButton:SimulateRareFound(npcID, nil, RSNpcDB.GetNpcName(npcID) or entityName, best.mx, best.my, RSConstants.NPC_VIGNETTE, RSConstants.TRACKING_SYSTEM.CLASS_SKILL_TRACKING)
				else
					local containerID = ChooseContainer(ids, mapID, best.mx, best.my)
					if (not (RSConfigDB.IsIgnoringCompletedEntities() and RSContainerDB.IsContainerOpened(containerID))) then
						scannerButton:SimulateRareFound(containerID, nil, RSContainerDB.GetContainerName(containerID) or entityName, best.mx, best.my, RSConstants.CONTAINER_VIGNETTE, RSConstants.TRACKING_SYSTEM.CLASS_SKILL_TRACKING)
					end
				end
			end
		end
	end
end

local errorBackoff = false

local function ScanSome()
	if (InCombatLockdown() or not Minimap:IsVisible() or not Minimap:GetLeft() or IsInInstance()) then
		scan = nil
		return
	end

	local left, bottom = Minimap:GetLeft(), Minimap:GetBottom()
	local scale = Minimap:GetEffectiveScale()
	local grid = scan.grid
	local deadline = debugprofilestop() + RSRoutines.GetBudgetMS()

	Minimap:SetUsingSoftCursor(true)

	local ok, err = pcall(function()
		repeat
			Probe(left, bottom, scale, grid[scan.next])
			scan.next = scan.next + 1
		until (scan.next > #grid or debugprofilestop() >= deadline)
	end)

	Minimap:SetUsingSoftCursor(false)

	if (not ok) then
		scan = nil
		errorBackoff = true
		RSLogger:PrintDebugMessage(string.format("MinimapTracking error: %s", tostring(err)))
		return
	end

	if (scan.next > #grid) then
		local finished = scan
		scan = nil
		FinishScan(finished)
	end
end

---============================================================================
-- Driver & Lifecycle
---============================================================================

local driver = CreateFrame("Frame", nil, UIParent)
driver:Hide()
local timer = 0
local wait = SCAN_INTERVAL

driver:SetScript("OnUpdate", function(_, elapsed)
	if (scan) then
		ScanSome()
		return
	end

	timer = timer + elapsed
	if (timer >= wait) then
		timer = 0
		if (errorBackoff) then
			errorBackoff = false
			wait = ERROR_INTERVAL
		elseif (StartScan()) then
			wait = SCAN_INTERVAL
		else
			wait = IDLE_INTERVAL
		end
	end
end)

function RSMinimapTracking.Start()
	if (RSConfigDB.IsScanningClassSkills()) then
		timer = 0
		wait = 0.5
		driver:Show()
	end
end

function RSMinimapTracking.Stop()
	scan = nil
	driver:Hide()
end

function RSMinimapTracking.ResetCache()
	nameMaps = {}
end
