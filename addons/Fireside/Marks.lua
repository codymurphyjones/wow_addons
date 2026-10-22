local _, ns = ...
local C = ns.Compat

-- The words feedback is given in. There are no scores and no thumbs down here: you tell people what
-- they did well (a kudo: public, your party sees it land and it travels with them as testimony) or
-- one thing to try next time (a tip: private, only that player ever sees it, and only together with
-- a kudo, as a "keep / try" pair). Both are fixed phrases, so feedback stays about what someone did,
-- never about who they are. A tip that matches a blame reason (History.lua's tags) can be practised:
-- the Mirror counts your runs since the tip without that reason, and tells the giver when it stuck.
local M = {}
ns.Marks = M

M.KUDOS = {
    { id = "steady", label = "Steady tank", icon = "Ability_Defend", roles = { tank = true }, says = "Held the mobs where they belonged." },
    { id = "pulls", label = "Clean pulls", icon = "Ability_Warrior_Charge", roles = { tank = true }, says = "Pulled at a pace the group could take." },
    { id = "saved", label = "Saved me", icon = "Spell_Holy_FlashHeal", says = "Turned a death into a close call." },
    { id = "kept", label = "Kept us up", icon = "Spell_Holy_Renew", roles = { healer = true }, says = "Healing that held through the hard pulls." },
    { id = "kicks", label = "Quick kicks", icon = "Ability_Kick", says = "Stopped the casts that mattered." },
    { id = "cc", label = "Crowd control", icon = "Spell_Nature_Polymorph", says = "Kept the extra mobs out of the fight." },
    { id = "damage", label = "Brought the damage", icon = "INV_Sword_04", roles = { damage = true }, says = "Fights ended fast." },
    -- Given by hand only, to anyone in any role: the campfire never suggests these (Moments.lua),
    -- because only the people there can judge them (damage numbers, for one, need context).
    { id = "highdamage", label = "High damage", icon = "Ability_Warrior_Cleave", says = "Hit hard." },
    { id = "buffs", label = "Kept us buffed", icon = "Spell_Holy_WordFortitude", says = "Buffs up before the pulls, for everyone." },
    { id = "prepared", label = "Came prepared", icon = "INV_Potion_51", says = "Brought food, water, potions and reagents." },
    { id = "turnaround", label = "Clutch play", icon = "Ability_Warrior_Revenge", says = "Turned a fight that was going wrong." },
    { id = "guide", label = "Knew the way", icon = "INV_Misc_Map_01", says = "Led the group the right way through." },
    { id = "calls", label = "Good target calls", icon = "Ability_Hunter_SniperShot", says = "Marked targets and called the kills." },
    { id = "aware", label = "Stayed out of fire", icon = "Ability_Rogue_Sprint", says = "Moved out of what hurts." },
    { id = "calm", label = "Calm after a wipe", icon = "Spell_Holy_MindVision", says = "Kept the mood up when it went wrong." },
    { id = "teach", label = "Explained the fights", icon = "INV_Misc_Book_09", says = "Shared what they knew before the pull." },
    { id = "patient", label = "Patient with newcomers", icon = "Spell_Holy_Heal", says = "Made new players welcome." },
    { id = "lead", label = "Led well", icon = "INV_Banner_02", says = "Kept the group moving and together." },
    { id = "fair", label = "Fair with loot", icon = "INV_Misc_Coin_01", says = "Rolled and shared fairly." },
    { id = "fun", label = "Great company", icon = "INV_Drink_04", says = "Made the run fun." },
}

-- tag: History.lua's reason tag the tip answers (what the Mirror watches for).
M.TIPS = {
    { id = "threat", label = "Let the tank build threat before opening up", tag = "pulling threat", roles = { damage = true, healer = true } },
    { id = "fire", label = "Step out of ground effects sooner", tag = "standing in avoidable damage" },
    { id = "loose", label = "Pick up loose mobs before they reach the healer", tag = "losing aggro", roles = { tank = true } },
    { id = "smaller", label = "Smaller pulls while the group warms up", tag = "over-pulling", roles = { tank = true } },
    { id = "wait", label = "Wait for the tank to pull", tag = "pulling early", roles = { damage = true, healer = true } },
    { id = "spread", label = "Spread healing across the whole group", tag = "low healing", roles = { healer = true } },
    { id = "kick", label = "Watch for casts to interrupt", tag = "missed interrupts" },
    { id = "mana", label = "Call out when you need to drink" },
    { id = "pace", label = "Slow down a little so everyone keeps up" },
    { id = "talk", label = "Say the plan before a pull" },
    { id = "loot", label = "Agree on loot rules at the start" },
}

-- Sparks: the small thanks of the moment, sent during the run from the Hearth (Hearth.lua) with one
-- click. They light up on that player for the whole party, pile up on their seat at the campfire,
-- and point at the kudo they add up to (kudo). They're not reputation: only kudos are.
M.SPARKS = {
    { id = "pull", label = "Nice pull", icon = "Ability_Warrior_DefensiveStance", kudo = "pulls" },
    { id = "clutch", label = "Clutch heal", icon = "Spell_Holy_GreaterHeal", kudo = "saved" },
    { id = "kick", label = "Good kick", icon = "Ability_Kick", kudo = "kicks" },
    { id = "cc", label = "Good crowd control", icon = "Spell_Frost_ChainsOfIce", kudo = "cc" },
    { id = "cleanse", label = "Thanks for the cleanse", icon = "Spell_Holy_DispelMagic", kudo = "kept" },
    { id = "buff", label = "Thanks for the buff", icon = "Spell_Holy_WordFortitude", kudo = "fun" },
    { id = "rez", label = "Thanks for the rez", icon = "Spell_Holy_Resurrection", kudo = "saved" },
    { id = "summon", label = "Thanks for the summon", icon = "Spell_Shadow_Twilight", kudo = "lead" },
    { id = "wait", label = "Thanks for waiting", icon = "INV_Misc_PocketWatch_01", kudo = "patient" },
    { id = "quest", label = "Thanks for the quest", icon = "INV_Misc_Note_02", kudo = "patient" },
    { id = "call", label = "Good call", icon = "Ability_Warrior_BattleShout", kudo = "lead" },
}

-- Flak: what someone did that made the run worse, in fixed phrases (about what they did, never who
-- they are). Given by hand at the campfire, never suggested from the data. The giver chooses, each
-- time, whether to tell the player (privately) and whether to pass it on (other Fireside users they
-- group with later learn it, never the player). One Flak shows to nobody else: only a pattern does
-- (M.FlakReport).
M.FLAK = {
    { id = "early", label = "Pulled before the group was ready", icon = "Ability_Racial_BloodRage" },
    { id = "aggro", label = "Kept pulling aggro off the tank", icon = "Ability_Warrior_Sunder", roles = { damage = true, healer = true } },
    { id = "lost", label = "Kept losing the mobs", icon = "INV_Shield_06", roles = { tank = true } },
    { id = "noheal", label = "Healing didn't keep up", icon = "Spell_Holy_Heal02", roles = { healer = true } },
    { id = "bad", label = "Kept standing in what hurts", icon = "Spell_Fire_Fire" },
    { id = "plan", label = "Ignored the plan and the calls", icon = "Spell_Shadow_Possession" },
    { id = "afk", label = "Away for long stretches", icon = "Spell_Nature_Sleep" },
    { id = "left", label = "Left before the run was over", icon = "Ability_Rogue_Vanish" },
    { id = "loot", label = "Unfair with loot", icon = "INV_Misc_Coin_02" },
    { id = "rude", label = "Rude to the group", icon = "Ability_Warrior_WarCry" },
    { id = "unready", label = "Came unprepared", icon = "INV_Drink_07" },
}

M.kudo, M.tip, M.spark, M.flak = {}, {}, {}, {}
for _, k in ipairs(M.KUDOS) do M.kudo[k.id] = k end
for _, t in ipairs(M.TIPS) do M.tip[t.id] = t end
for _, s in ipairs(M.SPARKS) do M.spark[s.id] = s end
for _, f in ipairs(M.FLAK) do M.flak[f.id] = f end

function M.FlakIcon(id, size)
    size = size or 14
    local f = M.flak[id]
    return ("|TInterface\\Icons\\%s:%d:%d:0:0:64:64:5:59:5:59|t"):format(f and f.icon or "INV_Misc_QuestionMark", size, size)
end

function M.FlakLabel(id) return M.flak[id] and M.flak[id].label or id end

function M.SparkIconPath(id)
    local s = M.spark[id]
    return "Interface\\Icons\\" .. (s and s.icon or "INV_Misc_QuestionMark")
end

function M.SparkIcon(id, size)
    size = size or 14
    return ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t"):format(M.SparkIconPath(id), size, size)
end

M.MAX_NOTE = 80 -- characters in a tip's own words

function M.IconPath(id)
    local k = M.kudo[id]
    return "Interface\\Icons\\" .. (k and k.icon or "INV_Misc_QuestionMark")
end

-- "|T...|t" for chat and labels.
function M.Icon(id, size)
    size = size or 14
    return ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t"):format(M.IconPath(id), size, size)
end

function M.SparkLabel(id) return M.spark[id] and M.spark[id].label or id end

function M.Label(id)
    local k = M.kudo[id] or M.tip[id]
    return k and k.label or id
end

-- Whether a kudo or tip suits a role ("tank", "healer", "damage" or nil: any).
function M.Suits(entry, role)
    return not entry.roles or not role or entry.roles[role] or false
end

-- ---------------------------------------------------------------------------
-- Known for
-- ---------------------------------------------------------------------------

-- What a player is known for: every kudo for them that reached you, merged from four sources:
--   yours        p.given   = { [kudo] = n }
--   testimony    p.heard   = { [giver] = { marks = { [kudo] = n }, t } }  (sent by the givers' own Fireside)
--   gossip       p.reports = { [key] = { g, kind = "k", k, t, hand, via } }  (Feedback.lua: first-hand
--                or passed along by others; one giver's kudo counts once however it arrived)
--   their own    p.banner  = { marks = { [kudo] = { n, g } }, t }        (what their Fireside says they got)
-- A list, most givers first: { id, n, givers (people you know gave it), names, mine, carried (their
-- own count of givers), carriedN, trusted (n, second-hand from strangers counting half) }.
function M.KnownFor(full)
    local p = full and ns.History:Get(full)
    if not p then return {} end
    local by = {}
    local function E(id)
        if not M.kudo[id] then return nil end
        local e = by[id]
        if not e then e = { id = id, n = 0, givers = 0, names = {}, trusted = 0, from = {} }; by[id] = e end
        return e
    end
    -- One giver's count for a kudo, the highest any source says; trust 1, or 0.5 for hearsay.
    local function Giver(e, giver, n, trust)
        local had = e.from[giver]
        if had and had.n >= n then return end
        if had then
            e.n, e.trusted = e.n - had.n, e.trusted - had.n * had.trust
        else
            e.givers = e.givers + 1
            if giver ~= "you" then e.names[#e.names + 1] = giver end
        end
        e.from[giver] = { n = n, trust = trust }
        e.n, e.trusted = e.n + n, e.trusted + n * trust
    end
    for id, n in pairs(p.given or {}) do
        local e = type(n) == "number" and n > 0 and E(id)
        if e then e.mine = n; Giver(e, "you", n, 1) end
    end
    for giver, h in pairs(p.heard or {}) do
        for id, n in pairs(type(h) == "table" and h.marks or {}) do
            local e = type(n) == "number" and n > 0 and not C.IsMe(giver) and E(id)
            if e then Giver(e, giver, n, 1) end
        end
    end
    local counts = {} -- [id][giver] = { n, trust }
    for _, r in pairs(p.reports or {}) do
        if r.kind == "k" and r.hand ~= 0 and M.kudo[r.k] and not C.IsMe(r.g) then
            counts[r.k] = counts[r.k] or {}
            local c = counts[r.k][r.g] or { n = 0, trust = 0.5 }
            c.n = c.n + 1
            if M.Trusted(r) then c.trust = 1 end
            counts[r.k][r.g] = c
        end
    end
    for id, givers in pairs(counts) do
        local e = E(id)
        for giver, c in pairs(givers) do Giver(e, giver, c.n, c.trust) end
    end
    for id, b in pairs(p.banner and p.banner.marks or {}) do
        local e = type(b) == "table" and E(id)
        if e then e.carried, e.carriedN = b.g, b.n end
    end
    local list = {}
    for _, e in pairs(by) do
        e.from = nil
        e.weight = math.max(e.givers, e.carried or 0)
        list[#list + 1] = e
    end
    table.sort(list, function(a, b)
        if a.weight ~= b.weight then return a.weight > b.weight end
        if a.n ~= b.n then return a.n > b.n end
        return a.id < b.id
    end)
    return list
end

-- How many people (as far as you know) have praised a player: for sorting.
function M.Praise(full)
    local total = 0
    for _, e in ipairs(M.KnownFor(full)) do total = total + e.weight end
    return total
end

-- "Steady tank (4), Quick kicks (2)" with icons; nil when nobody has said anything yet.
function M.KnownLine(full, max, size)
    local list = M.KnownFor(full)
    if #list == 0 then return nil end
    local parts = {}
    for i = 1, math.min(max or 3, #list) do
        local e = list[i]
        parts[#parts + 1] = ("%s %s |cffaaaaaa(%d)|r"):format(M.Icon(e.id, size), M.kudo[e.id].label, e.weight)
    end
    return table.concat(parts, "  ")
end

-- ---------------------------------------------------------------------------
-- Flak: a pattern, not one bad run
-- ---------------------------------------------------------------------------

-- Whether a report (Feedback.lua's gossip) is first-hand for you: yours, sent by its own giver, or
-- from a giver you've grouped with yourself (a real player you know). Anything else is hearsay: it
-- counts half, and whoever passed it to you counts as one half source at most however many givers
-- it names, so one person inventing givers can't make a pattern.
function M.Trusted(r)
    if r.hand == 0 or r.hand == 1 then return true end
    local g = ns.History:Get(r.g)
    return g ~= nil and g.t ~= nil and (g.t.runs or 0) > 0
end

-- Flak about a player reaches you two ways:
--   yours    p.flak    = { { k, t, run, told, passed } }  (all of it, passed on or not)
--   gossip   p.reports = { [key] = { g, kind = "f", k, t, hand, via } }  (Feedback.lua)
-- It only counts against them as a pattern: at least FLAK_MIN Flak from FLAK_SOURCES sources (a
-- source is one trusted giver on one day, or one passer-on of hearsay, at half), and then only when
-- it's a lot lately (the same in the last RECENT days) or a history that kudos don't outweigh
-- (OUTWEIGH kudos for every Flak, old Flak counting for less: half every HALF_LIFE days, and a
-- history that has faded under FADED doesn't count). Hearsay counts half everywhere. So one grudge
-- never shows, one liar can't make a pattern, and someone who has turned it around recovers. Your
-- own Flak always shows to you.
local FLAK_MIN, FLAK_SOURCES = 5, 3
local DAY = 86400
local RECENT, HALF_LIFE = 30 * DAY, 90 * DAY
local OUTWEIGH = 3
local FADED = 2 -- a history weighing less than this many recent Flak has faded (kudos or not)
local HEARSAY = 0.5
M.FLAK_MIN, M.FLAK_SOURCES = FLAK_MIN, FLAK_SOURCES

-- { mine = { your entries }, byK = { [k] = n }, total, firstHand, sources, recent, recentFirst,
--   recentSources, weighted, kudos, flagged, why ("lately" / "history"), recovered }. Counts (total,
--   recent, byK) are reports; sources and the weights behind the warning count hearsay at half.
function M.FlakReport(full)
    local p = full and ns.History:Get(full)
    local r = { mine = {}, byK = {}, total = 0, firstHand = 0, sources = 0, recent = 0, recentFirst = 0, recentSources = 0,
        weighted = 0, kudos = 0 }
    if not p then return r end
    local now = time()
    local amount, recentAmount = 0, 0
    local sources, recentSources = {}, {}       -- trusted giver@day -> true
    local passers, recentPassers = {}, {}       -- who passed hearsay on -> true
    local function Count(k, t, trusted, source)
        if not M.flak[k] then return end
        t = tonumber(t) or now
        local w = trusted and 1 or HEARSAY
        r.total = r.total + 1
        if trusted then r.firstHand = r.firstHand + 1 end
        r.byK[k] = (r.byK[k] or 0) + 1
        amount = amount + w
        local age = math.max(0, now - t)
        r.weighted = r.weighted + w * 0.5 ^ (age / HALF_LIFE)
        local set = trusted and sources or passers
        set[source] = true
        if age <= RECENT then
            r.recent = r.recent + 1
            if trusted then r.recentFirst = r.recentFirst + 1 end
            recentAmount = recentAmount + w
            local rset = trusted and recentSources or recentPassers
            rset[source] = true
        end
    end
    for _, e in ipairs(p.flak or {}) do
        r.mine[#r.mine + 1] = e
        Count(e.k, e.t, true, "you@" .. tostring(e.run or math.floor((e.t or now) / DAY)))
    end
    for _, rep in pairs(p.reports or {}) do
        if rep.kind == "f" and rep.hand ~= 0 and not C.IsMe(rep.g) then
            local trusted = M.Trusted(rep)
            Count(rep.k, rep.t, trusted, trusted and (rep.g .. "@" .. math.floor((tonumber(rep.t) or now) / DAY)) or (rep.via or "?"))
        end
    end
    local function Size(set) local n = 0; for _ in pairs(set) do n = n + 1 end; return n end
    r.sources = Size(sources) + HEARSAY * Size(passers)
    r.recentSources = Size(recentSources) + HEARSAY * Size(recentPassers)
    for _, e in ipairs(M.KnownFor(full)) do r.kudos = r.kudos + (e.trusted or e.n or 0) end
    local pattern = amount >= FLAK_MIN and r.sources >= FLAK_SOURCES
    if recentAmount >= FLAK_MIN and r.recentSources >= FLAK_SOURCES then
        r.flagged, r.why = true, "lately"
    elseif pattern and r.weighted >= FADED and r.kudos < OUTWEIGH * r.weighted then
        r.flagged, r.why = true, "history"
    end
    r.recovered = pattern and not r.flagged
    return r
end

-- "Pulled before the group was ready (3), Rude to the group (2)", most first.
function M.FlakList(byK, max, size)
    local list = {}
    for k, n in pairs(byK) do list[#list + 1] = { k = k, n = n } end
    table.sort(list, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.k < b.k
    end)
    local parts = {}
    for i = 1, math.min(max or 3, #list) do
        parts[#parts + 1] = ("%s %s |cffaaaaaa(%d)|r"):format(M.FlakIcon(list[i].k, size), M.flak[list[i].k].label, list[i].n)
    end
    return table.concat(parts, "  ")
end

-- The lines a player's Flak adds wherever you meet them: the warning (only for a pattern), saying
-- how much of it is first-hand, and, in strong orange, the Flak you gave them yourself. Either may
-- be nil.
function M.FlakLines(full, short)
    local r = M.FlakReport(full)
    local warning, mine
    if r.flagged then
        local what = r.why == "lately" and ("%d in the last 30 days, %d first-hand"):format(r.recent, r.recentFirst)
            or ("a history of it (%d, %d first-hand)"):format(r.total, r.firstHand)
        warning = ("|cffff4d40Flak: %s|r  %s"):format(what, M.FlakList(r.byK, short and 2 or 3))
    end
    if #r.mine > 0 then
        local byK = {}
        for _, e in ipairs(r.mine) do byK[e.k] = (byK[e.k] or 0) + 1 end
        mine = ("|cffff9020You gave them Flak:|r %s"):format(M.FlakList(byK, short and 2 or 4))
    end
    return warning, mine, r
end

-- ---------------------------------------------------------------------------
-- Practice: did a tip stick?
-- ---------------------------------------------------------------------------

-- Whether you were the likely cause of a death for reason `tag` in a run.
local function Slipped(run, tag)
    local me = C.Short(run.me)
    for _, d in ipairs(run.deaths or {}) do
        if d.top and me and C.SameName(d.top, me) then
            local why = d.reasons and d.reasons[d.top] and d.reasons[d.top][1]
            if why and ns.History.Tag(why) == tag then return true end
        end
    end
    return false
end

-- Your finished runs on this character since `since` (and, for comparison, the 10 before it):
-- { runs, clean, streak (clean runs in a row, newest last), slips, before = { runs, slips } }.
-- nil for a tip there's nothing to measure for.
function M.Practice(tipID, since)
    local tip = M.tip[tipID]
    if not (tip and tip.tag and since) then return nil end
    local out = { runs = 0, clean = 0, streak = 0, slips = 0, before = { runs = 0, slips = 0 } }
    local earlier = {}
    for _, run in ipairs(ns.db.runs or {}) do
        if run.stop and not run.temp and run.me and C.IsMe(run.me) then
            if run.start >= since then
                out.runs = out.runs + 1
                if Slipped(run, tip.tag) then
                    out.slips, out.streak = out.slips + 1, 0
                else
                    out.clean, out.streak = out.clean + 1, out.streak + 1
                end
            else
                earlier[#earlier + 1] = run
            end
        end
    end
    for i = math.max(1, #earlier - 9), #earlier do
        out.before.runs = out.before.runs + 1
        if Slipped(earlier[i], tip.tag) then out.before.slips = out.before.slips + 1 end
    end
    return out
end

M.STUCK = 3 -- clean runs in a row before a tip counts as one that stuck
