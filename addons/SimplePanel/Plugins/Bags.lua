local _, ns = ...

-- Bags: free slots, with a per-bag fill chart.
local T = SimplePanel.Theme
local C = ns.Compat

-- Bag families (the bit field GetContainerNumFreeSlots returns), with a name and an icon each.
local KINDS = {
    { 1, "Quiver", "Interface\\Icons\\INV_Ammo_Arrow_02" },
    { 2, "Ammo pouch", "Interface\\Icons\\INV_Ammo_Bullet_02" },
    { 4, "Soul bag", "Interface\\Icons\\INV_Misc_Gem_Amethyst_02" },
    { 8, "Leatherworking", "Interface\\Icons\\Trade_LeatherWorking" },
    { 16, "Inscription", "Interface\\Icons\\INV_Inscription_Tradeskill01" },
    { 32, "Herb bag", "Interface\\Icons\\Trade_Herbalism" },
    { 64, "Enchanting", "Interface\\Icons\\Trade_Engraving" },
    { 128, "Engineering", "Interface\\Icons\\Trade_Engineering" },
    { 256, "Keyring", "Interface\\Icons\\INV_Misc_Key_14" },
    { 512, "Gem bag", "Interface\\Icons\\INV_Misc_Gem_01" },
    { 1024, "Mining", "Interface\\Icons\\Trade_Mining" },
}
local NORMAL = { 0, "Bags", "Interface\\Icons\\INV_Misc_Bag_08" }
-- The reagent bag is a normal bag to the game (family 0), but a kind of its own here.
local REAGENT = { "reagent", "Reagent bag", "Interface\\Icons\\INV_Misc_Bag_10_Green", order = 0.5 }
local BACKPACK_ICON = 133633
-- Quivers and ammo pouches count the ammo in them, not their slots.
local AMMO = { [1] = true, [2] = true }
local LOW_AMMO = 200

local function KindOf(family, bag)
    if bag > C.NUM_BAGS then return REAGENT end
    if not family or family == 0 then return NORMAL end
    for _, k in ipairs(KINDS) do
        if family % (k[1] * 2) >= k[1] then return k end
    end
    return { family, "Special bag", "Interface\\Icons\\INV_Misc_Bag_10" }
end

-- The bag's own icon: the backpack's, or the equipped bag's.
local function BagIcon(bag)
    if bag == 0 then return BACKPACK_ICON end
    local toInv = (C_Container and C_Container.ContainerIDToInventoryID) or ContainerIDToInventoryID
    if not toInv then return nil end
    local ok, inv = pcall(toInv, bag)
    return ok and inv and GetInventoryItemTexture("player", inv) or nil
end

-- How much ammo a bag holds (every stack in it).
local function AmmoIn(bag)
    local n = 0
    for slot = 1, C.GetNumSlots(bag) do
        local info = ns.Items.GetSlotInfo(bag, slot)
        if info then n = n + (info.count or 1) end
    end
    return n
end

-- { name, free, total, special, kind, icon, ammo } for the backpack, each bag and the reagent bag
local function Scan(normalOnly)
    local bags, free, total = {}, 0, 0
    for bag = 0, C.NUM_BAGS + (ns.Items.NUM_REAGENT_BAGS or 0) do
        local slots = C.GetNumSlots(bag)
        if slots > 0 then
            local f, family = C.GetFreeSlots(bag)
            local kind = KindOf(family, bag)
            local special = kind ~= NORMAL -- the reagent bag too: its slots aren't the main bags'
            bags[#bags + 1] = { name = C.GetBagName(bag) or ("Bag " .. bag), free = f, total = slots, special = special, kind = kind,
                icon = BagIcon(bag) or kind[3], ammo = AMMO[kind[1]] and AmmoIn(bag) or nil }
            if not (normalOnly and special) then free, total = free + f, total + slots end
        end
    end
    return bags, free, total
end

-- Free and total slots (and ammo, for quivers and pouches) per kind of bag, normal bags first.
local function ByKind(bags)
    local list, index = {}, {}
    for _, b in ipairs(bags) do
        local k = b.kind
        local e = index[k[1]]
        if not e then
            -- the kind's icon is its first bag's (the backpack for normal bags)
            e = { kind = k, free = 0, total = 0, icon = b.icon }
            index[k[1]] = e
            list[#list + 1] = e
        end
        e.free, e.total = e.free + b.free, e.total + b.total
        if b.ammo then e.ammo = (e.ammo or 0) + b.ammo end
    end
    table.sort(list, function(a, b) return (a.kind.order or a.kind[1]) < (b.kind.order or b.kind[1]) end)
    return list
end

local function FreeColor(free) return free == 0 and T.red or (free <= 4 and T.yellow or nil) end
local function AmmoColor(n) return n == 0 and T.red or (n < LOW_AMMO and T.yellow or nil) end

-- A kind's figure: its ammo for quivers and pouches, else its free (and total) slots.
-- used: count the slots with something in them instead of the free ones (the colour still warns
-- when few are free).
local function SlotText(free, total, showTotal, used)
    local n = used and (total - free) or free
    return showTotal and (n .. "/" .. total) or tostring(n), FreeColor(free)
end

local function KindText(e, showTotal, used)
    if e.ammo then return ns.Format.Thousands(e.ammo), AmmoColor(e.ammo) end
    return SlotText(e.free, e.total, showTotal, used)
end

-- ---------------------------------------------------------------------------
-- Equipped bags: the menu shows them; right-click one to empty it into the others and put it away
-- ---------------------------------------------------------------------------

local I = ns.Items
local CC = C_Container
local EMPTY_SLOT = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"

-- The bag's inventory slot (for its icon, tooltip and PickupBagFromSlot).
local function InvSlot(bag)
    local fn = (CC and CC.ContainerIDToInventoryID) or ContainerIDToInventoryID
    if not fn then return nil end
    local ok, id = pcall(fn, bag)
    return ok and id or nil
end

local function IsReagentBag(bag) return bag > I.NUM_BAGS end

-- Can this item go in that bag? Reagent bags take crafting reagents; special bags their own family;
-- bags themselves only go in normal bags.
local function Fits(id, bag, family)
    if not id then return family == 0 and not IsReagentBag(bag) end
    if IsReagentBag(bag) then return select(17, I.GetItemInfo(id)) == true end
    local _, _, _, _, _, classID = I.GetItemInfoInstant(id)
    if classID == I.CLASS.CONTAINER or classID == I.CLASS.QUIVER then return family == 0 end
    if family == 0 then return true end
    return bit.band(I.GetItemFamily(id), family) ~= 0
end

-- The bags `src`'s items can go to: special and reagent bags first, so normal space is kept for
-- what fits nowhere else.
local function Dests(src)
    local list = {}
    for b = 0, I.NUM_BAGS + I.NUM_REAGENT_BAGS do
        if b ~= src and I.GetNumSlots(b) > 0 then
            local free, family = I.GetFreeSlots(b)
            list[#list + 1] = { bag = b, free = free, family = family, normal = family == 0 and not IsReagentBag(b) }
        end
    end
    table.sort(list, function(a, b)
        if a.normal ~= b.normal then return not a.normal end
        return a.bag < b.bag
    end)
    return list
end

-- How many more free slots emptying `src` and putting it in another bag needs (0: it can be done).
local function Shortfall(src)
    local dests, missing = Dests(src), 0
    for slot = 1, I.GetNumSlots(src) do
        local info = I.GetSlotInfo(src, slot)
        if info then
            local placed = false
            for _, d in ipairs(dests) do
                if d.free > 0 and Fits(info.id, d.bag, d.family) then d.free = d.free - 1; placed = true; break end
            end
            if not placed then missing = missing + 1 end
        end
    end
    -- the emptied bag itself needs a slot in a normal bag
    local normalFree = 0
    for _, d in ipairs(dests) do if d.normal then normalFree = normalFree + d.free end end
    if normalFree < 1 then missing = missing + 1 end
    return missing
end

-- An empty slot outside `src` that takes the item (id nil: a bag), not one in `taken`.
local function FindEmpty(id, src, taken)
    for _, d in ipairs(Dests(src)) do
        if Fits(id, d.bag, d.family) then
            for slot = 1, I.GetNumSlots(d.bag) do
                local key = d.bag * 1000 + slot
                if not taken[key] and not I.GetSlotInfo(d.bag, slot) then
                    taken[key] = true
                    return d.bag, slot
                end
            end
        end
    end
end

local function AnyLocked()
    for b = 0, I.NUM_BAGS + I.NUM_REAGENT_BAGS do
        for slot = 1, I.GetNumSlots(b) do
            local info = I.GetSlotInfo(b, slot)
            if info and info.locked then return true end
        end
    end
    return false
end

StaticPopupDialogs["SIMPLEPANEL_BAG_ROOM"] = {
    text = "%s", button1 = OKAY or "Okay",
    timeout = 0, whileDead = 1, hideOnEscape = 1, showAlert = 1, preferredIndex = 3,
}

-- Removing a bag that holds anchored items (Wally's sorter leaves those alone): move them to the
-- front of the backpack, still anchored, or release them.
StaticPopupDialogs["SIMPLEPANEL_BAG_ANCHOR"] = {
    text = "%s", button1 = "Move to front", button2 = CANCEL or "Cancel", button3 = "Release",
    OnAccept = function(_, data) data.start(true) end,
    OnAlt = function(_, data) data.start(false) end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}

-- Wally's bag sorting (WallyAPI version 3: sorting, auto sort and anchored items), when it's installed.
local function Wally()
    local api = WallyAPI
    return api and (tonumber(api.VERSION) or 0) >= 3 and api or nil
end

-- The anchored items in a bag: { { slot, id, link } }.
local function AnchoredIn(bag)
    local W, out = Wally(), {}
    if not W then return out end
    for _, a in ipairs(W.Anchors()) do
        if a.bag == bag then
            local info = I.GetSlotInfo(bag, a.slot)
            out[#out + 1] = { slot = a.slot, id = a.id, link = info and info.link }
        end
    end
    return out
end

-- Moves happen a few at a time: each waits for the server to confirm (the items stay locked till then).
local moving

local function Finish(msg)
    if moving then moving.ticker:Cancel(); moving = nil end
    if Wally() then Wally().HoldSorting("SimplePanel", false) end
    if msg then ns:Print(msg, true) end
end

-- One anchored item to the front of the backpack (the first slot that isn't anchored itself), a
-- move per tick: clear that slot, move the item in, then anchor it there. Returns true while busy.
local function FrontStep(m, taken)
    local a, W = m.front[1], Wally()
    if not a then return false end
    if not W then m.front = {}; return false end
    if not m.target then
        for slot = 1, I.GetNumSlots(0) do
            if not W.IsAnchored(0, slot) then m.target = slot; break end
        end
        if not m.target then
            Finish(("Couldn't move %s to the front: every backpack slot is anchored."):format(a.link or "the anchored item"))
            return true
        end
    end
    local here = I.GetSlotInfo(0, m.target)
    if m.placed and here and here.id == a.id then
        W.SetAnchor(0, m.target, true)
        table.remove(m.front, 1)
        m.target, m.placed = nil, nil
        return true
    end
    taken[m.target] = true
    if here then
        local db, ds = FindEmpty(here.id or -1, m.bag, { [m.target] = true })
        if not db then
            Finish(("Couldn't make room at the front of your backpack for %s."):format(a.link or "the anchored item"))
            return true
        end
        I.PickupItem(0, m.target); I.PickupItem(db, ds)
    else
        I.PickupItem(m.bag, a.slot); I.PickupItem(0, m.target)
        m.placed = true
    end
    if CursorHasItem() then ClearCursor() end
    m.settle = GetTime() + 0.3
    return true
end

local function Step()
    local m = moving
    if InCombatLockdown() then return Finish(("Stopped emptying %s: you entered combat."):format(m.name)) end
    if GetTime() > m.deadline then return Finish(("Stopped emptying %s: the items didn't move in time. Try again."):format(m.name)) end
    if CursorHasItem() or GetTime() < m.settle or AnyLocked() then return end
    if FrontStep(m, {}) then return end
    local taken, moved = {}, false
    for slot = 1, I.GetNumSlots(m.bag) do
        local info = I.GetSlotInfo(m.bag, slot)
        if info then
            local db, ds = FindEmpty(info.id or -1, m.bag, taken)
            if not db then return Finish(("Couldn't empty %s: no room left for %s."):format(m.name, info.link or "an item")) end
            I.PickupItem(m.bag, slot); I.PickupItem(db, ds)
            if CursorHasItem() then ClearCursor() end
            moved = true
        end
    end
    if moved then m.settle = GetTime() + 0.3; return end
    -- Empty: the bag itself goes in a normal bag.
    local db, ds = FindEmpty(nil, m.bag, taken)
    if not db then return Finish(("Emptied %s, but no normal bag has a free slot to put it in."):format(m.name)) end
    PickupBagFromSlot(m.inv); I.PickupItem(db, ds)
    if CursorHasItem() then ClearCursor() end
    Finish(("Emptied %s and put it in your bags."):format(m.name))
end

local function EmptyBag(bag)
    if moving then return ns:Print(("Still emptying %s."):format(moving.name), true) end
    if InCombatLockdown() then return ns:Print("Can't move bags in combat.", true) end
    if Wally() and Wally().IsSorting() then return ns:Print("Wait until Wally has finished sorting.", true) end
    local inv = InvSlot(bag)
    if not (inv and GetInventoryItemID("player", inv)) then return end
    local name = C.GetBagName(bag) or ("Bag " .. bag)
    local need = Shortfall(bag)
    if need > 0 then
        StaticPopup_Show("SIMPLEPANEL_BAG_ROOM", ("Emptying %s and putting it in your other bags needs %d more free slot%s."):format(
            name, need, need == 1 and "" or "s"))
        return
    end
    local function Start(front)
        if moving then return end
        local W = Wally()
        local anchored = AnchoredIn(bag)
        if W and not front then
            for _, a in ipairs(anchored) do W.SetAnchor(bag, a.slot, false) end
        end
        if W then W.HoldSorting("SimplePanel", true) end
        moving = { bag = bag, inv = inv, name = name, deadline = GetTime() + 30, settle = 0, front = front and anchored or {} }
        moving.ticker = C_Timer.NewTicker(0.1, Step)
    end
    local anchored = AnchoredIn(bag)
    if #anchored == 0 then return Start(false) end
    local what = #anchored == 1 and ("an anchored item, %s. Move it"):format(anchored[1].link or "")
        or ("%d anchored items. Move them"):format(#anchored)
    StaticPopup_Show("SIMPLEPANEL_BAG_ANCHOR", ("You're removing %s, which holds %s to the front of your backpack and keep %s anchored there?\n\nRelease: un-anchor and empty the bag as usual."):format(
        name, what, #anchored == 1 and "it" or "them"), nil, { start = Start })
end

-- The menu's row of bag slots: the reagent bag, then bags 4 to 1 (as on the bag bar).
local function SlotButtons()
    local slots = {}
    for bag = I.NUM_BAGS + I.NUM_REAGENT_BAGS, 1, -1 do
        local inv = InvSlot(bag)
        local equipped = inv and GetInventoryItemID("player", inv)
        local free = I.GetFreeSlots(bag)
        slots[#slots + 1] = {
            icon = equipped and GetInventoryItemTexture("player", inv) or EMPTY_SLOT,
            text = equipped and tostring(free) or nil, color = equipped and FreeColor(free) or nil,
            disabled = not equipped,
            border = IsReagentBag(bag) and T.yellow or nil, -- reagent bags in gold
            -- Lights up this bag's slots in Wally's bag window while hovered.
            onEnter = function() local W = Wally(); if W and W.HighlightBag then W.HighlightBag(bag) end end,
            onLeave = function() local W = Wally(); if W and W.HighlightBag then W.HighlightBag(nil) end end,
            tooltip = function(tt)
                if equipped then tt:SetInventoryItem("player", inv)
                else tt:SetText(IsReagentBag(bag) and "Reagent bag slot" or "Empty bag slot") end
                if equipped then
                    tt:AddLine(("%d free slot%s"):format(free, free == 1 and "" or "s"), 1, 1, 1)
                    tt:AddLine("Click: open this bag", T.muted[1], T.muted[2], T.muted[3])
                    tt:AddLine("Right-click: empty it into your other bags and put it away", T.muted[1], T.muted[2], T.muted[3], true)
                end
            end,
            fn = function(button)
                if button == "RightButton" then EmptyBag(bag)
                elseif ToggleBag then ns.SecureClick.Open(function() ToggleBag(bag) end, "that bag") end
            end,
        }
    end
    return slots
end

SimplePanel.RegisterPlugin({
    id = "Bags",
    name = "Bags",
    category = "Character",
    icon = 133633,
    zone = "right",
    label = "Bags",
    defaults = { normalOnly = true, showTotal = true, perKind = false, countUsed = false },
    events = { "BAG_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD" },

    text = function(p)
        local bags, free, total = Scan(p:Get("normalOnly"))
        -- A figure per kind: each with its own bag's icon, so the plugin's icon would repeat the first.
        p.hideIcon = p:Get("perKind") and true or nil
        if p:Get("perKind") then
            local segs = {}
            for _, e in ipairs(ByKind(bags)) do
                local text, color = KindText(e, p:Get("showTotal"), p:Get("countUsed"))
                segs[#segs + 1] = { icon = e.icon, text = text, color = color }
            end
            return segs
        end
        local text, color = SlotText(free, total, p:Get("showTotal"), p:Get("countUsed"))
        return { { text = text, color = color } }
    end,

    tooltip = function(p, tt)
        local bags, free, total = Scan(p:Get("normalOnly"))
        tt:AddDouble("Free slots", ("%d of %d"):format(free, total), nil, free == 0 and T.red or T.text)
        tt:AddDouble("Used slots", ("%d of %d"):format(total - free, total), nil, T.text)
        local kinds = ByKind(bags)
        if #kinds > 1 then
            for _, e in ipairs(kinds) do
                local right, color = ("%d of %d"):format(e.free, e.total), FreeColor(e.free)
                if e.ammo then right, color = ns.Format.Thousands(e.ammo) .. " ammo", AmmoColor(e.ammo) end
                tt:AddDouble(("|T%s:14:14:0:0:64:64:5:59:5:59|t %s"):format(tostring(e.icon), e.kind[2]), right,
                    T.text, color or T.text)
            end
        end
        local items = {}
        for _, b in ipairs(bags) do
            local used = b.total - b.free
            items[#items + 1] = { b.name .. (b.special and " |cff8fa3b3(special)|r" or ""), used / b.total * 100,
                b.free == 0 and T.red or (b.special and T.blue or nil), ("%d free"):format(b.free) }
        end
        tt:AddSpacer(2)
        tt:AddChart({ type = "hbarList", title = "How full", max = 100, items = items,
            thresholds = { { value = 90, color = T.yellow } } }, 260)
        tt:AddHint("Click: open bags. Right-click: your bags and options")
    end,

    menu = function(p, m)
        m:Slots({ slots = SlotButtons() })
        -- Sorting is Wally's (its Bag Sorting rules); anchored items are ctrl-right-clicked in the bags.
        local W = Wally()
        m:Button({ text = "Sort bags", disabled = not W, fn = function() W.SortBags() end,
            tooltip = W and "Sorts with Wally's Bag Sorting rules. Ctrl-right-click an item in your bags to anchor it: sorting leaves it where it is."
                or "Needs Wally, which does the sorting." })
        m:Submenu({ text = "Auto sort", disabled = not W, build = function(sub)
            for _, e in ipairs({ { "bags", "When your bags close" }, { "merchant", "When you leave a vendor" }, { "mail", "When you close the mailbox" } }) do
                sub:Checkbox({ text = e[2], get = function() return W.AutoSort(e[1]) end, set = function(v) W.SetAutoSort(e[1], v) end })
            end
            sub:Divider()
            local n = #W.Anchors()
            sub:Button({ text = ("Release anchored items (%d)"):format(n), disabled = n == 0,
                tooltip = "Lets sorting move every anchored item again.",
                fn = function() for _, a in ipairs(W.Anchors()) do W.SetAnchor(a.bag, a.slot, false) end end })
        end })
        m:Divider()
        m:Checkbox({ text = "Show total slots", get = function() return p:Get("showTotal") end, set = function(v) p:Set("showTotal", v) end })
        m:Checkbox({ text = "Count used slots", get = function() return p:Get("countUsed") end, set = function(v) p:Set("countUsed", v) end,
            tooltip = "Show how many slots hold something (36/56) instead of how many are free (20/56)." })
        m:Header("Shown as")
        m:Radio({ text = "One figure", value = false, get = function() return p:Get("perKind") end, set = function(v) p:Set("perKind", v) end })
        m:Radio({ text = "A figure per kind of bag", value = true, get = function() return p:Get("perKind") end, set = function(v) p:Set("perKind", v) end,
            tooltip = "Normal bags, the reagent bag, soul bags and profession bags each get their own count and icon; quivers and ammo pouches show how much ammo they hold." })
        m:Checkbox({ text = "Ignore special bags", get = function() return p:Get("normalOnly") end, set = function(v) p:Set("normalOnly", v) end,
            tooltip = "Don't count the reagent bag, quivers, ammo pouches, soul bags and the like.",
            disabled = function() return p:Get("perKind") end })
    end,

    -- Bags open through the game's own backpack button (see SecureClick.lua).
    secure = function() return ns.SecureClick.Click(MainMenuBarBackpackButton) end,
    secureInCombat = true,

    onClick = function(p, button)
        if button == "LeftButton" and not IsModifierKeyDown() and ToggleAllBags then ns.SecureClick.Open(ToggleAllBags, "your bags") end
    end,
})
