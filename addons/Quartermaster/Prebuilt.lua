local _, ns = ...

-- Prebuilt lists ("Raid Night"): reusable lists of target amounts. At the auction house the Cart
-- counts what you already have and buys only the difference. Character lists are the default;
-- account lists are shared by all your characters.
-- template = { id, name, entries = { {itemID, name, link, qty = target, tolerance} } }
local Prebuilt = {}
ns.Prebuilt = Prebuilt

-- What you already have: bags, bank (as last seen), the mailbox (as last seen) and anything
-- bought since the mailbox was last opened (auction wins arrive by mail).
local Stock = {}
ns.Stock = Stock

-- ---------------------------------------------------------------------------
-- Prebuilt lists
-- ---------------------------------------------------------------------------

local counter = 0
local function NewID()
    counter = counter + 1
    return ("%d-%d-%d"):format(time(), counter, math.random(1000, 9999))
end

local function Scopes() return { char = ns.char.templates, account = ns.db.templates } end

function Prebuilt:All() return Scopes() end

function Prebuilt:Get(id)
    if not id then return nil end
    for scope, list in pairs(Scopes()) do
        for i, t in ipairs(list) do
            if t.id == id then return t, scope, i end
        end
    end
end

function Prebuilt:ScopeLabel(scope) return scope == "account" and "Account" or "Character" end

-- Search entries stay behind: a prebuilt list counts exact items you own.
local function CopyEntries(entries)
    local out, searches = {}, 0
    for _, e in ipairs(entries) do
        if e.itemID then
            out[#out + 1] = { itemID = e.itemID, name = e.name, link = e.link, qty = e.qty, tolerance = e.tolerance }
        else
            searches = searches + 1
        end
    end
    return out, searches
end

function Prebuilt:Create(name, scope, entries)
    name = ns.Trim(name)
    local list = Scopes()[scope or "char"]
    if name == "" then name = "Prebuilt " .. (#ns.char.templates + #ns.db.templates + 1) end
    local t = { id = NewID(), name = name, entries = entries or {} }
    table.insert(list, t)
    ns.Lists:SetAddTarget("template", t.id)
    ns:Changed()
    return t
end

function Prebuilt:Rename(t, name)
    name = ns.Trim(name)
    if name == "" or name == t.name then return end
    local old = t.name
    t.name = name
    ns:Print(("Renamed \"%s\" to \"%s\"."):format(old, name))
    ns:Changed()
end

local function Detach(t)
    local _, scope, i = Prebuilt:Get(t.id)
    if scope then table.remove(Scopes()[scope], i) end
    return scope
end

function Prebuilt:Delete(t)
    Detach(t)
    ns.char.cart.ticked[t.id] = nil
    if ns.char.addTarget and ns.char.addTarget.id == t.id then ns.char.addTarget = nil end
    ns:Changed()
end

-- Moves a list between this character and the account; it keeps its id, so ticks stay.
function Prebuilt:Move(t, toScope)
    local from = Detach(t)
    if not from then return end
    table.insert(Scopes()[toScope], t)
    ns:Print(toScope == "account"
        and ("Shared \"%s\" with all your characters."):format(t.name)
        or ("\"%s\" is now for this character only."):format(t.name), true)
    ns:Changed()
end
function Prebuilt:Share(t) self:Move(t, "account") end
function Prebuilt:MakeCharacterOnly(t) self:Move(t, "char") end

function Prebuilt:Duplicate(t, scope)
    return self:Create(t.name .. " (copy)", scope or "char", CopyEntries(t.entries))
end

-- A character prebuilt list from an ordinary list: each quantity becomes the target.
function Prebuilt:FromList(list)
    local entries, searches = CopyEntries(list.entries)
    local t = self:Create(list.name, "char", entries)
    ns:Print(("Saved \"%s\" as a prebuilt list. Tick it in the Cart tab to restock it."):format(t.name), true)
    if searches > 0 then
        ns:Print(("Left out %d search entr%s: prebuilt lists only hold exact items."):format(searches, searches == 1 and "y" or "ies"), true)
    end
    return t
end

-- Market cost to bring one list up to target right now (and how many items have no price).
function Prebuilt:RestockCost(t)
    local total, unknown = 0, 0
    for _, e in ipairs(t.entries) do
        local need = math.max(0, e.qty - Stock:Have(e.itemID))
        local price = ns.Catalog:PriceFor(e.itemID)
        if need > 0 then
            if price then total = total + price * need else unknown = unknown + 1 end
        end
    end
    return total, unknown
end

-- Merges the ticked lists into one throwaway shopping list for the Buyer. Targets add up when an
-- item is on more than one list; only what's still missing goes in the run.
function Prebuilt:BuildRun(ids)
    local order, byItem, names = {}, {}, {}
    for _, id in ipairs(ids) do
        local t = self:Get(id)
        if t then
            names[#names + 1] = t.name
            for _, e in ipairs(t.entries) do
                local m = byItem[e.itemID]
                if not m then
                    m = { itemID = e.itemID, name = e.name, link = e.link, target = 0, from = {} }
                    byItem[e.itemID] = m
                    order[#order + 1] = m
                end
                m.target = m.target + e.qty
                if e.tolerance and (not m.tolerance or e.tolerance > m.tolerance) then m.tolerance = e.tolerance end
                m.from[#m.from + 1] = t.name
            end
        end
    end
    local run = { name = #names > 0 and ("Restock: " .. table.concat(names, " + ")) or "Restock",
        entries = {}, covered = {}, isRun = true }
    for _, m in ipairs(order) do
        local have = Stock:Have(m.itemID)
        local entry = { itemID = m.itemID, name = m.name, link = m.link, tolerance = m.tolerance,
            target = m.target, have = have, from = m.from, bought = 0, qty = m.target - have }
        if entry.qty > 0 then run.entries[#run.entries + 1] = entry
        else entry.qty = 0; run.covered[#run.covered + 1] = entry end
    end
    return run
end

function Prebuilt:TickedIDs()
    local ids = {}
    for _, scope in ipairs({ "char", "account" }) do
        for _, t in ipairs(Scopes()[scope]) do
            if ns.char.cart.ticked[t.id] then ids[#ids + 1] = t.id end
        end
    end
    return ids
end

-- ---------------------------------------------------------------------------
-- Stock
-- ---------------------------------------------------------------------------

function Stock:Breakdown(itemID)
    local bags = GetItemCount(itemID) or 0
    local bank = ns.db.options.countBank and math.max(0, (GetItemCount(itemID, true) or 0) - bags) or 0
    local s = ns.char.stock
    local mail = ns.db.options.countMail and ((s.mail[itemID] or 0) + (s.sinceMail[itemID] or 0)) or 0
    return bags, bank, mail
end

function Stock:Have(itemID)
    local bags, bank, mail = self:Breakdown(itemID)
    return bags + bank + mail
end

function Stock:Describe(itemID)
    local bags, bank, mail = self:Breakdown(itemID)
    local parts = { "bags " .. bags }
    if bank > 0 then parts[#parts + 1] = "bank " .. bank end
    if mail > 0 then parts[#parts + 1] = "mail " .. mail end
    return table.concat(parts, ", ")
end

function Stock:RecordPurchase(itemID, count)
    if not itemID then return end
    local s = ns.char.stock.sinceMail
    s[itemID] = (s[itemID] or 0) + (count or 1)
end

-- While the mailbox is open its contents are known exactly; purchases before now are in there.
local MAX_ATTACH = ATTACHMENTS_MAX_RECEIVE or 12
ns:On("MAIL_INBOX_UPDATE", function()
    local mail = {}
    for i = 1, GetInboxNumItems() do
        for a = 1, MAX_ATTACH do
            local link = GetInboxItemLink(i, a)
            local id = ns.Compat.IDFromLink(link)
            if id then
                -- Newer clients return name, itemID, texture, count; older ones name, texture, count.
                local r = { GetInboxItem(i, a) }
                local count = r[2] == id and r[4] or r[3]
                mail[id] = (mail[id] or 0) + (tonumber(count) or 1)
            end
        end
    end
    ns.char.stock.mail = mail
    wipe(ns.char.stock.sinceMail)
    ns:Changed()
end)
