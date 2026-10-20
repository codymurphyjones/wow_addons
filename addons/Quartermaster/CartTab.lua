local _, ns = ...
local PAL = ns.Palette

-- The Cart tab on the auction house (added through AHTabs.lua, next to the Buying tab). Find items
-- swaps the list for the live search panel (AuctionSearch.lua), and search entries are edited there.
local CartTab = {}
ns.CartTab = CartTab

local W = ns.Widgets
local ACCENT, MUTED = W.ACCENT, W.MUTED
local SetBackdrop, Label, Muted, MakeButton, Hint = W.SetBackdrop, W.Label, W.Muted, W.MakeButton, W.Hint

local COOL_GREEN = { 0.35, 0.95, 0.55 }
local SEARCH_ICON = "Interface\\Icons\\INV_Misc_Spyglass_03"

local panel

-- What the list shows: everything still to buy, and what's done unless it was finished more than
-- RECENT seconds ago ("recent"); only what's still to buy ("buy"); or everything ("all").
local RECENT = 15 * 60
local VIEWS = {
    { "recent", "Hide old done", "Finished items stay for 15 minutes, then drop off the list." },
    { "buy", "Still to buy", "Only what's left to buy." },
    { "all", "Everything", "Every item on the list, finished or not." },
}
local function View()
    local v = ns.char.cart.view
    for _, o in ipairs(VIEWS) do if o[1] == v then return o end end
    return VIEWS[1]
end

local STATUS_COLOR = {
    done = "|cff59f28c", scanning = "|cffffd24d", ["none listed"] = "|cffd9736b",
}
local function StatusText(entry)
    if ns.Lists:Remaining(entry) <= 0 then return "|cff59f28cdone|r" end
    local s = ns.Buyer.status[entry]
    if not s then return "|cff8fa3b3pending|r" end
    local color = STATUS_COLOR[s] or (s:find("^scanning") and "|cffffd24d") or (s:find("skipped") and "|cffff9933")
        or (s:find("short") and "|cffd9736b") or "|cffffffff"
    return color .. s .. "|r"
end

local function BuildPanel(parent)
    panel = CreateFrame("Frame", "QuartermasterCartPanel", parent, "BackdropTemplate")
    SetBackdrop(panel, 0.98)
    panel:SetFrameLevel(parent:GetFrameLevel() + 10)
    panel:EnableMouse(true)
    panel:Hide()

    local logo = panel:CreateTexture(nil, "ARTWORK"); logo:SetSize(26, 26)
    logo:SetPoint("TOPLEFT", 10, -9); logo:SetTexture(ns.ICON)
    Label(panel, "Cart", "QuartermasterGameFontNormalLarge", 42, -14):SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])

    -- What to buy: an ordinary shopping list, or prebuilt lists restocked to their targets.
    local modeList = MakeButton(panel, "Shopping list", 92, 24); modeList:SetPoint("TOPLEFT", 100, -10)
    local modePre = MakeButton(panel, "Prebuilt", 70, 24); modePre:SetPoint("LEFT", modeList, "RIGHT", 4, 0)
    Hint(modeList, "Shopping list", "Buy one of your lists. Bought amounts are remembered until you reset them.")
    Hint(modePre, "Prebuilt lists", "Tick one or more prebuilt lists, like Raid Night. Quartermaster counts what you already have (bags, bank, mailbox) and buys only what's missing.")
    local function SetMode(mode)
        if ns.char.cart.mode == mode then return end
        ns.Buyer:Stop(true)
        ns.char.cart.mode = mode
        CartTab:Recount()
        CartTab:Refresh()
    end
    modeList:SetScript("OnClick", function() SetMode("list") end)
    modePre:SetScript("OnClick", function() SetMode("prebuilt") end)
    panel.modeList, panel.modePre = modeList, modePre

    local picker = W.MakeDropdown(panel, 180, function()
        local opts = {}
        for i, l in ipairs(ns.Lists:All()) do opts[#opts + 1] = { i, l.name .. " |cff8fa3b3(" .. #l.entries .. ")|r" } end
        return opts
    end, function(index) ns.Lists:SetActive(index); ns.Buyer:SetList(ns.Lists:Active()) end)
    picker:SetPoint("LEFT", modePre, "RIGHT", 10, 0)
    Hint(picker, "List to buy", "Switching lists stops the current run.")
    panel.picker = picker

    local ticks = W.MakeMultiDropdown(panel, 200, function()
        local opts = {}
        local all = ns.Prebuilt:All()
        for _, scope in ipairs({ "char", "account" }) do
            if #all[scope] > 0 then
                opts[#opts + 1] = { nil, scope == "char" and "This character" or "Account (all characters)", header = true }
                for _, t in ipairs(all[scope]) do
                    opts[#opts + 1] = { t.id, t.name .. " |cff8fa3b3(" .. #t.entries .. ")|r", checked = ns.char.cart.ticked[t.id] and true or false }
                end
            end
        end
        if #opts == 0 then opts[1] = { nil, "No prebuilt lists yet - make one in /qm", header = true } end
        return opts
    end, function(id, checked)
        ns.Buyer:Stop(true)
        ns.char.cart.ticked[id] = checked or nil
        CartTab:Recount()
        CartTab:Refresh()
    end)
    ticks:SetPoint("LEFT", modePre, "RIGHT", 10, 0)
    Hint(ticks, "Prebuilt lists to restock", "Tick as many as you like. Items on more than one list add their targets together.")
    panel.ticks = ticks
    panel.summary = Muted(Label(panel, "", "QuartermasterGameFontHighlightSmall", 0, -16, 250))
    panel.summary:ClearAllPoints(); panel.summary:SetPoint("LEFT", ticks, "RIGHT", 10, 0)

    local open = MakeButton(panel, "Edit lists", 80, 24); open:SetPoint("TOPRIGHT", -10, -10)
    open:SetScript("OnClick", function()
        ns.UI:Show(ns.char.cart.mode == "prebuilt" and "prebuilt" or "lists")
    end)
    local find = MakeButton(panel, "Find items", 80, 24); find:SetPoint("RIGHT", open, "LEFT", -4, 0)
    find:SetScript("OnClick", function() CartTab:SetFind(not CartTab.finding) end)
    Hint(find, "Find items", "Search the live auction house without leaving the Cart: add what you find to the list you're buying (or the whole search as one entry), or buy it right away.")
    panel.find = find

    -- What the list shows (VIEWS), at the right above it.
    local view = W.MakeDropdown(panel, 170, function()
        local opts = {}
        for _, o in ipairs(VIEWS) do opts[#opts + 1] = { o[1], o[2] } end
        return opts
    end, function(value)
        ns.char.cart.view = value
        CartTab:Refresh()
    end)
    view:SetPoint("TOPRIGHT", -12, -38)
    view:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Show", ACCENT[1], ACCENT[2], ACCENT[3])
        for _, o in ipairs(VIEWS) do GameTooltip:AddLine(o[2] .. ": " .. o[3], 0.8, 0.85, 0.9, true) end
        GameTooltip:Show()
    end)
    view:HookScript("OnLeave", function() GameTooltip:Hide() end)
    panel.view = view

    -- Expected (market price on arrival) against what the auction house asks right now.
    panel.compare = panel:CreateFontString(nil, "OVERLAY", "QuartermasterGameFontHighlightSmall")
    panel.compare:SetPoint("TOPLEFT", 12, -44); panel.compare:SetPoint("RIGHT", view, "LEFT", -8, 0)
    panel.compare:SetJustifyH("LEFT"); panel.compare:SetWordWrap(false)
    local holder = CreateFrame("Frame", nil, panel)
    holder:SetPoint("TOPLEFT", 10, -68); holder:SetPoint("BOTTOMRIGHT", -6, 52)
    panel.list = W.CreateRowList(holder, 0, { rowHeight = 34 })
    panel.list.onDrop = function() W.AddCursorItem() end
    panel.holder = holder

    -- Footer: one big button that always says what the next click does.
    local buy = MakeButton(panel, "Start buying", 360, 34)
    buy:SetPoint("BOTTOMLEFT", 10, 10)
    buy.text:SetFontObject("QuartermasterGameFontHighlight")
    buy.fill = buy:CreateTexture(nil, "BACKGROUND", nil, 1)
    buy.fill:SetPoint("TOPLEFT", 1, -1); buy.fill:SetPoint("BOTTOMRIGHT", -1, 1)
    buy.fill:SetColorTexture(1, 1, 1, 1); buy.fill:SetVertexColor(0, 0, 0, 0)
    buy:SetScript("OnClick", function()
        if CartTab.finding then CartTab:SetFind(false) end
        ns.Buyer:Step()
    end)
    Hint(buy, "Buy Next", "Each click buys one auction (the game needs a click per purchase). Trade goods take two clicks: one to get the exact price, one to buy. Quartermaster searches between clicks on its own. You can also bind a key: Key Bindings > AddOns > Quartermaster.")
    panel.buy = buy

    local stop = MakeButton(panel, "Stop", 70, 34); stop:SetPoint("LEFT", buy, "RIGHT", 8, 0)
    stop:SetScript("OnClick", function() ns.Buyer:Stop() end)
    panel.stop = stop
    local reset = MakeButton(panel, "Reset bought", 100, 34); reset:SetPoint("LEFT", stop, "RIGHT", 8, 0)
    reset:SetScript("OnClick", function()
        ns.Buyer:Stop(true)
        if ns.char.cart.mode == "prebuilt" then CartTab:Recount(); CartTab:Refresh()
        else ns.Lists:ResetProgress(ns.Buyer:List()) end
    end)
    reset:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if ns.char.cart.mode == "prebuilt" then
            GameTooltip:AddLine("Recount", ACCENT[1], ACCENT[2], ACCENT[3])
            GameTooltip:AddLine("Counts your bags, bank and mailbox again and works out what's still missing.", 0.8, 0.85, 0.9, true)
        else
            GameTooltip:AddLine("Reset bought", ACCENT[1], ACCENT[2], ACCENT[3])
            GameTooltip:AddLine("Sets every item's bought count back to 0 so the whole list is bought again.", 0.8, 0.85, 0.9, true)
        end
        GameTooltip:Show()
    end)
    reset:HookScript("OnLeave", function() GameTooltip:Hide() end)
    panel.reset = reset

    panel.money = panel:CreateFontString(nil, "OVERLAY", "QuartermasterGameFontHighlightSmall")
    panel.money:SetPoint("BOTTOMRIGHT", -12, 22); panel.money:SetJustifyH("RIGHT")
    panel.spent = Muted(panel:CreateFontString(nil, "OVERLAY", "QuartermasterGameFontHighlightSmall"))
    panel.spent:SetPoint("TOPRIGHT", panel.money, "BOTTOMRIGHT", 0, -3); panel.spent:SetJustifyH("RIGHT")
    -- Background full scan (FullScan.lua): progress, paused, or up to date.
    panel.scan = panel:CreateFontString(nil, "OVERLAY", "QuartermasterGameFontHighlightSmall")
    panel.scan:SetPoint("BOTTOMRIGHT", panel.money, "TOPRIGHT", 0, 3); panel.scan:SetJustifyH("RIGHT")

    -- Find items: the live search panel in place of the list. Adds go to the active list.
    local findView = ns.AuctionSearch:Create(panel, { compact = true, target = function() return ns.Lists:Active() end })
    findView:SetPoint("TOPLEFT", 10, -44); findView:SetPoint("BOTTOMRIGHT", -10, 10)
    findView:Hide()
    findView.onEndEdit = function() CartTab:SetFind(false) end
    panel.findView = findView
    panel.cartParts = { panel.compare, view, holder, buy, stop, reset, panel.money, panel.spent, panel.scan }

    -- The button's enabled state depends on the AH throttle, which has no event; poll it lightly.
    local elapsed = 0
    panel:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.25 then return end
        elapsed = 0
        CartTab:UpdateButton()
    end)
    panel:SetScript("OnShow", function() ns.FullScan:Start(); CartTab:Recount(); CartTab:Refresh() end)
end

-- Shows the Find panel (live search) in place of the cart list, or the list again.
function CartTab:SetFind(on)
    if not panel then return end
    if on and ns.Buyer:Running() then return ns:Print("The Cart is buying. Stop it first.", true) end
    self.finding = on and true or false
    if not on then
        panel.findView:Stop()
        if panel.findView.editing then panel.findView.editing = nil end
    end
    panel.findView:SetShown(self.finding)
    for _, part in ipairs(panel.cartParts) do part:SetShown(not self.finding) end
    W.SetActive(panel.find, self.finding)
    panel.find.text:SetText(self.finding and "Back to cart" or "Find items")
    if self.finding then panel.findView:Refresh() else self:Refresh() end
end

-- Edits a search entry in the Find panel.
function CartTab:EditSearch(entry)
    self:SetFind(true)
    if self.finding then panel.findView:EditEntry(entry) end
end

function CartTab:UpdateButton()
    if not panel or self.finding then return end
    local text, enabled = ns.Buyer:ButtonState()
    local b = panel.buy
    b.text:SetText(text)
    b:SetEnabled(enabled)
    b.text:SetAlpha(enabled and 1 or 0.6)
    if enabled then
        b.fill:SetVertexColor(COOL_GREEN[1], COOL_GREEN[2], COOL_GREEN[3], 0.35)
        b:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    else
        b.fill:SetVertexColor(0, 0, 0, 0)
        b:SetBackdropBorderColor(PAL.border[1], PAL.border[2], PAL.border[3], 1)
    end
    panel.stop:SetEnabled(ns.Buyer:Running()); panel.stop:SetAlpha(ns.Buyer:Running() and 1 or 0.4)
end

-- What the Cart buys. In prebuilt mode it's a run rebuilt from the ticked lists, but only while
-- nothing is being bought, so counts don't shift under a run in progress.
function CartTab:Source()
    if ns.char.cart.mode ~= "prebuilt" then return ns.Lists:Active() end
    if not self.run or (self.runDirty and ns.Buyer.state == "idle") then
        self.run = ns.Prebuilt:BuildRun(ns.Prebuilt:TickedIDs())
        self.runDirty = false
    end
    return self.run
end

function CartTab:Recount() self.runDirty = true end

-- Whether the Cart has anything left to buy (decides where its tab goes, AHTabs.lua).
function CartTab:HasItems()
    for _, entry in ipairs(self:Source().entries) do
        if ns.Lists:Remaining(entry) > 0 then return true end
    end
    return false
end

local function TickedNames()
    local names = {}
    for _, id in ipairs(ns.Prebuilt:TickedIDs()) do names[#names + 1] = ns.Prebuilt:Get(id).name end
    return #names > 0 and table.concat(names, ", ") or "Pick prebuilt lists"
end

-- A search entry: what it matches, its price cap, and what it's buying right now.
local function SearchRow(entry, current)
    local remaining = ns.Lists:Remaining(entry)
    local f = entry.filter
    local detail = ("%d/%d bought  ·  "):format(entry.bought or 0, entry.qty)
    if f.maxPrice then detail = detail .. "pays up to " .. ns.Compat.Money(f.maxPrice) .. " each"
    else detail = detail .. ("pays up to market +%d%% (per item)"):format(ns.Lists:Tolerance(entry)) end
    if entry == current and ns.Buyer.group then
        local g = ns.Buyer.group
        detail = detail .. "  ·  now: " .. (g.link or g.name or "?")
        local c = ns.Buyer.candidate
        if c then detail = detail .. (" %dx at %s each"):format(c.count, ns.Compat.Money(c.unit)) end
    end
    local running = ns.Buyer:Running()
    return {
        icon = SEARCH_ICON, text = ns.Lists:Describe(entry), detail = detail,
        right = StatusText(entry),
        bar = entry.qty > 0 and math.min(1, (entry.bought or 0) / entry.qty) or nil, barText = "",
        selected = entry == current,
        dim = remaining == 0 and 0.55 or nil,
        hint = "A search: buys any items matching it, cheapest first.\n" .. ns.Search:Describe(f)
            .. "\nAuctionator: " .. (ns.Search:ToAuctionatorString(f, remaining) or "n/a"),
        actions = not running and { { "Edit", function() CartTab:EditSearch(entry) end, "Change this search in the Find panel" } } or nil,
    }
end

local function EntryRow(entry, current, prebuilt)
    if entry.filter then return SearchRow(entry, current) end
    -- Its own variant's price: an enchanted copy Auctionator can't price shows the price it was seen at.
    local market, seen = ns.Lists:Price(entry)
    local label = seen and "seen at" or "market"
    local e = ns.Catalog:Get(entry.itemID)
    local remaining = ns.Lists:Remaining(entry)
    local detail
    if prebuilt then
        detail = ("have %d / target %d (%s)"):format(entry.have, entry.target, ns.Stock:Describe(entry.itemID))
        if entry.qty > 0 then detail = detail .. ("  ·  buying %d/%d"):format(entry.bought or 0, entry.qty) end
        detail = detail .. "  ·  " .. label .. " " .. W.Money(market)
    else
        detail = ("%d/%d bought  ·  %s %s"):format(entry.bought or 0, entry.qty, label, W.Money(market))
    end
    if market and remaining > 0 then
        detail = detail .. ("  ·  pays up to %s"):format(ns.Compat.Money(market * (1 + ns.Lists:Tolerance(entry) / 100)))
    end
    local compare = ns.Compare:RowText(entry, remaining)
    if compare then detail = detail .. "  ·  " .. compare end
    if entry == current and ns.Buyer.candidate then
        local c = ns.Buyer.candidate
        detail = detail .. ("  ·  next: %dx at %s each"):format(c.count, ns.Compat.Money(c.unit))
    end
    local stocked = prebuilt and entry.qty == 0
    return {
        icon = W.IconFor(e or entry), link = entry.link or (e and e.link),
        text = ns.Lists:Describe(entry), detail = detail,
        right = stocked and "|cff59f28cstocked|r" or StatusText(entry),
        bar = prebuilt and entry.target > 0 and math.min(1, (entry.have + (entry.bought or 0)) / entry.target)
            or (entry.qty > 0 and math.min(1, (entry.bought or 0) / entry.qty)) or nil,
        barText = "",
        selected = entry == current,
        dim = (stocked or remaining == 0) and 0.55 or nil,
        hint = prebuilt and ("From: " .. table.concat(entry.from, ", ") .. "\nHave: " .. ns.Stock:Describe(entry.itemID)
            .. "\nAuction wins count from the moment you buy them, while they wait in your mailbox.") or nil,
    }
end

function CartTab:Refresh()
    if not panel or not panel:IsShown() then return end
    if self.finding and ns.Buyer:Running() then return self:SetFind(false) end
    if self.finding then return panel.findView:Refresh() end
    local prebuilt = ns.char.cart.mode == "prebuilt"
    W.SetActive(panel.modeList, not prebuilt); W.SetActive(panel.modePre, prebuilt)
    panel.picker:SetShown(not prebuilt); panel.ticks:SetShown(prebuilt)
    panel.reset.text:SetText(prebuilt and "Recount" or "Reset bought")

    local list = ns.Buyer:List()
    local current = ns.Buyer.entry
    -- The entries to show, by the view: what's still to buy first (in list order), then what's
    -- done, the most recently finished first. The one being bought always shows.
    local view, now = View()[1], time()
    local open, done, hidden = {}, {}, 0
    local function Take(entry, isPrebuilt)
        -- A prebuilt item already stocked (nothing to buy) counts as done long ago: its run is
        -- rebuilt on every recount, so a time on it wouldn't last.
        local at = (isPrebuilt and entry.qty == 0) and 0 or ns.Lists:DoneAt(entry)
        if not at then
            open[#open + 1] = { entry, isPrebuilt }
        elseif entry == current or view == "all" or (view == "recent" and now - at < RECENT) then
            done[#done + 1] = { entry, isPrebuilt, at }
        else
            hidden = hidden + 1
        end
    end
    for _, entry in ipairs(list.entries) do Take(entry, prebuilt) end
    if prebuilt then
        for _, entry in ipairs(list.covered or {}) do Take(entry, true) end
    end
    table.sort(done, function(a, b) return a[3] > b[3] end)
    local items = {}
    for _, o in ipairs(open) do items[#items + 1] = EntryRow(o[1], current, o[2]) end
    for _, o in ipairs(done) do items[#items + 1] = EntryRow(o[1], current, o[2]) end
    panel.view:SetValue(view, View()[2] .. (hidden > 0 and (" |cff8fa3b3(" .. hidden .. " hidden)|r") or ""))
    local allHidden = #items == 0 and hidden > 0
        and ("Everything here is bought (%d finished %s hidden). Show them: Everything, above."):format(hidden, hidden == 1 and "item" or "items")
    if prebuilt then
        panel.ticks:SetLabel(TickedNames())
        panel.list:Set(items, allHidden or (#ns.Prebuilt:TickedIDs() == 0
            and "Tick one or more prebuilt lists above, like Raid Night."
            or "Those prebuilt lists are empty. Add items in Quartermaster (/qm prebuilt)."))
    else
        panel.picker:SetValue(ns.char.activeList, list.name)
        panel.list:Set(items, allHidden or "This list is empty. Open Quartermaster (/qm) to add items.")
    end

    local total, unknown = ns.Lists:Estimate(list)
    panel.summary:SetText(("To buy: about %s%s  ·  tolerance %d%%"):format(ns.Compat.Money(total),
        unknown > 0 and (" + " .. unknown .. " unpriced") or "", ns.db.options.tolerance))
    ns.Compare:Check()
    panel.compare:SetText(ns.Compare:Summary(list))
    panel.money:SetText("Your gold: " .. ns.Compat.Money(GetMoney()))
    panel.scan:SetText(ns.FullScan:StatusText())
    panel.spent:SetText(ns.Buyer.spent > 0 and ("Spent this run: " .. ns.Compat.Money(ns.Buyer.spent)) or "")
    self:UpdateButton()
end

-- Opens the tab if the auction house is open. Returns true on success.
function CartTab:Select() return ns.AHTabs:Select("Cart") end

ns.AHTabs:Add("Cart", {
    label = "Cart", title = "Quartermaster Cart",
    build = function(parent) BuildPanel(parent); return panel end,
    onShow = function()
        if ns.Buyer.list == nil then ns.Buyer:SetList(ns.Lists:Active()) end
        CartTab:Refresh()
    end,
})
ns:On("PLAYER_MONEY", function() CartTab:Refresh() end)
ns:On("BAG_UPDATE_DELAYED", function()
    if ns.char and ns.char.cart.mode == "prebuilt" and ns.Buyer.state == "idle" then CartTab:Recount(); CartTab:Refresh() end
end)
