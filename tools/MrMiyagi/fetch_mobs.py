"""Mob data for MrMiyagi: every hostile creature of level 1-63 in the classic world
database, with its type, rank, immunities, the spells it uses and whether it flees,
plus what each of those spells does. Writes Data/Mobs.lua.

Sources:
  * CMaNGOS classic-db (github.com/cmangos/classic-db, Full_DB): creature_template,
    creature spawns (creature, creature_spawn_entry, spawn_group_entry), the spells
    a creature uses (creature_template_spells, creature_spell_list via
    creature_template.SpellList, creature_ai_scripts cast actions), EventAI "flee
    for assist" actions, and spell_template (the game's Spell.dbc for 1.12).
  * wago.tools DB2 exports: FactionTemplate (which factions are hostile) and
    SpellCastTimes (which spells have a cast time).

Downloads are cached in tools/MrMiyagi/.cache; the dump (and tables) already fetched by
tools/Spyglass/fetch_pulls.py are reused when they are there.

    python tools/MrMiyagi/fetch_mobs.py
"""
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "_shared"))
import fetcher as fetching  # noqa: E402  (cached downloads, through webfetch.py)
import luawrite  # noqa: E402
import sqldump  # noqa: E402
from sqldump import rows_of, sql_rows  # noqa: E402

ADDON = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "addons", "MrMiyagi")  # tools/MrMiyagi/ builds addons/MrMiyagi/
OUT = os.path.join(ADDON, "Data", "Mobs.lua")
CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".cache")
# Caches of sibling tools with the same file naming, read only.
EXTRA_CACHES = [os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Spyglass", ".wowhead_cache")]
MAX_LEVEL = 63

TYPES = {1: "Beast", 2: "Dragonkin", 3: "Demon", 4: "Elemental", 5: "Giant", 6: "Undead",
         7: "Humanoid", 8: "Critter", 9: "Mechanical", 10: "Not specified", 11: "Totem",
         12: "Non-combat Pet", 13: "Gas Cloud"}
SKIP_TYPES = {8, 11, 12, 13}

# Spell.dbc values (1.12).
E_HEAL, E_KNOCKBACK, E_APPLY_AURA = 10, 98, 6
E_SUMMON = {28, 40, 41, 42, 43, 44, 56, 73, 74, 75, 76, 87, 88, 89, 90, 93, 97, 112}
A_FEAR, A_STUN, A_ROOT, A_SILENCE, A_SNARE = 7, 12, 26, 27, 33
A_PERIODIC_DAMAGE = {3, 53, 64, 89}
A_PERIODIC_HEAL = 8
M_FEAR, M_ROOT, M_SILENCE, M_SNARE, M_STUN, M_KNOCKOUT = 5, 7, 9, 11, 12, 14
D_MAGIC, D_CURSE, D_DISEASE, D_POISON, D_ENRAGE = 1, 2, 3, 4, 9
# Implicit targets that mean "self or a friend": a magic aura on these is a buff.
FRIENDLY_TARGETS = {1, 5, 20, 21, 24, 27, 30, 31, 32, 33, 35, 37, 41, 42, 43, 44, 45, 46, 57, 61}


# ---------------------------------------------------------------------------
# Downloads (cached; tools/_shared/fetcher.py) and the SQL dump (tools/_shared/sqldump.py)
# ---------------------------------------------------------------------------

def Fetcher():
    """This tool's cache, then Spyglass's (read only); 0.5 s rest after each download."""
    return fetching.Fetcher(CACHE, extra_caches=EXTRA_CACHES, pace=0, rest=0.5, timeout=300, attempts=5,
                            min_backoff=0.25, give_up_after=1, give_up="Download keeps failing: {url}",
                            skip_empty=True, ok_only=True, flush=True)


def table(fetcher, name):
    return fetching.wago_table(fetcher, name)


# ---------------------------------------------------------------------------

def hostile_factions(fetcher):
    """Faction templates players can fight: hostile or neutral, i.e. not friendly to players
    and not aligned with the Alliance or the Horde (city guards and the like). Many
    hostile mobs (wolves: "Prey") are hostile only through their faction's default
    reputation, so friendliness is what is tested, not the enemy masks."""
    out = set()
    for r in table(fetcher, "FactionTemplate"):
        group, friend = int(r["FactionGroup"]), int(r["FriendGroup"])
        if group & 7 or friend & 7:
            continue
        out.add(int(r["ID"]))
    return out


def keep(t, hostile):
    if not (1 <= t["MinLevel"] <= MAX_LEVEL) or t["MaxLevel"] > MAX_LEVEL + 10:
        return False
    if t["CreatureType"] in SKIP_TYPES or t["NpcFlags"]:
        return False  # critters, totems, pets, gas clouds; vendors, trainers, gossip
    if t["UnitFlags"] & 0x02000000 or t["ExtraFlags"] & 0x80:
        return False  # not selectable, invisible triggers
    if re.search(r"trigger|\bDND\b|\[|invisible|stalker|dummy|\bzz|\btest\b|\(old\)", t["Name"], re.I):
        return False
    return t["Faction"] in hostile


def spell_flags(s, cast_ms):
    effects = [s["Effect%d" % i] for i in (1, 2, 3)]
    auras = [s["EffectApplyAuraName%d" % i] for i in (1, 2, 3)]
    mechs = {s["Mechanic"]} | {s["EffectMechanic%d" % i] for i in (1, 2, 3)}
    targets = {s["EffectImplicitTargetA%d" % i] for i in (1, 2, 3) if s["Effect%d" % i]}
    name = s["SpellName"] or ""
    f = []
    if E_HEAL in effects or A_PERIODIC_HEAL in auras:
        f.append("h")
    if E_SUMMON & set(effects):
        f.append("s")
    if s["Dispel"] == D_ENRAGE or re.search(r"\b(enrage|frenzy)\b", name, re.I):
        f.append("e")
    if re.search(r"\bflee", name, re.I):
        f.append("f")
    if cast_ms.get(s["CastingTimeIndex"], 0) > 0:
        f.append("c")
    if A_PERIODIC_DAMAGE & set(auras):
        f.append("d")
    if s["Dispel"] == D_POISON:
        f.append("p")
    if s["Dispel"] == D_DISEASE:
        f.append("D")
    if s["Dispel"] == D_CURSE:
        f.append("C")
    if s["Dispel"] == D_MAGIC and any(a for a in auras) and targets and not targets <= FRIENDLY_TARGETS:
        f.append("m")
    if M_ROOT in mechs or A_ROOT in auras:
        f.append("r")
    if M_SNARE in mechs or A_SNARE in auras:
        f.append("n")
    if M_FEAR in mechs or A_FEAR in auras:
        f.append("F")
    if M_STUN in mechs or M_KNOCKOUT in mechs or A_STUN in auras:
        f.append("S")
    if M_SILENCE in mechs or A_SILENCE in auras:
        f.append("x")
    if E_KNOCKBACK in effects:
        f.append("k")
    return "".join(f)


def lua_str(s):
    return luawrite.lua_str(s, lf="space", cr="keep")


def main():
    fetcher = Fetcher()
    text = sqldump.cmangos(fetcher)
    print("dump read")
    hostile = hostile_factions(fetcher)
    cast_ms = {int(r["ID"]): int(r["Base"]) for r in table(fetcher, "SpellCastTimes")}

    templates = {t["Entry"]: t for t in rows_of(text, "creature_template")}

    # Creatures that exist in the world: spawned, drawn into a spawn, or summoned.
    used = {r[1] for r in sql_rows(text, "creature") if r[1]}
    used |= {r[1] for r in sql_rows(text, "creature_spawn_entry")}
    used |= {r[1] for r in sql_rows(text, "spawn_group_entry")}
    ai = rows_of(text, "creature_ai_scripts")
    for r in ai:
        for k in (1, 2, 3):
            if r["action%d_type" % k] == 12:  # ACTION_T_SUMMON
                used.add(r["action%d_param1" % k])
    spell_rows = {s["Id"]: s for s in rows_of(text, "spell_template")}
    for s in spell_rows.values():
        for k in (1, 2, 3):
            if s["Effect%d" % k] in E_SUMMON and s["EffectMiscValue%d" % k]:
                used.add(s["EffectMiscValue%d" % k])

    # Spells each creature uses.
    spells_of = {}
    for r in sql_rows(text, "creature_template_spells"):
        spells_of.setdefault(r[0], []).extend(x for x in r[2:] if x)
    lists = {}
    for r in rows_of(text, "creature_spell_list"):
        lists.setdefault(r["Id"], []).append(r["SpellId"])
    for e, t in templates.items():
        if t.get("SpellList") and t["SpellList"] in lists:
            spells_of.setdefault(e, []).extend(lists[t["SpellList"]])
    flee = set()
    for r in ai:
        for k in (1, 2, 3):
            kind = r["action%d_type" % k]
            if kind == 11 and r["action%d_param1" % k]:  # ACTION_T_CAST
                spells_of.setdefault(r["creature_id"], []).append(r["action%d_param1" % k])
            elif kind == 25:  # ACTION_T_FLEE_FOR_ASSIST
                flee.add(r["creature_id"])

    npcs, spells, skipped_unused = {}, {}, 0
    for e, t in templates.items():
        if not keep(t, hostile):
            continue
        if e not in used:
            skipped_unused += 1
            continue
        ids = []
        for sid in spells_of.get(e, []):
            if sid in spell_rows and sid not in ids:
                ids.append(sid)
                spells[sid] = spell_rows[sid]
        npcs[e] = (t, ids, e in flee)

    L = [
        "local _, ns = ...",
        "-- Generated by tools/MrMiyagi/fetch_mobs.py from the CMaNGOS classic world database. Do not edit.",
        "-- npcs[entry] = { name, minLevel, maxLevel, type, rank (0 normal, 1 elite, 2 rare elite, 3 boss, 4 rare),",
        "--   mech = MechanicImmuneMask, school = SchoolImmuneMask, spells = { ids }, flee = true }",
        "-- spells[id] = { name, schoolMask, flags }: h heal, s summon, e enrage, f flee, c cast time, d periodic damage,",
        "--   p poison, D disease, C curse, m magic debuff, r root, n snare, F fear, S stun, x silence, k knockback",
        "ns.Mobs = {",
        "  npcs = {",
    ]
    for e in sorted(npcs):
        t, ids, fl = npcs[e]
        extra = ""
        if t["MechanicImmuneMask"]:
            extra += ", mech = %d" % t["MechanicImmuneMask"]
        if t["SchoolImmuneMask"]:
            extra += ", school = %d" % t["SchoolImmuneMask"]
        if ids:
            extra += ", spells = { %s }" % ", ".join(str(i) for i in ids)
        if fl:
            extra += ", flee = true"
        L.append("    [%d] = { %s, %d, %d, %d, %d%s }," % (e, lua_str(t["Name"]), t["MinLevel"], t["MaxLevel"],
                                                        t["CreatureType"], t["Rank"], extra))
    L += ["  },", "  spells = {"]
    for sid in sorted(spells):
        s = spells[sid]
        L.append("    [%d] = { %s, %d, %s }," % (sid, lua_str(s["SpellName"] or ""), 1 << s["School"],
                                               lua_str(spell_flags(s, cast_ms))))
    L += ["  },", "  types = {"]
    L += ["    [%d] = %s," % (k, lua_str(v)) for k, v in sorted(TYPES.items())]
    L += ["  },", "}", ""]
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(L))
    print("wrote Data/Mobs.lua: %d npcs (%d with spells, %d flee), %d spells, %.2f MB; %d hostile templates never spawned"
          % (len(npcs), sum(1 for v in npcs.values() if v[1]), sum(1 for v in npcs.values() if v[2]),
             len(spells), os.path.getsize(OUT) / 1048576.0, skipped_unused))
    return 0


if __name__ == "__main__":
    sys.exit(main())
