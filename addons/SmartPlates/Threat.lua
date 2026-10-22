local _, ns = ...
local C = ns.Compat

-- Threat level (colour, scale, alpha, glow) and the threat percentage on every plate.
--
-- The percentage uses one scale for everyone: 100% is where aggro changes hands.
--   * Not holding aggro: Blizzard's scaled threat. It reaches 100% exactly when you pull,
--     with the 110% melee / 130% ranged rule already built in.
--   * Holding aggro: 100 / (highest scaled threat of anyone else) * 100. If the next person is
--     at half of what it takes to pull, you hold 200%. If they're about to pull, you're at 100%.
local Threat = {}
ns.Threat = Threat

local LEVEL_BY_STATUS = { [0] = "LOW", [1] = "MEDIUM", [2] = "MEDIUM", [3] = "HIGH" }
Threat.LEVELS = { "LOW", "MEDIUM", "HIGH", "OFFTANK" }

-- Creatures that tank for their owner (Black Ox Statue, Treants, Earth Elemental).
local OFFTANK_NPCS = { [61146] = true, [103822] = true, [95072] = true, [15352] = true }

local groupUnits = {}

local function NpcID(unit)
    local guid = UnitGUID(unit)
    if not guid or not C.AllReadable(guid) then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Pet" or kind == "Vehicle" then return tonumber(id) end
end

local function InInstance()
    local inInstance, kind = IsInInstance()
    return inInstance and kind ~= "pvp" and kind ~= "arena"
end

-- Does this unit get threat feedback at all?
function Threat:Applies(u)
    local db = ns.db.threat
    if not db.enabled or not u.unitid then return false end
    if u.isPlayer or u.reaction == "FRIENDLY" or not u.canAttack then return false end
    if u.classification == "minus" and not db.minor then return false end
    if db.instancesOnly and not InInstance() then return false end
    return true
end

local function GroupTarget(target)
    return C.UnitIsUnit(target, "player") or C.UnitIsUnit(target, "pet")
        or C.Value(UnitInParty, target) or C.Value(UnitInRaid, target) or false
end

local function IsOffTanked(unit)
    if not ns.db.threat.offTank or not ns.Role:IsTank() then return false end
    local target = unit .. "target"
    if not C.Value(UnitExists, target) or C.UnitIsUnit(target, "player") then return false end
    local other = C.UnitIsUnit(target, "pet") or ns.Role:UnitIsTank(target) or OFFTANK_NPCS[NpcID(target) or 0]
    if not other then return false end
    local status = C.ThreatSituation(target, unit)
    return status ~= nil and status > 1
end

function Threat:Level(u)
    local unit = u.unitid
    local status
    if not ns.db.threat.heuristic then status = C.ThreatSituation("player", unit) end
    local level
    if status then
        level = LEVEL_BY_STATUS[status]
    else
        -- No threat table entry (or heuristic mode): judge from what the mob is attacking.
        local inCombat = UnitAffectingCombat(unit)
        if not C.AllReadable(inCombat) or not inCombat then return nil end
        local target = unit .. "target"
        if C.UnitIsUnit(target, "player") or C.UnitIsUnit(target, "vehicle") then
            level = "HIGH"
        elseif ns.db.threat.heuristic or GroupTarget(target) then
            level = "LOW"
        else
            return nil
        end
    end
    if level ~= "HIGH" and IsOffTanked(unit) then level = "OFFTANK" end
    return level
end

-- The aggro percentage (see the top of the file). math.huge means nobody else has threat.
function Threat:Percent(unit)
    local tanking, _, scaled = C.DetailedThreat("player", unit)
    if scaled == nil then return nil end
    if not tanking then return scaled end
    local top = 0
    for _, gu in ipairs(C.GroupUnits(groupUnits)) do
        if C.Value(UnitExists, gu) and not C.UnitIsUnit(gu, "player") then
            local _, _, other = C.DetailedThreat(gu, unit)
            if other and other > top then top = other end
        end
    end
    if top <= 0 then return math.huge end
    return 10000 / top
end

function Threat.Format(pct)
    if not pct then return "" end
    if pct == math.huge then return "MAX" end
    if pct > 999 then return ">999%" end
    return ("%d%%"):format(math.floor(pct + 0.5))
end

function Threat:ShowPercent(u)
    local mode = ns.db.threat.percent.show
    if mode == "never" or (u.threatPct == nil and not u.hasHiddenThreat) then return false end
    if mode == "always" then return true end
    return IsInGroup() or UnitExists("pet")
end

-- Updates u.threatLevel and u.threatPct, then tells the plate's elements.
function Threat:Evaluate(f)
    local u = f.unit
    if not u or not u.unitid then return end
    local level, pct, hidden
    if self:Applies(u) then
        level = self:Level(u)
        pct = self:Percent(u.unitid)
        if pct == nil then
            -- The client hides the numbers (WoW Forever / Midnight): show Blizzard's own scaled
            -- threat unread. Tanks see 100% rather than their lead, which needs arithmetic.
            local scaled = C.ScaledThreatAny("player", u.unitid)
            if C.IsSecret(scaled) then hidden = scaled end -- never compare it, even with nil
        end
    end
    -- A hidden value can't be compared, so plates showing one always redraw.
    local hasHidden = C.IsSecret(hidden)
    local changed = hasHidden or u.hasHiddenThreat or level ~= u.threatLevel or pct ~= u.threatPct
    u.threatLevel, u.threatPct, u.threatHidden, u.hasHiddenThreat = level, pct, hidden, hasHidden
    if changed then ns:Fire("ThreatUpdate", f) end
end

function Threat:Color(u)
    if not u.threatLevel or not ns.db.threat.useColor then return nil end
    local set = ns.db.threat.colors[ns.Role:Get()]
    local c = set and set[u.threatLevel]
    if c then return c[1], c[2], c[3] end
end

function Threat:Scale(u)
    if not u.threatLevel or not ns.db.threat.useScale then return 1 end
    local set = ns.db.threat.scale[ns.Role:Get()]
    return set and set[u.threatLevel] or 1
end

function Threat:Alpha(u)
    if not u.threatLevel or not ns.db.threat.useAlpha then return 1 end
    local set = ns.db.threat.alpha[ns.Role:Get()]
    return set and set[u.threatLevel] or 1
end

-- ---------------------------------------------------------------------------
-- Updates: events mark plates dirty; a 0.2 s tick evaluates them. A tank's
-- percentage scans the whole group, so it is never done more than 5x a second.
-- ---------------------------------------------------------------------------

local dirty, allDirty = {}, false
local ticker = CreateFrame("Frame")
local elapsedTotal = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    elapsedTotal = elapsedTotal + elapsed
    if elapsedTotal < 0.2 then return end
    elapsedTotal = 0
    if not ns.Plates then return end
    if allDirty then
        allDirty = false; wipe(dirty)
        ns.Plates:Each(function(f) Threat:Evaluate(f) end)
    elseif next(dirty) then
        for f in pairs(dirty) do
            if f.active then Threat:Evaluate(f) end
        end
        wipe(dirty)
    end
end)

function Threat:MarkUnit(unit)
    local f = ns.Plates and ns.Plates:ForUnit(unit)
    if f then dirty[f] = true end
end

function Threat:MarkAll() allDirty = true end

ns:On("UNIT_THREAT_LIST_UPDATE", function(unit) if unit then Threat:MarkUnit(unit) end end)
ns:On("UNIT_THREAT_SITUATION_UPDATE", function() Threat:MarkAll() end)
ns:On("UNIT_TARGET", function(unit) if unit then Threat:MarkUnit(unit) end end)
ns:On("UNIT_FLAGS", function(unit) if unit then Threat:MarkUnit(unit) end end)
ns:On("GROUP_ROSTER_UPDATE", function() Threat:MarkAll() end)
ns:On("UNIT_PET", function() Threat:MarkAll() end)
ns:On("PLAYER_REGEN_ENABLED", function() Threat:MarkAll() end)
ns:On("PLAYER_REGEN_DISABLED", function() Threat:MarkAll() end)
ns:Listen("RoleChanged", function() Threat:MarkAll() end)
ns:Listen("SettingsChanged", function() Threat:MarkAll() end)

function Threat:PrintTarget()
    if not UnitExists("target") then return ns:Print("No target.") end
    local tanking, status, scaled, raw = C.DetailedThreat("player", "target")
    if scaled == nil then
        local any = C.ScaledThreatAny("player", "target")
        if C.IsSecret(any) then
            return ns:Print("The client hides threat numbers; plates show Blizzard's scaled threat unread.")
        end
        return ns:Print("You are not on your target's threat table.")
    end
    local pct = self:Percent("target")
    ns:Print(("Role %s | tanking %s | status %s | scaled %.0f%% | raw %.0f%% | SmartPlates %s"):format(
        ns.Role:Get(), tostring(tanking), tostring(status), scaled or 0, raw or 0, Threat.Format(pct)))
end
