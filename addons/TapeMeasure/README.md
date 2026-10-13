# Tape Measure

<img src="Media/Logo.png" alt="Tape Measure logo" width="128">

Shows whether a piece of gear is an upgrade, and why, using your stat priority from
**StatLedger**. It replaces GearBot: turn GearBot off when you turn Tape Measure on, or both will
add lines to your tooltips.

Requires the StatLedger addon (`## Dependencies: StatLedger`).

## The tooltip

```
Tape Measure                                    Fire Mage
Upgrade  +18.4%                          41.2 to 48.8
vs [Apprentice Robe]  (Chest)
  +12 Fire Spell Power  #2                       +7.3
  +1% Spell Critical Strike  #3                 +10.4
  -4 Intellect  #4                               -2.5
Not valued by Fire Mage: +10 Strength
Better mostly for its Spell Critical Strike and Fire Spell Power, despite less Intellect.
```

- **Verdict**: Upgrade, Downgrade, Sidegrade (a change smaller than your sidegrade band), or an
  empty slot. The numbers on the right are your score now and with this item.
- **vs**: the item(s) it was compared with. Rings and trinkets compare with the weaker one you
  wear, a two-hander with your main hand plus off hand. A one-hander compares with either hand
  if you can dual wield, but never with a shield.
- **Stat lines**: each stat that moves the score, with its rank in your StatLedger list and
  how much it changes the score. Hold **Shift** to see all of them.
- **Not valued**: stats that change but aren't on your list. They count for nothing.
- Warnings appear for items you can't use, items above your level, unique items you already
  wear, and Use / Equip / Chance on hit effects (these aren't scored).

## How the score works

`score = sum over the item's stats of  amount x budget per point x StatLedger weight`

- **StatLedger weight**: your rank 1 stat is 1.0, falling evenly to 0.1 at the last rank.
  Stats you haven't ranked are 0. Change the order in `/statledger`, and Tape Measure updates
  straight away. Tape Measure has no weights of its own.
- **Budget per point**: puts stats on the same scale, since one percent of crit is worth far
  more than one Strength. It's the same for everyone and only converts units:

| Stat | Budget |
|---|---|
| Strength, Agility, Stamina, Intellect, Spirit | 1 |
| Attack Power / Ranged Attack Power | 0.5 / 0.4 |
| Spell Power / school Spell Power / Healing | 0.86 / 0.7 / 0.45 |
| Mana Regeneration (mp5) | 2.5 |
| Defense / Block Value / Armor | 1.2 / 0.15 / 0.04 |
| Weapon DPS | 3 |
| Crit, Spell Crit, Hit (per %) | 14 |
| Haste / Dodge / Parry / Block (per %) | 10 / 12 / 20 / 5 |

Values above 5 for the percent stats are read as ratings and count 1 each.

Upgrade % = (new score - current score) / current score x 100. This is a weighted stat score,
not a DPS or healing simulation.

"Equip:" lines that the game's item-stat API leaves out are read from the item tooltip:
school spell damage, spell crit and hit, healing, mp5, attack power, defense, dodge, parry, block.
These patterns only match the English client.

## Window

`/tape` opens it. The layout matches Wally's.

- **Upgrades**: upgrades in your bags, empty slots first, then the biggest gains.
- **Equipped**: every slot with its score. The shortest bars are your weakest slots.
- **Stat Priority**: your StatLedger list with each stat's weight and score per point.
- **Help**, and **Settings** (Options > AddOns > Tape Measure).

Bag slots holding an upgrade get a pulsing green border and a +% badge (Blizzard bags).

## Commands

| Command | |
|---|---|
| `/tape` | Open Tape Measure |
| `/tape upgrades` | Upgrades in your bags |
| `/tape prio` | Edit your stat priority (opens StatLedger) |
| `/tape config` | Settings |
| `/tape on` / `/tape off` | Turn tooltips and bag highlights on or off |
| `/tape minimap` | Show or hide the minimap button |
| `/tape pulse` | Preview the bag highlight for 6 seconds |

## Icon

`Media/Icon.tga` (128x128, used in game) and `Media/Logo.png` (512x512, for listings) are drawn
by `Media/make_icon.py`. To change them, edit the script and run
`python Media/make_icon.py Media` (needs Pillow).
