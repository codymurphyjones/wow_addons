local _, ns = ...

-- The emote wheel, in two steps around your cursor:
--   1. four categories: Fun (top), Social (right), Quick (bottom) and Battle (left);
--   2. the chosen category's eight emotes in a ring. Click one to do it.
-- Quick learns from you: it holds the eight emotes you use most from the wheel (until it has seen
-- enough, a starter set fills the gaps).
--
-- An account-wide macro, EmoteWheel (/click WallyHUDEmoteWheelToggle), opens it: put the macro on a
-- bar or bind its key. The hub (or a right-click on an emote) goes back to the categories; Escape, the macro
-- again, or a click anywhere else closes it. Options > AddOns > WallyHUD > Emote Wheel picks each
-- category's emotes, shows what Quick has learned, shows the macro's code, and creates or updates the
-- macro (and picks it up for your bars).
--
-- One secure macro button covers the wheel; its macro is the emote under the cursor ("/dance"), the
-- game's real emote command, run by your click
-- (C_ChatInfo.PerformEmote is restricted on this client). A frame holding secure buttons can't be
-- shown, hidden or changed in combat, so the wheel opens out of combat only.
local EW = {}
ns.EmoteWheel = EW

local SLOTS = 8
local MACRO_NAME = "EmoteWheel"
local MACRO_ICON = 134400 -- the question mark, as the macro window gives new macros
local TOGGLE = "WallyHUDEmoteWheelToggle"
local MACRO_BODY = "#showtooltip\n/click " .. TOGGLE

-- ---------------------------------------------------------------------------
-- Emotes: the game's real emote commands (/dance, /wave, ...), by group
-- ---------------------------------------------------------------------------

-- { token, label, group }. The command is "/" .. the token in lower case. Every one of these plays
-- an animation, a sound, or both. The groups only sort the settings' menus.
local EMOTES = {
    -- Fun
    { "DANCE", "Dance", "Fun" }, { "CHEER", "Cheer", "Fun" }, { "LAUGH", "Laugh", "Fun" },
    { "FLEX", "Flex", "Fun" }, { "CHICKEN", "Chicken", "Fun" }, { "TRAIN", "Train", "Fun" },
    { "JOKE", "Joke", "Fun" }, { "FLIRT", "Flirt", "Fun" }, { "KISS", "Kiss", "Fun" },
    { "SILLY", "Silly", "Fun" }, { "APPLAUD", "Applaud", "Fun" }, { "CLAP", "Clap", "Fun" },
    { "ROAR", "Roar", "Fun" }, { "VICTORY", "Victory", "Fun" }, { "RUDE", "Rude", "Fun" },
    -- Greetings
    { "WAVE", "Wave", "Greetings" }, { "HELLO", "Hello", "Greetings" }, { "BYE", "Bye", "Greetings" },
    { "BOW", "Bow", "Greetings" }, { "SALUTE", "Salute", "Greetings" }, { "THANK", "Thank", "Greetings" },
    { "WELCOME", "Welcome", "Greetings" }, { "CONGRATULATE", "Congratulate", "Greetings" },
    -- Reactions
    { "YES", "Yes", "Reactions" }, { "NO", "No", "Reactions" }, { "NOD", "Nod", "Reactions" },
    { "SHRUG", "Shrug", "Reactions" }, { "POINT", "Point", "Reactions" }, { "QUESTION", "Question", "Reactions" },
    { "CRY", "Cry", "Reactions" }, { "SHY", "Shy", "Reactions" }, { "BEG", "Beg", "Reactions" },
    { "ANGRY", "Angry", "Reactions" }, { "GASP", "Gasp", "Reactions" }, { "COWER", "Cower", "Reactions" },
    { "TALK", "Talk", "Reactions" }, { "SHOUT", "Shout", "Reactions" }, { "PRAY", "Pray", "Reactions" },
    -- Poses
    { "SIT", "Sit", "Poses" }, { "STAND", "Stand", "Poses" }, { "KNEEL", "Kneel", "Poses" },
    { "SLEEP", "Sleep", "Poses" }, { "EAT", "Eat", "Poses" }, { "DRINK", "Drink", "Poses" },
    -- Battle calls (spoken)
    { "CHARGE", "Charge", "Battle calls" }, { "ATTACKTARGET", "Attack target", "Battle calls" },
    { "HELPME", "Help me", "Battle calls" }, { "HEALME", "Heal me", "Battle calls" },
    { "INCOMING", "Incoming", "Battle calls" }, { "OPENFIRE", "Open fire", "Battle calls" },
    { "FLEE", "Flee", "Battle calls" }, { "OOM", "Out of mana", "Battle calls" },
    { "FOLLOWME", "Follow me", "Battle calls" }, { "WAIT", "Wait", "Battle calls" },
}
local GROUPS = { "Fun", "Greetings", "Reactions", "Poses", "Battle calls" }

local byToken = {}
for _, e in ipairs(EMOTES) do byToken[e[1]] = e end

-- "DANCE" -> "/dance" (nil for an unknown token)
local function Command(token)
    return type(token) == "string" and byToken[token] and ("/" .. token:lower()) or nil
end

-- "DANCE" -> "Dance"
local function Label(token)
    local e = byToken[token]
    return e and e[2] or tostring(token)
end

-- Every emote for a picker: { group, { { token, label }, ... } } in the list's order.
function EW:Choices()
    local out = {}
    for _, g in ipairs(GROUPS) do
        local items = {}
        for _, e in ipairs(EMOTES) do
            if e[3] == g then items[#items + 1] = { e[1], e[2] } end
        end
        out[#out + 1] = { g, items }
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Categories: three you fill, and Quick, which learns
-- ---------------------------------------------------------------------------

-- { key, name, angle in degrees clockwise from the top }. Quick sits at the bottom.
local CATEGORIES = {
    { "fun", "Fun", 0 },
    { "social", "Social", 90 },
    { "quick", "Quick", 180 },
    { "battle", "Battle", 270 },
}
local EDITABLE = { "fun", "social", "battle" }
local CAT_NAME = {}
for _, c in ipairs(CATEGORIES) do CAT_NAME[c[1]] = c[2] end

-- Quick's starter set, for the slots usage hasn't filled yet.
local QUICK_START = { "DANCE", "WAVE", "CHEER", "LAUGH", "BOW", "THANK", "HELLO", "ROAR" }

local function Lists()
    local t = ns.db and ns.db.emoteCategories
    if type(t) ~= "table" then
        t = {}
        if ns.db then ns.db.emoteCategories = t end
    end
    return t
end

-- A category you fill: its eight slots (a slot may be empty).
local function CategorySlots(key)
    local t = Lists()
    if type(t[key]) ~= "table" then t[key] = {} end
    return t[key]
end

local function Usage()
    local t = ns.db and ns.db.emoteUsage
    if type(t) ~= "table" then
        t = {}
        if ns.db then ns.db.emoteUsage = t end
    end
    return t
end

-- One use of an emote from the wheel: { n = times, t = last time }.
local function Count(token)
    local u = Usage()
    local e = type(u[token]) == "table" and u[token] or { n = 0, t = 0 }
    e.n, e.t = (e.n or 0) + 1, time()
    u[token] = e
end

-- Quick: the emotes used most (the more recent one first on a tie), then the starter set.
function EW:Quick()
    local used = {}
    for token, e in pairs(Usage()) do
        if byToken[token] and type(e) == "table" and (e.n or 0) > 0 then used[#used + 1] = { token, e.n, e.t or 0 } end
    end
    table.sort(used, function(a, b)
        if a[2] ~= b[2] then return a[2] > b[2] end
        return a[3] > b[3]
    end)
    local out, seen = {}, {}
    for _, u in ipairs(used) do
        if #out >= SLOTS then break end
        out[#out + 1], seen[u[1]] = u[1], true
    end
    for _, token in ipairs(QUICK_START) do
        if #out >= SLOTS then break end
        if not seen[token] then out[#out + 1], seen[token] = token, true end
    end
    return out, #used
end

-- A category's eight emotes, as the wheel shows them.
local function Emotes(key)
    if key == "quick" then return (EW:Quick()) end
    return CategorySlots(key)
end

-- ---------------------------------------------------------------------------
-- The wheel
-- ---------------------------------------------------------------------------

local wheel, toggle
local ShowCategories, ShowEmotes

-- The art (tools/WallyHUD/make_emote_wheel.py; the hub is the orb's, tools/WallyHUD/make_orb.py).
local ART = "Interface\\AddOns\\WallyHUD\\Media\\EmoteWheel\\"
local ORB = "Interface\\AddOns\\WallyHUD\\Media\\Orb\\"
local SIZE = 320          -- the wheel, rim to rim
local RING_INNER = 0.40   -- the ring's inner edge, a share of the half-width (as the art draws it)
local RING_OUTER = 0.92   -- the glass's outer edge
local HUB = math.floor(SIZE * RING_INNER) + 10 -- the hub's bezel covers the ring's inner edge
local LABEL_R = (RING_INNER + RING_OUTER) / 2 * SIZE / 2 -- where a wedge's label sits

local function Tok() return ns.T or WallyHUD.Tokens end
local function RGBA(c) return c[1], c[2], c[3], c[4] or 1 end

local function Face(fs, weight, size)
    fs:SetFont(WallyHUD.Face and WallyHUD.Face(weight) or STANDARD_TEXT_FONT, size, "")
    fs:SetShadowColor(0, 0, 0, 0.75)
    fs:SetShadowOffset(1, -1)
end

-- Which part of the wheel the cursor is over: "hub", a wedge's number (1..n, clockwise from the
-- top), or nil (outside the ring).
local function Under(n)
    local cx, cy = wheel:GetCenter()
    if not cx then return nil end
    local x, y = GetCursorPosition()
    local s = wheel:GetEffectiveScale()
    local dx, dy = x / s - cx, y / s - cy
    local r = math.sqrt(dx * dx + dy * dy) / (SIZE / 2)
    if r < RING_INNER then return "hub" end
    if r > 1 then return nil end
    local a = math.atan2(dx, dy) -- 0 at the top, clockwise
    if a < 0 then a = a + 2 * math.pi end
    local seg = 2 * math.pi / n
    return math.floor((a + seg / 2) / seg) % n + 1
end

-- The lit wedge over part i of n (nil: none).
local function Light(i, n)
    if not i or i == "hub" then wheel.wedge:Hide(); return end
    wheel.wedge:SetTexture(ART .. (n == 4 and "Wedge4" or "Wedge8"))
    wheel.wedge:SetRotation(-(i - 1) * 2 * math.pi / n)
    wheel.wedge:Show()
end

-- The hub's words: a title and a line under it.
local function Hub(title, line)
    wheel.title:SetText(title or "")
    wheel.line:SetText(line or "")
end

-- One label on the ring: a name and a small line under it, at part i of n.
local function Slot(i)
    local l = wheel.labels[i]
    if l then return l end
    l = {}
    l.name = wheel.front:CreateFontString(nil, "OVERLAY")
    Face(l.name, "semibold", 13)
    l.name:SetWidth(84); l.name:SetWordWrap(true)
    l.sub = wheel.front:CreateFontString(nil, "OVERLAY")
    Face(l.sub, "medium", 10)
    l.sub:SetPoint("TOP", l.name, "BOTTOM", 0, -1)
    wheel.labels[i] = l
    return l
end

local function PlaceLabels(n)
    for i, l in ipairs(wheel.labels) do
        if i <= n then
            local a = (i - 1) / n * 2 * math.pi
            l.name:ClearAllPoints()
            l.name:SetPoint("CENTER", wheel, "CENTER", math.sin(a) * LABEL_R, math.cos(a) * LABEL_R + 5)
            l.name:Show(); l.sub:Show()
        else
            l.name:Hide(); l.sub:Hide()
        end
    end
end

-- What's under the cursor now: the lit wedge, the hub's words, and (on the emotes step) the
-- emote the click will do. Called every frame while the wheel is open; changes only on a change.
local function Track()
    local n = wheel.category and SLOTS or #CATEGORIES
    local under = Under(n)
    if under == wheel.under then return end
    wheel.under = under
    local T = Tok()
    for i, l in ipairs(wheel.labels) do
        local hot = i == under
        l.name:SetTextColor(RGBA(hot and T.text.primary or T.text.secondary))
        l.sub:SetTextColor(RGBA(hot and T.accent or T.text.tertiary))
    end
    Light(under, n)
    local cmd
    if wheel.category then
        local e = type(under) == "number" and wheel.emotes[under]
        if e then
            cmd = e.cmd
            Hub(e.label, e.cmd)
        elseif under == "hub" then
            Hub("Back", "to the categories")
        else
            Hub(CAT_NAME[wheel.category], "pick an emote")
        end
    else
        local c = type(under) == "number" and CATEGORIES[under]
        if c then
            Hub(c[2], c[1] == "quick" and "your most used" or "eight emotes")
        else
            Hub("Emote", "pick a category")
        end
    end
    -- The one secure button: its macro is the emote under the cursor (out of combat only).
    if not InCombatLockdown() then
        wheel.pad:SetAttribute("type1", cmd and "macro" or nil)
        wheel.pad:SetAttribute("macrotext1", cmd)
    end
end

local function Build()
    if wheel then return wheel end
    local T = Tok()
    wheel = CreateFrame("Frame", "WallyHUDEmoteWheel", UIParent)
    wheel:SetSize(SIZE, SIZE)
    wheel:SetFrameStrata("DIALOG")
    wheel:SetClampedToScreen(true)
    wheel:Hide()
    tinsert(UISpecialFrames, "WallyHUDEmoteWheel") -- Escape closes it

    -- Back to front: the ring, the spokes, the lit wedge; the hub (the orb's smoky glass, shine
    -- and bezel); the words.
    wheel.ring = wheel:CreateTexture(nil, "BACKGROUND")
    wheel.ring:SetAllPoints()
    wheel.ring:SetTexture(ART .. "Ring")
    wheel.spokes = wheel:CreateTexture(nil, "BORDER")
    wheel.spokes:SetAllPoints()
    wheel.spokes:SetVertexColor(1, 1, 1, 0.14)
    wheel.wedge = wheel:CreateTexture(nil, "ARTWORK")
    wheel.wedge:SetAllPoints()
    wheel.wedge:SetBlendMode("ADD")
    wheel.wedge:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 0.85)
    wheel.wedge:Hide()

    local hub = CreateFrame("Frame", nil, wheel)
    hub:SetSize(HUB, HUB)
    hub:SetPoint("CENTER")
    hub:SetFrameLevel(wheel:GetFrameLevel() + 2)
    local mask = hub:CreateMaskTexture()
    mask:SetTexture(ORB .. "Mask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(hub)
    local function Tex(layer, sub, name, masked)
        local t = hub:CreateTexture(nil, layer, nil, sub)
        t:SetAllPoints(hub)
        t:SetTexture(ORB .. name)
        if masked and t.AddMaskTexture then t:AddMaskTexture(mask) end
        return t
    end
    Tex("BACKGROUND", 0, "Empty", true)
    local swirl = Tex("BORDER", 0, "Swirl", true)
    swirl:SetBlendMode("ADD"); swirl:SetAlpha(0.18)
    swirl:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 1)
    if swirl.CreateAnimationGroup then
        local ag = swirl:CreateAnimationGroup()
        local spin = ag:CreateAnimation("Rotation")
        spin:SetDegrees(-360); spin:SetDuration(40)
        ag:SetLooping("REPEAT")
        ag:Play()
    end
    Tex("ARTWORK", 1, "Glass")
    Tex("OVERLAY", 0, "Frame")

    local front = CreateFrame("Frame", nil, wheel)
    front:SetAllPoints()
    front:SetFrameLevel(wheel:GetFrameLevel() + 4)
    wheel.front = front
    wheel.title = front:CreateFontString(nil, "OVERLAY")
    Face(wheel.title, "semibold", 15)
    wheel.title:SetPoint("CENTER", hub, "CENTER", 0, 6)
    wheel.title:SetWidth(HUB - 30)
    wheel.title:SetTextColor(RGBA(T.text.primary))
    wheel.line = front:CreateFontString(nil, "OVERLAY")
    Face(wheel.line, "medium", 10)
    wheel.line:SetPoint("TOP", wheel.title, "BOTTOM", 0, -2)
    wheel.line:SetWidth(HUB - 30)
    wheel.line:SetTextColor(RGBA(T.text.tertiary))
    wheel.labels = {}
    for i = 1, SLOTS do Slot(i) end

    -- The one secure button over the whole wheel: Track sets its macro to the emote under the
    -- cursor, so any point of a wedge does it, round and all. Up only: the macro runs on the release.
    local pad = CreateFrame("Button", "WallyHUDEmoteWheelPad", wheel, "SecureActionButtonTemplate")
    pad:SetAllPoints()
    pad:SetFrameLevel(wheel:GetFrameLevel() + 6)
    pad:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pad:SetAttribute("useOnKeyDown", false)
    pad:HookScript("PostClick", function(_, button)
        if InCombatLockdown() then return end
        local under = wheel.under
        if button == "RightButton" or under == "hub" then
            if wheel.category then ShowCategories() else wheel:Hide() end
            return
        end
        if wheel.category then
            local e = type(under) == "number" and wheel.emotes[under]
            if e then
                Count(e.token)
                wheel:Hide()
            elseif not under then
                wheel:Hide()
            end
        else
            local c = type(under) == "number" and CATEGORIES[under]
            if c then ShowEmotes(c[1]) else wheel:Hide() end
        end
    end)
    wheel.pad = pad

    -- Opening: a quick fade and settle.
    if wheel.CreateAnimationGroup then
        local ag = wheel:CreateAnimationGroup()
        local fade = ag:CreateAnimation("Alpha")
        fade:SetFromAlpha(0); fade:SetToAlpha(1); fade:SetDuration(0.12)
        local grow = ag:CreateAnimation("Scale")
        if grow.SetScaleFrom then grow:SetScaleFrom(0.88, 0.88); grow:SetScaleTo(1, 1) else grow:SetScale(1 / 0.88, 1 / 0.88) end
        grow:SetDuration(0.12); grow:SetSmoothing("OUT")
        wheel.open = ag
    end
    -- A step's words: a quick fade in.
    if front.CreateAnimationGroup then
        local ag = front:CreateAnimationGroup()
        local fade = ag:CreateAnimation("Alpha")
        fade:SetFromAlpha(0.2); fade:SetToAlpha(1); fade:SetDuration(0.1)
        wheel.swap = ag
    end

    wheel:SetScript("OnUpdate", Track)
    -- A click anywhere else closes it; so does a fight starting (before the lockdown, which
    -- wouldn't let a frame holding a secure button hide).
    wheel:RegisterEvent("GLOBAL_MOUSE_DOWN")
    wheel:RegisterEvent("PLAYER_REGEN_DISABLED")
    wheel:SetScript("OnEvent", function(self, event)
        if not self:IsShown() then return end
        if event == "PLAYER_REGEN_DISABLED" then self:Hide(); return end
        if not self:IsMouseOver() and not InCombatLockdown() then self:Hide() end
    end)
    wheel:SetScript("OnHide", function() wheel.category = nil end)
    return wheel
end

local function Restep()
    wheel.under = false -- (Track paints it all again)
    if wheel.swap then wheel.swap:Stop(); wheel.swap:Play() end
    Track()
end

-- How many of a category's slots hold an emote.
local function Filled(key)
    local n = 0
    for i = 1, SLOTS do if Command(Emotes(key)[i]) then n = n + 1 end end
    return n
end

-- Step 1: the four categories.
function ShowCategories()
    local w = Build()
    w.category = nil
    w.spokes:SetTexture(ART .. "Spokes4")
    PlaceLabels(#CATEGORIES)
    local quick = EW:Quick()
    for i, c in ipairs(CATEGORIES) do
        local l = Slot(i)
        l.name:SetText(WallyHUD.Upper and WallyHUD.Upper(c[2]) or c[2]:upper())
        local first = c[1] == "quick" and quick[1] or nil
        l.sub:SetText(c[1] == "quick" and (first and ("top: " .. Label(first)) or "learned")
            or ("%d emotes"):format(Filled(c[1])))
    end
    Restep()
end

-- Step 2: a category's emotes (out of combat: secure attributes).
function ShowEmotes(key)
    if InCombatLockdown() then return end
    local w = Build()
    w.category = key
    w.spokes:SetTexture(ART .. "Spokes8")
    PlaceLabels(SLOTS)
    local list = Emotes(key)
    w.emotes = {}
    for i = 1, SLOTS do
        local token = list[i]
        local cmd = Command(token)
        local l = Slot(i)
        if cmd then
            w.emotes[i] = { token = token, cmd = cmd, label = Label(token) }
            l.name:SetText(Label(token))
            l.sub:SetText(cmd)
        else
            l.name:SetText("|cff606060-|r")
            l.sub:SetText("")
        end
    end
    Restep()
end

function EW:Toggle()
    if InCombatLockdown() then
        ns:Print("The emote wheel opens out of combat only.")
        return
    end
    local w = Build()
    if w:IsShown() then w:Hide(); return end
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    w:ClearAllPoints()
    w:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
    w:Show()
    ShowCategories()
    if w.open then w.open:Stop(); w.open:Play() end
end

-- The button the macro clicks (/click WallyHUDEmoteWheelToggle).
local function ToggleButton()
    if toggle then return toggle end
    toggle = CreateFrame("Button", TOGGLE, UIParent)
    toggle:Hide()
    toggle:SetScript("OnClick", function() EW:Toggle() end)
    return toggle
end

-- ---------------------------------------------------------------------------
-- The macro (account-wide)
-- ---------------------------------------------------------------------------

function EW:MacroBody() return MACRO_BODY end

-- The macro's index if it's there (account macros are 1..MAX_ACCOUNT_MACROS), or nil.
local function MacroIndex()
    local idx = GetMacroIndexByName and GetMacroIndexByName(MACRO_NAME) or 0
    return idx and idx > 0 and idx or nil
end

-- Creates the account macro, or updates it to this code. Returns its index, or nil and why not.
function EW:SaveMacro()
    if InCombatLockdown() then return nil, "Macros can't be changed in combat." end
    if not (CreateMacro and EditMacro and GetNumMacros) then return nil, "This client has no macro functions." end
    local idx = MacroIndex()
    local maxAccount = MAX_ACCOUNT_MACROS or 120
    if idx and idx <= maxAccount then
        EditMacro(idx, MACRO_NAME, MACRO_ICON, MACRO_BODY)
        return idx
    end
    local account = GetNumMacros()
    if (account or 0) >= maxAccount then return nil, "Your account macros are full (" .. maxAccount .. ")." end
    local ok, newIdx = pcall(CreateMacro, MACRO_NAME, MACRO_ICON, MACRO_BODY, nil)
    if not ok or not newIdx then return nil, "The game didn't create the macro." end
    return newIdx
end

-- Creates or updates the macro and puts it on your cursor, to drop on a bar.
function EW:PickUpMacro()
    local idx, why = self:SaveMacro()
    if not idx then ns:Print(why); return end
    if PickupMacro then PickupMacro(idx) end
end

function EW:MacroState()
    local idx = MacroIndex()
    if not idx then return "Not created yet." end
    if idx > (MAX_ACCOUNT_MACROS or 120) then return "A character macro named EmoteWheel is in the way: rename or delete it." end
    local _, _, body = GetMacroInfo(idx)
    if body and strtrim(body) == strtrim(MACRO_BODY) then return "Created (account macros, slot " .. idx .. ")." end
    return "Created, but its code differs: Create / update fixes it."
end

-- ---------------------------------------------------------------------------
-- Options > AddOns > WallyHUD > Emote Wheel: the categories, Quick, the macro
-- ---------------------------------------------------------------------------

local function Text(parent, template, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    if text then fs:SetText(text) end
    return fs
end

local function SimpleButton(parent, label, width, fn)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 160, 22)
    b:SetText(label)
    b:SetScript("OnClick", fn)
    return b
end

-- A slot's picker: a button showing the editing category's emote; it opens a menu of them all.
local function SlotPicker(parent, i, editing, refresh)
    local b = SimpleButton(parent, "", 150)
    b.Paint = function()
        local token = CategorySlots(editing())[i]
        b:SetText(("%d. %s"):format(i, Command(token) and Label(token) or "(empty)"))
    end
    b:SetScript("OnClick", function(self)
        if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
        local key = editing()
        MenuUtil.CreateContextMenu(self, function(_, root)
            root:CreateRadio("(empty)", function() return not Command(CategorySlots(key)[i]) end, function()
                CategorySlots(key)[i] = nil; refresh()
            end)
            for _, g in ipairs(EW:Choices()) do
                local sub = root:CreateButton(g[1])
                for _, c in ipairs(g[2]) do
                    sub:CreateRadio(c[2] .. "  |cff9d9d9d/" .. c[1]:lower() .. "|r", function() return CategorySlots(key)[i] == c[1] end, function()
                        CategorySlots(key)[i] = c[1]; refresh()
                    end)
                end
            end
        end)
    end)
    return b
end

local function BuildPage(frame)
    local title = Text(frame, "GameFontNormalLarge", "Emote Wheel")
    title:SetPoint("TOPLEFT", 16, -16)
    local about = Text(frame, "GameFontHighlightSmall",
        "A wheel around your cursor in two steps: pick a category (Fun, Social, Battle, or Quick at the bottom), then the emote. "
        .. "Quick learns the emotes you use most from the wheel. The account-wide macro EmoteWheel opens it: put it on a bar or bind its key. "
        .. "The middle or a right-click goes back; Escape, the macro again, or a click anywhere else closes it. It opens out of combat only.")
    about:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    about:SetWidth(560)
    about:SetWordWrap(true)

    local function Refresh() if frame.Paint then frame.Paint() end end
    local editingKey = "fun"
    local function Editing() return editingKey end

    -- Which category the slots below edit.
    local catLabel = Text(frame, "GameFontNormal", "Category")
    catLabel:SetPoint("TOPLEFT", about, "BOTTOMLEFT", 0, -14)
    frame.tabs = {}
    local prev
    for _, key in ipairs(EDITABLE) do
        local tab = SimpleButton(frame, CAT_NAME[key], 100, function() editingKey = key; Refresh() end)
        if prev then tab:SetPoint("LEFT", prev, "RIGHT", 6, 0) else tab:SetPoint("LEFT", catLabel, "RIGHT", 12, 0) end
        tab.key = key
        frame.tabs[#frame.tabs + 1] = tab
        prev = tab
    end

    frame.pickers = {}
    for i = 1, SLOTS do
        local p = SlotPicker(frame, i, Editing, Refresh)
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        p:SetPoint("TOPLEFT", catLabel, "BOTTOMLEFT", col * 170, -14 - row * 28)
        frame.pickers[i] = p
    end

    -- Quick: what it holds now, and a reset.
    local quickLabel = Text(frame, "GameFontNormal", "Quick (learned)")
    quickLabel:SetPoint("TOPLEFT", catLabel, "BOTTOMLEFT", 0, -14 - 4 * 28 - 10)
    local quickText = Text(frame, "GameFontHighlightSmall")
    quickText:SetPoint("TOPLEFT", quickLabel, "BOTTOMLEFT", 0, -6)
    quickText:SetWidth(560)
    quickText:SetWordWrap(true)
    local reset = SimpleButton(frame, "Forget usage", 120, function()
        if ns.db then ns.db.emoteUsage = {} end
        Refresh()
    end)
    reset:SetPoint("LEFT", quickLabel, "RIGHT", 12, 0)

    local codeLabel = Text(frame, "GameFontNormal", "The macro's code")
    codeLabel:SetPoint("TOPLEFT", quickText, "BOTTOMLEFT", 0, -16)
    local box = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    box:SetSize(340, 52)
    box:SetPoint("TOPLEFT", codeLabel, "BOTTOMLEFT", 0, -6)
    if box.SetBackdrop then
        box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        box:SetBackdropColor(0, 0, 0, 0.5)
        box:SetBackdropBorderColor(1, 1, 1, 0.14)
    end
    local code = CreateFrame("EditBox", nil, box)
    code:SetMultiLine(true)
    code:SetFontObject(ChatFontNormal)
    code:SetPoint("TOPLEFT", 8, -6)
    code:SetPoint("BOTTOMRIGHT", -8, 6)
    code:SetAutoFocus(false)
    code:SetText(MACRO_BODY)
    -- Read-only: whatever's typed, it goes back (select it and Ctrl+C to copy).
    code:SetScript("OnTextChanged", function(self, user) if user then self:SetText(MACRO_BODY) end end)
    code:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    code:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)

    local save = SimpleButton(frame, "Create / update macro", 180, function()
        local idx, why = EW:SaveMacro()
        ns:Print(idx and "The EmoteWheel macro is in your account macros." or why)
        Refresh()
    end)
    save:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -10)
    local pick = SimpleButton(frame, "Pick it up for a bar", 160, function() EW:PickUpMacro(); Refresh() end)
    pick:SetPoint("LEFT", save, "RIGHT", 8, 0)
    local try = SimpleButton(frame, "Try the wheel", 120, function() EW:Toggle() end)
    try:SetPoint("LEFT", pick, "RIGHT", 8, 0)
    local state = Text(frame, "GameFontHighlightSmall")
    state:SetPoint("TOPLEFT", save, "BOTTOMLEFT", 0, -8)

    frame.Paint = function()
        for _, tab in ipairs(frame.tabs) do
            local fs = tab:GetFontString()
            if fs then
                if tab.key == editingKey then fs:SetTextColor(1, 0.82, 0) else fs:SetTextColor(1, 1, 1) end
            end
        end
        for _, p in ipairs(frame.pickers) do p.Paint() end
        local quick, learned = EW:Quick()
        local names = {}
        for i, token in ipairs(quick) do names[i] = Label(token) end
        quickText:SetText(table.concat(names, ", ") .. "  |cff9d9d9d("
            .. (learned == 0 and "the starter set: nothing learned yet" or (math.min(learned, SLOTS) .. " learned from your use")) .. ")|r")
        state:SetText(EW:MacroState())
        if wheel and wheel:IsShown() and wheel.category and not InCombatLockdown() then ShowEmotes(wheel.category) end
    end
    frame.Paint()
end

function EW:AttachTo(page)
    page:Subpage({ name = "Emote Wheel", build = BuildPage, refresh = function(frame) if frame.Paint then frame.Paint() end end })
end

ns:On("PLAYER_LOGIN", function() ToggleButton() end)
