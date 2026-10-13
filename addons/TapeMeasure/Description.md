# Tape Measure

**Hover any piece of gear to see if it's an upgrade, and why.**

Most gear scorers give you a number and a green arrow. Tape Measure also tells you which item it compared against, which stats you gain and lose, how highly your spec ranks each one, and which stats don't count for you at all. It uses your stat order from **StatLedger**, so it agrees with your other addons about which stats matter.

---

## Features

### A tooltip that explains itself
Every piece of gear you can equip gets a Tape Measure section in its tooltip:

```
Tape Measure                                Fire Mage
Upgrade  +18.4%                          41.2 to 48.8
vs [Apprentice Robe]  (Chest)
  +1% Spell Critical Strike  #3                 +10.4
  +12 Fire Spell Power  #2                       +7.3
  -4 Intellect  #4                               -2.5
  1 more - hold Shift
Not valued by Fire Mage: +10 Strength
Better mostly for its Spell Critical Strike and Fire Spell Power, despite less Intellect.
```

- **The verdict:** **Upgrade** (green), **Downgrade** (red), or **Sidegrade** (yellow) for a change too small to matter. An item for a slot you have empty says so, in blue. The right side shows your score now and with the item.
- **What it was compared with:** the item(s) it would replace, and the slot.
- **Every stat that changes:** how much you gain or lose, its rank in your priority (**#2**), and how much it moves your score. Gains are green, losses red, biggest first.
- **Hold Shift** to see every stat line. By default the tooltip shows the top 4.
- **Not valued:** stats that change but aren't on your priority list. A big Strength number on a caster's sword won't fool you.
- **A one-line summary** of where the gain or loss comes from.

### Fair comparisons
- **Rings and trinkets** are compared with the *weaker* of the two you wear, so a real upgrade for either slot is always caught.
- **Two-handers** are compared with your main hand *plus* off hand together.
- **One-handers** can go in either hand if you can dual wield, but they're never compared with a shield or an off-hand item.
- **Off-hand items** while you hold a two-hander are flagged as not comparable, rather than given a misleading number.
- **Hovering what you already wear** shows its score and which stats it gets that score from.

### Warnings
- **You can't use this item:** your class, armor type or weapon skill doesn't allow it.
- **Requires level X:** fine to keep, but not an upgrade yet.
- **Unique: you already wear one.**
- **Effects not counted:** the item has a Use, Equip or Chance on hit effect that Tape Measure can't score, so read the item before you decide.

### Upgrades in your bags
- Bag slots holding an upgrade get a **pulsing green border** and a **+12.4% badge** (or **NEW** for an empty slot) in the Blizzard bags.
- The **Upgrades** page lists every upgrade you're carrying. Items for empty slots come first, then the biggest gains, each with what it replaces and why it's better.
- Items you can't use, can't use yet, or already wear as unique are left out.

### Your weakest slots at a glance
The **Equipped** page lists every slot with its score bar and its best stats. The shortest bars show where an upgrade would help most.

### One stat priority, shared
Tape Measure has no weights of its own to set up. It reads your list from StatLedger: rank 1 counts fully, falling evenly to a tenth at your last rank, and stats you haven't ranked count for nothing. Change your list in StatLedger, or respec, and every tooltip, badge and list updates straight away.

---

## How to use

1. Install **StatLedger** (required) and **Tape Measure**. If you use **GearBot**, turn it off. Tape Measure replaces it, and both would add lines to your tooltips.
2. Log in. Your class and spec are detected automatically, and StatLedger's default list for your spec is used.
3. **Hover gear.** Bags, character sheet, loot windows, vendors, chat links: any gear tooltip gets the Tape Measure section.
4. Want different stats to matter? Type **/statledger** (or **/tape prio**) and drag your stats into order. Tape Measure follows right away.
5. Open **/tape** to see every upgrade in your bags, your equipped slots, and your priority with each stat's weight.

### The window
Open it with **/tape**, the minimap button, or the AddOn compartment. It has the same dark dashboard look as Wally.

| Page | What it shows |
|---|---|
| **Upgrades** | Every upgrade in your bags: icon, what it replaces, the top reasons and a gain bar. **Rescan** re-reads every item, including any that hadn't loaded yet. Shift-click an item to link it. |
| **Equipped** | Each slot with its item, score bar and top stats, plus your total score. |
| **Stat Priority** | Your ranked list with each stat's weight and its score per point. Stats you've removed are shown greyed out, at zero. **Edit in StatLedger** opens the editor. |
| **Help** | How the score works and what isn't counted. |
| **Settings** | Opens Options > AddOns > Tape Measure. |

### Minimap button
- **Left-click:** open Tape Measure.
- **Right-click:** open the Upgrades page.
- **Shift-right-click:** edit your stat priority.
- **Drag:** move it around the minimap. Until you drag it yourself, it moves out of the way of other addons' minimap buttons.
- Hovering it shows your spec and how many upgrades you're carrying.

### Settings (Options > AddOns > Tape Measure)

| Setting | Default | What it does |
|---|---|---|
| Enable Tape Measure | On | Master switch for tooltips, bag highlights and the Upgrades list |
| Item tooltips | On | Add the Tape Measure section to gear tooltips |
| Compact tooltips | Off | Show only the verdict and what it was compared with |
| Highlight upgrades in bags | On | Green border on bag slots holding an upgrade |
| Pulse the border | On | Turn off for a steady border |
| Percent badges | On | The +% or NEW badge on the bag slot |
| Minimap button | On | Show or hide the minimap button |
| Stat lines in tooltips | 4 | Stat lines shown before "hold Shift" |
| Sidegrade band (%) | 1 | A change smaller than this is called a sidegrade |
| Minimum upgrade (%) | 0 | Smaller upgrades aren't highlighted or listed |

The settings page also has **Test bag pulse**, which marks every bag item TEST and flashes it for six seconds so you can preview the highlight, and **Edit stat priority**.

### Commands

| Command | What it does |
|---|---|
| `/tape` | Open or close Tape Measure (also `/tapemeasure`) |
| `/tape upgrades` | Open the Upgrades page |
| `/tape prio` | Edit your stat priority in StatLedger |
| `/tape config` | Open Options > AddOns > Tape Measure |
| `/tape on` / `/tape off` | Turn tooltips and bag highlights on or off |
| `/tape minimap` | Show or hide the minimap button |
| `/tape pulse` | Preview the bag highlight for six seconds |
| `/tape help` | List the commands in chat |

---

## How the score works

```
item score = sum over its stats of  amount x budget per point x StatLedger weight
upgrade %  = (score with the item - score now) / score now x 100
```

**StatLedger weight:** your rank 1 stat is 1.0, falling evenly to 0.1 at your last rank. Stats you haven't ranked are 0.

**Budget per point** puts different stats on one scale. One percent of crit is worth far more than one point of Strength, so without it crit, hit and weapon DPS would barely count. The table is the same for everyone and only converts units. Which stats matter to you comes from your StatLedger list alone.

| Stat | Budget per point |
|---|---|
| Strength, Agility, Stamina, Intellect, Spirit | 1 |
| Attack Power / Ranged Attack Power | 0.5 / 0.4 |
| Spell Power / Fire, Frost, Shadow, Arcane, Nature Spell Power / Healing | 0.86 / 0.7 / 0.45 |
| Mana Regeneration (mp5) | 2.5 |
| Defense / Block Value / Armor | 1.2 / 0.15 / 0.04 |
| Weapon DPS | 3 |
| Critical Strike, Spell Critical Strike, Hit (per 1%) | 14 |
| Haste / Dodge / Parry / Block Chance (per 1%) | 10 / 12 / 20 / 5 |

Percent stats with a value above 5 are read as ratings and count 1 per point.

Melee crit and spell crit are separate stats, as in StatLedger. "Equip:" bonuses that the game's item-stat data leaves out are read from the item's tooltip, so these count too:
- school spell damage ("Increases damage done by Fire spells...")
- spell crit and spell hit
- healing
- mana per 5
- attack power
- defense, dodge, parry and block

### Not counted
- Use, Equip and Chance on hit *effects* (the tooltip tells you when an item has one)
- set bonuses
- resistances
- enchants' special effects

The score measures weighted stats. It isn't a DPS, healing or survival simulation.

---

## Notes

- Built for **World of Warcraft: Forever** (Interface 16001).
- **Requires StatLedger.**
- Saved variables: `TapeMeasureDB` (settings, account-wide) and `TapeMeasureCharDB` (window position and minimap button, per character).
- Bag highlights support the default Blizzard bags (combined and separate). With a replacement bag addon, tooltips and the Upgrades page still work.
- Tape Measure never equips, moves or sells anything. Highlights are visual only.
- "Equip:" lines are read in English. On other client languages, bonuses missing from the game's item-stat data may not be counted.

Bug reports and suggestions are welcome in the comments or on the issue tracker.
