local _, ns = ...
local C = ns.Compat

-- Nameplate lifecycle. Each Blizzard nameplate gets one SmartPlates frame (plate.SP, called "f"
-- everywhere) with a unit table f.unit. Elements and plugins register here and are called on
-- create, on every full update, and when the unit leaves.
local Plates = { byUnit = {}, byGUID = {}, frames = {} }
ns.Plates = Plates

local elements = {}

-- mod = { name, Create(f), Update(f), Clear(f) }; every function is optional.
function Plates:Register(mod)
    elements[#elements + 1] = mod
    for _, f in pairs(self.frames) do
        if mod.Create then mod:Create(f) end
    end
end

function Plates:ForUnit(unit) return unit and self.byUnit[unit] end
function Plates:ForGUID(guid) return guid and self.byGUID[guid] end

function Plates:Each(fn)
    for _, f in pairs(self.byUnit) do
        if f.active then fn(f) end
    end
end

-- ---------------------------------------------------------------------------
-- Blizzard's own plate: hidden while ours is shown
-- ---------------------------------------------------------------------------

local savedParent = setmetatable({}, { __mode = "k" })

local function SetBlizzardShown(uf, show)
    if not uf or uf:IsForbidden() then return end
    if show then
        local parent = savedParent[uf]
        if parent then
            uf:SetParent(parent); uf:SetAllPoints(parent)
            savedParent[uf] = nil
        end
        if not uf:IsShown() then uf:Show() end
        uf:SetAlpha(1)
    elseif C.HAS_SECRETS and uf:IsProtected() then
        -- Blizzard's secure code can quietly re-show a protected frame; moving it away sticks.
        if not savedParent[uf] and uf:GetParent() then savedParent[uf] = uf:GetParent() end
        uf:ClearAllPoints(); uf:SetParent(nil)
    else
        uf:Hide()
    end
end

local function Reaction(unit)
    local ok, r = pcall(UnitReaction, unit, "player")
    r = ok and C.Num(r) or nil
    if r then
        if r >= 5 then return "FRIENDLY" end
        if r == 4 then return "NEUTRAL" end
        return "HOSTILE"
    end
    local okF, friend = pcall(UnitIsFriend, "player", unit)
    if okF and C.AllReadable(friend) and friend then return "FRIENDLY" end
    return "HOSTILE"
end

-- Should SmartPlates draw this unit (rather than Blizzard)?
local function Ours(unit)
    if not unit or not ns.db then return false end
    if C.UnitIsUnit(unit, "player") or C.WidgetsOnly(unit) then return false end
    if Reaction(unit) == "FRIENDLY" then return not ns.db.general.blizzardFriendly end
    return not ns.db.general.blizzardEnemy
end
Plates.Ours = Ours

local function UnitFrameOnShow(uf)
    if uf:IsForbidden() then return end
    if not uf.unit then return SetBlizzardShown(uf, false) end
    if Ours(uf.unit) then SetBlizzardShown(uf, false) end
end

local function HookUnitFrame(plate)
    local uf = plate and plate.UnitFrame
    if not uf or uf:IsForbidden() then return end
    if not uf.SmartPlatesHooked then
        uf.SmartPlatesHooked = true
        uf:HookScript("OnShow", UnitFrameOnShow)
        if C.HAS_SECRETS then
            hooksecurefunc(uf, "Show", function(self) if not self:IsForbidden() then UnitFrameOnShow(self) end end)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Unit data
-- ---------------------------------------------------------------------------

local function Safe(fn, ...)
    local ok, a, b = pcall(fn, ...)
    if not ok or not C.AllReadable(a) then return nil end
    return a, b
end

-- The class of a group member, read from the roster (party1, raid3...) where the client shows it
-- even when it hides it on the nameplate. Matched by unit, else by name.
local groupUnits = {}
local function GroupClass(unit, name)
    if not IsInGroup() then return nil end
    for _, gu in ipairs(C.GroupUnits(groupUnits)) do
        local match = C.UnitIsUnit(unit, gu)
        if not match and name then match = C.SameName(ns.Units.UnitFull(gu), name) end
        if match then
            local ok, _, token = pcall(UnitClass, gu)
            if ok and C.AllReadable(token) then return token end
            return nil
        end
    end
end

function Plates:UpdateUnit(f)
    local u, unit = f.unit, f.unit.unitid
    local isPlayer, class, race, guid = C.Identity(unit) -- each read may be secret on Forever/Midnight
    u.guid = guid
    u.name = Safe(UnitName, unit)
    -- A player's full "Given Family" (WoW Forever) when the client tells it: the family name is
    -- what tells two players apart. The given name alone otherwise.
    if isPlayer and u.name then u.name = ns.Units.UnitFull(unit) or u.name end
    if isPlayer and not class then class = GroupClass(unit, u.name) end
    u.isPlayer = isPlayer or false
    u.class = isPlayer and class or nil
    u.race = isPlayer and race or false
    -- A hidden class can't be tested (even "if x" errors), only checked with issecretvalue and passed on.
    u.secretClass, u.hasSecretClass = nil, false
    if isPlayer and not class then
        local ok, _, raw = pcall(UnitClass, unit)
        if ok and C.IsSecret(raw) then u.secretClass, u.hasSecretClass = raw, true end
    end
    u.reaction = Reaction(unit)
    u.canAttack = Safe(UnitCanAttack, "player", unit) or false
    u.classification = Safe(UnitClassification, unit) or "normal"
    u.level = Safe(UnitLevel, unit)
    u.tapped = UnitIsTapDenied and Safe(UnitIsTapDenied, unit) or false
    u.isTarget = C.UnitIsUnit(unit, "target")
    u.isMouseover = C.UnitIsUnit(unit, "mouseover")
    u.isFocus = C.UnitIsUnit(unit, "focus")
    -- Kind of unit, for the visibility filters: player, totem, pet (incl. guardians), minor or npc.
    if u.isPlayer then
        u.kind = "player"
    elseif ns.Totems and ns.Totems.IconFor(u.name) then
        u.kind = "totem"
    elseif Safe(UnitPlayerControlled, unit) then
        u.kind = "pet"
    elseif u.classification == "minus" then
        u.kind = "minor"
    else
        u.kind = "npc"
    end
    u.style = ns.Style:Decide(u)
end

-- Width of the reaction ring around the bars, or 0 (glows and markers sit outside it).
function Plates:RingSize(f)
    local g, u = ns.db.general, f.unit
    if not g.reactionBorder or u.style ~= "normal" then return 0 end
    -- World PvP: an enemy player out in the open world gets a much thicker ring.
    if u.isPlayer and u.reaction ~= "FRIENDLY" and not self.inPvPInstance then
        return math.max(g.reactionBorderSize, g.worldPvPBorderSize)
    end
    return g.reactionBorderSize
end

-- Battlegrounds and arenas, where every other player is PvP anyway.
local function UpdateInstance()
    local _, kind = IsInInstance()
    Plates.inPvPInstance = kind == "pvp" or kind == "arena"
end
ns:On("PLAYER_ENTERING_WORLD", UpdateInstance)
ns:On("ZONE_CHANGED_NEW_AREA", function() UpdateInstance(); Plates:UpdateAll() end)

-- Space the power bar takes under the healthbar (its height plus a 1px gap), for elements below it.
function Plates:BelowBar(f)
    local h = f.powerH or 0
    return h > 0 and (h + 1) or 0
end

-- Healthbar size for this kind of plate.
function Plates:Size(u)
    local g = ns.db.general
    if u.small then return g.smallWidth, g.smallHeight end
    if u.reaction == "FRIENDLY" then return g.friendlyWidth, g.friendlyHeight end
    if u.isPlayer then return g.playerWidth, g.playerHeight end
    return g.width, g.height
end

-- A plate's resting scale and opacity (threat, target, custom scale).
function Plates:BaseScaleAlpha(f)
    local u = f.unit
    return math.max(0.3, ns.Style:Scale(u)) * UIParent:GetEffectiveScale(), ns.Style:Alpha(u)
end

function Plates:ApplyScaleAlpha(f)
    local s, a = self:BaseScaleAlpha(f)
    f:SetScale(s)
    f:SetAlpha(a)
end

-- Your target's plate, if it has one.
function Plates:TargetPlate()
    for _, p in pairs(self.byUnit) do
        if p.active and p.unit.isTarget then return p end
    end
end

-- Full refresh of one plate.
function Plates:Refresh(f)
    if not f.active then return end
    self:UpdateUnit(f)
    f.barW, f.barH = self:Size(f.unit)
    f:SetSize(f.barW, f.barH)
    f.powerH = ns.Resource and ns.Resource:Height(f) or 0
    self:LayoutBounds(f)
    if f.unit.style == "hidden" then f:Hide() return end
    f:Show()
    ns.Threat:Evaluate(f)
    for _, mod in ipairs(elements) do
        if mod.Update then mod:Update(f) end
    end
    self:ApplyScaleAlpha(f)
end

-- The box the game stacks plates by. On Forever the engine keeps plates apart by each plate's
-- stacking bounds frame, not by our drawing, so this box covers what a plate shows: the name above
-- the bar, the bar and power bar, and room for the castbar below (kept even when not casting, so a
-- cast never runs into the plate under it). The spacing settings stretch it: 1 = touching.
function Plates:LayoutBounds(f)
    local b = f.bounds
    if not b then return end
    local g, c, cv = ns.db.general, ns.db.castbar, ns.db.cvars
    local nameOnly = f.unit.style == "name"
    local above = nameOnly and 0 or (g.nameSize + 3)
    local below = self:BelowBar(f)
    if c.enabled and not nameOnly then below = below + 3 + c.height end
    local h = (nameOnly and (g.nameSize + 4) or (f.barH + above + below)) * (cv.spacingV or 1)
    local w = (f.barW or g.width) * (cv.spacingH or 1)
    -- Centred on what is drawn: the name sits above the bar, the castbar below.
    local mid = nameOnly and 0 or (above - below) / 2
    b:ClearAllPoints()
    b:SetPoint("CENTER", f, "CENTER", 0, mid)
    b:SetSize(math.max(1, w), math.max(1, h))
end

-- The size the game stacks every plate by. The engine keeps plates apart by one size for all of them
-- (C_NamePlate.SetNamePlateSize), which Blizzard sets to its own small plate; SmartPlates draws far
-- more (the name above the bar, the castbar below), so plates sat on each other. It's set here to
-- what a SmartPlates plate draws (the same box as LayoutBounds, for an enemy at full size, with the
-- spacing settings), in the plates' own units, and set again whenever Blizzard sets its own (its
-- options change). Out of combat only (the call is restricted in a fight: it waits for the end).
local stackSize -- { w, h } last set
local function PlateScale()
    for _, f in pairs(Plates.byUnit) do
        if f.active and f.plate and f:IsShown() then
            local ours, theirs = f:GetEffectiveScale(), f.plate:GetEffectiveScale()
            if ours and theirs and theirs > 0 then return ours / theirs end
        end
    end
    -- No plate up yet: about the general scale (the game's plates sit at UIParent's scale).
    return ns.db.general.scale or 1
end

function Plates:ApplyStackSize()
    if not (ns.db and C_NamePlate and C_NamePlate.SetNamePlateSize) then return end
    local cv = ns.db.cvars
    if not (cv.manage and cv.stacking) or ns.db.general.engineStack == false then return end
    if InCombatLockdown() then return ns:AfterCombat("stackSize", function() Plates:ApplyStackSize() end) end
    local g, c = ns.db.general, ns.db.castbar
    local above = g.nameSize + 3
    local below = (c.enabled and (3 + c.height) or 0)
    local k = PlateScale()
    local w = math.floor(g.width * (cv.spacingH or 1) * k + 0.5)
    local h = math.floor((g.height + above + below) * (cv.spacingV or 1) * k + 0.5)
    if stackSize and stackSize[1] == w and stackSize[2] == h then return end
    if pcall(C_NamePlate.SetNamePlateSize, w, h) then stackSize = { w, h } end
end

-- Blizzard sets its own size when its nameplate options change: ours again right after.
local function HookDriver()
    local d = NamePlateDriverFrame
    if d and d.UpdateNamePlateSize and not Plates.driverHooked then
        Plates.driverHooked = true
        hooksecurefunc(d, "UpdateNamePlateSize", function() stackSize = nil; C_Timer.After(0, function() Plates:ApplyStackSize() end) end)
    end
end

-- /sp stack: what the game stacks by, for checking.
function Plates:StackStatus()
    local get = C_CVar and C_CVar.GetCVar or GetCVar
    local types = get and get("nameplateStackingTypes")
    local kinds = Enum and Enum.NamePlateStackType
    local enemy = GetCVarBitfield and types and GetCVarBitfield("nameplateStackingTypes", kinds and kinds.Enemy or 1)
    local friend = GetCVarBitfield and types and GetCVarBitfield("nameplateStackingTypes", kinds and kinds.Friendly or 2)
    local w, h = C_NamePlate and C_NamePlate.GetNamePlateSize and C_NamePlate.GetNamePlateSize()
    ns:Print(("Stacking: enemies %s, friends %s (nameplateStackingTypes = %s); old nameplateMotion = %s.")
        :format(tostring(enemy), tostring(friend), tostring(types), tostring(get and get("nameplateMotion"))))
    ns:Print(("The game stacks plates %s x %s; SmartPlates asked for %s."):format(tostring(w), tostring(h),
        stackSize and (stackSize[1] .. " x " .. stackSize[2]) or "nothing yet"))
end

-- Hands the plate our bounds box (or gives Blizzard's frame back). Older clients have no stacking
-- bounds and stack by their own settings.
local function SetStackingBounds(plate, frame)
    -- (/sp stack off: neither this nor the plate size is handed to the game, to test whether they
    -- are what makes the game's unit tooltip run as SmartPlates' code.)
    if ns.db and ns.db.general.engineStack == false then return end
    if plate and frame and plate.SetStackingBoundsFrame then pcall(plate.SetStackingBoundsFrame, plate, frame) end
end

-- Someone joining the group may now have a class colour (see GroupClass).
ns:On("GROUP_ROSTER_UPDATE", function() Plates:UpdateAll() end)

function Plates:UpdateAll()
    if not ns.db then return end
    for unit, f in pairs(self.byUnit) do
        if f.active then
            if Ours(unit) then
                SetBlizzardShown(f.plate.UnitFrame, false)
                self:Refresh(f)
            else
                self:Deactivate(f, true)
            end
        end
    end
    -- Plates that were Blizzard's may be ours now (or the other way round).
    for _, plate in ipairs(C.AllPlates()) do
        local uf = plate.UnitFrame
        local unit = uf and uf.unit
        if unit and not self.byUnit[unit] then self:Activate(plate, unit) end
    end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function Plates:Create(plate)
    if plate.SP then return plate.SP end
    local f = CreateFrame("Frame", nil, plate)
    f.plate = plate
    f.unit = {}
    f:SetSize(120, 12)
    f:SetPoint("CENTER", plate, "CENTER")
    f:EnableMouse(false)
    -- What the game stacks this plate by (see LayoutBounds); invisible, never takes the mouse.
    f.bounds = CreateFrame("Frame", nil, f)
    f.bounds:SetSize(120, 12)
    f.bounds:SetPoint("CENTER", f, "CENTER")
    f.bounds:EnableMouse(false)
    if f.SetIgnoreParentScale then f:SetIgnoreParentScale(true) end
    if f.SetIgnoreParentAlpha then f:SetIgnoreParentAlpha(true) end
    f:Hide()
    plate.SP = f
    self.frames[plate] = f
    for _, mod in ipairs(elements) do
        if mod.Create then mod:Create(f) end
    end
    plate:HookScript("OnHide", function() if f.active then f:Hide() end end)
    plate:HookScript("OnShow", function() if f.active and f.unit.style ~= "hidden" then f:Show() end end)
    return f
end

function Plates:Activate(plate, unit)
    if not Ours(unit) then
        -- NAME_PLATE_UNIT_REMOVED doesn't always fire (PvP); drop a leftover frame.
        if plate.SP and plate.SP.active then self:Deactivate(plate.SP) end
        if plate.UnitFrame then SetBlizzardShown(plate.UnitFrame, true) end
        return
    end
    local f = self:Create(plate)
    if f.active and f.unit.unitid and f.unit.unitid ~= unit then self:Deactivate(f) end
    HookUnitFrame(plate)
    SetBlizzardShown(plate.UnitFrame, false)
    f.active = true
    wipe(f.unit)
    f.unit.unitid = unit
    self.byUnit[unit] = f
    self:Refresh(f)
    SetStackingBounds(plate, f.bounds)
    if f.unit.guid then self.byGUID[f.unit.guid] = f end
    ns:Fire("PlateAdded", f)
    -- Blizzard's own NAME_PLATE_UNIT_ADDED handler may run after ours and show its frame again.
    C_Timer.After(0, function()
        if f.active and f.unit.unitid == unit and plate.UnitFrame then
            HookUnitFrame(plate)
            SetBlizzardShown(plate.UnitFrame, false)
        end
    end)
end

function Plates:Deactivate(f, showBlizzard)
    local u = f.unit
    for _, mod in ipairs(elements) do
        if mod.Clear then mod:Clear(f) end
    end
    if u.unitid and self.byUnit[u.unitid] == f then self.byUnit[u.unitid] = nil end
    if u.guid and self.byGUID[u.guid] == f then self.byGUID[u.guid] = nil end
    if self.mouseover == f then self.mouseover = nil end
    f.active = false
    f:Hide()
    if showBlizzard and f.plate.UnitFrame then SetBlizzardShown(f.plate.UnitFrame, true) end
    SetStackingBounds(f.plate, f.plate.UnitFrame)
    ns:Fire("PlateRemoved", f)
    wipe(u)
end

ns:On("NAME_PLATE_CREATED", function(plate)
    Plates:Create(plate)
    HookUnitFrame(plate)
end)

ns:On("NAME_PLATE_UNIT_ADDED", function(unit)
    local plate = C.PlateForUnit(unit)
    if plate then Plates:Activate(plate, unit) end
    -- (the first plate tells the real scale between ours and the game's)
    if not stackSize then Plates:ApplyStackSize() end
end)
ns:On("PLAYER_ENTERING_WORLD", function()
    HookDriver()
    C_Timer.After(1, function() Plates:ApplyStackSize() end)
end)
ns:Listen("SettingsChanged", function() stackSize = nil; Plates:ApplyStackSize() end)

ns:On("NAME_PLATE_UNIT_REMOVED", function(unit)
    local f = Plates.byUnit[unit]
    if f then Plates:Deactivate(f) end
end)

ns:OnLoad(function()
    if NamePlateDriverFrame and NamePlateDriverFrame.AcquireUnitFrame then
        hooksecurefunc(NamePlateDriverFrame, "AcquireUnitFrame", function(_, plate)
            -- Blizzard just re-parented this (pooled) frame to plate; any parent we saved is stale.
            if plate.UnitFrame then savedParent[plate.UnitFrame] = nil end
            HookUnitFrame(plate)
            if plate.SP and plate.SP.active then SetBlizzardShown(plate.UnitFrame, false) end
        end)
    end
end)

-- ---------------------------------------------------------------------------
-- Target, mouseover and unit changes
-- ---------------------------------------------------------------------------

ns:On("PLAYER_TARGET_CHANGED", function()
    Plates:Each(function(f)
        f.unit.isTarget = C.UnitIsUnit(f.unit.unitid, "target")
        Plates:ApplyScaleAlpha(f)
    end)
    ns:Fire("TargetChanged")
end)

ns:On("PLAYER_FOCUS_CHANGED", function()
    Plates:Each(function(f) f.unit.isFocus = C.UnitIsUnit(f.unit.unitid, "focus") end)
    ns:Fire("FocusChanged")
end)

local mouseWatcher = CreateFrame("Frame")
mouseWatcher:Hide()
mouseWatcher:SetScript("OnUpdate", function(self)
    local f = Plates.mouseover
    if not f or not f.active or not C.UnitIsUnit("mouseover", f.unit.unitid) then
        if f then f.unit.isMouseover = false; ns:Fire("MouseoverChanged", f) end
        Plates.mouseover = nil
        self:Hide()
    end
end)

ns:On("UPDATE_MOUSEOVER_UNIT", function()
    local old = Plates.mouseover
    local new
    Plates:Each(function(f) if C.UnitIsUnit("mouseover", f.unit.unitid) then new = f end end)
    if old == new then return end
    if old then old.unit.isMouseover = false; ns:Fire("MouseoverChanged", old) end
    Plates.mouseover = new
    if new then
        new.unit.isMouseover = true
        ns:Fire("MouseoverChanged", new)
        mouseWatcher:Show()
    end
end)

local function RefreshUnit(unit)
    local f = Plates.byUnit[unit]
    if not f or not f.active then
        -- A unit drawn by Blizzard may have become ours (e.g. it changed faction).
        local plate = C.PlateForUnit(unit) -- nil for raid/party/target tokens
        if plate and not Ours(unit) then plate = nil end
        if plate then Plates:Activate(plate, unit) end
        return
    end
    if not Ours(unit) then return Plates:Deactivate(f, true) end
    Plates:Refresh(f)
end
ns:On("UNIT_NAME_UPDATE", RefreshUnit)
ns:On("UNIT_FACTION", RefreshUnit)
ns:On("UNIT_LEVEL", RefreshUnit)
ns:On("UNIT_CLASSIFICATION_CHANGED", RefreshUnit)

-- Threat-based size and opacity follow the threat state.
ns:Listen("ThreatUpdate", function(f) if f.active then Plates:ApplyScaleAlpha(f) end end)

ns:On("UI_SCALE_CHANGED", function() Plates:UpdateAll() end)
ns:On("DISPLAY_SIZE_CHANGED", function() Plates:UpdateAll() end)
ns:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(0, function() Plates:UpdateAll() end) end)
