local _, ns = ...
local C = ns.Compat

-- Scores items with StatLedger's weights and compares them with what you wear.
-- An item's score = sum over its stats of their worth by StatLedger's weights, as StatLedger
-- prices them (budget per point for your class and level, plus a share of what each produces).
-- The scoring and comparing are the shared GearEngine.lua (addons/shared), which SpyGlass and
-- Wally use too, so all three agree on what's an upgrade.
local Sc = {}
ns.Scoring = Sc

local E = ns.GearEngine
local SLOT_MAP = E.SLOT_MAP
Sc.SLOT_MAP = SLOT_MAP
Sc.SLOT_NAMES = E.SLOT_NAMES
Sc.SLOT_ORDER = E.SLOT_ORDER

function Sc:Invalidate() E.Invalidate() end

-- StatLedger weight: 1.0 for your top stat falling to 0.1 for the last; 0 when unlisted.
function Sc:Weight(stat) return E.Weight(stat) end
function Sc:Rank(stat) return E.Rank(stat) end

-- { link, total, values = {stat=amount}, contrib = {stat=score}, info }, or nil while loading.
function Sc:Score(link) return E.Score(link) end

-- Compares an item with what it would replace (GearEngine.lua lists the fields). nil if it isn't
-- gear or is still loading. The sidegrade band is your setting.
function Sc:Compare(link)
    return E.Compare(link, tonumber(ns.db and ns.db.sidegrade) or 1)
end

-- Worth highlighting in bags: a usable upgrade (above the minimum %) or something for an empty slot.
function Sc:IsUpgrade(cmp)
    if not cmp or cmp.info.unusable or cmp.reqLevel or cmp.uniqueWorn then return false end
    if cmp.verdict == "new" then return cmp.new.total > 0 end
    if cmp.verdict ~= "upgrade" then return false end
    return not cmp.percent or cmp.percent + 0.000001 >= (tonumber(ns.db.minUpgrade) or 0)
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
