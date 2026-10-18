local _, ns = ...

-- Instance priority. On Forever, a dungeon with its quests in your log is the fastest leveling
-- there is. When your level reaches a dungeon's recommended range and you haven't done its
-- quests, a popup says it's time and where to pick them up; "Guide me" switches the guide to a
-- route that collects them, has you run the dungeon, and turns them in. The minimap button's
-- tooltip lists every dungeon in your range with quests left, for as long as that's true.
-- Dungeons and their quests: Guides\Instances.lua (generated).
--
-- Wings: Scarlet Monastery, Dire Maul, Blackrock Spire and Stratholme are entered wing by wing,
-- and each wing is its own run. The route runs only the wings your quests need, in order, with
-- the arrow on each wing's entrance. Which wing you're in comes from (best first): the final
-- boss you just killed; the instance's size (Blackrock Spire: Upper is the 10-player one); the
-- dungeon map you're on, once it has been learned (ns.db.wingMaps); the entrance nearest to
-- where you stepped in.
local I = {}
ns.Instance = I

ns.Instances = ns.Instances or {}

local function Faction() return UnitFactionGroup("player") or "" end

local function QuestsOf(inst)
    return inst[Faction()] or {}
end

-- The dungeon's quests you can still do.
function I:Open(inst)
    local out = {}
    for _, id in ipairs(QuestsOf(inst)) do
        if ns.Engine:QuestOpen(id) then out[#out + 1] = id end
    end
    return out
end

-- Quests that start inside, from an item you loot there: { questID, ... } you could take and
-- haven't done or chosen to leave.
function I:Inside(inst)
    local out, level = {}, ns.Progress:Level()
    local list = inst.inside and inst.inside[Faction()] or {}
    for _, id in ipairs(list) do
        local q = ns.Quests[id] or {}
        if ns.Engine:QuestOpen(id) and (q.r or 1) <= level then out[#out + 1] = id end
    end
    return out
end

-- "Damp Note (starts Allegiance to the Old Gods)"
function I:InsideText(id)
    local q = ns.Quests[id] or {}
    return ("%s (starts %s)"):format(q.ia or "an item", q.n or ("quest " .. id))
end

function I:Get(id)
    for _, inst in ipairs(ns.Instances) do
        if inst.id == id then return inst end
    end
end

-- ---------------------------------------------------------------------------------------------
-- Wings
-- ---------------------------------------------------------------------------------------------

function I:Wing(inst, key)
    for _, w in ipairs(inst.wings or {}) do
        if w.key == key then return w end
    end
end

-- The wing a quest is done in (nil: the dungeon has no wings, or any wing will do).
function I:WingOf(inst, id)
    return inst.wingOf and inst.wingOf[id]
end

-- "Scarlet Monastery: Library"
function I:RunName(inst, wingKey)
    local w = wingKey and self:Wing(inst, wingKey)
    return w and (inst.name .. ": " .. w.name) or inst.name
end

-- A run that's over on this route: its final boss died, or you left with its quests done.
local function RunKey(inst, wingKey) return inst.id .. ":" .. (wingKey or "") end
function I:Ran(inst, wingKey) return ns.char.ran[RunKey(inst, wingKey)] == true end

-- The wings this route runs, in order: those with a quest of yours, or an item to watch for.
-- Quests tied to no wing are done along the way, and count toward the last wing.
function I:RouteWings(inst)
    if not inst.wings then return {} end
    local need = {}
    for _, id in ipairs(self:Open(inst)) do
        local w = self:WingOf(inst, id)
        if w then need[w] = true end
    end
    for _, id in ipairs(QuestsOf(inst)) do
        local w = ns.Progress:InLog(id) and self:WingOf(inst, id)
        if w then need[w] = true end
    end
    for _, id in ipairs(self:Inside(inst)) do
        local w = self:WingOf(inst, id)
        if w then need[w] = true end
    end
    local out = {}
    for _, w in ipairs(inst.wings) do
        if need[w.key] then out[#out + 1] = w.key end
    end
    return out
end

-- Items still to find in a wing (nil wingKey: the whole dungeon). Items tied to no wing count
-- toward the last wing on the route.
function I:MissingItems(inst, wingKey)
    local wings = self:RouteWings(inst)
    local last = wings[#wings]
    local out = {}
    for _, id in ipairs(self:Inside(inst)) do
        if not ns.Progress:InLog(id) then
            local w = self:WingOf(inst, id) or last
            if wingKey == nil or w == wingKey then out[#out + 1] = id end
        end
    end
    return out
end

-- ---------------------------------------------------------------------------------------------
-- Which dungeons are due
-- ---------------------------------------------------------------------------------------------

-- Dungeons in your level range with quests left: { { inst = ..., open = { questID, ... } } }.
-- Worked out once a frame (the window, the minimap button and the route all ask).
local current, currentAt
function I:Current()
    local now = GetTime()
    if current and currentAt == now then return current end
    local level, out = ns.Progress:Level(), {}
    for _, inst in ipairs(ns.Instances) do
        if level >= inst.from and level <= inst.to then
            local open = self:Open(inst)
            if #open > 0 then out[#out + 1] = { inst = inst, open = open } end
        end
    end
    current, currentAt = out, now
    return out
end

local function ClearRuns(inst)
    for key in pairs(ns.char.ran) do
        if key:match("^(%d+):") == tostring(inst.id) then ns.char.ran[key] = nil end
    end
end

-- "Guide me": the guide collects this dungeon's quests, sends you in, and turns them in.
function I:Start(inst)
    if ns.char.instance ~= inst.id then ClearRuns(inst) end
    ns.char.instance, ns.char.lastInstance = inst.id, inst.id
    currentAt = nil
    ns.Engine:Invalidate()
    ns:Print(("Guiding you to %s: pick up its quests, run it, then turn them in. /fg dungeon stop goes back to questing."):format(inst.name))
    ns:Changed()
end

-- The dungeon "To Dungeons" goes to: the one you last followed if it's still due, else the
-- first one due.
function I:Next()
    local list = self:Current()
    for _, entry in ipairs(list) do
        if entry.inst.id == ns.char.lastInstance then return entry.inst end
    end
    return list[1] and list[1].inst
end

function I:Resume()
    local inst = self:Next()
    if inst then self:Start(inst) else ns:Print("No dungeon in your level range has quests left for you.") end
end

function I:Stop(quiet)
    if not ns.char.instance then return end
    ns.char.lastInstance = ns.char.instance
    ns.char.instance = nil
    ns.Engine:Invalidate()
    if not quiet then ns:Print("Back to questing.") end
    ns:Changed()
end

-- ---------------------------------------------------------------------------------------------
-- The route
-- ---------------------------------------------------------------------------------------------

-- Quests in an order where each comes after the ones it needs (lowest level first otherwise).
local function Ordered(list)
    table.sort(list, function(a, b)
        local qa, qb = ns.Quests[a] or {}, ns.Quests[b] or {}
        if (qa.l or 0) ~= (qb.l or 0) then return (qa.l or 0) < (qb.l or 0) end
        return a < b
    end)
    local out, placed, inList = {}, {}, {}
    for _, id in ipairs(list) do inList[id] = true end
    local function Place(id, depth)
        if placed[id] or depth > 20 then return end
        placed[id] = true
        for _, p in ipairs((ns.Quests[id] or {}).pre or {}) do
            if inList[p] then Place(p, depth + 1) end
        end
        out[#out + 1] = id
    end
    for _, id in ipairs(list) do Place(id, 0) end
    return out
end

-- The route for a dungeon, in the order that walks least:
--   1. hand-offs that only send you to someone ("Speak to Je'neu Sancrea"): picked up and
--      handed in straight away, since that someone usually gives the dungeon's quests;
--   2. pick up every quest you can take now;
--   3. out by the dungeon: loot the items that start its quests (the Damp Note, from the Tide
--      Priestess at Blackfathom's entrance), and do the objectives that are out in the world
--      (The Essence of Aku'Mai's sapphires, in the tunnel outside the portal; inst.before,
--      checked by hand), nearest the entrance last;
--   4. hand in the item quests and pick up what they unlock (Allegiance to the Old Gods);
--   5. run it (wing by wing), then turn everything in.
-- Quests that start inside (from an item you loot there) come last: their turn-ins and what they
-- lead to only show if you got the item.
function I:Section(inst)
    local open = Ordered(self:Open(inst))
    local steps, after = {}, {}
    local function Q(id) return ns.Quests[id] or {} end
    local function HandOff(q)
        return not q.o and type(q.ot) == "string" and (q.ot:find("^Speak to") or q.ot:find("^Talk to")
            or q.ot:find("^Report to") or q.ot:find("^Go to") or q.ot:find("^Travel to")) ~= nil
    end
    -- Quests that need one of the route's item quests first (directly or further back).
    local isItem = {}
    for _, id in ipairs(open) do if Q(id).ia then isItem[id] = true end end
    local function NeedsItem(id, depth)
        if depth > 10 then return false end
        for _, p in ipairs(Q(id).pre or {}) do
            if isItem[p] or NeedsItem(p, depth + 1) then return true end
        end
        return false
    end
    local outside = {}
    local function Outside(id)
        local q = Q(id)
        return q.o and inst.before and inst.before[id]
    end

    -- 1. hand-offs
    for _, id in ipairs(open) do
        local q = Q(id)
        if not q.ia and HandOff(q) and not NeedsItem(id, 0) then
            steps[#steps + 1] = { "A", id }
            steps[#steps + 1] = { "T", id }
        end
    end
    -- 2. what you can pick up now
    local later = {}
    for _, id in ipairs(open) do
        local q = Q(id)
        if not q.ia and not (HandOff(q) and not NeedsItem(id, 0)) then
            if NeedsItem(id, 0) then
                later[#later + 1] = id
            else
                steps[#steps + 1] = { "A", id }
                if Outside(id) then outside[#outside + 1] = id end
                after[#after + 1] = { "T", id }
            end
        end
    end
    -- 3. out by the dungeon: items to loot and objectives out in the world, nearest the entrance last
    local e = inst.entrance
    local function FromEntrance(spot)
        if not (e and spot) or spot[1] ~= e[1] then return math.huge end
        return ((spot[2] - e[2]) * 1.5) ^ 2 + (spot[3] - e[3]) ^ 2
    end
    local out = {}
    for _, id in ipairs(open) do
        local q = Q(id)
        if q.ia then
            out[#out + 1] = { d = FromEntrance(q.d and q.d[1]), steps = { { "L", id } } }
            if q.o then table.insert(out[#out].steps, { "O", id }) end
        end
    end
    for _, id in ipairs(outside) do
        out[#out + 1] = { d = FromEntrance(Q(id).o[1]), steps = { { "O", id, before = true, inst = inst.id } } }
    end
    table.sort(out, function(a, b) return a.d > b.d end)
    for _, o in ipairs(out) do
        for _, st in ipairs(o.steps) do steps[#steps + 1] = st end
    end
    -- 4. hand in the item quests, pick up what they unlock
    for _, id in ipairs(open) do
        if Q(id).ia then steps[#steps + 1] = { "T", id } end
    end
    local outsideLater = {}
    for _, id in ipairs(later) do
        steps[#steps + 1] = { "A", id }
        if HandOff(Q(id)) then
            steps[#steps + 1] = { "T", id }
        else
            if Outside(id) then outsideLater[#outsideLater + 1] = id end
            after[#after + 1] = { "T", id }
        end
    end
    for _, id in ipairs(outsideLater) do
        steps[#steps + 1] = { "O", id, before = true, inst = inst.id }
    end
    -- 5. the run, then the turn-ins
    local wings = self:RouteWings(inst)
    -- Each run step lists the quests it's for (the ones turned in after it), by wing.
    local function Needs(wingKey, last)
        local out = {}
        for _, t in ipairs(after) do
            local w = self:WingOf(inst, t[2])
            if not wingKey or w == wingKey or (w == nil and last) then out[#out + 1] = t[2] end
        end
        return out
    end
    if #wings == 0 then
        steps[#steps + 1] = { "I", inst.id, needs = Needs(nil, true) }
    else
        for i, key in ipairs(wings) do
            steps[#steps + 1] = { "I", inst.id, wing = key, last = i == #wings, needs = Needs(key, i == #wings) }
        end
    end
    for _, s in ipairs(after) do steps[#steps + 1] = s end
    -- Items that drop inside: expected during the run, listed last. If the run ends without one,
    -- you're asked whether to leave its quest or run the dungeon again (see EndOfRun).
    local listed = {}
    for _, id in ipairs(QuestsOf(inst)) do listed[id] = true end
    for _, id in ipairs(self:Inside(inst)) do
        steps[#steps + 1] = { "L", id, inside = true, inst = inst.id, wing = self:WingOf(inst, id), again = ns.char.rerun[id] }
        steps[#steps + 1] = { "T", id, inside = true }
        for _, f in ipairs(inst.follow and inst.follow[id] or {}) do
            local fq = ns.Quests[f]
            if fq and not listed[f] then
                listed[f] = true
                steps[#steps + 1] = { "A", f, inside = true, follow = true }
                if fq.o then steps[#steps + 1] = { "O", f, inside = true, follow = true } end
                steps[#steps + 1] = { "T", f, inside = true, follow = true }
            end
        end
    end
    return { id = "inst-" .. inst.id, title = inst.name .. " (dungeon)", zone = 0, from = inst.from, to = inst.to,
        top = inst.to, instance = inst, steps = steps }
end

-- "Run" (a dungeon or one wing of it) is done once each of its quests in your log has its
-- objectives done, and the run is over (or nothing is left to find in it).
function I:RunDone(inst, step)
    local P = ns.Progress
    -- Quests it's for that you haven't picked up yet (and didn't skip): the run is still ahead.
    for _, q in ipairs(step.needs or {}) do
        if not P:Done(q) and not P:InLog(q) and ns.Engine:QuestOpen(q) and not ns.char.skipped["A:" .. q] then
            return false
        end
    end
    for _, q in ipairs(QuestsOf(inst)) do
        local w = self:WingOf(inst, q)
        local mine = not step.wing or w == step.wing or (w == nil and step.last)
        if mine and P:InLog(q) and not P:ReadyToTurnIn(q) then return false end
    end
    if #self:MissingItems(inst, step.wing) > 0 and not self:Ran(inst, step.wing) then return false end
    return true
end

-- ---------------------------------------------------------------------------------------------
-- The popup
-- ---------------------------------------------------------------------------------------------

local MAX_LINES = 8

local function PopupText(entry)
    local inst, lines = entry.inst, {}
    for i, id in ipairs(entry.open) do
        if i > MAX_LINES then
            lines[#lines + 1] = ("...and %d more"):format(#entry.open - MAX_LINES)
            break
        end
        local q = ns.Quests[id] or {}
        if q.ia and q.d then
            lines[#lines + 1] = ("|cffffd100%s|r\nLoot %s from %s, %s%s"):format(q.n or ("Quest " .. id), q.ia, q.dm or "mobs",
                ns.Engine:Where(q.d[1]), q.de and " (the dungeon entrance)" or "")
        elseif q.o and inst.before and inst.before[id] then
            lines[#lines + 1] = ("|cffffd100%s|r\n%s, %s. %s outside, before you go in: %s"):format(q.n or ("Quest " .. id),
                q.a and q.a[4] or "?", ns.Engine:Where(q.a), inst.before[id] == "part" and "Started" or "Done",
                ns.Engine:Where(q.o[1]))
        else
            lines[#lines + 1] = ("|cffffd100%s|r\n%s, %s"):format(q.n or ("Quest " .. id), q.a and q.a[4] or "?", ns.Engine:Where(q.a))
        end
    end
    local inside = {}
    for _, id in ipairs(I:Inside(inst)) do inside[#inside + 1] = I:InsideText(id) end
    local wings = {}
    for _, key in ipairs(I:RouteWings(inst)) do wings[#wings + 1] = I:Wing(inst, key).name end
    return ("Time for |cff8fd16a%s|r (levels %d-%d)!%s\n\nPick up its quests first:\n\n%s%s"):format(
        inst.name, inst.from, inst.to,
        #wings > 0 and ("\nWings to run: " .. table.concat(wings, ", ")) or "",
        table.concat(lines, "\n"),
        #inside > 0 and ("\n\nInside, watch for:\n|cffd9a066" .. table.concat(inside, "\n") .. "|r") or "")
end

StaticPopupDialogs["FIELDGUIDE_DUNGEON"] = {
    text = "%s", button1 = "Guide me", button2 = "Later",
    OnAccept = function(_, data) if data then I:Start(data) end end,
    OnHide = function() C_Timer.After(0.2, function() I:Check() end) end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}

-- Shows the popup for a dungeon you've just come into range of (once per dungeon).
function I:Check()
    if not ns.char or StaticPopup_Visible("FIELDGUIDE_DUNGEON") then return end
    ns.char.dungeonsShown = ns.char.dungeonsShown or {}
    for _, entry in ipairs(self:Current()) do
        if not ns.char.dungeonsShown[entry.inst.id] and ns.char.instance ~= entry.inst.id then
            ns.char.dungeonsShown[entry.inst.id] = true
            StaticPopup_Show("FIELDGUIDE_DUNGEON", PopupText(entry), nil, entry.inst)
            return
        end
    end
end

-- ---------------------------------------------------------------------------------------------
-- Where you are: which dungeon and wing
-- ---------------------------------------------------------------------------------------------

local inRun      -- the dungeon on your route you're inside right now
local inWing     -- the wing of it you're in (nil: unknown, or no wings)
local wingFrom   -- how inWing was found: "boss", "size", "map", "entrance"
local asked = {} -- run key -> true (answered) or "later" (ask again after the next zone change)
local lastOutside -- { uiMapID, x, y } (0-100): where you last stood outside an instance

local function Route() return ns.char.instance and I:Get(ns.char.instance) end

-- "The Temple of Atal'Hakkar" and "Sunken Temple", "The Stockade" and "Stormwind Stockade": the
-- game's name may not be the guide's, so names are compared loosely.
local function Loose(name)
    name = strlower(name or ""):gsub("^the ", ""):gsub("[^%a]", "")
    return name
end

local function InsideNow(inst)
    if not (IsInInstance and IsInInstance()) then return false end
    local name, _, _, _, _, _, _, mapID = GetInstanceInfo()
    if inst.map and inst.map > 0 and mapID == inst.map then return true end
    local a, b = Loose(name), Loose(inst.name)
    return a ~= "" and (a == b or a:find(b, 1, true) ~= nil or b:find(a, 1, true) ~= nil)
end

local function Remember()
    if IsInInstance and IsInInstance() then return end
    local map = C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    local x, y = pos and pos:GetXY()
    if x and y and (x > 0 or y > 0) then lastOutside = { map, x * 100, y * 100 } end
end

-- Seeds for the dungeon maps of each wing, from QuestieDB's wing areas (Dire Maul's floors and
-- Upper Blackrock Spire). Others are learned (ns.db.wingMaps).
local SEED_MAPS = {
    [235] = "north", [236] = "west", [237] = "west", [238] = "west", [239] = "east", [240] = "east", [255] = "upper",
}

local function InsideMap() return C_Map.GetBestMapForUnit("player") end

local function Learn(inst, key)
    local map = InsideMap()
    if map and key and I:Wing(inst, key) then ns.db.wingMaps[map] = inst.id .. ":" .. key end
end

local function WingFromMap(inst)
    local map = InsideMap()
    if not map then return nil end
    local learned = ns.db.wingMaps[map]
    if learned then
        local id, key = learned:match("^(%d+):(.+)$")
        if tonumber(id) == inst.id then return key end
    end
    local seed = SEED_MAPS[map]
    return seed and I:Wing(inst, seed) and seed or nil
end

local function WingFromSize(inst)
    local _, _, _, _, maxPlayers = GetInstanceInfo()
    if type(maxPlayers) ~= "number" or maxPlayers <= 0 then return nil end
    local sized
    for _, w in ipairs(inst.wings) do
        if w.size then
            sized = true
            if (maxPlayers > 5) == (w.size > 5) then return w.key end
        end
    end
    return nil, sized
end

local function WingFromEntrance(inst)
    if not lastOutside then return nil end
    local best, bestD
    for _, w in ipairs(inst.wings) do
        local e = w.entrance
        if e[1] == lastOutside[1] then
            local d = math.sqrt(((e[2] - lastOutside[2]) * 1.5) ^ 2 + (e[3] - lastOutside[3]) ^ 2)
            if not best or d < bestD then best, bestD = w.key, d end
        end
    end
    return bestD and bestD <= 6 and best or nil
end

local function SetWing(inst, key, from)
    if not key or (inWing == key and wingFrom == from) then return end
    local changed = inWing ~= key
    inWing, wingFrom = key, from
    if from ~= "map" then Learn(inst, key) end
    if changed then ns:Print(("You're in %s."):format(I:RunName(inst, key))) end
end

local function IdentifyWing(inst)
    if not inst.wings then return end
    local key, sized = WingFromSize(inst)
    if key then return SetWing(inst, key, "size") end
    if sized then return end
    key = WingFromMap(inst)
    if key then return SetWing(inst, key, "map") end
    key = WingFromEntrance(inst)
    if key then return SetWing(inst, key, "entrance") end
end

-- The wing you're in, if known (for the route and the arrow).
-- Whether you're inside this dungeon on its route right now.
function I:InRun(inst)
    return inst ~= nil and inRun == inst.id
end

-- Whether you've been inside it on this route yet.
function I:Entered(inst)
    return inst ~= nil and ns.char.ran[inst.id .. ":in"] == true
end

function I:CurrentWing(inst)
    if inst and inRun == inst.id then return inWing end
end

-- ---------------------------------------------------------------------------------------------
-- The end of a run: an item that should have dropped didn't
-- ---------------------------------------------------------------------------------------------

StaticPopupDialogs["FIELDGUIDE_NOLOOT"] = {
    text = "%s", button1 = "Leave the quest", button2 = "Run it again", button3 = "Ask me later",
    OnAccept = function(_, data)
        for _, id in ipairs(data.quests) do ns.char.ignored[id] = true; ns.char.rerun[id] = nil end
        asked[data.key] = true
        ns:Print("Left those quests out. /fg unskip brings them back.")
        ns.Engine:Invalidate(); ns:Changed()
    end,
    OnCancel = function(_, data, reason)
        if reason ~= "clicked" then return end
        for _, id in ipairs(data.quests) do ns.char.rerun[id] = true end
        ns.char.ran[data.key] = nil
        asked[data.key] = true
        ns:Print(("Kept: run %s again to find it. The arrow points at the entrance."):format(data.name))
        ns.Engine:Invalidate(); ns:Changed()
    end,
    OnAlt = function(_, data)
        asked[data.key] = "later"
        ns:Print("Fine: I'll ask again after your next loading screen.")
    end,
    -- No Escape: it would count as one of the two answers. "Ask me later" puts it off instead.
    timeout = 0, whileDead = 1, hideOnEscape = false, preferredIndex = 3,
}

-- A run (or wing) is over: the final boss died, or you left with its quests done. Remembers it,
-- and asks about each item you didn't find (once a run).
function I:EndOfRun(inst, wingKey)
    if #self:RouteWings(inst) == 0 then wingKey = nil end -- one run on this route, whatever the wing
    local key = RunKey(inst, wingKey)
    ns.char.ran[key] = true
    ns.Engine:Invalidate(); ns:Changed()
    if asked[key] then return end
    local missing = self:MissingItems(inst, wingKey)
    if #missing == 0 then return end
    asked[key] = true
    local names = {}
    for _, id in ipairs(missing) do names[#names + 1] = I:InsideText(id) end
    local name = self:RunName(inst, wingKey)
    StaticPopup_Show("FIELDGUIDE_NOLOOT", ("Your %s run is over and this didn't drop:\n\n|cffd9a066%s|r\n\nLeave the quest, or run %s again for it?"):format(
        name, table.concat(names, "\n"), name), nil, { quests = missing, name = name, key = key })
end

-- A step that waits on a run that's over but wasn't answered for ("Ask me later", or the end
-- went unnoticed): ask now. Called by the guide when such a step comes up while you're outside.
function I:AskAgain(inst, wingKey)
    if #self:RouteWings(inst) == 0 then wingKey = nil end
    local key = RunKey(inst, wingKey)
    if asked[key] or inRun == inst.id or StaticPopup_Visible("FIELDGUIDE_NOLOOT") then return end
    self:EndOfRun(inst, wingKey)
end

-- Your quests for the wing you're in (or the dungeon) are all done.
local function QuestsDone(inst, wingKey)
    local P = ns.Progress
    local wings = I:RouteWings(inst)
    local last = wings[#wings]
    for _, q in ipairs(QuestsOf(inst)) do
        local w = I:WingOf(inst, q) or last
        if (wingKey == nil or w == wingKey) and P:InLog(q) and not P:ReadyToTurnIn(q) then return false end
    end
    return true
end

local function WhereAmI()
    for key, v in pairs(asked) do if v == "later" then asked[key] = nil end end
    local inst = Route()
    if not inst then inRun, inWing, wingFrom = nil, nil, nil; return end
    if InsideNow(inst) then
        if inRun ~= inst.id then
            -- A new run (dying and coming back in isn't one: see below): ask about it afresh.
            inRun, inWing, wingFrom = inst.id, nil, nil
            ns.char.ran[inst.id .. ":in"] = true
            for key in pairs(asked) do
                if key:match("^(%d+):") == tostring(inst.id) then asked[key] = nil end
            end
        end
        IdentifyWing(inst)
        if inWing and wingFrom ~= "boss" then Learn(inst, inWing) end
    elseif inRun == inst.id then
        -- You left. Released as a ghost after a wipe: the run goes on when you're back in.
        if UnitIsDeadOrGhost("player") then return end
        local wing = inWing
        inRun, inWing, wingFrom = nil, nil, nil
        -- Hearthed out to repair, or gave up: only over if its quests are done.
        if QuestsDone(inst, wing) and (wing or not inst.wings) then I:EndOfRun(inst, wing) end
    end
end
ns:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(1, WhereAmI) end)
ns:On("ZONE_CHANGED_NEW_AREA", function() C_Timer.After(1, WhereAmI) end)
ns:On("ZONE_CHANGED_INDOORS", function()
    local inst = Route()
    if inst and inRun == inst.id and inWing then Learn(inst, inWing) end
end)
ns:On("PLAYER_LOGIN", function() C_Timer.NewTicker(0.5, Remember) end)

local function BossDied(name)
    local inst = Route()
    name = type(name) == "string" and strlower(name) or nil
    if not (inst and name and inRun == inst.id) then return end
    local wing
    for _, w in ipairs(inst.wings or {}) do
        for _, boss in ipairs(w.bosses or {}) do
            if strlower(boss) == name then wing = w.key end
        end
    end
    if wing then
        SetWing(inst, wing, "boss")
    else
        local final = false
        for _, boss in ipairs(inst.bosses or {}) do
            if strlower(boss) == name then final = true end
        end
        if not final or inst.wings then return end
    end
    C_Timer.After(3, function() I:EndOfRun(inst, wing) end) -- time to loot
end
ns:On("ENCOUNTER_END", function(_, name, _, _, success) if success == 1 then BossDied(name) end end)
ns:On("BOSS_KILL", function(_, name) BossDied(name) end)

-- /fg dungeons
function I:PrintCurrent()
    local list = self:Current()
    if #list == 0 then
        ns:Print("No dungeon in your level range has quests left for you.")
        return
    end
    for i, entry in ipairs(list) do
        ns:Print(("%d. %s (levels %d-%d): %d quest%s left%s"):format(i, entry.inst.name, entry.inst.from, entry.inst.to,
            #entry.open, #entry.open == 1 and "" or "s", ns.char.instance == entry.inst.id and "  |cff8fd16a<- guiding|r" or ""))
    end
    ns:Print("/fg dungeon <number> to be guided there, /fg dungeon stop to go back to questing.")
end

function I:Command(arg)
    arg = strlower(strtrim(arg or ""))
    if arg == "stop" or arg == "off" then return self:Stop() end
    local entry = self:Current()[tonumber(arg) or 0]
    if entry then return self:Start(entry.inst) end
    self:PrintCurrent()
end

ns:On("PLAYER_LEVEL_UP", function() C_Timer.After(2, function() I:Check() end) end)
ns:On("PLAYER_LOGIN", function() C_Timer.After(6, function() I:Check() end) end)
ns:On("QUEST_TURNED_IN", function() C_Timer.After(2, function() I:Check() end) end)
