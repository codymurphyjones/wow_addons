"""The ways across the ground the navigation bake can't see, because they move or teleport you:
lifts, portals and the Deeprun Tram (tools/Waypoint/.nav/links.json, for nav_stitch.py).

    python -I tools/Waypoint/nav_links.py

  lifts   every lift (gameobject type 11) on a world map, from the CMaNGOS world database, with how
          far it travels and how long its round trip takes (TransportAnimation, wago.tools): its
          bottom and top, both ways, a round trip each (half of it waiting, half riding)
  portals the area triggers that move you within a world map (areatrigger_teleport, its trigger's
          place from AreaTrigger): one way each, LOAD seconds
  tram    the Deeprun Tram between Stormwind and Ironforge: in at one end's trigger, out where the
          other end's trigger puts you, TRAM seconds (the ride, waiting and two loading screens)
A link: { map, kind, name, a: [north, west, height], b: [...], secs, both } in world yards.
"""
import gzip
import json
import os
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(TOOLS, "_shared"))
import build_water as bw  # noqa: E402
import sqldump  # noqa: E402
import fetcher as fetching  # noqa: E402

OUT = os.path.join(HERE, ".nav", "links.json")
MAPS = set(bw.MAPS)
LOAD = 5          # seconds a loading screen takes
TRAM = 120        # Stormwind to Ironforge by tram: in, wait, ride, out
LIFT_MIN = 10     # yards a lift travels at least (less: a moving gate)
# Triggers no player reaches (test teleporters left in the world): never a way.
SKIP_TRIGGERS = ("Gnomeregan", "Leap of Faith")
TRAM_ENDS = [(2173, 2166, "Deeprun Tram to Ironforge"), (2175, 2171, "Deeprun Tram to Stormwind")]
DUMP_CACHE = os.path.join(TOOLS, "Spyglass", ".wowhead_cache")   # where the dump is cached already


def world_db():
    web = fetching.Fetcher(DUMP_CACHE, pace=0)
    return sqldump.cmangos(web)


def main():
    from casc import Casc
    build = Casc.open().version
    text = world_db()
    templates = {int(g["entry"]): g for g in sqldump.rows_of(text, "gameobject_template")}
    anim = defaultdict(list)
    for r in bw.wago_table("TransportAnimation", build):
        anim[int(r["TransportID"])].append((int(r["TimeIndex"]), float(r["Pos_2"])))
    links = []
    for s in sqldump.rows_of(text, "gameobject"):
        g = templates.get(int(s["id"]))
        if not g or str(g["type"]) != "11" or int(s["map"]) not in MAPS:
            continue
        frames = sorted(anim.get(int(s["id"]), []))
        if not frames:
            continue
        dz = [z for _, z in frames]
        lo, hi = min(dz), max(dz)
        if hi - lo < LIFT_MIN:
            continue                                  # a gate or door that moves, not a lift
        n, w, z = float(s["position_x"]), float(s["position_y"]), float(s["position_z"])
        period = frames[-1][0] / 1000.0
        links.append({"map": int(s["map"]), "kind": "lift", "name": g["name"], "a": [n, w, z + lo], "b": [n, w, z + hi],
                      "secs": round(period, 1), "both": True})
    triggers = {int(r["ID"]): r for r in bw.wago_table("AreaTrigger", build)}
    tele = {int(r[0]): r for r in sqldump.sql_rows(text, "areatrigger_teleport")}
    for tid, row in tele.items():
        trig = triggers.get(tid)
        if not trig or int(trig["ContinentID"]) not in MAPS or int(row[6]) != int(trig["ContinentID"]):
            continue
        if any(word in (row[1] or "") for word in SKIP_TRIGGERS):
            continue
        links.append({"map": int(trig["ContinentID"]), "kind": "portal", "name": row[1],
                      "a": [float(trig["Pos_0"]), float(trig["Pos_1"]), float(trig["Pos_2"])],
                      "b": [float(row[7]), float(row[8]), float(row[9])], "secs": LOAD, "both": False})
    for into, out, name in TRAM_ENDS:
        trig, dest = triggers.get(into), tele.get(out)
        if trig and dest:
            links.append({"map": int(trig["ContinentID"]), "kind": "tram", "name": name,
                          "a": [float(trig["Pos_0"]), float(trig["Pos_1"]), float(trig["Pos_2"])],
                          "b": [float(dest[7]), float(dest[8]), float(dest[9])], "secs": TRAM, "both": False})
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(links, f, indent=1)
    by = defaultdict(int)
    for l in links:
        by[l["kind"]] += 1
    print("%d links (%s) -> %s" % (len(links), ", ".join("%d %ss" % (v, k) for k, v in sorted(by.items())), OUT))
    for l in links:
        print("  %d %-6s %-40s %.0f s" % (l["map"], l["kind"], l["name"], l["secs"]))


if __name__ == "__main__":
    main()
