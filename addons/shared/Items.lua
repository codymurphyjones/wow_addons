local addonName, ns = ...

-- Items and bags (addons/shared): the C_Item / C_Container calls, each behind a guard that falls
-- back to the old global. The guards stay because no code in this repo calls those C_ functions
-- unguarded, so their presence on WoW Forever isn't confirmed. Built from Wally's Compat.lua, with WealthPlanner's
-- bound flag, TapeMeasure's ask-once item requests and link-shaped bag walk, Quartermaster's item
-- class names, Bandolier's and SimplePanel's counts, cooldowns, icons and use spells.
--
-- Reads that can come back secret on WoW Forever (counts, cooldowns) go through Readable, so they
-- answer 0 / nil instead of erroring. IsSlotBound's tooltip fallback uses ns.Tooltip (shared
-- Tooltip.lua) when the addon loads it, else a scan tooltip of its own.
local I = {}
ns.Items = I

local CC = C_Container
local CI = C_Item

local function Readable(v)
    if v == nil then return nil end
    if canaccessvalue and not canaccessvalue(v) then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
local function Num(v) v = Readable(v); return type(v) == "number" and v or nil end

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

I.NUM_BAGS = NUM_BAG_SLOTS or 4
I.NUM_REAGENT_BAGS = NUM_REAGENTBAG_SLOTS or 0
I.BANK = BANK_CONTAINER or -1
I.NUM_BANK_BAGS = NUM_BANKBAGSLOTS or 6

-- Item IDs the addons name.
I.ITEMS = { HEARTHSTONE = 6948 }

-- Item class IDs (GetItemInfoInstant's 6th return), from Enum.ItemClass when it's there.
local ItemClass = Enum and Enum.ItemClass or {}
I.CLASS = {
    CONSUMABLE = ItemClass.Consumable or 0,
    CONTAINER = ItemClass.Container or 1,
    WEAPON = ItemClass.Weapon or 2,
    GEM = ItemClass.Gem or 3,
    ARMOR = ItemClass.Armor or 4,
    REAGENT = ItemClass.Reagent or 5,
    PROJECTILE = ItemClass.Projectile or 6,
    TRADEGOODS = ItemClass.Tradegoods or 7,
    ENHANCEMENT = ItemClass.ItemEnhancement or 8,
    RECIPE = ItemClass.Recipe or 9,
    QUIVER = ItemClass.Quiver or 11,
    QUEST = ItemClass.Questitem or 12,
    KEY = ItemClass.Key or 13,
    MISCELLANEOUS = ItemClass.Miscellaneous or 15,
    GLYPH = ItemClass.Glyph or 16,
}

-- ---------------------------------------------------------------------------
-- Item info
-- ---------------------------------------------------------------------------

-- name, link, quality, ilvl, reqLevel, class, subclass, maxStack, equipLoc, texture, sellPrice, classID, subclassID
function I.GetItemInfo(item)
    if CI and CI.GetItemInfo then return CI.GetItemInfo(item) end
    return GetItemInfo(item)
end

-- itemID, type, subType, equipLoc, icon, classID, subclassID
function I.GetItemInfoInstant(item)
    if CI and CI.GetItemInfoInstant then return CI.GetItemInfoInstant(item) end
    if GetItemInfoInstant then return GetItemInfoInstant(item) end
end

-- "INVTYPE_HEAD" and the like, or nil.
function I.EquipLoc(item)
    if not item then return nil end
    local _, _, _, equipLoc = I.GetItemInfoInstant(item)
    return equipLoc
end

-- GetItemStats' table, or nil (no API, no link, or it errored).
function I.GetItemStats(link)
    local fn = (CI and CI.GetItemStats) or GetItemStats
    if not fn or not link then return nil end
    local ok, stats = pcall(fn, link)
    if ok then return stats end
end

function I.IsEquippableItem(item)
    if CI and CI.IsEquippableItem then return CI.IsEquippableItem(item) end
    if IsEquippableItem then return IsEquippableItem(item) end
end

-- Name and ID of the spell the item casts on use, or nil if it has no use effect.
function I.ItemSpell(item)
    local fn = (CI and CI.GetItemSpell) or GetItemSpell
    if fn and item then return fn(item) end
end

-- Whether you can use it now; true when there's no API to ask.
function I.IsUsableItem(item)
    local fn = (CI and CI.IsUsableItem) or IsUsableItem
    if not fn then return true end
    return (fn(item)) and true or false
end

function I.ItemIcon(id)
    if not id then return nil end
    local fn = (CI and CI.GetItemIconByID) or GetItemIcon
    local icon = fn and fn(id)
    if icon then return icon end
    return (select(10, I.GetItemInfo(id)))
end

-- How many you carry: bank = true counts the bank too; charges counts charges instead of items.
-- 0 when there's no API to ask (or the answer is secret).
function I.ItemCount(item, bank, charges, reagentBank)
    local fn = (CI and CI.GetItemCount) or GetItemCount
    if not (fn and item) then return 0 end
    local ok, n = pcall(fn, item, bank, charges, reagentBank)
    return ok and Num(n) or 0
end

-- start, duration, enable; 0, 0 while ready or unreadable.
function I.ItemCooldown(item)
    local fn = (CC and CC.GetItemCooldown) or GetItemCooldown
    if not (fn and item) then return 0, 0 end
    local ok, start, duration, enable = pcall(fn, item)
    if not ok then return 0, 0 end
    return Num(start) or 0, Num(duration) or 0, Readable(enable)
end

function I.GetClassName(classID)
    local fn = (CI and CI.GetItemClassInfo) or GetItemClassInfo
    return fn and fn(classID)
end

function I.GetSubClassName(classID, subClassID)
    local fn = (CI and CI.GetItemSubClassInfo) or GetItemSubClassInfo
    return fn and fn(classID, subClassID)
end

function I.GetItemFamily(item)
    local fn = (CI and CI.GetItemFamily) or GetItemFamily
    if not fn or not item then return 0 end
    local ok, family = pcall(fn, item)
    return ok and family or 0
end

-- ---------------------------------------------------------------------------
-- Links
-- ---------------------------------------------------------------------------

-- The item ID in a link or "item:123" string; a number comes back as it is.
function I.IDFromLink(link)
    if type(link) == "number" then return link end
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

-- Item name from a hyperlink; available even before GetItemInfo is cached.
function I.NameFromLink(link)
    return type(link) == "string" and link:match("|h%[(.-)%]|h") or nil
end

-- Asks the client to load an item (GET_ITEM_INFO_RECEIVED follows), once per item until
-- ResetRequests; again = true asks even so. Takes an ID or a link.
local requested = {}
function I.RequestItem(item, again)
    local id = I.IDFromLink(item)
    if not id or (requested[id] and not again) then return end
    requested[id] = true
    if CI and CI.RequestLoadItemDataByID then pcall(CI.RequestLoadItemDataByID, id) end
end

-- Lets every item be asked for again (a rescan).
function I.ResetRequests() wipe(requested) end

-- ---------------------------------------------------------------------------
-- Bags
-- ---------------------------------------------------------------------------

function I.GetNumSlots(bag)
    if CC and CC.GetContainerNumSlots then return CC.GetContainerNumSlots(bag) or 0 end
    return GetContainerNumSlots(bag) or 0
end

-- free, family (0 = a normal bag)
function I.GetFreeSlots(bag)
    local free, family
    if CC and CC.GetContainerNumFreeSlots then free, family = CC.GetContainerNumFreeSlots(bag)
    else free, family = GetContainerNumFreeSlots(bag) end
    return free or 0, family or 0
end

-- 0 for a normal bag; a bit mask for quivers, ammo pouches, soul bags and the like.
function I.GetBagFamily(bag)
    local _, family = I.GetFreeSlots(bag)
    return family
end

-- The bag's name; the backpack's is the game's "Backpack" when the API gives none.
function I.GetBagName(bag)
    local fn = (CC and CC.GetBagName) or GetBagName
    local name
    if fn then
        local ok, n = pcall(fn, bag)
        if ok then name = n end
    end
    if not name and bag == 0 then return BACKPACK_TOOLTIP or "Backpack" end
    return name
end

function I.GetSlotLink(bag, slot)
    if CC and CC.GetContainerItemLink then return CC.GetContainerItemLink(bag, slot) end
    return GetContainerItemLink(bag, slot)
end

-- { link, count, locked, quality, id, icon, noValue, bound, lootable, bag, slot } or nil.
-- bound comes from C_Container's info (nil from the old global's: ask IsSlotBound).
function I.GetSlotInfo(bag, slot)
    if CC and CC.GetContainerItemInfo then
        local i = CC.GetContainerItemInfo(bag, slot)
        if not i then return nil end
        return { link = i.hyperlink, count = i.stackCount or 1, locked = i.isLocked, quality = i.quality,
            id = i.itemID, icon = i.iconFileID, noValue = i.hasNoValue, bound = i.isBound, lootable = i.hasLoot,
            bag = bag, slot = slot }
    end
    local icon, count, locked, quality, _, lootable, link, _, noValue, id = GetContainerItemInfo(bag, slot)
    if not icon then return nil end
    return { link = link, count = count or 1, locked = locked, quality = quality, id = id, icon = icon, noValue = noValue,
        lootable = lootable, bag = bag, slot = slot }
end

-- Whether the item in a bag slot is soulbound: C_Item.IsBound, else its tooltip's lines.
local bindScanner
local function TooltipBound(bag, slot)
    local T = ns.Tooltip
    if T and T.Lines and T.Soulbound then return T.Soulbound(T.Lines("bag", bag, slot)) end
    local name = addonName .. "ItemsBindTooltip"
    bindScanner = bindScanner or CreateFrame("GameTooltip", name, nil, "GameTooltipTemplate")
    bindScanner:SetOwner(WorldFrame, "ANCHOR_NONE")
    bindScanner:ClearLines()
    pcall(bindScanner.SetBagItem, bindScanner, bag, slot)
    local bound = false
    for i = 2, math.min(6, bindScanner:NumLines()) do
        local fs = _G[name .. "TextLeft" .. i]
        if fs and fs:GetText() == ITEM_SOULBOUND then bound = true break end
    end
    bindScanner:Hide()
    return bound
end

function I.IsSlotBound(bag, slot)
    if CI and CI.IsBound and ItemLocation then
        local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
        if CI.DoesItemExist and not CI.DoesItemExist(loc) then return false end
        local ok, bound = pcall(CI.IsBound, loc)
        if ok then return bound and true or false end
    end
    return TooltipBound(bag, slot)
end

-- Item link at an ItemLocation (needs C_Item.DoesItemExist and GetItemLink), or nil.
function I.LinkFromLocation(location)
    if not (location and CI and CI.DoesItemExist and CI.GetItemLink) then return nil end
    local ok, exists = pcall(CI.DoesItemExist, location)
    if not ok or not exists then return nil end
    return CI.GetItemLink(location)
end

function I.UseContainerItem(bag, slot)
    if CC and CC.UseContainerItem then return CC.UseContainerItem(bag, slot) end
    return UseContainerItem(bag, slot)
end

-- Hooks the function used to sell/use bag items, on whichever table owns it.
function I.HookUseContainerItem(fn)
    if CC and CC.UseContainerItem then hooksecurefunc(CC, "UseContainerItem", fn)
    else hooksecurefunc("UseContainerItem", fn) end
end

function I.PickupItem(bag, slot)
    if CC and CC.PickupContainerItem then return CC.PickupContainerItem(bag, slot) end
    return PickupContainerItem(bag, slot)
end

-- "bags": backpack and bags. "reagent": the reagent bag (none when NUM_REAGENTBAG_SLOTS is unset).
-- "bank": the bank's own slots and its bags.
function I.BagList(which)
    local list = {}
    if which == "reagent" then
        for b = I.NUM_BAGS + 1, I.NUM_BAGS + I.NUM_REAGENT_BAGS do list[#list + 1] = b end
    elseif which == "bank" then
        list[1] = I.BANK
        for b = I.NUM_BAGS + 1, I.NUM_BAGS + I.NUM_BANK_BAGS do list[#list + 1] = b end
    else
        for b = 0, I.NUM_BAGS do list[#list + 1] = b end
    end
    return list
end

-- Every bag slot that holds an item:
--   for bag, slot, info in Items.IterateBags() do ... end          (info = GetSlotInfo's table)
--   for bag, slot, link in Items.IterateBags(nil, "link") do ... end (just the link: cheaper)
-- bags is a list of bag IDs (BagList's); the default is the backpack and bags.
function I.IterateBags(bags, shape)
    bags = bags or I.BagList("bags")
    if not bags[1] then return function() end end
    local byLink = shape == "link"
    local i, slot, num = 1, 0, I.GetNumSlots(bags[1])
    return function()
        while true do
            slot = slot + 1
            if slot > num then
                i, slot = i + 1, 1
                if not bags[i] then return end
                num = I.GetNumSlots(bags[i])
            end
            if slot <= num then
                if byLink then
                    local link = I.GetSlotLink(bags[i], slot)
                    if link then return bags[i], slot, link end
                else
                    local info = I.GetSlotInfo(bags[i], slot)
                    if info and info.link then return bags[i], slot, info end
                end
            end
        end
    end
end
