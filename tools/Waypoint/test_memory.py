"""Waypoint's memory on the real data and the real search, in Lua 5.1 as in the game.

    python -I tools/Waypoint/test_memory.py

A walk across Ashenvale on the way to Zoram'gar: what stays in memory while nothing's searching, that
clearing it changes no route, and that the worst case keeps under its ceiling. Exit code 1 on a failure.
"""
import base64
import os
import site
import sys
import time
import zlib

sys.path.append(site.getusersitepackages())

import lupa.lua51 as L  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ADDON = os.path.join(ROOT, "addons", "Waypoint")
CEILING_MB = 90  # the most Waypoint's ground data may hold at rest, tiles at their limit


def main():
    lua = L.LuaRuntime(encoding="latin-1", unpack_returned_tuples=True)
    g = lua.globals()
    g.PyDecode = lambda s: base64.b64decode(s).decode("latin-1")
    g.PyInflate = lambda s: zlib.decompress(s.encode("latin-1")).decode("latin-1")
    g.PyClock = lambda: time.perf_counter() * 1000
    lua.execute('''
    Enum = { CompressionMethod = { Zlib = 1 } }
    C_EncodingUtil = { DecodeBase64 = function(s) return PyDecode(s) end, DecompressString = function(s) return PyInflate(s) end }
    debugprofilestop = PyClock
    function GetTime() return PyClock() / 1000 end
    ns = { db = {}, char = {}, ZoneLevels = {} }
    HERE = 1
    ns.Nav = { Player = function() return HERE end }
    function UnitFactionGroup() return "Horde" end
    local FRAME = {}
    FRAME.__index = function(t, k) local v = rawget(FRAME, k); if v ~= nil then return v end; return function() end end
    DRIVERS = {}
    function FRAME:SetScript(k, fn) if k == "OnUpdate" then DRIVERS[#DRIVERS + 1] = { self, fn } end end
    function CreateFrame() return setmetatable({}, FRAME) end
    C_Timer = { After = function(_, fn) fn() end, NewTicker = function() end }
    function InCombatLockdown() return false end
    function UnitLevel() return 20 end
    function geterrorhandler() return function(e) print("ERROR", e) end end
    function ns:On() end
    function ns:Print() end
    function MB() collectgarbage("collect"); collectgarbage("collect"); return collectgarbage("count") / 1024 end
    OPTS = { speed = 7, swim = 4.72, safe = false, maxDrop = 8, climb = 1, offroad = 1, slack = 150 }
    function Walk(key, c, n, w, gn, gw)
        local o = { goal = { gn, gw } }
        for k, v in pairs(OPTS) do o[k] = v end
        local G, f = ns.Grid, nil
        for _ = 1, 40000 do
            f = G:Field(key, c, n, w, o)
            if f then return f end
            for _, d in ipairs(DRIVERS) do d[2](d[1], 0.03) end
        end
    end
    ''')
    run = lua.eval("function(s, n) local f, e = loadstring(s, n); if not f then error(e) end; f('Waypoint', ns) end")
    for name in ("Data/Transports.lua", "Data/Transit.lua", "Data/Water.lua", "Data/Roads.lua", "Grid.lua",
                 "Data/Nav0.lua", "Data/Nav1.lua", "Data/ZoneWays.lua", "Data/Spots.lua", "NavGrid.lua"):
        run(open(os.path.join(ADDON, name), encoding="utf8").read(), name)
    failed = []

    def check(label, good):
        print("%s %s" % ("ok  " if good else "FAIL", label), flush=True)
        if not good:
            failed.append(label)

    start, goal = (2300.0, -1500.0), (3331.0, 1025.0)
    lua.execute("F = Walk('here', 1, %f, %f, %f, %f)" % (start + goal))
    check("the walk has a field", lua.eval("F ~= nil"))
    full = lua.eval("MB()")
    # Far ahead on the walk: a tile the field has worked out, so a cost and a path can be asked of it.
    ask = (start[0] + 400, start[1] + 500)
    lua.execute("""
    local n, w = %f, %f
    COST = ns.Grid:Cost(F, n, w)
    local p = ns.Grid:Path(F, n, w)
    NODES = p and #p or 0
    """ % ask)
    lua.execute("ns.Grid:Tidy()")
    rest = lua.eval("MB()")
    print("     after the search %.1f MB, cleared %.1f MB" % (full, rest))
    check("clearing frees the links", rest < full - 15)
    lua.execute("""
    local n, w = %f, %f
    COST2 = ns.Grid:Cost(F, n, w)
    local p = ns.Grid:Path(F, n, w)
    NODES2 = p and #p or 0
    """ % ask)
    print("     cost %s, %s points; after clearing %s, %s" % (lua.eval("COST"), lua.eval("NODES"), lua.eval("COST2"), lua.eval("NODES2")))
    check("a cost is the same after clearing", lua.eval("COST == COST2 and COST ~= nil"))
    check("so is a path", lua.eval("NODES == NODES2 and NODES > 0"))
    # The worst at rest: fields and every tile the limit allows, all over Ashenvale.
    for i in range(1, 25):
        n, w = start[0] + (goal[0] - start[0]) * i / 24, start[1] + (goal[1] - start[1]) * i / 24
        lua.execute("Walk('here', 1, %f, %f, %f, %f)" % (n, w, goal[0], goal[1]))
    lua.execute("""
    local D, seen = ns.Grid.navDebug, 0
    local m = D.Map(1)
    for r = 0, 63 do for c = 0, 63 do
        local t = r * 64 + c
        if m.d.tiles[t] and seen < 200 then seen = seen + 1; D.TileOf = nil; D.Where(m, t * 65536 + 1) end
    end end
    ns.Grid:Tidy()
    TILES = m.count
    """)
    most = lua.eval("MB()")
    print("     tiles at their limit: %s tiles, %.1f MB" % (lua.eval("TILES"), most))
    check("the worst at rest is under %d MB" % CEILING_MB, most < CEILING_MB)
    # Leaving: the continent goes.
    lua.execute("""
    ns.Grid:Forget("here")
    HERE = 0
    ns.Grid:Tidy()
    """)
    left = lua.eval("MB()")
    print("     after leaving the continent %.1f MB" % left)
    check("a continent you've left is let go", left < most - 25)
    print("%d failed" % len(failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
