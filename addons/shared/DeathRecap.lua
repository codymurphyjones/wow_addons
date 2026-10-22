local _, ns = ...
local S = ns.Secrets

-- Blizzard's death recap (C_DeathRecap), read once for every addon that wants it (addons/shared;
-- needs Secrets.lua first). This client (WoW Forever, the 12.x engine) forbids addons the combat
-- log and hides health in combat as "secret" values, but a death's recap is readable: every hit in
-- the victim's final seconds, with its source, spell, amount, overkill and health at the time. Your
-- own latest recap needs no ID; the damage meter gives every group member's death one.
--
-- Each hit, oldest first (the killing blow last):
--   rel        seconds before the killing blow (0 for it, negative before)
--   amount, overkill, school, resisted, blocked, absorbed; crit, glancing, crushing (true or nil)
--   hp         the victim's health after the hit (the client's currentHP, made consistent)
--   spellId, spell; melee, ranged, periodic, env, heal (true or nil)
--   src        who dealt it, short name (nil if hidden or unknown; hidden = true when the game hid it)
--   srcFull    "Name-Realm" when cross-realm; srcGUID; srcClass (players only); npcID (creatures)
--   player     the source is a player; pet = a pet or guardian; playerPet = one a player controls
--   pvp        an enemy player, or a pet or totem an enemy player controls
--   partial    something about it couldn't be read
local DR = {}
ns.DeathRecap = DR

-- The recap may not be ready on the PLAYER_DEAD frame: try again at these delays.
local RETRY_DELAYS = { 0.3, 1, 2 }

local TYPE_PLAYER, TYPE_PET, TYPE_GUARDIAN = 0x00000400, 0x00001000, 0x00002000
local CONTROL_PLAYER, REACTION_HOSTILE = 0x00000100, 0x00000040
local band = bit and bit.band or function(a, b) return a % (b * 2) >= b and b or 0 end

local ENV_NAMES = {
    FALLING = "Falling", DROWNING = "Drowning", FATIGUE = "Fatigue",
    FIRE = "Fire", LAVA = "Lava", SLIME = "Slime",
}

-- Class token and name of a player GUID (nil for NPCs, pets and anything hidden).
local playerByGUID = {}
local function PlayerInfo(guid)
    if not guid then return nil end
    local cached = playerByGUID[guid]
    if cached == nil then
        cached = false
        if GetPlayerInfoByGUID then
            local ok, _, class, _, _, _, name = pcall(GetPlayerInfoByGUID, guid)
            if ok and (S.Str(class) or S.Str(name)) then cached = { class = S.Str(class), name = S.Str(name) } end
        end
        playerByGUID[guid] = cached
    end
    if cached then return cached.class, cached.name end
end

local function Convert(r)
    local sub = S.Str(r.event) or ""
    local h = {
        stamp = S.Num(r.timestamp),
        amount = S.Num(r.amount), overkill = S.Num(r.overkill), school = S.Num(r.school) or 1,
        resisted = S.Num(r.resisted), blocked = S.Num(r.blocked), absorbed = S.Num(r.absorbed),
        crit = S.Readable(r.critical) and true or nil, glancing = S.Readable(r.glancing) and true or nil,
        crushing = S.Readable(r.crushing) and true or nil,
        hpRaw = S.Num(r.currentHP),
    }
    if sub == "SWING_DAMAGE" then
        h.spellId, h.spell, h.melee = 0, "Melee", true
    elseif sub == "ENVIRONMENTAL_DAMAGE" then
        local env = S.Str(r.environmentalType)
        h.spellId, h.env = 0, true
        h.spell = ENV_NAMES[env and env:upper() or ""] or env or "Environment"
    else
        h.spellId = S.Num(r.spellId) or 0
        h.spell = S.Str(r.spellName) or S.SpellName(h.spellId) or "Unknown spell"
        h.periodic = sub == "SPELL_PERIODIC_DAMAGE" or nil
        h.ranged = sub == "RANGE_DAMAGE" or nil
    end
    if sub:find("HEAL") then h.heal = true end
    if not h.env then
        local guid = S.Str(r.sourceGUID)
        local class, guidName = PlayerInfo(guid)
        h.srcGUID, h.srcClass = guid, class
        h.srcFull = S.Str(r.sourceName) or guidName
        h.src = S.Short(h.srcFull)
        h.hidden = S.Readable(r.hideCaster) and true or nil
        if guid then h.npcID = tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)")) end
        local flags = S.Num(r.sourceFlags)
        if flags then
            local isPlayer = band(flags, TYPE_PLAYER) ~= 0
            local petLike = band(flags, TYPE_PET + TYPE_GUARDIAN) ~= 0
            local byPlayer = petLike and band(flags, CONTROL_PLAYER) ~= 0
            h.player = isPlayer or nil
            h.pet = (not isPlayer and petLike) or nil
            h.playerPet = byPlayer or nil
            if band(flags, REACTION_HOSTILE) ~= 0 and (isPlayer or byPlayer) then h.pvp = true end
        elseif guid and guid:find("^Player%-") then
            -- Flags hidden, but a player GUID; in the open world only enemies can hit you.
            h.player = true
            if class then h.pvp = true end
        end
    end
    if not h.stamp or not h.amount then h.partial = true end
    return h
end

-- A recap as hits (above), oldest first; the victim's max health; and the server times of the
-- killing blow and the earliest hit. id nil = your own latest recap. nil when there's none.
function DR.Read(id)
    if not C_DeathRecap then return nil end
    if id == nil and not S.Call(C_DeathRecap.HasRecapEvents) then return nil end
    if id ~= nil and C_DeathRecap.HasRecapEvents and not S.Call(C_DeathRecap.HasRecapEvents, id) then return nil end
    local raw = S.Readable(id and S.Call(C_DeathRecap.GetRecapEvents, id) or S.Call(C_DeathRecap.GetRecapEvents))
    if type(raw) ~= "table" or #raw == 0 then return nil end
    local maxHp = S.Num(id and S.Call(C_DeathRecap.GetRecapMaxHealth, id) or S.Call(C_DeathRecap.GetRecapMaxHealth))

    local hits = {}
    for i, r in ipairs(raw) do
        if type(r) == "table" then
            local h = Convert(r)
            h.order = i
            hits[#hits + 1] = h
        end
    end
    if #hits == 0 then return nil end
    -- Blizzard lists the killing blow first; sort by time, keeping their order for ties.
    table.sort(hits, function(a, b)
        if a.stamp and b.stamp and a.stamp ~= b.stamp then return a.stamp < b.stamp end
        return a.order > b.order
    end)

    local last = hits[#hits]
    local deathStamp, firstStamp = last.stamp, hits[1].stamp
    -- currentHP can be the health before the hit or after it: after it, the killing blow
    -- shows 0.
    local before = last.hpRaw ~= nil and last.hpRaw > 0
    for _, h in ipairs(hits) do
        h.rel = (h.stamp and deathStamp) and math.floor((h.stamp - deathStamp) * 100 + 0.5) / 100 or 0
        if h.hpRaw then
            h.hp = before and math.max(0, h.hpRaw - ((h.amount or 0) - math.max(0, h.overkill or 0))) or h.hpRaw
        end
        h.hpRaw, h.order, h.stamp = nil, nil, nil
    end
    return hits, maxHp, deathStamp, firstStamp
end

-- The last n hits of a list (the killing blow last), in place.
function DR.Trim(hits, n)
    while hits and #hits > n do table.remove(hits, 1) end
    return hits
end

-- After you die: your recap, retrying while it isn't ready. done(hits, maxHp, firstStamp) or
-- done(nil, maxHp). A recap identical to the last one read is from an earlier death, and is
-- waited out too.
local lastStamp
function DR.ReadOwnAfterDeath(done)
    local attempt = 0
    local function Try()
        attempt = attempt + 1
        local hits, maxHp, stamp, firstStamp = DR.Read(nil)
        local stale = hits and stamp and stamp == lastStamp
        if hits and not stale then
            lastStamp = stamp
            return done(hits, maxHp, firstStamp)
        end
        if attempt < #RETRY_DELAYS then
            C_Timer.After(RETRY_DELAYS[attempt + 1] - RETRY_DELAYS[attempt], Try)
        else
            done(nil, maxHp)
        end
    end
    C_Timer.After(RETRY_DELAYS[1], Try)
end
