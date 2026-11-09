local _, ns = ...
local PAL = ns.Palette
local C = ns.Compat
local W = ns.Widgets

-- Wally's bag window: the backpack, your bags and the reagent bag in one Wally-styled window, in place
-- of the game's bag windows (Options > AddOns > Wally > Bag window). The game's own bag windows still
-- open and close as usual (the B key, the bag bar, a vendor, the bank), only off the screen: this
-- window follows them, so every way of opening bags opens it. Bank bags stay the game's.
-- The slots are the game's own item buttons, borrowed from its bag windows: the game made them, so
-- clicking one to use an item is the game's own click. (Buttons Wally made from the same template
-- were Wally's: the 12.x engine blocks UseContainerItem from them, "Wally tried to call the
-- protected function UNKNOWN()", in combat and out.) A slot whose game window isn't open gets a
-- button of Wally's own, which shows and moves items but can't use the ones that cast something.
-- The reagent bag sits in a panel of its own under the bags (gold edge and heading, its own free
-- count), its slots in the same columns, and only while its game window is open, as the game
-- shows it: "Open All Bags" (B) opens it, the backpack button doesn't.
-- Only the look: sorting and everything else treat its slots as before.
local Bags = {}
ns.BagWindow = Bags

local SIZE, GAP, PAD = 37, 4, 12
local TOP, BOTTOM = 62, 34            -- header (title, search, buttons) and footer (free slots, money)
local GOLD = { 1, 0.82, 0.30 }
-- The reagent panel: its space above the bags' last row, its edge out from the slots (into the
-- window's padding, so its slots line up with the bags'), and its heading's height.
local SECTION_GAP, INSET, HEAD = 14, 6, 20

local frame, content, dock, search, freeText, moneyText
local reagentPanel, reagentLabel, reagentFree -- the reagent bag's panel, its heading and free count
local holders, buttons, list = {}, {}, {} -- bag -> holder frame; "bag:slot" -> Wally's button; shown buttons
local bagOf, slotOf = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" }) -- shown button -> bag, slot
local borrowed = setmetatable({}, { __mode = "k" }) -- the game's buttons this window has shown
local home = setmetatable({}, { __mode = "k" }) -- a borrowed button -> the game frame it came from

local function Enabled() return ns.db and ns.db.options.bags.window end
local closeSecure, closeX -- the X's secure button (a window of its own) and the X it covers (Build)

-- Puts the secure button over the X while this window shows, and hides it with the window. Only
-- out of combat (it's protected): in combat it waits, and the plain X answers clicks meanwhile.
local function PlaceClose()
    if not (closeSecure and closeX) then return end
    if InCombatLockdown() then return ns:AfterCombat("wallyBagsClosePlace", PlaceClose) end
    local show = frame ~= nil and frame:IsShown() and closeX:GetLeft() ~= nil
    if show then
        local s = closeX:GetEffectiveScale() / UIParent:GetEffectiveScale()
        closeSecure:ClearAllPoints()
        closeSecure:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", closeX:GetLeft() * s, closeX:GetBottom() * s)
        closeSecure:SetSize(closeX:GetWidth() * s, closeX:GetHeight() * s)
    end
    if closeSecure:IsShown() ~= show then closeSecure:SetShown(show) end
end
function Bags:Enabled() return Enabled() and true or false end

local function PlayerBags()
    local out = C.BagList("bags")
    for _, b in ipairs(C.BagList("reagent")) do out[#out + 1] = b end
    return out
end

local function IsReagent(bag) return bag > C.NUM_BAGS end

-- ---------------------------------------------------------------------------
-- The game's bag windows: kept working, out of sight
-- ---------------------------------------------------------------------------

local function BlizzardFrames()
    local out = { _G.ContainerFrameCombinedBags }
    for i = 1, NUM_CONTAINER_FRAMES or 13 do out[#out + 1] = _G["ContainerFrame" .. i] end
    return out
end

-- Which bag a game bag window shows (the combined one shows the backpack and bags).
local function IsPlayerBagFrame(f)
    if f == _G.ContainerFrameCombinedBags then return true end
    local id = f.GetID and f:GetID()
    return type(id) == "number" and id >= 0 and id <= C.NUM_BAGS + C.NUM_REAGENT_BAGS
end

-- A player bag window goes off the screen. (Not behind a hidden parent: a window that isn't
-- visible gets no OnShow, which is where it starts listening for bag updates, and its buttons, now
-- in this window, would stop updating.) The game places its windows again whenever one opens or
-- closes (UpdateContainerFrameAnchors); this runs after that. Bank bag windows that the game had
-- stacked on top of the bags move down into their place.
local function Away()
    if not Enabled() then return end
    -- (Not ContainerFrameSettingsManager:GetBagsShown(): it can rebuild its list, and a list built
    -- while Wally's code runs would be Wally's for every later use by the game.)
    local prev
    for _, f in pairs(BlizzardFrames()) do
        if f and f:IsShown() then
            if IsPlayerBagFrame(f) then
                f:SetClampedToScreen(false)
                f:ClearAllPoints()
                f:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", -2000, -2000)
            else
                f:ClearAllPoints()
                if prev then
                    f:SetPoint("BOTTOMRIGHT", prev, "TOPRIGHT", 0, CONTAINER_SPACING or 0)
                else
                    local right = EditModeUtil and EditModeUtil.GetRightActionBarWidth and EditModeUtil:GetRightActionBarWidth() or 0
                    f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -(right + 10), CONTAINER_OFFSET_Y or 70)
                end
                prev = f
            end
        end
    end
end

-- Other addons' frames on the game's bag windows (Plumber's item tracker and the like) would be
-- hidden with them, so they move into this window's dock, under the slots, stacked in the order
-- they were found. The bag windows' own children, there when Wally loaded, stay where they are.
local native, docked, dockOrder = {}, {}, {}
for _, f in pairs(BlizzardFrames()) do
    if f then for _, c in ipairs({ f:GetChildren() }) do native[c] = true end end
end

local function Foreign(c)
    if native[c] or docked[c] or c.GetBagID then return false end
    if c.GetObjectType and c:GetObjectType() == "ItemButton" then return false end
    local name = c.GetName and c:GetName()
    if not name then return true end
    for _, prefix in ipairs({ "Wally", "ContainerFrame", "BagItem", "Backpack", "Blizzard", "GamepadBagBar" }) do
        if name:find("^" .. prefix) then return false end
    end
    return true
end

local placing, dockQueued
local Layout
local function QueueDock()
    if dockQueued then return end
    dockQueued = true
    C_Timer.After(0, function()
        dockQueued = false
        if frame and frame:IsShown() then Layout() end
    end)
end

-- Stacks the docked frames that are showing; returns the height they take.
local function PlaceDock(width)
    local y = 0
    placing = true
    for _, c in ipairs(dockOrder) do
        if c:GetParent() == dock and c:IsShown() then
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", dock, "TOPLEFT", 0, -y)
            y = y + (c:GetHeight() or 0) + GAP
        end
    end
    placing = false
    dock:SetSize(width, math.max(1, y))
    return y > 0 and y or 0
end

local function Adopt()
    if not dock then return end
    placing = true
    for _, f in pairs(BlizzardFrames()) do
        if f and IsPlayerBagFrame(f) then
            for _, c in ipairs({ f:GetChildren() }) do
                if Foreign(c) then
                    docked[c] = true
                    dockOrder[#dockOrder + 1] = c
                    -- Its addon may move, resize, show or re-parent it later: dock it again then.
                    for _, m in ipairs({ "Show", "Hide", "SetShown", "SetSize", "SetWidth", "SetHeight", "SetPoint", "SetParent" }) do
                        if c[m] then hooksecurefunc(c, m, function() if not placing then QueueDock() end end) end
                    end
                end
                if docked[c] and c:GetParent() ~= dock then c:SetParent(dock) end
            end
        end
    end
    placing = false
end

-- Whether the game's reagent bag window is open.
local function ReagentOpen()
    for _, f in pairs(BlizzardFrames()) do
        if f and f:IsShown() and f ~= _G.ContainerFrameCombinedBags and IsPlayerBagFrame(f) then
            local id = f:GetID()
            if type(id) == "number" and id > C.NUM_BAGS then return true end
        end
    end
    return false
end

local function AnyBagOpen()
    for _, f in pairs(BlizzardFrames()) do
        if f and f:IsShown() and IsPlayerBagFrame(f) then return true end
    end
    return false
end

-- Points the X at the game's close button of every player bag window that's open: a /click macro
-- when they all have names, else a click on the first (the combined bag window closes them all).
-- Attributes can't change in combat; they're set again after it.
local function SetCloseTarget()
    if not closeSecure then return end
    if InCombatLockdown() then return ns:AfterCombat("wallyBagsClose", SetCloseTarget) end
    local targets, names = {}, {}
    for _, f in pairs(BlizzardFrames()) do
        if f and f:IsShown() and IsPlayerBagFrame(f) and f.CloseButton then
            targets[#targets + 1] = f.CloseButton
            local name = f.CloseButton:GetName()
            if name then names[#names + 1] = "/click " .. name end
        end
    end
    if #targets > 0 and #names == #targets then
        closeSecure:SetAttribute("type", "macro")
        closeSecure:SetAttribute("macrotext", table.concat(names, "\n"))
    else
        closeSecure:SetAttribute("type", "click")
        closeSecure:SetAttribute("clickbutton", targets[1])
    end
end

local syncQueued
local function Sync()
    if syncQueued then return end
    syncQueued = true
    C_Timer.After(0, function()
        syncQueued = false
        if not frame then return end
        local open = Enabled() and AnyBagOpen()
        if open ~= frame:IsShown() then frame:SetShown(open) end
        if open then SetCloseTarget() end
    end)
end

-- ---------------------------------------------------------------------------
-- Slots
-- ---------------------------------------------------------------------------

local function Edge(b, color)
    for _, t in ipairs(b.wallyEdge) do t:SetColorTexture(color[1], color[2], color[3], 1) end
end

-- Wally's own slot, for a bag whose game window isn't open (bags opened with the backpack button):
-- a plain button, not the game's item button template. Made by Wally, the template's click was
-- Wally's too, and using an item through it was blocked ("Wally tried to call the protected
-- function UseContainerItem()"). So its clicks are its own: left click and drag pick up and put
-- down, shift-click links, right-click sells at a vendor. Using an item needs the game's own
-- button: right-click says how to get it (open the bags with B).
local useHintAt = 0
local function OwnClick(self, button)
    local bag, slot = bagOf[self], slotOf[self]
    if not (bag and slot) then return end
    local info = self.wallyInfo
    if IsModifiedClick() then
        if info and info.link and HandleModifiedItemClick and HandleModifiedItemClick(info.link) then return end
        if button == "RightButton" then return end -- (Ctrl-right-click anchors it: Sort.lua)
    end
    if button == "LeftButton" then
        C.PickupItem(bag, slot)
    elseif MerchantFrame and MerchantFrame:IsShown() and info and not CursorHasItem() then
        C.UseContainerItem(bag, slot)
    elseif info and GetTime() - useHintAt > 5 then
        useHintAt = GetTime()
        ns:Print("This bag's own game window isn't open, so its items can't be used from here (the game "
            .. "only lets its own buttons do that). Close your bags and open them with B: every slot works then.", true)
    end
end

local function NewButton(bag, slot)
    local holder = holders[bag]
    if not holder then
        holder = CreateFrame("Frame", nil, content)
        holder:SetID(bag); holder:SetAllPoints(content)
        holders[bag] = holder
    end
    -- (The slot is its ID and the bag its holder's, as Sort.lua reads a slot.)
    local b = CreateFrame("Button", nil, holder)
    b:SetID(slot)
    b:SetSize(SIZE, SIZE)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1); b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.Count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.Count:SetPoint("BOTTOMRIGHT", -3, 3)
    b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cooldown:SetAllPoints(b.icon)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnClick", OwnClick)
    b:SetScript("OnDragStart", function(self) if bagOf[self] then C.PickupItem(bagOf[self], slotOf[self]) end end)
    b:SetScript("OnReceiveDrag", function(self) if bagOf[self] then C.PickupItem(bagOf[self], slotOf[self]) end end)
    b:SetScript("OnEnter", function(self)
        if not bagOf[self] then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetBagItem(bagOf[self], slotOf[self])
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b.wallyOwn = true
    return b
end

-- Wally's well on a slot (its own or the game's): a dark field and a 1px edge in place of the game's
-- art. Only fields named wally... are written on the game's buttons: its own code never reads them.
local function Style(b, bag)
    local normal = b:GetNormalTexture()
    if normal then normal:SetAlpha(0) end
    if b.wallyBg then
        b.wallyBg:Show()
        for _, t in ipairs(b.wallyEdge) do t:Show() end
        Edge(b, IsReagent(bag) and GOLD or PAL.border)
        return
    end
    b.wallyBg = b:CreateTexture(nil, "BACKGROUND", nil, -8)
    b.wallyBg:SetAllPoints(); b.wallyBg:SetColorTexture(PAL.field[1], PAL.field[2], PAL.field[3], 1)
    b.wallyEdge = {}
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 1 }, { "TOPRIGHT", "BOTTOMRIGHT", 1 } }) do
        local t = b:CreateTexture(nil, "OVERLAY", nil, 6)
        t:SetPoint(side[1]); t:SetPoint(side[2])
        if side[3] then t:SetWidth(side[3]) else t:SetHeight(side[4]) end
        b.wallyEdge[#b.wallyEdge + 1] = t
    end
    Edge(b, IsReagent(bag) and GOLD or PAL.border)
end

-- The game's buttons in its open bag windows: "bag:slot" -> button.
local function GameButtons()
    local out = {}
    for _, f in pairs(BlizzardFrames()) do
        if f and f:IsShown() and IsPlayerBagFrame(f) and f.EnumerateValidItems then
            local ok, iter, state, key = pcall(f.EnumerateValidItems, f)
            if ok and iter then
                for _, b in iter, state, key do
                    local okb, bag = pcall(b.GetBagID, b)
                    local slot = b.GetID and b:GetID()
                    if okb and type(bag) == "number" and type(slot) == "number" and slot > 0 then
                        out[bag .. ":" .. slot] = b
                    end
                end
            end
        end
    end
    return out
end

-- Gives one of the game's buttons back to its window.
local function Return(b)
    local h = home[b] or b.containerFrame
    if h and b:GetParent() ~= h then b:SetParent(h) end
    b:SetAlpha(1)
    if b.wallyBg then
        b.wallyBg:Hide()
        for _, t in ipairs(b.wallyEdge) do t:Hide() end
    end
    local normal = b:GetNormalTexture()
    if normal then normal:SetAlpha(1) end
    borrowed[b], bagOf[b], slotOf[b] = nil, nil, nil
end

-- Gives the game's buttons back to their windows (the option turned off).
local function GiveBack()
    for b in pairs(borrowed) do Return(b) end
    wipe(borrowed)
end

local function Matches(info, text)
    if not text or not info then return true end
    local name = info.link and C.NameFromLink(info.link)
    return name ~= nil and name:lower():find(text, 1, true) ~= nil
end

local function UpdateButton(b)
    local info = C.GetSlotInfo(bagOf[b], slotOf[b])
    b.wallyInfo = info
    -- (The game's own buttons: the game keeps them up to date. Writing its fields would make them Wally's.)
    if borrowed[b] then
        Bags:Paint(b)
        return
    end
    b.icon:SetTexture(info and info.icon or nil)
    b.icon:SetDesaturated(info and info.locked or false)
    local count = info and info.count or 0
    b.Count:SetText(count > 1 and count or "")
    local ok, start, duration, enable = pcall(C_Container.GetContainerItemCooldown, bagOf[b], slotOf[b])
    if ok and CooldownFrame_Set then pcall(CooldownFrame_Set, b.cooldown, start, duration, enable) end
    b.wallyInfo = info
    Bags:Paint(b)
end

-- A slot's edge and fade: the bag under the mouse on the bag bar (Highlight) stands out in the
-- accent and the others fade; a search fades what doesn't match.
local highlighted
function Bags:Paint(b)
    local text = search and search:GetText() or ""
    text = text ~= "" and text:lower() or nil
    local alpha = Matches(b.wallyInfo, text) and 1 or 0.2
    local bag = bagOf[b]
    if highlighted ~= nil and bag ~= highlighted then alpha = alpha * 0.3 end
    b:SetAlpha(alpha)
    if bag then Edge(b, bag == highlighted and PAL.accent or (IsReagent(bag) and GOLD or PAL.border)) end
end

-- Lights up one bag's slots (nil: none), e.g. while its button on the bag bar is under the mouse.
function Bags:Highlight(bag)
    if highlighted == bag then return end
    highlighted = bag
    for _, b in ipairs(list) do self:Paint(b) end
end

-- The game's bag bar: the backpack button and each bag slot light up their bag here.
local BAR = { MainMenuBarBackpackButton = 0, CharacterBag0Slot = 1, CharacterBag1Slot = 2, CharacterBag2Slot = 3,
    CharacterBag3Slot = 4, CharacterReagentBag0Slot = 5 }
local function HookBagBar()
    for name, bag in pairs(BAR) do
        local b = _G[name]
        if b and not b.wallyHighlight then
            b.wallyHighlight = true
            b:HookScript("OnEnter", function(self)
                local id = self.GetBagID and self:GetBagID()
                Bags:Highlight(type(id) == "number" and id or bag)
            end)
            b:HookScript("OnLeave", function() Bags:Highlight(nil) end)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function Layout()
    if not frame then return end
    Adopt()
    for _, b in pairs(buttons) do b:Hide() end
    wipe(list)
    local game = GameButtons()
    local used = {}
    local cols = ns.db.options.bags.columns or 12
    -- Lays out one section's slots from y (below the content's top); returns the rows used.
    local function Section(bags, y)
        local n = 0
        for _, bag in ipairs(bags) do
            for slot = 1, C.GetNumSlots(bag) do
                local key = bag .. ":" .. slot
                local b = game[key]
                if b then
                    borrowed[b], used[b] = true, true
                    if b:GetParent() ~= content then home[b] = b:GetParent(); b:SetParent(content) end
                    b:SetFrameLevel(content:GetFrameLevel() + 2)
                    b:SetSize(SIZE, SIZE)
                else
                    b = buttons[key] or NewButton(bag, slot)
                    buttons[key] = b
                end
                bagOf[b], slotOf[b] = bag, slot
                Style(b, bag)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", content, "TOPLEFT", (n % cols) * (SIZE + GAP), -y - math.floor(n / cols) * (SIZE + GAP))
                b:Show()
                list[#list + 1] = b
                n = n + 1
            end
        end
        return math.ceil(n / cols)
    end
    -- The backpack and bags, then the reagent bag in a panel of its own below them.
    local w = cols * (SIZE + GAP) - GAP
    local mainRows = Section(C.BagList("bags"), 0)
    local h = mainRows * (SIZE + GAP) - GAP
    local panelY = h + SECTION_GAP
    -- The reagent bag shows only while its own game window is open, as the game does: B bound to
    -- "Open All Bags" opens it with the rest, the backpack button doesn't. (Shown without it, its
    -- slots were Wally's own and couldn't use items.)
    local reagentRows = ReagentOpen() and Section(C.BagList("reagent"), panelY + HEAD + INSET) or 0
    -- A game button from before that its window no longer shows (the window closed, as when a trade
    -- or loot window opens and shuts the bags, or the game moved the button to another slot): the
    -- game stopped updating it, so left here it shows an old item over the slot. It goes home.
    for b in pairs(borrowed) do
        if not used[b] then Return(b) end
    end
    reagentPanel:SetShown(reagentRows > 0)
    if reagentRows > 0 then
        local panelH = HEAD + INSET + reagentRows * (SIZE + GAP) - GAP + INSET
        reagentPanel:ClearAllPoints()
        reagentPanel:SetPoint("TOPLEFT", content, "TOPLEFT", -INSET, -panelY)
        reagentPanel:SetSize(w + INSET * 2, panelH)
        h = panelY + panelH - INSET -- (its bottom edge sits in the gap above the dock and footer)
    end
    content:SetSize(w, math.max(1, h))
    local dockH = PlaceDock(w)
    frame:SetSize(w + PAD * 2, math.max(1, h) + (dockH > 0 and dockH + GAP * 2 or 0) + TOP + BOTTOM)
    PlaceClose() -- (the X moves when the window's size changes)
    Bags:Refresh()
end

function Bags:Relayout() if frame and frame:IsShown() then Layout() end end

function Bags:Refresh()
    if not (frame and frame:IsShown()) then return end
    for _, b in ipairs(list) do UpdateButton(b) end
    local free, total = 0, 0
    for _, bag in ipairs(C.BagList("bags")) do
        local f, family = C.GetFreeSlots(bag)
        if family == 0 then free, total = free + f, total + C.GetNumSlots(bag) end
    end
    freeText:SetText(("%d / %d free"):format(free, total))
    local rFree, rTotal = 0, 0
    for _, bag in ipairs(C.BagList("reagent")) do
        rFree, rTotal = rFree + (C.GetFreeSlots(bag) or 0), rTotal + C.GetNumSlots(bag)
    end
    reagentFree:SetText(("%d / %d free"):format(rFree, rTotal))
    moneyText:SetText(W.Money(GetMoney()))
    if ns.Sorter and ns.Sorter.RefreshAnchors then ns.Sorter:RefreshAnchors() end
end

-- Every slot button shown, for decorations (Sort.lua's anchors, TapeMeasure's upgrade marks).
function Bags:Buttons() return list end
function Bags:IsShown() return frame ~= nil and frame:IsShown() end

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------

local function SavePosition()
    local point, _, rel, x, y = frame:GetPoint(1)
    ns.char.bagWindow = { point = point, rel = rel, x = x, y = y }
end

local function Build()
    frame = CreateFrame("Frame", "WallyBagFrame", UIParent, "BackdropTemplate")
    W.SetBackdrop(frame, 0.97)
    frame:SetFrameStrata("MEDIUM"); frame:SetToplevel(true)
    frame:SetClampedToScreen(true); frame:EnableMouse(true); frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition(); PlaceClose() end)
    local p = ns.char.bagWindow or {}
    frame:SetPoint(p.point or "BOTTOMRIGHT", UIParent, p.rel or p.point or "BOTTOMRIGHT", p.x or -10, p.y or 85)
    frame:Hide()
    frame.Items = list -- TapeMeasure's upgrade marks look for this

    local logo = frame:CreateTexture(nil, "ARTWORK")
    logo:SetSize(22, 22); logo:SetPoint("TOPLEFT", PAD, -10); logo:SetTexture(ns.ICON)
    local title = W.Label(frame, "Bags", "WallyGameFontNormalLarge", PAD + 28, -12)
    title:SetTextColor(PAL.accent[1], PAL.accent[2], PAL.accent[3])

    local close = W.MakeButton(frame, "X", 24, 22)
    close:SetPoint("TOPRIGHT", -PAD + 2, -10)
    -- The click itself is a secure button over it that clicks the game's own close button(s)
    -- (SetCloseTarget): closing then runs as the game's click. CloseAllBags() called from Wally's
    -- code made the game's bag state Wally's: the next time the bags opened, every item button was
    -- built from it, and right-clicking one was blocked ("The game forbade Wally's call to
    -- UseContainerItem()").
    -- That secure button is NOT part of this window: a secure button inside it made the whole
    -- window protected, and the game then refused to show it in combat ("The game blocked Wally's
    -- call to WallyBagFrame:SetShown()"). It's a window of its own, placed over the X and shown or
    -- hidden only out of combat (PlaceClose). Bags opened in combat get this plain X, which says
    -- how to close them until combat ends.
    close:SetScript("OnClick", function()
        ns:Print("In combat the X can't close the game's bags: press B or Escape (it works again after combat).", true)
    end)
    closeSecure = CreateFrame("Button", "WallyBagsCloseButton", UIParent, "SecureActionButtonTemplate")
    closeSecure:SetFrameStrata("HIGH")
    closeSecure:RegisterForClicks("AnyUp", "AnyDown")
    closeSecure:Hide()
    closeSecure:SetScript("OnEnter", function() local f = close:GetScript("OnEnter"); if f then f(close) end end)
    closeSecure:SetScript("OnLeave", function() local f = close:GetScript("OnLeave"); if f then f(close) end end)
    closeX = close

    local sort = W.MakeButton(frame, "Sort", 56, 22)
    sort:SetPoint("RIGHT", close, "LEFT", -6, 0)
    sort:SetScript("OnClick", function() ns.Sorter:Start("bags") end)
    W.Hint(sort, "Sort bags", "Wally's Bag Sorting rules (Options > AddOns > Wally > Bag Sorting). Ctrl-right-click an item to anchor it: sorting leaves it where it is.")

    search = W.MakeEditBox(frame, 160, "Search")
    search:SetHeight(22)
    search:SetPoint("TOPLEFT", PAD, -36); search:SetPoint("RIGHT", -PAD, 0)
    search:HookScript("OnTextChanged", function() Bags:Refresh() end)

    content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", PAD, -TOP)

    -- The reagent bag's panel: under the slot buttons (the content's own level; their holders
    -- sit above it), a darker well with a gold edge, the heading and free count along its top.
    reagentPanel = CreateFrame("Frame", nil, content, "BackdropTemplate")
    reagentPanel:SetFrameLevel(content:GetFrameLevel())
    W.SetBackdrop(reagentPanel)
    reagentPanel:SetBackdropColor(PAL.panel[1], PAL.panel[2], PAL.panel[3], 0.9)
    reagentPanel:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.45)
    reagentPanel:Hide()
    reagentLabel = W.Label(reagentPanel, "REAGENT BAG", "WallyGameFontHighlightSmall", INSET, -INSET)
    reagentLabel:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    reagentFree = W.Muted(W.Label(reagentPanel, "", "WallyGameFontHighlightSmall", 0, 0))
    reagentFree:ClearAllPoints(); reagentFree:SetPoint("TOPRIGHT", -INSET, -INSET)

    dock = CreateFrame("Frame", "WallyBagDock", frame)
    dock:SetPoint("TOPLEFT", content, "BOTTOMLEFT", 0, -GAP * 2)

    freeText = W.Muted(W.Label(frame, "", "WallyGameFontHighlightSmall", PAD, 0))
    freeText:ClearAllPoints(); freeText:SetPoint("BOTTOMLEFT", PAD, 12)
    moneyText = W.Label(frame, "", "WallyGameFontHighlightSmall", 0, 0)
    moneyText:ClearAllPoints(); moneyText:SetPoint("BOTTOMRIGHT", -PAD, 12)

    frame:SetScript("OnShow", function() Layout() end)
    frame:SetScript("OnHide", function()
        search:SetText(""); search:ClearFocus()
        PlaceClose()
        -- (No CloseAllBags() here: run from Wally's code it made the game's bag state Wally's, and
        -- the bags' item buttons were blocked after. This window follows the game's: Escape, B and
        -- the X close those, and this one hides with them.)
    end)
end

-- Turns the window on or off (the option); the game's bag windows come back when it's off.
function Bags:Apply()
    if not frame then Build() end
    if Enabled() then
        Away()
        Sync()
    else
        frame:Hide()
        GiveBack()
        -- Only moved back on screen: calling the game's UpdateContainerFrameAnchors or
        -- UpdateItemLayout from here would make its bag state Wally's (and the item buttons blocked).
        -- The game places them properly itself the next time a bag opens or closes.
        local y = 100
        for _, f in pairs(BlizzardFrames()) do
            if f then
                f:SetClampedToScreen(true)
                if f:IsShown() and IsPlayerBagFrame(f) then
                    f:ClearAllPoints()
                    f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -60, y)
                    y = y + (f:GetHeight() or 0) + 10
                end
            end
        end
    end
end

ns:On("PLAYER_LOGIN", function()
    Build()
    HookBagBar()
    -- The game's windows open and close as usual: this one follows, and they go off the screen.
    if UpdateContainerFrameAnchors then hooksecurefunc("UpdateContainerFrameAnchors", Away) end
    local relayoutQueued
    local function Relayout()
        if relayoutQueued then return end
        relayoutQueued = true
        C_Timer.After(0, function()
            relayoutQueued = false
            if Enabled() and frame and frame:IsShown() then Layout() end
        end)
    end
    local function Closed() Sync(); Relayout() end
    local function Shown() Away(); Sync(); Relayout() end
    for _, f in pairs(BlizzardFrames()) do
        if f then
            hooksecurefunc(f, "Show", Shown)
            hooksecurefunc(f, "Hide", Closed)
            hooksecurefunc(f, "SetShown", function(_, show) if show then Shown() else Closed() end end)
            f:HookScript("OnShow", Shown)
            f:HookScript("OnHide", Closed)
            -- It lays its buttons out again in its own window (opening, a bag changing size):
            -- they come back here.
            if f.UpdateItemLayout then
                hooksecurefunc(f, "UpdateItemLayout", function()
                    if Enabled() and frame and frame:IsShown() then Layout() end
                end)
            end
        end
    end
    Away()
end)

-- If the game still blocks an item used from this window, say which kind of slot it was (the game's
-- button or Wally's own), so the cause can be found.
local lastBlocked = 0
ns:On("ADDON_ACTION_FORBIDDEN", function(addon, fn)
    if addon ~= "Wally" or GetTime() - lastBlocked < 2 then return end
    local foci = GetMouseFoci and GetMouseFoci()
    local focus = (type(foci) == "table" and foci[1]) or (GetMouseFocus and GetMouseFocus())
    if not (focus and bagOf[focus]) then return end
    lastBlocked = GetTime()
    ns:Print(("The game blocked %s from bag %d slot %d, a %s button. Please report this line."):format(
        tostring(fn), bagOf[focus], slotOf[focus] or 0, borrowed[focus] and "game's" or "Wally's own"), true)
end)

local refreshQueued
local function QueueRefresh()
    if refreshQueued or not (frame and frame:IsShown()) then return end
    refreshQueued = true
    C_Timer.After(0.05, function() refreshQueued = false; Bags:Refresh() end)
end
ns:On("BAG_UPDATE_DELAYED", function() if frame and frame:IsShown() then Layout() end end)
ns:On("ITEM_LOCK_CHANGED", QueueRefresh)
ns:On("BAG_UPDATE_COOLDOWN", QueueRefresh)
ns:On("PLAYER_MONEY", QueueRefresh)
ns:On("GET_ITEM_INFO_RECEIVED", QueueRefresh)
