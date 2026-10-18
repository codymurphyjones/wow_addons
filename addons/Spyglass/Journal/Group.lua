local ADDON, ns = ...

-- Group sync for the journal: private addon messages to your party or raid (no chat channel to
-- create or clean up), and one "host" per group who holds the master copy of shared data such as
-- the Pull Planner's plan.
--
-- Who hosts: the group leader if they run SpyGlass; otherwise the member running SpyGlass whose
-- full name sorts first. Every client works this out from the same facts (who's in the group,
-- who leads it, who has said hello), so they all arrive at the same host without a vote. The host
-- then announces itself; when two clients briefly disagree (a hello still in flight), the claim
-- from the better candidate wins and everyone settles on it. When the group ends, everything
-- shared is dropped.
local G = {}
ns.Group = G

local PREFIX = "SGJG"         -- SpyGlass Journal Group
local VERSION = 1
local CHUNK = 230             -- payload bytes per message (addon messages max 255)
local SEND_EVERY = 0.2        -- seconds between messages, under the client's throttle
local HELLO_AGAIN = 5         -- don't answer hellos more often than this

G.peers = {}                  -- full name -> { version, t }: group members running SpyGlass
G.host = nil                  -- full name of the host, or nil when not in a group
local handlers = {}           -- kind -> { fn(payload, sender) }
local listeners = {}          -- fn(event) for "host", "peers", "left"
local outbox, pumping = {}, false
local partial = {}            -- sender .. id -> { n, parts }
local nextID, lastHello = 0, 0

local function Me()
    local name, realm = UnitFullName("player")
    return name .. "-" .. (realm and realm ~= "" and realm or (GetNormalizedRealmName() or ""))
end

local function Full(name)
    if not name then return nil end
    if name:find("-", 1, true) then return name end
    return name .. "-" .. (GetNormalizedRealmName() or "")
end

local function Channel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and not IsInGroup(LE_PARTY_CATEGORY_HOME) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

local function Fire(event)
    for _, fn in ipairs(listeners) do pcall(fn, event) end
end

-- Group members now: full name -> true, and the leader's full name.
local function Roster()
    local out, leader = {}, nil
    local n = GetNumGroupMembers() or 0
    local raid = IsInRaid()
    local units = {}
    if raid then
        for i = 1, n do units[#units + 1] = "raid" .. i end
    else
        units[1] = "player"
        for i = 1, n - 1 do units[#units + 1] = "party" .. i end
    end
    for _, unit in ipairs(units) do
        local name, realm = UnitName(unit)
        if name then
            local full = name .. "-" .. ((realm and realm ~= "") and realm or (GetNormalizedRealmName() or ""))
            out[full] = true
            if UnitIsGroupLeader(unit) then leader = full end
        end
    end
    return out, leader
end

-- ---------------------------------------------------------------------------
-- Sending
-- ---------------------------------------------------------------------------

local function Pump()
    local item = table.remove(outbox, 1)
    if not item then pumping = false return end
    local channel = Channel()
    if channel then pcall(C_ChatInfo.SendAddonMessage, PREFIX, item, channel) end
    C_Timer.After(SEND_EVERY, Pump)
end

local function Queue(msg)
    outbox[#outbox + 1] = msg
    if not pumping then pumping = true; Pump() end
end

-- Sends `payload` (any text) under `kind` to the whole group, split into as many messages as needed.
function G:Send(kind, payload)
    if not Channel() then return false end
    payload = payload or ""
    nextID = nextID % 999 + 1
    local n = math.max(1, math.ceil(#payload / CHUNK))
    for i = 1, n do
        Queue(("%s|%d|%d|%d|%s"):format(kind, nextID, i, n, payload:sub((i - 1) * CHUNK + 1, i * CHUNK)))
    end
    return true
end

-- fn(payload, sender) runs for every complete message of this kind from someone else.
function G:On(kind, fn)
    handlers[kind] = handlers[kind] or {}
    table.insert(handlers[kind], fn)
end

-- fn(event): "host" (the host changed), "peers" (someone joined or left), "left" (the group ended).
function G:Listen(fn) listeners[#listeners + 1] = fn end

function G:InGroup() return Channel() ~= nil end
function G:IsHost() return self.host ~= nil and self.host == Me() end
function G:Me() return Me() end

-- ---------------------------------------------------------------------------
-- Choosing the host
-- ---------------------------------------------------------------------------

-- The best candidate, by the rule everyone shares: the leader if they run SpyGlass, else the
-- first full name in sort order among members who do.
local function Elect()
    if not Channel() then return nil end
    local roster, leader = Roster()
    local me = Me()
    G.peers[me] = { version = VERSION, t = time() }
    for name in pairs(G.peers) do
        if not roster[name] then G.peers[name] = nil end
    end
    if leader and G.peers[leader] then return leader end
    local best
    for name in pairs(G.peers) do
        if not best or name < best then best = name end
    end
    return best
end

-- Whether candidate a should host rather than b.
local function Better(a, b)
    if not b then return true end
    local _, leader = Roster()
    if a == leader then return true end
    if b == leader then return false end
    return a < b
end

local function Settle()
    local was = G.host
    G.host = Elect()
    if G.host ~= was then
        if G.host == Me() then G:Send("HOST", Me()) end
        Fire("host")
    end
end

local function Hello(reply)
    if not Channel() then return end
    if reply and GetTime() - lastHello < HELLO_AGAIN then return end
    lastHello = GetTime()
    G:Send(reply and "HI2" or "HI", tostring(VERSION))
end

-- ---------------------------------------------------------------------------
-- Receiving
-- ---------------------------------------------------------------------------

local function Dispatch(kind, payload, sender)
    if kind == "HI" or kind == "HI2" then
        local isNew = not G.peers[sender]
        G.peers[sender] = { version = tonumber(payload) or 0, t = time() }
        if kind == "HI" then Hello(true) end -- tell the newcomer we're here too
        if isNew then Fire("peers") end
        Settle()
        -- A newcomer needs the host's shared data.
        if isNew and G:IsHost() then Fire("newpeer") end
        return
    end
    if kind == "HOST" then
        G.peers[sender] = G.peers[sender] or { version = 0, t = time() }
        local mine = Elect()
        -- Accept a claim from a candidate at least as good as the one we'd pick.
        if payload == sender and (payload == mine or Better(payload, mine)) and G.host ~= payload then
            G.host = payload
            Fire("host")
        elseif mine == Me() and payload ~= Me() then
            G:Send("HOST", Me()) -- we're the better candidate: say so
        end
        return
    end
    for _, fn in ipairs(handlers[kind] or {}) do pcall(fn, payload, sender) end
end

local function OnAddonMessage(prefix, msg, _, sender)
    if prefix ~= PREFIX or type(msg) ~= "string" then return end
    local function Secret(v) return v ~= nil and (canaccessvalue and not canaccessvalue(v) or issecretvalue and issecretvalue(v)) end
    if Secret(msg) or Secret(sender) then return end
    sender = Full(sender)
    if sender == Me() then return end
    local kind, id, i, n, body = msg:match("^([^|]+)|(%d+)|(%d+)|(%d+)|(.*)$")
    if not kind then return end
    i, n = tonumber(i), tonumber(n)
    if n == 1 then return Dispatch(kind, body, sender) end
    local key = sender .. ":" .. id
    local p = partial[key]
    if not p or p.n ~= n then p = { n = n, parts = {}, got = 0, t = GetTime() }; partial[key] = p end
    if not p.parts[i] then p.parts[i] = body; p.got = p.got + 1 end
    if p.got == n then
        partial[key] = nil
        Dispatch(kind, table.concat(p.parts), sender)
    end
end

-- ---------------------------------------------------------------------------

local inGroup = false
local rosterPending = false

local function OnRoster()
    rosterPending = false
    local now = Channel() ~= nil
    if now and not inGroup then
        inGroup = true
        wipe(G.peers)
        Hello(false)
        Settle()
    elseif not now and inGroup then
        inGroup = false
        wipe(G.peers); wipe(partial); wipe(outbox)
        G.host = nil
        Fire("left")
    elseif now then
        Settle()
        Fire("peers")
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PARTY_LEADER_CHANGED")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
        C_Timer.After(3, OnRoster)
    elseif event == "CHAT_MSG_ADDON" then
        OnAddonMessage(...)
    elseif not rosterPending then
        -- Roster events come in bursts: look once things settle.
        rosterPending = true
        C_Timer.After(1, OnRoster)
    end
end)
