local _, ns = ...

-- Puts on an upgrade as soon as it lands in your bags (loot, a quest reward, something bought): when
-- the shared GearEngine.lua calls it an upgrade over what you wear (your StatLedger stat priority, the
-- same verdict SpyGlass's lists and the character tab show), or it fills an empty slot. Only items
-- that are already soulbound: a Bind on Equip piece, or one that never binds (vendor gear), is never
-- put on (it may be worth more sold or traded, and putting a BoE on binds it). Only Poor (gray) and Common (white) items: anything
-- Uncommon (green) or better is yours to decide, so it stays in your bags. Out of combat (it waits for
-- combat to end) and alive.
--
-- Only new arrivals: what was in your bags at login, and anything you wore, are left alone, so taking
-- a piece off on purpose doesn't put it back on. A fishing pole in your hands stands in for your
-- weapons (Bandolier puts them back): no weapon goes on over it.
--
-- db.autoEquip (on unless set false; Options > AddOns > SpyGlass).
local A = {}
ns.AutoEquip = A

local E, I = ns.GearEngine, ns.Items
local MAX_QUALITY = (Enum and Enum.ItemQuality and Enum.ItemQuality.Common) or 1 -- white: the best it may put on
local MAIN_HAND = INVSLOT_MAINHAND or 16
local FISHING_POLE = 20 -- the weapon subclass
local WEAPON_SLOTS = { [16] = true, [17] = true, [18] = true }
local RETRY, TRIES = 1, 10 -- seconds between looks while item data loads, and how many

local known = {}     -- item links already yours before they could be "new": never put on by this
local worn = {}      -- slot -> link worn now (what comes off becomes known)
local ready = false  -- the login snapshot is taken

local function On() return ns.db and ns.db.autoEquip ~= false end

local function Wear()
    for slot = 1, 19 do
        local link = GetInventoryItemLink("player", slot)
        worn[slot] = link
        if link then known[link] = true end
    end
end

local function HoldingPole()
    local id = GetInventoryItemID("player", MAIN_HAND)
    if not id then return false end
    local _, _, _, _, _, classID, subClassID = I.GetItemInfoInstant(id)
    return classID == I.CLASS.WEAPON and subClassID == FISHING_POLE
end

-- Where an item would go (the weaker of two ring or trinket slots, as the verdict compares), or nil.
local function SlotFor(link)
    local loc = E.EquipLoc(link)
    if not loc then return nil end
    local _, _, _, target = E.Worn(loc, function(slot)
        local s = E.Score(GetInventoryItemLink("player", slot))
        return s and s.total
    end)
    return target and target.slots[1]
end

-- One bag item: "wear", slot, cmp; "no" (never: remember it); nil (not now: loading, combat, a pole).
local function Judge(bag, slot, info)
    if info.locked then return nil end
    -- Gray and white only: green and better are worth more, and putting one on is your call.
    local quality = select(3, I.GetItemInfo(info.link))
    if quality == nil then return "loading" end
    if quality > MAX_QUALITY then return "no" end
    local cmp = E.Compare(info.link)
    if not cmp then
        return E.EquipLoc(info.link) and E.SLOT_MAP[E.EquipLoc(info.link)] and "loading" or "no"
    end
    if cmp.verdict ~= "upgrade" and cmp.verdict ~= "new" then return "no" end
    if cmp.reqLevel or cmp.uniqueWorn or (cmp.info and cmp.info.unusable) then return nil end
    -- Soulbound only: Bind on Equip pieces and items that never bind (vendor gear) can be sold or
    -- traded, so putting them on is your call.
    local bound = info.bound
    if bound == nil then bound = I.IsSlotBound(bag, slot) end
    if not bound then return "no" end
    local target = SlotFor(info.link)
    if not target then return nil end
    if WEAPON_SLOTS[target] and HoldingPole() then return nil end
    return "wear", target, cmp
end

local tries = 0
function A:Scan()
    if not (ready and On()) then return end
    if InCombatLockdown() or UnitIsDeadOrGhost("player") then return end
    local loading = false
    for bag, slot, info in I.IterateBags() do
        if not known[info.link] then
            local verdict, target, cmp = Judge(bag, slot, info)
            if verdict == "no" then
                known[info.link] = true
            elseif verdict == "loading" then
                loading = true
            elseif verdict == "wear" then
                known[info.link] = true
                if not I.EquipItemByName(info.link, target) then return end
                local gain = cmp.verdict == "new" and "an empty slot"
                    or (cmp.percent and ("+%.0f%%"):format(cmp.percent)) or "an upgrade"
                ns:Print(("Put on %s (%s, %s)."):format(info.link, E.SLOT_NAMES[target] or "?", gain))
                return -- one at a time: the bag update after it brings the next look
            end
        end
    end
    if loading and tries < TRIES then
        tries = tries + 1
        C_Timer.After(RETRY, function() A:Scan() end)
    else
        tries = 0
    end
end

-- What comes off (changed slots' old items) is known before the bags are looked at.
local function EquipmentChanged()
    for slot = 1, 19 do
        local old = worn[slot]
        if old then known[old] = true end
    end
    Wear()
end

local soon = false
local function ScanSoon()
    if soon then return end
    soon = true
    C_Timer.After(0.3, function() soon = false; A:Scan() end)
end

ns:On("PLAYER_LOGIN", function()
    C_Timer.After(3, function()
        -- Everything you have at login is yours already: only what arrives from now on.
        for _, _, info in I.IterateBags() do known[info.link] = true end
        Wear()
        ready = true
    end)
end)
ns:On("BAG_UPDATE_DELAYED", ScanSoon)
ns:On("PLAYER_EQUIPMENT_CHANGED", function() EquipmentChanged(); ScanSoon() end)
ns:On("PLAYER_REGEN_ENABLED", ScanSoon)
ns:On("PLAYER_UNGHOST", ScanSoon)
ns:On("PLAYER_ALIVE", ScanSoon)
