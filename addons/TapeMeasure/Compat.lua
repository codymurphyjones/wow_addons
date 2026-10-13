local _, ns = ...

-- Item and container calls for clients with or without C_Item / C_Container (taken from Wally).
local Compat = {}
ns.Compat = Compat

local CC = C_Container
local CI = C_Item

Compat.NUM_BAGS = NUM_BAG_SLOTS or 4

function Compat.GetNumSlots(bag)
    if CC and CC.GetContainerNumSlots then return CC.GetContainerNumSlots(bag) or 0 end
    return GetContainerNumSlots(bag) or 0
end

function Compat.GetSlotLink(bag, slot)
    if CC and CC.GetContainerItemLink then return CC.GetContainerItemLink(bag, slot) end
    return GetContainerItemLink(bag, slot)
end

-- name, link, quality, ilvl, reqLevel, class, subclass, maxStack, equipLoc, texture, sellPrice, classID, subclassID
function Compat.GetItemInfo(item)
    if CI and CI.GetItemInfo then return CI.GetItemInfo(item) end
    return GetItemInfo(item)
end

-- itemID, type, subType, equipLoc, icon, classID, subclassID
function Compat.GetItemInfoInstant(item)
    if CI and CI.GetItemInfoInstant then return CI.GetItemInfoInstant(item) end
    if GetItemInfoInstant then return GetItemInfoInstant(item) end
end

function Compat.GetItemStats(link)
    local fn = (CI and CI.GetItemStats) or GetItemStats
    if not fn or not link then return nil end
    local ok, stats = pcall(fn, link)
    if ok then return stats end
end

function Compat.IsEquippableItem(item)
    if CI and CI.IsEquippableItem then return CI.IsEquippableItem(item) end
    if IsEquippableItem then return IsEquippableItem(item) end
end

-- Asks the client to load an item, once; GET_ITEM_INFO_RECEIVED follows.
local requested = {}
function Compat.RequestItem(id)
    if not id or requested[id] then return end
    requested[id] = true
    if CI and CI.RequestLoadItemDataByID then CI.RequestLoadItemDataByID(id) end
end

-- Lets every item be asked for again (Rescan).
function Compat.ResetRequests() wipe(requested) end

function Compat.IDFromLink(link)
    return link and tonumber(link:match("item:(%d+)"))
end

function Compat.EquipLoc(link)
    if not link then return nil end
    local _, _, _, equipLoc = Compat.GetItemInfoInstant(link)
    return equipLoc
end

function Compat.CanDualWield()
    if IsPlayerSpell then return IsPlayerSpell(674) end
    if IsSpellKnown then return IsSpellKnown(674) end
end

-- Every backpack/bag slot holding an item: for bag, slot, link in Compat.IterateBags() do ... end
function Compat.IterateBags()
    local bag, slot, num = 0, 0, Compat.GetNumSlots(0)
    return function()
        while true do
            slot = slot + 1
            if slot > num then
                bag, slot = bag + 1, 1
                if bag > Compat.NUM_BAGS then return end
                num = Compat.GetNumSlots(bag)
            end
            if slot <= num then
                local link = Compat.GetSlotLink(bag, slot)
                if link then return bag, slot, link end
            end
        end
    end
end
