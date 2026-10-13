local ADDON, ns = ...

-- Players' SpyGlass clients share discoveries with each other, git-style, so
-- they spread past one realm and faction (an account carries them between its
-- characters) and reach the developer even when nobody saw the developer
-- online. Only with "Contribute data" on.
--
-- The data is a set of facts (Contribute.lua's: loot, vendors, quests...). Its
-- state is one hash (buckets of facts, hashed together); every change makes a
-- commit, hash(previous commit .. state), so each client has a history.
-- A client asks for everyone's state once, at login; after that it only
-- watches and reports: it announces each new commit, and whenever it sees a
-- state that differs from its own (also in other players' syncs, which it
-- didn't ask for) it pulls the facts it lacks from that peer, bucket by
-- bucket, until both have the same hash.
--
-- Only trusted peers are listened to. A peer proves it belongs by showing it
-- knows hashes from a shared history, without giving them away: we name three
-- positions in it and a random word, it answers with hash(word .. position ..
-- hash) for each.
local S = {}
ns.Sync = S

-- Trust, version 1: every client shares the 3 seed hashes in Data\Anchors.lua.
-- Set to false (or delete this line) for version 2: the developer's recent
-- history hashes (the latest RECENT of them) decide who is trusted.
local SIMPLE_TRUST = true

local RECENT = 40          -- version 2: challenges come from the latest this many developer commits
local NEEDED = 2           -- version 2: of the 3 asked, how many a peer must know (version 1: all 3)
local MAX_FACTS = 5000
local MAX_HISTORY = 200
local REPLY_DELAY = 15     -- answering a login's "HELLO": wait up to this long (others may answer first)
local COMMIT_AFTER = 10    -- seconds of quiet after a change before committing it
local SESSION = 30         -- seconds a pull from one peer may take before another may start
local BUCKETS = 16

local C = ns.Contribute

---------------------------------------------------------------------------
-- Hashing
---------------------------------------------------------------------------

local function H32a(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return h
end

local function H32b(s)
    local h = 0
    for i = 1, #s do h = (s:byte(i) + h * 65599) % 4294967296 end
    return h
end

-- 64-bit (16 hex characters): two different hashes side by side.
local function Hash(s)
    return string.format("%08x%08x", H32a(s), H32b(s))
end
S.Hash = Hash

---------------------------------------------------------------------------
-- The fact set and its history
---------------------------------------------------------------------------

local function DB()
    ns.db.sync = type(ns.db.sync) == "table" and ns.db.sync or {}
    local d = ns.db.sync
    d.facts = type(d.facts) == "table" and d.facts or {}        -- [fact] = true
    d.order = type(d.order) == "table" and d.order or {}        -- facts, oldest first (for the cap)
    d.history = type(d.history) == "table" and d.history or {}  -- { { seq, hash }, ... }
    d.dev = type(d.dev) == "table" and d.dev or {}              -- developer commits learned: [seq] = hash
    return d
end

local function Enabled()
    return C.Enabled() or C.Collecting()
end

local function BucketOf(fact)
    return tonumber(Hash(fact):sub(1, 1), 16) + 1
end

local cache -- { root, buckets = { hash per bucket }, lists = { facts per bucket } }

local function State()
    if cache then return cache end
    local lists = {}
    for b = 1, BUCKETS do lists[b] = {} end
    for fact in pairs(DB().facts) do
        local list = lists[BucketOf(fact)]
        list[#list + 1] = fact
    end
    local hashes = {}
    for b = 1, BUCKETS do
        table.sort(lists[b])
        hashes[b] = Hash(table.concat(lists[b], "\n")):sub(1, 8)
    end
    cache = { root = Hash(table.concat(hashes)), buckets = hashes, lists = lists }
    return cache
end

function S:Root() return State().root end

function S:Count()
    local n = 0
    for _ in pairs(DB().facts) do n = n + 1 end
    return n
end

local commitPending = false
local Recheck -- (below: looks for peers still ahead of us)

local function Commit()
    commitPending = false
    local d = DB()
    local last = d.history[#d.history]
    local root = State().root
    if last and last.root == root then return end
    local seq = (last and last.seq or 0) + 1
    local hash = Hash((last and last.hash or "") .. root)
    d.history[#d.history + 1] = { seq = seq, hash = hash, root = root }
    while #d.history > MAX_HISTORY do table.remove(d.history, 1) end
    -- The developer's commits are the version 2 history: announce them.
    if C.Collecting() then
        d.dev[seq] = hash
        C.Send("DC " .. seq .. " " .. hash)
    end
    -- Report the new state, so out-of-date clients come and pull.
    S:Announce()
    Recheck()
end

-- Adds a fact (well formed, new); true when it was new.
function S:Add(fact)
    if not (Enabled() and C.Valid(fact)) then return false end
    local d = DB()
    if d.facts[fact] then return false end
    d.facts[fact] = true
    d.order[#d.order + 1] = fact
    while #d.order > MAX_FACTS do
        d.facts[table.remove(d.order, 1)] = nil
    end
    cache = nil
    if not commitPending then
        commitPending = true
        C_Timer.After(COMMIT_AFTER, Commit)
    end
    return true
end

---------------------------------------------------------------------------
-- Trust
---------------------------------------------------------------------------

-- The shared history, as { [position] = hash }, and the positions a
-- challenge may name.
local function Pool()
    if SIMPLE_TRUST then
        local pool, positions = {}, {}
        for i, h in ipairs(ns.Anchors and ns.Anchors.seeds or {}) do
            pool[i] = h
            positions[#positions + 1] = i
        end
        return pool, positions
    end
    local pool = {}
    for seq, h in pairs(ns.Anchors and ns.Anchors.dev or {}) do pool[tonumber(seq)] = h end
    for seq, h in pairs(DB().dev) do pool[tonumber(seq)] = h end
    local seqs = {}
    for seq in pairs(pool) do seqs[#seqs + 1] = seq end
    table.sort(seqs, function(a, b) return a > b end)
    local positions = {}
    for i = 1, math.min(RECENT, #seqs) do positions[i] = seqs[i] end
    return pool, positions
end

local trust = {}       -- [peer] = true, false or a pending challenge { nonce, positions, at }
local lastRoot = {}    -- [peer] = the state it last announced
local lastCount = {}   -- [peer] = how many facts it said it has
local Differs          -- (below)
local me

local function Me()
    if not me then
        local realm = GetNormalizedRealmName and GetNormalizedRealmName()
        me = UnitName("player") .. (realm and ("-" .. realm) or "")
    end
    return me
end

local function IsMe(name)
    return name == Me() or name == UnitName("player")
end

local function Short(name)
    return (name or ""):match("^[^%-]+") or name
end

local function ForMe(target)
    return target == Me() or Short(target) == UnitName("player")
end

local function Proof(nonce, position, hash)
    return Hash(nonce .. ":" .. position .. ":" .. hash):sub(1, 8)
end

function S:Challenge(peer)
    if type(trust[peer]) == "boolean" then return end
    local pending = trust[peer]
    if type(pending) == "table" and GetTime() - pending.at < 60 then return end
    local _, positions = Pool()
    if #positions < 3 then return end
    local picks, used = {}, {}
    while #picks < 3 do
        local p = positions[math.random(#positions)]
        if not used[p] then
            used[p] = true
            picks[#picks + 1] = p
        end
    end
    local nonce = string.format("%08x", math.random(0, 2147483647))
    trust[peer] = { nonce = nonce, positions = picks, at = GetTime() }
    C.Send("CH " .. peer .. " " .. nonce .. " " .. table.concat(picks, ","))
end

local function Answer(peer, nonce, list)
    local pool = Pool()
    local out = {}
    for p in list:gmatch("[^,]+") do
        local h = pool[tonumber(p)]
        out[#out + 1] = h and Proof(nonce, p, h) or "-"
    end
    C.Send("RS " .. peer .. " " .. nonce .. " " .. table.concat(out, ","))
end

local function Check(peer, nonce, list)
    local pending = trust[peer]
    if type(pending) ~= "table" or pending.nonce ~= nonce then return end
    local pool = Pool()
    local i, good = 0, 0
    for proof in list:gmatch("[^,]+") do
        i = i + 1
        local p = pending.positions[i]
        if p and pool[p] and proof == Proof(nonce, tostring(p), pool[p]) then good = good + 1 end
    end
    trust[peer] = good >= (SIMPLE_TRUST and 3 or NEEDED)
    if trust[peer] then
        Differs(peer, lastRoot[peer])
        -- Version 2: catch up on developer commits we missed.
        if not SIMPLE_TRUST then
            local newest = 0
            for seq in pairs(DB().dev) do newest = math.max(newest, tonumber(seq)) end
            C.Send("DQ " .. peer .. " " .. newest)
        end
    end
end

function S:Trusted(peer)
    return trust[peer] == true
end

---------------------------------------------------------------------------
-- Gossip
---------------------------------------------------------------------------

local session -- { peer, at }
local replying     -- a reply to a HELLO is waiting
local heardRoots = {} -- states announced while a reply waits

function S:Announce()
    if not Enabled() then return end
    C.Send("ROOT " .. State().root .. " " .. self:Count())
end

local function Busy()
    return session and GetTime() - session.at < SESSION
end

local function Pull(peer)
    local this = { peer = peer, at = GetTime() }
    session = this
    C.Send("BK? " .. peer)
    -- Out of time: let another pull start, and look again.
    C_Timer.After(SESSION, function()
        if session == this then session = nil end
        Recheck()
    end)
end

-- A differing state from a trusted peer that has something: pull from it.
-- One peer at a time, but the peer we're pulling from may always be asked
-- again (it has moved on).
function Differs(peer, root)
    if not (root and root ~= State().root and S:Trusted(peer)) then return end
    if (lastCount[peer] or 1) == 0 then return end
    if Busy() and session.peer ~= peer then return end
    Pull(peer)
end

-- After a pull (or a commit): any trusted peer whose last announced state
-- still differs from ours? Pull from the first. No announcement is ever
-- missed this way, though we only ask once, at login.
function Recheck()
    if Busy() then return end
    for peer, root in pairs(lastRoot) do
        if root ~= State().root and S:Trusted(peer) and (lastCount[peer] or 1) > 0 then
            return Pull(peer)
        end
    end
end

-- Someone logged in and asked: answer after a while, unless someone else
-- already announced the same state as ours.
local function ReplyLater()
    if replying then return end
    replying = true
    heardRoots = {}
    C_Timer.After(math.random(2, REPLY_DELAY), function()
        replying = false
        if not heardRoots[State().root] then S:Announce() end
    end)
end

local function Handle(msg, sender)
    if not Enabled() or not sender or IsMe(sender) then return end
    local word, rest = msg:match("^(%S+)%s?(.*)$")
    if word == "ROOT" or word == "HELLO" then
        local root, count = rest:match("^(%x+) (%d+)")
        if root then
            heardRoots[root] = true
            lastRoot[sender] = root
            lastCount[sender] = tonumber(count)
        end
        if word == "HELLO" then ReplyLater() end
        if trust[sender] == nil or type(trust[sender]) == "table" then return S:Challenge(sender) end
        Differs(sender, root)
    elseif word == "CH" then
        local target, nonce, list = rest:match("^(%S+) (%x+) ([%d,]+)$")
        if target and ForMe(target) then Answer(sender, nonce, list) end
    elseif word == "RS" then
        local target, nonce, list = rest:match("^(%S+) (%x+) (%S+)$")
        if target and ForMe(target) then Check(sender, nonce, list) end
    elseif not S:Trusted(sender) then
        -- Untrusted peers are only challenged (when they announce), never listened to.
        return
    elseif word == "BK?" then
        if ForMe(rest) then C.Send("BK " .. sender .. " " .. table.concat(State().buckets)) end
    elseif word == "BK" then
        -- Bucket hashes, ours to ask for or someone else's sync: either way,
        -- pull the buckets where this peer's state differs from ours.
        local target, hashes = rest:match("^(%S+) (%x+)$")
        if not (target and #hashes == BUCKETS * 8) then return end
        local mine = State().buckets
        local ours = ForMe(target) and session and session.peer == sender
        if not ours then
            if Busy() then return end
            session = { peer = sender, at = GetTime() }
        end
        local any = false
        for b = 1, BUCKETS do
            if hashes:sub(b * 8 - 7, b * 8) ~= mine[b] then
                C.Send("GET " .. sender .. " " .. b)
                any = true
            end
        end
        if not any then
            session = nil
            Recheck()
        end
    elseif word == "GET" then
        local target, b = rest:match("^(%S+) (%d+)$")
        b = tonumber(b)
        if target and ForMe(target) and b and b >= 1 and b <= BUCKETS then
            for _, fact in ipairs(State().lists[b]) do C.Send("FX " .. fact) end
        end
    elseif word == "FX" then
        -- Facts a trusted peer sends are merged, whoever asked for them.
        S:Add(rest)
    elseif word == "DC" and not SIMPLE_TRUST then
        local seq, hash = rest:match("^(%d+) (%x+)$")
        seq = tonumber(seq)
        local d = DB()
        if seq and hash and #hash == 16 and not d.dev[seq] then
            d.dev[seq] = hash
            C.Send("DC " .. seq .. " " .. hash) -- pass it on
        end
    elseif word == "DQ" and not SIMPLE_TRUST then
        local target, from = rest:match("^(%S+) (%d+)$")
        if target and ForMe(target) then
            local d, sent = DB(), 0
            local seqs = {}
            for seq in pairs(d.dev) do if tonumber(seq) > tonumber(from) then seqs[#seqs + 1] = tonumber(seq) end end
            table.sort(seqs, function(a, b) return a > b end)
            for i = 1, math.min(RECENT, #seqs) do
                C.Send("DC " .. seqs[i] .. " " .. d.dev[seqs[i]])
                sent = sent + 1
            end
        end
    end
end
table.insert(C.handlers, Handle)

-- A new SpyGlass version ships what was gathered so far. The first time it
-- loads, the discoveries we hold that it still doesn't know are queued for
-- the developer (and the player is told how many), then the old set and its
-- history are dropped: syncing starts over from the release.
local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
function S:CheckRelease()
    local d = DB()
    local version = GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version") or "?"
    if d.release == version then return end
    if d.release ~= nil and next(d.facts) then
        local missing = 0
        for fact in pairs(d.facts) do
            if not C.KnownFact(fact) then
                C.Queue(fact)
                missing = missing + 1
            end
        end
        ns:Print(string.format("SpyGlass %s: %d of your shared discoveries aren't in this version yet; "
            .. "they'll be passed on. Sharing starts over from this version.", version, missing))
        d.facts, d.order, d.history = {}, {}, {}
        cache = nil
    end
    d.release = version
end

-- At login (or when turned on): announce our state and ask everyone for
-- theirs, once. After that we only watch and report.
local asked = false
function S:Apply()
    if Enabled() and not asked then
        asked = true
        C_Timer.After(15 + math.random(0, 15), function()
            if Enabled() then C.Send("HELLO " .. State().root .. " " .. S:Count()) end
        end)
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    S:CheckRelease()
    S:Apply()
end)

-- /sg sync [status]
function S:Status()
    local d = DB()
    local trusted, total = 0, 0
    for _, t in pairs(trust) do
        total = total + 1
        if t == true then trusted = trusted + 1 end
    end
    local devKnown = 0
    for _ in pairs(Pool()) do devKnown = devKnown + 1 end
    local last = d.history[#d.history]
    ns:Print(string.format("Sync %s (trust: %s). State %s, %d facts, %d commits (latest #%s). "
        .. "Peers: %d trusted of %d seen. Shared history known: %d.",
        Enabled() and "on" or "off (turn on Contribute data)", SIMPLE_TRUST and "version 1, seed hashes"
            or "version 2, developer history", State().root, self:Count(), #d.history,
        last and last.seq or "-", trusted, total, devKnown))
end

-- For tests and tools.
S.SIMPLE_TRUST = function() return SIMPLE_TRUST end
S.Commit = Commit
