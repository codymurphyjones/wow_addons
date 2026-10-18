# BattleRecap

When you die in PvP, or duel someone, a small window shows who beat you, which spells they used,
how much damage you took and how fast, and short notes on why you died. **Details** opens a full
breakdown. It also keeps lifetime stats (your nemeses, the classes and spells that kill you most,
your duel record), sums up each battleground and arena when it ends, and can target your last
killer with one key.

What it records:

| Where | Recorded |
|---|---|
| Battlegrounds | Every death |
| Arenas and the open world | Deaths where an enemy player, or a pet or totem an enemy player controls, hit you (`/brecap pvp` turns this off) |
| Duels | Every duel you lose (`/brecap duels` turns this off) and win (`/brecap wins`) |

Deaths to monsters outside battlegrounds are ignored.

- On this client (WoW Forever, build 16001, on the 12.x engine) addons may not read the combat log:
  registering for it gets the addon blocked. Health in combat is a "secret" value too. So
  BattleRecap reads Blizzard's own death recap (`C_DeathRecap`) after you die: every hit of your
  final seconds, with the attacker, spell, amount, crit, overkill, absorbed/resisted/blocked, and
  your health at each hit. Anything the game keeps secret is shown as unknown, and the recap says
  it was partly hidden.
- The recap has no heals, debuffs, crowd control or your own actions, so neither does BattleRecap.
- **Duels** end at 1 health, so there's no death and no death recap. When the "X has defeated Y
  in a duel" message names you, BattleRecap waits for combat to end and reads Blizzard's damage
  meter (`C_DamageMeter`): the damage you took and the damage you did, as totals per attacker and
  spell. There are no single hits, so duel recaps have no timeline, graph, hit counts or crits.
  Every duel counts toward your record against that opponent, even with duel recaps turned off.
- **Vanish and re-engage**: when combat drops mid-fight (a rogue vanishes, then opens on you
  again), the game starts a new damage-meter session and Blizzard's death recap may not reach
  back. BattleRecap keeps each combat for a few minutes, read from the meter as soon as it's
  readable, and counts a combat that ended at most 10 seconds before the next one began (30 if
  someone from it hits you again) as the same fight. A death recap shows that earlier damage as
  "Earlier in this fight" (totals per attacker and spell); a duel recap simply adds it in.
- The **death window** is the stretch from the last hit that left you at 90% health or more until
  you died. Totals, attackers and spells are counted over it.
- The last 20 recaps (deaths and duels) are saved account-wide (`BattleRecapDB.history`), and `<` / `>` step through
  them.

## Notes: why you died

Up to three short notes under each recap (and on the Details "Notes & mitigation" tab), from
simple rules: burst (most of your health in under 2 seconds), the same enemy killing you 3+ times
this match, focused by 3+ enemies, mostly damage over time (dispellable), mostly magic, a killing
blow with a lot of overkill, a slow death (time for a defensive), or falling and the like. Duels
compare your damage with theirs. Turn them off in the settings.

## Counter notes: how to beat them

For each enemy class in a recap, BattleRecap lists what its damage shows and how to counter it,
written for WoW Forever (Classic Era rules plus Forever's class changes: Mutilate, Arcane Blast,
Ice Lance, Victory Rush, in-combat traps, Banes, baseline Fear Ward and so on; no TBC tools):

- **Signature spells**: e.g. Ambush (stealth opener), Mutilate (poisoned targets take more),
  Aimed Shot (3s cast, LoS it), Conflagrate (dispel Immolate to deny it), Exorcism (you're Forsaken).
- **Combos**, timed from the hits: Frost Nova into a Frostbolt crit (Shatter), Stormstrike into
  Earth Shock, Immolate into Conflagrate, Pounce into Shred, and "a pause, then Eviscerate": no
  damage for a few seconds means crowd control (the recap has no CC, so a gap stands in for it).
- **Your class vs theirs**: one line on how your class beats theirs, with ability levels where
  they matter in a low bracket.
- **General advice** against that class.

Every line is tied to what actually happened: advice about Aimed Shot only appears if an Aimed
Shot hit you, pet advice only if their pet did damage, and the "a stun or Fear happened" lines
only when their damage came after a pause of 4s or more (5.5s for hunters, whose Auto Shot alone
is about 3s apart). Lines and their triggers are in `CounterAdvice.lua`.

The popup shows the top pattern and your matchup line under "How to beat <class>"; the Details
**Counter** tab lists every enemy class in the fight. Turn it off in the settings. The advice is
in `CounterData.lua` (sources: Blizzard's WoW Forever class deep dives, Sept/Oct 2026, and
Classic PvP guides); Forever is still in beta, so some of it may change.

## What you could have done

Damage your own class (or race) had an answer to, with the ability and the level you learn it:

- Poisons, diseases, magic DoTs, curses and bleeds: "Serpent Sting (poison) did 600 over 5 ticks.
  As a Druid, Cure Poison or Abolish Poison would have removed it." Dwarves get Stoneform.
- Casts that hit hard: Earth Shock, Kick, Counterspell, Shield Bash, Bash, Spell Lock...
- Slows and roots before the damage that followed: shapeshifting, Blessing of Freedom, Blink,
  Vanish, Escape Artist, or a Free Action Potion.
- A Fear (a pause in the damage before a warlock or priest hits again): Fear Ward, Tremor Totem,
  Berserker Rage, Will of the Forsaken, or the PvP trinket.
- One school doing most of the damage: resistance auras, totems and wards.

Each note also says what works whatever your class: which teammates can do it for you ("A
Paladin or Shaman teammate can cure it for you") and what anyone can use (Anti-Venom, a Free
Action Potion, a Restorative Potion, resistance gear, line of sight). And "How to beat <class>"
adds general advice against that class next to your own class's matchup line.

It shows when a kind of damage is at least 10% of what you took. An answer you haven't learned
yet says "(at 26)". It's on the popup (top two), the Details Counter tab and in shared text.

## Nemeses and lifetime stats

Each recap notes how often its killer has got you: "The 3rd time Stabbyface got you this match,
11 overall". `/brecap stats` (or shift-click the minimap button) opens lifetime stats, counted from
every recap ever saved, not just the last 20:

| Tab | Shows |
|---|---|
| Overview | Deaths by kind, average time to die and damage taken, deaths per match, your nemesis, damage by school, duel record and streak |
| Nemeses | Everyone who has killed you: kills, class, their favourite killing blow, when last |
| Classes | Which classes kill you, with shares |
| Spells | The spells that hurt you most: damage taken, killing blows, how many deaths they were in |
| Duels | Won, lost, win rate and streak per opponent |

Test recaps aren't counted. `/brecap clear stats` (or shift-click **Reset stats**) clears them.

## Match summary

When a battleground or arena ends, a card shows victory or defeat, your scoreboard line (killing
blows, honorable kills, deaths, honor, damage and healing, whatever the game shows), every death
of the match (click one for its recap) and who got you most. The last 5 are saved; `/brecap match`
reopens the latest.

## Revenge

Bind a key in **Key Bindings > BattleRecap > Target your last killer**, or make a macro with
`/brecap macro`, and one press targets whoever killed you last. The popup then shows "Press F5 to
target Stabbyface". Targeting is protected, so this is a hidden secure button with
`/targetexact <killer>`; its target can only change out of combat, so a death in combat updates it
as soon as combat ends.

## Share

**Share** on the popup (or `/brecap share [say|party|raid|guild|instance]`) posts a one-line
summary in chat, and shows the whole recap as text to copy (Ctrl+C) for Discord and the like. On
this client addons may not send chat in some places (inside instances, or in combat); then Send is
off and you can still copy the text.

## Settings

Options > AddOns > BattleRecap (or `/brecap options`, or right-click it in the addon compartment):
what to record, the popup per kind (battleground, arena, world PvP, duel), hiding it when you're
resurrected, notes, a sound, popup size and opacity, the match summary, the minimap button and the
revenge macro.

## Minimap button

A battleground-coloured button (crossed swords and a skull on Alliance blue and Horde red):

- **Left-click** shows or hides the latest recap. **Shift-click** opens the lifetime stats.
- **Right-click** lists your last 20 deaths and duels: killer, killing blow, battleground, damage
  taken and time. Click one to show its recap, right-click it for the full breakdown. **Stats**
  and **Match** at the top open the lifetime stats and the last match summary.
- **Drag** moves it around the minimap. Until you do, it steps aside from other minimap buttons.
- `/brecap minimap` hides or shows it.

## The popup

- **Killed by**: the killer in their class colour, and the killing blow (spell, amount, crit,
  overkill).
- **Summary**: damage taken, over how long, from how many enemies, damage per second, the biggest
  hit, crits and mitigated damage.
- **Damage taken**: the top three attackers, with share bars.
- **Nemesis**: how many times this killer has got you, this match and overall (for duels, your
  record against them).
- **Health strip**: your health over the death window; hover it for the time and health.
- **The killer's damage**: their spells, with hits, crits and totals.
- **Your damage**: what you did in the same fight: total, per second, how much of the damage you
  took you did back, healing, who you hit (and your share of the damage they took) and your top
  spells. Read from the damage meter when combat ends, for deaths and duels alike.
- **Notes**: why you died (see below).
- **Share** and **Details** buttons.

It closes with Escape or the X, and by itself when you're resurrected (`/brecap autohide`).

## Details

| Tab | Shows |
|---|---|
| Timeline | Every hit to the hundredth of a second, with your health after it, the source, the spell, the amount and flags (crit, crushing, glancing, tick, resisted, blocked, absorbed, overkill, killing blow) |
| Attackers | Per attacker: damage, share, hits, crits, crit %, max and average. Click one to show or hide their spells |
| Spells | Every spell that hit you, from anyone. Click a column title to sort |
| Your damage | Your damage done and per second, damage taken in the same combats, healing done, your damage to each enemy (and your share of what they took), and each of your spells |
| Notes & mitigation | The notes on why you died, damage by school, absorbed/resisted/blocked, the killing blow and the biggest hit |
| Counter | For each enemy class: the patterns and combos its damage showed, how to counter each, how your class beats it, and general advice |
| Graphs | Damage taken over time, stacked by attacker in class colours, with your health line over it; then bar charts of who hit you, what hit you, who you hit and your spells. Click a name (or a bar) to focus on one enemy: everything else dims, and a summary shows exactly what passed between you. "Death window only" leaves out earlier hits. Hover a time slice for its hits |

Hover any spell for its tooltip.

## Commands

| Command | |
|---|---|
| `/brecap` | Show your last death |
| `/brecap details` | Open the full breakdown |
| `/brecap history` | List saved deaths (up to 20); `/brecap <n>` opens one |
| `/brecap stats` | Lifetime stats: nemeses, classes, spells, duel record |
| `/brecap match` | The summary of your last battleground or arena |
| `/brecap share [channel]` | Post the recap in chat (say, party, raid, guild or instance; default: the one you're in) |
| `/brecap macro` | Make a character macro that targets your last killer |
| `/brecap options` | Open the settings |
| `/brecap test` | Show a made-up death, to try the windows anywhere (`test duel`, `test win`, `test match`) |
| `/brecap pvp` | Recording PvP deaths outside battlegrounds on or off |
| `/brecap duels` | Recording lost duels on or off |
| `/brecap wins` | Recording won duels on or off |
| `/brecap toggle` | Popup on or off, for every kind (per kind in the settings) |
| `/brecap autohide` | Hiding the popup when you're resurrected on or off |
| `/brecap minimap` | Show or hide the minimap button |
| `/brecap clear` | Forget saved deaths (`/brecap clear stats`: the lifetime stats) |
| `/brecap reset` | Put the windows back in the middle |

`/battlerecap` works too, and so does the AddOns compartment button.

## Notes

- The recap can take a moment to appear after death; BattleRecap tries again for about two
  seconds. A recap identical to the previous one is from an earlier death and is ignored.
- How many seconds the recap covers is up to Blizzard.
- Pets are marked "(pet)". The recap doesn't say who owns them.
