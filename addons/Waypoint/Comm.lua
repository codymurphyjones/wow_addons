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
local U = ns.Units

---------------------------------------------------------------------------
-- Offers: a teammate's waypoint while you're following your own
---------------------------------------------------------------------------

-- When a teammate shares a waypoint while you're going somewhere you chose yourself (waypoints you
-- put on your path, or a "navigate to" you clicked: a dungeon or town in Field Guide, a town or dock
-- on the map, the Navigate menu), it isn't added on its own: a popup asks whether you want to go as
-- well (Yes: it goes first, then what you were doing; No: not this time; Show: the map opens on it,
-- then the question comes back). An addon's own target (Field Guide's leveling steps and the like)
-- isn't your choice, so it never makes Waypoint ask. A whole path sent at once is one question.
local offers = {}   -- { { sender, starter, points = { { p, after } } } }, the first one being asked
local declined = {} -- point id -> true: said no this session; resends don't ask again

-- What you chose yourself and are following now: "path" (waypoints you placed), the request you
-- clicked (its entry), or nil.
local function OwnChoice()
    for _, p in ipairs(ns.Chain:Points()) do
        if U.Same(p.by, C.Me()) then return "path" end
    end
    return ns.Targets and ns.Targets:GetRequest() or nil
end

local function OfferOf(sender)
    for _, o in ipairs(offers) do
        if o.sender == sender then return o end
    end
end

local function OfferText(o)
    local who, n, first = C.Short(o.sender), #o.points, o.points[1].p
    local where = (first.title and (first.title .. ", ") or "") .. ns.Nav:Describe(first)
    local choice = OwnChoice()
    local after = type(choice) == "table" and ("then on to %s"):format(choice.title or "where you were going")
        or "then your own waypoints"
    if n == 1 then
        return ("%s shared a waypoint:\n|cffffffff%s|r\n\nGo there as well? It goes first, %s."):format(who, where, after)
    end
    return ("%s shared their path (%d waypoints), starting at:\n|cffffffff%s|r\n\nGo there as well? Their waypoints go first, %s.")
        :format(who, n, where, after)
end

local AskNext

local function Done(o)
    for i, other in ipairs(offers) do
        if other == o then table.remove(offers, i) break end
    end
    if ns.MapPins and ns.MapPins.ClearPreview then ns.MapPins:ClearPreview() end
    C_Timer.After(0, AskNext)
end

local function Accept(o)
    -- Their waypoints first, in their order; your own path follows.
    local prev = ns.Chain.FRONT
    local added = 0
    for _, item in ipairs(o.points) do
        if ns.Chain:Insert(item.p, prev, o.starter) then
            added = added + 1
            prev = item.p.id
        end
    end
    if added > 0 then
        ns:Print(("Going with %s: %s first, then back to what you were doing."):format(C.Short(o.sender), ns.Nav:Describe(o.points[1].p)))
    end
    Done(o)
end

local function Decline(o)
    for _, item in ipairs(o.points) do declined[item.p.id] = true end
    ns:Print(("Staying on your own way (not following %s's waypoint)."):format(C.Short(o.sender)))
    Done(o)
end

-- Show: the map on their waypoint, marked, then the same question again.
local function ShowOffer(o)
    local p = o.points[1].p
    if ns.MapPins and ns.MapPins.Preview then
        ns.MapPins:Preview(p, ("%s's waypoint"):format(C.Short(o.sender)), "Not on your path yet: answer the question to add it.")
    end
    if WorldMapFrame and not InCombatLockdown() then
        if not WorldMapFrame:IsShown() then
            if OpenWorldMap then OpenWorldMap(p.mapID) else ShowUIPanel(WorldMapFrame) end
        end
        if WorldMapFrame.SetMapID then WorldMapFrame:SetMapID(p.mapID) end
    end
    o.asking = nil
    C_Timer.After(0, AskNext)
end

StaticPopupDialogs["WAYPOINT_SHARED"] = {
    text = "%s", button1 = YES or "Yes", button2 = NO or "No", button3 = "Show",
    OnAccept = function(_, o) Accept(o) end,
    OnCancel = function(_, o, reason)
        -- No (Escape counts as No). Pushed away by another popup ("override") isn't an answer: ask again.
        if reason == "override" then o.asking = nil; C_Timer.After(1, AskNext) else Decline(o) end
    end,
    OnAlt = function(_, o) ShowOffer(o) end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}

function AskNext()
    local o = offers[1]
    if not o or o.asking then return end
    if StaticPopup_FindVisible and StaticPopup_FindVisible("WAYPOINT_SHARED") then return end
    o.asking = true
    StaticPopup_Show("WAYPOINT_SHARED", OfferText(o), nil, o)
end

-- A teammate's waypoint for your path: added as before, or (with your own waypoints in it) asked about.
local function Receive(p, after, starter, sender, quiet)
    if declined[p.id] then return false end
    local pending = OfferOf(sender)
    if pending or OwnChoice() then
        for _, item in ipairs(pending and pending.points or {}) do
            if item.p.id == p.id then return false end
        end
        if not pending then
            pending = { sender = sender, starter = starter, points = {} }
            offers[#offers + 1] = pending
            -- A path arrives a message at a time: ask once it's all here.
            C_Timer.After(quiet and 1.2 or 0.6, AskNext)
        end
        pending.points[#pending.points + 1] = { p = p, after = after }
        return false
    end
    return ns.Chain:Insert(p, after, starter)
end

-- Their removes and clears reach a waypoint you haven't answered for yet.
local function Withdraw(sender, id)
    local o = OfferOf(sender)
    if not o then return end
    for i = #o.points, 1, -1 do
        if not id or o.points[i].p.id == id then table.remove(o.points, i) end
    end
    if #o.points == 0 then
        if o.asking and StaticPopup_Hide then StaticPopup_Hide("WAYPOINT_SHARED") end
        Done(o)
    end
end

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
        if not Receive(p, f[5] ~= "" and f[5] or nil, starter, sender, kind == "S") then return end
        if kind == "A" then
            ns:Print(("%s added waypoint %d: %s."):format(who, ns.Chain:Count(), ns.Nav:Describe(p)))
        else
            if not batches[sender] then C_Timer.After(1, function() ReportBatch(sender) end) end
            batches[sender] = (batches[sender] or 0) + 1
        end
    elseif kind == "R" then
        Withdraw(sender, f[3])
        local p = ns.Chain:Delete(f[3])
        if p then ns:Print(("%s removed a waypoint (%s)."):format(who, ns.Nav:Describe(p))) end
    elseif kind == "C" then
        Withdraw(sender)
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
