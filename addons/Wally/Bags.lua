local _, ns = ...
local PAL = ns.Palette
local C = ns.Compat
local W = ns.Widgets

-- Wally's bag window: the backpack, your bags and the reagent bag in one Wally-styled grid, in place
-- of the game's bag windows (Options > AddOns > Wally > Bag window). The game's own bag windows still
-- open and close as usual (the B key, the bag bar, a vendor, the bank), only out of sight: this
-- window follows them, so every way of opening bags opens it. Bank bags stay the game's.
-- The slots are the game's own item buttons (ContainerFrameItemButtonTemplate), so clicks, drags,
-- tooltips and using items work exactly as in the game's bags. Reagent bag slots have a gold edge.
local Bags = {}
ns.BagWindow = Bags

local SIZE, GAP, PAD = 37, 4, 12
local TOP, BOTTOM = 62, 34            -- header (title, search, buttons) and footer (free slots, money)
local GOLD = { 1, 0.82, 0.30 }

local frame, content, dock, search, freeText, moneyText, reagentLabel
local holders, buttons, list = {}, {}, {} -- bag -> holder frame; "bag:slot" -> button; shown buttons
local hidden = CreateFrame("Frame"); hidden:Hide()
local original = {}                         -- Blizzard bag frame -> its parent, to give back

local function Enabled() return ns.db and ns.db.options.bags.window end
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

-- A player bag window goes behind a hidden parent; a bank bag window comes back to its own.
local function Park(f)
    if not original[f] then original[f] = f:GetParent() or UIParent end
    local want = (Enabled() and IsPlayerBagFrame(f)) and hidden or original[f]
    if f:GetParent() ~= want then f:SetParent(want) end
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

local function AnyBagOpen()
    for _, f in pairs(BlizzardFrames()) do
        if f and f:IsShown() and IsPlayerBagFrame(f) then return true end
    end
    return false
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
    end)
end

-- ---------------------------------------------------------------------------
-- Slots
-- ---------------------------------------------------------------------------

local function Edge(b, color)
    for _, t in ipairs(b.wallyEdge) do t:SetColorTexture(color[1], color[2], color[3], 1) end
end

local function NewButton(bag, slot)
    local holder = holders[bag]
    if not holder then
        holder = CreateFrame("Frame", nil, content)
        holder:SetID(bag); holder:SetAllPoints(content)
        holders[bag] = holder
    end
    local ok, b = pcall(CreateFrame, "ItemButton", nil, holder, "ContainerFrameItemButtonTemplate")
    if not ok then b = CreateFrame("Button", nil, holder, "ContainerFrameItemButtonTemplate") end
    b:SetID(slot)
    if b.SetBagID then b:SetBagID(bag) end
    b:SetSize(SIZE, SIZE)
    b.bag, b.slot = bag, slot
    -- Wally's well: a dark field and a 1px edge (gold for the reagent bag) in place of the game's art.
    local normal = b:GetNormalTexture()
    if normal then normal:SetAlpha(0) end
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
    return b
end

local function Matches(info, text)
    if not text or not info then return true end
    local name = info.link and C.NameFromLink(info.link)
    return name ~= nil and name:lower():find(text, 1, true) ~= nil
end

local function UpdateButton(b)
    local info = C.GetSlotInfo(b.bag, b.slot)
    SetItemButtonTexture(b, info and info.icon)
    SetItemButtonCount(b, info and info.count or 0)
    SetItemButtonDesaturated(b, info and info.locked or false)
    if SetItemButtonQuality then SetItemButtonQuality(b, info and info.quality, info and info.link) end
    if b.UpdateCooldown then pcall(b.UpdateCooldown, b, info and info.icon)
    elseif ContainerFrame_UpdateCooldown then pcall(ContainerFrame_UpdateCooldown, b.bag, b) end
    if b.UpdateNewItem then pcall(b.UpdateNewItem, b, info and info.quality) end
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
    if highlighted ~= nil and b.bag ~= highlighted then alpha = alpha * 0.3 end
    b:SetAlpha(alpha)
    Edge(b, b.bag == highlighted and PAL.accent or (IsReagent(b.bag) and GOLD or PAL.border))
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
    local cols = ns.db.options.bags.columns or 12
    -- Lays out one section's slots from y (below the content's top); returns the rows used.
    local function Section(bags, y)
        local n = 0
        for _, bag in ipairs(bags) do
            for slot = 1, C.GetNumSlots(bag) do
                local key = bag .. ":" .. slot
                local b = buttons[key] or NewButton(bag, slot)
                buttons[key] = b
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", content, "TOPLEFT", (n % cols) * (SIZE + GAP), -y - math.floor(n / cols) * (SIZE + GAP))
                b:Show()
                list[#list + 1] = b
                n = n + 1
            end
        end
        return math.ceil(n / cols)
    end
    -- The backpack and bags, then the reagent bag on rows of its own under a heading.
    local mainRows = Section(C.BagList("bags"), 0)
    local labelY = mainRows * (SIZE + GAP) + 2
    local reagentRows = Section(C.BagList("reagent"), labelY + 18)
    reagentLabel:SetShown(reagentRows > 0)
    reagentLabel:ClearAllPoints()
    reagentLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -labelY)
    local w = cols * (SIZE + GAP) - GAP
    local h = mainRows * (SIZE + GAP) - GAP
    if reagentRows > 0 then h = labelY + 18 + reagentRows * (SIZE + GAP) - GAP end
    content:SetSize(w, math.max(1, h))
    local dockH = PlaceDock(w)
    frame:SetSize(w + PAD * 2, math.max(1, h) + (dockH > 0 and dockH + GAP * 2 or 0) + TOP + BOTTOM)
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
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition() end)
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
    close:SetScript("OnClick", function() CloseAllBags() end)

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

    reagentLabel = W.Muted(W.Label(content, "Reagent bag", "WallyGameFontHighlightSmall", 0, 0))
    reagentLabel:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

    dock = CreateFrame("Frame", "WallyBagDock", frame)
    dock:SetPoint("TOPLEFT", content, "BOTTOMLEFT", 0, -GAP * 2)

    freeText = W.Muted(W.Label(frame, "", "WallyGameFontHighlightSmall", PAD, 0))
    freeText:ClearAllPoints(); freeText:SetPoint("BOTTOMLEFT", PAD, 12)
    moneyText = W.Label(frame, "", "WallyGameFontHighlightSmall", 0, 0)
    moneyText:ClearAllPoints(); moneyText:SetPoint("BOTTOMRIGHT", -PAD, 12)

    frame:SetScript("OnShow", function() Layout() end)
    frame:SetScript("OnHide", function()
        search:SetText(""); search:ClearFocus()
        if AnyBagOpen() then CloseAllBags() end
    end)
end

-- Turns the window on or off (the option); the game's bag windows come back when it's off.
function Bags:Apply()
    if not frame then Build() end
    for _, f in pairs(BlizzardFrames()) do if f then Park(f) end end
    if not Enabled() then frame:Hide() else Sync() end
end

ns:On("PLAYER_LOGIN", function()
    Build()
    HookBagBar()
    -- A frame under a hidden parent gets no OnShow or OnHide (it never becomes visible), so its
    -- Show and Hide calls are what's followed. A bank bag window shown there is moved back out.
    local function Shown(self) Park(self); Sync() end
    for _, f in pairs(BlizzardFrames()) do
        if f then
            hooksecurefunc(f, "Show", Shown)
            hooksecurefunc(f, "Hide", Sync)
            hooksecurefunc(f, "SetShown", function(self, show) if show then Shown(self) else Sync() end end)
            f:HookScript("OnShow", Shown)
            f:HookScript("OnHide", Sync)
            Park(f)
        end
    end
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
