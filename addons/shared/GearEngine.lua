local addonName, ns = ...

-- Is this item an upgrade? One engine for every addon here (addons/shared): Tape Measure's bag and
-- tooltip verdicts, SpyGlass's loot lists and Wally's "don't sell that" all judge an item the same
-- way. An item's stats are read in StatLedger's stat keys (GetItemStats plus the "Equip:" lines it
-- misses), scored by your StatLedger stat priority (fallback weights without it), and compared with
-- what it would replace: rings, trinkets and dual-wielded one-handers against the weaker of the
-- two, a two-hander against main hand plus off hand.
--
-- With SpyGlass installed, effects it can turn into stats (shapeshift costs, weapon skill, spell
-- cost...) count too, through SpyGlass:EffectStats; SpyGlass's own copy uses its Effects.lua.
local E = {}
ns.GearEngine = E

-- ---------------------------------------------------------------------------
-- Slots
-- ---------------------------------------------------------------------------

E.SLOT_MAP = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

E.SLOT_NAMES = {
    [1] = "Head", [2] = "Neck", [3] = "Shoulder", [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet",
    [9] = "Wrist", [10] = "Hands", [11] = "Finger 1", [12] = "Finger 2", [13] = "Trinket 1", [14] = "Trinket 2",
    [15] = "Back", [16] = "Main Hand", [17] = "Off Hand", [18] = "Ranged",
}
E.SLOT_ORDER = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }

-- An item's equip location ("INVTYPE_HEAD"), from its link or ID, or nil.
function E.EquipLoc(item)
    if not item then return nil end
    local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not fn then return nil end
    local ok, _, _, _, loc = pcall(fn, item)
    return ok and loc ~= "" and loc or nil
end

function E.CanDualWield()
    if IsPlayerSpell then return IsPlayerSpell(674) and true or false end
    if IsSpellKnown then return IsSpellKnown(674) and true or false end
    return false
end

-- What an item would replace: a list of { slots, label }, or nil and why it can't go on. Rings,
-- trinkets and dual-wielded one-handers have two choices; callers compare the weaker one.
function E.Targets(equipLoc)
    local slots = E.SLOT_MAP[equipLoc or ""]
    if not slots then return nil, "not gear" end
    local mainLoc = E.EquipLoc(GetInventoryItemLink("player", 16))
    if equipLoc == "INVTYPE_2HWEAPON" then
        if mainLoc == "INVTYPE_2HWEAPON" then return { { slots = { 16 }, label = "Main Hand" } } end
        return { { slots = { 16, 17 }, label = "Main Hand + Off Hand" } }
    end
    if slots[1] == 17 and mainLoc == "INVTYPE_2HWEAPON" then
        return nil, "Your two-handed weapon takes the off hand."
    end
    if equipLoc == "INVTYPE_WEAPON" and mainLoc ~= "INVTYPE_2HWEAPON" and E.CanDualWield() then
        -- Only against an off-hand weapon or an empty off hand, never a shield or held item.
        local offLoc = E.EquipLoc(GetInventoryItemLink("player", 17))
        if offLoc == nil or offLoc == "INVTYPE_WEAPON" or offLoc == "INVTYPE_WEAPONOFFHAND" then
            return { { slots = { 16 }, label = "Main Hand" }, { slots = { 17 }, label = "Off Hand" } }
        end
    end
    local out = {}
    for _, id in ipairs(slots) do out[#out + 1] = { slots = { id }, label = E.SLOT_NAMES[id] } end
    return out
end

-- What you wear where an item would go, scored by scoreOf(slot) (a number, or nil while that
-- item is loading): base (the weaker choice's total), empty (that choice has nothing in it), label,
-- target. nil, why when it can't go on; nil, "loading" while a worn item is loading.
function E.Worn(equipLoc, scoreOf)
    local targets, why = E.Targets(equipLoc)
    if not targets then return nil, why end
    local best
    for _, t in ipairs(targets) do
        local base, filled = 0, 0
        for _, slot in ipairs(t.slots) do
            if GetInventoryItemID("player", slot) then
                local s = scoreOf(slot)
                if s == nil then return nil, "loading" end
                base, filled = base + s, filled + 1
            end
        end
        if not best or base < best.base then best = { base = base, empty = filled == 0, label = t.label, target = t } end
    end
    return best.base, best.empty, best.label, best.target
end

-- The verdict for an item scoring total against base: "new" (its slot is empty), "sidegrade"
-- (within band percent, or 0.05 points when nothing is worn worth anything), "upgrade" or
-- "downgrade". band defaults to 1 (%).
function E.Verdict(total, base, empty, band)
    if empty then return "new" end
    band = band or 1
    local diff = total - base
    if (base > 0 and math.abs(diff / base * 100) < band) or (base <= 0 and math.abs(diff) < 0.05) then
        return "sidegrade"
    end
    return diff > 0 and "upgrade" or "downgrade"
end

-- ---------------------------------------------------------------------------
-- Stats
-- ---------------------------------------------------------------------------

-- GetItemStats keys -> StatLedger stat keys. Melee and spell crit stay apart: StatLedger ranks them
-- separately. Spell hit counts as Hit, which StatLedger has only one of.
E.STAT_ALIASES = {
    ITEM_MOD_STRENGTH_SHORT = "STR", ITEM_MOD_AGILITY_SHORT = "AGI", ITEM_MOD_STAMINA_SHORT = "STA",
    ITEM_MOD_INTELLECT_SHORT = "INT", ITEM_MOD_SPIRIT_SHORT = "SPI",
    ITEM_MOD_ATTACK_POWER_SHORT = "AP", ITEM_MOD_ATTACK_POWER = "AP", ITEM_MOD_MELEE_ATTACK_POWER_SHORT = "AP",
    ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "RAP", ITEM_MOD_RANGED_ATTACK_POWER = "RAP",
    ITEM_MOD_SPELL_POWER_SHORT = "SP", ITEM_MOD_SPELL_POWER = "SP",
    ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "SP", ITEM_MOD_SPELL_DAMAGE_DONE = "SP",
    ITEM_MOD_SPELL_HEALING_DONE_SHORT = "HEAL", ITEM_MOD_SPELL_HEALING_DONE = "HEAL",
    ITEM_MOD_HEALING_DONE_SHORT = "HEAL", ITEM_MOD_HEALING_DONE = "HEAL",
    ITEM_MOD_CRIT_RATING_SHORT = "CRIT", ITEM_MOD_CRIT_MELEE_RATING_SHORT = "CRIT", ITEM_MOD_CRIT_RANGED_RATING_SHORT = "CRIT",
    ITEM_MOD_CRIT_SPELL_RATING_SHORT = "SPELLCRIT", ITEM_MOD_SPELL_CRIT_RATING_SHORT = "SPELLCRIT",
    ITEM_MOD_HIT_RATING_SHORT = "HIT", ITEM_MOD_HIT_MELEE_RATING_SHORT = "HIT", ITEM_MOD_HIT_RANGED_RATING_SHORT = "HIT",
    ITEM_MOD_HIT_SPELL_RATING_SHORT = "HIT", ITEM_MOD_SPELL_HIT_RATING_SHORT = "HIT",
    ITEM_MOD_HASTE_RATING_SHORT = "HASTE", ITEM_MOD_HASTE_MELEE_RATING_SHORT = "HASTE",
    ITEM_MOD_HASTE_RANGED_RATING_SHORT = "HASTE", ITEM_MOD_HASTE_SPELL_RATING_SHORT = "HASTE",
    ITEM_MOD_MANA_REGENERATION_SHORT = "MP5", ITEM_MOD_MANA_REGENERATION = "MP5", ITEM_MOD_POWER_REGEN0_SHORT = "MP5",
    RESISTANCE0_NAME = "ARMOR", ITEM_MOD_ARMOR_SHORT = "ARMOR", ITEM_MOD_EXTRA_ARMOR_SHORT = "ARMOR",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "DEF", ITEM_MOD_DEFENSE_SKILL_RATING = "DEF",
    ITEM_MOD_DODGE_RATING_SHORT = "DODGE", ITEM_MOD_PARRY_RATING_SHORT = "PARRY",
    ITEM_MOD_BLOCK_RATING_SHORT = "BLOCK", ITEM_MOD_BLOCK_VALUE_SHORT = "BLOCKVALUE", ITEM_MOD_BLOCK_VALUE = "BLOCKVALUE",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "DPS",
}

-- "Equip:" effects GetItemStats may not report, matched against the line's text after "Equip:",
-- lower-cased and without commas (enUS). The first pattern that matches wins, so the more specific
-- come first. "SCHOOL" takes the school from the first capture and the amount from the second.
E.EQUIP_PATTERNS = {
    { "damage and healing done by magical spells and effects by up to (%d+)", { "SP", "HEAL" } },
    { "healing done by spells and effects by up to (%d+)", { "HEAL" } },
    { "healing done by up to (%d+)", { "HEAL" } },
    { "damage done by (%a+) spells and effects by up to (%d+)", "SCHOOL" },
    { "critical strike with spells by (%d+)", { "SPELLCRIT" } },
    { "critical strike by (%d+)", { "CRIT" } },
    { "chance to hit with spells by (%d+)", { "HIT" } },
    { "chance to hit by (%d+)", { "HIT" } },
    { "restores (%d+) mana per 5 sec", { "MP5" } },
    { "(%d+) mana every 5 sec", { "MP5" } },
    { "^%+(%d+) ranged attack power%.?$", { "RAP" } },
    { "^%+(%d+) attack power%.?$", { "AP" } }, -- not "...when fighting Undead"
    { "increased defense %+(%d+)", { "DEF" } },
    { "chance to dodge an attack by (%d+)", { "DODGE" } },
    { "chance to parry an attack by (%d+)", { "PARRY" } },
    { "chance to block attacks with a shield by (%d+)", { "BLOCK" } },
    { "block value of your shield by (%d+)", { "BLOCKVALUE" } },
    { "attack speed by (%d+)", { "HASTE" } },
}
E.SCHOOLS = { fire = "FIRE", frost = "FROST", shadow = "SHADOW", arcane = "ARCANE", nature = "NATURE" }

-- Without StatLedger.
E.FALLBACK_WEIGHTS = { STA = 0.6, STR = 0.5, AGI = 0.5, INT = 0.5, SPI = 0.3 }

local EQUIP = strlower(ITEM_SPELL_TRIGGER_ONEQUIP or "Equip:")
local USE = strlower(ITEM_SPELL_TRIGGER_ONUSE or "Use:")
local PROC = strlower(ITEM_SPELL_TRIGGER_ONPROC or "Chance on hit:")
local UNIQUE = ITEM_UNIQUE or "Unique"
local UNIQUE_EQUIPPED = ITEM_UNIQUE_EQUIPPABLE or "Unique-Equipped"

local function Starts(text, prefix) return text:sub(1, #prefix) == prefix end


-- One tooltip line's stats: adds an "Equip:" line's stats to out and returns true when it was a
-- line the patterns know; false for an Equip: line they don't (an effect nothing scores); nil
-- for any other line.
function E.EquipLine(text, out)
    local lower = strlower(text)
    if not Starts(lower, EQUIP) then return nil end
    local body = strtrim(lower:sub(#EQUIP + 1)):gsub(",", "")
    for _, p in ipairs(E.EQUIP_PATTERNS) do
        local a, b = body:match(p[1])
        if a then
            if p[2] == "SCHOOL" then
                local stat = E.SCHOOLS[a]
                if not stat then return false end -- Holy damage and the like
                out[stat] = (out[stat] or 0) + tonumber(b)
            else
                for _, stat in ipairs(p[2]) do out[stat] = (out[stat] or 0) + tonumber(a) end
            end
            return true
        end
    end
    return false
end

-- GetItemStats in StatLedger's keys, or nil while the item isn't loaded.
function E.ApiStats(link)
    local fn = (C_Item and C_Item.GetItemStats) or GetItemStats
    if not (fn and link) then return nil end
    local ok, raw = pcall(fn, link)
    if not ok or type(raw) ~= "table" then return nil end
    local values = {}
    for key, v in pairs(raw) do
        local stat = type(v) == "number" and E.STAT_ALIASES[key]
        if stat then values[stat] = (values[stat] or 0) + v end
    end
    return values
end

-- GetItemStats and the Equip: lines can report the same effect: the larger of the two counts.
function E.Merge(api, text)
    local out = {}
    for stat, v in pairs(api or {}) do out[stat] = v end
    for stat, v in pairs(text or {}) do
        if not out[stat] or v > out[stat] then out[stat] = v end
    end
    return out
end

-- Equip-line stats, whether it has effects nothing scores (Use:, Chance on hit:, Equip: lines the
-- patterns don't know), whether it's unique, and whether red text says you can't use it (level
-- requirements aside: you grow into those). The second value is false while it isn't loaded.
-- The tooltip is read by the shared Tooltip.lua (ns.Tooltip: load it before this file).
function E.Scan(link)
    local T = ns.Tooltip or error("GearEngine.lua needs shared Tooltip.lua listed before it in the TOC")
    local lines = T.Lines("hyperlink", link)
    local out = { equip = {}, unscored = false, unique = false, unusable = T.Unusable(lines) }
    for i = 2, #(lines or {}) do
        local text = lines[i][1]
        if text ~= "" then
            if text == UNIQUE or Starts(text, UNIQUE_EQUIPPED) then out.unique = true end
            local lower = strlower(text)
            if Starts(lower, USE) or Starts(lower, PROC) then
                out.unscored = true
            elseif E.EquipLine(text, out.equip) == false then
                out.unscored = true
            end
        end
    end
    -- A tooltip with only the name line hasn't loaded yet.
    return out, lines ~= nil and #lines >= 2
end

local function ItemID(link) return link and tonumber(link:match("item:(%d+)")) end

local function Request(link)
    local id = ItemID(link)
    if id and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
end

-- Stats effects stand in for, from E.extra(link) (SpyGlass's Effects.lua, or SpyGlass:EffectStats).
function E.extra(link)
    if SpyGlass and SpyGlass.EffectStats then
        local ok, stats = pcall(SpyGlass.EffectStats, SpyGlass, ItemID(link))
        if ok and type(stats) == "table" then return stats end
    end
end

local reads = {}

-- values { [stat] = amount } and info { unscored, unique, unusable, reqLevel }, or nil while the
-- item is still loading.
function E.Read(link)
    if not link then return nil end
    local hit = reads[link]
    if hit then return hit.values, hit.info end
    local api = E.ApiStats(link)
    if not api then Request(link) return nil end
    local scanned, complete = E.Scan(link)
    if not complete then Request(link) return nil end
    local values = E.Merge(api, scanned.equip)
    for stat, v in pairs(E.extra(link) or {}) do values[stat] = (values[stat] or 0) + v end
    local info = { unscored = scanned.unscored, unique = scanned.unique, unusable = scanned.unusable }
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if get then
        local ok, _, _, _, _, req = pcall(get, link)
        if ok then info.reqLevel = req end
    end
    reads[link] = { values = values, info = info }
    return values, info
end

-- ---------------------------------------------------------------------------
-- Weights and scores
-- ---------------------------------------------------------------------------

local weights, ranks
local scores = {}

local function HasLedger() return StatLedger and StatLedger.GetWeights and StatLedger.Score and true or false end

local function Load()
    if weights then return end
    ranks = {}
    if HasLedger() then
        weights = StatLedger:GetWeights()
        for i, stat in ipairs(StatLedger:GetPriority() or {}) do ranks[stat] = i end
    else
        weights = E.FALLBACK_WEIGHTS
        local order = {}
        for stat in pairs(weights) do order[#order + 1] = stat end
        table.sort(order, function(a, b) return weights[a] > weights[b] end)
        for i, stat in ipairs(order) do ranks[stat] = i end
    end
end

function E.HasStatLedger() return HasLedger() end
function E.Weights() Load(); return weights end
-- StatLedger weight: 1.0 for your top stat falling to 0.1 for the last; 0 when unlisted.
function E.Weight(stat) Load(); return weights[stat] or 0 end
function E.Rank(stat) Load(); return ranks[stat] end

function E.IsPercent(stat, value)
    if StatLedger and StatLedger.IsPercent then return StatLedger:IsPercent(stat, value) end
    return false
end

-- total, contrib { [stat] = score } for some stat values: StatLedger prices each point (budget per
-- point for your class and level, plus a share of what each produces); without it, amount x weight.
function E.ScoreValues(values)
    Load()
    if HasLedger() then return StatLedger:Score(values, weights) end
    local total, contrib = 0, {}
    for stat, v in pairs(values) do
        local c = v * (weights[stat] or 0)
        if c ~= 0 then contrib[stat] = c; total = total + c end
    end
    return total, contrib
end

-- { link, total, values, contrib, info }, or nil while loading.
function E.Score(link)
    if not link then return nil end
    local hit = scores[link]
    if hit then return hit end
    local values, info = E.Read(link)
    if not values then return nil end
    local s = { link = link, values = values, info = info }
    s.total, s.contrib = E.ScoreValues(values)
    scores[link] = s
    return s
end

-- New weights (StatLedger changed): scores again. Stats stay.
function E.Invalidate()
    weights, ranks = nil, nil
    wipe(scores)
end

-- Learning a weapon skill or levelling changes what's usable: read again.
function E.ClearCache()
    wipe(reads)
    E.Invalidate()
end

-- ---------------------------------------------------------------------------
-- Comparing with what you wear
-- ---------------------------------------------------------------------------

local function ByImpact(a, b) return math.abs(a.impact) > math.abs(b.impact) end
local function ByValue(a, b) return math.abs(a.value) > math.abs(b.value) end

-- Compares an item with what it would replace. nil if it isn't gear or is still loading.
-- cmp = { link, new (its Score), info, verdict, label, reason,
--         base, diff, percent, replaced = {links},
--         deltas = { {stat, value, impact, rank, percent} } (stats that move the score),
--         ignored = { {stat, value, percent} } (stats that change but your spec doesn't rank),
--         reqLevel (set when above your level), uniqueWorn }
-- verdict: "upgrade", "downgrade", "sidegrade" (within band %, default 1), "new" (empty slot),
-- "equipped" (this is the item you wear), "none" (can't be compared; see reason).
function E.Compare(link, band)
    local equipLoc = E.EquipLoc(link)
    if not equipLoc or not E.SLOT_MAP[equipLoc] then return nil end
    local new = E.Score(link)
    if not new then return nil end
    local cmp = { link = link, new = new, info = new.info, deltas = {}, ignored = {}, replaced = {} }

    local level = UnitLevel("player") or 0
    if new.info.reqLevel and new.info.reqLevel > level then cmp.reqLevel = new.info.reqLevel end
    if new.info.unique then
        local id = ItemID(link)
        for _, slot in ipairs({ 11, 12, 13, 14, 16, 17 }) do
            if id and GetInventoryItemID("player", slot) == id and GetInventoryItemLink("player", slot) ~= link then
                cmp.uniqueWorn = true
            end
        end
    end

    -- This very item worn: nothing to compare.
    for _, slot in ipairs(E.SLOT_MAP[equipLoc]) do
        if GetInventoryItemLink("player", slot) == link then
            cmp.verdict, cmp.label = "equipped", E.SLOT_NAMES[slot]
            return cmp
        end
    end

    local loading = false
    local base, empty, label, target = E.Worn(equipLoc, function(slot)
        local s = E.Score(GetInventoryItemLink("player", slot))
        if not s then loading = true end
        return s and s.total
    end)
    if loading then return nil end -- an equipped item is still loading
    if not base then
        cmp.verdict, cmp.reason = "none", empty
        return cmp
    end

    cmp.label, cmp.base = label, base
    cmp.diff = new.total - base
    if base > 0 then cmp.percent = cmp.diff / base * 100 end

    -- Stat by stat: the candidate against everything it replaces.
    local oldValues, oldContrib = {}, {}
    for _, slot in ipairs(target.slots) do
        local s = E.Score(GetInventoryItemLink("player", slot))
        if s then
            cmp.replaced[#cmp.replaced + 1] = s.link
            for stat, v in pairs(s.values) do oldValues[stat] = (oldValues[stat] or 0) + v end
            for stat, c in pairs(s.contrib) do oldContrib[stat] = (oldContrib[stat] or 0) + c end
        end
    end
    local seen = {}
    local function Consider(stat)
        if seen[stat] then return end
        seen[stat] = true
        local nv, ov = new.values[stat] or 0, oldValues[stat] or 0
        local impact = (new.contrib[stat] or 0) - (oldContrib[stat] or 0)
        local percent = E.IsPercent(stat, math.max(math.abs(nv), math.abs(ov)))
        if math.abs(impact) >= 0.005 then
            cmp.deltas[#cmp.deltas + 1] = { stat = stat, value = nv - ov, impact = impact, rank = E.Rank(stat), percent = percent }
        elseif nv ~= ov and E.Weight(stat) == 0 then
            cmp.ignored[#cmp.ignored + 1] = { stat = stat, value = nv - ov, percent = percent }
        end
    end
    for stat in pairs(new.values) do Consider(stat) end
    for stat in pairs(oldValues) do Consider(stat) end
    table.sort(cmp.deltas, ByImpact)
    table.sort(cmp.ignored, ByValue)

    cmp.verdict = E.Verdict(new.total, base, empty, band)
    return cmp
end

-- ---------------------------------------------------------------------------
-- Keeping it current
-- ---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("SKILL_LINES_CHANGED")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if StatLedger and StatLedger.RegisterCallback then
            StatLedger:RegisterCallback(addonName .. "GearEngine", function() E.Invalidate() end)
        end
    else
        E.ClearCache()
    end
end)
