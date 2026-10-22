local _, ns = ...

-- The orb: when it's your chosen unit frame (the setting "Your unit frame", Vitals.lua), a small
-- glass orb stands in for Blizzard's player frame, where your portrait was. Diablo-inspired: a
-- sphere of glowing liquid set in a bronze-and-iron bezel with a crest, split across the middle by an
-- iron bar with a gem. The top half holds your health (emerald), the bottom half your resource (in
-- its colour); each fills like a small vessel from its own floor, with a bright line on the surface
-- and a slow swirl turning in the liquid. It is your unit frame in every way that matters:
-- right-click opens your unit menu (the one your portrait opens), left-click targets you, the mouse
-- over it shows your tooltip. Shift-drag moves it (out of combat).
--
-- Two looks, depending on whether the tideline (Vitals) is on:
--   the line off (the default)  the full orb: health in the top half, your resource in the bottom half
--   the line on                 the line shows your health, so the orb becomes a smaller resource tracker:
--                               one sphere of your resource, with the exact amount in the middle ("100")
-- Its diameter is in the settings (Orb size). It keeps that size in and out of combat, so your menu
-- is always one right-click away. The orb hangs from the centre of a small holder frame that carries
-- its position.
--
-- Health and power can be hidden from addons ("secret" values), even out of combat: the fills take
-- them as they are (status bar values, which the engine accepts), and the tooltip's numbers come from
-- the game's own formatting. Nothing here tests or compares them.
--
-- Art: addons/WallyHUD/Media/Orb, drawn by tools/WallyHUD/make_orb.py.
local O = {}
ns.Orb = O

local ART = "Interface\\AddOns\\WallyHUD\\Media\\Orb\\"
local INNER = 0.80       -- the sphere's share of the orb (make_orb.py's INNER); the bezel is the rest
local TRACKER = 0.8      -- the resource tracker (the line on) is this much smaller than the full orb
local HP_COLOR = { 0.25, 0.95, 0.45 }
local SWIRL_SECONDS = 48 -- one slow turn of the swirl in the liquid

local orb, holder, events

-- Line on: the orb is a resource tracker.
local function Tracker() return ns.db and ns.db.vitals == true end

-- Its diameter now (the setting; smaller as a resource tracker).
local function Size()
    local size = math.max(16, tonumber(ns.db and ns.db.orbSize) or 100)
    if Tracker() then size = size * TRACKER end
    return math.floor(size + 0.5)
end
O.Size = Size

local function IsSecret(v)
    if issecretvalue and issecretvalue(v) then return true end
    if canaccessvalue and not canaccessvalue(v) then return true end
    return false
end

local function Try(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

local function SetBar(bar, value)
    if not IsSecret(value) and value == nil then return end
    local interp = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
    if interp and Try(bar.SetValue, bar, value, interp) then return end
    Try(bar.SetValue, bar, value)
end

local function Wanted()
    return ns.db and ns.db.vitalsPlayerFrame == "orb" and ns.Vitals and ns.Vitals:PlayerFrameHidden()
end

-- A brighter, more luminous take on a colour for the liquid's surface line.
local function Bright(c) return math.min(1, c[1] * 0.55 + 0.45), math.min(1, c[2] * 0.55 + 0.45), math.min(1, c[3] * 0.55 + 0.45) end

-- ---------------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------------

local function Tex(parent, layer, sub, file, mask)
    local t = parent:CreateTexture(nil, layer, nil, sub)
    t:SetAllPoints(orb)
    t:SetTexture(ART .. file)
    if mask and t.AddMaskTexture then t:AddMaskTexture(mask) end
    return t
end

-- One half of the sphere: a vertical status bar inside the sphere's bounds (top or bottom of the
-- middle), its fill the liquid, masked to the sphere, with a bright line on its surface.
local function Half(mask)
    local bar = CreateFrame("StatusBar", nil, orb)
    bar:SetOrientation("VERTICAL")
    bar:SetStatusBarTexture(ART .. "Liquid")
    bar:SetMinMaxValues(0, 1); bar:SetValue(1)
    bar:EnableMouse(false)
    local fill = bar:GetStatusBarTexture()
    if fill and fill.AddMaskTexture then fill:AddMaskTexture(mask) end
    -- The surface: a bright soft line riding the top of the fill.
    bar.surface = bar:CreateTexture(nil, "OVERLAY")
    bar.surface:SetTexture(ART .. "Surface")
    bar.surface:SetBlendMode("ADD")
    bar.surface:SetPoint("LEFT", fill, "TOPLEFT", 0, 0); bar.surface:SetPoint("RIGHT", fill, "TOPRIGHT", 0, 0)
    bar.surface:SetHeight(3)
    if bar.surface.AddMaskTexture then bar.surface:AddMaskTexture(mask) end
    return bar
end

-- The orb hangs from the holder's centre; the holder carries the position (so scaling keeps it in place).
local function SavePosition()
    local x, y = orb:GetCenter()
    if not (x and y) then return end
    local scale = orb:GetEffectiveScale() / UIParent:GetEffectiveScale()
    ns.char.orb = { cx = math.floor(x * scale + 0.5), cy = math.floor(y * scale + 0.5) }
    holder:ClearAllPoints()
    holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ns.char.orb.cx, ns.char.orb.cy)
    orb:ClearAllPoints()
    orb:SetPoint("CENTER", holder, "CENTER", 0, 0)
end

local function Place()
    holder:ClearAllPoints()
    local saved = ns.char and ns.char.orb
    if saved and saved.cx then
        holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", saved.cx, saved.cy)
    elseif ns.Vitals.playerSpot then
        -- Where the portrait was (screen coordinates, at UIParent's scale).
        holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ns.Vitals.playerSpot[1], ns.Vitals.playerSpot[2])
    else
        holder:SetPoint("CENTER", UIParent, "TOPLEFT", 83, -63)
    end
    orb:ClearAllPoints()
    orb:SetPoint("CENTER", holder, "CENTER", 0, 0)
end

local function Tooltip(self)
    if GameTooltip_SetDefaultAnchor then GameTooltip_SetDefaultAnchor(GameTooltip, self) else GameTooltip:SetOwner(self, "ANCHOR_RIGHT") end
    Try(GameTooltip.SetUnit, GameTooltip, "player")
    -- The numbers, through the game's own formatting (fine with hidden values).
    local Abbr = AbbreviateNumbers or tostring
    local okH, health = pcall(function()
        return ("%s / %s"):format(Abbr(UnitHealth("player")), Abbr(UnitHealthMax("player")))
    end)
    local ptype = UnitPowerType("player")
    if IsSecret(ptype) then ptype = 0 end
    local okP, power = pcall(function()
        return ("%s / %s"):format(Abbr(UnitPower("player", ptype)), Abbr(UnitPowerMax("player", ptype)))
    end)
    if okH then Try(GameTooltip.AddDoubleLine, GameTooltip, HEALTH or "Health", health, 0.75, 0.8, 0.85, HP_COLOR[1], HP_COLOR[2], HP_COLOR[3]) end
    local c = ns.Vitals.POWER[ptype] or ns.Vitals.POWER[0]
    if okP then Try(GameTooltip.AddDoubleLine, GameTooltip, "Power", power, 0.75, 0.8, 0.85, c[1], c[2], c[3]) end
    GameTooltip:AddLine(InCombatLockdown() and "Right-click: your menu." or "Right-click: your menu.  Shift-drag: move.", 0.6, 0.65, 0.7)
    GameTooltip:Show()
end

local function Build()
    holder = CreateFrame("Frame", "WallyHUDPlayerOrbHolder", UIParent)
    holder:SetSize(1, 1)

    orb = CreateFrame("Button", "WallyHUDPlayerOrb", UIParent, "SecureUnitButtonTemplate")
    orb:SetSize(100, 100)
    orb:SetFrameStrata("MEDIUM")
    orb:SetClampedToScreen(true)
    -- Your unit, as your portrait is: left-click targets you, right-click opens your menu.
    orb:SetAttribute("unit", "player")
    orb:SetAttribute("*type1", "target")
    orb:SetAttribute("*type2", "togglemenu")
    orb:RegisterForClicks("AnyUp")
    -- Shift-drag to move, out of combat.
    orb:SetMovable(true)
    orb:RegisterForDrag("LeftButton")
    orb:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() and not InCombatLockdown() then self:StartMoving() end
    end)
    orb:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    orb:HookScript("OnEnter", Tooltip)
    orb:HookScript("OnLeave", function() GameTooltip:Hide() end)

    -- The sphere's inside, for masking the liquid, the swirl and the glass.
    local mask = orb:CreateMaskTexture()
    mask:SetTexture(ART .. "Mask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(orb)
    orb.mask = mask

    -- Back to front: smoky glass, the two liquids (with their surfaces), the swirl, the bar and gem
    -- across the middle, the glass's shine and inner shadow, the bezel.
    orb.empty = Tex(orb, "BACKGROUND", 0, "Empty", mask)
    orb.health = Half(mask)
    orb.health:SetStatusBarColor(HP_COLOR[1], HP_COLOR[2], HP_COLOR[3], 1)
    orb.health.surface:SetVertexColor(Bright(HP_COLOR))
    orb.power = Half(mask)

    local front = CreateFrame("Frame", nil, orb)
    front:SetAllPoints(orb)
    front:SetFrameLevel(orb:GetFrameLevel() + 3)
    front:EnableMouse(false)
    orb.front = front
    orb.swirl = Tex(front, "BACKGROUND", 0, "Swirl", mask)
    orb.swirl:SetBlendMode("ADD"); orb.swirl:SetAlpha(0.28)
    if orb.swirl.CreateAnimationGroup then
        local ag = orb.swirl:CreateAnimationGroup()
        local spin = ag:CreateAnimation("Rotation")
        spin:SetDegrees(-360); spin:SetDuration(SWIRL_SECONDS)
        ag:SetLooping("REPEAT")
        ag:Play()
        orb.swirlAnim = ag
    end
    orb.divider = Tex(front, "ARTWORK", 0, "Divider")
    orb.glass = Tex(front, "ARTWORK", 1, "Glass")
    orb.frame = Tex(front, "OVERLAY", 0, "Frame")
    -- The resource tracker's number, over the glass.
    orb.count = front:CreateFontString(nil, "OVERLAY")
    orb.count:SetPoint("CENTER", orb, "CENTER", 0, 0)
    orb.count:SetShadowOffset(1, -1)
    orb.count:SetTextColor(1, 1, 1, 1)

    Place()
    orb:Hide()
end

-- Its size, the liquid's insets and its look (full orb or resource tracker), from the settings.
-- Out of combat only (it changes a protected button); a change made in combat waits.
function O:Layout()
    if not orb then return end
    if InCombatLockdown() then O.pendingLayout = true return end
    O.pendingLayout = false
    local size = Size()
    orb:SetSize(size, size)
    -- The liquid fills the sphere only (inside the bezel): both halves, or the whole sphere for the tracker.
    local inset = size * (1 - INNER) / 2
    local tracker = Tracker()
    orb.health:ClearAllPoints(); orb.power:ClearAllPoints()
    orb.health:SetPoint("TOPLEFT", orb, "TOPLEFT", inset, -inset); orb.health:SetPoint("BOTTOMRIGHT", orb, "RIGHT", -inset, 0)
    if tracker then
        orb.power:SetPoint("TOPLEFT", orb, "TOPLEFT", inset, -inset)
    else
        orb.power:SetPoint("TOPLEFT", orb, "LEFT", inset, 0)
    end
    orb.power:SetPoint("BOTTOMRIGHT", orb, "BOTTOMRIGHT", -inset, inset)
    orb.health:SetShown(not tracker)
    orb.divider:SetShown(not tracker)
    orb.count:SetShown(tracker)
    local face = WallyHUD.Face and WallyHUD.Face("bold") or STANDARD_TEXT_FONT
    orb.countFace, orb.countSize, orb.countFont = face, size, nil
    orb.mode = tracker and "tracker" or "full"
    self:UpdateHealth(); self:UpdatePower()
end

-- ---------------------------------------------------------------------------
-- Updating
-- ---------------------------------------------------------------------------

local COUNT_MIN = 3       -- the smallest the tracker's number gets: it always fits, readable or not
local DIGIT = 0.56        -- a digit's width as a share of the font size (Roboto Condensed Bold, outlined)

-- Sizes the tracker's number to fit inside the sphere, however many digits it has (10k and up shrink
-- it). When the number is hidden from Lua its width can't be measured, so the size comes from how many
-- digits it can have (from your maximum, remembered when it's readable; 5 if it never was); when it's
-- readable, the real width is measured and the font shrinks until it fits.
local function FitCount(text)
    local size = orb.countSize or Size()
    local room = size * INNER * 0.78                      -- the sphere's width, less a margin
    local digits = O.maxDigits or 5
    if type(text) == "string" and not IsSecret(text) then digits = math.max(1, #text) end
    local font = math.floor(math.min(size * 0.3, room / (digits * DIGIT)))
    font = math.max(COUNT_MIN, font)
    local function Set(f)
        if orb.countFont ~= f then
            orb.count:SetFont(orb.countFace, f, "OUTLINE")
            orb.countFont = f
        end
    end
    Set(font)
    if type(text) == "string" and not IsSecret(text) and orb.count.GetUnboundedStringWidth then
        local ok, w = pcall(orb.count.GetUnboundedStringWidth, orb.count)
        while ok and type(w) == "number" and not IsSecret(w) and w > room and font > COUNT_MIN do
            font = font - 1
            Set(font)
            ok, w = pcall(orb.count.GetUnboundedStringWidth, orb.count)
        end
    end
end
O.FitCount = function(text) if orb then FitCount(text) end end

function O:UpdateHealth()
    if not orb then return end
    Try(orb.health.SetMinMaxValues, orb.health, 0, UnitHealthMax("player"))
    SetBar(orb.health, UnitHealth("player"))
end

function O:UpdatePower()
    if not orb then return end
    local ptype = UnitPowerType("player")
    if IsSecret(ptype) or type(ptype) ~= "number" then ptype = 0 end
    local c = ns.Vitals.POWER[ptype] or ns.Vitals.POWER[0]
    orb.power:SetStatusBarColor(c[1], c[2], c[3], 1)
    orb.power.surface:SetVertexColor(Bright(c))
    Try(orb.power.SetMinMaxValues, orb.power, 0, UnitPowerMax("player", ptype))
    SetBar(orb.power, UnitPower("player", ptype))
    -- The tracker's number: the exact amount you have, nothing else ("100"). The game's own
    -- formatting takes it even when it's hidden from Lua.
    if orb.mode == "tracker" then
        -- How many digits it can have: from your maximum, whenever the game lets Lua read it.
        local max = UnitPowerMax("player", ptype)
        if not IsSecret(max) and type(max) == "number" and max > 0 then O.maxDigits = #tostring(math.floor(max)) end
        local ok, text = pcall(function() return ("%d"):format(UnitPower("player", ptype)) end)
        if not ok then ok, text = pcall(function() return (AbbreviateNumbers or tostring)(UnitPower("player", ptype)) end) end
        if ok then
            Try(orb.count.SetText, orb.count, text)
            FitCount(text)
        end
        orb.count:SetTextColor(Bright(c))
    end
end

-- Shows the orb when it's wanted, else takes it away. Secure changes wait for the end of a fight.
local pending = false
function O:Apply()
    if InCombatLockdown() then pending = true return end
    pending = false
    if Wanted() then
        if not orb then Build() end
        self:Layout()
        orb:Show()
    elseif orb then
        orb:Hide()
    end
end

function O:Frame() return orb end

-- Back where the portrait was (forgets where you dragged it).
function O:ResetPosition()
    if ns.char then ns.char.orb = nil end
    if orb and not InCombatLockdown() then Place() end
end

ns:OnLoad(function()
    events = CreateFrame("Frame")
    for _, e in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }) do
        if events.RegisterUnitEvent then pcall(events.RegisterUnitEvent, events, e, "player") else pcall(events.RegisterEvent, events, e) end
    end
    for _, e in ipairs({ "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "UPDATE_SHAPESHIFT_FORM" }) do pcall(events.RegisterEvent, events, e) end
    events:SetScript("OnEvent", function(_, event, unit)
        if type(unit) == "string" and unit ~= "player" and event:find("^UNIT_") then return end
        if event == "PLAYER_REGEN_ENABLED" then
            if pending then O:Apply() end
        if O.pendingLayout then O:Layout() end
            O:UpdateHealth(); O:UpdatePower()
        elseif event == "PLAYER_ENTERING_WORLD" then
            O:Apply()
        elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            O:UpdateHealth()
        else
            O:UpdatePower()
        end
    end)
end)
