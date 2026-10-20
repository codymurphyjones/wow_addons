local _, ns = ...
local C = ns.Compat

-- Scores items with StatLedger's weights and compares them with what you wear.
-- An item's score = sum over its stats of their worth by StatLedger's weights, as StatLedger
-- prices them (budget per point for your class and level, plus a share of what each produces).
local Sc = {}
ns.Scoring = Sc

local SLOT_MAP = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
Sc.SLOT_MAP = SLOT_MAP

Sc.SLOT_NAMES = {
    [1] = "Head", [2] = "Neck", [3] = "Shoulder", [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet",
    [9] = "Wrist", [10] = "Hands", [11] = "Finger 1", [12] = "Finger 2", [13] = "Trinket 1", [14] = "Trinket 2",
    [15] = "Back", [16] = "Main Hand", [17] = "Off Hand", [18] = "Ranged",
}
Sc.SLOT_ORDER = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }

-- ---------------------------------------------------------------------------
-- Weights and item scores
-- ---------------------------------------------------------------------------

local weights, ranks
local scores = {}

local function Load()
    if weights then return end
    weights, ranks = StatLedger:GetWeights(), {}
    for i, stat in ipairs(StatLedger:GetPriority()) do ranks[stat] = i end
end

function Sc:Invalidate()
    weights, ranks = nil, nil
    wipe(scores)
end

-- StatLedger weight: 1.0 for your top stat falling to 0.1 for the last; 0 when unlisted.
function Sc:Weight(stat) Load(); return weights[stat] or 0 end
function Sc:Rank(stat) Load(); return ranks[stat] end

-- { link, total, values = {stat=amount}, contrib = {stat=score}, info }, or nil while loading.
function Sc:Score(link)
    if not link then return nil end
    local hit = scores[link]
    if hit then return hit end
    local values, info = ns.Stats:Read(link)
    if not values then return nil end
    Load()
    local s = { link = link, values = values, info = info }
    s.total, s.contrib = StatLedger:Score(values, weights)
    scores[link] = s
    return s
end

-- ---------------------------------------------------------------------------
-- Comparison with equipped gear
-- ---------------------------------------------------------------------------

-- What an item would replace: a list of { slots, label }. Rings, trinkets and dual-wielded
-- one-handers have two choices; the weaker one is compared.
local function Targets(equipLoc)
    local slots = SLOT_MAP[equipLoc]
    local mainLoc = C.EquipLoc(GetInventoryItemLink("player", 16))
    if equipLoc == "INVTYPE_2HWEAPON" then
        if mainLoc == "INVTYPE_2HWEAPON" then return { { slots = { 16 }, label = "Main Hand" } } end
        return { { slots = { 16, 17 }, label = "Main Hand + Off Hand" } }
    end
    if slots[1] == 17 and mainLoc == "INVTYPE_2HWEAPON" then
        return nil, "Your two-handed weapon takes the off hand."
    end
    if equipLoc == "INVTYPE_WEAPON" and mainLoc ~= "INVTYPE_2HWEAPON" and C.CanDualWield() then
        -- Only against an off-hand weapon or an empty off hand, never a shield or held item.
        local offLoc = C.EquipLoc(GetInventoryItemLink("player", 17))
        if offLoc == nil or offLoc == "INVTYPE_WEAPON" or offLoc == "INVTYPE_WEAPONOFFHAND" then
            return { { slots = { 16 }, label = "Main Hand" }, { slots = { 17 }, label = "Off Hand" } }
        end
    end
    local out = {}
    for _, id in ipairs(slots) do out[#out + 1] = { slots = { id }, label = Sc.SLOT_NAMES[id] } end
    return out
end

local function ByImpact(a, b) return math.abs(a.impact) > math.abs(b.impact) end
local function ByValue(a, b) return math.abs(a.value) > math.abs(b.value) end

-- Compares an item with what it would replace. nil if it isn't gear or is still loading.
-- cmp = { link, new (its Score), info, verdict, label, reason,
--         base, diff, percent, replaced = {links},
--         deltas = { {stat, value, impact, rank, percent} } (stats that move the score),
--         ignored = { {stat, value, percent} } (stats that change but your spec doesn't rank),
--         reqLevel (set when above your level), uniqueWorn }
-- verdict: "upgrade", "downgrade", "sidegrade", "new" (empty slot), "equipped" (this is
-- the item you wear), "none" (can't be compared; see reason).
function Sc:Compare(link)
    local equipLoc = C.EquipLoc(link)
    if not equipLoc or not SLOT_MAP[equipLoc] then return nil end
    local new = self:Score(link)
    if not new then return nil end
    local cmp = { link = link, new = new, info = new.info, deltas = {}, ignored = {}, replaced = {} }

    local level = UnitLevel("player") or 0
    if new.info.reqLevel and new.info.reqLevel > level then cmp.reqLevel = new.info.reqLevel end
    if new.info.unique then
        local id = C.IDFromLink(link)
        for _, slot in ipairs({ 11, 12, 13, 14, 16, 17 }) do
            if id and GetInventoryItemID("player", slot) == id and GetInventoryItemLink("player", slot) ~= link then
                cmp.uniqueWorn = true
            end
        end
    end

    local targets, reason = Targets(equipLoc)
    if not targets then
        cmp.verdict, cmp.reason = "none", reason
        return cmp
    end

    local best
    for _, t in ipairs(targets) do
        local base, items = 0, {}
        for _, slot in ipairs(t.slots) do
            local worn = GetInventoryItemLink("player", slot)
            if worn == link then
                cmp.verdict, cmp.label = "equipped", Sc.SLOT_NAMES[slot]
                return cmp
            end
            if worn then
                local s = self:Score(worn)
                if not s then return nil end -- equipped item still loading
                base = base + s.total
                items[#items + 1] = s
            end
        end
        if not best or base < best.base then best = { base = base, items = items, label = t.label } end
    end

    cmp.label, cmp.base = best.label, best.base
    cmp.diff = new.total - best.base
    if best.base > 0 then cmp.percent = cmp.diff / best.base * 100 end

    -- Stat by stat: the candidate against everything it replaces.
    local oldValues, oldContrib = {}, {}
    for _, s in ipairs(best.items) do
        cmp.replaced[#cmp.replaced + 1] = s.link
        for stat, v in pairs(s.values) do oldValues[stat] = (oldValues[stat] or 0) + v end
        for stat, c in pairs(s.contrib) do oldContrib[stat] = (oldContrib[stat] or 0) + c end
    end
    local seen = {}
    local function Consider(stat)
        if seen[stat] then return end
        seen[stat] = true
        local nv, ov = new.values[stat] or 0, oldValues[stat] or 0
        local impact = (new.contrib[stat] or 0) - (oldContrib[stat] or 0)
        local percent = ns.Stats:IsPercent(stat, math.max(math.abs(nv), math.abs(ov)))
        if math.abs(impact) >= 0.005 then
            cmp.deltas[#cmp.deltas + 1] = { stat = stat, value = nv - ov, impact = impact, rank = self:Rank(stat), percent = percent }
        elseif nv ~= ov and self:Weight(stat) == 0 then
            cmp.ignored[#cmp.ignored + 1] = { stat = stat, value = nv - ov, percent = percent }
        end
    end
    for stat in pairs(new.values) do Consider(stat) end
    for stat in pairs(oldValues) do Consider(stat) end
    table.sort(cmp.deltas, ByImpact)
    table.sort(cmp.ignored, ByValue)

    local band = tonumber(ns.db and ns.db.sidegrade) or 1
    if #best.items == 0 then
        cmp.verdict = "new"
    elseif (cmp.percent and math.abs(cmp.percent) < band) or (not cmp.percent and math.abs(cmp.diff) < 0.05) then
        cmp.verdict = "sidegrade"
    else
        cmp.verdict = cmp.diff > 0 and "upgrade" or "downgrade"
    end
    return cmp
end

-- Worth highlighting in bags: a usable upgrade (above the minimum %) or something for an empty slot.
function Sc:IsUpgrade(cmp)
    if not cmp or cmp.info.unusable or cmp.reqLevel or cmp.uniqueWorn then return false end
    if cmp.verdict == "new" then return cmp.new.total > 0 end
    if cmp.verdict ~= "upgrade" then return false end
    return not cmp.percent or cmp.percent + 0.000001 >= (tonumber(ns.db.minUpgrade) or 0)
end

-- For other addons (Wally, before it sells gear): whether an item beats what it would replace, by
-- your StatLedger stats. Returns isUpgrade, detail ("+4.2% (+3 Stamina, +2 Strength)"), or nil while it
-- can't be judged (not gear, still loading). Unlike the bag highlight, a level requirement above yours
-- doesn't count against it: you'll grow into the item.
TapeMeasureAPI = TapeMeasureAPI or {}
function TapeMeasureAPI.IsUpgrade(link)
    if not link then return nil end
    local ok, cmp = pcall(Sc.Compare, Sc, link)
    if not ok or not cmp or cmp.verdict == "none" then return nil end
    if cmp.info.unusable then return false, "can't use" end
    if cmp.verdict == "new" then return cmp.new.total > 0, "empty slot" end
    if cmp.verdict ~= "upgrade" then return false, cmp.verdict end
    local reasons = Sc:Reasons(cmp, 2)
    return true, Sc:FormatChange(cmp, true) .. (reasons ~= "" and (" (" .. reasons .. ")") or "")
end

-- Upgrades in your bags: { bag, slot, link, cmp }, empty slots first, then by percent.
function Sc:ScanBags()
    local out = {}
    for bag, slot, link in C.IterateBags() do
        if SLOT_MAP[C.EquipLoc(link) or ""] and C.IsEquippableItem(link) then
            local cmp = self:Compare(link)
            if self:IsUpgrade(cmp) then out[#out + 1] = { bag = bag, slot = slot, link = link, cmp = cmp } end
        end
    end
    table.sort(out, function(a, b)
        local ap, bp = a.cmp.percent, b.cmp.percent
        if (ap == nil) ~= (bp == nil) then return ap == nil end
        if ap and bp and ap ~= bp then return ap > bp end
        return a.cmp.diff > b.cmp.diff
    end)
    return out
end

-- ---------------------------------------------------------------------------
-- Text
-- ---------------------------------------------------------------------------

function Sc:FormatScore(value)
    value = tonumber(value) or 0
    if math.abs(value) >= 100 then return ("%.0f"):format(value) end
    return ("%.1f"):format(value)
end

-- "+12.4%", "-3.0%", "NEW", "+2.1 score"
function Sc:FormatChange(cmp, compact)
    if cmp.verdict == "new" then return "NEW" end
    if cmp.percent then
        if cmp.percent > 0 and cmp.percent < 0.05 then return "+<0.1%" end
        return ("%+.1f%%"):format(cmp.percent)
    end
    return (cmp.diff >= 0 and "+" or "") .. self:FormatScore(cmp.diff) .. (compact and "" or " score")
end

-- "+12 Fire Spell Power, +1% Spell Critical Strike": the n biggest changes.
function Sc:Reasons(cmp, n)
    local parts = {}
    for i = 1, math.min(n or 3, #cmp.deltas) do
        local d = cmp.deltas[i]
        parts[i] = ns.Stats:FormatDelta(d.stat, d.value, d.percent)
    end
    return table.concat(parts, ", ")
end

local function Names(list, n)
    local names = {}
    for i = 1, math.min(n, #list) do names[i] = ns.Stats:Label(list[i].stat) end
    return table.concat(names, " and ")
end

-- One sentence on why: which stats carry the gain or the loss.
function Sc:Summary(cmp)
    local gains, losses = {}, {}
    for _, d in ipairs(cmp.deltas) do
        if d.impact > 0 then gains[#gains + 1] = d else losses[#losses + 1] = d end
    end
    if #gains == 0 and #losses == 0 then
        if #cmp.ignored > 0 then return "None of the stats that change are on your priority list." end
        return nil
    end
    if cmp.verdict == "upgrade" or cmp.verdict == "new" then
        if #gains == 0 then return nil end
        local text = "Better mostly for its " .. Names(gains, 2)
        if #losses > 0 then text = text .. ", despite less " .. Names(losses, 1) end
        return text .. "."
    elseif cmp.verdict == "downgrade" then
        if #losses == 0 then return nil end
        local text = "Worse mostly from losing " .. Names(losses, 2)
        if #gains > 0 then text = text .. "; the extra " .. Names(gains, 1) .. " doesn't make up for it" end
        return text .. "."
    end
    if #gains > 0 and #losses > 0 then
        return "Trades " .. Names(losses, 1) .. " for " .. Names(gains, 1) .. ": about even for your priority."
    end
    return "About even for your priority."
end
