# StatLedger

One place to set your stat priority for each class and spec. Other addons read it from here
instead of keeping their own lists.

- Each of the 27 class/spec combinations has a built-in default priority.
- Customising a spec starts from that default, so changing one slot leaves the others as they were.
- Customisations are saved account-wide, keyed by class and spec (`StatLedgerDB`).
- Your spec is the talent tree with the most points (the class's usual tree before any talents).

Open with `/statledger`, or from Options > AddOns > StatLedger. Pick a class and spec, then drag
stats into order. X moves a stat under "Removed", where it stays visible so you can drag it back
(or press + to add it to the bottom).

| Command | |
|---|---|
| `/statledger` | Open the settings page on your spec |
| `/statledger show` | Print your current priority |
| `/statledger reset` | Reset your current spec to its default |

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

`class` is a class token (`"MAGE"`), `spec` a talent tab index (1-3). Both default to the
player's when left out. Getters return copies.

| Function | Returns |
|---|---|
| `:GetActiveSpec()` | `class, spec, specName` |
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

### What stats are worth

Scoring addons all price stats through `:Score`, so they agree. A point of a main stat is 1; other
stats use rough item budgets (Attack Power 0.5, Spell Power 0.86, MP5 2.5, ...). Crit is priced in the
stat that buys it: 1% crit costs as much as the Agility that gives your class 1% crit at your level
(about 10 for a level 30 druid), capped at its item budget of 14. Agility, Strength and Intellect also
earn half the worth of what they produce for your class (crit, attack power, armor, spell crit), by
your weights, so the stat that feeds your top stats counts for more without running away.

Stat keys: STR AGI STA INT SPI AP RAP SP HEAL FIRE FROST SHADOW ARCANE NATURE CRIT SPELLCRIT
HIT HASTE MP5 ARMOR DEF DODGE PARRY BLOCK BLOCKVALUE DPS. Ignore keys your addon doesn't score.
