local _, ns = ...

-- How to beat each class, for the counter notes (Counter.lua). WoW Forever: Classic Era rules plus
-- Forever's class changes (Blizzard's class deep dives, Sept/Oct 2026; Paladin from the BlizzCon
-- panel), so no TBC tools like Cloak of Shadows, Spell Reflection or Cyclone. Levels are given where
-- they matter in a low-level bracket (the beta stops at 30; Forever talent medals at 11/16/21/31
-- points come at about levels 20/25/30/40).
--
-- spells[name] = { what the hit shows, how to counter it }. Names are as the death recap gives them.
-- combos = { first, second, seconds, what it shows, how to counter it, critSecond = true }:
--   `second` hit within `seconds` after `first`. first = "GAP": `second` came after at least
--   `seconds` with no damage from anyone (crowd control: a stun, Fear, Polymorph or trap).
-- The class-wide advice (general, and vs your class) is in CounterAdvice.lua, tied to evidence.
-- pets[spell] = { owner class, what it shows, how to counter it } for pets and totems.

ns.COUNTER_DATA = {
    classes = {
        WARRIOR = {
            spells = {
                ["Hamstring"] = { "Snare: they kept you from getting away", "Remove it (Blessing of Freedom, a Free Action Potion{Gnome|, Escape Artist|}{DRUID|, shapeshift|}) and get past 8 yd." },
                ["Rend"] = { "Bleed (scales with attack power in Forever, can proc Overpower)", "{D|Stoneform clears it|It can't be dispelled}; don't stand in melee while it ticks." },
                ["Overpower"] = { "Proc off your dodges, or off Rend (Bloodthrill)", "Stop dodging into a Battle Stance warrior: no Evasion, take range instead." },
                ["Mortal Strike"] = { "Arms burst with -50% healing (level 40+)", "Don't try to out-heal it: kite and use defensive cooldowns in its 6s windows." },
                ["Execute"] = { "Finisher under 20% health", "At 25% health break range or CC them; a shield at 20% wastes their rage." },
                ["Victory Rush"] = { "They killed someone and healed 10% (Forever)", "Kill them within its 20s window, before the heal is used." },
                ["Spearing Strike"] = { "Dismount opener (Forever Arms, 16 points)", "Dismount at range near warriors and pre-buff instead of riding into them." },
                ["Whirlwind"] = { "Fury/Arms AoE (10s cooldown)", "Spread out from allies and kite while it's on cooldown." },
                ["Cleave"] = { "Two-target rage dump", "Don't stack in melee with a friend." },
                ["Heroic Strike"] = { "Rage dump: you stood in melee too long", "Snare, root or Fear them and take range." },
                ["Slam"] = { "2H rage dump with a cast", "Interrupt their swing time with CC; never trade in melee." },
                ["Bloodthirst"] = { "Fury burst (40+); gives them +10% speed in Forever", "Root or Fear instead of snaring: the speed makes plain kiting weaker." },
                ["Deep Wounds"] = { "Their crits are landing", "{D|Stoneform clears it; it|It} means a high-crit warrior: avoid melee." },
                ["Thunder Clap"] = { "Sword-and-board or Arms AoE slow", "Low burst: out-sustain or kite." },
                ["Revenge"] = { "Protection warrior (no stun in Forever)", "Low burst; fake-cast through Shield Bash." },
                ["Shield Slam"] = { "Protection warrior", "Out-sustain them; their damage is low." },
                ["Intercept"] = { "Berserker charge-stun (level 30)", "30s cooldown: kite hard right after it's used." },
            },
            combos = {
                { "Rend", "Overpower", 6, "Rend procced Overpower (Bloodthrill)", "Leave melee once Rend is on you: each swing can proc Overpower." },
                { "Mortal Strike", "Execute", 6, "Mortal Strike into Execute", "Use a defensive or break range when Mortal Strike lands below 40%." },
                { "Hamstring", "Execute", 10, "Hamstring then Execute", "The snare was the kill: remove snares at once instead of saving it." },
            },
        },

        ROGUE = {
            spells = {
                ["Ambush"] = { "Stealth opener from behind", "Keep moving and check behind you; back to a wall when a rogue is near." },
                ["Garrote"] = { "Stealth opener bleed (Forever: can be from the front)", "{D|Stoneform removes it; it|It} ticks, not bursts: turn and fight." },
                ["Sinister Strike"] = { "Combat rogue builder", "Don't trade in melee: snare, root or Fear and get range." },
                ["Backstab"] = { "Dagger rogue behind you", "Turn to face them and strafe: Backstab needs your back." },
                ["Mutilate"] = { "Assassination daggers (level 30), stronger vs poisoned targets", "Cleanse poisons (Cure/Abolish Poison, Cleansing Totem{D|, Stoneform|}) to weaken it." },
                ["Hemorrhage"] = { "Subtlety rogue (Hemo boosts Rupture in Forever)", "Expect Rupture next: heal through it and CC the rogue before it ramps." },
                ["Ghostly Strike"] = { "Subtlety with a dodge buff", "Don't melee-race it; use spells." },
                ["Eviscerate"] = { "Finisher, usually right after a stun", "Save your escape for when the stun ends, before the Eviscerate." },
                ["Rupture"] = { "Bleed finisher", "{D|Stoneform or heal through it|Heal through it}; reposition and CC the rogue." },
                ["Instant Poison"] = { "Poisoned weapons", "Cure/Abolish Poison, Poison Cleansing Totem, Anti-Venom{D|, Stoneform|}." },
                ["Deadly Poison"] = { "Stacking poison DoT", "Cleanse it early: it stacks to five." },
                ["Wound Poison"] = { "Poison that cuts healing", "Cleanse it before healing yourself." },
                ["Riposte"] = { "They parried you", "Stop meleeing into them; use spells." },
                ["Gouge"] = { "Gouge: to bandage, restealth, or get behind you", "Expect a Backstab or Ambush next: turn to face them as it breaks." },
            },
            combos = {
                { "GAP", "Eviscerate", 4, "A stun (Cheap Shot or Kidney Shot) then Eviscerate", "Trinket or Free Action Potion the Kidney Shot, not the Cheap Shot, to deny the finisher." },
                { "Ambush", "Eviscerate", 6, "Ambush opener straight into a finisher", "The opener decided it: move, stay near allies, and detect stealth ({Human|Perception, |}AoE)." },
                { "Garrote", "Eviscerate", 8, "Garrote opener into a finisher", "{D|Stoneform the Garrote and break|Break} away during the stun's end." },
                { "Gouge", "Backstab", 4, "Gouge, then got behind you", "Turn to face as Gouge breaks." },
                { "Hemorrhage", "Rupture", 6, "Hemorrhage set up a big Rupture", "Heal or shield through the bleed and CC the rogue." },
            },
        },

        MAGE = {
            spells = {
                ["Pyroblast"] = { "Big opener from range, or a quick Pyro from Heating Up crits", "Break line of sight when a mage targets you out of combat; LoS or interrupt the next." },
                ["Fireball"] = { "Hard-cast nuke: they cast freely", "Interrupt (Kick, Shield Bash, Earth Shock, Counterspell) or close in and LoS." },
                ["Frostfire Bolt"] = { "Forever baseline (40) nuke with a slow", "Interrupt or LoS it; remove the slow." },
                ["Fire Blast"] = { "Instant finisher", "A low mage will Fire Blast: stay out of 20 yd or kill them first." },
                ["Scorch"] = { "Fire mage stacking crit debuffs", "Short cast: LoS; Fire Ward and fire resist help." },
                ["Frostbolt"] = { "Frost kite (slow)", "Remove the slow (Freedom, a Free Action Potion{Gnome|, Escape Artist|}{DRUID|, shapeshift|}) and LoS." },
                ["Ice Lance"] = { "Forever Frost instant, triple damage on frozen targets", "Break roots at once (Freedom, the trinket{Gnome|, Escape Artist|}{DRUID|, shapeshift|}): frozen = Ice Lance burst." },
                ["Frost Nova"] = { "Root: a Shatter or kite follows", "Break the root immediately and LoS." },
                ["Cone of Cold"] = { "Melee-range escape slow (26)", "Approach from the side; expect Blink next." },
                ["Arcane Explosion"] = { "Mage in melee with nothing left", "Stay on them: they're out of cooldowns." },
                ["Arcane Missiles"] = { "Channel (fast and free after Missile Barrage in Forever)", "Interrupt the channel or LoS mid-channel." },
                ["Arcane Blast"] = { "Forever Arcane: each cast within 8s hits harder", "Interrupt or LoS by the 2nd or 3rd cast; stacks drop if they cast something else." },
                ["Ignite"] = { "Fire crits landed", "Can't be dispelled: Fire Ward or fire resist." },
                ["Blizzard"] = { "AoE: you stood in it", "Move out at once." },
                ["Flamestrike"] = { "AoE: you stood in it", "Move out at once." },
                ["Blast Wave"] = { "Fire mage melee-range knock and slow", "Don't chase blindly: a Pyroblast or Fire Blast follows." },
            },
            combos = {
                { "Frost Nova", "Frostbolt", 3, "Shatter: frozen, then a Frostbolt crit", "Break the root before the next cast lands (trinket, Freedom{Gnome|, Escape Artist|}{MAGE|, Blink|}).", critSecond = true },
                { "Frost Nova", "Ice Lance", 3, "Frost Nova into Ice Lance (triple vs frozen)", "Get out of the root immediately: the Ice Lance follows within a second." },
                { "Pyroblast", "Fire Blast", 4, "Pyroblast opener into Fire Blast", "Open combat behind cover; a mage with a long opener range wins if you walk in." },
                { "Arcane Blast", "Arcane Blast", 3, "Arcane Blast stacking", "Interrupt or LoS by the second cast." },
                { "GAP", "Pyroblast", 4, "Polymorph or Frost Nova, then a free Pyroblast", "{DRUID|Shapeshift, trinket|Trinket} or LoS during the gap; don't wait out a Polymorph in the open." },
            },
        },

        HUNTER = {
            spells = {
                ["Auto Shot"] = { "Long-range white damage", "Close through cover: in the 5-8 yd dead zone they can't shoot or melee well." },
                ["Aimed Shot"] = { "3s cast burst (baseline at 20 in Forever)", "LoS or get inside 8 yd during the cast; it shares a cooldown with Multi-Shot now." },
                ["Arcane Shot"] = { "Instant kiting damage", "Push in while it's on cooldown." },
                ["Multi-Shot"] = { "Burst shot (shares Aimed Shot's cooldown in Forever)", "After one burst shot, push them: the next is a while off." },
                ["Serpent Sting"] = { "Nature DoT", "Cure/Abolish Poison{D|, Cleansing Totem or Stoneform| or a Cleansing Totem} remove it." },
                ["Scatter Shot"] = { "Disorient: a Freezing Trap or reset follows", "Step away from the hunter's feet; trinket the trap." },
                ["Raptor Strike"] = { "Melee: you stood next to them", "Leave melee into their dead zone, or Hamstring and root them." },
                ["Mongoose Bite"] = { "Survival melee after your dodge", "Don't trade in melee; stay at range." },
                ["Wing Clip"] = { "Snare to escape you", "Remove it and close back in." },
                ["Strider Kick"] = { "Forever Survival melee strike (30)", "Don't trade in melee: they get faster after it." },
                ["Counterattack"] = { "Survival hit after a parry (Forever, 25)", "Stop meleeing into them." },
                ["Volley"] = { "AoE channel", "Move out." },
                ["Immolation Trap"] = { "Trap under you (traps work in combat now)", "Watch the ground at their feet; traps have a 30s cooldown." },
                ["Explosive Trap"] = { "Trap under you (traps work in combat now)", "Watch the ground at their feet; traps have a 30s cooldown." },
            },
            combos = {
                { "Scatter Shot", "Aimed Shot", 6, "Scatter Shot then Aimed Shot", "After Scatter, break LoS or close in before the Aimed Shot lands." },
                { "GAP", "Aimed Shot", 5.5, "Freezing Trap or Scatter, then a free Aimed Shot", "Freezing Trap works in combat now: trinket it, or stay out of the hunter's path." },
                { "Arcane Shot", "Multi-Shot", 3, "Instant burst pair", "Close in once both are on cooldown." },
            },
        },

        WARLOCK = {
            spells = {
                ["Corruption"] = { "DoT pressure", "Dispel Magic or Cleanse it." },
                ["Immolate"] = { "Fire DoT (sets up Conflagrate)", "Dispel Immolate early to deny Conflagrate." },
                ["Bane of Agony"] = { "Curse DoT (Forever's Curse of Agony)", "Remove Curse (mage, druid) if it counts as a curse." },
                ["Curse of Agony"] = { "Curse DoT", "Remove Curse (mage, druid)." },
                ["Bane of Doom"] = { "Delayed big hit", "Remove it or kill the warlock before it lands." },
                ["Siphon Life"] = { "Drain DoT", "Dispel it." },
                ["Shadow Bolt"] = { "Hard-cast nuke", "Interrupt or LoS; Shadow Protection." },
                ["Searing Pain"] = { "Fast, high-crit fire spam", "Close in and LoS; it's their mobile damage." },
                ["Shadowburn"] = { "Instant execute-range burst", "Heal or shield before 30% vs a Destruction warlock." },
                ["Conflagrate"] = { "Destruction burst after Immolate (25), may Daze", "Dispel Immolate to deny it." },
                ["Soul Fire"] = { "Huge 6s cast (faster under 35%)", "Always interrupt or LoS it." },
                ["Drain Life"] = { "Channel heal", "Interrupt, LoS, or leave its 20 yd range." },
                ["Drain Soul"] = { "Channel", "Interrupt or LoS it." },
                ["Wrack"] = { "Forever Affliction capstone (40+)", "Interrupt or LoS the channel." },
                ["Death Coil"] = { "Horror plus a heal (42)", "Bait it before your big cast." },
                ["Hellfire Effect"] = { "AoE around the warlock (hurts them too)", "Kite them: they burn themselves." },
                ["Rain of Fire"] = { "AoE channel", "Move out." },
                ["Incinerate"] = { "Forever Destruction capstone (40+)", "Interrupt or LoS." },
            },
            combos = {
                { "GAP", "Shadow Bolt", 4, "Fear, then free casting", "{Scourge|Will of the Forsaken, |}Fear Ward, Tremor Totem or trinket the Fear." },
                { "Immolate", "Conflagrate", 10, "Immolate into Conflagrate", "Dispel Immolate as soon as it lands." },
                { "Corruption", "Shadowburn", 15, "DoTs then Shadowburn execute", "Heal before the execute range, or close and interrupt." },
                { "GAP", "Soul Fire", 4, "CC, then a free Soul Fire", "Break the Fear or Seduction (WotF, Tremor, trinket) before it finishes." },
            },
        },

        PRIEST = {
            spells = {
                ["Mind Blast"] = { "Shadow burst (8s cooldown)", "Interrupt or LoS; Shadow Protection." },
                ["Shadow Word: Pain"] = { "Shadow DoT (Blackout can stun)", "Dispel it; random stuns are Blackout procs." },
                ["Mind Flay"] = { "Channelled slow", "Interrupt or LoS; {DRUID|shapeshift or |}Freedom out of the slow." },
                ["Devouring Plague"] = { "Disease DoT and self-heal (every priest at 20 in Forever)", "Cure/Abolish Disease{D|, Stoneform|} or Disease Cleansing Totem." },
                ["Shadow Word: Death"] = { "Instant execute (32); costs them 10% if it doesn't kill", "Heal or shield before you're low." },
                ["Holy Fire"] = { "Holy priest nuke", "Interrupt the cast: they run out of mana first." },
                ["Smite"] = { "Holy or Discipline damage", "Interrupt or pressure their mana." },
                ["Penance"] = { "Discipline channel (30, Forever)", "Interrupt or LoS the channel." },
                ["Mana Burn"] = { "Your mana drained", "Close in and interrupt; keep past 30 yd." },
                ["Holy Nova"] = { "Melee-range AoE, hunting stealth", "Don't open into it." },
                ["Starshards"] = { "Night Elf priest racial (much stronger in Forever)", "30s cooldown: their burst is spent." },
                ["Chastise"] = { "Dwarf priest racial (damage and a root)", "{Gnome|Escape Artist, |}Freedom or a Free Action Potion." },
                ["Touch of Weakness"] = { "Undead priest: you hit them in melee", "Minor; triggers on your melee." },
            },
            combos = {
                { "Mind Blast", "Mind Flay", 3, "Mind Blast into Mind Flay", "Interrupt the Flay or leave its range." },
                { "GAP", "Mind Blast", 4, "Psychic Scream, Silence or Mind Control, then Mind Blast", "Fear Ward, WotF, Tremor or Berserker Rage beat Scream; trinket the CC." },
                { "Shadow Word: Pain", "Mind Blast", 3, "DoT then burst", "Dispel the DoT and close in." },
            },
        },

        DRUID = {
            spells = {
                ["Ravage"] = { "Prowl opener from behind (32)", "Face them, back to a wall; trinket the stun." },
                ["Pounce"] = { "Prowl stun opener (36)", "Trinket the stun or turn to face before the Shred." },
                ["Pounce Bleed"] = { "Prowl stun opener (36)", "{D|Stoneform clears the bleed; trinket|Trinket} the stun." },
                ["Shred"] = { "Cat behind you (stronger in Forever)", "Turn to face; root or slow them with your back to a wall." },
                ["Claw"] = { "Cat damage", "Polymorph or Hibernate the cat{D|; Stoneform clears bleeds|}." },
                ["Rake"] = { "Cat bleed", "{D|Stoneform clears it.|It can't be dispelled: kill or CC the druid.}" },
                ["Rip"] = { "Cat finisher bleed", "{D|Stoneform clears it; CC|It can't be dispelled; CC} the druid." },
                ["Ferocious Bite"] = { "Cat finisher (32)", "Break away or CC before five combo points." },
                ["Maul"] = { "Bear druid", "Low burst: kite them." },
                ["Swipe"] = { "Bear AoE", "Low burst: kite them." },
                ["Primal Bite"] = { "Forever bear strike (16 points)", "Low burst: kite them." },
                ["Lacerate"] = { "Bear bleed (42)", "{D|Stoneform clears it.|It can't be dispelled: get out of the bear's reach.}" },
                ["Moonfire"] = { "Instant DoT spam", "Dispel it (magic)." },
                ["Wrath"] = { "Cast spam (weak in Forever)", "Ignore or interrupt: go for the druid." },
                ["Starfire"] = { "Balance big cast", "Interrupt it or LoS." },
                ["Insect Swarm"] = { "Balance DoT (25), lowers your hit chance", "Dispel it, then fight." },
                ["Entangling Roots"] = { "You were rooted and kited", "{Gnome|Escape Artist, |}Freedom{DRUID|, shapeshift|} or a Free Action Potion break roots." },
                ["Hurricane"] = { "AoE channel (no cooldown in Forever)", "Move out or interrupt." },
                ["Thorns"] = { "You meleed into Thorns", "Purge or dispel Thorns before meleeing." },
            },
            combos = {
                { "Pounce", "Shred", 4, "Pounce stun into Shred", "Trinket the Pounce or turn to face: Shred needs your back." },
                { "Ravage", "Ferocious Bite", 6, "Ravage opener into Ferocious Bite", "Detect stealth ({Human|Perception, |}AoE, Faerie Fire) and stay near allies." },
                { "Wrath", "Starfire", 5, "Wrath set up a fast Starfire (Eclipse)", "Interrupt the Starfire that follows a Wrath." },
            },
        },

        SHAMAN = {
            spells = {
                ["Lightning Bolt"] = { "Caster nuke (can be instant with Maelstrom Weapon in Forever)", "Interrupt or LoS; close in, they have no Blink." },
                ["Chain Lightning"] = { "2s cast burst (32)", "Interrupt; spread out from allies." },
                ["Earth Shock"] = { "Instant burst and interrupt", "Fake-cast to bait it; it's their kill button." },
                ["Flame Shock"] = { "Fire DoT", "Dispel it; also cuts Lava Burst damage." },
                ["Frost Shock"] = { "Snare kite (20)", "{DRUID|Shapeshift, |}{Gnome|Escape Artist, |}Freedom or a Free Action Potion; push in while shocks are on cooldown." },
                ["Stormstrike"] = { "Enhancement (25, 8s cooldown): next shock or bolt +20%", "A big shock follows: kite or LoS for a moment." },
                ["Windfury Attack"] = { "Enhancement Windfury procs", "Avoid long melee: Disarm, Scream or Fear." },
                ["Flametongue Attack"] = { "Enhancement weapon procs", "Avoid long melee." },
                ["Lightning Shield"] = { "You meleed into Lightning Shield", "Purge or dispel it before meleeing." },
                ["Fire Nova"] = { "Fire totem burst (a spell in Forever)", "Kill the totem; step away from it." },
                ["Magma Totem"] = { "Totem AoE", "Kill the totem: one hit." },
                ["Lava Burst"] = { "Elemental capstone (40+), stronger with Flame Shock", "Dispel Flame Shock to cut it." },
            },
            combos = {
                { "Stormstrike", "Earth Shock", 3, "Stormstrike into Earth Shock", "After Stormstrike, step out or LoS for a second: the shock is coming." },
                { "Stormstrike", "Lightning Bolt", 4, "Stormstrike into Lightning Bolt", "Interrupt the bolt or break LoS." },
                { "Flame Shock", "Lava Burst", 4, "Flame Shock into Lava Burst", "Dispel Flame Shock at once." },
                { "GAP", "Lightning Bolt", 4, "Rooted by Earthbind (Earthbound, 30), then a bolt", "Kill the Earthbind Totem; {Gnome|Escape Artist, |}Freedom or a Free Action Potion." },
            },
        },

        PALADIN = {
            spells = {
                ["Seal of Command"] = { "Ret 2H proc burst, biggest after Hammer of Justice", "Don't stand in melee while stunned-or-about-to-be; kite their slow swings." },
                ["Judgement of Command"] = { "Seal of Command judged (double vs stunned targets)", "Hammer of Justice into Judgement: trinket the stun or pre-shield." },
                ["Judgement of Righteousness"] = { "Holy judgement (ignores armor)", "Steady pressure: kite rather than trade." },
                ["Seal of Righteousness"] = { "Holy damage seal", "Armor doesn't help: kite rather than trade." },
                ["Holy Strike"] = { "Forever baseline holy weapon strike (12s cooldown)", "They're in melee range: kite." },
                ["Exorcism"] = { "Only hits Undead and Demons: you're Forsaken", "Keep range from paladins; it's an instant on a 15s cooldown." },
                ["Hammer of Wrath"] = { "Execute under 20% (44)", "Heal or LoS before 20%; interrupt the 1s cast." },
                ["Consecration"] = { "Ground AoE (baseline 20 in Forever)", "Step out of it." },
                ["Holy Shock"] = { "Holy instant (30 in Forever)", "On a cooldown: stay out of 20 yd while it's ready." },
                ["Retribution Aura"] = { "You hit them into Retribution Aura", "Melee costs you here: purge or kite." },
            },
            combos = {
                { "Judgement of Command", "Seal of Command", 3, "Judgement into a Seal of Command swing", "Trinket the Hammer of Justice before the swing, or pre-shield." },
                { "Seal of Command", "Judgement of Command", 3, "Command proc into Judgement", "Break range: their next swing comes in 3s." },
            },
        },
    },

    pets = {
        ["Firebolt"] = { "WARLOCK", "Imp (no CC pet)", "Easy: kill or ignore the Imp, then go for the warlock." },
        ["Lash of Pain"] = { "WARLOCK", "Succubus: Seduction is coming", "Kill or CC the Succubus; WotF, Fear Ward and Tremor break Seduction." },
        ["Bite"] = { "HUNTER", "Hunter pet doing real damage", "CC or kill the pet (Fear, Polymorph, Hibernate, Scare Beast), or stun the hunter." },
        ["Claw"] = { "HUNTER", "Hunter pet doing real damage", "CC or kill the pet, or stun the hunter to stop Mend Pet." },
        ["Lightning Breath"] = { "HUNTER", "Wind serpent pet", "CC the pet; it's ranged, so LoS it too." },
        ["Scorpid Poison"] = { "HUNTER", "Scorpid pet poison", "Cure Poison{D| or Stoneform|}; CC the pet." },
        ["Dismember"] = { "HUNTER", "Crocolisk pet: -50% healing on you", "Kill or CC the pet before healing." },
        ["Savage Rend"] = { "HUNTER", "Raptor pet bleed", "{D|Stoneform clears it; CC|It can't be dispelled; CC} the pet." },
        ["Tendon Rip"] = { "HUNTER", "Hyena pet snare", "Remove the snare and CC the pet." },
        ["Searing Totem"] = { "SHAMAN", "Searing Totem shooting you", "Kill the totem: one hit." },
    },
}
