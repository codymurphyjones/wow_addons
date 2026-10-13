# SpyGlassPluginQuests

**Every known item in your SpyGlass list, and where it comes from: quest rewards with their whole chain, world drops, vendor gear and crafted gear.**

SpyGlass on its own covers dungeon and raid loot. Much of the gear you wear while levelling comes from elsewhere: a quest chain, a vendor in the next town, a recipe you could craft, or a drop out in the world. This plugin brings all of it into SpyGlass's ranked list, so every item, wherever it comes from, is scored the same way: by your own StatLedger stat priority for your class and spec. Nothing is ranked in advance for one class; whatever character you play, the list is ranked for it.

Each item says where to get it. Quest rewards name the next step of the chain you still have to do and open a quest window with a tracker. Vendor items name the vendor and zone, crafted items the profession and skill, and world drops their levels and zone. Click one and follow the marker on the world map.

---

## Requirements

| Addon | Why |
|---|---|
| **SpyGlass** (required) | The gear list and loot journal this plugin adds to. SpyGlass itself needs AtlasLootClassic and StatLedger. |

The quest data (chains, givers, spawns, objectives and which quests reward which items) and the world, vendor and crafted item index ship with the plugin; it needs nothing else installed. Questie and QuestieDB are no longer needed.

You don't need to enable anything by hand. SpyGlassPluginQuests is a SpyGlass plugin: SpyGlass finds it at login and loads it for you.

---

## Features

### Every source, one ranking
- **Four new buttons** join Dungeons and Raids at the top of the list: **Quests**, **World**, **Vendors** and **Crafted**. **All** includes every one of them.
- **About 6,800 items** beyond dungeon and raid loot: around 1,700 quest rewards, 1,500 vendor items, 1,100 crafted items and 2,500 world drops (including rare NPCs, trash and containers).
- **Ranked by your StatLedger priority.** Every item goes through SpyGlass's usual level window, class filter and stat scoring, so a vendor belt sits right where it belongs next to a dungeon drop. Change your priority in StatLedger and every list re-ranks.
- **Only what you can use.** Green quality or better, and items only the other faction can get are left out.

### Vendors
- **Each row names the vendor and their zone**, such as "Vendor: Samuel Hawke - Refuge Pointe".
- **Reputation** needs are shown against your own standing, in green once you have it ("Needs Honored with The League of Arathor (you: Friendly)").
- **Click** to put a marker on the nearest vendor that serves your faction.

### Crafted
- **Each row names the profession and skill**, such as "Crafted: Leatherworking (40)".
- **Hover** for the reagents and your own skill: whether you have the profession, and how far you are from the skill it needs.
- **Click** to mark the trainer who teaches it, when one is known.

### World drops
- **World drops** say the levels they drop at; **rare NPCs**, trash and bosses name the creature and zone; items found in objects or containers say where.
- **Click** to mark a known farming spot or spawn on the world map.

### Quest gear in your SpyGlass list
- **The Quests button** lists quest reward gear; **All** includes it too.
- **Only quests you can do.** Quests your race, class and faction can take, and that you haven't finished. Weapons and armor only, green quality or better.
- **Ranked like the rest.** Quest items go through SpyGlass's usual level window, class filter and stat priority ranking, so a quest reward sits right where it belongs next to dungeon drops. Upgrades are marked the same way.
- **Each row names the next step.** For example: "Quest: The Defias Brotherhood - next: The Defias Brotherhood (step 2 of 7)". As you hand quests in, it moves on by itself.
- **Hover** for where the next step starts (giver, subzone, zone and coordinates) and the whole chain, with finished steps marked **done** and the step you need marked **next**.
- **Click a quest item** to open its quest window.

### The quest window
A window in the style of the game's quest giver frame, on parchment. Drag it anywhere; **Esc** closes it.

- **Quest:** the title of the step you need now, its level, and the level you can take it at. For a chain, it also names the quest it leads to and that gives the gear.
- **Where to start:** the quest giver (with their title, such as *<Defias Brotherhood>*), then the continent, zone, subzone and map coordinates. Givers inside a dungeon say "inside the instance". Once the step is in your quest log, this becomes **Turn in** and names the NPC who takes it back.
- **Quest Objectives,** with your name, class and race filled in.
- **Quest chain:** every step in order. Finished steps are ticked, the next one has an arrow, and steps the giver didn't offer you are marked *(not offered here)*.
- **Rewards:** the gear on offer ("You will be able to choose one of these rewards"), with the item you clicked highlighted. Hover a reward for its tooltip; Shift-click links it in chat and Ctrl-click previews it in the dressing room.
- **Buttons:** **Track quest** / **Stop tracking**, **Reset skipped** (only shown when a step in this chain was skipped) and **Close**.

### Quest tracking
**Track quest** puts a marker on the world map and shows an on-screen tracker, such as **"Pick up: The Defias Brotherhood"** with the giver and zone underneath.

- **Always the right step.** Tracking points at the first step of the chain you haven't completed. With no completion data, that's the first quest of the chain.
- **Pick up, then turn in.** A step not yet in your log points to its quest giver. Once you accept it, the tracker switches to **"Turn in: ..."** and points to the NPC who takes it back.
- **Moves on by itself.** Accepting or handing in a quest updates the tracker a moment later. Finishing the reward quest stops tracking, and you're told in chat.
- **Steps you can't get are skipped.** If you reach the giver and they don't offer the step (you did it before the game kept track, or it isn't for your character), it's marked *not offered here* and the tracker moves to the next step. Being under the quest's level never counts: you're told the level you need instead. If a skip was wrong, press **Reset skipped** in the quest window.
- **Reopen the window** by clicking the tracker or the map marker.
- **Stop tracking** with the tracker's **X**, the window's **Stop tracking** button, or `/sg untrack`.
- **Survives a reload.** The tracked chain is kept through `/reload` and logging out.
- **Move the tracker** in the game's **Edit Mode** like any other UI element (it shows there even when nothing is tracked), or unlock it with `/sg tracker`.
- The marker is on the world map, not the minimap: you'll find the NPC once you're close.

### Dungeon and raid quests in the loot journal
The plugin adds a **Quests** tab (book icon) to every instance page in SpyGlass's loot journal, next to Loot, Abilities and Model.

- **Which quests:** every quest the quest data ties to that dungeon or raid. A quest counts when its zone is the instance, its giver stands inside, or something it asks for is only found there: a creature to kill, an object to use, or an item that drops from one of them.
- **Pick a boss** to see only the quests involving that boss (for VanCleef, *The Defias Brotherhood*).
- **Sorted for you:** quests in your log first (yellow, "In your log"), then quests you can take, then ones you're too low for ("Needs 18"), then ones you've done (dimmed and ticked). Quests your character can't take come last, dimmed, with the reason: "Horde only", "Alliance only", "Warrior only" and so on.
- **Each row** shows the quest's level, where it starts ("Starts: Gryan Stoutmantle - Sentinel Hill, Westfall" or "Starts inside"), and the reward's icon when it gives gear.
- **Hover** for the objectives, the rewards and how long the chain is. **Click** to open the quest window, where you can track it.
- The list ships with the plugin, so the tab fills at once.

---

## How to use

1. Install **SpyGlass** (with AtlasLootClassic and StatLedger) and this plugin.
2. Log in. You'll see "Quest Rewards: ... items added" in chat a moment later.
3. Open your Character window and click the **SpyGlass** tab (or type `/sg`). Press **Quests**, **World**, **Vendors** or **Crafted** to see one source, or **All** to see everything with dungeon and raid loot.
4. Click a quest item to open its quest window. Read where the chain starts and what it rewards.
5. Press **Track quest** and follow the world map marker and the on-screen tracker. It updates as you accept and hand in each step.
6. Planning a dungeon run? Open the journal (`/sgj` or the SpyGlass minimap button), pick the dungeon and open the **Quests** tab to pick up its quests before you go.

---

## Commands

These are SpyGlass's commands; the ones below are the ones that matter for this plugin.

| Command | What it does |
|---|---|
| `/sg` | Open or close your gear list on the Character window |
| `/sg journal` or `/sgj` | Open or close the loot journal (with the Quests tab) |
| `/sg plugins` | List the plugins found, and why any didn't load |
| `/sg untrack` | Stop tracking a quest |
| `/sg tracker` | Unlock the on-screen tracker to drag it (or use Edit Mode) |
| `/sg debug` | Show why items are or aren't listed. Quest items can be hidden as "unknown quest", "not for your character", "already done" or "below green" |

---

## Troubleshooting

- **No Quests, World, Vendors or Crafted buttons:** type `/sg plugins`. It should list SpyGlassPluginQuests as loaded. If it says a dependency is missing, check that SpyGlass is installed and enabled for this character. Quest gear takes a moment to appear after login.
- **A quest gear item you expected isn't listed:** `/sg debug` tells you why. Also check the level window: SpyGlass lists gear from 8 levels below you to 4 above.
- **The tracker skipped a step it shouldn't have:** open the quest window and press **Reset skipped**.
- **"where ... starts isn't known":** the quest data has no spawn for that giver, so there's nothing to mark on the map. The quest window still shows the chain and objectives.

---

## Notes

- Built for **World of Warcraft: Forever** (Interface 16001).
- **Quest data** (chains, givers, spawns, objectives, and which quests reward which items) comes from Wowhead's WoW Forever database, including this server's own quests. Item quality comes from the game's own item info.
- **Full quest text** isn't shipped, so the quest window shows the objectives.
- **Light at login:** the plugin goes through the quests' rewards a few hundred per frame, so logging in never stalls.
- **Item sources** for world drops, vendors and crafted gear come from a shipped index (`Data\Sources.lua`). Item names, stats and quality come from the game itself.
- **Saved variables:** `SpyGlassPluginQuestsDB`, per character (the steps marked *not offered here*). Data saved under the plugin's earlier name, LootPriorityPlugin, carries over by itself.

Bug reports and suggestions are welcome in the comments or on the issue tracker.
