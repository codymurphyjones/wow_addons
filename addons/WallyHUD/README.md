# WallyHUD

One look for the whole suite. WallyHUD is the design system our addons share and the part of the HUD that belongs to all of them.

It loads last: its TOC lists every addon of ours as an optional dependency. It repaints them to the shared look before any of their windows are built. Without WallyHUD each addon keeps its own colours.

## The look (Tokens.lua)

- **Surfaces** are see-through over the game: base (HUD panels), raised (windows, popovers), sunken (wells, edit boxes).
- **Borders** are 1px white hairlines at 8%, never coloured at rest. They go to 16% on hover or focus.
- **Text** has one ramp in four steps: primary, secondary, tertiary and inverse.
- **One accent:** teal `#40C4CD`, for selection, focus and active states only.
- **State colours** mean something: success (green), warning (amber) and danger (red). Gold is for loot and money only.
- **Type:** one family, Roboto Condensed (shipped in `Media`, SIL Open Font License, whose figures line up), in four weights: Regular, Medium (text, the default), SemiBold (titles) and Bold (emphasis). It's set as label 11px (capitals), body 12px, numbers 13px and titles 13px, all with a soft 1px shadow.

## How our addons use it

| Addon | What changes |
|---|---|
| Wally, Quartermaster, WealthPlanner, Fireside, MrMiyagi, TapeMeasure, SmartPlates, BattleRecap | Their colours live in one `Palette.lua` each, listed first in their TOC. WallyHUD repaints it in place: hairline borders, the shared surfaces and buttons, the one accent (BattleRecap's coral included). BattleRecap's window titles use primary text. |
| SimplePanel (status rail) | Its "Wally" scheme follows WallyHUD: the shared palette, state colours and font. No dividers. Values are only coloured when they're a problem: fps under 30, latency over 300 ms, durability at 50% or less, bags nearly full. |
| SaddleBags (tabs) | Underline tabs: capitals, the active one in primary text over a 2px accent line, no fills or borders. The panel, when it shows, is a hairline surface. |
| Waypoint (arrow) | A see-through hairline panel instead of the gold border. The arrow and title keep the target's colour (yours, a guide's, a dungeon's), because that one means something. The "Fly to" button follows the palette. |
| FieldGuide | Hairline panels and primary-text titles. Green (guide) and purple (dungeon) stay only on the progress bar. |

## The HUD

- **Minimap buttons** (Minimap.lua): no gold rings and no round backing. Icons are monochrome in secondary text colour and turn full colour under the mouse. This covers our buttons and every LibDBIcon button, without changing their files.
- **The minimap** (in SimplePanel's minimap plugin, when that's on): the map itself is square and fills its frame. Addon buttons sit in a row under it instead of on its edge. Under the map: the server and local time.
- **Issue Reporter** (Reporter.lua): Blizzard's PTR/beta Issue Reporter stays out of the play field. You can bring it up with:
  - Ctrl+Shift+/ (Key Bindings > AddOns > WallyHUD);
  - `/whud report`;
  - the **Report** button on the error notice. That notice shows in the bottom right only when an addon error actually happens, at most once a minute, and fades after 10 seconds. Errors still go wherever they went before.
- **Flag carriers** (RightColumn.lua): the battleground flag carrier frames sit in the column the game stacks down the right of the screen (`RightManagedFrameContainer`), which Edit Mode can't move. `/whud flags` shows a box over that column to drag; `/whud flags` again locks it (remembered), `/whud flags reset` puts it back. The column moves as one: the flag carriers are protected buttons the game won't let addons move in a fight, so the column is moved out of combat and keeps its place through fights. If the game lays it out again in a fight, it goes back where you put it when the fight ends.
- **Density** (Density.lua):

| | Status rail | Minimap buttons |
|---|---|---|
| Minimal | clock and performance | hidden |
| Standard (default) | everything you've set up except memory | shown |
| Expanded | everything | shown |

## Vitals (Vitals.lua)

Your health and your resource, drawn into the screen itself instead of a unit frame. By default WallyHUD shows the orb (below) and the line is off: turn **The line** on in the settings and the orb becomes a resource tracker.

- **The tideline:** one faint line across the whole screen. Its **height** is your health. At full health it sits at the top edge, out of the way; as you're hurt it sinks down the screen, through the world you're looking at.
- **The light:** your mana (rage, energy) lights the tideline from the left, ending in a small star. Your whole state is one point on the screen: up and right is well, sinking down and left is trouble.
- **The film:** the space above the line (what you've lost) takes a faint cold film, capped so the world stays clear.
- **The rim:** the screen's edges redden from your first point of damage on an exponential curve: barely there for a long while (2% at 75% health, 11% at 50%), climbing faster the lower you go, full at about 12%. Below your usual low (learned) they pulse like a heartbeat.
- **Rhythm:** after a spell costs mana, a sweep round the star counts down the five-second rule. Energy and mana ticks ripple off the star. Combo points ride beside it.
- **Readouts:** bring the mouse near the line and the numbers surface along it. No clicks, and the line never takes the mouse. Below 15% health the health readout shows by itself. The health readout sits at the right end of the line by default (Settings: Health numbers, left, center or right).
- **Nothing stays:** at full health with your resource at rest, out of combat, it all fades away. Any change brings it back.
- **It learns:** it remembers how low your health usually goes in a fight and only starts the edges' pulse below that. If you keep reaching for the numbers in fights, it starts showing them in fights on its own (and says so once). `/whud vitals` shows what it has learned; `/whud vitals forget` resets it.
- **Your unit frame** is one choice: **the orb** (the default) or Blizzard's player frame. It switches straight away either way (after the fight, if you're in one).
- **The orb** (Orb.lua): a Diablo-inspired glass orb in place of the player frame, where your portrait was: glowing liquid in a bronze-and-iron bezel with a crest, split by an iron bar with a gem. Health fills the top half (emerald), your resource the bottom half (in its colour), each with a bright surface line and a slow swirl in the liquid. Right-click opens your unit menu, left-click targets you, the mouse over it shows your tooltip with the numbers, shift-drag moves it (`/whud orb reset` puts it back). It keeps the same size in and out of combat, so your menu is always a right-click away. The art is drawn by `tools/WallyHUD/make_orb.py` into `Media/Orb`. Its diameter is in the settings (**Orb size**, 100 px). With **the line** on, the line shows your health, so the orb becomes a smaller **resource tracker** (80% of that size): one sphere of your resource, with the exact amount in the middle ("100", not "100 / 1000").

On WoW Forever health and power can be hidden from addons in combat ("secret" values). Vitals never does arithmetic or comparisons on them: they go straight into the engine's own channels (status bar values, curve-mapped alpha, anchors to a bar's fill edge, formatted text). Learning only uses values the game lets it read.

## Objectives (Questie's tracker)

Questie.lua restyles Questie's quest tracker from here, after every redraw, without changing Questie's files or settings:
- **Header:** OBJECTIVES with the count in tertiary text, and the logo dimmed.
- **Zones:** capitals, in tertiary text.
- **Quests:** titles in primary text, with the level after the title (in its difficulty colour) instead of a "[28]" prefix. The focused quest gets a 2px accent bar.
- **Goals:** secondary text, success colour once done, and a hairline progress bar under goals with a count.
- **Finished quests:** "Ready to turn in" with a check, in the success colour. "Failed" is in danger red.
- **Tracker frame:** a hairline panel.

Turn it off under **Objectives in the suite's look** in the settings, then `/reload`.

## Settings

Options > AddOns > WallyHUD, or `/whud`:
- density;
- the shared look;
- quiet minimap buttons;
- keeping the Issue Reporter out of the way;
- the error notice.

`/whud minimal | standard | expanded` switches density.

## For our addons

- **Palette:** put the colours in a table and add it to `WallyHUD_Palettes` (see any `Palette.lua`). The keys are bg, border, button, hover, row, panel, field, accent and muted, each `{ r, g, b }`. WallyHUD changes them in place.
- **Helpers:** `WallyHUD.Tokens`, `WallyHUD.Panel(frame, "base" | "raised" | "sunken")`, `WallyHUD.UnderlineTab(tab, label)` and `WallyHUD.SetTab(tab, active)`, `WallyHUD.GhostIcon(button, icon)`, `WallyHUD.Hex(color)` and `WallyHUD.RGBA(color)`.
- **Our addons' fonts:** each addon's `Fonts.lua` (first in its TOC) makes its own copies of the game fonts it draws with (`<Addon>GameFontNormal` and so on) and lists them in `WallyHUD_Fonts`. When WallyHUD loads it sets those copies in Roboto Condensed, keeping their size, outline and colour: the gold "Normal" and the large fonts in SemiBold, the rest in Medium. The game's own windows keep their fonts. Text set by file (nameplates, bag badges, signs) uses `WallyHUD.SuiteFace(weight)`, which is nil when the shared look is off.
- **Fonts:** `WallyHUDFontLabel`, `WallyHUDFontBody`, `WallyHUDFontNumber` and `WallyHUDFontTitle`. For a face at a weight, use `WallyHUD.Face("regular" | "medium" | "semibold" | "bold")` (or `WallyHUD.Tokens.weights`), never another font.

## Not covered yet

- Spyglass, Modified, ZeppelinSigns, StatLedger and SpyglassPluginQuests use Blizzard's own frame templates and aren't restyled.
- Chat message colours (`|cff55d6be` and others) are unchanged.
