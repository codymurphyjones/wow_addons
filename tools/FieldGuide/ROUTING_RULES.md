# Field Guide routing rules

What makes a hand-made leveling guide fast, turned into rules for Field Guide's planner. The source is a read-through of RestedXP's WoW Forever guides (`RXPGuides\Guides\forever\`, third-party, kept only as a reference; none of its code or text is used here). Line refs point at those files as evidence only.

Two things hold for every rule:

- **One measure.** A rule changes how Field Guide's XP-a-minute measure is worked out (`Engine.lua` `QuestRate`, `Tasks.lua` `Score`). It never adds a zone, race or level exception, and it works from wherever you press Play.
- **Quests first.** The aim is a fun, managed playthrough, not the fastest possible leveling. A rule that keeps you questing beats one that buys a few minutes by grinding. Grinding only fills a real gap.

Death as travel (RXP's "deathskip") is left out on purpose: Forever has a resurrection penalty, and RXP has turned off about a third of its own death skips.

Status: **built**, **partly** (some of it is already in the planner), **later** (written down, not built).

---

## 1. Take a hub's quests before you leave it (partly)

**The habit.** Arriving at a town, RXP takes every quest it will do in the next loop before walking out. Each hand-in is paired with the follow-up from the same person. Examples: Sen'jin Village (`Horde-01-12_Durotar.lua:1127-1148`), Westfall's arrival (`Alliance-11-20.lua:71-143`).

**As a measure.** A pick-up beside one you're already taking costs nearly no walk, so its rate should count only the detour, not a trip of its own.

**Field Guide now.** `E.Gather` takes everything within 75 yd on the first visit (`Engine.lua:2099-2150`). `Tuck` moves each pick-up to where it adds the least walk (`Engine.lua:1947-2053`). `Block` groups quests picked up along a transition quest's trip (`Tasks.lua:180-236`).

**Gap.** Little. Area choice (`Score`) still charges each quest's walk to its giver on its own, even when givers share a spot.

## 2. Kill for several quests in one sweep (built)

**The habit.** One step lists the objectives of 3-4 quests that share mobs or ground, and it stays open in the background while other steps run (`Horde-01-12_Durotar.lua:423-438`, `Alliance-11-20.lua:162-170`).

**Field Guide now.** Hunting areas: objectives on the same spawns share an area and are done in one visit, and the "on the way" box lists quests along the walk (README "Hunting areas"). Task areas group objectives across zone borders (`task_areas.py`).

## 3. Travel the quickest way: hearthstone, flights, mount (built)

**The habit.** RXP moves the hearthstone to the next hub, goes out on a long trip, and hearths back to hand in. Before hearthing it checks the cooldown, and flies or walks if the hearthstone isn't ready (`Alliance-11-20.lua:469-481`, `Horde-12-22_Barrens.lua:1885-1903`). Flight paths are picked up as it passes them, so later trips can fly (`Alliance-1-13_Human.lua:2503`). Hearthstone moves: Brill, then Undercity (`Horde-01-14_Undead.lua:914, 2301, 2897`); Auberdine around the Loch Modan trip (`Alliance-11-20.lua:869` to `3609`).

**As a measure.** A trip costs its quickest way, not the walk. The time from A to B is the least of:

- walking, at your travel speed (your mount's once you've ridden one);
- the hearthstone, when it's ready (or will be before the walk would end): cast and load, then the walk from where it's set;
- a flight: walk to a flight point you can use, the flight, then the walk from where it lands.

The hearthstone is used once per plan: after one chosen trip uses it, it's on cooldown for the rest of that plan. This is what makes "go far, hearth back to the town with your hand-ins" score right, with no rule about towns.

**Field Guide now.** Built:

- `Engine.lua` `TravelMinutes`;
- the planner's area choice and detours (`Tasks.lua` `Score`, `Detour`, `Choose`);
- `QuestRate`.

The timing data comes from Waypoint (`Waypoint:TravelSpeed`, `Hearth`, `FlightPoints`, `FlightSeconds` in `addons/Waypoint/API.lua`), so the plan times trips the same way the arrow takes them.

**Later.** Two pieces are not built yet:

- The step order inside a plan (`Delay`, `Engine.lua:1743-1751`) still weighs walked yards. The arrow takes the hearthstone and flights live, so in game this only affects which order is picked.
- Suggesting where to set the hearthstone (RXP moves it 3-4 times a guide). This needs the plan to know where it will come back to most.

## 4. Drop a quest when it stops paying (built)

**The habit.** Steps carry level caps: a quest is skipped once you're past the point where it's worth doing (`.maxlevel`, e.g. `Horde-12-22_Barrens.lua:124, 2566`). A whole zone's opening is skipped if you arrive over-levelled (`Alliance-11-20.lua:22`).

**Field Guide now.** `Worth` (1.5% of your level, `Engine.lua:149-153`), `LastLevel` and `Urgency` (`Tasks.lua:44-68`): a quest weighs more as its last paying level nears, then drops out.

## 5. Leave an area when somewhere else pays better (built)

**The habit.** RXP leaves each zone once its easy first tier is done. Harder follow-ups are dropped or carried into a dungeon (Westfall is only its 9-15 quests, `Alliance-11-20.lua:20-481`).

**Field Guide now.** `Choose` takes the best-paying task areas from where you stand, and stops when one pays under `KEEP_SHARE` of the best (`Tasks.lua:325-443`).

## 6. Cut quests that waste time: drop luck, contested spawns, groups, escorts (later)

**The habit.** Quests whose drops are rare, whose mob respawns slowly, or that need a group, an elite kill or an escort are made optional or cut. Some are kept only if the items happen to drop on the way. Examples: Harvesting the Harvesters (`Alliance-11-20.lua:176` and `383-389`), "skip after 25+ mobs" (`Horde-12-22_Barrens.lua:1599`), group and elite steps (`Horde-12-22_Barrens.lua:2671-2709`).

**As a measure.** A quest's time should come from its real drop rate and respawn. A group or elite quest should cost what it does solo: the expected deaths, the waiting, the chance of failing.

**Field Guide now.** One `DROP_RATE` of 0.45 for every drop (`build_guides.py`). Objective counts are read from the objective text. There is no group or elite flag.

**Needs.** Drop rates per item and mob from the Wowhead cache (`tools/FieldGuide/.wowhead_cache`), and elite flags for quest mobs, written into `Guides\Data.lua` by `build_guides.py`. With those, `m` (the minutes a quest takes) gets real and these quests fall back by themselves.

## 7. Grind only to close a gap, and only what the hand-ins don't cover (built, lowest priority)

**The habit.** RXP grinds to an exact XP number, chosen so the next batch of hand-ins lands the level, often right before a trainer (`Horde-01-14_Undead.lua:1446`, `Alliance-11-20.lua:5386` then `5404-5485`).

**For Field Guide.** Field Guide doesn't chase that. Quests come first, and grinding is never chosen over a quest you could be doing. What it takes from the habit:

- When the plan does run out of work it can do yet, and it has to say "Reach level N", the step counts the hand-ins you're carrying. You grind only the XP still missing after them, and it says how much.

**Field Guide now.** Built:

- `Engine.lua` `GrindRate`, `XPToReach` and `ReadyXP`;
- the "Reach level N" step's XP target, and its early finish once your hand-ins cover the rest (`Engine.lua` step `G`).

**Tried and dropped.** Charging quests above your level the grinding minutes it would take to reach them, in place of `SOON_SHARE`. At high levels one level of grinding is hours (about 280 minutes at 44), and a plan's running XP only covers that late in the plan. So every quest above your level looked terrible, and plans grabbed leftover low quests anywhere in the world. The simulator showed it as a level 44 Dwarf bouncing between Teldrassil and Darnassus. Quests that open soon keep counting at `SOON_SHARE`.

The simulator (`test_guides.py`) now charges time for a grind step, and prints it as "(N grinding)". Before, grinding was free. Zone changes (`Z` steps) still cost nothing there. The simulator doesn't load Waypoint, so it can't show rule 3: every trip in it is a walk.

## 8. Train when you're already in town (later)

**The habit.** RXP trains at even levels, and times hand-ins so you reach the level just before a city visit (`Horde-01-14_Undead.lua:2518-2591`).

**Field Guide now.** Class trainers aren't part of the plan, and class quests are left out entirely (`build_guides.py:132-136`). Waypoint already knows trainers (`Waypoint:NavigateTo("Class trainer")`).

**Needs.** A "train" stop added when a planned stop is in a town with your trainer at a level you have new ranks for. Its cost is only the detour.

## 9. Dungeons in place of slow late questing (partly)

**The habit.** RXP's dungeon guides reuse the normal guide up to about level 16. Then dungeons replace the slowest outdoor stretch: the zone's outdoor pre-quests first, then the run, then hand-ins and the hearthstone (`dungeon\Alliance-11-20.lua:2443-2692`; Horde: RFC, Ruins of Lordaeron, Wailing Caverns, `dungeon\Horde-12-22_Barrens.lua`).

**Field Guide now.** `DungeonRate` (`Engine.lua:659-680`) and a popup offer when a dungeon beats questing (`Instance.lua:570-586`). Dungeons aren't placed in the plan. Their numbers are placeholders (`Engine.lua:55-60`).

**Needs.** Forever's dungeon quest XP and a timed run per dungeon. Then a dungeon can be a candidate "area" in `Choose`, with its pre-quests.

## 10. Picked-up drop quests and items (partly)

**The habit.** Quests started by an item drop are taken on the spot (`Horde-01-12_Durotar.lua:1790`). Quest items for a later zone are kept, so those hand-ins are instant on arrival.

**Field Guide now.** Quests from items are in the data when Questie has them. Nothing plans for keeping items.

---

## How a rule is checked

- `python -u -I tools\FieldGuide\test_guides.py --race <Race>`, four races at a time at most. Compare minutes to levels 10, 20 and 30, yards walked, and avoidable double-backs, before against after. These numbers are information, not a pass/fail.
- In game: `yarn test`, then `/reload`. `/fg why` shows the areas chosen and how each trip is made.
