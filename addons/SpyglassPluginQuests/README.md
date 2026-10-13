# SpyGlassPluginQuests

Expands SpyGlass's list on the Character window to every known item, with where each one comes
from: quest rewards (with the whole chain and a tracker), world drops, vendor gear and crafted
gear. It's a SpyGlass plugin: SpyGlass finds and loads it by itself.

Nothing is ranked in advance: every item goes through SpyGlass's own scoring, by the StatLedger
priority of whichever class and spec you're playing.

Needs only **SpyGlass**. The quest data (`Data\QuestDB.lua`) ships with the plugin, baked from
Wowhead's WoW Forever database by `Spyglass\Tools\fetch_wowhead_quests.py` and `build_items.py`.

## World, Vendors and Crafted

- **Buttons:** World, Vendors and Crafted join Dungeons, Raids and Quests; All includes them.
- **Where the data comes from:** `Data\Sources.lua`, an index of about 6,800 items and their
  sources, built by `Spyglass\Tools\build_sources.py` from GearQuest Forever's local item facts
  (only the facts; its per-class rankings aren't used). Quest rewards it knows that the quest data
  doesn't tie to a quest are matched to a quest by name, or else listed with
  the index's own text.
- **What's listed:** green or better, and not only for the other faction.
- **Each row:** "Vendor: Samuel Hawke - Refuge Pointe", "Crafted: Leatherworking (40)",
  "World drop, levels 23-31", "Rare: Hammerspine - Dun Morogh".
- **Tooltip:** how to get it, reputation needs against your standing, your profession skill and
  the reagents, and the nearest map spot.
- **Click:** marks the nearest spot for your faction on the world map, with the on-screen
  tracker; click again to stop.
- **Rebuilding the index:** `python -I Spyglass/Tools/build_sources.py`. It also writes
  `Data\SourcesHarvest.lua` (items SpyGlass's item data lacks; `/sg harvest sources` in dev mode
  queues them) and `Data\sources_report.txt` (counts).

## Quests in the list

- **Quests** is a new button next to Dungeons and Raids, and All includes quest gear too.
- **What's listed:** quests your character can take (race, class and faction) and hasn't
  finished yet.
- **Ranking:** the items go through SpyGlass's usual level window, class filter and stat
  priority ranking.
- **Each row** names the quest and, for a chain, the next step you still have to do: "Quest:
  The Defias Brotherhood - next: The Defias Brotherhood (step 2 of 7)". As you hand quests in,
  it moves on to the next step.
- **Tooltip:** shows where the next step starts and the whole chain, with finished steps
  marked.
- **Click a quest item** to open its quest window.

## Quest window

Styled like the game's quest giver window:

- **Quest:** the next step's title and level, and the quest it leads to.
- **Quest Objectives.**
- **Where to start:** the quest giver, then continent, zone, subzone (when the quest's area is
  one) and map coordinates.
- **Quest chain:** every step, with finished ones ticked and the next one marked.
- **Rewards:** the gear on offer, with the item you came from highlighted.

**Track quest** marks where to go on the world map (not the minimap: you'll find the NPC there
once you're close). It also shows an on-screen tracker such as "Pick up: The Defias
Brotherhood". **Close** closes the window.

### How tracking finds the right quest

- **Which step:** tracking goes to the first step of the chain you haven't completed, as the game
  reports it. If it knows nothing, that's the first quest of the chain.
- **Picking up:** a step not yet in your quest log points to its quest giver ("Pick up: ...").
- **Turning in:** once a step is in your log, the tracker points to the NPC who takes it back
  ("Turn in: ...").
- **Not offered:** if you reach the giver and they don't offer that quest, the step is marked
  "not offered here" and the tracker moves down to the next step. Typical reasons are that you
  did it before the game kept track, or that it isn't for your character. This doesn't happen
  when you're simply under the quest's level; you're told the level instead.
- **Reset skipped:** in the quest window this undoes those marks if one was wrong.
- **Progress:** handing in a step moves on to the next. Finishing the reward quest stops
  tracking.
- **Reopening:** click the tracker or the map marker to reopen the window. The tracker's X stops
  tracking.
- **Moving the tracker:** use the game's Edit Mode, like any other UI element; it shows there
  even when nothing is tracked. Without Edit Mode, use `/sg tracker`.

## Dungeon quests in the journal

The plugin asks SpyGlass for a **Quests** tab (book icon) on the loot journal's instance page,
next to Loot, Abilities and Model.

- **Which quests:** every quest the quest data ties to that dungeon or raid. A quest counts when any
  of these is true:
  - its zone is the instance;
  - its giver stands inside;
  - something it asks for is only found there: a creature to kill, an object, or an item that
    drops from one of them.
- **With a boss picked:** only the quests involving that boss (for VanCleef, The Defias
  Brotherhood).
- **Order:** quests in your log first, then ones you can take, then ones you're too low for, then
  ones you've done (dimmed, with a tick). Quests your character can't take come last, dimmed and
  labelled with why ("Horde only", "Warrior only"). Ragefire Chasm's quests, for example, are all
  Horde only, so an Alliance character sees them there.
- **Each row:** shows the quest's level, where it starts ("Starts: giver - zone" or "Starts
  inside"), and the reward's icon when it gives gear.
- **Hover** for objectives and rewards; **click** to open the quest window, which has Track.

The list is worked out ahead of time and ships with the plugin, so the tab fills at once.

## Notes

- **Quest data** (chains, givers, spawns, objectives, and which quests reward which items)
  comes from Wowhead's WoW Forever database, including this server's own quests. Quests seen
  in game by a dev-mode harvest fill any gaps. Quality comes from the game's own item info.
- **Full quest descriptions** aren't shipped, so the window shows the objectives.
- **Loading:** at login the plugin goes through the quests' rewards a few hundred per frame, so
  quest gear appears a moment after you log in.
