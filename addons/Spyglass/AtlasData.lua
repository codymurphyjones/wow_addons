local _, ns = ...
local D = ns.Data

-- Dungeon and raid loot, from SpyGlass's own data (Data\Loot.lua, built by
-- tools/Spyglass/build_loot.py from AtlasLoot Continued's tables and SpyGlass's
-- harvest of what AtlasLoot listed in game). AtlasLoot doesn't have to be
-- installed. The result is cached the first time it is built:
-- { { key, name, areaID, kind, isRaid, isCustom, comingSoon, minLevel, maxLevel,
--     bosses = { { name, items, index, displayID, npcIDs, level, comingSoon } },
--     items = { itemID, ... }, source = { [itemID] = boss name },
--     bossOf = { [itemID] = boss index } }, ... }
-- comingSoon: the place (or boss) is known but its loot isn't recorded yet.
-- isCustom: one of the server's own ("Forever") instances. kind: "dungeon",
-- "raid" or "world" (the journal's tabs): the world bosses, and world places
-- plugins add (AddWorld), which are journal only (journalOnly: not in the gear
-- list, where the plugin lists those items itself). The keys are AtlasLoot's,
-- so "Open in AtlasLoot" still finds the page when AtlasLoot is installed.
local A = {}
ns.AtlasData = A

local instances
local world = {} -- [key] = a world place a plugin added (AddWorld)

-- The loot is shipped, so it's always ready: onReady runs now. (Kept for the
-- API: callers used to wait for AtlasLoot's load-on-demand module.)
function A:Load(onReady)
    onReady()
    return true
end

-- A boss's gear for your faction, without repeats, and whether its table
-- holds any real item at all (false: loot not recorded yet).
local function BossItems(boss, faction)
    local lists = { boss.items or {}, boss[faction == "Horde" and "H" or "A"] or {} }
    local out, seen, recorded = {}, {}, false
    for _, list in ipairs(lists) do
        for _, itemID in ipairs(list) do
            recorded = true
            if not seen[itemID] then
                seen[itemID] = true
                local equipLoc = ns:Instant(itemID)
                if equipLoc and D.EQUIP_GROUP[equipLoc] then out[#out + 1] = itemID end
            end
        end
    end
    return out, recorded
end

-- Loot not in the shipped tables yet, as wowtbc.gg reports it (tools/Spyglass/fetch_web_loot.py,
-- shipped in Data\Items.lua as ItemData.reported). Items go to the boss of
-- the same name, or to a new boss (index nil: no page for it) when the list
-- doesn't have one by that name.
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
    -- The "coming soon" stand-in once real bosses are there.
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
    local data = ns.LootData
    if not data then return nil end
    local faction = UnitFactionGroup("player")
    local list = {}
    for _, inst in ipairs(data.instances) do
        local raid = inst.isRaid and true or false
        local entry = {
            key = inst.key, name = inst.name, kind = inst.world and "world" or (raid and "raid" or "dungeon"),
            isRaid = raid, isCustom = inst.isCustom and true or false, comingSoon = true,
            -- The instance's AreaTable ID (as the game and QuestieDB use it).
            areaID = inst.areaID,
            minLevel = inst.minLevel or 60, maxLevel = inst.maxLevel or 60,
            bosses = {}, items = {}, source = {}, bossOf = {},
        }
        for index, boss in ipairs(inst.bosses) do
            local items, recorded = BossItems(boss, faction)
            -- Bosses with gear, and bosses whose loot isn't recorded yet. Tables
            -- with no gear at all (keys, books) are left out.
            if #items > 0 or not recorded then
                if recorded then entry.comingSoon = false end
                -- index: the boss's place in AtlasLoot's list, for opening it there.
                entry.bosses[#entry.bosses + 1] = {
                    name = boss.name, items = items, index = index, comingSoon = not recorded,
                    displayID = boss.displayID, npcIDs = boss.npcIDs or {}, level = boss.level,
                }
                for _, itemID in ipairs(items) do
                    if not entry.source[itemID] then
                        entry.source[itemID] = boss.name
                        entry.bossOf[itemID] = index
                        entry.items[#entry.items + 1] = itemID
                    end
                end
            end
        end
        local reported = ns.ItemData and ns.ItemData.reported and ns.ItemData.reported[inst.key]
        if reported then ApplyReported(entry, reported) end
        if #entry.bosses > 0 then list[#list + 1] = entry end
    end
    for _, entry in pairs(world) do list[#list + 1] = entry end
    table.sort(list, Order)
    return list
end

-- Every item ID listed for the instance (your faction), before any are left
-- out. For /sg debug.
function A:RawItems(key)
    local faction = UnitFactionGroup("player") == "Horde" and "H" or "A"
    local out, seen = {}, {}
    for _, inst in ipairs(ns.LootData and ns.LootData.instances or {}) do
        if inst.key == key then
            for _, boss in ipairs(inst.bosses) do
                for _, list in ipairs({ boss.items or {}, boss[faction] or {} }) do
                    for _, itemID in ipairs(list) do
                        if not seen[itemID] then
                            seen[itemID] = true
                            out[#out + 1] = itemID
                        end
                    end
                end
            end
        end
    end
    return out
end

-- The instance whose key matches (any case), or nil.
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

-- The instance list (the shipped loot plus plugins' world places).
function A:GetInstances()
    if not instances then instances = Build() end
    return instances
end

-- ---------------------------------------------------------------------------
-- Reading an installed AtlasLoot: only the dev harvester (Dev\Harvest.lua)
-- does, to record what a new AtlasLoot lists in game.
-- ---------------------------------------------------------------------------

-- The item IDs in one AtlasLoot loot entry ({ slot, value, ... }). Returns
-- true when the entry is a real item (not a header or placeholder).
function A.EntryItems(entry, isSet, faction, out)
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
        local itemSet = AtlasLoot and AtlasLoot.Data and AtlasLoot.Data.ItemSet
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
