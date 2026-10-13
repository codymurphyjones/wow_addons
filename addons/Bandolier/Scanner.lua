local _, ns = ...

local S = {}
ns.Scanner = S

local NUM_BAGS = NUM_BAG_SLOTS or 4

-- Sort position of a category: every kind of buff (flask, elixir, scroll,
-- other buffs, enhancement potion) shares one, so buffs are ranked by your
-- stat priority across kinds, with the kind only breaking ties.
local function Bucket(entry)
    return ns.Data.IsBuff(entry.category) and ns.Data.FLASK or entry.category
end

local function SortEntries(a, b)
    local ba, bb = Bucket(a), Bucket(b)
    if ba ~= bb then return ba < bb end
    -- Food and drink: buff food first, unless you're already Well Fed, then
    -- plain food first and buff food last (mealRank 0 / 1 / 2).
    if a.mealRank ~= b.mealRank then return a.mealRank < b.mealRank end
    -- Buffs and buff food: best match for your stat priority first.
    if a.statScore ~= b.statScore then return a.statScore > b.statScore end
    if a.statAmount ~= b.statAmount then return a.statAmount > b.statAmount end
    if a.category ~= b.category then return a.category < b.category end
    -- Known amounts first (strongest first), then unknown items by item level.
    local pa, pb = a.power or -1, b.power or -1
    if pa ~= pb then return pa > pb end
    if a.itemLevel ~= b.itemLevel then return a.itemLevel > b.itemLevel end
    return a.id < b.id
end

-- GetTime() when the item's cooldown ends and the cooldown's full length, or
-- nil if it is ready. Ignores the global cooldown.
function S.ReadyAt(itemID)
    local start, duration, enable = ns.ItemCooldown(itemID)
    if not duration or duration <= 1.5 then return end
    -- "Not enabled": the cooldown is waiting to start, as with a potion used
    -- in combat, which only starts its cooldown once combat ends. It isn't
    -- usable, so count it as on cooldown for its full length.
    if enable == 0 or enable == false then return GetTime() + duration, duration end
    if not start or start == 0 then return end
    local readyAt = start + duration
    if readyAt > GetTime() then return readyAt, duration end
end

-- Cooldown lengths that are fixed game rules, used until one is seen in game.
local DEFAULT_COOLDOWNS = { hs = 120, pot = 120, rune = 120, bandage = 60 }

-- Buff lengths stated on the item ("... for 30 min."), by group.
S.statedLength = {}

local UNIT_SECONDS = { sec = 1, min = 60, hour = 3600, hr = 3600 }

-- Seconds from "for 30 min", "for 1 hour", "for 2 hrs" in the "Use:" text. enUS only.
local function StatedLength(itemID)
    local text = (ns.ItemUseText(itemID) or ""):lower()
    for amount, unit in text:gmatch("for ([%d%.]+) (%a+)") do
        local n = tonumber(amount)
        for prefix, seconds in pairs(UNIT_SECONDS) do
            if n and unit:sub(1, #prefix) == prefix then return n * seconds end
        end
    end
end

-- Seconds a cooldown or buff lasts: seen in game, else stated on the item,
-- else a fixed game rule. Nil when unknown: then a use in combat blocks the
-- item for the rest of that fight (Flyout.lua), and the real length is
-- read once the fight ends.
function S.CooldownLength(group)
    return ns.data.cooldowns[group] or S.statedLength[group] or DEFAULT_COOLDOWNS[group]
end

-- Returns every usable consumable in the bags, sorted by priority. Each entry:
-- { id, name, link, count, category, power, itemLevel }
function S:Scan()
    local byID, list = {}, {}
    local playerLevel = UnitLevel("player")
    local wellFed = ns.PlayerBuff(nil, WELL_FED or "Well Fed") ~= nil
    self.waitingForInfo = false

    for bag = 0, NUM_BAGS do
        for slot = 1, ns.ContainerNumSlots(bag) or 0 do
            local itemID, count, link, hasLoot = ns.ContainerItem(bag, slot)
            if itemID then
                local entry = byID[itemID]
                if entry then
                    entry.count = entry.count + (count or 1)
                elseif byID[itemID] == nil then
                    local name, _, _, itemLevel, minLevel = ns.ItemInfo(itemID)
                    if not name then
                        self.waitingForInfo = true
                        name = link and link:match("%[(.-)%]")
                    end
                    local category, power = ns.Data.Classify(itemID, name)
                    -- Lockboxes, clams, bags and crates: opened with a click.
                    if not category and hasLoot then category = ns.Data.OPEN end
                    -- Skip what this character can't use: too high a level, a
                    -- missing skill (bandages need First Aid), no mana, ...
                    -- The usable check is only trusted out of combat. A fishing
                    -- pole has no use effect: it is equipped, not used.
                    local usable = (minLevel or 0) <= playerLevel
                        and (InCombatLockdown() or ns.IsUsableItem(itemID) or ns.Data.IsFishingPole(itemID))
                    if category and usable then
                        entry = {
                            id = itemID,
                            name = name,
                            link = link,
                            count = count or 1,
                            category = category,
                            power = power,
                            itemLevel = itemLevel or 0,
                        }
                        local spellName, spellID = ns.ItemSpell(itemID)
                        entry.spellID = spellID
                        entry.ooc = ns.Data.IsOutOfCombat(category)
                            or ns.data.ooc[itemID] or false
                        entry.mealRank = 1
                        if ns.Data.IsMeal(category)
                            and (ns.ItemUseText(itemID) or ""):lower():find("well fed") then
                            entry.mealRank = wellFed and 2 or 0
                        end
                        -- Buffs and buff food are scored against your stat priority.
                        entry.statScore, entry.statAmount = 0, 0
                        if ns.Data.IsBuff(category) or entry.mealRank ~= 1 then
                            entry.statScore, entry.statAmount = ns.Stats:Score(itemID)
                        end
                        entry.group = ns.Data.CooldownGroup(entry)
                        local readyAt, duration
                        if entry.group:sub(1, 1) == "a" then
                            -- Buff items: "ready" again when the buff runs out.
                            -- Prefer the buff learned from using the item; the
                            -- item's own spell may not be the buff it gives.
                            S.statedLength[entry.group] = S.statedLength[entry.group] or StatedLength(itemID)
                            local learned = ns.data.itemBuffs[itemID]
                            if learned then
                                readyAt, duration = ns.PlayerBuff(learned.spellID, learned.name)
                            else
                                readyAt, duration = ns.PlayerBuff(spellID, spellName)
                            end
                            if readyAt and (readyAt == 0 or readyAt <= GetTime()) then readyAt = nil end
                            -- Not learned yet and the buff wasn't found: a recent
                            -- use still counts as the buff being up.
                            local usedAt = ns.usedAt[itemID]
                            local length = S.CooldownLength(entry.group)
                            if not readyAt and not learned and usedAt and length then
                                local ends = usedAt + length
                                if ends > GetTime() then readyAt = ends end
                            end
                        else
                            readyAt, duration = S.ReadyAt(itemID)
                        end
                        entry.readyAt = readyAt
                        if duration and duration > 0 and entry.group ~= "" then
                            -- Remember the real length for in-combat estimates.
                            ns.data.cooldowns[entry.group] = duration
                        end
                        byID[itemID] = entry
                        list[#list + 1] = entry
                    else
                        byID[itemID] = false -- not ours; skip further stacks
                    end
                end
            end
        end
    end

    table.sort(list, SortEntries)
    return list
end

---------------------------------------------------------------------------
-- Plain-press fallback steps
---------------------------------------------------------------------------

-- Turns the sorted list into steps for the plain press: one step per item,
-- grouped by category (already strongest first within a category).
-- Returns steps ([key] = { item, count, group, entry }) and the orders:
-- ch/rh = health in/out of combat, cm/rm = mana in/out of combat, b = boss,
-- x = buffs on demand (Alt).
function S:BuildSteps(list)
    local D = ns.Data
    local steps = {}
    local stones, potions, emergency, bandages, buffs, mana = {}, {}, {}, {}, {}, {}
    local refreshment, food, drink = {}, {}, {}
    local groups = {
        [D.HEALTHSTONE] = { "h", stones },
        [D.HEALING] = { "p", potions },
        [D.EMERGENCY] = { "e", emergency },
        [D.BANDAGE] = { "b", bandages },
        [D.MANA] = { "n", mana },
        [D.REFRESHMENT] = { "m", refreshment },
        [D.FOOD] = { "f", food },
        [D.DRINK] = { "d", drink },
        -- Flask, elixir/juju, scroll, enhancement potion (the list's order).
        [D.FLASK] = { "x", buffs },
        [D.ELIXIR] = { "x", buffs },
        [D.SCROLL] = { "x", buffs },
        [D.BUFF] = { "x", buffs },
        [D.POTION] = { "x", buffs },
    }

    for _, entry in ipairs(list) do
        local group = groups[entry.category]
        if group then
            local keys = group[2]
            local key = group[1] .. (#keys + 1)
            steps[key] = { item = "item:" .. entry.id, count = entry.count, group = entry.group, entry = entry }
            keys[#keys + 1] = key
        end
    end

    -- Emergency heals that also restore mana (e.g. a stone that restores
    -- health and mana) belong in the mana orders too.
    local emergencyMana = {}
    for _, key in ipairs(emergency) do
        local text = (ns.ItemUseText(steps[key].entry.id) or ""):lower()
        if text:find("[%d%.%%]+ mana") or text:find("health and mana") then
            emergencyMana[#emergencyMana + 1] = key
        end
    end

    local orders = { ch = {}, rh = {}, cm = {}, rm = {}, b = {}, x = {} }
    local function Append(order, keys)
        for _, key in ipairs(keys) do
            if steps[key] then order[#order + 1] = key end
        end
    end
    -- Health, in combat: strongest first. Food and drink can't be used in combat.
    Append(orders.ch, stones)
    Append(orders.ch, potions)
    Append(orders.ch, emergency)
    Append(orders.ch, bandages)
    -- Health, out of combat: cheapest first, saving potions and healthstones
    -- for fights. Food that restores both comes before plain food.
    Append(orders.rh, bandages)
    Append(orders.rh, refreshment)
    Append(orders.rh, food)
    Append(orders.rh, emergency)
    Append(orders.rh, potions)
    Append(orders.rh, stones)
    -- Mana, in combat: mana potions, runes and gems, then mana-restoring stones.
    Append(orders.cm, mana)
    Append(orders.cm, emergencyMana)
    -- Mana, out of combat: refreshment and drink first, saving potions.
    Append(orders.rm, refreshment)
    Append(orders.rm, drink)
    Append(orders.rm, emergencyMana)
    Append(orders.rm, mana)
    -- Boss fight: keep buffs up first, then the primary resource in combat.
    -- Buffs (already best match first across every kind, see SortEntries):
    -- those that give one of your stats first, then the rest.
    local matched, unmatched = {}, {}
    for _, key in ipairs(buffs) do
        local list = steps[key].entry.statScore > 0 and matched or unmatched
        list[#list + 1] = key
    end
    buffs = matched
    for _, key in ipairs(unmatched) do buffs[#buffs + 1] = key end
    Append(orders.b, buffs)
    -- Alt+press: buffs only, any time (pre-pull, or fights without a boss).
    Append(orders.x, buffs)
    Append(orders.b, ns.Settings:PrioritizeMana() and orders.cm or orders.ch)

    return steps, orders
end
