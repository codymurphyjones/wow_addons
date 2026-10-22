local _, ns = ...
local C = ns.Compat

-- Feedback between players, over private addon messages (shared\GroupComm.lua, prefix FiresideFB).
-- Praise in public, critique in private:
--   Kudos   go to the whole party ("G"): everyone running Fireside sees them land at the
--           campfire, and remembers them as testimony about that player. Off the group, they go to
--           the player alone (addon whisper).
--   Tips    go to the player alone, never anyone else ("L", addon whisper), always as a pair: a kudo
--           to keep and one thing to try. They're acknowledged ("A"); one that isn't is sent again
--           the next time you group with them.
--   Cards   When someone new joins your party, each Fireside tells the party what kudos it has
--           given the others ("C", testimony) and what its own player has received ("B", their own
--           record). Nothing negative is ever in a card.
--   Thanks  ("T") and progress ("P"): you can thank someone for feedback, and when a tip sticks
--           (Marks.STUCK clean runs in a row) the giver hears about it.
-- Your received feedback is per character (ns.char.fb); what you know of others is on their record.
local F = {}
ns.Feedback = F

local Clean = ns.GroupComm.Clean
local Split = ns.GroupComm.Split
local M = ns.Marks

local comm = ns.NewGroupComm("FiresideFB", { pace = 0.3, raids = false, normalize = C.Canon, isMe = ns.Units.IsMe })
F.comm = comm

local FEED_KEEP = 100
local RETRIES = 5
local LIVE = 45 * 60 -- a finished run's campfire still takes kudos this long

local function Me() return C.UnitFull("player") end
local function Wire(name) return ns.Units.Wire(name) or Clean(name, "[|;,=:]") end

function F.DB()
    local fb = ns.char.fb
    if type(fb) ~= "table" then fb = {}; ns.char.fb = fb end
    for _, k in ipairs({ "received", "letters", "sent", "feed", "sparks" }) do
        if type(fb[k]) ~= "table" then fb[k] = {} end
    end
    return fb
end

local function Feed(kind, text, extra)
    local feed = F.DB().feed
    local e = { t = time(), kind = kind, text = text }
    for k, v in pairs(extra or {}) do e[k] = v end
    table.insert(feed, e)
    while #feed > FEED_KEEP do table.remove(feed, 1) end
end

local function NewID()
    return ("%x%04x"):format(time(), math.random(0, 0xffff))
end

-- ---------------------------------------------------------------------------
-- The campfire's run: the one in progress, or the last one for a while after it ends
-- ---------------------------------------------------------------------------

function F.LiveRun()
    local run = ns.Run.current
    if run then return run end
    local last = ns.db.runs[#ns.db.runs]
    if last and last.stop and time() - last.stop <= LIVE then return last end
end

-- The run's member key for a name (any shape), or the run's "me".
local function MemberOf(run, name)
    if not (run and name) then return nil end
    if run.me and C.SameName(run.me, name) then return run.me end
    for full in pairs(run.members or {}) do
        if C.SameName(full, name) then return full end
    end
end
F.MemberOf = MemberOf

-- Kudos in a run, as { from, to, k, t }; one per giver, receiver and kudo.
local function HasKudo(run, from, to, k)
    for _, e in ipairs(run.kudos or {}) do
        if e.k == k and C.SameName(e.from, from) and C.SameName(e.to, to) then return true end
    end
    return false
end

-- Kudos a member got in a run, by kudo: { [k] = { givers } }.
function F.KudosIn(run, to)
    local out = {}
    for _, e in ipairs(run and run.kudos or {}) do
        if C.SameName(e.to, to) then
            out[e.k] = out[e.k] or {}
            table.insert(out[e.k], e.from)
        end
    end
    return out
end

-- What you've given a member in a run: { [k] = true }.
function F.GivenIn(run, to)
    local out = {}
    for _, e in ipairs(run and run.kudos or {}) do
        if C.IsMe(e.from) and C.SameName(e.to, to) then out[e.k] = true end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Receiving kudos (yours, or testimony about someone else)
-- ---------------------------------------------------------------------------

local function ReceiveMine(from, k)
    local r = F.DB().received
    local e = r[k]
    if type(e) ~= "table" then e = { n = 0, g = {} }; r[k] = e end
    e.n = e.n + 1
    local key = ns.History:Key(from) or from
    e.g[key] = (e.g[key] or 0) + 1
    Feed("kudo", ("%s gave you %s %s"):format(from, M.Icon(k), M.Label(k)), { from = key, k = k })
end

local function Heard(giver, to, k, n)
    local p = ns.History:Get(to, true)
    if not p then return end
    p.heard = p.heard or {}
    local key = ns.History:Key(giver) or giver
    local h = p.heard[key]
    if type(h) ~= "table" then h = { marks = {} }; p.heard[key] = h end
    h.marks[k] = n or ((h.marks[k] or 0) + 1)
    h.t = time()
end

-- A kudo given at the campfire, by anyone (you included): on the run, on records, on screen.
local function Landed(run, from, to, k)
    if run then
        run.kudos = run.kudos or {}
        if HasKudo(run, from, to, k) then return false end
        table.insert(run.kudos, { from = from, to = to, k = k, t = time() })
    end
    if C.IsMe(to) then
        ReceiveMine(from, k)
        if ns.db.options.chat ~= false then
            ns:Print(("%s gave you %s |cffffffff%s|r."):format(C.Colored(from, nil), M.Icon(k), M.Label(k)))
        end
    elseif not C.IsMe(from) then
        Heard(from, to, k)
    end
    if ns.Campfire then ns.Campfire:Fly(run, from, to, k) end
    ns:Changed()
    return true
end

-- You give a kudo. false (and why) when it can't be given.
function F:Give(run, to, k)
    if not (M.kudo[k] and to) then return false, "unknown" end
    if C.IsMe(to) then return false, "self" end
    run = run or F.LiveRun()
    local key = MemberOf(run, to) or to
    if run and HasKudo(run, Me(), key, k) then return false, "given" end
    local p = ns.History:Get(key, true)
    p.given = p.given or {}
    p.given[k] = (p.given[k] or 0) + 1
    Landed(run, Me(), key, k)
    local payload = ("%s|%s"):format(Wire(key), k)
    if C.InGroup(key) then comm:Send("G", payload) else comm:SendTo("G", payload, key) end
    return true
end

comm:On("G", function(payload, sender)
    local to, k = payload:match("^([^|]+)|(%w+)$")
    if not (to and M.kudo[k]) or C.SameName(to, sender) then return end
    local run = F.LiveRun()
    local from = MemberOf(run, sender) or sender
    to = MemberOf(run, to) or (C.IsMe(to) and Me()) or ns.History:Key(to) or to
    -- Only kudos between people in the run (or for you, off the group) count for it.
    if not (run and MemberOf(run, from) and MemberOf(run, to)) then run = nil end
    if not run and not C.IsMe(to) and not C.InGroup(to) then return end
    Landed(run, from, to, k)
end)

-- ---------------------------------------------------------------------------
-- Sparks: small thanks in the moment ("S", to the party)
-- ---------------------------------------------------------------------------

local SPARK_GAP = 15   -- seconds before you can send the same spark to the same person again
local SPARK_FLOOD = 4  -- the same spark from the same sender to the same person counts once this often
local SPARKS_KEEP = 400
local lastSpark = {}   -- "from>to>spark" -> GetTime()

-- Sparks a member got in a run: { [spark] = { givers... } }.
function F.SparksIn(run, to)
    local out = {}
    for _, e in ipairs(run and run.sparks or {}) do
        if C.SameName(e.to, to) then
            out[e.s] = out[e.s] or {}
            table.insert(out[e.s], e.from)
        end
    end
    return out
end

local function SparkLanded(run, from, to, s)
    if run then
        run.sparks = run.sparks or {}
        table.insert(run.sparks, { from = from, to = to, s = s, t = time() })
        while #run.sparks > SPARKS_KEEP do table.remove(run.sparks, 1) end
    end
    if C.IsMe(to) then
        local r = F.DB().sparks
        r[s] = (r[s] or 0) + 1
    end
    if ns.Hearth then ns.Hearth:OnSpark(from, to, s) end
    if ns.Campfire then ns.Campfire:Fly(run, from, to, s, true) end
    ns:Changed()
end

local function Flooding(from, to, s, gap)
    local key = ("%s>%s>%s"):format(ns.Units.Compact(from) or "?", ns.Units.Compact(to) or "?", s)
    local now = GetTime()
    if lastSpark[key] and now - lastSpark[key] < gap then return true end
    lastSpark[key] = now
    return false
end

-- You send a spark. false (and why) when it can't go.
function F:Spark(to, s)
    if not (M.spark[s] and to) then return false, "unknown" end
    if C.IsMe(to) then return false, "self" end
    local run = F.LiveRun()
    local key = MemberOf(run, to) or to
    if Flooding(Me(), key, s, SPARK_GAP) then return false, "soon" end
    SparkLanded(run, Me(), key, s)
    local payload = ("%s|%s"):format(Wire(key), s)
    if C.InGroup(key) then comm:Send("S", payload) else comm:SendTo("S", payload, key) end
    return true
end

comm:On("S", function(payload, sender)
    local to, s = payload:match("^([^|]+)|(%w+)$")
    if not (to and M.spark[s]) or C.SameName(to, sender) then return end
    local run = F.LiveRun()
    local from = MemberOf(run, sender) or sender
    to = MemberOf(run, to) or (C.IsMe(to) and Me()) or ns.History:Key(to) or to
    if not (run and MemberOf(run, from) and MemberOf(run, to)) then run = nil end
    if not run and not C.IsMe(to) and not C.InGroup(to) then return end
    if Flooding(from, to, s, SPARK_FLOOD) then return end
    SparkLanded(run, from, to, s)
end)

-- ---------------------------------------------------------------------------
-- Jots: your own notes about someone, in the moment (private, never sent)
-- ---------------------------------------------------------------------------

local JOTS_KEEP = 50
F.MAX_JOT = 140

-- A note to yourself about a player, tied to the run you're in (if any). They wait at the campfire.
function F:Jot(to, text)
    text = ns.Trim(text or ""):sub(1, F.MAX_JOT)
    if text == "" or not to or C.IsMe(to) then return false end
    local run = F.LiveRun()
    local key = MemberOf(run, to) or ns.History:Key(to) or to
    local p = ns.History:Get(key, true)
    p.jots = p.jots or {}
    table.insert(p.jots, { t = time(), text = text, run = run and run.id })
    while #p.jots > JOTS_KEEP do table.remove(p.jots, 1) end
    ns:Changed()
    return true
end

-- Your jots about a member during a run, oldest first.
function F.JotsIn(run, to)
    local p = run and to and ns.History:Get(to)
    local out = {}
    for _, j in ipairs(p and p.jots or {}) do
        if j.run == run.id then out[#out + 1] = j end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Cards: testimony and their own record, when the party changes
-- ---------------------------------------------------------------------------

-- "to=k:n,k:n;to=..." for the kudos you've given the people in your group.
local function Card()
    local parts = {}
    for _, unit in ipairs(C.GroupUnits()) do
        local full = C.UnitFull(unit)
        local p = full and ns.History:Get(full)
        if p and p.given then
            local marks = {}
            for k, n in pairs(p.given) do
                if M.kudo[k] and n > 0 then marks[#marks + 1] = k .. ":" .. n end
            end
            if #marks > 0 then parts[#parts + 1] = Wire(full) .. "=" .. table.concat(marks, ",") end
        end
    end
    return table.concat(parts, ";")
end

-- "k:n:g,..." for the kudos you've received (n kudos from g people).
local function Banner()
    local marks = {}
    for k, e in pairs(F.DB().received) do
        if M.kudo[k] and type(e) == "table" then
            local g = 0
            for _ in pairs(e.g or {}) do g = g + 1 end
            marks[#marks + 1] = ("%s:%d:%d"):format(k, e.n or 0, g)
        end
    end
    return table.concat(marks, ",")
end

function F:ShareCards()
    if not IsInGroup() or IsInRaid() then return end
    local o = ns.db.options
    if o.shareKudos ~= false then
        local card = Card()
        if card ~= "" then comm:Send("C", card) end
    end
    if o.shareBanner ~= false then
        local banner = Banner()
        if banner ~= "" then comm:Send("B", banner) end
    end
end

comm:On("C", function(payload, sender)
    for entry in payload:gmatch("[^;]+") do
        local to, marks = entry:match("^([^=]+)=(.+)$")
        if to and not C.IsMe(to) and not C.SameName(to, sender) then
            local key = MemberOf(F.LiveRun(), to) or ns.History:Key(to) or to
            local p = ns.History:Get(key, true)
            if p then
                p.heard = p.heard or {}
                local h = { marks = {}, t = time() }
                for k, n in marks:gmatch("(%w+):(%d+)") do
                    if M.kudo[k] then h.marks[k] = math.min(tonumber(n), 99) end
                end
                p.heard[ns.History:Key(sender) or sender] = h
            end
        end
    end
    ns:Changed()
end)

comm:On("B", function(payload, sender)
    local p = ns.History:Get(MemberOf(F.LiveRun(), sender) or sender, true)
    if not p then return end
    local b = { marks = {}, t = time() }
    for k, n, g in payload:gmatch("(%w+):(%d+):(%d+)") do
        if M.kudo[k] then b.marks[k] = { n = math.min(tonumber(n), 9999), g = math.min(tonumber(g), 999) } end
    end
    p.banner = b
    ns:Changed()
end)

-- ---------------------------------------------------------------------------
-- Tips: keep / try letters, private
-- ---------------------------------------------------------------------------

local function LetterPayload(id, s)
    return table.concat({ id, s.keep, s.try or "", Clean(s.note or "", "[|\n]", " ", M.MAX_NOTE), Clean(s.instance or "", "|", "/", 60) }, "|")
end

-- A note needs something to say: a tip to try, your own words, or both.
local function Says(try, note)
    return (try and M.tip[try]) or (not try and note and note ~= "")
end

-- The tip you've sent a member for a run, if any.
function F.TipIn(run, to)
    local id = run and run.tips and ns.History.ByName(run.tips, to)
    return id and F.DB().sent[id], id
end

-- You leave someone a private note: a kudo to keep (also given as a public kudo) with a tip to
-- try, your own words, or both. try may be nil when there are words.
function F:SendTip(run, to, keep, try, note)
    note = ns.Trim(note or ""):sub(1, M.MAX_NOTE)
    if try == "" then try = nil end
    if not (M.kudo[keep] and to and Says(try, note)) or C.IsMe(to) then return false end
    run = run or F.LiveRun()
    local key = MemberOf(run, to) or to
    if run and F.TipIn(run, key) then return false end
    self:Give(run, key, keep)
    local id = NewID()
    local s = { to = key, keep = keep, try = try, note = note, t = time(), instance = run and run.instance, tries = 1 }
    if s.note == "" then s.note = nil end
    F.DB().sent[id] = s
    if run then
        run.tips = run.tips or {}
        run.tips[key] = id
    end
    comm:SendTo("L", LetterPayload(id, s), key)
    ns:Changed()
    return true
end

-- Tips not acknowledged yet go again when their player is in your group.
local function Resend()
    for id, s in pairs(F.DB().sent) do
        if not s.acked and (s.tries or 0) < RETRIES and C.InGroup(s.to) then
            s.tries = (s.tries or 0) + 1
            comm:SendTo("L", LetterPayload(id, s), s.to)
        end
    end
end

comm:On("L", function(payload, sender)
    local f = Split(payload)
    local id, keep, try, note, instance = f[1], f[2], f[3], f[4], f[5]
    if try == "" then try = nil end
    if note == "" then note = nil end
    if not (id and id:match("^%x+$") and M.kudo[keep] and Says(try, note)) then return end
    local from = ns.History:Key(sender) or sender
    if ns.db.options.acceptTips == false then return comm:SendTo("A", id .. "|closed", sender) end
    local letters = F.DB().letters
    if not letters[id] then
        letters[id] = { from = from, keep = keep, try = try, note = note,
            instance = (instance and instance ~= "") and instance or nil, t = time(), new = true }
        Feed("letter", ("%s left you a note: keep %s%s"):format(from, M.Label(keep),
            try and (", try \"" .. M.Label(try) .. "\"") or ""), { id = id, from = from })
        if ns.db.options.chat ~= false then
            ns:Print(("%s left you a private note (only you can see it). |cffffffff/fire mirror|r to read it."):format(from))
        end
        ns:Changed()
    end
    comm:SendTo("A", id .. "|ok", sender)
end)

comm:On("A", function(payload, sender)
    local id, status = payload:match("^(%x+)|(%a+)$")
    local s = id and F.DB().sent[id]
    if not (s and C.SameName(s.to, sender)) then return end
    s.acked = status == "closed" and "closed" or true
    ns:Changed()
end)

-- How many notes you haven't opened yet.
function F.Unread()
    local n = 0
    for _, l in pairs(F.DB().letters) do if l.new then n = n + 1 end end
    return n
end

function F.MarkRead()
    for _, l in pairs(F.DB().letters) do l.new = nil end
    ns:Changed()
end

-- ---------------------------------------------------------------------------
-- Thanks and progress
-- ---------------------------------------------------------------------------

-- Thank someone for a note (id) or for a kudo (k).
function F:Thank(to, id, k)
    if id then
        local l = F.DB().letters[id]
        if not l or l.thanked then return end
        l.thanked = time()
        comm:SendTo("T", id, to)
    elseif k then
        local r = F.DB().received[k]
        if not r then return end
        r.thanked = r.thanked or {}
        if r.thanked[to] then return end
        r.thanked[to] = time()
        comm:SendTo("T", "k:" .. k, to)
    end
    ns:Changed()
end

comm:On("T", function(payload, sender)
    local from = ns.History:Key(sender) or sender
    local k = payload:match("^k:(%w+)$")
    if k and M.kudo[k] then
        Feed("thanks", ("%s thanked you for %s %s"):format(from, M.Icon(k), M.Label(k)), { from = from })
    else
        local s = F.DB().sent[payload]
        if not (s and C.SameName(s.to, sender)) or s.thanked then return end
        s.thanked = time()
        Feed("thanks", s.try and ("%s thanked you for your tip: \"%s\""):format(from, M.Label(s.try))
            or ("%s thanked you for your note"):format(from), { from = from, id = payload })
    end
    ns:Changed()
end)

-- After each run: tips that stuck tell their giver (once).
function F:CheckPractice()
    for id, l in pairs(F.DB().letters) do
        if not l.stuck then
            local pr = M.Practice(l.try, l.t)
            if pr and pr.streak >= M.STUCK then
                l.stuck = time()
                Feed("stuck", ("Your practice on \"%s\" stuck: %d clean runs in a row"):format(M.Label(l.try), pr.streak), { id = id })
                comm:SendTo("P", ("%s|%d|%d"):format(id, pr.clean, pr.runs), l.from)
            end
        end
    end
end

comm:On("P", function(payload, sender)
    local id, clean, runs = payload:match("^(%x+)|(%d+)|(%d+)$")
    local s = id and F.DB().sent[id]
    if not (s and C.SameName(s.to, sender)) or s.progress then return end
    s.progress = { clean = tonumber(clean), runs = tonumber(runs), t = time() }
    local from = ns.History:Key(sender) or sender
    Feed("ripple", ("Your tip helped %s: \"%s\" - %s clean of %s runs since"):format(from, M.Label(s.try), clean, runs), { from = from, id = id })
    if ns.db.options.chat ~= false then
        ns:Print(("Your tip to %s stuck: \"%s\", %s clean runs since. |cffffffff/fire mirror|r"):format(from, M.Label(s.try), clean))
    end
    ns:Changed()
end)

-- ---------------------------------------------------------------------------
-- The party changing
-- ---------------------------------------------------------------------------

local inParty = {}
local pending
ns:On("GROUP_ROSTER_UPDATE", function()
    if pending then return end
    pending = true
    C_Timer.After(2, function()
        pending = false
        -- (Queued whispers, like a tip to someone who just left, still go out.)
        if not IsInGroup() or IsInRaid() then wipe(inParty); return end
        local newcomer = false
        local now = {}
        for _, unit in ipairs(C.GroupUnits()) do
            local full = C.UnitFull(unit)
            if full then
                now[full] = true
                if not inParty[full] then newcomer = true end
            end
        end
        inParty = now
        if newcomer then
            F:ShareCards()
            Resend()
        end
    end)
end)

ns:OnLoad(function() F.DB() end)
