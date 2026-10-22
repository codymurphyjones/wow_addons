local _, ns = ...

-- Quartermaster's tabs on the auction house (Cart, Auction). On the classic AuctionFrame they're
-- added the way Auctionator adds its own tabs (Source_LegacyAH/Tabs/Mixins/TabButton.lua); on the
-- modern AuctionHouseFrame they go through LibAHTab like Wally's tab.
--
-- AHTabs:Add(id, { label, title, build = function(parent) return panel end, onShow = function() end })
--
-- On the modern auction house, AHTabs:Relayout() also orders and hides tabs, re-anchoring the whole
-- row the way Wally does (Wally/AuctionTab.lua): a Cart with something to buy comes first (and is the
-- tab you see when the auction house opens); Buying sits right after Wally's tab if there is one,
-- otherwise first (after the Cart); an empty Cart goes last. "Hide Auction Tabs" hides Auctionator's
-- Shopping tab. Tabs another addon has hidden (Wally's own option) stay hidden and leave no gap.
local AHTabs = { list = {}, byID = {} }
ns.AHTabs = AHTabs

local IMAGES = "Interface\\AddOns\\Auctionator\\Images_Classic\\"

function AHTabs:Add(id, def)
    def.id = id
    self.list[#self.list + 1] = def
    self.byID[id] = def
end

-- ---------------------------------------------------------------------------
-- Classic AuctionFrame
-- ---------------------------------------------------------------------------

local function SetBlankFrameArt()
    -- Auctionator's plain frame art, as its own tabs use; skip if the files ever move.
    if not AuctionFrameTopLeft then return end
    AuctionFrameTopLeft:SetTexture(IMAGES .. "topleft")
    AuctionFrameTop:SetTexture(IMAGES .. "top")
    AuctionFrameTopRight:SetTexture(IMAGES .. "topright")
    AuctionFrameBotLeft:SetTexture(IMAGES .. "botleft")
    AuctionFrameBot:SetTexture(IMAGES .. "bot")
    AuctionFrameBotRight:SetTexture(IMAGES .. "botright")
end

local hooked
local function BuildClassic(def)
    if def.tab or not AuctionFrame or not AuctionFrame.numTabs then return end
    local panel = def.build(AuctionFrame)
    panel:SetPoint("TOPLEFT", AuctionFrame, "TOPLEFT", 20, -72)
    panel:SetPoint("BOTTOMRIGHT", AuctionFrame, "BOTTOMRIGHT", -8, 14)
    def.panel = panel

    local index = AuctionFrame.numTabs + 1
    local tab = CreateFrame("Button", "AuctionFrameTab" .. index, AuctionFrame, "AuctionTabTemplate")
    tab:SetID(index)
    tab:SetText(def.label)
    tab:SetPoint("LEFT", _G["AuctionFrameTab" .. (index - 1)], "RIGHT", -15, 0)
    PanelTemplates_SetNumTabs(AuctionFrame, index)
    PanelTemplates_EnableTab(AuctionFrame, index)
    if PanelTemplates_TabResize then PanelTemplates_TabResize(tab, 0, nil, 36) end
    def.tab, def.index = tab, index
    AuctionFrame:HookScript("OnHide", function() panel:Hide() end)

    if hooked then return end
    hooked = true
    hooksecurefunc("AuctionFrameTab_OnClick", function(clicked)
        for _, d in ipairs(AHTabs.list) do
            if d.tab and d.tab == clicked then
                PanelTemplates_SetTab(AuctionFrame, d.index)
                SetBlankFrameArt()
                d.panel:Show()
            elseif d.panel then
                d.panel:Hide()
            end
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Modern AuctionHouseFrame (the one WoW Forever shows)
-- ---------------------------------------------------------------------------

local function BuildModern(def)
    if def.tab or not AuctionHouseFrame then return end
    local lib = LibStub and LibStub("LibAHTab-1-0", true)
    if not lib then return end
    local panel = def.build(AuctionHouseFrame)
    panel:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", 6, -60)
    panel:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -6, 28)
    def.panel = panel
    lib:CreateTab("Quartermaster" .. def.id, panel, def.label, def.title)
    def.tab, AHTabs.lib = "Quartermaster" .. def.id, lib
end

-- Opens a tab if the auction house is open. Returns true on success.
function AHTabs:Select(id)
    local def = self.byID[id]
    if not def or not def.tab then return false end
    if self.lib then
        if AuctionHouseFrame and AuctionHouseFrame:IsShown() then self.lib:SetSelected(def.tab) return true end
        return false
    end
    if not AuctionFrame:IsShown() then return false end
    def.tab:Click()
    return true
end

function AHTabs:Panel(id) return self.byID[id] and self.byID[id].panel end

-- ---------------------------------------------------------------------------
-- Tab order and hiding (modern AuctionHouseFrame)
-- ---------------------------------------------------------------------------

-- LibAHTab's spacing between tabs on WoW Forever (LibAHTab.lua's OFFSET_X), as Wally uses it.
local TAB_OFFSET_X = 3
local SHOPPING = "AuctionatorTabs_Shopping"
local WALLY = "Wally" -- Wally's LibAHTab tab (Wally/AuctionTab.lua)

local origin         -- Blizzard's first tab's anchor as first found (nobody else moves that tab)
local hiddenByUs = {} -- tab -> true: hidden by "Hide Auction Tabs"
local hookedShow = {} -- tab -> true: OnShow hook installed
local libHooked = false
local cartHad         -- last known "Cart has something to buy"

local function Button(lib, id) return lib:DoesIDExist(id) and lib:GetButton(id) or nil end

local function Hiding() return ns.db and ns.db.options.hideTabs end

-- Showing a hidden tab's page (Auctionator opens on Shopping, say)? Switch to Buying.
local function LeaveHiddenPage()
    local lib = AHTabs.lib
    if not (Hiding() and lib and lib.internalState and AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return end
    local shopping = Button(lib, SHOPPING)
    if shopping and shopping.frameRef and shopping.frameRef:IsShown() and AHTabs.byID.Buying and AHTabs.byID.Buying.tab then
        lib:SetSelected(AHTabs.byID.Buying.tab)
    end
end

function AHTabs:Relayout()
    local lib = self.lib
    if not (lib and lib.internalState and AuctionHouseFrame and AuctionHouseFrame.Tabs and AuctionHouseFrame.Tabs[1]) then return end
    local blizzard = AuctionHouseFrame.Tabs
    origin = origin or { blizzard[1]:GetPoint(1) }
    if not libHooked then
        libHooked = true
        -- Tabs other addons add later join the row; picking a hidden tab's page bounces to Buying.
        hooksecurefunc(lib, "CreateTab", function() C_Timer.After(0, function() AHTabs:Relayout() end) end)
        hooksecurefunc(lib, "SetSelected", LeaveHiddenPage)
    end

    local cart = self.byID.Cart and self.byID.Cart.tab and Button(lib, self.byID.Cart.tab)
    local buying = self.byID.Buying and self.byID.Buying.tab and Button(lib, self.byID.Buying.tab)

    -- Hide or bring back Auctionator's Shopping tab.
    local shopping = Button(lib, SHOPPING)
    if shopping then
        if not hookedShow[shopping] then
            hookedShow[shopping] = true
            shopping:HookScript("OnShow", function(b) if Hiding() then b:Hide() end end)
        end
        if Hiding() then
            hiddenByUs[shopping] = true
            shopping:Hide()
        elseif hiddenByUs[shopping] then
            hiddenByUs[shopping] = nil
            shopping:Show()
        end
    end

    local cartFirst = cart and ns.CartTab and ns.CartTab:HasItems()
    cartHad = cartFirst and true or false
    local wally = Button(lib, WALLY)
    local order = {}
    if cartFirst then order[#order + 1] = cart end
    if buying and not wally then order[#order + 1] = buying end
    for _, t in ipairs(blizzard) do order[#order + 1] = t end
    for _, t in ipairs(lib.internalState.Tabs) do
        if t ~= cart and t ~= buying then
            order[#order + 1] = t
            if t == wally and buying then order[#order + 1] = buying end
        end
    end
    if cart and not cartFirst then order[#order + 1] = cart end

    -- Re-chain every visible tab from the first tab's spot, so hidden ones leave no gap.
    local prev
    for _, t in ipairs(order) do
        if t:IsShown() or t == cart or t == buying then
            t:ClearAllPoints()
            if prev then t:SetPoint("TOPLEFT", prev, "TOPRIGHT", TAB_OFFSET_X, 0)
            else t:SetPoint(unpack(origin)) end
            prev = t
        end
    end
    LeaveHiddenPage()
end

-- A Cart with something to buy is the tab you see when the auction house opens. Only while opening
-- (focusPending), so switching tabs yourself is never undone.
local focusPending = false
function AHTabs:FocusCart()
    local lib, def = self.lib, self.byID.Cart
    if not (focusPending and lib and def and def.tab and def.panel and AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return end
    if not (ns.CartTab and ns.CartTab:HasItems()) then return end
    if not def.panel:IsShown() then lib:SetSelected(def.tab) end
end

-- After list changes: the Cart moves when it goes from empty to not (or back).
function AHTabs:CartChanged()
    if not (self.lib and AuctionHouseFrame and AuctionHouseFrame:IsShown() and ns.CartTab) then return end
    local has = ns.CartTab:HasItems() and true or false
    if has ~= cartHad then self:Relayout() end
end

ns:On("AUCTION_HOUSE_SHOW", function()
    -- After Auctionator has added its tabs (it builds them on this same event).
    C_Timer.After(0, function()
        for _, def in ipairs(AHTabs.list) do
            if AuctionFrame then BuildClassic(def) else BuildModern(def) end
        end
        for _, def in ipairs(AHTabs.list) do
            if def.onShow then def.onShow() end
        end
        if not AuctionFrame then
            focusPending = true
            AHTabs:Relayout()
            AHTabs:FocusCart()
            -- Again once Auctionator, Wally and others have finished their own AUCTION_HOUSE_SHOW work.
            C_Timer.After(0.5, function()
                AHTabs:Relayout()
                AHTabs:FocusCart()
                focusPending = false
            end)
        end
    end)
end)
