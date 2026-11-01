# Field Guide

<img src="Media/Logo.png" alt="Field Guide logo" width="128">

Leveling guides for **WoW Forever**, planned from the game's own quest data. Each route ranks every quest by the XP it pays against the time it takes to get to it. You don't plan anything yourself. Field Guide reads your level, the zone you're in and the quests you've finished, picks the next best section, and **Waypoint**'s arrow shows you where to go.

Requires **Waypoint** and **Questie**.

## The field: no window

Field Guide has no window, no buttons and nothing that stays on screen. **Stand still** and the guide surfaces around your character; **move** (or get into a fight) and it lets go. It stays away in combat and inside dungeons, raids, battlegrounds and arenas.

- **Hotspots where things are.** Each place you have steps at (a quest giver, a hunting ground) is one light, in the direction it really is from you (up on the screen is the way you face, so turning turns the field), farther out the farther away it is. The field is wide and flat and stays in the top 70% of the screen, above your bars.
- **Stillness is depth.** The longer you stay still, the more comes up: the hotspot of the step to do now, with its name; then who, where, the XP, and everything else you do at that place, in order; then the other hotspots, numbered in the order you'll get to them, and a moon for a dungeon that's due (on a dungeon's route: the way back to questing). `/fg trail` brings up every step left.
- **The path.** A dotted line runs from your feet to the step to do now, then on through the hotspots in the order you'll walk to them (back to a place, when the route returns there), with a chevron on each leg pointing the way and a slow pulse running forward along it.
- **Towns as landmarks.** The nearest of Waypoint's towns (up to five within about 2000 yards) show with Waypoint's town badge and their name; rest the cursor on one for what's there (innkeeper, repair, vendors, trainers, "No flight master").
- **Double-click** a hotspot, a moon or a town and Waypoint's arrow leads there (a request, like clicking a town badge on the world map; the guide's step comes back after).
- **Rest the cursor on a hotspot** to see every step there, numbered in the order you'll do them.
- **Icons instead of words.** ! pick up, ? turn in, target: objectives, bag: an item to loot, swords: grind, footprints: travel, gate: a dungeon, back arrow: missed earlier, arrow through a door: leads to the next zone, padlock: needs a level, XP: what the quest pays. `tools/FieldGuide/make_field_icons.py` draws them (`Media\Field`).
- **Flick, don't click.** On the step to do now, rest the cursor until its ring closes, then flick the cursor off it: up = done it, down = skip, sideways = pause the guide. Drifting off slowly does nothing, and the whispers around the ring stay up for a moment, so you can move to one and click it instead (each says what it does on mouseover). Every quest step also has **Done it** and **Skip this quest** buttons under its text: a skipped quest is never suggested again (nor what needs it first), so it is yours to do on your own; `/fg unskip` brings it back. Flick a moon toward your character to go where it leads.
- **Nothing is final.** A thrown step lingers as a ghost for five seconds: rest the cursor on it to take it back.
- **While you run** a new step comes up for a moment when the last one ticks off; Waypoint's arrow does the rest.
- **It learns** how long you stay to read and opens faster (or slower) to match, brings two more steps up if you often look ahead, and stops whispering a gesture once you've used it a few times (hesitate on a closed ring and the whispers come back). Off in the options ("Learn how I read"); `/fg relearn` forgets it.

## How it picks what you do

- **Level anywhere.** Every zone with quests has a guide, levels 1 to 60, for each faction. Walk into a zone and, if it has quests worth doing at your level, its guide takes over and says so in chat. (`/fg section <n>` pins one instead.)
- **Your race doesn't matter.** Guides are per faction: a Human on Zephras Isle at level 1 gets the Zephras Isle guide. Quests your race can't take are skipped on their own.
- **XP against what you need.** Each quest's XP at your level (scaled the way the game does) is compared with the XP your next level needs. Quests paying under 1.5% of that are hidden, so gray and nearly gray quests drop out as you level, unless a quest still worth doing needs them first. Quests in your log always show. The pick-up line shows the XP you'd get.
- **Moving on by itself.** Quests that send you from one zone to another (breadcrumbs, "report to ..." quests) aren't mixed into a zone's route. The zone ends with the one that leads to the next zone suited to your level: pick it up, travel, and the new zone's guide takes over and turns it in first.
- **Quests wait for you.** The route never sends you to a quest you can't use yet. A quest waits until you're within 3 levels of it, even if the game would let you take it sooner, and until what it needs first is done. With only waiting quests left, it says "Needs level N". If nothing nearer your level is left anywhere, on any route or off them, it reaches up to 4 levels further for quests the game will offer, rather than have you wait for a level.
- **Every zone weighed the same way (Leveling).** Wherever you are, at any level, the guide works out what each zone pays: the quests you'd really get to from your level, against the time they take and the walk to them, as XP a minute. You stay while where you are pays best, and go when somewhere else pays better, walk included (leaving needs a 20% better rate, so it doesn't flip back and forth). Chat says why. There are no special rules for starting zones or for levels: quests right next to you win because they cost no walk, and a zone stops winning when its quests stop paying. `/fg why` shows the numbers.
- **Things to do on the way.** When two or more quests in your log have objectives along your walk to the next pick-up or hand-in, they become one task: "On the way: X, Y, Z". Each drops off when it's done. Reach the place with some left and the guide looks at the walk to the next place the same way, so you keep moving with a new "On the way" task. If nothing lies along it, they become "Finish: X, Y"; the last one left is a regular step.
- **Natural transitions (Leveling).** A zone doesn't hold you. Zones that touch know each other's quests, whichever of them you're in, so they plan from the same picture and agree. Everything competes on the same XP an hour, so when one zone runs short for your level the plan fills the gap from the next one and knows to come back. Zone Clear stays on its zone, unless one of its quests needs you elsewhere. When the best place left is a long trip away and doesn't touch your zone, the guide asks first: it says when your zone has more for you and what it recommends. Stay here, and it doesn't ask again until you level up.
- **Plans cross zones.** The plan doesn't stop at a zone change: it covers the whole trip, and sees whether you'll be back ("An errand: the plan brings you back to Mulgore after it") or moving on. A trip is a task of its own, and the zones you cross on it don't change the plan. Skip a trip while you're still in the zone and the guide carries on without leaving, if it can; if nothing's left there, it asks whether to wait until you enter a new zone or go back to the route. Skip it after you've left and it starts from where you are.
- **What's in the area comes first.** A quest you can pick up, or one ready to hand in, within about 75 yards of you goes to the front, whatever the plan said: it takes moments, and coming back for it later doesn't. The step you were on carries on after them.
- **Your current step stays yours.** Zones are weighed when the step you're on is done, not while you're in the middle of it. If you've wandered off and want the guide to start over from where you are, press Pause and Play.
- **Pause, go anywhere, come back.** The guide works from where you are, not where it left off. Press Play somewhere new and it weighs every zone from there and starts with the nearest thing you can do. If that place is too high for you, it finds the closest one that isn't.
- **Going back for what you missed has to pay.** A quest you need first is only fetched when the trip there and back pays what the route does.
- **Your path counts.** Quests you took on your own join the route: their objectives and turn-ins in this zone show up as steps.
- **Zone done for your level?** If the zone you're in has nothing left for you (quests all done, too low, or still too high), the guide looks for a quest here that takes you on. If there isn't one, it sends you to the nearest zone with quests for your level ("Head to Westfall").
- **Big zones come in level bands.** A zone with quests far apart in level (Stranglethorn's early camps and its late chains, or the few high-level quests in a starting area) gets one section per band; the one for your level is used.
- **Steps tick off by themselves** as you pick up, complete and turn in quests. Quests you've done, and ones Questie says you can't take (class, reputation, a quest that rules it out), are skipped.
- **Nothing to miss.** A quest you need first but never did is put in front, marked "missed earlier", with anything it needs.
- **Level gates.** Quests above your level show "Needs level N"; starting zones say how far to grind when the route runs short.
- **Questie:** the current quest goes to the top of Questie's tracker (`/fg questie` turns that off).
- **Only quests that are really there.** The quest data comes from QuestieDB, which knows quests Forever doesn't have. Before a quest goes on the route, Field Guide asks the server about it. It does this in the background, once per game patch, and remembers the answers. Quests the server doesn't have are left out (`/fg missing` lists them, `/fg recheck` asks again). And when you talk to a quest giver who doesn't offer the quest you came for, that step drops off the route (`/fg unskip` brings it back).

## The next steps, in the quickest order

The guide's route is planned ahead of time, without knowing where you'll be standing. So it scores every quest it can reach, follow-ups you'll unlock along the way included, and quests above your level that the plan's own XP gets you to (they stay after the hand-ins that earn it), by the share of your current level's total XP it pays per hour from where you stand, counting the walks and the objectives. The 30 best are planned together, with anything they need first, so work in one area gets done at once. The rest stay on the route, after them. `/fg why` shows the top five. The field shows six steps at most (`/fg trail` shows all of them). Those steps (pick-ups, objectives, hand-ins, loot) are put in the order that brings your XP in soonest from where you are: the same measure as choosing a zone, so a good quest right beside you comes before a poorer one, even if a different order walks a few yards less. Field Guide estimates every order they can go in and picks the best. A quest's own steps stay in order (pick up, do, hand in), and so do a quest and the one that needs it. Zone changes, grinding and dungeons are never moved. When the new order saves time, chat says how much: "about 2 min of walking instead of 5".

The order is only worked out again at login, when you press Play (unpause), when the zone section changes, after a Skip or "Done it", when you gain a level, when you've been moving for 30 seconds without getting closer (measured along the arrow's route; stopping or a fight pauses that clock, and working near an objective resets it), and once you've done every step in it. Plans run in the background a few milliseconds a frame, with a tiny wheel at the top left of the screen meanwhile. Until then it stays. A hand-in that comes up meanwhile waits until the planned steps are done. The step you're on stays the one you're on until it's done or you skip it, even if you hand in something else out of order: what comes after it can change, it can't. Only after you've been away (login, Play, a new section) does the guide start from the nearest thing you can do.

## In the quest log

Every quest in your quest log has a small Field Guide icon left of its title. Hover it to see where the quest sits on the route ("Turn in: step 4 of 23"). Click it for a popup with the route for the zone you're on: the steps left, in the order the arrow follows them, with this quest's steps in gold. A long route shows its start and the steps around the quest. A quest that isn't on the route says why: it's on another section, you skipped it, or it pays too little XP at your level. Escape or the close button shuts the popup, and you can drag it.

It works with the quest log beside the world map and with a separate Quest Log window, whichever the client has.

## Auto Accept and Auto Turn-in

Both are on until you turn them off in the options. Talking to an NPC takes its quests and hands in the ones you've finished, turn-ins first. Auto Turn-in stops when there's a reward to choose, or when a quest wants gold. Quests you skipped and repeatable quests are left alone, and gray quests are only taken in Zone Clear. Hold Shift while you talk to the NPC to do it by hand.

## Preference: Leveling or Zone Clear

Pick it under **Focus** in the right-click menu on Waypoint's arrow, under Options > AddOns > Field Guide ("Preference"), or with `/fg mode leveling` / `/fg mode clear`. It's saved per character.

- **Leveling** (the default): experience and convenience come first, as described above. On top of that, it takes **detours**: a quick quest a little off the route, one with nothing to do but hand it in (a delivery, "speak with ...", an auto turn-in), goes on the route when the extra walk fits the **Detour budget** (2 minutes by default, 0 to 5 in the options; 0 turns detours off). The quest also has to pay at least the route's usual XP per minute. A quest like that already in your log just gets its hand-in fitted in. Detour steps are marked "(detour)".
- **Zone Clear**: 100% of the zone: finish every quest in the zone you're on that you haven't done, whatever it pays, gray quests included. `/fg trail` shows how far along you are ("Mulgore: 41 of 47 quests"). All of the zone's level bands count as one. Quests these need first are fetched wherever they are, and the zone stays yours while you're away getting them. The zone's hand-off quests count too, and the one that leads on comes last. Quests above your level wait at the end of the trail as "Needs level N". Once only those are left, the zone counts as cleared and the guide moves on the usual way.

## Dungeon time (instance priority)

On Forever, running a dungeon with its quests in your log is the fastest leveling there is.

- Dungeons are weighed like zones. In a dungeon's recommended range (Wailing Caverns 17-24, the Deadmines 17-26, ... Stratholme 58-60), with its quests not done, the guide works out its XP a minute: its quests and kills, over collecting them, reaching the entrance, finding a group (about 3 minutes) and the run (about 35). When that beats questing where you are, a popup says so, and where to pick each quest up. It never starts one by itself: a dungeon takes a group. `/fg dungeons` and `/fg why` show the numbers.
- **Guide me** switches the guide to that dungeon: pick up every quest (and anything they need first), run the dungeon (the arrow points at the entrance), then turn them in. The steps before the run go in the best order, as on any route, and so do the hand-ins after it. Then it goes back to questing.
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
| `/fg mode leveling`, `/fg mode clear` | Preference: XP and convenience first, or finish every quest of the zone |
| `/fg missing`, `/fg recheck` | Quests left out because the server doesn't have them / ask the server again |
| `/fg skip`, `/fg unskip` | Skip the current quest (Field Guide stops suggesting it, and what needs it) / bring skipped quests back |
| `/fg why` | Why the guide picked this section, and what it sees in your zone's quests |
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
- **The plan:** for each zone (split into level bands where its quests jump by more than 6 levels), a simulated character walks the route, always taking the nearest step, with quests above its level counting as farther away. In a starting zone it starts at the first camp. Pick-ups at the same NPC are batched, objectives are done at the busiest spot of their mobs or objects, and a quest only opens up once its prerequisites are turned in and the character is within 3 levels of it (and has its required level). XP is scaled by level the way the game does, and kills along the way count too. Quests paying well under the route's usual share of a level per minute are dropped when that makes the whole route faster, unless a kept quest needs them. A starting zone's quests up to level 5 are never dropped. The report lists everything dropped.
- **Zone Clear's routes:** each section also carries the walk with every quest of its pool (`clear`, written when it differs from the kept route), and the quests that walk never got to (`rest`, mostly level gates). All of them go into `Data.lua`, and so do the quests the planner dropped. A quest with nothing to do but hand it in is flagged `talk` for Leveling's detours.
- **Hand-offs:** a quest picked up in one zone and turned in in another zone with a guide (not a capital city), with any objectives in one of the two, becomes that zone's way out (`exits` in `Guides\<Faction>.lua`; listed per zone in the report). A small zone (under 12 other quests), or a chain in the same zone that needs it, keeps it as an ordinary quest instead. A quest that opens another one, in any zone, stays on its route instead: otherwise the whole chain would depend on making that one move.
