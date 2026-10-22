local _, ns = ...
local C = ns.Compat

-- Shares the waypoint path with your group over a hidden addon channel (after Fireside's
-- Sync.lua). Messages, all short enough for one send:
--   A|1|starter|id|after|mapID|x|y|title   added a waypoint after `after` (empty: at the end)
--   S|1|...                                the same, quietly: resends of a whole path
--   R|1|id                                 removed a waypoint
--   C|1                                    cleared the path
--   Q|1                                    "send me your path" (on joining a group)
local Comm = {}
ns.Comm = Comm

local PREFIX, VER = "WAYPT", "1"

local batches = {} -- sender -> count of quiet adds still to report

-- The channel (shared GroupComm.lua): plain "KIND|1|rest" messages, one every 0.2 s, the instance
-- group first, then raid, then party. Senders arrive as keys (Compat.Full: Units.KeyOf), your own
-- are dropped (Units.IsMe also knows the "GivenFamily" and "-Server" shapes).
local comm = ns.NewGroupComm(PREFIX, {
    framing = "plain", version = VER, pace = 0.2, instance = "first",
    normalize = C.Full, isMe = ns.Units.IsMe,
    onFail = function()
        ns:Print("Couldn't reach your group right now (the game may be blocking addon messages); your waypoints stayed on your map.")
    end,
})
Comm.comm = comm

-- Queues "KIND|rest" (the version is added on the way out: "KIND|1|rest").
function Comm:Send(msg)
    if not ns.db.share then return end
    local kind, rest = msg:match("^(%u)|?(.*)$")
    comm:Send(kind, rest)
end

local function Clean(text) return ns.GroupComm.Clean(text, "|", "/", 60) end

function Comm:SendAdd(p, after, quiet)
    self:Send(table.concat({ quiet and "S" or "A", ns.Chain:Starter() or C.Me(), p.id, after or "",
        tostring(p.mapID), ("%.4f"):format(p.x), ("%.4f"):format(p.y), Clean(p.title) }, "|"))
end

-- Your whole path, quietly, in order.
function Comm:SendPath()
    local prev
    for _, p in ipairs(ns.Chain:Points()) do
        self:SendAdd(p, prev, true)
        prev = p.id
    end
end

function Comm:AskForPath()
    self:Send("Q")
end

local function ReportBatch(sender)
    local n = batches[sender]
    batches[sender] = nil
    if n and n > 0 then
        ns:Print(("%s sent their waypoint path (%d waypoint%s)."):format(C.Short(sender), n, n == 1 and "" or "s"))
    end
end

-- A message from someone else in the group (GroupComm has dropped your own, secret and other
-- versions'): f = its fields, "KIND|1|..." split on "|".
local function OnMessage(kind, _, sender, m)
    if not ns.db.share then return end
    local f = m.fields
    local who = C.Short(sender)
    if kind == "A" or kind == "S" then
        -- Who added it and who started the path, as the sender wrote them: in key form here.
        local p = { id = f[4], by = C.Full(f[4] and f[4]:match("^(.-)#%d+$")) or sender,
            mapID = tonumber(f[6]), x = tonumber(f[7]), y = tonumber(f[8]), title = f[9] ~= "" and f[9] or nil }
        if not (p.id and p.mapID and p.x and p.y) then return end
        local starter = C.Full(f[3]) or sender
        if not ns.Chain:Insert(p, f[5] ~= "" and f[5] or nil, starter) then return end
        if kind == "A" then
            ns:Print(("%s added waypoint %d: %s."):format(who, ns.Chain:Count(), ns.Nav:Describe(p)))
        else
            if not batches[sender] then C_Timer.After(1, function() ReportBatch(sender) end) end
            batches[sender] = (batches[sender] or 0) + 1
        end
    elseif kind == "R" then
        local p = ns.Chain:Delete(f[3])
        if p then ns:Print(("%s removed a waypoint (%s)."):format(who, ns.Nav:Describe(p))) end
    elseif kind == "C" then
        if ns.Chain:Count() > 0 then
            ns.Chain:WipeLocal()
            ns:Print(who .. " cleared the waypoint path.")
        end
    elseif kind == "Q" then
        if ns.Chain:Count() > 0 then Comm:SendPath() end
    end
end

local asked = false
comm:OnAny(OnMessage)
ns:On("GROUP_JOINED", function()
    C_Timer.After(2, function() Comm:AskForPath() end)
end)
ns:On("PLAYER_ENTERING_WORLD", function()
    if asked then return end
    asked = true
    C_Timer.After(3, function()
        if ns.Chain:Count() == 0 then Comm:AskForPath() end
    end)
end)
