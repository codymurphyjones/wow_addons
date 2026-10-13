local _, ns = ...
local C = ns.Compat

-- Wally's own bag sorter. Blizzard's sort can't be configured, so items are moved a swap at a time
-- with PickupContainerItem. Every tick rescans the bags and recomputes where everything belongs,
-- so loot, sales and server lag can't throw it out of step.
local Sorter = {}
ns.Sorter = Sorter

local TICK = 0.05
local SWAPS_PER_TICK = 4
local MAX_MOVES = 600
local MAX_SECONDS = 30
local CURSOR_PATIENCE = 20 -- ticks
local CLASS_CONTAINER, CLASS_QUIVER = 1, 11

-- Sort rules. dir = labels for { ascending, descending }.
Sorter.CRITERIA = {
    { key = "category", label = "Group", dir = { "In order", "Reversed" }, hint = "Uses the group order on the right." },
    { key = "quality", label = "Quality", dir = { "Low first", "Best first" }, desc = true },
    { key = "ilvl", label = "Item level", dir = { "Low first", "High first" }, desc = true },
    { key = "reqlevel", label = "Required level", dir = { "Low first", "High first" }, desc = true },
    { key = "slot", label = "Equip slot", dir = { "Head to feet", "Feet to head" }, hint = "Head, neck, shoulders ... feet, then rings, trinkets and weapons." },
    { key = "name", label = "Name", dir = { "A to Z", "Z to A" } },
    { key = "worth", label = "Worth", dir = { "Low first", "High first" }, desc = true,
        hint = "Auction price from Auctionator, or Wally's estimate from rarity, tier and kind. Whole stack." },
    { key = "value", label = "Sell value", dir = { "Cheap first", "Pricey first" }, desc = true, hint = "Vendor price of the whole stack." },
    { key = "count", label = "Stack size", dir = { "Small first", "Big first" }, desc = true },
}

Sorter.CATEGORIES = {
    { key = "hearth", label = "Hearthstone & keys" },
    { key = "consumable", label = "Consumables" },
    { key = "quest", label = "Quest items" },
    { key = "gear", label = "Weapons & armor" },
    { key = "trade", label = "Trade goods & reagents" },
    { key = "recipe", label = "Recipes" },
    { key = "container", label = "Bags & quivers" },
    { key = "ammo", label = "Ammo" },
    { key = "misc", label = "Everything else" },
}

Sorter.PRESETS = {
    { label = "Blizzard", hint = "Group, then best quality, then most valuable, then highest item level, then name.",
        list = { { "category" }, { "quality", true }, { "worth", true }, { "ilvl", true }, { "name" } } },
    { label = "Quality", hint = "Best quality first, then most valuable, then by group and name.",
        list = { { "quality", true }, { "worth", true }, { "category" }, { "name" } } },
    { label = "Type", hint = "By group, gear by equip slot, then highest item level.",
        list = { { "category" }, { "slot" }, { "ilvl", true }, { "name" } } },
    { label = "A to Z", hint = "Alphabetical, nothing else.", list = { { "name" } } },
}

local EQUIP_ORDER = {}
for i, loc in ipairs({ "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_CLOAK", "INVTYPE_CHEST",
    "INVTYPE_ROBE", "INVTYPE_BODY", "INVTYPE_TABARD", "INVTYPE_WRIST", "INVTYPE_HAND", "INVTYPE_WAIST",
    "INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_FINGER", "INVTYPE_TRINKET", "INVTYPE_2HWEAPON", "INVTYPE_WEAPON",
    "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND", "INVTYPE_SHIELD", "INVTYPE_HOLDABLE", "INVTYPE_RANGED",
    "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN", "INVTYPE_RELIC", "INVTYPE_AMMO", "INVTYPE_BAG", "INVTYPE_QUIVER" }) do
    EQUIP_ORDER[loc] = i
end

local HEARTHSTONE = { [6948] = true }

local function CategoryOf(id, classID)
    if HEARTHSTONE[id] or classID == 13 then return "hearth" end
    if classID == 0 then return "consumable" end
    if classID == 12 then return "quest" end
    if classID == 2 or classID == 4 then return "gear" end
    if classID == 7 or classID == 5 or classID == 3 then return "trade" end
    if classID == 9 then return "recipe" end
    if classID == CLASS_CONTAINER or classID == CLASS_QUIVER then return "container" end
    if classID == 6 then return "ammo" end
    return "misc"
end

-- ---------------------------------------------------------------------------
-- Saved settings
-- ---------------------------------------------------------------------------

-- Drops unknown or duplicate entries and adds anything missing, keeping the user's order.
function Sorter:Validate()
    local opt = ns.db.options.sort
    local known, out, seen = {}, {}, {}
    for _, c in ipairs(self.CRITERIA) do known[c.key] = c end
    if #opt.criteria == 0 then
        for _, p in ipairs(self.PRESETS[1].list) do
            out[#out + 1] = { key = p[1], on = true, desc = p[2] or false }; seen[p[1]] = true
        end
    end
    for _, c in ipairs(opt.criteria) do
        if type(c) == "table" and known[c.key] and not seen[c.key] then
            seen[c.key] = true
            out[#out + 1] = { key = c.key, on = c.on and true or false, desc = c.desc and true or false }
        end
    end
    for _, c in ipairs(self.CRITERIA) do
        if not seen[c.key] then out[#out + 1] = { key = c.key, on = false, desc = c.desc or false } end
    end
    opt.criteria = out

    local cats, cseen, cknown = {}, {}, {}
    for _, c in ipairs(self.CATEGORIES) do cknown[c.key] = true end
    for _, k in ipairs(opt.categories) do
        if cknown[k] and not cseen[k] then cseen[k] = true; cats[#cats + 1] = k end
    end
    for _, c in ipairs(self.CATEGORIES) do
        if not cseen[c.key] then cats[#cats + 1] = c.key end
    end
    opt.categories = cats

    local pins, pseen = {}, {}
    for _, p in ipairs(opt.pinned) do
        if type(p) == "string" then p = { key = ns.Key(p), name = p } end
        if type(p) == "table" and p.key and not pseen[p.key] then pseen[p.key] = true; pins[#pins + 1] = p end
    end
    opt.pinned = pins
end
ns:OnLoad(function() Sorter:Validate() end)

function Sorter:CriterionInfo(key)
    for _, c in ipairs(self.CRITERIA) do if c.key == key then return c end end
end

function Sorter:CategoryLabel(key)
    for _, c in ipairs(self.CATEGORIES) do if c.key == key then return c.label end end
    return key
end

function Sorter:ApplyPreset(index)
    local preset = self.PRESETS[index]
    if not preset then return end
    local opt = ns.db.options.sort
    opt.criteria = {}
    for _, p in ipairs(preset.list) do opt.criteria[#opt.criteria + 1] = { key = p[1], on = true, desc = p[2] or false } end
    self:Validate()
    ns:Changed()
end

-- Swaps list[index] with its neighbour (delta -1 = up, +1 = down).
function Sorter:MoveEntry(list, index, delta)
    local j = index + delta
    if j < 1 or j > #list then return end
    list[index], list[j] = list[j], list[index]
    ns:Changed()
end

function Sorter:Pin(input)
    local key, meta, pendingID = ns.Lists:Resolve(input)
    if pendingID then
        if Item and Item.CreateFromItemID then
            Item:CreateFromItemID(pendingID):ContinueOnItemLoad(function() Sorter:Pin(pendingID) end)
        end
        return
    end
    if not key then
        ns:Print("Couldn't find an item called " .. tostring(input) .. ".", true)
        return
    end
    local pins = ns.db.options.sort.pinned
    for _, p in ipairs(pins) do if p.key == key then return end end
    pins[#pins + 1] = { key = key, name = meta and meta.name or key, link = meta and meta.link, icon = meta and meta.icon }
    ns:Changed()
end

function Sorter:Unpin(key)
    local pins = ns.db.options.sort.pinned
    for i = #pins, 1, -1 do if pins[i].key == key then table.remove(pins, i) end end
    ns:Changed()
end

function Sorter:IsIgnored(bag) return ns.char.sortIgnore[bag] == true end

function Sorter:SetIgnored(bag, ignored)
    ns.char.sortIgnore[bag] = ignored and true or nil
    ns:Changed()
end

-- One line describing what Sort does right now, for the settings view.
function Sorter:Describe()
    local opt = ns.db.options.sort
    local parts = {}
    if #opt.pinned > 0 then parts[#parts + 1] = "pinned items" end
    if (opt.protectTop or 0) > 0 or opt.protectRare then parts[#parts + 1] = "protected valuables" end
    if opt.reagentsByWorth then parts[#parts + 1] = "reagents by worth" end
    for _, c in ipairs(opt.criteria) do
        if c.on then
            local info = self:CriterionInfo(c.key)
            parts[#parts + 1] = info.label:lower() .. " (" .. info.dir[c.desc and 2 or 1]:lower() .. ")"
        end
    end
    if opt.junkLast then parts[#parts + 1] = "junk last" end
    if #parts == 0 then return "Sort only packs items together and merges stacks." end
    return "Sort orders by " .. table.concat(parts, ", then ") .. ", filling from the " ..
        (opt.fillFromEnd and "end of your last bag." or "start of your backpack.")
end

-- ---------------------------------------------------------------------------
-- Item data (cached per link for one sort run)
-- ---------------------------------------------------------------------------

local cache

local function Data(info)
    local link = info.link
    local d = cache and cache[link]
    if d then return d end
    local name, _, quality, ilvl, reqLevel, _, _, maxStack, equipLoc, _, price, classID = C.GetItemInfo(link)
    local id = info.id or C.IDFromLink(link) or 0
    if not name then
        -- Not loaded yet: sort it by what the link says, and look again next tick.
        C.RequestItem(id)
        local fallback = C.NameFromLink(link) or ""
        return { id = id, key = ns.Key(fallback), name = fallback:lower(), quality = info.quality or 1, ilvl = 0,
            reqlevel = 0, slot = 99, price = 0, worth = 0, maxStack = 1, category = "misc", family = 0, junk = false }
    end
    -- Locked slots never count as junk; the verdict shouldn't depend on a pickup in progress.
    local wasLocked = info.locked
    info.locked = nil
    local isJunk = ns.JunkFilter:Evaluate(link, info)
    info.locked = wasLocked
    d = {
        id = id, key = ns.Key(name), name = name:lower(), quality = quality or info.quality or 1,
        ilvl = ilvl or 0, reqlevel = reqLevel or 0, slot = EQUIP_ORDER[equipLoc] or 99, price = price or 0,
        worth = ns.Value:UnitWorth(link) or 0,
        maxStack = maxStack or 1, classID = classID, category = CategoryOf(id, classID),
        family = C.GetItemFamily(id), junk = isJunk and true or false,
    }
    if cache then cache[link] = d end
    return d
end

-- Whether an item may sit in a bag of this family. Bags never go inside special bags.
local function Fits(d, family)
    if family == 0 then return true end
    if d.classID == CLASS_CONTAINER or d.classID == CLASS_QUIVER then return false end
    return bit.band(d.family or 0, family) ~= 0
end

-- ---------------------------------------------------------------------------
-- Sorting
-- ---------------------------------------------------------------------------

local function Scan(which)
    local slots = {}
    for _, bag in ipairs(C.BagList(which)) do
        if not Sorter:IsIgnored(bag) then
            local family = C.GetBagFamily(bag)
            for slot = 1, C.GetNumSlots(bag) do
                local info = C.GetSlotInfo(bag, slot)
                local s = { bag = bag, slot = slot, family = family }
                if info and info.link then
                    s.info, s.d = info, Data(info)
                    s.key = info.link .. "#" .. (info.count or 1)
                end
                slots[#slots + 1] = s
            end
        end
    end
    return slots
end

local function Compare(a, b)
    if a.pin ~= b.pin then return a.pin < b.pin end
    -- Protected valuables come straight after pinned items, most valuable first.
    if a.protected ~= b.protected then return a.protected end
    if a.protected and a.v.worth ~= b.v.worth then return a.v.worth > b.v.worth end
    if a.junk ~= b.junk then return not a.junk end
    if a.reagent and b.reagent and a.v.worth ~= b.v.worth then return a.v.worth > b.v.worth end
    for _, c in ipairs(a.criteria) do
        if c.on then
            local va, vb = a.v[c.key], b.v[c.key]
            if va ~= vb then
                if c.desc then return va > vb end
                return va < vb
            end
        end
    end
    if a.d.id ~= b.d.id then return a.d.id < b.d.id end
    if a.link ~= b.link then return a.link < b.link end
    return a.count > b.count
end

-- Decides which entry belongs in each slot. Returns the slots in fill order and a slot -> entry map.
local function Plan(slots)
    local opt = ns.db.options.sort
    local pinRank, catRank = {}, {}
    for i, p in ipairs(opt.pinned) do pinRank[p.key] = i end
    for i, k in ipairs(opt.categories) do catRank[k] = i end

    -- The most valuable stacks among the slots being sorted (bags or bank).
    local infos = {}
    for _, s in ipairs(slots) do if s.info then infos[#infos + 1] = s.info end end
    local protected = ns.Value:RankSlots(infos)

    local entries = {}
    for _, s in ipairs(slots) do
        if s.info then
            local d, count = s.d, s.info.count or 1
            local isProtected = protected[s.info.link] ~= nil
            entries[#entries + 1] = {
                d = d, link = s.info.link, count = count, key = s.key, criteria = opt.criteria,
                pin = (d.key and pinRank[d.key]) or math.huge,
                protected = isProtected,
                junk = opt.junkLast and d.junk and not isProtected or false,
                reagent = opt.reagentsByWorth and d.category == "trade" or false,
                v = { category = catRank[d.category] or 99, quality = d.quality, ilvl = d.ilvl, reqlevel = d.reqlevel,
                    slot = d.slot, name = d.name, value = d.price * count, worth = d.worth * count, count = count },
            }
        end
    end
    table.sort(entries, Compare)

    local order = {}
    if opt.fillFromEnd then
        for i = #slots, 1, -1 do order[#order + 1] = slots[i] end
    else
        for i = 1, #slots do order[i] = slots[i] end
    end

    -- Special bags take the first items that fit them; everything else fills normal bags in order.
    local target, taken = {}, {}
    for _, s in ipairs(order) do
        if s.family ~= 0 then
            for i, e in ipairs(entries) do
                if not taken[i] and Fits(e.d, s.family) then taken[i] = true; target[s] = e; break end
            end
        end
    end
    local i = 1
    for _, s in ipairs(order) do
        if s.family == 0 then
            while taken[i] do i = i + 1 end
            if entries[i] then taken[i] = true; target[s] = entries[i] end
        end
    end
    return order, target
end

local function Swap(from, to)
    C.PickupItem(from.bag, from.slot)
    C.PickupItem(to.bag, to.slot)
    -- If the drop was refused (wrong bag type), put the item back where it came from.
    if CursorHasItem() then ClearCursor() end
end

-- Tops up partial stacks from later ones. Returns acted, waiting.
function Sorter:MergeStacks(slots)
    local partial, acted, waiting, used = {}, false, false, 0
    for _, s in ipairs(slots) do
        local info = s.info
        if info and s.d.maxStack > 1 and (info.count or 1) < s.d.maxStack then
            local first = partial[info.link]
            if not first then
                partial[info.link] = s
            elseif first.info.locked or info.locked then
                waiting = true
                partial[info.link] = nil
            else
                local pairKey = s.bag .. ":" .. s.slot .. ">" .. first.bag .. ":" .. first.slot
                local tries = self.mergeTries[pairKey] or 0
                if tries < 2 and used < SWAPS_PER_TICK then
                    self.mergeTries[pairKey] = tries + 1
                    Swap(s, first)
                    used, acted, self.moves = used + 1, true, self.moves + 1
                    partial[info.link] = nil
                else
                    partial[info.link] = s
                end
            end
        end
    end
    return acted, waiting
end

-- Moves items toward their planned slots. Returns done, acted, waiting.
function Sorter:Arrange(slots)
    local order, target = Plan(slots)
    local used, swaps, mismatched, acted, waiting = {}, 0, false, false, false
    local function Correct(t) return t.key == (target[t] and target[t].key) end

    for _, s in ipairs(order) do
        if not Correct(s) then
            mismatched = true
            local want = target[s]
            if want and swaps < SWAPS_PER_TICK and not used[s] then
                local src
                for _, t in ipairs(order) do
                    if t ~= s and t.key == want.key and not used[t] and not Correct(t) then src = t; break end
                end
                if not src then
                    waiting = true
                elseif src.info.locked or (s.info and s.info.locked) then
                    waiting = true
                elseif s.info and not Fits(s.d, src.family) then
                    -- What's here can't go into src's special bag: park it in an empty slot it fits first.
                    for _, e in ipairs(order) do
                        if not e.info and not used[e] and e ~= s and Fits(s.d, e.family) then
                            Swap(s, e)
                            used[s], used[e], swaps, acted, self.moves = true, true, swaps + 1, true, self.moves + 1
                            break
                        end
                    end
                else
                    Swap(src, s)
                    used[s], used[src], swaps, acted, self.moves = true, true, swaps + 1, true, self.moves + 1
                end
            end
        end
    end
    return not mismatched, acted, waiting
end

function Sorter:IsBusy() return self.ticker ~= nil end

function Sorter:Start(which, auto)
    which = which == "bank" and "bank" or "bags"
    local function Fail(msg) if not auto then ns:Print(msg, true) end end
    if self.ticker then return Fail("Already sorting.") end
    if InCombatLockdown() then return Fail("Can't sort bags in combat.") end
    if CursorHasItem() then return Fail("Put down the item on your cursor first.") end
    if ns.Seller:IsBusy() then return Fail("Wait until Wally has finished selling.") end
    if which == "bank" and not self.bankOpen then return Fail("Open your bank first.") end
    cache = {}
    self.which, self.moves, self.started, self.cursorWait, self.mergeTries = which, 0, GetTime(), 0, {}
    self.ticker = C_Timer.NewTicker(TICK, function() Sorter:Tick() end)
    self:RefreshButtons()
    ns:Changed()
end

function Sorter:Stop(msg, force)
    if not self.ticker then return end
    self.ticker:Cancel()
    self.ticker, cache = nil, nil
    if msg then ns:Print(msg, force) end
    self:RefreshButtons()
    ns:Changed()
end

function Sorter:Tick()
    local what = self.which == "bank" and "Bank" or "Bags"
    if InCombatLockdown() then return self:Stop("Sorting stopped: you entered combat.", true) end
    if self.which == "bank" and not self.bankOpen then return self:Stop("Sorting stopped: the bank closed.", true) end
    if self.moves >= MAX_MOVES or GetTime() - self.started > MAX_SECONDS then
        return self:Stop("Sorting stopped because it was taking too long. Click Sort again to carry on.", true)
    end
    if CursorHasItem() then
        self.cursorWait = self.cursorWait + 1
        if self.cursorWait > CURSOR_PATIENCE then self:Stop("Sorting stopped: you picked up an item.", true) end
        return
    end
    self.cursorWait = 0

    local slots = Scan(self.which)
    local acted, waiting = self:MergeStacks(slots)
    if acted or waiting then return end
    local done
    done, acted, waiting = self:Arrange(slots)
    if done then
        return self:Stop(self.moves > 0 and (what .. " sorted.") or (what .. " are already sorted."))
    end
    if not acted and not waiting then
        self:Stop("Couldn't finish sorting: some items won't move. Try again in a moment.", true)
    end
end

-- ---------------------------------------------------------------------------
-- Sort buttons on the game's bag and bank windows
-- ---------------------------------------------------------------------------

local bagButton, bankButton

local function OnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(self.which == "bank" and "Sort bank" or "Sort bags", 0.33, 0.92, 0.78)
    GameTooltip:AddLine("Sorted by Wally, using your rules in Options > AddOns > Wally > Bag Sorting.", 0.82, 0.89, 0.93, true)
    GameTooltip:AddLine("Left-click: sort", 0.75, 0.8, 0.85)
    GameTooltip:AddLine("Right-click: sort options", 0.75, 0.8, 0.85)
    GameTooltip:Show()
end

local function CreateSortButton(name, which)
    local b = CreateFrame("Button", name, UIParent)
    b.which = which
    b:SetSize(24, 24)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local atlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("bags-button-autosort-up")
    if not (atlas and b.SetNormalAtlas and pcall(b.SetNormalAtlas, b, "bags-button-autosort-up")) then
        b:SetNormalTexture(ns.ICON)
        b:SetPushedTexture(ns.ICON)
        b:GetPushedTexture():SetVertexColor(0.7, 0.7, 0.7)
    elseif b.SetPushedAtlas then
        pcall(b.SetPushedAtlas, b, "bags-button-autosort-down")
    end
    b:SetHighlightTexture("Interface/Buttons/ButtonHilight-Square", "ADD")
    b:SetScript("OnEnter", OnEnter)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then ns.UI:OpenSettings("sorting") else Sorter:Start(self.which) end
    end)
    b:Hide()
    return b
end

-- Takes the spot of Blizzard's own sort button when the client has one, and keeps that one hidden
-- so there's only ever one sort button. Otherwise uses `fallback`.
local hookedBlizz = {}
-- Blizzard's update code shows its button again on every bag change; keep it hidden while ours is on.
local function HideBlizzard(blizz)
    if not blizz then return end
    if not hookedBlizz[blizz] then
        hookedBlizz[blizz] = true
        blizz:HookScript("OnShow", function(self) if ns.db.options.sort.bagButton then self:Hide() end end)
    end
    blizz:Hide()
end

local function Place(b, parent, blizz, fallback)
    b:SetParent(parent)
    b:SetFrameLevel(parent:GetFrameLevel() + 10)
    b:ClearAllPoints()
    HideBlizzard(blizz)
    if blizz and blizz:GetParent() == parent and blizz:GetNumPoints() > 0 then
        b:SetPoint("CENTER", blizz, "CENTER")
    else
        fallback(b, parent)
    end
end

local function BackpackFrame()
    local combined = _G.ContainerFrameCombinedBags
    if combined and combined:IsShown() then return combined end
    for i = 1, NUM_CONTAINER_FRAMES or 13 do
        local f = _G["ContainerFrame" .. i]
        if f and f:IsShown() and f:GetID() == 0 then return f end
    end
end

local function IsInside(frame, ancestor)
    local f = frame and frame:GetParent()
    while f do
        if f == ancestor then return true end
        f = f:GetParent()
    end
    return false
end

-- The bag window's search box. It may sit in a child frame, and it often isn't shown yet at the
-- moment the bag opens, so belonging to the window counts as much as being on screen.
-- Clients name it differently, so fall back to the first edit box inside the window.
local function FindEditBox(frame, depth)
    if depth > 4 then return nil end
    for _, child in ipairs({ frame:GetChildren() }) do
        if child:GetObjectType() == "EditBox" and child:IsShown() then return child end
        local found = FindEditBox(child, depth + 1)
        if found then return found end
    end
end

function Sorter:FindSearchBox(parent)
    for _, box in ipairs({ parent.SearchBox, _G.BagItemSearchBox }) do
        if box and box.GetParent and (IsInside(box, parent) or box:IsVisible()) then return box end
    end
    return FindEditBox(parent, 1)
end

-- Troubleshooting: where the sort button and its neighbours are. Kept in WallyCharDB.sortDebug
-- (written to disk on /reload) and printed by /wally sortdebug.
local function DebugLines()
    local function Name(f)
        if not f then return "none" end
        return (f.GetName and f:GetName()) or tostring(f)
    end
    local function Where(f)
        if not f or f:GetNumPoints() == 0 then return "no anchor" end
        local point, rel, relPoint, x, y = f:GetPoint(1)
        local left, bottom = f:GetLeft(), f:GetBottom()
        return ("%s to %s %s (%d, %d), screen %s,%s size %dx%d"):format(point, Name(rel), relPoint or "?", x or 0, y or 0,
            left and math.floor(left) or "?", bottom and math.floor(bottom) or "?", f:GetWidth() or 0, f:GetHeight() or 0)
    end
    local function Kids(f)
        local out = {}
        for _, k in ipairs({ f:GetChildren() }) do
            if k:IsShown() then out[#out + 1] = Name(k) .. "[" .. (k.GetObjectType and k:GetObjectType() or "?") .. "]" end
        end
        return table.concat(out, ", ")
    end
    local parent = BackpackFrame()
    local search = parent and Sorter:FindSearchBox(parent)
    local g, blizz = _G.BagItemSearchBox, _G.BagItemAutoSortButton
    local lines = {
        "Side setting: " .. tostring(ns.db.options.sort.buttonSide) .. ", button on: " .. tostring(ns.db.options.sort.bagButton),
        "Backpack frame: " .. Name(parent) .. (parent and (" " .. Where(parent)) or ""),
        ("Search box used: %s"):format(search and (Name(search) .. " " .. Where(search)) or "none"),
        ("Global search box: %s (parent %s, visible %s)"):format(g and "yes" or "no", g and Name(g:GetParent()) or "-",
            g and tostring(g:IsVisible()) or "-"),
        ("Blizzard sort button: %s (parent %s, shown %s, %s)"):format(blizz and "yes" or "no",
            blizz and Name(blizz:GetParent()) or "-", blizz and tostring(blizz:IsShown()) or "-", blizz and Where(blizz) or "-"),
        ("Wally sort button: %s (parent %s, shown %s, visible %s, %s)"):format(bagButton and "yes" or "no",
            bagButton and Name(bagButton:GetParent()) or "-", bagButton and tostring(bagButton:IsShown()) or "-",
            bagButton and tostring(bagButton:IsVisible()) or "-", bagButton and Where(bagButton) or "-"),
        "Backpack children: " .. (parent and Kids(parent) or "-"),
    }
    return lines
end

function Sorter:Debug()
    local lines = DebugLines()
    ns.char.sortDebug = { time = date("%H:%M:%S"), lines = lines, err = self.lastError }
    for _, line in ipairs(lines) do ns:Print(line, true) end
    if self.lastError then ns:Print("Last error: " .. self.lastError, true) end
end

function Sorter:RefreshButtons()
    if not ns.db then return end
    local ok, err = pcall(self.PlaceButtons, self)
    self.lastError = not ok and tostring(err) or self.lastError
    if BackpackFrame() then
        local okLines, lines = pcall(DebugLines)
        ns.char.sortDebug = { time = date("%H:%M:%S"), lines = okLines and lines or { tostring(lines) }, err = self.lastError }
    end
end

function Sorter:PlaceButtons()
    local show = ns.db.options.sort.bagButton
    local busy = self:IsBusy()
    local parent = show and BackpackFrame()
    if parent then
        bagButton = bagButton or CreateSortButton("WallyBagSortButton", "bags")
        local search = Sorter:FindSearchBox(parent)
        local hasSearch = search ~= nil
        local blizz = _G.BagItemAutoSortButton
        if (ns.db.options.sort.buttonSide or "left") == "left" then
            -- Left of the search box, or the top-left of the bag window if there isn't one.
            Place(bagButton, parent, nil, function(b, p)
                -- The search box's border art reaches past its frame, so clear that too.
                if hasSearch then b:SetPoint("RIGHT", search, "LEFT", -8, 0)
                else b:SetPoint("TOPLEFT", p, "TOPLEFT", 36, -30) end
            end)
            HideBlizzard(blizz)
        else
            Place(bagButton, parent, blizz, function(b, p)
                if hasSearch then
                    b:SetPoint("LEFT", search, "RIGHT", 4, 0)
                else
                    b:SetPoint("TOPRIGHT", p, "TOPRIGHT", -10, -30)
                end
            end)
        end
        bagButton:Show()
    elseif bagButton then
        bagButton:Hide()
    end
    if bagButton then bagButton:SetAlpha(busy and 0.5 or 1) end

    local bank = _G.BankFrame
    if show and self.bankOpen and bank and bank:IsShown() then
        bankButton = bankButton or CreateSortButton("WallyBankSortButton", "bank")
        Place(bankButton, bank, _G.BankItemAutoSortButton, function(b, p)
            local close = _G.BankCloseButton
            if close and close:GetParent() == p then
                b:SetPoint("RIGHT", close, "LEFT", -2, 0)
            else
                b:SetPoint("TOPRIGHT", p, "TOPRIGHT", -60, -44)
            end
        end)
        bankButton:Show()
    elseif bankButton then
        bankButton:Hide()
    end
    if bankButton then bankButton:SetAlpha(busy and 0.5 or 1) end
end

-- Classic hands out ContainerFrameN to whichever bag opens first, so check after every open or close.
-- Checked again a moment later, once Blizzard has finished laying out the window and its search box.
local function QueueRefresh()
    C_Timer.After(0, function() Sorter:RefreshButtons() end)
    C_Timer.After(0.2, function() Sorter:RefreshButtons() end)
end

ns:On("PLAYER_LOGIN", function()
    for i = 1, NUM_CONTAINER_FRAMES or 13 do
        local f = _G["ContainerFrame" .. i]
        if f then f:HookScript("OnShow", QueueRefresh); f:HookScript("OnHide", QueueRefresh) end
    end
    local combined = _G.ContainerFrameCombinedBags
    if combined then combined:HookScript("OnShow", QueueRefresh); combined:HookScript("OnHide", QueueRefresh) end
    local search = _G.BagItemSearchBox
    if search then search:HookScript("OnShow", QueueRefresh) end
    QueueRefresh()
end)

ns:On("BANKFRAME_OPENED", function() Sorter.bankOpen = true; QueueRefresh() end)
ns:On("BANKFRAME_CLOSED", function()
    Sorter.bankOpen = false
    if Sorter.which == "bank" then Sorter:Stop("Sorting stopped: the bank closed.", true) end
    QueueRefresh()
end)
ns:On("PLAYER_REGEN_DISABLED", function()
    if Sorter:IsBusy() then Sorter:Stop("Sorting stopped: you entered combat.", true) end
end)
ns:On("MERCHANT_CLOSED", function()
    if ns.db.options.sort.onMerchantClose then C_Timer.After(0.3, function() Sorter:Start("bags", true) end) end
end)
