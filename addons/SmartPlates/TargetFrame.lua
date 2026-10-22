local _, ns = ...
local C = ns.Compat

-- SmartPlates' own target frame (Settings: General > Target frame), and the target's plate flying
-- into it.
--
-- The frame is a SmartPlates plate whose unit is "target": it's registered in Plates.byUnit["target"],
-- so every unit event the elements listen to (health, casts, auras, threat) reaches it, and every
-- element draws it exactly as it draws a nameplate, at its own pixel size (targetFrame.width and
-- .height: drawn at that size, not scaled up, so its 1px edges and its text stay crisp) and always as
-- a full bar. Under it sits a secure unit button for "target": right-click opens the target's menu, the
-- game shows it only while you have a target (RegisterUnitWatch), and shift-drag moves it (out of
-- combat). Blizzard's target frame is parked out of sight while it's on (out of combat: it's protected).
--
-- The fly-in (targetFrame.fly, enemy plates only): when you target an enemy, its nameplate glides from
-- where it is into the target frame, growing to the frame's size and fading to nothing on the way, so it
-- seems to slip in behind it. Switch away from it while it's still alive and it flies back, faster, to
-- full opacity and its place among the plates. Plates move with the camera, so the flight follows the
-- plate's live position every frame. A plate's resting scale and opacity come from Plates
-- (BaseScaleAlpha), so threat changes during a flight still show.
local TF = {}
ns.TargetFrame = TF

local DOCK_IN, DOCK_OUT = 0.6, 0.25 -- seconds: into the frame (slow), back out (fast)
local PAD = 6                       -- the click area's margin round the bar

local holder, f, events
local hiddenParent
local blizzardParked = false
local pendingApply = false

local function DB() return ns.db and ns.db.targetFrame or {} end
local function Enabled() return DB().enabled == true end
local function Flying() return Enabled() and DB().fly ~= false end

function TF:Frame() return f end
function TF:Holder() return holder end
function TF:Active() return f ~= nil and f.active == true end

-- ---------------------------------------------------------------------------
-- Blizzard's target frame
-- ---------------------------------------------------------------------------

local function ParkBlizzard(park)
    local bf = _G.TargetFrame
    if not bf or InCombatLockdown() then return end
    if park and not blizzardParked then
        hiddenParent = hiddenParent or CreateFrame("Frame")
        hiddenParent:Hide()
        TF.blizzardParent = TF.blizzardParent or bf:GetParent() or UIParent
        pcall(bf.SetParent, bf, hiddenParent)
        blizzardParked = true
    elseif not park and blizzardParked then
        pcall(bf.SetParent, bf, TF.blizzardParent or UIParent)
        blizzardParked = false
    end
end

-- ---------------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------------

-- The frame's bar size in pixels (it's drawn at that size, never scaled).
local function BarSize()
    local db = DB()
    return math.max(60, tonumber(db.width) or 144), math.max(6, tonumber(db.height) or 14)
end
TF.BarSize = BarSize

-- The click area: the bar, with its name above and castbar below.
local function SizeHolder()
    local w, h = BarSize()
    holder:SetSize(w + PAD * 2, h + 34)
end

local function SavePosition()
    local x, y = holder:GetCenter()
    if not (x and y) then return end
    local k = holder:GetEffectiveScale() / UIParent:GetEffectiveScale()
    ns.char.targetFrame = { cx = math.floor(x * k + 0.5), cy = math.floor(y * k + 0.5) }
    holder:ClearAllPoints()
    holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ns.char.targetFrame.cx, ns.char.targetFrame.cy)
end

local function Place()
    holder:ClearAllPoints()
    local saved = ns.char and ns.char.targetFrame
    if saved and saved.cx then
        holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", saved.cx, saved.cy)
        return
    end
    -- Where Blizzard's target frame was, else to the right of the player frame's usual spot.
    local bf = _G.TargetFrame
    local ok, x, y = pcall(function() return bf:GetCenter() end)
    if ok and x and not C.IsSecret(x) and not C.IsSecret(y) and not blizzardParked then
        local k = bf:GetEffectiveScale() / UIParent:GetEffectiveScale()
        holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * k, y * k)
    else
        holder:SetPoint("CENTER", UIParent, "TOPLEFT", 420, -90)
    end
end

local function Build()
    holder = CreateFrame("Button", "SmartPlatesTargetFrame", UIParent, "SecureUnitButtonTemplate")
    holder:SetFrameStrata("LOW")
    holder:SetClampedToScreen(true)
    holder:SetAttribute("unit", "target")
    holder:SetAttribute("*type1", "target")
    holder:SetAttribute("*type2", "togglemenu")
    holder:RegisterForClicks("AnyUp")
    holder:SetMovable(true)
    holder:RegisterForDrag("LeftButton")
    holder:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() and not InCombatLockdown() then self:StartMoving() end
    end)
    holder:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    holder:HookScript("OnEnter", function(self)
        if GameTooltip_SetDefaultAnchor then GameTooltip_SetDefaultAnchor(GameTooltip, self) else GameTooltip:SetOwner(self, "ANCHOR_RIGHT") end
        pcall(GameTooltip.SetUnit, GameTooltip, "target")
        GameTooltip:AddLine(InCombatLockdown() and "Right-click: its menu." or "Right-click: its menu.  Shift-drag: move.", 0.6, 0.65, 0.7)
        GameTooltip:Show()
    end)
    holder:HookScript("OnLeave", function() GameTooltip:Hide() end)
    -- The drawn frame: a SmartPlates plate (every element's Create runs on it).
    f = ns.Plates:Create(holder)
    f.isTargetFrame = true
    SizeHolder()
    Place()
    holder:Hide()
end

-- ---------------------------------------------------------------------------
-- The frame's unit
-- ---------------------------------------------------------------------------

-- Points the frame at your current target (or takes it away when there's none).
function TF:Update()
    if not f then return end
    if not Enabled() or not C.Value(UnitExists, "target") then
        if f.active then ns.Plates:Deactivate(f) end
        return
    end
    if not f.active then
        f.active = true
        wipe(f.unit)
    end
    f.unit.unitid = "target"
    ns.Plates.byUnit.target = f
    ns.Plates:Refresh(f)
end

-- Turns it on or off, from the settings. Out of combat only (a protected button and Blizzard's frame);
-- a change made in combat waits for the fight to end.
function TF:Apply()
    if InCombatLockdown() then pendingApply = true return end
    pendingApply = false
    if Enabled() then
        if not holder then Build() end
        SizeHolder()
        ParkBlizzard(true)
        if RegisterUnitWatch and not TF.watching then RegisterUnitWatch(holder); TF.watching = true end
        self:Update()
    else
        if holder then
            if UnregisterUnitWatch and TF.watching then UnregisterUnitWatch(holder); TF.watching = false end
            holder:Hide()
        end
        if f and f.active then ns.Plates:Deactivate(f) end
        ParkBlizzard(false)
        self:UndockAll(true)
    end
end

function TF:ResetPosition()
    if ns.char then ns.char.targetFrame = nil end
    if holder and not InCombatLockdown() then Place() end
end

-- ---------------------------------------------------------------------------
-- The fly-in
-- ---------------------------------------------------------------------------

local flying = {} -- plate frame -> true while it's docked or on its way
local driver = CreateFrame("Frame")
driver:Hide()

local function ScreenCenter(frame)
    if not frame then return nil end
    local ok, x, y = pcall(frame.GetCenter, frame)
    if not ok or C.IsSecret(x) or C.IsSecret(y) or x == nil or y == nil then return nil end
    local s = frame:GetEffectiveScale()
    return x * s, y * s
end

local function Smooth(t) return t * t * (3 - 2 * t) end

-- Draws a plate at progress e (0 = in its place, 1 = inside the target frame).
local function Draw(p)
    local d = p.dock
    local e = d.e
    local k = Smooth(e)
    -- Grows to the frame's width on the way in (the frame is drawn at that width; the plate, briefly
    -- and fading, is stretched to match).
    local frameScale = BarSize() / math.max(1, p.barW or ns.db.general.width) * UIParent:GetEffectiveScale()
    local s = d.baseScale + (frameScale - d.baseScale) * k
    p:SetScale(s)
    p:SetAlpha(d.baseAlpha * (1 - e))
    local px, py = ScreenCenter(p.plate)
    local tx, ty = ScreenCenter(holder)
    p:ClearAllPoints()
    if px and tx then
        p:SetPoint("CENTER", p.plate, "CENTER", (tx - px) * k / s, (ty - py) * k / s)
    else
        p:SetPoint("CENTER", p.plate, "CENTER", 0, 0)
    end
end

-- The plate is back home: its own anchor, scale and opacity.
local function Land(p)
    p.dock = nil
    flying[p] = nil
    p:ClearAllPoints()
    p:SetPoint("CENTER", p.plate, "CENTER", 0, 0)
    ns.Plates:ApplyScaleAlpha(p)
end

driver:SetScript("OnUpdate", function(self, elapsed)
    local any = false
    for p in pairs(flying) do
        local d = p.dock
        if not (d and p.active) then
            flying[p] = nil
        else
            if d.dir ~= 0 then
                d.e = d.e + d.dir * elapsed / (d.dir > 0 and DOCK_IN or DOCK_OUT)
                if d.e >= 1 then d.e, d.dir = 1, 0 end
                if d.e <= 0 then d.e = 0; Land(p) end
            end
            if p.dock then
                Draw(p)
                if p.dock.dir ~= 0 then any = true end
            end
        end
    end
    if not any then self:Hide() end
end)

local function Enemy(p) return p.unit.reaction ~= "FRIENDLY" end

-- Sends a plate into the target frame (instant: already docked, e.g. it appeared while targeted).
function TF:Dock(p, instant)
    if not (p and p.active and not p.isTargetFrame and holder) then return end
    local s, a = ns.Plates:BaseScaleAlpha(p)
    p.dock = p.dock or { e = 0 }
    p.dock.baseScale, p.dock.baseAlpha = s, a
    p.dock.dir = instant and 0 or 1
    if instant then p.dock.e = 1 end
    flying[p] = true
    Draw(p)
    driver:Show()
end

-- Brings a plate back out (instant: no flight, e.g. the unit died or the feature was turned off).
function TF:Undock(p, instant)
    if not (p and p.dock) then return end
    if instant then return Land(p) end
    p.dock.dir = -1
    flying[p] = true
    driver:Show()
end

function TF:UndockAll(instant)
    for p in pairs(flying) do self:Undock(p, instant) end
end

-- Plates calls this instead of setting a flying plate's scale and alpha: the flight keeps them.
function TF:DockApply(p, s, a)
    p.dock.baseScale, p.dock.baseAlpha = s, a
    Draw(p)
end

-- Your target changed: the frame follows, the old plate comes home, the new enemy plate flies in.
local function OnTargetChanged()
    TF:Update()
    local new
    ns.Plates:Each(function(p) if not p.isTargetFrame and p.unit.isTarget then new = p end end)
    for p in pairs(flying) do
        if p ~= new then
            local dead = C.Value(UnitIsDeadOrGhost, p.unit.unitid)
            TF:Undock(p, dead == true)
        end
    end
    if new and Flying() and Enemy(new) and TF:Active() then TF:Dock(new) end
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------

ns:On("PLAYER_TARGET_CHANGED", OnTargetChanged)
ns:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(0.1, function() TF:Apply() end) end)
ns:On("PLAYER_REGEN_ENABLED", function() if pendingApply then TF:Apply() end end)
ns:Listen("SettingsChanged", function()
    TF:Apply()
    if not Flying() then TF:UndockAll(true) end
end)
ns:Listen("ProfileChanged", function() TF:Apply() end)
-- A plate that appears while its unit is your (enemy) target is already "inside" the frame.
ns:Listen("PlateAdded", function(p)
    if Flying() and TF:Active() and p.unit.isTarget and Enemy(p) then TF:Dock(p, true) end
end)
ns:Listen("PlateRemoved", function(p)
    if p.dock then p.dock = nil; flying[p] = nil; p:ClearAllPoints(); p:SetPoint("CENTER", p.plate, "CENTER", 0, 0) end
end)
