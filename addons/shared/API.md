# The suite's public APIs

Every global one of our addons (the ones in `addons\myaddons.txt`) offers other addons, and how
the addons plug into each other. Read the code before trusting a line here: the definitions are
cited for each global.

## 1. How an API is made: `ns.NewAPI`

`addons\shared\API.lua` (loaded by Bandolier, BattleRecap, Fireside, Quartermaster,
SimplePanel, Spyglass, StatLedger, Wally, Waypoint, WealthPlanner, ZeppelinSigns):

```lua
local API, Fire = ns.NewAPI("BandolierAPI", 1)   -- the global table, and the addon's own Fire
function API.Something(...) ... end
Fire("USAGE")                                    -- runs every registered callback
ns.APIListener(API, "OnUsage", "USAGE")          -- keeps an older one-function hook working
```

What the table gets:

| Field | What it does |
|---|---|
| `VERSION` | A number, 1 unless the addon says otherwise. Raised when functions are added. Some APIs also keep `API_VERSION` (or Wally's `version`), the older name, equal to `VERSION`. |
| `RegisterCallback(owner, fn)` | `fn(event, ...)` runs on every event the addon fires. `owner` is any non-nil value, usually your addon's name. One callback per owner: registering again replaces it (and keeps its place). |
| `UnregisterCallback(owner)` | Removes the owner's callback. Safe during a Fire (a removed callback is skipped). |

- Callbacks run in the order they were registered.
- An error in a callback goes to `geterrorhandler()` (the error window); it never stops the addon
  firing, nor the other callbacks.
- Dot and colon both work: `API.RegisterCallback("Me", fn)` and `API:RegisterCallback("Me", fn)`.
- `Fire` is local to the owning addon: other addons can't fire its events.
- Calling `ns.NewAPI` again with the same name (another file of the same addon) returns the same
  table and `Fire`; a higher version number raises `VERSION`.
- `ns.APIListener(api, name, event)` adds `api[name](fn)`: `fn(...)` for that event only, or
  `fn(event, ...)` for every event when `event` is nil. These old hooks can't be replaced or
  unregistered. Use `RegisterCallback` in new code.

### Conventions for new hooks

- Make the global with `ns.NewAPI("<Addon>API", version)`; don't hand-roll a listener list.
- Event names are UPPERCASE (`"CHANGED"`, `"RECAP"`). Waypoint before `VERSION` 2 and
  ZeppelinSigns before `VERSION` 2 used lowercase names; to work with both, compare with
  `event:upper()` (FieldGuide's `Engine.lua` and WealthPlanner's `Nav.lua` do).
- Before using a function that came in a later version, check it:
  `if X and X.VERSION and X.VERSION >= 2 then ... end` (or check the function itself:
  `if X and X.Fn then`). This works for every suite API: `VERSION` is always a number.
  `API_VERSION` is the older name some APIs keep, equal to `VERSION`; release strings are in
  `SimplePanel.RELEASE` and `WallyHUD.RELEASE`.
- Never call another addon's API at file load without checking that it exists. Load order is set
  only by the TOC: `## Dependencies` makes the other addon load first (and makes yours need it);
  `## OptionalDeps` makes it load first when it's installed. Without either, it may load after
  you, so call it from `PLAYER_LOGIN` or later, or at the moment you need it.
- Wrap calls into another addon in `pcall` where a failure would break your own feature (the
  suite does this almost everywhere).
- Player names are realmless "Given Family" on Forever: compare keys with `ns.Units.Same`, never `==`.

## 2. The globals

Callers are the files outside the provider that use the global. `shared\X.lua` callers run in every
addon whose TOC loads that shared file (listed).

### BandolierAPI

Provider: Bandolier (`Bandolier\API.lua`). `VERSION` 1. Usage is read from your bags: a consumable
whose count went down counts as used (not while a vendor, bank, mail, trade, AH or guild bank
window is open, or with an item on the cursor). Kept 30 days, per character.

| Function | Returns |
|---|---|
| `Category(itemID [, name])` | Bandolier's kind of consumable (`"Healing"`, `"Food"`, `"Elixir"`...), or nil when Bandolier wouldn't use it. Needs the item's data loaded for items not in Bandolier's tables. |
| `RecentlyUsed([days=7])` | `{ { id, used, last } }`, most used first (`used` = count in the last `days`, `last` = `time()` of the latest use). |
| `Used(itemID [, days=7])` | How many you used in the last `days`. |
| `OnUsage(fn)` | Old hook: `fn()` on each `USAGE`. |

| Event | Args | Fired |
|---|---|---|
| `USAGE` | none | After a bag rescan records a new use. |

Callers: Quartermaster (`ConsumablesPage.lua`: `Category`, `RecentlyUsed`, `Used`, `OnUsage` at file
load; Quartermaster lists Bandolier in OptionalDeps).

### BattleRecapAPI

Provider: BattleRecap (`BattleRecap\Core.lua`, after `ns:AddRecap`). `VERSION` 1.

| Function | Returns |
|---|---|
| `Nemeses()` | Enemy players who've killed you, most kills first: `{ { key = "Given Family", name, class, kills, last } }`. Pets and NPCs left out. |
| `RevengeTarget()` | Who the Revenge key targets: your last killer's name, or nil. |
| `OnRecap(fn)` | Old hook: `fn(recap)` on each `RECAP`. |

| Event | Args | Fired |
|---|---|---|
| `RECAP` | `recap` (the saved recap table) | Each time a recap is saved, after its death is counted in the stats. |

Callers: SmartPlates (`Plugins\Nemesis.lua`: `Nemeses`, `RevengeTarget`, `OnRecap` at file load;
OptionalDeps BattleRecap).

### FiresideAPI

Provider: Fireside (`Fireside\History.lua`, end of file; `DeathPopupShown` in
`DeathPopup.lua`). `VERSION` 1. `name` is a player's name in any shape (`"Given Family"`,
`"GivenFamily"`, `"Given Family-Server"`); `guid`, when given, supplies the name when there's none
or only the given name.

| Function | Returns |
|---|---|
| `Get(name [, guid])` | `{ full, rating (1 / -1 / nil), runs, finished, wipes, deaths, bosses, note, last, summary, knownFor }`, or nil if you've never grouped with (nor marked or noted) them, and nobody has praised them to you. `knownFor` is `{ { id, label, givers } }`, the kudos that reached you, most givers first; `summary` leads with them and never mentions faults. |
| `Show(name [, guid])` | Opens the Fireside window on the player. |
| `SetRating(name, guid, rating)` | Your private "would group again" (1) or "wouldn't" (-1); the same value again clears it. Never sent to anyone. |
| `SetNote(name, guid, note)` | Your note; `""` clears it. |
| `DeathPopupShown()` | Whether Fireside's death popup is up. |

| Event | Args | Fired |
|---|---|---|
| `CHANGED` | none | After what Fireside knows changes (a run, a kudo, a mark, a note), at most once a frame. |

Callers: SimplePanel (`Fireside.lua`: `Get`, `Show`, `SetRating`, `SetNote`;
`Plugins\Social.lua`: `Get`; OptionalDeps Fireside), MrMiyagi (`Coach.lua`: `DeathPopupShown`).
No one registers for `CHANGED` yet.

### QuartermasterAPI

Provider: Quartermaster (`AuctionTab.lua`, `Lists.lua`, `ConsumablesPage.lua`). `VERSION` 1. No events.

| Function | Returns |
|---|---|
| `SearchAuction(text)` | Opens the Buying tab and searches the auction house for `text` (an item name). `true` when the search started (the AH must be open). |
| `SetShoppingList(name, items)` | Fills the list `name` (made if missing), replacing its contents; makes it the Cart's list and opens the Cart tab if the AH is open. `items = { { id, qty [, maxUnit] } }` (`maxUnit`: the most to pay per unit, copper). Returns how many items are on the list (0 on bad arguments). |
| `NewShoppingList(name, items)` | Same, but always a new list (`" (2)"`, `" (3)"`... if the name is taken). Returns the item count and the list's final name. |
| `ShowConsumables()` | Opens the Consumables page. `false` without Bandolier. |

Callers: Bandolier (`Core.lua`, `/bandolier stock`: `ShowConsumables`), WealthPlanner
(`Invest.lua`: `SearchAuction`, `NewShoppingList`; `InvestTab.lua`: checks `SetShoppingList`).

### WealthPlannerAPI

Provider: WealthPlanner (`WealthPlanner\API.lua`). `VERSION` 2 (2 = the shared registry; no events yet).

| Function | Returns |
|---|---|
| `Price(itemID)` | `copper, timeSeen`: today's close, else the newest sample, else Auctionator's price; or nil. |
| `Stats(itemID)` | A copy of `{ price, normal (30-day median), ma7, ma30, chg7, chg30, days (of history), signal = "buy"/"sell"/"hold", reason }`, or nil. |
| `Normal(itemID)` | The 30-day normal, or nil. |

Callers: `shared\AuctionPrice.lua` (`Stats`), so Quartermaster, Wally and WealthPlanner itself.

### ZeppelinSignsAPI

Provider: ZeppelinSigns (`ZeppelinSigns\Rides.lua` ~line 330). `VERSION` 2 (2 = upper-case event names).

| Function | Returns |
|---|---|
| `Ride()` | The ride you're on, or nil: `{ key, kind ("zeppelin"/"ship"), from, dest, fromKey, toKey, landing = { mapID, x, y } or nil, elapsed, left (seconds), timed, arriving }`. |
| `RideTime(key)` | `seconds, timesTimed` for a dock's ride from boarding; nil if never timed. |
| `OnChange(fn)` | Old hook: `fn(event)` on every event. |

| Event | Args | Fired |
|---|---|---|
| `BOARD` | none | A ride starts (carried off the dock). |
| `ARRIVE` | none | It lands. |
| `CANCEL` | none | It turned out not to be a ride. |

Before `VERSION` 2 these were lowercase (`board`, `arrive`, `cancel`).

Callers: Waypoint (`Route.lua`: `Ride`, `OnChange` at file load, OptionalDeps ZeppelinSigns;
`TransportPins.lua`: `RideTime`). Waypoint also reads `ZeppelinSignsDB` directly (`Route.lua`
`ZepDB`, for moved and added signs).

### WallyAPI

Provider: Wally (`Wally\API.lua`). `VERSION` 3 (also `version`, the field's older name, same value).
Plugins list Wally in `## Dependencies`, so it exists when they load.

| Function | Returns |
|---|---|
| `RegisterTab(key, label, icon, builder)` | Adds a tab to Wally's window, above Settings (see section 3). `false` once the window is built (the tab shows after a /reload). |
| `Show(key)` | Opens the window on a tab. |
| `Toggle()` | Opens or closes the window. |
| `ActiveTab()` | The tab showing. |
| `Refresh()` | Redraws the window. |
| `OnChanged(fn)` | Old hook: `fn()` on each `CHANGED`. |
| `AuctionsEnabled()` | Whether the auction features are on (modern AH and Auctionator). |
| `AuctionsOnMarket()` | `list, seen, live`: a copy of `{ { key, link, icon, quantity, unit, expires, exact, someSold } }`, when it was seen, whether it's live from the AH. |
| `AuctionHistory()` | Auctions you posted and cancelled, newest first, read only: `{ { t, link, count, unit, duration, byWally, cancelled } }`. |
| `OnAuctionList(name)` | Whether an item (by name) is on the Auction List. |
| `SellOnce(item, how)` | Queues an item (link or ID) to sell once: `how = "auction"` (Ready to Post, for you to approve) or `"vendor"` (sold with the junk), nil to unqueue. `false` when the item isn't loaded yet. |
| `SellingOnce(item)` | `"auction"`, `"vendor"` or nil. |
| `SortBags()` | Sorts the bags with your Bag Sorting rules (prints why when it can't). Version 3. |
| `IsSorting()` | Whether a sort is running. |
| `AutoSort(when)` / `SetAutoSort(when, on)` | Auto sort after `"bags"` close, `"merchant"` or `"mail"` closes. |
| `IsAnchored(bag, slot)` / `SetAnchor(bag, slot, on)` | Anchored items (ctrl-right-click in the bags) are never moved by sorting. `SetAnchor` anchors whatever is in the slot now. |
| `Anchors()` | `{ { bag, slot, id } }`, every anchored item still in its slot. |
| `HighlightBag(bag)` | Lights up one bag's slots in Wally's bag window (`nil`: none). |
| `HoldSorting(owner, on)` | Holds sorting (auto sorts too) off while another addon moves items. |
| `FireChanged()` | Wally's own (it fires `CHANGED`); not for other addons. |

| Event | Args | Fired |
|---|---|---|
| `CHANGED` | none | After Wally's data changes (lists, auctions, sales), at most once a frame. |

Callers: WealthPlanner (`UI.lua`: `RegisterTab` at file load, `Show`, `Toggle`, `OnChanged`;
`Minimap.lua`: `Toggle`; `Invest.lua`: `AuctionsOnMarket`, `OnAuctionList`; `InvestTab.lua`:
`SellOnce`, `SellingOnce`; `Portfolio.lua`: `AuctionsOnMarket`); SimplePanel (`Plugins\Bags.lua`: the
sorting functions, version 3 or later).

### StatLedger (and StatPriority)

Provider: StatLedger (`StatLedger\Core.lua`, `Convert.lua`; StatLedger's README.md). `StatPriority`
is the same table under its old name (no callers left). Built with `NewAPI`: `VERSION` 1 (`API_VERSION`
the same), `MAX_SLOTS`. Call its functions with a colon (`StatLedger:GetPriority()`); the registry
takes dot or colon. `class` is a class token (`"MAGE"`), `spec` a talent tab (1-3); both
default to the player's. Getters return copies.

| Function | Returns |
|---|---|
| `GetActiveSpec()` | `class, spec, specName`. |
| `GetStats()` / `GetStatLabel(stat)` | Every stat key / a stat's label. |
| `GetClasses()` / `GetClassName(class)` | Class tokens / a class's name. |
| `GetSpecs(class)` / `GetSpecName(class, spec)` | `{ "Arms", "Fury", "Protection" }` / one name. |
| `GetDefaultPriority(class, spec)` | The default ranked list of stats. |
| `GetPriority(class, spec)` | Your list if you changed it, else the default. |
| `IsCustom(class, spec)` | Whether you changed it. |
| `GetWeights(class, spec)` | `{ [stat] = weight }`: 1.0 for the first, falling evenly to 0.1 at the last. |
| `SetPriority(class, spec, list)` | Saves a list (unknown stats and repeats dropped; equal to the default = not stored). |
| `SetSlot(class, spec, slot, stat)` | Puts a stat in a slot (`nil`/`"NONE"` clears it). |
| `MoveStat(class, spec, from, to)` / `RemoveStat(class, spec, stat)` / `InsertStat(class, spec, stat [, index])` | Edits the list. |
| `GetRemovedStats(class, spec)` | Stats not in the list, standard order. |
| `ResetPriority(class, spec)` | Back to the default. |
| `Describe(class, spec)` | `"Strength > Stamina > ..."`. |
| `Score(values [, weights])` | `total, contrib` for `{ [stat] = amount }`; weights default to `GetWeights()`. |
| `Value(stat, amount [, weights])` / `Budget(stat, amount)` / `IsPercent(stat, amount)` | One stat's worth / its item budget / whether it's a percent stat. |
| `RegisterCallback(owner, fn)` / `UnregisterCallback(owner)` | The shared registry: one callback per owner, `fn(event, class, spec)`. |

| Event | Args | Fired |
|---|---|---|
| `PRIORITY_CHANGED` | `class, spec` | A spec's list was changed or reset. |
| `SPEC_CHANGED` | `class, spec` | Your detected spec changed. |
| `VALUES_CHANGED` | none | Level-up: what stats are worth changed. |


Callers: Bandolier (`Core.lua`, `Stats.lua`; Dependencies StatLedger), Spyglass (`Scoring.lua`,
`Journal\Professions.lua`; Dependencies StatLedger), TapeMeasure (`Core.lua`, `Stats.lua`, `UI.lua`;
Dependencies StatLedger), Wally (`Gear.lua`; OptionalDeps StatLedger), `shared\GearEngine.lua`
(Spyglass, TapeMeasure, Wally), `shared\Player.lua` (`GetActiveSpec`; Bandolier, MrMiyagi,
SimplePanel, Spyglass, SpyglassPluginQuests, StatLedger, Wally, WealthPlanner).

### SpyGlass

Provider: Spyglass (`Spyglass\API.lua`; Spyglass's README.md, "Writing a plugin"). Built with
`NewAPI`. Call its functions with a colon; the registry takes dot or colon. Version numbers:
`VERSION` 1 (the whole API; `API_VERSION` the same), `PLUGIN_API` 1 (`RegisterPlugin`),
`EMBED_API` 1 (the gear list in another window). Instances and rows are SpyGlass's own tables: read only.

| Function | Returns |
|---|---|
| `Load(onReady)` | Calls `onReady` once the loot data is ready (at once: it's shipped). `true`. |
| `GetInstances()` | Every dungeon and raid, by level (fields: `AtlasData.lua`). |
| `Rows(itemIDs [, filter [, inst [, sourceOf]]])` | `rows, loading`: scored rows, best first; `filter = { showAll, slot, search, keepZero }`. Rows may be `{ placeholder = true }` for items still loading. |
| `PeekItem(itemID)` / `InstantItem(itemID)` / `ItemInfo(itemID)` | The item's details without asking the server / what's known instantly (`equipLoc, icon, subType, classID, subClassID`) / `{ name, link, quality, itemLevel, reqLevel, icon, equipLoc, subType }` or nil (it's asked for). |
| `RequestItem(itemID)` | Asks the server (paced, retried); callbacks fire when it arrives. |
| `EffectStats(itemID)` | `{ [stat] = amount }` an item's Equip: effects are worth. |
| `Usable(itemID)` | `true`, or `false, reason` (`"Plate"`, `"Level 34"`). |
| `IsClassSpecific(itemID)` | Whether it's a class item. |
| `WindowText()` / `Describe()` / `UpgradeText(row)` / `QualityColor(quality)` | Display strings and colours. |
| `ItemTooltip(row)` / `ItemClick(row, button)` | OnEnter / OnClick handlers for a button showing a row (plain functions, dot call). |
| `RegisterPlugin(def)` | Adds a plugin's items and origin kinds (section 3). `true`, or `false, why`. |
| `RequestJournalTab(addon, tab)` | A tab on the loot journal's instance page for a registered plugin (at most 3). `true`, or `false, why`. |
| `AddWorldInstances(list)` | Adds open-world places to the journal's World tab (same key again replaces). |
| `SetKnownCheck(kind, fn)` | Tells "Contribute data" what a plugin already knows: `fn(a, b)` true for a known fact; kinds `Q`, `R`, `L`, `V`, `B`. |
| `HasWaypoints()` / `SetWaypoint(wp)` / `ClearWaypoint()` / `GetWaypoint()` | Waypoint's arrow under the owner `"SpyGlass"` (nothing without Waypoint). |
| `IsGearListWanted()` / `EmbedGearList(host, onChange)` / `ReleaseGearList()` / `GearListHost()` / `GearListSlotInfo(slotID)` / `GearListClickSlot(slotID)` | The gear list inside another addon's window. `EmbedGearList` returns `true`, or `false, why`; `onChange()` runs when the slot filter or grades change. |
| `RequestRefresh()` / `RefreshSettings()` | Redraw the lists and journal soon / the settings page. |
| `OpenInAtlasLoot([instKey [, bossIndex]])` | Opens AtlasLoot there. |
| `RegisterCallback(owner, fn)` / `UnregisterCallback(owner)` | The shared registry: one per owner, `fn("REFRESH")` when the lists should be redrawn. |

| Event | Args | Fired |
|---|---|---|
| `REFRESH` | none | The lists should be redrawn: item details arrived, your level, gear or stat priority changed. |

Callers: SpyglassPluginQuests (`Plugin.lua`, `Quests.lua`, `QuestWindow.lua`, `Sources.lua`:
`RegisterPlugin`, `RequestJournalTab`, `SetKnownCheck`, `AddWorldInstances`, the waypoint and item
functions; Dependencies Spyglass), SimplePanel (`CharacterSheet.lua`: the `EMBED_API` functions),
`shared\GearEngine.lua` (`EffectStats`; Spyglass, TapeMeasure, Wally).

### SpyGlassJournal

Provider: Spyglass (`Spyglass\Journal\Journal.lua`). No version. Colon calls.

| Function | Returns |
|---|---|
| `Toggle()` / `Open()` | The loot journal. |
| `OpenTo(instKey [, bossIndex [, itemID]])` | Opens on an instance (AtlasLoot key) and boss; with `itemID`, the Loot tab on that item. |
| `IsMinimapShown()` / `SetMinimapShown(on)` | The journal's minimap button. |

Callers: none outside Spyglass.

### Waypoint

Provider: Waypoint (`Waypoint\API.lua`; events fired in `Targets.lua`). Built with `NewAPI`:
`VERSION` 2 (2 = upper-case event names; `API_VERSION` the same). Call its functions with a colon;
the registry takes dot or colon.
`owner` is your addon's name: one target, one button, one manager per owner.

| Function | Returns |
|---|---|
| `Set(owner, wp)` | Your target: `{ title, subtitle, mapID, x, y` or `points = { ... }, arrive, next, upcoming, color ("gold"/"green"/"purple"), key, onClick(entry), onArrive(entry) }`. Setting again replaces it. The newest target is the one the arrow follows. Saved without its functions: Set again after a reload. |
| `Get(owner)` / `Clear(owner)` | Your target (plus `owner`, `points`) or nil / removes it. |
| `GetCurrent()` | `entry, point`: what the arrow aims at (`entry.owner` is an addon, `"path"` or `"Questie"`). |
| `Request(owner, wp)` / `ClearRequest()` | A one-off "go here first" above every target; points may carry `npc`; `ordered = true` for stops in turn. |
| `NavigateTo(category [, owner])` | A request to the nearest place of a category (`"Repair"`, `"Mailbox"`, `"Class trainer"`...). |
| `NavigateToUndiscoveredFlight([owner])` | The nearest flight master you haven't found. |
| `NavigateToItems(itemIDs, title, owner [, auction])` | The vendors for the items, as stops; `auction = { { id, name } }` ends at an auctioneer. |
| `PlaceCategories()` | `{ { name, ids, menu path, class, count } }`. |
| `SoldByVendors(itemID)` | How many vendors sell it (any faction), or 0. |
| `PromptVendors(items, onAddAnyway, owner [, auction])` | One popup: Navigate / Add anyway (`onAddAnyway(items)`) / Cancel. |
| `GetFrame()` / `Dock(frame)` / `Undock(frame)` | The arrow's frame / dock a window under it (returns the arrow's frame). |
| `SetButton(owner, button)` | A button on the arrow: `{ text, color, tooltip, onClick [, icon, iconPushed] }`; nil removes it. |
| `TrackQuest(owner, questID)` / `UntrackQuest(owner, questID)` / `QuestTrackedBy(questID)` / `TrackedQuests()` | Quest tracking with a record of who tracked what (`"user"`, an addon's name). |
| `SetManager(owner, m)` | Own the arrow: `{ name, restore(), expected(), yield(), pause() }`; nil gives it up. |
| `RegisterCallback(owner, fn)` / `UnregisterCallback(owner)` | The shared registry: one per owner, `fn(event, entry)`. |

| Event | Args | Fired |
|---|---|---|
| `CHANGED` | `entry` (may be nil) | The arrow follows something else. |
| `ARRIVED` | `entry` | You reached a single-place target. |
| `CLEARED` | `entry` | You stopped a target from the arrow (`entry.owner` says whose). |

Before `VERSION` 2 these were lowercase; FieldGuide and WealthPlanner compare with `event:upper()`.

Callers: FieldGuide (`Engine.lua`: `Set`, `Get`, `Clear`, `SetButton`, `SetManager`,
`RegisterCallback`, `TrackQuest`, `UntrackQuest`, `TrackedQuests`; `UI.lua`: `Dock`, `Undock`;
Dependencies Waypoint), Convergence (`Convergence.lua`: `Set`; OptionalDeps), WealthPlanner
(`Nav.lua`, `MapPins.lua`: `Set`, `Get`, `Clear`, `RegisterCallback`; OptionalDeps), Quartermaster
(`Reagents.lua`: `SoldByVendors`, `PromptVendors`; OptionalDeps), Spyglass (`API.lua`: `Set`, `Get`,
`Clear`, behind its own waypoint functions; OptionalDeps).

Waypoint also reads `RoadLogDB` (RoadLog's saved roads, passes and blockers, `Route.lua`) and
`ZeppelinSignsDB` directly; both are OptionalDeps.

### SimplePanel

Provider: SimplePanel (`SimplePanel\Core.lua` and the files below). `VERSION` 1 (the API's
version); the release string (`"0.1.4"`) is `SimplePanel.RELEASE`. Dot calls. SimplePanel has no
events of its own.

| Member | What it is |
|---|---|
| `RegisterPlugin(def)` | A bar plugin (section 3). `PluginKit.lua`. |
| `UnregisterPlugin(id)` / `GetPlugin(id)` / `ListPlugins()` | Remove one (its saved layout stays) / find one by id or name / every id. |
| `SetDensityHidden(set)` | `{ [id] = true }` plugins to hide for now (WallyHUD's density presets); also kept as `SimplePanel.densityHidden`. |
| `RegisterLauncher(button, name)` | Hands a minimap button to the launcher drawer (section 3). `Launchers.lua`. |
| `Menu` | `Menu:New([anchor])` builder: `Title`, `Checkbox`, `Radio`, `Submenu`, `Slider`, `Color`, `Input`, `Divider`, `Header`, `Button`, `Show` (`Menu.lua` header). |
| `Tooltip` | `Tooltip:Begin(owner)`, then `SetTitle`, `AddDouble`, `AddChart`, `AddHint`, `Show`... (`Tooltip.lua`). |
| `Chart` | The shared chart renderer (`shared\Chart.lua`) in SimplePanel's theme. |
| `Theme` | SimplePanel's colours (`Widgets.lua`). |
| `RangeSeconds(range)` | Seconds in `"15m"`, `"1h"`, `"2d"`; nil for `"session"`/`"all"`. |

Callers: `shared\MinimapButton.lua` (`RegisterLauncher`; BattleRecap, FieldGuide, Fireside,
MrMiyagi, Quartermaster, RoadLog, SmartPlates, Spyglass, TapeMeasure, Wally, Waypoint,
WealthPlanner), WallyHUD (`Density.lua`: `ListPlugins`, `SetDensityHidden`). Nothing outside
SimplePanel calls `RegisterPlugin`, `Menu`, `Tooltip` or `Chart` yet. SimplePanel also turns
LibDataBroker objects into plugins and launchers (`LDB.lua`) when another addon loaded LibDataBroker.

### SimplePanelProfessions

Provider: SimplePanel (`SimplePanel\ProfessionsPanel.lua`, its own professions window). Built with
`NewAPI`: `VERSION` 1 (`API_VERSION` the same). Dot calls (colon works for the registry).

| Function | Returns |
|---|---|
| `GetFrame()` | The window (for anchoring), shown or not; nil before it's built. |
| `IsCrafting()` | Whether this window holds the open profession. |
| `GetSelectedRecipeID()` | The recipe shown, or nil. |
| `SelectRecipe(recipeID [, name])` | Shows the recipe once its profession is open here. |
| `RegisterCallback(owner, fn)` / `UnregisterCallback(owner)` | The shared registry: one per owner, `fn("CHANGED")`. |

| Event | Args | Fired |
|---|---|---|
| `CHANGED` | none | The window opens or closes, or the recipe shown changes. |

Callers: Quartermaster (`Reagents.lua`: `GetFrame`, `GetSelectedRecipeID`, `RegisterCallback`),
Spyglass (`Journal\Professions.lua`: `IsCrafting`, `GetSelectedRecipeID`, `SelectRecipe`).

### WallyHUD

Provider: WallyHUD (`WallyHUD\Tokens.lua`, `Primitives.lua`, `Palettes.lua`, `Minimap.lua`). The
suite's design system. `VERSION` 1 (the API's version); the release string (`"0.1.0"`) is
`WallyHUD.RELEASE`. No events. It loads last (its TOC lists every
addon of ours in OptionalDeps), so other addons must check `WallyHUD and WallyHUD.X` at the time
they draw, or use the hook tables below.

| Member | What it is |
|---|---|
| `Tokens` | The design tokens: `surface`, `border`, `text`, `accent`, `accentDim`, `state`, `gold`, `space`, `weights`, `font`, `fontStrong`, `panel`, `edge`... |
| `Face(weight)` / `SuiteFace(weight)` | The suite's font file at a weight; `SuiteFace` is nil when the shared look is off. |
| `SuiteFont(entry)` | Sets a `{ font, source }` font object in the suite's face. |
| `FontLabel` / `FontBody` / `FontNumber` / `FontTitle` | Font objects. |
| `Over(top, under)` / `Hex(c)` / `RGBA(c [, a])` | Colour helpers. |
| `Upper(text)` | A label in capitals. |
| `WHITE` | The flat texture path. |
| `Panel(frame [, kind])` / `HoverEdge(frame)` / `Hairline(frame [, "TOP"])` | Surfaces: `kind` `"base"`/`"raised"`/`"sunken"`; `Hairline` returns the texture. |
| `UnderlineTab(tab, label)` / `SetTab(tab, active)` | Underline tabs. |
| `GhostIcon(button, icon)` | Desaturated icon, colour on hover. |
| `PaletteColors` / `RepaintAll()` / `SimplePanelPalette()` | The palette map, the repaint, SimplePanel's "Wally" scheme. |
| `MinimapButtonList()` | The addon minimap buttons (cached 5 s). |
| `db` | WallyHUD's saved settings, read only. |

Hook tables (globals any addon fills before WallyHUD loads; WallyHUD never needs to know the addon):

| Global | Put in it | WallyHUD does |
|---|---|---|
| `WallyHUD_Palettes` | Your palette table (`bg`, `border`, `button`, `hover`, `row`, `panel`, `field`, `accent`, `muted`, each `{ r, g, b }`) | Repaints it in place to the tokens on its ADDON_LOADED, before windows are built. |
| `WallyHUD_Fonts` | `{ font = fontObject, source = "GameFontNormal" }` | Sets each in the suite's face on load. |
| `WallyHUD_Refresh` | A function | Calls it once at login (after everything loaded) to redraw in the shared look. Skipped with the shared look off. |

Callers: `shared\Palette.lua` and Waypoint (`Flight.lua`) fill `WallyHUD_Palettes`; `shared\Fonts.lua`
fills `WallyHUD_Fonts` (17 addons); SaddleBags (`Core.lua`) fills `WallyHUD_Refresh`. Functions:
SaddleBags (`Panel.lua`: `Tokens`, `Panel`, `RGBA`, `UnderlineTab`, `SetTab`, `Upper`, `WHITE`,
`FontLabel`), FieldGuide (`UI.lua`: `Panel`, `RGBA`, `Tokens`), Waypoint (`Arrow.lua`: `Panel`,
`SuiteFace`), SimplePanel (`Widgets.lua`: `Face`, `SimplePanelPalette`; `Plugins\Minimap.lua`:
`MinimapButtonList`, `Tokens`, `db`), WallyChat (`Core.lua`: `SuiteFace`, `Tokens`), SmartPlates
(`Media.lua`), TapeMeasure (`Bags.lua`), ZeppelinSigns (`ZeppelinSigns.lua`, `Rides.lua`): `SuiteFace`;
`shared\Window.lua`: `Tokens`, `RGBA`, `SuiteFont`.

### Other globals (not APIs)

| Global | Provider | Note |
|---|---|---|
| `SaddleBags` | SaddleBags (`Core.lua`) | The addon's whole namespace, made global for its key bindings (`Bindings.xml`). Not meant for other addons. |
| `WallyChat`, `WallyTooltip` | WallyChat, WallyTooltip | Empty tables (a name only); no functions. |
| `<Addon>_OnCompartmentClick` | `shared\Core.lua` | The addon compartment's click handler, set per addon. |

## 3. Plugging in

| Scheme | Adds | Signature | When to register | Used by |
|---|---|---|---|---|
| `SimplePanel.RegisterPlugin(def)` | A plugin on SimplePanel's bar: text, icon, tooltip, menu, chart, progress bar, secure click. | `def = { id (required), name, title, category, icon, label, zone, defaultEnabled, scope, defaults, events, interval, series, spark, progress, text, tooltip, menu, chart, chartRanges, onClick, onWheel, secure, indicators, onInit, onEnable, onDisable, ... }`; returns the plugin object (`p:Refresh()`, `p:Get(k)`, `p:Set(k, v)`, `p:On(event, fn)`, `p:Every(sec, fn)`, `p:Record(...)`...). A missing `id` is an error; an id already taken prints a warning and returns the existing plugin. Full list: `PluginKit.lua` header. | Any time. Before the bar exists (login) it's queued; after, it starts at once. | SimplePanel's own `Plugins\*.lua` and `Config.lua`; no other addon yet. |
| `SimplePanel.RegisterLauncher(button, name)` | Your minimap button in the launcher drawer (SimplePanel decides where it shows). | `button` must have a global frame name (placement is keyed by it); `name` is the drawer's label. Returns `true`; raises an error before SimplePanel's saved variables are loaded (call it in `pcall`). In combat it waits until combat ends. | After SimplePanel's ADDON_LOADED: when the button is made (`shared\MinimapButton.lua` does it at Init). Buttons not handed over are found by SimplePanel's scans after login. | Every addon using `shared\MinimapButton.lua` (12, listed above). |
| `WallyAPI.RegisterTab(key, label, icon, builder)` | A tab in Wally's window, above Settings. | `icon` is an icon name (`"INV_Misc_Coin_01"`) or a texture path; `builder(page)` fills the page (586 x 466); set `page.Refresh` to redraw whenever Wally refreshes while the tab shows. Returns `true`, or `false` once the window is built. | At file load, before the window is built (list Wally in `## Dependencies`). Later tabs appear after a /reload. | WealthPlanner (`UI.lua`, the Wealth tab). |
| `SpyGlass:RegisterPlugin(def)` | Items in SpyGlass's gear list with where each comes from, as filter buttons; origin kinds that say whether an item is available and what to show. | `def = { addon, name, apiVersion, category = { key, label }, entries = { { itemID, origin = { kind, ... } } }` or `categories = { { key, label, entries } }`, `origins = { [kind] = { Resolve(origin), Lines(origin), OnClick(origin, row) } } }`. Returns `true`, or `false, why` (no addon name, or `apiVersion` above `PLUGIN_API`). Then `SpyGlass:RequestJournalTab(addon, tab)` for a journal tab. | Any time after Spyglass loads; the plugin's TOC needs `## Dependencies: Spyglass` and `## X-SpyGlass-Plugin: 1` (Spyglass checks both and loads LoadOnDemand plugins at login). | SpyglassPluginQuests (`Plugin.lua`, after its quest scan finishes). |
