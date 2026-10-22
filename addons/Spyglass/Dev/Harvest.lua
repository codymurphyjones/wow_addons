local _, ns = ...
local D = ns.Data

-- Developer tool: /sg harvest asks the server, slowly, about every item
-- AtlasLoot lists for dungeons and raids and every gear item in
-- D.HARVEST_RANGES, and saves what it learns in SpyGlassDevDB. Run
-- tools/Spyglass/build_items.py afterwards to turn that into Data\Items.lua.
-- Only exists when D.DEV_MODE is true.
if not D.DEV_MODE then return end

local H = {}
ns.Harvest = H

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstant = C_Item.GetItemInfoInstant -- no global on WoW Forever
local RequestLoadItemDataByID = C_Item and C_Item.RequestLoadItemDataByID

local MAX_TRIES, RETRY_AFTER = 3, 5
local SCAN_PER_TICK = 500 -- IDs checked locally (no server cost) per tick

-- SpyGlassDevDB = {
--   items = { [itemID] = { name, quality, itemLevel, reqLevel, equipLoc, classID,
--             subClassID, subType, icon, stats, classes, effects } },
--   sources = { [instKey] = { name, minLevel, maxLevel, isRaid, isCustom,
--               bosses = { [index] = { name, Alliance = { ids }, Horde = { ids } } } } },
--   skip = { [itemID] = true },      -- answered, but not gear
--   failed = { [itemID] = true },    -- never answered
--   encrypted = { [itemID] = true }, -- the client keeps it encrypted
--   state = { phase, range, cursor, running, inflight = { [itemID] = true },
--             extra = { [itemID] = true } }, -- asked for by plugins (H:Enqueue)
-- }
local db
local queue = {}   -- AtlasLoot items still to ask about
local waiting = {} -- [itemID] = { tries, at, probe }
local ticker
local startedAt, savedAtStart

local function Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function Init()
    SpyGlassDevDB = type(SpyGlassDevDB) == "table" and SpyGlassDevDB or {}
    db = SpyGlassDevDB
    db.version = 1
    for _, k in ipairs({ "items", "sources", "skip", "failed", "encrypted", "state" }) do
        db[k] = type(db[k]) == "table" and db[k] or {}
    end
    db.state.inflight = type(db.state.inflight) == "table" and db.state.inflight or {}
    db.state.extra = type(db.state.extra) == "table" and db.state.extra or {}
    db.build = GetBuildInfo and select(2, GetBuildInfo()) or "?"
end

local function Known(itemID)
    return db.items[itemID] or db.skip[itemID] or db.failed[itemID] or db.encrypted[itemID]
end

---------------------------------------------------------------------------
-- Phase 1: AtlasLoot
---------------------------------------------------------------------------

-- Records where every AtlasLoot dungeon and raid item drops (both
-- factions, every difficulty, gear or not) and queues the unknown ones.
local function WalkAtlas()
    local itemDB = AtlasLoot and AtlasLoot.ItemDB
    local mod = itemDB and itemDB:Get(D.ATLAS_MODULE)
    if not mod then return false end
    local names = {}
    for _, inst in ipairs(ns.AtlasData:GetInstances() or {}) do names[inst.key] = inst end
    local queued = {}
    for _, key in ipairs(itemDB:GetModuleList(D.ATLAS_MODULE)) do
        local inst = mod[key]
        if type(inst) == "table" and type(inst.items) == "table" then
            local known = names[key]
            local okName, name = pcall(inst.GetName, inst, true)
            local range = type(inst.LevelRange) == "table" and inst.LevelRange
            local src = {
                name = known and known.name or (okName and name) or tostring(key),
                minLevel = range and (range[2] or range[1]) or nil,
                maxLevel = range and (range[3] or range[2]) or nil,
                isRaid = known and known.isRaid or nil, isCustom = known and known.isCustom or nil,
                bosses = {},
            }
            for index, boss in ipairs(inst.items) do
                if type(boss) == "table" then
                    local okBoss, bossName = pcall(inst.GetNameForItemTable, inst, index, true)
                    local entry = { name = okBoss and bossName or boss.name or ("#" .. index), Alliance = {}, Horde = {} }
                    for diff, t in pairs(boss) do
                        if type(diff) == "number" and type(t) == "table" then
                            local ok, items, tableType = pcall(itemDB.GetItemTable, itemDB, D.ATLAS_MODULE, key, index, diff)
                            if ok and type(items) == "table" then
                                local isSet = type(tableType) == "table" and tableType[1] == "Set"
                                for _, faction in ipairs({ "Alliance", "Horde" }) do
                                    for _, e in ipairs(items) do
                                        ns.AtlasData.EntryItems(e, isSet, faction, entry[faction])
                                    end
                                end
                            end
                        end
                    end
                    for _, faction in ipairs({ "Alliance", "Horde" }) do
                        for _, itemID in ipairs(entry[faction]) do
                            if not queued[itemID] and not Known(itemID) then
                                queued[itemID] = true
                                queue[#queue + 1] = itemID
                            end
                        end
                    end
                    src.bosses[index] = entry
                end
            end
            db.sources[key] = src
        end
    end
    return true
end

---------------------------------------------------------------------------
-- Phase 2: ID ranges
---------------------------------------------------------------------------

-- The next ID in the ranges worth asking about, and whether it's only a
-- probe (unknown to the client: asked once). nil when the ranges are done.
local function NextFromRanges()
    local st = db.state
    st.range = st.range or 1
    local scanned = 0
    while scanned < SCAN_PER_TICK do
        local r = D.HARVEST_RANGES[st.range]
        if not r then return nil end
        st.cursor = math.max(st.cursor or r[1], r[1])
        if st.cursor > r[2] then
            st.range, st.cursor = st.range + 1, nil
        else
            local itemID = st.cursor
            st.cursor = itemID + 1
            scanned = scanned + 1
            if not Known(itemID) and not waiting[itemID] then
                local _, _, _, equipLoc = GetItemInfoInstant(itemID)
                if equipLoc and D.EQUIP_GROUP[equipLoc] then return itemID, false end
                if not equipLoc and r.probe then return itemID, true end
            end
        end
    end
    return false -- nothing found this tick; carry on next tick
end

---------------------------------------------------------------------------
-- Asking and saving
---------------------------------------------------------------------------

local function Ask(itemID, probe)
    local w = waiting[itemID] or { tries = 0, probe = probe }
    w.tries, w.at = w.tries + 1, GetTime()
    waiting[itemID] = w
    db.state.inflight[itemID] = true
    if RequestLoadItemDataByID and w.tries % 2 == 1 then
        RequestLoadItemDataByID(itemID)
    else
        GetItemInfo(itemID)
    end
end

local function Done(itemID)
    waiting[itemID] = nil
    db.state.inflight[itemID] = nil
end

-- Saves the item if the game has all of it (details and tooltip). Returns
-- true when the item is finished with.
local function TrySave(itemID)
    local name, _, quality, itemLevel, reqLevel, _, subType, _, equipLoc, icon = GetItemInfo(itemID)
    if not name then return false end
    if ns:IsEncryptedText(name) then
        db.encrypted[itemID] = true
        return true
    end
    if not D.EQUIP_GROUP[equipLoc or ""] then
        db.skip[itemID] = true
        return true
    end
    -- The tooltip must be filled in too ("Retrieving item information" until then).
    local lines = ns:TooltipLines(itemID)
    if not lines or not lines[1] or lines[1][1] ~= name then return false end
    local _, _, _, _, _, classID, subClassID = GetItemInfoInstant(itemID)
    local facts = ns.Usability:Facts(itemID) or { effects = {} }
    local stats = {}
    for stat, amount in pairs(ns.Scoring:ItemStats(itemID) or {}) do stats[stat] = amount end
    db.items[itemID] = {
        name = name, quality = quality, itemLevel = itemLevel, reqLevel = reqLevel,
        equipLoc = equipLoc, classID = classID, subClassID = subClassID, subType = subType,
        icon = icon, stats = stats, classes = facts.classes, effects = facts.effects,
    }
    return true
end

local function Stop(reason)
    if ticker then ticker:Cancel() ticker = nil end
    db.state.running = nil
    if reason then ns:Print("Harvest " .. reason) end
end

local function Tick()
    if InCombatLockdown() then return end
    local now, sent = GetTime(), 0
    for itemID, w in pairs(waiting) do
        if TrySave(itemID) then
            Done(itemID)
        elseif now - w.at >= RETRY_AFTER then
            if w.tries >= (w.probe and 1 or MAX_TRIES) then
                -- Probes that never answer are simply not items.
                if not w.probe then db.failed[itemID] = true end
                Done(itemID)
            elseif sent < D.HARVEST_RATE then
                Ask(itemID)
                sent = sent + 1
            end
        end
    end
    local exhausted = false
    while sent < D.HARVEST_RATE and Count(waiting) < D.HARVEST_RATE * RETRY_AFTER * 2 do
        local itemID, probe = table.remove(queue, 1), false
        if not itemID then
            itemID = next(db.state.extra)
            if itemID then db.state.extra[itemID] = nil end
        end
        if not itemID and db.state.phase ~= "done" then
            db.state.phase = "ranges"
            itemID, probe = NextFromRanges()
        end
        if itemID == nil then exhausted = true break end
        if itemID == false then break end
        if not Known(itemID) then
            Ask(itemID, probe)
            sent = sent + 1
        end
    end
    if exhausted and next(waiting) == nil then
        db.state.phase = "done"
        Stop("finished: " .. Count(db.items) .. " items saved. /reload, then run tools/Spyglass/build_items.py.")
    end
end

-- Loads an installed AtlasLoot's dungeon and raid module (it's load-on-demand), then calls
-- onReady. SpyGlass itself ships its loot (Data\Loot.lua); only the harvest reads AtlasLoot, and
-- without it the harvest goes straight on to the ID ranges.
local function LoadAtlas(onReady)
    if not (AtlasLoot and AtlasLoot.ItemDB) then onReady() return true end
    local IsLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    local Load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if IsLoaded(D.ATLAS_MODULE) then onReady() return true end
    local loader = AtlasLoot.Loader
    if loader and loader.LoadModule then
        local result = loader:LoadModule(D.ATLAS_MODULE, onReady)
        if IsLoaded(D.ATLAS_MODULE) or result == nil then return true end
        if result == "InCombat" then return false, "AtlasLoot's dungeon data will load after combat." end
    end
    if InCombatLockdown() then return false, "AtlasLoot's dungeon data can't load in combat." end
    Load(D.ATLAS_MODULE)
    onReady()
    return true
end

function H:Start()
    if ticker then ns:Print("Harvest is already running.") return end
    local ok, reason = LoadAtlas(function()
        if ticker then return end
        if db.state.phase ~= "ranges" and db.state.phase ~= "done" then
            db.state.phase = "atlas"
            WalkAtlas()
        end
        if db.state.phase == "done" and not next(db.state.extra) and not next(db.state.inflight) then
            ns:Print("Harvest already finished. /sg harvest reset to start over.")
            return
        end
        -- Asked about before the last /reload, but never answered: ask again.
        for itemID in pairs(db.state.inflight) do
            if not Known(itemID) then table.insert(queue, 1, itemID) end
        end
        wipe(db.state.inflight)
        db.state.running = true
        startedAt, savedAtStart = GetTime(), Count(db.items)
        ticker = C_Timer.NewTicker(1, Tick)
        ns:Print("Harvest running (" .. #queue .. " AtlasLoot items, " .. Count(db.state.extra)
            .. " plugin items queued" .. (db.state.phase ~= "done" and ", then the ID ranges" or "") .. "). /sg harvest status")
    end)
    if not ok then ns:Print("Harvest can't start: " .. tostring(reason)) end
end

function H:Status()
    local st = db.state
    local r = D.HARVEST_RANGES[st.range or 1]
    local where = st.phase == "ranges" and r
        and string.format("range %d/%d at %d (%d%%)", st.range, #D.HARVEST_RANGES, st.cursor or r[1],
            math.floor(((st.cursor or r[1]) - r[1]) / math.max(1, r[2] - r[1]) * 100))
        or (st.phase or "not started")
    ns:Print(string.format("Harvest %s - %s. Saved %d, not gear %d, failed %d, encrypted %d, waiting %d, queued %d.",
        ticker and "running" or "stopped", where, Count(db.items), Count(db.skip), Count(db.failed),
        Count(db.encrypted), Count(waiting), #queue + Count(db.state.extra)))
    if ticker and startedAt then
        local mins = (GetTime() - startedAt) / 60
        print(string.format("  %.1f min this session, %d items saved (%.0f/min)", mins,
            Count(db.items) - savedAtStart, (Count(db.items) - savedAtStart) / math.max(mins, 0.1)))
    end
end

-- Adds items to the harvest (plugins call this through SpyGlass:HarvestItems)
-- and starts it if it isn't running. Returns how many were new.
function H:Enqueue(ids)
    if not db then Init() end
    local added = 0
    for _, itemID in ipairs(ids) do
        if type(itemID) == "number" and not Known(itemID) and not waiting[itemID] and not db.state.extra[itemID] then
            db.state.extra[itemID] = true
            added = added + 1
        end
    end
    if added > 0 and not ticker then self:Start() end
    return added
end

H.commands = {} -- [word] = fn(rest): /sg harvest <word> ... (plugins)

function H:Command(arg, rest)
    if arg and self.commands[arg] then
        self.commands[arg](rest or "")
    elseif arg == "start" then
        self:Start()
    elseif arg == "stop" then
        Stop("stopped. /sg harvest start carries on where it left off.")
    elseif arg == "reset" then
        Stop()
        wipe(queue)
        wipe(waiting)
        SpyGlassDevDB = nil
        Init()
        ns:Print("Harvest data cleared.")
    elseif arg == "retry" then
        -- Give the ones that never answered another go (Start queues inflight first).
        for itemID in pairs(db.failed) do db.state.inflight[itemID] = true end
        wipe(db.failed)
        if db.state.phase == "done" then db.state.phase = "ranges" end
        ns:Print("Failed items requeued; /sg harvest start to try them again.")
    else
        self:Status()
        print("  /sg harvest start | stop | status | retry | reset")
        for word in pairs(self.commands) do print("  /sg harvest " .. word .. " ...") end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    Init()
    ns:Print("|cffff8040Developer mode is on|r (D.DEV_MODE in Data.lua). /sg harvest")
    -- Running when the UI was last reloaded: carry on.
    if db.state.running then C_Timer.After(5, function() H:Start() end) end
end)
