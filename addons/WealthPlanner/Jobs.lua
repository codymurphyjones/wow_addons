local _, ns = ...
local C = ns.Compat

-- Jobs: ways to earn gold out in the world, built from the farm data (Data\Farms.lua) and priced
-- from the market, like postings on a jobs board. Kinds:
--   mob   hunt mobs in one zone and level band for their drops (and coin)
--   skin  the same hunt, skinning what you kill (needs Skinning)
--   herb  an herbalism route through one zone (needs Herbalism)
--   mine  a mining route through one zone (needs Mining)
--   fish  fishing in one zone (needs Fishing)
-- Every job carries what you'd want to know before taking it: pay per hour (estimated, or measured
-- once you've worked it), difficulty, danger, requirements, distance, pay outlook, market depth and
-- bag load.
local Jobs = {}
ns.Jobs = Jobs

Jobs.KINDS = {
    { "mob", "Hunting", "Ability_Hunter_SniperShot" },
    { "skin", "Skinning", "INV_Misc_Pelt_Wolf_01" },
    { "herb", "Herbalism", "INV_Misc_Flower_02" },
    { "mine", "Mining", "INV_Pick_02" },
    { "fish", "Fishing", "Trade_Fishing" },
    { "craft", "Crafting", "Trade_BlackSmithing" },
}
Jobs.KIND_LABEL, Jobs.KIND_ICON = {}, {}
for _, k in ipairs(Jobs.KINDS) do Jobs.KIND_LABEL[k[1]], Jobs.KIND_ICON[k[1]] = k[2], "Interface\\Icons\\" .. k[3] end

local BAND = 5                -- mob jobs group mobs in level bands this wide
local MIN_MEASURED = 10 * 60  -- seconds worked before measured pay replaces the estimate
local PER_NODE = { herb = 1.6, mine = 1.4 } -- average items a gathering node gives
local CATCHES_PER_HOUR = 100
local NODE_RESPAWN_PER_HOUR = 0.6 -- how many times each node spawn point can be visited an hour

-- Zones where one faction is at home; everywhere else is contested.
local HOME = {
    Horde = { [1411] = true, [1412] = true, [1413] = true, [1420] = true, [1421] = true },
    Alliance = { [1426] = true, [1429] = true, [1432] = true, [1436] = true, [1438] = true, [1439] = true, [1433] = true },
}

-- ---------------------------------------------------------------------------
-- Data
-- ---------------------------------------------------------------------------

local index -- built once from ns.FarmData

local function Points(str)
    local pts = {}
    for x, y in (str or ""):gmatch("([%d%.]+),([%d%.]+)") do pts[#pts + 1] = { tonumber(x), tonumber(y) } end
    return pts
end
Jobs.Points = Points

-- npcs/objects store spawns as { [uiMapID] = { n = count, "x,y;x,y" } }.
local function Spawns(entry)
    if type(entry) ~= "table" then return {} end
    return entry[5] or entry.spawns or {}
end

local function ObjectSpawns(obj) return obj and (obj[3] or obj.spawns) or {} end

local function BuildIndex()
    if index then return index end
    index = { npcDrops = {}, skinDrops = {}, nodeDrops = {}, fishZones = {} }
    local data = ns.FarmData
    if not data then return index end
    for itemID, item in pairs(data.items or {}) do
        for _, src in ipairs(item[2] or {}) do
            local kind, id, chance = src[1], src[2], src[3] or 0
            local into = kind == "npc" and index.npcDrops or kind == "skin" and index.skinDrops
                or kind == "node" and index.nodeDrops or kind == "fish" and index.fishZones or nil
            if into and chance > 0 then
                into[id] = into[id] or {}
                table.insert(into[id], { item = itemID, chance = chance })
            end
        end
    end
    return index
end

function Jobs:HasData()
    return (ns.FarmData ~= nil and next(ns.FarmData.items or {}) ~= nil) or (ns.Crafting and ns.Crafting:Known() > 0) or false
end

-- ---------------------------------------------------------------------------
-- The player
-- ---------------------------------------------------------------------------

-- Gathering skills by English name -> rank (Classic skill lines).
function Jobs:Skills()
    local out = {}
    if GetNumSkillLines and GetSkillLineInfo then
        for i = 1, GetNumSkillLines() do
            local name, isHeader, _, rank = GetSkillLineInfo(i)
            if name and not isHeader then out[name:lower()] = rank end
        end
    end
    return out
end

local SKILL_NAME = { skin = "skinning", herb = "herbalism", mine = "mining", fish = "fishing" }

-- Skinning skill a mob of this level needs.
local function SkinSkill(level)
    if level <= 10 then return 1 end
    if level <= 20 then return (level - 10) * 10 end
    return level * 5
end

local zoneNames = {}
function Jobs.ZoneName(mapID)
    if zoneNames[mapID] == nil then
        local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
        zoneNames[mapID] = info and info.name or ("Zone " .. mapID)
    end
    return zoneNames[mapID]
end

-- World position (continent, x, y in yards) of a point on a zone map.
local function World(mapID, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x / 100, y / 100))
    if ok and continent and pos then return continent, pos:GetXY() end
end
Jobs.World = World

function Jobs:PlayerWorld()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local map = C_Map.GetBestMapForUnit("player")
    if not map then return nil end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if not (ok and pos) then return nil end
    local x, y = pos:GetXY()
    if not x or (x == 0 and y == 0) then return nil end
    return World(map, x * 100, y * 100)
end

-- ---------------------------------------------------------------------------
-- Building jobs
-- ---------------------------------------------------------------------------

-- Coin a mob of this level drops on average (copper; classic mobs drop coin about 60% of the time).
local function CoinPerKill(level) return math.floor((level * level * 0.35 + level * 2) * 0.6) end

-- Kills an hour on mobs `diff` levels above you (negative: below), before the spawn cap.
local function KillRate(diff, elite)
    local base = ns.db.options.killRate or 90
    local f = diff >= 0 and math.max(0.25, 1 - 0.12 * diff) or math.min(1.6, 1 - 0.06 * diff)
    if elite then f = f * 0.3 end
    return base * f
end

local function Center(spawnStr)
    local sx, sy, n = 0, 0, 0
    for _, pt in ipairs(Points(spawnStr)) do sx, sy, n = sx + pt[1], sy + pt[2], n + 1 end
    if n == 0 then return nil end
    return sx / n, sy / n
end

-- Raw jobs (no prices) from the data; rebuilt when the data first loads.
local raw
local function BuildRaw()
    if raw then return raw end
    raw = {}
    local data, idx = ns.FarmData, BuildIndex()
    if not data then return raw end

    -- Hunting and skinning: mobs grouped by zone and level band.
    local groups = {}
    for npcID, npc in pairs(data.npcs or {}) do
        local drops, skins = idx.npcDrops[npcID], idx.skinDrops[npcID]
        if drops or skins then
            local level = math.floor(((npc[2] or 1) + (npc[3] or npc[2] or 1)) / 2)
            local band = math.floor((level - 1) / BAND)
            for mapID, sp in pairs(Spawns(npc)) do
                for _, kind in ipairs({ "mob", "skin" }) do
                    if (kind == "mob" and drops) or (kind == "skin" and skins) then
                        local key = kind .. ":" .. mapID .. ":" .. band
                        local g = groups[key]
                        if not g then
                            g = { key = key, kind = kind, zone = mapID, npcs = {}, spawns = 0 }
                            groups[key] = g
                        end
                        g.npcs[#g.npcs + 1] = npcID
                        g.spawns = g.spawns + (sp.n or #Points(sp[1]))
                    end
                end
            end
        end
    end
    for _, g in pairs(groups) do raw[#raw + 1] = g end

    -- Gathering: one route per zone and kind, every node the zone has.
    local routes = {}
    for objID, obj in pairs(data.objects or {}) do
        local kind = obj[2] or obj.kind
        if (kind == "herb" or kind == "mine") and idx.nodeDrops[objID] then
            for mapID, sp in pairs(ObjectSpawns(obj)) do
                local key = kind .. ":" .. mapID
                local g = routes[key]
                if not g then
                    g = { key = key, kind = kind, zone = mapID, nodes = {}, spawns = 0 }
                    routes[key] = g
                end
                g.nodes[#g.nodes + 1] = objID
                g.spawns = g.spawns + (sp.n or #Points(sp[1]))
            end
        end
    end
    for _, g in pairs(routes) do raw[#raw + 1] = g end

    for mapID in pairs(idx.fishZones) do
        raw[#raw + 1] = { key = "fish:" .. mapID, kind = "fish", zone = mapID, spawns = 0 }
    end
    return raw
end

-- What one job pays and asks for, with today's prices and your character.
local function Price(g, level, skills, faction, here)
    local data, idx = ns.FarmData, BuildIndex()
    local j = { key = g.key, kind = g.kind, zone = g.zone, zoneName = Jobs.ZoneName(g.zone), npcs = g.npcs, nodes = g.nodes, spawns = g.spawns }
    local perHour = {} -- itemID -> items an hour
    local coin, minL, maxL, elite = 0, nil, nil, false
    local req = {}

    if g.kind == "mob" or g.kind == "skin" then
        local names, kills = {}, 0
        local count = 0
        for _, npcID in ipairs(g.npcs) do
            local npc = data.npcs[npcID]
            local lo, hi = npc[2] or 1, npc[3] or npc[2] or 1
            minL, maxL = math.min(minL or lo, lo), math.max(maxL or hi, hi)
            if (npc[4] or 0) == 1 then elite = true end
            names[#names + 1] = { npc[1], (Spawns(npc)[g.zone] or {}).n or 0 }
            count = count + 1
        end
        local avg = (minL + maxL) / 2
        kills = math.min(KillRate(avg - level, elite), g.spawns * 8)
        j.kills = kills
        -- Each mob's share of the kills follows how many of them spawn.
        for _, npcID in ipairs(g.npcs) do
            local npc = data.npcs[npcID]
            local share = ((Spawns(npc)[g.zone] or {}).n or 1) / math.max(1, g.spawns)
            for _, d in ipairs(idx.npcDrops[npcID] or {}) do
                perHour[d.item] = (perHour[d.item] or 0) + kills * share * d.chance
            end
            if g.kind == "skin" then
                for _, d in ipairs(idx.skinDrops[npcID] or {}) do
                    perHour[d.item] = (perHour[d.item] or 0) + kills * share * d.chance
                end
            end
        end
        -- Coin: each mob's real average drop where the data has it, else an estimate by level.
        for _, npcID in ipairs(g.npcs) do
            local npc = data.npcs[npcID]
            local share = ((Spawns(npc)[g.zone] or {}).n or 1) / math.max(1, g.spawns)
            local lvl = math.floor(((npc[2] or 1) + (npc[3] or npc[2] or 1)) / 2)
            coin = coin + (npc.coin or CoinPerKill(lvl)) * kills * share
        end
        table.sort(names, function(a, b) return a[2] > b[2] end)
        local who = names[1][1] .. (names[2] and (" and " .. names[2][1]) or "") .. (#names > 2 and (" +" .. (#names - 2)) or "")
        j.title = (g.kind == "skin" and "Skin " or "Hunt ") .. who
        j.minL, j.maxL, j.elite = minL, maxL, elite
        local diff = avg - level
        j.difficulty = math.max(1, math.min(5, (diff <= -3 and 1 or diff <= -1 and 2 or diff <= 1 and 3 or diff <= 2 and 4 or 5) + (elite and 2 or 0)))
        req[#req + 1] = { text = ("Level %d-%d mobs"):format(minL, maxL), met = maxL <= level + 3 }
        if g.kind == "skin" then
            local need = SkinSkill(maxL)
            req[#req + 1] = { text = ("Skinning %d"):format(need), met = (skills.skinning or 0) >= need }
        end
    elseif g.kind == "herb" or g.kind == "mine" then
        local nodesPerHour = math.min(60, g.spawns * NODE_RESPAWN_PER_HOUR)
        j.nodesPerHour = nodesPerHour
        local names, needMax = {}, 0
        local reachable = 0
        local have = skills[SKILL_NAME[g.kind]] or 0
        for _, objID in ipairs(g.nodes) do
            local obj = data.objects[objID]
            local need = obj.skill or 1
            local n = (ObjectSpawns(obj)[g.zone] or {}).n or 0
            if need <= have then reachable = reachable + n end
            needMax = math.max(needMax, need)
            names[#names + 1] = { obj[1], n, need }
        end
        table.sort(names, function(a, b) return a[2] > b[2] end)
        -- Nodes you can't gather yet don't pay; with none gatherable the route is priced as if you could.
        local usable = reachable > 0 and reachable or g.spawns
        for _, objID in ipairs(g.nodes) do
            local obj = data.objects[objID]
            if reachable == 0 or (obj.skill or 1) <= have then
                local share = ((ObjectSpawns(obj)[g.zone] or {}).n or 1) / math.max(1, usable)
                for _, d in ipairs(idx.nodeDrops[objID] or {}) do
                    perHour[d.item] = (perHour[d.item] or 0) + nodesPerHour * share * d.chance * PER_NODE[g.kind]
                end
            end
        end
        j.title = (g.kind == "herb" and "Pick " or "Mine ") .. names[1][1] .. (names[2] and (" and " .. names[2][1]) or "")
            .. (#names > 2 and (" +" .. (#names - 2)) or "")
        j.difficulty = 1
        local minNeed = names[1][3]
        for _, n in ipairs(names) do minNeed = math.min(minNeed, n[3]) end
        req[#req + 1] = { text = ("%s %d"):format(g.kind == "herb" and "Herbalism" or "Mining", minNeed), met = have >= minNeed }
        if needMax > minNeed then
            req[#req + 1] = { text = ("all nodes at %d"):format(needMax), met = have >= needMax, soft = true }
        end
    else -- fish
        for _, d in ipairs(idx.fishZones[g.zone] or {}) do
            perHour[d.item] = (perHour[d.item] or 0) + CATCHES_PER_HOUR * d.chance
        end
        j.title = "Fish in " .. j.zoneName
        j.difficulty = 1
        req[#req + 1] = { text = "Fishing", met = (skills.fishing or 0) > 0 }
    end

    -- Pay, outlook and market depth from the goods.
    local goods, trend, vol, weight, stacks = 0, 0, 0, 0, 0
    local drops, depthWarn = {}, false
    for itemID, n in pairs(perHour) do
        local price = ns.Prices:Price(itemID) or ns.Prices:Vendor(itemID) or 0
        local value = price * n
        goods = goods + value
        local s = ns.Analytics:Stats(itemID)
        if s and value > 0 then
            if s.chg7 then trend = trend + s.chg7 * value end
            if s.vol then vol = vol + s.vol * value end
            weight = weight + value
            -- You'd bring more in an hour than the market usually lists: hard to sell it all.
            if s.supplyAvg and n > s.supplyAvg * 0.5 then depthWarn = true end
        end
        local maxStack = select(8, C.GetItemInfo(itemID)) or 20
        stacks = stacks + n / math.max(1, maxStack)
        drops[#drops + 1] = { item = itemID, perHour = n, price = price, value = value, stats = s }
    end
    table.sort(drops, function(a, b) return a.value > b.value end)
    j.drops = drops
    j.payGoods, j.payCoin = goods, coin
    j.estimate = goods + coin
    j.outlook = weight > 0 and trend / weight or nil
    j.volatility = weight > 0 and vol / weight or nil
    j.saturated = depthWarn
    j.stacksPerHour = stacks
    j.req = req
    j.reqMet = true
    for _, r in ipairs(req) do if not r.met and not r.soft then j.reqMet = false end end

    local stats = ns.db.jobStats[g.key]
    if stats and (stats.secs or 0) >= MIN_MEASURED then
        j.measured = stats.value / stats.secs * 3600
        j.pay = j.measured
    else
        j.pay = j.estimate
    end

    local home = HOME[faction]
    local enemy = HOME[faction == "Horde" and "Alliance" or "Horde"]
    j.danger = home and home[g.zone] and "safe" or (enemy and enemy[g.zone] and "hostile") or "contested"

    -- Distance from you to the middle of the job's spawns.
    j.distance = nil
    if here then
        local str
        if g.npcs then str = (Spawns(data.npcs[g.npcs[1]])[g.zone] or {})[1]
        elseif g.nodes then str = (ObjectSpawns(data.objects[g.nodes[1]])[g.zone] or {})[1] end
        local cx, cy = Center(str)
        if not cx then cx, cy = 50, 50 end
        local continent, x, y = World(g.zone, cx, cy)
        if continent and continent == here[1] then
            j.distance = math.sqrt((x - here[2]) ^ 2 + (y - here[3]) ^ 2)
        elseif continent then
            j.distance = math.huge
        end
    end
    return j
end

-- ---------------------------------------------------------------------------
-- The board
-- ---------------------------------------------------------------------------

local board, boardAt = nil, 0

function Jobs:Invalidate() board = nil end

-- Every job for your character, priced now, best paid first. Filtered by ns.char.jobFilter when
-- `filtered` is true.
function Jobs:All()
    if board and GetTime() - boardAt < 5 then return board end
    local level = UnitLevel("player") or 1
    local skills = self:Skills()
    local faction = UnitFactionGroup("player")
    local continent, x, y = self:PlayerWorld()
    local here = continent and { continent, x, y } or nil
    local out = {}
    for _, g in ipairs(BuildRaw()) do
        local ok, j = pcall(Price, g, level, skills, faction, here)
        if ok and j and j.pay and j.pay > 0 then out[#out + 1] = j end
    end
    if ns.Crafting then
        local ok, crafts = pcall(ns.Crafting.Jobs, ns.Crafting)
        if ok then
            for _, j in ipairs(crafts) do j.pay = j.estimate; out[#out + 1] = j end
        end
    end
    table.sort(out, function(a, b) return a.pay > b.pay end)
    -- Badges, from the best on the board.
    local nearest, best = nil, out[1]
    for _, j in ipairs(out) do
        if j.distance and j.distance < math.huge and (not nearest or j.distance < nearest.distance) then nearest = j end
    end
    for _, j in ipairs(out) do
        local badges = {}
        if j == best then badges[#badges + 1] = "Best pay" end
        if j.difficulty <= 2 and j.reqMet then badges[#badges + 1] = "Easy" end
        if j == nearest or (j.distance and j.distance < 800) then badges[#badges + 1] = "Near you" end
        if j.outlook and j.outlook > 0.1 then badges[#badges + 1] = "Pay rising" end
        if j.measured then badges[#badges + 1] = "Measured" end
        if j.diff == "orange" or j.diff == "yellow" then badges[#badges + 1] = "Skill-up" end
        if j.learnable then badges[#badges + 1] = "Learnable" end
        j.badges = badges
    end
    board, boardAt = out, GetTime()
    return out
end

-- Jobs that pass your filters (kinds, requirements, level), in the chosen order.
function Jobs:Board()
    local f = ns.char.jobFilter
    local level = UnitLevel("player") or 1
    local above = ns.db.options.levelAbove or 2
    local out = {}
    for _, j in ipairs(self:All()) do
        local keep = f.kinds[j.kind] ~= false
        if keep and f.reqMet and not j.reqMet then keep = false end
        if keep and j.minL and j.minL > level + above then keep = false end
        if keep and f.maxDifficulty and j.difficulty > f.maxDifficulty then keep = false end
        if keep and f.safeOnly and j.danger ~= "safe" then keep = false end
        if keep then out[#out + 1] = j end
    end
    local sort = f.sort or "pay"
    if sort ~= "pay" then
        table.sort(out, function(a, b)
            if sort == "distance" then return (a.distance or math.huge) < (b.distance or math.huge) end
            if sort == "difficulty" then
                if a.difficulty ~= b.difficulty then return a.difficulty < b.difficulty end
                return a.pay > b.pay
            end
            if sort == "outlook" then return (a.outlook or -1) > (b.outlook or -1) end
            return a.pay > b.pay
        end)
    end
    return out
end

function Jobs:Get(key)
    for _, j in ipairs(self:All()) do if j.key == key then return j end end
end

-- ---------------------------------------------------------------------------
-- Taking a job
-- ---------------------------------------------------------------------------

function Jobs:Active()
    local key = ns.char.activeJob
    return key and self:Get(key) or nil
end

-- Takes a job (or quits with nil): its pins go on the maps, the tracker shows, the clock starts.
function Jobs:Take(key)
    local old = ns.char.activeJob
    if old and ns.Session then ns.Session:Stop() end
    ns.char.activeJob = key
    -- Waypoint's arrow follows the job you take.
    if key then ns.char.trackedJob = nil end
    if ns.Nav then ns.Nav:Invalidate() end
    if key then
        local j = self:Get(key)
        if ns.Session then ns.Session:Start(key, j and j.title, j and j.estimate) end
        ns:Print(("Job taken: %s in %s. Its spots are on your map."):format(j and j.title or key, j and j.zoneName or "?"))
    elseif old then
        ns:Print("Job finished. See the Work Log for how it paid.")
    end
    ns:Changed()
end

-- Points on one zone for the active job: { { x, y, label, color, kind, id } }.
function Jobs:Pins(job, mapID)
    local out = {}
    local data = ns.FarmData
    if not (job and data) then return out end
    if job.npcs then
        for i, npcID in ipairs(job.npcs) do
            local npc = data.npcs[npcID]
            local sp = Spawns(npc)[mapID]
            if sp then
                for _, pt in ipairs(Points(sp[1])) do
                    out[#out + 1] = { pt[1], pt[2], kind = "npc", id = npcID, index = i }
                end
            end
        end
    elseif job.nodes then
        for i, objID in ipairs(job.nodes) do
            local sp = ObjectSpawns(data.objects[objID])[mapID]
            if sp then
                for _, pt in ipairs(Points(sp[1])) do
                    out[#out + 1] = { pt[1], pt[2], kind = "object", id = objID, index = i }
                end
            end
        end
    end
    return out
end

-- Drop table for one mob or node: { { item, chance } }.
function Jobs:DropsOf(kind, id)
    local idx = BuildIndex()
    if kind == "npc" then
        local out = {}
        for _, d in ipairs(idx.npcDrops[id] or {}) do out[#out + 1] = d end
        for _, d in ipairs(idx.skinDrops[id] or {}) do out[#out + 1] = { item = d.item, chance = d.chance, skin = true } end
        return out
    end
    return idx.nodeDrops[id] or {}
end

ns:On("PLAYER_LEVEL_UP", function() Jobs:Invalidate(); ns:Changed() end)
ns:On("SKILL_LINES_CHANGED", function() Jobs:Invalidate() end)
ns:On("ZONE_CHANGED_NEW_AREA", function() Jobs:Invalidate() end)
