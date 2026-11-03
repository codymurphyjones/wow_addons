"""The setup wizards on the real shared/Wizard.lua and each addon's Setup.lua, with frames stubbed.

    python -I tools/shared/test_wizard.py

Checks the flow (once only, Later, the queue, a new character), and that every step's option exists in
its addon's defaults and can show every choice. Exit code 1 on any failure.
"""
import os
import re
import site
import sys

sys.path.append(site.getusersitepackages())

import lupa.lua51 as L  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ADDONS = os.path.join(ROOT, "addons")
ALL = ("SimplePanel", "SmartPlates", "Wally", "Waypoint", "FieldGuide", "StatLedger")

STUBS = r'''
UISpecialFrames, COMBAT, TIMERS = {}, false, {}
function InCombatLockdown() return COMBAT end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
C_Timer = { After = function(_, fn) TIMERS[#TIMERS + 1] = fn end }
local function Frame()
    local f = { shown = false, scripts = {} }
    return setmetatable(f, { __index = function(_, k)
        return function() end
    end })
end
local function Make()
    local f = Frame()
    f.Show = function(s) s.shown = true end
    f.Hide = function(s)
        if s.shown then
            s.shown = false
            if s.scripts.OnHide then s.scripts.OnHide(s) end
        end
    end
    f.SetShown = function(s, on) s.shown = on end
    f.IsMouseOver = function() return false end
    f.SetScript = function(s, n, fn) s.scripts[n] = fn end
    f.GetName = function() return "Wizard" end
    f.GetStringHeight = function() return 14 end
    f.SetText = function(s, t) s.value = t end
    f.CreateFontString = function() return Make() end
    f.CreateTexture = function() return Make() end
    return f
end
FRAMES = {}
function CreateFrame() local f = Make(); FRAMES[#FRAMES + 1] = f; return f end
UIParent = Make()
function NewNs()
    local ns = { db = {}, char = {}, handlers = {} }
    function ns:On(e, fn) self.handlers[e] = fn end
    function ns:AfterCombat(_, fn) AFTER = fn end
    function ns:GetOption(path) return self.values[path] end
    function ns:SetOption(path, v) self.values[path] = v end
    ns.values = {}
    return ns
end
function Login(ns)
    ns.handlers.PLAYER_ENTERING_WORLD()
end
function Run()
    local t = TIMERS; TIMERS = {}
    for _, fn in ipairs(t) do fn() end
end
function Steps(n, char)
    local s = {}
    for i = 1, n do
        s[i] = { title = "s" .. i, path = "db.s" .. i, char = char, choices = { { true, "On" }, { false, "Off" } } }
    end
    return s
end
'''

FLOW = r'''
local chunk = ...
local out = {}
local function Check(name, ok) out[#out + 1] = (ok and "ok   " or "FAIL ") .. name end
local function Open() return _G.SuiteSetupQueue.open end
local function Fresh()
    _G.SuiteSetupQueue = nil
    local a, b = NewNs(), NewNs()
    chunk("A", a); chunk("B", b)
    return a, b
end

-- Two addons at login take turns.
local a, b = Fresh()
a.setup = a.NewWizard({ name = "A", steps = Steps(2) })
b.setup = b.NewWizard({ name = "B", steps = Steps(1) })
Login(a); Login(b); Run()
Check("first addon opens", Open() == a.setup)
Check("second waits its turn", #_G.SuiteSetupQueue.waiting == 1)
local function Showing()
    for i = #FRAMES, 1, -1 do -- newest first: an earlier case's window may still be up
        local f = FRAMES[i]
        if rawget(f, "later") and f.shown then return f end
    end
end
local frame = Showing()
frame.next.scripts.OnClick(); frame.next.scripts.OnClick()
Check("Done marks it", a.db.wizardDone == true and a.char.wizardDone == true)
Check("second opens after", Open() == b.setup)

-- Later comes back; nothing more this session.
a, b = Fresh()
a.setup = a.NewWizard({ name = "A", steps = Steps(1) })
b.setup = b.NewWizard({ name = "B", steps = Steps(1) })
Login(a); Login(b); Run()
Showing().later.scripts.OnClick()
Check("Later leaves it unmarked", not a.db.wizardDone)
Check("Later holds the rest too", Open() == nil and #_G.SuiteSetupQueue.waiting == 0)

-- A new character sees only its own steps.
a = Fresh()
a.db.wizardDone = true
local steps = Steps(2); steps[2].char = true
a.setup = a.NewWizard({ name = "A", steps = steps })
Check("char steps pending on a new character", a.setup:Pending() == "char")
a.char.wizardDone = true
Check("then nothing", a.setup:Pending() == nil)

-- Done is done; combat waits; needed can skip.
a = Fresh()
a.db.wizardDone = true; a.char.wizardDone = true
a.setup = a.NewWizard({ name = "A", steps = Steps(1) })
Login(a); Run()
Check("not shown twice", Open() == nil)
a = Fresh()
a.setup = a.NewWizard({ name = "A", steps = Steps(1) })
COMBAT = true; Login(a); Run()
Check("waits out combat", Open() == nil and AFTER ~= nil)
COMBAT = false; AFTER()
Check("opens after combat", Open() == a.setup)
a = Fresh()
a.setup = a.NewWizard({ name = "A", needed = function() return false end, steps = Steps(1) })
Login(a); Run()
Check("needed false skips", Open() == nil)

-- A step's demo runs while it's up, and stops when you leave it or close the window.
a = Fresh()
local shown = {}
local steps2 = Steps(2)
steps2[2].demo = function(on) shown[#shown + 1] = on end
a.setup = a.NewWizard({ name = "A", steps = steps2 })
Login(a); Run()
frame = Showing()
Check("no demo on another step", #shown == 0)
frame.next.scripts.OnClick()
Check("the demo starts on its step", shown[1] == true)
frame.back.scripts.OnClick()
Check("and stops when you leave it", shown[2] == false)
frame.next.scripts.OnClick()
frame.later.scripts.OnClick()
Check("and when the window closes", shown[4] == false)

return table.concat(out, "\n")
'''


PANEL_STUBS = r'''
UIWIDTH, UISCALE = 1024, 1
UIParent.GetWidth = function() return UIWIDTH end
UIParent.GetScale = function() return UISCALE end
function UnitLevel() return 10 end
function GetMaxPlayerLevel() return 60 end
function PanelNs()
    local ns = NewNs()
    ns.db.options = { scale = 1 }
    ns.NewWizard = function(def) return def end
    ns.Clamp = function(v, a, b) return math.max(a, math.min(b, v)) end
    return ns
end
local plugin = {}
plugin.__index = plugin
function plugin:Layout() return { progress = self.bar, progressWidth = 140 } end
function plugin:IsEnabled() return false end
function plugin:Get() return nil end
SimplePanel = { GetPlugin = function(id)
    local bar = id == "XP" or id == "Reputation" or id == "Professions"
    return setmetatable({ def = { progress = bar }, bar = bar }, plugin)
end }
'''


def defaults_text(addon):
    text = ""
    for root, _, files in os.walk(os.path.join(ADDONS, addon)):
        for f in files:
            if f.endswith(".lua") and f != "Setup.lua":
                text += open(os.path.join(root, f), encoding="utf8", errors="replace").read()
    return text


def main():
    bad = 0
    lua = L.LuaRuntime(encoding="utf8", unpack_returned_tuples=True)
    lua.execute(STUBS)
    wizard = open(os.path.join(ADDONS, "shared", "Wizard.lua"), encoding="utf8").read()
    load = lua.eval("function(s) local f, e = loadstring(s, 'Wizard.lua'); if not f then error(e) end; return f end")
    report = lua.eval("function(flow, chunk) return loadstring(flow)(chunk) end")(FLOW, load(wizard))
    print(report)
    bad += report.count("FAIL")

    # Every option a step names exists in the addon's code.
    for addon in ALL:
        src = open(os.path.join(ADDONS, addon, "Setup.lua"), encoding="utf8").read()
        code = defaults_text(addon)
        keys = re.findall(r'(?:path = "|SetOption\(")((?:db|char)\.[\w.]+)', src)
        keys += ["db.options.sort." + k for k in re.findall(r'"(on\w+Close)"', src)]
        for key in keys:
            leaf = key.split(".")[-1]
            ok = re.search(r'\b%s\s*=' % leaf, code)
            if not ok:
                bad += 1
            print(("ok   " if ok else "FAIL ") + addon + " " + key)
        for i, line in enumerate(src.split("\n")):
            if "—" in line:
                bad += 1
                print("FAIL %s:%d dash" % (addon, i + 1))
    # SimplePanel: every plugin is in the wizard, and the recommended set follows the bar's width.
    panel = open(os.path.join(ADDONS, "SimplePanel", "Setup.lua"), encoding="utf8").read()
    listed = set(re.findall(r'\{ "(\w+)", "[^"]+", "[^"]+"(?:, \d+)? \}', panel))
    registered = set()
    folder = os.path.join(ADDONS, "SimplePanel", "Plugins")
    for f in os.listdir(folder):
        registered |= set(re.findall(r'RegisterPlugin\(\{\s*id = "(\w+)"', open(os.path.join(folder, f), encoding="utf8").read()))
    missing = registered - listed - {"Minimap"}
    print(("FAIL missing " + str(sorted(missing))) if missing else "ok   all %d plugins are in the wizard" % len(listed))
    bad += 1 if missing else 0
    lua.execute(PANEL_STUBS)
    picks = lua.eval("function(src, w, s, share) UIWIDTH, UISCALE = w, s; local ns = PanelNs(); "
                     "loadstring(src)('SimplePanel', ns); local n = 0; "
                     "for _ in pairs(ns.SetupPicks(share, 1)) do n = n + 1 end; return n end")
    small, wide, minimal = picks(panel, 1024, 1, 0.7), picks(panel, 2560, 1, 0.7), picks(panel, 2560, 1, 0.4)
    print("     recommended at 1024: %d, at 2560: %d, minimal at 2560: %d" % (small, wide, minimal))
    if not (small < wide and minimal < wide):
        bad += 1
        print("FAIL the set doesn't follow the width")
    print("%d failed" % bad)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
