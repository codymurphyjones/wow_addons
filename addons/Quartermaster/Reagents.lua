local _, ns = ...

-- A Quartermaster section under the profession window: the selected recipe's reagents, how many of
-- each the Cart still has to buy, and buttons to add or take them off the order. Works with the
-- Blizzard_Professions window (ProfessionsFrame) and the older TradeSkillFrame / CraftFrame.
local Reagents = {}
ns.Reagents = Reagents

local W = ns.Widgets
local C = ns.Compat
local ACCENT, MUTED = W.ACCENT, W.MUTED
local MAX_ROWS = 8
local ROW_H, HEADER_H = 30, 34
local LEFT_W = 70           -- the "left over" column
local BUTTONS_W = 22 + 2 + 34 + 2 + 22 + 10 -- minus, count, plus, and the gap before them (MakeRow)

local function Call(name, ...)
    local fn = _G[name]
    if fn then return fn(...) end
end

-- ---------------------------------------------------------------------------
-- Windows. Each kind says where the window is, which recipe is selected and what it takes:
-- Read() returns { {itemID, name, link, texture, need, have}, ... }.
-- ---------------------------------------------------------------------------

-- Blizzard_Professions (ProfessionsFrame.CraftingPage.SchematicForm).
local currentRecipeID
local function SchematicForm()
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    return page and page.SchematicForm
end

local function SelectedRecipeID()
    local form = SchematicForm()
    if form and form.GetRecipeInfo then
        local ok, info = pcall(form.GetRecipeInfo, form)
        if ok and type(info) == "table" and info.recipeID then return info.recipeID end
    end
    return currentRecipeID
end

local BASIC = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic

local ItemCount = ns.Items.ItemCount

-- A recipe's basic reagents from C_TradeSkillUI (the Professions window and SimplePanel's).
local function ReadRecipe(recipeID)
    local api = C_TradeSkillUI
    if not (recipeID and api and api.GetRecipeSchematic) then return {} end
    local schematic = api.GetRecipeSchematic(recipeID, false)
    local out = {}
    for _, slot in ipairs(schematic and schematic.reagentSlotSchematics or {}) do
        local first = slot.reagents and slot.reagents[1]
        local basic = slot.required or not BASIC or slot.reagentType == BASIC
        if basic and first and first.itemID then
            local id = first.itemID
            local name, link, _, _, _, _, _, _, _, icon = C.GetItemInfo(id)
            if not name then C.RequestItem(id) end
            out[#out + 1] = { itemID = id, name = name, link = link,
                texture = icon or select(5, C.GetItemInfoInstant(id)),
                need = slot.quantityRequired or 0, have = ItemCount(id) }
        end
    end
    return out
end

-- SimplePanel's own professions window (Own Panels), when it holds the profession: the game's
-- window is kept open there but out of sight, so the section goes under SimplePanel's instead.
local function SimplePanelCrafting()
    local api = SimplePanelProfessions
    return api and api.IsCrafting and api.IsCrafting() or false
end

local PROFESSIONS = {
    name = "ProfessionsFrame",
    Frame = function() return ProfessionsFrame end,
    Active = function()
        local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
        return page and page:IsVisible() and not SimplePanelCrafting()
    end,
    Key = SelectedRecipeID,
    Read = function() return ReadRecipe(SelectedRecipeID()) end,
    Hook = function(kind)
        local form = SchematicForm()
        if not form or kind.hooked then return end
        kind.hooked = true
        if form.Init then
            hooksecurefunc(form, "Init", function(_, recipeInfo)
                currentRecipeID = recipeInfo and recipeInfo.recipeID or currentRecipeID
                Reagents:Refresh()
            end)
        end
        ProfessionsFrame:HookScript("OnShow", function() Reagents:Refresh() end)
        ProfessionsFrame.CraftingPage:HookScript("OnShow", function() Reagents:Refresh() end)
        ProfessionsFrame.CraftingPage:HookScript("OnHide", function() Reagents:Refresh() end)
    end,
}

-- Older TradeSkillFrame and CraftFrame (enchanting), driven by the GetTradeSkill*/GetCraft* API.
local function Legacy(frameName, prefix, hooks)
    local selected, num = "Get" .. prefix .. "SelectionIndex", "Get" .. prefix .. "NumReagents"
    local info, link = "Get" .. prefix .. "ReagentInfo", "Get" .. prefix .. "ReagentItemLink"
    return {
        name = frameName,
        Frame = function() return _G[frameName] end,
        Active = function() return _G[frameName]:IsShown() end,
        Key = function() return Call(selected) end,
        Read = function()
            local index = Call(selected)
            local out = {}
            if not index or index <= 0 then return out end
            for i = 1, Call(num, index) or 0 do
                local name, texture, need, have = Call(info, index, i)
                local l = Call(link, index, i)
                out[#out + 1] = { itemID = C.IDFromLink(l), name = name, link = l, texture = texture,
                    need = need or 0, have = have or 0 }
            end
            return out
        end,
        Hook = function(kind)
            kind.hookedFns = kind.hookedFns or {}
            for _, fn in ipairs(hooks) do
                if not kind.hookedFns[fn] and type(_G[fn]) == "function" then
                    kind.hookedFns[fn] = true
                    hooksecurefunc(fn, function() Reagents:Refresh() end)
                end
            end
            local frame = _G[frameName]
            if frame and not kind.hooked then
                kind.hooked = true
                frame:HookScript("OnShow", function() Reagents:Refresh() end)
            end
        end,
    }
end

local SIMPLEPANEL = {
    name = "SimplePanelProfessions",
    Frame = function() return SimplePanelProfessions and SimplePanelProfessions.GetFrame() end,
    Active = SimplePanelCrafting,
    Key = function() return SimplePanelProfessions and SimplePanelProfessions.GetSelectedRecipeID() end,
    Read = function() return ReadRecipe(SimplePanelProfessions.GetSelectedRecipeID()) end,
    Hook = function(kind)
        if kind.hooked or not (SimplePanelProfessions and SimplePanelProfessions.RegisterCallback) then return end
        kind.hooked = true
        SimplePanelProfessions.RegisterCallback("Quartermaster", function() Reagents:Refresh() end)
    end,
}

local KINDS = {
    PROFESSIONS,
    SIMPLEPANEL,
    Legacy("TradeSkillFrame", "TradeSkill", { "TradeSkillFrame_SetSelection", "TradeSkillFrame_Update" }),
    Legacy("CraftFrame", "Craft", { "CraftFrame_SetSelection", "CraftFrame_Update" }),
}

-- ---------------------------------------------------------------------------
-- Cart
-- ---------------------------------------------------------------------------

local function Source()
    return ns.CartTab and ns.CartTab:Source() or ns.Lists:Active()
end

-- The cart entry for a reagent: by itemID, or by name when the client gives no link.
local function FindEntry(source, itemID, name)
    if not source then return nil end
    if itemID then return ns.Lists:Find(source, itemID) end
    if not name then return nil end
    for _, entry in ipairs(source.entries) do
        if (entry.name or C.NameFromLink(entry.link)) == name then return entry end
    end
end

-- The selected recipe's reagents, each with what's on the cart.
local function ReadReagents(kind)
    local source = Source()
    local list = kind.Read()
    for _, d in ipairs(list) do
        local entry = FindEntry(source, d.itemID, d.name)
        d.itemID = d.itemID or (entry and entry.itemID)
        d.qty = entry and ns.Lists:Remaining(entry) or 0
        -- Same estimate as the Cart's "To buy: about ..." (Lists:Estimate).
        d.price = ns.Catalog:PriceFor(d.itemID)
        d.cost = d.price and d.price * d.qty
    end
    return list
end

-- Where clicks change the order: the active list, or in Prebuilt mode the prebuilt list Browse
-- adds to if it's ticked, else the first ticked one.
local function OrderList()
    if ns.char.cart.mode ~= "prebuilt" then return ns.Lists:Active() end
    local target, kind = ns.Lists:AddTarget()
    if kind == "template" and ns.char.cart.ticked[target.id] then return target end
    local first = ns.Prebuilt:TickedIDs()[1]
    return first and ns.Prebuilt:Get(first)
end

-- item is an itemID, or a name when the client gave no link (Lists:AddItem resolves names).
local function Adjust(item, delta)
    local list = OrderList()
    if not list then return ns:Print("Tick a prebuilt list in the Cart first.", true) end
    if delta > 0 then
        ns.Lists:AddItem(item, delta, list)
    else
        local entry = type(item) == "number" and ns.Lists:Find(list, item)
        if not entry then return end
        local qty = math.max(entry.bought or 0, entry.qty + delta)
        if qty <= 0 then ns.Lists:Remove(list, entry)
        else entry.qty = qty; ns:Changed() end
    end
    if ns.CartTab then ns.CartTab:Recount() end
end

local function Step() return IsShiftKeyDown() and 5 or 1 end

-- ---------------------------------------------------------------------------
-- Vendor reagents. Thread, wood, vials, dyes, flux...: anything a vendor sells isn't put on the
-- Cart. The Waypoint addon owns where vendors are and what they sell: Quartermaster asks it which
-- reagents vendors sell (Waypoint:SoldByVendors), and hands those to its popup
-- (Waypoint:PromptVendors): Navigate (its arrow leads to the nearest vendor selling them), Add
-- anyway (back here, onto the Cart), or Cancel. Without Waypoint, everything goes to the Cart.
-- ---------------------------------------------------------------------------

local function Vendors()
    return Waypoint and Waypoint.SoldByVendors and Waypoint.PromptVendors and Waypoint or nil
end

-- One click's additions: { { item, qty, name } }. Auction reagents go to the Cart as always;
-- vendor ones go to Waypoint's popup, once per click. kind: the recipe's window, so the trip
-- Navigate plans also ends at the auction house for its reagents still to buy there (on the Cart
-- from an earlier click too, not only this one's).
local function AddBatch(adds, kind)
    local wp, vendor, auction, seen = Vendors(), {}, {}, {}
    for _, a in ipairs(adds) do
        if a.qty > 0 then
            if wp and type(a.item) == "number" and wp:SoldByVendors(a.item) > 0 then
                vendor[#vendor + 1] = { id = a.item, qty = a.qty, name = a.name }
            else
                Adjust(a.item, a.qty)
                auction[#auction + 1] = { id = type(a.item) == "number" and a.item or nil, name = a.name }
                seen[a.item] = true
            end
        end
    end
    if #vendor > 0 and kind then
        for _, d in ipairs(ReadReagents(kind)) do
            local key = d.itemID or d.name
            if key and not seen[key] and d.qty > 0 and not (d.itemID and wp:SoldByVendors(d.itemID) > 0) then
                auction[#auction + 1] = { id = d.itemID, name = d.name }
                seen[key] = true
            end
        end
    end
    if #vendor > 0 then
        -- Navigate: the vendors, then the auction house for this recipe's reagents bought there.
        wp:PromptVendors(vendor, function(items)
            for _, it in ipairs(items) do Adjust(it.id, it.qty) end
        end, "Quartermaster", auction)
    end
end

-- ---------------------------------------------------------------------------
-- Panel
-- ---------------------------------------------------------------------------

local function MakeRow(panel, i)
    local row = CreateFrame("Frame", nil, panel)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 10, -HEADER_H - (i - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", -10, -HEADER_H - (i - 1) * ROW_H)

    local iconBox = CreateFrame("Frame", nil, row, "BackdropTemplate")
    iconBox:SetSize(26, 26); iconBox:SetPoint("LEFT")
    W.SetBackdrop(iconBox, 0.9)
    row.icon = iconBox:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("TOPLEFT", 1, -1); row.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    iconBox:EnableMouse(true)
    iconBox:SetScript("OnEnter", function(self)
        local d = row.data
        if not d or not (d.link or d.itemID) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(d.link or ("item:" .. d.itemID))
        GameTooltip:Show()
    end)
    iconBox:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local plus = W.MakeButton(row, "+", 22, 22); plus:SetPoint("RIGHT")
    row.count = row:CreateFontString(nil, "OVERLAY", "QuartermasterGameFontHighlight")
    row.count:SetWidth(34); row.count:SetJustifyH("CENTER")
    row.count:SetPoint("RIGHT", plus, "LEFT", -2, 0)
    local minus = W.MakeButton(row, "-", 22, 22); minus:SetPoint("RIGHT", row.count, "LEFT", -2, 0)
    plus:SetScript("OnClick", function()
        local d = row.data
        if d and (d.itemID or d.name) then AddBatch({ { item = d.itemID or d.name, qty = Step(), name = d.name } }, panel.kind) end
    end)
    minus:SetScript("OnClick", function()
        local d = row.data
        if d and d.itemID then Adjust(d.itemID, -Step()) end
    end)
    W.Hint(plus, "Add to cart", "Adds 1 (Shift: 5) to the list the Cart buys. Vendor-sold reagents ask to navigate to a vendor instead.")
    W.Hint(minus, "Take off cart", "Removes 1 (Shift: 5). Never below what you've already bought.")

    -- What's left of this reagent after crafting as many as the reagents cover (bags + cart).
    row.left = row:CreateFontString(nil, "OVERLAY", "QuartermasterGameFontHighlightSmall")
    row.left:SetWidth(LEFT_W); row.left:SetJustifyH("RIGHT")
    row.left:SetPoint("RIGHT", minus, "LEFT", -10, 0)

    row.name = row:CreateFontString(nil, "OVERLAY", "QuartermasterGameFontHighlightSmall")
    row.name:SetPoint("TOPLEFT", iconBox, "TOPRIGHT", 8, -1)
    row.name:SetPoint("RIGHT", row.left, "LEFT", -8, 0)
    row.name:SetJustifyH("LEFT"); row.name:SetWordWrap(false)
    row.detail = W.Muted(row:CreateFontString(nil, "OVERLAY", "QuartermasterGameFontHighlightSmall"))
    row.detail:SetPoint("BOTTOMLEFT", iconBox, "BOTTOMRIGHT", 8, 1)
    row.detail:SetPoint("RIGHT", row.left, "LEFT", -8, 0)
    row.detail:SetJustifyH("LEFT"); row.detail:SetWordWrap(false)
    return row
end

local function BuildPanel(kind, parent)
    local panel = CreateFrame("Frame", "QuartermasterReagentPanel" .. kind.name, parent, "BackdropTemplate")
    panel:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, -2)
    panel:SetPoint("TOPRIGHT", parent, "BOTTOMRIGHT", 0, -2)
    W.SetBackdrop(panel, 0.95)
    panel:EnableMouse(true)
    panel:Hide()
    panel.kind = kind

    local logo = panel:CreateTexture(nil, "ARTWORK"); logo:SetSize(20, 20)
    logo:SetPoint("TOPLEFT", 10, -7); logo:SetTexture(ns.ICON)
    local title = W.Label(panel, "Quartermaster", "QuartermasterGameFontNormal", 36, -10)
    title:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    panel.target = W.Muted(panel:CreateFontString(nil, "OVERLAY", "QuartermasterGameFontHighlightSmall"))
    panel.target:SetPoint("LEFT", title, "RIGHT", 10, 0)

    local all = W.MakeButton(panel, "Add all", 70, 22); all:SetPoint("TOPRIGHT", -10, -6)
    all:SetScript("OnClick", function()
        local times, adds = Step(), {}
        for _, row in ipairs(panel.rows) do
            local d = row:IsShown() and row.data
            if d and d.need > 0 and (d.itemID or d.name) then adds[#adds + 1] = { item = d.itemID or d.name, qty = d.need * times, name = d.name } end
        end
        AddBatch(adds, kind)
    end)
    W.Hint(all, "Add all reagents", "Adds what one craft needs of every reagent (Shift: five crafts).")

    -- Add needed: evens the reagents out one craft at a time. Each reagent covers (have + on the
    -- cart) / need crafts; one click raises the fewest covered by one (Shift: five) and tops every
    -- reagent up to that, so only what's missing is added. Read fresh at the click, so fast clicks
    -- count what the previous ones added.
    local needed = W.MakeButton(panel, "Add needed", 84, 22); needed:SetPoint("RIGHT", all, "LEFT", -6, 0)
    needed:SetScript("OnClick", function()
        local reagents = {}
        for _, d in ipairs(ReadReagents(kind)) do
            if d.need > 0 and (d.itemID or d.name) then reagents[#reagents + 1] = d end
        end
        if #reagents == 0 then return end
        local fewest = math.huge
        for _, d in ipairs(reagents) do fewest = math.min(fewest, math.floor((d.have + d.qty) / d.need)) end
        local crafts, adds = fewest + Step(), {}
        for _, d in ipairs(reagents) do
            local missing = crafts * d.need - (d.have + d.qty)
            if missing > 0 then adds[#adds + 1] = { item = d.itemID or d.name, qty = missing, name = d.name } end
        end
        AddBatch(adds, kind)
    end)
    W.Hint(needed, "Add needed reagents", "Evens out your reagents one craft at a time: counts how many crafts each reagent covers "
        .. "(in your bags plus on the cart), then adds only what's missing for one more craft than the lowest (Shift: five more).")

    -- Reset: this recipe's reagents off the order (down to what's already bought), nothing else.
    local reset = W.MakeButton(panel, "Reset", 60, 22); reset:SetPoint("RIGHT", needed, "LEFT", -6, 0)
    reset:SetScript("OnClick", function()
        local list = OrderList()
        if not list then return ns:Print("Tick a prebuilt list in the Cart first.", true) end
        local changed = false
        for _, d in ipairs(kind.Read()) do
            local entry = FindEntry(list, d.itemID, d.name)
            if entry then
                if (entry.bought or 0) > 0 then entry.qty = entry.bought else ns.Lists:Remove(list, entry) end
                changed = true
            end
        end
        if changed then
            ns:Changed()
            if ns.CartTab then ns.CartTab:Recount() end
        end
    end)
    W.Hint(reset, "Reset this recipe", "Takes this recipe's reagents off the list you're adding to, back to what you've already bought. "
        .. "Other items on the list stay.")
    panel.target:SetPoint("RIGHT", reset, "LEFT", -10, 0)
    panel.target:SetJustifyH("LEFT"); panel.target:SetWordWrap(false)

    panel.rows = {}
    for i = 1, MAX_ROWS do panel.rows[i] = MakeRow(panel, i) end
    panel.empty = W.Muted(panel:CreateFontString(nil, "OVERLAY", "QuartermasterGameFontHighlightSmall"))
    panel.empty:SetPoint("TOPLEFT", 12, -HEADER_H)
    panel.empty:SetText("Pick a recipe to see its reagents.")
    -- How many the reagents cover, right under the "left over" column.
    panel.crafts = panel:CreateFontString(nil, "OVERLAY", "QuartermasterGameFontHighlightSmall")
    panel.crafts:SetPoint("BOTTOMRIGHT", -(10 + BUTTONS_W), 9)
    panel.crafts:SetJustifyH("RIGHT")
    panel.total = panel:CreateFontString(nil, "OVERLAY", "QuartermasterGameFontHighlightSmall")
    panel.total:SetPoint("BOTTOMLEFT", 12, 9)
    panel.total:SetPoint("RIGHT", panel.crafts, "LEFT", -10, 0)
    panel.total:SetJustifyH("LEFT")
    kind.panel = panel
    return panel
end

local function RefreshKind(kind)
    local frame = kind.Frame()
    if not frame then return end
    kind.Hook(kind)
    local panel = kind.panel or BuildPanel(kind, frame)
    if not (frame:IsShown() and kind.Active()) then panel:Hide() return end
    panel:Show()
    local list = OrderList()
    panel.target:SetText(list and ("Adding to: " .. list.name) or "Tick a prebuilt list in the Cart")
    local reagents = ReadReagents(kind)
    -- Crafts the reagents cover: with the cart (have + to buy), and from your bags alone.
    local crafts, now
    for _, d in ipairs(reagents) do
        if d.need > 0 then
            crafts = math.min(crafts or math.huge, math.floor((d.have + d.qty) / d.need))
            now = math.min(now or math.huge, math.floor(d.have / d.need))
        end
    end
    local total, unpriced = 0, 0
    for i, row in ipairs(panel.rows) do
        local d = reagents[i]
        row.data = d
        if d then
            row.icon:SetTexture(d.texture or W.UNKNOWN_ICON)
            row.icon:SetDesaturated(d.qty == 0)
            row.name:SetText(d.link or d.name or ("item:" .. tostring(d.itemID)))
            local detail = ("need %d  ·  have %d  ·  each %s"):format(d.need, d.have, W.Money(d.price))
            if d.qty > 0 then
                detail = detail .. "  ·  cart " .. W.Money(d.cost)
                if d.cost then total = total + d.cost else unpriced = unpriced + 1 end
            end
            row.detail:SetText(detail)
            if crafts and d.need > 0 then
                local left = d.have + d.qty - crafts * d.need
                row.left:SetText(("%d left"):format(left))
                local c = left > 0 and ACCENT or MUTED
                row.left:SetTextColor(c[1], c[2], c[3])
            else
                row.left:SetText("")
            end
            row.count:SetText(d.qty)
            local color = d.qty > 0 and ACCENT or MUTED
            row.count:SetTextColor(color[1], color[2], color[3])
            row:Show()
        else
            row:Hide()
        end
    end
    local shown = math.min(#reagents, MAX_ROWS)
    panel.empty:SetShown(shown == 0)
    if total > 0 or unpriced > 0 then
        panel.total:SetText(("Cart for this recipe: %s%s"):format(C.Money(total),
            unpriced > 0 and (" |cff8fa3b3(+" .. unpriced .. " unpriced)|r") or ""))
        panel.total:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    else
        panel.total:SetText(shown > 0 and "Nothing from this recipe on the cart yet" or "")
        panel.total:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
    end
    if crafts then
        panel.crafts:SetText(("Can craft |cffffffff%d|r%s"):format(crafts,
            now < crafts and (" |cff8fa3b3(%d from bags)|r"):format(now) or ""))
    else
        panel.crafts:SetText("")
    end
    panel:SetHeight(HEADER_H + math.max(shown, 1) * ROW_H + 24)
end

local reported
local function DoRefresh()
    if not ns.char then return end
    for _, kind in ipairs(KINDS) do
        local ok, err = pcall(RefreshKind, kind)
        if not ok and not reported then
            reported = true
            ns:Print("reagent panel failed: " .. tostring(err) .. " (type /qm reagents for details)", true)
        end
    end
end

-- Coalesced and deferred a frame, so Blizzard has updated the selection first.
local pending
function Reagents:Refresh()
    if pending then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        DoRefresh()
    end)
end

local function Refresh() Reagents:Refresh() end

ns:OnLoad(Refresh)
-- Prices change when Auctionator finishes a scan.
ns:OnLoad(function()
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if api and api.RegisterForDBUpdate then pcall(api.RegisterForDBUpdate, ns.CALLER, Refresh) end
end)
ns:On("ADDON_LOADED", Refresh)
for _, event in ipairs({ "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED", "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE",
    "TRADE_SKILL_LIST_UPDATE", "CRAFT_SHOW", "CRAFT_UPDATE" }) do
    ns:On(event, Refresh)
end

-- A cheap safety net for when no hook fires: refresh when the selected recipe changes.
local watcher = CreateFrame("Frame")
local elapsed, lastKey = 0, {}
watcher:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.2 then return end
    elapsed = 0
    for _, kind in ipairs(KINDS) do
        local frame = kind.Frame()
        if frame and frame:IsShown() then
            local ok, key = pcall(kind.Key)
            key = ok and key or nil
            if key ~= lastKey[kind] or not kind.panel then lastKey[kind] = key; Refresh() end
        end
    end
end)

-- /qm reagents: what the profession window looks like to us, step by step.
function Reagents:Debug()
    local P = function(s) ns:Print(s, true) end
    local source = Source()
    local list = OrderList()
    P(("cart mode %s, source \"%s\" with %d entries, adding to \"%s\""):format(ns.char.cart.mode,
        source and source.name or "?", source and #source.entries or 0, list and list.name or "none"))
    for _, kind in ipairs(KINDS) do
        local frame = kind.Frame()
        local panel = kind.panel
        P(("%s: %s; panel %s; hooked %s"):format(kind.name, frame and (frame:IsShown() and "shown" or "hidden") or "missing",
            panel and ((panel:IsShown() and "shown " or "hidden ") .. table.concat({ panel:GetRect() }, ",")) or "none",
            tostring(kind.hooked)))
        if frame and frame:IsShown() then
            local okKey, key = pcall(kind.Key)
            local ok, reagents = pcall(ReadReagents, kind)
            P(("  active %s, selected %s, %s"):format(tostring(kind.Active()), tostring(okKey and key),
                ok and (#reagents .. " reagents") or ("ERROR " .. tostring(reagents))))
            for i, d in ipairs(ok and reagents or {}) do
                P(("  %d: %s, link %s, item %s, need %d, have %d, to buy %d"):format(i, tostring(d.name),
                    tostring(d.link), tostring(d.itemID), d.need, d.have, d.qty))
            end
        end
    end
end
