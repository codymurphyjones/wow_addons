# WallyTooltip

Smart placement for tooltips that use the game's default spot (`GameTooltip_SetDefaultAnchor`, from `Blizzard_SharedXML/SharedTooltipTemplates.lua`; world tooltips reach it through `GameTooltipDataMixin:SetWorldCursor`): units and objects in the world, and anything else that asks for the default anchor. Tooltips that their own code places (an item next to its bag slot, a button's tooltip anchored to the button) are left where they are.

## Files

| File | What it does |
|---|---|
| `Core.lua` | Settings (`WallyTooltipDB`: enabled, glide, combatAware, debug) and `/wtip` (on, off, options, status, debug) |
| `Screen.lua` | What's on screen, as rectangles in UIParent's units with a weight: VITAL (8: unit frames, action bars, cast bars, raid frames, the 60x60 around the cursor, the tooltip's owner frame), IMPORTANT (3: minimap, trackers, buffs, SimplePanel's bar, the Waypoint arrow, Field Guide, any open window on the main strata that takes the mouse), MINOR (1: chat, micro menu, bags, each nameplate up to 40), and a narrow column in the middle of the screen where the character stands (1.5; 4 in combat, 2.5 while moving). Frames are looked up by name; only shown ones count; forbidden frames are never touched; a frame big in both directions is a container and is skipped. |
| `Place.lua` | Tries where it is now (when showing), 4 spots beside the cursor (34 from it) and 10 along the edges (corners, sides and their thirds). Cost of a spot: the sum over things on screen of (share of the tooltip over it x its weight); + FAR x distance from what it's about (the owner frame's centre, else the cursor) / screen diagonal, FAR halved in combat and halved again for a tooltip over 12% of the screen; + HEADING x how far it's in the cursor's path when the cursor moves faster than 300/s; + CLAMPED when the spot had to be pushed onto the screen; - STAY for where it is now. The cheapest wins; if even that has more than 20% of the tooltip over something VITAL, the tooltip keeps the point the game gave it (Edit Mode's). Placing runs right after `GameTooltip_SetDefaultAnchor` (when the anchor type is ANCHOR_NONE, so a cursor-anchored setting is kept), again on OnSizeChanged/OnShow, and when the cursor moves onto it. Sizes the game keeps secret (world tooltips can) fall back to the last size it could read. A showing tooltip glides to its new spot (GLIDE); one that opens within AGAIN seconds of the last one going glides on from there. `/wtip status` counts hooks, placements, Edit Mode fallbacks, secret sizes and errors. |
| `Settings.lua` | Options > AddOns > WallyTooltip |

## Build

`tools/WallyTooltip/make_icon.py` draws `Media/Icon.tga`. It needs Pillow, so run it with `python tools/WallyTooltip/make_icon.py` (not `-I`).

## Tuning

The weights are at the top of `Screen.lua` (and `CENTRE`, `CENTRE_COMBAT`, `CENTRE_MOVING`); the distances and thresholds (`MARGIN`, `NEAR`, `FAR`, `STAY`, `HEADING`, `MOVING_FAST`, `CLAMPED`, `BIG`, `VITAL_SHARE`, `GLIDE`, `AGAIN`) at the top of `Place.lua`. `/wtip debug` says which spot won and what it touched.
