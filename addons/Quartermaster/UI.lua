local _, ns = ...

-- The Quartermaster window: Browse, Lists, Prebuilt (Settings live in Options > AddOns). Same frame, sidebar and page layout as Wally.
local UI = {}
ns.UI = UI

local W = ns.Widgets
local ACCENT = W.ACCENT
local Label, Muted = W.Label, W.Muted

-- ---------------------------------------------------------------------------
-- Window (shared\Window.lua): built the first time it opens
-- ---------------------------------------------------------------------------

-- Optional pages (Consumables, with Bandolier) only get a tab when their file registered them.
local TABS = {
    { "browse", "Browse", "INV_Misc_Spyglass_03" },
    { "lists", "Lists", "INV_Misc_Note_05" },
    { "prebuilt", "Prebuilt", "INV_Crate_01" },
    { "consumables", "Consumables", "INV_Potion_54", optional = true },
    { "settings", "Settings", "INV_Misc_Gear_01", onClick = function() UI:OpenSettings() end,
        hint = { "Settings", "Opens Options > AddOns > Quartermaster." } },
}

local win = ns.NewWindow({
    name = "QuartermasterWindow", title = "Quartermaster", subtitle = "Supply lists from Auctionator's prices",
    width = 860, height = 580, tabs = TABS, active = "browse",
    refresh = function() UI:Refresh() end,
    decorate = function(_, side, count)
        side.summary = Muted(Label(side, "", "QuartermasterGameFontHighlightSmall", 12, -14 - count * 46, 145))
        Muted(Label(side, "Shift-click an item link\ninto the Name box to\nlook it up.\n\nDrop items on a list to\nadd them.\n\nAt the auction house,\nthe Cart tab buys a\nlist or restocks your\nprebuilt lists.", "QuartermasterGameFontHighlightSmall", 12, -100 - count * 46, 145))
        UI.side = side
    end,
})
UI.window = win

-- ---------------------------------------------------------------------------
-- Pages
-- ---------------------------------------------------------------------------

function UI:NewPage(name) return win:NewPage(name) end

-- BrowsePage.lua and ListsPage.lua register their builders; they run when the window is first made.
function UI:RegisterPage(name, builder) win:RegisterPage(name, builder) end

-- ---------------------------------------------------------------------------
-- Settings: Options > AddOns > Quartermaster, built with the shared OptionsPage.lua (addons/shared).
-- The window's Settings button, /qm settings and /qm minimap change the same options, so every UI
-- shows the same value. The key binding note and where prices come from are on its About subpage.
-- ---------------------------------------------------------------------------

local function Gold(v) return v == 0 and "Never ask" or ("%d gold"):format(v) end

-- The About subpage: what Quartermaster is, its key binding, and where its prices come from.
local function BuildAbout(f)
    local p = CreateFrame("Frame", nil, f)
    p:SetPoint("TOPLEFT", 16, -16); p:SetPoint("BOTTOMRIGHT", -16, 16)
    local logo = p:CreateTexture(nil, "ARTWORK"); logo:SetSize(40, 40)
    logo:SetPoint("TOPLEFT", 0, 0); logo:SetTexture(ns.ICON)
    Label(p, "Quartermaster", "QuartermasterGameFontNormalLarge", 50, -3):SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    Muted(Label(p, "v" .. ns.VERSION .. "  ·  Supply lists from Auctionator's prices, live auction house search, one-click buying.",
        "QuartermasterGameFontHighlightSmall", 50, -24, 560))
    local divider = p:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.6); divider:SetHeight(2)
    divider:SetPoint("TOPLEFT", 0, -48); divider:SetPoint("TOPRIGHT", 0, -48)
    local function Section(text, y) W.Section(p, text, 0, y) end
    Section("Key binding", -62)
    Muted(Label(p, "Bind \"Buy next cart item\" under Key Bindings > AddOns > Quartermaster. Each key press buys one stack, just like clicking Buy Next.", "QuartermasterGameFontHighlightSmall", 0, -86, 560))
    Section("Where prices come from", -118)
    f.data = Muted(Label(p, "", "QuartermasterGameFontHighlightSmall", 0, -142, 560))
end

local function RefreshAbout(f)
    if not f.data then return end
    ns.Catalog:EnsureBuilt()
    local n = #ns.Catalog.entries
    f.data:SetText(n > 0
        and ("Auctionator knows %d items on this realm. Quartermaster's auto full scan, Auctionator's own scan, and every search you make at the auction house keep them fresh."):format(n)
        or "Auctionator has no prices yet. Open the auction house: the auto full scan (or Auctionator's Scan button) fills them in.")
end

UI.page = ns.NewOptionsPage({ name = "Quartermaster", icon = true, build = function(p)
    p:Header("Buying")
    p:Slider({ path = "db.options.tolerance", label = "Market tolerance", min = 0, max = 100, step = 1,
        format = function(v) return ("%d%% over market"):format(v) end,
        tooltip = "The Cart buys anything at or below Auctionator's market price plus this much. If nothing qualifies, it asks whether to buy the cheapest listing, skip the item or stop." })
    p:Slider({ path = "db.options.overshoot", label = "Allowed overshoot", min = 0, max = 200, step = 5,
        format = function(v) return ("%d%% of the amount still needed"):format(v) end,
        tooltip = "Auctions sell whole stacks. A stack may bring you over the wanted amount by up to this share of what you still need. Example: need 10 at 50% -> stacks up to 15." })
    p:Slider({ path = "db.options.confirmOver", label = "Confirm purchases over", min = 0, max = 500, step = 5, format = Gold,
        tooltip = "Any single purchase at or above this asks for confirmation first (0 = never ask)." })

    p:Header("Auction house")
    p:Check({ path = "db.options.autoScan", label = "Auto full scan",
        tooltip = "Full Auctionator scan when you first open the Cart or Buying tab each session. Pauses while you search.\n\n"
            .. "Starts Auctionator's own full scan in the background, unless Auctionator or another addon already is, or did one recently. Your searches come first: the scan pauses while you search and starts again once you've been idle a few seconds." })
    p:Check({ path = "db.options.hideTabs", label = "Hide Auction Tabs",
        tooltip = "Hides Auctionator's Shopping tab; Quartermaster's Buying tab replaces it.",
        apply = function() if ns.AHTabs then ns.AHTabs:Relayout() end end })

    p:Header("General")
    p:Check({ path = "db.options.chat", label = "Print messages in chat", tooltip = "Quartermaster's chat messages (errors always show)." })
    p:Check({ path = "char.minimap.hide", invert = true, label = "Show minimap button", tooltip = "Quartermaster's minimap button (/qm minimap).",
        apply = function() if ns.MinimapButton then ns.MinimapButton:Refresh() end end })
    p:Check({ path = "db.options.countBank", label = "Prebuilt lists count items in your bank",
        tooltip = "Uses the bank contents from your last visit to the bank." })
    p:Check({ path = "db.options.countMail", label = "Prebuilt lists count auction wins waiting in the mailbox",
        tooltip = "Auctions you win arrive by mail. Quartermaster counts what it bought, plus what was in your mailbox the last time you opened it, so you don't buy the same items twice." })

    p:Subpage({ name = "About", build = BuildAbout, refresh = RefreshAbout })
end })

-- Opens Options > AddOns > Quartermaster.
function UI:OpenSettings() return self.page:Open() end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------

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

function UI:RefreshPage(name) win:RefreshPage(name) end

function UI:Refresh()
    if not ns.db or not win:IsShown() then return end
    RefreshSide()
    self:RefreshPage(win.active)
end

-- Item data arrives in the background; only the Browse page shows lots of it.
function UI:OnCatalogChanged()
    if not win:IsShown() then return end
    RefreshSide()
    local p = win.pages[win.active]
    if p and p.OnCatalogChanged then p.OnCatalogChanged() elseif p and p.Refresh then p.Refresh() end
end

function UI:Toggle()
    if not ns.db then return end
    win:Toggle()
end

function UI:Show(tab)
    if not ns.db then return end
    if tab == "settings" then return self:OpenSettings() end
    win:Show(tab)
end

function UI:SearchFor(text)
    local p = win.pages.browse
    if p and p.SearchFor then p.SearchFor(text) end
end

function UI:IsShown() return win:IsShown() end

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
