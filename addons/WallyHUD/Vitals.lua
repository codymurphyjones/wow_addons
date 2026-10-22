local _, ns = ...

-- Vitals: your health and your resource, drawn into the screen itself instead of a unit frame.
--
--   The tideline   One faint line across the whole screen. Its HEIGHT is your health: full health
--                  keeps it at the top edge, out of the way; as you're hurt it sinks down the
--                  screen, through the world you're looking at ("my life is at my shoulders").
--   The light      Along the tideline, your resource lights it from the left: how far it's lit is
--                  your mana (rage, energy). The lit tip is a small star, so your whole state is
--                  one point on the screen: up and right is well, sinking down and left is trouble.
--   The drained    The space above the tideline (what you've lost) takes a faint cold film.
--   The rim        The screen's edges redden from your first point of damage on an exponential
--                  curve (barely there for a long while, full near 12%); below your calm band
--                  (well under it) they beat like a pulse.
--   Rhythm         The five-second rule after a mana spell is a sweep round the star; energy and
--                  mana ticks ripple off it; combo points ride beside it.
--   Readouts       None, until you reach for them: bring the mouse near the tideline and the
--                  numbers surface along it. No clicks anywhere.
--   Nothing stays  At full health with your resource at rest, out of combat, it all fades away.
--   It learns      It watches how low your health usually goes in a fight (your calm band) and
--                  only pulses the edges below that; a tank living at 60% isn't nagged at 60%.
--                  And if you keep reaching for the numbers, it starts showing them in fights on
--                  its own.
--
-- WoW Forever (a 12.x engine) can hide health and power from addons in combat ("secret" values).
-- Nothing here does arithmetic or comparisons on them: they go straight into the engine's own
-- channels (status bar values, curve-mapped alpha, anchors to a bar's fill edge, formatted text),
-- which accept them. Where a value is readable, Lua does the same work itself. Learning only uses
-- readable values.
--
-- Your unit frame: Blizzard's player frame or the orb (Orb.lua), one setting. Options > AddOns > WallyHUD, /whud vitals.
local V = {}
ns.Vitals = V

local WHITE = "Interface\\Buttons\\WHITE8X8"
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local PAD = 3                      -- the tideline's travel stays this far inside the screen's edges
local LEAN = 46                    -- pixels above and below the tideline that count as reaching for it
local MANA_TYPE, ENERGY_TYPE = 0, 3
local POWER = {                    -- the light's colour per resource
    [0] = { 0.40, 0.66, 1.00 },    -- mana
    [1] = { 0.94, 0.38, 0.36 },    -- rage
    [2] = { 0.95, 0.62, 0.30 },    -- focus
    [3] = { 0.98, 0.86, 0.38 },    -- energy
    [6] = { 0.40, 0.80, 0.95 },    -- runic power
}
local FILLS_UP = { [1] = true, [6] = true } -- rage-like: rests empty, so "at rest" is zero
V.POWER = POWER

V.calmDefault = 0.35               -- the calm band (where the pulse starts) before anything's learned
V.minFights = 3                    -- fights before the learned calm band takes over

-- ---------------------------------------------------------------------------
-- Secret-safe helpers
-- ---------------------------------------------------------------------------

-- Whether the client hides v. Asked first, before anything else touches v: a hidden value can't be
-- tested (if v, not v, v and x, v == nil), compared or used in arithmetic, only handed to the engine.
local function IsSecret(v)
    if issecretvalue and issecretvalue(v) then return true end
    if canaccessvalue and not canaccessvalue(v) then return true end
    return false
end
V.IsSecret = IsSecret

-- v when Lua may use it, else nil.
local function Readable(v)
    if IsSecret(v) then return nil end
    return v
end
V.Readable = Readable

local function Try(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

-- Piecewise-linear curve through points { {x, y}, ... } (x ascending), at x.
local function LuaEval(points, x)
    if x <= points[1][1] then return points[1][2] end
    for i = 2, #points do
        local a, b = points[i - 1], points[i]
        if x <= b[1] then
            local t = (x - a[1]) / math.max(1e-6, b[1] - a[1])
            return a[2] + (b[2] - a[2]) * t
        end
    end
    return points[#points][2]
end
V.LuaEval = LuaEval

-- A curve the engine can apply to hidden values (C_CurveUtil), with its points kept for Lua.
local function MakeCurve(points)
    local c = { points = points }
    if C_CurveUtil and C_CurveUtil.CreateCurve then
        local ok, obj = pcall(C_CurveUtil.CreateCurve)
        if ok and obj then
            for _, p in ipairs(points) do pcall(obj.AddPoint, obj, p[1], p[2]) end
            c.obj = obj
        end
    end
    return c
end
V.MakeCurve = MakeCurve

-- Health (0..1) as Lua can read it, or nil.
local function HealthFrac()
    local cur, max = Readable(UnitHealth("player")), Readable(UnitHealthMax("player"))
    if cur and max and max > 0 then return cur / max end
end

local function PowerFrac(ptype)
    local cur, max = Readable(UnitPower("player", ptype)), Readable(UnitPowerMax("player", ptype))
    if cur and max and max > 0 then return cur / max end
end

-- The curve at your health: a plain number when readable, else the engine's (possibly hidden)
-- result, else nil. Callers only hand the result to the engine.
local function HealthThrough(curve)
    local f = HealthFrac()
    if f then return LuaEval(curve.points, f) end
    if curve.obj and UnitHealthPercent then
        local ok, v = pcall(UnitHealthPercent, "player", true, curve.obj)
        if ok then return v end
    end
end

-- The same for your resource.
local function PowerThrough(curve, ptype)
    local f = PowerFrac(ptype)
    if f then return LuaEval(curve.points, f) end
    if curve.obj and UnitPowerPercent then
        local ok, v = pcall(UnitPowerPercent, "player", ptype, false, curve.obj)
        if ok then return v end
    end
end

-- Alpha that may be hidden: straight to the engine. A readable nil leaves the region as it is.
local function SetAlphaSafe(region, a)
    if not IsSecret(a) and a == nil then return end
    if not Try(region.SetAlpha, region, a) then region:SetAlpha(1) end
end

local INTERP
local function SetBar(bar, value)
    if not IsSecret(value) and value == nil then return end
    INTERP = INTERP or (Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut) or false
    if INTERP and Try(bar.SetValue, bar, value, INTERP) then return end
    Try(bar.SetValue, bar, value)
end

local function Gradient(tex, orientation, r, g, b, aMin, aMax)
    tex:SetTexture(WHITE)
    if CreateColor and Try(tex.SetGradient, tex, orientation, CreateColor(r, g, b, aMin), CreateColor(r, g, b, aMax)) then return end
    if not Try(tex.SetGradientAlpha, tex, orientation, r, g, b, aMin, r, g, b, aMax) then
        tex:SetVertexColor(r, g, b, (aMin + aMax) / 2)
    end
end

-- ---------------------------------------------------------------------------
-- Saved state (per character): what it has learned
-- ---------------------------------------------------------------------------

local function Mem()
    local c = ns.char
    if not c then return {} end
    c.vitals = type(c.vitals) == "table" and c.vitals or {}
    local m = c.vitals
    m.fights = m.fights or 0
    m.glances = m.glances or 0       -- moving average of times you reach for the numbers per fight
    return m
end
V.Mem = Mem

-- Your calm band: a bit under how low your health usually goes in a fight (the pulse starts under it).
function V.CalmThreshold()
    local m = Mem()
    if (m.fights or 0) < V.minFights or not m.low then return V.calmDefault end
    return math.max(0.18, math.min(0.6, m.low - 0.08))
end

-- Whether the numbers show in fights on their own (you keep reaching for them).
function V.Pinned()
    local mode = ns.db and ns.db.vitalsReadouts or "learn"
    if mode == "always" then return true end
    if mode == "approach" then return false end
    local m = Mem()
    return (m.fights or 0) >= V.minFights and (m.glances or 0) >= 2
end

-- ---------------------------------------------------------------------------
-- The frames
-- ---------------------------------------------------------------------------

local field, presence, health, film, tide, power, star, rim, beat, hint
local hpText, pText, band, cooldown, ripple, lowFrame, lowText
local combo = {}
V.combo = combo
local curves = {}

local LOW_TEXT = 0.15   -- below this much health the health readout shows without reaching for it
local RIM_FULL = 0.1225 -- health at and below which the rim is at full strength
local RIM_STEEP = 5      -- how sharply it climbs (exp(k * x) - 1) / (exp(k) - 1)

-- The rim's curve as points (health ascending): 1 up to RIM_FULL, then an exponential fall to 0
-- at full health, sampled finely enough that the engine's straight segments read as a curve.
local function RimPoints()
    local pts = { { 0, 1 } }
    local steps = 24
    local span = math.exp(RIM_STEEP) - 1
    for i = steps, 0, -1 do
        local x = i / steps                      -- 1 at RIM_FULL, 0 at full health
        pts[#pts + 1] = { 1 - x * (1 - RIM_FULL), (math.exp(RIM_STEEP * x) - 1) / span }
    end
    return pts
end
V.RimPoints = RimPoints

local function BuildCurves()
    local calm = V.CalmThreshold()
    -- The drained film: nothing at full, deepening as you fall (capped: you still need to see).
    curves.film = MakeCurve({ { 0, 0.22 }, { 0.5, 0.12 }, { 0.98, 0.02 }, { 1, 0 } })
    -- The rim: an exponential spread from the first point of damage. Barely there for a long while
    -- (2% at 75% health, 11% at 50%), climbing faster the lower you go, full at RIM_FULL and below.
    curves.rim = MakeCurve(RimPoints())
    -- The beat: only well under your calm band.
    curves.beat = MakeCurve({ { 0, 1 }, { calm * 0.55, 1 }, { calm * 0.6, 0 }, { 1, 0 } })
    -- Low health: the health readout shows by itself below LOW_TEXT.
    curves.low = MakeCurve({ { 0, 1 }, { LOW_TEXT, 1 }, { LOW_TEXT + 0.002, 0 }, { 1, 0 } })
    -- The tideline's own brightness: brighter the lower it sits, and gone at full health. (Whether
    -- you're at full health is often hidden from Lua, even out of combat, so the engine decides.)
    curves.line = MakeCurve({ { 0, 1 }, { 0.5, 0.75 }, { 0.99, 0.45 }, { 0.995, 0 }, { 1, 0 } })
    -- The light at rest: mana or energy rests full, rage rests empty; at rest it's gone.
    curves.restFull = MakeCurve({ { 0, 1 }, { 0.99, 1 }, { 0.995, 0 }, { 1, 0 } })
    curves.restEmpty = MakeCurve({ { 0, 0 }, { 0.005, 0 }, { 0.01, 1 }, { 1, 1 } })
    V.builtCalm = calm
end

-- Where the health readout sits on the tideline: "left", "center" or "right" (the setting).
local SIDES = {
    left = { "BOTTOMLEFT", "TOPLEFT", 14, "LEFT" },
    center = { "BOTTOM", "TOP", 0, "CENTER" },
    right = { "BOTTOMRIGHT", "TOPRIGHT", -14, "RIGHT" },
}

function V:PlaceHealthText()
    if not (hpText and lowText and tide) then return end
    local side = SIDES[ns.db and ns.db.vitalsHealthTextSide or "right"] or SIDES.right
    for _, fs in ipairs({ hpText, lowText }) do
        fs:ClearAllPoints()
        fs:SetPoint(side[1], tide, side[2], side[3], 5)
        fs:SetJustifyH(side[4])
    end
end

local function Build()
    field = CreateFrame("Frame", "WallyHUDVitals", UIParent)
    field:SetAllPoints(UIParent)
    field:SetFrameStrata("BACKGROUND")
    field:EnableMouse(false)

    -- Presence: everything that fades away at rest.
    presence = CreateFrame("Frame", nil, field)
    presence:SetAllPoints()
    presence:SetAlpha(1)

    -- Health: a full-screen vertical bar with an invisible fill; the tideline rides its top edge.
    health = CreateFrame("StatusBar", nil, presence)
    health:SetPoint("TOPLEFT", 0, -PAD); health:SetPoint("BOTTOMRIGHT", 0, PAD)
    health:SetOrientation("VERTICAL")
    health:SetStatusBarTexture(WHITE)
    health:SetStatusBarColor(0, 0, 0, 0)
    health:SetMinMaxValues(0, 1); health:SetValue(1)
    local fill = health:GetStatusBarTexture()

    -- The drained film above it: a reverse bar of what's missing.
    film = CreateFrame("StatusBar", nil, presence)
    film:SetPoint("TOPLEFT", 0, -PAD); film:SetPoint("BOTTOMRIGHT", 0, PAD)
    film:SetOrientation("VERTICAL")
    if film.SetReverseFill then film:SetReverseFill(true) end
    film:SetStatusBarTexture(WHITE)
    film:SetStatusBarColor(0.06, 0.09, 0.18, 1)
    film:SetMinMaxValues(0, 1); film:SetValue(0)

    -- The tideline, on the fill's top edge, with brighter ends where it meets the screen's walls.
    tide = CreateFrame("Frame", nil, presence)
    tide:SetPoint("BOTTOMLEFT", fill, "TOPLEFT", 0, -1)
    tide:SetPoint("BOTTOMRIGHT", fill, "TOPRIGHT", 0, -1)
    tide:SetHeight(2)
    tide.line = tide:CreateTexture(nil, "ARTWORK"); tide.line:SetAllPoints(); tide.line:SetTexture(WHITE)
    tide.line:SetVertexColor(1, 0.86, 0.82, 0.32)
    tide.left = tide:CreateTexture(nil, "ARTWORK"); tide.left:SetPoint("TOPLEFT"); tide.left:SetPoint("BOTTOMLEFT"); tide.left:SetWidth(140)
    Gradient(tide.left, "HORIZONTAL", 1, 0.84, 0.80, 0.85, 0)
    tide.right = tide:CreateTexture(nil, "ARTWORK"); tide.right:SetPoint("TOPRIGHT"); tide.right:SetPoint("BOTTOMRIGHT"); tide.right:SetWidth(140)
    Gradient(tide.right, "HORIZONTAL", 1, 0.84, 0.80, 0, 0.85)

    -- The light: the resource as a bar riding the tideline, lit from the left; the star at its tip.
    power = CreateFrame("StatusBar", nil, tide)
    power:SetPoint("LEFT"); power:SetPoint("RIGHT"); power:SetHeight(2)
    power:SetStatusBarTexture(WHITE)
    power:SetMinMaxValues(0, 1); power:SetValue(1)
    local pfill = power:GetStatusBarTexture()
    power.glow = power:CreateTexture(nil, "BACKGROUND")
    power.glow:SetPoint("TOPLEFT", pfill, "TOPLEFT", 0, 5); power.glow:SetPoint("BOTTOMRIGHT", pfill, "BOTTOMRIGHT", 0, -5)
    power.glow:SetTexture(WHITE); power.glow:SetBlendMode("ADD")

    star = CreateFrame("Frame", nil, power)
    star:SetSize(30, 30)
    star:SetPoint("CENTER", pfill, "RIGHT", 0, 0)
    star.halo = star:CreateTexture(nil, "BACKGROUND"); star.halo:SetAllPoints(); star.halo:SetTexture(DISC); star.halo:SetBlendMode("ADD")
    star.core = star:CreateTexture(nil, "OVERLAY"); star.core:SetSize(7, 7); star.core:SetPoint("CENTER"); star.core:SetTexture(DISC)
    star.core:SetVertexColor(1, 1, 1, 1)

    -- The five-second rule: a sweep round the star.
    cooldown = CreateFrame("Cooldown", nil, star, "CooldownFrameTemplate")
    cooldown:SetSize(22, 22); cooldown:SetPoint("CENTER")
    Try(cooldown.SetHideCountdownNumbers, cooldown, true)
    Try(cooldown.SetDrawBling, cooldown, false)
    Try(cooldown.SetDrawEdge, cooldown, true)
    Try(cooldown.SetSwipeColor, cooldown, 0, 0, 0, 0.55)
    Try(cooldown.SetReverse, cooldown, true)

    -- Ticks: a ring rippling off the star.
    ripple = star:CreateTexture(nil, "ARTWORK"); ripple:SetSize(14, 14); ripple:SetPoint("CENTER"); ripple:SetTexture(DISC)
    ripple:SetBlendMode("ADD"); ripple:SetAlpha(0)
    ripple.t = 99

    -- Combo points, riding behind the star.
    for i = 1, 5 do
        local c = star:CreateTexture(nil, "OVERLAY"); c:SetSize(6, 6); c:SetTexture(DISC)
        c:SetPoint("CENTER", star, "CENTER", -14 - (i - 1) * 9, 10)
        c:SetVertexColor(1, 0.82, 0.35, 1); c:Hide()
        combo[i] = c
    end

    -- Readouts, surfacing along the tideline when you reach for them.
    local face = WallyHUD.Face and WallyHUD.Face("semibold") or STANDARD_TEXT_FONT
    hpText = tide:CreateFontString(nil, "OVERLAY"); hpText:SetFont(face, 13, ""); hpText:SetShadowOffset(1, -1)
    hpText:SetTextColor(1, 0.9, 0.86, 1); hpText:SetAlpha(0)
    -- The same readout when your health is low, shown by the engine (a curve: it works with hidden
    -- health). Its frame steps aside while the hover readout is up, so the two never stack.
    lowFrame = CreateFrame("Frame", nil, tide); lowFrame:SetAllPoints(tide)
    lowText = lowFrame:CreateFontString(nil, "OVERLAY"); lowText:SetFont(face, 13, ""); lowText:SetShadowOffset(1, -1)
    lowText:SetTextColor(1, 0.9, 0.86, 1); lowText:SetAlpha(0)
    V:PlaceHealthText()
    pText = star:CreateFontString(nil, "OVERLAY"); pText:SetFont(face, 12, ""); pText:SetShadowOffset(1, -1)
    pText:SetPoint("TOPLEFT", star, "CENTER", 14, -6); pText:SetAlpha(0)
    -- The reach band: not mouse-enabled (the world stays clickable through it), only asked.
    band = CreateFrame("Frame", nil, tide)
    band:SetPoint("TOPLEFT", tide, "TOPLEFT", 0, LEAN); band:SetPoint("BOTTOMRIGHT", tide, "BOTTOMRIGHT", 0, -LEAN)
    band:EnableMouse(false)

    -- The rim: four soft edges, and the beat inside them.
    rim = CreateFrame("Frame", nil, field)
    rim:SetAllPoints(); rim:SetAlpha(0)
    beat = CreateFrame("Frame", nil, field)
    beat:SetAllPoints(); beat:SetAlpha(0)
    local function Edges(parent, size, a)
        local r, g, b = 0.78, 0.08, 0.12
        local t = parent:CreateTexture(nil, "BACKGROUND"); t:SetPoint("TOPLEFT"); t:SetPoint("TOPRIGHT"); t:SetHeight(size)
        Gradient(t, "VERTICAL", r, g, b, 0, a)
        local bt = parent:CreateTexture(nil, "BACKGROUND"); bt:SetPoint("BOTTOMLEFT"); bt:SetPoint("BOTTOMRIGHT"); bt:SetHeight(size)
        Gradient(bt, "VERTICAL", r, g, b, a, 0)
        local l = parent:CreateTexture(nil, "BACKGROUND"); l:SetPoint("TOPLEFT"); l:SetPoint("BOTTOMLEFT"); l:SetWidth(size)
        Gradient(l, "HORIZONTAL", r, g, b, a, 0)
        local rt = parent:CreateTexture(nil, "BACKGROUND"); rt:SetPoint("TOPRIGHT"); rt:SetPoint("BOTTOMRIGHT"); rt:SetWidth(size)
        Gradient(rt, "HORIZONTAL", r, g, b, 0, a)
    end
    Edges(rim, 110, 0.55)
    beat.pulse = CreateFrame("Frame", nil, beat); beat.pulse:SetAllPoints()
    Edges(beat.pulse, 160, 0.7)
    if beat.pulse.CreateAnimationGroup then
        local ag = beat.pulse:CreateAnimationGroup()
        ag:SetLooping("REPEAT")
        local up = ag:CreateAnimation("Alpha"); up:SetFromAlpha(0.1); up:SetToAlpha(1); up:SetDuration(0.18); up:SetOrder(1)
        local down = ag:CreateAnimation("Alpha"); down:SetFromAlpha(1); down:SetToAlpha(0.1); down:SetDuration(0.7); down:SetOrder(2)
        beat.anim = ag
        ag:Play()
    end

    -- First contact: one hint, once.
    hint = presence:CreateFontString(nil, "OVERLAY"); hint:SetFont(face, 13, ""); hint:SetShadowOffset(1, -1)
    hint:SetPoint("TOP", tide, "BOTTOM", 0, -14); hint:SetTextColor(0.93, 0.94, 0.96, 1); hint:SetAlpha(0)
    hint:SetText("This line's height is your life.  Its light is your " .. "power" .. ".  Bring the mouse to it to read it.")
end

-- ---------------------------------------------------------------------------
-- Updating
-- ---------------------------------------------------------------------------

local state = { ptype = MANA_TYPE, rest = 0, inCombat = false, over = false, overAlpha = 0, lastSpend = 0, lastHint = nil,
    glancesThisFight = 0, fightStart = nil, fightLow = nil }
V.state = state

local function Enabled() return ns.db and ns.db.vitals ~= false end

function V:UpdateHealth()
    if not field then return end
    local max = UnitHealthMax("player")
    Try(health.SetMinMaxValues, health, 0, max)
    Try(film.SetMinMaxValues, film, 0, max)
    SetBar(health, UnitHealth("player"))
    local missing = UnitHealthMissing and UnitHealthMissing("player")
    if not IsSecret(missing) and missing == nil then
        local cur, m = Readable(UnitHealth("player")), Readable(max)
        missing = cur and m and (m - cur) or 0
    end
    SetBar(film, missing)
    -- (Never "x and hidden or y": that tests the hidden value.)
    if ns.db.vitalsFilm ~= false then SetAlphaSafe(film, HealthThrough(curves.film)) else film:SetAlpha(0) end
    if ns.db.vitalsRim ~= false then
        SetAlphaSafe(rim, HealthThrough(curves.rim))
        SetAlphaSafe(beat, HealthThrough(curves.beat))
    else
        rim:SetAlpha(0); beat:SetAlpha(0)
    end
    local line = HealthThrough(curves.line)
    SetAlphaSafe(tide.line, line); SetAlphaSafe(tide.left, line); SetAlphaSafe(tide.right, line)
    -- The readout: formatted by the game's own helpers, which accept hidden numbers. Each case is
    -- one format call: a string made from a hidden number is hidden too, so it's never tested.
    local ok, text = pcall(function()
        local Abbr = AbbreviateNumbers or tostring
        local cur, max = UnitHealth("player"), UnitHealthMax("player")
        local f = HealthFrac()
        if f then return ("%d%%   %s / %s"):format(math.floor(f * 100 + 0.5), Abbr(cur), Abbr(max)) end
        if UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
            return ("%.f%%   %s / %s"):format(UnitHealthPercent("player", true, CurveConstants.ScaleTo100), Abbr(cur), Abbr(max))
        end
        return ("%s / %s"):format(Abbr(cur), Abbr(max))
    end)
    if ok then Try(hpText.SetText, hpText, text); Try(lowText.SetText, lowText, text) end
    SetAlphaSafe(lowText, HealthThrough(curves.low))
    -- Learning: the lowest readable health this fight.
    if state.inCombat then
        local f = HealthFrac()
        if f and (not state.fightLow or f < state.fightLow) then state.fightLow = f end
    end
end

function V:UpdatePower()
    if not field then return end
    local ptype = Readable(UnitPowerType("player")) or MANA_TYPE
    state.ptype = ptype
    local c = POWER[ptype] or POWER[0]
    power:SetStatusBarColor(c[1], c[2], c[3], 0.95)
    power.glow:SetVertexColor(c[1], c[2], c[3], 0.35)
    star.halo:SetVertexColor(c[1], c[2], c[3], 0.55)
    ripple:SetVertexColor(c[1], c[2], c[3], 1)
    pText:SetTextColor(c[1] * 0.5 + 0.5, c[2] * 0.5 + 0.5, c[3] * 0.5 + 0.5, 1)
    Try(power.SetMinMaxValues, power, 0, UnitPowerMax("player", ptype))
    SetBar(power, UnitPower("player", ptype))
    -- In a fight the light always shows; out of one it's gone at rest (decided by the engine).
    if state.inCombat then
        power:SetAlpha(1)
    else
        SetAlphaSafe(power, PowerThrough(FILLS_UP[ptype] and curves.restEmpty or curves.restFull, ptype))
    end
    local ok, text = pcall(function()
        local f = PowerFrac(ptype)
        local name = _G[({ [0] = "MANA", [1] = "RAGE", [2] = "FOCUS", [3] = "ENERGY", [6] = "RUNIC_POWER" })[ptype] or "MANA"] or "power"
        if f then return ("%d%%  %s"):format(math.floor(f * 100 + 0.5), tostring(name):lower()) end
        if UnitPowerPercent and CurveConstants and CurveConstants.ScaleTo100 then
            return ("%.f%%  %s"):format(UnitPowerPercent("player", ptype, false, CurveConstants.ScaleTo100), tostring(name):lower())
        end
        return (AbbreviateNumbers or tostring)(UnitPower("player", ptype))
    end)
    if ok then Try(pText.SetText, pText, text) end
    self:UpdateCombo()
end

function V:UpdateCombo()
    if not field then return end
    local n
    local ok, v = pcall(function()
        if GetComboPoints then return GetComboPoints("player", "target") end
        return UnitPower("player", 4)
    end)
    n = ok and Readable(v) or 0
    for i, c in ipairs(combo) do c:SetShown(n >= i) end
end

local acc = 0
local function OnUpdate(_, elapsed)
    acc = acc + elapsed
    if acc < 0.05 then return end
    local dt = acc
    acc = 0
    -- (Fading away at rest is the engine's job: the line and the light take their alpha from
    -- curves of your health and power, which are often hidden from Lua even out of combat.)
    -- Reaching for it: the numbers surface while the mouse is near the tideline (or pinned in
    -- fights). Where the line is depends on your health, so the answer can be hidden too: then it
    -- goes to the engine as it is (SetAlphaFromBoolean), never tested here.
    local okOver, over = pcall(band.IsMouseOver, band)
    if not okOver then over = false end
    local pinned = state.inCombat and V.Pinned() or false
    if IsSecret(over) then
        local rest = pinned and 1 or 0
        if not Try(hpText.SetAlphaFromBoolean, hpText, over, 1, rest) then hpText:SetAlpha(rest) end
        if not Try(pText.SetAlphaFromBoolean, pText, over, 1, rest) then pText:SetAlpha(rest) end
        if pinned then lowFrame:SetAlpha(0)
        elseif not Try(lowFrame.SetAlphaFromBoolean, lowFrame, over, 0, 1) then lowFrame:SetAlpha(1) end
        state.overAlpha, state.over = rest, false
    else
        over = over and true or false
        local want = (over or pinned) and 1 or 0
        if over and not state.over and state.inCombat then state.glancesThisFight = state.glancesThisFight + 1 end
        state.over = over
        local o = state.overAlpha
        if want > o then o = math.min(want, o + dt * 6) elseif want < o then o = math.max(want, o - dt * 3) end
        state.overAlpha = o
        hpText:SetAlpha(o); pText:SetAlpha(o)
        lowFrame:SetAlpha(1 - o)
    end
    -- The tick ripple.
    if ripple.t < 1 then
        ripple.t = ripple.t + dt / 0.6
        local t = math.min(1, ripple.t)
        ripple:SetSize(10 + 40 * t, 10 + 40 * t)
        ripple:SetAlpha(0.7 * (1 - t))
    end
    -- The first-contact hint.
    if state.hintUntil then
        local left = state.hintUntil - GetTime()
        hint:SetAlpha(left > 0 and math.min(1, left / 1.5) or 0)
        if left <= 0 then state.hintUntil = nil end
    end
end

function V:Ripple() if ripple then ripple.t = 0 end end

-- A spell just cost mana: the five-second rule starts (regen stops for 5 seconds).
function V:OnSpend(spellID)
    if not field or state.ptype ~= MANA_TYPE or ns.db.vitalsRhythm == false then return end
    local ok, costs = pcall(function() return C_Spell and C_Spell.GetSpellPowerCost and C_Spell.GetSpellPowerCost(spellID) end)
    if not (ok and type(costs) == "table") then return end
    for _, cost in ipairs(costs) do
        local t, amount = Readable(cost.type), Readable(cost.cost)
        if t == MANA_TYPE and amount and amount > 0 then
            state.lastSpend = GetTime()
            Try(cooldown.SetCooldown, cooldown, GetTime(), 5)
            return
        end
    end
end

-- A power update that we didn't cause by casting: a regen tick (energy, or mana outside the rule).
function V:OnPowerTick()
    if ns.db.vitalsRhythm == false then return end
    local now = GetTime()
    if now - (state.lastCast or 0) < 0.35 then return end
    if state.ptype == ENERGY_TYPE or (state.ptype == MANA_TYPE and now - state.lastSpend > 5) then
        local f = PowerFrac(state.ptype)
        if f and f >= 0.999 then return end
        self:Ripple()
    end
end

-- ---------------------------------------------------------------------------
-- Fights: learning the calm band and whether you want the numbers
-- ---------------------------------------------------------------------------

function V:OnCombat(inCombat)
    state.inCombat = inCombat
    if field and Enabled() then self:UpdatePower() end
    if inCombat then
        state.fightStart, state.fightLow, state.glancesThisFight = GetTime(), HealthFrac(), 0
        return
    end
    local m = Mem()
    local length = state.fightStart and (GetTime() - state.fightStart) or 0
    if length >= 8 then
        m.fights = (m.fights or 0) + 1
        if state.fightLow then
            m.low = m.low and (m.low * 0.8 + state.fightLow * 0.2) or state.fightLow
        end
        m.glances = (m.glances or 0) * 0.7 + (state.glancesThisFight or 0) * 0.3
        local wasPinned = m.pinnedSaid
        if V.Pinned() and not wasPinned and (ns.db.vitalsReadouts or "learn") == "learn" then
            m.pinnedSaid = true
            ns:Print("Vitals: you keep reaching for the numbers, so they'll stay out in fights now (/whud vitals to change).")
        end
    end
    state.fightStart = nil
    -- Out of combat: rebuild the curves when the calm band has moved.
    if math.abs((V.builtCalm or 0) - V.CalmThreshold()) > 0.01 then
        BuildCurves()
        self:UpdateHealth()
    end
end

-- ---------------------------------------------------------------------------
-- Blizzard's player frame
-- ---------------------------------------------------------------------------

-- Your unit frame is one choice (the setting "Your unit frame"): Blizzard's player frame, or the
-- orb (Orb.lua). Switching either way works live, out of combat (a protected frame can't be moved
-- between parents in a fight; a switch made in one happens as it ends). Blizzard's frame is parked
-- under a hidden parent, not torn down, so it comes straight back.
local hiddenParent
local playerHidden, pendingSwitch = false, false

local function WantOrb() return ns.db and ns.db.vitalsPlayerFrame == "orb" end

function V:HidePlayerFrame()
    if playerHidden or not PlayerFrame then return end
    -- Where the portrait was: the orb starts there.
    local spot = _G.PlayerPortrait or PlayerFrame
    local ok, x, y = pcall(spot.GetCenter, spot)
    if ok and V.Readable(x) and V.Readable(y) then V.playerSpot = { x, y } end
    V.playerParent = V.playerParent or PlayerFrame:GetParent() or UIParent
    hiddenParent = hiddenParent or CreateFrame("Frame")
    hiddenParent:Hide()
    Try(PlayerFrame.SetParent, PlayerFrame, hiddenParent)
    playerHidden = true
end

function V:ShowPlayerFrame()
    if not playerHidden or not PlayerFrame then return end
    Try(PlayerFrame.SetParent, PlayerFrame, V.playerParent or UIParent)
    Try(PlayerFrame.Show, PlayerFrame)
    playerHidden = false
end

-- Puts the chosen unit frame on screen: Blizzard's, or the orb.
function V:ApplyPlayerFrame()
    if InCombatLockdown() then pendingSwitch = true return end
    pendingSwitch = false
    if WantOrb() then self:HidePlayerFrame() else self:ShowPlayerFrame() end
    if ns.Orb then ns.Orb:Apply() end
end

function V:PlayerFrameHidden() return playerHidden end

-- ---------------------------------------------------------------------------
-- Turning it on and off
-- ---------------------------------------------------------------------------

local events

function V:Apply()
    if Enabled() then
        if not field then
            BuildCurves()
            Build()
            field:SetScript("OnUpdate", OnUpdate)
        end
        field:Show()
        self:UpdatePower()
        self:UpdateHealth()
        local m = Mem()
        if not m.introduced then
            m.introduced = true
            local name = _G[({ [0] = "MANA", [1] = "RAGE", [3] = "ENERGY" })[state.ptype] or "MANA"] or "power"
            hint:SetText(("This line's height is your life. Its light is your %s. Bring the mouse to it to read it."):format(tostring(name):lower()))
            state.hintUntil = GetTime() + 9
        end
    elseif field then
        field:Hide()
    end
    self:ApplyPlayerFrame()
end

local function OnEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then return V:OnCombat(true) end
    if event == "PLAYER_REGEN_ENABLED" then
        if pendingSwitch then V:ApplyPlayerFrame() end
        return V:OnCombat(false)
    end
    if event == "PLAYER_ENTERING_WORLD" then return V:Apply() end
    if not (Enabled() and field) then return end
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        V:UpdateHealth()
    elseif event == "UNIT_POWER_FREQUENT" or event == "UNIT_POWER_UPDATE" then
        V:UpdatePower()
        if event == "UNIT_POWER_FREQUENT" then V:OnPowerTick() end
    elseif event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" or event == "UPDATE_SHAPESHIFT_FORM" then
        V:UpdatePower()
    elseif event == "PLAYER_TARGET_CHANGED" then
        V:UpdateCombo()
    end
end

ns:OnLoad(function()
    events = CreateFrame("Frame")
    for _, e in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER",
        "UNIT_DISPLAYPOWER", "UNIT_SPELLCAST_SUCCEEDED" }) do
        if events.RegisterUnitEvent then pcall(events.RegisterUnitEvent, events, e, "player") else pcall(events.RegisterEvent, events, e) end
    end
    for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "UPDATE_SHAPESHIFT_FORM",
        "PLAYER_TARGET_CHANGED" }) do
        pcall(events.RegisterEvent, events, e)
    end
    events:SetScript("OnEvent", function(self, event, ...)
        local unit = ...
        if unit ~= nil and type(unit) == "string" and unit ~= "player" and event:find("^UNIT_") then return end
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            state.lastCast = GetTime()
            return V:OnSpend(select(3, ...))
        end
        return OnEvent(self, event, ...)
    end)
end)

-- What it has learned, in words (the settings and /whud vitals).
function V.Describe()
    local m = Mem()
    local calm = V.CalmThreshold()
    local parts = {}
    if (m.fights or 0) < V.minFights then
        parts[#parts + 1] = ("Still learning (%d of %d fights). The edges start to pulse below %d%% health for now."):format(m.fights or 0, V.minFights, math.floor(calm * 60 + 0.5))
    else
        parts[#parts + 1] = ("Your health usually goes down to about %d%% in a fight, so the edges only start to pulse below %d%%."):format(
            math.floor((m.low or calm) * 100 + 0.5), math.floor(calm * 60 + 0.5))
    end
    if V.Pinned() then parts[#parts + 1] = "The numbers stay out in fights." else parts[#parts + 1] = "The numbers surface when you bring the mouse to the line." end
    return table.concat(parts, " ")
end

-- Forget what it learned.
function V.Forget()
    if ns.char then ns.char.vitals = { introduced = true } end
    if field then BuildCurves(); V:UpdateHealth() end
end
