local _, ns = ...
local PAL = ns.Palette

-- The Quartermaster window: Browse, Lists, Prebuilt (Settings live in Options > AddOns). Same frame, sidebar and page layout as Wally.
local UI = {}
ns.UI = UI

local frame
local pages, tabs, builders = {}, {}, {}
local activeTab = "browse"

local W = ns.Widgets
local ACCENT = W.ACCENT
local SetBackdrop, Label, Muted, MakeButton, Hint = W.SetBackdrop, W.Label, W.Muted, W.MakeButton, W.Hint
local MakeCheckbox, MakeNumberBox = W.MakeCheckbox, W.MakeNumberBox

-- ---------------------------------------------------------------------------
-- Pages
-- ---------------------------------------------------------------------------

function UI:NewPage(name)
    local p = CreateFrame("Frame", nil, frame)
    p:SetPoint("TOPLEFT", 196, -76); p:SetPoint("BOTTOMRIGHT", -18, 18)
    p:Hide(); pages[name] = p
    return p
end

-- BrowsePage.lua and ListsPage.lua register their builders; they run when the window is first made.
function UI:RegisterPage(name, builder) builders[name] = builder end

-- ---------------------------------------------------------------------------
-- Settings: one branded panel in the game's Options > AddOns > Quartermaster (Wally's pattern,
-- Wally/UI.lua). The window's Settings button and /qm settings open it.
-- ---------------------------------------------------------------------------

local settingsPanel, settingsCategory

-- A section heading with a thin rule under it.
local function Section(p, text, y)
    Label(p, text, "QuartermasterGameFontNormal", 0, y)
    local rule = p:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(PAL.border[1], PAL.border[2], PAL.border[3], 1); rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 0, y - 17); rule:SetPoint("TOPRIGHT", 0, y - 17)
end

-- Builds the settings into any parent (the Options panel).
local function BuildSettings(p)
    local o = ns.db.options

    -- Branding: logo, name, version and what Quartermaster does.
    local logo = p:CreateTexture(nil, "ARTWORK"); logo:SetSize(40, 40)
    logo:SetPoint("TOPLEFT", 0, 0); logo:SetTexture(ns.ICON)
    Label(p, "Quartermaster", "QuartermasterGameFontNormalLarge", 50, -3):SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    Muted(Label(p, "v" .. ns.VERSION .. "  ·  Supply lists from Auctionator's prices, live auction house search, one-click buying.",
        "QuartermasterGameFontHighlightSmall", 50, -24, 560))
    local divider = p:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.6); divider:SetHeight(2)
    divider:SetPoint("TOPLEFT", 0, -48); divider:SetPoint("TOPRIGHT", 0, -48)

    local function NumberSetting(y, title, key, suffix, hint)
        Label(p, title, "QuartermasterGameFontHighlight", 0, y)
        local box = MakeNumberBox(p, 60)
        box:SetPoint("TOPLEFT", 220, y + 6)
        box:SetValue(o[key])
        local unit = Muted(Label(p, suffix, "QuartermasterGameFontHighlightSmall", 290, y))
        box:SetScript("OnTextChanged", function(self, user)
            local v = self:GetValue()
            if user and v and v >= 0 then o[key] = v; ns:Changed() end
        end)
        Hint(box, title, hint)
        box.unit = unit
        p[key] = box
    end
    -- Checkbox with a muted description line under it, like Wally's options.
    local function Toggle(y, text, desc, onClick)
        local c = MakeCheckbox(p, text)
        c:SetPoint("TOPLEFT", -4, y)
        c:SetScript("OnClick", onClick)
        if desc then Muted(Label(p, desc, "QuartermasterGameFontHighlightSmall", 27, y - 24, 560)) end
        return c
    end

    Section(p, "Buying", -62)
    NumberSetting(-90, "Market tolerance", "tolerance", "% over market",
        "The Cart buys anything at or below Auctionator's market price plus this much. If nothing qualifies, it asks whether to buy the cheapest listing, skip the item or stop.")
    NumberSetting(-118, "Allowed overshoot", "overshoot", "% of the amount still needed",
        "Auctions sell whole stacks. A stack may bring you over the wanted amount by up to this share of what you still need. Example: need 10 at 50% -> stacks up to 15.")
    NumberSetting(-146, "Confirm purchases over", "confirmOver", "gold (0 = never ask)",
        "Any single purchase at or above this asks for confirmation first.")

    Section(p, "Auction house", -178)
    local scan = Toggle(-200, "Auto full scan",
        "Full Auctionator scan when you first open the Cart or Buying tab each session. Pauses while you search.",
        function(self) o.autoScan = self:GetChecked() and true or false; ns:Changed() end)
    Hint(scan, "Auto full scan", "Starts Auctionator's own full scan in the background, unless Auctionator or another addon already is, or did one recently. Your searches come first: the scan pauses while you search and starts again once you've been idle a few seconds.")
    local hideTabs = Toggle(-248, "Hide Auction Tabs",
        "Hides Auctionator's Shopping tab; Quartermaster's Buying tab replaces it.",
        function(self) o.hideTabs = self:GetChecked() and true or false; if ns.AHTabs then ns.AHTabs:Relayout() end end)

    Section(p, "General", -298)
    local chat = Toggle(-320, "Print messages in chat", nil, function(self) o.chat = self:GetChecked() and true or false end)
    local map = Toggle(-346, "Show minimap button", nil, function(self)
        ns.char.minimap.hide = not self:GetChecked()
        if ns.MinimapButton then ns.MinimapButton:Refresh() end
    end)
    local bank = Toggle(-372, "Prebuilt lists count items in your bank", nil,
        function(self) o.countBank = self:GetChecked() and true or false; ns:Changed() end)
    Hint(bank, "Count the bank", "Uses the bank contents from your last visit to the bank.")
    local mail = Toggle(-398, "Prebuilt lists count auction wins waiting in the mailbox", nil,
        function(self) o.countMail = self:GetChecked() and true or false; ns:Changed() end)
    Hint(mail, "Count the mailbox", "Auctions you win arrive by mail. Quartermaster counts what it bought, plus what was in your mailbox the last time you opened it, so you don't buy the same items twice.")

    Section(p, "Key binding", -434)
    Muted(Label(p, "Bind \"Buy next cart item\" under Key Bindings > AddOns > Quartermaster. Each key press buys one stack, just like clicking Buy Next.", "QuartermasterGameFontHighlightSmall", 0, -458, 560))

    Section(p, "Where prices come from", -490)
    p.data = Muted(Label(p, "", "QuartermasterGameFontHighlightSmall", 0, -514, 560))

    p.Refresh = function()
        for _, key in ipairs({ "tolerance", "overshoot", "confirmOver" }) do
            if not p[key]:HasFocus() then p[key]:SetValue(o[key]) end
        end
        scan:SetChecked(o.autoScan); hideTabs:SetChecked(o.hideTabs)
        chat:SetChecked(o.chat); map:SetChecked(not ns.char.minimap.hide)
        bank:SetChecked(o.countBank); mail:SetChecked(o.countMail)
        ns.Catalog:EnsureBuilt()
        local n = #ns.Catalog.entries
        p.data:SetText(n > 0
            and ("Auctionator knows %d items on this realm. Quartermaster's auto full scan, Auctionator's own scan, and every search you make at the auction house keep them fresh."):format(n)
            or "Auctionator has no prices yet. Open the auction house: the auto full scan (or Auctionator's Scan button) fills them in.")
    end
end

local function CreateSettingsPanel()
    if settingsPanel then return end
    settingsPanel = CreateFrame("Frame", "QuartermasterSettingsPanel")
    settingsPanel.name = "Quartermaster"
    local content = CreateFrame("Frame", nil, settingsPanel)
    content:SetPoint("TOPLEFT", 16, -16); content:SetPoint("BOTTOMRIGHT", -16, 16)
    settingsPanel.content = content
    -- Built the first time it's shown, after saved variables have loaded.
    settingsPanel:SetScript("OnShow", function()
        if not content.Refresh then BuildSettings(content) end
        content.Refresh()
    end)
    settingsPanel:Hide()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        settingsCategory = Settings.RegisterCanvasLayoutCategory(settingsPanel, "Quartermaster")
        Settings.RegisterAddOnCategory(settingsCategory)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(settingsPanel)
    end
end
ns:OnLoad(CreateSettingsPanel)

-- Opens Options > AddOns > Quartermaster.
function UI:OpenSettings()
    CreateSettingsPanel()
    if Settings and Settings.OpenToCategory and settingsCategory then
        Settings.OpenToCategory(settingsCategory:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        -- Called twice: the first call can land on the wrong page the first time the frame opens.
        InterfaceOptionsFrame_OpenToCategory(settingsPanel); InterfaceOptionsFrame_OpenToCategory(settingsPanel)
    end
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------

-- Optional pages (Consumables, with Bandolier) only get a tab when their file registered them.
local TABS = {
    { "browse", "Browse", "INV_Misc_Spyglass_03" },
    { "lists", "Lists", "INV_Misc_Note_05" },
    { "prebuilt", "Prebuilt", "INV_Crate_01" },
    { "consumables", "Consumables", "INV_Potion_54", optional = true },
    { "settings", "Settings", "INV_Misc_Gear_01" },
}

local function ShowTab(name)
    activeTab = name
    for key, p in pairs(pages) do p:SetShown(key == name) end
    for key, b in pairs(tabs) do
        b.selected:SetShown(key == name)
        b:SetBackdropColor(key == name and 0.09 or 0.075, key == name and 0.15 or 0.105, key == name and 0.17 or 0.13, 1)
    end
end

local function CreateMainFrame()
    if frame then return end
    frame = CreateFrame("Frame", "QuartermasterWindow", UIParent, "BackdropTemplate")
    frame:SetSize(860, 580); frame:SetFrameStrata("DIALOG"); frame:SetToplevel(true)
    frame:SetClampedToScreen(true); frame:SetMovable(true); frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton"); SetBackdrop(frame, 0.985)
    local w = ns.char.window
    frame:SetPoint(w.point or "CENTER", UIParent, w.point or "CENTER", w.x or 0, w.y or 0)
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        ns.char.window = { point = point, x = x, y = y }
    end)
    frame:SetScript("OnShow", function() UI:Refresh() end)
    tinsert(UISpecialFrames, "QuartermasterWindow")

    local logo = frame:CreateTexture(nil, "ARTWORK"); logo:SetSize(38, 38)
    logo:SetPoint("TOPLEFT", 20, -17); logo:SetTexture(ns.ICON)
    Label(frame, "Quartermaster", "QuartermasterGameFontNormalLarge", 70, -20):SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    Muted(Label(frame, "Supply lists from Auctionator's prices", "QuartermasterGameFontHighlightSmall", 70, -42))
    local close = MakeButton(frame, "X", 28, 26); close:SetPoint("TOPRIGHT", -18, -18)
    close:SetScript("OnClick", function() frame:Hide() end)

    local side = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    side:SetPoint("TOPLEFT", 14, -74); side:SetPoint("BOTTOMLEFT", 14, 14); side:SetWidth(165)
    SetBackdrop(side); side:SetBackdropColor(PAL.panel[1], PAL.panel[2], PAL.panel[3], 1)
    local shown = {}
    for _, d in ipairs(TABS) do
        if not d.optional or builders[d[1]] then shown[#shown + 1] = d end
    end
    for i, d in ipairs(shown) do
        local b = MakeButton(side, d[2], 147, 40); b:SetPoint("TOPLEFT", 9, -12 - (i - 1) * 46)
        b.text:ClearAllPoints(); b.text:SetPoint("LEFT", 40, 0)
        local icon = b:CreateTexture(nil, "ARTWORK"); icon:SetSize(23, 23); icon:SetPoint("LEFT", 9, 0)
        icon:SetTexture("Interface\\Icons\\" .. d[3]); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.selected = b:CreateTexture(nil, "OVERLAY"); b.selected:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
        b.selected:SetPoint("TOPLEFT"); b.selected:SetPoint("BOTTOMLEFT"); b.selected:SetWidth(3)
        b:SetScript("OnLeave", function(self) if activeTab ~= d[1] then self:SetBackdropColor(PAL.button[1], PAL.button[2], PAL.button[3], 1) end end)
        if d[1] == "settings" then
            b:SetScript("OnClick", function() UI:OpenSettings() end)
            Hint(b, "Settings", "Opens Options > AddOns > Quartermaster.")
        else
            b:SetScript("OnClick", function() ShowTab(d[1]); UI:Refresh() end)
        end
        tabs[d[1]] = b
    end
    side.summary = Muted(Label(side, "", "QuartermasterGameFontHighlightSmall", 12, -14 - #shown * 46, 145))
    Muted(Label(side, "Shift-click an item link\ninto the Name box to\nlook it up.\n\nDrop items on a list to\nadd them.\n\nAt the auction house,\nthe Cart tab buys a\nlist or restocks your\nprebuilt lists.", "QuartermasterGameFontHighlightSmall", 12, -100 - #shown * 46, 145))
    Label(side, "v" .. ns.VERSION, "QuartermasterGameFontHighlightSmall", 12, -470, 145):SetTextColor(0.38, 0.50, 0.57)
    UI.side = side

    for _, name in ipairs({ "browse", "lists", "prebuilt", "consumables" }) do
        if builders[name] then builders[name](UI:NewPage(name)) end
    end
    ShowTab(activeTab); frame:Hide()
end

local function RefreshSide()
    local side = UI.side
    if not side then return end
    local list, kind = ns.Lists:AddTarget()
    local text
    if kind == "template" then
        text = ("Adding to prebuilt:\n|cffffffff%s|r\n%d item%s"):format(list.name, #list.entries, #list.entries == 1 and "" or "s")
    else
        local total, unknown = ns.Lists:Estimate(list)
        text = ("Adding to list:\n|cffffffff%s|r\n%d item%s, about %s%s"):format(list.name, #list.entries,
            #list.entries == 1 and "" or "s", ns.Compat.Money(total), unknown > 0 and (" + " .. unknown .. " unpriced") or "")
    end
    side.summary:SetText(text)
end

function UI:RefreshPage(name)
    local p = pages[name]
    if p and p.Refresh and frame and frame:IsShown() then p.Refresh() end
end

function UI:Refresh()
    if not ns.db or not frame or not frame:IsShown() then return end
    RefreshSide()
    self:RefreshPage(activeTab)
end

-- Item data arrives in the background; only the Browse page shows lots of it.
function UI:OnCatalogChanged()
    if not frame or not frame:IsShown() then return end
    RefreshSide()
    local p = pages[activeTab]
    if p and p.OnCatalogChanged then p.OnCatalogChanged() elseif p and p.Refresh then p.Refresh() end
end

function UI:Toggle()
    if not ns.db then return end
    CreateMainFrame()
    frame:SetShown(not frame:IsShown())
end

function UI:Show(tab)
    if not ns.db then return end
    if tab == "settings" then return self:OpenSettings() end
    CreateMainFrame()
    if tab then ShowTab(tab) end
    frame:Show(); self:Refresh()
end

function UI:SearchFor(text)
    local p = pages.browse
    if p and p.SearchFor then p.SearchFor(text) end
end

function UI:IsShown() return frame and frame:IsShown() end

-- Shift-clicking an item while a Quartermaster box has focus inserts the item name there.
-- Works for every box registered with W.RegisterLinkBox (the filter bars in /qm and at the AH).
local function InsertLink(link)
    if not link then return end
    for box, onInsert in pairs(W.linkBoxes) do
        if box:IsVisible() and box:HasFocus() then
            W.SetExactName(box, ns.Compat.NameFromLink(link) or link)
            if onInsert then onInsert() end
            return true
        end
    end
end
if ChatFrameUtil and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, "InsertLink", InsertLink)
elseif ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", InsertLink) end
