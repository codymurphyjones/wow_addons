-- A small stand-in for the WoW client, enough to load Modified and drive the Bloom (Veil.lua,
-- Lens.lua) from smoke.py. Frames remember points, sizes, scripts and visibility; the API
-- functions return a fixed little world (a priest with a few spells, one friendly target).
-- Unknown globals are reported by smoke.py, not invented, so a typo still fails loudly.

local mock = { now = 100, cursor = { 0, 0 }, keys = {}, mouse = {}, focus = nil, prints = {}, macros = {},
    reloads = 0, frames = {}, unit = { target = "friend" } }
MOCK = mock

bit = {
    band = function(a, b) return a & b end,
    bor = function(a, b) return a | b end,
    bxor = function(a, b) return a ~ b end,
    bnot = function(a) return ~a end,
}
unpack = table.unpack
math.atan2 = math.atan -- Lua 5.1 (WoW) still has atan2
strfind, strlower, strsub, strupper = string.find, string.lower, string.sub, string.upper
tinsert, tremove = table.insert, table.remove
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function geterrorhandler() return function(e) error(e, 0) end end
function print(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end mock.prints[#mock.prints + 1] = table.concat(t, " ") end
UISpecialFrames = {}
NUM_BAG_SLOTS = 4
MAX_CHARACTER_MACROS = 18
SlashCmdList = {}

-------------------------------------------------------------------------------- regions

local Region = {}
Region.__index = function(self, k)
    local v = rawget(Region, k)
    if v ~= nil then return v end
    if type(k) ~= "string" or not k:match("^%u") then return nil end -- fields the addon sets on frames
    error("mock: no method " .. tostring(k) .. " on " .. tostring(rawget(self, "_type")), 2)
end

local function New(kind, parent, name)
    local r = setmetatable({ _type = kind, _parent = parent, _shown = true, _w = 0, _h = 0, _points = {},
        _scripts = {}, _alpha = 1, _level = parent and (parent._level or 0) + 1 or 0, _text = "" }, Region)
    if name then _G[name] = r; r._name = name end
    mock.frames[#mock.frames + 1] = r
    return r
end
mock.New = New

local function noop() end
for _, m in ipairs({ "SetTexCoord", "SetBlendMode", "SetDesaturated",
    "SetDrawLayer", "AddMaskTexture", "SetJustifyV", "SetWordWrap", "SetShadowColor",
    "SetFontObject", "SetFrameStrata", "SetToplevel", "SetClampedToScreen", "SetMovable", "RegisterForDrag",
    "RegisterForClicks", "SetAutoFocus", "SetLooping", "SetFromAlpha", "SetToAlpha", "SetDuration", "SetSmoothing",
    "SetStartDelay", "SetNormalFontObject", "SetHighlightFontObject", "SetDisabledFontObject", "SetHighlightTexture",
    "SetNormalTexture", "SetPushedTexture", "SetDisabledTexture", "SetScrollChild", "SetVerticalScroll", "SetChecked",
    "SetEnabled", "StartMoving", "StopMovingOrSizing", "SetPropagateKeyboardInput", "EnableKeyboard", "SetMaxLetters",
    "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "SetID", "SetMultiLine", "SetTextInsets" }) do
    Region[m] = noop
end

function Region:GetObjectType() return self._type end
function Region:SetTexture(t) self._tex = t end
function Region:SetColorTexture(r, g, b, a) self._tex = "color"; self._color = { r, g, b }; self._calpha = a end
function Region:SetVertexColor(r, g, b) self._color = { r, g, b } end
function Region:GetName() return self._name end
function Region:IsForbidden() return false end
function Region:Show() self._shown = true; local s = self._scripts.OnShow; if s then s(self) end end
function Region:Hide()
    local was = self._shown
    self._shown = false
    if was and self._scripts.OnHide then self._scripts.OnHide(self) end
end
function Region:SetShown(v) if v then self:Show() else self:Hide() end end
function Region:IsShown() return self._shown end
function Region:IsVisible()
    local r = self
    while r do
        if not r._shown then return false end
        r = r._parent
    end
    return true
end
function Region:SetSize(w, h) self._w, self._h = w, h end
function Region:SetWidth(w) self._w = w end
function Region:SetHeight(h) self._h = h end
function Region:GetWidth() if self._all then return self._all:GetWidth() end return self._w end
function Region:GetHeight() if self._all then return self._all:GetHeight() end return self._h end
function Region:SetAlpha(a) self._alpha = a end
function Region:GetAlpha() return self._alpha end
function Region:SetPoint(point, rel, relPoint, x, y)
    if type(rel) == "number" then rel, relPoint, x, y = nil, nil, rel, relPoint end
    self._points[point] = { rel = rel, relPoint = relPoint or point, x = x or 0, y = y or 0 }
    self._anchor = self._points[point]
    self._anchorPoint = point
end
function Region:ClearAllPoints() self._points = {}; self._anchor = nil end
function Region:SetAllPoints(rel) self._all = rel or self._parent end
function Region:GetPoint() local a = self._anchor; if a then return self._anchorPoint, a.rel, a.relPoint, a.x, a.y end end
function Region:GetEffectiveScale()
    local scale, r = 1, self
    while r do
        scale = scale * (r._scale or 1)
        r = r._parent
    end
    return scale
end
function Region:GetScale() return self._scale or 1 end
function Region:SetScale(v) self._scale = v end
-- Where each anchor point sits, as a fraction of the size from the centre.
local OFF = { CENTER = { 0, 0 }, TOP = { 0, 0.5 }, BOTTOM = { 0, -0.5 }, LEFT = { -0.5, 0 }, RIGHT = { 0.5, 0 },
    TOPLEFT = { -0.5, 0.5 }, TOPRIGHT = { 0.5, 0.5 }, BOTTOMLEFT = { -0.5, -0.5 }, BOTTOMRIGHT = { 0.5, -0.5 } }

-- Size in screen pixels (a font string measures its text).
function Region:ScreenSize()
    if self._all then return self._all:ScreenSize() end
    local scale = self:GetEffectiveScale()
    local w, h = self._w, self._h
    if self._type == "FontString" then
        if (w or 0) == 0 then w = self:GetStringWidth() end
        h = self:GetStringHeight()
    end
    return (w or 0) * scale, (h or 0) * scale
end

-- Centre in screen pixels: the anchor point of this region sits at the anchor point of the
-- region it's attached to, plus the offset (in this region's own, scaled, units).
function Region:ScreenCenter()
    if self._center then return self._center[1], self._center[2] end
    if self._all then return self._all:ScreenCenter() end
    local a = self._anchor
    if not a then
        if self._parent then return self._parent:ScreenCenter() end
        return 0, 0
    end
    local rel = a.rel or self._parent
    local rx, ry, rw, rh = 0, 0, 0, 0
    if rel then
        rx, ry = rel:ScreenCenter()
        rw, rh = rel:ScreenSize()
    end
    local ro, so = OFF[a.relPoint] or OFF.CENTER, OFF[self._anchorPoint] or OFF.CENTER
    local scale = self:GetEffectiveScale()
    local sw, sh = self:ScreenSize()
    return rx + ro[1] * rw + a.x * scale - so[1] * sw, ry + ro[2] * rh + a.y * scale - so[2] * sh
end
function Region:GetLeft() local x = self:ScreenCenter(); local w = self:ScreenSize(); return (x - w / 2) / self:GetEffectiveScale() end
function Region:GetBottom() local _, y = self:ScreenCenter(); local _, h = self:ScreenSize(); return (y - h / 2) / self:GetEffectiveScale() end
-- Like the client: in the region's own units.
function Region:GetCenter()
    local x, y = self:ScreenCenter()
    local scale = self:GetEffectiveScale()
    return x / scale, y / scale
end
function Region:IsMouseOver()
    local x, y = self:ScreenCenter()
    local scale = self:GetEffectiveScale()
    return math.abs(mock.cursor[1] - x) <= self._w * scale / 2 and math.abs(mock.cursor[2] - y) <= self._h * scale / 2
end
function Region:SetScript(name, fn) self._scripts[name] = fn end
function Region:GetScript(name) return self._scripts[name] end
function Region:HookScript(name, fn) local old = self._scripts[name]; self._scripts[name] = function(...) if old then old(...) end fn(...) end end
function Region:SetFrameLevel(l) self._level = l end
function Region:GetFrameLevel() return self._level end
function Region:EnableMouse(v) self._mouse = v end
function Region:EnableMouseWheel(v) self._wheel = v end
function Region:RegisterEvent(e) mock.events = mock.events or {}; mock.events[e] = mock.events[e] or {}; table.insert(mock.events[e], self) end
function Region:UnregisterEvent() end
function Region:SetText(t)
    self._text = t == nil and "" or tostring(t)
    -- Like the client: an edit box's OnTextChanged runs for SetText too (userInput false).
    if self._type == "EditBox" and self._scripts.OnTextChanged then self._scripts.OnTextChanged(self, false) end
end
function Region:GetText() return self._text end
function Region:GetStringWidth() local longest = 0 for line in (self._text .. "\n"):gmatch("(.-)\n") do longest = math.max(longest, #line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end return longest * 6 end
function Region:SetJustifyH(j) self._justify = j end
function Region:SetShadowOffset(x, y) self._bold = (x == 1 and y == 0) end
function Region:SetTextColor(r, g, b) self._color = { r, g, b } end
-- Lines times 15, counting word wrap when the width is set (about 6 pixels a letter).
function Region:GetStringHeight()
    if self._text == "" then return 0 end
    local n = 0
    for line in (self._text .. "\n"):gmatch("(.-)\n") do
        local plain = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T[^|]*|t", "oo ")
        n = n + ((self._w or 0) > 0 and math.max(1, math.ceil(#plain * 6 / self._w)) or 1)
    end
    return n * 15
end
function Region:SetSpacing() end
function Region:SetFormattedText(f, ...) self._text = f:format(...) end
function Region:SetAttribute(k, v) self._attr = self._attr or {}; self._attr[k] = v end
function Region:GetAttribute(k) return self._attr and self._attr[k] end
function Region:SetFocus() mock.focus = self end
function Region:ClearFocus() if mock.focus == self then mock.focus = nil end end
function Region:HasFocus() return mock.focus == self end
function Region:SetMask() end
function Region:IsPlaying() return self._playing end
function Region:Play() self._playing = true end
function Region:Stop() self._playing = false end
function Region:SetMouseClickEnabled() end

function Region:CreateTexture(name, layer) return New("Texture", self, name) end
function Region:CreateMaskTexture() return New("MaskTexture", self) end
function Region:CreateFontString(name, layer, font) return New("FontString", self, name) end
function Region:CreateLine() return New("Line", self) end
function Region:CreateAnimationGroup() return New("AnimationGroup", self) end
function Region:CreateAnimation(kind) return New("Animation", self) end

UIParent = New("Frame", nil, "UIParent")
local SW, SH = (MOCK_SCREEN or {})[1] or 1920, (MOCK_SCREEN or {})[2] or 1080
mock.W, mock.H = SW, SH
UIParent._w, UIParent._h = SW, SH
UIParent._center = { SW / 2, SH / 2 }

function CreateFrame(kind, name, parent, template)
    local f = New(kind, parent, name)
    if kind == "EditBox" then f._mouse = true end
    return f
end
function CreateFont(name) local f = New("Font", nil, name); f.CopyFontObject = noop; return f end

-- Frames: our own, plus twelve "action buttons" of Action Bar 1 along the bottom.
for i = 1, 12 do
    local b = CreateFrame("CheckButton", "ActionButton" .. i, UIParent)
    b._w, b._h = 45, 45
    b._center = { SW / 2 - 270 + (i - 1) * 49, 40 }
    b.action = i
end
function EnumerateFrames(after)
    local list = mock.frames
    local start = 1
    if after then
        for i, f in ipairs(list) do if f == after then start = i + 1 end end
    end
    for i = start, #list do
        local f = list[i]
        if f._type == "Frame" or f._type == "Button" or f._type == "CheckButton" or f._type == "EditBox" then return f end
    end
end

-------------------------------------------------------------------------------- game state

local SPELLS = {
    [2061] = { "Flash Heal", 135907, true }, [139] = { "Renew", 135953, true }, [17] = { "Power Word: Shield", 135940, true },
    [585] = { "Smite", 135924, false }, [589] = { "Shadow Word: Pain", 136207, false }, [2006] = { "Resurrection", 135955, true },
}
local ORDER = { 2061, 139, 17, 585, 589, 2006 }
local NAME_TO_ID = {}
for id, s in pairs(SPELLS) do NAME_TO_ID[s[1]] = id end

C_Spell = {
    GetSpellInfo = function(spell)
        local id = type(spell) == "number" and spell or NAME_TO_ID[spell]
        local s = id and SPELLS[id]
        if s then return { name = s[1], iconID = s[2], spellID = id } end
    end,
    GetSpellName = function(id) return SPELLS[id] and SPELLS[id][1] end,
    IsSpellHelpful = function(id) return SPELLS[id] and SPELLS[id][3] end,
    IsSpellHarmful = function(id) return SPELLS[id] and not SPELLS[id][3] end,
    IsSpellPassive = function() return false end,
    GetSpellSubtext = function() return nil end,
    PickupSpell = function(id) MOCK.cursorItem = { "spell", id } end,
}
Enum = { SpellBookSpellBank = { Player = 0 }, SpellBookItemType = { Spell = 1 } }
C_SpellBook = {
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #ORDER } end,
    GetSpellBookItemInfo = function(slot) local id = ORDER[slot]; return { spellID = id, name = SPELLS[id][1], iconID = SPELLS[id][2], itemType = 1, isPassive = false } end,
    IsSpellKnown = function() return true end,
}
C_Item = {
    GetItemNameByID = function(id) return id == 5512 and "Healthstone" or nil end,
    GetItemIconByID = function() return 135230 end,
    GetItemSpell = function(id) return id == 5512 and "Healthstone" or nil end,
    PickupItem = noop,
}
C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end,
    GetContainerItemID = function(bag, slot) return slot == 1 and 5512 or nil end,
}
C_Timer = { After = function(_, fn) mock.timers = mock.timers or {}; table.insert(mock.timers, fn) end,
    NewTimer = function(_, fn) return { Cancel = noop } end }
C_AddOns = { GetAddOnMetadata = function() return "test" end }

local ACTIONS = {}
for i = 1, 12 do ACTIONS[i] = { "spell", ORDER[(i - 1) % #ORDER + 1] } end
function GetActionInfo(slot) local a = ACTIONS[slot]; if a then return a[1], a[2] end end
function GetActionTexture(slot) local a = ACTIONS[slot]; if a and a[1] == "spell" then return SPELLS[a[2]][2] end if a and a[1] == "macro" then return 134400 end end
function GetActionText(slot) local a = ACTIONS[slot]; if a and a[1] == "macro" then return a[3] end end
function HasAction(slot) return ACTIONS[slot] ~= nil end
function PlaceAction(slot) local c = mock.cursorItem; if c then ACTIONS[slot] = c end end
function PickupAction(slot) ACTIONS[slot] = nil end
function ClearCursor() mock.cursorItem = nil end
function GetCursorInfo() if mock.cursorItem then return mock.cursorItem[1] end end
function PickupMacro(index) local m = mock.macros[index]; mock.cursorItem = { "macro", index, m.name } end

function GetNumMacros() return 0, #mock.macros end
function GetMacroIndexByName(name) for i, m in ipairs(mock.macros) do if m.name == name then return i end end return 0 end
function GetMacroBody(i) return mock.macros[i] and mock.macros[i].body end
function CreateMacro(name, icon, body) table.insert(mock.macros, { name = name, body = body }) end
function EditMacro(i, name, icon, body) mock.macros[i].body = body end
function DeleteMacro(i) table.remove(mock.macros, i) end

function GetTime() return mock.now end
function GetCursorPosition() return mock.cursor[1], mock.cursor[2] end
function InCombatLockdown() return mock.combat or false end
function IsShiftKeyDown() return mock.keys.shift or false end
function IsControlKeyDown() return mock.keys.ctrl or false end
function IsAltKeyDown() return mock.keys.alt or false end
function IsMouseButtonDown(b) return mock.mouse[b] or false end
function GetCurrentKeyBoardFocus() return mock.focus end
function ReloadUI() mock.reloads = mock.reloads + 1 end
function UnitExists(u) return u == "player" or mock.unit[u] ~= nil end
function UnitCanAssist(_, u) return u == "player" or mock.unit[u] == "friend" end
function UnitCanAttack(_, u) return mock.unit[u] == "enemy" end
function UnitIsDeadOrGhost(u) return mock.unit[u] == "dead" end
-- A secret: comparing or testing it the wrong way errors, like in the client.
mock.SECRET = setmetatable({}, { __lt = function() error("attempt to compare a secret value") end,
    __le = function() error("attempt to compare a secret value") end })
function issecretvalue(v) return v == mock.SECRET end
-- Your real setup: a frame tied to a secret health bar reports a secret width, and Bartender4's
-- buttons (LibActionButton) keep their slot in _state_action rather than .action.
do
    local hp = CreateFrame("Button", "WallyHUDHealthClick", UIParent)
    hp.GetWidth = function() return mock.SECRET end
    local lab = CreateFrame("CheckButton", "BT4Button13", UIParent)
    lab._w, lab._h = 36, 36
    lab._center = { SW / 2, 120 }
    lab._state_type, lab._state_action = "action", 13
end
GameTooltip = New("Frame", nil, "GameTooltip")
for _, m in ipairs({ "SetOwner", "SetSpellByID", "SetItemByID", "SetAction", "AddLine", "IsOwned" }) do GameTooltip[m] = noop end

-- Fire an event at every frame that registered it.
function mock.Fire(event, ...)
    for _, f in ipairs(mock.events and mock.events[event] or {}) do
        local s = f._scripts.OnEvent
        if s then s(f, event, ...) end
    end
end
function mock.RunTimers()
    local t = mock.timers or {}
    mock.timers = {}
    for _, fn in ipairs(t) do fn() end
end

-- Every visible texture and font string with its screen rectangle, for smoke.py's renderer.
function mock.Dump()
    local out = {}
    for _, r in ipairs(mock.frames) do
        if (r._type == "Texture" or r._type == "FontString") and r:IsVisible() then
            local a, p = r._alpha, r._parent
            while p do a = a * (p._alpha or 1); p = p._parent end
            if r._calpha then a = a * r._calpha end
            if a > 0.01 and not (r._all and r._tex ~= "color") then
                local x, y = r:ScreenCenter()
                local w, h = r:ScreenSize()
                local c = r._color or { 1, 1, 1 }
                out[#out + 1] = { kind = r._type, x = x, y = y, w = w, h = h, tex = tostring(r._tex or ""),
                    r = c[1], g = c[2], b = c[3], a = a, text = r._text, justify = r._justify or "CENTER", bold = r._bold }
            end
        end
    end
    return out
end
