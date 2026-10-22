# Field Guide

<img src="Media/Logo.png" alt="Field Guide logo" width="128">

Leveling guides for **WoW Forever**, planned from the game's own quest data. Each route ranks every quest by the XP it pays against the time it takes to get to it. You don't plan anything yourself. Field Guide reads your level, the zone you're in and the quests you've finished, picks the next best section, and **Waypoint**'s arrow shows you where to go.

Requires **Waypoint** and **Questie**.

## The field: no window

Field Guide has no window, no buttons and nothing that stays on screen. **Stand still** and the guide surfaces around your character; **move** (or get into a fight) and it lets go.

- **Hotspots where things are.** Each place you have steps at (a quest giver, a hunting ground) is one light, in the direction it really is from you (up on the screen is the way you face, so turning turns the field), farther out the farther away it is. The field is wide and flat and stays in the top 70% of the screen, above your bars.
- **Stillness is depth.** The longer you stay still, the more comes up: the hotspot of the step to do now, with its name; then who, where, the XP, and everything else you do at that place, in order; then the other hotspots, numbered in the order you'll get to them, and a moon for a dungeon that's due (on a dungeon's route: the way back to questing). `/fg trail` brings up every step left.
- **The path.** A dotted line runs from your feet to the step to do now, then on through the hotspots in the order you'll walk to them (back to a place, when the route returns there), with a chevron on each leg pointing the way and a slow pulse running forward along it.
- **Towns as landmarks.** The nearest of Waypoint's towns (up to five within about 2000 yards) show with Waypoint's town badge and their name; rest the cursor on one for what's there (innkeeper, repair, vendors, trainers, "No flight master").
- **Double-click** a hotspot, a moon or a town and Waypoint's arrow leads there (a request, like clicking a town badge on the world map; the guide's step comes back after).
- **Rest the cursor on a hotspot** to see every step there, numbered in the order you'll do them.
- **Icons instead of words.** ! pick up, ? turn in, target: objectives, bag: an item to loot, swords: grind, footprints: travel, gate: a dungeon, back arrow: missed earlier, arrow through a door: leads to the next zone, padlock: needs a level, XP: what the quest pays. `tools/FieldGuide/make_field_icons.py` draws them (`Media\Field`).
- **Flick, don't click.** On the step to do now, rest the cursor until its ring closes, then flick the cursor off it: up = done it, down = skip, sideways = pause the arrow. Drifting off slowly does nothing. Every quest step also has a **Skip this quest** button under its text: a skipped quest is never suggested again (nor what needs it first), so it is yours to do on your own; `/fg unskip` brings it back. Flick a moon toward your character to go where it leads.
- **Nothing is final.** A thrown step lingers as a ghost for five seconds: rest the cursor on it to take it back.
- **While you run** a new step comes up for a moment when the last one ticks off; Waypoint's arrow does the rest.
- **It learns** how long you stay to read and opens faster (or slower) to match, brings two more steps up if you often look ahead, and stops whispering a gesture once you've used it a few times (hesitate on a closed ring and the whispers come back). Off in the options ("Learn how I read"); `/fg relearn` forgets it.

## How it picks what you do

- **Level anywhere.** Every zone with quests has a guide, levels 1 to 60, for each faction. Walk into a zone and, if it has quests worth doing at your level, its guide takes over and says so in chat. (`/fg section <n>` pins one instead.)
- **Your race doesn't matter.** Guides are per faction: a Human on Zephras Isle at level 1 gets the Zephras Isle guide. Quests your race can't take are skipped on their own.
- **XP against what you need.** Each quest's XP at your level (scaled the way the game does) is compared with the XP your next level needs. Quests paying under 1.5% of that are hidden, so gray and nearly gray quests drop out as you level, unless a quest still worth doing needs them first. Quests in your log always show. The pick-up line shows the XP you'd get.
- **Moving on by itself.** Quests that send you from one zone to another (breadcrumbs, "report to ..." quests) aren't mixed into a zone's route. The zone ends with the one that leads to the next zone suited to your level: pick it up, travel, and the new zone's guide takes over and turns it in first.
- **Zone done for your level?** If the zone you're in has nothing left for you (quests all done, too low, or still too high), the guide looks for a quest here that takes you on. If there isn't one, it sends you to the nearest zone with quests for your level ("Head to Westfall").
- **Big zones come in level bands.** A zone with quests far apart in level (Stranglethorn's early camps and its late chains, or the few high-level quests in a starting area) gets one section per band; the one for your level is used.
- **Steps tick off by themselves** as you pick up, complete and turn in quests. Quests you've done, and ones Questie says you can't take (class, reputation, a quest that rules it out), are skipped.
- **Nothing to miss.** A quest you need first but never did is put in front, marked "missed earlier", with anything it needs.
- **Level gates.** Quests above your level show "Needs level N"; starting zones say how far to grind when the route runs short.
- **Questie:** the current quest goes to the top of Questie's tracker (`/fg questie` turns that off).

## Dungeon time (instance priority)

On Forever, running a dungeon with its quests in your log is the fastest leveling there is.

- When your level reaches a dungeon's recommended range (Wailing Caverns 17-24, the Deadmines 17-26, ... Stratholme 58-60) and its quests aren't done, a popup says it's time and where to pick each quest up.
- **Guide me** switches the guide to that dungeon: pick up every quest (and anything they need first), run the dungeon (the arrow points at the entrance), then turn them in. Then it goes back to questing.
- **Later**: the popup won't come back for that dungeon, but the **minimap button's tooltip lists it, with its quests, every time** while you're in its level range and haven't done them.
- `/fg dungeons` lists them, `/fg dungeon <n>` starts the guide for one, `/fg dungeon stop` goes back to questing.

Covers the 19 classic 5-player dungeons, Ragefire Chasm to Stratholme, with each faction's quests for them.

## Sections

`/fg list` shows them all: 48 for the Alliance (39 zones) and 43 for the Horde (35 zones), from the starting zones (Elwynn, Dun Morogh, Teldrassil, Zephras Isle, Durotar, Mulgore, Tirisfal) up to Silithus, the Plaguelands and Winterspring. `tools/FieldGuide/guides_report.txt` lists each one with its levels, quests, estimated time and the quests it leaves out.

## Commands

| Command | |
|---|---|
| `/fg` | Turn the guide on or off |
| `/fg trail` | Every step left in the section, until you move |
| `/fg relearn` | Forget the pace and gestures the field learned |
| `/fg list` | The guides and their sections |
| `/fg guide <name>` | Follow another faction's guide (`/fg guide auto`: yours) |
| `/fg section <n>` | Follow a section from `/fg list` (`/fg section auto`: pick for me) |
| `/fg dungeons` | Dungeons in your level range with quests left (`/fg dungeon <n>`: guide me there, `/fg dungeon stop`) |
| `/fg skip`, `/fg unskip` | Skip the current quest (Field Guide stops suggesting it, and what needs it) / bring skipped quests back |
| `/fg questie` | Focus the current quest in Questie's tracker, or not |
| `/fg minimap` | Show or hide the minimap button |

## Building the guides

The guides in `Guides\` are generated. Don't edit them by hand.

```
python tools/FieldGuide/fetch_xp.py       # quest XP: QuestieDB's Classic table + Spyglass's Wowhead cache
python tools/FieldGuide/build_guides.py   # plans every section, writes Guides\*.lua and tools/FieldGuide/guides_report.txt
```

- **Quest data:** the QuestieDB addon's Forever database (`tools/_shared/questiedb.py` reads it straight from the game folder, read-only): every quest, its givers, objectives, prerequisites and race mask, and every NPC and object with spawn points.
- **Quest XP:** Wowhead's quest lists, as cached by Spyglass's tools, plus QuestieDB's Classic XP table. Wowhead now blocks scripted downloads, so only what's cached is used. Quests with no known XP are estimated from their level and flagged in the report.
- **The plan:** for each zone (split into level bands where its quests jump by more than 6 levels), a simulated character walks the route, always taking the nearest step. Pick-ups at the same NPC are batched, objectives are done at the busiest spot of their mobs or objects, and a quest only opens up once its prerequisites are turned in and the level allows it. XP is scaled by level the way the game does, and kills along the way count too. Quests paying well under the route's usual XP per minute are dropped when that makes the whole route faster, unless a kept quest needs them. The report lists everything dropped.
- **Hand-offs:** a quest picked up in one zone and turned in in another zone with a guide (not a capital city), with any objectives in one of the two, becomes that zone's way out (`exits` in `Guides\<Faction>.lua`; listed per zone in the report). A small zone (under 12 other quests), or a chain in the same zone that needs it, keeps it as an ordinary quest instead.
