local _, ns = ...
local C = ns.Compat

-- Named shopping lists, saved per character.
-- list  = { name, entries = { entry, ... } }
-- entry = { itemID, name, link, qty, tolerance (nil = default), bought }
--      or a search entry: { filter = filters (Search.lua), label, qty, tolerance, bought } that buys
--      any matching items (shopping lists only: prebuilt lists count exact items you own).
local Lists = {}
ns.Lists = Lists

function Lists:All() return ns.char.lists end

function Lists:Active()
    local all = ns.char.lists
    if #all == 0 then
        all[1] = { name = "Shopping List", entries = {} }
        ns.char.activeList = 1
    end
    if not all[ns.char.activeList] then ns.char.activeList = 1 end
    return all[ns.char.activeList]
end

function Lists:SetActive(index)
    if ns.char.lists[index] then
        ns.char.activeList = index
        ns.char.addTarget = { kind = "list", index = index }
        ns:Changed()
    end
end

-- Where Browse (and drag-and-drop) adds items: a list or a prebuilt list. Defaults to the active list.
function Lists:AddTarget()
    local t = ns.char.addTarget
    if t and t.kind == "template" and ns.Prebuilt then
        local template = ns.Prebuilt:Get(t.id)
        if template then return template, "template" end
    elseif t and t.kind == "list" and ns.char.lists[t.index] then
        return ns.char.lists[t.index], "list"
    end
    return self:Active(), "list"
end

function Lists:SetAddTarget(kind, key)
    if kind == "template" then ns.char.addTarget = { kind = kind, id = key }
    else ns.char.addTarget = { kind = "list", index = key } end
    ns:Changed()
end

function Lists:Create(name)
    name = ns.Trim(name)
    if name == "" then name = "List " .. (#ns.char.lists + 1) end
    table.insert(ns.char.lists, { name = name, entries = {} })
    ns.char.activeList = #ns.char.lists
    ns:Changed()
    return ns.char.lists[#ns.char.lists]
end

function Lists:Rename(list, name)
    name = ns.Trim(name)
    if name ~= "" then list.name = name; ns:Changed() end
end

function Lists:Delete(list)
    for i, l in ipairs(ns.char.lists) do
        if l == list then table.remove(ns.char.lists, i) break end
    end
    if ns.char.addTarget and ns.char.addTarget.kind == "list" then ns.char.addTarget = nil end
    ns.char.activeList = math.max(1, math.min(ns.char.activeList, #ns.char.lists))
    ns:Changed()
end

-- Accepts an itemID, an item link or an item name (looked up in the catalog).
local function Resolve(item)
    if type(item) == "number" then return item end
    if type(item) ~= "string" then return nil end
    local id = C.IDFromLink(item) or tonumber(item)
    if id then return id end
    local lname = ns.Trim(item):lower()
    ns.Catalog:EnsureBuilt()
    for _, e in ipairs(ns.Catalog.entries) do
        if e.lname == lname then return e.id end
    end
    local _, link = C.GetItemInfo(item)
    return C.IDFromLink(link)
end

function Lists:Find(list, itemID)
    if not itemID then return nil end
    for i, entry in ipairs(list.entries) do
        if entry.itemID == itemID then return entry, i end
    end
end

-- Adding an item that is already on the list raises its quantity.
function Lists:AddItem(item, qty, list)
    list = list or self:AddTarget()
    qty = math.max(1, math.floor(tonumber(qty) or 1))
    local id = Resolve(item)
    if not id then
        ns:Print("Couldn't find an item called " .. tostring(item) .. ".", true)
        return nil
    end
    local entry = self:Find(list, id)
    local e = ns.Catalog:Get(id)
    if entry then
        entry.qty = entry.qty + qty
    else
        entry = { itemID = id, name = e and e.name, link = e and e.link, qty = qty, bought = 0 }
        table.insert(list.entries, entry)
    end
    ns:Print(("Added %dx %s to %s (%d %s)."):format(qty, entry.link or entry.name or ("item " .. id), list.name, entry.qty,
        list.id and "target" or "wanted"))
    ns:Changed()
    return entry
end

-- Adds a search as an entry: the Cart buys qty of anything matching it.
function Lists:AddSearch(f, qty, list, label)
    list = list or self:AddTarget()
    if list.id then
        ns:Print("Prebuilt lists restock exact items you own, so they can't hold searches. Pick a shopping list.", true)
        return nil
    end
    if ns.Search.IsEmpty(f) then
        ns:Print("That search has no filters. Type a name or pick some filters first.", true)
        return nil
    end
    qty = math.max(1, math.floor(tonumber(qty) or 1))
    local entry = { filter = ns.Search.Copy(f), label = label, qty = qty, bought = 0 }
    entry.filter.quantity = nil
    table.insert(list.entries, entry)
    ns:Print(("Added a search to %s: %dx %s."):format(list.name, qty, self:Describe(entry)))
    ns:Changed()
    return entry
end

function Lists:IsSearch(entry) return entry.filter ~= nil end

function Lists:Contains(list, entry)
    for _, e in ipairs(list.entries) do if e == entry then return true end end
    return false
end

function Lists:Remove(list, entry)
    for i, en in ipairs(list.entries) do
        if en == entry then table.remove(list.entries, i) break end
    end
    ns:Changed()
end

function Lists:SetQty(entry, qty)
    entry.qty = math.max(1, math.floor(tonumber(qty) or entry.qty))
    ns:Changed()
end

function Lists:Clear(list)
    wipe(list.entries); ns:Changed()
end

function Lists:ResetProgress(list)
    for _, entry in ipairs(list.entries) do entry.bought = 0 end
    ns:Print("Progress on " .. list.name .. " reset.", true)
    ns:Changed()
end

-- Fills in name/link once item data arrives (entries can be added before it's cached).
function Lists:Describe(entry)
    if entry.filter then return "|cff55d6be[Search]|r " .. (entry.label or ns.Search:Describe(entry.filter)) end
    if not entry.link then
        local e = ns.Catalog:Get(entry.itemID)
        if e and e.link then entry.name, entry.link = e.name, e.link end
    end
    return entry.link or entry.name or ("item:" .. entry.itemID)
end

function Lists:Tolerance(entry)
    return entry.tolerance or ns.db.options.tolerance
end

function Lists:Remaining(entry)
    return math.max(0, entry.qty - (entry.bought or 0))
end

-- Market price per unit and the estimated cost of what's still needed.
function Lists:Estimate(list)
    local total, unknown = 0, 0
    for _, entry in ipairs(list.entries) do
        local price = entry.filter and entry.filter.maxPrice or ns.Catalog:PriceFor(entry.itemID)
        local remaining = self:Remaining(entry)
        if price then total = total + price * remaining
        elseif remaining > 0 then unknown = unknown + 1 end
    end
    return total, unknown
end

-- Creates (or replaces) an Auctionator shopping list with the same items.
function Lists:ExportToAuctionator(list)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not (api and api.ConvertToSearchString and api.CreateShoppingList) then
        return ns:Print("This version of Auctionator can't import shopping lists.", true)
    end
    local terms = {}
    for _, entry in ipairs(list.entries) do
        self:Describe(entry)
        local name = entry.name
        if entry.filter then
            local s = ns.Search:ToAuctionatorString(entry.filter, self:Remaining(entry))
            if s then terms[#terms + 1] = s end
        elseif name then
            local ok, s = pcall(api.ConvertToSearchString, ns.CALLER,
                { searchString = name, isExact = true, quantity = self:Remaining(entry) })
            if ok and s then terms[#terms + 1] = s end
        end
    end
    local listName = "Quartermaster - " .. list.name
    local ok, err = pcall(api.CreateShoppingList, ns.CALLER, listName, terms)
    if ok then ns:Print(("Sent %d items to Auctionator as \"%s\"."):format(#terms, listName), true)
    else ns:Print("Auctionator refused the list: " .. tostring(err), true) end
end

-- For other addons (Wealth Planner's Invest tab). items = { { id, qty, maxUnit } }; maxUnit, when
-- given, is the most the Cart pays per unit for that item (instead of market price plus tolerance).
QuartermasterAPI = QuartermasterAPI or {}

-- Puts items on a list (adding to an item already on it), makes it the Cart's list and opens the
-- Cart tab when the auction house is open, so you can review it before buying anything.
local function Fill(list, index, items)
    for _, it in ipairs(items) do
        local id, qty = tonumber(it.id), math.floor(tonumber(it.qty) or 0)
        if id and qty >= 1 then
            local existing = Lists:Find(list, id)
            if existing then
                existing.qty = existing.qty + qty
                if it.maxUnit then existing.maxUnit = math.max(existing.maxUnit or 0, math.floor(it.maxUnit)) end
            else
                local e = ns.Catalog:Get(id)
                table.insert(list.entries, { itemID = id, name = e and e.name, link = e and e.link, qty = qty, bought = 0,
                    maxUnit = it.maxUnit and math.floor(it.maxUnit) or nil })
            end
        end
    end
    Lists:SetActive(index)
    if ns.char.cart.mode ~= "list" then ns.Buyer:Stop(true); ns.char.cart.mode = "list" end
    if ns.CartTab then ns.CartTab:Recount(); ns.CartTab:Select() end
    ns:Changed()
    return #list.entries
end

-- Fills the list called `name` (made if missing), replacing what was on it. Returns how many items
-- went on it.
function QuartermasterAPI.SetShoppingList(name, items)
    if type(name) ~= "string" or type(items) ~= "table" then return 0 end
    local index
    for i, l in ipairs(ns.char.lists) do if l.name == name then index = i break end end
    if not index then Lists:Create(name); index = #ns.char.lists end
    local list = ns.char.lists[index]
    if ns.Buyer.list == list then ns.Buyer:Stop(true) end
    wipe(list.entries)
    return Fill(list, index, items)
end

-- Makes a new list with these items (its name gets " (2)", " (3)"... if taken), leaving your other
-- lists alone. Returns how many items went on it and the list's name.
function QuartermasterAPI.NewShoppingList(name, items)
    if type(name) ~= "string" or type(items) ~= "table" then return 0 end
    local taken = {}
    for _, l in ipairs(ns.char.lists) do taken[l.name] = true end
    local final, n = name, 1
    while taken[final] do n = n + 1; final = ("%s (%d)"):format(name, n) end
    Lists:Create(final)
    local index = #ns.char.lists
    return Fill(ns.char.lists[index], index, items), final
end
