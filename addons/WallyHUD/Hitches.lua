local _, ns = ...

-- Hitch watch: a frame that takes HITCH_MS or longer says in chat what took the time, from the
-- game's own addon profiler (C_AddOnProfiler): each addon's time in that frame (its LastTime, read
-- on the frame right after), the addons' total, and how Lua's memory changed (a big drop is a
-- garbage collection, which addons' garbage causes but no addon is charged for). When the addons
-- took little of it, the game itself did (loading, textures, the world): it says that too.
-- And the game's events that fired in that frame (QUEST_TURNED_IN, TRANSMOG_COLLECTION_SOURCE_ADDED...):
-- what set it off, when the time isn't any addon's.
--   /whud hitches        on and off (db.hitchWatch, on by default)
--   /whud hitches list   the last ones again
local H = {}
ns.Hitches = H

local HITCH_MS = 250   -- a frame this long or longer is a hitch
local QUIET = 2        -- seconds between lines (a burst of slow frames is one line)
local KEEP = 20        -- hitches kept for /whud hitches list
local SHOWN = 4        -- addons named per line

local log = {}
local lastSaid = 0
local loading = true   -- loading screens are long frames by nature: not hitches
local lastMem

-- Events since the last frame, and in the frame before (the slow work can be in either): name -> count,
-- in the order they first fired. Constant chatter (power, the mouse, chat) is left out.
local NOISE = { UNIT_POWER_FREQUENT = true, UNIT_POWER_UPDATE = true, CURSOR_CHANGED = true, UPDATE_MOUSEOVER_UNIT = true,
    MODIFIER_STATE_CHANGED = true, UNIT_AURA = true, UNIT_HEALTH = true, UNIT_MAXHEALTH = true, NAME_PLATE_UNIT_ADDED = true,
    NAME_PLATE_UNIT_REMOVED = true, UNIT_THREAT_LIST_UPDATE = true, UNIT_FLAGS = true, SPELL_UPDATE_COOLDOWN = true,
    ACTIONBAR_UPDATE_COOLDOWN = true, ACTIONBAR_UPDATE_USABLE = true, SPELL_UPDATE_USABLE = true, UNIT_TARGET = true,
    PLAYER_STARTED_MOVING = true, PLAYER_STOPPED_MOVING = true }
local seen, seenOrder, before, beforeOrder = {}, {}, {}, {}
local events = CreateFrame("Frame")
events:RegisterAllEvents()
events:SetScript("OnEvent", function(_, e)
    if NOISE[e] or e:find("^CHAT_MSG_") then return end
    local n = seen[e]
    if not n then seenOrder[#seenOrder + 1] = e end
    seen[e] = (n or 0) + 1
end)

local function Events()
    local out, listed = {}, {}
    for _, list in ipairs({ { beforeOrder, before }, { seenOrder, seen } }) do
        for _, e in ipairs(list[1]) do
            if not listed[e] and #out < 6 then
                listed[e] = true
                local n = (before[e] or 0) + (seen[e] or 0)
                out[#out + 1] = n > 1 and ("%s x%d"):format(e, n) or e
            end
        end
    end
    return #out > 0 and table.concat(out, ", ") or nil
end

local function Profiler()
    local P = C_AddOnProfiler
    if not (P and P.GetTopKAddOnsForMetric and Enum and Enum.AddOnProfilerMetric) then return nil end
    if P.IsEnabled and not P.IsEnabled() then return nil end
    return P
end

local function Ms(v) return v and math.floor(v + 0.5) or 0 end

local function Describe(ms, memDelta)
    local P = Profiler()
    local parts, total = {}, nil
    if P then
        local metric = Enum.AddOnProfilerMetric.LastTime
        local ok, top = pcall(P.GetTopKAddOnsForMetric, metric, SHOWN)
        if ok and type(top) == "table" then
            for _, r in ipairs(top) do
                if r.metricValue and r.metricValue >= 1 then
                    parts[#parts + 1] = ("%s %d"):format(r.addOnName or "?", Ms(r.metricValue))
                end
            end
        end
        local ok2, all = pcall(P.GetOverallMetric, metric)
        if ok2 then total = all end
    end
    local line = ("|cffff8c33Hitch|r %d ms"):format(ms)
    if total then
        line = line .. (": addons %d ms"):format(Ms(total))
        if #parts > 0 then line = line .. " (" .. table.concat(parts, ", ") .. ")" end
        if total < ms * 0.3 then line = line .. ", the rest the game itself" end
    else
        line = line .. " (the game's addon profiler is off: no per-addon times)"
    end
    local fired = Events()
    if fired then line = line .. "; events: " .. fired end
    if memDelta and memDelta < -10240 then
        line = line .. (", Lua memory %d MB lower (a garbage collection)"):format(-memDelta / 1024)
    end
    if InCombatLockdown() then line = line .. " (in combat)" end
    return line
end

local watch = CreateFrame("Frame")
watch:SetScript("OnUpdate", function(_, elapsed)
    local mem = collectgarbage("count")
    local delta = lastMem and (mem - lastMem) or nil
    lastMem = mem
    local ms = elapsed * 1000
    local line
    if not loading and ns.db and ns.db.hitchWatch ~= false and ms >= HITCH_MS then line = Describe(ms, delta) end
    -- (This frame's events become the frame before's.)
    before, seen = seen, before
    beforeOrder, seenOrder = seenOrder, beforeOrder
    wipe(seen); wipe(seenOrder)
    if not line then return end
    table.insert(log, 1, date("%H:%M:%S ") .. line)
    if #log > KEEP then log[#log] = nil end
    local now = GetTime()
    if now - lastSaid >= QUIET then
        lastSaid = now
        print(line)
    end
end)

-- Loading screens: their long frames aren't hitches (from the screen until a moment after it).
ns:On("LOADING_SCREEN_ENABLED", function() loading = true end)
ns:On("LOADING_SCREEN_DISABLED", function() C_Timer.After(3, function() loading = false end) end)
ns:On("PLAYER_ENTERING_WORLD", function() loading = true; C_Timer.After(5, function() loading = false end) end)

function H:Toggle()
    ns.db.hitchWatch = ns.db.hitchWatch == false
    ns:Print(ns.db.hitchWatch and ("Hitch watch on: a frame of %d ms or longer says in chat what took the time."):format(HITCH_MS)
        or "Hitch watch off.")
end

function H:List()
    if #log == 0 then return ns:Print("No hitches since you logged in.") end
    for i = #log, 1, -1 do print(log[i]) end
end
