local _, ns = ...

-- Private addon messages to your group (addons/shared, copied into each addon's Shared\ folder by
-- the build). One channel object per addon prefix:
--
--   local comm = ns.NewGroupComm("GHIS", { pace = 0.25, raids = false })
--   comm:On("D", function(payload, sender, m) ... end)
--   comm:Send("D", text)
--
-- It registers the prefix, queues what you send and lets it out one message every `pace` seconds
-- (under the client's throttle), splits long payloads into chunks and puts them back together on
-- the other side, picks the channel (instance, raid, party), checks the send result, and drops
-- secret, malformed and your own messages.
--
-- Wire formats (unchanged from the addons this came from, so old versions still understand us):
--   framing "chunked" (default; GroupHistory, Spyglass):  kind|id|i|n|body
--       id counts 1..999 per channel object, i of n chunks, each body at most `chunk` (230) bytes.
--       Partial messages are kept per sender:id until every chunk is in.
--   framing "plain" (Waypoint):  kind|version|rest  (just kind|version when rest is empty)
--       One message per send, no chunking; messages with another version are ignored.
--
-- Senders: handlers get the sender as opts.normalize(raw) (default: the raw text) and the raw text
-- in m.raw. On WoW Forever a sender can arrive as "Given Family", "GivenFamily" or
-- "Given Family-Server", so matching a sender to a character is not done here: pass
-- opts.normalize / opts.isMe from shared\Units.lua (the character-key component) when the addon
-- loads it. Without them, isMe compares a compact form (lowercase, no spaces, no "-Realm" on
-- Forever) with your own name, which is all the self-filter needs.
local GC = {}
ns.GroupComm = GC

local Comm = {}
Comm.__index = Comm

local DEFAULTS = { pace = 0.2, chunk = 230, framing = "chunked", raids = true, instance = "alone", partialTTL = 120 }

-- ---------------------------------------------------------------------------
-- Helpers (also on ns.GroupComm)
-- ---------------------------------------------------------------------------

-- A value we may read, or nil for a secret one (as shared\Secrets.lua).
local function Readable(v)
    if v == nil then return nil end
    if canaccessvalue and not canaccessvalue(v) then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
GC.Readable = Readable

-- Text with the wire separators taken out (or replaced), optionally cut to `max` bytes.
--   GC.Clean(s)               GroupHistory: ":", ";" and "|" removed, nil -> ""
--   GC.Clean(s, "|", "/", 60) Waypoint: "|" -> "/", at most 60 bytes
function GC.Clean(s, pattern, repl, max)
    local out = tostring(s or ""):gsub(pattern or "[:;|]", repl or "")
    if max then out = out:sub(1, max) end
    return out
end

-- "a|b||c" -> { "a", "b", "", "c" } (empty fields kept).
function GC.Split(s, sep)
    sep = sep or "|"
    local out, start = {}, 1
    while true do
        local i = s:find(sep, start, true)
        if not i then
            out[#out + 1] = s:sub(start)
            return out
        end
        out[#out + 1] = s:sub(start, i - 1)
        start = i + #sep
    end
end

local function InInstanceGroup()
    return IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and true or false
end

-- The channel to use now, or opts.fallback (nil by default) when there's none.
--   opts.raids     true (default): RAID in a raid. false: nothing in a raid (GroupHistory).
--   opts.instance  "alone" (default): INSTANCE_CHAT only when you're in an instance group and not
--                  also in a home group (GroupHistory, Spyglass). "first": INSTANCE_CHAT whenever
--                  you're in an instance group (Waypoint, BattleRecap's chat).
--   opts.fallback  the channel when you're in no group ("SAY" for chat; nil for addon messages).
function GC.Channel(opts)
    opts = opts or DEFAULTS
    local instance = InInstanceGroup()
    if instance then
        if opts.instance == "first" then return "INSTANCE_CHAT" end
        if not (LE_PARTY_CATEGORY_HOME and IsInGroup(LE_PARTY_CATEGORY_HOME)) then return "INSTANCE_CHAT" end
    end
    if IsInGroup and IsInGroup() then
        if IsInRaid and IsInRaid() then
            if opts.raids ~= false then return "RAID" end
            return opts.fallback
        end
        return "PARTY"
    end
    return opts.fallback
end

-- Comparison form of a name: "givenfamily" (no spaces, no "-Server"), as WoW Forever names come.
function GC.Compact(name)
    name = Readable(name)
    if type(name) ~= "string" or name == "" then return nil end
    local base = (name:match("^([^%-]+)") or name):gsub("%s", ""):lower()
    return base ~= "" and base or nil
end

-- Whether a sender is you (the default self-filter). UnitName("player") is (given, family).
function GC.IsMe(sender)
    local c = GC.Compact(sender)
    if not c or not UnitName then return false end
    local given, family = UnitName("player")
    given, family = Readable(given), Readable(family)
    if type(given) ~= "string" then return false end
    if type(family) == "string" and family ~= "" and c == GC.Compact(given .. " " .. family) then return true end
    return c == GC.Compact(given)
end

-- ---------------------------------------------------------------------------
-- A channel object
-- ---------------------------------------------------------------------------

-- prefix: the addon-message prefix (at most 16 characters). opts (all optional):
--   pace        seconds between messages (0.2)
--   chunk       payload bytes per chunked message (230)
--   framing     "chunked" (kind|id|i|n|body) or "plain" (kind|version|rest)
--   version     plain framing only: the version field ("1")
--   raids, instance, fallback   the channel choice (GC.Channel)
--   normalize   fn(rawSender) -> the sender handlers get (and partials are keyed by); nil drops
--   isMe        fn(rawSender) -> true for your own messages (GC.IsMe)
--   keepOwn     true: don't drop your own messages
--   onFail      fn(result, msg, channel): the first failed send after a good one (the game
--               refused or throttled it); onRecover fn(): the first good send after a failure
--   partialTTL  seconds an incomplete chunked message is kept (120)
--   listen      false: no event frame; feed comm:Receive(prefix, msg, channel, sender) yourself
function ns.NewGroupComm(prefix, opts)
    local c = setmetatable({ prefix = prefix, opts = {}, outbox = {}, pumping = false, nextID = 0,
        partial = {}, handlers = {}, any = {}, raw = {}, failed = false }, Comm)
    for k, v in pairs(DEFAULTS) do c.opts[k] = v end
    for k, v in pairs(opts or {}) do c.opts[k] = v end
    c:Register()
    if c.opts.listen ~= false and CreateFrame then
        local f = CreateFrame("Frame")
        f:RegisterEvent("CHAT_MSG_ADDON")
        f:RegisterEvent("PLAYER_LOGIN")
        f:SetScript("OnEvent", function(_, event, ...)
            if event == "CHAT_MSG_ADDON" then c:Receive(...) else c:Register() end
        end)
        c.frame = f
    end
    return c
end
GC.New = ns.NewGroupComm

-- Registers the prefix (again: harmless). True when the client accepted it.
function Comm:Register()
    local fn = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
    if not fn then return false end
    local ok, result = pcall(fn, self.prefix)
    return ok and result ~= false
end

function Comm:Channel() return GC.Channel(self.opts) end
function Comm:InGroup() return self:Channel() ~= nil end

local function SendFn() return C_ChatInfo and C_ChatInfo.SendAddonMessage end

-- Sends one wire message now (no queue). true, or false and the result when it failed.
function Comm:SendNow(msg, channel)
    channel = channel or self:Channel()
    local send = SendFn()
    if not (channel and send) then return false end
    local ok, result = pcall(send, self.prefix, msg, channel)
    -- A result code (0 is success); a false result counts as a failure too.
    local failed = not ok or result == false or (type(result) == "number" and result ~= 0)
    if failed then
        if not self.failed and self.opts.onFail then pcall(self.opts.onFail, result, msg, channel) end
        self.failed = true
        return false, result
    end
    if self.failed and self.opts.onRecover then pcall(self.opts.onRecover) end
    self.failed = false
    return true
end

-- Lets the queue out, one message every `pace` seconds. The channel is looked up per message:
-- with no group left, the message is dropped (as before).
function Comm:Pump()
    local msg = table.remove(self.outbox, 1)
    if not msg then self.pumping = false return end
    local channel = self:Channel()
    if channel then self:SendNow(msg, channel) end
    C_Timer.After(self.opts.pace, function() self:Pump() end)
end

-- Queues exact wire text. false when there's no channel (nothing queued).
function Comm:SendRaw(msg)
    if not (self:Channel() and SendFn()) then return false end
    self.outbox[#self.outbox + 1] = msg
    if not self.pumping then self.pumping = true; self:Pump() end
    return true
end

-- The wire messages a send produces (also used by the tests), without queueing them.
function Comm:Frames(kind, payload)
    payload = payload or ""
    if self.opts.framing == "plain" then
        local head = kind .. "|" .. tostring(self.opts.version or "1")
        return { payload ~= "" and (head .. "|" .. payload) or head }
    end
    self.nextID = self.nextID % 999 + 1
    local size = self.opts.chunk
    local n = math.max(1, math.ceil(#payload / size))
    local out = {}
    for i = 1, n do
        out[i] = ("%s|%d|%d|%d|%s"):format(kind, self.nextID, i, n, payload:sub((i - 1) * size + 1, i * size))
    end
    return out
end

-- Sends `payload` (any text; plain framing: the rest after kind|version) under `kind` to the
-- group. false when you're in no group (nothing is queued).
function Comm:Send(kind, payload)
    if not (self:Channel() and SendFn()) then return false end
    for _, msg in ipairs(self:Frames(kind, payload)) do self.outbox[#self.outbox + 1] = msg end
    if not self.pumping then self.pumping = true; self:Pump() end
    return true
end

-- fn(payload, sender, m) for every complete message of this kind from someone else.
-- m = { kind, payload, sender, raw (the sender as it came), channel, version, fields (plain:
-- the whole message split on "|") }.
function Comm:On(kind, fn)
    self.handlers[kind] = self.handlers[kind] or {}
    table.insert(self.handlers[kind], fn)
end

-- fn(kind, payload, sender, m) for every complete message.
function Comm:OnAny(fn) self.any[#self.any + 1] = fn end

-- fn(msg, sender, m) for every message under the prefix before any parsing (any framing).
function Comm:OnRaw(fn) self.raw[#self.raw + 1] = fn end

-- Forget queued and half-received messages (leaving the group).
function Comm:Reset()
    wipe(self.outbox)
    wipe(self.partial)
end

function Comm:Queued() return #self.outbox end

local function Run(list, ...)
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, ...)
        if not ok and geterrorhandler then geterrorhandler()(err) end
    end
end

function Comm:Dispatch(m)
    Run(self.any, m.kind, m.payload, m.sender, m)
    Run(self.handlers[m.kind] or {}, m.payload, m.sender, m)
end

local function Now() return GetTime and GetTime() or 0 end

-- The CHAT_MSG_ADDON handler: (prefix, msg, channel, sender).
function Comm:Receive(prefix, msg, channel, sender)
    if prefix ~= self.prefix or type(msg) ~= "string" then return end
    if Readable(msg) == nil or Readable(sender) == nil then return end
    if not self.opts.keepOwn and (self.opts.isMe or GC.IsMe)(sender) then return end
    local key = sender
    if self.opts.normalize then
        key = self.opts.normalize(sender)
        if key == nil then return end
    end
    local m = { raw = sender, sender = key, channel = channel }
    Run(self.raw, msg, key, m)

    if self.opts.framing == "plain" then
        local f = GC.Split(msg)
        if f[2] ~= tostring(self.opts.version or "1") then return end
        m.kind, m.version, m.fields = f[1], f[2], f
        m.payload = msg:match("^[^|]*|[^|]*|(.*)$") or ""
        return self:Dispatch(m)
    end

    local kind, id, i, n, body = msg:match("^([^|]+)|(%d+)|(%d+)|(%d+)|(.*)$")
    if not kind then return end
    i, n = tonumber(i), tonumber(n)
    m.kind = kind
    if n == 1 then
        m.payload = body
        return self:Dispatch(m)
    end
    local now, ttl = Now(), self.opts.partialTTL
    if ttl and ttl > 0 then
        for k, p in pairs(self.partial) do
            if now - p.t > ttl then self.partial[k] = nil end
        end
    end
    local pkey = tostring(key) .. ":" .. id
    local p = self.partial[pkey]
    if not p or p.n ~= n then p = { n = n, parts = {}, got = 0, t = now }; self.partial[pkey] = p end
    if i and i >= 1 and i <= n and not p.parts[i] then p.parts[i] = body; p.got = p.got + 1 end
    if p.got == n then
        self.partial[pkey] = nil
        m.payload = table.concat(p.parts)
        return self:Dispatch(m)
    end
end
