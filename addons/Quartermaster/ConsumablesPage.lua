local _, ns = ...

-- Consumables: the potions, food and buffs you want to keep on hand, each with a minimum stock.
-- Only there when Bandolier is loaded: Bandolier knows what counts as a consumable and records
-- what you use up (Bandolier/API.lua), so the page can suggest what you've been going through.
--
-- The list is an ordinary character prebuilt list ("Consumables"), so the Cart restocks it like any
-- other: tick it at the auction house and Quartermaster buys whatever has dropped below its minimum.
local W = ns.Widgets
local Label, Muted, MakeButton, Hint = W.Label, W.Muted, W.MakeButton, W.Hint
local MakeEditBox, MakeNumberBox = W.MakeEditBox, W.MakeNumberBox

local LIST_ID = "consumables"
local LEFT_W = 300
local RECENT_DAYS = 14   -- how far back "recently used" looks
local MAX_RESULTS = 60
local CONSUMABLE = (Enum and Enum.ItemClass and Enum.ItemClass.Consumable) or 0
local HIGHLIGHT = { 1, 0.82, 0.30 }

local Consumables = {}
ns.Consumables = Consumables

function Consumables:Available() return BandolierAPI ~= nil and BandolierAPI.RecentlyUsed ~= nil end

-- The stock list, made the first time it's needed (and again if it's deleted).
function Consumables:List()
    local t = ns.Prebuilt:Get(LIST_ID)
    if not t then
        t = { id = LIST_ID, name = "Consumables", entries = {} }
        table.insert(ns.char.templates, t)
    end
    return t
end

-- A starting minimum from how many you used: at least 5, rounded up to a multiple of 5.
local function SuggestedMin(used)
    return math.max(5, math.ceil((used or 0) / 5) * 5)
end

-- Bandolier's kind of consumable, remembered per item (it can read the item's tooltip).
local categories = {}
local function Category(e)
    if categories[e.id] == nil and e.name then
        categories[e.id] = BandolierAPI.Category(e.id, e.name) or false
    end
    return categories[e.id] or nil
end

-- Puts an item on the list with this minimum (or sets the minimum if it's already there).
function Consumables:Add(itemID, min)
    local t = self:List()
    local entry = ns.Lists:Find(t, itemID)
    if entry then ns.Lists:SetQty(entry, min) else ns.Lists:AddItem(itemID, min, t) end
end

-- Ticks the list in the Cart (prebuilt mode) and opens the Cart if the auction house is open.
function Consumables:Restock()
    local t = self:List()
    ns.Buyer:Stop(true)
    ns.char.cart.mode = "prebuilt"
    ns.char.cart.ticked[t.id] = true
    if ns.CartTab then ns.CartTab:Recount() end
    ns:Changed()
    if not (ns.CartTab and ns.CartTab:Select()) then
        ns:Print("\"" .. t.name .. "\" is ticked in the Cart. Open the auction house and the Cart tab buys what's below its minimum.", true)
    end
end

local function Build(p)
    local selectedEntry
    local query = ""

    Label(p, "Consumables", "QuartermasterGameFontNormalLarge", 0, 0)
    p.summary = Muted(Label(p, "Keep a minimum of each consumable on hand. At the auction house, Restock buys whatever has dropped below its minimum. Highlighted items are ones you've used lately that aren't on your list yet.", "QuartermasterGameFontHighlightSmall", 0, -24, 640))
    p.summary:SetWordWrap(true)

    -- Left: search, with what you've been using on top.
    local search = MakeEditBox(p, LEFT_W, "Search consumables...")
    search:SetPoint("TOPLEFT", 0, -60)
    W.RegisterLinkBox(search, function() query = ns.Trim(search:GetText()):lower(); p.Refresh() end)
    search:HookScript("OnTextChanged", function(self, user)
        if user then query = ns.Trim(self:GetText()):lower(); p.Refresh() end
    end)
    Hint(search, "Search", "Type part of a name to find consumables Auctionator knows. Shift-click an item link here to look it up. You can also drop items from your bags on either list.")

    local leftHolder = CreateFrame("Frame", nil, p)
    leftHolder:SetPoint("TOPLEFT", 0, -92); leftHolder:SetPoint("BOTTOMLEFT", 0, 0); leftHolder:SetWidth(LEFT_W + 26)
    local found = W.CreateRowList(leftHolder, 0, { rowHeight = 34 })

    -- Right: the stock list.
    local right = CreateFrame("Frame", nil, p)
    right:SetPoint("TOPLEFT", LEFT_W + 36, -60); right:SetPoint("BOTTOMRIGHT", 0, 0)
    right.title = Label(right, "Your stock list", "QuartermasterGameFontNormal", 0, -4)
    right.status = Muted(right:CreateFontString(nil, "OVERLAY", "QuartermasterGameFontHighlightSmall"))
    right.status:SetPoint("TOPRIGHT", -26, -6); right.status:SetJustifyH("RIGHT")
    local items = W.CreateRowList(right, -28, { bottom = 40 })

    local bar = CreateFrame("Frame", nil, right)
    bar:SetPoint("BOTTOMLEFT", 0, 0); bar:SetPoint("BOTTOMRIGHT", 0, 0); bar:SetHeight(32)
    local selText = bar:CreateFontString(nil, "OVERLAY", "QuartermasterGameFontHighlightSmall")
    selText:SetPoint("LEFT", 0, 0); selText:SetWidth(110); selText:SetJustifyH("LEFT"); selText:SetWordWrap(false)
    local minLabel = Muted(bar:CreateFontString(nil, "OVERLAY", "QuartermasterGameFontHighlightSmall"))
    minLabel:SetPoint("LEFT", selText, "RIGHT", 6, 0); minLabel:SetText("Minimum")
    local minBox = MakeNumberBox(bar, 46); minBox:SetPoint("LEFT", minLabel, "RIGHT", 4, 0)
    Hint(minBox, "Minimum stock", "Restock buys enough to bring you back up to this many (counting your bags, bank and mailbox).")
    local save = MakeButton(bar, "Save", 46, 26); save:SetPoint("LEFT", minBox, "RIGHT", 4, 0)
    local restock = MakeButton(bar, "Restock", 70, 26); restock:SetPoint("RIGHT", -26, 0)
    Hint(restock, "Restock at the auction house", "Ticks this list in the Cart's prebuilt mode. At the auction house the Cart opens and buys only what's below each minimum.")
    restock:SetScript("OnClick", function() Consumables:Restock() end)

    local function SaveSelected()
        if selectedEntry and minBox:GetValue() then ns.Lists:SetQty(selectedEntry, minBox:GetValue()) end
        minBox:ClearFocus()
    end
    save:SetScript("OnClick", SaveSelected)
    minBox:SetScript("OnEnterPressed", SaveSelected)

    -- One row for the left list. rec: how many you used lately, when it's a suggestion.
    local function FoundRow(e, t, used)
        local onList = ns.Lists:Find(t, e.id)
        local detail = {}
        if used then detail[#detail + 1] = ("Used %d in the last %d days"):format(used, RECENT_DAYS) end
        local kind = Category(e)
        if kind then detail[#detail + 1] = kind end
        detail[#detail + 1] = (e.price and "market " .. W.Money(e.price)) or "no auction price"
        local min = SuggestedMin(used)
        return {
            icon = W.IconFor(e), link = e.link,
            text = e.name and W.QualityName(e.name, e.quality) or ("|cff8fa3b3Loading item " .. e.id .. "...|r"),
            detail = table.concat(detail, "  ·  "),
            detailColor = used and not onList and HIGHLIGHT or nil,
            right = onList and ("|cff55d6beon list (min %d)|r"):format(onList.qty) or nil,
            dim = onList and 0.6 or nil,
            hint = onList and "Already on your stock list." or ("Click + to add it with a minimum of %d. Set the exact number on the right."):format(min),
            actions = not onList and { { "+ " .. min, function() Consumables:Add(e.id, min) end, ("Add with a minimum of %d"):format(min) } } or nil,
        }
    end

    local function Header(text, detail)
        return { noIcon = true, text = text, detail = detail or "", plainText = text }
    end

    local function RefreshFound(t)
        local rows = {}
        local shown = {}
        -- Suggestions: what you've used lately, not yet on the list (and matching the search).
        local recent = {}
        for _, r in ipairs(BandolierAPI.RecentlyUsed(RECENT_DAYS)) do
            local e = ns.Catalog:Get(r.id)
            if e and not ns.Lists:Find(t, r.id) and (query == "" or (e.lname and e.lname:find(query, 1, true))) then
                recent[#recent + 1] = { e = e, used = r.used }
            end
        end
        if #recent > 0 then
            rows[#rows + 1] = Header("|cffffd24dRecently used|r", "Not on your list yet")
            for _, r in ipairs(recent) do
                rows[#rows + 1] = FoundRow(r.e, t, r.used)
                shown[r.e.id] = true
            end
        end

        if #query >= 2 then
            ns.Catalog:EnsureBuilt()
            local matches = {}
            for _, e in ipairs(ns.Catalog.entries) do
                if not shown[e.id] and e.classID == CONSUMABLE and e.lname and e.lname:find(query, 1, true) then
                    matches[#matches + 1] = e
                end
            end
            table.sort(matches, function(a, b) return a.lname < b.lname end)
            rows[#rows + 1] = Header("Search results", #matches > MAX_RESULTS and ("First %d of %d"):format(MAX_RESULTS, #matches) or nil)
            for i = 1, math.min(#matches, MAX_RESULTS) do rows[#rows + 1] = FoundRow(matches[i], t) end
            if #matches == 0 then rows[#rows + 1] = Header("|cff8fa3b3No consumables match.|r", "Auctionator only knows items it has seen at the auction house.") end
        elseif #recent == 0 then
            rows[#rows + 1] = Header("Search for a consumable", "Type at least two letters above.")
        end
        found:Set(rows)
        found.onDrop = function() W.AddCursorItem(t) end
    end

    local function RefreshStock(t)
        if selectedEntry and not ns.Lists:Contains(t, selectedEntry) then selectedEntry = nil end
        local list, stocked = {}, 0
        for _, entry in ipairs(t.entries) do
            local e = ns.Catalog:Get(entry.itemID)
            local market = ns.Lists:Price(entry)
            local have = ns.Stock:Have(entry.itemID)
            local need = math.max(0, entry.qty - have)
            if need == 0 then stocked = stocked + 1 end
            local used = BandolierAPI.Used(entry.itemID, 7)
            local detail = ("min %d  ·  have %d (%s)"):format(entry.qty, have, ns.Stock:Describe(entry.itemID))
            if used > 0 then detail = detail .. ("  ·  used %d this week"):format(used) end
            list[#list + 1] = {
                icon = W.IconFor(e or entry), link = entry.link or (e and e.link),
                text = ns.Lists:Describe(entry), detail = detail,
                right = need == 0 and "|cff59f28cstocked|r"
                    or ("need %d%s"):format(need, market and ("  ~" .. ns.Compat.Money(market * need)) or ""),
                bar = entry.qty > 0 and math.min(1, have / entry.qty) or nil, barText = "",
                selected = selectedEntry == entry,
                hint = "Click to set its minimum below.",
                onClick = function() selectedEntry = entry; minBox:SetValue(entry.qty); p.Refresh() end,
                actions = {
                    { "X", function() if selectedEntry == entry then selectedEntry = nil end; ns.Lists:Remove(t, entry) end, "Remove from the list" },
                    { "+", function() ns.Lists:SetQty(entry, entry.qty + 1) end, "Raise the minimum" },
                    { "-", function() ns.Lists:SetQty(entry, entry.qty - 1) end, "Lower the minimum" },
                },
            }
        end
        items:Set(list, "Nothing to keep stocked yet. Add consumables from the left, or drop them here from your bags.")
        items.onDrop = function() W.AddCursorItem(t) end

        local cost, unknown = ns.Prebuilt:RestockCost(t)
        right.status:SetText(#t.entries == 0 and "" or ("%d of %d stocked  ·  restock ~%s%s"):format(stocked, #t.entries,
            ns.Compat.Money(cost), unknown > 0 and "+" or ""))
        selText:SetText(selectedEntry and ns.Lists:Describe(selectedEntry) or "|cff8fa3b3Select an item|r")
        for _, w in ipairs({ minBox, save }) do w:SetEnabled(selectedEntry ~= nil); w:SetAlpha(selectedEntry and 1 or 0.5) end
        if not selectedEntry then minBox:SetText("") end
        restock:SetEnabled(#t.entries > 0); restock:SetAlpha(#t.entries > 0 and 1 or 0.5)
    end

    p.Refresh = function()
        if not Consumables:Available() then return end
        local t = Consumables:List()
        RefreshFound(t)
        RefreshStock(t)
    end
    p.OnCatalogChanged = p.Refresh
end

if Consumables:Available() then
    ns.UI:RegisterPage("consumables", Build)
    -- A new use recorded by Bandolier: suggestions and "used this week" change.
    BandolierAPI.OnUsage(function() ns:Changed() end)
end

-- For other addons (Bandolier's /bandolier stock): opens this page.
QuartermasterAPI = QuartermasterAPI or {}
function QuartermasterAPI.ShowConsumables()
    if not Consumables:Available() then return false end
    ns.UI:Show("consumables")
    return true
end
