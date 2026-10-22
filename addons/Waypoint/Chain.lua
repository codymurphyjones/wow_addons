local _, ns = ...
local C = ns.Compat

-- The waypoint path: waypoints in order, shared with your group (Comm.lua). The arrow leads to the
-- first one; reaching it drops it from your copy only, so everyone walks the path at their own pace.
-- Your own adds, removes and wipes can be undone (10 deep): Ctrl+Z on the map, or /way undo.
--
-- The first waypoint is Blizzard's map pin (C_Map's user waypoint): Waypoint keeps the two the same
-- (SyncBlizzard), so the game's own pin, OpenMap and other map addons show the current waypoint. A
-- pin set anywhere else (OpenMap, a chat link, another addon) becomes the path's new first waypoint;
-- clearing Blizzard's pin finishes the first waypoint, and the next one takes its place. With no
-- path, a "navigate to" you clicked (a town, a dock, a dungeon in Field Guide: Targets' request) is
-- Blizzard's pin instead, and clearing the pin stops it.
-- Saved per character: chain = { { id, by, mapID, x, y, title } }, chainStarter, chainT, reached.
local Chain = {}
ns.Chain = Chain
local U = ns.Units

local UNDO_MAX = 10
local undo = {} -- { kind = "add", id } | { kind = "remove", point, after } | { kind = "wipe" | "replace", old, starter, id }

local entry = { owner = "path", key = "path", ordered = true, arrive = 15, visited = {} }
local FRONT = "^"   -- `after` for a waypoint that goes before all the others
Chain.FRONT = FRONT
local NEAR = 0.002  -- two points closer than this (on the same map) are the same waypoint

local function Points() return ns.char.chain end

local function IndexOf(id)
    for i, p in ipairs(Points()) do
        if p.id == id then return i end
    end
end

local function Sharing() return ns.db.share and IsInGroup and IsInGroup() end

local function Bump() ns.char.chainT = ns:NextSeq() end

local function NewID()
    ns.char.idCounter = (ns.char.idCounter or 0) + 1
    return C.Me() .. "#" .. ns.char.idCounter
end

local function Copy(p)
    return { id = p.id, by = p.by, mapID = p.mapID, x = p.x, y = p.y, title = p.title }
end

local function Near(p, mapID, x, y)
    return p.mapID == mapID and math.abs(p.x - x) < NEAR and math.abs(p.y - y) < NEAR
end

-- The waypoint of the path at a point, and its number.
local function InPath(mapID, x, y)
    for i, p in ipairs(Points()) do
        if Near(p, mapID, x, y) then return p, i end
    end
end

local function Record(action)
    undo[#undo + 1] = action
    if #undo > UNDO_MAX then table.remove(undo, 1) end
end

-- The arrow's entry for the path, or nil when it's empty.
function Chain:Entry()
    local points = Points()
    if #points == 0 then return nil end
    local first = points[1]
    entry.points = points
    entry.t = ns.char.chainT or 0
    entry.title = first.title or ("Waypoint" .. (#points > 1 and (" (1 of %d)"):format(#points) or ""))
    entry.subtitle = not U.Same(first.by, U.Me()) and ("by " .. C.Short(first.by)) or nil
    return entry
end

function Chain:Count() return #Points() end
function Chain:Points() return Points() end
function Chain:Starter() return ns.char.chainStarter end
function Chain:IsMine() return not ns.char.chainStarter or U.Same(ns.char.chainStarter, U.Me()) end

-- At login: names saved by earlier versions in the shape they have now. Yours (written as
-- "Given-ClassicBetaPvP" before) become your key ("Given Family"), other players' Units.KeyOf's.
-- Point IDs stay as they are: the group knows them by those.
local function NewKey(name)
    if type(name) ~= "string" then return name end
    for _, old in ipairs(U.OldCharKeys()) do
        if name == old then return U.CharKey() or name end
    end
    return U.KeyOf(name) or name
end

function Chain:MigrateNames()
    local char = ns.char
    if not (char and U.CharKey()) then return 0 end
    local moved = 0
    local function Fix(t, k)
        local new = NewKey(t[k])
        if new ~= t[k] then t[k], moved = new, moved + 1 end
    end
    Fix(char, "chainStarter")
    for _, p in ipairs(char.chain or {}) do Fix(p, "by") end
    return moved
end
ns:On("PLAYER_LOGIN", function() Chain:MigrateNames() end)

---------------------------------------------------------------------------
-- Changes to your copy (no undo, nothing sent)
---------------------------------------------------------------------------

-- Inserts p after the waypoint `after` (or at the end; FRONT: before all of them). False when
-- it's already there or reached.
function Chain:Insert(p, after, starter)
    local list = Points()
    if IndexOf(p.id) or ns.char.reached[p.id] then return false end
    if #list == 0 and not ns.char.chainStarter then ns.char.chainStarter = starter or p.by end
    local i = after == FRONT and 0 or (after and IndexOf(after))
    table.insert(list, i and i + 1 or #list + 1, p)
    Bump()
    ns:Changed()
    return true
end

-- Removes a waypoint: the point, the id of the one before it, and its number in the path.
function Chain:Delete(id)
    local i = IndexOf(id)
    if not i then return nil end
    local list = Points()
    local after = i > 1 and list[i - 1].id or nil
    local p = table.remove(list, i)
    if #list == 0 then ns.char.chainStarter = nil end
    ns:Changed()
    return p, after, i
end

-- Empties the path: the old points and who started it.
function Chain:WipeLocal()
    local old, starter = ns.char.chain, ns.char.chainStarter
    ns.char.chain, ns.char.chainStarter = {}, nil
    wipe(ns.char.reached)
    ns:Changed()
    return old, starter
end

---------------------------------------------------------------------------
-- Your actions (undoable, sent to your group)
---------------------------------------------------------------------------

-- Adds a waypoint at the end. newPath: wipe the path first and start your own.
function Chain:Add(mapID, x, y, title, newPath)
    if not newPath then
        local same, i = InPath(mapID, x, y)
        if same then
            ns:Print(("Waypoint %d is already there."):format(i))
            return
        end
    end
    local old, oldStarter
    if newPath and #Points() > 0 then
        old, oldStarter = self:WipeLocal()
        ns.Comm:Send("C")
    end
    local list = Points()
    local after = list[#list] and list[#list].id
    local p = { id = NewID(), by = C.Me(), mapID = mapID, x = x, y = y, title = title }
    self:Insert(p, after, #list == 0 and C.Me() or nil)
    ns.Comm:SendAdd(p, after)
    Record(old and { kind = "replace", old = old, starter = oldStarter, id = p.id } or { kind = "add", id = p.id })
    if old then
        ns:Print(("Started a new path at %s. Ctrl+Z on the map brings the old one back."):format(ns.Nav:Describe(p)))
    else
        ns:Print(("Added waypoint %d: %s."):format(#Points(), ns.Nav:Describe(p)))
    end
end

-- A waypoint before all the others: the new current one (Blizzard's pin set somewhere else).
function Chain:AddFirst(mapID, x, y, title)
    local p = { id = NewID(), by = C.Me(), mapID = mapID, x = x, y = y, title = title }
    self:Insert(p, FRONT, C.Me())
    ns.Comm:SendAdd(p, FRONT)
    Record({ kind = "add", id = p.id })
    local n = #Points()
    ns:Print(("Following the map pin at %s%s."):format(ns.Nav:Describe(p),
        n > 1 and (" first (then the rest of your path: %d more)"):format(n - 1) or ""))
end

-- Follow this point now (another map's "follow this pin"): it's the first waypoint, or already is.
function Chain:Follow(mapID, x, y, title)
    local p, i = InPath(mapID, x, y)
    if i == 1 then return end
    if p then self:Remove(p.id) end
    self:AddFirst(mapID, x, y, title)
end

-- Removes the n-th waypoint of the path. False when there isn't one.
function Chain:RemoveAt(n)
    local p = Points()[n]
    if not p then return false end
    self:Remove(p.id)
    return true
end

function Chain:Remove(id)
    local p, after, i = self:Delete(id)
    if not p then return end
    ns.Comm:Send("R|" .. id)
    Record({ kind = "remove", point = Copy(p), after = after })
    ns:Print(("Removed waypoint %d (%s)."):format(i, ns.Nav:Describe(p)))
end

function Chain:Clear()
    if #Points() == 0 then
        ns:Print("There's no waypoint path to clear.")
        return
    end
    local old, starter = self:WipeLocal()
    ns.Comm:Send("C")
    Record({ kind = "wipe", old = old, starter = starter })
    ns:Print("Cleared the waypoint path. Ctrl+Z on the map (or /way undo) brings it back.")
end

-- Puts a whole path back: yours, and your group's.
local function Restore(old, starter)
    Chain:WipeLocal()
    ns.Comm:Send("C")
    ns.char.chainStarter = starter
    local prev
    for _, p in ipairs(old) do
        local copy = Copy(p)
        Chain:Insert(copy, prev, starter)
        ns.Comm:SendAdd(copy, prev, true)
        prev = copy.id
    end
end

function Chain:Undo()
    local a = table.remove(undo)
    if not a then
        ns:Print("Nothing to undo.")
        return
    end
    if a.kind == "add" then
        local p = self:Delete(a.id)
        if p then ns.Comm:Send("R|" .. a.id) end
        ns:Print("Undid adding " .. (p and ns.Nav:Describe(p) or "a waypoint") .. ".")
    elseif a.kind == "remove" then
        ns.char.reached[a.point.id] = nil
        self:Insert(a.point, a.after)
        ns.Comm:SendAdd(a.point, a.after)
        ns:Print("Put back " .. ns.Nav:Describe(a.point) .. ".")
    else
        Restore(a.old, a.starter)
        ns:Print(("Brought back the waypoint path (%d waypoint%s)."):format(#a.old, #a.old == 1 and "" or "s"))
    end
end

-- You reached the first waypoint (or skipped it from the arrow). Only your copy changes.
function Chain:Reached(p, skipped)
    if not self:Delete(p.id) then return end
    ns.char.reached[p.id] = true
    local nxt = Points()[1]
    if nxt then
        ns:Print(("%s %s. Next: %s (%d left)."):format(skipped and "Skipped" or "Reached", ns.Nav:Describe(p),
            ns.Nav:Describe(nxt), #Points()))
    else
        wipe(ns.char.reached)
        ns:Print(skipped and "Skipped the last waypoint." or "Reached the last waypoint.")
    end
end

---------------------------------------------------------------------------
-- From the map (double-click) and /way x y
---------------------------------------------------------------------------

StaticPopupDialogs["WAYPOINT_ADD"] = {
    text = "%s", button1 = YES or "Yes", button2 = NO or "No",
    OnAccept = function(_, d) Chain:Add(d.mapID, d.x, d.y, d.title) end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}

StaticPopupDialogs["WAYPOINT_APPEND"] = {
    text = "%s", button1 = "Append", button2 = CANCEL or "Cancel", button3 = "New path",
    OnAccept = function(_, d) Chain:Add(d.mapID, d.x, d.y, d.title) end,
    OnAlt = function(_, d) Chain:Add(d.mapID, d.x, d.y, d.title, true) end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}

-- Asks first: Append or New path on someone else's path, otherwise a plain "Add?" (unless
-- confirming is off, or noConfirm).
function Chain:Request(mapID, x, y, title, noConfirm)
    local d = { mapID = mapID, x = x, y = y, title = title }
    local where = ns.Nav:Describe(d)
    local n = #Points()
    if n > 0 and not self:IsMine() then
        StaticPopup_Show("WAYPOINT_APPEND", ("%s's path has %d waypoint%s.\n\nAdd %s to the end of it, or wipe it and start a new path?")
            :format(C.Short(ns.char.chainStarter), n, n == 1 and "" or "s", where), nil, d)
    elseif noConfirm or not ns.db.confirm then
        self:Add(mapID, x, y, title)
    else
        local text = n == 0 and ("Start a waypoint path at %s?"):format(where)
            or ("Add waypoint %d at %s?"):format(n + 1, where)
        if Sharing() then text = text .. "\n\nYour group will see it." end
        StaticPopup_Show("WAYPOINT_ADD", text, nil, d)
    end
end

-- Ctrl+right-click: removes the waypoint nearest (cx, cy) on the map you're looking at (or stops
-- the "navigate to" when its point is nearer).
function Chain:RemoveNearest(mapID, cx, cy, aspect)
    aspect = aspect or 1
    local best, bestD
    local r = ns.Targets and ns.Targets:GetRequest()
    local rp = r and (r.held or r.points[1])
    if rp then
        local px, py = ns.Nav:OnCanvas(rp.mapID, rp.x, rp.y, mapID)
        if px then
            local dx, dy = (px - cx) * aspect, py - cy
            best, bestD = rp, dx * dx + dy * dy
        end
    end
    for _, p in ipairs(Points()) do
        local px, py = ns.Nav:OnCanvas(p.mapID, p.x, p.y, mapID)
        if px then
            local dx, dy = (px - cx) * aspect, py - cy
            local d = dx * dx + dy * dy
            if not bestD or d < bestD then best, bestD = p, d end
        end
    end
    if best and best == rp then
        ns:Print(("Stopped navigating to %s."):format(r.title or "your destination"))
        ns.Targets:ClearRequest(true)
    elseif best then
        self:Remove(best.id)
    else
        ns:Print("No waypoint on this map to remove.")
    end
end

---------------------------------------------------------------------------
-- Blizzard's map pin: the first waypoint
---------------------------------------------------------------------------

local syncing   -- true while Waypoint sets or clears Blizzard's pin itself
local mirrored  -- the waypoint Blizzard's pin was last set to (nil: none of ours)
local ready     -- the game's map data is there (after the first PLAYER_ENTERING_WORLD)

-- Blizzard's pin now: mapID, x, y, or nil.
local function BlizzardPin()
    if not (C_Map and C_Map.HasUserWaypoint and C_Map.GetUserWaypoint) then return end
    if not C.Readable(C.Call(C_Map.HasUserWaypoint)) then return end
    local point = C.Call(C_Map.GetUserWaypoint)
    local pos = point and C.Readable(point.position)
    if not (pos and pos.GetXY) then return end
    local x, y = C.Call(pos.GetXY, pos)
    local mapID = C.Num(point.uiMapID)
    x, y = C.Num(x), C.Num(y)
    if mapID and x and y then return mapID, x, y end
end

local function Quietly(fn, ...)
    syncing = true
    local ok = pcall(fn, ...)
    syncing = false
    return ok
end

-- The point Blizzard's pin should show: the path's first waypoint, else the request's ("navigate
-- to") point; and the request when it's that.
local function Manual()
    local first = Points()[1]
    if first then return first end
    local T = ns.Targets
    local r = T and T:GetRequest()
    if not r then return end
    local p = (T.current == r and T.point) or r.held or r.points[1]
    return p, r
end

-- The request's point at mapID, x, y, if any.
local function InRequest(mapID, x, y)
    local r = ns.Targets and ns.Targets:GetRequest()
    for _, p in ipairs(r and r.points or {}) do
        if Near(p, mapID, x, y) then return p, r end
    end
end

-- Points Blizzard's pin at the path's first waypoint, or the request's point (or clears ours when
-- there's neither).
function Chain:SyncBlizzard()
    if not (ready and ns.db and C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then return end
    local first = Manual()
    local mapID, x, y = BlizzardPin()
    if not first then
        if mirrored and mapID and Near(mirrored, mapID, x, y) and C_Map.ClearUserWaypoint then Quietly(C_Map.ClearUserWaypoint) end
        mirrored = nil
        return
    end
    if mapID and Near(first, mapID, x, y) then
        mirrored = first
        return
    end
    local allowed = not C_Map.CanSetUserWaypointOnMap or C.Call(C_Map.CanSetUserWaypointOnMap, first.mapID)
    if not allowed then
        -- This map won't take Blizzard's pin: Waypoint draws the first waypoint itself (MapPins.lua).
        if mirrored and mapID and Near(mirrored, mapID, x, y) and C_Map.ClearUserWaypoint then Quietly(C_Map.ClearUserWaypoint) end
        mirrored = nil
        return
    end
    if Quietly(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(first.mapID, first.x, first.y)) then
        mirrored = first
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then Quietly(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
    else
        mirrored = nil
    end
end

-- Whether Blizzard's pin is one of Waypoint's (a path waypoint or the request's point): then
-- MapPins.lua hides its map icon and draws its own, so every pin on the map works the same.
function Chain:IsOurs()
    local mapID, x, y = BlizzardPin()
    if not mapID then return false end
    return (InPath(mapID, x, y) or InRequest(mapID, x, y)) and true or false
end

-- Whether Blizzard's pin shows this waypoint.
function Chain:IsMirrored(p)
    local mapID, x, y = BlizzardPin()
    return mapID and Near(p, mapID, x, y) or false
end

-- Blizzard's pin changed: set somewhere else (a new first waypoint), or cleared (the first is done).
function Chain:OnBlizzardPin()
    if syncing or not (ready and ns.db) then return end
    local mapID, x, y = BlizzardPin()
    if mapID then
        local _, i = InPath(mapID, x, y)
        if i or InRequest(mapID, x, y) then
            -- One of ours (OpenMap's Ctrl-click lands on a waypoint we just added): keep the order.
            if i ~= 1 then self:SyncBlizzard() end
            return
        end
        self:AddFirst(mapID, x, y)
        return
    end
    if not mirrored then return end
    local was = mirrored
    mirrored = nil
    local first = Points()[1]
    if first and first == was then
        local d = ns.Nav:To(first)
        self:Reached(first, not (d and d <= 2 * (entry.arrive or 15)))
        return
    end
    local r = ns.Targets and ns.Targets:GetRequest()
    if r then
        for _, p in ipairs(r.points) do
            if p == was then
                -- Cleared on the map: you stopped it (or the game cleared it on arrival).
                local d = ns.Nav:To(p)
                local there = d and d <= 2 * (r.arrive or 15)
                if not there then ns:Print(("Stopped navigating to %s."):format(r.title or "your destination")) end
                ns.Targets:ClearRequest(not there)
                return
            end
        end
    end
end

ns:On("USER_WAYPOINT_UPDATED", function() Chain:OnBlizzardPin() end)
ns:OnChanged(function() Chain:SyncBlizzard() end)
ns:On("PLAYER_ENTERING_WORLD", function()
    if ready then return end
    C_Timer.After(1, function()
        ready = true
        -- A pin the game kept from last time that isn't one of ours becomes the first waypoint.
        Chain:OnBlizzardPin()
        Chain:SyncBlizzard()
    end)
end)

ns:OnLoad(function()
    -- An empty path has no starter, whatever was saved.
    if #Points() == 0 then ns.char.chainStarter = nil end
end)
