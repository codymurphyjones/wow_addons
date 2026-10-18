local _, ns = ...
local D = ns.Data

-- Reads dungeon and raid loot from AtlasLootClassic. Its tables are only
-- read, never changed. The result is cached the first time it is built:
-- { { key, name, areaID, kind, isRaid, isCustom, comingSoon, minLevel, maxLevel,
--     bosses = { { name, items, index, displayID, npcIDs, level, comingSoon } },
--     items = { itemID, ... }, source = { [itemID] = boss name },
--     bossOf = { [itemID] = boss index } }, ... }
-- comingSoon: AtlasLoot lists the place (or boss) but has no loot recorded
-- for it yet, only a placeholder. isCustom: one of the server's own
-- ("Forever") instances. kind: "dungeon", "raid" or "world" (the journal's
-- tabs): AtlasLoot's world bosses, and world places plugins add
-- (AddWorld), which are journal only (journalOnly: not in the gear list,
-- where the plugin lists those items itself).
local A = {}
ns.AtlasData = A

local instances
local loading
local world = {} -- [key] = a world place a plugin added (AddWorld)

local function ItemDB()
    return AtlasLoot and AtlasLoot.ItemDB
end

-- Loads AtlasLoot's dungeon and raid module (it is load-on-demand), then
-- calls onReady. Returns false with a reason if it can't be loaded.
local IsAddOnLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
local LoadAddOn = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn

function A:Load(onReady)
    if instances or IsAddOnLoaded(D.ATLAS_MODULE) then onReady() return true end
    if not ItemDB() then return false, "AtlasLootClassic is not loaded." end
    if loading then return true end
    loading = true

    -- AtlasLoot's own loader first: it waits out combat for us.
    local loader = AtlasLoot.Loader
    if loader and loader.LoadModule then
        local result = loader:LoadModule(D.ATLAS_MODULE, function()
            loading = false
            onReady()
        end)
        if IsAddOnLoaded(D.ATLAS_MODULE) then return true end -- the callback has run
        if result == "InCombat" then
            return false, "AtlasLoot's dungeon data will load after combat."
        elseif type(result) == "string" then
            loading = false
            return false, D.ATLAS_MODULE .. ": " .. result:lower() .. "."
        end
    end

    -- The loader doesn't know the module yet; load it directly.
    loading = false
    if InCombatLockdown() then
        return false, "AtlasLoot's dungeon data can't load in combat. Try again after combat."
    end
    local ok, reason = LoadAddOn(D.ATLAS_MODULE)
    if not ok then
        return false, D.ATLAS_MODULE .. " could not be loaded (" .. tostring(reason) .. ")."
    end
    onReady()
    return true
end

-- The item IDs in one AtlasLoot loot entry ({ slot, value, ... }). Returns
-- true when the entry is a real item (not a header or placeholder).
local function EntryItems(entry, isSet, faction, out)
    if type(entry) ~= "table" then return false end
    local value = entry[2]
    if faction == "Horde" and entry[ATLASLOOT_IT_HORDE or 901] then
        value = entry[ATLASLOOT_IT_HORDE or 901]
    elseif faction ~= "Horde" and entry[ATLASLOOT_IT_ALLIANCE or 902] then
        value = entry[ATLASLOOT_IT_ALLIANCE or 902]
    end
    if type(value) == "string" then
        value = tonumber(value:match("^i(%d+)"))
    end
    if type(value) ~= "number" or value <= 0 then return false end -- 0: AtlasLoot placeholder
    if isSet then
        local itemSet = AtlasLoot.Data and AtlasLoot.Data.ItemSet
        local setItems = itemSet and itemSet.GetSetItems and itemSet.GetSetItems(value)
        if type(setItems) == "table" then
            for _, itemID in ipairs(setItems) do
                if type(itemID) == "number" then out[#out + 1] = itemID end
            end
        end
    else
        out[#out + 1] = value
    end
    return true
end

-- Gear in a boss's loot table, without repeats, and whether the table
-- holds any real item at all (false: only a placeholder, loot not recorded).
-- Items the shipped item data has for this boss (Data\Items.lua) are added too.
local function BossItems(db, key, index, diff, faction)
    local found, recorded = {}, false
    local ok, items, tableType = pcall(db.GetItemTable, db, D.ATLAS_MODULE, key, index, diff)
    if ok and type(items) == "table" then
        local isSet = type(tableType) == "table" and tableType[1] == "Set"
        for _, entry in ipairs(items) do
            if EntryItems(entry, isSet, faction, found) then recorded = true end
        end
    end
    -- { itemID, ..., A = { Alliance only }, H = { Horde only } }
    local shipped = ns.ItemData and ns.ItemData.sources[key]
    shipped = shipped and shipped[index]
    if shipped then
        local own = shipped[faction == "Horde" and "H" or "A"] or {}
        for _, list in ipairs({ shipped, own }) do
            for _, itemID in ipairs(list) do
                found[#found + 1] = itemID
                recorded = true
            end
        end
    end
    local out, seen = {}, {}
    for _, itemID in ipairs(found) do
        if not seen[itemID] then
            seen[itemID] = true
            local equipLoc = ns:Instant(itemID)
            if equipLoc and D.EQUIP_GROUP[equipLoc] then out[#out + 1] = itemID end
        end
    end
    return out, recorded
end

local function IsCustom(inst)
    local ok, typeName = pcall(inst.GetContentType, inst)
    return ok and type(typeName) == "string" and typeName:find("Forever") ~= nil
end

-- The boss's creature IDs as a list (AtlasLoot has a number or a table).
local function NpcIDs(boss)
    local id = boss.npcID
    if type(id) == "number" then return { id } end
    local out = {}
    if type(id) == "table" then
        for _, v in ipairs(id) do
            if type(v) == "number" then out[#out + 1] = v end
        end
    end
    return out
end

local function DisplayID(boss)
    local ids = boss.DisplayIDs
    local first = type(ids) == "table" and ids[1]
    local id = type(first) == "table" and first[1] or first
    return type(id) == "number" and id or nil
end

local function IsRaid(mod, inst)
    local uname = inst.LoadDifficulty and mod.GetDifficultyUName and mod:GetDifficultyUName(inst.LoadDifficulty)
    if uname == "r20" or uname == "r40" then return true end
    local ok, typeName = pcall(inst.GetContentType, inst)
    return ok and type(typeName) == "string" and typeName:lower():find("raid") ~= nil
end

-- Loot AtlasLoot hasn't got yet, as wowtbc.gg reports it (tools/Spyglass/fetch_web_loot.py,
-- shipped in Data\Items.lua as ItemData.reported). Items go to the AtlasLoot
-- boss of the same name, or to a new boss (index nil: AtlasLoot has no
-- page for it) when AtlasLoot's list doesn't have one by that name.
local function ApplyReported(entry, reported)
    local byName, added = {}, false
    for _, boss in ipairs(entry.bosses) do byName[boss.name:lower()] = boss end
    for _, r in ipairs(reported) do
        local items = {}
        for _, itemID in ipairs(r.items) do
            local equipLoc = ns:Instant(itemID)
            if equipLoc and D.EQUIP_GROUP[equipLoc] then items[#items + 1] = itemID end
        end
        if #items > 0 then
            local boss = byName[r.name:lower()]
            if not boss then
                boss = { name = r.name, items = {}, npcIDs = {} }
                entry.bosses[#entry.bosses + 1] = boss
                byName[r.name:lower()] = boss
                added = true
            end
            boss.comingSoon, boss.reported = false, true
            entry.comingSoon = false
            for _, itemID in ipairs(items) do
                if not tContains(boss.items, itemID) then boss.items[#boss.items + 1] = itemID end
                if not entry.source[itemID] then
                    entry.source[itemID] = boss.name
                    entry.bossOf[itemID] = boss.index
                    entry.items[#entry.items + 1] = itemID
                end
            end
        end
    end
    -- AtlasLoot's stand-in ("Loot will be updated asap!") once real bosses are there.
    if added then
        for i = #entry.bosses, 1, -1 do
            local boss = entry.bosses[i]
            if boss.comingSoon and #boss.items == 0 then table.remove(entry.bosses, i) end
        end
    end
end

-- By level, then name.
local function Order(a, b)
    if a.minLevel ~= b.minLevel then return a.minLevel < b.minLevel end
    if a.maxLevel ~= b.maxLevel then return a.maxLevel < b.maxLevel end
    return a.name < b.name
end

local function Build()
    local db = ItemDB()
    local mod = db and db:Get(D.ATLAS_MODULE)
    if not mod then return nil end
    local diff = mod:GetDifficultyByName("n") or 1
    local faction = UnitFactionGroup("player")
    local list = {}
    -- WoW Forever stops at level 60: AtlasLoot's TBC places (its data-tbc.lua,
    -- stamped with the TBC game version) don't exist there and are left out.
    local tbc = AtlasLoot.BC_VERSION_NUM
    for _, key in ipairs(db:GetModuleList(D.ATLAS_MODULE)) do
        local inst = mod[key]
        local isTBC = type(inst) == "table" and tbc and (tonumber(inst.gameVersion) or 0) >= tbc
        if type(inst) == "table" and type(inst.items) == "table" and not isTBC then
            local okName, name = pcall(inst.GetName, inst, true)
            name = okName and name or tostring(key)
            name = name:gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            name = strtrim(name)
            local raid = IsRaid(mod, inst)
            local kind = tostring(key):find("^WorldBoss") and "world" or (raid and "raid" or "dungeon")
            local range = type(inst.LevelRange) == "table" and inst.LevelRange
            local entry = {
                key = key, name = name, kind = kind, isRaid = raid, isCustom = IsCustom(inst), comingSoon = true,
                -- The instance's AreaTable ID (as the game and QuestieDB use it).
                areaID = tonumber(inst.MapID) or tonumber(inst.AreaID),
                minLevel = range and (range[2] or range[1]) or 60,
                maxLevel = range and (range[3] or range[2]) or 60,
                bosses = {}, items = {}, source = {}, bossOf = {},
            }
            for index = 1, #inst.items do
                local boss = inst.items[index]
                if type(boss) == "table" then
                    local okBoss, bossName = pcall(inst.GetNameForItemTable, inst, index, true)
                    bossName = okBoss and bossName or boss.name or ("#" .. index)
                    local items, recorded = BossItems(db, key, index, diff, faction)
                    -- Bosses with gear, and bosses whose loot isn't recorded yet. Tables
                    -- with no gear at all (keys, books) are left out.
                    if #items > 0 or not recorded then
                        if recorded then entry.comingSoon = false end
                        -- index: the boss's place in AtlasLoot's list, for opening it there.
                        entry.bosses[#entry.bosses + 1] = {
                            name = bossName, items = items, index = index, comingSoon = not recorded,
                            displayID = DisplayID(boss), npcIDs = NpcIDs(boss),
                            level = tonumber(type(boss.Level) == "table" and boss.Level[2] or boss.Level),
                        }
                        for _, itemID in ipairs(items) do
                            if not entry.source[itemID] then
                                entry.source[itemID] = bossName
                                entry.bossOf[itemID] = index
                                entry.items[#entry.items + 1] = itemID
                            end
                        end
                    end
                end
            end
            local reported = ns.ItemData and ns.ItemData.reported and ns.ItemData.reported[key]
            if reported then ApplyReported(entry, reported) end
            if #entry.bosses > 0 then list[#list + 1] = entry end
        end
    end
    for _, entry in pairs(world) do list[#list + 1] = entry end
    table.sort(list, Order)
    return list
end

-- Every item ID AtlasLoot lists for the instance (normal difficulty, your
-- faction), before any are left out. For /sg debug.
function A:RawItems(key)
    local db = ItemDB()
    local mod = db and db:Get(D.ATLAS_MODULE)
    local inst = mod and mod[key]
    if type(inst) ~= "table" or type(inst.items) ~= "table" then return {} end
    local diff = mod:GetDifficultyByName("n") or 1
    local out, seen = {}, {}
    for index = 1, #inst.items do
        local ok, items, tableType = pcall(db.GetItemTable, db, D.ATLAS_MODULE, key, index, diff)
        if ok and type(items) == "table" then
            local isSet = type(tableType) == "table" and tableType[1] == "Set"
            local found = {}
            for _, entry in ipairs(items) do EntryItems(entry, isSet, UnitFactionGroup("player"), found) end
            for _, itemID in ipairs(found) do
                if not seen[itemID] then
                    seen[itemID] = true
                    out[#out + 1] = itemID
                end
            end
        end
    end
    return out
end

-- The instance whose AtlasLoot key matches (any case), or nil.
function A:FindInstance(key)
    for _, inst in ipairs(self:GetInstances() or {}) do
        if inst.key:lower() == key:lower() then return inst end
    end
end

-- World places from a plugin (the journal's World tab): { { key, name,
-- minLevel, maxLevel, bosses = { { name, items, rare, zone } } }, ... }.
-- Only gear is kept; items, source and bossOf are filled in here. A key
-- added again replaces the old place.
function A:AddWorld(list)
    for _, place in ipairs(list or {}) do
        if type(place) == "table" and type(place.key) == "string" and type(place.bosses) == "table" then
            local entry = {
                key = place.key, name = place.name or place.key, kind = "world", isRaid = false,
                journalOnly = true, comingSoon = false, areaID = place.areaID,
                minLevel = place.minLevel or 1, maxLevel = place.maxLevel or place.minLevel or 60,
                bosses = {}, items = {}, source = {}, bossOf = {},
            }
            for _, b in ipairs(place.bosses) do
                local items = {}
                for _, itemID in ipairs(b.items or {}) do
                    local equipLoc = ns:Instant(itemID)
                    if equipLoc and D.EQUIP_GROUP[equipLoc] then items[#items + 1] = itemID end
                end
                if #items > 0 then
                    entry.bosses[#entry.bosses + 1] = { name = b.name, items = items, rare = b.rare, npcIDs = {} }
                    for _, itemID in ipairs(items) do
                        if not entry.source[itemID] then
                            entry.source[itemID] = b.name
                            entry.items[#entry.items + 1] = itemID
                        end
                    end
                end
            end
            if #entry.bosses > 0 then world[entry.key] = entry end
        end
    end
    -- Already built: rebuild the list with them (cheap: only the order).
    if instances then
        local kept = {}
        for _, inst in ipairs(instances) do
            if not (inst.journalOnly and inst.kind == "world") then kept[#kept + 1] = inst end
        end
        for _, entry in pairs(world) do kept[#kept + 1] = entry end
        table.sort(kept, Order)
        instances = kept
    end
    ns:RequestRefresh()
end

-- The instance list, or nil before AtlasLoot's data is loaded.
function A:GetInstances()
    if not instances then instances = Build() end
    return instances
end
