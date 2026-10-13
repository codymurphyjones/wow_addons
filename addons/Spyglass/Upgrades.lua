local ADDON, ns = ...
local D = ns.Data

-- Upgrade counts for the journal's home tiles. Which of an instance's items
-- your character could use, and their scores, are worked out once and saved
-- (per character, in SpyGlassDB.upgrades); each redraw then only holds those
-- scores against what you wear, so changing gear needs no new work.
local Up = {}
ns.Upgrades = Up

local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata

-- Same margin as the gear list's green "+x" (List:UpgradeText).
local MIN_DELTA = 0.05
-- "Extend Upgrade Search" (the journal's home page) looks this many levels
-- above yours, for both the instances and the items' required level.
local EXTEND = 3
-- Bumped when the saved candidates change shape, so old saves are redone.
local FORMAT = 2

local store -- SpyGlassDB.upgrades[character] = { sig, inst = { [key] = entry (see Derive) } }
local checkSig = true

local function Level()
    return ns.Usability:Level()
end

-- Everything the candidates depend on besides the loot itself: class,
-- level, stat priority, talents, spells, the addon and client versions.
local function Serialize(value, out)
    if type(value) ~= "table" then
        out[#out + 1] = tostring(value)
        return
    end
    local keys = {}
    for k in pairs(value) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    out[#out + 1] = "{"
    for _, k in ipairs(keys) do
        out[#out + 1] = tostring(k) .. "="
        Serialize(value[k], out)
        out[#out + 1] = ";"
    end
    out[#out + 1] = "}"
end

local function Signature()
    local out = { FORMAT, select(2, UnitClass("player")), Level(),
        GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version") or "?",
        GetBuildInfo and select(2, GetBuildInfo()) or "?" }
    Serialize(ns.Scoring:Weights(), out)
    if GetNumTalentTabs and GetTalentInfo then
        for tab = 1, GetNumTalentTabs() do
            for i = 1, (GetNumTalents and GetNumTalents(tab) or 0) do
                local _, _, _, _, rank = GetTalentInfo(tab, i)
                out[#out + 1] = rank or 0
            end
        end
    end
    if GetNumSpellTabs and GetSpellTabInfo then
        for tab = 1, GetNumSpellTabs() do
            local _, _, _, count = GetSpellTabInfo(tab)
            out[#out + 1] = count or 0
        end
    end
    for i, part in ipairs(out) do out[i] = tostring(part) end
    return table.concat(out, ",")
end

-- The saved candidates for this character, dropped when what they were
-- worked out from has changed.
local function Store()
    if not ns.db then return nil end
    if not store then
        ns.db.upgrades = type(ns.db.upgrades) == "table" and ns.db.upgrades or {}
        local who = UnitName("player") .. "-" .. (GetRealmName() or "?")
        local saved = ns.db.upgrades[who]
        if type(saved) ~= "table" or type(saved.inst) ~= "table" then
            saved = { inst = {} }
            ns.db.upgrades[who] = saved
        end
        store = saved
        checkSig = true
    end
    if checkSig then
        checkSig = false
        local sig = Signature()
        if store.sig ~= sig then
            store.sig, store.inst = sig, {}
        end
    end
    return store
end

-- Something the candidates depend on may have changed (stat priority,
-- talents, spells, level, skills). The signature decides on next use, so a
-- change that turns out to be none (as at login) keeps the saved data.
function Up:Invalidate()
    checkSig = true
end

-- The highest level counted: yours, or a few above with the search extended.
function Up:MaxLevel()
    local extended = ns.J and ns.J.db and ns.J.db.extendUpgrades
    return Level() + (extended and EXTEND or 0)
end

-- Instances worth a count: loot recorded, and not above MaxLevel.
function Up:Eligible(inst)
    return not inst.comingSoon and inst.minLevel <= self:MaxLevel()
end

-- The instance's items you could wear (now, or within EXTEND levels) that
-- score for you: { items = { { itemID, group, score, reqLevel }, ... },
-- missing = { itemID, ... } }. Both settings of the toggle share them.
-- missing are items the game knew nothing about yet (they aren't asked for
-- here); once one of them loads, the instance is worked out again.
local function Derive(inst)
    local items, missing, level = {}, {}, Level() + EXTEND
    for _, itemID in ipairs(inst.items) do
        if not (ns:IsEncrypted(itemID) and not ns:Shipped(itemID)) then
            local info = ns:Peek(itemID)
            local status = info and ns.Usability:Status(itemID, false)
            if not info or status == "pending" then
                if ns.Usability:CanEquipInstant(itemID) then missing[#missing + 1] = itemID end
            elseif status == true and info.reqLevel <= level then
                local group = D.EQUIP_GROUP[info.equipLoc]
                local score = ns.Scoring:Score(itemID)
                if group and (score > 0 or ns.Usability:IsClassSpecific(itemID)) then
                    items[#items + 1] = { itemID, group, score, info.reqLevel }
                end
            end
        end
    end
    return { items = items, missing = #missing > 0 and missing or nil }
end

local function Stale(entry)
    for _, itemID in ipairs(entry.missing or {}) do
        if ns:Peek(itemID) then return true end
    end
    return false
end

local function Candidates(inst)
    local saved = Store()
    local entry = saved and saved.inst[inst.key]
    if not entry or Stale(entry) then
        entry = Derive(inst)
        if saved then saved.inst[inst.key] = entry end
    end
    return entry.items
end

-- How many of the instance's items beat what you wear, and
-- { [group] = count } for them. 0 for instances that aren't eligible.
function Up:Count(inst)
    if not self:Eligible(inst) then return 0, nil end
    local main = GetInventoryItemID("player", 16)
    local twoHanded = main and ns:Instant(main) == "INVTYPE_2HWEAPON"
    local maxLevel = self:MaxLevel()
    local n, groups = 0, {}
    for _, c in ipairs(Candidates(inst)) do
        local itemID, group, score, req = c[1], c[2], c[3], c[4]
        if req <= maxLevel and not (group == "OFFHAND" and twoHanded) and not ns.Scoring:IsWorn(itemID) then
            local worn, empty = ns.Scoring:EquippedScore(group)
            if empty or score - worn > MIN_DELTA then
                n = n + 1
                groups[group] = (groups[group] or 0) + 1
            end
        end
    end
    return n, groups
end

-- How many of these items beat what you wear: the same test as Count, for
-- any list (a boss's loot, a profession's crafts), worked out as asked.
-- Items not loaded yet don't count until they are.
function Up:CountItems(itemIDs)
    local main = GetInventoryItemID("player", 16)
    local twoHanded = main and ns:Instant(main) == "INVTYPE_2HWEAPON"
    local maxLevel = self:MaxLevel()
    local n = 0
    for _, itemID in ipairs(itemIDs or {}) do
        local info = ns:Peek(itemID)
        if info and info.reqLevel <= maxLevel and ns.Usability:Status(itemID, false) == true
            and not ns.Scoring:IsWorn(itemID) then
            local group = D.EQUIP_GROUP[info.equipLoc]
            if group and not (group == "OFFHAND" and twoHanded) then
                local score = ns.Scoring:Score(itemID)
                if score > 0 or ns.Usability:IsClassSpecific(itemID) then
                    local worn, empty = ns.Scoring:EquippedScore(group)
                    if empty or score - worn > MIN_DELTA then n = n + 1 end
                end
            end
        end
    end
    return n
end

-- "Head, Finger x2, Weapons", in the slot dropdown's order.
function Up:GroupsText(groups)
    local parts = {}
    for _, g in ipairs(D.SLOT_GROUPS) do
        local count = groups[g[1]]
        if count then parts[#parts + 1] = g[2] .. (count > 1 and " x" .. count or "") end
    end
    return table.concat(parts, ", ")
end
