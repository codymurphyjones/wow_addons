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
-- nearest of its points on your continent, so it doesn't jump between vendors as you walk.
local T = {}
ns.Targets = T

local DEFAULT_ARRIVE = 15
local entries = {}     -- owner -> entry
local questie          -- Questie's entry, or nil
local callbacks = {}   -- owner -> fn(event, entry)
local manager          -- { owner, name, restore = fn }: the addon that owns the arrow, or nil
local request          -- the request entry, or nil (see the top of this file)
local REQUEST_ARRIVE = 10
local lastKey

T.current, T.point = nil, nil -- the resolved entry and the point the arrow aims at

local function Fire(event, entry)
    for owner, fn in pairs(callbacks) do
        local ok, err = pcall(fn, event, entry)
        if not ok then geterrorhandler()(("Waypoint callback from %s: %s"):format(owner, tostring(err))) end
    end
end

function T:RegisterCallback(owner, fn) callbacks[owner] = fn end
function T:UnregisterCallback(owner) callbacks[owner] = nil end

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

-- byUser: you stopped it (from the arrow), so its addon hears "cleared".
function T:ClearEntry(owner, byUser)
    local e = entries[owner]
    if not e then return end
    entries[owner] = nil
    ns.char.entries[owner] = nil
    if byUser then Fire("cleared", e) end
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
    if byUser then Fire("cleared", e) end
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
        manager = { owner = owner, name = m.name or owner, restore = m.restore, expected = m.expected, yield = m.yield }
    end
    ns:Changed()
end

function T:GetManager() return manager end

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

-- The owner takes the arrow back (the restore button): it sets its target up again.
function T:Restore()
    if not manager then return end
    if manager.restore then
        local ok, err = pcall(manager.restore)
        if not ok then geterrorhandler()(("Waypoint restore from %s: %s"):format(manager.owner, tostring(err))) end
    end
    ns:Changed()
end

-- The entry the arrow follows.
function T:Resolve()
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
    if e.request then
        ns:Print(("Arrived at |cffffffff%s|r."):format(p.label or e.title or "your destination"))
        if e.onArrive then pcall(e.onArrive, e) end
        Fire("arrived", e)
        T:ClearRequest(false)
    elseif e.ordered then
        ns.Chain:Reached(p)
    elseif #e.points > 1 then
        e.visited[PointKey(p)] = true
    elseif not e.arrived then
        e.arrived = true
        if e.onArrive then pcall(e.onArrive, e) end
        Fire("arrived", e)
    end
end

function T:Tick()
    if not ns.db then return end
    local e = self:Resolve()
    local continent, n, w = ns.Nav:Player()
    local p = e and Pick(e, continent, n, w)
    local key = e and (e.owner .. ":" .. tostring(e.key or e.title or ""))
    self.current, self.point = e, p
    if key ~= lastKey then
        lastKey = key
        if e and p and e.owner ~= "path" then Announce(e, p) end
        Fire("changed", e)
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
    if e.request then
        ns:Print(("Stopped navigating to %s."):format(e.title or "your request"))
        self:ClearRequest(true)
    elseif e.owner == "path" then
        if clear then ns.Chain:Clear() elseif self.point then ns.Chain:Reached(self.point, true) end
    elseif e.owner == "Questie" then
        ns.Questie:Skip()
    elseif manager and e.owner == manager.owner then
        -- The owner's target isn't stopped from here: that's what pausing it is for.
        ns:Print(("%s owns the arrow. Pause it there to take the arrow back."):format(manager.name))
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

-- "/way" with nothing after it.
function T:Describe()
    local e, p = self.current, self.point
    if not (e and p) then
        return "Not pointing at anything. Ctrl+click the world map to add a waypoint."
    end
    local from = e.request and "your request (Navigate to)"
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
