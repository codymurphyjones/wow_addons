local _, ns = ...

-- Reads what killed you from Blizzard's death recap (C_DeathRecap). This client (WoW Forever, the
-- 12.x engine) forbids addons the combat log and hides health in combat as "secret" values, but
-- the recap of your last death is readable: every hit in your final seconds, with its source,
-- spell, amount, overkill and your health at the time (see HeadHunter/Detection/ForeverDeaths.lua).
local Log = {}
ns.Log = Log

-- The recap may not be ready on the PLAYER_DEAD frame: try again at these delays.
local RETRY_DELAYS = { 0.3, 1, 2 }

local TYPE_PLAYER = 0x00000400
local TYPE_PET = 0x00001000
local TYPE_GUARDIAN = 0x00002000
local CONTROL_PLAYER = 0x00000100
local REACTION_HOSTILE = 0x00000040

local band = bit and bit.band or function(a, b) return a % (b * 2) >= b and b or 0 end

-- A value we may read, or nil for a secret one (which can't be compared or printed).
local function Readable(value)
    if value == nil then return nil end
    if canaccessvalue and not canaccessvalue(value) then return nil end
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

local function Num(value)
    value = Readable(value)
    return type(value) == "number" and value or nil
end

local function Str(value)
    value = Readable(value)
    return (type(value) == "string" and value ~= "") and value or nil
end

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end
Log.SafeCall, Log.Readable = SafeCall, Readable

-- Class token and name of a player GUID (nil for NPCs, pets and anything hidden).
local playerByGUID = {}
local function PlayerInfo(guid)
    if not guid then return nil end
    local cached = playerByGUID[guid]
    if cached == nil then
        cached = false
        if GetPlayerInfoByGUID then
            local ok, _, class, _, _, _, name = pcall(GetPlayerInfoByGUID, guid)
            if ok and (Str(class) or Str(name)) then cached = { class = Str(class), name = Str(name) } end
        end
        playerByGUID[guid] = cached
    end
    if cached then return cached.class, cached.name end
end

local ENV_NAMES = {
    FALLING = "Falling", DROWNING = "Drowning", FATIGUE = "Fatigue",
    FIRE = "Fire", LAVA = "Lava", SLIME = "Slime",
}

-- "Name-Realm" -> "Name"
local function ShortName(name)
    return name and (name:match("^([^%-]+)") or name)
end

-- One recap entry as a BattleRecap event (see Analysis.lua for the fields).
local function Convert(r)
    local sub = Str(r.event) or ""
    local e = {
        kind = "dmg", stamp = Num(r.timestamp),
        amount = Num(r.amount), overkill = Num(r.overkill), school = Num(r.school) or 1,
        resisted = Num(r.resisted), blocked = Num(r.blocked), absorbed = Num(r.absorbed),
        crit = Readable(r.critical) and true or nil, glancing = Readable(r.glancing) and true or nil,
        crushing = Readable(r.crushing) and true or nil,
        hpRaw = Num(r.currentHP),
    }
    if sub == "SWING_DAMAGE" then
        e.spellId, e.spell, e.melee = 0, "Melee", true
    elseif sub == "ENVIRONMENTAL_DAMAGE" then
        local env = Str(r.environmentalType)
        e.spellId, e.env = 0, true
        e.spell = ENV_NAMES[env and env:upper() or ""] or env or "Environment"
        e.src = e.spell
    else
        e.spellId = Num(r.spellId) or 0
        e.spell = Str(r.spellName)
        if not e.spell and e.spellId > 0 then
            if C_Spell and C_Spell.GetSpellName then e.spell = Str(SafeCall(C_Spell.GetSpellName, e.spellId))
            elseif GetSpellInfo then e.spell = Str(SafeCall(GetSpellInfo, e.spellId)) end
        end
        e.spell = e.spell or "Unknown spell"
        e.periodic = sub == "SPELL_PERIODIC_DAMAGE" or nil
        e.ranged = sub == "RANGE_DAMAGE" or nil
    end
    if not e.env then
        local guid = Str(r.sourceGUID)
        local class, guidName = PlayerInfo(guid)
        e.srcGUID, e.srcClass = guid, class
        e.src = ShortName(Str(r.sourceName)) or ShortName(guidName) or (Readable(r.hideCaster) and "Hidden") or "Unknown"
        e.srcFull = Str(r.sourceName) or guidName -- "Name-Realm" when cross-realm: for /targetexact and stats
        local flags = Num(r.sourceFlags)
        if flags then
            local isPlayer = band(flags, TYPE_PLAYER) ~= 0
            local petLike = band(flags, TYPE_PET) ~= 0 or band(flags, TYPE_GUARDIAN) ~= 0
            if not isPlayer and petLike then e.pet = true end
            -- A hit from an enemy player, or from a pet or totem an enemy player controls.
            if band(flags, REACTION_HOSTILE) ~= 0 and (isPlayer or (petLike and band(flags, CONTROL_PLAYER) ~= 0)) then
                e.pvp = true
            end
        elseif class and guid and guid:find("^Player") then
            e.pvp = true -- flags hidden, but a player GUID; in the open world only enemies can hit you
        end
    end
    -- Anything we couldn't read is flagged, so the windows can say the recap is incomplete.
    if not e.stamp or not e.amount then e.partial = true end
    return e
end

-- The latest recap as BattleRecap events, oldest first, or nil if there's none yet.
-- Times are made relative to the killing blow; health is your health after each hit.
function Log:Read()
    if not C_DeathRecap or not SafeCall(C_DeathRecap.HasRecapEvents) then return nil end
    local raw = SafeCall(C_DeathRecap.GetRecapEvents)
    if type(raw) ~= "table" or #raw == 0 then return nil end
    local maxHp = Num(SafeCall(C_DeathRecap.GetRecapMaxHealth))

    local events = {}
    for i, r in ipairs(raw) do
        if type(r) == "table" then
            local e = Convert(r)
            e.order = i
            events[#events + 1] = e
        end
    end
    if #events == 0 then return nil end
    -- Blizzard lists the killing blow first; sort by time, keeping their order for ties.
    table.sort(events, function(a, b)
        if a.stamp and b.stamp and a.stamp ~= b.stamp then return a.stamp < b.stamp end
        return a.order > b.order
    end)

    local last = events[#events]
    local deathStamp, firstStamp = last.stamp, events[1].stamp

    -- currentHP is your health before the hit on some clients and after it on others: after it,
    -- the killing blow shows 0.
    local before = last.hpRaw ~= nil and last.hpRaw > 0
    for _, e in ipairs(events) do
        e.rel = (e.stamp and deathStamp) and math.floor((e.stamp - deathStamp) * 100 + 0.5) / 100 or 0
        if e.hpRaw then
            if before then
                local taken = (e.amount or 0) - math.max(0, e.overkill or 0)
                e.hp = math.max(0, e.hpRaw - taken)
            else
                e.hp = e.hpRaw
            end
            e.hpMax = maxHp
        end
        e.hpRaw, e.order, e.stamp = nil, nil, nil
    end
    return events, maxHp, deathStamp, firstStamp
end

-- After a death: read the recap (retrying while it isn't ready), then call done(events, maxHp,
-- firstStamp), firstStamp being the server time of its earliest hit.
-- A recap identical to the last one we read is from an earlier death, and is waited out too.
local lastStamp
function Log:ReadAfterDeath(done)
    local attempt = 0
    local function Try()
        attempt = attempt + 1
        local events, maxHp, stamp, firstStamp = self:Read()
        local stale = events and stamp and stamp == lastStamp
        if events and not stale then
            lastStamp = stamp
            return done(events, maxHp, firstStamp)
        end
        if attempt < #RETRY_DELAYS then
            C_Timer.After(RETRY_DELAYS[attempt + 1] - RETRY_DELAYS[attempt], Try)
        else
            done(nil, maxHp)
        end
    end
    C_Timer.After(RETRY_DELAYS[1], Try)
end
