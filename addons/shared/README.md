# shared

Lua that several addons load. It is not an addon: it has no TOC, and `yarn test` / `yarn deploy`
never install or publish it on its own.

An addon loads a shared file by listing its real path in its TOC:

```
Compat.lua
..\shared\Secrets.lua
..\shared\DeathRecap.lua
Core.lua
```

Every build (the dev copy `yarn test` installs, and the release zips) copies each listed file into
that addon's own `Shared\` folder and rewrites the line to `Shared\DeathRecap.lua`, so the game
only ever sees files inside the addon. Files that an XML file listed this way loads come along too.
`yarn test:watch` re-syncs every addon that loads a shared file when it changes. `yarn lint`
checks that every `..\shared\` line names a file that's here.

Each addon gets its own copy, loaded into its own namespace (`local _, ns = ...`), so the copies
never clash and an addon can't break another by shipping an older one. Write shared files that
way: no globals, everything on `ns`.

The addons run only on WoW Forever (Interface 16001, the 12.x engine), so nothing here branches on
the client. An old global stays behind a modern API's guard (`C_Container.X or GetContainerX`) until
code in this repo calls that modern API unguarded, which confirms Forever has it.

| File | Gives | Used by |
|---|---|---|
| `Core.lua` | Every addon's start (first in its TOC): `ns:On` events, saved variables from `ns.SAVED` + `ns.DEFAULTS`/`ns.CHAR_DEFAULTS` (array-safe `ns.Merge`), `ns:OnLoad`, `ns:Migrate`, `ns:Print`/`ns:Debug`, `ns:Changed`/`ns:OnChanged`, `ns.Soon`, `ns.Every`, `ns:AfterCombat`, `ns:Slash`, `ns:Compartment`, `ns.IconMarkup`, `ns.VERSION` | every addon |
| `API.lua` | `ns.NewAPI(globalName, version)`: an addon's public global with `VERSION` and one callback registry (`RegisterCallback(owner, fn)`, `UnregisterCallback(owner)`, a `Fire(event, ...)` for the addon); `ns.APIListener` keeps older one-function hooks. Every API is listed in `API.md` | Bandolier, BattleRecap, GroupHistory, Quartermaster, Wally, WealthPlanner, ZeppelinSigns |
| `Fonts.lua` | `<Addon>GameFont…` copies of the game fonts, registered with WallyHUD for the suite face | every addon except Convergence, MusicLib, RoadLog, SimplePanel, WallyChat, WallyHUD, WallyTooltip |
| `Palette.lua` | `ns.Palette`, the colour table WallyHUD repaints; `## X-Accent: r g b` in a TOC sets that addon's accent | BattleRecap, GroupHistory, MrMiyagi, Quartermaster, SmartPlates, TapeMeasure, Wally, WealthPlanner |
| `OptionsPage.lua` | `ns.NewOptionsPage(def)`: the addon's Options > AddOns page (headers, checkboxes, sliders, dropdowns, buttons, canvas subpages), and the option store every UI changes settings through (`ns:GetOption`, `ns:SetOption`, `ns:ToggleOption`, `ns:OptionChanged`, `ns:OnOptionChanged`), so the page, the addon's own windows and its slash commands always agree | every addon except Convergence, MusicLib, SaddleBags, SpyglassPluginQuests, StatLedger |
| `Widgets.lua` | `ns.Widgets`: buttons, labels, checkboxes, edit boxes, hints, confirm popups, item names and icons, and the scrolling row list (status, marker, bar, spark, two-line right column, actions); per-addon fonts and `ns.Palette` colours, `W.style` switches | BattleRecap, GroupHistory, MrMiyagi, Quartermaster, SmartPlates, TapeMeasure, Wally, WealthPlanner |
| `WidgetsPlus.lua` | More of `ns.Widgets`: menus, dropdowns, column headers, number/range/link boxes, ask-text and three-way prompts, quantity dialog, category tree, cursor items, `W.Theme` | Quartermaster, WealthPlanner |
| `Window.lua` | `ns.NewWindow(def)`: the suite's sidebar window (tabs, plugin tabs, saved position, header and sidebar buttons, version); `W.SubTabs` (a page's sub-tab row), `W.Section` (heading + rule), `W.MakeWindow` (a title-bar window) | BattleRecap, GroupHistory, MrMiyagi, Quartermaster, SimplePanel, SmartPlates, TapeMeasure, Wally, WealthPlanner |
| `Chart.lua` | `ns.Chart`: line/bar charts with thresholds, legends, hover readout; `ns.Chart:Configure(opts)` sets each addon's look (SimplePanel exposes it as `SimplePanel.Chart`) | SimplePanel, WealthPlanner |
| `Bar.lua` | `ns.NewProgressBar(parent, w, h, opts)`: a track + fill with value, colour, text, labels, title and marker | BattleRecap, SimplePanel, ZeppelinSigns |
| `Items.lua` | `ns.Items`: item info, bags (`GetSlotInfo`, `IterateBags`, `BagList`, `IsSlotBound`), `ItemCount`, `ItemCooldown`, `RequestItem` (asks once), item class constants, `ITEMS.HEARTHSTONE` | Bandolier, MrMiyagi, Quartermaster, SimplePanel, Spyglass, TapeMeasure, Wally, Waypoint, WealthPlanner |
| `Tooltip.lua` | `ns.Tooltip`: one hidden-tooltip scanner (C_TooltipInfo first) with line colours, `IsRed` (r>0.9, g<0.25, b<0.25), `Unusable`, `UseText`, `Soulbound`, `RepairCost`; `HookItem`/`HookUnit` tooltip hooks | Bandolier, GroupHistory, MrMiyagi, Quartermaster, SimplePanel, SmartPlates, Spyglass, TapeMeasure, Wally |
| `Units.lua` | `ns.Units`: names and identity (on WoW Forever realmless "Given Family" keys, compared compactly), `CharKey`, `ServerKey`, `MigrateKeys`, `MigrateNames`, class colours, `GroupUnits`, the client flags (constants: `IS_FOREVER` true) | BattleRecap, GroupHistory, MrMiyagi, Quartermaster, SimplePanel, SmartPlates, Spyglass, TapeMeasure, Wally, Waypoint, WealthPlanner |
| `Format.lua` | `ns.Format`: money (game/icons/letters, presets), `Clock`, `Duration`, `Ago`, `When`, `Pct`, `Short`, `Thousands` | BattleRecap, GroupHistory, Quartermaster, SimplePanel, SmartPlates, Spyglass, Wally, Waypoint, WealthPlanner, ZeppelinSigns |
| `WorldMap.lua` | `ns.WorldMap`: positions (`Player`, `World`, `To`, `Project`, `OnCanvas`, `ZoneName`, distance and ETA), world-map pin/line layers (`NewLayer`), minimap pin views (`MinimapView`) | Convergence, FieldGuide, RoadLog, SimplePanel, SpyglassPluginQuests, Waypoint, WealthPlanner, ZeppelinSigns |
| `GroupComm.lua` | `ns.NewGroupComm(prefix, opts)`: addon messages to the group: paced outbox, chunking and reassembly (wire-compatible), channel choice with a raids option | GroupHistory, Spyglass, Waypoint |
| `Player.lua` | `ns.Player`: professions and skills (one profession table), `HasEnchanting`, fishing spells, talent tabs and points, `ActiveSpec` (StatLedger when loaded) | Bandolier, MrMiyagi, SimplePanel, Spyglass, SpyglassPluginQuests, StatLedger, Wally, WealthPlanner |
| `Questie.lua` | `ns.QuestieKit`: cached Questie modules, tracker focus read/write, completed quests, quest queries | FieldGuide, SpyglassPluginQuests, WallyHUD, Waypoint |
| `Secrets.lua` | `ns.Secrets`: secret-safe reads (`Readable`, `Num`, `Str`, `Call`, `Short`, `SpellName`) | BattleRecap, GroupHistory, MrMiyagi |
| `DeathRecap.lua` | `ns.DeathRecap`: `C_DeathRecap` as hits, and your own recap after you die | BattleRecap, GroupHistory, MrMiyagi |
| `DamageMeter.lua` | `ns.DamageMeter`: `C_DamageMeter` sessions, sources and spell rows | BattleRecap, GroupHistory, MrMiyagi |
| `MinimapButton.lua` | `ns.NewMinimapButton(def)`: the draggable minimap button; with SimplePanel loaded it goes in its launcher drawer (`SimplePanel.RegisterLauncher`) | BattleRecap, FieldGuide, GroupHistory, MrMiyagi, Quartermaster, RoadLog, SmartPlates, Spyglass, TapeMeasure, Wally, Waypoint, WealthPlanner |
| `AuctionPrice.lua` | `ns.AuctionPrice`: Auctionator's price and age, and Wealth Planner's 30-day normal (`WealthPlannerAPI`) to guard buys and sells | Quartermaster, Wally, WealthPlanner |
| `GearEngine.lua` | `ns.GearEngine`: is this item an upgrade (slots, stats, StatLedger scoring, the verdict) | Spyglass, TapeMeasure, Wally |
| `Consumables.lua` | `ns.CONSUMABLES`, `ns.BestConsumable`: potions, healthstones, bandages, elixirs | Bandolier, MrMiyagi |
| `Instances.lua` | `ns.Instances`: every classic dungeon and raid (and Forever's own dungeons) with area, instance and uiMap IDs, recommended levels, final bosses, wings and entrances; lookups `Get`, `ByArea`, `ByInstanceID`, `ByMap`, `ByName`, `Find`, `Current`, `IsFinalBoss`; generated by `tools/shared/build_instances.py` | FieldGuide, GroupHistory, Spyglass |
| `Recipes.lua` | `ns.RecipeData`: every recipe, generated by `tools/shared/build_recipes.py` | Spyglass, WealthPlanner |

Generated shared data is built by scripts in `tools/shared/`, like any addon's in `tools/<Addon>/`.
