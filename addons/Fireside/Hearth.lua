local _, ns = ...
local C = ns.Compat

-- The Hearth: the campfire's small flame, on screen for the whole time you're in a group. One of:
--   on the party frames (default)  a small spark button on each member's party frame, and a fire on
--                                  yours, on the portrait's bottom-left corner: clear of buffs and
--                                  debuffs. When some member has no Blizzard party frame showing
--                                  (another unit frame addon), it falls back to the strip.
--   the strip                      a slim strip with a portrait for each member and a fire at its end
--                                  (db.options.hearthFrames off).
--   the raid button                in a raid, and in a party shown with raid-style frames: one button
--                                  that opens the raid kudos window (RaidKudos.lua), so nothing is
--                                  added to the raid frames. Where it sits is db.options.raidSpot:
--                                  "free" (dragged anywhere), "raidframes" (the raid frames area's
--                                  bottom-right corner) or "minimap" (under the minimap); the setup
--                                  wizard shows each spot before you pick one (H:Demo).
-- The party frames and the strip:
--   left-click someone    a row of sparks (Marks.SPARKS): "Nice pull", "Clutch heal", "Thanks for
--                         the rez"... One click sends it; the party sees it light up on them.
--   right-click someone   jot a note to yourself about them, in the moment (private, never sent);
--                         it waits for you at the campfire.
--   shift-click           their page
--   the fire              the campfire of this run (drag the strip by its edge to move it)
-- Sparks you receive flash on the fire; sparks between others flash on their button. After a
-- fight, when the data saw someone do something worth a thank-you (Moments.FightPrompt), a toast
-- where the strip sits offers the spark in one click.
--
-- Party frames are secure: the buttons on them are their children, and they're placed, reparented
-- and shown only out of combat. A roster change in combat waits for combat to end, and a click asks
-- the frame which unit it shows now, so a reshuffled frame never sparks the wrong person.
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
local PIN = 14 -- a button on a party frame: the member's role icon
local ROLE_LABEL = { tank = "Tank", healer = "Healer", damage = "Damage" }
local RAID_SIZE = 30
local FLASH, FLOAT = 0.9, 1.6
local TOAST_SECONDS, GOT_SECONDS = 12, 3.5

local strip, picker, jotBox, toast, myPin, raidBtn, ghost
local buttons = {} -- the strip's
local pins = {}    -- the party frames'
local mode         -- "pins", "strip", "button" or nil (hidden)
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

-- Above a strip button; beside a party frame's (the frames stack down the screen's edge).
local function Place(popup, b)
    popup:ClearAllPoints()
    popup:SetClampedToScreen(true)
    if b.pinned then
        popup:SetPoint("LEFT", b, "RIGHT", 12, 0)
    else
        popup:SetPoint("BOTTOM", b, "TOP", 0, 14)
    end
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
    Place(picker, b)
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
    Place(jotBox, b)
    jotBox:Show()
    jotBox.box:SetFocus()
end

-- ---------------------------------------------------------------------------
-- The toast: a prompt after a fight, or a spark you received
-- ---------------------------------------------------------------------------

local function BuildToast()
    local t = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    t:SetHeight(34); W.SetBackdrop(t, 0.95)
    t:SetFrameStrata("MEDIUM"); t:SetClampedToScreen(true)
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

local function Active() return mode ~= nil end

local function ShowToast(icon, text, prompt, seconds)
    if not Active() then return end
    toast = toast or BuildToast()
    toast:ClearAllPoints()
    if strip and strip:IsShown() then
        toast:SetPoint("TOP", strip, "BOTTOM", 0, -4)
    elseif raidBtn and raidBtn:IsShown() then
        toast:SetPoint("TOP", raidBtn, "BOTTOM", 0, -8)
    else -- where the strip would sit
        local s = ns.char.hearth
        toast:SetPoint(s.point or "TOP", UIParent, s.point or "TOP", s.x or 0, s.y or -120)
    end
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

-- The fire: this run's campfire, and where your own sparks land.
local function MakeFire(parent, size, pinned)
    local fire = CreateFrame("Button", nil, parent)
    fire:SetSize(size, size)
    fire.pinned = pinned
    fire.icon = fire:CreateTexture(nil, "ARTWORK"); fire.icon:SetAllPoints(); fire.icon:SetTexture(FIRE)
    fire.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92); Round(fire.icon, fire)
    fire.count = fire:CreateFontString(nil, "OVERLAY", SMALL); fire.count:SetPoint("BOTTOMRIGHT", 4, -2)
    AddFlash(fire, size)
    fire:SetScript("OnClick", function() ns.Campfire:OpenLatest() end)
    fire:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, self.pinned and "ANCHOR_RIGHT" or "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Fireside", ACCENT[1], ACCENT[2], ACCENT[3])
        local n = counts.me or 0
        GameTooltip:AddLine(n > 0 and ("%d spark%s for you so far."):format(n, n == 1 and "" or "s") or "No sparks for you yet.", 1, 1, 1)
        GameTooltip:AddLine("Click: this run's campfire.", 0.75, 0.8, 0.85)
        GameTooltip:AddLine("Left-click someone: a spark. Right-click: a note to yourself.", 0.75, 0.8, 0.85, true)
        if not self.pinned then GameTooltip:AddLine("Drag the strip's edge to move it.", 0.75, 0.8, 0.85) end
        GameTooltip:Show()
    end)
    fire:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return fire
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
    strip.fire = MakeFire(strip, SIZE)
    strip.fire:SetPoint("LEFT", PAD, 0)
    strip:Hide()
end

-- The unit a party frame shows now.
local function FrameUnit(f)
    local unit = f and (f.unit or (f.GetAttribute and f:GetAttribute("unit")))
    return type(unit) == "string" and unit or nil
end

-- A member's button: a portrait on the strip, a small spark button on a party frame.
local function MakeMember(parent, size, pinned)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.pinned = pinned
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local ring = size + (pinned and 3 or 4)
    b.ring = b:CreateTexture(nil, "BORDER"); b.ring:SetSize(ring, ring); b.ring:SetPoint("CENTER")
    b.ring:SetColorTexture(1, 1, 1, 1); Round(b.ring, b)
    b.portrait = b:CreateTexture(nil, "ARTWORK"); b.portrait:SetAllPoints(); Round(b.portrait, b)
    b.count = b:CreateFontString(nil, "OVERLAY", SMALL); b.count:SetPoint("BOTTOMRIGHT", 4, -2)
    b.jots = b:CreateFontString(nil, "OVERLAY", SMALL); b.jots:SetPoint("TOPRIGHT", 4, 2)
    AddFlash(b, size)
    b:SetScript("OnClick", function(self, button)
        if self.pinned then -- the frame may show someone else since it was placed (a change in combat)
            local unit = FrameUnit(self:GetParent())
            local full = unit and C.UnitFull(unit)
            if not full then return end
            if not C.SameName(full, self.full) then
                local _, class = C.Call(UnitClass, unit)
                self.full, self.unit, self.class = full, unit, C.Str(class)
            end
        end
        if IsShiftKeyDown() then return ns.UI:ShowPlayer(self.full) end
        if button == "RightButton" then return OpenJot(self) end
        OpenPicker(self)
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, self.pinned and "ANCHOR_RIGHT" or "ANCHOR_BOTTOM")
        GameTooltip:AddLine(C.Colored(C.Short(self.full), self.class))
        if self.pinned and self.role then
            GameTooltip:AddLine(("%s (from %s)"):format(ROLE_LABEL[self.role] or self.role, self.roleWhy or "?"), 0.6, 0.65, 0.7)
        end
        local known = M.KnownLine(self.full, 3)
        if known then GameTooltip:AddLine(known, 1, 1, 1, true) end
        local n = counts[Key(self.full)] or 0
        if n > 0 then GameTooltip:AddLine(("%d spark%s from the party so far."):format(n, n == 1 and "" or "s"), 0.9, 0.92, 0.95) end
        GameTooltip:AddLine("Left-click: send a spark.  Right-click: jot a note.", 0.75, 0.8, 0.85)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function Button(i)
    buttons[i] = buttons[i] or MakeMember(strip, SIZE)
    return buttons[i]
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

-- ---------------------------------------------------------------------------
-- Roles: the icon on a party frame's button
-- ---------------------------------------------------------------------------

-- Each member's role ("tank", "healer", "damage") and where it came from, for the whole group at
-- once (one tank and one healer at most get guessed). In order:
--   1. the Dungeon Finder's role (UnitGroupRolesAssigned);
--   2. this run's data: who took the hits and who did the healing (Blame.Roles);
--   3. their specialization, when the game has inspected it;
--   4. a guess from the class: classes that can only deal damage deal damage; otherwise the
--      likeliest tank (warrior, then paladin, then druid) tanks and the likeliest healer (priest,
--      then shaman, druid, paladin) heals, when nobody already does.
local TANK_ORDER = { WARRIOR = 1, PALADIN = 2, DRUID = 3, DEATHKNIGHT = 4, MONK = 5, DEMONHUNTER = 6 }
local HEAL_ORDER = { PRIEST = 1, SHAMAN = 2, DRUID = 3, PALADIN = 4, MONK = 5, EVOKER = 6 }
local ASSIGNED = { TANK = "tank", HEALER = "healer", DAMAGER = "damage" }
local GUESSED = "a guess from the class"

local function SpecRole(unit)
    if not (GetInspectSpecialization and GetSpecializationRoleByID) then return nil end
    local ok, spec = pcall(GetInspectSpecialization, unit)
    if not ok or type(spec) ~= "number" or spec <= 0 then return nil end
    local ok2, role = pcall(GetSpecializationRoleByID, spec)
    return ok2 and ASSIGNED[C.Str(role) or ""] or nil
end

-- unit -> { role, why } for the player and every party member.
local function GroupRoles(run)
    local units = { "player" }
    for _, u in ipairs(C.GroupUnits()) do units[#units + 1] = u end
    local out, class, have = {}, {}, {}
    local tank, healer
    if run then tank, healer = ns.Blame.Roles(run) end
    for _, u in ipairs(units) do
        local _, c = C.Call(UnitClass, u)
        class[u] = C.Str(c)
        local role, why = ASSIGNED[C.Str(C.Call(UnitGroupRolesAssigned, u)) or ""], "the Dungeon Finder"
        if not role then
            local short = C.Short(C.UnitFull(u) or "")
            if tank and short == tank then role, why = "tank", "this run: took the hits"
            elseif healer and short == healer then role, why = "healer", "this run: did the healing" end
        end
        if not role then role, why = SpecRole(u), "their specialization" end
        if role then out[u] = { role = role, why = why }; have[role] = true end
    end
    -- What's left: guessed from the class.
    local function Pick(order, role)
        if have[role] then return end
        local best, rank
        for _, u in ipairs(units) do
            local r = not out[u] and order[class[u] or ""]
            if r and (not rank or r < rank) then best, rank = u, r end
        end
        if best then out[best] = { role = role, why = GUESSED }; have[role] = true end
    end
    Pick(TANK_ORDER, "tank")
    Pick(HEAL_ORDER, "healer")
    for _, u in ipairs(units) do out[u] = out[u] or { role = "damage", why = GUESSED } end
    return out
end

-- The game's small round role art on a texture.
local ROLE_ATLAS = { tank = "roleicon-tiny-tank", healer = "roleicon-tiny-healer", damage = "roleicon-tiny-dps" }
local ROLE_FILE = [[Interface\LFGFrame\UI-LFG-ICON-PORTRAITROLES]]
local ROLE_COORDS = {
    tank = { 0, 19 / 64, 22 / 64, 41 / 64 }, healer = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 },
    damage = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 },
}
local function SetRole(tex, role)
    local atlas = ROLE_ATLAS[role]
    if atlas and tex.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetAtlas(atlas)
        return
    end
    local c = ROLE_COORDS[role] or ROLE_COORDS.damage
    tex:SetTexture(ROLE_FILE)
    tex:SetTexCoord(c[1], c[2], c[3], c[4])
end

-- A button's spark and jot counts.
local function Counts(b, run)
    local c = counts[Key(b.full)] or 0
    b.count:SetText(c > 0 and ("|cffffd24d%d|r"):format(c) or "")
    local j = run and #F.JotsIn(run, b.full) or 0
    b.jots:SetText(j > 0 and ("|cffaaaaaa%d|r|TInterface\\Icons\\INV_Misc_Note_01:10:10|t"):format(j) or "")
end

-- Who a button is for, its class ring and its counts.
local function Fill(b, unit, full, run)
    local _, class = C.Call(UnitClass, unit)
    b.full, b.unit, b.class = full, unit, C.Str(class)
    local _, r, g, bl = ns.Units.ClassColor(b.class, { 0.5, 0.55, 0.6 })
    b.ring:SetVertexColor(r, g, bl, 1)
    Counts(b, run)
end

local function FireCount(fire)
    local mine = counts.me or 0
    fire.count:SetText(mine > 0 and ("|cffffd24d%d|r"):format(mine) or "")
end

local function Wanted()
    return ns.db and ns.db.options.hearth ~= false and IsInGroup()
end

-- ---------------------------------------------------------------------------
-- On the party frames
-- ---------------------------------------------------------------------------

-- Blizzard's unit frames that may show a group member: the classic party frames, the modern
-- PartyFrame's members, raid-style party frames, and the player frame (for your fire).
-- kind "portrait": a portrait on the frame's left, its auras to the right and below.
-- kind "compact": a raid-style frame, its auras inside it, the frames stacked in a column.
local function Candidates()
    local list = {}
    local function Add(f, kind)
        if type(f) == "table" and f.IsVisible then list[#list + 1] = { f, kind } end
    end
    Add(_G.PlayerFrame, "portrait")
    for i = 1, 4 do
        Add(_G["PartyMemberFrame" .. i], "portrait")
        Add(_G.PartyFrame and _G.PartyFrame["MemberFrame" .. i], "portrait")
    end
    for i = 1, 5 do Add(_G["CompactPartyFrameMember" .. i], "compact") end
    return list
end

local function FindFrame(unit, list)
    for _, c in ipairs(list) do
        local f = c[1]
        local shown = FrameUnit(f)
        if shown and f:IsVisible() and (shown == unit or ns.Units.UnitIsUnit(shown, unit)) then
            return f, c[2]
        end
    end
end

local function PortraitOf(f)
    local name = f.GetName and f:GetName()
    return f.portrait or f.Portrait or (name and _G[name .. "Portrait"])
        or (f.PlayerFrameContainer and f.PlayerFrameContainer.PlayerPortrait)
end

-- Onto a frame: its child (so it hides with it), drawn above it, clear of its auras.
local function Attach(b, f, kind)
    b:SetParent(f)
    b:SetFrameStrata(f:GetFrameStrata())
    b:SetFrameLevel(f:GetFrameLevel() + 10)
    b:ClearAllPoints()
    local portrait = kind == "portrait" and PortraitOf(f)
    if portrait then
        b:SetPoint("CENTER", portrait, "BOTTOMLEFT", 5, 5)
    elseif kind == "portrait" then
        b:SetPoint("CENTER", f, "BOTTOMLEFT", 10, 10)
    else
        b:SetPoint("LEFT", f, "RIGHT", 3, 0)
    end
    b:Show()
end

local function HidePins()
    for _, b in ipairs(pins) do b:Hide() end
    if myPin then myPin:Hide() end
end

local function PinsShown()
    if myPin and myPin:IsShown() then return true end
    for _, b in ipairs(pins) do if b:IsShown() then return true end end
end

-- Out of combat only. The look to use: "pins" (placed), "button" (the party shows in raid-style
-- frames: nothing is attached to them) or "strip" (some member has no party frame showing).
local function PlacePins()
    local list, run = Candidates(), F.LiveRun()
    local placed = {}
    for _, unit in ipairs(C.GroupUnits()) do
        local full = C.UnitFull(unit)
        if full then
            local f, kind = FindFrame(unit, list)
            if not f then return "strip" end
            if kind == "compact" then return "button" end
            placed[#placed + 1] = { unit = unit, full = full, f = f, kind = kind }
        end
    end
    if #placed == 0 then return "strip" end
    local roles = GroupRoles(run)
    for i, p in ipairs(placed) do
        local b = pins[i] or MakeMember(UIParent, PIN, true)
        pins[i] = b
        Fill(b, p.unit, p.full, run)
        local r = roles[p.unit] or { role = "damage", why = GUESSED }
        b.role, b.roleWhy = r.role, r.why
        SetRole(b.portrait, r.role)
        Attach(b, p.f, p.kind)
    end
    for i = #placed + 1, #pins do pins[i]:Hide() end
    local f, kind = FindFrame("player", list)
    if f then
        myPin = myPin or MakeFire(UIParent, PIN, true)
        FireCount(myPin)
        Attach(myPin, f, kind)
    elseif myPin then
        myPin:Hide()
    end
    return "pins"
end

-- In combat only the counts change; who sits where waits for combat to end.
local function UpdatePins()
    local run = F.LiveRun()
    for _, b in ipairs(pins) do
        if b:IsShown() and b.full then Counts(b, run) end
    end
    if myPin then FireCount(myPin) end
end

-- ---------------------------------------------------------------------------
-- The strip, and choosing between the two
-- ---------------------------------------------------------------------------

local function ShowStrip()
    if not strip then Build() end
    local n = 0
    local run = F.LiveRun()
    for _, unit in ipairs(C.GroupUnits()) do
        local full = C.UnitFull(unit)
        if full then
            n = n + 1
            local b = Button(n)
            Fill(b, unit, full, run)
            SetPortrait(b.portrait, unit, b.class)
            b:ClearAllPoints(); b:SetPoint("LEFT", strip.fire, "RIGHT", GAP + (n - 1) * (SIZE + GAP), 0)
            b:Show()
        end
    end
    for i = n + 1, #buttons do buttons[i]:Hide() end
    FireCount(strip.fire)
    strip:SetWidth(PAD * 2 + SIZE + n * (SIZE + GAP) + 4)
    strip:Show()
end

-- ---------------------------------------------------------------------------
-- The raid button
-- ---------------------------------------------------------------------------

local function SaveButton()
    local point, _, _, x, y = raidBtn:GetPoint()
    local p = ns.char.raidButton
    p.point, p.x, p.y = point, math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5)
end

local function Spot() return ns.db.options.raidSpot or "free" end

local function BuildRaidButton()
    local b = CreateFrame("Button", "FiresideRaidButton", UIParent)
    b:SetSize(RAID_SIZE, RAID_SIZE)
    b:SetFrameStrata("MEDIUM"); b:SetClampedToScreen(true)
    b:SetMovable(true); b:RegisterForDrag("LeftButton")
    b.ring = b:CreateTexture(nil, "BORDER"); b.ring:SetSize(RAID_SIZE + 4, RAID_SIZE + 4); b.ring:SetPoint("CENTER")
    b.ring:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1); Round(b.ring, b)
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints(); b.icon:SetTexture(FIRE)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92); Round(b.icon, b)
    b.count = b:CreateFontString(nil, "OVERLAY", SMALL); b.count:SetPoint("BOTTOMRIGHT", 4, -2)
    b.preview = b:CreateFontString(nil, "OVERLAY", SMALL); b.preview:SetPoint("TOP", b, "BOTTOM", 0, -4)
    b.preview:SetText("|cffffd24dThe kudos button|r")
    AddFlash(b, RAID_SIZE)
    b:SetScript("OnDragStart", function(self)
        if Spot() == "free" then self:StartMoving() end
    end)
    b:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if Spot() == "free" then SaveButton() end
    end)
    b:SetScript("OnClick", function() if ns.RaidKudos then ns.RaidKudos:Toggle() end end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Fireside: kudos", ACCENT[1], ACCENT[2], ACCENT[3])
        GameTooltip:AddLine("Click: thank the people you've fought beside, with sparks, kudos or a private note.", 1, 1, 1, true)
        local n = counts.me or 0
        if n > 0 then GameTooltip:AddLine(("%d spark%s for you so far."):format(n, n == 1 and "" or "s"), 0.9, 0.92, 0.95) end
        if Spot() == "free" then GameTooltip:AddLine("Drag to move it.", 0.75, 0.8, 0.85) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    return b
end

-- Blizzard's raid frames area while it's on screen: the raid's container, else raid-style party frames.
local function RaidFramesArea()
    for _, name in ipairs({ "CompactRaidFrameContainer", "CompactPartyFrame" }) do
        local f = _G[name]
        if type(f) == "table" and f.IsVisible and f:IsVisible() and f:GetRight() and f:GetBottom() then return f end
    end
end

-- The wizard's preview while no raid frames are up: an outline where they usually sit.
local function Ghost()
    if not ghost then
        ghost = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        ghost:SetSize(180, 260); ghost:SetPoint("LEFT", 20, 40); ghost:SetFrameStrata("MEDIUM")
        W.SetBackdrop(ghost, 0.35)
        ghost:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
        local l = ghost:CreateFontString(nil, "OVERLAY", NORMAL); l:SetPoint("CENTER")
        l:SetText("Your raid frames")
    end
    ghost:Show()
    return ghost
end

-- The button where db.options.raidSpot says. The raid frames are secure, so the button is placed by
-- their position, never anchored to them: it can still show, hide and move in combat.
local function PlaceButton()
    local show = mode == "button" or H.demo
    if ghost then ghost:Hide() end
    if not show then
        if raidBtn then raidBtn:Hide() end
        return
    end
    raidBtn = raidBtn or BuildRaidButton()
    raidBtn.preview:SetShown(H.demo and mode ~= "button" or false)
    local spot = Spot()
    raidBtn:ClearAllPoints()
    local area = spot == "raidframes" and (RaidFramesArea() or (H.demo and Ghost()))
    if area then
        local scale = area:GetEffectiveScale() / UIParent:GetEffectiveScale()
        raidBtn:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", area:GetRight() * scale, area:GetBottom() * scale - 4)
    elseif spot == "minimap" and Minimap then
        raidBtn:SetPoint("TOP", Minimap, "BOTTOM", 0, -22)
    else -- "free", and "raidframes" while no raid frames are up
        local p = ns.char.raidButton
        raidBtn:SetPoint(p.point or "TOP", UIParent, p.point or "TOP", p.x or 0, p.y or -120)
    end
    FireCount(raidBtn)
    raidBtn:Show()
end

-- The setup wizard's preview of the raid button (Setup.lua).
function H:Demo(on)
    self.demo = on and true or nil
    PlaceButton()
end

-- ---------------------------------------------------------------------------
-- Choosing the look
-- ---------------------------------------------------------------------------

local function Later()
    ns:AfterCombat("FiresideHearth", function() H:Refresh() end)
end

-- The party frames fill in a moment after the roster changes (and after a loading screen): asked too
-- early, a member had no frame showing yet, the strip took over, and nothing asked again until some
-- later event, so the pins showed only sometimes. A strip for want of a frame looks again in a moment
-- (a few times), and the party frames showing or changing who they show ask too (HookFrames).
local RETRIES = { 0.5, 1.5, 4 }
local retry = 0
local function Retry()
    retry = retry + 1
    local wait = RETRIES[retry]
    if wait then C_Timer.After(wait, function() H:Refresh(true) end) end
end

local hooked = {}
local pending = false
local function Soon()
    if pending then return end
    pending = true
    C_Timer.After(0.2, function() pending = false; H:Refresh() end)
end
local function HookFrames()
    for _, c in ipairs(Candidates()) do
        local f = c[1]
        if not hooked[f] and f.HookScript then
            hooked[f] = true
            f:HookScript("OnShow", Soon)
            f:HookScript("OnHide", Soon)
            if f.SetAttribute then hooksecurefunc(f, "SetAttribute", function(_, k) if k == "unit" then Soon() end end) end
        end
    end
end

function H:Refresh(retrying)
    if not retrying then retry = 0 end
    HookFrames()
    local m
    if Wanted() then
        if IsInRaid() then
            m = "button"
        elseif ns.db.options.hearthFrames == false then
            m = "strip"
        elseif InCombatLockdown() then -- party frames can't change now: keep the look until combat ends
            Later()
            m = mode or "strip"
        else
            m = PlacePins()
            if m == "strip" then Retry() end
        end
    end
    if m ~= "pins" and PinsShown() then
        if InCombatLockdown() then Later() else HidePins() end
    end
    if m ~= "strip" and strip then strip:Hide() end
    if not m then HidePopups() end
    mode = m
    if m == "pins" then UpdatePins() elseif m == "strip" then ShowStrip() end
    PlaceButton()
end

local function ButtonFor(name)
    for _, b in ipairs(mode == "pins" and pins or buttons) do
        if b:IsShown() and b.full and C.SameName(b.full, name) then return b end
    end
end

local function MyFire()
    if mode == "pins" then return myPin and myPin:IsShown() and myPin or nil end
    if mode == "button" then return raidBtn end
    return strip and strip:IsShown() and strip.fire or nil
end

-- A spark landed (Feedback.lua): count it, light it up.
function H:OnSpark(from, to, s)
    local label = M.SparkLabel(s)
    if C.IsMe(to) then
        counts.me = (counts.me or 0) + 1
        if Active() then
            Flash(MyFire(), "+" .. label)
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
    if not (ns.db.options.prompts ~= false and Active()) then return end
    local p = Mo.FightPrompt(run, f, deaths)
    if not (p and C.InGroup(p.to)) then return end
    local full = ns.Run:FullName(run, p.to) or p.to
    ShowToast(M.SparkIconPath(p.s), p.text, { full = full, s = p.s }, TOAST_SECONDS)
end

ns:On("GROUP_ROSTER_UPDATE", function()
    if not IsInGroup() then wipe(counts) end
    H:Refresh()
    C_Timer.After(1, PlaceButton) -- the raid frames area grows once the roster settles
end)
ns:On("PLAYER_ENTERING_WORLD", function() H:Refresh() end)
ns:On("PLAYER_ROLES_ASSIGNED", function() H:Refresh() end)
ns:On("INSPECT_READY", function() if mode == "pins" then H:Refresh() end end)
ns:OnChanged(function() H:Refresh() end)
