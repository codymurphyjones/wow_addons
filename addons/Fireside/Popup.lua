local _, ns = ...
local C = ns.Compat

-- The party in chat: when you join a party, a line for each member; after that, a line for each
-- newcomer only. Each says what they're known for (the kudos that reached you, Marks.lua) and your
-- history with them. /fire party (and the minimap button's right-click) lists the whole party.
-- Also the run summary lines the Runs page shows. (The end of a run is the Campfire: Campfire.lua.)
local Popup = {}
ns.Popup = Popup

local known = {} -- the members you've already been told about, to spot newcomers

-- "Grommash Swiftarrow (level 30, Healer): 2 runs together (2 finished)", or "...: new to you".
local function Line(unit, full)
    local _, class = C.Call(UnitClass, unit)
    local p = ns.History:Get(full)
    local summary = ns.History:Summary(full, true)
    return ("%s |cffaaaaaa(level %s%s)|r: %s"):format(C.Colored(full, C.Str(class)), C.Num(C.Call(UnitLevel, unit)) or "?",
        p and p.lastRole and (", " .. (p.lastRole == "damager" and "damage" or p.lastRole)) or "", summary or "|cffaaaaaanew to you|r")
end

-- force: the whole party, asked for (/fire party, the minimap button). Otherwise only the members
-- in only (a set of names), and only with the option on.
function Popup:ShowParty(force, only, joined)
    if not (force or ns.db.options.popup) then return end
    if not IsInGroup() or IsInRaid() then
        if force then ns:Print("You're not in a party.", true) end
        return
    end
    local n = 0
    for _, unit in ipairs(C.GroupUnits()) do
        local full = C.UnitFull(unit)
        if full and (force or not only or only[full]) then
            n = n + 1
            ns:Print(((force or joined) and "In your party: " or "Joined: ") .. Line(unit, full), true)
        end
    end
    if force and n == 0 then ns:Print("Nobody else in your party yet.", true) end
end

-- On joining a party: everyone in it. Later: whoever joins.
local pending
ns:On("GROUP_ROSTER_UPDATE", function()
    if pending then return end
    pending = true
    C_Timer.After(1.5, function()
        pending = false
        if not IsInGroup() or IsInRaid() then wipe(known) return end
        local joined = next(known) == nil
        local now, newcomers = {}, {}
        for _, unit in ipairs(C.GroupUnits()) do
            local full = C.UnitFull(unit)
            if full then
                now[full] = true
                if not known[full] then newcomers[full] = true end
            end
        end
        known = now
        if next(newcomers) then Popup:ShowParty(false, newcomers, joined) end
    end)
end)

-- ---------------------------------------------------------------------------
-- Run summary (the Runs page)
-- ---------------------------------------------------------------------------

local DURATION = { days = false, alwaysHours = true }
local function Duration(run) return ns.Format.Duration((run.stop or time()) - run.start, DURATION) end

-- Lines describing a run: bosses, wipes, deaths by person, who caused the most.
function Popup.RunLines(run)
    local lines = {}
    lines[#lines + 1] = ("%s, %s. %d boss%s killed, %d wipe%s, %d death%s."):format(date("%m/%d %H:%M", run.start), Duration(run),
        ns.Run.BossKills(run), ns.Run.BossKills(run) == 1 and "" or "es", run.wipes or 0, (run.wipes or 0) == 1 and "" or "s",
        #run.deaths, #run.deaths == 1 and "" or "s")
    for _, name in ipairs(run.bossOrder or {}) do
        local b = run.bosses[name]
        lines[#lines + 1] = ("  %s: %d attempt%s, %s"):format(name, b.attempts, b.attempts == 1 and "" or "s",
            b.kills > 0 and "|cff59f28ckilled|r" or "|cffd9736bnot killed|r")
    end
    local died, caused = {}, {}
    for _, d in ipairs(run.deaths) do
        died[d.victim] = (died[d.victim] or 0) + 1
        for who, share in pairs(d.blame or {}) do caused[who] = (caused[who] or 0) + share * (d.weight or 1) end
    end
    local list = {}
    for who, n in pairs(caused) do list[#list + 1] = { who, n } end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    if #list > 0 then
        local parts = {}
        for i = 1, math.min(5, #list) do
            parts[#parts + 1] = ("%s %.1f (died %d)"):format(list[i][1], list[i][2], died[list[i][1]] or 0)
        end
        lines[#lines + 1] = "Deaths caused, most likely: " .. table.concat(parts, ", ")
    end
    -- Damage and healing over the whole run.
    local done, healed = {}, {}
    for _, f in ipairs(run.fights) do
        for name, p in pairs(f.stats or {}) do
            done[name] = (done[name] or 0) + (p.done or 0)
            healed[name] = (healed[name] or 0) + (p.healed or 0)
        end
    end
    local function Top(t)
        local best, n = nil, 0
        for name, v in pairs(t) do if v > n then best, n = name, v end end
        return best, n
    end
    local dps, dn = Top(done)
    local heal, hn = Top(healed)
    if dps then lines[#lines + 1] = ("Most damage: %s (%s)"):format(dps, AbbreviateNumbers and AbbreviateNumbers(dn) or dn) end
    if heal and hn > 0 then lines[#lines + 1] = ("Most healing: %s (%s)"):format(heal, AbbreviateNumbers and AbbreviateNumbers(hn) or hn) end
    -- What was said at the campfire.
    local kudos = {}
    for _, e in ipairs(run.kudos or {}) do
        kudos[#kudos + 1] = ("%s to %s: %s %s"):format(C.IsMe(e.from) and "you" or C.Short(e.from), C.IsMe(e.to) and "you" or C.Short(e.to),
            ns.Marks.Icon(e.k), ns.Marks.Label(e.k))
    end
    if #kudos > 0 then lines[#lines + 1] = "At the campfire: " .. table.concat(kudos, ";  ") end
    return lines
end
