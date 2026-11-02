"""Wally's grey rule on the real Gear.lua and JunkFilter.lua, with the game stubbed.

    python -I tools/Wally/test_grey.py

Each case: a grey item, what's worn in its slot, and the verdict wanted. Exit code 1 on any failure.
"""
import os
import site
import sys

sys.path.append(site.getusersitepackages())

import lupa.lua51 as L  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WALLY = os.path.join(ROOT, "addons", "Wally")

STUBS = r'''
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
ARMOR_TEMPLATE = "%d Armor"
ITEMS, WORN, LEVEL, EQUIPPED, COMBAT = {}, {}, 10, nil, false
function UnitLevel() return LEVEL end
function UnitIsDeadOrGhost() return false end
function InCombatLockdown() return COMBAT end
function GetInventoryItemLink(_, slot) return WORN[slot] end
function GetInventoryItemID(_, slot) return WORN[slot] and 1 or nil end
function EquipItemByName(link, slot) EQUIPPED = { link, slot } end
ns = { db = { options = { sellGreys = true, wearGreys = true, protectUpgrades = true, sellUnusableBound = true },
              exclusions = {}, inclusions = {}, auctionList = {}, oneOff = {} },
       handlers = {} }
function ns:On(event, fn) self.handlers[event] = fn end
function ns:Print() end
function ns:Changed() end
function ns.Key(name) return name end
ns.Lists = { MatchPattern = function() return nil end }
ns.Value = { IsProtected = function() return nil end }
ns.Player = { Invalidate = function() end, HasEnchanting = function() return false end }
ns.Tooltip = { Lines = function() return {} end, Find = function() end }
local CLASS = { WEAPON = 2, ARMOR = 4, QUEST = 12 }
BAGS = {}
ns.Items = { CLASS = CLASS }
ns.Compat = {
    GetItemInfo = function(link)
        local i = ITEMS[link]
        if not i then return nil end
        return i.name, link, i.q, 1, i.level or 1, "", "", 1, i.loc, 0, i.price or 10, i.class
    end,
    GetItemStats = function(link) return ITEMS[link] and ITEMS[link].stats or nil end,
    NameFromLink = function(link) return link end,
    IsEquippableItem = function(link) return not (ITEMS[link] and ITEMS[link].noequip) end,
    IterateBags = function()
        local i = 0
        return function()
            i = i + 1
            if BAGS[i] then return 0, i, { link = BAGS[i] } end
        end
    end,
}
ns.GearEngine = {
    SLOT_MAP = { INVTYPE_CHEST = { 5 }, INVTYPE_FEET = { 8 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_WEAPONMAINHAND = { 16 },
                 INVTYPE_2HWEAPON = { 16 }, INVTYPE_SHIELD = { 17 } },
    Read = function(link) local i = ITEMS[link]; if not i then return nil end; return {}, { unusable = i.unusable } end,
    Targets = function(loc)
        local out = {}
        for _, s in ipairs(ns.GearEngine.SLOT_MAP[loc] or {}) do out[#out + 1] = { slots = { s } } end
        if #out == 0 then return nil, "not gear" end
        return out
    end,
    Invalidate = function() end,
    Compare = function() return { verdict = "none" } end,
}
function item(link, t) t.name = link; ITEMS[link] = t end
ARMOR = { RESISTANCE0_NAME = 0 }
function armor(n, extra)
    local s = { RESISTANCE0_NAME = n }
    for k, v in pairs(extra or {}) do s[k] = v end
    return s
end
'''

CASES = r'''
local ARMOR_CLASS, WEAPON = 4, 2
local R = {}
local function Case(name, want, grey, worn, setup)
    WORN, EQUIPPED, BAGS, LEVEL = {}, nil, {}, 10
    item("G", grey)
    for slot, w in pairs(worn or {}) do item("W" .. slot, w); WORN[slot] = "W" .. slot end
    if setup then setup() end
    local isJunk, why, verdict = ns.JunkFilter:Evaluate("G", {})
    local got = isJunk and "sell" or (verdict == "upgrade" and "keep" or "other:" .. tostring(verdict))
    R[#R + 1] = { name, want, got, tostring(why) }
end
local chest = { q = 0, class = ARMOR_CLASS, loc = "INVTYPE_CHEST", stats = armor(40) }
Case("more armor than a grey piece", "keep", chest, { [5] = { q = 0, class = ARMOR_CLASS, loc = "INVTYPE_CHEST", stats = armor(20) } })
Case("more armor than a white piece", "keep", chest, { [5] = { q = 1, class = ARMOR_CLASS, loc = "INVTYPE_CHEST", stats = armor(20) } })
Case("same armor", "sell", chest, { [5] = { q = 1, class = ARMOR_CLASS, loc = "INVTYPE_CHEST", stats = armor(40) } })
Case("less armor", "sell", chest, { [5] = { q = 0, class = ARMOR_CLASS, loc = "INVTYPE_CHEST", stats = armor(60) } })
Case("worn white has a stat", "sell", chest, { [5] = { q = 1, class = ARMOR_CLASS, loc = "INVTYPE_CHEST", stats = armor(10, { ITEM_MOD_STAMINA_SHORT = 2 }) } })
Case("worn is green", "sell", chest, { [5] = { q = 2, class = ARMOR_CLASS, loc = "INVTYPE_CHEST", stats = armor(10) } })
Case("empty slot", "keep", chest, {})
Case("can't use it", "sell", { q = 0, class = ARMOR_CLASS, loc = "INVTYPE_CHEST", stats = armor(90), unusable = true }, {})
Case("above your level", "sell", { q = 0, class = ARMOR_CLASS, loc = "INVTYPE_CHEST", stats = armor(90), level = 30 }, {})
Case("not gear", "sell", { q = 0, class = 15, loc = "" }, {})
Case("weapon, more DPS", "keep", { q = 0, class = WEAPON, loc = "INVTYPE_WEAPONMAINHAND", stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 8 } },
    { [16] = { q = 1, class = WEAPON, loc = "INVTYPE_WEAPONMAINHAND", stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 5 } } })
Case("weapon, less DPS", "sell", { q = 0, class = WEAPON, loc = "INVTYPE_WEAPONMAINHAND", stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 3 } },
    { [16] = { q = 1, class = WEAPON, loc = "INVTYPE_WEAPONMAINHAND", stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 5 } } })
Case("ring: beats the weaker of two", "keep", { q = 0, class = ARMOR_CLASS, loc = "INVTYPE_FINGER", stats = armor(5) },
    { [11] = { q = 2, class = ARMOR_CLASS, loc = "INVTYPE_FINGER", stats = armor(1) }, [12] = { q = 1, class = ARMOR_CLASS, loc = "INVTYPE_FINGER", stats = armor(2) } })
Case("Never Sell list wins", "other:keep", { q = 0, class = 15, loc = "" }, {}, function() ns.db.exclusions.G = true end)
ns.db.exclusions.G = nil
Case("sell greys off", "other:none", { q = 0, class = 15, loc = "" }, {}, function() ns.db.options.sellGreys = false end)
ns.db.options.sellGreys = true
Case("white is not touched", "other:none", { q = 1, class = 15, loc = "" }, {})
-- Wearing.
local W = {}
local function Wear(name, want, setup)
    WORN, EQUIPPED, BAGS, COMBAT = {}, nil, { "G" }, false
    item("G", chest)
    item("Old", { q = 0, class = ARMOR_CLASS, loc = "INVTYPE_CHEST", stats = armor(20) }); WORN[5] = "Old"
    if setup then setup() end
    ns.Gear:WearGreys()
    W[#W + 1] = { name, want, EQUIPPED and ("slot " .. tostring(EQUIPPED[2])) or "no" }
end
Wear("better grey goes on", "slot 5")
Wear("not in combat", "no", function() COMBAT = true end)
Wear("option off", "no", function() ns.db.options.wearGreys = false end)
ns.db.options.wearGreys = true
Wear("Never Sell keeps it in the bag", "no", function() ns.db.exclusions.G = true end)
ns.db.exclusions.G = nil
local out, bad = {}, 0
for _, r in ipairs(R) do
    local ok = r[2] == r[3]
    if not ok then bad = bad + 1 end
    out[#out + 1] = ("%s %-34s want %-11s got %-11s %s"):format(ok and "ok  " or "FAIL", r[1], r[2], r[3], r[4])
end
for _, r in ipairs(W) do
    local ok = r[2] == r[3]
    if not ok then bad = bad + 1 end
    out[#out + 1] = ("%s %-34s want %-11s got %s"):format(ok and "ok  " or "FAIL", r[1], r[2], r[3])
end
return table.concat(out, "\n"), bad
'''


def main():
    lua = L.LuaRuntime(encoding="utf8", unpack_returned_tuples=True)
    lua.execute(STUBS)
    run = lua.eval("function(s, n) local f, e = loadstring(s, n); if not f then error(e) end; f('Wally', ns) end")
    for name in ("Gear.lua", "JunkFilter.lua"):
        run(open(os.path.join(WALLY, name), encoding="utf8").read(), name)
    text, bad = lua.execute(CASES)
    print(text)
    print("%d failed" % bad)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
