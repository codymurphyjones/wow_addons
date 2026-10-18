# SpyGlass

**A loot journal for every dungeon and raid, and a list on your Character window of the gear you can use, best for your spec first.**

Finding your next upgrade usually means paging through every boss in a loot browser and working out which items suit you. SpyGlass does that for you. It takes every dungeon and raid drop from AtlasLoot, keeps the gear your class can use at your level, and ranks it by your stat priority from StatLedger. Upgrades over what you're wearing are marked, and a click on any item opens the journal at the boss that drops it.

---

## Features

### Your gear list, on the Character window
A **SpyGlass** tab sits with the Character window's other tabs. Click it and your gear list replaces the stats on the right, next to your paper doll.

- **Only your gear.** Items your class can use, in your level window, with at least one of your priority stats.
- **Ranked for your spec.** Each item gets a score: every stat on it, multiplied by how high that stat sits in your StatLedger priority, added up. The best scores come first. Hover an item to see its score.
- **Upgrades marked.** A green **+x** means the item beats what you wear in that slot (the weaker of your two, for rings and trinkets). **new** marks a slot you have nothing in.
- **Where it drops.** Each row names the boss and the instance. Item names are in their rarity colour, so you can see what an item is worth at a glance.
- **Filter by slot.** Click an equipment slot on your character, such as Shoulder, to see only shoulder loot. Click it again or press **All** to see every slot. The tab opens on your weakest slot, the one most likely to have an upgrade waiting.
- **Filter by source.** Dungeons, Raids, Quests, World, Vendors and Crafted (with the quest plugin) or All, plus a search box.
- **Click an item** to open the journal at the boss that drops it, with the item scrolled into view and highlighted. **Shift-click** links it in chat, and **Ctrl-click** previews it in the dressing room.
- **Buttons.** The cog opens StatLedger; change your priority there and the list re-ranks straight away. **Journal** opens the loot journal, and **AtlasLoot** opens AtlasLoot's own window.

### The loot journal
A dungeon and raid journal in the style of the game's own windows, built from AtlasLoot's data and ranked by your StatLedger priority.

**Home page**
- A grid of tiles for every dungeon or raid, with its level range and number of bosses, using the game's own Dungeon Finder art.
- It opens on **My level**: places whose levels run from 8 below you to 4 above. Switch to all levels or a level band, or search by instance or boss name.
- Places this server added are marked **Forever**.
- Places AtlasLoot lists but hasn't recorded loot for yet carry a gold **LOOT COMING SOON** band. Their known bosses are still listed, and the loot appears by itself once AtlasLoot is updated. Untick **Show coming soon** to hide them.

**Instance pages** open like a book: the bosses on the left, and on the right whatever you pick with the tabs along the window's edge.

- **Loot:** the boss's gear, best for your spec first. Each row shows the slot, armor or weapon type, required level (orange when it's above yours), the SpyGlass score and any upgrade. Gear you can't use is dimmed, with the reason in red. Tick **Only my gear** to hide it. Right-click an item to open it in AtlasLoot.
- **Abilities:** each of the boss's abilities is a bar with its icon and name, coloured by spell school. Click one to open it: you get the game's description, when the boss casts it (for example "First cast 7-12s, every 6-16s") and a short tip. A strategy overview for the fight follows. With **All bosses** picked, you get an overview of the instance.
- **Model:** the boss in 3D. Drag to turn it, scroll to zoom, and press **Reset** to put it back.

### Every known item (optional plugin)
Install **SpyGlassPluginQuests** to add every other known item (green or better) alongside dungeon and raid loot: quest rewards, world drops, vendor gear and crafted gear, all ranked by your StatLedger priorities.

- **World**, **Vendors** and **Crafted** buttons list where each item comes from: the vendor and their zone, the profession and skill (with your own skill and the reagents), or the drop's levels and zone. Reputation needs are shown against your own standing. Click one to mark it on the world map.

- A **Quests** button joins Dungeons and Raids, and All includes quest gear too.
- It lists only quests your race, class and faction can take and that you haven't finished. Each row names the next step of the chain you still have to do, such as "next: The Defias Brotherhood (step 2 of 7)", and moves on as you hand quests in.
- **Click a quest item** to open a quest window with the objectives, where to start (giver, zone and map coordinates), the whole chain with finished steps ticked, and the rewards.
- **Track quest** (with the **Waypoint** addon) points Waypoint's arrow at the next step, such as "Pick up: ..." or "Turn in: ...". It moves on as you progress, skips any step a quest giver doesn't offer you, and stops once you finish the reward quest.
- The journal gets a **Quests** tab on every instance page. It lists the quests tied to that dungeon or raid, or with a boss picked, the quests involving that boss. Quests you can't take are shown dimmed, with why ("Horde only").

The plugin needs **QuestieDB**. Questie itself is optional; when it's loaded, the plugin uses its zone data for more exact map markers.

### Light on the server
SpyGlass only asks the server about items you can see. Rows load as you scroll, pick a slot or open a boss, and nothing is fetched in the background. Items still loading show as "Loading..." and fill in a moment later. If the server never answers, the row says "Couldn't load item"; click it to try again. Items this game client keeps encrypted ("Encrypted by Forever beta build") can't be shown, so they're hidden and never asked for.

---

## How to use

1. Install **AtlasLootClassic** and **StatLedger**, then install SpyGlass.
2. Set up your stat priority in StatLedger (`/statledger`), or keep its default for your spec.
3. Open your Character window and click the **SpyGlass** tab, or type **/sg**.
4. Click a slot on your character to see the loot for that slot. Click any item to see where it drops.
5. Open the journal with the **SpyGlass minimap button**, the **Journal** button, or **/sgj**. Browse any dungeon or raid, and read up on its bosses before you go in.

The minimap button: left-click opens the journal, right-click opens your gear list, and dragging moves it around the minimap.

| Command | What it does |
|---|---|
| `/sg` | Open or close your gear list on the Character window |
| `/sg journal` or `/sgj` | Open or close the loot journal |
| `/sgj minimap` | Show or hide the minimap button |
| `/sg atlas` | Open AtlasLoot |
| `/sg tab` | Show or hide the Character window tab |
| `/sg options` | Open the settings |
| `/sg plugins` | List the plugins found, and why any didn't load |
| `/sg untrack` | Stop tracking a quest |
| `/sg debug` | Show why items are or aren't listed |

---

## Settings

Open **Options > AddOns > SpyGlass**, or type `/sg options`.

- **Hide AtlasLoot minimap button:** takes AtlasLoot's book off the minimap so it doesn't sit beside SpyGlass's. AtlasLoot still opens with `/al`, or from SpyGlass. If a minimap button bar addon holds onto the button, you're offered a reload. Fanny Pack removes it straight away.
- **Show SpyGlass minimap button.**
- **Show the SpyGlass tab** on the Character window.
- **Plugins:** every plugin found, and whether it loaded.

---

## What's shown

With your level as L:

| Item | Listed when its required level is |
|---|---|
| Most gear | L - 8 to L + 4 |
| Class-specific gear | L - 20 to L + 4 |

- **Class-specific gear** is restricted to your class, is a libram, idol or totem, or has an effect that names one of your class's spells.
- **Items with no required level**, like most quest rewards, go by the level they were made for.
- **Gear your class can never use is hidden:** the wrong armor or weapon type, or another class's item. Armor and weapon types your class learns later still show, so a young warrior sees plate. AtlasLoot's own class filter also applies.
- **Stats** come from the item's stats and its "Equip:" lines (spell power, healing, crit, hit, mp5, defense and more). Percent stats count roughly what they're worth in item budget.

---

## Works with

- **AtlasLootClassic** (required): the loot data for every dungeon and raid.
- **StatLedger** (required): your stat priority for each class and spec.
- **SpyGlassPluginQuests** (optional): quest reward gear with quest tracking, plus world drops, vendor and crafted gear. It needs **QuestieDB**.
- **Fanny Pack**: hiding AtlasLoot's minimap button from SpyGlass's settings takes effect in Fanny Pack straight away.
- **Your own addon:** see *For addon authors* below.

---

## For addon authors

SpyGlass sets a global `SpyGlass` table (`API_VERSION` 1). The built-in journal uses nothing but this API, so your addon can use it too:

- instances and bosses from AtlasLoot;
- ranked rows for any list of items;
- item info and usability checks;
- the shared tooltip and click handlers;
- waypoints, through the Waypoint addon's arrow;
- a refresh callback.

**Plugins** add their own items to the list, each with where it comes from:

1. Name your addon with "plugin" in it.
2. Add these lines to its TOC (`Spyglass` is SpyGlass's folder name):

   ```
   ## Dependencies: Spyglass
   ## X-SpyGlass-Plugin: 1
   ## LoadOnDemand: 1
   ```
3. Call `SpyGlass:RegisterPlugin({ ... })` with your items and a filter button.
4. If you want a tab on the journal's instance pages, ask for one with `SpyGlass:RequestJournalTab(...)`. There's room for three plugin tabs, and a plugin only gets one by asking.

The README has the full plugin and API reference.

---

## Notes

- Built for **World of Warcraft: Forever** (Interface 16001).
- **Saved variables:** `SpyGlassDB` and `SpyGlassJournalDB` (account-wide). The quest plugin saves `SpyGlassPluginQuestsDB` per character. Settings from LootPriority, SpyGlass's earlier name, carry over by themselves.
- **Sources:** loot data from AtlasLootClassic. Ability lists and cast timings come from the open-source VMaNGOS Classic database (spell IDs only); the names, icons and descriptions come from your game client. The tips and fight strategies were written for SpyGlass, and this server may have changed some fights. Quest data comes from QuestieDB.
- **Art:** the journal uses only the game's own art.
- The "Equip:" lines are read in English only.

Bug reports and suggestions are welcome in the comments or on the issue tracker.
