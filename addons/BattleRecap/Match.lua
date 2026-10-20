local _, ns = ...
local W = ns.Widgets

-- Battleground and arena matches: the deaths of the current match (for "killed you 3 times this
-- match"), and a summary card when it ends, with your line from the scoreboard. The last few
-- summaries are saved (BattleRecapDB.matches); /brecap match reopens the latest.
local M = {}
ns.Match = M

local MAX_MATCHES = 5
local STALE = 3 * 3600 -- a match "in progress" older than this is from another session
local WIDTH, HEIGHT = 380, 380

local Readable, SafeCall = ns.Log.Readable, ns.Log.SafeCall
local function Num(v) v = Readable(v); return type(v) == "number" and v or nil end
local function Str(v) v = Readable(v); return (type(v) == "string" and v ~= "") and v or nil end
local function Short(name) return name and (name:match("^([^%-]+)") or name) end

local function Current() return BattleRecapDB.currentMatch end

---------------------------------------------------------------------------
-- Tracking
---------------------------------------------------------------------------

-- Starts a match on entering a battleground or arena; a /reload inside it keeps the one going.
function M:OnEnterWorld()
    local kind = ns.Where()
    if kind ~= "bg" and kind ~= "arena" then
        BattleRecapDB.currentMatch = nil
        return
    end
    local zone = GetRealZoneText and GetRealZoneText() or GetZoneText()
    local cur = Current()
    if cur and not cur.done and cur.zone == zone and time() - (cur.start or 0) < STALE then return end
    BattleRecapDB.currentMatch = { zone = zone, kind = kind, start = time(), deaths = {} }
end

-- A death in the current match (from ns:AddRecap, before Stats:Record counts it).
function M:AddDeath(recap)
    local cur = Current()
    if not cur or cur.done or recap.test or recap.kind ~= cur.kind then return end
    local k, T = recap.killer or {}, recap.totals or {}
    cur.deaths[#cur.deaths + 1] = {
        time = recap.time, name = k.name, key = ns.Stats.Key(k), class = k.class, env = k.env,
        spell = k.spell, icon = k.icon, amount = k.amount, damage = T.damage, duration = recap.duration,
    }
end

-- How many times this killer has got you in the current match.
function M:KillsBy(key)
    local cur = Current()
    if not cur or cur.done or not key then return nil end
    local n = 0
    for _, d in ipairs(cur.deaths) do
        if d.key == key then n = n + 1 end
    end
    return n
end

---------------------------------------------------------------------------
-- The end of a match
---------------------------------------------------------------------------

-- Your line on the scoreboard: { killingBlows, honorableKills, deaths, honor, damage, healing }.
local function ReadScore()
    local guid, me = UnitGUID("player"), UnitName("player")
    local info
    if C_PvP and C_PvP.GetScoreInfoByPlayerGuid then info = SafeCall(C_PvP.GetScoreInfoByPlayerGuid, guid) end
    local n = GetNumBattlefieldScores and Num(SafeCall(GetNumBattlefieldScores)) or 0
    if type(info) ~= "table" and C_PvP and C_PvP.GetScoreInfo then
        for i = 1, n do
            local s = SafeCall(C_PvP.GetScoreInfo, i)
            if type(s) == "table" and (Str(s.guid) == guid or Short(Str(s.name)) == me) then info = s; break end
        end
    end
    if type(info) == "table" then
        return {
            killingBlows = Num(info.killingBlows), honorableKills = Num(info.honorableKills), deaths = Num(info.deaths),
            honor = Num(info.honorGained), damage = Num(info.damageDone), healing = Num(info.healingDone),
        }
    end
    -- Older clients: GetBattlefieldScore(i) -> name, killingBlows, honorableKills, deaths, honorGained, ...
    if GetBattlefieldScore then
        for i = 1, n do
            local ok, name, kb, hk, deaths, honor = pcall(GetBattlefieldScore, i)
            if ok and Short(Str(name)) == me then
                return { killingBlows = Num(kb), honorableKills = Num(hk), deaths = Num(deaths), honor = Num(honor) }
            end
        end
    end
end

-- "win", "loss" or nil when the game won't say.
local function ReadResult()
    local winner = C_PvP and C_PvP.GetActiveMatchWinner and Num(SafeCall(C_PvP.GetActiveMatchWinner))
    if winner == nil and GetBattlefieldWinner then winner = Num(SafeCall(GetBattlefieldWinner)) end
    local mine = GetBattlefieldArenaFaction and Num(SafeCall(GetBattlefieldArenaFaction))
    if winner == nil or mine == nil or winner > 1 then return nil end
    return winner == mine and "win" or "loss"
end

function M:OnComplete()
    local cur = Current()
    if not cur or cur.done then return end
    cur.done = true
    if RequestBattlefieldScoreData then SafeCall(RequestBattlefieldScoreData) end
    -- The scoreboard fills in a moment after the match ends.
    C_Timer.After(1.5, function()
        local summary = {
            zone = cur.zone, kind = cur.kind, start = cur.start, finish = time(), deaths = cur.deaths,
            score = ReadScore(), result = ReadResult(),
        }
        local list = BattleRecapDB.matches
        table.insert(list, 1, summary)
        while #list > MAX_MATCHES do table.remove(list) end
        ns.Stats:RecordMatch(#cur.deaths)
        if BattleRecapDB.matchCard then M:Show(1) end
    end)
end

---------------------------------------------------------------------------
-- The card
---------------------------------------------------------------------------

local f

local COLS = { { "", 220, "LEFT" }, { "", 100, "RIGHT" } }

-- The saved recap of a death in a match, if it's still in the history.
local function FindRecap(t)
    for i, recap in ipairs(ns:History()) do
        if recap.time == t then return i end
    end
end

local function Create()
    BattleRecapDB.matchPos = BattleRecapDB.matchPos or { point = "CENTER", x = 0, y = 60 }
    f = W.MakeWindow("BattleRecapMatch", WIDTH, HEIGHT, "Match summary", BattleRecapDB.matchPos)
    f.result = W.Label(f, "", "BattleRecapGameFontNormalLarge", 12, -36, WIDTH - 24)
    f.score = W.Label(f, "", "BattleRecapGameFontHighlightSmall", 12, -60, WIDTH - 24)
    f.score:SetSpacing(3)
    local holder = CreateFrame("Frame", nil, f)
    holder:SetPoint("TOPLEFT", 10, -104); holder:SetPoint("BOTTOMRIGHT", -6, 10)
    f.table = W.CreateTable(holder, COLS, { noHeader = true })
end

local function Duration(s)
    s = math.max(0, s or 0)
    return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

function M:Render(m)
    local result = m.result == "win" and "|cff55ff55Victory|r" or m.result == "loss" and "|cffff5555Defeat|r" or "Match over"
    f.result:SetText(result .. "  |cffd0d0d0" .. (m.zone or "?") .. "|r")
    f.subtitle:SetText(("%s  %s, %s long"):format(ns.KIND_LABELS[m.kind] or "", date("%m/%d %H:%M", m.finish or m.start),
        Duration((m.finish or 0) - (m.start or 0))))

    local lines = {}
    local s = m.score
    if s then
        local parts = {}
        if s.killingBlows then parts[#parts + 1] = "|cffffffff" .. s.killingBlows .. "|r killing blows" end
        if s.honorableKills then parts[#parts + 1] = "|cffffffff" .. s.honorableKills .. "|r honorable kills" end
        if s.deaths then parts[#parts + 1] = "|cffffffff" .. s.deaths .. "|r deaths" end
        if s.honor then parts[#parts + 1] = "|cffffffff" .. ns.Num(s.honor) .. "|r honor" end
        if #parts > 0 then lines[#lines + 1] = table.concat(parts, "  |cff445566-|r  ") end
        local more = {}
        if s.damage then more[#more + 1] = "Damage done |cffffffff" .. ns.Num(s.damage) .. "|r" end
        if s.healing then more[#more + 1] = "healing |cffffffff" .. ns.Num(s.healing) .. "|r" end
        if #more > 0 then lines[#lines + 1] = table.concat(more, ", ") end
    else
        lines[1] = "|cff8899aaThe scoreboard wasn't readable.|r"
    end
    f.score:SetText(table.concat(lines, "\n"))

    local items = {}
    local deaths = m.deaths or {}
    local taken = 0
    for _, d in ipairs(deaths) do taken = taken + (d.damage or 0) end
    items[#items + 1] = { section = true, cells = { ("Your deaths: %d%s"):format(#deaths,
        #deaths > 0 and ("  |cff8899aa%s damage taken|r"):format(ns.Num(taken)) or "") } }
    if #deaths == 0 then items[#items + 1] = { cells = { "|cff55ff55You didn't die once.|r" } } end
    for _, d in ipairs(deaths) do
        local who = d.env and ("|cffffd100" .. (d.name or "?") .. "|r") or ns.ColorName(d.name, d.class)
        local index = FindRecap(d.time)
        items[#items + 1] = {
            icon = d.icon or ns.UNKNOWN_ICON,
            cells = { who .. "  |cffd0d0d0" .. (d.spell or "?") .. "|r", date("%H:%M", d.time) },
            colors = { [2] = W.MUTED },
            onClick = index and function() ns.Popup:Show(FindRecap(d.time) or index) end or nil,
            onEnter = function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(who, 1, 1, 1)
                GameTooltip:AddDoubleLine("Killing blow", (d.spell or "?") .. " " .. ns.Num(d.amount), 0.75, 0.8, 0.85, 1, 1, 1)
                GameTooltip:AddDoubleLine("Damage taken", ns.Num(d.damage) .. " in " .. ns.Secs(d.duration), 0.75, 0.8, 0.85, 1, 1, 1)
                GameTooltip:AddLine(FindRecap(d.time) and "Click: show this recap" or "This recap is no longer saved", 0.5, 0.6, 0.7)
                GameTooltip:Show()
            end,
        }
    end

    -- Who got you most.
    local killers, list = {}, {}
    for _, d in ipairs(deaths) do
        if not d.env and d.name then
            local key = d.key or d.name
            if not killers[key] then
                killers[key] = { name = d.name, class = d.class, n = 0 }
                list[#list + 1] = killers[key]
            end
            killers[key].n = killers[key].n + 1
        end
    end
    table.sort(list, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.name < b.name end)
    if #list > 0 then
        items[#items + 1] = { section = true, cells = { "Top killers" } }
        for i = 1, math.min(3, #list) do
            local e = list[i]
            items[#items + 1] = { cells = { ns.ColorName(e.name, e.class), e.n == 1 and "1 kill" or (e.n .. " kills") } }
        end
    end
    f.table:Set(items)
end

-- Shows the saved match summary at index (1 = the latest).
function M:Show(index)
    local m = BattleRecapDB.matches[index or 1]
    if not m then return false end
    if not f then Create() end
    self:Render(m)
    f:Show()
    return true
end

function M:Hide() if f then f:Hide() end end

function M:IsShown() return f and f:IsShown() or false end

-- A made-up match, for /brecap test match.
function M:Test()
    local now = time()
    local deaths = {}
    for i, row in ipairs({ { "Stabbyface", "ROGUE", "Eviscerate" }, { "Smashgrip", "WARRIOR", "Mortal Strike" },
        { "Stabbyface", "ROGUE", "Ambush" } }) do
        deaths[i] = { time = now - (4 - i) * 180, name = row[1], key = row[1], class = row[2], spell = row[3],
            icon = ns.SpellIcon(nil, row[3]), amount = 900 + i * 100, damage = 4000 + i * 300, duration = 5 + i }
    end
    table.insert(BattleRecapDB.matches, 1, {
        zone = "Warsong Gulch (test)", kind = "bg", start = now - 900, finish = now, deaths = deaths, result = "win",
        score = { killingBlows = 4, honorableKills = 17, deaths = 3, honor = 412, damage = 128400, healing = 9100 },
        test = true,
    })
    while #BattleRecapDB.matches > MAX_MATCHES do table.remove(BattleRecapDB.matches) end
    self:Show(1)
end
