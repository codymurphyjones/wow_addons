local _, ns = ...
local C, M = ns.Compat, ns.Media

-- Marks enemy players who heal: a green cross next to their name, from their spec in arenas when
-- the client tells it. WoW Forever gives addons no combat log, so heals cast can't be watched.
local Healer = { name = "HealerTracker" }

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
    if not ArenaHealer(f) then return SetShown(f, false) end
    f.healer[1]:ClearAllPoints()
    f.healer[1]:SetPoint("RIGHT", f.name, "LEFT", -6, 0)
    SetShown(f, true)
end

function Healer:Clear(f) SetShown(f, false) end

ns.Plates:Register(Healer)

ns:On("ARENA_PREP_OPPONENT_SPECIALIZATIONS", function() ns.Plates:Each(function(f) Healer:Update(f) end) end)
