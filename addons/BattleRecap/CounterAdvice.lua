local _, ns = ...

-- The class-wide advice in the counter notes, tied to evidence: every line names what in the fight
-- makes it relevant, and is only shown when that happened. A line about Aimed Shot only appears if
-- an Aimed Shot hit you.
--
-- general = { { text, trigger, ... } }: advice against that class, whatever yours is.
-- vs[YOUR_CLASS] = { { clause, trigger, ... } }: how your class beats them; the clauses that apply
--   are joined into one line.
-- Triggers: an enemy spell name that hit you, or
--   "MELEE" their weapon swings ("Melee"), "PET" their pet or totem hit you,
--   "GAP" their damage came after a pause of a few seconds (a stun, Fear, Polymorph or trap).

local C = ns.COUNTER_DATA.classes

-- Racial (and self-only class) answers are only advice for that race or class: such wording in
-- this data is marked {Who|what they read|what everyone else reads} (the second part may be empty),
-- Who being a race (UnitRace's file name: Dwarf, Gnome, Scourge, Human...; D = Dwarf) or a class
-- (DRUID, MAGE...). Stoneform for Dwarves, Escape Artist for Gnomes, shapeshifting for druids. Help a
-- teammate can give (Freedom, Fear Ward, Tremor Totem) stays for everyone. The marks are resolved
-- for you the first time the counter notes read the data (Counter.lua).
local resolved = false
function ns.ResolveRacialAdvice()
    if resolved then return end
    resolved = true
    local _, race = UnitRace("player")
    local _, class = UnitClass("player")
    local function Mine(who) return who == race or who == class or (who == "D" and race == "Dwarf") end
    local seen = {}
    local function Walk(t)
        seen[t] = true
        for k, v in pairs(t) do
            if type(v) == "string" and v:find("{%a+|") then
                t[k] = v:gsub("{(%a+)|([^|}]*)|?([^}]*)}", function(who, mine, other) return Mine(who) and mine or other end)
            elseif type(v) == "table" and not seen[v] then
                Walk(v)
            end
        end
    end
    Walk(ns.COUNTER_DATA)
end

C.WARRIOR.general = {
    { "Hamstring kept you in reach: remove it (Freedom, a Free Action Potion{Gnome|, Escape Artist|}{DRUID|, shapeshift|}) and get past 8 yd before the next one.", "Hamstring" },
    { "Below 30 their only gap closers are Charge (out of combat) and Intercept (at 30, 30s cooldown): after an Intercept, kite hard.", "Intercept" },
    { "Heroic Strike, Slam and Cleave are rage dumps: every second in melee feeds them. Snare, root or Fear them and leave.", "Heroic Strike", "Slam", "Cleave" },
    { "Execute and Mortal Strike punish healing late: CC or break range at 25% instead of healing into them.", "Execute", "Mortal Strike" },
    { "Overpower comes from your dodges (and Rend procs in Forever): don't Evasion or dodge-tank a Battle Stance warrior.", "Overpower" },
    { "Rend and Deep Wounds are bleeds{D|: Stoneform clears them|: nothing dispels them}, so get out of melee before they're refreshed.", "Rend", "Deep Wounds" },
    { "Whirlwind has a 10s cooldown: spread out from allies, and kite right after it.", "Whirlwind" },
    { "Victory Rush healed them 10% after a kill: finish them inside its 20s window, before they use it.", "Victory Rush" },
    { "Bloodthirst gives them +10% speed in Forever: root or Fear them instead of relying on a snare.", "Bloodthirst" },
}
C.WARRIOR.vs = {
    WARRIOR = { { "answer their Hamstring with yours", "Hamstring" }, { "Disarm them when Mortal Strike or Overpower start landing", "Mortal Strike", "Overpower" }, { "save rage for your Execute, not theirs", "Execute" } },
    ROGUE = { { "Crippling Poison and Gouge to get out of their Hamstring range", "Hamstring", "MELEE" }, { "skip Evasion: it feeds their Overpower", "Overpower" } },
    MAGE = { { "Blink out of Hamstring, then Frost Nova and kite with Frostbolt", "Hamstring" }, { "Frost Nova and step away the moment they're in melee", "MELEE" }, { "Ice Block (Frost, 25) when Execute range comes", "Execute", "Mortal Strike" } },
    HUNTER = { { "Wing Clip and Concussive Shot, then stay past 8 yd", "MELEE", "Hamstring" }, { "Freezing Trap works in combat now: drop it between you", "MELEE" } },
    WARLOCK = { { "Fear them (no Berserker Rage below 32) and DoT while they run", "MELEE", "Hamstring" }, { "Curse of Exhaustion (25) once Hamstring is off you", "Hamstring" } },
    PRIEST = { { "Psychic Scream as soon as they're in melee, then Mind Blast and DoTs", "MELEE" }, { "Shield doesn't starve their rage in Forever: don't stand and soak", "Heroic Strike", "Slam", "Cleave" } },
    DRUID = { { "Travel or Cat Form breaks Hamstring", "Hamstring" }, { "Entangling Roots and Moonfire to kite once they're on you", "MELEE" } },
    SHAMAN = { { "Ghost Wolf out of Hamstring, then Frost Shock and Earthbind", "Hamstring" }, { "Earth Shock or Frost Shock before Execute range", "Execute" } },
    PALADIN = { { "Blessing of Freedom their Hamstring", "Hamstring" }, { "Hammer of Justice into their burst", "Mortal Strike", "Overpower", "MELEE" }, { "Divine Protection at Execute range", "Execute" } },
}

C.ROGUE.general = {
    { "The pause before the Eviscerate was a stun (Cheap Shot, Kidney Shot at 30): trinket or Free Action the second stun, not the first.", "GAP" },
    { "Ambush and Garrote are openers from stealth: move, stay near allies, and use {Human|Perception or AoE|AoE} when a rogue is about.", "Ambush", "Garrote" },
    { "Backstab needs your back: turn to face them and strafe; a wall behind you takes it away.", "Backstab" },
    { "Sinister Strike and Eviscerate are physical: armor, Bear Form, Divine Protection or Ice Block blunt the burst.", "Sinister Strike", "Eviscerate" },
    { "Their poisons can be cleansed (Cure/Abolish Poison, Cleansing Totem{D|, Stoneform|}): Crippling Poison is what stops you escaping.", "Instant Poison", "Deadly Poison", "Wound Poison" },
    { "Mutilate hits harder on poisoned targets: cleanse poisons first.", "Mutilate" },
    { "Rupture and Garrote are bleeds{D|: Stoneform clears them|: nothing dispels them}; heal through and CC the rogue.", "Rupture", "Garrote" },
    { "Sap no longer breaks their stealth in Forever: if you were sapped, expect the opener from a rogue you never saw.", "Ambush", "Garrote" },
}
C.ROGUE.vs = {
    WARRIOR = { { "Hamstring them the moment their opener or stun ends, so they can't stay behind you", "GAP", "MELEE", "Sinister Strike", "Backstab", "Eviscerate" }, { "Intimidating Shout their Evasion", "Riposte" } },
    ROGUE = { { "Gouge their finisher and Vanish their Kidney Shot", "Eviscerate", "GAP" }, { "open first: whoever lands Cheap Shot wins", "Ambush", "Garrote" } },
    MAGE = { { "Frost Nova as the stun ends, Blink, then Polymorph and kite", "GAP", "Eviscerate" }, { "Ice Block (25) the Kidney Shot", "GAP" }, { "Frost Armor up so their swings slow them", "MELEE", "Sinister Strike", "Backstab" } },
    HUNTER = { { "Freezing Trap works in combat now: trap at your feet once the stun ends", "GAP" }, { "Wing Clip and step past 8 yd", "MELEE", "Sinister Strike", "Backstab" } },
    WARLOCK = { { "Fear as the stun breaks, then DoTs", "GAP" }, { "Voidwalker Sacrifice to shield the Eviscerate", "Eviscerate" } },
    PRIEST = { { "Shield first, Psychic Scream as the stun ends", "GAP", "Eviscerate" }, { "you can't cure poison yourself: {D|Stoneform it|Anti-Venom, or a druid, paladin or shaman can}", "Instant Poison", "Deadly Poison", "Wound Poison" } },
    DRUID = { { "Bear Form through the stun chain", "GAP", "Eviscerate" }, { "Abolish Poison (26) their poisons", "Instant Poison", "Deadly Poison", "Wound Poison" }, { "shift to break Crippling Poison", "MELEE" } },
    SHAMAN = { { "Poison Cleansing Totem (22) down early", "Instant Poison", "Deadly Poison", "Wound Poison", "Mutilate" }, { "Frost Shock and Earthbind as the stun ends", "GAP" } },
    PALADIN = { { "Divine Protection the Eviscerate", "Eviscerate" }, { "Hammer of Justice back once their stun ends", "GAP" }, { "Purify their poisons", "Instant Poison", "Deadly Poison", "Wound Poison" } },
}

C.MAGE.general = {
    { "Fireball and Frostbolt are casts: line of sight or an interrupt (Kick, Shield Bash, Earth Shock, Counterspell) denies them.", "Fireball", "Frostbolt", "Frostfire Bolt" },
    { "Pyroblast opened on you from range: close behind cover when a mage targets you out of combat.", "Pyroblast" },
    { "Frost Nova then a big hit is Shatter: break the root at once (trinket, Freedom{Gnome|, Escape Artist|}{DRUID|, shapeshift|}).", "Frost Nova" },
    { "Ice Lance triples on frozen targets in Forever: never stand rooted near a Frost mage.", "Ice Lance" },
    { "Arcane Blast hits harder each cast within 8s: interrupt or LoS by the second cast.", "Arcane Blast" },
    { "Their damage stopped for a while: that was Polymorph or Frost Nova. A trinket{DRUID| or shapeshift|} breaks Polymorph{Scourge|; Will of the Forsaken doesn't|}.", "GAP" },
    { "Cone of Cold and Arcane Explosion mean the mage was in melee range with no escape left: stay on them.", "Cone of Cold", "Arcane Explosion" },
    { "Fire Blast is their instant finisher (20 yd): kill them before they get you to that range.", "Fire Blast" },
}
C.MAGE.vs = {
    WARRIOR = { { "LoS their Frostbolt with pillars and save Intercept (30) for after their Blink", "Frostbolt", "Frost Nova" }, { "don't chase into Frost Nova", "Frost Nova" } },
    ROGUE = { { "Kick their Polymorph or Frostbolt", "Frostbolt", "Fireball", "GAP" }, { "Kidney once Blink and Nova are down", "Frost Nova" } },
    MAGE = { { "Counterspell their Polymorph or big cast first", "Fireball", "Frostbolt", "Pyroblast", "GAP" }, { "land your Nova first: Frost vs Frost is whoever Shatters first", "Frost Nova" } },
    HUNTER = { { "fight from 30-41 yd with your pet on them to push back casts", "Fireball", "Frostbolt", "Pyroblast" }, { "Concussive Shot after their Blink", "Frost Nova", "Cone of Cold" } },
    WARLOCK = { { "Curse of Tongues (26) slows their casts", "Fireball", "Frostbolt", "Pyroblast" }, { "Felhunter Spell Lock their Polymorph", "GAP" } },
    PRIEST = { { "Shield before their Shatter", "Frost Nova" }, { "Psychic Scream when they Blink in close", "Cone of Cold", "Arcane Explosion" }, { "Mana Burn in long fights", "Frostbolt", "Fireball" } },
    DRUID = { { "shift out of Polymorph and roots at once", "GAP", "Frost Nova" }, { "Feral Charge (20) to stick to them", "Frostbolt", "Fireball" } },
    SHAMAN = { { "Earth Shock their casts", "Fireball", "Frostbolt", "Pyroblast" }, { "Grounding Totem (30) eats a Polymorph or Pyroblast", "GAP", "Pyroblast" } },
    PALADIN = { { "Blessing of Freedom their Nova and Frostbolt slow", "Frost Nova", "Frostbolt" }, { "Hammer of Justice their cast", "Fireball", "Pyroblast" } },
}

C.HUNTER.general = {
    { "Aimed Shot is a 3s cast (baseline at 20 in Forever): LoS it or get inside 8 yd while it casts.", "Aimed Shot" },
    { "Auto Shot did real damage: close through cover into the 5-8 yd dead zone, where they can't shoot or melee well.", "Auto Shot" },
    { "Their damage resumed after a pause: Freezing Trap or Scatter Shot. Traps work in combat in Forever (30s cooldown).", "GAP", "Scatter Shot" },
    { "Their pet did a lot of it: CC or kill the pet (Fear, Polymorph, Hibernate, Scare Beast), or stun the hunter to stop Mend Pet.", "PET" },
    { "Serpent Sting is a poison: cure it{D|, or Stoneform|}.", "Serpent Sting" },
    { "Raptor Strike and Mongoose Bite mean you fought a Survival hunter in melee: take range instead.", "Raptor Strike", "Mongoose Bite", "Strider Kick" },
    { "Multi-Shot shares Aimed Shot's cooldown in Forever: after one, push in.", "Multi-Shot" },
}
C.HUNTER.vs = {
    WARRIOR = { { "Charge in and stay glued; Intercept (30) when they Disengage", "Auto Shot", "Aimed Shot", "Arcane Shot" }, { "trinket their trap", "GAP" } },
    ROGUE = { { "keep them in melee, in their dead zone", "Auto Shot", "Aimed Shot", "Arcane Shot" }, { "Vanish (22) to drop Hunter's Mark and re-open", "Arcane Shot", "Serpent Sting" } },
    MAGE = { { "fight from behind cover so they must come around it, then Frost Nova and Blink to reset range", "Auto Shot", "Arcane Shot", "Aimed Shot" }, { "Polymorph or Nova the pet", "PET" }, { "Nova them in melee and Blink to 20 yd", "Raptor Strike", "Mongoose Bite", "Wing Clip" }, { "LoS their Aimed Shot", "Aimed Shot" } },
    HUNTER = { { "Scare Beast their pet first", "PET" }, { "out-range their Aimed Shot from behind cover", "Aimed Shot", "Auto Shot" } },
    WARLOCK = { { "Felhunter or Voidwalker on their pet", "PET" }, { "Fear the hunter and stack DoTs", "Auto Shot", "Aimed Shot", "Arcane Shot" } },
    PRIEST = { { "Psychic Scream hits the pet too", "PET" }, { "Shield their Aimed Shot", "Aimed Shot" } },
    DRUID = { { "Bear Form soaks their shots", "Auto Shot", "Aimed Shot", "Arcane Shot" }, { "Hibernate the pet", "PET" }, { "Abolish Poison their stings", "Serpent Sting" } },
    SHAMAN = { { "Earthbind or Frost Shock the pet", "PET" }, { "Poison Cleansing Totem their stings", "Serpent Sting" } },
    PALADIN = { { "Purify their stings", "Serpent Sting" }, { "Freedom their Wing Clip, then Hammer of Justice", "Wing Clip" } },
}

C.WARLOCK.general = {
    { "Their damage resumed after a pause: Fear. {Scourge|Will of the Forsaken, |}Fear Ward (every priest at 20), Tremor Totem or a trinket stop it.", "GAP" },
    { "Corruption, Immolate and Siphon Life are magic DoTs: dispel them early, before Conflagrate or the stacks add up.", "Corruption", "Immolate", "Siphon Life" },
    { "Their curse (Bane of Agony in Forever) can be removed by a mage or druid.", "Bane of Agony", "Curse of Agony", "Bane of Doom" },
    { "Shadow Bolt and Soul Fire are long casts: interrupt them or LoS.", "Shadow Bolt", "Soul Fire" },
    { "Drain Life is a 20 yd channel: break range or LoS and it stops healing them.", "Drain Life", "Drain Soul" },
    { "Shadowburn is their execute: heal or shield before 30% against a Destruction warlock.", "Shadowburn" },
    { "Conflagrate needs Immolate on you: dispel Immolate and it can't happen.", "Conflagrate" },
    { "Their pet did real damage: Succubus means Seduction is coming; the Imp is fragile.", "PET" },
}
C.WARLOCK.vs = {
    WARRIOR = { { "trinket the Fear (no Berserker Rage below 32)", "GAP" }, { "Charge or Intercept and Hamstring before the DoTs stack", "Corruption", "Immolate", "Bane of Agony", "Curse of Agony" } },
    ROGUE = { { "Kick the Fear or Shadow Bolt", "GAP", "Shadow Bolt" }, { "Vanish drops Fear's target but not the DoTs", "Corruption", "Immolate" } },
    MAGE = { { "Counterspell the Fear", "GAP" }, { "Remove Lesser Curse their curse", "Bane of Agony", "Curse of Agony", "Bane of Doom" }, { "Polymorph the Succubus", "PET" } },
    HUNTER = { { "Scatter Shot their Fear cast", "GAP" }, { "let your pet interrupt their Shadow Bolts", "Shadow Bolt", "Soul Fire" } },
    WARLOCK = { { "Felhunter Spell Lock their Fear", "GAP" }, { "Devour Magic their DoTs off you", "Corruption", "Immolate", "Siphon Life" } },
    PRIEST = { { "Fear Ward (20) before they Fear", "GAP" }, { "Dispel Magic their DoTs", "Corruption", "Immolate", "Siphon Life" } },
    DRUID = { { "Bash the Fear cast; shifting doesn't break Fear", "GAP" }, { "Remove Curse (24) their curse", "Bane of Agony", "Curse of Agony", "Bane of Doom" } },
    SHAMAN = { { "Tremor Totem (18) down before the Fear", "GAP" }, { "Earth Shock their Shadow Bolt", "Shadow Bolt", "Soul Fire" } },
    PALADIN = { { "Cleanse or Purify what you can, Hammer of Justice the cast", "Shadow Bolt", "Corruption", "Immolate" }, { "Divine Shield (34) breaks Fear", "GAP" } },
}

C.PRIEST.general = {
    { "Mind Blast is on an 8s cooldown: after one lands, that's your window to close in or LoS.", "Mind Blast" },
    { "Shadow Word: Pain is magic: dispel it. Random stuns from shadow spells are Blackout procs.", "Shadow Word: Pain" },
    { "Mind Flay is a slowing channel: interrupt it, break LoS, or leave its range.", "Mind Flay" },
    { "Devouring Plague is a disease that heals them: Cure Disease{D|, Stoneform|} or a Disease Cleansing Totem.", "Devouring Plague" },
    { "Their damage resumed after a pause: Psychic Scream, Silence or Mind Control. Fear Ward{Scourge|, Will of the Forsaken|} or Tremor Totem beat Scream.", "GAP" },
    { "Holy Fire and Smite are casts from a healer: interrupt them and they run out of mana first.", "Holy Fire", "Smite" },
    { "Mana Burn drained you: close in and interrupt, or stay past 30 yd.", "Mana Burn" },
}
C.PRIEST.vs = {
    WARRIOR = { { "trinket the Scream (no Berserker Rage below 32)", "GAP" }, { "Shield Bash their Mind Blast", "Mind Blast" } },
    ROGUE = { { "Kick the Mind Blast", "Mind Blast" }, { "save Kidney for after their Scream", "GAP" } },
    MAGE = { { "Counterspell their Mind Blast", "Mind Blast" }, { "kite outside Scream range (8 yd)", "GAP" } },
    HUNTER = { { "Scatter Shot when they move in to Scream", "GAP" }, { "pet on them to push back Mind Blast", "Mind Blast" } },
    WARLOCK = { { "Curse of Tongues (26) slows their casts", "Mind Blast", "Mind Flay", "Smite", "Holy Fire" }, { "bait Fear Ward before you Fear", "GAP" } },
    PRIEST = { { "Dispel their Shadow Word: Pain", "Shadow Word: Pain" }, { "Silence or Scream their heal", "Mind Blast", "Smite" } },
    DRUID = { { "shift out of Mind Flay's slow", "Mind Flay" }, { "Bash their cast in Bear Form", "Mind Blast", "Smite", "Holy Fire" } },
    SHAMAN = { { "Tremor Totem before the Scream", "GAP" }, { "Earth Shock their Mind Blast", "Mind Blast" }, { "Disease Cleansing Totem (38) or Cure Disease their Plague", "Devouring Plague" } },
    PALADIN = { { "Cleanse or Purify their DoTs and Plague", "Shadow Word: Pain", "Devouring Plague" }, { "Hammer of Justice their cast", "Mind Blast", "Smite", "Holy Fire" } },
}

C.DRUID.general = {
    { "Ravage and Pounce are Prowl openers: face them with your back to a wall, and use {Human|Perception, |}Faerie Fire or AoE when one is about.", "Ravage", "Pounce", "Pounce Bleed" },
    { "Shred needs your back: turn to face the cat.", "Shred" },
    { "Rake and Rip are bleeds{D|: Stoneform clears them|: nothing dispels them}; CC the druid instead.", "Rake", "Rip", "Pounce Bleed" },
    { "Moonfire and Insect Swarm are magic: dispel them.", "Moonfire", "Insect Swarm" },
    { "Starfire and Wrath are casts: interrupt the Starfire, especially right after a Wrath.", "Starfire", "Wrath" },
    { "Ferocious Bite is their finisher: break away or CC before five combo points.", "Ferocious Bite" },
    { "Shapeshifting breaks snares and Polymorph: use stuns, Fear and interrupts on druids.", "Shred", "Claw", "Rake", "Maul" },
}
C.DRUID.vs = {
    WARRIOR = { { "Intimidating Shout or Intercept: they shift out of Hamstring", "Shred", "Claw", "Rake", "Maul" } },
    ROGUE = { { "Kick when they shift out to heal or cast", "Starfire", "Wrath", "Moonfire" }, { "face them so Shred and Ravage can't land", "Shred", "Ravage" } },
    MAGE = { { "Polymorph works on Cat and Bear", "Shred", "Claw", "Rake", "Maul" }, { "Counterspell their Starfire", "Starfire", "Wrath" } },
    HUNTER = { { "Freezing Trap the cat (works in combat)", "Shred", "Claw", "Rake" }, { "Concussive Shot when they Dash in", "Ravage", "Pounce" } },
    WARLOCK = { { "Fear them: shifting doesn't break it", "Shred", "Claw", "Rake", "Maul", "Starfire" } },
    PRIEST = { { "Psychic Scream the cat", "Shred", "Claw", "Rake" }, { "Dispel their Moonfire and Insect Swarm", "Moonfire", "Insect Swarm" } },
    DRUID = { { "Hibernate the feral", "Shred", "Claw", "Rake", "Maul" }, { "Bash their Starfire", "Starfire" } },
    SHAMAN = { { "Earth Shock their Starfire", "Starfire", "Wrath" }, { "Earthbind the cat (shifting breaks Frost Shock)", "Shred", "Claw", "Rake" } },
    PALADIN = { { "Hammer of Justice the cat", "Shred", "Claw", "Rake", "Ravage" }, { "Cleanse their Moonfire and Insect Swarm", "Moonfire", "Insect Swarm" } },
}

C.SHAMAN.general = {
    { "Stormstrike makes their next shock or bolt hit 20% harder: step out or LoS for a second after it.", "Stormstrike" },
    { "Earth Shock is their instant burst and interrupt: fake a cast to bait it.", "Earth Shock" },
    { "Lightning Bolt and Chain Lightning are casts and shamans can't Blink: interrupt or close in.", "Lightning Bolt", "Chain Lightning" },
    { "Flame Shock is magic: dispel it (it also cuts Lava Burst damage).", "Flame Shock", "Lava Burst" },
    { "Frost Shock slowed you: {DRUID|shapeshift, |}{Gnome|Escape Artist, |}Freedom or a Free Action Potion, and push in while their shocks are on cooldown.", "Frost Shock" },
    { "Their totems did damage: one hit kills a totem.", "PET", "Fire Nova", "Magma Totem" },
    { "Windfury procs make long melee a gamble: Disarm, Scream or Fear an Enhancement shaman.", "Windfury Attack", "MELEE" },
}
C.SHAMAN.vs = {
    WARRIOR = { { "Shield Bash their Lightning Bolt", "Lightning Bolt", "Chain Lightning" }, { "Disarm when Stormstrike starts", "Stormstrike", "Windfury Attack" } },
    ROGUE = { { "Kick their bolt (locks Nature)", "Lightning Bolt", "Chain Lightning" }, { "Kidney after their Earth Shock", "Earth Shock" } },
    MAGE = { { "Counterspell their Lightning Bolt", "Lightning Bolt", "Chain Lightning" }, { "kite with Frostbolt: they can't Blink", "Stormstrike", "MELEE" } },
    HUNTER = { { "keep range from Stormstrike and Windfury", "Stormstrike", "Windfury Attack", "MELEE" }, { "shoot their totems", "PET", "Fire Nova" } },
    WARLOCK = { { "DoTs they can't dispel from themselves", "Lightning Bolt", "Earth Shock", "Flame Shock" }, { "Felhunter Spell Lock their bolt", "Lightning Bolt", "Chain Lightning" } },
    PRIEST = { { "Shadow DoTs they can't dispel", "Lightning Bolt", "Earth Shock" }, { "Psychic Scream their melee", "Stormstrike", "Windfury Attack", "MELEE" } },
    DRUID = { { "Bear Form their Stormstrike burst", "Stormstrike", "Earth Shock" }, { "Roots and Moonfire against a casting shaman", "Lightning Bolt", "Chain Lightning" } },
    SHAMAN = { { "Earth Shock their bolt", "Lightning Bolt", "Chain Lightning" }, { "Grounding Totem eats their Earth Shock", "Earth Shock" } },
    PALADIN = { { "Cleanse their Flame and Frost Shock", "Flame Shock", "Frost Shock" }, { "Freedom their Frost Shock", "Frost Shock" }, { "Hammer of Justice their bolt", "Lightning Bolt" } },
}

C.PALADIN.general = {
    { "Seal of Command procs are their burst, biggest after Hammer of Justice: don't stay in melee around their stun.", "Seal of Command", "Judgement of Command" },
    { "Their damage resumed after a pause: Hammer of Justice. Trinket it, or pre-shield before their Judgement.", "GAP" },
    { "Righteousness is Holy damage: armor doesn't help, so kite rather than trade.", "Judgement of Righteousness", "Seal of Righteousness" },
    { "Exorcism only hits Undead: Forsaken, keep away from paladins.", "Exorcism" },
    { "Hammer of Wrath is their execute (below 20%): heal or LoS before it.", "Hammer of Wrath" },
    { "Consecration is ground damage: step out of it.", "Consecration" },
    { "Paladins have no gap closer: snare them and kite; they only shrug it off with Blessing of Freedom.", "MELEE", "Holy Strike", "Seal of Command" },
}
C.PALADIN.vs = {
    WARRIOR = { { "Disarm the 2H when Seal of Command procs start", "Seal of Command", "Judgement of Command" }, { "re-Hamstring after their Freedom ends", "MELEE" } },
    ROGUE = { { "save Kidney for after their Hammer of Justice", "GAP" }, { "wait out Divine Protection before your burst", "Seal of Command", "MELEE" } },
    MAGE = { { "kite at range: they have no gap closer", "MELEE", "Seal of Command", "Holy Strike" }, { "Blink out of their Hammer of Justice follow-up", "GAP" } },
    HUNTER = { { "Concussive Shot and range: they can't reach you", "MELEE", "Seal of Command", "Holy Strike" } },
    WARLOCK = { { "Fear and DoT, Curse of Tongues their heals", "MELEE", "Seal of Command", "Judgement of Righteousness" } },
    PRIEST = { { "Psychic Scream and stay out of melee", "MELEE", "Seal of Command" }, { "Shield before their Judgement", "GAP" } },
    DRUID = { { "Bear Form their Seal of Command burst", "Seal of Command", "Judgement of Command" }, { "Roots and Moonfire kite", "MELEE" } },
    SHAMAN = { { "Frost Shock kite", "MELEE", "Seal of Command" }, { "Grounding Totem eats a Hammer of Justice", "GAP" } },
    PALADIN = { { "Hammer of Justice their burst first", "Seal of Command", "MELEE" }, { "save Divine Shield for their Seal of Command", "Seal of Command" } },
}
