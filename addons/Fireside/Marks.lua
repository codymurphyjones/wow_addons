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

M.kudo, M.tip, M.spark = {}, {}, {}
for _, k in ipairs(M.KUDOS) do M.kudo[k.id] = k end
for _, t in ipairs(M.TIPS) do M.tip[t.id] = t end
for _, s in ipairs(M.SPARKS) do M.spark[s.id] = s end

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

-- What a player is known for: every kudo for them that reached you, merged from three sources:
--   yours        p.given  = { [kudo] = n }
--   testimony    p.heard  = { [giver] = { marks = { [kudo] = n }, t } }  (sent by the givers' own Fireside)
--   their own    p.banner = { marks = { [kudo] = { n, g } }, t }        (what their Fireside says they got)
-- A list, most givers first: { id, n, givers (people you know gave it), names, mine, carried (their
-- own count of givers), carriedN }.
function M.KnownFor(full)
    local p = full and ns.History:Get(full)
    if not p then return {} end
    local by = {}
    local function E(id)
        if not M.kudo[id] then return nil end
        local e = by[id]
        if not e then e = { id = id, n = 0, givers = 0, names = {} }; by[id] = e end
        return e
    end
    for id, n in pairs(p.given or {}) do
        local e = type(n) == "number" and n > 0 and E(id)
        if e then e.n, e.givers, e.mine = e.n + n, e.givers + 1, n end
    end
    for giver, h in pairs(p.heard or {}) do
        for id, n in pairs(type(h) == "table" and h.marks or {}) do
            local e = type(n) == "number" and n > 0 and not C.IsMe(giver) and E(id)
            if e then
                e.n, e.givers = e.n + n, e.givers + 1
                e.names[#e.names + 1] = giver
            end
        end
    end
    for id, b in pairs(p.banner and p.banner.marks or {}) do
        local e = type(b) == "table" and E(id)
        if e then e.carried, e.carriedN = b.g, b.n end
    end
    local list = {}
    for _, e in pairs(by) do
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
