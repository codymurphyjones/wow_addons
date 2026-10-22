local _, ns = ...

-- Death recaps (C_DeathRecap): the last hits before a death, with who dealt them, the spell, the
-- amount and the victim's health. The meter gives every group member's death a recap ID; your own
-- latest recap is also readable without one. Read by the shared DeathRecap.lua (addons/shared),
-- which BattleRecap, Mr. Miyagi and Fireside all use; this keeps the last KEEP hits and drops
-- the fields only BattleRecap needs.
local Recap = {}
ns.Recap = Recap

local DR = ns.DeathRecap
local KEEP = 12 -- hits kept per death
local DROP = { "school", "resisted", "blocked", "absorbed", "glancing", "crushing", "srcFull", "srcGUID", "srcClass", "hidden", "pet", "pvp" }

local function Slim(hits)
    for _, h in ipairs(hits) do
        for _, k in ipairs(DROP) do h[k] = nil end
    end
    return DR.Trim(hits, KEEP)
end

-- A recap as hits, oldest first (the killing blow last), trimmed to the last KEEP; and the
-- victim's max health. id nil = your own latest recap.
function Recap.Read(id)
    local hits, maxHp = DR.Read(id)
    if not hits then return nil end
    return Slim(hits), maxHp
end

-- Your own recap after you die, retried while it isn't ready. done(hits, maxHp) or done(nil).
function Recap.ReadOwnAfterDeath(done)
    DR.ReadOwnAfterDeath(function(hits, maxHp)
        done(hits and Slim(hits), maxHp)
    end)
end

-- Plain text for one hit: "Shadow Bolt 412 (crit) from Defias Wizard".
function Recap.Describe(h)
    return ("%s %s%s%s"):format(h.spell or "?", h.amount and tostring(h.amount) or "?", h.crit and " (crit)" or "",
        h.src and (" from " .. h.src) or "")
end
