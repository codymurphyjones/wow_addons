local _, ns = ...

-- Reads what killed you from Blizzard's death recap (C_DeathRecap). This client (WoW Forever, the
-- 12.x engine) forbids addons the combat log and hides health in combat as "secret" values, but
-- the recap of your last death is readable: every hit in your final seconds, with its source,
-- spell, amount, overkill and your health at the time (see HeadHunter/Detection/ForeverDeaths.lua).
-- The reading itself is the shared DeathRecap.lua (addons/shared), which Mr. Miyagi and Group
-- History use too; this turns its hits into BattleRecap events.
local Log = {}
ns.Log = Log

local S, DR = ns.Secrets, ns.DeathRecap
Log.SafeCall, Log.Readable = S.Call, S.Readable

-- Fields of the shared reader's hits that BattleRecap's events don't have.
local DROP = { "player", "playerPet", "npcID", "heal", "hidden" }

-- One shared hit as a BattleRecap event (see Analysis.lua for the fields).
local function Convert(h, maxHp)
    h.kind = "dmg"
    if h.env then
        h.src = h.spell
    else
        h.src = h.src or (h.hidden and "Hidden") or "Unknown"
    end
    if h.hp then h.hpMax = maxHp end
    for _, k in ipairs(DROP) do h[k] = nil end
    return h
end

-- The latest recap as BattleRecap events, oldest first, or nil if there's none yet.
-- Times are made relative to the killing blow; health is your health after each hit.
function Log:Read()
    local events, maxHp, deathStamp, firstStamp = DR.Read(nil)
    if not events then return nil end
    for _, e in ipairs(events) do Convert(e, maxHp) end
    return events, maxHp, deathStamp, firstStamp
end

-- After a death: read the recap (retrying while it isn't ready), then call done(events, maxHp,
-- firstStamp), firstStamp being the server time of its earliest hit.
-- A recap identical to the last one we read is from an earlier death, and is waited out too.
function Log:ReadAfterDeath(done)
    DR.ReadOwnAfterDeath(function(events, maxHp, firstStamp)
        if not events then return done(nil, maxHp) end
        for _, e in ipairs(events) do Convert(e, maxHp) end
        done(events, maxHp, firstStamp)
    end)
end
