local _, ns = ...

-- Every character on the account, kept up to date while you play: gold, level, XP, rested XP,
-- where they are and when they were last seen. Gold and Alts read it; Mail adds each character's
-- inbox. Account-wide (ns.db.characters), keyed ns.CharKey(), outside profiles. Each entry keeps
-- its own name and realm; entries of alts not logged in since 0.1.5 are still keyed "Realm - Name".
local Chars = {}
ns.Characters = Chars

-- Which characters a plugin counts.
Chars.SCOPES = {
    { "char", "Only this character" },
    { "faction", "This realm and faction" },
    { "realm", "This realm" },
    { "all", "Every realm" },
}

local function DB() return ns.db.characters end

function Chars:Me() return DB()[ns.CharKey()] end
-- info defaults to the entry saved under key; an old "Realm - Name" key is read when it has none.
-- Characters are keyed by their "Given Family"; entries saved before kept only the given name in
-- info.name, so a key that starts with it wins.
function Chars.Name(key, info)
    info = info or DB()[key]
    local name = info and info.name
    if name and not name:find(" ", 1, true) and key:sub(1, #name + 1) == name .. " " then return key end
    return name or key:match(" %- (.+)$") or key
end
function Chars.Realm(key, info)
    info = info or DB()[key]
    return (info and info.realm) or key:match("^(.-) %- ") or ""
end

-- The name in its class color.
function Chars.ClassName(key, info)
    return ns.Units.Colored(Chars.Name(key, info), info and info.class, { plain = true })
end

-- Writes everything we can read about the character you're playing.
function Chars:Refresh()
    if not ns.db then return end
    local key = ns.CharKey()
    local info = DB()[key] or {}
    DB()[key] = info
    local _, class = UnitClass("player")
    info.name = ns.Units.CharKey() or info.name
    info.realm = ns.Units.RealmLabel()
    info.class, info.faction = class, UnitFactionGroup("player")
    info.copper = GetMoney()
    info.level = UnitLevel("player")
    info.xp, info.xpMax = UnitXP("player"), UnitXPMax("player")
    info.rested = GetXPExhaustion and GetXPExhaustion() or 0
    info.resting = IsResting and IsResting() and true or false
    info.zone = GetRealZoneText and GetRealZoneText() or info.zone
    info.subzone = (GetMinimapZoneText and GetMinimapZoneText()) or info.subzone
    info.bind = GetBindLocation and GetBindLocation() or info.bind
    info.seen = time()
    return info
end

-- { key, info } for the characters in a scope, unsorted.
function Chars:All(scope)
    local realm, faction, me = ns.Units.RealmLabel(), UnitFactionGroup("player"), ns.CharKey()
    local out = {}
    for key, info in pairs(DB()) do
        local same = Chars.Realm(key, info) == realm
        local ok = scope == "all" or key == me
            or (scope == "realm" and same)
            or (scope == "faction" and same and info.faction == faction)
        if ok then out[#out + 1] = { key = key, info = info } end
    end
    return out
end

function Chars:Forget(key)
    if key == ns.CharKey() then return false end
    DB()[key] = nil
    return true
end

-- Rested XP a logged-out character has built up since: 5% of a level every 8 hours in an inn or
-- city, a quarter of that elsewhere, up to a level and a half. The character you're playing reports
-- its own.
function Chars:Rested(key, info)
    if key == ns.CharKey() then return info.rested or 0 end
    if not info.xpMax or info.xpMax == 0 then return 0 end
    local hours = math.max(0, time() - (info.seen or time())) / 3600
    local rate = (info.resting and 0.05 or 0.0125) * info.xpMax / 8
    return math.min(info.xpMax * 1.5, (info.rested or 0) + hours * rate)
end

-- "now", "5m", "3h", "2d"
local AGO = { justNow = 120, suffix = "", missing = "?" }
function Chars.Ago(t) return ns.Format.Ago(t, AGO) end

ns:OnLoad(function()
    -- Older versions kept only gold, in ns.db.gold.
    if type(ns.db.gold) == "table" then
        for key, g in pairs(ns.db.gold) do
            local info = DB()[key] or {}
            DB()[key] = info
            info.copper = info.copper or g.copper
            info.class = info.class or g.class
            info.faction = info.faction or g.faction
            info.seen = info.seen or g.seen
        end
        ns.db.gold = nil
    end
end)

-- /played, asked for quietly once per session: the game prints it to chat unless we hold that back.
local askedPlayed
function Chars:RequestPlayed()
    if not RequestTimePlayed then return end
    askedPlayed = true
    RequestTimePlayed()
end
-- Total and this-level played time right now, counting the time since the last answer.
function Chars:Played(key, info)
    if not info.played then return nil end
    local since = key == ns.CharKey() and math.max(0, time() - (info.playedAt or time())) or 0
    return info.played + since, (info.playedLevel or 0) + since
end
if ChatFrame_DisplayTimePlayed then
    local original = ChatFrame_DisplayTimePlayed
    ChatFrame_DisplayTimePlayed = function(...)
        if askedPlayed then askedPlayed = false; return end
        return original(...)
    end
end
ns:On("TIME_PLAYED_MSG", function(total, level)
    local me = Chars:Refresh()
    if me then me.played, me.playedLevel, me.playedAt = total, level, time() end
end)
ns:On("PLAYER_LOGIN", function() C_Timer.After(5, function() Chars:RequestPlayed() end) end)

-- Saved instances on this character: { name, resetAt, done, total, raid }.
function Chars:SaveLockouts()
    if not (GetNumSavedInstances and GetSavedInstanceInfo) then return end
    local me = Chars:Refresh()
    if not me then return end
    local list = {}
    for i = 1, GetNumSavedInstances() do
        local name, _, reset, _, locked, _, _, isRaid, _, _, total, done = GetSavedInstanceInfo(i)
        if name and locked and reset and reset > 0 then
            list[#list + 1] = { name = name, resetAt = time() + reset, done = done, total = total, raid = isRaid and true or false }
        end
    end
    me.lockouts = list
end
ns:On("UPDATE_INSTANCE_INFO", function() Chars:SaveLockouts() end)
-- C_Timer only takes Lua functions, so the game's own RequestRaidInfo goes inside one.
ns:On("PLAYER_LOGIN", function() if RequestRaidInfo then C_Timer.After(3, function() RequestRaidInfo() end) end end)

local function Refresh() Chars:Refresh() end
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_MONEY", "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION",
    "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "PLAYER_UPDATE_RESTING", "HEARTHSTONE_BOUND", "PLAYER_LOGOUT" }) do
    ns:On(event, Refresh)
end
