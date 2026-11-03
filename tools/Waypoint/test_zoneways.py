"""Waypoint's stored zone to zone walks on the real ZoneWays.lua and Data/ZoneWays.lua.

    python -I tools/Waypoint/test_zoneways.py

Thunder Bluff to Zoram'gar (the trip that had no route), a short trip, and each road mode. Exit code 1 on
any failure.
"""
import base64
import os
import re
import site
import sys
import zlib

sys.path.append(site.getusersitepackages())

import lupa.lua51 as L  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ADDON = os.path.join(ROOT, "addons", "Waypoint")


def main():
    lua = L.LuaRuntime(encoding="latin-1", unpack_returned_tuples=True)
    g = lua.globals()
    g.PyDecode = lambda s: base64.b64decode(s).decode("latin-1")
    g.PyInflate = lambda s: zlib.decompress(s.encode("latin-1")).decode("latin-1")
    tiles = {}
    for mapid in (0, 1):
        src = open(os.path.join(ADDON, "Data", "Nav%d.lua" % mapid), encoding="utf-8").read()
        part = src[src.index("zoneOf = {"):src.index("}, areas = {")]
        tiles[mapid] = {int(t): zlib.decompress(base64.b64decode(v)) for t, v in re.findall(r'\[(\d+)\] = "([^"]+)"', part)}

    def zone_at(c, n, w):
        """The same sum as NavGrid.lua's G:ZoneAt, on the real table."""
        tile_yards = 1600 / 3
        fine, top = tile_yards / 64, 32 * tile_yards
        gr, gc = int((top - n) // fine), int((top - w) // fine)
        raw = tiles[int(c)].get((gr // 64) * 64 + gc // 64)
        return raw[(gr % 64) // 4 * 16 + (gc % 64) // 4] if raw else 0
    g.PyZone = zone_at
    lua.execute('''
    Enum = { CompressionMethod = { Zlib = 1 } }
    C_EncodingUtil = { DecodeBase64 = function(s) return PyDecode(s) end,
        DecompressString = function(s) return PyInflate(s) end }
    ns = {}
    ''')
    run = lua.eval("function(s, n) local f, e = loadstring(s, n); if not f then error(e) end; f('Waypoint', ns) end")
    for name in ("Data/ZoneWays.lua", "ZoneWays.lua"):
        run(open(os.path.join(ADDON, name), encoding="utf8").read(), name)
    report = lua.execute('''
    local out = {}
    local function Check(n, ok) out[#out + 1] = (ok and "ok   " or "FAIL ") .. n end
    local Z = ns.ZoneWays
    local function Length(w, n0, w0)
        local d, pn, pw = 0, n0, w0
        for i = 1, #w do
            d = d + math.sqrt((w[i].n - pn) ^ 2 + (w[i].w - pw) ^ 2)
            pn, pw = w[i].n, w[i].w
        end
        return d
    end
    function Z.ZoneAt(c, n, w) return PyZone(c, n, w) end
    -- Heights by hand: up on Thunder Bluff, down everywhere else.
    Z.HeightAt = function(c, n, w)
        if math.sqrt((n + 1199) ^ 2 + (w - 27) ^ 2) < 400 then return 135 end
        return 0
    end
    local start = os.clock()
    local way = Z:Way(1, -1199, 27, 1, 3331, 1025, "balanced")
    local secs = os.clock() - start
    Check("Thunder Bluff to Zoram'gar has a walk", way ~= nil)
    if way then
        local d = Length(way, -1199, 27)
        out[#out + 1] = ("     %d points, %d yards, %.0f ms first time"):format(#way, d, secs * 1000)
        Check("it ends at the target", way[#way].n == 3331 and way[#way].w == 1025)
        Check("it's longer than the straight line", d > 4600)
        Check("and no longer than twice it", d < 9300)
        -- Its first stop is one of your own zone's exits, not the nearest one on the map.
        local first = math.sqrt((way[1].n + 1199) ^ 2 + (way[1].w - 27) ^ 2)
        out[#out + 1] = ("     first stop %d yards from you"):format(first)
        Check("it leaves by your own zone's exit", first < 600)
        Check("from up there the way starts at a lift", way[1].lift == true)
        local back = Z:Way(1, 3331, 1025, 1, -1199, 27, "balanced")
        Check("to up there the way ends by a lift", back and back[#back - 1].lift == true)
        Check("with the target last", back and back[#back].n == -1199)
        start = os.clock()
        Z:Way(1, -1199, 27, 1, 3331, 1025, "balanced")
        out[#out + 1] = ("     %.0f ms after that"):format((os.clock() - start) * 1000)
        local gap = 0
        for i = 2, #way do
            gap = math.max(gap, math.sqrt((way[i].n - way[i-1].n) ^ 2 + (way[i].w - way[i-1].w) ^ 2))
        end
        out[#out + 1] = ("     longest straight stretch %d yards"):format(gap)
    end
    Check("a short trip isn't one", Z:Way(1, 0, 0, 1, 500, 500, "balanced") == nil)
    Check("another continent isn't one", Z:Way(1, 0, 0, 0, 500, 500, "balanced") == nil)
    for _, mode in ipairs({ "safe", "speed" }) do
        Check(mode .. " has its own walk", Z:Way(1, -1199, 27, 1, 3331, 1025, mode) ~= nil)
    end
    -- A dock and a flight master are stops of their own.
    local dock = Z:Way(1, -1199, 27, 1, 1677.6, -4315.7, "balanced")
    Check("Thunder Bluff to Orgrimmar's flight master has a walk", dock ~= nil)
    local secs = Z:Secs(1, -1199, 27, 3331, 1025, "balanced")
    Check("the plan can ask how long", secs and secs > 600)
    start = os.clock()
    for i = 1, 200 do Z:Secs(1, -1199, 27, 3331 + i, 1025, "balanced") end
    out[#out + 1] = ("     200 asks from one spot: %.0f ms"):format((os.clock() - start) * 1000)
    local e = Z:Way(0, -8900, -100, 0, 1500, 300, "balanced")
    if e then out[#out + 1] = ("     Northshire to Tirisfal area: %d points, %d yards"):format(#e, Length(e, -8900, -100)) end
    Check("the Eastern Kingdoms too", e ~= nil)
    return table.concat(out, "\\n")
    ''')
    print(report)
    bad = report.count("FAIL")
    print("%d failed" % bad)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
