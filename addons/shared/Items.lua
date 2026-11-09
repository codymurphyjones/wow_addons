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
-- The bank on WoW Forever: up to 9 tabs, bags 6-14 (Enum.BagIndex.CharacterBankTab_1...). A tab
-- not bought yet has no slots. (There's no bank container: bag -1 is the keyring.)
local BI = Enum and Enum.BagIndex
I.BANK_TABS = {}
for i = 1, 9 do I.BANK_TABS[i] = (BI and BI["CharacterBankTab_" .. i]) or (5 + i) end

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
-- Merchant
-- ---------------------------------------------------------------------------

-- The open merchant's item at index: price (copper for the whole stack), stack size, and whether
-- it also costs items or currency. The 12.x engine has C_MerchantFrame.GetItemInfo (a table) in
-- place of the old global GetMerchantItemInfo. Nil when neither answers.
function I.MerchantItemInfo(index)
    local MF = C_MerchantFrame
    if MF and MF.GetItemInfo then
        local info = MF.GetItemInfo(index)
        if type(info) ~= "table" then return nil end
        return Num(info.price), Num(info.stackCount), Readable(info.hasExtendedCost) and true or false
    end
    if GetMerchantItemInfo then
        local _, _, price, quantity, _, _, _, extendedCost = GetMerchantItemInfo(index)
        return Num(price), Num(quantity), Readable(extendedCost) and true or false
    end
    return nil
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

-- A profession bag's family from the bag item itself: its item family, else its subclass
-- (Container: 1 soul, 2 herb, 3 enchanting, 4 engineering, 5 gem, 6 mining, 7 leatherworking,
-- 8 inscription). 0 for a normal bag, the backpack and reagent bags. Cached per bag item.
local SUBCLASS_FAMILY = { [1] = 4, [2] = 32, [3] = 64, [4] = 128, [5] = 512, [6] = 1024, [7] = 8, [8] = 16 }
local itemBagFamily = {}
function I.BagItemFamily(bag)
    if type(bag) ~= "number" or bag < 1 or bag > I.NUM_BAGS then return 0 end
    local toInv = (CC and CC.ContainerIDToInventoryID) or ContainerIDToInventoryID
    if not toInv then return 0 end
    local ok, inv = pcall(toInv, bag)
    local id = ok and inv and GetInventoryItemID("player", inv)
    if not id then return 0 end
    local fam = itemBagFamily[id]
    if fam then return fam end
    fam = I.GetItemFamily(id)
    if type(fam) ~= "number" or fam <= 0 then
        local _, _, _, _, _, classID, subClassID = I.GetItemInfoInstant(id)
        fam = (classID == I.CLASS.CONTAINER and SUBCLASS_FAMILY[subClassID]) or 0
    end
    itemBagFamily[id] = fam
    return fam
end

-- free, family (0 = a normal bag). The client doesn't always say a bag's family with its free
-- slots; read as 0, a herb bag looked like a normal one, and sorting or emptying a bag kept
-- trying to put anything in it (the game refusing each time). So with none given, the bag item's
-- own family is used (BagItemFamily).
function I.GetFreeSlots(bag)
    local free, family
    if CC and CC.GetContainerNumFreeSlots then free, family = CC.GetContainerNumFreeSlots(bag)
    else free, family = GetContainerNumFreeSlots(bag) end
    if not family or family == 0 then family = I.BagItemFamily(bag) end
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

-- ---------------------------------------------------------------------------
-- Quest items
-- ---------------------------------------------------------------------------

-- Names of the items your active quests ask for ("Cactus Apple"), lower case. Rebuilt after
-- QUEST_LOG_UPDATE; built on first use.
local questNeeds
local function ObjectiveItem(text, objType)
    if type(text) ~= "string" or (objType and objType ~= "item") then return nil end
    local name = text:match("^(.-):%s*%d+%s*/%s*%d+") or text:match("^%d+%s*/%s*%d+%s+(.+)$")
    return name and name:lower()
end
local function BuildQuestNeeds()
    questNeeds = {}
    local QL = C_QuestLog
    local count = (QL and QL.GetNumQuestLogEntries and QL.GetNumQuestLogEntries())
        or (GetNumQuestLogEntries and GetNumQuestLogEntries()) or 0
    for i = 1, count do
        local n = GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(i) or 0
        for j = 1, n do
            local ok, text, objType = pcall(GetQuestLogLeaderBoard, j, i)
            local name = ok and ObjectiveItem(text, objType)
            if name then questNeeds[name] = true end
        end
        if n == 0 and QL and QL.GetInfo and QL.GetQuestObjectives then
            local info = QL.GetInfo(i)
            local objectives = info and info.questID and not info.isHeader and QL.GetQuestObjectives(info.questID)
            for _, o in ipairs(objectives or {}) do
                local name = ObjectiveItem(o.text, o.type)
                if name then questNeeds[name] = true end
            end
        end
    end
    return questNeeds
end
local questFrame = CreateFrame("Frame")
questFrame:RegisterEvent("QUEST_LOG_UPDATE")
questFrame:SetScript("OnEvent", function() questNeeds = nil end)

-- Whether you're on a quest that needs this item, from ns.QUEST_ITEMS (shared QuestItems.lua,
-- built from QuestieDB) when the addon loads it. IsOnQuest asks by quest ID, so collapsed headers
-- in the quest log don't hide anything.
local function OnQuestFor(link)
    local needs = ns.QUEST_ITEMS
    local isOn = C_QuestLog and C_QuestLog.IsOnQuest
    local id = needs and isOn and I.IDFromLink(link)
    local quests = id and needs[id]
    if not quests then return false end
    for _, questID in ipairs(quests) do
        local ok, on = pcall(isOn, questID)
        if ok and on == true then return true end
    end
    return false
end

-- Whether an item is for a quest, and why: its class is Quest, it's quest-bound ("Quest Item"
-- on the tooltip), the bag says it's a quest item, you're on a quest QuestItems.lua says needs it,
-- or an active quest asks for it by name (read from the quest log: the fallback for items the
-- data lacks). bag and slot are optional.
function I.IsQuestItem(link, bag, slot)
    if not link then return false end
    if OnQuestFor(link) then return true, "Needed for a quest" end
    local name, _, _, _, _, _, _, _, _, _, _, classID, _, bindType = I.GetItemInfo(link)
    if not classID then
        local _
        _, _, _, _, _, classID = I.GetItemInfoInstant(link)
    end
    if classID == I.CLASS.QUEST then return true, "Quest item" end
    if bindType == ((Enum and Enum.ItemBind and Enum.ItemBind.Quest) or 4) then return true, "Quest item" end
    if bag and slot then
        local fn = (CC and CC.GetContainerItemQuestInfo) or GetContainerItemQuestInfo
        if fn then
            local ok, a, b = pcall(fn, bag, slot)
            if ok then
                local isQuest, questID = a, b
                if type(a) == "table" then isQuest, questID = a.isQuestItem, a.questID end
                if isQuest or questID then return true, "Quest item" end
            end
        end
    end
    name = name or I.NameFromLink(link)
    if name and (questNeeds or BuildQuestNeeds())[name:lower()] then return true, "Needed for a quest" end
    return false
end

-- Item link at an ItemLocation (needs C_Item.DoesItemExist and GetItemLink), or nil.
function I.LinkFromLocation(location)
    if not (location and CI and CI.DoesItemExist and CI.GetItemLink) then return nil end
    local ok, exists = pcall(CI.DoesItemExist, location)
    if not ok or not exists then return nil end
    return CI.GetItemLink(location)
end

-- Bag items right-clicked (used, sold at a vendor, equipped): fn(bag, slot) for each, just after.
-- Not a hook on UseContainerItem itself: on the 12.x engine a hooked UseContainerItem is the
-- hooking addon's, so every item used from the bags, the game's own included, was blocked
-- ("Wally tried to call the protected function UNKNOWN()"). The clicks are followed instead, on
-- the game's bag buttons (HookScript runs after the game's own click, which stays the game's),
-- plus I.UseContainerItem's own calls and any addon button that reports with I.BagItemUsed.
local usedFns, hookedButtons = {}, setmetatable({}, { __mode = "k" })

function I.BagItemUsed(bag, slot)
    for _, fn in ipairs(usedFns) do
        local ok, err = pcall(fn, bag, slot)
        if not ok then geterrorhandler()(err) end
    end
end

local function OnItemButtonClick(self, button)
    if button ~= "RightButton" or IsModifiedClick() then return end
    local ok, bag = pcall(self.GetBagID, self)
    local slot = self.GetID and self:GetID()
    if ok and type(bag) == "number" and type(slot) == "number" then I.BagItemUsed(bag, slot) end
end

local function BagFrames()
    local out = { _G.ContainerFrameCombinedBags }
    for i = 1, NUM_CONTAINER_FRAMES or 13 do out[#out + 1] = _G["ContainerFrame" .. i] end
    return out
end

-- The game makes its bag buttons as its windows need them: new ones are followed when a window
-- lays its buttons out.
-- (Only open windows: one never opened yet can fail partway through its list, and the whole walk
-- is guarded, since this runs while an addon's files load: an error there stopped the file.)
local function FollowButtons(f)
    if not (f and f.EnumerateValidItems and f:IsShown()) then return end
    pcall(function()
        for _, b in f:EnumerateValidItems() do
            if not hookedButtons[b] and b.HookScript then
                hookedButtons[b] = true
                b:HookScript("OnClick", OnItemButtonClick)
            end
        end
    end)
end

function I.OnBagItemUsed(fn)
    usedFns[#usedFns + 1] = fn
    if #usedFns > 1 then return end
    for _, f in pairs(BagFrames()) do
        if f then
            pcall(function()
                if f.UpdateItemLayout then hooksecurefunc(f, "UpdateItemLayout", FollowButtons) end
                f:HookScript("OnShow", FollowButtons)
            end)
            FollowButtons(f)
        end
    end
end

function I.UseContainerItem(bag, slot)
    if CC and CC.UseContainerItem then CC.UseContainerItem(bag, slot)
    else UseContainerItem(bag, slot) end
    I.BagItemUsed(bag, slot)
end

function I.PickupItem(bag, slot)
    if CC and CC.PickupContainerItem then return CC.PickupContainerItem(bag, slot) end
    return PickupContainerItem(bag, slot)
end

-- The global EquipItemByName is gone on WoW Forever (calling it errored); C_Item has it.
-- Answers false when neither exists.
function I.EquipItemByName(item, slot)
    local fn = (CI and CI.EquipItemByName) or EquipItemByName
    if not fn then return false end
    fn(item, slot)
    return true
end

-- "bags": backpack and bags. "reagent": the reagent bag (none when NUM_REAGENTBAG_SLOTS is unset).
-- "bank": the bank's tabs (I.BANK_TABS).
function I.BagList(which)
    local list = {}
    if which == "reagent" then
        for b = I.NUM_BAGS + 1, I.NUM_BAGS + I.NUM_REAGENT_BAGS do list[#list + 1] = b end
    elseif which == "bank" then
        for i, b in ipairs(I.BANK_TABS) do list[i] = b end
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
