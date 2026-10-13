# Bandolier

**Puts all your consumables on one smart key that picks the right heal, mana restore or buff for the moment, with a Ctrl pop-out bar for everything else.**

Bandolier reads your bags, ranks every consumable you can use, and keeps a single macro pointed at the best one. Press it when you're low and it uses your best heal. In a boss fight it keeps your flask and elixirs up first. Hold Ctrl and a bar of everything else pops up under your mouse.

---

## Features

- **One key for everything.** One macro covers healthstones, potions, bandages, food, drink, flasks, elixirs, scrolls and more.
- **Smart priority.** Bandolier always picks the best item you have and can use right now, and falls back to weaker ones as you run out, down to that last apple.
- **Knows the situation.** It uses different choices in combat, out of combat and in boss fights.
- **Cooldown and buff aware.** It skips items that are on cooldown or whose buff you already have.
- **Pop-out bar.** Ctrl+press shows every consumable at your cursor, sorted into rows.
- **Knows your class.** Buffs and buff food are ranked by a stat priority for every class and talent spec, and you can customise it.
- **Learns as you play.** It remembers real cooldown and buff lengths, which buff each item gives, and which items can't be used in combat. This is shared by all your characters.
- **Works in combat.** Everything runs inside WoW's secure system, with no Lua errors or "addon blocked" messages.
- **Settings in the game's own options.** Find it under *Options › AddOns › Bandolier*.

---

## Getting started

1. **Install** Bandolier and launch the game. A new addon folder is only picked up on a full launch, not on `/reload`.
2. **Find the macro.** On first login Bandolier creates a character macro called **Bandolier** and tells you in chat. Open `/macro` and switch to the *character* tab to see it.
3. **Drag it onto an action bar** and give it a key you can reach in a fight.
4. **That's it.** Bandolier keeps the macro up to date whenever your bags, cooldowns, buffs or level change. You never need to edit it.

> **Note:** If all your character macro slots are full, Bandolier will ask you to free one up.

---

## The four presses

Everything goes through the one Bandolier key. Modifiers change what it does:

| Press | What it does |
|---|---|
| **Plain press** | Uses your **primary resource**: health or mana, depending on the *Prioritize Mana* setting. In a boss fight it keeps your **buffs** up first. |
| **Shift + press** | Uses your **other resource**: mana if your primary is health, health if your primary is mana. |
| **Alt + press** | Uses the **next buff you don't have yet**, best match for your stat priority first. Does nothing once every buff is up. |
| **Fishing pole equipped** | A plain press **casts Fishing** (out of combat, with Fishing learned). **Shift + press** puts back the weapons the pole replaced, in combat too. Alt still uses buffs. |
| **Ctrl + press** | Opens the **pop-out bar** with everything else. |

The macro's icon and tooltip always show what a plain press will use. Hold Shift or Alt and they switch to show what *that* press would use.

---

## Walkthrough: what gets picked, and when

### Health

**In combat**, strongest first, because you're in trouble:
1. Healthstone
2. Healing and rejuvenation potions, strongest first
3. Other instant heals: Whipper Root Tuber, Night Dragon's Breath, and any reusable item that "restores health"
4. Bandages

**Out of combat**, cheapest first, saving potions and healthstones for fights:
1. Bandages
2. Food that restores both health and mana ("Refreshment")
3. Food: buff food first unless you're already Well Fed, then by how much it heals
4. Other instant heals, then potions, then the healthstone last

### Mana

**In combat:** mana potions, Demonic/Dark Runes and mage mana gems, strongest first. After those, any item that restores mana as well as health.

**Out of combat:** refreshment, then drink, then the items above. Potions come last, so they're saved for fights.

### Boss fights

When a boss is on the field (the game shows boss frames), a **plain press keeps your buffs up first**. That covers flasks, elixirs, juju, scrolls, enhancement potions and any other item that gives stats for a while. They're used in order of how well they match your [stat priority](#stat-priority): for a Fury Warrior, Mighty Rage Potion and Juju Power come before Elixir of the Mongoose, and Flask of the Titans comes last.

Once they're all up or on cooldown, the plain press goes back to your primary resource. Shift still gives you the other resource.

Some bosses don't show boss frames. For those, type `/bandolier boss` before the pull to treat every fight as a boss fight. Type it again to turn it off.

### Example

> You're a warrior with 1 Healthstone, 3 Major Healing Potions, 5 Heavy Runecloth Bandages and 10 apples.
>
> - **Mid-fight, low health, plain press:** Healthstone. Press again: it's on cooldown, so a Major Healing Potion. Press again: potions are on cooldown, so a bandage.
> - **After the fight, plain press:** a bandage first, since it's free. When you're Recently Bandaged, the apples.
> - **Run out of everything except apples:** the plain press still eats an apple out of combat.

---

## The pop-out bar (Ctrl + press)

Ctrl+press opens a bar centred on your mouse. Click an item to use it, and the bar closes. Ctrl+press again to close it without using anything.

**Out of combat**, the bar is arranged in rows:

| Row | Contents |
|---|---|
| 1 | Combat consumables: potions, healthstones, bandages, buffs and so on |
| 2 | Out-of-combat items: food, drink, weapon enhancements, containers to open |
| 3 | Camp and campfire items, always on the bottom row |

**In combat**, out-of-combat items are hidden and the bar shows:

| Row | Contents |
|---|---|
| 1 | Ready items (buffs first in a boss fight) |
| 2 | Items on cooldown |

Every button shows a count and a cooldown sweep. Mouse over a button for its tooltip.

### Weapon enhancements

Sharpening stones, weightstones, wizard and mana oils, rogue poisons and fishing lures go straight onto your weapon:

- **Left-click:** main hand. Use this for fishing lures too, since the pole is in your main hand.
- **Right-click:** off hand.

### Containers

Lockboxes, clams, bags and crates that can be opened show up on the bar. Click one to open it.

---

## Settings

Open them from *Options › AddOns › Bandolier*, or type `/bandolier options`.

### Prioritize Mana

This one setting decides which resource your plain press restores:

| Prioritize Mana | Plain press | Shift + press |
|---|---|---|
| **Off** | Health | Mana |
| **On** | Mana | Health |

It also decides whether drink or food comes first out of combat. Food that restores both always comes first either way.

It's **on by default for Priests, Paladins, Druids and Shamans**, the classes that heal themselves with mana, and off for everyone else. It's saved per character.

### Stat Priority

Bandolier ranks every buff by **how well its stats suit you**. That covers flasks, elixirs, juju, scrolls, enhancement potions, other stat items (Winterfall Firewater, rums...) and buff food and drink. Buffs are ranked against each other by score, whatever their kind. Food and drink keep their own groups (refreshment, food, drink), with buff versions ranked by score within each.

- **Automatic (default):** your class and the talent tree with the most points decide the priority. All 27 class/spec combinations have a default, and it updates when you respec.
- **Preset:** pick any class/spec preset from the dropdown, for example to buff for a different role.
- **1st to 5th stat:** change any slot to make your own custom priority. Picking a preset again resets it.

**Scoring:** your 1st stat counts most (10), then 6, 4, 2 and 1. A buff that gives several of your stats adds them together, so Elixir of the Mongoose (Agility + Crit) beats Elixir of Giants (Strength) for a Rogue.

**Off-stat buffs:** buffs that give none of your stats are still used, but only after every matching buff is up.

| Spec | Default priority |
|---|---|
| Fury Warrior | Strength > Attack Power > Crit > Agility > Hit |
| Protection Warrior | Stamina > Armor > Strength > Agility > Attack Power |
| Combat Rogue | Agility > Attack Power > Crit > Strength > Hit |
| Frost Mage | Spell Power > Frost Spell Power > Spell Crit > Intellect > Mana Regen |
| Holy Priest | Healing > Intellect > Spirit > Mana Regen > Stamina |

Type `/bandolier stats` to see the priority in use and where it comes from.

---

## How cooldowns and buffs are tracked

WoW deliberately hides cooldowns, the clock, your health and your buffs from addon code that runs during combat. This stops addons from automating fights. Bandolier works within that:

- **Out of combat**, it reads real cooldowns and your real buffs. An item on cooldown, or whose buff you already have, is skipped.
- **In combat**, when Bandolier uses an item it starts a timer for that item's cooldown or buff. When the timer runs out, the item goes back on the list. Items that share a cooldown are tracked together, so one potion marks all potions.
- **If a length isn't known yet**, using the item blocks it for the rest of that fight. When combat ends, Bandolier reads the real length and remembers it.
- **Buff lengths** are also read straight from the item's tooltip ("for 30 min", "for 1 hour").
- **Which buff an item gives** is learned the first time you use it through Bandolier.

The macro icon and the bar's cooldown sweeps update live in combat, because they're only visual.

> **Note:** If everything left is marked as on cooldown, a press still tries the best item, in case the estimate is running long. Alt+press is the exception: it never re-uses a buff you already have.

### What Bandolier remembers

Learned data is saved **account-wide**, so every character benefits from what one has learned. That includes cooldown and buff lengths, which buff each item gives, and items that can't be used in combat. Your *Prioritize Mana* setting is saved per character.

> **Note:** WoW writes saved data to disk when you log out, `/reload` or exit normally. If the game crashes, anything learned in that session is lost.

---

## Slash commands

`/bandolier` or `/bando`:

| Command | What it does |
|---|---|
| `/bandolier` | Lists every consumable Bandolier found, in priority order |
| `/bandolier options` | Opens the settings page |
| `/bandolier stats` | Shows your stat priority (`/bandolier stats reset` returns to your spec default) |
| `/bandolier boss` | Turns boss mode on or off: every fight is treated as a boss fight |
| `/bandolier reset` | Recreates the Bandolier macro (drag it back onto your bar afterwards) |
| `/bandolier debug` | Shows the macro text, the bar state and every priority order with what's left |
| `/bandolier trace` | Prints a line for each plain press, for troubleshooting |
| `/bandolier help` | Lists the commands |

---

## Tips and known limits

- **Shift+1 to Shift+6:** by default WoW uses these to switch action bar pages. If Bandolier sits on keys 1–6, unbind the Shift versions under *Key Bindings* so Shift+press reaches the macro. Shift-clicking the button with the mouse always works.
- **No automatic health-versus-mana choice in combat:** WoW doesn't let addons read your health or mana in combat. That's why health and mana are split across the plain press and Shift instead.
- **English client:** Bandolier reads item tooltips to recognise food, heals and buff lengths, so some detection currently works on English clients only.
- **Items used straight from your bags,** without Bandolier, don't start an in-combat timer. Real cooldowns are picked up again after the fight.
- **Supported action bars:** the default bars, Bartender, Dominos and ElvUI, for keeping the macro icon up to date.

---

## Troubleshooting

- **The macro doesn't do anything:** run `/bandolier debug`. It shows what the macro contains and what Bandolier found in your bags.
- **An item is missing or in the wrong place:** run `/bandolier` to see how each item was classified.
- **Something looks wrong mid-fight:** it corrects itself when combat ends, once Bandolier can read the real state again.

When reporting a bug, please include the output of `/bandolier debug` and any Lua error text. Turn errors on with `/console scriptErrors 1`.
