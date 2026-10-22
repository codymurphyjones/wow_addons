# SpyGlass

Dungeon and raid gear for your level and class, ranked by your spec's stat priority, on the
Character window, plus a loot journal with every dungeon and raid, boss abilities, strategy and
models. The loot is SpyGlass's own (built from AtlasLoot Continued's tables and SpyGlass's harvest, so
AtlasLoot doesn't have to be installed; with it, "Open in AtlasLoot" still works), and the priority
comes from StatLedger.

## Character window tab

Open the Character window and click the SpyGlass tab (the spyglass) under its other tabs, or type `/sg`
(also in the AddOns menu on the minimap). Your gear list takes the place of the stats on the
right, next to your paper doll:

- **What's listed:** gear you can use (see below) that has at least one of your priority stats,
  best total value first, with each item's boss and instance. Names are in their rarity
  colour (grey, white, green, blue, purple, orange), so an item's worth shows at a glance.
- **Score:** each stat on the item, multiplied by how high that stat sits in your StatLedger
  list, added up. Hover an item to see its score.
- **Upgrades:** a green `+x` marks an item that beats what you wear in that slot (for rings
  and trinkets, the weaker of your two). `new` marks a slot you have nothing in.
- **Filtering by slot:** while the list is open, click an equipment slot on your character
  (say, Shoulder) to see shoulder loot only. Click it again, or press "All", to go back to
  every slot. The picked slot glows. Clicks there don't pick up your gear, and Shift-click
  still links what you wear.
- **Other filters:** Dungeons / Raids / Quests / All, and search. The list is always your own
  gear: your class, your level window and your priority stats. To browse everything, use the
  journal or AtlasLoot.
- **Clicking an item** opens the journal on the dungeon and boss that drop it, with the Loot tab
  scrolled to the item and highlighted.
  Shift-click links the item, and Ctrl-click previews it in the dressing room.
- **Buttons:** the cog opens StatLedger (changing it re-ranks the list straight away).
  "Journal" opens the loot journal.

Click the tab again, or any other tab, to go back to your stats.

| Command | |
|---|---|
| `/sg` | Open or close the list on the Character window |
| `/sg journal` or `/sgj` | Open or close the loot journal |
| `/sgj minimap` | Hide or show the journal's minimap button |
| `/sg atlas` | Open AtlasLoot |
| `/sg tab` | Hide or show the Character window tab |
| `/sg options` | Open SpyGlass's settings |
| `/sg plugins` | List the plugins found and whether each loaded |
| `/sg untrack` | Stop tracking a quest (with the Waypoint addon) |

## Loot journal

A dungeon and raid journal, built from AtlasLoot's data and ranked by your StatLedger.

### Opening it

- The SpyGlass button on the minimap: left-click opens the journal, right-click opens your gear list
  on the Character window. Drag it to move it around the minimap.
- "Journal" at the bottom of the SpyGlass panel on the Character window.
- `/sgj`, or `/sg journal`.
- Clicking an item in the Character window list opens the journal on the dungeon and boss that drop
  it, with the Loot tab scrolled to that item and highlighted in gold.

### Home

A grid of instances for the Dungeons or Raids tab, by level, with the level range and boss count.
It starts on **My level**: instances whose level range overlaps 8 levels below you to 4 above.
Switch to All levels or a level band with the dropdown, or search by instance or boss name.

**Upgrades.** A green arrow and number in a tile's corner counts the items there that beat what you
wear (the weaker ring or trinket; any item for an empty slot), for places at or below your level.
Only gear you can wear now counts. Hover the tile to see which slots. Tick **Extend Upgrade Search**
to count places and gear up to 3 levels above you as well.

Places the server added itself are marked "Forever".

**Loot coming soon.** Some places are listed in AtlasLoot before their loot has been
data-mined. Their tiles are greyed out with a gold "LOOT COMING SOON" band and read "Not yet
recorded". Inside, a banner says so, the known bosses are listed with a clock, and the loot side
shows a "Loot not yet recorded" card. When AtlasLoot is updated with the loot, it appears on its
own.

### Instance page

The page opens like a book.

**Left page:** the instance name, then a card for each boss. Each card has a round portrait,
the boss's name and level, and a gold border on the boss you've picked. "All bosses" comes
first. Bosses whose loot isn't recorded yet show a clock.

**Right page:** three tabs on the window's right edge choose what it shows.

- **Loot:** the boss's gear, best for your spec first.
  - Names are in their rarity colour. Each row shows the slot, type, required level (orange when
    it's above yours), the SpyGlass score, and a green `+x` when it beats what you wear.
  - Gear you can't use is dimmed, with the reason in red. "Only my gear" hides it, along with
    anything outside your level window.
  - Shift-click links an item, Ctrl-click previews it, and right-click opens it in AtlasLoot.
- **Abilities:** each ability is a bar with its icon and its name, coloured by spell school.
  - Click a bar to open it. Open, it shows the game's description, when the boss casts it ("First
    cast 7-12s, Every 6-16s", where the data has it) and a short tip.
  - Below the abilities is a strategy overview for the fight.
  - With "All bosses" picked, the tab shows an overview of the instance and each boss's
    abilities as icons.
- **Model:** the boss's 3D model. Drag to turn it, scroll to zoom, and Reset puts it back.

Bosses this server added itself aren't in the classic data, so their Abilities tab says
"Abilities not documented yet".

The spell lists and cast timings come from the open-source VMaNGOS Classic database (spell IDs
only). The tips and strategy were written for this addon. Names, icons and descriptions come from
your game client. This server may have changed some fights.

### Pictures

The tiles use only the game's own art: the Dungeon Finder backgrounds where the game has one for
the place. Elsewhere, a tinted generic card with the first boss's portrait. No images from other
addons are used.

## Plugins

Plugins add more items to the list, each with where it comes from: its origin.

- **Finding them:** at login SpyGlass looks for installed addons with "plugin" in their
  name. It checks each one is written for SpyGlass and loads those that are.
- **Filter buttons:** a plugin can add its own button, such as **Quests**, next to Dungeons and
  Raids. All includes plugin items too.
- **Journal tabs:** a plugin can also ask for its own tab on the loot journal's instance page.
  It only gets one if it asks, and SpyGlass can say no: there's room for three plugin tabs,
  and each key belongs to one plugin.
- **Checking them:** `/sg plugins`, or Options > AddOns > SpyGlass, lists every plugin
  found and why any of them didn't load.

The first plugin is **SpyGlassPluginQuests**. It adds quest reward gear with the next step of
each quest chain, a quest window and quest tracking, plus every other known item: world drops,
vendor gear and crafted gear, each under its own button. See its own README.

## Settings

Open the settings from Options > AddOns > SpyGlass, or with `/sg options`.

- **Hide AtlasLoot minimap button:** removes AtlasLoot's book from the minimap, so it doesn't
  sit next to SpyGlass's. This changes AtlasLoot's own minimap setting, so AtlasLoot's
  options agree, and the choice survives a reload. AtlasLoot still opens with `/al`; its own
  switch for the same thing is `/al mmb`. A minimap button bar addon (such as Minimap Button:
  Forever) keeps the buttons it has gathered visible until you reload, so with one installed you
  are offered a reload and the button is gone after it. Fanny Pack, a fork of it, removes the
  button straight away, so it needs no reload.
- **Show SpyGlass minimap button:** the SpyGlass button that opens the journal.
- **Show the SpyGlass tab:** the spyglass tab on the Character window.

## What's shown by default

With your level as L:

| Item | Shown when its required level is |
|---|---|
| Most gear | L - 8 to L + 4 |
| Class-specific gear | L - 20 to L + 4 |

An item counts as class-specific when it is restricted to your class, is a libram, totem or
idol, or its effect names one of your class's spells (for example "your Frostbolt spell").

Gear your class can never use (wrong armor or weapon type, or another class's item) is hidden.
Armor and weapon types your class can learn later still show, so a warrior sees plate before
training it. Hidden items also include anything AtlasLoot's own class filter rejects for your
class, which by default includes items with stats your class has no use for.

The level window sizes are at the top of `Data.lua` (`LEVELS_ABOVE`, `LEVELS_BELOW`,
`CLASS_LEVELS_BELOW`).

## Notes

- **Requirements:** AtlasLootClassic is required, and its dungeon and raid module loads the
  first time you open the list. StatLedger is required too: it
  holds the stat priority that items are ranked by.
- **Stats** come from the game's item stats plus the item's "Equip:" lines (spell damage,
  healing, school damage, crit, hit, mp5, defense and so on). The "Equip:" lines are read in
  English only. Percent stats such as 1% crit count roughly what they're worth in item budget
  (about 14 Strength) rather than as 1 point.
- **New items** show as "Loading" until the server has sent their details. Only rows drawn on
  screen ask the server, so items load as you scroll, pick a slot or open a boss. If the
  server still hasn't answered after several tries, the row reads "Couldn't load item #..."
  instead of vanishing. Click it, or reopen the page, to try again.
- **Encrypted items** (the tooltip reads "Encrypted by Forever beta build") can't load on this
  client, so they're hidden from every list and never asked for again. The list is remembered
  between sessions and starts over when the client build changes.

## For addon authors

### Writing a plugin

1. **Name:** name the addon with "plugin" in it, for example `MyLootPlugin`.
2. **TOC fields:**
   ```
   ## Dependencies: Spyglass
   ## X-SpyGlass-Plugin: 1
   ## LoadOnDemand: 1
   ```
   `Spyglass` is SpyGlass's folder name. `X-SpyGlass-Plugin` is the plugin API version the plugin was written for.
   `LoadOnDemand: 1` is optional; with it, SpyGlass loads the plugin itself.
3. **Register** once loaded:
   ```lua
   SpyGlass:RegisterPlugin({
       addon = "MyLootPlugin", name = "My Loot", apiVersion = 1,
       category = { key = "mine", label = "Mine" },   -- a filter button
       entries = { { itemID = 1234, origin = { kind = "mine", where = 1 } }, ... },
       -- or, for several buttons: categories = { { key, label, entries = { ... } }, ... },
       origins = { mine = {
           Resolve = function(origin)  -- worked out each time the list is drawn
               return { available = true, text = "Shown on the row", lines = { "Tooltip lines" } }
           end,
           OnClick = function(origin, row) end,  -- optional
       } },
   })
   ```
   `available = false` hides the item, for example when it isn't for this character.
   `Resolve` runs for every listed item, so keep it cheap. SpyGlass keeps each answer until
   your quests, level or skills change; return `cache = false` to be asked again next time.
   For costly tooltip lines, add `Lines = function(origin) return { ... } end` to the handler:
   it runs only when the item is hovered.

4. **Ask for a journal tab** (optional), after registering:
   ```lua
   local granted, why = SpyGlass:RequestJournalTab("MyLootPlugin", {
       key = "mine", label = "Mine", icon = "Interface\Icons\INV_Misc_Book_08",
       Rows = function(inst, boss)  -- boss is nil for "All bosses"; inst.areaID is the AreaTable ID
           return { { text = "Title", subtext = "Second line", right = "Level 18", icon = "...",
                      color = { 1, 0.82, 0 }, dim = false, tooltip = { "line" },
                      onClick = function(row) end } }, "Text when there are no rows"
       end,
   })
   ```
   It's refused, with a reason, if the plugin isn't registered, another plugin has the key, or
   the three plugin tab spaces are taken.

Plugin items go through the same level window, class filter and ranking as everything else. A
plugin can also mark a place with `SpyGlass:SetWaypoint({ uiMapID, x, y, title, subtitle,
onClick, key })`, which hands it to the **Waypoint** addon's arrow. `ClearWaypoint()` removes it,
and `GetWaypoint()` returns the tracked waypoint. Without Waypoint installed tracking is off:
`HasWaypoints()` says whether it's there, so a plugin can hide its Track buttons.

### The API

SpyGlass sets a global `SpyGlass` table (`VERSION` 1; `API_VERSION`, its older name, still works; check `SpyGlass.VERSION >= 1`). The built-in journal uses only
this API, so other addons can too; see `API.lua`. It provides:
- instances and bosses from AtlasLoot, including loot that isn't recorded yet (`comingSoon`);
- ranked rows for a list of items;
- item info and usability;
- the shared tooltip and click handlers;
- a refresh callback: `SpyGlass:RegisterCallback(owner, fn)` calls `fn("REFRESH")` when the lists should be
  redrawn (dot or colon call; one callback per owner; see `addons\shared\API.md`).
