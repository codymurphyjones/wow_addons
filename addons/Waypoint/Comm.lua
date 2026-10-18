local _, ns = ...
local C = ns.Compat

-- Shares the waypoint path with your group over a hidden addon channel (after GroupHistory's
-- Sync.lua). Messages, all short enough for one send:
--   A|1|starter|id|after|mapID|x|y|title   added a waypoint after `after` (empty: at the end)
--   S|1|...                                the same, quietly: resends of a whole path
--   R|1|id                                 removed a waypoint
--   C|1                                    cleared the path
--   Q|1                                    "send me your path" (on joining a group)
local Comm = {}
ns.Comm = Comm

local PREFIX, VER = "WAYPT", "1"
local SPACING = 0.2

local outbox, sending, warned = {}, false, false
local batches = {} -- sender -> count of quiet adds still to report

local function Channel()
    if not (IsInGroup and IsInGroup()) then return nil end
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid and IsInRaid() then return "RAID" end
    return "PARTY"
end

local function Pump()
    local msg = table.remove(outbox, 1)
    if not msg then
        sending = false
        return
    end
    local channel = Channel()
    if channel then
        local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, channel)
        -- Newer clients return a result code (0 is success), older ones a boolean.
        local failed = not ok or result == false or (type(result) == "number" and result ~= 0)
        if failed and not warned then
            warned = true
            ns:Print("Couldn't reach your group right now (the game may be blocking addon messages); your waypoints stayed on your map.")
        elseif not failed then
            warned = false
        end
    end
    C_Timer.After(SPACING, Pump)
end

-- Queues "KIND|rest" (the version is added here).
function Comm:Send(msg)
    if not (ns.db.share and Channel() and C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    local kind, rest = msg:match("^(%u)|?(.*)$")
    outbox[#outbox + 1] = kind .. "|" .. VER .. (rest ~= "" and ("|" .. rest) or "")
    if not sending then
        sending = true
        Pump()
    end
end

local function Clean(text)
    return text and text:gsub("|", "/"):sub(1, 60) or ""
end

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

local function Split(s)
    local out, start = {}, 1
    while true do
        local i = s:find("|", start, true)
        if not i then
            out[#out + 1] = s:sub(start)
            return out
        end
        out[#out + 1] = s:sub(start, i - 1)
        start = i + 1
    end
end

local function ReportBatch(sender)
    local n = batches[sender]
    batches[sender] = nil
    if n and n > 0 then
        ns:Print(("%s sent their waypoint path (%d waypoint%s)."):format(C.Short(sender), n, n == 1 and "" or "s"))
    end
end

local function OnMessage(prefix, msg, _, sender)
    if prefix ~= PREFIX or type(C.Readable(msg)) ~= "string" then return end
    sender = C.Full(sender)
    if not sender or sender == C.Me() or not ns.db.share then return end
    local f = Split(msg)
    local kind = f[1]
    if f[2] ~= VER then return end
    local who = C.Short(sender)
    if kind == "A" or kind == "S" then
        local p = { id = f[4], by = f[4] and f[4]:match("^(.-)#%d+$") or sender,
            mapID = tonumber(f[6]), x = tonumber(f[7]), y = tonumber(f[8]), title = f[9] ~= "" and f[9] or nil }
        if not (p.id and p.mapID and p.x and p.y) then return end
        local starter = f[3] ~= "" and f[3] or sender
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
ns:OnLoad(function()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    end
end)
ns:On("CHAT_MSG_ADDON", OnMessage)
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
