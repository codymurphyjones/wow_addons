"""SaddleBags' Bottom Dock on the real Core.lua and Panel.lua, with frames stubbed.

    python -I tools/SaddleBags/test_dock.py

Exit code 1 on any failure.
"""
import os
import site
import sys

sys.path.append(site.getusersitepackages())

import lupa.lua51 as L  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ADDON = os.path.join(ROOT, "addons", "SaddleBags")

STUBS = r'''
SaddleBagsGameFontNormalSmall, SaddleBagsGameFontHighlightSmall = {}, {}
MOUSE, COMBAT, EDITING = nil, false, true
local methods = {}
local meta = { __index = methods }
local function Noop() end
methods.wallyPanel, methods.wallyTab = false, false
setmetatable(methods, { __index = function() return Noop end })
function methods:GetName() return self.name end
function methods:SetSize(w, h) self.w, self.h = w, h end
function methods:SetWidth(w) self.w = w end
function methods:SetHeight(h) self.h = h end
function methods:GetWidth() return rawget(self, "w") or 100 end
function methods:GetHeight() return rawget(self, "h") or 50 end
function methods:GetParent() return rawget(self, "parent") end
function methods:SetParent(p) self.parent = p end
function methods:GetFrameLevel() return 1 end
function methods:GetFrameStrata() return "MEDIUM" end
function methods:SetPoint(a, b, c, d, e) local t = rawget(self, "pts") or {}; rawset(self, "pts", t); t[#t + 1] = { a, b, c, d, e } end
function methods:ClearAllPoints() self.pts = {} end
function methods:GetPoint(i) local p = (rawget(self, "pts") or {})[i or 1]; if p then return p[1], p[2], p[3], p[4], p[5] end end
function methods:GetNumPoints() return #(rawget(self, "pts") or {}) end
function methods:Show() self.hidden = false end
function methods:Hide() self.hidden = true end
function methods:SetShown(on) self.hidden = not on end
function methods:IsShown() return not rawget(self, "hidden") end
function methods:IsVisible() return not rawget(self, "hidden") end
function methods:IsMouseOver() return MOUSE == self end
function methods:IsForbidden() return false end
function methods:IsProtected() return rawget(self, "protected") end
function methods:IsClampedToScreen() return false end
function methods:GetChildren() end
function methods:SetAlpha(a) self.alpha = a end
function methods:SetNormalTexture(t) self.art = t end
function methods:GetDisabledTexture() return setmetatable({}, meta) end
function methods:GetNormalTexture() return nil end
function methods:GetPushedTexture() return nil end
function methods:GetHighlightTexture() return nil end
function methods:GetLeft() return 10 end
function methods:GetRight() return 110 end
function methods:GetTop() return 200 end
function methods:GetBottom() return 150 end
function methods:GetEffectiveScale() return 1 end
function methods:GetStringWidth() return 30 end
function methods:CreateFontString() return setmetatable({}, meta) end
function methods:CreateTexture() return setmetatable({}, meta) end
function methods:StartMoving() end
function methods:StopMovingOrSizing() end
function CreateFrame(_, name, parent)
    local f = setmetatable({ name = name, parent = parent }, meta)
    if name then _G[name] = f end
    return f
end
UIParent = CreateFrame("Frame", "UIParent")
UIParent.w, UIParent.h = 1920, 1080
WorldFrame = CreateFrame("Frame")
GameTooltip = CreateFrame("Frame")
GameTooltip_Hide = function() end
C_Timer = { After = function(_, fn) fn() end, NewTicker = function() return { Cancel = function() end } end }
function InCombatLockdown() return COMBAT end
function hooksecurefunc() end
function issecurevariable() return false end
function CopyTable(t) local c = {}; for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end; return c end
strtrim = function(s) return s end
function geterrorhandler() return error end
function print() end
SlashCmdList = {}
StaticPopupDialogs = {}
function NewMod()
    local ns = {}
    function ns:On() end
    function ns:Changed() end
    function ns:Migrate(_, fn) fn(self.db) end
    function ns:OnLoad() end
    function ns:OnChanged() end
    function ns:IsEditing() return EDITING end
    return ns
end
'''

CASES = r'''
local TS = ...
function TS:IsEditing() return EDITING end
function TS:StopPicker() end
local out = {}
local function Check(n, ok) out[#out + 1] = (ok and "ok   " or "FAIL ") .. n end
local sd = { id = 1, name = "S", point = { "CENTER", "CENTER", 0, 0 }, rightToLeft = false, activeTab = 1, tabCount = 2, tabs = {}, dockOpen = false }
TS.db = { saddles = { sd }, released = {}, nextId = 2 }
TS.ready = true
TS:EnsureTabs(sd)
local s = TS:CreateSaddle(sd)
local p = s.panel
local dock, toggle = p.dock, p.dockToggle
local function Parked() return select(2, dock:GetPoint(1)) == UIParent end

Check("starts closed, plus", Parked() and toggle.art:find("Plus") ~= nil)
s:ToggleDock()
Check("plus opens an empty section", not Parked() and dock.w == 140 and toggle.art:find("Minus") ~= nil)

local win = CreateFrame("Frame", "Win", UIParent); win:SetSize(300, 120); win:SetPoint("CENTER")
MOUSE = dock
local ok = s:Dock(win)
Check("drop captures it", ok and TS.captured[win] and TS.captured[win].tab == TS.DOCK)
Check("sized to the window", dock.w == 308 and dock.h == 128)
do
    local a, rel, b, _, y = dock:GetPoint(1)
    Check("anchored to the Saddle's bottom edge", a == "TOPLEFT" and rel == p and b == "BOTTOMLEFT" and y == 1)
    local _, under, corner = toggle:GetPoint(1)
    Check("toggle at the dock's bottom right", under == dock and corner == "BOTTOMRIGHT")
end
Check("parented into the dock", win:GetParent() == s.tabFrames[TS.DOCK].content)
Check("FindTab sees it", select(2, TS:FindTab("Win")) == TS.DOCK)

win.hidden = false
s:ToggleDock()
Check("minus hides it by parking", Parked() and dock.alpha == 0)
Check("the window itself is never hidden", win:IsShown() and dock:IsShown())
s:ToggleDock()
Check("plus shows it", not Parked() and dock.alpha == 1 and dock.w == 308)

EDITING = false
s:UpdateEditState()
Check("toggle stays outside editing", toggle:IsShown())
Check("no overlay outside editing, so the window keeps its clicks", dock.overlay.hidden)
s:ToggleDock()
Check("still toggles outside editing", Parked())
s:ToggleDock()
EDITING = true
s:UpdateEditState()

local other = CreateFrame("Frame", "Other", UIParent); other:SetSize(200, 90); other:SetPoint("CENTER")
s:Dock(other)
Check("a new drop swaps it", not TS.captured[win] and TS.captured[other] and dock.w == 208)
Check("holds one window", #sd.tabs[TS.DOCK].frames == 1)

TS:Capture(s, 1, other, false)
Check("dragged to a tab leaves the dock", #sd.tabs[TS.DOCK].frames == 0 and TS.captured[other].tab == 1)
s:Dock(other)
Check("and back again", #sd.tabs[1].frames == 0)

dock.overlay:GetScript("OnMouseUp")(dock.overlay, "LeftButton")
Check("left click does nothing", TS.captured[other] ~= nil)
dock.overlay:GetScript("OnMouseUp")(dock.overlay, "RightButton")
Check("right click removes it", not TS.captured[other] and s:DockName() == nil and dock.w == 140)

EDITING = false
s:UpdateEditState()
Check("empty dock is out of sight outside editing", Parked() and toggle.hidden)
EDITING = true
s:UpdateEditState()

win:SetSize(300, 120); s:Dock(win)
COMBAT = true; win.protected = true; dock.protected = true
s:ToggleDock()
Check("protected: waits for combat", s.pendingDock == true and sd.dockOpen == true)
COMBAT = false; dock.protected = false
s:ToggleDock(); s.pendingDock = nil
Check("then toggles", sd.dockOpen == false)

sd.rightToLeft = true; s:ToggleDock()
Check("right to left: pinned to the right edge", dock:GetPoint(1) == "TOPRIGHT")

-- The wheel, while a tab scrolls, and windows that cap their own height.
local inner = CreateFrame("Frame"); inner.wheel = true
function inner:IsMouseWheelEnabled() return self.wheel end
function inner:EnableMouseWheel(on) self.wheel = on end
function inner:IsClampedToScreen() return false end
local tall = CreateFrame("Frame", "Tall", UIParent); tall:SetSize(200, 90); tall:SetPoint("CENTER")
tall.wheel = false
function tall:IsMouseWheelEnabled() return false end
tall.GetChildren = function() return inner end
local children = TS.ClampTargets
TS.ClampTargets = function(f) if f == tall then return { tall, inner } end return children(f) end
TS:Capture(s, 1, tall, false)
s:TakeWheel(1, true)
Check("a scrolling tab takes the wheel", inner.wheel == false)
s:TakeWheel(1, false)
Check("and gives it back", inner.wheel == true)
s:TakeWheel(1, true)
TS:Detach(tall)
Check("leaving gives it back too", inner.wheel == true)
Questie = { db = { profile = { TrackerHeight = 0 } } }
local qf = CreateFrame("Frame", "Questie_BaseFrame", UIParent); qf:SetSize(200, 90); qf:SetPoint("CENTER")
TS:Capture(s, 1, qf, false)
Check("Questie's tracker drops its limit in a tab", Questie.db.profile.TrackerHeight == 100000)
TS:Detach(qf)
Check("and gets your height back", Questie.db.profile.TrackerHeight == 0 and TS.db.questieHeight == nil)
return table.concat(out, "\n")
'''


def main():
    lua = L.LuaRuntime(encoding="utf8", unpack_returned_tuples=True)
    lua.execute(STUBS)
    # Frames' GetScript for the test: keep what SetScript sets.
    lua.execute('''
    do
        local any = getmetatable(CreateFrame("Frame")).__index
        function any:SetScript(n, fn) local t = rawget(self, "scripts") or {}; rawset(self, "scripts", t); t[n] = fn end
        function any:GetScript(n) local t = rawget(self, "scripts"); return t and t[n] end
    end''')
    make = lua.eval("function() return NewMod() end")
    ts = make()
    run = lua.eval("function(src, n, ts) local f, e = loadstring(src, n); if not f then error(e) end; f('SaddleBags', ts) end")
    for name in ("Core.lua", "Panel.lua"):
        run(open(os.path.join(ADDON, name), encoding="utf8").read(), name, ts)
    text = lua.eval("function(c, ts) return loadstring(c)(ts) end")(CASES, ts)
    print(text)
    bad = text.count("FAIL")
    print("%d failed" % bad)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
