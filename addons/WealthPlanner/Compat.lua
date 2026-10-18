local _, ns = ...

-- Normalizes item and bag APIs across clients that do or don't have C_Item / C_Container
-- (Quartermaster's Compat.lua plus Wally's bag helpers).
local Compat = {}
ns.Compat = Compat

local CI = C_Item
local CC = C_Container

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

function Compat.RequestItem(id)
    if id and CI and CI.RequestLoadItemDataByID then CI.RequestLoadItemDataByID(id) end
end

function Compat.GetClassName(classID)
    local fn = (CI and CI.GetItemClassInfo) or GetItemClassInfo
    return fn and fn(classID)
end

function Compat.GetSubClassName(classID, subClassID)
    local fn = (CI and CI.GetItemSubClassInfo) or GetItemSubClassInfo
    return fn and fn(classID, subClassID)
end

function Compat.Money(copper)
    copper = math.floor(tonumber(copper) or 0)
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then return C_CurrencyInfo.GetCoinTextureString(copper) end
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    return GetMoneyString(copper)
end

-- Item name from a hyperlink; available even before GetItemInfo is cached.
function Compat.NameFromLink(link)
    return link and link:match("|h%[(.-)%]|h")
end

function Compat.IDFromLink(link)
    return link and tonumber(link:match("item:(%d+)"))
end

Compat.NUM_BAGS = NUM_BAG_SLOTS or 4
Compat.NUM_REAGENT_BAGS = NUM_REAGENTBAG_SLOTS or 0

function Compat.GetNumSlots(bag)
    if CC and CC.GetContainerNumSlots then return CC.GetContainerNumSlots(bag) or 0 end
    return GetContainerNumSlots(bag) or 0
end

function Compat.GetSlotLink(bag, slot)
    if CC and CC.GetContainerItemLink then return CC.GetContainerItemLink(bag, slot) end
    return GetContainerItemLink(bag, slot)
end

-- Returns a table { link, count, locked, quality, id, icon, noValue } or nil.
function Compat.GetSlotInfo(bag, slot)
    if CC and CC.GetContainerItemInfo then
        local i = CC.GetContainerItemInfo(bag, slot)
        if not i then return nil end
        return { link = i.hyperlink, count = i.stackCount or 1, locked = i.isLocked, quality = i.quality,
            id = i.itemID, icon = i.iconFileID, noValue = i.hasNoValue, bound = i.isBound, bag = bag, slot = slot }
    end
    local icon, count, locked, quality, _, _, link, _, noValue, id = GetContainerItemInfo(bag, slot)
    if not icon then return nil end
    return { link = link, count = count or 1, locked = locked, quality = quality, id = id, icon = icon, noValue = noValue,
        bag = bag, slot = slot }
end

Compat.BANK = BANK_CONTAINER or -1
Compat.NUM_BANK_BAGS = NUM_BANKBAGSLOTS or 6

-- "bags": backpack and bags. "reagent": the reagent bag, if the client has one.
-- "bank": the bank's own slots and its bags.
function Compat.BagList(which)
    local list = {}
    if which == "reagent" then
        for b = Compat.NUM_BAGS + 1, Compat.NUM_BAGS + Compat.NUM_REAGENT_BAGS do list[#list + 1] = b end
    elseif which == "bank" then
        list[1] = Compat.BANK
        for b = Compat.NUM_BAGS + 1, Compat.NUM_BAGS + Compat.NUM_BANK_BAGS do list[#list + 1] = b end
    else
        for b = 0, Compat.NUM_BAGS do list[#list + 1] = b end
    end
    return list
end

-- Iterates every bag slot that holds an item: for bag, slot, info in Compat.IterateBags() do ... end
-- Takes an optional list of bag IDs; the default is the backpack and bags.
function Compat.IterateBags(bags)
    bags = bags or Compat.BagList("bags")
    if not bags[1] then return function() end end
    local i, slot, num = 1, 0, Compat.GetNumSlots(bags[1])
    return function()
        while true do
            slot = slot + 1
            if slot > num then
                i, slot = i + 1, 1
                if not bags[i] then return end
                num = Compat.GetNumSlots(bags[i])
            end
            if slot <= num then
                local info = Compat.GetSlotInfo(bags[i], slot)
                if info and info.link then return bags[i], slot, info end
            end
        end
    end
end
