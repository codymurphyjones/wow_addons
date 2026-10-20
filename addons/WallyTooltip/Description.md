# WallyTooltip

**Tooltips that place themselves: each one goes where you can read it and where it blocks nothing vital, judged from what's on your screen and what you're doing right now.**

The game puts most tooltips in one fixed corner (the one you set in Edit Mode), whatever is there. WallyTooltip looks at the screen every time a tooltip opens and picks a better spot, and it glides there instead of jumping.

---

## How it decides

Each time a tooltip opens, WallyTooltip tries spots **beside your cursor** (or beside the button the tooltip belongs to), spots **along the screen's edges**, and **where the tooltip already is**. It scores each one on:

- **What it would cover.**
  - *Vital, never covered if it can be helped:* the thing under your cursor, the button or window the tooltip is about, your unit frames, target and party frames, action bars, cast bars and raid frames.
  - *Important:* the minimap, quest trackers, buffs, open windows, SimplePanel's bar, the Waypoint arrow, and the middle of the screen where your character stands.
  - *Minor:* chat, the micro menu and bags, and the nameplates over people and creatures.
- **How far it is from what it's about.** Close is better, so your eyes don't have to travel. A very tall tooltip cares less, because beside the cursor it would cover a lot.
- **Where your cursor is heading.** If you're sweeping the mouse across the screen, the tooltip stays out of its path.
- **The fight.** In combat, and while you're moving, the middle of the screen counts much more, and the tooltip moves further out of the way.
- **Steadiness.** A tooltip that's showing only moves for a clearly better spot, so it doesn't hop around.
- **The screen's edges.** A spot that only fits by being squashed against an edge counts as a worse spot.

The spot covering the least wins. If **every** spot would cover something vital, the tooltip goes to the spot you set in **Edit Mode**, just as without the addon. If you've told the game to show tooltips **at your cursor**, WallyTooltip leaves that alone.

## Smooth moves

A tooltip that's showing **glides** to its new spot in about a fifth of a second: when its lines come in and it grows, when your cursor moves onto it, or when you point at something else while it's still fading. A brand-new tooltip simply appears where it goes.

## Settings

**Options > AddOns > WallyTooltip** (or `/wtip options`):
- **Smart placement:** on or off.
- **Glide to a new spot:** on or off (off: it jumps).
- **Keep the fight clear:** in combat and while moving, keep the middle of the screen clearer.
- **Say where each tooltip goes:** a line in chat per tooltip, for when a spot looks wrong.

## Commands

| Command | What it does |
|---|---|
| `/wtip on \| off` | Smart placement on or off |
| `/wtip options` | The settings |
| `/wtip status` | What it has done since you logged in: tooltips seen, placed, sent to Edit Mode's spot, errors |
| `/wtip debug` | Says in chat where each tooltip went and what it touched |
