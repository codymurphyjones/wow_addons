# SmartPlates

**Threat-reactive nameplates that tell you how much aggro you have, not just whether you have it.**

SmartPlates colours, sizes and fades every enemy nameplate by threat, the way Threat Plates does, and adds a number to each plate: your **aggro percentage**. Its look is flat and dark, with thin borders and a teal accent.

- Built for **World of Warcraft: Forever**.
- No libraries and no dependencies.
- Settings are shared by all your characters. Your role, window position and minimap button are saved per character.

---

## The aggro percentage

**100% is the point where aggro changes hands.** Everyone reads the same scale.

| You are... | You see | Meaning |
|---|---|---|
| Holding aggro | **100% or more** | How far ahead you are. **200%**: the next person has half of what it takes to pull. **110%**: someone is about to take it. **MAX**: nobody else is on the threat table. |
| Not holding aggro | **0% to 100%** | How close you are to pulling. At **100%** the mob turns to you. The 110% melee / 130% ranged rule is already counted. |

The number takes the colour of the threat state. By default it shows only in a group or with a pet out, since solo it would always say MAX. You can set it to always or never, and move it left of, right of, or above the healthbar.

---

## Threat colours

| State | DPS / Healer | Tank |
|---|---|---|
| Low threat | green (safe) | red (lost aggro) |
| Medium threat | yellow | yellow (losing it) |
| High threat | red (you have aggro) | green (holding it) |
| Off-tanked | | blue (another tank or your pet has it) |

Plates also grow or shrink and fade by threat state, and a warning glow appears when the state is bad for your role. Everything can be changed on the **Threat** and **Threat Look** pages.

**Role detection.** SmartPlates works out your role from:
- Warrior: Defensive Stance.
- Druid: Bear or Dire Bear Form.
- Paladin: Righteous Fury.

You can force it with `/sp role tank` or `/sp role dps`.

---

## Everything else on a plate

- Healthbar with health text, level, name, target border, mouseover highlight and absorbs. The health text shows the actual value by default (12k); switch it to a percent, both, the missing amount or off under **General > Health text**. It keeps working in combat, even though WoW Forever hides health values from addons.
- Castbar with spell icon and name. It's grey when the cast can't be interrupted, and flashes red when interrupted.
- Auras: your debuffs, crowd control from anyone, and buffs you can steal or purge. Spell whitelist and blacklist.
- Raid target marker, plus elite and rare icons.
- Combo points under your target.
- Your target's power as a thin strip.
- Arena numbers and spec icons.
- Enemy healer marker.
- Totem icons.
- Class icons.
- Friend and guild markers.
- Quest mob marker.
- Optional XP bar.
- Boss ability icons and timers from **DBM** or **BigWigs**, if you use either.
- **Custom plates**: recolour, resize or hide mobs by name.
- **View distance and stacking**: plates show up to 41 yards away (the game's maximum) and stack instead of overlapping. Your previous game settings come back if you turn this off.
- **Unit-type filters**: enemy pets and guardians and minor mobs get small plates. Friendly pets are hidden. Each type can be set to show, small or hide.
- **Interrupt ready**: enemy castbars turn green while your interrupt (Kick, Pummel, Counterspell, Earth Shock...) is off cooldown.
- **Execute range**: enemies under 20% health (adjustable) change colour, with a marker on the bar.
- **Mob's target**: who each mob is attacking ("YOU" in red), inside its healthbar.
- **Focus**: an orange border on your focus target. Your target gets teal arrows (or a border or glow).
- **Big crowd-control icon**: stuns, fears and polymorphs as one large icon with a countdown. Aura icons show seconds left.
- **Bar textures**: Flat, Blizzard, Raid or Smooth.
- **Sizes by kind**: separate sizes for enemy players, NPCs, friendly units and small plates.
- **Profiles**: named profiles shared by your characters, with export to one line of text and import.
- Friendly units show just their name by default.

## Your target frame (optional)

Turn on **SmartPlates draws your target frame** (General) and your target gets a big SmartPlates plate in place of Blizzard's target frame: the same health, name, threat colour and percentage, castbar, auras and combo points as its nameplate, as a compact, crisp bar (144 x 14 px by default, 1.2 times a nameplate; set its width and height to taste). Right-click it for the target's menu; shift-drag it to move it.

With **Enemy plates fly into it** (on by default), targeting an enemy sends its nameplate gliding into the target frame, growing and fading out as it slips in behind it. Switch away while it's still alive and it flies back, faster, to full opacity and its place among the plates. Friendly targets stay where they are.

---

## Commands

| Command | Does |
|---|---|
| `/sp` (or `/smartplates`) | Open the settings window |
| `/sp test` | Preview plates with the aggro percentage sweeping, so you can tune the look out of combat |
| `/sp role auto\|tank\|dps` | How SmartPlates decides your role |
| `/sp threat` | Print your threat on your target |
| `/sp minimap` | Show or hide the minimap button |
| `/sp target reset` | Put the target frame back where Blizzard's was |
| `/sp reset` | Reset every setting |

The window also opens from the minimap button, the addon compartment and **Options > AddOns > SmartPlates**.

---

## Credits

Inspired by **Threat Plates** (Suicidal Katt, Blacksalsify) and **Tidy Plates** (danltiger). SmartPlates is written from scratch and shares no code with them.
