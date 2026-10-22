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
