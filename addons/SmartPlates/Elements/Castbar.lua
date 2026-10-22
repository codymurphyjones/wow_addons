local _, ns = ...
local C, M = ns.Compat, ns.Media

-- Cast and channel bar under the healthbar, with spell icon, spell name and a grey bar for casts
-- you can't interrupt.
local Cast = { name = "Castbar" }

-- ---------------------------------------------------------------------------
-- Interrupt ready: enemy castbars turn green (teal border) while your interrupt is off cooldown.
-- Reads your own cooldowns; while the game hides them in combat the bar just shows the normal colour.
-- ---------------------------------------------------------------------------

local Interrupt = { ready = nil } -- true ready, false on cooldown, nil no interrupt known
ns.Interrupt = Interrupt

local _, PLAYER_CLASS = UnitClass("player")
local INTERRUPTS = {
    WARRIOR = { 6552, 72 },            -- Pummel, Shield Bash
    ROGUE = { 1766 },                  -- Kick
    MAGE = { 2139 },                   -- Counterspell
    SHAMAN = { 57994, 8042 },          -- Wind Shear; Earth Shock (Classic)
    PRIEST = { 15487 },                -- Silence
    PALADIN = { 96231 },               -- Rebuke
    HUNTER = { 147362, 187707 },       -- Counter Shot, Muzzle
    DRUID = { 106839, 78675 },         -- Skull Bash, Solar Beam
    WARLOCK = { 19244, 119910, 132409 }, -- Spell Lock (pet)
    DEATHKNIGHT = { 47528 },           -- Mind Freeze
    MONK = { 116705 },                 -- Spear Hand Strike
    DEMONHUNTER = { 183752 },          -- Disrupt
    EVOKER = { 351338 },               -- Quell
}

local function Known(id)
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    if C.IsSpellKnown(id) then return true end
    if IsSpellKnown then
        local ok, pet = pcall(IsSpellKnown, id, true)
        if ok and pet then return true end
    end
    return false
end

local function Cooldown(id)
    local start, duration
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, id)
        if ok and info then start, duration = info.startTime, info.duration end
    elseif GetSpellCooldown then
        local ok, s, d = pcall(GetSpellCooldown, id)
        if ok then start, duration = s, d end
    end
    return C.Num(start), C.Num(duration)
end

local recheck
function Interrupt:Update()
    local state, wait = nil, nil
    for _, id in ipairs(INTERRUPTS[PLAYER_CLASS] or {}) do
        if Known(id) then
            local start, duration = Cooldown(id)
            if start and duration then
                -- A duration up to 1.5 s is only the global cooldown.
                if duration <= 1.5 then state = true break end
                state = false
                local left = start + duration - GetTime()
                if left > 0 and (not wait or left < wait) then wait = left end
            end
        end
    end
    local changed = state ~= self.ready
    self.ready = state
    -- The game doesn't announce a cooldown ending, so look again when it should have.
    if wait and not recheck then
        recheck = true
        C_Timer.After(wait + 0.05, function() recheck = false; Interrupt:Update() end)
    end
    if changed then
        ns.Plates:Each(function(f) if f.castbar:IsShown() then Cast:Colorize(f) end end)
    end
end

ns:On("SPELL_UPDATE_COOLDOWN", function() Interrupt:Update() end)
ns:On("SPELLS_CHANGED", function() Interrupt:Update() end)
ns:On("UNIT_PET", function(unit) if unit == "player" then Interrupt:Update() end end)
ns:On("PLAYER_ENTERING_WORLD", function() Interrupt:Update() end)

local function OnUpdate(bar, elapsed)
    local now = GetTime()
    if now >= bar.endTime then
        bar.interrupted = nil
        bar:Hide()
        return
    end
    local progress = bar.channel and (bar.endTime - now) or (now - bar.startTime)
    bar:SetValue(progress)
    bar.time:SetFormattedText("%.1f", bar.endTime - now)
end

function Cast:Create(f)
    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetStatusBarTexture(M.BAR)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints(); bar.bg:SetColorTexture(M.BAR_BG[1], M.BAR_BG[2], M.BAR_BG[3], 0.9)
    bar.border = M.Border(bar, "OVERLAY")
    bar.icon = M.Icon(bar, 16)
    bar.text = bar:CreateFontString(nil, "OVERLAY")
    bar.time = bar:CreateFontString(nil, "OVERLAY")
    bar.shield = bar:CreateTexture(nil, "OVERLAY")
    bar.shield:SetColorTexture(1, 1, 1, 0.12)
    bar.shield:SetAllPoints()
    bar:SetScript("OnUpdate", OnUpdate)
    -- The cast icon sits where the enemy sword is (Elements\Text.lua): fade the sword meanwhile.
    bar:HookScript("OnShow", function() if f.sword and bar.icon:IsShown() then f.sword:SetAlpha(0) end end)
    bar:HookScript("OnHide", function() if f.sword then f.sword:SetAlpha(1) end end)
    bar:Hide()
    f.castbar = bar
end

function Cast:Layout(f)
    local bar, db = f.castbar, ns.db.castbar
    bar:SetStatusBarTexture(M.BarTexture())
    local h = db.height
    bar:ClearAllPoints()
    local y = -3 - ns.Plates:BelowBar(f)
    bar:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, y)
    bar:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, y)
    bar:SetHeight(h)
    -- The spell icon spans the healthbar and the castbar, left of both.
    local size = h + (f.barH or ns.db.general.height) + 3
    bar.icon:SetSize(size, size)
    bar.icon:ClearAllPoints()
    bar.icon:SetPoint("TOPRIGHT", f, "TOPLEFT", -3, 0)
    bar.icon:SetShown(db.icon)
    M.SetFont(bar.text, math.max(7, h + 1))
    M.SetFont(bar.time, math.max(7, h))
    bar.text:ClearAllPoints(); bar.text:SetPoint("LEFT", bar, "LEFT", 2, 0)
    bar.text:SetPoint("RIGHT", bar.time, "LEFT", -2, 0)
    bar.text:SetJustifyH("LEFT"); bar.text:SetWordWrap(false)
    bar.text:SetShown(db.text)
    bar.time:ClearAllPoints(); bar.time:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
end

local function Enabled(f)
    local db = ns.db.castbar
    if not db.enabled or f.unit.style ~= "normal" then return false end
    return db.friendly or f.unit.reaction ~= "FRIENDLY"
end

function Cast:Start(f)
    local bar, unit = f.castbar, f.unit.unitid
    if not unit or not Enabled(f) then return bar:Hide() end
    local channel = false
    local name, text, icon, startMS, endMS, _, castID, notInterruptible = C.UnitCastingInfo(unit)
    if not name then
        castID = nil
        name, text, icon, startMS, endMS, _, notInterruptible = C.UnitChannelInfo(unit)
        channel = name ~= nil
    end
    if not name or not C.AllReadable(startMS, endMS) then return bar:Hide() end
    bar.channel, bar.interrupted = channel, nil
    bar.castID = C.AllReadable(castID) and castID or nil
    bar.startTime, bar.endTime = startMS / 1000, endMS / 1000
    bar:SetMinMaxValues(0, bar.endTime - bar.startTime)
    -- Only a real true means uninterruptible.
    bar.locked = C.AllReadable(notInterruptible) and notInterruptible == true or false
    bar.lockUnknown = not C.AllReadable(notInterruptible) -- hidden: we can't promise it's interruptible
    self:Colorize(f)
    pcall(bar.icon.tex.SetTexture, bar.icon.tex, icon)
    pcall(bar.text.SetText, bar.text, text or name)
    OnUpdate(bar, 0)
    bar:Show()
end

-- Cast colour: uninterruptible grey, "your interrupt is ready" green, otherwise cast/channel colour.
function Cast:Colorize(f)
    local bar, colors = f.castbar, ns.db.colors
    if bar.interrupted then return end
    local c = bar.channel and colors.channel or colors.cast
    local ready = false
    if bar.locked then
        c = colors.uninterruptible
    elseif ns.db.castbar.interruptReady and f.unit.reaction ~= "FRIENDLY" and Interrupt.ready and not bar.lockUnknown then
        c, ready = colors.interruptReady, true
    end
    bar:SetStatusBarColor(c[1], c[2], c[3], 1)
    bar.shield:SetShown(bar.locked)
    if ready then bar.border:SetColor(M.ACCENT[1], M.ACCENT[2], M.ACCENT[3], 1)
    else bar.border:SetColor(M.BORDER[1], M.BORDER[2], M.BORDER[3], 1) end
end

function Cast:Stop(f, interrupted)
    local bar = f.castbar
    if not interrupted and bar.interrupted then return end -- let the red flash finish
    if interrupted and bar:IsShown() then
        bar.interrupted = true
        bar:SetStatusBarColor(0.9, 0.2, 0.2, 1)
        bar.text:SetText(INTERRUPTED or "Interrupted")
        bar.endTime = GetTime() + 0.5
        bar.startTime = bar.endTime - 1
        bar.channel = false
        bar:SetMinMaxValues(0, 1)
        return
    end
    bar:Hide()
end

function Cast:Update(f)
    self:Layout(f)
    self:Start(f)
end

function Cast:Clear(f) f.castbar:Hide() end

ns.Plates:Register(Cast)

local function OnStart(unit)
    local f = ns.Plates:ForUnit(unit)
    if f and f.active then Cast:Start(f) end
end
local function OnStop(unit)
    local f = ns.Plates:ForUnit(unit)
    if f and f.active then Cast:Stop(f) end
end
-- A failed second cast must not hide the one still running.
local function OnFailed(unit, castID)
    local f = ns.Plates:ForUnit(unit)
    if not f or not f.active then return end
    local current = f.castbar.castID
    if current and castID and C.AllReadable(castID) and castID ~= current then return end
    Cast:Stop(f)
end
local function OnInterrupted(unit)
    local f = ns.Plates:ForUnit(unit)
    if f and f.active then Cast:Stop(f, true) end
end

ns:On("UNIT_SPELLCAST_START", OnStart)
ns:On("UNIT_SPELLCAST_DELAYED", OnStart)
ns:On("UNIT_SPELLCAST_CHANNEL_START", OnStart)
ns:On("UNIT_SPELLCAST_CHANNEL_UPDATE", OnStart)
ns:On("UNIT_SPELLCAST_INTERRUPTIBLE", OnStart)
ns:On("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", OnStart)
ns:On("UNIT_SPELLCAST_STOP", OnStop)
ns:On("UNIT_SPELLCAST_CHANNEL_STOP", OnStop)
ns:On("UNIT_SPELLCAST_FAILED", OnFailed)
ns:On("UNIT_SPELLCAST_INTERRUPTED", OnInterrupted)
