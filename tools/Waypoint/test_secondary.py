"""Waypoint's box of secondary tasks on the real Secondary.lua, with frames stubbed.

    python -I tools/Waypoint/test_secondary.py

Exit code 1 on any failure.
"""
import os
import site
import sys

sys.path.append(site.getusersitepackages())

import lupa.lua51 as L  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

CASES = r'''
local methods = {}
setmetatable(methods, { __index = function() return function() end end })
local meta = { __index = methods }
function methods:SetSize(w, h) rawset(self, "w", w); rawset(self, "h", h) end
function methods:SetWidth(w) rawset(self, "w", w) end
function methods:GetWidth() return rawget(self, "w") or 0 end
function methods:SetShown(on) rawset(self, "on", on) end
function methods:SetText(t) rawset(self, "t", t) end
function methods:GetStringWidth() return #(rawget(self, "t") or "") * 6 end
function methods:GetUnboundedStringWidth() return #(rawget(self, "t") or "") * 6 end
function methods:GetStringHeight()
    local per = math.max(1, math.floor((rawget(self, "w") or 0) / 6))
    local w = rawget(self, "w") or 0
    return 12 * (w > 0 and math.ceil(#(rawget(self, "t") or "") / per) or 1)
end
function methods:CreateFontString() return setmetatable({}, meta) end
function methods:CreateTexture() return setmetatable({}, meta) end
function CreateFrame() return setmetatable({}, meta) end
local arrow = CreateFrame(); arrow.w = 300
ns = { db = { secondaryOpen = true }, Arrow = { GetFrame = function() return arrow end, Dock = function(_, b) docked = b end } }
function ns:SetOption(path, v) self.db.secondaryOpen = v end
GameTooltip = CreateFrame()
'''


def main():
    lua = L.LuaRuntime(encoding="utf8", unpack_returned_tuples=True)
    lua.execute(CASES)
    src = open(os.path.join(ROOT, "addons", "Waypoint", "Secondary.lua"), encoding="utf8").read()
    lua.eval("function(s) loadstring(s, 'Secondary.lua')('Waypoint', ns) end")(src)
    report = lua.execute(r'''
    local out = {}
    local function Check(n, ok) out[#out + 1] = (ok and "ok   " or "FAIL ") .. n end
    local S = ns.Secondary
    Check("no box until there's a task", _G.WaypointSecondaryBuilt == nil)
    S:Set("FieldGuide", { { text = "Kill 8 Swoops" } })
    local box = docked
    Check("docked under the arrow", box ~= nil and box.on == true)
    Check("only as wide as it needs", box.w < 300 and box.w >= 120)
    S:Set("FieldGuide", { { text = string.rep("long ", 40) }, { text = "Short" } })
    Check("never wider than the arrow", box.w == 300)
    local tall = box.h
    Check("as tall as it needs", tall > 40)
    box.head.scripts = nil
    ns.db.secondaryOpen = false
    S:Layout()
    Check("folded: just the header", box.h == 18)
    ns.db.secondaryOpen = true
    S:Set("FieldGuide", nil)
    Check("gone with its tasks", box.on == false)
    S:Set("A", { { text = "one" } }); S:Set("B", { { text = "two" } })
    Check("every addon's list shows", box.head.text.t == "On the way (2)")
    return table.concat(out, "\n")
    ''')
    print(report)
    bad = report.count("FAIL")
    print("%d failed" % bad)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
