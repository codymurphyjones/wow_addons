local _, ns = ...
local C = ns.Compat

-- The waypoint path: waypoints in order, shared with your group (Comm.lua). The arrow leads to the
-- first one; reaching it drops it from your copy only, so everyone walks the path at their own pace.
-- Your own adds, removes and wipes can be undone (10 deep): Ctrl+Z on the map, or /way undo.
-- Saved per character: chain = { { id, by, mapID, x, y, title } }, chainStarter, chainT, reached.
local Chain = {}
ns.Chain = Chain

local UNDO_MAX = 10
local undo = {} -- { kind = "add", id } | { kind = "remove", point, after } | { kind = "wipe" | "replace", old, starter, id }

local entry = { owner = "path", key = "path", ordered = true, arrive = 15, visited = {} }

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
    entry.subtitle = first.by ~= C.Me() and ("by " .. C.Short(first.by)) or nil
    return entry
end

function Chain:Count() return #Points() end
function Chain:Points() return Points() end
function Chain:Starter() return ns.char.chainStarter end
function Chain:IsMine() return not ns.char.chainStarter or ns.char.chainStarter == C.Me() end

---------------------------------------------------------------------------
-- Changes to your copy (no undo, nothing sent)
---------------------------------------------------------------------------

-- Inserts p after the waypoint `after` (or at the end). False when it's already there or reached.
function Chain:Insert(p, after, starter)
    local list = Points()
    if IndexOf(p.id) or ns.char.reached[p.id] then return false end
    if #list == 0 and not ns.char.chainStarter then ns.char.chainStarter = starter or p.by end
    local i = after and IndexOf(after)
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
-- From the map (Ctrl+click) and /way x y
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

-- Ctrl+right-click: removes the waypoint nearest (cx, cy) on the map you're looking at.
function Chain:RemoveNearest(mapID, cx, cy, aspect)
    aspect = aspect or 1
    local best, bestD
    for _, p in ipairs(Points()) do
        local px, py = ns.Nav:Project(p.mapID, p.x, p.y, mapID)
        if px then
            local dx, dy = (px - cx) * aspect, py - cy
            local d = dx * dx + dy * dy
            if not bestD or d < bestD then best, bestD = p, d end
        end
    end
    if best then self:Remove(best.id) else ns:Print("No waypoint on this map to remove.") end
end

ns:OnLoad(function()
    -- An empty path has no starter, whatever was saved.
    if #Points() == 0 then ns.char.chainStarter = nil end
end)
