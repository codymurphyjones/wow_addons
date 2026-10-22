local ADDON, ns = ...

--[[
The Lens: one button's shape, bloomed out of the button itself (the veil, Veil.lua, opens it).

    The core is the button. Around it, petals: each is a rule of the macro.
      * Angle is WHO it is cast on: target up, mouseover upper right, cursor lower right,
        self down, focus lower left, target's target upper left.
      * Distance from the core is ORDER: inner petals are checked first.
      * The bead arc behind a petal is its BREADTH: a catch-all wraps the whole lens, a
        "friendly, alive mouseover" is a short arc.
      * The edge colour is its TEMPERAMENT: green friend, red enemy, grey dead.
        An orange outer ring: only in combat. A blue one: only out of combat.
    The world (which modifiers are held) is chosen with your hands (Veil.lua).
    A pulse walks the petals in the order the macro checks them, and rests on the one that
    would answer right now (your real target, focus and so on).

    Verbs. None of them are buttons:
      * Point: at a petal to touch it; at open space to make room for a new one there.
      * Type: a spell or item where you point. "a, b, c" braids a cast sequence.
        "/" words change the touched petal (/combat, /reset 5 target, ...).
      * Wheel on a petal: its temperament. With the right button held: orbit it to another WHO.
      * Backspace on a petal: let it go.
      * Rest on a lone catch-all: it shows what it could grow into. Enter or click to let it.
      * Hold the core: seal (apply). Hold it with the right button: unravel (revert).
    The petal you touch never moves; when the shape changes, the lens slides around it.
]]

local L = {}
ns.Lens = L

local B = ns.Builder
local V -- ns.Veil (loaded after this file is read)

local CORE = 26          -- core radius
local R0, DR = 74, 42    -- first ring's radius, distance between rings
local PETAL = 34         -- petal size
local STEP = 15          -- braid step size
local HOLD = 0.7         -- seconds to hold the core to seal / unravel
local SPROUT = 0.65      -- seconds resting on a lone catch-all before it shows its growth
local WILT = 0.5         -- seconds away from a growing petal and its ghosts before they fold back
local HOP = 3.2          -- pulse hops per second
local REST = 2.2         -- seconds the pulse rests on its answer
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local UNITS = {
    { key = "default",      label = "target",          angle = 90 },
    { key = "mouseover",    label = "mouseover",       angle = 30 },
    { key = "cursor",       label = "cursor",          angle = 330 },
    { key = "player",       label = "self",            angle = 270 },
    { key = "focus",        label = "focus",           angle = 210 },
    { key = "targettarget", label = "target's target", angle = 150 },
}
local ANGLE, LABEL = {}, {}
for _, u in ipairs(UNITS) do ANGLE[u.key], LABEL[u.key] = u.angle, u.label end

-- Reaction and state together, in wheel order.
local TEMPERS = {
    { "any", "any" }, { "help", "any" }, { "help", "alive" }, { "harm", "any" }, { "harm", "alive" },
    { "any", "dead" }, { "help", "dead" }, { "any", "alive" }, { "harm", "dead" },
}

-- What a lone catch-all could grow into (inner petals, checked before it), by the spell's nature.
local GROWTH = {
    help = { { unit = "mouseover", reaction = "help", state = "alive" }, { reaction = "help", state = "alive" } },
    harm = { { unit = "mouseover", reaction = "harm", state = "alive" } },
    any  = { { unit = "mouseover" } },
}

local COMMANDS = {
    { "/combat",  "only in combat" },
    { "/calm",    "only out of combat" },
    { "/always",  "in or out of combat" },
    { "/reset",   "a braid starts over: /reset 5 target combat shift ctrl alt (or off)" },
    { "/tooltip", "#showtooltip on or off" },
    { "/ranks",   "offer every spell rank" },
    { "/clear",   "silence this world" },
    { "/classic", "the old editor window" },
}

-- The halo badge on a selected rule: its combat condition, in click order.
local HALOS = {
    { value = "any",      label = "any time",          color = { 0.86, 0.89, 0.94 },
      icon = "Interface\\Icons\\INV_Misc_PocketWatch_01" },
    { value = "combat",   label = "only in combat",     color = { 1, 0.55, 0.15 },
      icon = "Interface\\CharacterFrame\\UI-StateIcon", coords = { 0.5, 1, 0, 0.49 } },
    { value = "nocombat", label = "only out of combat", color = { 0.35, 0.65, 1 },
      icon = "Interface\\Icons\\Spell_Nature_Sleep" },
}
local function HaloOf(value)
    for i, h in ipairs(HALOS) do
        if h.value == value then return h, HALOS[i % #HALOS + 1] end
    end
    return HALOS[1], HALOS[2]
end

local COLOR = {
    help = { 0.35, 1, 0.55 },
    harm = { 1, 0.35, 0.3 },
    combat = { 1, 0.55, 0.15 },
    nocombat = { 0.35, 0.65, 1 },
}

---------------------------------------------------------------------------
-- Geometry and words
---------------------------------------------------------------------------

local function Polar(r, deg)
    local a = math.rad(deg)
    return r * math.cos(a), r * math.sin(a)
end

local function RingR(k) return R0 + (k - 1) * DR end

local function Dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

-- Degrees of arc a rule covers.
local function Breadth(rule)
    if B:IsUnconditional(rule) then return 360 end
    local span = 56
    if rule.reaction ~= "any" then span = span * 0.6 end
    if rule.state == "dead" then span = span * 0.5 elseif rule.state == "alive" then span = span * 0.78 end
    if rule.combat ~= "any" then span = span * 0.6 end
    return math.max(span, 12)
end

local function Tag(rule)
    if B:IsUnconditional(rule) then return "anyone" end
    local parts = { LABEL[rule.unit] or rule.unit }
    if rule.reaction == "help" then parts[#parts + 1] = "friend" elseif rule.reaction == "harm" then parts[#parts + 1] = "enemy" end
    if rule.state == "alive" then parts[#parts + 1] = "alive" elseif rule.state == "dead" then parts[#parts + 1] = "dead" end
    if rule.combat == "combat" then parts[#parts + 1] = "in combat" elseif rule.combat == "nocombat" then parts[#parts + 1] = "out of combat" end
    return table.concat(parts, " · ")
end

local function Ordinal(n)
    local last, tens = n % 10, math.floor(n / 10) % 10
    if tens ~= 1 and last == 1 then return n .. "st" end
    if tens ~= 1 and last == 2 then return n .. "nd" end
    if tens ~= 1 and last == 3 then return n .. "rd" end
    return n .. "th"
end

local function WorldName(key)
    if key == "none" then return "no modifier" end
    local label = B:ModLabel(key):gsub("S%+C%+A", "Shift+Ctrl+Alt"):lower():gsub("%+", " + ")
    return label
end

local function ActionIcon(a)
    if not a or not a.kind then return end
    if a.kind == "spell" then
        local _, icon = ns.SpellInfo(a.id or a.name)
        return icon or QUESTION
    elseif a.kind == "item" then
        return ns.ItemIcon(a.id) or QUESTION
    end
end

local function ActionName(a)
    local name = a.name or B:ActionToken(a)
    if a.rank then name = name .. " (" .. a.rank .. ")" end
    return name
end

local function Braided(rule) return rule.steps ~= nil and #rule.steps > 1 end

local function Conflict(rules, candidate, ignore)
    for _, rule in ipairs(rules) do
        if rule ~= ignore and rule ~= candidate and B:Conflicts(rule, candidate, false) then return rule end
    end
end

-- Is the spell for friends, foes or neither?
local function Nature(rule)
    if rule.kind ~= "spell" then return "any" end
    local helpful, harmful
    if C_Spell and C_Spell.IsSpellHelpful and rule.id then
        local ok1, h = pcall(C_Spell.IsSpellHelpful, rule.id)
        local ok2, x = pcall(C_Spell.IsSpellHarmful, rule.id)
        helpful, harmful = ok1 and h, ok2 and x
    elseif IsHelpfulSpell and rule.name then
        helpful, harmful = IsHelpfulSpell(rule.name), IsHarmfulSpell(rule.name)
    end
    if ns.IsSecret(helpful) or ns.IsSecret(harmful) then return "any" end
    if helpful then return "help" end
    if harmful then return "harm" end
    return "any"
end

L.WHO = {
    default = "your target", mouseover = "your mouseover", focus = "your focus", player = "yourself",
    targettarget = "your target's target", cursor = "the ground at your cursor",
}

-- One rule as a sentence: "Healing Touch on your mouseover, if friendly and alive".
function L.Describe(rule)
    local what
    if Braided(rule) then
        local names = {}
        for _, s in ipairs(rule.steps) do names[#names + 1] = ActionName(s) end
        what = table.concat(names, " > ") .. " (one per press)"
    elseif B:RuleHasAction(rule) then
        what = ActionName(rule)
    else
        what = "(no spell yet)"
    end
    local who = L.WHO[rule.unit] or rule.unit
    if B:IsUnconditional(rule) then return ("Otherwise: %s on %s"):format(what, who) end
    local ifs = {}
    if rule.reaction == "help" then ifs[#ifs + 1] = "friendly" elseif rule.reaction == "harm" then ifs[#ifs + 1] = "hostile" end
    if rule.state == "alive" then ifs[#ifs + 1] = "alive" elseif rule.state == "dead" then ifs[#ifs + 1] = "dead" end
    local cond
    if #ifs > 0 then
        cond = "if " .. table.concat(ifs, " and ")
    elseif rule.unit == "mouseover" or rule.unit == "focus" or rule.unit == "targettarget" then
        cond = "if there is one"
    end
    if rule.combat == "combat" then
        cond = (cond and cond .. ", " or "") .. "only in combat"
    elseif rule.combat == "nocombat" then
        cond = (cond and cond .. ", " or "") .. "only out of combat"
    end
    return ("%s on %s%s"):format(what, who, cond and (", " .. cond) or "")
end

L.ActionName, L.ActionIcon, L.WorldName, L.Braided = ActionName, ActionIcon, WorldName, Braided

---------------------------------------------------------------------------
-- The live situation: would this rule answer right now?
-- true, false, or "maybe" (mouseover: whatever is under the mouse when you press).
---------------------------------------------------------------------------

local function Truth(v)
    if ns.IsSecret(v) then return nil end
    return v and true or false
end

function L:Match(rule)
    local fighting = InCombatLockdown()
    if rule.combat == "combat" and not fighting then return false end
    if rule.combat == "nocombat" and fighting then return false end
    if B:IsUnconditional(rule) then return true end
    local unit = rule.unit == "default" and "target" or rule.unit
    if unit == "cursor" then return true end
    if unit == "mouseover" then return "maybe" end
    local exists = unit == "player" or Truth(UnitExists(unit))
    if exists == nil then return "maybe" end
    if not exists then
        -- [help]/[harm] need a unit; a bare [nodead] on your target passes without one.
        if rule.unit ~= "default" then return false end
        return rule.reaction == "any" and rule.state ~= "dead"
    end
    if rule.reaction ~= "any" then
        local v
        if rule.reaction == "help" then
            v = Truth(UnitCanAssist("player", unit))
        else
            v = Truth(UnitCanAttack("player", unit))
        end
        if v == nil then return "maybe" end
        if not v then return false end
    end
    if rule.state ~= "any" then
        local dead = Truth(UnitIsDeadOrGhost(unit))
        if dead == nil then return "maybe" end
        if dead ~= (rule.state == "dead") then return false end
    end
    return true
end

-- The icon a design shows in `world` right now (nil: none of its petals answer).
function L:VoiceIcon(design, world)
    for _, rule in ipairs(design.rules or {}) do
        if rule.mod == world and B:RuleHasAction(rule) and self:Match(rule) == true then
            return ActionIcon(rule)
        end
    end
end

---------------------------------------------------------------------------
-- Drafts
---------------------------------------------------------------------------

-- Old cast sequence designs may hold several rows with one context; here a context is one
-- petal, so they become one braid (the same macro: such rows always chained in row order).
local function MergeContexts(design)
    local out = {}
    for _, rule in ipairs(design.rules) do
        local home
        for _, o in ipairs(out) do
            if B:SameConditions(o, rule) then home = o end
        end
        if home then
            B:EnsureSteps(home)
            B:EnsureSteps(rule)
            for _, step in ipairs(rule.steps) do
                if #home.steps < B.MAX_STEPS then table.insert(home.steps, step) end
            end
            B:SyncFromSteps(home)
        else
            out[#out + 1] = rule
        end
    end
    design.rules = out
end

local function AnyBraid(design)
    for _, rule in ipairs(design.rules) do
        if Braided(rule) then return true end
    end
end

function L:Load(slot)
    local saved = ns.db.designs[slot]
    local draft
    if saved then
        draft = B:Migrate(ns.DeepCopy(saved))
        MergeContexts(draft)
        draft.sequence = nil
        B:Sanitize(draft)
    else
        draft = ns.Editor:NewDesignFromSlot(slot)
    end
    draft.sequence = AnyBraid(draft) or nil
    return draft
end

function L:WorldRules()
    local world, list = V:World(), {}
    for _, rule in ipairs(self.draft.rules) do
        if rule.mod == world then list[#list + 1] = rule end
    end
    return list
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

local function Tex(parent, layer, name, size)
    local t = parent:CreateTexture(nil, layer)
    t:SetTexture(V.TEX .. name)
    if size then t:SetSize(size, size) end
    t:SetPoint("CENTER")
    return t
end

function L:Create(veil)
    V = ns.Veil
    local f = CreateFrame("Frame", nil, veil)
    f.modifiedOwn = true
    f:SetSize(1, 1)
    f:SetFrameLevel(veil:GetFrameLevel() + 10)
    f:Hide()
    self.frame = f

    f.bloom = f:CreateAnimationGroup()
    local a = f.bloom:CreateAnimation("Alpha")
    a:SetFromAlpha(0)
    a:SetToAlpha(1)
    a:SetDuration(0.3)
    a:SetSmoothing("OUT")

    -- Shapes drawn straight on the lens: beads, the pulse, the cube, the compass.
    self.aura = Tex(f, "BACKGROUND", "Glow", 190)
    self.beads, self.sealBeads = {}, {}
    self.core = V.Masked(f, "ARTWORK")
    self.core:SetSize(CORE * 2, CORE * 2)
    self.core:SetPoint("CENTER")
    self.coreRing = Tex(f, "OVERLAY", "Ring", CORE * 2 + 14)
    -- The answering rule's halo on the core: an outer ring and its small combat icon.
    self.coreMood = Tex(f, "OVERLAY", "Ring", CORE * 2 + 26)
    self.coreMood:Hide()
    local coreMini = CreateFrame("Frame", nil, f)
    coreMini:SetSize(18, 18)
    coreMini:SetPoint("CENTER", f, "CENTER", -12, -12) -- 17 px out, radius 9: inside the 26 px core
    coreMini:SetFrameLevel(f:GetFrameLevel() + 2)
    coreMini.back = Tex(coreMini, "BACKGROUND", "Disc", 18)
    coreMini.back:SetVertexColor(0.04, 0.05, 0.08)
    coreMini.icon = V.Masked(coreMini, "ARTWORK")
    coreMini.icon:SetSize(13, 13)
    coreMini.icon:SetPoint("CENTER")
    coreMini.ring = Tex(coreMini, "OVERLAY", "Ring", 18)
    coreMini:Hide()
    self.coreMini = coreMini
    -- The answering rule's number, like the badge on each rule.
    local coreNum = CreateFrame("Frame", nil, f)
    coreNum:SetSize(22, 22)
    coreNum:SetPoint("CENTER", f, "CENTER", -CORE * 0.72, CORE * 0.72)
    coreNum:SetFrameLevel(f:GetFrameLevel() + 2)
    coreNum.back = Tex(coreNum, "BACKGROUND", "Disc", 22)
    coreNum.back:SetVertexColor(0.05, 0.06, 0.09)
    coreNum.ring = Tex(coreNum, "BORDER", "Ring", 24)
    coreNum.ring:SetVertexColor(1, 0.85, 0.3)
    coreNum.text = coreNum:CreateFontString(nil, "OVERLAY", "ModifiedNumberFontNormal")
    coreNum.text:SetPoint("CENTER", 0, 0)
    coreNum:Hide()
    self.coreNum = coreNum

    -- Petals are frames, so they draw above the beads.
    self.petals, self.spare = {}, {}

    local top = CreateFrame("Frame", nil, f)
    top:SetAllPoints()
    top:SetFrameLevel(f:GetFrameLevel() + 20)
    self.top = top
    self.pulseGlow = Tex(top, "ARTWORK", "Glow", 26)
    self.pulseDot = Tex(top, "OVERLAY", "Dot", 9)
    self.ghost = Tex(top, "ARTWORK", "Ring", 30)
    self.ghost:SetAlpha(0)
    -- The selected spot (a click selects; typing, the wheel and Backspace act on it).
    self.pinRing = Tex(top, "OVERLAY", "Ring", PETAL * 1.9)
    self.pinRing:SetVertexColor(1, 0.85, 0.3)
    self.pinRing:SetAlpha(0)

    -- The halo (combat condition) of the selected rule: a badge at its bottom-left showing the
    -- current value; a click steps to the next.
    local badge = CreateFrame("Frame", nil, top)
    badge:SetSize(20, 20)
    badge:SetFrameLevel(top:GetFrameLevel() + 5)
    badge.back = Tex(badge, "BACKGROUND", "Disc", 22)
    badge.back:SetVertexColor(0.04, 0.05, 0.08)
    badge.icon = V.Masked(badge, "ARTWORK")
    badge.icon:SetSize(16, 16)
    badge.icon:SetPoint("CENTER")
    badge.ring = Tex(badge, "OVERLAY", "Ring", 26)
    badge:Hide()
    self.badge = badge
    self.haloChips = { badge }

    -- The order of the selected rule: Earlier above it, Later below it.
    self.orderChips = {}
    for i, o in ipairs({ { delta = -1, label = "Earlier" }, { delta = 1, label = "Later" } }) do
        local c = CreateFrame("Frame", nil, top)
        c:SetSize(52, 16)
        c:SetFrameLevel(top:GetFrameLevel() + 5)
        c.delta = o.delta
        c.bg = c:CreateTexture(nil, "BACKGROUND")
        c.bg:SetAllPoints()
        c.label = c:CreateFontString(nil, "OVERLAY", "ModifiedGameFontHighlightSmall")
        c.label:SetPoint("CENTER")
        c.label:SetText(o.label)
        c:Hide()
        self.orderChips[i] = c
    end
    self.cube = {}
    for bits = 0, 7 do self.cube[bits] = Tex(top, "OVERLAY", "Dot", 8) end
    self.worldName = top:CreateFontString(nil, "OVERLAY", "ModifiedGameFontNormal")
    self.compass = {}
    for i, u in ipairs(UNITS) do
        local fs = top:CreateFontString(nil, "OVERLAY", "ModifiedGameFontHighlightSmall")
        fs:SetText(u.label:upper())
        fs:SetAlpha(0)
        self.compass[i] = fs
    end
    self.incant = top:CreateFontString(nil, "OVERLAY", "ModifiedGameFontHighlightSmall")
    self.incant:SetJustifyH("LEFT")
    self.incant:SetTextColor(0.75, 0.9, 1)

    -- The lens listens: an invisible edit box holds the keyboard while it is open.
    local eb = CreateFrame("EditBox", nil, f)
    eb:SetFontObject("ModifiedGameFontHighlightSmall")
    eb:SetSize(1, 1)
    eb:SetPoint("CENTER")
    eb:SetAlpha(0)
    eb:SetAutoFocus(false)
    eb:EnableMouse(false)
    eb:SetScript("OnTextChanged", function(box)
        L.text = box:GetText() or ""
        L.pick = 1
        -- The world holds still while you type (Veil.lua's V:World).
        if L.text == "" then
            L.frozen = nil
        elseif not L.frozen then
            L.frozen = V:World()
        end
    end)
    eb:SetScript("OnChar", function() V.touched = true end)
    eb:SetScript("OnEnterPressed", function() L:Commit() end)
    eb:SetScript("OnTabPressed", function() L:Tab() end)
    eb:SetScript("OnEscapePressed", function(box)
        if (box:GetText() or "") ~= "" then
            box:SetText("")
        elseif L.pin then
            L.pin = nil
        else
            L:Dissolve()
        end
    end)
    eb:SetScript("OnKeyDown", function(box, key)
        V.touched = true
        if (key == "BACKSPACE" or key == "DELETE") and (box:GetText() or "") == "" then L:LetGo() end
        if (key == "UP" or key == "DOWN") and (box:GetText() or "") == "" and L.hover then
            L:MoveOrder(L.hover, key == "UP" and -1 or 1)
        end
    end)
    self.eb = eb
    self.text = ""
end

function L:IsOpen() return self.slot ~= nil and self.frame ~= nil and self.frame:IsShown() end
function L:IsSpeaking() return self:IsOpen() and (self.text or "") ~= "" end

function L:Bloom(slot, reflection)
    V = ns.Veil
    if self:IsOpen() then self:Dissolve() end
    ns.Voice:Refresh()
    self.slot = slot
    self.draft = V.drafts[slot] or self:Load(slot)
    V.drafts[slot] = self.draft
    self.pick, self.sprout, self.props = 1, false, nil
    self.hover, self.prop, self.ghostAt, self.onCore, self.hold, self.orbiting = nil, nil, nil, nil, nil, nil
    self.away, self.sproutWait = 0, 0
    -- The lens opens in the middle of the desk's lens area (Veil.lua's PlaceDesk), and Place
    -- keeps it there, shrinking it when a big shape wouldn't fit.
    self.floor = (V.deskBottom or 0) + 8
    local top = V.frame:GetHeight() - (V.safeTop or 30)
    self.cx = ((V.safeLeft or 0) + (V.safeRight or V.frame:GetWidth())) / 2
    self.cy = (self.floor + top) / 2
    self.frame:Show()
    self.frame.bloom:Play()
    self.eb:SetText("")
    self.text = ""
    self.eb:SetFocus()
    self:Layout()
    self:RestartPulse()
end

function L:Dissolve()
    if not self.frame then return end
    self.slot = nil
    self.hold = nil
    self.frozen = nil
    self.lock = nil
    self.pin = nil
    self.frame:Hide()
    self.eb:SetText("")
    self.eb:ClearFocus()
    for rule in pairs(self.petals) do self:FreePetal(rule) end
    self.layout = {}
    if V and V.IsOpen and V:IsOpen() then
        V:Whisper(nil)
        V:Paint()
    end
end

function L:WorldChanged()
    if not self:IsOpen() then return end
    self.sprout, self.props = false, nil
    self:Layout()
    self:RestartPulse()
end

---------------------------------------------------------------------------
-- Layout: where everything goes
---------------------------------------------------------------------------

-- Remember where `rule` sits, so the next layout slides the lens to keep it there.
function L:Hold(rule, x, y)
    if not x then
        for _, p in ipairs(self.layout or {}) do
            if p.rule == rule then x, y = p.x, p.y end
        end
    end
    if x then self.anchor = { rule = rule, x = x, y = y } end
end

-- Moves the lens by (dx, dy) lens units; petals keep their place on screen and drift to their
-- new spots. self.cx/cy are in the veil's units, the rest of the lens in its own (self.scale).
function L:Slide(dx, dy)
    if dx == 0 and dy == 0 then return end
    local s = self.scale or 1
    self.cx, self.cy = self.cx + dx * s, self.cy + dy * s
    for _, w in pairs(self.petals) do
        w.cx, w.cy = w.cx - dx, w.cy - dy
    end
end

-- Keeps the lens between the guide panels, below the modifier strip and above its button,
-- shrinking it when a big shape wouldn't fit.
function L:Place()
    local veil = V.frame
    local w, h = veil:GetWidth(), veil:GetHeight()
    local left, right = V.safeLeft or 0, V.safeRight or w
    if right - left < 300 then left, right = 0, w end
    local top = h - (V.safeTop or 30)
    local floor = self.floor or 0
    local needW, needH = 2 * (self.outer + 60), 2 * (self.outer + 72)
    local s = math.max(0.55, math.min(1, (right - left) / needW, (top - floor) / needH))
    if s ~= self.scale then
        self.scale = s
        self.frame:SetScale(s)
    end
    local mx, my = (self.outer + 60) * s, (self.outer + 72) * s
    local lo, hi = left + mx, right - mx
    local x = lo > hi and (lo + hi) / 2 or math.max(lo, math.min(hi, self.cx))
    local low, high = floor + (self.outer + 44) * s, top - my
    local y = low > high and low or math.max(low, math.min(high, self.cy))
    self:Slide((x - self.cx) / s, (y - self.cy) / s)
    self.frame:SetPoint("CENTER", veil, "BOTTOMLEFT", self.cx / s, self.cy / s)
end

function L:Layout()
    if not self.slot then return end
    local draft = self.draft
    B:Normalize(draft.rules)
    local list = {}
    for _, rule in ipairs(self.sprout and self.props or {}) do list[#list + 1] = { rule = rule, growth = true } end
    for _, rule in ipairs(self:WorldRules()) do list[#list + 1] = { rule = rule } end
    local order = 0
    for k, p in ipairs(list) do
        if not p.growth then
            order = order + 1
            p.order = order
        end
        p.k = k
        p.r = RingR(k)
        p.angle = ANGLE[p.rule.unit] or 90
        p.x, p.y = Polar(p.r, p.angle)
    end
    self.layout = list
    self.outer = RingR(math.max(#list, 1))

    local anchor = self.anchor
    self.anchor = nil
    if anchor then
        -- Until the cursor moves, it still touches this petal, even if the screen's edge
        -- nudged the lens a little.
        local x, y = V:Cursor()
        self.lock = { rule = anchor.rule, x = x, y = y }
        for _, p in ipairs(list) do
            if p.rule == anchor.rule then
                self:Slide(anchor.x - p.x, anchor.y - p.y)
                local w = self.petals[p.rule]
                if not w then -- newborn: born under the cursor
                    w = self:Petal(p.rule)
                    w.cx, w.cy = p.x, p.y
                end
            end
        end
    end
    self:Place()
    self:Paint()
end

---------------------------------------------------------------------------
-- Painting
---------------------------------------------------------------------------

function L:Petal(rule)
    local w = self.petals[rule]
    if w then return w end
    w = table.remove(self.spare)
    if not w then
        w = CreateFrame("Frame", nil, self.frame)
        w:SetSize(PETAL, PETAL)
        w.glow = Tex(w, "BACKGROUND", "Glow", PETAL * 2.4)
        w.disc = Tex(w, "BORDER", "Disc", PETAL)
        w.icon = V.Masked(w, "ARTWORK")
        w.icon:SetSize(PETAL - 4, PETAL - 4)
        w.icon:SetPoint("CENTER")
        w.edge = Tex(w, "OVERLAY", "Ring", PETAL * 1.3)
        -- The halo when the rule isn't selected: a small round icon at its bottom-left, wholly
        -- inside the rule's circle (none for "any time"). Selected, the bigger badge takes over.
        local mini = CreateFrame("Frame", nil, w)
        -- Centre 7 px from the rule's, radius 7: it ends inside the 15 px spell icon.
        mini:SetSize(14, 14)
        mini:SetPoint("CENTER", w, "CENTER", -5, -5)
        mini.back = Tex(mini, "BACKGROUND", "Disc", 14)
        mini.back:SetVertexColor(0.04, 0.05, 0.08)
        mini.icon = V.Masked(mini, "ARTWORK")
        mini.icon:SetSize(10, 10)
        mini.icon:SetPoint("CENTER")
        mini.ring = Tex(mini, "OVERLAY", "Ring", 14)
        mini:Hide()
        w.mini = mini
        w.mood = Tex(w, "OVERLAY", "Ring", PETAL * 1.62)
        w.mark = w:CreateFontString(nil, "OVERLAY", "ModifiedGameFontNormalLarge")
        w.mark:SetPoint("CENTER")
        w.tag = w:CreateFontString(nil, "OVERLAY", "ModifiedGameFontHighlightSmall")
        w.tag:SetTextColor(0.7, 0.78, 0.88)
        w.name = w:CreateFontString(nil, "OVERLAY", "ModifiedGameFontHighlightSmall")
        w.name:SetWordWrap(false)
        w.badge = Tex(w, "OVERLAY", "Disc", 17)
        w.badge:ClearAllPoints()
        w.badge:SetPoint("CENTER", w, "TOPLEFT", 3, -3)
        w.badge:SetVertexColor(0.05, 0.06, 0.09)
        w.num = w:CreateFontString(nil, "OVERLAY", "ModifiedNumberFontNormalSmall")
        w.num:SetPoint("CENTER", w.badge, "CENTER", 0, 0)
        w.steps = {}
    end
    w:SetFrameLevel(self.frame:GetFrameLevel() + 3)
    w.cx, w.cy = 0, 0 -- grows out of the core
    w:Show()
    self.petals[rule] = w
    return w
end

function L:FreePetal(rule)
    local w = self.petals[rule]
    if not w then return end
    self.petals[rule] = nil
    w:Hide()
    self.spare[#self.spare + 1] = w
end

local function Bead(pool, parent, i)
    local b = pool[i]
    if not b then
        b = parent:CreateTexture(nil, "BORDER")
        b:SetTexture(V.TEX .. "Dot")
        pool[i] = b
    end
    b:Show()
    return b
end

function L:PaintPetal(p, color)
    local rule, w = p.rule, self:Petal(p.rule)
    w.tx, w.ty = p.x, p.y
    w.growth = p.growth
    local has = B:RuleHasAction(rule)
    w.icon:SetTexture(has and ActionIcon(rule) or nil)
    w.icon:SetDesaturated(rule.state == "dead")
    w.disc:SetVertexColor(0, 0, 0)
    w.disc:SetAlpha(has and 0.7 or 0.35)
    w.mark:SetText(has and "" or "?")
    local edge = COLOR[rule.reaction] or color
    if rule.state == "dead" then edge = { 0.6, 0.6, 0.6 } end
    w.edge:SetVertexColor(edge[1], edge[2], edge[3])
    local halo = HaloOf(rule.combat)
    w.haloOn = rule.combat ~= "any" and not p.growth
    if w.haloOn then
        w.mini.icon:SetTexture(halo.icon)
        if halo.coords then w.mini.icon:SetTexCoord(unpack(halo.coords)) else w.mini.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
        w.mini.ring:SetVertexColor(halo.color[1], halo.color[2], halo.color[3])
    end
    w.mini:SetShown(w.haloOn and not (self.pin and self.pin.rule == rule))
    local mood = COLOR[rule.combat]
    w.mood:SetShown(mood ~= nil)
    if mood then w.mood:SetVertexColor(mood[1], mood[2], mood[3]) end
    w:SetAlpha(p.growth and 0.45 or 1)
    w.num:SetText(p.growth and "+" or p.order or "")
    w.badge:SetShown(p.growth or p.order ~= nil)
    -- Its name beside it: to the right on the right half and straight up or down, else to the left.
    local steps = Braided(rule) and rule.steps or {}
    local left = p.angle > 100 and p.angle < 260
    local gap = PETAL / 2 + 5 + ((not left and p.angle >= 80 and p.angle <= 100) and math.max(#steps - 1, 0) * (STEP + 2) or 0)
    w.name:ClearAllPoints()
    w.tag:ClearAllPoints()
    if left then
        w.name:SetPoint("RIGHT", w, "CENTER", -gap, 4)
        w.name:SetJustifyH("RIGHT")
        w.tag:SetPoint("TOPRIGHT", w.name, "BOTTOMRIGHT", 0, -1)
        w.tag:SetJustifyH("RIGHT")
    else
        w.name:SetPoint("LEFT", w, "CENTER", gap, 4)
        w.name:SetJustifyH("LEFT")
        w.tag:SetPoint("TOPLEFT", w.name, "BOTTOMLEFT", 0, -1)
        w.tag:SetJustifyH("LEFT")
    end
    local label
    if Braided(rule) then
        label = ActionName(steps[1]) .. " +" .. (#steps - 1)
    elseif has then
        label = ActionName(rule)
    else
        label = "|cff8090a0(no spell)|r"
    end
    w.name:SetText(label)
    -- Braid: the later steps trail clockwise along the ring.
    local tx, ty = math.sin(math.rad(p.angle)), -math.cos(math.rad(p.angle))
    for i = 2, math.max(#steps, #w.steps + 1) do
        local s = w.steps[i]
        if steps[i] then
            if not s then
                s = V.Masked(w, "ARTWORK")
                s:SetSize(STEP, STEP)
                w.steps[i] = s
            end
            local d = PETAL / 2 + 4 + (i - 1.5) * (STEP + 2)
            s:ClearAllPoints()
            s:SetPoint("CENTER", w, "CENTER", tx * d, ty * d)
            s:SetTexture(ActionIcon(steps[i]))
            s:Show()
        elseif s then
            s:Hide()
        end
    end
end

function L:PaintTags()
    for _, p in ipairs(self.layout or {}) do
        local w = self.petals[p.rule]
        if w then
            -- Conditions under the name for the touched petal, the pulse's answer and suggestions.
            local show = p.rule == self.lit or p.growth or p.rule == self.hover
            w.tag:SetText(show and Tag(p.rule) or "")
        end
    end
end

function L:Paint()
    local world = V:World()
    local color = V.WorldColor(world)
    local live = {}
    for _, p in ipairs(self.layout) do
        live[p.rule] = true
        self:PaintPetal(p, color)
    end
    for rule in pairs(self.petals) do
        if not live[rule] then self:FreePetal(rule) end
    end
    self:PaintTags()

    -- Bead arcs: how much of the world each petal catches.
    local n = 0
    for _, p in ipairs(self.layout) do
        local span = Breadth(p.rule)
        local count = math.max(3, math.floor(span * p.r * math.pi / 180 / 10))
        for j = 0, count - 1 do
            local t = span >= 360 and j / count or j / (count - 1)
            local x, y = Polar(p.r, p.angle - span / 2 + span * t)
            n = n + 1
            local b = Bead(self.beads, self.frame, n)
            b:SetSize(5, 5)
            b:SetPoint("CENTER", self.frame, "CENTER", x, y)
            b:SetVertexColor(color[1], color[2], color[3])
            b:SetAlpha(p.growth and 0.18 or 0.5)
        end
    end
    -- The breath of the macro: 40 beads round the core fill up to the 255-byte limit.
    local text, length = B:Build(self.draft)
    self.length = length
    local over = length > B.MAX_LENGTH
    local lit = math.ceil(math.min(length / B.MAX_LENGTH, 1) * 40)
    for j = 0, 39 do
        local x, y = Polar(CORE + 9, 90 - j * 9)
        n = n + 1
        local b = Bead(self.beads, self.frame, n)
        b:SetSize(4, 4)
        b:SetPoint("CENTER", self.frame, "CENTER", x, y)
        if over then b:SetVertexColor(1, 0.3, 0.3) else b:SetVertexColor(1, 1, 1) end
        b:SetAlpha(j < lit and 0.9 or 0.12)
    end
    for i = n + 1, #self.beads do self.beads[i]:Hide() end

    -- The core follows the live situation every frame (Animate's PaintCore).
    self.coreKey = nil
    self.aura:SetVertexColor(color[1], color[2], color[3])
    self.aura:SetAlpha(0.35)

    -- The cube of worlds and this world's name, above the outermost ring.
    local cubeY = self.outer + 80
    local CUBE = { [0] = { -16, -10 }, { 4, -16 }, { -4, 2 }, { 16, -4 }, { -16, 10 }, { 4, 4 }, { -4, 22 }, { 16, 16 } }
    for bits = 0, 7 do
        local d = self.cube[bits]
        local key = V.WORLD[bits]
        local used = false
        for _, rule in ipairs(self.draft.rules) do
            if rule.mod == key and B:RuleHasAction(rule) then used = true end
        end
        local c = V.WorldColor(key)
        d:SetPoint("CENTER", self.top, "CENTER", CUBE[bits][1], cubeY + CUBE[bits][2])
        d:SetVertexColor(c[1], c[2], c[3])
        local here = key == world
        d:SetSize(here and 13 or 8, here and 13 or 8)
        d:SetAlpha(here and 1 or used and 0.75 or 0.18)
    end
    local name = WorldName(world)
    if V.latched ~= 0 then name = name .. "  ·  locked (tap again to unlock)" end
    self.worldName:SetText("SET:  " .. name:upper())
    self.worldName:SetTextColor(color[1], color[2], color[3])
    self.worldName:SetPoint("CENTER", self.top, "CENTER", 0, self.outer + 52)

    for i, u in ipairs(UNITS) do
        local x, y = Polar(self.outer + 30, u.angle)
        self.compass[i]:SetPoint("CENTER", self.top, "CENTER", x, y)
    end
    self.incant:Hide()
    self.macro = length > 0 and text or nil
end

---------------------------------------------------------------------------
-- Motion: petals drift, the pulse walks, the seal fills
---------------------------------------------------------------------------

-- The core is the button as it would be right now: the answering rule's spell, its ring
-- (friendly, hostile, dead) and its halo (combat), or a greyed button when nothing answers.
-- It follows your target, focus and modifier keys as they change, before anything is saved.
function L:PaintCore(rule)
    local order = rule and self:OrderOf(rule)
    local key = rule and (tostring(rule) .. (rule.name or "") .. rule.reaction .. rule.state .. rule.combat .. (order or "")) or "none"
    key = key .. V:World()
    if key == self.coreKey then return end
    self.coreKey = key
    local world = V.WorldColor(V:World())
    if not rule then
        self.core:SetTexture(GetActionTexture(self.slot) or QUESTION)
        self.core:SetDesaturated(true)
        self.core:SetAlpha(0.35)
        self.coreRing:SetVertexColor(0.5, 0.5, 0.5)
        self.coreMood:Hide()
        self.coreMini:Hide()
        self.coreNum:Hide()
        return
    end
    self.coreNum.text:SetText(order or "")
    self.coreNum:SetShown(order ~= nil)
    self.core:SetTexture(ActionIcon(rule) or QUESTION)
    self.core:SetDesaturated(rule.state == "dead")
    self.core:SetAlpha(1)
    local edge = COLOR[rule.reaction] or world
    if rule.state == "dead" then edge = { 0.6, 0.6, 0.6 } end
    self.coreRing:SetVertexColor(edge[1], edge[2], edge[3])
    local mood = COLOR[rule.combat]
    self.coreMood:SetShown(mood ~= nil)
    if mood then self.coreMood:SetVertexColor(mood[1], mood[2], mood[3]) end
    local halo = HaloOf(rule.combat)
    if rule.combat ~= "any" then
        self.coreMini.icon:SetTexture(halo.icon)
        if halo.coords then self.coreMini.icon:SetTexCoord(unpack(halo.coords)) else self.coreMini.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
        self.coreMini.ring:SetVertexColor(halo.color[1], halo.color[2], halo.color[3])
        self.coreMini:Show()
    else
        self.coreMini:Hide()
    end
end

function L:RestartPulse()
    self.pulseT = 0
    self.lit = nil
end

function L:Animate(elapsed)
    local k = math.min(1, elapsed * 11)
    for _, w in pairs(self.petals) do
        if w.tx then
            w.cx = w.cx + (w.tx - w.cx) * k
            w.cy = w.cy + (w.ty - w.cy) * k
        end
        w:SetPoint("CENTER", self.frame, "CENTER", w.cx, w.cy)
    end

    -- The pulse: core, then each petal in macro order, resting on the one that answers.
    local path = { { x = 0, y = 0 } }
    local hit, maybes = nil, {}
    for _, p in ipairs(self.layout) do
        if not p.growth and B:RuleHasAction(p.rule) then
            local w = self.petals[p.rule]
            path[#path + 1] = { x = w.cx, y = w.cy, rule = p.rule }
            local m = self:Match(p.rule)
            if m == "maybe" then maybes[#path - 1] = true end
            if m == true and not hit then hit = #path - 1 end
        end
    end
    local hops = #path - 1
    local goal = hit or hops
    self.pulseT = (self.pulseT or 0) + elapsed * HOP
    local pos = math.min(self.pulseT, goal)
    local i = math.floor(pos)
    local a, b = path[i + 1], path[math.min(i + 2, #path)]
    local f = pos - i
    local x, y = a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f
    self.pulseGlow:SetPoint("CENTER", self.top, "CENTER", x, y)
    self.pulseDot:SetPoint("CENTER", self.top, "CENTER", x, y)
    local resting = self.pulseT >= goal
    local fade = (hops == 0 or (resting and not hit)) and 0.2 or 1
    self.pulseGlow:SetAlpha(fade)
    self.pulseDot:SetAlpha(fade)
    self:PaintCore(hit and path[hit + 1].rule or nil)
    local litRule = resting and hit and path[hit + 1].rule or nil
    if litRule ~= self.lit then
        self.lit = litRule
        self:PaintTags()
    end
    for idx = 1, hops do
        local w = self.petals[path[idx + 1].rule]
        local glow = 0
        if path[idx + 1].rule == litRule then
            glow = 0.9
        elseif maybes[idx] and math.abs(self.pulseT - idx) < 0.45 then
            glow = 0.4 -- a fork: it would answer if something were under the mouse
        end
        w.glow:SetAlpha(glow)
        local c = V.WorldColor(V:World())
        w.glow:SetVertexColor(c[1], c[2], c[3])
    end
    if self.pulseT > goal + REST * HOP then self.pulseT = 0 end

    -- The seal: beads round the core light up while it is held.
    local progress = self.hold and math.min((GetTime() - self.hold.at) / HOLD, 1) or 0
    for j = 1, 24 do
        local s = Bead(self.sealBeads, self.top, j)
        local bx, by = Polar(CORE + 18, 90 - (j - 1) * 15)
        s:SetSize(6, 6)
        s:SetPoint("CENTER", self.top, "CENTER", bx, by)
        if self.hold and self.hold.button == "RightButton" then s:SetVertexColor(1, 0.35, 0.3) else s:SetVertexColor(1, 0.85, 0.4) end
        s:SetAlpha(progress > 0 and (j / 24 <= progress and 1 or 0.15) or 0)
    end
end

---------------------------------------------------------------------------
-- Pointing (every frame, from the veil)
---------------------------------------------------------------------------

function L:CanSprout(rule)
    local rules = self:WorldRules()
    if #rules ~= 1 or rules[1] ~= rule or not B:IsUnconditional(rule) or not B:RuleHasAction(rule) then return false end
    return true
end

function L:Growth()
    local seed = self:WorldRules()[1]
    local out = {}
    for _, fields in ipairs(GROWTH[Nature(seed)]) do
        local rule = B:NewRule(fields)
        rule.mod = seed.mod
        rule.kind, rule.id, rule.name, rule.rank = seed.kind, seed.id, seed.name, seed.rank
        if not Conflict(self.draft.rules, rule) and not Conflict(out, rule) then out[#out + 1] = rule end
    end
    return out
end

-- Returns true while the cursor is the lens's: near enough to touch it.
function L:Point(x, y, elapsed)
    self:Animate(elapsed)
    if not self.eb:HasFocus() and not GetCurrentKeyBoardFocus() then self.eb:SetFocus() end
    local s = self.scale or 1
    local dx, dy = (x - self.cx) / s, (y - self.cy) / s
    local r = math.sqrt(dx * dx + dy * dy)
    if r > self.outer + 80 then
        -- Away from the lens it stays open: Escape or a click on the background closes it.
        self.raw = nil
        if not self.slot then return false end
        self:SetTouch(nil, nil, nil, false)
        self:Say(x, y)
        return false
    end
    self.away = 0

    local hover, prop
    local lock = self.lock
    if lock and (Dist(x, y, lock.x, lock.y) > 6 or not self.petals[lock.rule]) then
        lock, self.lock = nil, nil
    end
    -- The locked petal wins over whatever slid under the cursor meanwhile.
    if lock then
        for _, p in ipairs(self.layout) do
            if p.rule == lock.rule then
                if p.growth then prop = p.rule else hover = p.rule end
            end
        end
    end
    if not hover and not prop then
        for _, p in ipairs(self.layout) do
            local w = self.petals[p.rule]
            if w and Dist(w.cx, w.cy, dx, dy) < PETAL * 0.62 then
                if p.growth then prop = p.rule else hover = p.rule end
                break
            end
        end
    end
    local onCore = r < CORE + 6
    local ghostAt
    if not hover and not prop and not onCore and r < self.outer + DR + 10 then
        local angle = math.deg(math.atan2(dy, dx)) % 360
        local best, bestD
        for _, u in ipairs(UNITS) do
            local d = math.abs(((angle - u.angle + 540) % 360) - 180)
            if not bestD or d < bestD then best, bestD = u, d end
        end
        local index = 0
        for _, p in ipairs(self.layout) do
            if not p.growth and p.r < r then index = index + 1 end
        end
        ghostAt = { unit = best.key, index = index, angle = best.angle, r = math.max(r, CORE + 16) }
    end

    -- Resting on a lone catch-all shows what it could grow into.
    if hover and self:CanSprout(hover) then
        self.wilt = 0
        self.sproutWait = self.sproutWait + elapsed
        if not self.sprout and self.sproutWait >= SPROUT then
            local growth = self:Growth()
            if #growth > 0 then
                self.sprout, self.props = true, growth
                self:Hold(hover)
                self:Layout()
            end
        end
    elseif prop then
        self.wilt = 0
    else
        self.sproutWait = 0
        if self.sprout then
            self.wilt = (self.wilt or 0) + elapsed
            if self.wilt >= WILT then
                self.sprout, self.props = false, nil
                self:Layout()
            end
        end
    end

    for _, c in ipairs(self.haloChips) do
        if c:IsShown() and c:IsMouseOver() then
            self.raw = { chip = c }
            self:SetTouch(nil, nil, nil, false)
            self:Say(x, y)
            return true
        end
    end
    for _, c in ipairs(self.orderChips) do
        if c:IsShown() and c:IsMouseOver() then
            self.raw = { order = c }
            self:SetTouch(nil, nil, nil, false)
            self:Say(x, y)
            return true
        end
    end
    self.raw = { hover = hover, prop = prop, ghostAt = ghostAt, onCore = onCore }
    self:SetTouch(hover, prop, ghostAt, onCore)
    self:Say(x, y)
    return true
end

-- The selected spot, if it still exists: hover, ghostAt, onCore as if the cursor were there.
function L:Pinned()
    local pin = self.pin
    if not pin then return end
    if pin.rule then
        for _, p in ipairs(self.layout or {}) do
            if p.rule == pin.rule and not p.growth then return true, pin.rule, nil, false end
        end
        self.pin = nil
        return
    elseif pin.ghost then
        return true, nil, pin.ghost, false
    elseif pin.core then
        return true, nil, nil, true
    end
end

-- Where the selection is, in lens units.
function L:PinPosition()
    local pin = self.pin
    if not pin then return end
    if pin.rule then
        local w = self.petals[pin.rule]
        if w then return w.cx, w.cy, PETAL * 1.9 end
    elseif pin.ghost then
        local gx, gy = Polar(pin.ghost.r, pin.ghost.angle)
        return gx, gy, 46
    elseif pin.core then
        return 0, 0, CORE * 2 + 34
    end
end

local function SamePin(a, b)
    if not a or not b then return false end
    if a.rule or b.rule then return a.rule == b.rule end
    if a.core or b.core then return a.core == b.core end
    return a.ghost.unit == b.ghost.unit and a.ghost.index == b.ghost.index
end

-- A left click (not a hold) on the lens: select what's under the cursor. Clicking the selected
-- spot again places what you typed there, or unselects it.
function L:Click()
    local raw = self.raw or {}
    if raw.order then
        local rule = self.pin and self.pin.rule
        if rule then self:MoveOrder(rule, raw.order.delta) end
        return
    end
    if raw.chip then
        local rule = self.pin and self.pin.rule
        if rule then
            local _, nextHalo = HaloOf(rule.combat)
            self:SetHalo(rule, nextHalo.value)
        end
        return
    end
    if raw.prop then return self:AcceptGrowth() end
    local target
    if raw.hover then
        target = { rule = raw.hover }
    elseif raw.ghostAt then
        local g = raw.ghostAt
        target = { ghost = { unit = g.unit, index = g.index, angle = g.angle, r = g.r } }
    elseif raw.onCore then
        target = { core = true }
    end
    if not target then
        -- The desk's background: the first click lets go of the selection, the next closes the lens.
        if self.pin then self.pin = nil else self:Dissolve() end
        return
    end
    if SamePin(target, self.pin) then
        if (self.text or "") ~= "" then self:Commit() else self.pin = nil end
    else
        self.pin = target
        if target and not target.core then
            self:Flash("|cffffd100Selected.|r Type a spell name and press Enter. You can move the mouse away.")
        end
    end
end

function L:SetTouch(hover, prop, ghostAt, onCore)
    self.rawCore = onCore
    local pinned, ph, pg, pc = self:Pinned()
    if pinned then hover, prop, ghostAt, onCore = ph, nil, pg, pc end
    if self.orbiting and IsMouseButtonDown("RightButton") then hover = self.orbiting end
    local px, py, size = self:PinPosition()
    local rule = self.pin and self.pin.rule
    -- The small halo icons: hidden on the selected rule, which shows its badge instead.
    for r, w in pairs(self.petals) do
        w.mini:SetShown(w.haloOn and r ~= rule)
    end
    for _, c in ipairs(self.orderChips) do
        if rule and px then
            c:SetPoint("CENTER", self.top, "CENTER", px, py + c.delta * -(size / 2 + 4))
            local ok = self:CanMoveOrder(rule, c.delta)
            local hot = self.raw and self.raw.order == c
            c.bg:SetColorTexture(ok and 0.35 or 0.12, ok and 0.3 or 0.12, ok and 0.1 or 0.14, hot and 1 or 0.9)
            c.label:SetTextColor(ok and 1 or 0.5, ok and 0.9 or 0.5, ok and 0.6 or 0.55)
            c:Show()
        else
            c:Hide()
        end
    end
    local badge = self.badge
    if rule and px then
        local h = HaloOf(rule.combat)
        badge.value = h.value
        badge:SetPoint("CENTER", self.top, "CENTER", px - PETAL / 2, py - PETAL / 2)
        badge.icon:SetTexture(h.icon)
        if h.coords then badge.icon:SetTexCoord(unpack(h.coords)) else badge.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
        badge.ring:SetVertexColor(h.color[1], h.color[2], h.color[3])
        badge.ring:SetAlpha(self.raw and self.raw.chip and 1 or 0.8)
        local hot = self.raw and self.raw.chip and 31 or 26
        badge.ring:SetSize(hot, hot)
        badge:Show()
    else
        badge:Hide()
    end
    if px then
        self.pinRing:SetPoint("CENTER", self.top, "CENTER", px, py)
        self.pinRing:SetSize(size, size)
        self.pinRing:SetAlpha(0.65 + 0.35 * math.sin(GetTime() * 5))
    else
        self.pinRing:SetAlpha(0)
    end
    local changed = hover ~= self.hover or prop ~= self.prop
    self.hover, self.prop, self.ghostAt, self.onCore = hover, prop, ghostAt, onCore
    if changed then self:PaintTags() end
    if ghostAt then
        local gx, gy = Polar(ghostAt.r, ghostAt.angle)
        self.ghost:SetPoint("CENTER", self.top, "CENTER", gx, gy)
        local c = V.WorldColor(V:World())
        self.ghost:SetVertexColor(c[1], c[2], c[3])
        self.ghost:SetAlpha(0.7)
    else
        self.ghost:SetAlpha(0)
    end
    for i, u in ipairs(UNITS) do
        self.compass[i]:SetAlpha(ghostAt and (u.key == ghostAt.unit and 1 or 0.3) or 0.45)
    end

end

---------------------------------------------------------------------------
-- Whispers: the words near the cursor
---------------------------------------------------------------------------

function L:Flash(text)
    self.flash, self.flashUntil = text, GetTime() + 2.6
end

local function Suggestions(found, pick)
    local names = {}
    for i, e in ipairs(found) do
        if i > 4 then break end
        names[#names + 1] = (i == pick) and ("|cffffffff" .. e.label .. "|r") or ("|cff8090a0" .. e.label .. "|r")
    end
    return table.concat(names, "  ·  ")
end

function L:Say(x, y)
    -- Reading the guide: no words by the cursor or the selection on top of it.
    if ns.Guide:Owns() then
        V:Whisper(nil)
        return
    end
    local px, py = self:PinPosition()
    if px then
        local s = self.scale or 1
        x, y = self.cx + px * s + 14, self.cy + py * s + 6
    end
    local text = self.text or ""
    local out
    if self.flashUntil and GetTime() < self.flashUntil and not (self.raw and (self.raw.chip or self.raw.order)) and text == "" then
        out = self.flash
    elseif text:sub(1, 1) == "/" then
        local lines = { "|cffffe9a8" .. text .. "|r" }
        local typed = text:match("^/(%S*)") or ""
        for _, c in ipairs(COMMANDS) do
            if c[1]:sub(2, #typed + 1) == typed:lower() then
                lines[#lines + 1] = ("|cffffffff%s|r  |cff8090a0%s|r"):format(c[1], c[2])
            end
        end
        out = table.concat(lines, "\n")
    elseif text ~= "" then
        local done, last = {}, text
        if text:find(",") then
            local parts = {}
            for part in text:gmatch("[^,]+") do parts[#parts + 1] = strtrim(part) end
            last = text:match(",%s*$") and "" or table.remove(parts)
            for _, part in ipairs(parts) do
                local e = ns.Voice:Find(part, 1)[1]
                done[#done + 1] = e and e.label or ("|cffff6060" .. part .. "?|r")
            end
        end
        local found = ns.Voice:Find(last, 6)
        local pick = #found > 0 and ((self.pick - 1) % #found) + 1 or 0
        local head = #done > 0 and ("|cffb0ffc0" .. table.concat(done, " > ") .. " >|r ") or ""
        out = ("%s|cffffe9a8%s|r\n%s"):format(head, last ~= "" and last or "...",
            #found > 0 and Suggestions(found, pick) or (last ~= "" and "|cffff6060nothing answers to that|r" or ""))
        if not self.hover and not self.ghostAt then
            out = out .. "\n|cff8090a0Point at a rule or at empty space, then press Enter.|r"
        else
            out = out .. "\n|cff8090a0Enter: use it  ·  Tab: next match  ·  Escape: clear|r"
        end
    elseif self.raw and self.raw.order then
        local rule = self.pin and self.pin.rule
        local n = rule and self:OrderOf(rule) or 0
        local delta = self.raw.order.delta
        local ok, why = self:CanMoveOrder(rule, delta)
        if ok then
            out = ("Click: make this rule |cffffffff%d|r instead of %d (tried %s).\n|cff8090a0Ctrl + mouse wheel on a rule, or the Up/Down arrow keys, do the same.|r")
                :format(n + delta, n, delta < 0 and "sooner" or "later")
        else
            out = "|cffff9040Can't move it " .. (delta < 0 and "earlier" or "later") .. ":|r " .. why
        end
    elseif self.raw and self.raw.chip then
        local now, nextHalo = HaloOf(self.raw.chip.value)
        out = ("Halo: this rule fires |cffffffff%s|r.\n|cffffd100Click: %s|r  |cff8090a0(any time > in combat > out of combat)|r")
            :format(now.label, nextHalo.label)
    elseif self.hold then
        out = self.hold.button == "RightButton" and "Keep holding to |cffff8080revert|r..." or "Keep holding to |cffffd100save|r..."
    elseif self.prop then
        out = "A suggested rule (see the panel on the right).\n|cff8090a0Enter or click: add these suggestions.|r"
    elseif self.hover then
        local rule = self.hover
        local lines = { "|cffffffff" .. L.Describe(rule) .. "|r" }
        if self.sprout == false and self:CanSprout(rule) then lines[#lines + 1] = "|cff8090a0Keep resting here for suggestions.|r" end
        if not self.pin then
            lines[#lines + 1] = "|cffffd100Click to select it|r |cff8090a0(then type without holding the mouse here, or set its halo).|r"
        else
            lines[#lines + 1] = "|cff8090a0Halo (combat): click the small icon at its bottom-left to cycle it.|r"
        end
        lines[#lines + 1] = "|cff8090a0Type: new spell  ·  Wheel: friendly/hostile/alive/dead  ·  Ctrl + wheel: move earlier/later  ·  Right-click held + wheel: other unit  ·  Backspace: delete|r"
        out = table.concat(lines, "\n")
    elseif self.ghostAt then
        local g = self.ghostAt
        local lines = {}
        lines[#lines + 1] = ("New rule on |cffffffff%s|r, tried |cffffffff%s|r. Type a spell name, then Enter."):format(L.WHO[g.unit], Ordinal(g.index + 1))
        local clash = self:Clash(g)
        if clash then
            lines[#lines + 1] = ("|cffff9040Rule %d already catches this|r (%s). Typing here changes that rule.")
                :format(self:OrderOf(clash) or 0, L.Describe(clash))
            if B:IsUnconditional(clash) then
                lines[#lines + 1] = "|cff8090a0A rule on yourself or the cursor with no conditions always fires, so a set only has room for one. Add friendly/hostile first (wheel) to make room.|r"
            end
        end
        if not self.pin then lines[#lines + 1] = "|cffffd100Click to select this spot|r |cff8090a0(then type without holding the mouse here).|r" end
        local echoes = ns.Voice:Echoes(3)
        if #echoes > 0 then
            local names = {}
            for _, e in ipairs(echoes) do names[#names + 1] = e.label end
            lines[#lines + 1] = "|cff8090a0Tab: " .. table.concat(names, "  ·  ") .. "|r"
        end
        out = table.concat(lines, "\n")
    elseif self.onCore then
        out = "|cffffd100Hold left-click: save.|r  |cffff8080Hold right-click: revert.|r"
        if self.macro then
            out = out .. ("\n|cff8f9bb0The macro (%d / %d characters):|r\n|cffbfe7ff%s|r"):format(self.length, B.MAX_LENGTH,
                (self.macro:gsub("; ", ";\n    ")))
        end
    end
    V:Whisper(out, x, y)
end

---------------------------------------------------------------------------
-- Verbs
---------------------------------------------------------------------------

function L:Edited()
    if not self.slot then return end
    V.dirty[self.slot] = true
    self.draft.sequence = AnyBraid(self.draft) or nil
    self:Layout()
    self:RestartPulse()
    V:Paint()
end

-- A new petal where the ghost is, or the petal that already sits in that context.
function L:Birth(ghostAt, x, y)
    local rules = self.draft.rules
    local candidate = B:NewRule({ mod = V:World(), unit = ghostAt.unit })
    local existing = Conflict(rules, candidate)
    if existing then
        self:Hold(existing)
        self.merged = existing
        return existing
    end
    local before = self:WorldRules()[ghostAt.index + 1]
    local pos = #rules + 1
    for i, r in ipairs(rules) do
        if r == before then pos = i end
    end
    table.insert(rules, pos, candidate)
    self:Hold(candidate, x, y)
    return candidate
end

local function Give(rule, actions)
    rule.role = nil
    if #actions > 1 then
        rule.steps = {}
        for i = 1, math.min(#actions, B.MAX_STEPS) do rule.steps[i] = actions[i] end
        B:SyncFromSteps(rule)
    else
        rule.steps = nil
        local a = actions[1]
        rule.kind, rule.id, rule.name, rule.rank = a.kind, a.id, a.name, a.rank
    end
end

function L:Commit()
    if not self:IsOpen() then return end
    local text = strtrim(self.text or "")
    if text == "" then
        if self.prop then self:AcceptGrowth() end
        return
    end
    if text:sub(1, 1) == "/" then return self:Command(text) end
    if text:match("^%d+$") then return self:Command("/reset " .. text) end

    local actions = {}
    if text:find(",") then
        for raw in text:gmatch("[^,]+") do
            local part = strtrim(raw)
            if part ~= "" then
                local e = ns.Voice:Find(part, 1)[1]
                if not e then return self:Flash(("|cffff6060Nothing answers to \"%s\".|r"):format(part)) end
                actions[#actions + 1] = ns.Voice.Action(e)
            end
        end
    else
        local found = ns.Voice:Find(text, 6)
        local e = found[((self.pick - 1) % math.max(#found, 1)) + 1]
        if not e then return self:Flash("|cffff6060Nothing answers to that.|r") end
        actions[1] = ns.Voice.Action(e)
    end
    if #actions == 0 then return end

    local rule = self.hover
    if rule then
        self:Hold(rule)
    elseif self.ghostAt then
        local bx, by
        if self.pin and self.pin.ghost then
            bx, by = Polar(self.ghostAt.r, self.ghostAt.angle)
        else
            local x, y = V:Cursor()
            local s = self.scale or 1
            bx, by = (x - self.cx) / s, (y - self.cy) / s
        end
        rule = self:Birth(self.ghostAt, bx, by)
        if self.pin then self.pin = { rule = rule } end
    else
        return self:Flash("Point at a rule, or at empty space around the centre.")
    end
    Give(rule, actions)
    self.eb:SetText("")
    self:Edited()
    if self.merged then
        self.merged = nil
        self:Flash(("|cffffd100Changed rule %d instead:|r it already covers that spot (%s), and a set can't have two.")
            :format(self:OrderOf(rule) or 0, L.Describe(rule)))
        if self.pin then self.pin = { rule = rule } end
    end
end

-- Sets a rule's combat condition (its halo). Returns true if it changed or already was so.
function L:SetHalo(rule, value, quiet)
    if rule.combat == value then return true end
    local test = ns.DeepCopy(rule)
    test.combat = value
    if Conflict(self.draft.rules, test, rule) then
        self:Flash("Another rule already covers that.")
        return false
    end
    rule.combat = value
    self:Hold(rule)
    if not quiet then
        self:Flash(value == "combat" and "|cffffa040Only in combat now|r (orange halo)."
            or value == "nocombat" and "|cff59a6ffOnly out of combat now|r (blue halo)."
            or "Any time now (no halo).")
        self:Edited()
    end
    return true
end

-- Can `rule` move one place (delta -1 earlier, +1 later) in its set? If not, why.
function L:CanMoveOrder(rule, delta)
    if not rule then return false, "select a rule first." end
    local rules = self.draft.rules
    local index
    for i, r in ipairs(rules) do
        if r == rule then index = i end
    end
    local other = index and rules[index + delta]
    if not other or other.mod ~= rule.mod then
        return false, delta < 0 and "it's already tried first." or "it's already tried last."
    end
    if B:CanMove(rules, index, delta) then return true end
    local upper, lower = rule, other
    if delta > 0 then upper, lower = other, rule end
    return false, ("rule %d (%s) would catch everything rule %d does, so %d could never fire. A broader rule has to come after the narrower ones.")
        :format(self:OrderOf(upper) or 0, L.Describe(upper), self:OrderOf(lower) or 0, self:OrderOf(lower) or 0)
end

-- Moves a rule one place in the order its set is tried.
function L:MoveOrder(rule, delta)
    local ok, why = self:CanMoveOrder(rule, delta)
    if not ok then return self:Flash("|cffff9040Can't move it:|r " .. why) end
    local rules = self.draft.rules
    for i, r in ipairs(rules) do
        if r == rule then
            local other = rules[i + delta]
            rules[i], rules[i + delta] = other, r
            break
        end
    end
    self:Flash(("Now rule |cffffffff%d|r."):format(self:OrderOf(rule) or 0))
    self:Edited()
end

-- A rule's number in the shown set.
function L:OrderOf(rule)
    for i, r in ipairs(self:WorldRules()) do
        if r == rule then return i end
    end
end

-- The rule a new one at this spot would collide with, if any.
function L:Clash(ghostAt)
    return Conflict(self.draft.rules, B:NewRule({ mod = V:World(), unit = ghostAt.unit }))
end

function L:Tab()
    if (self.text or "") == "" then
        -- Empty: offer what you cast most.
        local echoes = ns.Voice:Echoes(3)
        self.echoPick = ((self.echoPick or 0) % math.max(#echoes, 1)) + 1
        local e = echoes[self.echoPick]
        if e then self.eb:SetText(e.label) end
    else
        self.pick = self.pick + 1
    end
end

function L:AcceptGrowth()
    local rules = self.draft.rules
    local first = self:WorldRules()[1]
    local pos = #rules + 1
    for i, r in ipairs(rules) do
        if r == first then pos = i end
    end
    for i, rule in ipairs(self.props or {}) do table.insert(rules, pos + i - 1, rule) end
    self.sprout, self.props, self.prop = false, nil, nil
    self.sproutWait = -math.huge -- don't sprout again until the cursor leaves the petal
    self:Flash("Suggestions added.")
    self:Edited()
end

function L:LetGo()
    local rule = self.hover
    if not rule then return end
    for i, r in ipairs(self.draft.rules) do
        if r == rule then table.remove(self.draft.rules, i) break end
    end
    self.hover = nil
    if self.pin and self.pin.rule == rule then self.pin = nil end
    self:Edited()
end

-- Steps `rule` through `options` (each a table of fields), skipping ones that would clash.
function L:Turn(rule, options, current, delta)
    local n = #options
    for _ = 1, n - 1 do
        current = (current - 1 + (delta < 0 and 1 or -1)) % n + 1
        local test = ns.DeepCopy(rule)
        for k, v in pairs(options[current]) do test[k] = v end
        if not Conflict(self.draft.rules, test, rule) then
            for k, v in pairs(options[current]) do rule[k] = v end
            return true
        end
    end
end

function L:Wheel(delta)
    if not self:IsOpen() then return false end
    local rule = self.hover
    if not rule then
        if self.pin then return true end
        local x, y = V:Cursor()
        return Dist(x, y, self.cx, self.cy) <= (self.outer + 80) * (self.scale or 1) -- inside the lens: nothing to turn
    end
    -- Ctrl + wheel: swap with the rule before (up) or after (down) it.
    if IsControlKeyDown() then
        self:MoveOrder(rule, delta > 0 and -1 or 1)
        return true
    end
    if IsMouseButtonDown("RightButton") then
        local options, current = {}, 1
        for i, u in ipairs(UNITS) do
            options[i] = { unit = u.key }
            if u.key == rule.unit then current = i end
        end
        self.orbiting = rule
        if self:Turn(rule, options, current, delta) then self:Edited() end
    else
        local options, current = {}, 1
        for i, t in ipairs(TEMPERS) do
            options[i] = { reaction = t[1], state = t[2] }
            if t[1] == rule.reaction and t[2] == rule.state then current = i end
        end
        if self:Turn(rule, options, current, delta) then
            self:Hold(rule)
            self:Edited()
        end
    end
    return true
end

function L:MouseDown(button)
    if self.rawCore then
        self.hold = { button = button, at = GetTime() }
    end
end

-- A release is a key press (hardware event), so a seal may reload the UI here.
function L:MouseUp(button)
    if button == "RightButton" then self.orbiting = nil end
    local hold = self.hold
    self.hold = nil
    if hold and hold.button == button and GetTime() - hold.at >= HOLD then
        if button == "RightButton" then self:Unravel() else self:Seal() end
        return
    end
    if button == "LeftButton" then self:Click() end
end

function L:Command(text)
    local cmd, rest = text:match("^/(%S+)%s*(.-)$")
    cmd = (cmd or ""):lower()
    local rule = self.hover
    local function NeedPetal()
        if not rule then self:Flash("Point at a rule first.") end
        return rule
    end
    if cmd == "combat" or cmd == "calm" or cmd == "always" then
        if not NeedPetal() then return end
        local value = cmd == "combat" and "combat" or cmd == "calm" and "nocombat" or "any"
        if not self:SetHalo(rule, value, true) then return end
    elseif cmd == "reset" then
        if not NeedPetal() then return end
        local reset = {}
        for word in rest:lower():gmatch("%S+") do
            local seconds = tonumber(word:match("^(%d+)s?$"))
            if seconds then
                reset.seconds = math.min(seconds, B.MAX_RESET_SECONDS)
            else
                for _, flag in ipairs(B.RESET_FLAGS) do
                    if flag.key == word then reset[flag.key] = true end
                end
            end
        end
        rule.reset = next(reset) and reset or nil
        if not Braided(rule) then self:Flash("Kept. It only matters for a cast sequence (type a, b, c).") end
        self:Hold(rule)
    elseif cmd == "tooltip" then
        self.draft.showtooltip = not self.draft.showtooltip or nil
        self:Flash(self.draft.showtooltip and "#showtooltip on." or "#showtooltip off.")
    elseif cmd == "ranks" then
        ns:SetOption("db.showAllRanks", not ns.db.showAllRanks)
        ns.Voice:Refresh()
        self:Flash(ns.db.showAllRanks and "Every rank is offered." or "Only your highest ranks are offered.")
    elseif cmd == "clear" then
        local world = V:World()
        for i = #self.draft.rules, 1, -1 do
            if self.draft.rules[i].mod == world then table.remove(self.draft.rules, i) end
        end
    elseif cmd == "classic" then
        local slot = self.slot
        V:Close()
        ns.UI:Create():Show()
        ns.UI:SelectSlot(slot)
        return
    else
        return self:Flash(("|cffff6060No word \"/%s\".|r"):format(cmd))
    end
    self.eb:SetText("")
    self:Edited()
end

local function ReloadIfNeeded()
    if ns.needsReload and ns.db.autoReload then
        ns:Print("Reloading the UI so your action bars stay error-free...")
        ReloadUI()
    end
end

function L:Seal()
    local slot = self.slot
    local _, length = B:Build(self.draft)
    if length == 0 then return self:Flash("Nothing to save yet: add a spell first.") end
    local design = ns.DeepCopy(self.draft)
    for _, rule in ipairs(design.rules) do rule.role = nil end
    local ok, err = ns.Manager:Apply(slot, design)
    if ok == "queued" then
        ns:Print("In combat. The macro will be saved when combat ends.")
    elseif ok then
        V.dirty[slot] = nil
        V.drafts[slot] = nil
        self.draft = self:Load(slot)
        V.drafts[slot] = self.draft
        ns:Print(("Saved %s (%s)."):format(ns.Bars:Describe(slot), design.macroName))
        self:Flash("|cffffd100Saved.|r Your button now uses this macro.")
        self:Layout()
        V:Paint()
        ReloadIfNeeded()
    elseif err then
        self:Flash("|cffff6060" .. err .. "|r")
    end
end

function L:Unravel()
    local slot = self.slot
    if not ns.db.designs[slot] then
        V.drafts[slot], V.dirty[slot] = nil, nil
        self.draft = self:Load(slot)
        V.drafts[slot] = self.draft
        self:Flash("Unsaved changes thrown away.")
        self:Layout()
        V:Paint()
        return
    end
    local result = ns.Manager:Revert(slot)
    if result == "queued" then
        ns:Print("In combat. The button will be reverted when combat ends.")
    elseif result then
        V.drafts[slot], V.dirty[slot] = nil, nil
        self.draft = self:Load(slot)
        V.drafts[slot] = self.draft
        ns:Print(("Reverted %s to its original action."):format(ns.Bars:Describe(slot)))
        self:Flash("|cffff8080Reverted.|r The original action is back.")
        self:Layout()
        V:Paint()
        ReloadIfNeeded()
    end
end
