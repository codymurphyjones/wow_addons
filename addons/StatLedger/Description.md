# StatLedger

**Set your stat priority once, for every class and spec, and every addon that supports it uses the same list.**

Gear scorers, consumable pickers and loot lists all need to know which stats matter to you, and they usually make you set that up again in each addon. StatLedger keeps one list per class and spec, starts you from a sensible default, and lets other addons read it. Change it in one place, and they all follow.

---

## Features

### A default for every class and spec
All 27 class and spec combinations (the nine classes, three talent trees each) come with a ready-made priority of 7 to 10 stats. It's in use straight away, with nothing to set up.

### Customise by dragging
Open the settings page and you see one list of every stat:

- **Drag and drop** any stat to reorder it. A gold line shows where it will land, and it snaps into place when you let go.
- **X** removes a stat. It moves below a red **Removed** divider and stays visible, greyed out and marked "removed", so you can drag it back whenever you want.
- **+** adds a removed stat back at the bottom of your priority.
- **Reset to default** puts the spec back the way it started.

### Starts from the defaults, never from a blank list
Your first change to a spec starts from that spec's default list, so moving one stat leaves the rest as they were. If you change it back to the default, StatLedger goes back to following the default.

### Knows your spec
Your spec is the talent tree you've put the most points into (your class's usual tree before you spend any). When you respec, every addon using StatLedger switches to the matching list.

### Account-wide
Customisations are saved by class and spec across your account. Tune Fire Mage once, and every Fire Mage you play uses it.

### Edit any spec
Class icons and spec buttons across the top of the page let you set up a priority for any class and spec, not just the one you're logged in as. That's handy for alts and dual specs.

---

## Works with

- **SpyGlass**: ranks dungeon and raid loot by your StatLedger list, right on the Character window.
- **Bandolier**: uses your StatLedger list when choosing buff food, elixirs and enhancement potions (with its "Automatic" stat preset).
- **Your own addon**: see *For addon authors* below.

StatLedger has no dependencies and works on its own.

---

## How to use

1. Type **/statledger**, or open **Options > AddOns > StatLedger**.
2. The page opens on your current class and spec, marked "(you)".
3. Drag stats into order, best first. Press **X** on anything you don't care about.
4. That's it. Your changes save immediately, and supporting addons update straight away.

| Command | What it does |
|---|---|
| `/statledger` | Open the settings page on your current spec |
| `/statledger show` | Print your current priority in chat |
| `/statledger reset` | Reset your current spec to its default |

---

## Default priorities

These are starting points, not simulation results. Adjust them to your gear, your raid and your play style.

| Class | Spec | Default priority |
|---|---|---|
| Warrior | Arms | Strength > Attack Power > Critical Strike > Agility > Stamina > Hit > Weapon DPS > Armor |
| Warrior | Fury | Strength > Attack Power > Critical Strike > Agility > Hit > Stamina > Weapon DPS > Armor |
| Warrior | Protection | Stamina > Armor > Strength > Agility > Attack Power > Defense > Parry > Dodge > Block Chance > Block Value |
| Paladin | Holy | Healing > Intellect > Mana Regeneration > Spell Critical Strike > Stamina > Spirit > Spell Power |
| Paladin | Protection | Stamina > Armor > Spell Power > Strength > Agility > Defense > Block Chance > Block Value > Parry > Dodge |
| Paladin | Retribution | Strength > Attack Power > Critical Strike > Agility > Intellect > Hit > Stamina > Weapon DPS |
| Hunter | Beast Mastery | Agility > Attack Power > Critical Strike > Hit > Intellect > Ranged Attack Power > Stamina > Mana Regeneration |
| Hunter | Marksmanship | Agility > Attack Power > Critical Strike > Hit > Intellect > Ranged Attack Power > Stamina > Mana Regeneration |
| Hunter | Survival | Agility > Attack Power > Critical Strike > Stamina > Intellect > Hit > Ranged Attack Power > Mana Regeneration |
| Rogue | Assassination | Agility > Attack Power > Critical Strike > Strength > Hit > Stamina > Weapon DPS > Haste |
| Rogue | Combat | Agility > Attack Power > Critical Strike > Strength > Hit > Stamina > Weapon DPS > Haste |
| Rogue | Subtlety | Agility > Attack Power > Critical Strike > Strength > Stamina > Hit > Weapon DPS > Haste |
| Priest | Discipline | Healing > Intellect > Spirit > Mana Regeneration > Stamina > Spell Critical Strike > Spell Power |
| Priest | Holy | Healing > Intellect > Spirit > Mana Regeneration > Stamina > Spell Critical Strike > Spell Power |
| Priest | Shadow | Spell Power > Shadow Spell Power > Intellect > Spirit > Stamina > Hit > Spell Critical Strike > Mana Regeneration |
| Shaman | Elemental | Spell Power > Nature Spell Power > Spell Critical Strike > Intellect > Mana Regeneration > Hit > Stamina > Spirit |
| Shaman | Enhancement | Strength > Attack Power > Agility > Critical Strike > Intellect > Hit > Weapon DPS > Stamina |
| Shaman | Restoration | Healing > Intellect > Mana Regeneration > Spirit > Stamina > Spell Critical Strike > Spell Power |
| Mage | Arcane | Spell Power > Arcane Spell Power > Intellect > Spirit > Mana Regeneration > Spell Critical Strike > Hit > Stamina |
| Mage | Fire | Spell Power > Fire Spell Power > Spell Critical Strike > Intellect > Mana Regeneration > Hit > Spirit > Stamina |
| Mage | Frost | Spell Power > Frost Spell Power > Spell Critical Strike > Intellect > Mana Regeneration > Hit > Spirit > Stamina |
| Warlock | Affliction | Spell Power > Shadow Spell Power > Stamina > Intellect > Spirit > Hit > Spell Critical Strike > Mana Regeneration |
| Warlock | Demonology | Spell Power > Shadow Spell Power > Stamina > Intellect > Spirit > Hit > Spell Critical Strike > Mana Regeneration |
| Warlock | Destruction | Spell Power > Shadow Spell Power > Spell Critical Strike > Intellect > Stamina > Hit > Fire Spell Power > Spirit |
| Druid | Balance | Spell Power > Arcane Spell Power > Nature Spell Power > Intellect > Mana Regeneration > Spell Critical Strike > Hit > Spirit |
| Druid | Feral | Agility > Strength > Attack Power > Stamina > Armor > Critical Strike > Hit > Dodge |
| Druid | Restoration | Healing > Intellect > Spirit > Mana Regeneration > Stamina > Spell Critical Strike > Spell Power |

Every list can hold all 26 stats: Strength, Agility, Stamina, Intellect, Spirit, Attack Power, Ranged Attack Power, Spell Power, Healing, Fire / Frost / Shadow / Arcane / Nature Spell Power, Critical Strike, Spell Critical Strike, Hit, Haste, Mana Regeneration, Armor, Defense, Dodge, Parry, Block Chance, Block Value and Weapon DPS.

---

## For addon authors

StatLedger sets a global `StatLedger` table. Add `## OptionalDeps: StatLedger` to your TOC so it loads first, then:

```lua
if StatLedger and StatLedger.VERSION and StatLedger.VERSION >= 1 then
    local stats   = StatLedger:GetPriority()  -- { "SP", "FIRE", "SPELLCRIT", ... } best first
    local weights = StatLedger:GetWeights()   -- { SP = 1.0, FIRE = 0.87, ... } 1st = 1.0 down to 0.1

    StatLedger:RegisterCallback("MyAddon", function(event, class, spec)
        -- "PRIORITY_CHANGED" or "SPEC_CHANGED": re-read and refresh
    end)
end
```

`VERSION` is the API's version (a number); `API_VERSION`, its older name, still works.

`class` is a class token (`"MAGE"`) and `spec` a talent tab (1-3). Both default to the player's when left out. Getters return copies, so you can change what you get.

| Function | Returns / does |
|---|---|
| `GetActiveSpec()` | `class, spec, specName` |
| `GetPriority(class, spec)` | Ordered stat keys: the custom list, else the default |
| `GetDefaultPriority(class, spec)` | The built-in list |
| `GetWeights(class, spec)` | `{ [stat] = weight }` |
| `IsCustom(class, spec)` | Whether the player has changed this spec |
| `SetPriority`, `SetSlot`, `InsertStat`, `RemoveStat`, `MoveStat`, `ResetPriority` | Edit a spec's list |
| `GetRemovedStats(class, spec)` | Stats not in the list |
| `GetStats()`, `GetStatLabel(stat)`, `GetClasses()`, `GetSpecs(class)` | Metadata for your own UI |
| `RegisterCallback(owner, fn)`, `UnregisterCallback(owner)` | Change notifications: `fn(event, class, spec)`, one callback per owner, run in the order registered |

Stat keys: `STR AGI STA INT SPI AP RAP SP HEAL FIRE FROST SHADOW ARCANE NATURE CRIT SPELLCRIT HIT HASTE MP5 ARMOR DEF DODGE PARRY BLOCK BLOCKVALUE DPS`. Ignore any your addon doesn't score.

---

## Notes

- Built for **World of Warcraft: Forever** (Interface 16001).
- Saved variables: `StatLedgerDB` (account-wide). Only the specs you change are stored.
- The defaults are starting points. They aren't simulator output or best-in-slot rankings.

Bug reports and suggestions are welcome in the comments or on the issue tracker.
