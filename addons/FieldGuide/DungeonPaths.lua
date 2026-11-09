local _, ns = ...

-- Dungeon paths. Many dungeon quests are only offered once you've done a chain of quests out in the
-- world first (Rear Guard Patrol before The Wrath of Rath'mael). Walking that chain when the dungeon
-- comes up costs a trip of its own; doing it while you level past its givers costs almost nothing.
--
-- So: every dungeon quest's chain of earlier quests is worked out (your faction's quests, the
-- dungeons up to REACH levels over yours). When you come within NEAR_YARDS of the giver of a chain's
-- next quest while leveling, a popup asks whether to pick it up, and says what it leads to: the
-- dungeon quest, its dungeon and levels, and what it pays. "Pick it up" accepts a path for each
-- dungeon quest that quest leads to (ns.char.dungeonPaths). The leveling planner (Tasks.lua) then
-- fits the rest of the chain into your plan: each quest of an accepted path counts PATH_SHARE of
-- what the dungeon quest pays on top of its own XP, by the same XP-a-minute measure as everything
-- else, so a step that's on your way gets done, and one far off waits until the plan goes near it.
-- Its last step is picking up the dungeon quest itself; then the path is done and the dungeon
-- route (Instance.lua) takes over when the dungeon is due. "No thanks" never asks about those
-- dungeon quests again (/fg paths reset forgets the answers).
local DP = {}
ns.DungeonPaths = DP

local REACH = 8         -- dungeons whose levels start up to this many over yours are worth preparing for
local NEAR_YARDS = 200  -- the next quest's giver this close to you: the popup asks
local PATH_SHARE = 0.25 -- an accepted path's quest counts this share of the dungeon quest's pay, on top of its own
local ASK_AGAIN = 600   -- seconds before a popup closed without an answer (Escape) asks again
local CHECK_SECONDS = 3

local P
local function L() return ns.Engine.lib end
local function Q(id) return ns.Quests[id] end
local function Faction() return UnitFactionGroup("player") or "" end

local function Paths()
    ns.char.dungeonPaths = ns.char.dungeonPaths or {}
    return ns.char.dungeonPaths
end
local function Declined()
    ns.char.dungeonPathsNo = ns.char.dungeonPathsNo or {}
    return ns.char.dungeonPathsNo
end

-- ---------------------------------------------------------------------------------------------
-- The chains
-- ---------------------------------------------------------------------------------------------

-- The quests a dungeon quest needs first and you haven't done, earliest first, then the dungeon
-- quest itself: { questID, ... }. nil: it needs nothing first, or the chain can't be walked (a quest
-- you skipped, one the server doesn't have, another dungeon's quest in it, or no data).
-- (For "any one of these" the one in your log is taken, else one you can take now, else the first.)
local function Chain(id)
    P = P or ns.Progress
    local out, seen, ok = {}, {}, true
    local function Walk(qid, depth)
        local q = Q(qid)
        if not ok or depth > 12 or not q or not q.pre or #q.pre == 0 then return end
        local needed = q.pre
        if q.preAny then
            for _, p in ipairs(q.pre) do if P:Done(p) then return end end
            needed = { q.pre[1] }
            for _, p in ipairs(q.pre) do
                if P:InLog(p) then needed = { p }; break end
            end
            if not P:InLog(needed[1]) then
                for _, p in ipairs(q.pre) do
                    if ns.Engine:QuestOpen(p) then needed = { p }; break end
                end
            end
        end
        for _, p in ipairs(needed) do
            local pq = Q(p)
            if not seen[p] and not P:Done(p) then
                seen[p] = true
                if not pq or pq.dq or ns.char.ignored[p] or (ns.Exists and ns.Exists:Missing(p))
                    or not P:RaceAllowed(pq.rm) then
                    ok = false
                    return
                end
                Walk(p, depth + 1)
                out[#out + 1] = p
            end
        end
    end
    Walk(id, 0)
    if not ok or #out == 0 then return nil end
    out[#out + 1] = id
    return out
end

-- What the dungeon quest pays: its XP at the dungeon's levels (or yours, if higher), counted as the
-- dungeon routes count it.
local function DungeonPay(id, inst)
    P = P or ns.Progress
    return L().QuestXP(Q(id), math.max(P:Level(), inst.from or 1)) * 2
end

-- The dungeon quests worth preparing for now: { { quest, inst, chain }, ... }. Yours to take (a giver,
-- not started by an item), not done or in your log, needing something first, the dungeon not
-- out-levelled and starting within REACH levels, and the quest still paying when you get there.
function DP:Candidates()
    P = P or ns.Progress
    local level, out = P:Level(), {}
    for _, inst in ipairs(ns.Instance and ns.Instance.list or {}) do
        if (inst.from or 1) <= level + REACH and (inst.to or 60) >= level then
            for _, id in ipairs(inst[Faction()] or {}) do
                local q = Q(id)
                if q and q.a and not q.ia and not P:Done(id) and not P:InLog(id) and P:RaceAllowed(q.rm)
                    and not ns.char.ignored[id] and ns.Tasks:LastLevel(id) >= math.max(level, inst.from or 1) then
                    local chain = Chain(id)
                    if chain then out[#out + 1] = { quest = id, inst = inst, chain = chain } end
                end
            end
        end
    end
    return out
end

-- The chain's quest to do next (the first not done), and whether it's in your log.
function DP.NextOf(chain)
    P = P or ns.Progress
    for _, id in ipairs(chain) do
        if not P:Done(id) then return id, P:InLog(id) end
    end
end

-- ---------------------------------------------------------------------------------------------
-- Accepted paths (for the planner)
-- ---------------------------------------------------------------------------------------------

-- The accepted paths still under way: { { quest, inst, chain }, ... }. A path whose dungeon quest is
-- in your log or done is over (said once); one that can't go on any more (its dungeon out-levelled,
-- the quest no longer paying, a quest of the chain skipped) is dropped, also said once.
local active, activeAt
function DP:Active()
    P = P or ns.Progress
    if not ns.char then return {} end
    local now = GetTime()
    if active and activeAt == now then return active end
    local level, out = P:Level(), {}
    for id, clause in pairs(Paths()) do
        local inst = ns.Instance:Get(clause.inst)
        local name = ns.Engine:QuestName(id)
        if P:InLog(id) or P:Done(id) then
            Paths()[id] = nil
            if P:InLog(id) then
                ns:Print(("%s is in your log, ready for %s."):format(name, inst and inst.name or "its dungeon"))
            end
        else
            local chain = Chain(id)
            if not inst or not chain or level > (inst.to or 60)
                or ns.Tasks:LastLevel(id) < math.max(level, inst.from or 1) then
                Paths()[id] = nil
                ns:Print(("Dropped the path to %s: it can't be done any more, or no longer pays."):format(name))
            else
                out[#out + 1] = { quest = id, inst = inst, chain = chain }
            end
        end
    end
    active, activeAt = out, now
    return out
end

-- The planner's view: [questID] = the extra XP an accepted path gives it (PATH_SHARE of the dungeon
-- quest's pay, shared by the chain's quests still to do, so a path closer to its end weighs more),
-- and [questID] = the dungeon quest it leads to. The dungeon quest itself is in both: its pick-up
-- is the path's last step.
function DP:Bonus()
    P = P or ns.Progress
    local bonus, leads = {}, {}
    for _, path in ipairs(self:Active()) do
        local left = {}
        for _, id in ipairs(path.chain) do
            if not P:Done(id) then left[#left + 1] = id end
        end
        local each = #left > 0 and DungeonPay(path.quest, path.inst) * PATH_SHARE / #left or 0
        for _, id in ipairs(left) do
            bonus[id] = (bonus[id] or 0) + each
            leads[id] = leads[id] or path.quest
        end
    end
    return bonus, leads
end

-- On an accepted path (the planner lets it in whatever it pays by itself, and a dungeon quest's
-- pick-up too).
function DP:On(id)
    local _, leads = self:Bonus()
    return leads[id] ~= nil
end

-- ---------------------------------------------------------------------------------------------
-- The popup
-- ---------------------------------------------------------------------------------------------

local function Commas(n)
    local s = tostring(math.floor(n + 0.5))
    while true do
        local t, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
        s = t
        if k == 0 then return s end
    end
end

local function PopupText(head, list)
    local hq = Q(head) or {}
    local lines = {}
    for _, c in ipairs(list) do
        local left = 0
        for _, id in ipairs(c.chain) do
            if not P:Done(id) and id ~= head then left = left + 1 end
        end
        -- (left counts the dungeon quest's own pick-up: the quests in between are left - 1.)
        local between = left - 1
        lines[#lines + 1] = ("|cff8fd16a%s|r for |cffffd100%s|r (levels %d-%d): about %s XP when you run it.%s"):format(
            ns.Engine:QuestName(c.quest), c.inst.name, c.inst.from or 0, c.inst.to or 0, Commas(DungeonPay(c.quest, c.inst)),
            between > 0 and (" %d more quest%s after this one to unlock it."):format(between, between == 1 and "" or "s")
                or " It unlocks it straight away.")
    end
    return ("|cffffd100%s|r (%s, here) leads to a dungeon quest:\n\n%s\n\nPick it up? The guide fits the rest into your leveling where it costs little (a bit less XP now for a lot more in the dungeon), and you'll have the dungeon quest ready when you go."):format(
        hq.n or ns.Engine:QuestName(head), hq.a and hq.a[4] or "its giver", table.concat(lines, "\n\n"))
end

local asking -- { head, quests = { questID, ... } } while the popup is up
local askedAt = {} -- head questID -> GetTime() it was asked and left unanswered

function DP:Accept(data)
    if not data then return end
    P = P or ns.Progress
    local level = P:Level()
    for _, c in ipairs(data.list) do
        Paths()[c.quest] = { inst = c.inst.id, level = level, head = data.head }
        -- Chosen now: a dungeon quest skipped for now is wanted again.
        if ns.char.later then ns.char.later[c.quest] = nil end
    end
    active = nil
    ns:Print(("Dungeon path accepted: pick up %s. The guide fits the rest in along the way (/fg paths)."):format(
        ns.Engine:QuestName(data.head)))
    if ns.Tasks then ns.Tasks:Refresh() end
    ns.Engine:Invalidate()
    ns:Changed()
end

local function Decline(data)
    if not data then return end
    for _, c in ipairs(data.list) do Declined()[c.quest] = true end
end

StaticPopupDialogs["FIELDGUIDE_DUNGEON_PATH"] = {
    text = "%s", button1 = "Pick it up", button2 = "No thanks",
    OnAccept = function(_, data) DP:Accept(data) end,
    OnCancel = function(_, data, reason)
        -- (Escape or another popup taking its place: no answer, ask again later.)
        if reason == "clicked" then Decline(data) end
    end,
    OnHide = function() asking = nil end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}

-- Openings near you: the next quest of a chain you haven't answered for, takeable now, its giver
-- within NEAR_YARDS. head questID -> { candidate, ... } (one quest can lead to several dungeon quests).
local function Openings()
    P = P or ns.Progress
    local lib = L()
    local c, n, w = ns.WorldMap.Player()
    if not c then return nil end
    local level = P:Level()
    local paths, no = Paths(), Declined()
    local best, bestD, list
    local byHead = {}
    for _, cand in ipairs(DP:Candidates()) do
        if not paths[cand.quest] and not no[cand.quest] then
            local head, inLog = DP.NextOf(cand.chain)
            local q = head and Q(head)
            if q and not inLog and head ~= cand.quest and q.a and lib.Practical(q) <= level
                and lib.PrereqsDone(q) and ns.Engine:QuestOpen(head) and P:Doable(head) then
                local g = lib.World(q.a)
                if g and g[1] == c then
                    local d = math.sqrt((g[2] - n) ^ 2 + (g[3] - w) ^ 2)
                    if d <= NEAR_YARDS then
                        byHead[head] = byHead[head] or { d = d }
                        table.insert(byHead[head], cand)
                    end
                end
            end
        end
    end
    for head, l in pairs(byHead) do
        if not (askedAt[head] and GetTime() - askedAt[head] < ASK_AGAIN) and (not bestD or l.d < bestD) then
            best, bestD, list = head, l.d, l
        end
    end
    return best, list
end

-- While leveling (not a dungeon route, Zone Clear or a section you chose; not paused, in combat or
-- inside an instance), ask about the nearest opening.
function DP:Check()
    if not ns.char or not ns.Engine or not ns.Engine.lib or not ns.Instance then return end
    if asking or ns.char.paused or ns.char.instance or ns.char.section or InCombatLockdown() then return end
    if IsInInstance() or UnitIsDeadOrGhost("player") then return end
    if StaticPopup_Visible("FIELDGUIDE_DUNGEON") or StaticPopup_Visible("FIELDGUIDE_DUNGEON_PATH") then return end
    local s = ns.Engine.section
    if not (s and s.tasks) then return end
    local head, list = Openings()
    if not head then return end
    askedAt[head] = GetTime()
    asking = { head = head, list = list }
    StaticPopup_Show("FIELDGUIDE_DUNGEON_PATH", PopupText(head, list), nil, asking)
end

ns:On("PLAYER_LOGIN", function()
    C_Timer.NewTicker(CHECK_SECONDS, function() DP:Check() end)
end)

-- ---------------------------------------------------------------------------------------------
-- /fg paths
-- ---------------------------------------------------------------------------------------------

function DP:Command(arg)
    P = P or ns.Progress
    arg = strlower(arg or "")
    if arg == "reset" then
        wipe(Declined())
        wipe(askedAt)
        ns:Print("Dungeon paths: the popup asks again about every dungeon quest you said no to.")
        return
    elseif arg == "stop" or arg == "clear" then
        wipe(Paths())
        active = nil
        if ns.Tasks then ns.Tasks:Refresh() end
        ns.Engine:Invalidate()
        ns:Changed()
        ns:Print("Dungeon paths: none followed any more.")
        return
    end
    local list = self:Active()
    if #list == 0 then
        ns:Print("No dungeon paths accepted. The guide asks when you pass a quest that leads to a dungeon quest. (/fg paths reset: ask again about ones you said no to)")
        return
    end
    ns:Print("Dungeon paths (/fg paths stop drops them all):")
    for _, path in ipairs(list) do
        local next = DP.NextOf(path.chain)
        local left = 0
        for _, id in ipairs(path.chain) do if not P:Done(id) then left = left + 1 end end
        ns:Print(("  %s for %s: next %s (%d step%s left)"):format(ns.Engine:QuestName(path.quest), path.inst.name,
            next and ns.Engine:QuestName(next) or "?", left, left == 1 and "" or "s"))
    end
end

-- For /fg why (Tasks.lua): the accepted paths, one line.
function DP:Why(lines)
    local list = self:Active()
    if #list == 0 then return end
    local names = {}
    for _, path in ipairs(list) do
        names[#names + 1] = ("%s (%s)"):format(ns.Engine:QuestName(path.quest), path.inst.name)
    end
    lines[#lines + 1] = "  Dungeon paths fitted in: " .. table.concat(names, ", ")
end
