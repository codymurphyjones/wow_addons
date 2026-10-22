local _, ns = ...
local C = ns.Compat

-- The Hearth: the campfire's small flame, on screen for the whole time you're in a party (never a
-- raid). A slim strip with a portrait for each member and a fire at its end:
--   left-click someone    a row of sparks (Marks.SPARKS): "Nice pull", "Clutch heal", "Thanks for
--                         the rez"... One click sends it; the party sees it light up on them.
--   right-click someone   jot a note to yourself about them, in the moment (private, never sent);
--                         it waits for you at the campfire.
--   shift-click           their page
--   the fire              the campfire of this run (drag the strip by its edge to move it)
-- Sparks you receive flash on the fire; sparks between others flash on their portrait. After a
-- fight, when the data saw someone do something worth a thank-you (Moments.FightPrompt), a toast
-- under the strip offers the spark in one click.
local H = {}
ns.Hearth = H

local W = ns.Widgets
local Label, Muted, MakeButton = W.Label, W.Muted, W.MakeButton
local ACCENT = W.ACCENT
local M, F, Mo = ns.Marks, ns.Feedback, ns.Moments

local SMALL, NORMAL = "FiresideGameFontHighlightSmall", "FiresideGameFontNormal"
local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local FIRE = "Interface\\Icons\\Spell_Fire_Fire"
local SIZE, GAP, PAD = 36, 10, 8
local FLASH, FLOAT = 0.9, 1.6
local TOAST_SECONDS, GOT_SECONDS = 12, 3.5

local strip, picker, jotBox, toast
local buttons = {}
local counts = {} -- compact name -> sparks they've received this party (you: "me")

local function Round(tex, parent)
    if not (parent.CreateMaskTexture and tex.AddMaskTexture) then return end
    local mask = parent:CreateMaskTexture()
    mask:SetTexture(ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(tex)
    tex:AddMaskTexture(mask)
end

local function Key(name) return ns.Units.Compact(name) or "?" end

-- A flash of fire behind a texture-holding frame, and a line of text rising off it.
local function AddFlash(b, size)
    b.flash = b:CreateTexture(nil, "BACKGROUND"); b.flash:SetSize(size * 1.9, size * 1.9); b.flash:SetPoint("CENTER")
    b.flash:SetTexture(FIRE); b.flash:SetBlendMode("ADD"); Round(b.flash, b); b.flash:SetAlpha(0)
    b.float = b:CreateFontString(nil, "OVERLAY", SMALL); b.float:SetPoint("BOTTOM", b, "TOP", 0, 4); b.float:SetAlpha(0)
    b.flashT, b.floatT = 99, 99
    b:SetScript("OnUpdate", function(self, elapsed)
        if self.flashT < FLASH then
            self.flashT = self.flashT + elapsed
            self.flash:SetAlpha(math.max(0, 1 - self.flashT / FLASH))
        end
        if self.floatT < FLOAT then
            self.floatT = self.floatT + elapsed
            local t = self.floatT / FLOAT
            self.float:ClearAllPoints(); self.float:SetPoint("BOTTOM", self, "TOP", 0, 4 + t * 26)
            self.float:SetAlpha(t < 0.7 and 1 or math.max(0, 1 - (t - 0.7) / 0.3))
        end
    end)
end

local function Flash(b, text)
    if not b then return end
    b.flashT = 0
    if text then b.float:SetText(text); b.floatT = 0 end
end

-- ---------------------------------------------------------------------------
-- The spark picker and the jot box
-- ---------------------------------------------------------------------------

local function HidePopups()
    if picker then picker:Hide() end
    if jotBox then jotBox:Hide() end
end

local function BuildPicker()
    local p = CreateFrame("Frame", "FiresideSparkPicker", UIParent, "BackdropTemplate")
    p:SetFrameStrata("DIALOG"); W.SetBackdrop(p, 0.96); p:EnableMouse(true)
    p.title = Label(p, "", SMALL, 8, -6, 300)
    p.buttons = {}
    for i, s in ipairs(M.SPARKS) do
        local b = MakeButton(p, "", 28, 28)
        b:SetPoint("TOPLEFT", 6 + (i - 1) * 30, -24)
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetPoint("TOPLEFT", 3, -3); b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
        b.icon:SetTexture(M.SparkIconPath(s.id)); b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.s = s.id
        b:SetScript("OnClick", function(self)
            local ok, why = F:Spark(p.full, self.s)
            if not ok and why == "soon" then ns:Print("You just sent them that one.", true) end
            p:Hide()
        end)
        W.Hint(b, s.label, "Sends it now: your party sees it light up on them.")
        p.buttons[i] = b
    end
    p:SetSize(12 + #M.SPARKS * 30, 60)
    p.idle = 0
    p:SetScript("OnUpdate", function(self, elapsed)
        if self:IsMouseOver() or (self.owner and self.owner:IsMouseOver()) then self.idle = 0 return end
        self.idle = self.idle + elapsed
        if self.idle > 2.5 then self:Hide() end
    end)
    tinsert(UISpecialFrames, "FiresideSparkPicker")
    p:Hide()
    return p
end

local function OpenPicker(b)
    HidePopups()
    picker = picker or BuildPicker()
    picker.full, picker.owner, picker.idle = b.full, b, 0
    picker.title:SetText(("A spark for %s"):format(C.Colored(C.Short(b.full), b.class)))
    picker:ClearAllPoints(); picker:SetPoint("BOTTOM", b, "TOP", 0, 14)
    picker:Show()
end

local function BuildJotBox()
    local j = CreateFrame("Frame", "FiresideJotBox", UIParent, "BackdropTemplate")
    j:SetFrameStrata("DIALOG"); W.SetBackdrop(j, 0.97); j:EnableMouse(true); j:SetSize(340, 74)
    j.title = Label(j, "", SMALL, 8, -6, 324)
    j.sub = Muted(Label(j, "Only you see it. It waits for you at the campfire.", SMALL, 8, -20, 324))
    j.box = W.MakeEditBox(j, 324, "What just happened? (Enter to keep it)")
    j.box:SetPoint("TOPLEFT", 8, -38); j.box:SetMaxLetters(F.MAX_JOT)
    j.box:SetScript("OnEnterPressed", function(self)
        if F:Jot(j.full, self:GetText()) then
            Flash(j.owner, "jotted")
        end
        self:SetText(""); self:ClearFocus(); j:Hide()
    end)
    j.box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); j:Hide() end)
    tinsert(UISpecialFrames, "FiresideJotBox")
    j:Hide()
    return j
end

local function OpenJot(b)
    HidePopups()
    jotBox = jotBox or BuildJotBox()
    jotBox.full, jotBox.owner = b.full, b
    local n = #F.JotsIn(F.LiveRun(), b.full)
    jotBox.title:SetText(("A note about %s%s"):format(C.Colored(C.Short(b.full), b.class),
        n > 0 and ("  |cffaaaaaa(%d this run)|r"):format(n) or ""))
    jotBox:ClearAllPoints(); jotBox:SetPoint("BOTTOM", b, "TOP", 0, 14)
    jotBox:Show()
    jotBox.box:SetFocus()
end

-- ---------------------------------------------------------------------------
-- The toast: a prompt after a fight, or a spark you received
-- ---------------------------------------------------------------------------

local function BuildToast()
    local t = CreateFrame("Frame", nil, strip, "BackdropTemplate")
    t:SetHeight(34); W.SetBackdrop(t, 0.95)
    t:SetPoint("TOP", strip, "BOTTOM", 0, -4)
    t.icon = t:CreateTexture(nil, "ARTWORK"); t.icon:SetSize(24, 24); t.icon:SetPoint("LEFT", 6, 0)
    t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92); Round(t.icon, t)
    t.text = t:CreateFontString(nil, "OVERLAY", SMALL); t.text:SetPoint("LEFT", t.icon, "RIGHT", 8, 0); t.text:SetJustifyH("LEFT")
    t.send = MakeButton(t, "", 120, 22); t.send:SetPoint("RIGHT", -30, 0)
    t.close = MakeButton(t, "X", 20, 20); t.close:SetPoint("RIGHT", -6, 0)
    t.close:SetScript("OnClick", function() t:Hide() end)
    t.send:SetScript("OnClick", function()
        if t.prompt then F:Spark(t.prompt.full, t.prompt.s) end
        t:Hide()
    end)
    t:SetScript("OnUpdate", function(self, elapsed)
        if self:IsMouseOver() then return end
        self.left = self.left - elapsed
        if self.left <= 0 then self:Hide() end
    end)
    t:Hide()
    return t
end

local function ShowToast(icon, text, prompt, seconds)
    if not (strip and strip:IsShown()) then return end
    toast = toast or BuildToast()
    toast.icon:SetTexture(icon)
    toast.text:SetText(text)
    toast.prompt = prompt
    toast.send:SetShown(prompt ~= nil)
    if prompt then toast.send.text:SetText("Send " .. M.SparkLabel(prompt.s)) end
    toast.send:SetWidth(math.max(90, (toast.send.text:GetStringWidth() or 60) + 20))
    local w = 6 + 24 + 8 + (toast.text:GetStringWidth() or 200) + 12 + (prompt and toast.send:GetWidth() + 8 or 0) + 30
    toast:SetWidth(math.max(220, w))
    toast.left = seconds
    toast:Show()
end

-- ---------------------------------------------------------------------------
-- The strip
-- ---------------------------------------------------------------------------

local function SavePosition()
    local point, _, _, x, y = strip:GetPoint()
    local s = ns.char.hearth
    s.point, s.x, s.y = point, math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5)
end

local function Build()
    strip = CreateFrame("Frame", "FiresideHearth", UIParent, "BackdropTemplate")
    strip:SetHeight(SIZE + PAD * 2 + 4); W.SetBackdrop(strip, 0.82)
    strip:SetFrameStrata("MEDIUM"); strip:SetClampedToScreen(true)
    strip:SetMovable(true); strip:EnableMouse(true); strip:RegisterForDrag("LeftButton")
    strip:SetScript("OnDragStart", strip.StartMoving)
    strip:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition() end)
    local s = ns.char.hearth
    strip:SetPoint(s.point or "TOP", UIParent, s.point or "TOP", s.x or 0, s.y or -120)

    -- The fire: this run's campfire, and where your own sparks land.
    local fire = CreateFrame("Button", nil, strip)
    fire:SetSize(SIZE, SIZE); fire:SetPoint("LEFT", PAD, 0)
    fire.icon = fire:CreateTexture(nil, "ARTWORK"); fire.icon:SetAllPoints(); fire.icon:SetTexture(FIRE)
    fire.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92); Round(fire.icon, fire)
    fire.count = fire:CreateFontString(nil, "OVERLAY", SMALL); fire.count:SetPoint("BOTTOMRIGHT", 4, -2)
    AddFlash(fire, SIZE)
    fire:SetScript("OnClick", function() ns.Campfire:OpenLatest() end)
    fire:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Fireside", ACCENT[1], ACCENT[2], ACCENT[3])
        local n = counts.me or 0
        GameTooltip:AddLine(n > 0 and ("%d spark%s for you so far."):format(n, n == 1 and "" or "s") or "No sparks for you yet.", 1, 1, 1)
        GameTooltip:AddLine("Click: this run's campfire.", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("Left-click someone: a spark. Right-click: a note to yourself.", 0.75, 0.8, 0.85, true)
        GameTooltip:AddLine("Drag the strip's edge to move it.", 0.75, 0.8, 0.85)
        GameTooltip:Show()
    end)
    fire:SetScript("OnLeave", function() GameTooltip:Hide() end)
    strip.fire = fire
    strip:Hide()
end

local function Button(i)
    local b = buttons[i]
    if b then return b end
    b = CreateFrame("Button", nil, strip)
    b:SetSize(SIZE, SIZE)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.ring = b:CreateTexture(nil, "BORDER"); b.ring:SetSize(SIZE + 4, SIZE + 4); b.ring:SetPoint("CENTER")
    b.ring:SetColorTexture(1, 1, 1, 1); Round(b.ring, b)
    b.portrait = b:CreateTexture(nil, "ARTWORK"); b.portrait:SetAllPoints(); Round(b.portrait, b)
    b.count = b:CreateFontString(nil, "OVERLAY", SMALL); b.count:SetPoint("BOTTOMRIGHT", 4, -2)
    b.jots = b:CreateFontString(nil, "OVERLAY", SMALL); b.jots:SetPoint("TOPRIGHT", 4, 2)
    AddFlash(b, SIZE)
    b:SetScript("OnClick", function(self, button)
        if IsShiftKeyDown() then return ns.UI:ShowPlayer(self.full) end
        if button == "RightButton" then return OpenJot(self) end
        OpenPicker(self)
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(C.Colored(C.Short(self.full), self.class))
        local known = M.KnownLine(self.full, 3)
        if known then GameTooltip:AddLine(known, 1, 1, 1, true) end
        local n = counts[Key(self.full)] or 0
        if n > 0 then GameTooltip:AddLine(("%d spark%s from the party so far."):format(n, n == 1 and "" or "s"), 0.9, 0.92, 0.95) end
        GameTooltip:AddLine("Left-click: send a spark.  Right-click: jot a note.", 0.75, 0.8, 0.85)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    buttons[i] = b
    return b
end

local function SetPortrait(tex, unit, class)
    tex:SetTexCoord(0, 1, 0, 1)
    if unit and SetPortraitTexture and C.Bool(C.Call(UnitIsVisible, unit)) then
        SetPortraitTexture(tex, unit)
        return
    end
    local coords = CLASS_ICON_TCOORDS and class and CLASS_ICON_TCOORDS[class]
    if coords then
        tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
end

local function Wanted()
    return ns.db and ns.db.options.hearth ~= false and IsInGroup() and not IsInRaid()
end

function H:Refresh()
    if not Wanted() then
        if strip then strip:Hide() end
        HidePopups()
        return
    end
    if not strip then Build() end
    local n = 0
    local run = F.LiveRun()
    for _, unit in ipairs(C.GroupUnits()) do
        local full = C.UnitFull(unit)
        if full then
            n = n + 1
            local b = Button(n)
            local _, class = C.Call(UnitClass, unit)
            b.full, b.unit, b.class = full, unit, C.Str(class)
            local _, r, g, bl = ns.Units.ClassColor(b.class, { 0.5, 0.55, 0.6 })
            b.ring:SetVertexColor(r, g, bl, 1)
            SetPortrait(b.portrait, unit, b.class)
            local c = counts[Key(full)] or 0
            b.count:SetText(c > 0 and ("|cffffd24d%d|r"):format(c) or "")
            local j = run and #F.JotsIn(run, full) or 0
            b.jots:SetText(j > 0 and ("|cffaaaaaa%d|r|TInterface\\Icons\\INV_Misc_Note_01:10:10|t"):format(j) or "")
            b:ClearAllPoints(); b:SetPoint("LEFT", strip.fire, "RIGHT", GAP + (n - 1) * (SIZE + GAP), 0)
            b:Show()
        end
    end
    for i = n + 1, #buttons do buttons[i]:Hide() end
    local mine = counts.me or 0
    strip.fire.count:SetText(mine > 0 and ("|cffffd24d%d|r"):format(mine) or "")
    strip:SetWidth(PAD * 2 + SIZE + n * (SIZE + GAP) + 4)
    strip:Show()
end

local function ButtonFor(name)
    for _, b in ipairs(buttons) do
        if b:IsShown() and b.full and C.SameName(b.full, name) then return b end
    end
end

-- A spark landed (Feedback.lua): count it, light it up.
function H:OnSpark(from, to, s)
    local label = M.SparkLabel(s)
    if C.IsMe(to) then
        counts.me = (counts.me or 0) + 1
        if strip and strip:IsShown() then
            Flash(strip.fire, "+" .. label)
            ShowToast(M.SparkIconPath(s), ("%s: |cffffffff%s|r"):format(C.Colored(C.Short(from), nil), label), nil, GOT_SECONDS)
        end
    else
        local k = Key(to)
        counts[k] = (counts[k] or 0) + 1
        Flash(ButtonFor(to), (C.IsMe(from) and "" or (C.Short(from) .. ": ")) .. label)
    end
    self:Refresh()
end

-- A fight was analyzed (Fight.lua): offer a spark for the best thing the data saw.
function H:OnFight(run, f, deaths)
    if not (ns.db.options.prompts ~= false and strip and strip:IsShown()) then return end
    local p = Mo.FightPrompt(run, f, deaths)
    if not (p and C.InGroup(p.to)) then return end
    local full = ns.Run:FullName(run, p.to) or p.to
    ShowToast(M.SparkIconPath(p.s), p.text, { full = full, s = p.s }, TOAST_SECONDS)
end

ns:On("GROUP_ROSTER_UPDATE", function()
    if not IsInGroup() then wipe(counts) end
    H:Refresh()
end)
ns:On("PLAYER_ENTERING_WORLD", function() H:Refresh() end)
ns:OnChanged(function() H:Refresh() end)
