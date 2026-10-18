local _, ns = ...
local C, M = ns.Compat, ns.Media

-- Marks enemy players who heal: a green cross next to their name. Healers are spotted from the
-- combat log (direct heals cast on others), or from their spec in arenas where the client has it.
-- Midnight hides the combat log from addons, so there it only uses arena specs.
local Healer = { name = "HealerTracker" }
local healers = {} -- guid -> time last seen healing
local MEMORY = 300 -- seconds

local HEAL_EVENTS = { SPELL_HEAL = true, SPELL_PERIODIC_HEAL = false }
local HOSTILE = COMBATLOG_OBJECT_REACTION_HOSTILE or 0x40
local PLAYER = COMBATLOG_OBJECT_TYPE_PLAYER or 0x400

function Healer:Create(f)
    local t = (f.textLayer or f):CreateTexture(nil, "OVERLAY")
    t:SetTexture("Interface\\Buttons\\WHITE8X8")
    t:SetVertexColor(0.2, 0.95, 0.4, 1)
    -- A plus sign from two bars.
    t:SetSize(4, 14)
    local t2 = (f.textLayer or f):CreateTexture(nil, "OVERLAY")
    t2:SetTexture("Interface\\Buttons\\WHITE8X8")
    t2:SetVertexColor(0.2, 0.95, 0.4, 1)
    t2:SetSize(14, 4)
    t2:SetPoint("CENTER", t, "CENTER")
    t:Hide(); t2:Hide()
    f.healer = { t, t2 }
end

local function SetShown(f, shown) f.healer[1]:SetShown(shown); f.healer[2]:SetShown(shown) end

local function ArenaHealer(f)
    if not (GetArenaOpponentSpec and GetSpecializationInfoByID) then return false end
    for i = 1, 5 do
        if C.UnitIsUnit(f.unit.unitid, "arena" .. i) then
            local spec = GetArenaOpponentSpec(i)
            return spec and spec > 0 and select(5, GetSpecializationInfoByID(spec)) == "HEALER" or false
        end
    end
    return false
end

function Healer:Update(f)
    local u = f.unit
    if not ns.db.widgets.healer or not u.isPlayer or u.reaction == "FRIENDLY" then return SetShown(f, false) end
    local seen = u.guid and healers[u.guid]
    local yes = (seen and GetTime() - seen < MEMORY) or ArenaHealer(f)
    if not yes then return SetShown(f, false) end
    f.healer[1]:ClearAllPoints()
    f.healer[1]:SetPoint("RIGHT", f.name, "LEFT", -6, 0)
    SetShown(f, true)
end

function Healer:Clear(f) SetShown(f, false) end

ns.Plates:Register(Healer)

if CombatLogGetCurrentEventInfo and not C.HAS_SECRETS then
    ns:On("COMBAT_LOG_EVENT_UNFILTERED", function()
        local _, event, _, srcGUID, _, srcFlags, _, dstGUID = CombatLogGetCurrentEventInfo()
        if not HEAL_EVENTS[event] or srcGUID == dstGUID then return end
        if bit.band(srcFlags or 0, PLAYER) == 0 or bit.band(srcFlags or 0, HOSTILE) == 0 then return end
        local last, now = healers[srcGUID], GetTime()
        healers[srcGUID] = now
        if not last or now - last >= MEMORY then
            local f = ns.Plates:ForGUID(srcGUID)
            if f and f.active then Healer:Update(f) end
        end
    end)
end
ns:On("ARENA_PREP_OPPONENT_SPECIALIZATIONS", function() ns.Plates:Each(function(f) Healer:Update(f) end) end)
ns:On("PLAYER_ENTERING_WORLD", function() wipe(healers) end)
