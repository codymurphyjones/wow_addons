local _, ns = ...
local C = ns.Compat

-- The clock for the job you took. Time counts while you're in the job's zone (travel is kept
-- apart), and everything you loot and the coin you pick up are added up and valued at market price.
-- Finished shifts go to the Work Log, and their pay per hour replaces the job's estimate.
local S = {}
ns.Session = S

local KEEP = 200 -- work log entries

S.current = nil -- { key, title, zone, start, secs, travel, items = { [id] = qty }, coin, estimate }

-- "You receive loot: %s." style messages -> Lua patterns with captures.
local function Pattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local pat = fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
    return "^" .. pat .. "$"
end

local LOOT_MULTI = { Pattern(LOOT_ITEM_SELF_MULTIPLE), Pattern(LOOT_ITEM_PUSHED_SELF_MULTIPLE) }
local LOOT_ONE = { Pattern(LOOT_ITEM_SELF), Pattern(LOOT_ITEM_PUSHED_SELF) }
-- Coin words ("Gold", "Silver", "Copper") from the game's own "%d Gold" strings.
local function CoinWord(fmt) return (fmt:gsub("%%d", ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local COIN = {
    { CoinWord(GOLD_AMOUNT or "%d Gold"), 10000 },
    { CoinWord(SILVER_AMOUNT or "%d Silver"), 100 },
    { CoinWord(COPPER_AMOUNT or "%d Copper"), 1 },
}

local function Secret(v)
    return (issecretvalue and issecretvalue(v)) or (canaccessvalue and not canaccessvalue(v)) or false
end

local function ParseLoot(msg)
    for _, pat in ipairs(LOOT_MULTI) do
        local link, n = pat and msg:match(pat)
        if link then return link, tonumber(n) or 1 end
    end
    for _, pat in ipairs(LOOT_ONE) do
        local link = pat and msg:match(pat)
        if link then return link, 1 end
    end
end

-- "You loot 1 Silver, 23 Copper": sums each coin word anywhere in the message.
local function ParseCoin(msg)
    local total = 0
    for _, c in ipairs(COIN) do
        if c[1] ~= "" then
            local n = msg:match("(%d+)%s*" .. c[1])
            if n then total = total + tonumber(n) * c[2] end
        end
    end
    return total
end

function S:Start(key, title, estimate)
    local j = ns.Jobs:Get(key)
    self.current = {
        key = key, title = title or key, zone = j and j.zone, kind = j and j.kind, start = time(),
        secs = 0, travel = 0, items = {}, coin = 0, estimate = estimate,
    }
    ns.char.shift = self.current
end

-- Market value of the goods so far.
function S:Value(sess)
    sess = sess or self.current
    if not sess then return 0 end
    local v = sess.coin or 0
    for id, n in pairs(sess.items) do v = v + (ns.Portfolio:Value(id) or 0) * n end
    return v
end

function S:PerHour(sess)
    sess = sess or self.current
    if not sess or sess.secs < 60 then return nil end
    return self:Value(sess) / sess.secs * 3600
end

function S:Stop()
    local s = self.current
    self.current, ns.char.shift = nil, nil
    if not s then return end
    s.stop = time()
    s.value = self:Value(s)
    if s.secs < 60 and s.value == 0 then return end
    table.insert(ns.db.sessions, 1, s)
    for i = #ns.db.sessions, KEEP + 1, -1 do ns.db.sessions[i] = nil end
    local st = ns.db.jobStats[s.key]
    if not st then st = { secs = 0, value = 0, runs = 0 }; ns.db.jobStats[s.key] = st end
    st.secs, st.value, st.runs = st.secs + s.secs, st.value + s.value, st.runs + 1
    ns.Jobs:Invalidate()
    local rate = s.secs > 0 and s.value / s.secs * 3600 or 0
    ns:Print(("Shift over: %s earned in %d min, %s an hour."):format(C.Money(s.value), math.floor(s.secs / 60), C.Money(rate)))
end

-- ---------------------------------------------------------------------------

local function InJobZone()
    local s = S.current
    if not (s and s.zone and C_Map and C_Map.GetBestMapForUnit) then return true end
    local map = C_Map.GetBestMapForUnit("player")
    while map do
        if map == s.zone then return true end
        local info = C_Map.GetMapInfo(map)
        map = info and info.parentMapID
        if not map or map == 0 or (info and info.mapType and info.mapType <= 2) then break end
    end
    return false
end

local ticker = CreateFrame("Frame")
local acc = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    local s = S.current
    if not s then return end
    acc = acc + elapsed
    if acc < 1 then return end
    if InJobZone() and not UnitIsAFK("player") then s.secs = s.secs + acc else s.travel = s.travel + acc end
    acc = 0
    if ns.Tracker and ns.Tracker.Tick then ns.Tracker:Tick() end
end)

ns:On("CHAT_MSG_LOOT", function(msg)
    local s = S.current
    if not s or Secret(msg) or type(msg) ~= "string" then return end
    local link, n = ParseLoot(msg)
    local id = link and C.IDFromLink(link)
    if not id then return end
    s.items[id] = (s.items[id] or 0) + n
    s.lastLoot = { id = id, n = n, t = GetTime() }
    ns.Portfolio:AddLot(id, n, 0, "farm")
    ns:Changed()
end)

ns:On("CHAT_MSG_MONEY", function(msg)
    local s = S.current
    if not s or Secret(msg) or type(msg) ~= "string" then return end
    s.coin = s.coin + ParseCoin(msg)
    ns:Changed()
end)

-- A shift survives /reload and logging out.
ns:OnLoad(function()
    if ns.char.activeJob and type(ns.char.shift) == "table" then S.current = ns.char.shift end
end)
