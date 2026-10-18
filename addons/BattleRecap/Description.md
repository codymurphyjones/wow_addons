# BattleRecap

**Died in PvP and not sure what hit you? BattleRecap tells you the moment you die, why it happened, how to beat them next time, and who keeps doing it.**

PvP is chaos. You're at full health, three people jump you, and you're dead before you know who did it. When you die in a battleground, an arena or world PvP, BattleRecap shows a short recap: who killed you, with what, and how fast it happened. One click opens a breakdown of every hit. Duel someone, and you get both sides of the fight, won or lost.

- Built for **WoW Forever**. It never touches the combat log, so it never gets blocked.
- Lifetime stats, nemeses, match summaries, counter advice and one-key revenge targeting.
- No libraries and no dependencies.

---

## Features

### A recap the moment you die
A small window pops up with:

- **Killed by**: the killer in their class colour, and the killing blow: the spell, how hard it hit, whether it crit, and the overkill.
- **Summary**: damage taken, over how many seconds, from how many enemies, damage per second, your biggest hit, crits and mitigated damage.
- **Damage taken**: your top three attackers with share bars.
- **Nemesis**: how many times this killer has got you, this match and overall. For duels, your record against them.
- **Health strip**: your health across the fight. Hover it for the time and health at any point.
- **The killer's damage**: their spells, with hits, crits and totals.
- **Your damage**: what you did back in the same fight. You get your total and damage per second, how much of the damage you took you returned, your healing, who you hit (and your share of the damage they took) and your top spells.
- **Notes**, **How to beat them** and **What you could have done** (see below).
- **Share** and **Details** buttons.

It closes with Escape or the X, and by itself when you're resurrected (you can turn that off). The **<** and **>** arrows step through your saved recaps.

### A detailed breakdown
Press **Details** for every hit:

| Tab | Shows |
|---|---|
| **Timeline** | Every hit to the hundredth of a second, with your health after it, the source, spell and amount. Crits, crushing and glancing blows, ticks, resists, blocks, absorbs, overkill and the killing blow are all marked. |
| **Attackers** | Each enemy's damage, share, hits, crits, crit rate, biggest and average hit. Click one to show their spells. |
| **Spells** | Everything that hit you, from anyone. Click a column title to sort by total, hits, crits, biggest or average hit. |
| **Your damage** | Your damage, per second, and healing in the fight, per enemy and per spell. |
| **Notes & mitigation** | Why you died, damage by school, what was absorbed, resisted and blocked, the killing blow and the biggest hit. |
| **Counter** | Every enemy class in the fight: what its damage showed, how to counter it, and how your class beats theirs. |
| **Graphs** | Damage taken over time, stacked by attacker in class colours, with your health line on top. Then bar charts of who hit you, what hit you, who you hit and your spells. Click a name or bar to focus on one enemy: everything else dims and a summary shows exactly what passed between you. Hover a time slice for its hits. |

Hover any spell for its tooltip.

### Why you died
Up to three short notes on every recap, such as:
- burst you couldn't react to (most of your health in under 2 seconds)
- the same enemy killing you 3+ times this match
- being focused by three or more enemies
- mostly damage over time that a dispel would have stopped
- mostly magic damage
- a killing blow no heal would have saved
- a slow death with time for a defensive
- falling and the like

Duel recaps compare your damage with theirs.

### How to beat them
Class-specific counter notes written for WoW Forever: Classic Era rules plus Forever's class changes, such as Mutilate, Arcane Blast, Ice Lance, Victory Rush, in-combat traps and baseline Fear Ward.

- **Signature spells**: Ambush (a stealth opener), Aimed Shot (a 3-second cast, so break line of sight), Conflagrate (dispel Immolate to deny it) and more.
- **Combos**, timed from the hits: Frost Nova into a Frostbolt crit (Shatter), Stormstrike into Earth Shock, Immolate into Conflagrate, Pounce into Shred, a stun before Eviscerate.
- **Your class vs theirs**: one line on how your class beats theirs, with ability levels where they matter in low brackets.
- **General advice** against that class.

Every line is tied to what actually happened. Aimed Shot advice only appears if an Aimed Shot hit you, and pet advice only if their pet did damage. The recap can't see crowd control, so a gap in the damage stands in for a stun or Fear.

### What you could have done
Damage your own class or race had an answer to, with the ability and the level you learn it at:

- **Poisons, diseases, magic DoTs, curses and bleeds**: "Serpent Sting did 600 over 5 ticks. As a Druid, Cure Poison or Abolish Poison would have removed it." Dwarves get Stoneform.
- **Casts that hit hard**: Kick, Counterspell, Earth Shock, Shield Bash, Bash, Spell Lock...
- **Slows and roots** before the damage: shapeshifting, Blessing of Freedom, Blink, Vanish, Escape Artist, a Free Action Potion.
- **Fears**: Fear Ward, Tremor Totem, Berserker Rage, Will of the Forsaken, the PvP trinket.
- **One school doing most of the damage**: resistance auras, totems and wards.

Each note also says what works for any class: which teammates can help ("A Paladin or Shaman teammate can cure it for you"), plus potions, resistance gear and line of sight. An answer you haven't learned yet says so, for example "(at 26)".

### Vanishes don't split the fight
If a rogue vanishes, combat drops, and they open on you again, the recap still shows the damage from before the vanish as "Earlier in this fight". Combat that comes back within 10 seconds (30 if it's the same enemy) counts as the same fight.

### Nemeses and lifetime stats
"The 3rd time Stabbyface got you this match, 11 overall." Lifetime stats are counted from every recap you've ever had, not just the last 20:

| Tab | Shows |
|---|---|
| **Overview** | Deaths by kind, average time to die and damage taken, deaths per match, your nemesis, damage by school, duel record and streak |
| **Nemeses** | Everyone who has killed you: kills, class, their favourite killing blow, and when they last got you |
| **Classes** | Which classes kill you, with shares |
| **Spells** | The spells that hurt you most: damage taken, killing blows, and how many deaths they were in |
| **Duels** | Won, lost, win rate and streak per opponent |

### Match summary
When a battleground or arena ends, a card shows:
- victory or defeat
- your scoreboard line: killing blows, honorable kills, deaths, honor, damage and healing
- every death of the match (click one for its recap)
- who got you most

Your last 5 matches are saved.

### Revenge
Bind a key in **Key Bindings > BattleRecap > Target your last killer**, or make a macro with `/brecap macro`. One press then targets whoever killed you last, and the popup reminds you: "Press F5 to target Stabbyface". If you die in combat, the target updates as soon as combat ends.

### Share
Post a one-line summary to say, party, raid, guild or instance chat. You can also copy the whole recap as text for Discord. Where the game won't let addons send chat (inside instances, or in combat), you can still copy the text.

### Every PvP death, and every duel
- **Battlegrounds**: every death.
- **Arenas and world PvP**: any death where an enemy player, or a pet or totem they control, was hitting you. Deaths to monsters are left out.
- **Duels**: a duel doesn't kill anyone, so BattleRecap reads Blizzard's damage meter instead. It shows the damage you took and the damage you did, with totals per spell, for duels you win or lose. Every duel counts toward your record against that opponent.

### Your last 20 recaps, one click away
A minimap button in battleground colours (crossed swords and a skull on Alliance blue and Horde red):
- **Left-click** shows or hides your latest recap.
- **Shift-click** opens your lifetime stats.
- **Right-click** lists your last 20 deaths and duels, with killer, killing blow, battleground, damage taken and time. Click one to open it, or right-click it for the full breakdown.
- **Drag** it around the minimap. Until you move it, it steps aside from other minimap buttons.

### Settings
In **Options > AddOns > BattleRecap** (or right-click it in the addon compartment), you can set:
- what to record
- the popup per kind (battleground, arena, world PvP, duel)
- hiding the popup when you're resurrected
- notes and counter advice
- a sound
- popup size and opacity
- the match summary
- the minimap button
- the revenge macro

### Built for WoW Forever
Addons can't read the combat log on this client, so BattleRecap reads Blizzard's own death recap after you die. That covers every hit of your final seconds, with the attacker, spell, amount, crits, overkill, absorbs, resists, blocks and your health after each hit. It never reads values the game keeps hidden, so it never gets blocked. Anything hidden shows as unknown, and the recap tells you so.

---

## Good to know

- Blizzard's death recap has no heals, debuffs, crowd control or your own actions, so neither does BattleRecap. Blizzard also decides how many seconds it covers.
- Duel recaps come from totals, so they have no timeline, graph, hit counts or crits.
- The recap can take a moment to appear after death. BattleRecap keeps trying for about two seconds.
- Pets are marked "(pet)". The recap doesn't say who owns them.
- Test recaps never count toward your stats.
- WoW Forever is still in beta, so some counter advice may change as classes do.

---

## Commands

| Command | Does |
|---|---|
| `/brecap` | Show your last death |
| `/brecap details` | Open the full breakdown |
| `/brecap history` | List your saved deaths (up to 20); `/brecap <n>` opens one |
| `/brecap stats` | Lifetime stats: nemeses, classes, spells, duel record |
| `/brecap match` | The summary of your last battleground or arena |
| `/brecap share [channel]` | Post the recap in chat (say, party, raid, guild or instance) |
| `/brecap macro` | Make a macro that targets your last killer |
| `/brecap options` | Open the settings |
| `/brecap test` | Show a made-up death to try it anywhere (`test duel`, `test win`, `test match`) |
| `/brecap toggle` | Popup on death on or off |
| `/brecap autohide` | Hide the popup when you're resurrected, on or off |
| `/brecap minimap` | Show or hide the minimap button |
| `/brecap pvp` | Record PvP deaths outside battlegrounds, on or off |
| `/brecap duels` | Record lost duels, on or off |
| `/brecap wins` | Record won duels, on or off |
| `/brecap clear` | Forget saved deaths (`/brecap clear stats` clears lifetime stats) |
| `/brecap reset` | Put the windows back in the middle |

`/battlerecap` works too, and so does the addon compartment button.
