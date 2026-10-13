local _, ns = ...

-- Every other known item and where it comes from: world drops, vendors and
-- crafted gear (Data\Sources.lua, built by Spyglass\Tools\build_sources.py).
-- Nothing here ranks anything: SpyGlass scores each item by your StatLedger
-- priorities, the same as dungeon loot.
local S = {}
ns.SourceIndex = S

local PREFIX = "|TInterface\\AddOns\\Spyglass\\Media\\Icon:14:14|t |cff66bbffSpyGlass|r: "

S.CATEGORIES = {
    { key = "world", label = "World", kinds = { world = true } },
    { key = "vendors", label = "Vendors", kinds = { vendor = true } },
    { key = "crafted", label = "Crafted", kinds = { craft = true } },
}

local WORLD_LABEL = {
    world = "World drop", rare = "Rare", boss = "Boss", trash = "Drops from",
    object = "Found in", container = "Found in", fishing = "Fishing", mail = "Mail", special = "Special",
}

local function Facts(itemID)
    return ns.Sources and ns.Sources.items[itemID]
end

-- The item's expected required level, before the game answers.
local function LevelHint(f)
    if f.req and f.req > 0 then return f.req end
    if f.ilvl and f.ilvl > 0 then return math.max(1, f.ilvl - 5) end
    return f.lv and tonumber(f.lv:match("^(%d+)")) or nil
end

---------------------------------------------------------------------------
-- Packed fields (Data\Sources.lua keeps lists as strings, so the game holds
-- one string per item rather than many small tables). Unpacked only for the
-- item you hover or click, and kept in a weak table so they can go again.
---------------------------------------------------------------------------

local SIDE = { A = "Alliance", H = "Horde" }
local unpacked = setmetatable({}, { __mode = "k" }) -- [facts] = { spots, mats, rep }

local function Unpack(f)
    local u = unpacked[f]
    if u then return u end
    u = { spots = {}, mats = {}, rep = {} }
    for map, x, y, side in (f.spots or ""):gmatch("([^,;]+),([^,;]+),([^,;]+),(%a?)") do
        u.spots[#u.spots + 1] = { map = tonumber(map), x = tonumber(x), y = tonumber(y), fac = SIDE[side] }
    end
    for id, count, name in (f.mats or ""):gmatch("([^,;]+),([^,;]+),([^;]*)") do
        u.mats[#u.mats + 1] = { tonumber(id), tonumber(count), name }
    end
    for faction, standing in (f.rep or ""):gmatch("([^:;]+):([^;]+)") do
        u.rep[#u.rep + 1] = { faction, standing }
    end
    unpacked[f] = u
    return u
end

---------------------------------------------------------------------------
-- What your character has: reputation and professions (read once, and
-- again only after they change)
---------------------------------------------------------------------------

local STANDINGS = { Hated = 1, Hostile = 2, Unfriendly = 3, Neutral = 4, Friendly = 5, Honored = 6, Revered = 7, Exalted = 8 }
local standings, skills

-- Your standing with a faction by name (1-8), or nil when you haven't met it.
local function Standing(name)
    if not standings then
        standings = {}
        if GetNumFactions and GetFactionInfo then
            for i = 1, GetNumFactions() do
                local fname, _, standingID, _, _, _, _, _, isHeader = GetFactionInfo(i)
                if fname and not isHeader then standings[fname] = standingID end
            end
        end
    end
    return standings[name]
end

-- Your skill in a profession by name, or nil when you don't have it.
local function Skill(name)
    if not skills then
        skills = {}
        if GetNumSkillLines and GetSkillLineInfo then
            for i = 1, GetNumSkillLines() do
                local sname, isHeader, _, rank = GetSkillLineInfo(i)
                if sname and not isHeader then skills[sname] = rank end
            end
        end
    end
    return skills[name]
end

local watcher = CreateFrame("Frame")
pcall(watcher.RegisterEvent, watcher, "UPDATE_FACTION")
pcall(watcher.RegisterEvent, watcher, "SKILL_LINES_CHANGED")
watcher:SetScript("OnEvent", function(_, event)
    if event == "UPDATE_FACTION" then standings = nil else skills = nil end
end)

---------------------------------------------------------------------------
-- Map spots
---------------------------------------------------------------------------

local function MapName(mapID)
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    return info and info.name or ("map " .. mapID)
end

-- The nearest spot your faction can use: one on the map you're on, else the
-- closest on your continent, else the first. Also how many there are.
local scratch
local function NearestSpot(f)
    local faction = UnitFactionGroup("player")
    local usable, best, bestD = 0, nil, math.huge
    local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local hereCont, hereWorld
    for _, s in ipairs(Unpack(f).spots) do
        if not s.fac or s.fac == faction then
            usable = usable + 1
            if s.map == here then
                if bestD > -1 then best, bestD = s, -1 end
            elseif bestD > -1 then
                if hereWorld == nil then
                    -- Your own position, once, and only when it's needed.
                    hereWorld = false
                    local pos = here and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(here, "player")
                    if pos and C_Map.GetWorldPosFromMapPos then
                        local ok, cont, world = pcall(C_Map.GetWorldPosFromMapPos, here, pos)
                        if ok and world then hereCont, hereWorld = cont, world end
                    end
                end
                local d = 1e300 -- distance unknown: still better than no spot
                if hereWorld and CreateVector2D then
                    scratch = scratch or CreateVector2D(0, 0)
                    scratch:SetXY(s.x / 100, s.y / 100)
                    local ok, cont, world = pcall(C_Map.GetWorldPosFromMapPos, s.map, scratch)
                    if ok and cont == hereCont and world then
                        local dx, dy = world.x - hereWorld.x, world.y - hereWorld.y
                        d = math.sqrt(dx * dx + dy * dy)
                    end
                end
                if d < bestD then best, bestD = s, d end
            end
        end
    end
    return best, usable
end

---------------------------------------------------------------------------
-- Origins: the row text (for every listed item) and tooltip lines (on hover)
---------------------------------------------------------------------------

-- The zone by name, or (Wowhead's entries) by AreaTable ID, named in game.
local areaNames = {}
local function Zone(f)
    if f.zone or not f.area then return f.zone end
    local name = areaNames[f.area]
    if name == nil then
        name = C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(f.area) or false
        areaNames[f.area] = name
    end
    return name or nil
end

local function Where(f)
    local zone = Zone(f)
    if f.npc and zone then return f.npc .. " - " .. zone end
    return f.npc or zone
end

local function Text(f)
    local zone = Zone(f)
    if f.k == "vendor" then
        return "Vendor: " .. (Where(f) or "?")
    elseif f.k == "craft" then
        return "Crafted: " .. (f.prof or "?") .. (f.skill and (" (" .. f.skill .. ")") or "")
    elseif f.k == "quest" then
        if not f.quest then return "Quest: " .. (zone or "?") end
        return "Quest: " .. f.quest .. (zone and (" - " .. zone) or "")
    end
    local label = WORLD_LABEL[f.s or "world"] or "World drop"
    if f.s == "world" or not f.s then
        if f.open or not f.npc then
            return label .. (f.lv and (", levels " .. f.lv) or (zone and (": " .. zone) or ""))
        end
    end
    local where = Where(f)
    return label .. (where and (": " .. where) or "")
end

local GOOD, BAD, GREY = "|cff40ff40", "|cffff6060", "|cff9a9a9a"

local function Lines(origin)
    local f = Facts(origin.item)
    if not f then return {} end
    local u = Unpack(f)
    local lines = {}
    if f.t then lines[#lines + 1] = f.t end
    for _, rep in ipairs(u.rep) do
        local name, need = rep[1], rep[2]
        local have = Standing(name)
        local ok = have and STANDINGS[need] and have >= STANDINGS[need]
        local yours = have and _G["FACTION_STANDING_LABEL" .. have] or "not met yet"
        lines[#lines + 1] = (ok and GOOD or BAD) .. "Needs " .. need .. " with " .. name .. " (you: " .. yours .. ")|r"
    end
    if f.k == "craft" and f.prof then
        local rank = Skill(f.prof)
        if not rank then
            lines[#lines + 1] = GREY .. "You don't have " .. f.prof .. ".|r"
        elseif f.skill and rank < f.skill then
            lines[#lines + 1] = BAD .. f.prof .. " " .. rank .. " of " .. f.skill .. " needed.|r"
        else
            lines[#lines + 1] = GOOD .. "Your " .. f.prof .. ": " .. rank .. ".|r"
        end
        if #u.mats > 0 then
            local parts = {}
            for _, m in ipairs(u.mats) do
                parts[#parts + 1] = (m[2] or 1) .. "x " .. (m[3] ~= "" and m[3] or ("item " .. m[1]))
            end
            lines[#lines + 1] = "Reagents: " .. table.concat(parts, ", ")
        end
    end
    local spot, count = NearestSpot(f)
    if spot then
        lines[#lines + 1] = string.format("%s%s: %s %.1f, %.1f%s|r", GREY, f.note and (f.note:gsub("^%l", string.upper)) or "Map",
            MapName(spot.map), spot.x, spot.y, count > 1 and (" (+" .. (count - 1) .. " more)") or "")
    end
    return lines
end

-- Cheap: runs for every listed item (SpyGlass keeps the answer).
local function Resolve(origin)
    local f = Facts(origin.item)
    if not f then return { available = false, reason = "no source data" } end
    -- Green or better only, like quest rewards (the game's quality wins).
    local info = SpyGlass:PeekItem(origin.item)
    if (info and info.quality or f.q or 2) < 2 then return { available = false, reason = "below green" } end
    return { available = true, text = Text(f) }
end

local function TrackKey(itemID)
    return "source:" .. itemID
end

function S:Track(itemID)
    local f = Facts(itemID)
    local spot = f and NearestSpot(f)
    if not spot then
        print(PREFIX .. "no map spot is known for this item.")
        return
    end
    local info = SpyGlass:PeekItem(itemID)
    SpyGlass:SetWaypoint({
        uiMapID = spot.map, x = spot.x / 100, y = spot.y / 100,
        title = (info and info.name or f.name or ("Item " .. itemID)),
        subtitle = Text(f), key = TrackKey(itemID),
        onClick = function() S:Track(itemID) end,
    })
end

local function OnClick(origin)
    local wp = SpyGlass:GetWaypoint()
    if wp and wp.key == TrackKey(origin.item) then
        SpyGlass:ClearWaypoint()
    else
        S:Track(origin.item)
    end
end

S.origins = {
    source = { Resolve = Resolve, Lines = Lines, OnClick = OnClick },
}

-- A waypoint saved before a reload gets its click handler back.
function S:RestoreTracking()
    local wp = SpyGlass:GetWaypoint()
    local itemID = wp and wp.key and tonumber(wp.key:match("^source:(%d+)$"))
    if itemID and Facts(itemID) then self:Track(itemID) end
end

---------------------------------------------------------------------------
-- Building the entries
---------------------------------------------------------------------------

-- The shipped quests' IDs by name: a function from a name to { ids }.
local function QuestNames(onDone)
    local byName = {}
    for id, q in pairs(ns.QuestDB.quests) do
        if q.name then
            local ids = byName[q.name] or {}
            byName[q.name] = ids
            ids[#ids + 1] = id
        end
    end
    onDone(function(name) return byName[name] end)
end

-- World drops from a named mob (a rare, a boss out in the world, a named
-- creature) go to the journal's World tab too: one place per zone.
local WORLD_MOBS = { rare = true, boss = true, trash = true }

-- { { key, name, minLevel, maxLevel, bosses = { { name, items, rare } } } }
-- for SpyGlass:AddWorldInstances: rares first, then by name.
local function WorldPlaces(zones)
    local out = {}
    for zone, mobs in pairs(zones) do
        local place = { key = "World:" .. zone, name = zone, bosses = {} }
        local lo, hi
        for name, mob in pairs(mobs) do
            place.bosses[#place.bosses + 1] = { name = name, items = mob.items, rare = mob.rare }
            for _, level in ipairs(mob.levels) do
                if level then
                    lo = math.min(lo or level, level)
                    hi = math.max(hi or level, level)
                end
            end
        end
        table.sort(place.bosses, function(a, b)
            if (a.rare or false) ~= (b.rare or false) then return a.rare or false end
            return a.name < b.name
        end)
        place.minLevel, place.maxLevel = lo or 1, hi or lo or 60
        out[#out + 1] = place
    end
    return out
end

-- Builds the World, Vendors and Crafted entries, and finds quest rewards that
-- the quest data didn't tie to a quest (its rewards lists), by the quest's name.
-- rewarded = { [itemID] = true } for items the Quests button has already.
-- Calls onDone(categories, questEntries): each quest entry has quest (its
-- ID) or, when the quest data doesn't know it, a "source" origin.
function S:Build(rewarded, onDone)
    local items = ns.Sources and ns.Sources.items
    if not items then onDone({}, {}) return end
    local faction = UnitFactionGroup("player")
    QuestNames(function(idsByName)
        local lists, quests = {}, {}
        local zones = {} -- the journal's World tab: [zone] = { [mob] = { itemID, ... } }
        for _, cat in ipairs(self.CATEGORIES) do lists[cat.key] = {} end
        for itemID, f in pairs(items) do
            if (f.q or 2) >= 2 and (not f.fac or f.fac == faction) then
                if f.k == "world" and f.npc and WORLD_MOBS[f.s or ""] then
                    local zone = Zone(f) or "The world"
                    zones[zone] = zones[zone] or {}
                    local mob = zones[zone][f.npc] or { rare = f.s == "rare", items = {}, levels = {} }
                    zones[zone][f.npc] = mob
                    mob.items[#mob.items + 1] = itemID
                    mob.levels[#mob.levels + 1] = LevelHint(f)
                end
                if f.k == "quest" then
                    if not rewarded[itemID] then
                        local ids = idsByName and f.quest and idsByName(f.quest)
                        local quest
                        for _, id in ipairs(ids or {}) do
                            if ns.Quests:Allowed(id) then quest = id break end
                        end
                        -- The quest data doesn't know the quest: the source's own text.
                        quests[#quests + 1] = {
                            itemID = itemID, quest = quest, levelHint = LevelHint(f),
                            origin = not quest and { kind = "source", item = itemID } or nil,
                        }
                    end
                else
                    for _, cat in ipairs(self.CATEGORIES) do
                        if cat.kinds[f.k] then
                            local list = lists[cat.key]
                            list[#list + 1] = { itemID = itemID, levelHint = LevelHint(f), origin = { kind = "source", item = itemID } }
                        end
                    end
                end
            end
        end
        local categories = {}
        for _, cat in ipairs(self.CATEGORIES) do
            categories[#categories + 1] = { key = cat.key, label = cat.label, entries = lists[cat.key] }
        end
        if SpyGlass.AddWorldInstances then SpyGlass:AddWorldInstances(WorldPlaces(zones)) end
        onDone(categories, quests)
    end)
end
