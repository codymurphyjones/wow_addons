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
--
-- The messages go through the shared GroupComm.lua (framing, pacing, the channel, dropping your
-- own); names are the shared Units.lua keys ("Given Family").
local G = {}
ns.Group = G

local U = ns.Units
local PREFIX = "SGJG"         -- SpyGlass Journal Group
local VERSION = 1
local HELLO_AGAIN = 5         -- don't answer hellos more often than this

G.peers = {}                  -- full name -> { version, t }: group members running SpyGlass
G.host = nil                  -- full name of the host, or nil when not in a group
local handlers = {}           -- kind -> { fn(payload, sender) }
local listeners = {}          -- fn(event) for "host", "peers", "left"
local lastHello = 0

local Me = U.Me

local function Fire(event)
    for _, fn in ipairs(listeners) do pcall(fn, event) end
end

-- Group members now: full name -> true, and the leader's full name.
local ROSTER = { includeSelf = true }
local function Roster()
    local out, leader = {}, nil
    for _, unit in ipairs(U.GroupUnits(ROSTER)) do
        local full = U.UnitFull(unit)
        if full then
            out[full] = true
            if UnitIsGroupLeader(unit) then leader = full end
        end
    end
    return out, leader
end

-- A sender as the roster names them (on Forever a sender can arrive as "GivenFamily" or with
-- "-Server"), else in key form: the shared Units.lua Canon.
local SenderKey = U.Canon

local comm = ns.NewGroupComm(PREFIX, { pace = 0.2, raids = true, normalize = SenderKey, isMe = U.IsMe })

-- ---------------------------------------------------------------------------
-- Sending
-- ---------------------------------------------------------------------------

-- Sends `payload` (any text) under `kind` to the whole group, split into as many messages as needed.
function G:Send(kind, payload) return comm:Send(kind, payload) end

-- fn(payload, sender) runs for every complete message of this kind from someone else.
function G:On(kind, fn)
    handlers[kind] = handlers[kind] or {}
    table.insert(handlers[kind], fn)
end

-- fn(event): "host" (the host changed), "peers" (someone joined or left), "left" (the group ended).
function G:Listen(fn) listeners[#listeners + 1] = fn end

function G:InGroup() return comm:Channel() ~= nil end
function G:IsHost() return self.host ~= nil and self.host == Me() end
function G:Me() return Me() end

-- ---------------------------------------------------------------------------
-- Choosing the host
-- ---------------------------------------------------------------------------

-- The best candidate, by the rule everyone shares: the leader if they run SpyGlass, else the
-- first full name in sort order among members who do.
local function Elect()
    if not comm:Channel() then return nil end
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
    if not comm:Channel() then return end
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
        -- The claim names its sender (as they write their own name: matched loosely, then kept
        -- in our key form). Accept it from a candidate at least as good as the one we'd pick.
        local claim = (payload == sender or U.Same(payload, sender)) and sender or nil
        if claim and (claim == mine or Better(claim, mine)) and G.host ~= claim then
            G.host = claim
            Fire("host")
        elseif mine == Me() and not U.IsMe(payload) then
            G:Send("HOST", Me()) -- we're the better candidate: say so
        end
        return
    end
    for _, fn in ipairs(handlers[kind] or {}) do pcall(fn, payload, sender) end
end

comm:OnAny(function(kind, payload, sender) Dispatch(kind, payload, sender) end)

-- ---------------------------------------------------------------------------

local inGroup = false
local rosterPending = false

local function OnRoster()
    rosterPending = false
    local now = comm:Channel() ~= nil
    if now and not inGroup then
        inGroup = true
        wipe(G.peers)
        Hello(false)
        Settle()
    elseif not now and inGroup then
        inGroup = false
        wipe(G.peers); comm:Reset()
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
frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(3, OnRoster)
    elseif not rosterPending then
        -- Roster events come in bursts: look once things settle.
        rosterPending = true
        C_Timer.After(1, OnRoster)
    end
end)
