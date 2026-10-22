local _, ns = ...

-- What the arrow points at. Three kinds of target:
--   * entries other addons set through the API (one per addon, saved without their functions so a
--     plugin can find its own again after a reload and set it back up);
--   * the waypoint path (Chain.lua), shared with your group;
--   * your Questie quests (Questie.lua), only when there's nothing else.
-- An addon can own the arrow (SetManager: Field Guide while it isn't paused): its entry wins over
-- every other addon's, and only your waypoint path goes above it. Otherwise the newest entry or
-- path wins. An entry is { owner, key, title, subtitle, points = { { mapID, x, y,
-- label } }, arrive = yards, onClick, onArrive, ordered, t }. With several points the arrow leads to
-- the nearest one you haven't reached yet, and moves on (quietly) as you reach them.
--
-- A request (SetRequest: "Navigate to" a vendor, Quartermaster's vendor reagents) goes above all of
-- that: it's always the next point, whatever the arrow followed before, and when you get there (or
-- open that vendor) it clears and the arrow goes back to what it was following. It holds the
-- nearest of its points on your continent, so it doesn't jump between vendors as you walk. An
-- ordered request (ordered = true) is stops to make in turn instead: getting to one moves the arrow
-- on to the next, and it clears after the last.
--
-- Your body goes above even a request: while you're a ghost the arrow leads back to it, planned
-- like any target (on foot: a ghost can't take a flight or a boat). Once you're alive again it
-- goes back to what it was following. Right-click the arrow to stop it until you next die.
local T = {}
local C = ns.Compat
ns.Targets = T

local DEFAULT_ARRIVE = 15
local entries = {}     -- owner -> entry
local questie          -- Questie's entry, or nil
local manager          -- { owner, name, restore = fn, pause = fn }: the addon that owns the arrow, or nil
local request          -- the request entry, or nil (see the top of this file)
local REQUEST_ARRIVE = 10
local corpse           -- the entry for your body while you're a ghost, or nil
local corpseSkipped    -- you stopped it from the arrow: until you're alive again
local nextCorpseLook = 0
local CORPSE_ARRIVE = 20 -- yards: close enough to resurrect (the game allows a little more)
local CORPSE_LOOK = 1    -- seconds between looks for where your body is
local lastKey

T.current, T.point = nil, nil -- the resolved entry and the point the arrow aims at

-- Other addons' callbacks (Waypoint:RegisterCallback, the shared API.lua): fn(event, entry).
local _, Fire = ns.NewAPI("Waypoint", 2)

local function PointKey(p)
    return ("%s:%.4f:%.4f"):format(p.mapID or 0, p.x or 0, p.y or 0)
end

-- The saved copy of an entry: everything but functions and caches.
local function Saved(e)
    local out = {}
    for k, v in pairs(e) do
        if type(v) ~= "function" and k ~= "visited" and k ~= "points" and k ~= "held" then out[k] = v end
    end
    out.points = {}
    for i, p in ipairs(e.points) do out.points[i] = { mapID = p.mapID, x = p.x, y = p.y, label = p.label, npc = p.npc } end
    return out
end

-- Normalizes what an addon passed: mapID (or uiMapID), x, y, or points.
local function Normalize(owner, wp)
    local e = {}
    for k, v in pairs(wp) do e[k] = v end
    e.owner = owner
    local points = {}
    for _, p in ipairs(wp.points or {}) do
        local mapID = p.mapID or p.uiMapID or p[1]
        local x, y = p.x or p[2], p.y or p[3]
        if mapID and x and y then points[#points + 1] = { mapID = mapID, x = x, y = y, label = p.label, npc = p.npc } end
    end
    local mapID = wp.mapID or wp.uiMapID
    if #points == 0 and mapID and wp.x and wp.y then points[1] = { mapID = mapID, x = wp.x, y = wp.y } end
    e.points = points
    e.visited = {}
    return e
end

-- An addon's target. Setting one makes it the newest, so the arrow follows it.
function T:SetEntry(owner, wp)
    if type(owner) ~= "string" or type(wp) ~= "table" then return false end
    local e = Normalize(owner, wp)
    if #e.points == 0 then return false end
    e.t = ns:NextSeq()
    entries[owner] = e
    ns.char.entries[owner] = Saved(e)
    ns:Changed()
    return true
end

-- byUser: you stopped it (from the arrow), so its addon hears "CLEARED".
function T:ClearEntry(owner, byUser)
    local e = entries[owner]
    if not e then return end
    entries[owner] = nil
    ns.char.entries[owner] = nil
    if byUser then Fire("CLEARED", e) end
    ns:Changed()
end

function T:GetEntry(owner) return entries[owner] end

-- A request: the next point, above everything else, until you get there. wp as for SetEntry; a
-- point may carry npc = the NPC standing there, so opening its window counts as arriving.
function T:SetRequest(owner, wp)
    if type(wp) ~= "table" then return false end
    local e = Normalize(owner or "request", wp)
    if #e.points == 0 then return false end
    e.request, e.color = true, "request"
    e.arrive = wp.arrive or REQUEST_ARRIVE
    e.key = e.key or ("request:" .. (e.title or ""))
    if e.ordered and #e.points > 1 then
        e.stop, e.stops = 1, #e.points
        e.subtitle = ("%s (stop 1 of %d)"):format(e.points[1].label or "Stop", e.stops)
    end
    e.t = ns:NextSeq()
    request = e
    ns.char.request = Saved(e)
    ns:Changed()
    return true
end

-- byUser: you stopped it (from the arrow or the menu); else you got there.
function T:ClearRequest(byUser)
    local e = request
    if not e then return end
    request = nil
    ns.char.request = nil
    if byUser then Fire("CLEARED", e) end
    ns:Changed()
end

function T:GetRequest() return request end

-- Questie.lua's pick, or nil. Keeps what you reached when it's the same objective again.
function T:SetQuestie(e)
    if e and questie and questie.key == e.key then e.visited = questie.visited end
    if e then e.owner, e.visited = "Questie", e.visited or {} end
    questie = e
    ns:Changed()
end

function T:GetQuestie() return questie end

-- The addon that owns the arrow (nil: none). See the top of this file.
function T:SetManager(owner, m)
    if m == nil then
        if manager and manager.owner == owner then manager = nil end
    elseif type(m) == "table" then
        manager = { owner = owner, name = m.name or owner, restore = m.restore, expected = m.expected, yield = m.yield, pause = m.pause }
    end
    ns:Changed()
end

function T:GetManager() return manager end

-- Arrow menu: the owner lets go of the arrow (Field Guide pauses).
function T:PauseManager()
    if not (manager and manager.pause) then return end
    local ok, err = pcall(manager.pause)
    if not ok then geterrorhandler()(("Waypoint pause for %s: %s"):format(manager.owner, tostring(err))) end
    ns:Changed()
end

-- The owner steps aside for a quest you tracked yourself (yield(): Field Guide while its window is
-- closed).
local function Yields()
    if not (manager and manager.yield and questie and questie.byUser) then return false end
    local ok, yes = pcall(manager.yield)
    return ok and yes == true
end

-- Whether the arrow has drifted from what its owner expects: you (or something) changed it. The
-- owner's expected() gives the keys of where it should point now and the next few after it (up
-- to 5); its target carries the plan it was set with (plan = { keys }). Drifted when the arrow
-- follows something else (your path, a cleared target), the target isn't the expected one, or
-- its plan's next steps differ. Without expected(), the owner never counts as drifted.
local PLAN = 5
function T:Altered()
    if not (manager and manager.expected) then return false end
    local ok, exp = pcall(manager.expected)
    if not ok or type(exp) ~= "table" or not exp[1] then return false end -- nothing to point at
    if Yields() then return false end -- stepping aside on purpose, not changed by hand
    local mine = entries[manager.owner]
    if not mine or self.current ~= mine or mine.key ~= exp[1] then return true end
    if type(mine.plan) == "table" then
        for i = 1, PLAN do
            if mine.plan[i] ~= exp[i] then return true end
        end
    end
    return false
end

-- The owner takes the arrow back (the restore button): it sets its target up again. A request
-- ("Navigate to") would stay on top of it, so asking for the owner back ends the request.
function T:Restore()
    if not manager then return end
    if request then self:ClearRequest(true) end
    if manager.restore then
        local ok, err = pcall(manager.restore)
        if not ok then geterrorhandler()(("Waypoint restore from %s: %s"):format(manager.owner, tostring(err))) end
    end
    ns:Changed()
end

-- Where your body is: on the map you're in if it's there (the most exact), else on a map above
-- it (the corpse is in the next zone over). nil when the game won't say (in an instance).
local function CorpsePoint()
    if not (C_DeathInfo and C_DeathInfo.GetCorpseMapPosition and C_Map) then return nil end
    local mapID = C.Call(C_Map.GetBestMapForUnit, "player")
    for _ = 1, 4 do
        if not mapID or mapID == 0 then return nil end
        local pos = C.Call(C_DeathInfo.GetCorpseMapPosition, mapID)
        if pos and pos.GetXY then
            local x, y = pos:GetXY()
            x, y = C.Num(x), C.Num(y)
            if x and y and (x > 0 or y > 0) then return { mapID = mapID, x = x, y = y, label = "Your body" } end
        end
        local info = C.Call(C_Map.GetMapInfo, mapID)
        mapID = info and info.parentMapID
    end
end

-- Keeps the corpse entry up to date: there while you're a ghost and the game says where your body
-- is, gone once you're alive. Looked up again now and then (a zone map is more exact than the
-- continent's), but it stays the same entry so the arrow doesn't announce it again.
local function UpdateCorpse()
    if not C.Readable(C.Call(UnitIsGhost, "player")) then
        if corpse then
            corpse = nil
            ns:Changed()
        end
        corpseSkipped = nil
        return
    end
    if corpseSkipped then return end
    local now = GetTime()
    if now < nextCorpseLook then return end
    nextCorpseLook = now + CORPSE_LOOK
    local p = CorpsePoint()
    if not p then return end
    if not corpse then
        corpse = { owner = "corpse", key = "corpse", title = "Your body", corpse = true, color = "corpse",
            arrive = CORPSE_ARRIVE, points = { p }, visited = {}, t = 0 }
        ns:Changed()
    else
        local old = corpse.points[1]
        if old.mapID ~= p.mapID or math.abs(old.x - p.x) > 1e-4 or math.abs(old.y - p.y) > 1e-4 then
            corpse.points[1] = p
            ns:Changed()
        end
    end
    local info = C_Map and C.Call(C_Map.GetMapInfo, p.mapID)
    corpse.subtitle = info and C.Readable(info.name) or nil
end

function T:GetCorpse() return corpse end

-- The entry the arrow follows.
function T:Resolve()
    if corpse then return corpse end
    if request then return request end
    local path = ns.Chain and ns.Chain:Entry()
    if manager then
        if path then return path end
        if Yields() and ns.db and ns.db.quests then return questie end
        local mine = entries[manager.owner]
        if mine then return mine end
    end
    local best
    for _, e in pairs(entries) do
        if not best or (e.t or 0) > (best.t or 0) then best = e end
    end
    if path and (not best or path.t > (best.t or 0)) then best = path end
    if not best and ns.db and ns.db.quests then best = questie end
    return best
end

-- The point of an entry to aim at: the first for the path, else the nearest not yet reached.
local function Pick(e, continent, n, w)
    if e.ordered or #e.points == 1 then return e.points[1] end
    if e.request then
        -- The nearest on your continent, held until you change continent.
        local held = e.held
        if held and (not continent or ns.Nav:World(held) == continent) then return held end
        local best, bestD
        for _, p in ipairs(e.points) do
            local d = continent and ns.Nav:To(p, continent, n, w)
            if d and (not bestD or d < bestD) then best, bestD = p, d end
        end
        if best then e.held, e.subtitle = best, best.label or e.subtitle end
        return best or held or e.points[1]
    end
    local best, bestD
    for pass = 1, 2 do
        for _, p in ipairs(e.points) do
            if not e.visited[PointKey(p)] then
                local d = continent and ns.Nav:To(p, continent, n, w)
                if d and (not bestD or d < bestD) then best, bestD = p, d end
            end
        end
        if best or not next(e.visited) then break end
        wipe(e.visited) -- reached them all: start over
    end
    return best or e.points[1]
end

local function Announce(e, p)
    local text = e.title or "Waypoint"
    if e.subtitle and e.subtitle ~= "" then text = text .. " - " .. e.subtitle end
    ns:Print(("Now pointing at: |cffffffff%s|r (%s)"):format(text, ns.Nav:Describe(p)))
end

local function Arrive(e, p)
    if e.corpse then
        if not e.arrived then
            e.arrived = true
            ns:Print("You're back at your body: resurrect when you're ready.")
        end
    elseif e.request and e.ordered and #e.points > 1 then
        -- One of its stops: on to the next.
        for i, q in ipairs(e.points) do
            if q == p then table.remove(e.points, i) break end
        end
        e.stop = (e.stop or 1) + 1
        local nextP = e.points[1]
        e.subtitle = ("%s (stop %d of %d)"):format(nextP.label or "Stop", e.stop, e.stops or e.stop)
        ns:Print(("Arrived at |cffffffff%s|r. Next: |cffffffff%s|r (%s)."):format(p.label or "the stop",
            nextP.label or "the next stop", ns.Nav:Describe(nextP)))
        ns.char.request = Saved(e)
        Fire("ARRIVED", e)
        ns:Changed()
    elseif e.request then
        ns:Print(("Arrived at |cffffffff%s|r."):format(p.label or e.title or "your destination"))
        if e.onArrive then pcall(e.onArrive, e) end
        Fire("ARRIVED", e)
        T:ClearRequest(false)
    elseif e.ordered then
        ns.Chain:Reached(p)
    elseif #e.points > 1 then
        e.visited[PointKey(p)] = true
    elseif not e.arrived then
        e.arrived = true
        if e.onArrive then pcall(e.onArrive, e) end
        Fire("ARRIVED", e)
    end
end

function T:Tick()
    if not ns.db then return end
    UpdateCorpse()
    local e = self:Resolve()
    local continent, n, w = ns.Nav:Player()
    local p = e and Pick(e, continent, n, w)
    local key = e and (e.owner .. ":" .. tostring(e.key or e.title or ""))
    self.current, self.point = e, p
    if key ~= lastKey then
        lastKey = key
        if e and p and e.owner ~= "path" then Announce(e, p) end
        Fire("CHANGED", e)
    end
    if ns.Flight then ns.Flight:Update(p) end
    if not (e and p and continent) then return end
    local d = ns.Nav:To(p, continent, n, w)
    if d and d <= (e.arrive or DEFAULT_ARRIVE) then
        Arrive(e, p)
        if not e.request and (e.ordered or #e.points > 1) then self.point = Pick(e, continent, n, w) end
    elseif d and e.arrived and d > 2 * (e.arrive or DEFAULT_ARRIVE) then
        e.arrived = nil
    end
end

-- Arrow right-click: move on from what it points at. clear: drop the whole path or entry.
function T:Skip(clear)
    local e = self.current
    if not e then return end
    if e.corpse then
        ns:Print("Stopped leading you to your body. It comes back the next time you die.")
        corpseSkipped, corpse = true, nil
        ns:Changed()
    elseif e.request then
        ns:Print(("Stopped navigating to %s."):format(e.title or "your request"))
        self:ClearRequest(true)
    elseif e.owner == "path" then
        if clear then ns.Chain:Clear() elseif self.point then ns.Chain:Reached(self.point, true) end
    elseif e.owner == "Questie" then
        ns.Questie:Skip()
    elseif manager and e.owner == manager.owner then
        -- The owner's target isn't stopped from here: that's what pausing it is for.
        ns:Print(("%s owns the arrow. Pause it from the arrow's menu to take the arrow back."):format(manager.name))
    else
        ns:Print(("Stopped pointing at %s."):format(e.title or e.owner))
        self:ClearEntry(e.owner, true)
    end
end

-- The waypoints the arrow could follow, newest first (up to n): { { text, clear = fn } }. Addon
-- targets, and the points of your waypoint path (the last added first).
function T:History(n)
    local items = {}
    for owner, e in pairs(entries) do
        items[#items + 1] = { t = e.t or 0, entry = e, text = ("%s  |cff999999(%s)|r"):format(e.title or "Waypoint", owner),
            clear = function()
                ns:Print(("Stopped pointing at %s."):format(e.title or owner))
                T:ClearEntry(owner, true)
            end }
    end
    local path = ns.Chain and ns.Chain:Points() or {}
    local pathT = ns.char.chainT or 0
    for i = #path, 1, -1 do
        local p = path[i]
        items[#items + 1] = { t = pathT, order = i, text = ("Waypoint %d: %s"):format(i, p.title or ns.Nav:Describe(p)),
            clear = function() ns.Chain:Remove(p.id) end }
    end
    table.sort(items, function(a, b)
        if a.t ~= b.t then return a.t > b.t end
        return (a.order or 0) > (b.order or 0)
    end)
    local out = {}
    for i = 1, math.min(n or 5, #items) do out[i] = items[i] end
    return out
end

-- What comes after the current target, as a hint: the target's own next (an addon passes
-- next = "Pick up: Allegiance to the Old Gods"), the path's next waypoint, or the next waypoint in
-- the history.
function T:NextText()
    local e = self.current
    if not e then return nil end
    if type(e.next) == "string" and e.next ~= "" then return e.next end
    if e.owner == "path" then
        local path = ns.Chain:Points()
        local p = path[2]
        return p and ("Waypoint 2: " .. (p.title or ns.Nav:Describe(p))) or nil
    end
    for _, item in ipairs(self:History(5)) do
        if item.entry ~= e then return item.text end
    end
end

-- Where the arrow will most likely point after the current target, so its way can be worked out
-- ahead of time (Route.lua): the path's next waypoint, an addon's upcoming = { mapID, x, y } (API),
-- or the target's nearest other point not reached yet. nil when nothing's known.
function T:Upcoming()
    local e, cur = self.current, self.point
    if not (e and cur) then return nil end
    if e.owner == "path" then return ns.Chain:Points()[2] end
    local up = e.upcoming
    if type(up) == "table" then
        local mapID = up.mapID or up.uiMapID or up[1]
        local x, y = up.x or up[2], up.y or up[3]
        if mapID and x and y then return { mapID = mapID, x = x, y = y } end
    end
    if #e.points > 1 and not e.request then
        local c, n, w = ns.Nav:World(cur)
        local best, bestD
        for _, p in ipairs(e.points) do
            if p ~= cur and not e.visited[PointKey(p)] then
                local d = c and ns.Nav:To(p, c, n, w)
                if d and (not bestD or d < bestD) then best, bestD = p, d end
            end
        end
        return best
    end
end

-- "/way" with nothing after it.
function T:Describe()
    local e, p = self.current, self.point
    if not (e and p) then
        return "Not pointing at anything. Ctrl+click the world map to add a waypoint."
    end
    local from = e.corpse and "your death (you're a ghost)"
        or e.request and "your request (Navigate to)"
        or e.owner == "path" and "your group's waypoint path"
        or e.owner == "Questie" and "your Questie quests" or e.owner
    local d = ns.Nav:To(p)
    return ("Pointing at |cffffffff%s|r (%s%s), from %s."):format(e.title or "Waypoint", ns.Nav:Describe(p),
        d and (", " .. ns.Nav.Distance(d)) or "", from)
end

-- Opening the window of the vendor a request leads to counts as getting there.
ns:On("MERCHANT_SHOW", function()
    local e = request
    if not e then return end
    local ok, guid = pcall(UnitGUID, "npc")
    guid = ok and ns.Compat.Readable(guid)
    local id = type(guid) == "string" and tonumber((select(6, strsplit("-", guid))))
    if not id then return end
    for _, p in ipairs(e.points) do
        if p.npc == id then return Arrive(e, p) end
    end
end)

-- Saved addon entries come back without their functions; their addon sets them up again.
ns:OnLoad(function()
    local saved = ns.char.request
    if type(saved) == "table" and type(saved.points) == "table" and #saved.points > 0 then
        saved.visited = {}
        request = saved
    else
        ns.char.request = nil
    end
    for owner, saved in pairs(ns.char.entries) do
        if type(saved) == "table" and type(saved.points) == "table" and #saved.points > 0 then
            saved.owner, saved.visited = owner, {}
            entries[owner] = saved
        else
            ns.char.entries[owner] = nil
        end
    end
end)

local acc = 0
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.1 then return end
    acc = 0
    T:Tick()
end)
