local _, ns = ...
local C = ns.Compat

-- Filters and sorts the catalog the way the Blizzard Browse tab and Auctionator's advanced
-- search do, but offline: everything runs against Auctionator's saved prices.
local Search = {}
ns.Search = Search

-- Blizzard's Browse order for the classic auction house; anything else follows.
local CLASS_ORDER = { 2, 4, 1, 0, 7, 6, 11, 9, 5, 15, 12 }

-- filters = { text, exact, classID, subClassID, equipLoc, minLevel, maxLevel, quality, usable,
--             minIlvl, maxIlvl, minPrice, maxPrice (copper), maxAge (days), hidePriceless, quantity,
--             minCrafted, maxCrafted, tier, expansion (kept only so Auctionator strings round-trip) }
-- The same table drives the offline Browse page, the live Buying tab, and search entries on lists.

-- "Usable" means no red requirement line on the tooltip, the same thing the Browse checkbox tests.
local usableCache = {}
local scanner
local function IsRed(fs)
    if not fs or not fs:IsShown() or (fs:GetText() or "") == "" then return false end
    local r, g, b = fs:GetTextColor()
    return r > 0.9 and g < 0.2 and b < 0.2
end
function Search:IsUsable(e)
    if usableCache[e.id] ~= nil then return usableCache[e.id] end
    if not e.link then return true end
    if not scanner then
        scanner = CreateFrame("GameTooltip", "QuartermasterScanTooltip", nil, "GameTooltipTemplate")
    end
    scanner:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanner:ClearLines()
    scanner:SetHyperlink(e.link)
    local usable = true
    for i = 2, scanner:NumLines() do
        if IsRed(_G["QuartermasterScanTooltipTextLeft" .. i]) or IsRed(_G["QuartermasterScanTooltipTextRight" .. i]) then
            usable = false; break
        end
    end
    usableCache[e.id] = usable
    return usable
end
ns:On("PLAYER_LEVEL_UP", function() wipe(usableCache) end)
ns:On("SKILL_LINES_CHANGED", function() wipe(usableCache) end)

local function Matches(e, f)
    if f.text then
        if not e.lname then return false end
        if f.exact then
            if e.lname ~= f.text then return false end
        elseif not e.lname:find(f.text, 1, true) then
            return false
        end
    end
    if f.classID and e.classID ~= f.classID then return false end
    if f.subClassID and e.subClassID ~= f.subClassID then return false end
    if f.equipLoc and e.equipLoc ~= f.equipLoc then return false end
    if f.quality and (e.quality or -1) < f.quality then return false end
    if f.minLevel and (e.reqLevel or 0) < f.minLevel then return false end
    if f.maxLevel and (e.reqLevel or 0) > f.maxLevel then return false end
    if f.minIlvl and (e.ilvl or 0) < f.minIlvl then return false end
    if f.maxIlvl and (e.ilvl or 0) > f.maxIlvl then return false end
    if (f.minPrice or f.maxPrice or f.hidePriceless) and not e.price then return false end
    if f.minPrice and e.price < f.minPrice then return false end
    if f.maxPrice and e.price > f.maxPrice then return false end
    if f.maxAge and (e.ageDays == nil or e.ageDays > f.maxAge) then return false end
    if f.usable and not Search:IsUsable(e) then return false end
    return true
end

function Search:Matches(e, f) return Matches(e, f) end

-- Live auction results: the price is what the auction house asks now (not Auctionator's market
-- price), and the server has already applied level and usable.
function Search:LiveMatches(e, f, unit, ilvl)
    if f.text then
        if not e.lname then return false end
        if f.exact then
            if e.lname ~= f.text then return false end
        elseif not e.lname:find(f.text, 1, true) then
            return false
        end
    end
    if f.classID and e.classID ~= f.classID then return false end
    if f.subClassID and e.subClassID ~= f.subClassID then return false end
    if f.equipLoc and e.equipLoc ~= f.equipLoc then return false end
    if f.quality and (e.quality or -1) < f.quality then return false end
    ilvl = ilvl or e.ilvl or 0
    if f.minIlvl and ilvl < f.minIlvl then return false end
    if f.maxIlvl and ilvl > f.maxIlvl then return false end
    if f.minPrice and unit < f.minPrice then return false end
    if f.maxPrice and unit > f.maxPrice then return false end
    return true
end

-- A copy that can be saved: no functions, no shared tables.
function Search.Copy(f)
    local out = {}
    for k, v in pairs(f or {}) do if type(v) ~= "table" and type(v) ~= "function" then out[k] = v end end
    return out
end

-- Whether a filter asks for anything at all (an empty search would list the whole auction house).
function Search.IsEmpty(f)
    return not (f.text or f.classID or f.equipLoc or f.minLevel or f.maxLevel or f.quality or f.usable
        or f.minIlvl or f.maxIlvl or f.minPrice or f.maxPrice)
end

local function Range(label, lo, hi, fmt)
    fmt = fmt or tostring
    if lo and hi then return ("%s %s-%s"):format(label, fmt(lo), fmt(hi)) end
    if lo then return ("%s %s+"):format(label, fmt(lo)) end
    if hi then return ("%s up to %s"):format(label, fmt(hi)) end
end

-- One line for list rows, recent searches and tooltips: "cloth" · Chest · iLvl 20-30 · up to 5g
function Search:Describe(f)
    local parts = {}
    if f.text then parts[#parts + 1] = f.exact and ('"' .. f.text .. '"') or f.text end
    if f.classID then
        local name = f.subClassID and C.GetSubClassName(f.classID, f.subClassID) or C.GetClassName(f.classID)
        if name then parts[#parts + 1] = name end
    end
    if f.equipLoc and _G[f.equipLoc] then parts[#parts + 1] = _G[f.equipLoc] end
    if f.quality then
        local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[f.quality]
        parts[#parts + 1] = (c and c.hex or "") .. (_G["ITEM_QUALITY" .. f.quality .. "_DESC"] or ("quality " .. f.quality)) .. "+|r"
    end
    parts[#parts + 1] = Range("Lvl", f.minLevel, f.maxLevel)
    parts[#parts + 1] = Range("iLvl", f.minIlvl, f.maxIlvl)
    parts[#parts + 1] = Range("price", f.minPrice, f.maxPrice, function(c) return C.Money(c) end)
    if f.usable then parts[#parts + 1] = "usable" end
    if f.maxAge then parts[#parts + 1] = ("seen within %dd"):format(f.maxAge) end
    if #parts == 0 then return "Anything" end
    return table.concat(parts, "  ·  ")
end

-- Auctionator's "categoryKey" for a class/subclass: "Weapon/One-Handed Swords".
local function CategoryKey(f)
    if not f.classID then return "" end
    local className = C.GetClassName(f.classID)
    if not className then return "" end
    local sub = f.subClassID and C.GetSubClassName(f.classID, f.subClassID)
    return sub and (className .. "/" .. sub) or className
end

-- Filters to an Auctionator advanced search string (the reverse of FromAuctionatorString).
function Search:ToAuctionatorString(f, quantity)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not api or not api.ConvertToSearchString then return nil end
    local ok, s = pcall(api.ConvertToSearchString, ns.CALLER, {
        searchString = f.text or "", isExact = f.exact or false, categoryKey = CategoryKey(f),
        minLevel = f.minLevel, maxLevel = f.maxLevel, minItemLevel = f.minIlvl, maxItemLevel = f.maxIlvl,
        minCraftedLevel = f.minCrafted, maxCraftedLevel = f.maxCrafted,
        minPrice = f.minPrice, maxPrice = f.maxPrice, quality = f.quality,
        tier = f.tier, expansion = f.expansion, quantity = quantity or f.quantity,
    })
    if ok then return s end
end

-- Every item class and subclass the auction house can filter by, for the live category dropdown.
-- Falls back to the classes seen in Auctionator's prices.
function Search:AllCategories()
    local getSubs = (C_AuctionHouse and C_AuctionHouse.GetAuctionItemSubClasses) or GetAuctionItemSubClasses
    if not getSubs then return self:Categories() end
    local tree, used = {}, {}
    local order = {}
    for _, id in ipairs(CLASS_ORDER) do order[#order + 1] = id; used[id] = true end
    for id = 0, 20 do if not used[id] then order[#order + 1] = id end end
    for _, classID in ipairs(order) do
        local name = C.GetClassName(classID)
        if name and name ~= "" then
            local subs = {}
            -- C_AuctionHouse returns one table of subclass IDs; the old global returns them as values.
            local ok, list = pcall(function()
                local first = getSubs(classID)
                if type(first) == "table" then return first end
                return { getSubs(classID) }
            end)
            for _, subID in ipairs(ok and list or {}) do
                local subName = C.GetSubClassName(classID, subID)
                if subName and subName ~= "" then subs[#subs + 1] = { subID, subName } end
            end
            tree[#tree + 1] = { classID, name, subs = subs }
        end
    end
    if #tree == 0 then return self:Categories() end
    return tree
end

local SORTERS = {
    name = function(a, b) return (a.lname or "~") < (b.lname or "~") end,
    level = function(a, b) return (a.reqLevel or 0) < (b.reqLevel or 0) end,
    ilvl = function(a, b) return (a.ilvl or 0) < (b.ilvl or 0) end,
    price = function(a, b) return (a.price or math.huge) < (b.price or math.huge) end,
    age = function(a, b) return (a.ageDays or math.huge) < (b.ageDays or math.huge) end,
}

function Search:Run(f, sortKey, desc)
    local results = {}
    if not ns.Catalog:EnsureBuilt() then return results end
    for _, e in ipairs(ns.Catalog.entries) do
        if Matches(e, f) then results[#results + 1] = e end
    end
    local cmp = SORTERS[sortKey or "name"] or SORTERS.name
    table.sort(results, function(a, b)
        if cmp(a, b) then return not desc end
        if cmp(b, a) then return desc end
        return a.id < b.id
    end)
    return results
end

-- Normalizes free text: lower-case; surrounding quotes mean an exact match (Auctionator's rule).
function Search.ParseText(text)
    text = ns.Trim(text)
    if text == "" then return nil, false end
    local inner = text:match('^"(.*)"$')
    if inner then return inner:lower(), true end
    return text:lower(), false
end

-- Category tree from the classes and subclasses that actually appear in the catalog.
-- { {classID, name, subs = { {subClassID, name}, ... }}, ... }
function Search:Categories()
    local seen = {}
    for _, e in ipairs(ns.Catalog.entries) do
        if e.classID then
            seen[e.classID] = seen[e.classID] or {}
            if e.subClassID then seen[e.classID][e.subClassID] = true end
        end
    end
    local order, used = {}, {}
    for _, id in ipairs(CLASS_ORDER) do if seen[id] then order[#order + 1] = id; used[id] = true end end
    local rest = {}
    for id in pairs(seen) do if not used[id] then rest[#rest + 1] = id end end
    table.sort(rest)
    for _, id in ipairs(rest) do order[#order + 1] = id end

    local tree = {}
    for _, classID in ipairs(order) do
        local subs = {}
        for subID in pairs(seen[classID]) do
            subs[#subs + 1] = { subID, C.GetSubClassName(classID, subID) or ("Type " .. subID) }
        end
        table.sort(subs, function(a, b) return a[2] < b[2] end)
        tree[#tree + 1] = { classID, C.GetClassName(classID) or ("Class " .. classID), subs = subs }
    end
    return tree
end

-- Equipment slots seen in the catalog, for the advanced Slot dropdown.
function Search:EquipSlots()
    local seen, list = {}, {}
    for _, e in ipairs(ns.Catalog.entries) do
        local loc = e.equipLoc
        if loc and loc ~= "" and not seen[loc] and _G[loc] then
            seen[loc] = true
            list[#list + 1] = { loc, _G[loc] }
        end
    end
    table.sort(list, function(a, b) return a[2] < b[2] end)
    return list
end

-- Auctionator "categoryKey" ("Weapon/One-Handed Swords") to classID/subClassID by name.
local function CategoryFromKey(key)
    if not key or key == "" then return nil end
    local className, subName = strsplit("/", key)
    for _, c in ipairs(Search:AllCategories()) do
        if c[2] == className then
            for _, s in ipairs(c.subs) do
                if s[2] == subName then return c[1], s[1] end
            end
            return c[1]
        end
    end
end

-- Auctionator advanced search string ("name;category;minIlvl;maxIlvl;minLvl;maxLvl;...") to filters.
function Search:FromAuctionatorString(str)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not api or not api.ConvertFromSearchString then return nil end
    local ok, t = pcall(api.ConvertFromSearchString, ns.CALLER, str)
    if not ok or type(t) ~= "table" then return nil end
    local f = {
        text = t.searchString ~= "" and t.searchString:lower() or nil,
        exact = t.isExact or false,
        minLevel = t.minLevel, maxLevel = t.maxLevel,
        minIlvl = t.minItemLevel, maxIlvl = t.maxItemLevel,
        minPrice = t.minPrice and t.minPrice > 0 and t.minPrice or nil,
        maxPrice = t.maxPrice and t.maxPrice > 0 and t.maxPrice or nil,
        quality = t.quality,
        quantity = t.quantity,
        minCrafted = t.minCraftedLevel, maxCrafted = t.maxCraftedLevel,
        tier = t.tier, expansion = t.expansion,
    }
    f.classID, f.subClassID = CategoryFromKey(t.categoryKey)
    return f, t
end
