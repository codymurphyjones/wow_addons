local ADDON, ns = ...

-- The veil: the way into Modified. /mod (or its key binding) dims the screen and lights your
-- action buttons where they really are. There is no list of bars: click a button and its lens
-- opens in the work area (the desk, docked at the right of the screen: the modifier strip on top,
-- the lens, and the guide column beside it). It stays open until Escape or a click on the desk's
-- background. The mouse wheel over the desk peels through the bars that aren't on screen.
--
-- Only the desk and the lit buttons take the mouse: the rest of the screen stays the game's, so
-- you can target people and watch the lens answer for them.
--
-- Your hands pick the world. Holding Shift, Ctrl or Alt shows that modifier's world while held;
-- a quick tap latches it (tap again to let go), so you can work in it with your hands free.
-- Each modifier is one axis: the eight worlds are the corners of a cube.
local V = {}
ns.Veil = V

local TAP = 0.26   -- a modifier released faster than this (with nothing else pressed) is a tap
local TEX = "Interface\\AddOns\\Modified\\Textures\\"
V.TEX = TEX
V.DESK_W, V.PANEL_W, V.STRIP_H, V.PAD = 900, 340, 100, 12
V.MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- Modifier bits (shift 1, ctrl 2, alt 4) to the Builder's modifier keys.
V.WORLD = { [0] = "none", "shift", "ctrl", "shiftctrl", "alt", "shiftalt", "ctrlalt", "shiftctrlalt" }
local AXIS = { LSHIFT = 1, RSHIFT = 1, LCTRL = 2, RCTRL = 2, LALT = 4, RALT = 4 }

-- The world's colour: each modifier has its own, combinations mix them.
local AXIS_COLOR = { [1] = { 0.35, 0.78, 1 }, [2] = { 1, 0.7, 0.24 }, [4] = { 0.75, 0.47, 1 } }
local WORLD_COLOR = { none = { 0.86, 0.89, 0.94 } }
for bits = 1, 7 do
    local c, n = { 0, 0, 0 }, 0
    for axis, color in pairs(AXIS_COLOR) do
        if bit.band(bits, axis) ~= 0 then
            n = n + 1
            for i = 1, 3 do c[i] = c[i] + color[i] end
        end
    end
    for i = 1, 3 do c[i] = c[i] / n end
    WORLD_COLOR[V.WORLD[bits]] = c
end
function V.WorldColor(key) return WORLD_COLOR[key] or WORLD_COLOR.none end

V.latched, V.held = 0, 0
V.drafts = {} -- [slot] = draft the lens is shaping (kept until sealed, unravelled or /reload)
V.dirty = {}  -- [slot] = true when the draft differs from what's sealed

function V:World()
    -- While you type, the world holds still (Lens.lua sets frozen).
    if ns.Lens and ns.Lens.frozen then return ns.Lens.frozen end
    return V.WORLD[bit.bor(self.latched, self.held)]
end

function V:WorldChanged()
    ns.Lens:WorldChanged()
    ns.Guide:Refresh()
    self:Paint()
end

-- Cursor position in the veil's coordinates.
function V:Cursor()
    local x, y = GetCursorPosition()
    local scale = self.frame:GetEffectiveScale()
    return x / scale, y / scale
end

---------------------------------------------------------------------------
-- Finding the buttons on screen
---------------------------------------------------------------------------

-- The action slot a frame shows, if it is an action button: Blizzard's keep it in .action,
-- bar addons in the secure "action" attribute.
local function SlotOf(f)
    if f:IsForbidden() or rawget(f, "modifiedOwn") then return end
    local objType = f:GetObjectType()
    if objType ~= "CheckButton" and objType ~= "Button" then return end
    -- Some frames (anchored to secret health bars) report secret sizes; never compare those.
    local visible, width = f:IsVisible(), f:GetWidth()
    if ns.IsSecret(visible) or ns.IsSecret(width) or not visible or width <= 12 then return end
    local slot = rawget(f, "action")
    if type(slot) ~= "number" and rawget(f, "_state_type") == "action" then
        slot = tonumber(rawget(f, "_state_action")) -- LibActionButton (Bartender4, ElvUI)
    end
    if type(slot) ~= "number" then
        local ok, kind, attr = pcall(function() return f:GetAttribute("type"), f:GetAttribute("action") end)
        slot = ok and kind == "action" and tonumber(attr) or nil
    end
    if slot and not ns.IsSecret(slot) and slot >= 1 and slot <= 180 and slot == math.floor(slot) then return slot end
end

local function FindButtons()
    local found, f = {}, EnumerateFrames()
    while f do
        local ok, slot = pcall(SlotOf, f)
        if ok and slot then found[#found + 1] = { button = f, slot = slot } end
        f = EnumerateFrames(f)
    end
    return found
end

---------------------------------------------------------------------------
-- Reflections: the lit copies of your buttons, above the veil
---------------------------------------------------------------------------

local function Masked(parent, layer)
    local tex = parent:CreateTexture(nil, layer)
    local mask = parent:CreateMaskTexture()
    mask:SetTexture(V.MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(tex)
    tex:AddMaskTexture(mask)
    return tex
end
V.Masked = Masked

local function CreateReflection()
    local r = CreateFrame("Frame", nil, V.frame)
    r.modifiedOwn = true
    r:SetFrameLevel(V.frame:GetFrameLevel() + 30)
    r:EnableMouse(true)
    r:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then V:OpenButton(self) end
    end)
    r.glow = r:CreateTexture(nil, "BACKGROUND")
    r.glow:SetTexture(TEX .. "Glow")
    r.glow:SetPoint("CENTER")
    r.icon = Masked(r, "ARTWORK")
    r.icon:SetPoint("CENTER")
    r.halo = r:CreateTexture(nil, "OVERLAY")
    r.halo:SetTexture(TEX .. "Ring")
    r.halo:SetPoint("CENTER")
    -- One dot per world the button has a voice in, on a small arc above it.
    r.dots = {}
    for i = 0, 7 do
        local d = r:CreateTexture(nil, "OVERLAY")
        d:SetTexture(TEX .. "Dot")
        d:SetSize(6, 6)
        r.dots[i] = d
    end
    -- Unsealed changes breathe.
    r.breath = r.halo:CreateAnimationGroup()
    r.breath:SetLooping("BOUNCE")
    local a = r.breath:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.25)
    a:SetDuration(0.8)
    a:SetSmoothing("IN_OUT")
    return r
end

-- What a button would cast right now in the current world: the sealed or draft design's voice,
-- else the action on the slot.
function V:VoiceIcon(slot)
    local design = self.drafts[slot] or ns.db.designs[slot]
    if design and ns.Lens then
        local icon = ns.Lens:VoiceIcon(design, self:World())
        if icon then return icon end
    end
    return GetActionTexture(slot)
end

function V:PaintReflection(r)
    local slot = r.slot
    local size = r.size
    r:SetSize(size, size)
    r.icon:SetSize(size - 4, size - 4)
    r.halo:SetSize(size * 1.45, size * 1.45)
    r.glow:SetSize(size * 2.2, size * 2.2)
    local icon = self:VoiceIcon(slot)
    r.icon:SetTexture(icon)
    r.icon:SetAlpha(icon and 1 or 0)
    local design = ns.db.designs[slot]
    local draft = self.drafts[slot]
    local shown = draft or design
    local color = V.WorldColor(self:World())
    if design and design.detached then
        r.halo:SetVertexColor(1, 0.3, 0.3)
    elseif shown then
        r.halo:SetVertexColor(color[1], color[2], color[3])
    else
        r.halo:SetVertexColor(0.6, 0.66, 0.75)
    end
    r.halo:SetAlpha(shown and 0.95 or 0.4)
    local hot = self.hover == r or (ns.Lens:IsOpen() and ns.Lens.slot == slot)
    r.glow:SetVertexColor(color[1], color[2], color[3])
    r.glow:SetAlpha(hot and 0.55 or 0)
    if self.dirty[slot] then
        if not r.breath:IsPlaying() then r.breath:Play() end
    elseif r.breath:IsPlaying() then
        r.breath:Stop()
    end
    -- World dots: which corners of the cube this button speaks in.
    local used = {}
    for _, rule in ipairs(shown and shown.rules or {}) do
        if ns.Builder:RuleHasAction(rule) then used[rule.mod] = true end
    end
    local n = 0
    for bits = 0, 7 do
        if used[V.WORLD[bits]] then n = n + 1 end
    end
    local i = 0
    for bits = 0, 7 do
        local d = r.dots[bits]
        local key = V.WORLD[bits]
        if used[key] then
            local angle = math.rad(90 + (i - (n - 1) / 2) * 16)
            local radius = size * 0.72
            d:ClearAllPoints()
            d:SetPoint("CENTER", r, "CENTER", radius * math.cos(angle), radius * math.sin(angle))
            local c = V.WorldColor(key)
            d:SetVertexColor(c[1], c[2], c[3])
            d:SetAlpha(key == self:World() and 1 or 0.6)
            d:Show()
            i = i + 1
        else
            d:Hide()
        end
    end
end

-- Bars with no button on screen, peeled through with the wheel.
function V:HiddenBars(visible)
    local list = {}
    for _, bar in ipairs(ns.Bars.ALL) do
        local any = false
        for i = 0, ns.Bars.BUTTONS_PER_BAR - 1 do
            if visible[bar.start + i] then any = true end
        end
        if not any and (not bar.requires or _G[bar.requires]) then list[#list + 1] = bar end
    end
    return list
end

-- A click on a lit button opens its lens (or switches the open lens to it).
function V:OpenButton(r)
    if ns.Lens:IsOpen() and ns.Lens.slot == r.slot then return end
    ns.Lens.hold = nil
    ns.Lens:Bloom(r.slot, r)
    self:Paint()
end

-- The desk: in the middle of the screen, kept above your bars (the lit buttons it finds), or
-- where you dragged it (ModifiedDB.deskPoint, the desk's bottom-left corner).
function V:PlaceDesk()
    local f = self.frame
    local W, H = f:GetWidth(), f:GetHeight()
    local barsTop = 0
    for _, r in ipairs(self.active or {}) do
        if not r.floating then
            local _, y = r:GetCenter()
            if y and y < H * 0.45 then barsTop = math.max(barsTop, y + (r.size or 36) / 2) end
        end
    end
    local width = math.min(V.DESK_W, W - 40)
    local left, bottom, height
    local saved = ns.db.deskPoint
    if saved then
        height = math.max(320, math.min(680, H - 20 - saved.y))
        left = math.max(0, math.min(W - width, saved.x))
        bottom = math.max(0, math.min(H - height, saved.y))
    else
        height = math.max(320, math.min(680, H - 30 - (barsTop + 16)))
        left = (W - width) / 2
        bottom = math.max(barsTop + 16, (H - height) / 2)
        if bottom + height > H - 10 then bottom = math.max(0, H - 10 - height) end
    end
    self.desk:ClearAllPoints()
    self.desk:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", left, bottom)
    self.desk:SetSize(width, height)
    self.deskRect = { left = left, right = left + width, bottom = bottom, top = bottom + height }
    -- The lens's room: the desk's left part, below the strip (Lens.lua's Place).
    self.safeLeft = left + V.PAD
    self.safeRight = left + width - V.PANEL_W - 2 * V.PAD
    self.safeTop = H - (bottom + height - V.STRIP_H)
    self.deskBottom = bottom
end

function V:Scan()
    self.pool = self.pool or {}
    self.active = {}
    local visible = {}
    local n = 0
    local function Take()
        n = n + 1
        local r = self.pool[n] or CreateReflection()
        self.pool[n] = r
        r:ClearAllPoints()
        r.floating = nil
        r:Show()
        self.active[#self.active + 1] = r
        return r
    end
    local scale = self.frame:GetEffectiveScale()
    for _, found in ipairs(FindButtons()) do
        local r = Take()
        r.slot = found.slot
        r.size = found.button:GetWidth() * found.button:GetEffectiveScale() / scale
        r:SetPoint("CENTER", found.button, "CENTER")
        visible[found.slot] = true
    end
    self:PlaceDesk()
    -- The peeled page: its twelve buttons on a crescent in the desk's lens area.
    self.hidden = self:HiddenBars(visible)
    if self.depth > #self.hidden then self.depth = 0 end
    local bar = self.hidden[self.depth]
    if bar then
        for i = 0, ns.Bars.BUTTONS_PER_BAR - 1 do
            local r = Take()
            r.slot = bar.start + i
            r.size = 38
            r.floating = true
            local cx = (self.safeLeft + self.safeRight) / 2
            local cy = (self.deskBottom + self.frame:GetHeight() - self.safeTop) / 2 + 60
            local angle = math.rad(200 + i * (140 / (ns.Bars.BUTTONS_PER_BAR - 1)))
            r:SetPoint("CENTER", self.frame, "BOTTOMLEFT", cx + 200 * math.cos(angle), cy + 200 * math.sin(angle))
        end
        self.page:ClearAllPoints()
        self.page:SetPoint("CENTER", self.frame, "BOTTOMLEFT", (self.safeLeft + self.safeRight) / 2,
            (self.deskBottom + self.frame:GetHeight() - self.safeTop) / 2 + 60)
        self.page:SetText(("%s\n|cff8090a0wheel for the next|r"):format(bar.name))
    else
        self.page:SetText("")
    end
    for i = n + 1, #self.pool do self.pool[i]:Hide() end
    self:Paint()
end

function V:Paint()
    if not self.frame or not self.frame:IsShown() then return end
    for _, r in ipairs(self.active) do self:PaintReflection(r) end
end

---------------------------------------------------------------------------
-- The veil
---------------------------------------------------------------------------

function V:Create()
    if self.frame then return self.frame end
    local f = CreateFrame("Frame", "ModifiedVeil", UIParent)
    f.modifiedOwn = true
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetAllPoints(UIParent)
    f:EnableMouse(false) -- the game stays clickable: target people while you edit
    f:Hide()
    tinsert(UISpecialFrames, f:GetName()) -- Escape lifts it (when the lens isn't listening)
    self.frame = f
    self.depth = 0

    -- The work area: the only part of the screen (besides the lit buttons) that takes the mouse.
    local desk = CreateFrame("Frame", nil, f)
    desk.modifiedOwn = true
    desk:SetFrameLevel(f:GetFrameLevel() + 1)
    desk:EnableMouse(true)
    desk:EnableMouseWheel(true)
    -- With no button open, drag the background to move the work area; it remembers where.
    desk:SetMovable(true)
    desk:SetClampedToScreen(true)
    desk:RegisterForDrag("LeftButton")
    desk:SetScript("OnDragStart", function(self)
        if ns.Lens:IsOpen() or ns.Guide:Owns() then return end
        V.dragging = true
        self:StartMoving()
    end)
    desk:SetScript("OnDragStop", function(self)
        if not V.dragging then return end
        V.dragging = nil
        self:StopMovingOrSizing()
        ns.db.deskPoint = { x = self:GetLeft(), y = self:GetBottom() }
        V:Scan()
    end)
    desk.bg = desk:CreateTexture(nil, "BACKGROUND")
    desk.bg:SetAllPoints()
    desk.bg:SetColorTexture(0.02, 0.025, 0.045, 0.86)
    desk.edge = desk:CreateTexture(nil, "BORDER")
    desk.edge:SetPoint("TOPLEFT")
    desk.edge:SetPoint("TOPRIGHT")
    desk.edge:SetHeight(2)
    desk.edge:SetColorTexture(1, 0.82, 0, 0.7)
    self.desk = desk

    local deselect = CreateFrame("Frame", nil, desk)
    deselect:SetSize(150, 22)
    deselect:SetPoint("TOPRIGHT", -V.PAD, -6)
    deselect:SetFrameLevel(desk:GetFrameLevel() + 20)
    deselect.bg = deselect:CreateTexture(nil, "BACKGROUND")
    deselect.bg:SetAllPoints()
    deselect.bg:SetColorTexture(0.35, 0.08, 0.08, 0.9)
    deselect.label = deselect:CreateFontString(nil, "OVERLAY", "ModifiedGameFontHighlightSmall")
    deselect.label:SetPoint("CENTER")
    deselect.label:SetText("Deselect button")
    deselect:Hide()
    self.deselect = deselect

    f.fade = f:CreateAnimationGroup()
    local a = f.fade:CreateAnimation("Alpha")
    a:SetFromAlpha(0)
    a:SetToAlpha(1)
    a:SetDuration(0.35)
    a:SetSmoothing("OUT")

    -- Words go on a layer above the reflections and the lens.
    local ink = CreateFrame("Frame", nil, f)
    ink:SetAllPoints()
    ink:SetFrameLevel(f:GetFrameLevel() + 60)
    self.ink = ink

    self.page = ink:CreateFontString(nil, "OVERLAY", "ModifiedGameFontNormalLarge")

    -- The one line of help that drifts in when the veil falls, then leaves.
    self.hint = ink:CreateFontString(nil, "OVERLAY", "ModifiedGameFontHighlight")
    self.hint:SetPoint("BOTTOM", desk, "TOP", 0, 8)
    self.hint.fade = self.hint:CreateAnimationGroup()
    local h = self.hint.fade:CreateAnimation("Alpha")
    h:SetFromAlpha(1)
    h:SetToAlpha(0)
    h:SetStartDelay(4)
    h:SetDuration(1.5)
    self.hint.fade:SetScript("OnFinished", function() self.hint:SetAlpha(0) end)

    -- Words near the cursor: the only text the Bloom shows, and only where you look.
    self.whisper = ink:CreateFontString(nil, "OVERLAY", "ModifiedGameFontHighlight")
    ns.Guide:Create(desk, ink)
    self.whisper:SetJustifyH("LEFT")
    self.whisper:SetShadowOffset(1, -1)

    f:SetScript("OnShow", function() f.fade:Play() end)
    f:SetScript("OnHide", function() V:OnLifted() end)
    f:SetScript("OnUpdate", function(_, elapsed)
        local ok, err = pcall(V.Update, V, elapsed)
        if not ok then V:Fail(err) end
    end)
    desk:SetScript("OnMouseDown", function(_, button)
        V.touched = true
        -- The deselect button: close this button's editor and go back to picking one.
        if button == "LeftButton" and V.deselect:IsShown() and V.deselect:IsMouseOver() then
            V.skipClick = true
            ns.Lens:Dissolve()
            return
        end
        -- The strip switches sets; the guide column is only for reading.
        V.skipClick = (button == "LeftButton" and ns.Guide:Click()) or ns.Guide:Owns()
        if V.skipClick then return end
        if ns.Lens:IsOpen() then ns.Lens:MouseDown(button) end
    end)
    desk:SetScript("OnMouseUp", function(_, button)
        if V.skipClick then
            V.skipClick = nil
            return
        end
        if ns.Lens:IsOpen() then ns.Lens:MouseUp(button) end
    end)
    desk:SetScript("OnMouseWheel", function(_, delta)
        V.touched = true
        if ns.Guide:Owns() then return end
        if ns.Lens:IsOpen() and ns.Lens:Wheel(delta) then return end
        V:Peel(delta)
    end)
    ns.Lens:Create(f)
    return f
end

function V:Peel(delta)
    local count = #(self.hidden or {})
    if count == 0 then
        self:Whisper("Every bar you have is already on screen.")
        return
    end
    self.depth = (self.depth + (delta < 0 and 1 or -1)) % (count + 1)
    ns.Lens:Dissolve()
    self:Scan()
end

function V:Open()
    if InCombatLockdown() then
        ns:Print("The veil can't fall in combat.")
        return
    end
    local f = self:Create()
    ns.Manager:UpdateDetached()
    self.latched = 0
    self.held = 0
    f:Show()
    local ok, err = pcall(self.Scan, self)
    if not ok then return self:Fail(err) end
    if #self.active == 0 then
        ns:Print("The veil found none of your action buttons on screen. Wheel over the work area to reach your bars, "
            .. "or use /mod classic.")
    end
    -- The guide panels explain everything else (Guide.lua).
    local hint = ""
    if ns.needsReload and not ns.db.autoReload then
        hint = "|cffffd100Modified changed your bars: /reload before your next fight.|r"
    end
    self.hint:SetText(hint)
    self.hint:SetAlpha(1)
    self.hint.fade:Stop()
    self.hint.fade:Play()
end

-- Something went wrong: never leave a dead overlay behind. Lift the veil and say why.
function V:Fail(err)
    self.failed = true
    if self.frame then self.frame:Hide() end
    ns:Print("|cffff5555The veil hit an error and lifted:|r " .. tostring(err), true)
    ns:Print("/mod classic still opens the old window.", true)
end

function V:Close()
    if self.frame then self.frame:Hide() end
end

function V:Toggle()
    if self.frame and self.frame:IsShown() then self:Close() else self:Open() end
end

function V:IsOpen() return self.frame and self.frame:IsShown() end

function V:OnLifted()
    ns.Lens:Dissolve()
    self.hover = nil
    self.whisper:SetText("")
end

-- What a button would cast depends on your target and focus: repaint the lit buttons.
for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UNIT_FLAGS" }) do
    ns:On(event, function(unit)
        if event == "UNIT_FLAGS" and unit ~= "target" and unit ~= "focus" then return end
        if V:IsOpen() then V:Paint() end
    end)
end

-- Combat lifts the veil: its frames must never sit over your buttons in a fight.
ns:On("PLAYER_REGEN_DISABLED", function()
    if V:IsOpen() then
        V:Close()
        ns:Print("The veil lifted for combat. Unsealed changes are kept.")
    end
end)

function V:Refresh()
    -- A draft nobody changed is only a copy of what's sealed; let it follow changes made elsewhere
    -- (/mod classic, a re-sync).
    for slot in pairs(self.drafts) do
        if not self.dirty[slot] and not (ns.Lens:IsOpen() and ns.Lens.slot == slot) then self.drafts[slot] = nil end
    end
    if not self:IsOpen() then return end
    local ok, err = pcall(self.Scan, self)
    if not ok then self:Fail(err) end
end

---------------------------------------------------------------------------
-- Hands and pointing
---------------------------------------------------------------------------

V.downAt = {}

local KEY_DOWN = { [1] = IsShiftKeyDown, [2] = IsControlKeyDown, [4] = IsAltKeyDown }

-- A modifier pressed and released quickly, with nothing else pressed meanwhile, is a tap: it
-- latches (or lets go of) that axis. Held alone for longer than a tap, it peeks: its world shows
-- until it's released. Held while typing or clicking (Shift for a capital), it does neither.
ns:On("MODIFIER_STATE_CHANGED", function(key, down)
    if not V:IsOpen() then return end
    local axis = AXIS[key]
    if not axis then return end
    local before = V:World()
    if down == 1 or down == true then
        V.downAt[axis] = GetTime()
        V.touched = false
    else
        local at = V.downAt[axis]
        V.downAt[axis] = nil
        if at and bit.band(V.held, axis) == 0 and GetTime() - at < TAP and not V.touched
            and not ns.Lens:IsSpeaking() then
            V.latched = bit.bxor(V.latched, axis)
        end
        V.held = bit.band(V.held, bit.bnot(axis))
    end
    if V:World() ~= before then V:WorldChanged() end
end)

function V:Hands()
    local before = self:World()
    for axis, isDown in pairs(KEY_DOWN) do
        local at = self.downAt[axis]
        -- Ctrl held over a rule is for Ctrl + wheel (reordering), not a peek at the Ctrl set.
        local overRule = axis == 2 and ns.Lens:IsOpen() and ns.Lens.raw and ns.Lens.raw.hover
        if at and bit.band(self.held, axis) == 0 and not self.touched and not overRule and GetTime() - at >= TAP then
            self.held = bit.bor(self.held, axis) -- a peek
        elseif bit.band(self.held, axis) ~= 0 and not isDown() then
            self.held = bit.band(self.held, bit.bnot(axis)) -- released while we weren't looking
            self.downAt[axis] = nil
        end
    end
    if self:World() ~= before then self:WorldChanged() end
end

function V:Whisper(text, x, y)
    local w = self.whisper
    if not text or text == "" then
        w:SetText("")
        return
    end
    if not x then x, y = self:Cursor() end
    w:ClearAllPoints()
    -- Keep it on screen: to the cursor's left near the right edge, above it near the bottom.
    local right = x > self.frame:GetWidth() - 360
    local low = y < 200
    local point = (low and "BOTTOM" or "TOP") .. (right and "RIGHT" or "LEFT")
    w:SetPoint(point, self.frame, "BOTTOMLEFT", x + (right and -16 or 18), y + (low and 22 or -14))
    w:SetJustifyH(right and "RIGHT" or "LEFT")
    w:SetText(text)
end

function V:Update(elapsed)
    self:Hands()
    self.deselect:SetShown(ns.Lens:IsOpen())
    ns.Guide:Update(elapsed)
    local x, y = self:Cursor()
    local lens = ns.Lens
    if lens:IsOpen() and lens:Point(x, y, elapsed) then
        local raw = lens.raw
        if raw and (raw.hover or raw.prop or raw.ghostAt or raw.onCore or raw.chip or raw.order) then
            self:SetHover(nil)
            return
        end
    end
    local over
    for _, r in ipairs(self.active or {}) do
        if r:IsShown() and r:IsMouseOver() then
            over = r
            break
        end
    end
    self:SetHover(over)
    if over then
        local info = ns.Bars:GetSlotInfo(over.slot)
        local design = ns.db.designs[over.slot]
        local text = ("%s\n|cff8090a0%s|r"):format(info.name or (info.type and "Unknown action" or "Empty"),
            ns.Bars:Describe(over.slot))
        if design and design.detached then
            text = text .. "\n|cffff6060Its macro was moved off this button. Open it and save to put it back.|r"
        end
        if self.dirty[over.slot] then text = text .. "\n|cffffd100Unsaved changes.|r" end
        if lens:IsOpen() and lens.slot == over.slot then
            text = text .. "\n|cff8090a0This is the button that's open.|r"
        else
            text = text .. "\n|cffffd100Click to open it.|r"
        end
        self:Whisper(text, x, y)
    elseif self.deselect:IsShown() and self.deselect:IsMouseOver() then
        self:Whisper("Close this button's editor and pick another.\n|cff8090a0Unsaved changes are kept until you save or revert.|r", x, y)
    elseif not lens:IsOpen() and self.desk:IsMouseOver() and not ns.Guide:Owns() then
        self:Whisper("|cffffd100Drag to move this area.|r |cff8090a0(/mod reset puts it back in the middle)|r", x, y)
    elseif not ns.Lens:IsOpen() then
        self:Whisper(nil)
    end
end

-- Highlights the button under the cursor (a click opens it: OnMouseUp).
function V:SetHover(r)
    if r == self.hover then return end
    local old = self.hover
    self.hover = r
    if old then self:PaintReflection(old) end
    if r then self:PaintReflection(r) end
end

-- Key binding (Bindings.xml).
BINDING_NAME_MODIFIED_VEIL = "Lower / lift the veil"
function ModifiedVeil_Toggle() V:Toggle() end
