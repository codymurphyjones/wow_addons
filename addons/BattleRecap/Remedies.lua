local _, ns = ...

-- "What you could have done": damage in a recap that YOUR class (or race) has an answer to. A
-- Serpent Sting doing real damage to a Druid means Cure Poison; a Fireball that went through a
-- Shaman means Earth Shock; a Fear before the kill on a Forsaken means Will of the Forsaken.
-- WoW Forever / Classic Era abilities, with the level each is learned at (an answer you don't have
-- yet says so). Only damage is in a recap, so a Fear shows as a pause in the damage.
local R = {}
ns.Remedies = R

local MIN_PCT = 10     -- a kind of damage worth a note: at least this share of what you took
local GAP = 4          -- seconds with no damage before a hit: crowd control (Fear, stun)

-- What each enemy spell is, for what can answer it.
local KIND = {
    -- poisons
    ["Serpent Sting"] = "poison", ["Deadly Poison"] = "poison", ["Instant Poison"] = "poison",
    ["Wound Poison"] = "poison", ["Scorpid Poison"] = "poison",
    -- diseases
    ["Devouring Plague"] = "disease",
    -- magic you can dispel
    ["Corruption"] = "magic", ["Immolate"] = "magic", ["Siphon Life"] = "magic", ["Shadow Word: Pain"] = "magic",
    ["Moonfire"] = "magic", ["Insect Swarm"] = "magic", ["Flame Shock"] = "magic", ["Holy Fire"] = "magic",
    -- curses
    ["Bane of Agony"] = "curse", ["Curse of Agony"] = "curse", ["Bane of Doom"] = "curse", ["Curse of Doom"] = "curse",
    -- bleeds
    ["Rend"] = "bleed", ["Deep Wounds"] = "bleed", ["Garrote"] = "bleed", ["Rupture"] = "bleed", ["Rake"] = "bleed",
    ["Rip"] = "bleed", ["Pounce Bleed"] = "bleed", ["Lacerate"] = "bleed", ["Savage Rend"] = "bleed",
    -- casts and channels you can interrupt
    ["Fireball"] = "cast", ["Frostbolt"] = "cast", ["Pyroblast"] = "cast", ["Frostfire Bolt"] = "cast",
    ["Arcane Blast"] = "cast", ["Arcane Missiles"] = "cast", ["Scorch"] = "cast", ["Shadow Bolt"] = "cast",
    ["Soul Fire"] = "cast", ["Searing Pain"] = "cast", ["Drain Life"] = "cast", ["Drain Soul"] = "cast",
    ["Incinerate"] = "cast", ["Mind Blast"] = "cast", ["Mind Flay"] = "cast", ["Smite"] = "cast", ["Penance"] = "cast",
    ["Lightning Bolt"] = "cast", ["Chain Lightning"] = "cast", ["Lava Burst"] = "cast", ["Wrath"] = "cast",
    ["Starfire"] = "cast", ["Hammer of Wrath"] = "cast",
}

-- Spells that slow or root you: the damage after them was damage you couldn't walk away from.
local SNARE = {
    ["Hamstring"] = "snare", ["Frostbolt"] = "snare", ["Frost Shock"] = "snare", ["Wing Clip"] = "snare",
    ["Cone of Cold"] = "snare", ["Mind Flay"] = "snare", ["Frostfire Bolt"] = "snare", ["Tendon Rip"] = "snare",
    ["Frost Nova"] = "root", ["Entangling Roots"] = "root", ["Chastise"] = "root",
}

-- Classes whose pause before damage is most likely a Fear.
local FEARS = { WARLOCK = true, PRIEST = true }

-- How each kind is described, and what an answer to it does.
local WHAT = {
    poison = { "poison", "would have removed it" },
    disease = { "disease", "would have removed it" },
    magic = { "magic damage over time", "would have dispelled it" },
    curse = { "curse", "would have removed it" },
    bleed = { "bleed", "would have removed it" },
    cast = { "cast damage", "would have interrupted it" },
    snare = { "slowed", "would have freed you" },
    root = { "rooted", "would have freed you" },
    fear = { "feared", "would have stopped the Fear" },
    shadow = { "Shadow damage", "would have cut it" },
    fire = { "Fire damage", "would have cut it" },
    frost = { "Frost damage", "would have cut it" },
    nature = { "Nature damage", "would have cut it" },
}

-- Your answers: [class][kind] = { { ability, level learned (0: any), note } }.
local ANSWERS = {
    DRUID = {
        poison = { { "Cure Poison", 14 }, { "Abolish Poison", 26 } },
        curse = { { "Remove Curse", 24 } },
        snare = { { "shifting into Bear or Cat Form", 10 } },
        root = { { "shifting into Bear or Cat Form", 10 } },
        cast = { { "Bash", 14, "in Bear Form" }, { "Feral Charge", 20, "a talent" } },
    },
    PRIEST = {
        magic = { { "Dispel Magic", 18 } },
        disease = { { "Cure Disease", 14 }, { "Abolish Disease", 32 } },
        fear = { { "Fear Ward", 20, "cast before the fight" } },
        cast = { { "Silence", 0, "a Shadow talent" }, { "Psychic Scream", 14, "in melee range" } },
        shadow = { { "Shadow Protection", 30 } },
    },
    PALADIN = {
        poison = { { "Purify", 8 }, { "Cleanse", 42 } },
        disease = { { "Purify", 8 }, { "Cleanse", 42 } },
        magic = { { "Cleanse", 42 } },
        snare = { { "Blessing of Freedom", 18 } },
        root = { { "Blessing of Freedom", 18 } },
        cast = { { "Hammer of Justice", 8 } },
        fear = { { "Divine Shield", 34 } },
        shadow = { { "Shadow Resistance Aura", 28 } },
        frost = { { "Frost Resistance Aura", 32 } },
        fire = { { "Fire Resistance Aura", 36 } },
    },
    SHAMAN = {
        poison = { { "Cure Poison", 16 }, { "Poison Cleansing Totem", 22 } },
        disease = { { "Cure Disease", 22 }, { "Disease Cleansing Totem", 38 } },
        cast = { { "Earth Shock", 4 } },
        fear = { { "Tremor Totem", 18, "down before the Fear" } },
        frost = { { "Frost Resistance Totem", 24 } },
        fire = { { "Fire Resistance Totem", 28 } },
        nature = { { "Nature Resistance Totem", 30 } },
    },
    MAGE = {
        curse = { { "Remove Lesser Curse", 18 } },
        cast = { { "Counterspell", 24 } },
        root = { { "Blink", 20 } },
        fire = { { "Fire Ward", 20 } },
        frost = { { "Frost Ward", 22 } },
    },
    WARLOCK = {
        magic = { { "your Felhunter's Devour Magic", 30 } },
        cast = { { "your Felhunter's Spell Lock", 30 } },
        shadow = { { "Shadow Ward", 32 } },
    },
    ROGUE = {
        cast = { { "Kick", 12 } },
        snare = { { "Vanish", 22 } },
        root = { { "Vanish", 22 } },
    },
    WARRIOR = {
        cast = { { "Shield Bash", 12, "with a shield" }, { "Pummel", 38 } },
        fear = { { "Berserker Rage", 32, "before the Fear" } },
    },
    HUNTER = {
        nature = { { "Aspect of the Wild", 46 } },
    },
}

-- Racial answers (UnitRace's file name).
local RACIAL = {
    Dwarf = { poison = "Stoneform", disease = "Stoneform", bleed = "Stoneform" },
    Scourge = { fear = "Will of the Forsaken" },
    Gnome = { snare = "Escape Artist", root = "Escape Artist" },
    Tauren = { cast = "War Stomp" },
}

local RACE_NAMES = { Dwarf = "Dwarf", Scourge = "Forsaken", Gnome = "Gnome", Tauren = "Tauren" }

-- For anyone, whatever your class: items, and what works in general.
local GENERAL = {
    poison = "Anyone: Anti-Venom (First Aid) or an Elixir of Poison Resistance.",
    disease = "Anyone: a Restorative Potion clears it.",
    magic = "Anyone: a Restorative Potion removes one magic effect every 5s; kill the caster before the DoTs stack.",
    curse = "Anyone: a Restorative Potion removes it; the curse keeps ticking, so don't drag the fight out.",
    bleed = "Bleeds can't be dispelled: bandage once they end, or kill the source.",
    cast = "Anyone: break line of sight before the cast ends, or close in so they have to move.",
    snare = "Anyone: a Free Action Potion (20) or the PvP trinket; don't fight in the open when slowed.",
    root = "Anyone: a Free Action Potion (20) or the PvP trinket; fight near cover so roots don't leave you exposed.",
    fear = "Anyone: the PvP trinket breaks a Fear.",
    shadow = "Anyone: shadow resistance gear or a Shadow Protection Potion.",
    fire = "Anyone: fire resistance gear or a Fire Protection Potion.",
    frost = "Anyone: frost resistance gear or a Frost Protection Potion.",
    nature = "Anyone: nature resistance gear or a Nature Protection Potion.",
}

-- Teammates who can do it for you: [kind] = { classes, what they do }.
local TEAM = {
    poison = { { "DRUID", "PALADIN", "SHAMAN" }, "can cure it for you" },
    disease = { { "PRIEST", "PALADIN", "SHAMAN" }, "can cure it for you" },
    magic = { { "PRIEST", "PALADIN" }, "can dispel it from you" },
    curse = { { "MAGE", "DRUID" }, "can remove it from you" },
    snare = { { "PALADIN" }, "can free you with Blessing of Freedom" },
    root = { { "PALADIN" }, "can free you with Blessing of Freedom" },
    fear = { { "PRIEST", "SHAMAN" }, "can stop it (Fear Ward, Tremor Totem)" },
    shadow = { { "PRIEST", "PALADIN" }, "can buff or aura you against it" },
    fire = { { "PALADIN", "SHAMAN" }, "can aura or totem you against it" },
    frost = { { "PALADIN", "SHAMAN" }, "can aura or totem you against it" },
    nature = { { "SHAMAN", "HUNTER" }, "can totem or aspect you against it" },
}

local function ClassWord(class) return ns.ClassName(class) or (class:sub(1, 1) .. class:sub(2):lower()) end

local SCHOOL_KIND = { [32] = "shadow", [4] = "fire", [16] = "frost", [8] = "nature" }
local RESIST = { shadow = true, fire = true, frost = true, nature = true }

local function Answers(recap, kind)
    local out = {}
    local level = recap.level
    for _, a in ipairs(ANSWERS[recap.class or ""] and ANSWERS[recap.class][kind] or {}) do
        local name, learned, note = a[1], a[2], a[3]
        local text = name
        if note then text = text .. " (" .. note .. ")" end
        if learned > 0 and level and level < learned then text = text .. (" |cff8899aa(at %d)|r"):format(learned) end
        out[#out + 1] = { text = text, have = not (learned > 0 and level and level < learned) }
    end
    local racial = RACIAL[recap.race or ""] and RACIAL[recap.race][kind]
    if racial then out[#out + 1] = { text = racial, have = true, racial = true } end
    -- Learned ones first, otherwise in order (class answers before racials).
    for i, a in ipairs(out) do a.order = i end
    table.sort(out, function(a, b)
        if a.have ~= b.have then return a.have end
        return a.order < b.order
    end)
    return out
end

local function Join(list)
    if #list == 1 then return list[1] end
    return table.concat(list, ", ", 1, #list - 1) .. " or " .. list[#list]
end

-- The notes, most damage first: { kind, damage, pct, spells = { names }, text }.
function R.Analyze(recap)
    local out = {}
    if not recap or not recap.class then return out end
    local total = (recap.totals and recap.totals.damage or 0) + (recap.earlier and recap.earlier.damage or 0)
    if total <= 0 then return out end
    local buckets, order = {}, {}
    local function Bucket(kind)
        local b = buckets[kind]
        if not b then
            b = { kind = kind, damage = 0, spells = {}, seen = {}, ticks = 0 }
            buckets[kind] = b
            order[#order + 1] = b
        end
        return b
    end
    local function AddSpell(kind, s)
        local b = Bucket(kind)
        b.damage = b.damage + (s.total or 0)
        b.ticks = b.ticks + (s.hits or 0)
        if not b.seen[s.name] then b.seen[s.name] = true; b.spells[#b.spells + 1] = s.name end
    end

    -- Poisons, diseases, magic, curses, bleeds and casts, by spell.
    local function Scan(attackers)
        for _, a in ipairs(attackers or {}) do
            if not a.env then
                for _, s in ipairs(a.spellList or {}) do
                    local kind = KIND[s.name]
                    if kind then AddSpell(kind, s) end
                end
            end
        end
    end
    Scan(recap.attackers)
    if recap.earlier then Scan(recap.earlier.attackers) end

    -- Resistances: one school doing most of the damage.
    for _, s in ipairs(recap.schools or {}) do
        local kind = SCHOOL_KIND[s.school]
        if kind and (s.pct or 0) >= 50 then
            local b = Bucket(kind)
            b.damage = s.total
        end
    end

    -- From the timeline: what hit you while slowed or rooted, and after a Fear.
    if not recap.totalsOnly then
        local events = recap.events or {}
        local slowedBy = {}
        local prev
        local fearer, fearEnd
        for _, e in ipairs(events) do
            if e.kind == "dmg" and not e.env then
                local kind = SNARE[e.spell]
                if kind and not slowedBy[e.src] then
                    slowedBy[e.src] = kind
                    local b = Bucket(kind)
                    if not b.seen[e.spell] then b.seen[e.spell] = true; b.spells[#b.spells + 1] = e.spell end
                elseif slowedBy[e.src] then
                    local b = Bucket(slowedBy[e.src])
                    b.damage = b.damage + (e.amount or 0)
                end
                if prev and e.rel - prev.rel >= GAP and FEARS[e.srcClass] then
                    fearer, fearEnd = e.src, e.rel + 6
                    local b = Bucket("fear")
                    if not b.seen[e.src] then b.seen[e.src] = true; b.spells[#b.spells + 1] = e.src end
                end
                if fearer and e.rel <= fearEnd then
                    Bucket("fear").damage = Bucket("fear").damage + (e.amount or 0)
                end
                prev = e
            end
        end
    end

    local you = ClassWord(recap.class)
    for _, b in ipairs(order) do
        b.pct = b.damage / total * 100
        if b.pct >= MIN_PCT then
            local answers = Answers(recap, b.kind)
            local list = {}
            for i, a in ipairs(answers) do if i <= 2 then list[i] = a.text end end
            local fix
            if #list > 0 then
                local as = answers[1].racial and RACE_NAMES[recap.race] or you
                fix = ("As a %s, %s %s."):format(as, Join(list), WHAT[b.kind][2])
            end
            -- What works whatever your class: teammates, items, play.
            local general = {}
            local team = TEAM[b.kind]
            if team then
                local who = {}
                for _, class in ipairs(team[1]) do
                    if class ~= recap.class then who[#who + 1] = ClassWord(class) end
                end
                if #who > 0 then general[#general + 1] = ("A %s teammate %s."):format(Join(who), team[2]) end
            end
            if GENERAL[b.kind] then general[#general + 1] = GENERAL[b.kind] end
            general = #general > 0 and table.concat(general, " ") or nil
            if fix or general then
                local what
                if b.kind == "fear" then
                    what = ("Feared by %s: %s damage in the 6s after"):format(Join(b.spells), ns.Num(b.damage))
                elseif b.kind == "snare" or b.kind == "root" then
                    what = ("%s by %s: %s damage while you couldn't get away"):format(
                        b.kind == "root" and "Rooted" or "Slowed", Join(b.spells), ns.Num(b.damage))
                elseif RESIST[b.kind] then
                    what = ("%d%% of your damage taken was %s"):format(b.pct + 0.5, WHAT[b.kind][1])
                else
                    what = ("%s (%s) did %s%s"):format(Join(b.spells), WHAT[b.kind][1], ns.Num(b.damage),
                        (b.ticks > 1 and b.kind ~= "cast") and (" over %d ticks"):format(b.ticks) or "")
                end
                out[#out + 1] = { kind = b.kind, damage = b.damage, pct = b.pct, spells = b.spells, what = what, fix = fix,
                    general = general, text = what .. "." .. (fix and (" " .. fix) or "") .. (general and (" " .. general) or "") }
            end
        end
    end
    table.sort(out, function(a, b) return a.damage > b.damage end)
    return out
end
