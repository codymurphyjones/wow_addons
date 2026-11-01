# StatLedger

One place to set your stat priority for each class and spec. Other addons read it from here
instead of keeping their own lists.

- Each of the 28 class/spec combinations has a built-in default priority. Druid has four specs:
  Balance, Feral DPS, Restoration and Feral Tank.
- Customising a spec starts from that default, so changing one slot leaves the others as they were.
- Customisations are saved account-wide, keyed by class and spec (`StatLedgerDB`).
- Each character picks a main spec. A "Select main spec" window asks once you have talents, showing
  your points in each tree, and **Update Mainspec** on the settings page changes it any time. Until
  you choose, your spec is the talent tree with the most points (the class's usual tree before any talents).

Open with `/statledger`, or from Options > AddOns > StatLedger. Pick a class and spec, then drag
stats into order. X moves a stat under "Removed", where it stays visible so you can drag it back
(or press + to add it to the bottom).

| Command | |
|---|---|
| `/statledger` | Open the settings page on your spec |
| `/statledger show` | Print your current priority |
| `/statledger reset` | Reset your current spec to its default |
| `/statledger mainspec` | Choose your main spec |
| `/statledger designer` | Open the Weight Designer |

## Weight Designer

Build your own weight profiles with **Weight Designer** on the settings page, or `/statledger designer`.
Each character has its own profiles. Pick a stat to set its base weight and add cap tiers: past a
value, its weight changes (0 is a hard cap). The chart shows what the stat is worth at each value and
where you are.

A tier can **move with another stat**. Set a 35% crit soft cap, press **Move with a stat**, and pick Hit
at 1: with 5% hit the cap sits at 40%. Use a factor of 0.5 for half as much, or a negative one to
lower the cap. A tier can move with several stats.

Each of those stats can have its own limit. Enter 8 under **Up to** and hit past 8% stops raising the
cap. Set **then x** to 0.5 and hit past 8% still raises it, at half the rate.

Thresholds are what the character sheet shows: percent for hit, crit, dodge, parry and block, points
for everything else. Item scoring doesn't use these weights yet.

## For addon authors

Add `## OptionalDeps: StatLedger` to your TOC so it loads first, then check for the global:

```lua
if StatLedger and StatLedger.VERSION and StatLedger.VERSION >= 1 then
    local stats = StatLedger:GetPriority()       -- { "SP", "FIRE", "SPELLCRIT", ... }
    local weights = StatLedger:GetWeights()      -- { SP = 1.0, FIRE = 0.87, ... }
    StatLedger:RegisterCallback("MyAddon", function(event, class, spec)
        -- "PRIORITY_CHANGED" or "SPEC_CHANGED": re-read and refresh
    end)
end
```

`VERSION` is the API's version (a number); `API_VERSION`, its older name, still works.

`class` is a class token (`"MAGE"`), `spec` a spec number (1-3 is the talent tab; Druid's 4 is Feral
Tank, on the Feral tree). Both default to the player's when left out. Getters return copies.

| Function | Returns |
|---|---|
| `:GetActiveSpec()` | `class, spec, specName`: your main spec if you chose one, else your talents' top tree |
| `:GetMainSpec()`, `:SetMainSpec(spec)`, `:PromptMainSpec()` | The spec this character chose (nil: none), save it, open the window. Version 2 |
| `:GetPriority(class, spec)` | Ordered stat keys, best first: your custom list, else the default |
| `:GetDefaultPriority(class, spec)` | The built-in list |
| `:GetWeights(class, spec)` | `{ [stat] = weight }`, 1st = 1.0 falling evenly to 0.1 at the last; unlisted stats absent |
| `:IsCustom(class, spec)` | Whether the spec has been customised |
| `:SetPriority(class, spec, list)` | Replace the whole list |
| `:SetSlot(class, spec, slot, stat)` | Set one slot (a listed stat moves; `"NONE"` clears) |
| `:MoveStat(class, spec, from, to)` | Reorder |
| `:InsertStat(class, spec, stat, index)` | Put a stat at a rank (moves it if already listed) |
| `:RemoveStat(class, spec, stat)` | Take a stat out of the ranked list |
| `:GetRemovedStats(class, spec)` | Stats not in the ranked list |
| `:ResetPriority(class, spec)` | Back to the default |
| `:Describe(class, spec)` | `"Spell Power > Fire Spell Power > ..."` |
| `:GetStats()`, `:GetStatLabel(stat)` | All stat keys, display names |
| `:GetClasses()`, `:GetClassName(class)`, `:GetSpecs(class)`, `:GetSpecName(class, spec)` | Class/spec metadata |
| `:RegisterCallback(owner, fn)`, `:UnregisterCallback(owner)` | `fn(event, class, spec)`; event is `PRIORITY_CHANGED`, `SPEC_CHANGED` or `VALUES_CHANGED` (stat worth changed: you levelled; no class or spec). One callback per owner, run in the order registered; dot or colon call (the shared registry, `addons\shared\API.md`) |
| `:Score(values, weights)` | `total, contrib`: an item's worth from `{ [stat] = amount }` (percents as items give them, `1` for 1%); `contrib[stat]` includes the stat's share of what it produces. `weights` default to `:GetWeights()` |
| `:Value(stat, amount, weights)` | The worth of one stat amount, the same way |
| `:Budget(stat, amount)` | What one point (or 1%) of a stat costs before weights, for your class and level |
| `:IsPercent(stat, amount)` | Whether that amount is a percent (crit, hit... up to 5) rather than a rating |

### Assumptions

Every assumption about how stats convert is in `Assumptions.lua`: item points per 1%, cap values, item
budgets, what stats produce and effect rates. Each is a number or an equation that can use your level,
class, spec, boss level or any stat's current value. Change them there, and only there. Default weights
are preferences, so they stay in `Defaults.lua`. A cap's value is copied when a profile is made, so
changing one here affects new profiles, not existing ones.

| Function | Returns |
|---|---|
| `:ToPercent(stat, points)`, `:ToPoints(stat, percent)` | Item points of a stat as a percent and back; nil for a stat without one |
| `:EffectRates(kind)` | `{ [stat] = rate }` for an effect type (`"SPELL_DAMAGE"`, `"WEAPON_SKILL"`...) |

### What stats are worth

Scoring addons all price stats through `:Score`, so they agree. A point of a main stat is 1; other
stats use rough item budgets (Attack Power 0.5, Spell Power 0.86, MP5 2.5, ...). Crit is priced in the
stat that buys it: 1% crit costs as much as the Agility that gives your class 1% crit at your level
(about 10 for a level 30 druid), capped at its item budget of 14. Agility, Strength and Intellect also
earn half the worth of what they produce for your class (crit, attack power, armor, spell crit), by
your weights, so the stat that feeds your top stats counts for more without running away.

Stat keys: STR AGI STA INT SPI AP RAP SP HEAL FIRE FROST SHADOW ARCANE NATURE CRIT SPELLCRIT
HIT HASTE MP5 ARMOR DEF DODGE PARRY BLOCK BLOCKVALUE DPS. Ignore keys your addon doesn't score.
