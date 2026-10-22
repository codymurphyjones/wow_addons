local _, ns = ...
local D = ns.Data

-- Scores items against the StatLedger weights for your spec:
-- score = sum of stat amount x stat unit value x priority weight. Reading stats, the weights and
-- what counts as an upgrade are the shared GearEngine.lua (addons/shared), the same as Tape
-- Measure's and Wally's; this adds SpyGlass's shipped stats (items not loaded yet) and its effects.
local S = {}
ns.Scoring = S

local GE = ns.GearEngine

local itemStats = {} -- [itemID] = { [stat] = amount }
local scores = {}    -- [itemID] = { score, top }
-- Scores from the shipped stats, until the game's own details arrive (then
-- scores takes over), so a redraw doesn't score them all again.
local bakedScores = {}
local NO_TOP = {}
local weights

function S:Init()
    if StatLedger and StatLedger.RegisterCallback then
        StatLedger:RegisterCallback("SpyGlass", function()
            S:Reset()
            ns:RequestRefresh()
        end)
    end
end

function S:Reset()
    weights = nil
    GE.Invalidate()
    wipe(scores)
    wipe(bakedScores)
    self:EquipmentChanged()
    ns.Upgrades:Invalidate()
end

-- Inventory slots for each slot group.
local GROUP_SLOTS = {
    HEAD = { 1 }, NECK = { 2 }, SHOULDER = { 3 }, BACK = { 15 }, CHEST = { 5 }, WRIST = { 9 },
    HANDS = { 10 }, WAIST = { 6 }, LEGS = { 7 }, FEET = { 8 }, FINGER = { 11, 12 },
    TRINKET = { 13, 14 }, MAINHAND = { 16 }, OFFHAND = { 17 }, RANGED = { 18 },
}
S.GROUP_SLOTS = GROUP_SLOTS
local worn = {} -- [group] = { score, empty }

-- What you wear in an inventory slot: score, itemID; nil when it's empty.
function S:SlotScore(slotID)
    local itemID = GetInventoryItemID("player", slotID)
    if not itemID then return nil end
    return (self:Score(itemID)), itemID
end

-- The slot most likely to have an upgrade: an empty slot first, else the
-- one whose worn item scores lowest for your stat priority. Off Hand is
-- skipped while you wield a two-hander; slots whose worn item isn't loaded
-- yet are skipped. Nil when nothing can be scored.
function S:WeakestSlot()
    local main = GetInventoryItemID("player", 16)
    -- ns:Instant: this client has only C_Item.GetItemInfoInstant, no global.
    local twoHanded = main and ns:Instant(main) == "INVTYPE_2HWEAPON"
    local best, bestScore
    for _, group in ipairs(ns.Data.SLOT_GROUPS) do
        local key = group[1]
        local slots = GROUP_SLOTS[key]
        if slots and not (key == "OFFHAND" and twoHanded) then
            local lowest, known = nil, true
            for _, slot in ipairs(slots) do
                local itemID = GetInventoryItemID("player", slot)
                if not itemID then
                    return key -- an empty slot: anything is an upgrade
                elseif ns:Peek(itemID) then
                    local score = self:Score(itemID)
                    if not lowest or score < lowest then lowest = score end
                else
                    known = false
                end
            end
            if known and lowest and (not bestScore or lowest < bestScore) then
                best, bestScore = key, lowest
            end
        end
    end
    return best
end

local wornIDs -- [itemID] = true for what you wear

function S:EquipmentChanged()
    wipe(worn)
    wornIDs = nil
end

-- Are you wearing this item?
function S:IsWorn(itemID)
    if not wornIDs then
        wornIDs = {}
        for slot = 1, 19 do
            local id = GetInventoryItemID("player", slot)
            if id then wornIDs[id] = true end
        end
    end
    return wornIDs[itemID] or false
end

-- The score of what you wear in a slot group (the weaker one for rings and
-- trinkets), and whether a slot in it is empty.
function S:EquippedScore(group)
    local cached = worn[group]
    if cached then return cached[1], cached[2] end
    local slots = GROUP_SLOTS[group]
    if not slots then return 0, false end
    local lowest, empty, loading = nil, false, false
    for _, slot in ipairs(slots) do
        local itemID = GetInventoryItemID("player", slot)
        if itemID then
            if not ns:Info(itemID) then loading = true end
            local score = self:Score(itemID)
            if not lowest or score < lowest then lowest = score end
        else
            empty = true
        end
    end
    if empty then lowest = 0 end
    if not loading then worn[group] = { lowest or 0, empty } end
    return lowest or 0, empty
end

-- What you wear where an item of this equip location goes, the way Tape Measure compares it:
-- rings, trinkets and dual-wielded one-handers against the weaker, a two-hander against main hand
-- plus off hand. base, empty; nil, why when it can't go on (an off hand under a two-hander) or
-- while a worn item is loading.
function S:WornScore(equipLoc)
    local key = "loc:" .. (equipLoc or "")
    local cached = worn[key]
    if cached then return cached[1], cached[2] end
    local base, empty = GE.Worn(equipLoc, function(slot)
        local itemID = GetInventoryItemID("player", slot)
        if not ns:Info(itemID) then return nil end
        return (self:Score(itemID))
    end)
    if base then worn[key] = { base, empty } end
    return base, empty
end

-- Whether an item scoring score beats what you wear: upgrade (true for "upgrade" or "new"), the
-- engine's verdict, and the worn score. Nil verdict while it can't be told.
function S:Beats(itemID, score, equipLoc)
    equipLoc = equipLoc or ns:Instant(itemID)
    local base, empty = self:WornScore(equipLoc)
    if not base then return false, nil, nil end
    local verdict = GE.Verdict(score, base, empty)
    return verdict == "upgrade" or verdict == "new", verdict, base, empty
end

function S:HasStatLedger() return GE.HasStatLedger() end

function S:Weights()
    if not weights then weights = GE.Weights() end
    return weights
end

function S:Label(stat)
    if StatLedger and StatLedger.GetStatLabel then return StatLedger:GetStatLabel(stat) end
    return stat
end

-- "Mage: Fire  Spell Power > Fire Spell Power > ..."
function S:Describe()
    if not self:HasStatLedger() then
        return "Install StatLedger to rank items by your spec's stats."
    end
    local class, _, specName = StatLedger:GetActiveSpec()
    local who = StatLedger:GetClassName(class or "?") .. ": " .. (specName or "?")
    return "|cffffd100" .. who .. "|r  " .. StatLedger:Describe()
end

-- Effects on "Equip:" lines (spell power, crit, hit, mp5, ...).
local function EquipStats(itemID, out)
    local f = ns.Usability:Facts(itemID)
    if not f then return end
    for _, text in ipairs(f.effects) do GE.EquipLine(text, out) end
end

-- { [stat] = amount } in StatLedger's stat keys. GetItemStats and the
-- "Equip:" lines can report the same effect, so the larger of the two counts.
function S:ItemStats(itemID)
    local cached = itemStats[itemID]
    if cached then return cached end
    local info = ns:Peek(itemID)
    if not info then return nil end
    -- Not loaded yet: the stats in the shipped item data.
    -- Not cached, so the game's own details count once they arrive.
    if info.baked then
        local s = ns:Shipped(itemID)
        return s and s.stats or {}
    end

    local fromText = {}
    EquipStats(itemID, fromText)
    local stats = GE.Merge(GE.ApiStats(info.link), fromText)
    itemStats[itemID] = stats
    return stats
end

-- score, top: top is up to three { stat, amount } that count most, best first.
function S:Score(itemID)
    local cached = scores[itemID]
    if cached then return cached[1], cached[2] end
    local info = ns:Peek(itemID)
    local baked = not info or info.baked
    if baked then
        cached = bakedScores[itemID]
        if cached then return cached[1], cached[2] end
    end
    local stats = self:ItemStats(itemID)
    if not stats then return 0, NO_TOP end
    -- Its stats plus what its effects are worth to you (Effects.lua), priced by StatLedger
    -- (crit for your class and level, and the share each stat earns from what it
    -- produces), the same prices Tape Measure uses.
    local values = {}
    for stat, amount in pairs(stats) do values[stat] = amount end
    for stat, amount in pairs((ns.Effects:Stats(itemID))) do values[stat] = (values[stat] or 0) + amount end
    local score, contrib = GE.ScoreValues(values)
    local parts = {}
    for stat, value in pairs(contrib) do
        if value > 0 then parts[#parts + 1] = { stat, values[stat], value } end
    end
    table.sort(parts, function(a, b) return a[3] > b[3] end)
    local top = {}
    for i = 1, math.min(3, #parts) do top[i] = { parts[i][1], parts[i][2] } end
    if baked then bakedScores[itemID] = { score, top } else scores[itemID] = { score, top } end
    return score, top
end

-- "+12 Spell Power, +8 Intellect"
function S:TopText(top)
    local out = {}
    for i, part in ipairs(top) do
        local amount = part[2]
        local text = (amount % 1 == 0) and tostring(amount) or string.format("%.1f", amount)
        out[i] = "+" .. text .. " " .. self:Label(part[1])
    end
    return table.concat(out, ", ")
end
